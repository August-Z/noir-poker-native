package com.august.noirpoker.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RulesTest {
    @Test
    fun `tables seat six by default and reject unsupported sizes`() {
        assertEquals(6, newGame().players.size)
        assertEquals(listOf("You", "Mia", "Alex", "River", "Kai", "Luna"), newGame().players.map { it.name })
        for (bad in listOf(4, 10, 0, -1)) assertFailsWith<PokerException> { newGame(bad) }
    }

    @Test
    fun `six-seat rotations deal, post blinds and run all four betting rounds in order`() {
        val roles = listOf("BTN", "SB", "BB", "UTG", "HJ", "CO")
        for (d in 0 until 6) {
            val g = newGame()
            g.dealer = if (d == 0) 5 else d - 1
            startHand(g, UNSHUFFLED)
            assertEquals(List(6) { roles[(it - d + 6) % 6] }, g.players.map { seatPosition(g, it.id) })
            assertEquals(25, g.players[(d + 1) % 6].bet)
            assertEquals(50, g.players[(d + 2) % 6].bet)
            val top = deckOfCards().reversed()
            for (i in 1..6) assertEquals(listOf(top[i - 1], top[i + 5]), g.players[(d + i) % 6].hole)
            assertEquals(40, g.deck.size)
            for (k in 0 until 6) {
                assertEquals((d + 3 + k) % 6, g.actor)
                act(g, g.actor, Action.CALL)
            }
            assertEquals(Phase.BETWEEN, g.phase)
            for ((street, sizes) in listOf(3 to 36, 4 to 34, 5 to 32)) {
                advanceStreet(g)
                assertEquals(street, g.board.size)
                assertEquals(sizes, g.deck.size)
                for (k in 0 until 6) {
                    assertEquals((d + 1 + k) % 6, g.actor)
                    assertTrue(legalActions(g).canCheck)
                    act(g, g.actor, Action.CHECK)
                }
            }
            assertEquals(listOf("2-14", "2-13", "2-12", "2-10", "2-8"), g.board.map { it.key })
            val seen = g.players.flatMap { it.hole } + g.board + g.deck
            assertEquals(49, seen.map { it.key }.toSet().size)
            advanceStreet(g)
            assertEquals(Phase.DONE, g.phase)
            assertEquals(30000, totalStacks(g))
        }
    }

    @Test
    fun `positions, blinds and action order hold for every seat count and button`() {
        for (n in 5..9) {
            for (d in 0 until n) {
                val g = newGame(n)
                g.dealer = (d + n - 1) % n
                startHand(g, SeededRandom(n * 100L + d))
                assertEquals(d, g.dealer)
                assertEquals(POSITION_ROLES.getValue(n), List(n) { seatPosition(g, (d + it) % n) })
                assertEquals("SB", seatPosition(g, (d + 1) % n))
                assertEquals("BB", seatPosition(g, (d + 2) % n))
                assertEquals("CO", seatPosition(g, (d + n - 1) % n))
                assertEquals(25, g.players[(d + 1) % n].bet)
                assertEquals(50, g.players[(d + 2) % n].bet)
                assertEquals(2 * n, g.players.flatMap { it.hole }.map { it.key }.toSet().size)
                assertEquals(52 - 2 * n, g.deck.size)
                for (i in 0 until n) {
                    assertEquals((d + 3 + i) % n, g.actor)
                    act(g, g.actor, Action.CALL)
                }
                assertFalse(g.revealed)
                for (street in 1..3) {
                    advanceStreet(g)
                    for (i in 0 until n) {
                        assertEquals((d + 1 + i) % n, g.actor)
                        assertFalse(g.revealed)
                        assertTrue(legalActions(g).canCheck)
                        act(g, g.actor, Action.CHECK)
                    }
                    assertEquals(street == 3, g.revealed)
                    assertEquals(Phase.BETWEEN, g.phase)
                }
                advanceStreet(g)
                assertEquals(Phase.DONE, g.phase)
                assertEquals(n, g.payouts.size)
                assertEquals(n * STARTING_STACK, totalStacks(g))
                assertEquals(44 - 2 * n, g.deck.size)
            }
        }
    }

    @Test
    fun `the button advances one seat each hand over a full orbit`() {
        val g = newGame()
        val random = SeededRandom(3)
        for (expected in listOf(0, 1, 2, 3, 4, 5, 0)) {
            startHand(g, random)
            assertEquals(expected, g.dealer)
            finish(g, Action.FOLD)
            assertEquals(Phase.DONE, g.phase)
        }
    }

    @Test
    fun `the big blind keeps the option after five limps`() {
        val g = newGame()
        startHand(g, SeededRandom(1))
        repeat(5) { act(g, g.actor, Action.CALL) }
        assertEquals(2, g.actor)
        val legal = legalActions(g)
        assertTrue(legal.canCheck && legal.canRaise)
        assertEquals(100, legal.minRaiseTo)
        act(g, 2, Action.RAISE, 100)
        val order = mutableListOf<Int>()
        while (g.phase == Phase.PLAYING) {
            order.add(g.actor)
            act(g, g.actor, Action.CALL)
        }
        assertEquals(listOf(3, 4, 5, 0, 1), order)
    }

    @Test
    fun `postflop action skips a folded small blind and an all-in big blind`() {
        val g = newGame()
        g.players[2].stack = 50
        startHand(g, SeededRandom(2))
        assertTrue(g.players[2].allin)
        for (id in listOf(3, 4, 5, 0)) act(g, id, Action.CALL)
        act(g, 1, Action.FOLD)
        assertEquals(Phase.BETWEEN, g.phase)
        advanceStreet(g)
        val order = mutableListOf<Int>()
        while (g.phase == Phase.PLAYING) {
            order.add(g.actor)
            act(g, g.actor, Action.CHECK)
        }
        assertEquals(listOf(3, 4, 5, 0), order)
    }

    @Test
    fun `two survivors keep their six-handed positions`() {
        val g = newGame()
        startHand(g, SeededRandom(4))
        for (id in listOf(3, 4, 5)) act(g, id, Action.FOLD)
        act(g, 0, Action.CALL)
        act(g, 1, Action.CALL)
        act(g, 2, Action.FOLD)
        advanceStreet(g)
        assertEquals(1, g.actor)
        assertEquals("BTN", seatPosition(g, 0))
        assertEquals("SB", seatPosition(g, 1))
    }

    @Test
    fun `short blinds post their whole stacks and keep the full big blind bring-in`() {
        val g = newGame()
        g.players[1].stack = 10
        g.players[2].stack = 20
        startHand(g, SeededRandom(5))
        assertEquals(10, g.players[1].bet)
        assertEquals("SB 10", g.players[1].action)
        assertTrue(g.players[1].allin)
        assertEquals(20, g.players[2].bet)
        assertTrue(g.players[2].allin)
        assertEquals(50, legalActions(g).callAmount)
        assertEquals(100, legalActions(g).minRaiseTo)
    }

    @Test
    fun `an ordinary check-raise stays legal after a full opening bet`() {
        val g = postflop()
        act(g, 0, Action.CHECK)
        act(g, 1, Action.RAISE, 100)
        for (id in 2..5) act(g, id, Action.CALL)
        assertEquals(0, g.actor)
        assertTrue(legalActions(g).canRaise)
        assertEquals(200, legalActions(g).minRaiseTo)
    }

    @Test
    fun `a checker facing only a sub-minimum all-in cannot raise`() {
        val g = postflop(listOf(1000, 20, 1000, 1000, 1000, 1000))
        act(g, 0, Action.CHECK)
        act(g, 1, Action.RAISE, 20)
        assertEquals(70, legalActions(g).fullRaiseTo)
        for (id in 2..5) act(g, id, Action.CALL)
        assertEquals(0, g.actor)
        assertFalse(legalActions(g).canRaise)
        assertEquals(20, legalActions(g).callAmount)
        assertRejected(g) { act(g, 0, Action.RAISE, 70) }
        act(g, 0, Action.CALL)
        assertEquals(Phase.BETWEEN, g.phase)
    }

    @Test
    fun `cumulative sub-minimum all-ins reopen the checker at one full blind`() {
        val g = postflop(listOf(1000, 20, 40, 50, 1000, 1000))
        act(g, 0, Action.CHECK)
        act(g, 1, Action.RAISE, 20)
        act(g, 2, Action.RAISE, 40)
        act(g, 3, Action.RAISE, 50)
        act(g, 4, Action.CALL)
        act(g, 5, Action.CALL)
        assertEquals(0, g.actor)
        assertTrue(legalActions(g).canRaise)
        assertEquals(100, legalActions(g).minRaiseTo)
    }

    @Test
    fun `raise sizes follow the increment, not the total`() {
        val g = postflop()
        act(g, 0, Action.RAISE, 125)
        assertEquals(250, legalActions(g).minRaiseTo)
        act(g, 1, Action.RAISE, 250)
        act(g, 2, Action.RAISE, 550)
        assertEquals(850, legalActions(g).minRaiseTo)
        assertRejected(g) { act(g, 3, Action.RAISE, 800) }
    }

    @Test
    fun `a short all-in does not remove the unacted big blind's raise option`() {
        val g = newGame()
        g.players[3].stack = 75
        startHand(g, SeededRandom(6))
        act(g, 3, Action.RAISE, 75)
        for (id in listOf(4, 5, 0, 1)) act(g, id, Action.CALL)
        assertEquals(2, g.actor)
        assertTrue(legalActions(g).canRaise)
        assertEquals(125, legalActions(g).minRaiseTo)
    }

    @Test
    fun `cumulative short raises reopen the original raiser but not an intervening caller`() {
        val g = postflop(listOf(1000, 125, 1000, 200, 1000, 1000))
        act(g, 0, Action.RAISE, 100)
        act(g, 1, Action.RAISE, 125)
        act(g, 2, Action.CALL)
        act(g, 3, Action.RAISE, 200)
        act(g, 4, Action.CALL)
        act(g, 5, Action.FOLD)
        assertEquals(0, g.actor)
        assertTrue(legalActions(g).canRaise)
        assertEquals(300, legalActions(g).minRaiseTo)
        act(g, 0, Action.CALL)
        assertEquals(2, g.actor)
        assertFalse(legalActions(g).canRaise)
        assertEquals(75, legalActions(g).callAmount)
    }

    @Test
    fun `a completed raise is not reopened by a later short all-in`() {
        val g = newGame()
        g.phase = Phase.PLAYING
        g.street = 1
        g.currentBet = 100
        g.minRaise = 100
        g.actor = 1
        g.pending = mutableListOf(1, 2)
        for (p in g.players) {
            if (p.id <= 2) {
                p.bet = 100
                p.total = 100
                p.stack = 1000
            } else {
                p.folded = true
            }
        }
        g.players[1].stack = 50
        g.players[0].actedTo = 100
        act(g, 1, Action.RAISE, 150)
        act(g, 2, Action.CALL)
        assertEquals(0, g.actor)
        assertFalse(legalActions(g).canRaise)
        assertRejected(g) { act(g, 0, Action.RAISE, 250) }
        act(g, 0, Action.CALL)
        assertEquals(Phase.BETWEEN, g.phase)
    }

    @Test
    fun `one player with chips behind cannot bet into a dry side pot`() {
        val g = postflop(listOf(1000, 100, 100, 100, 100, 100))
        act(g, 0, Action.RAISE, 100)
        for (id in 1..5) act(g, id, Action.CALL)
        assertEquals(Phase.BETWEEN, g.phase)
        assertTrue(g.revealed)
        g.deck = deckOfCards()
        advanceStreet(g)
        assertEquals(Phase.BETWEEN, g.phase)
        assertEquals(-1, g.actor)
        assertFalse(legalActions(g, 0).enabled)
    }

    @Test
    fun `illegal actions are rejected without changing state`() {
        val g = newGame()
        startHand(g, SeededRandom(8))
        assertEquals("It's not your turn yet.", assertRejected(g) { act(g, 0, Action.CALL) }.message)
        assertEquals("You must call; checking isn't allowed.", assertRejected(g) { act(g, 3, Action.CHECK) }.message)
        assertRejected(g) { act(g, 3, "shove") }
        assertRejected(g) { act(g, 3, Action.RAISE) }
        assertRejected(g) { act(g, 3, Action.RAISE, 99) }
        assertRejected(g) { act(g, 3, Action.RAISE, 5001) }
        act(g, 3, "call")
        assertEquals(4, g.actor)
    }

    @Test
    fun `a fold-win awards the pot without a board`() {
        val g = newGame()
        startHand(g, SeededRandom(9))
        repeat(5) { act(g, g.actor, Action.FOLD) }
        assertEquals(Phase.DONE, g.phase)
        assertEquals(2, g.winners[0].id)
        assertEquals("Alex wins 50 chips", g.result)
        assertEquals(listOf(Refund(2, 25)), g.refunds)
        assertEquals(30000, totalStacks(g))
        assertEquals(0, g.board.size)
    }

    @Test
    fun `the last action survives street resets and settlement`() {
        val g = newGame()
        startHand(g, SeededRandom(10))
        val raiser = g.actor
        act(g, raiser, Action.RAISE, 5000)
        while (g.phase == Phase.PLAYING) act(g, g.actor, Action.CALL)
        assertEquals("2-bet all-in to 5,000", g.players[raiser].lastAction!!.text)
        while (g.phase != Phase.DONE) {
            advanceStreet(g)
            for (p in g.players) {
                assertEquals(0, p.lastAction!!.street)
                assertEquals(5000, p.lastAction!!.bet)
                assertTrue(p.lastAction!!.text.endsWith("5,000"))
            }
        }
        assertEquals(5, g.board.size)
        assertEquals(30000, wealth(g))
    }

    @Test
    fun `a later action replaces the retained action while street resets keep calls and folds`() {
        val g = newGame()
        startHand(g, SeededRandom(11))
        act(g, 3, Action.RAISE, 150)
        act(g, 4, Action.CALL)
        act(g, 5, Action.FOLD)
        while (g.phase == Phase.PLAYING) act(g, g.actor, Action.CALL)
        advanceStreet(g)
        assertEquals("", g.players[4].action)
        assertEquals(LastAction("Call 150", 0, 150), g.players[4].lastAction)
        act(g, 1, Action.RAISE, 100)
        act(g, 2, Action.CALL)
        act(g, 3, Action.FOLD)
        act(g, 4, Action.CALL)
        act(g, 0, Action.CALL)
        advanceStreet(g)
        assertEquals(LastAction("Call 100", 1, 100), g.players[4].lastAction)
        assertEquals(LastAction("Fold", 1, 0), g.players[3].lastAction)
        assertEquals(LastAction("Fold", 0, 0), g.players[5].lastAction)
        act(g, 1, Action.CHECK)
        assertEquals(LastAction("Check", 2, 0), g.players[1].lastAction)
        assertEquals(30000, wealth(g))
    }

    @Test
    fun `an uncalled shove keeps its last action through refund, practice runout and replay`() {
        val g = newGame()
        startHand(g, SeededRandom(12))
        val raiser = g.actor
        act(g, raiser, Action.RAISE, 5000)
        val shove = g.players[raiser].lastAction
        while (g.phase == Phase.PLAYING) act(g, g.actor, Action.FOLD)
        assertTrue(g.refunds.single { it.id == raiser }.amount > 0)
        assertEquals(shove, g.players[raiser].lastAction)
        completeBoardForPractice(g)
        assertEquals(5, g.practiceBoard!!.size)
        assertEquals(0, g.board.size)
        assertEquals(shove, g.players[raiser].lastAction)
        restartHand(g)
        assertNull(g.players[raiser].lastAction)
        assertNull(g.practiceBoard)
        assertEquals(2, g.players.count { it.lastAction != null })
        finish(g, Action.FOLD)
        startHand(g, SeededRandom(13))
        val texts = g.players.mapNotNull { it.lastAction?.text }
        assertEquals(2, texts.size)
        assertTrue(texts.all { it.startsWith("SB ") || it.startsWith("BB ") })
        assertEquals(30000, wealth(g))
    }

    @Test
    fun `activity log lines follow the English copy table`() {
        val g = newGame()
        g.players[0].stack = 0
        startHand(g, UNSHUFFLED)
        val oldestFirst = g.logs.reversed().map { it.text }
        assertEquals(
            listOf("Hand 1 begins · Button: You", "You rebuy 5,000 virtual chips", "Mia: SB 25 · Alex: BB 50"),
            oldestFirst,
        )
        assertEquals(LogType.BLIND, g.logs[0].type)
        act(g, 3, Action.RAISE, 1500)
        assertEquals("River: 2-bet open to 1,500", g.logs[0].text)
        assertEquals("2-bet open to", g.history.last().betLabel)
        for (id in listOf(4, 5, 0, 1)) act(g, id, Action.FOLD)
        act(g, 2, Action.CALL)
        assertEquals("Alex: Call 1,450", g.logs[0].text)
        advanceStreet(g)
        assertEquals("Flop · A♣ K♣ Q♣", g.logs[0].text)
        assertEquals(LogType.STREET, g.logs[0].type)
    }

    @Test
    fun `randomized legal hands conserve chips and always end`() {
        val g = newGame()
        val random = SeededRandom(2024)
        var chips = totalStacks(g)
        repeat(200) {
            startHand(g, random)
            val rebuys = g.logs.count { it.text.endsWith(" 5,000 virtual chips") }
            chips += rebuys * STARTING_STACK
            assertEquals(chips, wealth(g))
            var turns = 0
            while (g.phase != Phase.DONE) {
                assertTrue(++turns < 600)
                if (g.phase == Phase.BETWEEN) {
                    advanceStreet(g)
                    continue
                }
                val legal = legalActions(g)
                val r = random.next()
                when {
                    r < 0.16 -> act(g, g.actor, Action.FOLD)
                    r < 0.43 && legal.canRaise ->
                        act(g, g.actor, Action.RAISE, if (random.next() < 0.25) legal.maxRaiseTo else legal.minRaiseTo)
                    else -> act(g, g.actor, Action.CALL)
                }
                assertTrue(g.players.all { it.stack >= 0 })
                assertEquals(chips, wealth(g))
            }
            assertConserved(g, chips)
        }
    }
}
