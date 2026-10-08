package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.actionLabel
import com.august.noirpoker.core.jsRound

/** A candidate action: [amount] is the raise-to total, the call amount, or 0. */
data class CandidateAction(val action: Action, val amount: Int)

/** A conditional practice line. [summary] is present only on a primary route. */
data class Route(
    val action: Action,
    val amount: Int,
    val label: String,
    val summary: String?,
    val condition: String,
    val tradeoff: String,
) {
    val candidate: CandidateAction get() = CandidateAction(action, amount)
}

data class Routes(val primary: Route, val secondary: Route?)

/** The review status codes the classifier assigns. */
enum class ReviewStatus(val id: String) { SOUND("sound"), CONSIDER("consider"), ATTENTION("attention") }

private fun same(a: CandidateAction, b: CandidateAction) = a.action == b.action && (a.action != Action.RAISE || a.amount == b.amount)

// Candidate routes are conditional practice plans, not solved EV rankings.
fun comparisonRoutes(
    s: ReviewDecision,
    ctx: DecisionContext,
    code: String,
    status: ReviewStatus,
    alternative: CandidateAction,
    pre: PreflopContext?,
): Routes {
    val step = s.labelStep()
    fun label(a: CandidateAction) = actionLabel(step, a.action, a.amount)
    val actual = CandidateAction(s.action, s.amount)
    var summary = if (status == ReviewStatus.SOUND && same(actual, alternative)) ReviewCopy.routeKeep else label(alternative)
    var condition = ReviewCopy.routeDefaultCondition
    var tradeoff = ReviewCopy.routeDefaultTradeoff
    // A secondary candidate before its condition and trade-off are attached.
    var secondary: CandidateAction? = null
    var secondaryCondition = ""
    var secondaryTradeoff = ""
    fun raise(amount: Double): CandidateAction? = if (s.legal.canRaise) {
        CandidateAction(
            Action.RAISE,
            minOf(s.legal.maxRaiseTo, maxOf(s.legal.minRaiseTo, (jsRound(amount / 25) * 25).toInt())),
        )
    } else {
        null
    }
    fun setSecondary(candidate: CandidateAction?, c: String, t: String) {
        secondary = candidate
        secondaryCondition = c
        secondaryTradeoff = t
    }
    val callOrCheck = CandidateAction(if (s.legal.canCheck) Action.CHECK else Action.CALL, s.legal.callAmount)
    when {
        code == "late-open" || code == "late-isolation" -> {
            val limpers = pre?.limpers ?: 0
            summary = if (limpers != 0) ReviewCopy.routeLateSummaryIso else ReviewCopy.routeLateSummaryOpen
            condition = if (limpers != 0) ReviewCopy.routeLateConditionIso else ReviewCopy.routeLateConditionOpen
            tradeoff = ReviewCopy.routeLateTradeoff
            val size = if (alternative.amount > 100 + 50 * limpers) 100 + 50 * limpers else 150 + 50 * limpers
            setSecondary(raise(size.toDouble()), ReviewCopy.routeLateAltCondition, ReviewCopy.routeLateAltTradeoff)
        }
        code == "early-suited-entry" -> {
            summary = ReviewCopy.routeEarlySuitedSummary
            condition = ReviewCopy.routeEarlySuitedCondition
            tradeoff = ReviewCopy.routeEarlySuitedTradeoff
            setSecondary(raise(125.0), ReviewCopy.routeEarlySuitedAltCondition, ReviewCopy.routeEarlySuitedAltTradeoff)
        }
        code == "squeeze-candidate" -> {
            condition = ReviewCopy.routeSqueezeCondition
            tradeoff = ReviewCopy.routeSqueezeTradeoff
            setSecondary(raise(s.currentBet * 4.5), ReviewCopy.routeSqueezeAltCondition, ReviewCopy.routeSqueezeAltTradeoff)
        }
        code == "weak-threebet-defense" || code == "weak-fourbet-defense" || code == "weak-entry" -> {
            condition = ReviewCopy.routeWeakDefenseCondition
            tradeoff = ReviewCopy.routeWeakDefenseTradeoff
            setSecondary(
                if (s.legal.canCheck) null else CandidateAction(Action.CALL, s.legal.callAmount),
                if ((pre?.raises ?: 0) >= 3) ReviewCopy.routeWeakDefenseAltCondition4Bet else ReviewCopy.routeWeakDefenseAltCondition,
                ReviewCopy.routeWeakDefenseAltTradeoff,
            )
        }
        alternative.action == Action.RAISE -> {
            condition = when {
                code == "pressure-bet" -> ReviewCopy.routeRaiseConditionPressure
                ctx.draw.outs != 0 && ctx.handClass !in STRONG_CLASSES -> ReviewCopy.routeRaiseConditionDraw
                else -> ReviewCopy.routeRaiseConditionValue
            }
            tradeoff = ReviewCopy.routeRaiseTradeoff
            setSecondary(
                callOrCheck,
                if (ctx.inPosition) ReviewCopy.routeRaiseAltConditionIp else ReviewCopy.routeRaiseAltConditionOop,
                ReviewCopy.routeRaiseAltTradeoff,
            )
        }
        alternative.action == Action.FOLD -> {
            condition = ReviewCopy.routeFoldCondition
            tradeoff = ReviewCopy.routeFoldTradeoff
            setSecondary(
                if (!s.legal.canCheck) CandidateAction(Action.CALL, s.legal.callAmount) else null,
                ReviewCopy.routeFoldAltCondition,
                ReviewCopy.routeFoldAltTradeoff,
            )
        }
        alternative.action == Action.CALL -> {
            condition = ReviewCopy.routeCallCondition
            tradeoff = ReviewCopy.routeCallTradeoff
            setSecondary(CandidateAction(Action.FOLD, 0), ReviewCopy.routeCallAltCondition, ReviewCopy.routeCallAltTradeoff)
        }
        else -> {
            condition = if (ctx.inPosition) ReviewCopy.routeCheckConditionIp else ReviewCopy.routeCheckConditionOop
            tradeoff = ReviewCopy.routeCheckTradeoff
            if (ctx.handClass != HandClass.BOARD && s.legal.canRaise) {
                setSecondary(
                    raise(maxOf(50.0, s.pot * (if (ctx.texture.wet) 0.6 else 0.33))),
                    if (ctx.draw.outs != 0) ReviewCopy.routeCheckAltConditionDraw else ReviewCopy.routeCheckAltCondition,
                    ReviewCopy.routeCheckAltTradeoff,
                )
            }
        }
    }
    val primary = Route(alternative.action, alternative.amount, label(alternative), summary, condition, tradeoff)
    val second = secondary?.takeUnless { same(alternative, it) }
    return Routes(
        primary,
        second?.let { Route(it.action, it.amount, label(it), null, secondaryCondition, secondaryTradeoff) },
    )
}

private val STRONG_CLASSES = setOf(HandClass.OVERPAIR, HandClass.SET, HandClass.STRONG, HandClass.TWO_PAIR)
