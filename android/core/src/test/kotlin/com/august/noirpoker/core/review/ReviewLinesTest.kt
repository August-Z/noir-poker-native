package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.SeededRandom
import com.august.noirpoker.core.act
import com.august.noirpoker.core.advanceStreet
import com.august.noirpoker.core.legalActions
import com.august.noirpoker.core.parseCards
import com.august.noirpoker.core.playBotTurn
import com.august.noirpoker.core.restartHand
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** Port of the reference `review-lines.test.js` (preflop lines and the review privacy boundary). */
class ReviewLinesTest {
    private fun threeBetFourBetLine() = buttonGame().also { g ->
        act(g, 0, Action.RAISE, 150)
        act(g, 1, Action.CALL)
        act(g, 2, Action.RAISE, 650)
        act(g, 0, Action.CALL)
        act(g, 1, Action.RAISE, 1800)
        act(g, 2, Action.CALL)
        act(g, 0, Action.CALL)
    }

    @Test
    fun `A7 offsuit button open has a position and blocker rationale and a distinct conditional size`() {
        val g = buttonGame()
        act(g, 0, Action.RAISE, 150)
        val s = g.reviewDecisions()[0]
        val r = analyzeDecision(s, TEST_TRIALS)
        assertEquals("late-open", r.code)
        assertEquals(ReviewStatus.SOUND, r.status)
        assertTrue("blocks" in r.reason || "late position" in r.reason.lowercase(), r.reason)
        assertTrue("open / steal" in r.reason, r.reason)
        assertFalse(Regex("no .*draw", RegexOption.IGNORE_CASE).containsMatchIn(r.reason), r.reason)
        assertFalse(r.recommendation.endsWith(" to 150"), r.recommendation)
        val secondary = assertNotNull(r.routes.secondary)
        assertEquals(Action.RAISE, secondary.action)
        assertNotEquals(r.routes.primary.amount, secondary.amount)
        assertTrue(secondary.amount >= s.legal.minRaiseTo)
        assertTrue(Regex("range|cost", RegexOption.IGNORE_CASE).containsMatchIn(secondary.tradeoff), secondary.tradeoff)
    }

    @Test
    fun `button isolation of a limper is distinct from an unopened steal and a true squeeze`() {
        val g = buttonGame(limp = true)
        act(g, 0, Action.RAISE, 200)
        val r = analyzeDecision(g.reviewDecisions()[0], TEST_TRIALS)
        assertEquals("late-isolation", r.code)
        assertTrue(Regex("limper|isolation", RegexOption.IGNORE_CASE).containsMatchIn(r.reason), r.reason)
        assertTrue(Regex("multiway|a lot", RegexOption.IGNORE_CASE).containsMatchIn(r.plan), r.plan)
    }

    @Test
    fun `calls against a 3-bet and a 4-bet get distinct recommendations from the actual legal line`() {
        val a = threeBetFourBetLine().reviewDecisions().map { analyzeDecision(it, TEST_TRIALS) }
        assertEquals(listOf("late-open", "weak-threebet-defense", "weak-fourbet-defense"), a.map { it.code })
        assertEquals(Action.FOLD, a[1].alternative.action)
        assertEquals(ReviewStatus.ATTENTION, a[2].status)
        assertTrue("earlier open was reasonable" in a[1].reason, a[1].reason)
        assertTrue("4-bet" in a[2].lesson, a[2].lesson)
        assertNotEquals(a[1].plan, a[2].plan)
    }

    @Test
    fun `suited weak ace defense discusses realization rather than only the rank label`() {
        val steps = listOf("Ac 7h", "Ac 7c").map { hole ->
            val g = buttonGame(hole)
            act(g, 0, Action.RAISE, 150)
            act(g, 1, Action.RAISE, 350)
            act(g, 2, Action.FOLD)
            act(g, 0, Action.CALL)
            analyzeDecision(g.reviewDecisions()[1], TEST_TRIALS)
        }
        assertTrue("offsuit" in steps[0].plan, steps[0].plan)
        assertTrue("flush potential" in steps[1].plan, steps[1].plan)
        assertEquals(ReviewStatus.CONSIDER, steps[0].status)
    }

    @Test
    fun `repeated calls on one street do not count as several earlier streets`() {
        val g = threeBetFourBetLine()
        advanceStreet(g)
        while (g.actor != 0) act(g, g.actor, Action.CHECK)
        act(g, 0, Action.CHECK)
        val c = decisionContext(g.reviewDecisions().last())
        assertEquals(1, c.pastCalls)
        assertEquals(2, c.pastCallActions)
    }

    @Test
    fun `calling a sole all-in opponent closes future betting even with hero chips behind`() {
        val g = buttonGame()
        act(g, 0, Action.RAISE, 150)
        g.players[1].stack = 850
        act(g, 1, Action.RAISE, 875)
        act(g, 2, Action.FOLD)
        act(g, 0, Action.CALL)
        assertTrue(callPrice(g.reviewDecisions().last()).closing)
        assertFalse(g.players[0].allin)
    }

    @Test
    fun `an opponent all-in does not close betting while another live opponent can act`() {
        val g = buttonGame()
        act(g, 0, Action.RAISE, 150)
        g.players[1].stack = 850
        act(g, 1, Action.RAISE, 875)
        act(g, 2, Action.CALL)
        act(g, 0, Action.CALL)
        assertFalse(callPrice(g.reviewDecisions().last()).closing)
    }

    @Test
    fun `settled bot traces stay separate from hero grading and replay clears them`() {
        val g = utgGame(seed = 91)
        val rng = SeededRandom(91)
        val wealth = g.players.sumOf { it.stack + it.total }
        while (g.phase != Phase.DONE) {
            when {
                g.phase == Phase.BETWEEN -> advanceStreet(g)
                g.actor == 0 -> act(g, 0, if (legalActions(g).canCheck) Action.CHECK else Action.CALL)
                else -> playBotTurn(g, rng)
            }
        }
        assertEquals(wealth, g.players.sumOf { it.stack })
        val input = createReviewInput(g)
        assertTrue(input.opponents.isNotEmpty())
        val steps = analyzeReview(input, TEST_TRIALS).steps
        val fake = input.opponents[0].let { it.copy(trace = it.trace.copy(reason = "fake", view = it.trace.view?.copy(hole = parseCards("As Ah")))) }
        val altered = input.copy(
            opponents = listOf(fake),
            outcome = input.outcome.copy(profit = -9999, board = parseCards("2s 3h 4c 5d 6s")),
        )
        assertEquals(steps, analyzeReview(altered, TEST_TRIALS).steps)
        restartHand(g)
        assertTrue(g.botDecisions.isEmpty())
        assertTrue(g.decisions.isEmpty())
        assertTrue(input.opponents.isNotEmpty())
    }

    @Test
    fun `Q7 suited under the gun acknowledges its suit and treats the open as range-sensitive`() {
        val g = utgGame()
        g.players[0].hole = parseCards("Qs 7s").toMutableList()
        act(g, 0, Action.RAISE, 150)
        val r = analyzeDecision(g.reviewDecisions()[0], TEST_TRIALS)
        assertEquals("early-suited-entry", r.code)
        assertEquals(ReviewStatus.CONSIDER, r.status)
        assertTrue("genuinely suited" in r.reason, r.reason)
        assertFalse("harder to realize" in r.reason, r.reason)
        assertEquals(Action.RAISE, r.routes.secondary?.action)
        val simulation = assertNotNull(r.simulation)
        assertTrue(simulation.rows.size >= 4)
    }
}
