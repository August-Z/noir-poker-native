package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.BotDecisionRecord
import com.august.noirpoker.core.EmotionMode
import com.august.noirpoker.core.MoodKind
import com.august.noirpoker.core.evaluate

/** English names of the bot decision reasons (`BOT_REASON_NAMES`). */
val BOT_REASON_NAMES: Map<String, String> = linkedMapOf(
    "outside-range" to "Hand outside this defending range",
    "insufficient-equity" to "Estimated equity below the calling threshold",
    "stack-pressure" to "Stack pressure triggered a tighter range",
    "loose-exception" to "Random leeway kept a marginal action",
    "premium-continue" to "Premium-hand branch kept it in",
    "affordable-entry" to "Low-cost entry range kept it in",
    "affordable-open" to "Small open's price and effective stack supported calling",
    "price-continue" to "Passed the price and pressure checks",
    "value-raise" to "Raising range triggered aggression",
    "semi-bluff" to "Draw triggered a semi-bluff",
    "pure-bluff" to "Bluff roll triggered pressure",
    "trap" to "Strong hand on a dry board triggered a trap check",
    "free-check" to "Took a free look / pot control",
)

/** English names of the random branch rolls (`BOT_CHECK_NAMES`). */
val BOT_CHECK_NAMES: Map<String, String> = LinkedHashMap(BOT_REASON_NAMES).apply {
    put("outside-range", "Leeway roll when outside range")
    put("insufficient-equity", "Leeway roll when equity is short")
    put("stack-pressure", "Leeway roll under high pressure")
    put("attack", "Aggression frequency roll")
    put("trap", "Trap-check roll")
    put("rare-pocket-shove", "Rare small-pair shove roll")
}

/** The reason name, or the raw code for an unknown one. */
fun botReasonName(code: String): String = BOT_REASON_NAMES[code] ?: code

/** The branch-roll name, or the raw code for an unknown one. */
fun botCheckName(code: String): String = BOT_CHECK_NAMES[code] ?: code

/** Why an executed bot action happened, from its private record, shown after settlement. */
data class OpponentExplanation(
    val title: String,
    val detail: String,
    val reasons: List<String>,
    /** Hand-strength label at the time (`"Preflop hand"` before the flop). */
    val made: String,
    val warning: String,
)

private fun names(codes: List<String>) = codes.joinToString(", ") { lower(botReasonName(it)) }

private fun opponents(n: Int) = count(n, "opponent", "opponents")

/**
 * Explains one executed bot decision from its own record (the bot's perspective and
 * trace). It never grades the hero and never reads the hero's decision snapshots.
 */
fun explainOpponent(record: BotDecisionRecord): OpponentExplanation {
    val t = record.trace
    val v = requireNotNull(t.view) { "A bot decision record carries its view" }
    val made = evaluate(v.hole + v.board)
    val draw = drawInfo(v.hole, v.board)
    val call = record.action == Action.CALL
    val raises = v.history.filter { it.street == v.street && it.action == Action.RAISE }
    val comparison = t.equity + t.callTolerance
    val reasons = mutableListOf<String>()
    if (v.street == 0) {
        reasons.add(
            "Starting-hand rank: about top ${pct(t.percentile)}; this style, position, and the public raising line allow the top ${pct(t.range)}. " +
                "It ${if (t.admitted) "was inside" else "was outside"} that range" +
                (if (t.premium) ", and it also triggered the top-7% premium branch" else "") +
                ". The ranking is a starting-hand heuristic, not a win rate.",
        )
    }
    reasons.add(
        "It faced ${opponents(v.rivals)} still in, needed ${number(v.legal.callAmount)} to call, could win ${number(v.contestable)} in the model, " +
            "and needed ${pct(t.odds)} equity to call.",
    )
    if (t.exceptions.isNotEmpty() && t.reason != "loose-exception") {
        reasons.add(
            "It had triggered ${names(t.exceptions)}, but a leeway roll kept it in before it reached the current action branch; " +
                "don't ignore this risk just because of the final value / bluff label.",
        )
    }
    if (t.cheapRangePassed) {
        reasons.add(
            "It passed the low-cost entry branch, so the normal equity fold check didn't run; the equity and threshold below are only " +
                "the values computed at the time, not what triggered this action.",
        )
    }
    if (t.affordableOpen && t.affordableRangePassed == true) {
        reasons.add(
            sentences(
                "There was only one small open this street; the effective stack behind after calling was about " +
                    "${number(t.entryContext.effectiveBehind / 50.0)} BB, with " +
                    "${count(t.entryContext.openCallers, "caller", "callers")} already in.",
                (if (t.entryContext.speculative || t.entryContext.suitedHigh) {
                    "The postflop potential of a pair or a suitable suited hand"
                } else {
                    "Its starting-hand rank and the current price"
                }) + " put it into a separate calling range, so the usual fold check on random-hand showdown equity across the table didn't run.",
                "This approximation doesn't prove the call is profitable.",
            ),
        )
    }
    reasons.add(
        "Using only its own cards and the board, it sampled random opponent ranges ${t.trials} times: raw estimate ${pct(t.rawEquity)}, " +
            "judgment noise ${signedPct(t.noise)}, equity used ${pct(t.equity)}. Calling-tendency shift ${signedPct(t.callTolerance)}, " +
            "compared value ${pct(comparison)}; the usual threshold, including a 2-point buffer, was ${pct(t.odds + 0.02)}.",
    )
    val detail = when (t.reason) {
        "loose-exception" ->
            "It originally triggered ${names(t.exceptions)}, but a random leeway roll kept it in. So this ${if (call) "call" else "action"} " +
                "is a deliberately loose mistake built into the model; it can't be read as the odds proving it worth continuing."
        "premium-continue" ->
            "It classed this hand as a premium starting hand and skipped the normal equity and high-pressure fold checks preflop; " +
                "this is a model approximation and doesn't mean an all-in should be called at any player count or price."
        "affordable-entry" ->
            "This was a low-cost entry into an unraised pot, costing at most one more BB. The hand was in an entry range widened by " +
                "position and style, so it didn't mechanically fold by comparing multiway showdown equity against random hands with the " +
                "immediate blind odds; this is no reason to call a big raise or an all-in."
        "affordable-open" ->
            "This was a conditional call against a single small open: the open was no more than 4 BB, the extra cost was small, the " +
                "opener wasn't all-in, and the effective stack behind after calling was still deep enough. Position, style, hand " +
                "playability, and the callers already in set the candidate range. Calling and re-raising are decided separately; " +
                "3-bets, large bets, and short stacks don't get this exemption."
        "price-continue" ->
            "No fold branch was triggered. If it didn't raise, the aggression roll missed, there was no suitable target, or raising " +
                "was no longer allowed. Passing the program's checks doesn't mean the play is profitable against the real continuing range."
        "value-raise" -> if (v.street == 0) {
            "The hand was in the ${if (raises.isNotEmpty()) "separate value re-raise" else "open / isolation raise"} candidate range " +
                "(about the top ${pct(t.raiseRange)}), or triggered the premium branch, and the aggression roll hit, so it built the pot. " +
                "Marginal hands allowed to flat don't automatically re-raise just because the entry range widened, and the label doesn't mean the nuts."
        } else {
            "Equity against a random range was above ${pct(if (v.rivals == 1) 0.53 else 1.0 / (v.rivals + 1) + 0.23)}, or it met " +
                "\"overpair with more than 40% equity,\" and the aggression roll hit. A made hand isn't required; even ace-high can land " +
                "in this branch under a wide-range estimate. If the opponent's continuing range is strong, this estimate may be too optimistic."
        }
        "semi-bluff" ->
            "It saw that it had a draw, with no more than three players in the hand, and both the semi-bluff and aggression rolls hit. " +
                "The payoff includes fold equity; its completion cards may still not be clean winning outs."
        "pure-bluff" ->
            "It saw pressure conditions (late position / continuing aggression / a fairly dry board), its stack pressure was under 25%, " +
                "and both the bluff and aggression rolls hit. It didn't read your hole cards and doesn't prove you would fold."
        "trap" ->
            "With a free check, a dry board, and estimated equity above 65%, it hit the trap branch, leaving room for opponents to bet."
        "free-check" ->
            "It had nothing to call, didn't raise, and took a free look. A check doesn't mean it was weak; the aggression roll may simply have missed."
        else -> "Actually executed: ${lower(botReasonName(t.reason))}. Cards dealt later were not used to decide this step."
    }
    if (draw.outs != 0) {
        reasons.add(
            "It saw ${count(draw.outs, "direct straight / flush completion card", "direct straight / flush completion cards")}, " +
                "${pct(draw.nextChance)} to hit on the next card; that is not a probability of winning.",
        )
    }
    val moodActive = t.mode != EmotionMode.OFF && t.mood.kind != MoodKind.STEADY
    reasons.add(
        if (moodActive) {
            "Simulated mood: ${t.mood.kind.label}. Trigger: ${t.mood.reason.ifEmpty { "an event in an earlier hand" }}. " +
                "Base / actual looseness ${t.baseAxes[0]} / ${jsNumber(t.axes[0])}, aggression ${t.baseAxes[1]} / ${jsNumber(t.axes[1])}, " +
                "calling ${t.baseAxes[3]} / ${jsNumber(t.axes[3])}; whether this state changed the action still depends on the branches above."
        } else {
            "No mood shift this time; base style settings were used."
        },
    )
    val sizing = t.sizing
    if (sizing != null && !sizing.executed) {
        reasons.add(
            "It tried to raise to ${number(sizing.actual)}, but that hit the safeguard against max-size pure-bluff shoves, so the raise " +
                "wasn't made; the actual action is still the ${if (call) "call" else "check"} recorded above.",
        )
    }
    if (sizing != null && sizing.executed) {
        reasons.add(
            sentences(
                "Sizing first produced a total of ${number(sizing.desired)}, then was clamped to the legal range " +
                    "${number(sizing.minimum)}–${number(sizing.maximum)}, giving ${number(sizing.actual)}.",
                if (sizing.opening) {
                    "In an unraised pot, it uses the open / number-of-limpers formula."
                } else {
                    "Sizing factor about ${pct(sizing.fraction)} × (pot at the time + call amount), plus the current total bet."
                },
            ),
        )
    }
    val warn = call &&
        (t.exceptions.isNotEmpty() || (t.affordableRangePassed != true && comparison < t.odds + 0.02) || raises.size > 1)
    return OpponentExplanation(
        title = botReasonName(t.reason),
        detail = detail,
        reasons = reasons,
        made = if (v.street != 0) made.label else "Preflop hand",
        warning = if (warn) {
            "Be especially careful with this continue: the bot estimated against a random range and didn't fully narrow it for your " +
                "raising line; small samples, the premium-hand exemption, or random leeway can all produce unreasonable calls. The record " +
                "explains why it happened; it doesn't prove the play was right."
        } else {
            "This is the decision record the simulator actually used at the time. Equity is a small-sample estimate against a random " +
                "range; it doesn't fully model the opponent's continuing range, equity realization, or future strategy. It is not a real " +
                "pro's thinking and not proof of optimal play."
        },
    )
}
