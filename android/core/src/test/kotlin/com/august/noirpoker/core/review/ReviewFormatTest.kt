package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.actionLabel
import kotlin.test.Test
import kotlin.test.assertEquals

/** JavaScript number formatting and label fallbacks that the review fixtures do not reach. */
class ReviewFormatTest {
    @Test
    fun `jsNumber matches JavaScript String(x)`() {
        val cases = listOf(
            0.0 to "0",
            -0.0 to "0",
            79.0 to "79",
            94.5 to "94.5",
            -12.25 to "-12.25",
            0.1 + 0.2 to "0.30000000000000004",
            76.30000000000001 to "76.30000000000001",
            0.0005 to "0.0005",
            1e-6 to "0.000001",
            1e-7 to "1e-7",
            1.5e-7 to "1.5e-7",
            -2.5e-9 to "-2.5e-9",
            12345678.5 to "12345678.5",
            1e20 to "100000000000000000000",
            1e21 to "1e+21",
            1.2345e22 to "1.2345e+22",
            Double.NaN to "NaN",
            Double.POSITIVE_INFINITY to "Infinity",
            Double.NEGATIVE_INFINITY to "-Infinity",
        )
        for ((x, expected) in cases) assertEquals(expected, jsNumber(x), "String($x)")
    }

    @Test
    fun `jsToFixed matches JavaScript toFixed`() {
        // Rounds the exact binary value: 1.05 is 1.0500…044, 0.15 is 0.1499…94.
        assertEquals("1.1", jsToFixed(1.05, 1))
        assertEquals("2.5", jsToFixed(2.45, 1))
        assertEquals("0.1", jsToFixed(0.15, 1))
        assertEquals("8.35", jsToFixed(8.345, 2))
        assertEquals("-0.0", jsToFixed(-0.04, 1))
        assertEquals("0.0", jsToFixed(-0.0, 1))
        assertEquals("66.7", jsToFixed(66.66666666666667, 1))
        assertEquals("1e+21", jsToFixed(1e21, 1))
        assertEquals("NaN", jsToFixed(Double.NaN, 1))
    }

    @Test
    fun `review percent and chip formatters print NaN like JavaScript`() {
        assertEquals("NaN%", percent(Double.NaN))
        assertEquals("NaN", number(Double.NaN))
        assertEquals("NaN", roundedInt(Double.NaN))
        assertEquals("0%", percent(-0.004))
        assertEquals("-1,234", number(-1234.5)) // Math.round rounds half up: -1234.5 → -1234
        assertEquals("NaN%", pct(Double.NaN))
        assertEquals("+0.0%", signedPct(-0.0))
        assertEquals("-0.0%", signedPct(-0.0001))
    }

    @Test
    fun `a hand-built snapshot without fullRaiseTo labels a short all-in raise like the reference`() {
        // review-check "short all-in raise": legal has no fullRaiseTo, so the caption falls
        // back to currentBet + minRaise = 150 and a raise to the 125 maximum is short.
        val s = checkSnapshot(
            totals = listOf(100, 100, 0, 0, 0, 0),
            stacks = listOf(25, 1000, 0, 0, 0, 0),
            action = Action.RAISE,
            amount = 125,
            currentBet = 100,
        ).let { it.copy(legal = it.legal.copy(toCall = 125, callAmount = 125, maxRaiseTo = 125), labelFullRaiseTo = null) }
        assertEquals("2-bet short all-in to 125", actionLabel(s.labelStep(), Action.RAISE, 125))
        // An engine snapshot always carries fullRaiseTo; it wins over the fallback.
        val engine = s.copy(labelFullRaiseTo = 100)
        assertEquals("2-bet all-in to 125", actionLabel(engine.labelStep(), Action.RAISE, 125))
    }
}
