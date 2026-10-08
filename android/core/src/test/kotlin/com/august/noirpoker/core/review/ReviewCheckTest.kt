package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.PokerException
import com.august.noirpoker.core.SeededRandom
import com.august.noirpoker.core.act
import com.august.noirpoker.core.actionLabel
import com.august.noirpoker.core.advanceStreet
import com.august.noirpoker.core.newGame
import com.august.noirpoker.core.parseCards
import com.august.noirpoker.core.startHand
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/** Port of the reference `review-check.test.js`. */
class ReviewCheckTest {
    private val trials = 100

    private fun outcome(profit: Int, board: String, result: String = "") =
        ReviewOutcome(profit, 0, 0, folded = false, wonPot = false, board = parseCards(board), pots = emptyList(), result = result)

    @Test
    fun `every valid hero action records a before-action snapshot without hidden data`() {
        val g = utgGame()
        assertEquals(0, g.actor)
        val beforeStack = g.players[0].stack
        val beforePot = g.players.sumOf { it.total }
        act(g, 0, Action.CALL)
        val s = g.decisions[0].toReviewDecision()
        assertEquals(beforeStack, s.stack)
        assertEquals(beforePot, s.pot)
        assertEquals(Action.CALL, s.action)
        assertEquals(50, s.amount)
        assertTrue(s.board.isEmpty())
        assertTrue(s.history.isEmpty())
        val saved = s.copy()
        g.players[0].hole[0] = parseCards("2c")[0]
        g.players[1].stack = 1
        g.board.addAll(parseCards("As Kh Qc"))
        assertEquals(saved, g.decisions[0].toReviewDecision())
        assertEquals(saved, s)
    }

    @Test
    fun `illegal and out-of-turn actions do not create history entries`() {
        val g = newGame()
        startHand(g, SeededRandom(3))
        assertFailsWith<PokerException> { act(g, 0, Action.CALL) }
        assertTrue(g.decisions.isEmpty())
        assertTrue(g.history.isEmpty())
        g.dealer = 2
        g.phase = Phase.DONE
        startHand(g, SeededRandom(4))
        assertFailsWith<PokerException> { act(g, 0, Action.CHECK) }
        assertTrue(g.decisions.isEmpty())
    }

    @Test
    fun `all four streets are recorded and an empty call normalizes to check`() {
        val g = utgGame()
        while (g.phase != Phase.DONE) {
            if (g.phase == Phase.BETWEEN) advanceStreet(g) else act(g, g.actor, Action.CALL)
        }
        assertEquals(listOf(0, 1, 2, 3), g.decisions.map { it.street })
        assertEquals(listOf(0, 3, 4, 5), g.decisions.map { it.board.size })
        assertEquals(listOf(Action.CALL, Action.CHECK, Action.CHECK, Action.CHECK), g.decisions.map { it.action })
        val input = createReviewInput(g)
        startHand(g, SeededRandom(8))
        assertTrue(g.decisions.isEmpty())
        assertEquals(4, input.decisions.size)
        assertEquals(5, input.outcome.board.size)
    }

    @Test
    fun `review cannot start before settlement`() {
        val g = newGame()
        startHand(g, SeededRandom(1))
        val e = assertFailsWith<ReviewException> { createReviewInput(g) }
        assertEquals("You can review a hand only after it ends.", e.message)
    }

    @Test
    fun `folding when a free check exists recommends the legal free check`() {
        val s = checkSnapshot(action = Action.FOLD, canCheck = true, amount = 0, currentBet = 0, totals = listOf(50, 50, 0, 0, 0, 0))
        val r = analyzeDecision(s, trials)
        assertEquals(ReviewStatus.ATTENTION, r.status)
        assertEquals(Action.CHECK, r.alternative.action)
    }

    @Test
    fun `weak early-position preflop entry recommends folding`() {
        val s = checkSnapshot(
            street = 0,
            board = "",
            position = "UTG",
            totals = listOf(0, 50, 25, 0, 0, 0),
            stacks = List(6) { 1000 },
            currentBet = 50,
            amount = 50,
        )
        assertEquals(Action.FOLD, analyzeDecision(s, trials).alternative.action)
    }

    @Test
    fun `strong all-in losing to a later runout is not automatically a mistake`() {
        val s = checkSnapshot(
            hole = "As Ah",
            street = 0,
            board = "",
            action = Action.RAISE,
            amount = 1000,
            totals = listOf(0, 50, 25, 0, 0, 0),
            stacks = listOf(1000, 1000, 1000, 0, 0, 0),
            currentBet = 50,
        )
        val input = ReviewInput(1, s.hole, listOf(s), emptyList(), outcome(-1000, "Ks Kh Kc Qd 2s"))
        val r = analyzeReview(input, trials)
        assertEquals(0, r.attention)
        assertEquals("No obvious decision mistakes found", r.title)
    }

    @Test
    fun `decision verdicts do not change with the showdown winner or the future board`() {
        val s = checkSnapshot(street = 1, board = "2s 6h 9c")
        val a = ReviewInput(1, s.hole, listOf(s), emptyList(), outcome(-200, "2s 6h 9c As Ah", "Mia wins 400 chips"))
        val b = a.copy(outcome = outcome(500, "2s 6h 9c 7h 7c", "You win 400 chips"))
        assertEquals(analyzeReview(a, trials).steps, analyzeReview(b, trials).steps)
    }

    @Test
    fun `recommendations never reopen a legally closed raise`() {
        val s = checkSnapshot(hole = "As Ah", street = 0, board = "", canRaise = false)
        assertNotEquals(Action.RAISE, analyzeDecision(s, trials).alternative.action)
    }

    @Test
    fun `a recommended raise respects the minimum and maximum`() {
        val s = checkSnapshot(hole = "As Ah", street = 0, board = "", currentBet = 50, totals = listOf(0, 50, 25, 0, 0, 0), amount = 50)
        val r = analyzeDecision(s, trials)
        assertEquals(Action.RAISE, r.alternative.action)
        assertTrue(r.alternative.amount in s.legal.minRaiseTo..s.legal.maxRaiseTo)
    }

    @Test
    fun `short-stack call price excludes unreachable side pots`() {
        val s = checkSnapshot(
            totals = listOf(50, 300, 300, 0, 0, 0),
            stacks = listOf(50, 1000, 1000, 0, 0, 0),
            amount = 50,
            currentBet = 300,
            folded = { id, total -> id > 2 && total == 0 },
        )
        val p = callPrice(s)
        assertEquals(300, p.contestable)
        assertEquals(50, p.cost)
        assertEquals(1.0 / 6, p.required)
        assertEquals(1, p.pots.size)
        assertEquals(listOf(0, 1, 2), p.pots[0].eligible)
    }

    @Test
    fun `main and side pots have distinct eligible opponents in call analysis`() {
        val s = checkSnapshot(
            totals = listOf(100, 100, 300, 300, 0, 0),
            stacks = listOf(200, 0, 1000, 1000, 0, 0),
            amount = 200,
            currentBet = 300,
            allins = listOf(1),
            folded = { id, total -> id > 3 && total == 0 },
        )
        val p = callPrice(s)
        assertEquals(listOf(400, 600), p.pots.map { it.amount })
        assertEquals(listOf(listOf(0, 1, 2, 3), listOf(0, 2, 3)), p.pots.map { it.eligible })
        assertEquals(1000, p.contestable)
        assertEquals(0.2, p.required)
    }

    @Test
    fun `uncalled refunds are not confused with risk or pot winnings`() {
        val s = checkSnapshot(
            totals = listOf(25, 20, 0, 0, 0, 0),
            stacks = listOf(1000, 0, 0, 0, 0, 0),
            allins = listOf(1),
            amount = 25,
            currentBet = 50,
            canRaise = false,
        )
        val p = callPrice(s)
        assertEquals(5, p.refundBefore)
        assertEquals(30, p.refundAfter)
        assertEquals(0, p.cost)
        assertEquals(40, p.contestable)
    }

    @Test
    fun `folded contributions remain in the call price but folded players cannot win`() {
        val s = checkSnapshot(
            totals = listOf(100, 200, 200, 0, 0, 0),
            stacks = listOf(1000, 1000, 0, 0, 0, 0),
            amount = 100,
            folded = { id, total -> id == 2 || (id > 1 && total == 0) },
        )
        val p = callPrice(s)
        assertEquals(600, p.contestable)
        assertEquals(listOf(0, 1), p.pots[0].eligible)
    }

    @Test
    fun `royal flush on the board yields a tie rather than a false advantage`() {
        val s = checkSnapshot(hole = "2h 3h", board = "As Ks Qs Js Ts", totals = listOf(100, 200, 0, 0, 0, 0), amount = 100)
        val r = analyzeDecision(s, trials)
        assertEquals(0.5, r.metrics.equityLow)
        assertEquals(0.5, r.metrics.equityHigh)
        assertEquals(ReviewStatus.SOUND, r.status)
    }

    @Test
    fun `deterministic ranges stay stable when a review is reopened`() {
        val s = checkSnapshot()
        assertEquals(analyzeDecision(s, trials), analyzeDecision(s, trials))
    }

    @Test
    fun `blind-only loss has no fabricated decision mistakes`() {
        val input = ReviewInput(1, parseCards("7s 2h"), emptyList(), emptyList(), outcome(-25, ""))
        val r = analyzeReview(input, trials)
        assertTrue(r.steps.isEmpty())
        assertEquals(0, r.attention)
        assertEquals("You made no decisions this hand; forced blinds can't count as mistakes.", r.summary)
    }

    @Test
    fun `short all-in raise and all-in call labels use street total versus added amount`() {
        val s = checkSnapshot(
            action = Action.RAISE,
            amount = 125,
            totals = listOf(100, 100, 0, 0, 0, 0),
            stacks = listOf(25, 1000, 0, 0, 0, 0),
            currentBet = 100,
        )
        assertEquals("2-bet short all-in to 125", actionLabel(s.labelStep()))
        val call = s.copy(action = Action.CALL, legal = s.legal.copy(callAmount = 25))
        assertEquals("All-In Call 25", actionLabel(call.labelStep()))
    }

    @Test
    fun `starting-hand tiers distinguish premium and weak unsuited hands`() {
        assertEquals(3, startingTier(parseCards("As Ah")))
        assertEquals(0, startingTier(parseCards("7s 2h")))
    }
}
