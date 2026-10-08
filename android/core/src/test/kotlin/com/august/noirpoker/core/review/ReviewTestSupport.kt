package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.Game
import com.august.noirpoker.core.HistoryEntry
import com.august.noirpoker.core.LegalActions
import com.august.noirpoker.core.SeededRandom
import com.august.noirpoker.core.act
import com.august.noirpoker.core.newGame
import com.august.noirpoker.core.parseCards
import com.august.noirpoker.core.startHand

// Hand-built snapshots like the reference review unit tests. They omit the dealer and the
// seat-state keys, so they hash like the reference fixtures and run no candidate simulation.

private fun fullRaiseTo(currentBet: Int, minRaise: Int) = if (currentBet == 0) 50 else currentBet + minRaise

/** The `snapshot()` fixture of the reference review-check tests (river call by default). */
fun checkSnapshot(
    hole: String = "7s 2h",
    board: String = "2s 6h 9c Jd Qs",
    street: Int = 3,
    action: Action = Action.CALL,
    amount: Int = 100,
    position: String = "BTN",
    totals: List<Int> = listOf(100, 200, 0, 0, 0, 0),
    stacks: List<Int> = listOf(1000, 1000, 0, 0, 0, 0),
    allins: List<Int> = emptyList(),
    folded: (id: Int, total: Int) -> Boolean = { id, total -> id > 1 && total == 0 },
    pending: List<Int> = listOf(0),
    currentBet: Int = 200,
    canCheck: Boolean = false,
    canRaise: Boolean = true,
): ReviewDecision = ReviewDecision(
    index = 0,
    hand = 1,
    street = street,
    position = position,
    hole = parseCards(hole),
    board = if (board.isEmpty()) emptyList() else parseCards(board),
    stack = stacks[0],
    bet = totals[0],
    total = totals[0],
    pot = totals.sum(),
    currentBet = currentBet,
    minRaise = 50,
    dealer = null,
    emotionMode = null,
    legal = LegalActions(
        enabled = true,
        toCall = if (canCheck) 0 else amount,
        callAmount = if (canCheck) 0 else amount,
        canCheck = canCheck,
        raiseReopened = canRaise,
        canRaise = canRaise,
        minRaiseTo = currentBet + 50,
        fullRaiseTo = fullRaiseTo(currentBet, 50),
        maxRaiseTo = totals[0] + stacks[0],
    ),
    pending = pending,
    action = action,
    amount = amount,
    players = totals.mapIndexed { id, total ->
        ReviewSeat(
            id = id,
            name = listOf("You", "Mia", "Alex", "River", "Kai", "Luna")[id],
            position = position,
            stack = stacks[id],
            bet = total,
            total = total,
            folded = folded(id, total),
            allin = id in allins,
            action = if (id == 1) "Bet $currentBet" else "",
        )
    },
    history = listOf(HistoryEntry(street, 1, Action.RAISE, currentBet)),
)

/** The `decision()` fixture of the reference review-context tests (flop check by default). */
fun contextDecision(
    hole: String = "Qs Qh",
    board: String = "Js 7h 2c",
    street: Int = 1,
    action: Action = Action.CHECK,
    amount: Int = 0,
    stack: Int = 5000,
    currentBet: Int = 0,
    pot: Int = 300,
): ReviewDecision = ReviewDecision(
    index = 0,
    hand = 1,
    street = street,
    position = "BTN",
    hole = parseCards(hole),
    board = if (board.isEmpty()) emptyList() else parseCards(board),
    stack = stack,
    bet = 0,
    total = pot / 2,
    pot = pot,
    currentBet = currentBet,
    minRaise = 50,
    dealer = null,
    emotionMode = null,
    legal = LegalActions(
        enabled = true,
        toCall = currentBet,
        callAmount = currentBet,
        canCheck = currentBet == 0,
        canRaise = true,
        minRaiseTo = currentBet + 50,
        fullRaiseTo = fullRaiseTo(currentBet, 50),
        maxRaiseTo = stack,
    ),
    pending = listOf(0),
    action = action,
    amount = amount,
    players = listOf(
        ReviewSeat(0, "You", "BTN", stack, 0, pot / 2, folded = false, allin = false),
        ReviewSeat(1, "Mia", "BB", stack, currentBet, pot / 2, folded = false, allin = false),
    ),
    history = emptyList(),
)

/** A six-seat hand with the hero on the button after everyone before the hero folds (UTG…CO). */
fun buttonGame(hole: String = "Ac 7h", limp: Boolean = false, seed: Long = 5): Game {
    val g = newGame()
    g.dealer = 5
    startHand(g, SeededRandom(seed))
    g.players[0].hole = parseCards(hole).toMutableList()
    while (g.actor != 0) act(g, g.actor, if (limp && g.actor == 5) Action.CALL else Action.FOLD)
    return g
}

/** A six-seat hand with the hero under the gun (dealer seat 3). */
fun utgGame(seed: Long = 7): Game {
    val g = newGame()
    g.dealer = 2
    startHand(g, SeededRandom(seed))
    return g
}

fun Game.reviewDecisions(): List<ReviewDecision> = decisions.map { it.toReviewDecision() }

const val TEST_TRIALS = 120
