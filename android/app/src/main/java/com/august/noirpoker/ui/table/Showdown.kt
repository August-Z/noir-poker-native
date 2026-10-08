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
import androidx.compose.ui.draw.alpha
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
import com.august.noirpoker.ui.theme.NoirType

/**
 * The showdown stage below the arena: one panel per live player with the best
 * five cards in display order, the category cards emphasized and kickers dimmed.
 * Winner motions per hand category come in a later step.
 */
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
        val columns = if (metrics.twoPane && !metrics.largeText) 2 else 1
        showdown.scenes.chunked(columns).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                row.forEach { ScenePanel(it, Modifier.weight(1f)) }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun ScenePanel(scene: ShowdownSceneState, modifier: Modifier) {
    val shape = RoundedCornerShape(11.dp)
    val winner = scene.isWinner
    val metrics = LocalNoirMetrics.current
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
            scene.scene.cards.forEachIndexed { i, card ->
                val match = scene.scene.highlights.getOrElse(i) { false }
                PlayingCardView(
                    card,
                    w,
                    h,
                    size = CardSize.SMALL,
                    modifier = Modifier
                        .alpha(if (match) 1f else 0.7f)
                        .then(
                            if (match) Modifier.border(1.dp, if (winner) Noir.SceneMatch else Noir.SceneLoserOutline, RoundedCornerShape(6.dp)) else Modifier,
                        ),
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        HorizontalDivider(color = Color(0x66345044))
        Spacer(Modifier.height(8.dp))
        Text(scene.footerText, style = NoirType.style(12.sp, color = if (winner) Noir.GoldPale else Noir.SceneLoser))
    }
}
