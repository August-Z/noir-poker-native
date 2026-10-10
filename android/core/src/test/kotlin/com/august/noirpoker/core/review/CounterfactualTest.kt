package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.HistoryEntry
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.act
import com.august.noirpoker.core.advanceStreet
import com.august.noirpoker.core.parseCards
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Port of the reference `counterfactual.test.js`. */
class CounterfactualTest {
    private fun snap(): ReviewDecision {
        val g = utgGame()
        act(g, 0, Action.CALL)
        return g.reviewDecisions()[0]
    }

    @Test
    fun `simulation is deterministic, public-only and leaves the snapshot unchanged`() {
        val s = snap()
        val saved = s.copy()
        val a = compareCandidateActions(s, trials = 6)
        assertEquals(saved, s)
        assertEquals(a, compareCandidateActions(s, trials = 6))
        assertEquals(Action.FOLD, a.rows[0].action.action)
        assertTrue(a.rows[0].scenarios.all { it.ev == 0.0 })
        assertTrue(a.rows.all { r -> r.scenarios.all { it.ev.isFinite() && it.margin.isFinite() } })
    }

    @Test
    fun `candidate generation respects closed raising and capped short-stack calls`() {
        val base = snap()
        val s = base.copy(legal = base.legal.copy(canRaise = false, callAmount = 25), stack = 25)
        val actions = candidateActions(s, listOf(CandidateAction(Action.RAISE, 5000)))
        assertTrue(actions.none { it.action == Action.RAISE })
        assertEquals(25, actions.first { it.action == Action.CALL }.amount)
    }

    @Test
    fun `a previous flat caller is not treated as defending a later unanswered 3-bet`() {
        val base = snap()
        val p = base.players[1]
        val h = parseCards("Qs 7s")
        val history = mutableListOf(HistoryEntry(0, 2, Action.RAISE, 150), HistoryEntry(0, 1, Action.CALL, 125))
        val before = rangeWeight(h, base.copy(history = history.toList()), p)
        history += HistoryEntry(0, 3, Action.RAISE, 650)
        assertEquals(before, rangeWeight(h, base.copy(history = history.toList()), p))
        history += HistoryEntry(0, 1, Action.CALL, 500)
        assertTrue(rangeWeight(h, base.copy(history = history.toList()), p) < before)
    }

    @Test
    fun `an opener who actually calls a 3-bet receives the later defense range`() {
        val base = snap()
        val p = base.players[1]
        val h = parseCards("Qs 7s")
        val before = rangeWeight(h, base.copy(history = listOf(HistoryEntry(0, 1, Action.RAISE, 150))), p)
        val after = rangeWeight(
            h,
            base.copy(
                history = listOf(
                    HistoryEntry(0, 1, Action.RAISE, 150),
                    HistoryEntry(0, 2, Action.RAISE, 650),
                    HistoryEntry(0, 1, Action.CALL, 500),
                ),
            ),
            p,
        )
        assertTrue(after < before)
    }

    @Test
    fun `river counterfactual uses pot eligibility and a board royal flush splits exactly`() {
        val g = utgGame()
        while (g.street < 3) {
            if (g.phase == Phase.BETWEEN) advanceStreet(g) else act(g, g.actor, Action.CALL)
        }
        g.board = parseCards("As Ks Qs Js Ts").toMutableList()
        g.players[0].hole = parseCards("2h 3h").toMutableList()
        while (g.actor != 0) act(g, g.actor, Action.CHECK)
        act(g, 0, Action.CHECK)
        val result = compareCandidateActions(g.reviewDecisions().last(), trials = 6)
        val row = result.rows.first { it.action.action == Action.CHECK }
        // Every player plays the same royal board, so the pot splits without invented hole-card edges.
        assertTrue(row.scenarios.all { it.ev == 50.0 }, row.toString())
    }
}
