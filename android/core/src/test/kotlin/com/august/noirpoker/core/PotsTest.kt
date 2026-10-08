package com.august.noirpoker.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PotsTest {
    @Test
    fun `one main pot and two side pots can have different winners`() {
        val g = potFixture(listOf(100, 300, 500, 500))
        val before = totalStacks(g) + potSize(g)
        val parts = partitionPots(g)
        assertEquals(listOf(400, 600, 400), parts.pots.map { it.amount })
        assertEquals(listOf(listOf(0, 1, 2, 3), listOf(1, 2, 3), listOf(2, 3)), parts.pots.map { it.eligible })
        assertEquals(listOf("Main Pot", "Side Pot 1", "Side Pot 2"), parts.pots.map { it.label })
        settle(g)
        assertEquals(listOf(400, 600, 400, 0, 0, 0), g.payouts)
        assertEquals(listOf(0, 1, 2), g.pots.map { it.awards[0].id })
        assertEquals("Split pots · You win 400 chips · One Pair / Mia wins 600 chips · One Pair / Alex wins 400 chips · One Pair", g.result)
        assertConserved(g, before)
    }

    @Test
    fun `six players make five contested pots plus a refund`() {
        val g = potFixture(listOf(100, 200, 300, 400, 500, 600))
        val before = totalStacks(g) + potSize(g)
        settle(g)
        assertEquals(listOf(600, 500, 400, 300, 200), g.pots.map { it.amount })
        assertEquals(listOf(600, 500, 400, 300, 200, 100), g.payouts)
        assertEquals(listOf(Refund(5, 100)), g.refunds)
        assertTrue(g.winners.none { it.id == 5 })
        assertTrue(g.logs.any { it.text == "Uncalled 100 chips returned to Luna" })
        assertConserved(g, before)
    }

    @Test
    fun `folded chips stay in the pots without creating a spurious pot`() {
        val g = potFixture(listOf(100, 300, 500, 500, 200), folded = listOf(4))
        val before = totalStacks(g) + potSize(g)
        settle(g)
        assertEquals(listOf(500, 700, 400), g.pots.map { it.amount })
        assertTrue(g.pots.none { 4 in it.eligible })
        assertEquals(0, g.payouts[4])
        assertEquals(100, g.pots[1].contributions.single { it.id == 4 }.amount)
        assertConserved(g, before)
    }

    @Test
    fun `folded contributions without an all-in stay in one pot`() {
        val g = potFixture(listOf(25, 50, 100, 100), folded = listOf(0, 1))
        assertEquals(1, partitionPots(g).pots.size)
        val before = totalStacks(g) + potSize(g)
        settle(g)
        assertEquals(275, g.pots.single().amount)
        assertConserved(g, before)
    }

    @Test
    fun `a side pot can split while the other pots have single winners`() {
        val g = potFixture(listOf(100, 300, 500, 500), holes = listOf("As Ah", "Ks Kh", "Qs Qh", "Qc Qd"))
        val before = totalStacks(g) + potSize(g)
        settle(g)
        assertEquals(listOf(400, 600, 200, 200, 0, 0), g.payouts)
        assertEquals(listOf(1, 1, 2), g.pots.map { it.awards.size })
        assertConserved(g, before)
    }

    @Test
    fun `the odd side-pot chip goes to the first tied winner left of the button`() {
        for ((dealer, expected) in listOf(0 to listOf(400, 202, 201, 0, 0, 0), 1 to listOf(400, 201, 202, 0, 0, 0))) {
            val g = potFixture(listOf(100, 301, 301, 101), folded = listOf(3), holes = listOf("As Ah", "Ks Kh", "Kc Kd"))
            g.dealer = dealer
            val before = totalStacks(g) + potSize(g)
            settle(g)
            assertEquals(listOf(400, 403), g.pots.map { it.amount })
            assertEquals(expected, g.payouts)
            assertConserved(g, before)
        }
    }

    @Test
    fun `an uncalled return is separate from winnings and never counts as a win`() {
        val g = potFixture(listOf(800, 100, 300, 500), holes = listOf("Js Jh", "As Ah", "Ks Kh", "Qs Qh"))
        val before = totalStacks(g) + potSize(g)
        settle(g)
        assertEquals(listOf(400, 600, 400), g.pots.map { it.amount })
        assertEquals(listOf(Refund(0, 300)), g.refunds)
        assertEquals(listOf(300, 400, 600, 400, 0, 0), g.payouts)
        assertEquals(0, g.stats.wins)
        assertEquals(1400, g.potAtShowdown)
        assertConserved(g, before)
    }

    @Test
    fun `four legal all-ins form three pots before settlement`() {
        val g = potFixture(emptyList())
        g.phase = Phase.PLAYING
        g.street = 3
        g.currentBet = 0
        g.actor = 0
        g.pending = mutableListOf(0, 1, 2, 3)
        for ((i, stack) in listOf(100, 300, 500, 500, 5000, 5000).withIndex()) {
            val p = g.players[i]
            p.stack = stack
            p.total = 0
            p.bet = 0
            p.actedTo = null
            p.folded = i >= 4
        }
        act(g, 0, Action.RAISE, 100)
        act(g, 1, Action.RAISE, 300)
        act(g, 2, Action.RAISE, 500)
        act(g, 3, Action.CALL)
        assertEquals(Phase.BETWEEN, g.phase)
        assertTrue(g.revealed)
        assertEquals(listOf(400, 600, 400), partitionPots(g).pots.map { it.amount })
        advanceStreet(g)
        assertEquals(listOf(400, 600, 400, 0, 0, 0), g.payouts)
        assertConserved(g, 11400)
    }

    @Test
    fun `a short stack is exposed only once the deep stacks can no longer bet`() {
        val g = potFixture(listOf(0, 0, 0))
        g.phase = Phase.PLAYING
        g.street = 1
        g.board = cards("2c 3d 4h")
        g.deck = cards("5s 6s 7s 8s 9s Ts")
        g.currentBet = 0
        g.actor = 0
        g.dealer = 5
        g.pending = mutableListOf(0, 1, 2)
        for ((i, stack) in listOf(100, 300, 500).withIndex()) {
            g.players[i].stack = stack
            g.players[i].folded = false
        }
        val chips = totalStacks(g)
        act(g, 0, Action.RAISE, 100)
        act(g, 1, Action.CALL)
        act(g, 2, Action.CALL)
        assertFalse(g.revealed)
        advanceStreet(g)
        assertEquals(1, g.actor)
        act(g, 1, Action.RAISE, 200)
        act(g, 2, Action.CALL)
        assertTrue(g.revealed)
        assertEquals(listOf(300, 400), partitionPots(g).pots.map { it.amount })
        assertEquals(200, g.players[2].stack)
        advanceStreet(g)
        assertEquals(Phase.BETWEEN, g.phase)
        advanceStreet(g)
        assertEquals(Phase.DONE, g.phase)
        assertConserved(g, chips)
    }

    @Test
    fun `pot odds exclude side pots beyond the short stack's cap`() {
        val g = potFixture(listOf(0, 100, 100))
        assertEquals(60, contestableAfterCall(g, 0, 20))
        assertEquals(300, contestableAfterCall(g, 0, 100))
    }

    @Test
    fun `several short all-ins can cumulatively reopen raising`() {
        val g = potFixture(listOf(100, 100, 100, 100))
        g.phase = Phase.PLAYING
        g.currentBet = 100
        g.minRaise = 100
        g.actor = 1
        g.pending = mutableListOf(1, 2, 3)
        g.players[0].actedTo = 100
        g.players[1].stack = 40
        g.players[2].stack = 100
        act(g, 1, Action.RAISE, 140)
        act(g, 2, Action.RAISE, 200)
        act(g, 3, Action.CALL)
        assertEquals(0, g.actor)
        assertTrue(legalActions(g).canRaise)
        assertEquals(300, legalActions(g).fullRaiseTo)
    }

    @Test
    fun `folded players do not split one tied pot into several odd-chip awards`() {
        val g = potFixture(listOf(5, 5, 1, 2, 3, 4), folded = listOf(2, 3, 4, 5), holes = listOf("As Ah", "Ac Ad"))
        val before = totalStacks(g) + potSize(g)
        settle(g)
        assertEquals(listOf(20), g.pots.map { it.amount })
        assertEquals(listOf(10, 10, 0, 0, 0, 0), g.payouts)
        assertConserved(g, before)
    }

    @Test
    fun `settlement cannot award chips twice`() {
        val g = potFixture(listOf(100, 300, 500, 500))
        settle(g)
        val error = assertRejected(g) { settle(g) }
        assertEquals("This hand has already been settled.", error.message)
    }

    @Test
    fun `a royal board ties every seat and the odd chip follows the button`() {
        for (n in 5..9) for (d in 0 until n) {
            val g = newGame(n)
            g.dealer = d
            g.phase = Phase.BETWEEN
            g.street = 3
            g.board = cards("Ts Js Qs Ks As")
            val used = g.board.map { it.key }.toSet()
            val spare = deckOfCards().filter { it.key !in used }
            for (p in g.players) {
                p.hole = spare.subList(p.id * 2, p.id * 2 + 2).toMutableList()
                p.total = listOf(100, 100, 101).getOrElse(p.id) { 0 }
                p.stack = STARTING_STACK - p.total
                p.folded = p.id >= 3
            }
            settle(g)
            assertEquals(300, g.pots[0].amount)
            assertEquals(3, g.pots[0].awards.size)
            assertEquals(1, g.refunds.single().amount)
            val first = listOf(0, 1, 2).minBy { (it - d + n - 1) % n }
            assertEquals(first, g.pots[0].awards[0].id)
        }
    }

    @Test
    fun `live pots split only at all-in caps and keep uncalled excess separate`() {
        val g = newGame()
        g.phase = Phase.PLAYING
        for ((i, total) in listOf(100, 300, 500, 500, 0, 0).withIndex()) {
            g.players[i].total = total
            g.players[i].allin = i <= 2
            g.players[i].folded = i >= 4
        }
        val live = currentPots(g)
        assertEquals(listOf(400, 600, 400), live.pots.map { it.amount })
        assertEquals(listOf(listOf(0, 1, 2, 3), listOf(1, 2, 3), listOf(2, 3)), live.pots.map { it.eligible })
        g.players[3].total = 800
        val raised = currentPots(g)
        assertEquals(listOf(Refund(3, 300)), raised.refunds)
        assertEquals(live.pots, raised.pots)
    }

    @Test
    fun `blinds and unfinished raises do not create live side pots`() {
        val g = newGame()
        startHand(g, SeededRandom(21))
        assertEquals(1, currentPots(g).pots.size)
        act(g, 3, Action.RAISE, 125)
        assertEquals(1, currentPots(g).pots.size)
        assertEquals(listOf(Refund(3, 75)), currentPots(g).refunds)
        act(g, 4, Action.CALL)
        val pots = currentPots(g)
        assertEquals(1, pots.pots.size)
        assertEquals(0, pots.refunds.size)
        assertEquals(potSize(g), pots.pots.sumOf { it.amount } + pots.refunds.sumOf { it.amount })
    }
}
