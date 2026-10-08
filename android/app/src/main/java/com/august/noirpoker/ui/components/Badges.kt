package com.august.noirpoker.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.august.noirpoker.core.session.PositionBadge
import com.august.noirpoker.core.session.RankBadge
import com.august.noirpoker.ui.theme.Noir
import com.august.noirpoker.ui.theme.NoirType

/** Position badge: BTN is the off-white dealer disc, SB and BB have their own tints. */
@Composable
fun PositionBadgeView(badge: PositionBadge, compact: Boolean, modifier: Modifier = Modifier) {
    val (bg, fg) = when (badge.code) {
        "BTN" -> Noir.BtnBg to Noir.BtnText
        "SB" -> Noir.SbBg to Noir.SbText
        "BB" -> Noir.BbBg to Noir.BbText
        else -> Noir.BadgeBg to Noir.BadgeText
    }
    val btn = badge.code == "BTN"
    val shape = if (btn) CircleShape else RoundedCornerShape(4.dp)
    Box(
        modifier
            .background(bg, shape)
            .defaultMinSize(minWidth = if (btn) (if (compact) 25.dp else 28.dp) else 0.dp)
            .padding(horizontal = 5.dp, vertical = 1.dp)
            .semantics { contentDescription = badge.name },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            badge.code,
            style = NoirType.style(if (compact) 10.sp else 11.sp, if (btn) FontWeight.Bold else FontWeight.Normal, fg),
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
    }
}

private val crownPath = PathParser().parsePathString("M2 4 6 7 10 2 14 7 18 4 16 12H4Z").toPath()

/** The crown (viewBox 20×16): a filled crown and a base line. */
fun DrawScope.drawCrown(color: Color) {
    val s = size.width / 20f
    scale(s, s, pivot = Offset.Zero) {
        drawPath(crownPath, color)
        drawLine(color, Offset(4f, 15f), Offset(16f, 15f), strokeWidth = 1.6f, cap = StrokeCap.Round)
    }
}

@Composable
fun CrownIcon(size: Dp, color: Color = Noir.GoldSettled, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size, size * 0.8f)) { drawCrown(color) }
}

/** Hand-rank badge; the winner variant is gold with a crown. */
@Composable
fun RankBadgeView(badge: RankBadge, compact: Boolean, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(5.dp)
    val winner = badge.isWinner
    val semanticsLabel = badge.a11y ?: badge.text
    Row(
        modifier
            .then(if (winner) Modifier.shadow(8.dp, shape, ambientColor = Noir.GoldSettled, spotColor = Noir.GoldSettled) else Modifier)
            .background(if (winner) Noir.GoldBadgeBg else Noir.RankBg, shape)
            .border(1.dp, if (winner) Noir.GoldSettled else Noir.RankBorder, shape)
            .padding(horizontal = 9.dp, vertical = 4.dp)
            .semantics(mergeDescendants = true) { contentDescription = semanticsLabel },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        if (winner) CrownIcon(13.dp)
        Text(
            badge.text,
            style = NoirType.style(if (compact) 11.sp else 12.sp, FontWeight.SemiBold, if (winner) Noir.GoldBadgeText else Noir.RankText),
            textAlign = TextAlign.Center,
        )
    }
}

/** The style label chip on a seat plate (`Balanced`, `ST Wang`). */
@Composable
fun StyleChipView(text: String, a11y: String, compact: Boolean, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(3.dp)
    Box(
        modifier
            .background(Noir.StyleBg, shape)
            .border(1.dp, Noir.StyleBorder, shape)
            .padding(horizontal = 5.dp, vertical = 1.dp)
            .semantics { contentDescription = a11y },
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = NoirType.style(if (compact) 11.sp else 12.sp, color = Noir.StyleText), textAlign = TextAlign.Center)
    }
}

/** A poker chip icon (ring with notches) for the pot. */
@Composable
fun ChipIcon(size: Dp, color: Color = Noir.Mint, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val r = this.size.minDimension / 2f
        val stroke = r * 0.16f
        drawCircle(color.copy(alpha = 0.22f), r * 0.92f)
        drawCircle(color, r * 0.88f, style = Stroke(stroke))
        drawCircle(color, r * 0.45f, style = Stroke(stroke))
        for (i in 0 until 8) {
            val a = Math.toRadians(i * 45.0 + 22.5)
            val dx = kotlin.math.cos(a).toFloat()
            val dy = kotlin.math.sin(a).toFloat()
            drawLine(color, center + Offset(dx * r * 0.45f, dy * r * 0.45f), center + Offset(dx * r * 0.88f, dy * r * 0.88f), stroke * 0.8f)
        }
    }
}

private val eyePath = PathParser().parsePathString("M2 10C4 6 7 5 10 5C13 5 16 6 18 10C16 14 13 15 10 15C7 15 4 14 2 10Z").toPath()

/** The eye icon (viewBox 20×20) for the post-settlement reveal toggle. */
@Composable
fun EyeIcon(size: Dp, color: Color, crossed: Boolean, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val s = this.size.width / 20f
        scale(s, s, pivot = Offset.Zero) {
            drawPath(eyePath, color, style = Stroke(1.4f))
            drawCircle(color, 2.5f, Offset(10f, 10f), style = Stroke(1.4f))
            if (crossed) drawLine(color, Offset(3f, 17f), Offset(17f, 3f), 1.4f, StrokeCap.Round)
        }
    }
}

/** A small mint status dot (live indicator, decision strip). */
@Composable
fun Dot(size: Dp = 5.dp, color: Color = Noir.Mint, modifier: Modifier = Modifier) {
    Box(modifier.size(size).background(color, CircleShape))
}
