package com.august.noirpoker.ui.table

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import com.august.noirpoker.ui.theme.LocalReducedMotion
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.august.noirpoker.core.session.ShowdownSceneState
import com.august.noirpoker.core.session.ShowdownState
import com.august.noirpoker.ui.UiCopy
import com.august.noirpoker.ui.components.CardSize
import com.august.noirpoker.ui.components.PlayingCardView
import com.august.noirpoker.ui.theme.LocalNoirMetrics
import com.august.noirpoker.ui.theme.Noir
import com.august.noirpoker.ui.theme.NoirMetrics
import com.august.noirpoker.ui.theme.NoirType

/**
 * The showdown stage below the arena: one panel per live player with the best
 * five cards in display order, the category cards emphasized and kickers dimmed.
 * Every card arrives with `rank-arrive`; in winner panels the cards that make
 * the category (or all five, by category) play the hand's winner motion. The
 * clock restarts only when the settled hand's `key` changes.
 */
/** Longest winner motion (royal flush 2,000 ms + 4 × 60 ms, straight 1,600 + 4 × 140) with margin. */
private const val END_MS = 2800f

/** Kicker opacity in a scene (`.winning-card.kicker`). */
private const val KICKER_ALPHA = 0.7f

@Composable
fun ShowdownStage(showdown: ShowdownState, modifier: Modifier = Modifier) {
    val metrics = LocalNoirMetrics.current
    Column(
        modifier
            .fillMaxWidth()
            .background(Brush.verticalGradient(listOf(Noir.ShowdownBg, Color(0xFF14201F))))
            .padding(horizontal = if (metrics.compact) 14.dp else 25.dp, vertical = if (metrics.compact) 19.dp else 22.dp)
            .semantics {
                contentDescription = UiCopy.showdownRegionA11y
                liveRegion = LiveRegionMode.Polite
            },
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(UiCopy.showdownEyebrow, style = NoirType.style(10.sp, FontWeight.SemiBold, Noir.GoldEyebrow, 2.sp))
            Text(showdown.context, style = NoirType.style(12.sp, color = Noir.TextStrip))
        }
        val reduced = LocalReducedMotion.current
        val clock = remember(showdown.key) { Animatable(if (reduced) END_MS else 0f) }
        LaunchedEffect(showdown.key, reduced) {
            if (reduced) clock.snapTo(END_MS) else clock.animateTo(END_MS, tween(END_MS.toInt(), easing = LinearEasing))
        }
        val columns = showdownColumns(metrics)
        showdown.scenes.chunked(columns).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.height(IntrinsicSize.Max)) {
                row.forEach { ScenePanel(it, { clock.value }, Modifier.weight(1f).fillMaxHeight()) }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/**
 * Scene grid columns, as in the reference (`showdown.css`, visual spec 10.1): two
 * columns above 1,150 dp and at 601–900 dp, one column in the 901–1,150 dp
 * two-pane band (the table shares the width with the sidebar) and on phones
 * (≤600 dp). Large accessibility text also gets one column, as browser zoom
 * narrows the reference's CSS viewport into the one-column bands.
 */
internal fun showdownColumns(metrics: NoirMetrics): Int =
    if (metrics.compact || metrics.narrowPane || metrics.largeText) 1 else 2

@Composable
private fun ScenePanel(scene: ShowdownSceneState, clock: () -> Float, modifier: Modifier) {
    val shape = RoundedCornerShape(11.dp)
    val winner = scene.isWinner
    val metrics = LocalNoirMetrics.current
    // Reduced motion shows every card at full opacity, kickers included (`showdown.css` reduced-motion block).
    val reduced = LocalReducedMotion.current
    Column(
        modifier
            .background(
                if (winner) Brush.linearGradient(listOf(Color(0x223B3823), Color(0xFF14252A))) else Brush.linearGradient(listOf(Noir.ScenePanel, Noir.ScenePanel)),
                shape,
            )
            .border(1.dp, if (winner) Noir.GoldMuted else Noir.ScenePanelBorder, shape)
            .padding(16.dp)
            .semantics(mergeDescendants = true) { contentDescription = scene.a11y },
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                buildAnnotatedString {
                    scene.nameSegments.forEach { seg ->
                        if (seg.isPersona) withStyle(SpanStyle(color = Noir.SceneName.copy(alpha = 0.7f), fontWeight = FontWeight.Normal)) { append(seg.text) } else append(seg.text)
                    }
                },
                style = NoirType.style(14.sp, FontWeight.SemiBold, Noir.SceneName),
                modifier = Modifier.weight(1f),
            )
            Text(scene.statusText, style = NoirType.style(12.sp, FontWeight.Medium, if (winner) Noir.GoldPale else Noir.SceneLoser))
        }
        Spacer(Modifier.height(8.dp))
        Text(scene.scene.label, style = NoirType.style(if (metrics.compact) 20.sp else 24.sp, color = if (winner) Noir.GoldBright else Noir.SceneHand, tracking = 1.sp))
        Text(scene.scene.explanation, style = NoirType.style(12.sp, color = Noir.TextSubtle))
        Spacer(Modifier.height(12.dp))
        val w = if (metrics.tiny) 37.dp else 43.dp
        val h = if (metrics.tiny) 54.dp else 62.dp
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp, Alignment.CenterHorizontally)) {
            val motion = scene.scene.motion
            scene.scene.cards.forEachIndexed { i, card ->
                val match = scene.scene.highlights.getOrElse(i) { false }
                val anim = remember(motion, i, winner, match) {
                    if (winner && (match || CardMotion.appliesToAll(motion))) CardMotion.winner(motion, i) else CardMotion.arrive(i)
                }
                val outline = if (winner) Noir.SceneMatch else Noir.SceneLoserOutline
                PlayingCardView(
                    card,
                    w,
                    h,
                    size = CardSize.SMALL,
                    modifier = Modifier
                        .graphicsLayer {
                            val pose = anim.pose(clock())
                            translationX = pose.tx * density
                            translationY = pose.ty * density
                            rotationZ = pose.rz
                            rotationY = pose.ry
                            scaleX = pose.scale
                            scaleY = pose.scale
                            alpha = pose.alpha * (if (match || reduced) 1f else KICKER_ALPHA)
                            cameraDistance = 7f * density
                        }
                        .drawWithContent {
                            drawContent()
                            val b = anim.pose(clock()).brightness
                            if (b != 1f) {
                                val tint = if (b > 1f) Color.White.copy(alpha = ((b - 1f) * 1.6f).coerceIn(0f, 0.5f)) else Color.Black.copy(alpha = (1f - b).coerceIn(0f, 0.6f))
                                drawRoundRect(tint, cornerRadius = CornerRadius(5.dp.toPx()))
                            }
                            if (match) {
                                val o = 2.dp.toPx()
                                drawRoundRect(
                                    outline,
                                    topLeft = Offset(-o, -o),
                                    size = Size(size.width + 2 * o, size.height + 2 * o),
                                    cornerRadius = CornerRadius(7.dp.toPx()),
                                    style = Stroke(1.dp.toPx()),
                                )
                            }
                        }
                        .then(if (match && winner) Modifier.shadow(8.dp, RoundedCornerShape(5.dp), ambientColor = Noir.SceneMatch, spotColor = Noir.SceneMatch) else Modifier),
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        HorizontalDivider(color = Color(0x66345044))
        Spacer(Modifier.height(8.dp))
        Text(scene.footerText, style = NoirType.style(12.sp, color = if (winner) Noir.GoldPale else Noir.SceneLoser))
    }
}
