package com.august.noirpoker.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class BetLabelsTest {
    private fun nextLabel(g: Game, amount: Int) = actionLabel(labelStep(g, legalActions(g), Action.RAISE, amount))

    @Test
    fun `preflop 2-, 3- and 4-bets survive calls and before-action snapshots`() {
        val g = newGame()
        g.dealer = 5
        startHand(g, SeededRandom(1))
        while (g.actor != 0) act(g, g.actor, Action.FOLD)
        assertEquals("2-bet open to 150", nextLabel(g, 150))
        act(g, 0, Action.RAISE, 150)
        act(g, 1, Action.CALL)
        assertEquals("3-bet raise to 650", nextLabel(g, 650))
        act(g, 2, Action.RAISE, 650)
        act(g, 0, Action.CALL)
        assertEquals("4-bet raise to 1,800", nextLabel(g, 1800))
        act(g, 1, Action.RAISE, 1800)
        act(g, 2, Action.CALL)
        act(g, 0, Action.CALL)
        assertEquals("2-bet open to 150", actionLabel(g.decisions[0].labelStep()))
        assertEquals("5-bet raise to 3,000", actionLabel(g.decisions[2].labelStep(), Action.RAISE, 3000))
        assertEquals(
            listOf("2-bet open to", "3-bet raise to", "4-bet raise to"),
            g.history.filter { it.action == Action.RAISE }.map { it.betLabel },
        )
        assertTrue(g.logs.any { it.text.endsWith(": 3-bet raise to 650") })
        assertEquals(30000, wealth(g))

        advanceStreet(g)
        assertEquals("1-bet bet to 100", nextLabel(g, 100))
        act(g, 1, Action.CHECK)
        act(g, 2, Action.RAISE, 100)
        act(g, 0, Action.CALL)
        assertEquals("2-bet raise to 300", nextLabel(g, 300))
        act(g, 1, Action.RAISE, 300)
        act(g, 2, Action.CALL)
        act(g, 0, Action.CALL)
        advanceStreet(g)
        assertEquals("1-bet bet to 100", nextLabel(g, 100))
        assertEquals(30000, wealth(g))
    }

    @Test
    fun `a short all-in gets an ordinal without reopening the prior bettor`() {
        val g = newGame()
        g.dealer = 5
        g.players[2].stack = 175
        g.players[3].stack = 100
        val chips = wealth(g)
        startHand(g, SeededRandom(2))
        while (g.phase == Phase.PLAYING) act(g, g.actor, Action.CALL)
        advanceStreet(g)
        act(g, 1, Action.RAISE, 100)
        assertEquals("2-bet short all-in to 125", nextLabel(g, 125))
        act(g, 2, Action.RAISE, 125)
        assertEquals("2-bet short all-in to 125", g.players[2].action)
        assertEquals(100, g.minRaise)
        act(g, 3, Action.CALL)
        assertEquals("All-In 50", g.players[3].action)
        assertEquals(3, nextBetLevel(g))
        act(g, 4, Action.CALL)
        act(g, 5, Action.CALL)
        act(g, 0, Action.CALL)
        assertEquals(1, g.actor)
        assertFalse(legalActions(g).raiseReopened)
        assertFalse(legalActions(g).canRaise)
        val index = g.history.indexOfFirst { it.betLabel?.contains("short all-in") == true }
        assertEquals("2-bet short all-in to 125", historyActionLabel(g.history, index))
        assertEquals(chips, wealth(g))
    }

    @Test
    fun `historical ordinals count the whole street and ignore other streets and folds`() {
        val history = mutableListOf(HistoryEntry(0, 0, Action.RAISE, 150))
        for (i in 1..6) {
            history.add(HistoryEntry(1, 0, Action.RAISE, 100 * i))
            history.add(HistoryEntry(1, 0, Action.CALL, 100))
            history.add(HistoryEntry(1, 0, Action.FOLD, 0))
        }
        val tail = history.indices.map { historyActionLabel(history, it) }.takeLast(6)
        assertEquals(
            listOf("5-bet raise to 500", "Call 100", "Fold", "6-bet raise to 600", "Call 100", "Fold"),
            tail,
        )
        assertEquals("2-bet open to 150", historyActionLabel(history, 0))
        assertEquals("1-bet bet to 100", historyActionLabel(history, 1))
        assertEquals(1, nextBetLevel(2, history))
    }

    @Test
    fun `an empty stored bet label is treated as absent like the reference`() {
        // The reference tests `if (a.betLabel)`, so an empty label falls back to the derived caption.
        val history = listOf(HistoryEntry(0, 3, Action.RAISE, 150, betLabel = ""))
        assertEquals("2-bet open to 150", historyActionLabel(history, 0))
    }

    @Test
    fun `a replay clears the raise sequence and starts again at the 2-bet`() {
        val g = newGame()
        g.dealer = 2
        startHand(g, SeededRandom(3))
        act(g, 0, Action.RAISE, 150)
        while (g.phase == Phase.PLAYING) act(g, g.actor, Action.FOLD)
        restartHand(g)
        assertTrue(g.history.isEmpty())
        assertEquals("2-bet open to 150", nextLabel(g, 150))
        assertEquals(30000, wealth(g))
    }

    @Test
    fun `call labels distinguish an all-in call`() {
        val legal = LegalActions(enabled = true, toCall = 400, callAmount = 300)
        assertEquals("All-In Call 300", actionLabel(LabelStep(street = 1, legal = legal, stack = 300, action = Action.CALL)))
        assertEquals("Call 300", actionLabel(LabelStep(street = 1, legal = legal, stack = 900, action = Action.CALL)))
        assertEquals("Check", actionLabel(LabelStep(street = 1, action = Action.CHECK)))
        assertEquals("Fold", actionLabel(LabelStep(street = 1, action = Action.FOLD)))
    }
}
