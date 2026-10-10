package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.BotDecisionRecord
import com.august.noirpoker.core.Card
import com.august.noirpoker.core.DecisionSnapshot
import com.august.noirpoker.core.EmotionMode
import com.august.noirpoker.core.Game
import com.august.noirpoker.core.HistoryEntry
import com.august.noirpoker.core.LabelLegal
import com.august.noirpoker.core.LabelStep
import com.august.noirpoker.core.LegalActions
import com.august.noirpoker.core.MoodKind
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.SnapshotPlayer

// Privacy boundary. Decision review grades the hero only from what was public (plus the
// hero's own cards) before each decision. The types below have no field for opponents'
// hole cards, the remaining deck, future community cards, settlement results or final
// winners, so grading code cannot read them.

/**
 * Seat keys every engine snapshot carries. Hand-built snapshots (reference unit tests)
 * omit all four; that absence changes the decision seed and disables the candidate
 * simulation, exactly like an absent JavaScript key.
 */
data class SeatState(
    /** The bet level this seat last acted at this street; `null` before acting. */
    val actedTo: Int?,
    val checked: Boolean,
    /** Public style id; `null` for the hero. */
    val botProfile: String?,
    /** Public mood kind; `null` for the hero. */
    val botMoodKind: MoodKind?,
)

/** One seat at the moment of a hero decision: public chip state only, never hole cards. */
data class ReviewSeat(
    val id: Int,
    val name: String,
    val position: String,
    val stack: Int,
    val bet: Int,
    val total: Int,
    val folded: Boolean,
    val allin: Boolean,
    /** Current-street public action text. */
    val action: String = "",
    val publicAxes: List<Double>? = null,
    /** `null` when the snapshot omits these keys (hand-built snapshots). */
    val state: SeatState? = null,
)

/**
 * A hero decision snapshot as review reads it (the reference `g.decisions[i]`).
 * [dealer] and [emotionMode] are `null` where a hand-built snapshot omits them.
 */
data class ReviewDecision(
    val index: Int,
    val hand: Int,
    val street: Int,
    val position: String,
    /** The hero's own hole cards. */
    val hole: List<Card>,
    /** Community cards dealt before this decision. */
    val board: List<Card>,
    val stack: Int,
    val bet: Int,
    val total: Int,
    val pot: Int,
    val currentBet: Int,
    val minRaise: Int,
    val dealer: Int?,
    val emotionMode: EmotionMode?,
    val legal: LegalActions,
    /** Seats still to act this round, including the hero. */
    val pending: List<Int>,
    /** The normalized hero action (`call` with nothing owed is `check`). */
    val action: Action,
    /** Raise-to total, call amount, or 0. */
    val amount: Int,
    /** Every seat; the list index equals the seat id. */
    val players: List<ReviewSeat>,
    /** Public actions before this decision. */
    val history: List<HistoryEntry>,
    /**
     * `legal.fullRaiseTo` as the label functions see it. Hand-built snapshots (reference unit
     * tests) omit the key; `null` then makes raise captions fall back to
     * `currentBet + minRaise` (or 50 unopened), like the reference's `??` fallback.
     */
    val labelFullRaiseTo: Int? = legal.fullRaiseTo,
) {
    /** The label step `actionLabel(s, …)` reads. */
    fun labelStep(): LabelStep = LabelStep(
        street,
        history,
        currentBet,
        minRaise,
        if (legal.enabled) LabelLegal(legal.callAmount, labelFullRaiseTo, legal.maxRaiseTo) else LabelLegal(),
        stack,
        action,
        amount.toDouble(),
    )
}

fun SnapshotPlayer.toReviewSeat(): ReviewSeat = ReviewSeat(
    id = id,
    name = name,
    position = position,
    stack = stack,
    bet = bet,
    total = total,
    folded = folded,
    allin = allin,
    action = action,
    publicAxes = publicAxes?.toList(),
    state = SeatState(actedTo, checked, botProfile, botMoodKind),
)

/** The review view of an engine decision snapshot; every key is present. */
fun DecisionSnapshot.toReviewDecision(): ReviewDecision = ReviewDecision(
    index = index,
    hand = hand,
    street = street,
    position = position,
    hole = hole.toList(),
    board = board.toList(),
    stack = stack,
    bet = bet,
    total = total,
    pot = pot,
    currentBet = currentBet,
    minRaise = minRaise,
    dealer = dealer,
    emotionMode = emotionMode,
    legal = legal,
    pending = pending.toList(),
    action = action,
    amount = amount,
    players = players.map { it.toReviewSeat() },
    history = history.toList(),
)

// Settlement display fields the reference copies into the review input. They are shown
// next to the review and never passed to `analyzeDecision`.

data class OutcomeAward(val name: String, val amount: Int, val label: String)

data class OutcomePot(val label: String, val amount: Int, val eligible: List<String>, val awards: List<OutcomeAward>)

data class ReviewOutcome(
    val profit: Int,
    val paid: Int,
    val returned: Int,
    val folded: Boolean,
    val wonPot: Boolean,
    val board: List<Card>,
    val pots: List<OutcomePot>,
    val result: String,
)

/**
 * `createReviewInput(g)`. [decisions] are the only grading input; [opponents] are the
 * executed bot records for the opponent explanations, read only by [explainOpponent].
 */
data class ReviewInput(
    val hand: Int,
    val hole: List<Card>,
    val decisions: List<ReviewDecision>,
    val opponents: List<BotDecisionRecord>,
    val outcome: ReviewOutcome,
)

class ReviewException(message: String) : RuntimeException(message)

/** An immutable copy of a settled hand; later engine mutations never reach it. */
fun createReviewInput(g: Game): ReviewInput {
    if (g.phase != Phase.DONE) throw ReviewException(ReviewCopy.errorInputNotDone)
    val hero = g.players[0]
    val returned = g.payouts.getOrNull(0) ?: 0
    return ReviewInput(
        hand = g.hand,
        hole = hero.hole.toList(),
        decisions = g.decisions.map { it.toReviewDecision() },
        opponents = g.botDecisions.toList(),
        outcome = ReviewOutcome(
            profit = returned - hero.total,
            paid = hero.total,
            returned = returned,
            folded = hero.folded,
            wonPot = g.winners.any { it.id == 0 },
            board = g.board.toList(),
            pots = g.pots.map { p ->
                OutcomePot(
                    label = p.label,
                    amount = p.amount,
                    eligible = p.eligible.map { g.players[it].name },
                    awards = p.awards.map { OutcomeAward(g.players[it.id].name, it.amount, it.label) },
                )
            },
            result = g.result,
        ),
    )
}
