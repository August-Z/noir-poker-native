package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.actionLabel
import com.august.noirpoker.core.jsRound
import kotlin.math.max
import kotlin.math.min

/** Numbers behind a decision analysis. */
data class ReviewMetrics(
    val required: Double,
    val equityLow: Double,
    val equityHigh: Double,
    val randomEquity: Double,
    val weightedEquity: Double,
    val uncertainty: Double,
    val callCost: Int,
    val contestable: Int,
    val closing: Boolean,
    val sidePots: Boolean,
    /** Samples per range, or 990 combinations when enumerating. */
    val trials: Int,
    val method: EquityMethod,
    val randomEV: Double,
    val weightedEV: Double,
)

/** `analyzeDecision` result for one hero decision. */
data class DecisionAnalysis(
    val index: Int,
    val status: ReviewStatus,
    /** Classifier code such as `late-open` or `priced-call`. */
    val code: String,
    val title: String,
    val reason: String,
    val lesson: String,
    val plan: String,
    val confidence: String,
    val evidence: List<String>,
    val alternative: CandidateAction,
    val alternativeLabel: String,
    val routes: Routes,
    val recommendation: String,
    /** `null` when the snapshot lacks a dealer or seat state (hand-built snapshots). */
    val simulation: CounterfactualResult?,
    val metrics: ReviewMetrics,
    val draw: DrawInfo,
    val context: DecisionContext,
)

/** `rolloutTrials` default: `max(12, min(64, Math.round(trials / 15)))`. */
fun defaultRolloutTrials(trials: Int): Int = max(12, min(64, jsRound(trials / 15.0).toInt()))

private val EARLY = setOf("UTG", "UTG+1", "MP", "LJ")
private val WEAK_CLASSES = setOf(HandClass.HIGH, HandClass.UNDERPAIR, HandClass.MIDDLE_PAIR, HandClass.BOARD, HandClass.BOARD_PAIR)
private val NO_OVERRIDE = setOf("free-fold", "expensive-call", "weak-threebet-defense", "weak-fourbet-defense")

/**
 * Grades one hero decision from its before-action snapshot only. Hidden opponent cards,
 * the future deck and the final winners cannot enter: [ReviewDecision] has no field for them.
 */
fun analyzeDecision(
    s: ReviewDecision,
    trials: Int = 600,
    rolloutTrials: Int = defaultRolloutTrials(trials),
    checkpoint: () -> Unit = {},
): DecisionAnalysis {
    if (trials < 1) throw ReviewException(ReviewCopy.errorTrials)
    val price = callPrice(s)
    val wide = sampleValue(s, price, trials, false)
    val strong = sampleValue(s, price, trials, true)
    val ctx = decisionContext(s)
    val pre = if (s.street == 0) preflopContext(s) else null
    val low = min(wide.equity, strong.equity)
    val high = max(wide.equity, strong.equity)
    val uncertainty = max(wide.margin, strong.margin)
    val draw = ctx.draw
    val texture = ctx.texture
    val handClass = ctx.handClass
    val hand = ctx.handLabel
    val tier = ctx.tier
    val early = s.position in EARLY
    val deep = ctx.effective >= 2500
    val step = s.labelStep()
    fun label(a: CandidateAction) = actionLabel(step, a.action, a.amount)
    val priced = ReviewCopy.priced(price.cost, price.contestable, price.required)
    val estimated = ReviewCopy.estimated(wide.equity, strong.equity)
    val strongMade = s.street > 0 && handClass !in WEAK_CLASSES && !(texture.maxSuit >= 4 && ctx.made.score[0] < 5)
    val valueTarget = strongMade || (s.street == 0 && tier >= 2)
    val callOrCheck = CandidateAction(if (s.legal.canCheck) Action.CHECK else Action.CALL, s.legal.callAmount)
    val checkOrFold = CandidateAction(if (s.legal.canCheck) Action.CHECK else Action.FOLD, 0)
    val fold = CandidateAction(Action.FOLD, 0)
    var status = ReviewStatus.SOUND
    val code: String
    val title: String
    var reason: String
    val lesson: String
    var plan: String
    var confidence = ReviewCopy.confRangeDependent
    var alternative = callOrCheck
    fun raiseTo(): CandidateAction {
        val target: Double = if (s.street == 0) {
            val limpers = s.history.count { it.street == 0 && it.action == Action.CALL }
            if (s.currentBet <= 50) (150 + 50 * limpers).toDouble() else s.currentBet * (if (ctx.inPosition) 3.0 else 4.0)
        } else if (s.currentBet > 0) {
            s.currentBet * (if (ctx.inPosition) 2.5 else 3.0)
        } else {
            jsRound((s.pot * (if (texture.wet || ctx.opponents > 1) 0.65 else 0.4)) / 25) * 25
        }
        return CandidateAction(
            Action.RAISE,
            min(s.legal.maxRaiseTo, max(s.legal.minRaiseTo, jsRound(target).toInt())),
        )
    }
    if (s.action == Action.FOLD && s.legal.canCheck) {
        code = "free-fold"
        status = ReviewStatus.ATTENTION
        confidence = ReviewCopy.confRuleClear
        title = ReviewCopy.freeFoldTitle
        reason = ReviewCopy.freeFoldReason(s.position, ctx.pendingOthers)
        alternative = CandidateAction(Action.CHECK, 0)
        lesson = ReviewCopy.freeFoldLesson
        plan = ReviewCopy.freeFoldPlan
    } else if (pre != null && pre.unopened && pre.late && pre.openingCandidate && tier < 2 &&
        s.action == Action.RAISE && ctx.extra <= 400 && s.amount < s.legal.maxRaiseTo
    ) {
        code = if (pre.limpers != 0) "late-isolation" else "late-open"
        title = if (pre.limpers != 0) ReviewCopy.lateTitleIso else ReviewCopy.lateTitleOpen
        reason = ReviewCopy.lateReason(hand, s.position, pre.limpers, s.amount, pre.ace, pre.weakAce, pre.kicker)
        alternative = CandidateAction(Action.RAISE, min(s.legal.maxRaiseTo, max(s.legal.minRaiseTo, 125 + pre.limpers * 50)))
        lesson = ReviewCopy.lateLesson
        plan = ReviewCopy.latePlan(pre.limpers != 0)
    } else if (pre != null && pre.raises >= 2 && (pre.weakAce || tier == 0) &&
        (s.action == Action.CALL || s.action == Action.RAISE)
    ) {
        code = if (pre.raises >= 3) "weak-fourbet-defense" else "weak-threebet-defense"
        status = if (pre.raises >= 3 || price.cost >= s.stack * 0.1) ReviewStatus.ATTENTION else ReviewStatus.CONSIDER
        title = if (pre.raises >= 3) ReviewCopy.weakDefTitle4Bet else ReviewCopy.weakDefTitle3Bet
        reason = ReviewCopy.weakDefReason(
            hand, s.position, pre.phrase, s.currentBet, pre.ratio, priced, estimated, pre.ownOpen, pre.weakAce, ctx.pendingOthers,
        )
        alternative = fold
        lesson = if (pre.raises >= 3) ReviewCopy.weakDefLesson4Bet else ReviewCopy.weakDefLesson3Bet
        plan = if (pre.raises >= 3) ReviewCopy.weakDefPlan4Bet else ReviewCopy.weakDefPlan3Bet(pre.suited)
    } else if (pre != null && pre.unopened && pre.late && pre.openingCandidate && tier < 2 && pre.limpers == 0 &&
        ctx.effective >= 500 && s.legal.canRaise && (s.action == Action.FOLD || s.action == Action.CALL)
    ) {
        code = "late-passive-entry"
        status = ReviewStatus.CONSIDER
        title = ReviewCopy.latePassiveTitle
        reason = ReviewCopy.latePassiveReason(hand, s.position, pre.ace, s.action == Action.CALL)
        alternative = CandidateAction(Action.RAISE, min(s.legal.maxRaiseTo, max(s.legal.minRaiseTo, 125)))
        lesson = ReviewCopy.latePassiveLesson
        plan = ReviewCopy.latePassivePlan
    } else if (pre != null && pre.raises == 1 && pre.callersAfterOpen > 0 && pre.late && pre.weakAce && s.action == Action.RAISE) {
        code = "squeeze-candidate"
        status = ReviewStatus.CONSIDER
        title = ReviewCopy.squeezeTitle
        reason = ReviewCopy.squeezeReason(hand, s.position, pre.callersAfterOpen, s.amount)
        alternative = fold
        lesson = ReviewCopy.squeezeLesson
        plan = ReviewCopy.squeezePlan
    } else if (pre != null && pre.unopened && early && pre.suited && tier == 0 &&
        (s.action == Action.CALL || s.action == Action.RAISE)
    ) {
        code = "early-suited-entry"
        status = ReviewStatus.CONSIDER
        title = ReviewCopy.earlySuitedTitle
        reason = ReviewCopy.earlySuitedReason(hand, s.position, ctx.pendingOthers, pre.kicker <= 8)
        alternative = checkOrFold
        lesson = ReviewCopy.earlySuitedLesson
        plan = ReviewCopy.earlySuitedPlan
    } else if (pre != null && s.street == 0 && tier == 0 && (s.action == Action.CALL || s.action == Action.RAISE) &&
        ((pre.raises > 0 && s.currentBet >= 150) || early)
    ) {
        code = "weak-entry"
        status = if (early && pre.raises == 0) ReviewStatus.ATTENTION else ReviewStatus.CONSIDER
        title = if (early && pre.raises == 0) ReviewCopy.weakEntryTitleEarly else ReviewCopy.weakEntryTitleOpen
        reason = ReviewCopy.weakEntryReason(hand, s.position, s.legal.callAmount, ctx.pendingOthers, early, pre.suited)
        alternative = checkOrFold
        lesson = ReviewCopy.weakEntryLesson
        plan = ReviewCopy.weakEntryPlan
    } else if (s.action == Action.RAISE && s.amount == s.legal.maxRaiseTo && deep && ctx.betRatio > 4 && s.street == 0 && tier >= 2) {
        code = "deep-value-shove"
        status = ReviewStatus.CONSIDER
        title = ReviewCopy.deepShoveTitle
        reason = ReviewCopy.deepShoveReason(hand, ctx.extra, s.pot, ctx.betRatio, ctx.effective)
        alternative = raiseTo()
        lesson = ReviewCopy.deepShoveLesson
        plan = ReviewCopy.deepShovePlan(label(alternative))
    } else if (s.action == Action.CALL && price.cost > 0 && high + uncertainty + 0.035 < price.required) {
        code = "expensive-call"
        status = if (price.closing) ReviewStatus.ATTENTION else ReviewStatus.CONSIDER
        title = if (price.closing) ReviewCopy.expCallTitleClosing else ReviewCopy.expCallTitleOpen
        reason = ReviewCopy.expCallReason(hand, ctx.opponents, priced, estimated, draw.outs, draw.nextChance)
        alternative = fold
        lesson = if (price.closing) ReviewCopy.expCallLessonClosing else ReviewCopy.expCallLessonOpen
        plan = if (price.closing) ReviewCopy.expCallPlanClosing else ReviewCopy.expCallPlanOpen(ctx.pendingOthers)
    } else if (s.street == 0 && tier == 3 && s.action == Action.FOLD) {
        code = "premium-fold"
        status = ReviewStatus.CONSIDER
        title = ReviewCopy.premFoldTitle
        reason = ReviewCopy.premFoldReason(hand, s.currentBet, s.legal.callAmount, ctx.effective, ctx.preflopRaises)
        alternative = CandidateAction(Action.CALL, s.legal.callAmount)
        lesson = ReviewCopy.premFoldLesson
        plan = if (ctx.preflopRaises >= 2) ReviewCopy.premFoldPlanMulti else ReviewCopy.premFoldPlanNormal
    } else if (s.street == 0 && tier == 3 && s.action == Action.CALL && s.legal.canRaise) {
        code = "premium-flat"
        status = ReviewStatus.CONSIDER
        title = ReviewCopy.premFlatTitle
        reason = ReviewCopy.premFlatReason(hand, s.position, s.legal.callAmount, ctx.opponents, ctx.pendingOthers, ctx.preflopRaises != 0)
        alternative = raiseTo()
        lesson = ReviewCopy.premFlatLesson
        plan = ReviewCopy.premFlatPlan(label(alternative))
    } else if (s.action == Action.RAISE && ctx.extra > max(500.0, s.pot * 2.5) && !strongMade && draw.outs == 0 &&
        (s.street != 0 || tier < 2)
    ) {
        code = "large-unbacked-bet"
        status = ReviewStatus.CONSIDER
        title = if (s.street == 3) ReviewCopy.bigBetTitleRiver else ReviewCopy.bigBetTitle
        reason = ReviewCopy.bigBetReason(hand, ctx.extra, ctx.betRatio, ctx.opponents, ctx.missedDraw, ctx.nutFlushBlocker)
        alternative = callOrCheck
        lesson = ReviewCopy.bigBetLesson
        plan = ReviewCopy.bigBetPlan
    } else if (s.action == Action.CHECK && strongMade && s.legal.canRaise &&
        !(handClass == HandClass.TOP_PAIR && ctx.opponents > 1 && texture.wet)
    ) {
        code = "value-check"
        status = ReviewStatus.CONSIDER
        title = ReviewCopy.valueCheckTitle
        reason = ReviewCopy.valueCheckReason(hand, texture.phrase, ctx.opponents, ctx.inPosition, handClass == HandClass.OVERPAIR)
        alternative = raiseTo()
        lesson = if (texture.wet) ReviewCopy.valueCheckLessonWet else ReviewCopy.valueCheckLessonDry
        plan = ReviewCopy.valueCheckPlan(label(alternative))
    } else if (s.action == Action.CALL && handClass == HandClass.TOP_PAIR && ctx.opponents > 1 && texture.wet) {
        code = "multiway-top-pair"
        status = ReviewStatus.CONSIDER
        title = ReviewCopy.multiwayTopPairTitle
        reason = ReviewCopy.multiwayTopPairReason(hand, ctx.opponents, texture.phrase, priced, estimated)
        lesson = ReviewCopy.multiwayTopPairLesson
        plan = ReviewCopy.multiwayTopPairPlan
    } else if (s.action == Action.FOLD && price.cost > 0 && low - uncertainty > price.required + 0.08) {
        code = "tight-fold"
        status = ReviewStatus.CONSIDER
        title = ReviewCopy.tightFoldTitle
        reason = ReviewCopy.tightFoldReason(hand, priced, estimated)
        alternative = CandidateAction(Action.CALL, s.legal.callAmount)
        lesson = ReviewCopy.tightFoldLesson
        plan = if (price.closing) ReviewCopy.tightFoldPlanClosing else ReviewCopy.tightFoldPlanOpen
    } else if (s.action == Action.FOLD) {
        code = "priced-fold"
        title = ReviewCopy.pricedFoldTitle
        reason = ReviewCopy.pricedFoldReason(
            hand,
            s.position,
            s.legal.callAmount,
            if (s.street != 0) texture.phrase else null,
            if (price.cost != 0) priced else null,
            draw.outs,
            draw.nextChance,
        )
        alternative = fold
        lesson = ReviewCopy.pricedFoldLesson
        plan = ReviewCopy.pricedFoldPlan
    } else if (s.action == Action.CALL) {
        code = if (ctx.pastCalls >= 2) "multi-street-call" else "priced-call"
        title = if (ctx.pastCalls >= 2) ReviewCopy.callTitleMulti else ReviewCopy.callTitle
        reason = ReviewCopy.callReason(hand, ctx.opponents, priced, estimated, ctx.pastCalls, draw.outs, draw.nextChance)
        lesson = if (price.closing) ReviewCopy.callLessonClosing else ReviewCopy.callLessonOpen
        plan = if (price.closing) ReviewCopy.callPlanClosing else ReviewCopy.callPlanOpen(ctx.pendingOthers)
    } else if (s.action == Action.RAISE) {
        code = if (valueTarget) "value-bet" else if (draw.outs != 0) "draw-bet" else "pressure-bet"
        title = if (valueTarget) {
            ReviewCopy.raiseTitleValue
        } else if (draw.outs != 0) {
            ReviewCopy.raiseTitleDraw
        } else {
            ReviewCopy.raiseTitlePressure
        }
        reason = ReviewCopy.raiseReason(
            hand,
            ctx.extra,
            ctx.betRatio,
            if (s.street != 0) texture.phrase else null,
            ctx.opponents,
            draw.outs,
            draw.nextChance,
            valueTarget,
        )
        alternative = CandidateAction(Action.RAISE, s.amount)
        lesson = if (valueTarget) ReviewCopy.raiseLessonValue else ReviewCopy.raiseLessonOther
        plan = if (s.legal.isShortAllin) ReviewCopy.raisePlanShortAllin else ReviewCopy.raisePlan
    } else {
        code = if (handClass == HandClass.BOARD) "board-check" else if (draw.outs != 0) "draw-check" else "pot-control"
        title = if (handClass == HandClass.BOARD) {
            ReviewCopy.checkTitleBoard
        } else if (draw.outs != 0) {
            ReviewCopy.checkTitleDraw
        } else {
            ReviewCopy.checkTitleControl
        }
        reason = ReviewCopy.checkReason(hand, texture.phrase, draw.outs, draw.nextChance, ctx.pendingOthers)
        alternative = CandidateAction(Action.CHECK, 0)
        lesson = ReviewCopy.checkLesson
        plan = ReviewCopy.checkPlan
    }
    if (alternative.action == Action.RAISE && !s.legal.canRaise) alternative = callOrCheck
    if (alternative.action == Action.CALL && s.legal.canCheck) alternative = CandidateAction(Action.CHECK, 0)
    val evidence = mutableListOf(
        ReviewCopy.evPosition(s.position, ctx.opponents, s.street, ctx.inPosition),
        ReviewCopy.evHand(hand),
        if (s.street != 0) ReviewCopy.evBoard(texture.phrase) else ReviewCopy.evPreflop(ctx.preflopRaises, ctx.pendingOthers),
        ReviewCopy.evStack(ctx.effective, ctx.spr),
    )
    if (draw.outs != 0) evidence.add(ReviewCopy.evDraw(draw.outs, draw.nextChance))
    if (price.cost != 0) evidence.add(priced)
    if (pre != null) evidence.add(ReviewCopy.evPreflopContext(pre.phrase, pre.limpers, pre.ace))
    var routes = comparisonRoutes(s, ctx, code, status, alternative, pre)
    var simulation: CounterfactualResult? = null
    if (s.dealer != null && s.players.all { it.state != null }) {
        val result = compareCandidateActions(s, listOf(alternative, routes.secondary?.candidate), rolloutTrials, checkpoint)
        simulation = result
        if (!result.stable && status != ReviewStatus.ATTENTION) confidence = ReviewCopy.confSimUnstable
        if (result.stable && code !in NO_OVERRIDE &&
            (result.best.action != alternative.action || (result.best.action == Action.RAISE && result.best.amount != alternative.amount))
        ) {
            val previous = alternative
            alternative = result.best
            status = ReviewStatus.CONSIDER
            confidence = ReviewCopy.confSimStable
            reason += ReviewCopy.simReasonSuffix(label(alternative))
            routes = Routes(
                primary = Route(
                    alternative.action,
                    alternative.amount,
                    label(alternative),
                    ReviewCopy.simSummary(label(alternative)),
                    ReviewCopy.simPrimaryCondition,
                    ReviewCopy.simPrimaryTradeoff,
                ),
                secondary = Route(
                    previous.action,
                    previous.amount,
                    label(previous),
                    null,
                    ReviewCopy.simSecondaryCondition,
                    ReviewCopy.simSecondaryTradeoff,
                ),
            )
            plan += ReviewCopy.simPlanSuffix
        }
    }
    return DecisionAnalysis(
        index = s.index,
        status = status,
        code = code,
        title = title,
        reason = reason,
        lesson = lesson,
        plan = plan,
        confidence = confidence,
        evidence = evidence,
        alternative = alternative,
        alternativeLabel = label(alternative),
        routes = routes,
        recommendation = routes.primary.summary ?: routes.primary.label,
        simulation = simulation,
        metrics = ReviewMetrics(
            required = price.required,
            equityLow = low,
            equityHigh = high,
            randomEquity = wide.equity,
            weightedEquity = strong.equity,
            uncertainty = uncertainty,
            callCost = price.cost,
            contestable = price.contestable,
            closing = price.closing,
            sidePots = price.pots.size > 1,
            trials = wide.samples?.takeIf { it != 0 } ?: trials,
            method = wide.method ?: EquityMethod.SAMPLING,
            randomEV = wide.ev,
            weightedEV = strong.ev,
        ),
        draw = draw,
        context = ctx,
    )
}

data class ReviewSummary(
    val steps: List<DecisionAnalysis>,
    /** Index of the first step with the highest status (0 without decisions). */
    val priorityIndex: Int,
    val attention: Int,
    val consider: Int,
    /** Distinct titles of attention steps, then consider steps. */
    val themes: List<String>,
    val title: String,
    val summary: String,
)

private fun rank(status: ReviewStatus) = when (status) {
    ReviewStatus.ATTENTION -> 2
    ReviewStatus.CONSIDER -> 1
    ReviewStatus.SOUND -> 0
}

/** Never reads the outcome: only the decisions and their analyses. */
fun summarizeReview(decisions: List<ReviewDecision>, steps: List<DecisionAnalysis>): ReviewSummary {
    val attention = steps.filter { it.status == ReviewStatus.ATTENTION }
    val consider = steps.filter { it.status == ReviewStatus.CONSIDER }
    val priority = steps.sortedByDescending { rank(it.status) }.firstOrNull()
    val extra = decisions.sumOf {
        when (it.action) {
            Action.RAISE -> it.amount - it.bet
            Action.CALL -> it.legal.callAmount
            else -> 0
        }
    }
    val themes = (attention + consider).map { it.title }.distinct()
    val summary = if (priority != null) {
        ReviewCopy.summary(
            decisions.size,
            extra,
            priority.index + 1,
            ReviewCopy.streetNames[decisions.getOrNull(priority.index)?.street ?: 0],
            priority.title,
            themes.size - 1,
        )
    } else {
        ReviewCopy.summaryNoDecisions
    }
    return ReviewSummary(
        steps = steps,
        priorityIndex = priority?.index ?: 0,
        attention = attention.size,
        consider = consider.size,
        themes = themes,
        title = when {
            attention.isNotEmpty() -> ReviewCopy.titleAttention(priority!!.title)
            consider.isNotEmpty() -> ReviewCopy.titleConsider(priority!!.title)
            else -> ReviewCopy.titleClean
        },
        summary = summary,
    )
}

fun summarizeReview(input: ReviewInput, steps: List<DecisionAnalysis>): ReviewSummary = summarizeReview(input.decisions, steps)

/**
 * Analyzes every hero decision in order. [progress] is called after each decision with
 * `(done, total)`, like the reference worker's progress messages; [checkpoint] runs before
 * each decision and between simulation trials so the caller can cancel stale work by
 * throwing (for example a coroutine `ensureActive`).
 */
fun analyzeReview(
    decisions: List<ReviewDecision>,
    trials: Int = 600,
    rolloutTrials: Int = defaultRolloutTrials(trials),
    checkpoint: () -> Unit = {},
    progress: (done: Int, total: Int) -> Unit = { _, _ -> },
): ReviewSummary {
    val steps = mutableListOf<DecisionAnalysis>()
    for (s in decisions) {
        checkpoint()
        steps.add(analyzeDecision(s, trials, rolloutTrials, checkpoint))
        progress(steps.size, decisions.size)
    }
    return summarizeReview(decisions, steps)
}

fun analyzeReview(
    input: ReviewInput,
    trials: Int = 600,
    rolloutTrials: Int = defaultRolloutTrials(trials),
    checkpoint: () -> Unit = {},
    progress: (done: Int, total: Int) -> Unit = { _, _ -> },
): ReviewSummary = analyzeReview(input.decisions, trials, rolloutTrials, checkpoint, progress)
