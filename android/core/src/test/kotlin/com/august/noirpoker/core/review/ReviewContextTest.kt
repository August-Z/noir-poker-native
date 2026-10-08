package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.parseCards
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Port of the reference `review-context.test.js`, plus the equity reference vectors. */
class ReviewContextTest {
    @Test
    fun `open-ended draw has eight distinct direct completion cards`() {
        val draw = drawInfo(parseCards("8s 9h"), parseCards("6c 7d Kc"))
        assertEquals(8, draw.straightOuts)
        assertEquals(8, draw.outs)
        assertEquals(8.0 / 47, draw.nextChance)
    }

    @Test
    fun `combined flush and straight draw deduplicates the shared ten of spades`() {
        val draw = drawInfo(parseCards("As Ks"), parseCards("Qs Js 2h"))
        assertEquals(9, draw.flushOuts)
        assertEquals(4, draw.straightOuts)
        assertEquals(12, draw.outs)
        assertEquals(12.0 / 47, draw.nextChance)
    }

    @Test
    fun `made straight is not mislabeled as a straight draw and the river has no next card`() {
        val draw = drawInfo(parseCards("8s 9h"), parseCards("6c 7d Tc"))
        assertFalse(draw.straight)
        assertEquals(0, draw.outs)
        assertEquals(0, drawInfo(parseCards("As Ks"), parseCards("Qs Js 2h 4d 5c")).outs)
    }

    @Test
    fun `overpair, top pair kicker and a public pair get different factual descriptions`() {
        val overpair = decisionContext(contextDecision())
        assertEquals(HandClass.OVERPAIR, overpair.handClass)
        assertEquals("an overpair (Queens)", overpair.handLabel.phrase)
        assertEquals("An overpair (Queens)", overpair.handLabel.start)
        val top = decisionContext(contextDecision(hole = "As Jh"))
        assertEquals(HandClass.TOP_PAIR, top.handClass)
        assertTrue("an A kicker" in top.handLabel.phrase, top.handLabel.phrase)
        val publicPair = decisionContext(contextDecision(hole = "As Kh", board = "7s 7h 2c"))
        assertEquals(HandClass.BOARD_PAIR, publicPair.handClass)
        assertTrue("board pair" in publicPair.handLabel.phrase)
        assertNotEquals("value-check", analyzeDecision(contextDecision(hole = "As Kh", board = "7s 7h 2c"), TEST_TRIALS).code)
    }

    @Test
    fun `deep pocket queens shove suggests a legal smaller value route while short aces do not get that verdict`() {
        // The reference uses pot 75 (fractional totals); native totals are integers, so pot 76.
        val r = analyzeDecision(
            contextDecision(street = 0, board = "", action = Action.RAISE, amount = 5000, pot = 76, currentBet = 50),
            TEST_TRIALS,
        )
        assertEquals("deep-value-shove", r.code)
        assertEquals(CandidateAction(Action.RAISE, 150), r.alternative)
        assertTrue("100 BB" in r.reason, r.reason)
        val a = analyzeDecision(
            contextDecision(hole = "As Ah", street = 0, board = "", stack = 1000, action = Action.RAISE, amount = 1000, currentBet = 50, pot = 76),
            TEST_TRIALS,
        )
        assertEquals("value-bet", a.code)
        assertFalse("which opponent ranges will fold" in a.lesson)
    }

    @Test
    fun `four-suit board with no flush does not produce a strong value-check recommendation`() {
        val r = analyzeDecision(contextDecision(hole = "Kh Kc", board = "Ks 7s 2s 4s", street = 2), TEST_TRIALS)
        assertNotEquals("value-check", r.code)
        assertTrue(r.evidence.any { "four to a flush" in it.lowercase() }, r.evidence.toString())
    }

    @Test
    fun `river heads-up completely enumerates 990 legal pairs and ties on a royal board`() {
        val r = analyzeDecision(contextDecision(hole = "2h 3h", board = "As Ks Qs Js Ts", street = 3), TEST_TRIALS)
        assertEquals(EquityMethod.ENUMERATION, r.metrics.method)
        assertEquals(990, r.metrics.trials)
        assertEquals(0.0, r.metrics.uncertainty)
        assertEquals(0.5, r.metrics.randomEquity)
        assertEquals(0.5, r.metrics.weightedEquity)
    }

    @Test
    fun `sampling keeps a nonzero protection band even for an observed all-win sample`() {
        val r = analyzeDecision(contextDecision(hole = "As Ah", board = "Ac Ad 2s"), trials = 10)
        assertEquals(EquityMethod.SAMPLING, r.metrics.method)
        assertTrue(r.metrics.uncertainty > 0)
    }

    // Reference vectors (computed with the pinned reference).

    @Test
    fun `snapshot seed hashes the exact reference JSON text`() {
        val s = contextDecision()
        assertEquals(
            "[[{\"rank\":12,\"suit\":0,\"symbol\":\"♠\",\"key\":\"0-12\"},{\"rank\":12,\"suit\":1,\"symbol\":\"♥\",\"key\":\"1-12\"}]," +
                "[{\"rank\":11,\"suit\":0,\"symbol\":\"♠\",\"key\":\"0-11\"},{\"rank\":7,\"suit\":1,\"symbol\":\"♥\",\"key\":\"1-7\"}," +
                "{\"rank\":2,\"suit\":2,\"symbol\":\"♣\",\"key\":\"2-2\"}]," +
                "[{\"id\":0,\"position\":\"BTN\",\"stack\":5000,\"bet\":0,\"total\":150,\"folded\":false,\"allin\":false}," +
                "{\"id\":1,\"position\":\"BB\",\"stack\":5000,\"bet\":0,\"total\":150,\"folded\":false,\"allin\":false}],[],1,0]",
            snapshotSeedJson(s),
        )
        assertEquals(2583955511L, snapshotSeed(s))
        val rng = seedRandom(2583955511L)
        assertEquals(listOf(0.275968698784709, 0.8002593538258225, 0.1536247490439564), List(3) { rng.next() })
    }

    @Test
    fun `seed offsets wrap modulo two to the thirty-second`() {
        assertEquals(0.5067068429198116, seedRandom(4294967295L + 11071).next())
        val rng = seedRandom(1)
        assertEquals(listOf(0.6270739405881613, 0.002735721180215478, 0.5274470399599522), List(3) { rng.next() })
    }

    @Test
    fun `sampled equity matches the reference values`() {
        val s = contextDecision()
        val price = callPrice(s)
        val random = sampleValue(s, price, 120, false)
        assertEquals(0.8583333333333333, random.equity)
        assertEquals(257.5, random.ev)
        assertEquals(0.13512381104432028, random.margin)
        assertEquals(EquityMethod.SAMPLING, random.method)
        val weighted = sampleValue(s, price, 120, true)
        assertEquals(0.7916666666666666, weighted.equity)
        assertEquals(237.5, weighted.ev)
        val wide = sampleValue(s, price, 600, false)
        assertEquals(0.8133333333333334, wide.equity)
        assertEquals(244.0, wide.ev)
        assertEquals(0.0604292053747874, wide.margin)
        assertEquals(1.0, sampleValue(s, price, 1, false).margin)
    }

    @Test
    fun `heads-up river enumeration matches the reference values`() {
        val s = contextDecision(hole = "As Kh", board = "Qs Jd 7c 5h 2s", street = 3)
        for (weighted in listOf(false, true)) {
            val v = sampleValue(s, callPrice(s), 120, weighted)
            assertEquals(EquityMethod.ENUMERATION, v.method)
            assertEquals(990, v.samples)
            assertEquals(0.3924242424242424, v.equity)
            assertEquals(117.72727272727272, v.ev)
        }
    }

    @Test
    fun `nothing contestable returns zero equity without a method`() {
        val s = contextDecision(pot = 0)
        val v = sampleValue(s, callPrice(s), 50, false)
        assertEquals(SampledValue(0.0, 0.0, 0.0), v)
        assertNull(v.method)
    }

    @Test
    fun `board texture tags read in the reference order`() {
        assertEquals("paired, three to a flush", boardTexture(parseCards("7s 7h 2s 9s")).phrase)
        assertEquals("Paired, three to a flush", boardTexture(parseCards("7s 7h 2s 9s")).label)
        assertEquals("two-tone, clearly straight-connected", boardTexture(parseCards("8s 9h Ts")).phrase)
        assertEquals("trips on board, four to a straight", boardTexture(parseCards("5s 5h 5c 4d 3d 2c")).phrase)
        assertEquals("rainbow and disconnected", boardTexture(emptyList()).phrase)
        assertTrue(boardTexture(parseCards("Ah 2c 3d")).connected == 3)
    }

    @Test
    fun `preflop hand labels follow hole order and suitedness`() {
        val ctx = decisionContext(contextDecision(hole = "7h Ac", street = 0, board = ""))
        assertEquals(HandClass.UNPAIRED, ctx.handClass)
        assertEquals("7/A offsuit", ctx.handLabel.phrase)
        assertEquals("pocket Nines", decisionContext(contextDecision(hole = "9h 9c", street = 0, board = "")).handLabel.phrase)
        val set = decisionContext(contextDecision(hole = "7c 7d"))
        assertEquals(HandClass.SET, set.handClass)
        assertEquals("A set of Sevens", set.handLabel.start)
        val board = decisionContext(contextDecision(hole = "2c 3d", board = "As Ks Qs Js Ts", street = 3))
        assertEquals(HandClass.BOARD, board.handClass)
        val straight = decisionContext(contextDecision(hole = "Tc 9d", board = "8s 7h 6c"))
        assertEquals(HandClass.STRONG, straight.handClass)
        assertEquals("a straight", straight.handLabel.phrase)
        assertEquals("Straight", straight.handLabel.start)
    }
}
