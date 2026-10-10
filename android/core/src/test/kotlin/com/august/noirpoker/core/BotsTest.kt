package com.august.noirpoker.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BotsTest {
    private val raiseLegal = LegalActions(
        enabled = true, toCall = 50, callAmount = 50, canCheck = false, canRaise = true,
        minRaiseTo = 100, fullRaiseTo = 100, maxRaiseTo = 5000,
    )

    /** View V from the reference profile tests: 9♠7♠ in the cutoff facing the big blind. */
    private val viewV = BotView(
        id = 1, hole = cards("9s 7s"), street = 0, position = "CO", count = 6, stack = 5000, bet = 0,
        pot = 75, currentBet = 50, contestable = 125, rivals = 5, equity = 0.35, difficulty = Difficulty.HARD,
        legal = raiseLegal, opponents = null,
    )

    private fun smallOpen(hole: String = "7s 6s", count: Int = 6) = BotView(
        id = 1, hole = cards(hole), street = 0, position = "CO", count = count, stack = 5000, bet = 0,
        pot = 225, currentBet = 150, contestable = 375, rivals = 5, equity = 0.05, difficulty = Difficulty.HARD,
        history = listOf(HistoryEntry(0, 0, Action.RAISE, 150)),
        opponents = listOf(0, 2, 3, 4, 5).map { BotOpponent(it, if (it == 0) 4850 else 5000, if (it == 0) 150 else 0, false) },
        legal = LegalActions(
            enabled = true, toCall = 150, callAmount = 150, canRaise = true,
            minRaiseTo = 250, fullRaiseTo = 250, maxRaiseTo = 5000,
        ),
    )

    private fun decide(view: BotView, profile: String = "balanced", random: RandomSource = RandomSource { 0.9 }) =
        chooseBotAction(view, getBotProfile(profile), freshBotMood(), EmotionMode.OFF, random)

    @Test
    fun `nine profiles carry their reference parameters`() {
        assertEquals(
            listOf("balanced", "tan", "st", "zang", "peter", "abao", "viktor", "jungleman", "dwan"),
            BOT_PROFILES.map { it.id },
        )
        assertEquals(listOf(92, 88, 72, 84, 18), getBotProfile("peter").axes)
        assertEquals(listOf(0.75, 1.25), getBotProfile("peter").sizing)
        assertEquals("balanced", getBotProfile("nope").id)
        assertTrue(BOT_PROFILES.drop(1).all { it.sources.isNotEmpty() })
    }

    @Test
    fun `saved settings reject unknown profiles and malformed modes`() {
        val settings = sanitizeBotSettings(
            mapOf("emotionMode" to "hack", "assignments" to mapOf(1 to "tan", "2" to "nope", 9 to "peter")),
        )
        assertEquals(EmotionMode.SUBTLE, settings.emotionMode)
        assertEquals("tan", settings.assignments[1])
        assertEquals("balanced", settings.assignments[2])
        assertEquals((1..8).toSet(), settings.assignments.keys)
        assertEquals(defaultBotSettings(), sanitizeBotSettings(null))
        assertEquals(defaultBotSettings(), sanitizeBotSettings("garbage"))
        assertEquals(EmotionMode.LIVELY, sanitizeBotSettings(mapOf("emotionMode" to "lively")).emotionMode)
        assertEquals("st", sanitizeBotSettings(mapOf("assignments" to mapOf("3" to "st"))).assignments[3])
    }

    @Test
    fun `saved settings accept an array of assignments indexed by seat like the reference`() {
        // The reference reads `value?.assignments?.[id]`, which indexes an array as well as an object.
        val settings = sanitizeBotSettings(mapOf("assignments" to listOf(null, "tan", "nope", "dwan")))
        assertEquals("tan", settings.assignments[1])
        assertEquals("balanced", settings.assignments[2])
        assertEquals("dwan", settings.assignments[3])
        assertEquals("balanced", settings.assignments[8])
        assertEquals((1..8).toSet(), settings.assignments.keys)
    }

    @Test
    fun `a reassigned profile starts a separate observed sample`() {
        val g = newGame()
        g.players[1].botStats = BotStats(hands = 20, vpip = 10)
        applyBotSettings(g, BotSettings(EmotionMode.SUBTLE, mapOf(1 to "peter")))
        assertEquals("peter", g.players[1].botProfile)
        assertEquals(0, g.players[1].botStats.hands)
    }

    @Test
    fun `loss, win and pressure triggers are bounded, cooled down and can be disabled`() {
        val odd = newGame().players[1]
        assertNull(finishBotHand(odd, -1249, EmotionMode.SUBTLE))
        assertEquals(MoodKind.FRUSTRATED, finishBotHand(odd, -1250, EmotionMode.SUBTLE)!!.kind)
        assertNull(finishBotHand(odd, -5000, EmotionMode.SUBTLE))
        val even = newGame().players[2]
        val cautious = finishBotHand(even, -1250, EmotionMode.LIVELY)!!
        assertEquals(MoodKind.CAUTIOUS, cautious.kind)
        assertEquals("Lost at least 25 BB net in a single hand", cautious.reason)
        val off = newGame().players[1]
        assertNull(finishBotHand(off, -5000, EmotionMode.OFF))
        assertEquals(MoodKind.STEADY, off.botMood.kind)
        val winner = newGame().players[1]
        assertNull(finishBotHand(winner, 500, EmotionMode.SUBTLE))
        assertEquals(MoodKind.CONFIDENT, finishBotHand(winner, 500, EmotionMode.SUBTLE)!!.kind)
        val mood = freshBotMood()
        assertNull(recordPressureFold(mood, 2, EmotionMode.SUBTLE))
        assertNull(recordPressureFold(mood, 3, EmotionMode.SUBTLE))
        assertNull(recordPressureFold(mood, 2, EmotionMode.SUBTLE))
        assertNull(recordPressureFold(mood, 2, EmotionMode.SUBTLE))
        val reactive = recordPressureFold(mood, 2, EmotionMode.SUBTLE)!!
        assertEquals(MoodKind.REACTIVE, reactive.kind)
        assertEquals(0, mood.pressureFolds[2])
        repeat(4) { decayBotMood(mood) }
        assertEquals(MoodKind.STEADY, mood.kind)
        assertEquals(0, mood.cooldown)
    }

    @Test
    fun `emotions shift the policy axes, half as much when subtle`() {
        val tan = BOT_PROFILES[1]
        val frustrated = freshBotMood().apply { kind = MoodKind.FRUSTRATED }
        assertEquals(tan.axes.map { it.toDouble() }, effectiveBotAxes(tan, frustrated, EmotionMode.OFF))
        val subtle = effectiveBotAxes(tan, frustrated, EmotionMode.SUBTLE)
        val lively = effectiveBotAxes(tan, frustrated, EmotionMode.LIVELY)
        assertTrue(subtle[0] > tan.axes[0] && lively[0] > subtle[0] && lively[4] < subtle[4])
        assertEquals(listOf(99.0, 100.0, 92.0, 85.0, 15.0), lively)
        val cautious = freshBotMood().apply { kind = MoodKind.CAUTIOUS }
        assertEquals(listOf(33.0, 59.0, 37.0, 34.0, 80.5), effectiveBotAxes(getBotProfile("st"), cautious, EmotionMode.SUBTLE))
    }

    @Test
    fun `starting percentiles rank AA first and keep exactly seventeen premium classes`() {
        assertEquals(0.0, startingPercentile(cards("As Ah")))
        assertEquals(6.0 / 1326, startingPercentile(cards("Ks Kh")))
        assertEquals(594.0 / 1326, startingPercentile(cards("9s 7s")))
        assertEquals(90.0 / 1326, startingPercentile(cards("As Qh")))
        assertEquals(102.0 / 1326, startingPercentile(cards("As 8s")))
        val classes = mutableSetOf<String>()
        val deck = deckOfCards()
        for (a in 0 until 52) for (b in a + 1 until 52) {
            val hole = listOf(deck[a], deck[b])
            if (startingPercentile(hole) < 0.07) {
                val (hi, lo) = hole.map { it.rank }.sortedDescending()
                classes.add("$hi-$lo-${if (hi == lo) "p" else if (hole[0].suit == hole[1].suit) "s" else "o"}")
            }
        }
        assertEquals(17, classes.size)
    }

    @Test
    fun `board features detect wet boards, draws and overpairs`() {
        val hole = cards("As 5h")
        val board = cards("2s 3c 9d")
        assertEquals(
            BoardFeatures(wet = false, draw = true, overpair = false),
            botBoardFeatures(hole, board, evaluate(hole + board).score),
        )
        val flush = cards("Ks 2s 7s")
        val qq = cards("Qh Qd")
        assertEquals(BoardFeatures(wet = true, draw = false, overpair = false), botBoardFeatures(qq, flush, evaluate(qq + flush).score))
        val dry = cards("2c 7d 9h")
        assertTrue(botBoardFeatures(qq, dry, evaluate(qq + dry).score).overpair)
    }

    @Test
    fun `the reference profile fixtures choose the same actions`() {
        val balanced = decide(viewV, "balanced", Lcg(100))
        assertEquals(Action.CALL, balanced.action)
        assertEquals("affordable-entry", balanced.trace.reason)
        assertEquals(0.6766, balanced.trace.range, 1e-12)
        assertEquals(0.4366, balanced.trace.openingRange, 1e-12)
        assertEquals(-0.009007071377709508, balanced.trace.noise)
        assertEquals(0.34099292862229047, balanced.trace.equity)
        assertEquals(0.4, balanced.trace.odds)
        assertEquals(0.01, balanced.trace.pressure)
        assertEquals(0.4479638009049774, balanced.trace.percentile)
        assertEquals(52, balanced.trace.trials)
        assertTrue(balanced.trace.cheapEntry)
        assertTrue(balanced.trace.checks.isEmpty())

        val st = decide(viewV, "st", Lcg(100))
        assertEquals(Action.CALL, st.action)
        assertEquals(0.60704, st.trace.range, 1e-12)

        val peter = decide(viewV, "peter", Lcg(100))
        assertEquals(Action.RAISE, peter.action)
        assertEquals(150, peter.amount)
        assertEquals("value-raise", peter.trace.reason)
        assertEquals(0.95, peter.trace.range)
        assertEquals(0.644752, peter.trace.openingRange, 1e-12)
        assertEquals(listOf(RollCheck("attack", 0.3489434248767793, 0.8335999999999999, true)), peter.trace.checks)
        assertEquals(BotSizing(0.8951804969692603, 150, 150, 100, 5000, opening = true, executed = true), peter.trace.sizing)

        val abao = decide(viewV, "abao", Lcg(100))
        assertEquals(Action.RAISE, abao.action)
        assertEquals(150, abao.amount)
        assertEquals(0.71138, abao.trace.range, 1e-12)
    }

    @Test
    fun `style differences change entry and value-trap behavior`() {
        fun count(profile: String, view: BotView, action: Action) =
            (0 until 300).count { decide(view, profile, Lcg(it + 100L)).action == action }
        assertTrue(count("peter", viewV, Action.RAISE) > count("st", viewV, Action.RAISE))
        val value = viewV.copy(street = 2, equity = 0.9, rivals = 1, legal = raiseLegal.copy(toCall = 0, callAmount = 0, canCheck = true))
        assertTrue(count("st", value, Action.CHECK) > count("peter", value, Action.CHECK))
    }

    @Test
    fun `deep small opens keep playable calls without turning admissions into 3-bets`() {
        for (count in listOf(6, 9)) for (hole in listOf("7s 6s", "Qs 7s", "2s 2h", "As 5s", "Ks Jh")) {
            val d = decide(smallOpen(hole, count))
            assertEquals(Action.CALL, d.action, hole)
            assertEquals("affordable-open", d.trace.reason)
            assertEquals(true, d.trace.affordableRangePassed)
            assertFalse(d.trace.cheapRangePassed)
            assertFalse(d.trace.value)
            assertTrue(d.trace.checks.none { it.code == "insufficient-equity" })
        }
        val aces = decide(smallOpen("As Ah"), random = RandomSource { 0.1 })
        assertEquals(Action.RAISE, aces.action)
        assertTrue(aces.amount!! >= 250)
    }

    @Test
    fun `the small-open branch stops at size, stack, all-in and re-raise boundaries`() {
        val base = smallOpen()
        val unsafe = listOf(
            base.copy(opponents = null),
            base.copy(opponents = base.opponents!!.filter { it.id != 0 }),
            base.copy(currentBet = 201, legal = base.legal.copy(toCall = 201, callAmount = 201)),
            base.copy(stack = 1000),
            base.copy(opponents = base.opponents!!.map { if (it.id == 0) it.copy(stack = 2249) else it }),
            base.copy(opponents = base.opponents!!.map { if (it.id == 0) it.copy(stack = 0, allin = true) else it }),
            base.copy(history = base.history + HistoryEntry(0, 2, Action.RAISE, 175)),
            base.copy(street = 1, board = cards("2s 4h Jd")),
            base.copy(history = listOf(HistoryEntry(0, 1, Action.RAISE, 150))),
        )
        for (view in unsafe) {
            val d = decide(view)
            assertFalse(d.trace.affordableOpen)
            assertEquals(false, d.trace.affordableRangePassed)
            assertEquals(Action.FOLD, d.action)
        }
        assertTrue(decide(base.copy(currentBet = 200, legal = base.legal.copy(toCall = 200, callAmount = 200))).trace.affordableOpen)
        assertTrue(decide(base.copy(opponents = base.opponents!!.map { if (it.id == 0) it.copy(stack = 2250) else it })).trace.affordableOpen)
    }

    @Test
    fun `a cheap completion is not a cheap all-in with a tiny remaining stack`() {
        val v = viewV.copy(hole = cards("9s 8s"), stack = 625)
        assertTrue(decide(v).trace.cheapRangePassed)
        assertFalse(decide(v.copy(stack = 624)).trace.cheapRangePassed)
        val short = v.copy(stack = 25, legal = raiseLegal.copy(callAmount = 25, canRaise = false))
        assertEquals(false, decide(short).trace.affordableRangePassed)
    }

    @Test
    fun `no profile raises when a short all-in has not reopened the action`() {
        val g = newGame()
        startHand(g, SeededRandom(31))
        val first = g.actor
        act(g, first, Action.RAISE, 100)
        val shover = g.players[g.actor]
        shover.stack = 125 - shover.bet
        act(g, shover.id, Action.RAISE, 125)
        while (g.actor != first) act(g, g.actor, Action.CALL)
        assertFalse(legalActions(g).canRaise)
        for (profile in BOT_PROFILES) {
            g.players[first].botProfile = profile.id
            for (seed in 0L until 10L) assertNotEquals(Action.RAISE, botDecision(g, Lcg(seed)).action)
        }
    }

    @Test
    fun `bot decisions ignore opponent holes, the future deck and final results`() {
        for (profile in BOT_PROFILES) {
            val g = newGame(9)
            startHand(g, SeededRandom(51))
            g.players[g.actor].botProfile = profile.id
            val expected = botDecision(g, Lcg(50))
            for (p in g.players) if (p.id != g.actor) p.hole = cards("2c 2d")
            g.deck = deckOfCards()
            g.winners = listOf(Winner(3, "River", 1, 1, "x"))
            g.result = "rigged"
            assertEquals(expected, botDecision(g, Lcg(50)))
        }
    }

    @Test
    fun `every mixed assignment reaches the executed policy with its parameters`() {
        val lineup = mapOf(1 to "tan", 2 to "st", 3 to "zang", 4 to "peter", 5 to "abao", 6 to "viktor", 7 to "jungleman", 8 to "dwan")
        for (id in 1..8) {
            val g = newGame(9)
            applyBotSettings(g, BotSettings(EmotionMode.OFF, lineup))
            startHand(g, SeededRandom(id.toLong()))
            while (g.actor != id) act(g, g.actor, Action.CALL)
            val decision = playBotTurn(g, Lcg(id.toLong()))
            val record = g.botDecisions.last()
            val profile = getBotProfile(lineup.getValue(id))
            assertEquals(id, record.id)
            assertEquals(decision.action, record.action)
            assertEquals(profile.id, record.trace.profile)
            assertEquals(profile.name, record.trace.profileName)
            assertEquals(profile.axes, record.trace.baseAxes)
            assertEquals(profile.axes.map { it.toDouble() }, record.trace.axes)
            assertEquals(45000, wealth(g))
        }
    }

    @Test
    fun `all profiles and emotion strengths play legal 5 to 9 seat hands and conserve chips`() {
        for (count in 5..9) for (mode in EmotionMode.entries) {
            val g = newGame(count)
            applyBotSettings(g, BotSettings(mode, (1..8).associateWith { BOT_PROFILES[it % 9].id }))
            for (hand in 0 until 4) {
                for (p in g.players) p.stack = 300 + p.id * 175
                val chips = totalStacks(g)
                startHand(g, SeededRandom(count * 1000L + hand))
                finishWithBots(g, Lcg(100L + count + hand))
                assertConserved(g, chips)
            }
        }
    }

    @Test
    fun `an intervening hand without pressure breaks the consecutive-fold trigger`() {
        val g = newGame()
        for (hand in 0 until 5) {
            g.dealer = 2
            startHand(g, SeededRandom(60L + hand))
            assertEquals(0, g.actor)
            if (hand % 2 == 0) act(g, 0, Action.RAISE, 100) else act(g, 0, Action.FOLD)
            while (g.phase == Phase.PLAYING) act(g, g.actor, Action.FOLD)
            assertEquals(MoodKind.STEADY, g.players[1].botMood.kind)
        }
    }

    @Test
    fun `three straight pressure folds to the same raiser trigger a logged reactive mood`() {
        val g = newGame()
        for (hand in 0 until 3) {
            g.dealer = 2
            startHand(g, SeededRandom(70L + hand))
            act(g, 0, Action.RAISE, 100)
            while (g.phase == Phase.PLAYING) act(g, g.actor, Action.FOLD)
        }
        assertEquals(MoodKind.REACTIVE, g.players[1].botMood.kind)
        assertTrue(
            g.logs.any {
                it.text == "Mia simulated mood: Fighting Back · Folded to the same opponent's raise three hands in a row"
            },
        )
    }

    @Test
    fun `an uncalled shove refund is not a loss and blinds alone are not VPIP`() {
        val g = newGame()
        g.dealer = 3
        startHand(g, SeededRandom(80))
        assertEquals(1, g.actor)
        act(g, 1, Action.RAISE, 5000)
        while (g.phase == Phase.PLAYING) act(g, g.actor, Action.FOLD)
        assertTrue(g.refunds.any { it.id == 1 })
        assertEquals(MoodKind.STEADY, g.players[1].botMood.kind)
        val stats = g.players[1].botStats
        assertEquals(listOf(1, 1, 1), listOf(stats.hands, stats.vpip, stats.pfr))
        assertTrue(g.players.drop(2).all { it.botStats.vpip == 0 })
    }

    @Test
    fun `bot decision validates the actor and the equity trial count`() {
        val g = newGame()
        assertFailsWith<PokerException> { botDecision(g, Lcg(1)) }
        startHand(g, SeededRandom(81))
        assertEquals(
            "Equity trial count must be a positive integer.",
            assertFailsWith<PokerException> { botDecision(g, Lcg(1), trials = 0) }.message,
        )
        assertEquals(10, botDecision(g, Lcg(1), trials = 10).trace.view!!.equityTrials)
    }
}
