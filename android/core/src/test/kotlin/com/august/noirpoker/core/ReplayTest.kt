package com.august.noirpoker.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ReplayTest {
    /** State minus the activity log and replay counter. */
    private fun withoutRetry(g: Game): List<Any?> {
        val copy = g.deepCopy()
        copy.logs = mutableListOf()
        copy.replayAttempt = 0
        return copy.stateFields()
    }

    /** Additionally ignores the practice runout, which is display-only. */
    private fun withoutDisplay(g: Game): List<Any?> {
        val copy = g.deepCopy()
        copy.logs = mutableListOf()
        copy.replayAttempt = 0
        copy.practiceBoard = null
        return copy.stateFields()
    }

    @Test
    fun `replay is rejected before the hand ends without changing state`() {
        val g = newGame()
        assertFalse(canRestartHand(g))
        assertRejected(g) { restartHand(g) }
        startHand(g, SeededRandom(1))
        assertRejected(g) { restartHand(g) }
        while (g.phase == Phase.PLAYING) act(g, g.actor, Action.CALL)
        assertEquals(Phase.BETWEEN, g.phase)
        val error = assertRejected(g) { restartHand(g) }
        assertEquals("You can replay a hand after it ends; the original deal is required.", error.message)
    }

    @Test
    fun `an all-in fold-win replays the same deal, button, stacks and pre-hand statistics`() {
        var found: Game? = null
        var seed = 1L
        while (found == null && seed < 5000) {
            val g = newGame()
            g.dealer = 2
            g.stats = GameStats(hands = 9, wins = 4, buyin = 10000)
            g.players[0].stack = 14000
            startHand(g, SeededRandom(seed))
            if (g.players[0].hole.all { it.rank == 12 }) found = g
            seed++
        }
        val g = found!!
        val baseline = withoutRetry(g)
        assertEquals(0, g.actor)
        act(g, 0, Action.RAISE, legalActions(g).maxRaiseTo)
        while (g.phase == Phase.PLAYING) act(g, g.actor, Action.FOLD)
        assertEquals(Phase.DONE, g.phase)
        assertFalse(g.showdown)
        assertEquals(10, g.stats.hands)
        assertTrue(g.refunds.isNotEmpty())
        assertTrue(g.players[0].stack > 14000)
        restartHand(g)
        assertEquals(baseline, withoutRetry(g))
        assertEquals(1, g.replayAttempt)
        assertEquals(0, g.players[0].total)
        assertEquals(75, potSize(g))
        assertEquals(GameStats(9, 4, 10000), g.stats)
        assertEquals(14000, g.players[0].stack)
        assertFalse(g.revealed)
        assertTrue(g.decisions.isEmpty() && g.history.isEmpty() && g.payouts.isEmpty() && g.winners.isEmpty())
        assertEquals("Hand 1 · Replay #1 · previous settlement reversed", g.logs[0].text)
        act(g, 0, Action.RAISE, 150)
        assertEquals(150, g.decisions.single().amount)
        assertFalse(g.players[0].allin)
    }

    @Test
    fun `every seat count and button rotation replays to its baseline`() {
        for (n in 5..9) for (d in 0 until n) {
            val g = newGame(n)
            g.dealer = (d + n - 1) % n
            for (p in g.players) p.stack = 1000 + p.id * 123
            g.stats = GameStats(7, 3, 1000)
            startHand(g, SeededRandom(n * 31L + d))
            val baseline = withoutRetry(g)
            val chips = totalStacks(g) + potSize(g)
            finish(g, Action.FOLD)
            assertTrue(canRestartHand(g))
            restartHand(g)
            assertEquals(baseline, withoutRetry(g))
            assertEquals(d, g.dealer)
            assertEquals(1, g.hand)
            assertEquals(chips, totalStacks(g) + potSize(g))
            assertEquals(GameStats(7, 3, 1000), g.stats)
        }
    }

    @Test
    fun `a replay deals the same runout after different choices`() {
        val g = newGame()
        startHand(g, SeededRandom(77))
        val deck = g.deck.toList()
        finish(g, Action.CALL)
        val board = g.board.toList()
        val firstDecision = g.decisions.first()
        restartHand(g)
        assertEquals(deck, g.deck)
        act(g, g.actor, Action.RAISE, 100)
        finish(g, Action.CALL)
        assertEquals(board, g.board)
        assertEquals(1, g.stats.hands)
        if (g.decisions.first().history.isNotEmpty()) {
            assertEquals(Action.RAISE, g.decisions.first().history[0].action)
            assertEquals(Action.CALL, firstDecision.history[0].action)
            assertEquals(100, g.decisions.first().currentBet)
            assertEquals(50, firstDecision.currentBet)
        }
    }

    @Test
    fun `nine unequal all-ins retract eight contested pots and one refund`() {
        val g = newGame(9)
        for (p in g.players) p.stack = (p.id + 1) * 100
        startHand(g, SeededRandom(9))
        val baseline = withoutRetry(g)
        while (g.phase != Phase.DONE) {
            if (g.phase == Phase.BETWEEN) {
                advanceStreet(g)
                continue
            }
            val legal = legalActions(g)
            if (legal.canRaise) act(g, g.actor, Action.RAISE, legal.maxRaiseTo) else act(g, g.actor, Action.CALL)
        }
        assertEquals(8, g.pots.size)
        assertEquals(1, g.refunds.size)
        assertEquals(4500, totalStacks(g))
        restartHand(g)
        assertEquals(baseline, withoutRetry(g))
        assertEquals(4500, totalStacks(g) + potSize(g))
    }

    @Test
    fun `a rebuy and short blinds are restored once with the actual blind amounts`() {
        val g = newGame()
        g.players[0].stack = 0
        g.players[1].stack = 20
        g.players[2].stack = 35
        startHand(g, SeededRandom(10))
        assertEquals(10000, g.stats.buyin)
        assertEquals(20, g.players[1].bet)
        assertEquals(35, g.players[2].bet)
        assertEquals(50, g.currentBet)
        val baseline = withoutRetry(g)
        finish(g, Action.CALL)
        restartHand(g)
        assertEquals(baseline, withoutRetry(g))
        assertEquals(10000, g.stats.buyin)
        assertTrue(g.players[1].allin)
        assertEquals(55, potSize(g))
    }

    @Test
    fun `repeated replays keep the baseline immutable and count only the latest attempt`() {
        val g = newGame()
        startHand(g, SeededRandom(12))
        val baseline = withoutRetry(g)
        for (attempt in 1..20) {
            finish(g, if (attempt % 2 == 0) Action.CALL else Action.FOLD)
            assertEquals(1, g.stats.hands)
            restartHand(g)
            assertEquals(attempt, g.replayAttempt)
            assertEquals(baseline, withoutRetry(g))
            if (attempt == 1) {
                // Mutating the live game must not leak into the private baseline.
                g.players[0].hole[0] = Card(2, 0)
                g.deck[0] = Card(3, 1)
                g.players[1].botMood.pressureFolds[4] = 9
            }
        }
        g.difficulty = Difficulty.HARD
        finish(g)
        restartHand(g)
        assertEquals(Difficulty.HARD, g.difficulty)
        assertEquals(21, g.replayAttempt)
        assertEquals(0, g.stats.hands)
        finish(g)
        assertEquals(1, g.stats.hands)
    }

    @Test
    fun `decision snapshots and bot records are copies isolated from the live table`() {
        val g = newGame()
        g.dealer = 2 // The hero is under the gun and acts first.
        startHand(g, SeededRandom(21))
        act(g, 0, Action.CALL)
        val snapshot = g.decisions.single()
        val hole = snapshot.hole.toList()
        while (g.phase == Phase.PLAYING && g.actor != 0) playBotTurn(g, SeededRandom(g.history.size + 5))
        val record = g.botDecisions.first()
        val botHole = record.trace.view!!.hole.toList()
        val botHistory = record.trace.view!!.history.toList()
        // Later live mutations must not reach the stored evidence.
        g.players[0].hole[0] = Card(2, 0)
        g.players[record.id].hole.clear()
        g.history.clear()
        assertEquals(hole, snapshot.hole)
        assertTrue(snapshot.history.isEmpty())
        assertEquals(botHole, record.trace.view!!.hole)
        assertEquals(botHistory, record.trace.view!!.history)
        // The hero snapshot holds only the hero's own cards; no rival holes or deck.
        assertEquals(2, snapshot.hole.size)
        assertTrue(snapshot.board.isEmpty())
    }

    @Test
    fun `the next hand replaces the replay baseline and resets the counter`() {
        val g = newGame()
        val random = SeededRandom(13)
        startHand(g, random)
        finish(g, Action.FOLD)
        restartHand(g)
        finish(g, Action.FOLD)
        startHand(g, random)
        assertEquals(2, g.hand)
        assertEquals(1, g.dealer)
        assertEquals(0, g.replayAttempt)
        val second = withoutRetry(g)
        finish(g, Action.FOLD)
        restartHand(g)
        assertEquals(second, withoutRetry(g))
        assertEquals(2, g.hand)
        assertEquals(1, g.stats.hands)
    }

    @Test
    fun `replay restores bot profiles, moods and observed statistics exactly once`() {
        val g = newGame()
        applyBotSettings(g, BotSettings(EmotionMode.LIVELY, mapOf(1 to "tan", 2 to "st")))
        g.players[1].botMood.apply {
            kind = MoodKind.FRUSTRATED
            remaining = 3
            cooldown = 4
            reason = "test"
        }
        startHand(g, SeededRandom(14))
        val baseline = g.players.map { Triple(it.botProfile, it.botMood.deepCopy(), it.botStats.copy()) }
        for (attempt in 1..4) {
            finishWithBots(g, Lcg(attempt + 5L))
            applyBotSettings(g, BotSettings(EmotionMode.OFF, mapOf(1 to "peter")))
            restartHand(g)
            assertEquals(EmotionMode.LIVELY, g.emotionMode)
            assertEquals(baseline, g.players.map { Triple(it.botProfile, it.botMood, it.botStats) })
            assertEquals(0, g.stats.hands)
        }
        val error = assertFailsWith<PokerException> { applyBotSettings(g, emptyMap<String, Any>()) }
        assertEquals("Opponent settings take effect at the start of the next hand.", error.message)
    }

    @Test
    fun `a practice runout matches the real river and leaves settlement untouched`() {
        for (street in 0..3) {
            val g = newGame(9)
            g.dealer = 5
            startHand(g, SeededRandom(40L + street))
            val river = g.deepCopy()
            finish(river, Action.CALL)
            while (g.street < street) {
                if (g.phase == Phase.BETWEEN) advanceStreet(g) else act(g, g.actor, Action.CALL)
            }
            if (g.phase == Phase.BETWEEN) advanceStreet(g)
            if (street > 0) act(g, g.actor, Action.RAISE, 100)
            while (g.phase == Phase.PLAYING) act(g, g.actor, Action.FOLD)
            assertEquals(Phase.DONE, g.phase)
            assertFalse(g.showdown)
            val settled = withoutDisplay(g)
            val chips = totalStacks(g)
            completeBoardForPractice(g)
            val practice = g.practiceBoard ?: g.board
            assertEquals(river.board, practice)
            assertEquals(5, practice.map { it.key }.toSet().size)
            assertEquals(settled, withoutDisplay(g))
            assertEquals(chips, totalStacks(g))
            if (street < 3) {
                assertEquals(
                    "Practice runout · all five community cards shown; the fold-win result is unchanged",
                    g.logs[0].text,
                )
            } else {
                assertEquals(null, g.practiceBoard)
            }
            val once = g.deepCopy()
            completeBoardForPractice(g)
            assertTrue(g.sameState(once))
            assertFailsWith<PokerException> { advanceStreet(g) }
            restartHand(g)
            assertNull(g.practiceBoard)
            finish(g, Action.CALL)
            assertEquals(river.board, g.board)
            startHand(g, SeededRandom(1))
            assertNull(g.practiceBoard)
        }
    }

    @Test
    fun `a practice runout cannot expose a live deck and is a no-op after a showdown`() {
        val g = newGame()
        assertRejected(g) { completeBoardForPractice(g) }
        startHand(g, SeededRandom(15))
        assertRejected(g) { completeBoardForPractice(g) }
        while (g.phase == Phase.PLAYING) act(g, g.actor, Action.CALL)
        assertRejected(g) { completeBoardForPractice(g) }
        finish(g, Action.CALL)
        assertTrue(g.showdown)
        val done = g.deepCopy()
        completeBoardForPractice(g)
        assertTrue(g.sameState(done))
        assertNotEquals(0, g.board.size)
    }
}
