package com.august.noirpoker.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class BotTimingTest {
    /** The reference timing sample: a cheap button call, heads-up. */
    private fun sample(
        action: Action = Action.CALL,
        amount: Int? = null,
        trace: (BotTrace) -> BotTrace = { it },
        view: (BotView) -> BotView = { it },
    ): BotDecision {
        val v = BotView(
            id = 1, hole = cards("Ah Kd"), street = 0, position = "BTN", rivals = 1, stack = 5000, bet = 0,
            pot = 100, currentBet = 50, contestable = 150,
            opponents = listOf(BotOpponent(2, 5000, 50, false)),
            legal = LegalActions(enabled = true, toCall = 50, callAmount = 50),
        )
        val t = BotTrace(
            equity = 0.6, odds = 0.1, callTolerance = 0.0, percentile = 0.05, range = 0.45,
            axes = listOf(50.0, 50.0, 40.0, 50.0, 20.0), mode = EmotionMode.OFF, reason = "price-continue",
            cheapEntry = false, admitted = true, view = view(v),
        )
        return BotDecision(action, amount, trace(t))
    }

    private fun half(d: BotDecision) = botThinkingTime(d, RandomSource { 0.5 })

    @Test
    fun `timing matches the reference samples`() {
        val base = half(sample())
        assertEquals(2154, base.durationMs)
        assertEquals(Acting.NEUTRAL, base.acting)
        assertEquals(
            ThinkingFactors(0.0, 0.0, 0.0, 0.0, 0.006999999999999999, 0.0, 4950, 33.0),
            base.factors,
        )
        val deliberate = botThinkingTime(sample(), RandomSource { 0.1 })
        assertEquals(1992, deliberate.durationMs)
        assertEquals(Acting.DELIBERATE, deliberate.acting)
        val seeded = botThinkingTime(sample(), Lcg(2341))
        assertEquals(2271, seeded.durationMs)
        assertEquals(Acting.NEUTRAL, seeded.acting)
    }

    @Test
    fun `timing responds to closeness, draws, texture, action line, position and commitment`() {
        val base = half(sample()).durationMs
        assertTrue(half(sample(trace = { it.copy(equity = 0.12) })).durationMs > base)
        val draw = sample(view = {
            it.copy(features = BoardFeatures(wet = true, draw = true, overpair = true), board = cards("8s 9s Th"))
        })
        assertTrue(half(draw).durationMs > base)
        val line = sample(view = {
            it.copy(
                street = 1,
                history = listOf(
                    HistoryEntry(0, 2, Action.RAISE),
                    HistoryEntry(1, 2, Action.CHECK),
                    HistoryEntry(1, 2, Action.RAISE),
                ),
            )
        })
        assertTrue(half(line).factors.route > 0.6)
        assertTrue(half(sample(view = { it.copy(position = "SB", rivals = 5) })).durationMs > base)
        val pressure = sample(view = { it.copy(legal = it.legal.copy(toCall = 4000, callAmount = 4000)) })
        assertTrue(half(pressure).factors.commitment > half(sample()).factors.commitment)
    }

    @Test
    fun `a re-raise after the actor's own raise adds route and position follows action order`() {
        val single = listOf(HistoryEntry(1, 2, Action.RAISE))
        val without = half(sample(view = { it.copy(street = 1, history = single) }))
        val withOwn = sample(view = { it.copy(street = 1, history = listOf(HistoryEntry(1, 1, Action.RAISE)) + single) })
        assertTrue(half(withOwn).factors.route > without.factors.route)
        val inPosition = half(sample(view = { it.copy(street = 1, history = single, inPosition = true) }))
        val outOfPosition = half(sample(view = { it.copy(street = 1, history = single, inPosition = false) }))
        assertTrue(outOfPosition.durationMs > inPosition.durationMs)
    }

    @Test
    fun `a short all-in does not collapse a deep opponent's effective stack`() {
        val d = sample(view = {
            it.copy(
                history = listOf(HistoryEntry(0, 2, Action.RAISE)),
                opponents = listOf(BotOpponent(2, 0, 50, true), BotOpponent(3, 3000, 50, false)),
            )
        })
        assertEquals(3000, half(d).factors.effectiveStack)
    }

    @Test
    fun `pacing is bounded and varied with overlapping value, bluff, trap and fold pauses`() {
        val ranges = mutableListOf<Pair<Int, Int>>()
        for (reason in listOf("value-raise", "pure-bluff", "trap", "outside-range")) {
            val action = when (reason) {
                "trap" -> Action.CHECK
                "outside-range" -> Action.FOLD
                else -> Action.RAISE
            }
            val times = mutableListOf<Int>()
            val acting = mutableSetOf<Acting>()
            for (seed in 1..150) {
                val result = botThinkingTime(sample(action, 150, trace = { it.copy(reason = reason) }), Lcg(seed * 2341L))
                assertTrue(result.durationMs in BotThinkLimits.MINIMUM..BotThinkLimits.MAXIMUM)
                times.add(result.durationMs)
                acting.add(result.acting)
            }
            assertTrue(times.toSet().size > 100)
            assertEquals(Acting.entries.toSet(), acting)
            ranges.add(times.min() to times.max())
        }
        assertTrue(ranges.maxOf { it.first } < ranges.minOf { it.second })
        val cautious = { mode: EmotionMode -> sample(trace = { it.copy(mode = mode, mood = TraceMood(MoodKind.CAUTIOUS)) }) }
        assertTrue(half(cautious(EmotionMode.LIVELY)).durationMs > half(sample()).durationMs)
        assertEquals(half(sample()), half(cautious(EmotionMode.OFF)))
    }

    @Test
    fun `planning does not mutate the game and execution reuses the selected action`() {
        val g = newGame()
        startHand(g, SeededRandom(42))
        val before = g.deepCopy()
        val expected = botDecision(g, Lcg(42))
        val plan = planBotTurn(g, Lcg(42), timingRandom = Lcg(55))
        assertTrue(g.sameState(before))
        val result = executeBotTurn(g, plan, waitedMs = plan.delayMs.toLong())
        assertEquals(expected.action, result.action)
        assertEquals(expected.amount, result.amount)
        assertEquals(1, g.botDecisions.size)
        assertEquals(before.history.size + 1, g.history.size)
        val thinking = g.botDecisions[0].trace.thinking!!
        assertEquals(plan.delayMs, thinking.durationMs)
        assertEquals(plan.delayMs.toLong(), thinking.waitedMs)
        assertFalse(thinking.expedited)
        assertEquals(1, g.botDecisions[0].sequence)
        assertEquals(
            "This bot action plan is stale.",
            assertFailsWith<PokerException> { executeBotTurn(g, plan) }.message,
        )
    }

    @Test
    fun `different timing randomness leaves the strategy action unchanged`() {
        val first = newGame()
        startHand(first, SeededRandom(44))
        val second = first.deepCopy()
        val p1 = planBotTurn(first, Lcg(44), timingRandom = RandomSource { 0.1 })
        val p2 = planBotTurn(second, Lcg(44), timingRandom = RandomSource { 0.8 })
        assertNotEquals(p1.delayMs, p2.delayMs)
        assertEquals(executeBotTurn(first, p1), executeBotTurn(second, p2))
    }

    @Test
    fun `planning cannot read rival holes, the future deck or final winners`() {
        val g = newGame(9)
        startHand(g, SeededRandom(76))
        val expected = planBotTurn(g, Lcg(76), timingRandom = Lcg(77))
        for (p in g.players) if (p.id != g.actor) p.hole = cards("2c 3c")
        g.deck = mutableListOf()
        g.winners = emptyList()
        g.result = "hidden"
        assertEquals(expected.delayMs, planBotTurn(g, Lcg(76), timingRandom = Lcg(77)).delayMs)
    }

    @Test
    fun `plans go stale after another action, in another game, on a difficulty change or a replay`() {
        val g = newGame()
        startHand(g, SeededRandom(90))
        val plan = planBotTurn(g, Lcg(90))
        assertTrue(isBotTurnCurrent(g, plan))
        assertFalse(isBotTurnCurrent(g.deepCopy(), plan))
        g.difficulty = Difficulty.HARD
        assertFalse(isBotTurnCurrent(g, plan))
        g.difficulty = Difficulty.NORMAL
        assertTrue(isBotTurnCurrent(g, plan))
        act(g, g.actor, Action.CALL)
        assertFalse(isBotTurnCurrent(g, plan))
        while (g.phase == Phase.PLAYING) act(g, g.actor, Action.FOLD)
        restartHand(g)
        assertFalse(isBotTurnCurrent(g, plan))
        assertFailsWith<PokerException> { executeBotTurn(g, plan) }
        assertEquals(0, g.botDecisions.size)
    }

    @Test
    fun `the hero's turn cannot use the bot executor`() {
        val g = newGame()
        g.dealer = 2
        startHand(g, SeededRandom(91))
        assertEquals(0, g.actor)
        assertEquals(
            "The hero's turn can't use the bot executor.",
            assertFailsWith<PokerException> { planBotTurn(g, Lcg(1)) }.message,
        )
    }

    @Test
    fun `instant execution records expedited thinking without a wait`() {
        val g = newGame()
        startHand(g, SeededRandom(88))
        playBotTurn(g, Lcg(88))
        assertEquals(1, g.botDecisions.size)
        val thinking = g.botDecisions[0].trace.thinking!!
        assertTrue(thinking.expedited)
        assertEquals(0L, thinking.waitedMs)
    }
}
