package com.august.noirpoker.ui.table

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import com.august.noirpoker.core.session.SessionEffect
import com.august.noirpoker.ui.theme.LocalReducedMotion
import com.august.noirpoker.ui.theme.Noir
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/**
 * Remembers where the arena's actors are drawn so chip flights can start at a
 * seat plate (or the hero row) and end at the pot. Plain fields, not state: the
 * positions are only read when a flight starts.
 */
class ArenaAnchors {
    internal var root: LayoutCoordinates? = null
    private val nodes = HashMap<Int, LayoutCoordinates>()

    /** Center of anchor [id] in arena coordinates, if it is laid out. */
    fun center(id: Int): Offset? {
        val r = root ?: return null
        val c = nodes[id] ?: return null
        if (!r.isAttached || !c.isAttached) return null
        return r.localPositionOf(c, Offset(c.size.width / 2f, c.size.height / 2f))
    }

    fun rootModifier(): Modifier = Modifier.onGloballyPositioned { root = it }

    fun anchor(id: Int): Modifier = Modifier.onGloballyPositioned { nodes[id] = it }

    companion object {
        /** Anchor id of the pot; seats use their id (0 = hero). */
        const val POT = -1
    }
}

private class Flight(val from: Offset, val to: Offset) {
    val clock = Animatable(0f)
}

private fun lerp(a: Float, b: Float, t: Float) = a + (b - a) * t

private val chipEasing = CubicBezierEasing(0.2f, 0.7f, 0.3f, 1f)
private const val CHIP_MS = 520f
private const val CHIP_STAGGER_MS = 60f
private const val CHIPS = 3

/**
 * Flying chips (visual spec 8.9): on a bet, call or raise the session emits
 * `ChipFlight(seat)`; three 17 dp chips leave the actor's plate 60 ms apart and
 * slide to the pot in 520 ms, shrinking to 0.7 and fading out. Replay Hand emits
 * `CancelChipFlights`, which removes chips in flight. Skipped under reduced motion.
 */
@Composable
fun ChipFlightLayer(effects: Flow<SessionEffect>?, anchors: ArenaAnchors, modifier: Modifier = Modifier) {
    val reduced = LocalReducedMotion.current
    val flights = remember { mutableStateListOf<Flight>() }
    LaunchedEffect(effects, reduced) {
        if (effects == null) return@LaunchedEffect
        val jobs = ArrayList<Job>()
        effects.collect { effect ->
            when (effect) {
                is SessionEffect.ChipFlight -> {
                    if (reduced) return@collect
                    val from = anchors.center(effect.seat) ?: return@collect
                    val to = anchors.center(ArenaAnchors.POT) ?: return@collect
                    val flight = Flight(from, to)
                    flights.add(flight)
                    jobs.removeAll { !it.isActive }
                    jobs += launch {
                        try {
                            val total = CHIP_MS + CHIP_STAGGER_MS * (CHIPS - 1)
                            flight.clock.animateTo(total, tween(total.toInt(), easing = LinearEasing))
                        } finally {
                            flights.remove(flight)
                        }
                    }
                }
                SessionEffect.CancelChipFlights -> {
                    jobs.forEach { it.cancel() }
                    jobs.clear()
                    flights.clear()
                }
                else -> Unit
            }
        }
    }
    if (flights.isEmpty()) return
    Canvas(modifier.fillMaxSize()) {
        val radius = 8.5f * density
        val dash = PathEffect.dashPathEffect(floatArrayOf(3f * density, 2.2f * density))
        for (flight in flights) {
            val t = flight.clock.value
            for (i in 0 until CHIPS) {
                val local = ((t - i * CHIP_STAGGER_MS) / CHIP_MS).coerceIn(0f, 1f)
                if (t < i * CHIP_STAGGER_MS) continue
                val e = chipEasing.transform(local)
                val start = flight.from + Offset(3f * i * density, -3f * i * density)
                val p = Offset(lerp(start.x, flight.to.x, e), lerp(start.y, flight.to.y, e))
                val scale = lerp(1f, 0.7f, e)
                val alpha = 1f - e
                val r = radius * scale
                drawCircle(Noir.Bg.copy(alpha = 0.3f * alpha), r, p + Offset(0f, 2f * density))
                drawCircle(Noir.ChipFill.copy(alpha = alpha), r, p)
                drawCircle(
                    Noir.ChipEdge.copy(alpha = alpha),
                    r - density,
                    p,
                    style = Stroke(2f * density * scale, pathEffect = dash),
                )
            }
        }
    }
}
