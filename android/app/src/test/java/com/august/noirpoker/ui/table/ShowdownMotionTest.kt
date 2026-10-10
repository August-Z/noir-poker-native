package com.august.noirpoker.ui.table

import com.august.noirpoker.core.session.HandMotion
import com.august.noirpoker.ui.theme.NoirMetrics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The showdown card motions ported from the reference's `showdown.css`
 * keyframes, and the scene grid column rule. Poses are sampled on a plain
 * clock, so these run on the JVM without a device.
 */
class ShowdownMotionTest {
    private val eps = 1e-4f

    private fun assertPose(expected: CardPose, actual: CardPose, label: String) {
        assertEquals("$label tx", expected.tx, actual.tx, eps)
        assertEquals("$label ty", expected.ty, actual.ty, eps)
        assertEquals("$label rz", expected.rz, actual.rz, eps)
        assertEquals("$label ry", expected.ry, actual.ry, eps)
        assertEquals("$label scale", expected.scale, actual.scale, eps)
        assertEquals("$label alpha", expected.alpha, actual.alpha, eps)
        assertEquals("$label brightness", expected.brightness, actual.brightness, eps)
    }

    @Test
    fun winnerMotionsEndAtRestExceptHighCardAndRoyal() {
        for (motion in HandMotion.entries) {
            for (i in 0 until 5) {
                val anim = CardMotion.winner(motion, i)
                val end = anim.pose(anim.endMs.toFloat())
                val expected = when (motion) {
                    // `high-spotlight` 100%: translateY(-5px).
                    HandMotion.HIGH -> CardPose(ty = -5f)
                    // `royal-fan` 100%: rotate(calc((var(--i) - 2) * 2deg)).
                    HandMotion.ROYAL -> CardPose(rz = (i - 2) * 2f)
                    else -> CardPose()
                }
                assertPose(expected, end, "$motion card $i at the end")
                // Fill mode `both`: the pose holds after the end.
                assertPose(end, anim.pose(anim.endMs + 5_000f), "$motion card $i after the end")
            }
        }
    }

    @Test
    fun royalFanRotatesAroundTheMiddleCard() {
        val ends = (0 until 5).map { i -> CardMotion.winner(HandMotion.ROYAL, i).let { it.pose(it.endMs.toFloat()).rz } }
        assertEquals(listOf(-4f, -2f, 0f, 2f, 4f), ends)
    }

    @Test
    fun highCardSpotlightStartsSmallAndDim() {
        val start = CardMotion.winner(HandMotion.HIGH, 0).pose(0f)
        assertEquals(0.7f, start.scale, eps)
        assertEquals(0.6f, start.brightness, eps)
        assertEquals(1f, start.alpha, eps)
        // 40%: translateY(-10px) scale(1.12) brightness(1.12).
        val peak = CardMotion.winner(HandMotion.HIGH, 0).pose(1700 * 0.4f)
        assertPose(CardPose(ty = -10f, scale = 1.12f, brightness = 1.12f), peak, "high card at 40%")
    }

    @Test
    fun delaysAndDurationsFollowTheReference() {
        val timing = mapOf(
            HandMotion.HIGH to (1700 to 0),
            HandMotion.PAIR to (1500 to 60),
            HandMotion.TWO_PAIR to (1600 to 90),
            HandMotion.TRIPS to (1600 to 150),
            HandMotion.STRAIGHT to (1600 to 140),
            HandMotion.FLUSH to (1800 to 100),
            HandMotion.FULL_HOUSE to (1800 to 80),
            HandMotion.QUADS to (1800 to 60),
            HandMotion.STRAIGHT_FLUSH to (1900 to 100),
            HandMotion.ROYAL to (2000 to 60),
        )
        assertEquals(HandMotion.entries.toSet(), timing.keys)
        for ((motion, t) in timing) {
            for (i in 0 until 5) {
                val anim = CardMotion.winner(motion, i)
                assertEquals("$motion duration", t.first, anim.durationMs)
                assertEquals("$motion card $i delay", t.second * i, anim.delayMs)
            }
        }
        // The stage clock (2,800 ms) covers the longest motion: straight 1,600 + 4 × 140.
        assertTrue(HandMotion.entries.all { m -> (0 until 5).all { CardMotion.winner(m, it).endMs <= 2_800 } })
    }

    @Test
    fun rankArriveFadesInAndEndsAtRest() {
        for (i in 0 until 5) {
            val anim = CardMotion.arrive(i)
            assertEquals(800, anim.durationMs)
            assertEquals(i * 80, anim.delayMs)
            assertPose(CardPose(ty = 18f, ry = 45f, alpha = 0f), anim.pose(0f), "arrive card $i before its delay")
            assertPose(CardPose(), anim.pose(anim.endMs.toFloat()), "arrive card $i at the end")
        }
    }

    @Test
    fun appliesToAllMatchesTheCategoriesThatMoveEveryCard() {
        // `.motion-X .winning-card` (every card) versus `.motion-X .rank-match` (category cards only).
        val everyCard = setOf(HandMotion.STRAIGHT, HandMotion.FLUSH, HandMotion.FULL_HOUSE, HandMotion.STRAIGHT_FLUSH, HandMotion.ROYAL)
        val matchOnly = setOf(HandMotion.HIGH, HandMotion.PAIR, HandMotion.TWO_PAIR, HandMotion.TRIPS, HandMotion.QUADS)
        assertEquals(HandMotion.entries.toSet(), everyCard + matchOnly)
        everyCard.forEach { assertTrue("$it moves every card", CardMotion.appliesToAll(it)) }
        matchOnly.forEach { assertFalse("$it moves only the category cards", CardMotion.appliesToAll(it)) }
    }

    @Test
    fun sceneGridColumnsFollowTheReferenceBreakpoints() {
        // Mirrors the metrics NoirTableScreen derives from the window width.
        fun metrics(widthDp: Int, largeText: Boolean = false) = NoirMetrics(
            compact = widthDp <= 600,
            twoPane = widthDp >= 900,
            largeText = largeText,
            tiny = widthDp <= 360,
            narrowPane = widthDp in 900 until 1150,
        )
        assertEquals("phone", 1, showdownColumns(metrics(360)))
        assertEquals("phone at the breakpoint", 1, showdownColumns(metrics(600)))
        assertEquals("tablet portrait", 2, showdownColumns(metrics(601)))
        assertEquals("tablet portrait", 2, showdownColumns(metrics(800)))
        assertEquals("two panes beside the sidebar", 1, showdownColumns(metrics(1000)))
        assertEquals("two panes beside the sidebar", 1, showdownColumns(metrics(1149)))
        assertEquals("wide two panes", 2, showdownColumns(metrics(1150)))
        assertEquals("wide two panes", 2, showdownColumns(metrics(1280)))
        assertEquals("large text", 1, showdownColumns(metrics(1280, largeText = true)))
        assertEquals("large text", 1, showdownColumns(metrics(800, largeText = true)))
    }
}
