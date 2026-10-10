package com.august.noirpoker.core.review

import com.august.noirpoker.core.BotDecisionRecord
import com.august.noirpoker.core.BotView
import com.august.noirpoker.core.Card
import com.august.noirpoker.core.LabelStep
import com.august.noirpoker.core.LegalActions
import com.august.noirpoker.core.actionLabel
import com.august.noirpoker.core.forLabels
import com.august.noirpoker.core.historyActionLabel
import com.august.noirpoker.core.labelStep
import com.august.noirpoker.core.session.OptionItem
import com.august.noirpoker.core.session.ReviewState
import com.august.noirpoker.core.session.ReviewStatus as JobStatus
import kotlin.math.ceil

// The Hand Review dialog as data (`review-controller.js` `renderDialog` and
// `opponent-review.js`). The apps render these views; they never format review
// numbers or choose review copy themselves. Opponent execution records feed only
// the opponent view, and only after settlement (the session captures them then).

/** Static and templated copy of the Hand Review dialog (review copy catalog §8, §9, Appendix B). */
object ReviewDialogCopy {
    const val eyebrow = "HAND REVIEW"
    const val closeA11y = "Close review"
    const val titleDefault = "Hand Review"
    fun title(hand: Int) = "Hand #$hand · Review"
    fun change(profit: Int) = when {
        profit < 0 -> "${formatChipsSigned(profit)} chips"
        profit > 0 -> "+${formatChipsSigned(profit)} chips"
        else -> "0 chips"
    }
    const val contextFolded = "You folded this hand"
    const val contextPartialWin = "Won part of the pot, net loss for the hand"
    const val contextWon = "You won the pot"
    const val contextLost = "You didn't win the pot"

    const val stateError = "Analysis didn't finish. You can try again."
    fun stateProgress(done: Int, total: Int) = "Analyzing decision $done of $total…"
    const val statePreparing = "Preparing this hand's decision snapshots…"
    const val summaryTitleDefault = "Back to the decisions as they were"
    const val priorityButton = "Go to the priority decision"
    const val fromFirstButton = "Review from step 1"
    const val retry = "Analyze Again"

    const val tabsA11y = "Review perspective"
    const val tabHero = "Your Decisions"
    const val tabOpponents = "Opponent Decisions"
    const val tabOpponentsSubtitle = "Why they played it that way"

    const val timelineA11y = "Decision timeline for this hand"
    const val timelineTitle = "Your Decisions"
    fun actionCount(n: Int) = "$n ${if (n == 1) "action" else "actions"}"
    const val empty = "You made no decisions this hand, so there's nothing to evaluate. Blinds are forced bets and never count as mistakes."

    const val statusAttention = "Needs Work"
    const val statusConsider = "Worth Discussing"
    const val statusSound = "Well Reasoned"
    const val statusPending = "Pending"
    const val statusAnalyzing = "Analyzing"
    fun status(s: ReviewStatus) = when (s) {
        ReviewStatus.ATTENTION -> statusAttention
        ReviewStatus.CONSIDER -> statusConsider
        ReviewStatus.SOUND -> statusSound
    }

    fun detailTitle(step: Int, street: String) = "Step $step · $street"
    const val holeLabel = "Your hole cards"
    const val boardLabel = "Community cards at the time"
    const val noBoard = "No community cards yet"
    const val positionLabel = "Position"
    const val potLabel = "Pot at the time"
    const val stackLabel = "Stack remaining"
    const val yourChoice = "Your choice"
    const val suggestedLine = "Suggested Line"
    const val suggestionPending = "Comparing available actions…"
    const val routesA11y = "Conditions and trade-offs for both lines"
    const val routePrimary = "When the main line holds"
    const val routeSecondary = "Conditional alternative"

    const val simA11y = "Candidate action simulation comparison"
    const val simHeading = "Candidate Action Simulation"
    const val simStable = "In this sample, one line clearly led under both ranges; it still depends on assumptions about later play."
    const val simUnstable = "Ranges or sampling error could change the order; no single best action has been shown."
    fun simCaption(trials: Int) = "$trials hands simulated per action and range · Net chip change from this decision on"
    const val simColAction = "Action"
    const val simColRandom = "Random Range"
    const val simColWeighted = "Action-Weighted"
    fun simMargin(margin: Double) = "≈ ±${formatChipsSigned(margin)}"
    const val simDetailsSummary = "How the simulation handles later action"
    const val simDetailsBody =
        "Results include immediate folds, calls, later raises, and showdowns; the real hidden hole cards, the actual card order that followed, and the final winners are never used. The two range results are not a range of optimal returns."
    const val simUnavailable =
        "This older snapshot lacks the full action state, so later action can't be simulated; the range and price analysis from public information still applies."
    const val simRunning = "Simulating each legal action and the rest of the hand…"

    const val decisionTitleDefault = "Analysis based on what you knew then"
    const val reasonDefault =
        "Uses your hole cards, the community cards, public actions, and stacks at the time, never opponents' hidden cards or cards dealt later."
    const val evidenceHeading = "Key factors at the time"
    const val confidenceDefault = "Waiting for analysis"
    const val lessonHeading = "Focus for next practice"
    const val lessonDefault = "Judge the decision separately from the result; a specific practice focus appears when the review is done."
    const val planHeading = "Plan for later streets"
    const val planDefault = "The follow-up plan appears when analysis finishes."

    fun modelEnumeration(trials: Int) =
        "River heads-up: all $trials legal opponent hole-card combos were enumerated; there's no sampling error across combos, but the real range is still unknown."
    fun modelSampling(trials: Int, points: Int) =
        "$trials samples per range, with a conservative sampling-error band of about ±$points percentage points; this isn't the error in the opponent's real range."
    fun modelEquity(random: String, weighted: String) =
        "Random / action-weighted equity: $random / $weighted. The gap between the two ranges is not a confidence interval."

    const val metricRequired = "Equity needed to call"
    const val metricEquity = "Two-range estimate"
    const val metricContestable = "Winnable after calling"
    const val pricePending = "…"
    const val priceNoCall = "No call needed"
    fun equityAbout(p: String) = "≈$p"
    const val equityNone = "—"
    const val priceNoteSidePots = "Estimated separately for each pot you're eligible for; side pots beyond your all-in amount are excluded."
    const val priceNoteClosing = "The call price uses the amount you can currently win, after removing uncalled refunds."
    const val priceNoteDefault = "The price is only a guide; later bets, other players' actions, and potential winnings aren't included."

    const val publicActionsSummary = "Earlier public actions"
    const val publicActionsEmpty = "No other actions yet this round."
    const val previous = "Previous"
    const val next = "Next"
    fun stepPosition(step: Int, total: Int) = "$step / $total"

    // Accessibility text of timeline items and simulation cells (shared with iOS).
    fun heroStepA11y(step: Int, meta: String, action: String, chip: String) = "Step $step, $meta, $action, $chip"
    fun oppStepA11y(sequence: Int, meta: String, action: String, profile: String) = "${oppPublicAction(sequence)}, $meta, $action, $profile"
    fun simCellA11y(action: String, column: String, value: String, margin: String) = "$action, $column: $value chips, $margin"

    const val scope =
        "Reviewed with the information available at each decision · Ranges are assumptions, and winning or losing doesn't decide whether a choice was good."
    const val methodSummary = "How the analysis works"
    val methodParagraphs = listOf(
        "Only the hole cards, community cards, public actions, and stacks at the moment of each decision are used. Opponents' hidden cards, later cards, and the final winners play no part in grading decisions.",
        "Required equity = effective call cost ÷ the pot you can win after calling. The Main Pot and Side Pots are estimated separately by eligibility, and uncalled refunds don't count as winnings.",
        "The \"two-range estimate\" comes from sampling a random range and a stronger range for whoever bet or raised. These range assumptions are not the opponents' actual hands, and they are not an error interval. Later betting, fold rates, and potential winnings are not fully modeled. The analysis accounts for hand type, kicker, draws, position, board texture, number of players, and betting pressure. Direct completion cards are not guaranteed winning outs; only the chance of hitting on the next card is shown, because seeing both the turn and the river from the flop usually costs more than one payment. Heads-up on the river, every legal hole-card combo is enumerated; everything else uses fixed-seed sampling. Enumeration removes sampling error but not the error in the range assumptions. Candidate bet sizes are practice lines, not a GTO solution.",
    )
    const val methodReferencesLabel = "References:"
    /** External lessons from the reference; optional offline, opened in the system browser. */
    val methodReferences = listOf(
        "Pot Odds" to "https://www.pokerstars.com/poker/learn/lesson/pot-odds/",
        "Starting Hands and Position" to "https://www.pokerstars.com/poker/learn/lesson/poker-starting-hands/",
    )
    val methodClosingParagraphs = listOf(
        "The candidate action simulation samples the unknown cards from the position at the time and plays the hand out with the rules engine, including further bets, folds, side pots, and refunds. Your later decisions use a balanced simulated strategy, opponents keep their public styles, and each simulated decision uses 8 equity samples. It compares chip results under these strategies, not the value of an optimal follow-up strategy, and sampling error doesn't cover range or model errors.",
        "Opponent explanations read the actual decision records after settlement and show the price, range, mood, and random branches each bot used at the time. These private records never feed into grading your decisions.",
    )
    const val backToTable = "Back to Table"

    // Opponent tab (§9).
    const val oppEmpty =
        "No bot decision records for this hand. Reasons are never invented for actions that can't be reconstructed; the next hand will record the actual decisions."
    const val oppIntro =
        "Step through how each bot decided at the time. Hole cards enter this panel only after the hand ends; your own decision ratings still use only the public information at the time."
    const val oppFilterLabel = "Show opponent"
    const val oppFilterAll = "All Opponents"
    const val oppTimelineA11y = "Opponent decision timeline"
    const val oppTimelineTitle = "What Opponents Actually Did"
    const val oppRecordStatus = "Actual decision record"
    fun oppHoleLabel(name: String) = "$name's hole cards at the time"
    fun oppChoiceLabel(made: String) = "It chose · $made"
    const val oppEvidenceHeading = "What it actually used"
    const val oppBranchesSummary = "Show the actual random branches (0–1 rolls)"
    fun oppBranch(value: Double, threshold: Double, hit: Boolean) =
        "${jsToFixed(value, 3)} / threshold ${pct(threshold)} · ${if (hit) "Hit" else "Miss"}"
    const val oppBranchesEmpty = "No extra random branches on this step."
    fun oppPublicAction(sequence: Int) = "Public action #$sequence"

    private fun formatChipsSigned(v: Number) = number(v)
}

/** Status tone of a chip: `attention`, `consider`, `sound` or `pending` (the reference CSS classes). */
enum class ReviewTone { ATTENTION, CONSIDER, SOUND, PENDING }

fun ReviewStatus.tone(): ReviewTone = when (this) {
    ReviewStatus.ATTENTION -> ReviewTone.ATTENTION
    ReviewStatus.CONSIDER -> ReviewTone.CONSIDER
    ReviewStatus.SOUND -> ReviewTone.SOUND
}

data class ReviewTimelineItem(
    val index: Int,
    /** The number badge: the step number, or the public action sequence for opponents. */
    val number: String,
    val meta: String,
    val action: String,
    val chip: String,
    val tone: ReviewTone,
    val selected: Boolean,
    val a11y: String,
)

data class ReviewMeta(val label: String, val value: String)

/** The cards and public numbers of one decision point. [board] empty shows [noBoard]. */
data class ReviewSceneView(
    val holeLabel: String,
    val hole: List<Card>,
    val boardLabel: String,
    val board: List<Card>,
    val noBoard: String,
    val meta: List<ReviewMeta>,
)

data class ReviewRouteView(val kicker: String, val label: String, val condition: String, val tradeoff: String)

data class ReviewSimCell(val value: String, val margin: String, val a11y: String)

data class ReviewSimRow(val label: String, val cells: List<ReviewSimCell>)

data class ReviewSimulationView(
    val heading: String,
    val stability: String,
    val stable: Boolean,
    val caption: String,
    val columns: List<String>,
    val rows: List<ReviewSimRow>,
    val detailsSummary: String,
    val details: List<String>,
)

data class ReviewPublicAction(val name: String, val label: String)

data class HeroStepView(
    val index: Int,
    val title: String,
    val statusText: String,
    val tone: ReviewTone,
    val scene: ReviewSceneView,
    val yourChoice: String,
    val suggestion: String,
    val suggestionReady: Boolean,
    val routes: List<ReviewRouteView>,
    val simulation: ReviewSimulationView?,
    /** Shown instead of the table: the simulation is running or unavailable. */
    val simulationNote: String?,
    val decisionTitle: String,
    val reason: String,
    /** Empty until the analysis finishes. */
    val evidence: List<String>,
    val confidence: String,
    val lesson: String,
    val plan: String,
    val metrics: List<ReviewMeta>,
    val modelNote: String?,
    val priceNote: String,
    val publicActions: List<ReviewPublicAction>,
    val publicActionsEmpty: String?,
    val position: String,
    val canPrevious: Boolean,
    val canNext: Boolean,
)

data class HeroReviewView(
    val title: String,
    val change: String,
    /** Sign of the hand's net result. */
    val changeSign: Int,
    val context: String,
    val stateText: String,
    val running: Boolean,
    /** Analysis progress: decisions done of [total]. */
    val progress: Int,
    val total: Int,
    val summaryTitle: String,
    /** Null while no analysis or no decision exists. */
    val priorityButton: String?,
    val priorityIndex: Int,
    val retryVisible: Boolean,
    val timelineTitle: String,
    val stepCount: String,
    val timeline: List<ReviewTimelineItem>,
    val step: HeroStepView?,
    val empty: String?,
)

data class OpponentBranchRow(val name: String, val value: String)

data class OpponentStepView(
    val index: Int,
    val title: String,
    val statusText: String,
    val tone: ReviewTone,
    val scene: ReviewSceneView,
    val choiceLabel: String,
    val choice: String,
    val explanationTitle: String,
    val explanation: String,
    val evidenceHeading: String,
    val profileName: String,
    val reasons: List<String>,
    val warning: String,
    val branchesSummary: String,
    val branches: List<OpponentBranchRow>,
    val branchesEmpty: String?,
    val position: String,
    val canPrevious: Boolean,
    val canNext: Boolean,
)

data class OpponentReviewView(
    val intro: String,
    val filterLabel: String,
    /** `null` value: every opponent. */
    val filterOptions: List<OptionItem<Int?>>,
    val filter: Int?,
    val filterText: String,
    val timelineTitle: String,
    val count: String,
    val timeline: List<ReviewTimelineItem>,
    val step: OpponentStepView?,
    val empty: String?,
)

private fun streetName(street: Int) = ReviewCopy.streetNames.getOrElse(street) { "" }

/** Integer percent as the review dialog prints it: `Math.round(v * 100) + '%'`. */
fun reviewPercent(v: Double): String = percent(v)

/** `Math.round(v).toLocaleString('en-US')`. */
fun reviewChips(v: Number): String = number(v)

/** `(v > 0 ? '+' : '') + format(v)`: tests the unrounded value, as the reference does. */
fun reviewSigned(v: Double): String = (if (v > 0) "+" else "") + number(v)

/**
 * The label step of an executed bot decision (`{...trace.view, action, amount}`): the
 * bot's own view at the time, which has no `minRaise` key.
 */
fun BotDecisionRecord.labelStep(): LabelStep {
    // The engine always records a view; a record without one still gets a plain label.
    val v = trace.view ?: return LabelStep(0, action = action, amount = amount?.toDouble())
    return LabelStep(v.street, v.history, v.currentBet, null, v.legal.forLabels(), v.stack, action, amount?.toDouble())
}

/** Distinct opponents of the records in first-appearance order (`new Map(records.map(r => [r.id, r.name]))`). */
fun opponentFilterOptions(records: List<BotDecisionRecord>): List<OptionItem<Int?>> {
    val seen = LinkedHashMap<Int, String>()
    records.forEach { seen[it.id] = it.name }
    return listOf(OptionItem<Int?>(null, ReviewDialogCopy.oppFilterAll)) + seen.map { (id, name) -> OptionItem<Int?>(id, name) }
}

/** The hero panel of the Hand Review dialog, or null when there is nothing to review. */
fun presentHeroReview(state: ReviewState): HeroReviewView? {
    val input = state.input ?: return null
    val copy = ReviewDialogCopy
    val steps = input.decisions
    val analysis = (state.analysis as? HeroReviewAnalysis)?.summary
    val outcome = input.outcome
    val selected = state.selected
    val decision = steps.getOrNull(selected)
    val result = analysis?.steps?.getOrNull(selected)
    val stateText = when {
        state.status == JobStatus.ERROR -> copy.stateError
        analysis != null -> analysis.summary
        state.status == JobStatus.RUNNING -> copy.stateProgress(state.progress, steps.size)
        else -> copy.statePreparing
    }
    val timeline = steps.mapIndexed { i, s ->
        val status = analysis?.steps?.getOrNull(i)?.status
        val meta = "${streetName(s.street)} · ${s.position}"
        val action = actionLabel(s.labelStep())
        val chip = status?.let(copy::status) ?: copy.statusPending
        ReviewTimelineItem(i, "${i + 1}", meta, action, chip, status?.tone() ?: ReviewTone.PENDING, i == selected, copy.heroStepA11y(i + 1, meta, action, chip))
    }
    val step = decision?.let { d ->
        val labels = d.labelStep()
        val sim = result?.simulation
        val m = result?.metrics
        val publicActions = d.history
            .mapIndexed { index, a -> a to historyActionLabel(d.history, index) }
            .filter { it.first.street == d.street }
            .takeLast(6)
            .map { (a, label) -> ReviewPublicAction(d.players.getOrNull(a.id)?.name ?: "", label) }
        HeroStepView(
            index = selected,
            title = copy.detailTitle(selected + 1, streetName(d.street)),
            statusText = result?.status?.let(copy::status) ?: copy.statusAnalyzing,
            tone = result?.status?.tone() ?: ReviewTone.PENDING,
            scene = ReviewSceneView(
                copy.holeLabel, d.hole, copy.boardLabel, d.board, copy.noBoard,
                listOf(
                    ReviewMeta(copy.positionLabel, d.position),
                    ReviewMeta(copy.potLabel, number(d.pot)),
                    ReviewMeta(copy.stackLabel, number(d.stack)),
                ),
            ),
            yourChoice = actionLabel(labels),
            suggestion = result?.recommendation?.takeIf { it.isNotEmpty() } ?: copy.suggestionPending,
            suggestionReady = result != null,
            routes = result?.let { r ->
                listOfNotNull(r.routes.primary, r.routes.secondary).mapIndexed { i, route ->
                    ReviewRouteView(if (i == 0) copy.routePrimary else copy.routeSecondary, route.label, route.condition, route.tradeoff)
                }
            } ?: emptyList(),
            simulation = sim?.let { s ->
                ReviewSimulationView(
                    heading = copy.simHeading,
                    stability = if (s.stable) copy.simStable else copy.simUnstable,
                    stable = s.stable,
                    caption = copy.simCaption(s.trials),
                    columns = listOf(copy.simColAction, copy.simColRandom, copy.simColWeighted),
                    rows = s.rows.map { row ->
                        val label = actionLabel(labels, row.action.action, row.action.amount)
                        ReviewSimRow(
                            label,
                            row.scenarios.mapIndexed { i, sc ->
                                val column = if (i == 0) copy.simColRandom else copy.simColWeighted
                                val value = reviewSigned(sc.ev)
                                val margin = copy.simMargin(sc.margin)
                                ReviewSimCell(value, margin, copy.simCellA11y(label, column, value, margin))
                            },
                        )
                    },
                    detailsSummary = copy.simDetailsSummary,
                    details = listOf(s.note, copy.simDetailsBody),
                )
            },
            simulationNote = when {
                sim != null -> null
                result != null -> copy.simUnavailable
                else -> copy.simRunning
            },
            decisionTitle = result?.title?.takeIf { it.isNotEmpty() } ?: copy.decisionTitleDefault,
            reason = result?.reason?.takeIf { it.isNotEmpty() } ?: copy.reasonDefault,
            evidence = result?.evidence ?: emptyList(),
            confidence = result?.confidence?.takeIf { it.isNotEmpty() } ?: copy.confidenceDefault,
            lesson = result?.lesson?.takeIf { it.isNotEmpty() } ?: copy.lessonDefault,
            plan = result?.plan?.takeIf { it.isNotEmpty() } ?: copy.planDefault,
            metrics = listOf(
                ReviewMeta(
                    copy.metricRequired,
                    if (d.legal.callAmount != 0) (m?.let { percent(it.required) } ?: copy.pricePending) else copy.priceNoCall,
                ),
                ReviewMeta(
                    copy.metricEquity,
                    if (m != null && m.contestable != 0) {
                        val low = percent(m.equityLow)
                        val high = percent(m.equityHigh)
                        if (low == high) copy.equityAbout(low) else "$low–$high"
                    } else {
                        copy.equityNone
                    },
                ),
                ReviewMeta(copy.metricContestable, m?.let { number(it.contestable) } ?: copy.pricePending),
            ),
            modelNote = m?.let {
                val method = if (it.method == EquityMethod.ENUMERATION) {
                    copy.modelEnumeration(it.trials)
                } else {
                    copy.modelSampling(it.trials, ceil(it.uncertainty * 100).toInt())
                }
                method + " " + copy.modelEquity(percent(it.randomEquity), percent(it.weightedEquity))
            },
            priceNote = when {
                m?.sidePots == true -> copy.priceNoteSidePots
                m?.closing == true -> copy.priceNoteClosing
                else -> copy.priceNoteDefault
            },
            publicActions = publicActions,
            publicActionsEmpty = if (publicActions.isEmpty()) copy.publicActionsEmpty else null,
            position = copy.stepPosition(selected + 1, steps.size),
            canPrevious = selected > 0,
            canNext = selected < steps.size - 1,
        )
    }
    return HeroReviewView(
        title = copy.title(input.hand),
        change = copy.change(outcome.profit),
        changeSign = outcome.profit.compareTo(0),
        context = when {
            outcome.folded -> copy.contextFolded
            outcome.wonPot -> if (outcome.profit < 0) copy.contextPartialWin else copy.contextWon
            else -> copy.contextLost
        },
        stateText = stateText,
        running = state.status == JobStatus.RUNNING,
        progress = state.progress,
        total = steps.size,
        summaryTitle = analysis?.title ?: copy.summaryTitleDefault,
        priorityButton = if (analysis != null && steps.isNotEmpty()) {
            if (analysis.attention > 0 || analysis.consider > 0) copy.priorityButton else copy.fromFirstButton
        } else {
            null
        },
        priorityIndex = analysis?.priorityIndex ?: 0,
        retryVisible = state.status == JobStatus.ERROR,
        timelineTitle = copy.timelineTitle,
        stepCount = copy.actionCount(steps.size),
        timeline = timeline,
        step = step,
        empty = if (decision == null) copy.empty else null,
    )
}

/** The opponent panel: executed bot decisions explained from their own records. */
fun presentOpponentReview(state: ReviewState): OpponentReviewView? {
    val input = state.input ?: return null
    val copy = ReviewDialogCopy
    val visible = state.opponentRecords
    val selected = state.opponentSelected
    val options = opponentFilterOptions(input.opponents)
    val timeline = visible.mapIndexed { i, r ->
        val v = r.trace.view
        val meta = "${r.name} · ${streetName(v?.street ?: 0)}"
        val action = actionLabel(r.labelStep())
        ReviewTimelineItem(i, "${r.sequence}", meta, action, r.trace.profileName, ReviewTone.PENDING, i == selected, copy.oppStepA11y(r.sequence, meta, action, r.trace.profileName))
    }
    val record = visible.getOrNull(selected)
    val step = record?.let { r ->
        val t = r.trace
        // The engine always records a view; without one the scene stays empty instead of failing.
        val v = t.view
        val e = explainOpponent(if (v != null) r else r.copy(trace = t.copy(view = BotView(r.id, emptyList(), legal = LegalActions.DISABLED))))
        OpponentStepView(
            index = selected,
            title = "${r.name} · ${streetName(v?.street ?: 0)}",
            statusText = copy.oppRecordStatus,
            tone = if (t.exceptions.isNotEmpty()) ReviewTone.CONSIDER else ReviewTone.SOUND,
            scene = ReviewSceneView(
                copy.oppHoleLabel(r.name), v?.hole ?: emptyList(), copy.boardLabel, v?.board ?: emptyList(), copy.noBoard,
                listOf(
                    ReviewMeta(copy.positionLabel, v?.position ?: ""),
                    ReviewMeta(copy.potLabel, number(v?.pot ?: 0)),
                    ReviewMeta(copy.stackLabel, number(v?.stack ?: 0)),
                ),
            ),
            choiceLabel = copy.oppChoiceLabel(e.made),
            choice = actionLabel(r.labelStep()),
            explanationTitle = e.title,
            explanation = e.detail,
            evidenceHeading = copy.oppEvidenceHeading,
            profileName = t.profileName,
            reasons = e.reasons,
            warning = e.warning,
            branchesSummary = copy.oppBranchesSummary,
            branches = t.checks.map { OpponentBranchRow(botCheckName(it.code), copy.oppBranch(it.value, it.threshold, it.selected)) },
            branchesEmpty = if (t.checks.isEmpty()) copy.oppBranchesEmpty else null,
            position = copy.oppPublicAction(r.sequence),
            canPrevious = selected > 0,
            canNext = selected < visible.size - 1,
        )
    }
    return OpponentReviewView(
        intro = copy.oppIntro,
        filterLabel = copy.oppFilterLabel,
        filterOptions = options,
        filter = state.opponentFilter,
        filterText = options.firstOrNull { it.value == state.opponentFilter }?.label ?: copy.oppFilterAll,
        timelineTitle = copy.oppTimelineTitle,
        count = copy.actionCount(visible.size),
        timeline = timeline,
        step = step,
        empty = if (record == null) copy.oppEmpty else null,
    )
}
