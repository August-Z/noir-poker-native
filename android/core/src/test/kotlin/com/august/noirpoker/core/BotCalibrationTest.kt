package com.august.noirpoker.core

import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * Port of the reference `measure:bots` harness (`scripts/measure-bots.mjs`) and its documented
 * calibration table (see docs/BOTS.md). Every seat, the hero included, plays the bot policy for
 * 250 hands with policy seed 781 and deck seed 711, emotions off, and 100 BB stacks reset before
 * each hand. The engine is fixture-exact, so the reference numbers must reproduce exactly.
 *
 * The run plays 500 simulated hands with equity sampling, so it takes a few seconds.
 */
class BotCalibrationTest {
    data class Measurement(
        val samples: Int,
        val vpip: Int,
        val pfr: Int,
        val flopHands: Int,
        val flopPlayers: Int,
        val threePlusFlopHands: Int,
        val flopPlayerDistribution: Map<Int, Int>,
        val preflopReraisedHands: Int,
    ) {
        val vpipPercent get() = 100.0 * vpip / samples
        val pfrPercent get() = 100.0 * pfr / samples
        val averageFlopPlayers get() = if (flopHands == 0) 0.0 else flopPlayers.toDouble() / flopHands
    }

    private fun measureBots(
        players: Int,
        hands: Int = 250,
        profile: String = "balanced",
        policySeed: Long = 781,
        deckSeed: Long = 711,
    ): Measurement {
        val random = Lcg(policySeed)
        val deckRandom = Lcg(deckSeed)
        val g = newGame(players)
        applyBotSettings(
            g,
            mapOf("emotionMode" to "off", "assignments" to (1 until players).associateWith { profile }),
        )
        var flopHands = 0
        var flopPlayers = 0
        var threePlus = 0
        val distribution = sortedMapOf<Int, Int>()
        var reraised = 0
        repeat(hands) {
            for (p in g.players) p.stack = STARTING_STACK
            startHand(g, deckRandom)
            var actions = 0
            while (g.phase != Phase.DONE) {
                if (++actions > 1000) fail("unfinished hand")
                if (g.phase == Phase.BETWEEN) {
                    if (g.street == 0) {
                        val entrants = g.players.count { !it.folded }
                        flopHands++
                        flopPlayers += entrants
                        if (entrants >= 3) threePlus++
                        distribution[entrants] = (distribution[entrants] ?: 0) + 1
                    }
                    advanceStreet(g)
                } else {
                    val d = botDecision(g, random)
                    act(g, g.actor, d.action, d.amount)
                }
            }
            if (g.history.count { it.street == 0 && it.action == Action.RAISE } >= 2) reraised++
        }
        val bots = g.players.drop(1)
        return Measurement(
            samples = bots.sumOf { it.botStats.hands },
            vpip = bots.sumOf { it.botStats.vpip },
            pfr = bots.sumOf { it.botStats.pfr },
            flopHands = flopHands,
            flopPlayers = flopPlayers,
            threePlusFlopHands = threePlus,
            flopPlayerDistribution = distribution,
            preflopReraisedHands = reraised,
        )
    }

    private fun assertPercent(expected: String, actual: Double) =
        assertEquals(expected, "%.2f".format(Locale.ROOT, actual))

    private fun assertAverage(expected: String, actual: Double) =
        assertEquals(expected, "%.3f".format(Locale.ROOT, actual))

    // Expected values are the raw `node scripts/measure-bots.mjs` output of the pinned reference.

    @Test
    fun `six-max balanced calibration reproduces the documented reference statistics`() {
        val m = measureBots(players = 6)
        assertEquals(
            Measurement(1250, 677, 181, 217, 712, 148, mapOf(2 to 69, 3 to 59, 4 to 55, 5 to 27, 6 to 7), 33),
            m,
        )
        assertPercent("54.16", m.vpipPercent)
        assertPercent("14.48", m.pfrPercent)
        assertAverage("3.281", m.averageFlopPlayers)
    }

    @Test
    fun `nine-max balanced calibration reproduces the documented reference statistics`() {
        val m = measureBots(players = 9)
        assertEquals(
            Measurement(
                2000, 919, 252, 192, 741, 141,
                mapOf(2 to 51, 3 to 36, 4 to 42, 5 to 33, 6 to 17, 7 to 8, 8 to 5), 52,
            ),
            m,
        )
        assertPercent("45.95", m.vpipPercent)
        assertPercent("12.60", m.pfrPercent)
        assertAverage("3.859", m.averageFlopPlayers)
    }

    @Test
    fun `tight and loose archetypes keep their documented six-max entry rates`() {
        val st = measureBots(players = 6, profile = "st")
        val peter = measureBots(players = 6, profile = "peter")
        assertEquals(
            Measurement(1250, 629, 206, 216, 662, 139, mapOf(2 to 77, 3 to 74, 4 to 42, 5 to 20, 6 to 3), 38),
            st,
        )
        assertEquals(
            Measurement(1250, 889, 276, 214, 775, 144, mapOf(2 to 70, 3 to 34, 4 to 37, 5 to 53, 6 to 20), 65),
            peter,
        )
        assertPercent("50.32", st.vpipPercent)
        assertPercent("71.12", peter.vpipPercent)
        assertTrue(st.vpipPercent < 54.16 && 54.16 < peter.vpipPercent)
    }

    @Test
    fun `second six-max seed pair reproduces the documented flop statistics`() {
        val m = measureBots(players = 6, policySeed = 9182, deckSeed = 123)
        assertEquals(
            Measurement(1250, 715, 203, 205, 684, 138, mapOf(2 to 67, 3 to 51, 4 to 47, 5 to 31, 6 to 9), 36),
            m,
        )
        assertAverage("3.337", m.averageFlopPlayers)
    }

    /** The reference `smallOpen` view: a 3 BB open from the hero, deep stacks, action on the cutoff. */
    private fun smallOpen(hole: List<Card>, count: Int = 9, position: String = "CO") = BotView(
        id = 1, hole = hole, street = 0, position = position, count = count, stack = 5000, bet = 0,
        pot = 225, currentBet = 150, contestable = 375, rivals = 5, equity = 0.05, difficulty = Difficulty.HARD,
        history = listOf(HistoryEntry(0, 0, Action.RAISE, 150)),
        opponents = listOf(0, 2, 3, 4, 5).map { BotOpponent(it, if (it == 0) 4850 else 5000, if (it == 0) 150 else 0, false) },
        legal = LegalActions(
            enabled = true, toCall = 150, callAmount = 150, canRaise = true,
            minRaiseTo = 250, fullRaiseTo = 250, maxRaiseTo = 5000,
        ),
    )

    private fun decide(view: BotView, profile: String = "balanced") =
        chooseBotAction(view, getBotProfile(profile), freshBotMood(), EmotionMode.OFF, RandomSource { 0.9 })

    @Test
    fun `small-open continuation keeps style and position order across all 1326 holes`() {
        assertEquals(Action.CALL, decide(smallOpen(cards("7s 6s"))).action)
        assertEquals(Action.FOLD, decide(smallOpen(cards("7s 6s"), position = "UTG")).action)
        assertEquals(Action.FOLD, decide(smallOpen(cards("7s 2h"), count = 6)).action)
        val deck = deckOfCards()
        val continues = listOf("st", "balanced", "peter").map { profile ->
            var n = 0
            for (a in deck.indices) for (b in a + 1 until deck.size) {
                if (decide(smallOpen(listOf(deck[a], deck[b])), profile).action != Action.FOLD) n++
            }
            n
        }
        assertTrue(continues[0] < continues[1] && continues[1] < continues[2], "ST / balanced / Peter: $continues")
    }
}
