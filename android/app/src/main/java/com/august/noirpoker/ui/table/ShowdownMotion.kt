package com.august.noirpoker.ui.table

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import com.august.noirpoker.core.session.HandMotion

/**
 * The showdown card motions of the reference (`showdown.css`, visual spec 10.2–10.3)
 * as sampled keyframes. Values are CSS units: dp for translation, degrees for
 * rotation, a factor for scale, alpha and brightness. As in CSS, the timing
 * function applies to each keyframe interval, transforms missing from a keyframe
 * are the identity, and opacity / brightness interpolate between the keyframes
 * that set them.
 */
data class CardPose(
    val tx: Float = 0f,
    val ty: Float = 0f,
    val rz: Float = 0f,
    val ry: Float = 0f,
    val scale: Float = 1f,
    val alpha: Float = 1f,
    val brightness: Float = 1f,
)

private class Key(
    val at: Float,
    val tx: Float = 0f,
    val ty: Float = 0f,
    val rz: Float = 0f,
    val ry: Float = 0f,
    val scale: Float = 1f,
    val alpha: Float? = null,
    val brightness: Float? = null,
)

/** One card's animation: duration, delay, easing and keyframes. */
class CardMotion private constructor(
    val durationMs: Int,
    val delayMs: Int,
    private val easing: Easing,
    private val keys: List<Key>,
) {
    val endMs: Int get() = delayMs + durationMs

    /** The pose at [timeMs] since the scene appeared (fill mode `both`). */
    fun pose(timeMs: Float): CardPose {
        val t = ((timeMs - delayMs) / durationMs).coerceIn(0f, 1f)
        return CardPose(
            tx = sample(t, keys) { it.tx },
            ty = sample(t, keys) { it.ty },
            rz = sample(t, keys) { it.rz },
            ry = sample(t, keys) { it.ry },
            scale = sample(t, keys) { it.scale },
            alpha = sample(t, keys.withEnds { it.alpha }) { it.alpha!! },
            brightness = sample(t, keys.withEnds { it.brightness }) { it.brightness!! },
        )
    }

    private fun List<Key>.withEnds(get: (Key) -> Float?): List<Key> {
        val set = filter { get(it) != null }.map { Key(it.at, alpha = it.alpha ?: 1f, brightness = it.brightness ?: 1f) }
        val list = ArrayList(set)
        if (list.none { it.at == 0f }) list.add(0, Key(0f, alpha = 1f, brightness = 1f))
        if (list.none { it.at == 1f }) list.add(Key(1f, alpha = 1f, brightness = 1f))
        // Keep the property being sampled; the other one is ignored by the caller.
        return list
    }

    private fun sample(t: Float, keys: List<Key>, get: (Key) -> Float): Float {
        if (keys.isEmpty()) return 0f
        if (t <= keys.first().at) return get(keys.first())
        for (k in 1 until keys.size) {
            val a = keys[k - 1]
            val b = keys[k]
            if (t <= b.at) {
                val span = (b.at - a.at).takeIf { it > 0f } ?: return get(b)
                val local = easing.transform((t - a.at) / span)
                return get(a) + (get(b) - get(a)) * local
            }
        }
        return get(keys.last())
    }

    companion object {
        private val easeOut = CubicBezierEasing(0f, 0f, 0.58f, 1f)
        private val easeInOut = CubicBezierEasing(0.42f, 0f, 0.58f, 1f)
        private val arrive = CubicBezierEasing(0.18f, 0.7f, 0.25f, 1f)
        private val fullHouse = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f)

        /** `rank-arrive`: every card that has no winner motion. */
        fun arrive(i: Int) = CardMotion(
            800, i * 80, arrive,
            listOf(Key(0f, ty = 18f, ry = 45f, alpha = 0f), Key(1f, alpha = 1f)),
        )

        /** Whether [motion] moves every card or only the cards that make the category. */
        fun appliesToAll(motion: HandMotion) = when (motion) {
            HandMotion.STRAIGHT, HandMotion.FLUSH, HandMotion.FULL_HOUSE, HandMotion.STRAIGHT_FLUSH, HandMotion.ROYAL -> true
            else -> false
        }

        /** The winner motion for card [i] (0–4) of a [motion] hand. */
        fun winner(motion: HandMotion, i: Int): CardMotion {
            val c = i - 2f
            return when (motion) {
                HandMotion.HIGH -> CardMotion(
                    1700, 0, easeOut,
                    listOf(Key(0f, scale = 0.7f, brightness = 0.6f), Key(0.4f, ty = -10f, scale = 1.12f, brightness = 1.12f), Key(1f, ty = -5f, brightness = 1f)),
                )
                HandMotion.PAIR -> CardMotion(
                    1500, i * 60, easeOut,
                    listOf(
                        Key(0f, ty = 14f, alpha = 0f), Key(0.3f, ty = -4f, scale = 1.08f), Key(0.45f, alpha = 1f),
                        Key(0.65f, ty = -4f, scale = 1.08f), Key(1f, alpha = 1f),
                    ),
                )
                HandMotion.TWO_PAIR -> CardMotion(
                    1600, i * 90, easeOut,
                    listOf(Key(0f, tx = (1.5f - i) * 14f, rz = (i - 1.5f) * 8f, alpha = 0f), Key(0.55f, ty = -7f), Key(1f, alpha = 1f)),
                )
                HandMotion.TRIPS -> CardMotion(
                    1600, i * 150, easeOut,
                    listOf(Key(0f, ty = 24f, alpha = 0f), Key(0.45f, ty = -12f), Key(0.7f, ty = 3f), Key(1f, alpha = 1f)),
                )
                HandMotion.STRAIGHT -> CardMotion(
                    1600, i * 140, easeOut,
                    listOf(Key(0f, ty = 20f, ry = 90f, alpha = 0f), Key(0.5f, ty = -7f, alpha = 1f), Key(1f)),
                )
                HandMotion.FLUSH -> CardMotion(
                    1800, i * 100, easeInOut,
                    listOf(
                        Key(0f, rz = -8f, ty = 10f, alpha = 0f), Key(0.35f, rz = 5f, ty = -10f, brightness = 1.12f),
                        Key(0.7f, rz = -2f, ty = 4f), Key(1f, alpha = 1f, brightness = 1f),
                    ),
                )
                HandMotion.FULL_HOUSE -> CardMotion(
                    1800, i * 80, fullHouse,
                    listOf(Key(0f, tx = c * 20f, ty = 14f, alpha = 0f), Key(0.5f, tx = -c * 3f, ty = -4f), Key(1f, alpha = 1f)),
                )
                HandMotion.QUADS -> CardMotion(
                    1800, i * 60, easeOut,
                    listOf(
                        Key(0f, scale = 0.6f, alpha = 0f), Key(0.25f, scale = 1.14f, brightness = 1.16f),
                        Key(0.45f, scale = 0.96f), Key(0.65f, scale = 1.04f), Key(1f, alpha = 1f, brightness = 1f),
                    ),
                )
                HandMotion.STRAIGHT_FLUSH -> CardMotion(
                    1900, i * 100, easeOut,
                    listOf(
                        Key(0f, ty = 28f, ry = 100f, alpha = 0f),
                        Key(0.4f, ty = c * c * -3f - 7f, alpha = 1f, brightness = 1.15f),
                        Key(1f, brightness = 1f),
                    ),
                )
                HandMotion.ROYAL -> CardMotion(
                    2000, i * 60, easeOut,
                    listOf(
                        Key(0f, tx = -c * 40f, rz = c * 14f, alpha = 0f),
                        Key(0.5f, ty = -10f, rz = c * 5f, alpha = 1f, brightness = 1.14f),
                        Key(1f, rz = c * 2f, brightness = 1f),
                    ),
                )
            }
        }
    }
}
