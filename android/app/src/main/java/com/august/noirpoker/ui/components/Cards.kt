package com.august.noirpoker.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.august.noirpoker.core.Card
import com.august.noirpoker.ui.theme.LocalReducedMotion
import com.august.noirpoker.ui.theme.Noir
import com.august.noirpoker.ui.theme.NoirType

/** Suit vectors from the reference (viewBox 0 0 20 22), by suit index 0 ♠, 1 ♥, 2 ♣, 3 ♦. */
object SuitPaths {
    private val data = listOf(
        "M10 0C7 5 0 8 0 14C0 19 7 21 10 16C13 21 20 19 20 14C20 8 13 5 10 0ZM9 16L6 22H14L11 16Z",
        "M10 22C7 18 0 12 0 6C0 -1 8 -2 10 4C12 -2 20 -1 20 6C20 12 13 18 10 22Z",
        "M10 0C3 0 3 8 6 10C-2 7 -2 19 5 19C7 19 9 18 10 15C11 18 13 19 15 19C22 19 22 7 14 10C17 8 17 0 10 0ZM9 15L6 22H14L11 15Z",
        "M10 0L20 11L10 22L0 11Z",
    )
    private val paths: List<Path> = data.map { PathParser().parsePathString(it).toPath() }

    fun path(suit: Int): Path = paths[suit]

    fun isRed(suit: Int) = suit == 1 || suit == 3
}

/** Draws suit [suit] with its center at [center], [width] wide and `width × 1.1` high. */
fun DrawScope.drawSuit(suit: Int, center: Offset, width: Float, color: Color) {
    val s = width / 20f
    translate(center.x - width / 2f, center.y - width * 0.55f) {
        scale(s, s, pivot = Offset.Zero) { drawPath(SuitPaths.path(suit), color) }
    }
}

private val RANK_NAMES = mapOf(11 to "Jack", 12 to "Queen", 13 to "King", 14 to "Ace")
private val NUMBER_NAMES = listOf("", "", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten")
private val SUIT_NAMES = listOf("spades", "hearts", "clubs", "diamonds")

/** Spoken card name for TalkBack: `Ace of spades`. */
fun Card.spokenName(): String = "${RANK_NAMES[rank] ?: NUMBER_NAMES[rank]} of ${SUIT_NAMES[suit]}"

enum class CardSize { LARGE, SMALL }

private val faceBrush = Brush.linearGradient(
    0f to Noir.CardFaceA,
    0.58f to Noir.CardFaceB,
    1f to Noir.CardFaceC,
    start = Offset(0f, 0f),
    end = Offset(Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY),
)

private val dealEasing = CubicBezierEasing(0.15f, 0.65f, 0.25f, 1f)
private val flipEasing = CubicBezierEasing(0.2f, 0.6f, 0.2f, 1f)

enum class CardEntrance { NONE, DEAL, FLIP }

/**
 * Plays the entrance once per [key] (deal: drop and rotate in; flip: rotate around Y).
 * Under reduced motion the card is shown at rest.
 */
@Composable
fun Modifier.cardEntrance(entrance: CardEntrance, delayMs: Int, key: Any?): Modifier {
    val reduced = LocalReducedMotion.current
    // The entrance is decided when the card first appears under this key; later
    // states (which no longer flag the card as new) do not cut the animation short.
    val play = remember(key) { if (reduced) CardEntrance.NONE else entrance }
    val progress = remember(key) { Animatable(if (play == CardEntrance.NONE) 1f else 0f) }
    LaunchedEffect(key) {
        if (play == CardEntrance.NONE) return@LaunchedEffect
        progress.animateTo(
            1f,
            tween(
                durationMillis = if (play == CardEntrance.DEAL) 600 else 650,
                delayMillis = delayMs,
                easing = if (play == CardEntrance.DEAL) dealEasing else flipEasing,
            ),
        )
    }
    if (play == CardEntrance.NONE) return this
    return graphicsLayer {
        val p = progress.value
        alpha = p
        if (play == CardEntrance.DEAL) {
            translationY = (1f - p) * -36f * density
            rotationZ = (1f - p) * -12f
            val sc = 0.75f + 0.25f * p
            scaleX = sc
            scaleY = sc
        } else {
            rotationY = (1f - p) * 90f
            translationY = (1f - p) * -10f * density
            cameraDistance = 12f * density
        }
    }
}

/** Draws the content through a saturation matrix at [alpha] (the folded hero's cards). */
fun Modifier.desaturated(saturation: Float, alpha: Float): Modifier = drawWithContent {
    val paint = Paint().apply {
        colorFilter = ColorFilter.colorMatrix(ColorMatrix().apply { setToSaturation(saturation) })
        this.alpha = alpha
    }
    drawIntoCanvas { canvas ->
        val pad = 24.dp.toPx()
        canvas.saveLayer(Rect(-pad, -pad, size.width + pad, size.height + pad), paint)
        drawContent()
        canvas.restore()
    }
}

/**
 * A face-up card drawn natively: gradient face, inner rule, rank corners and a
 * vector suit pip (large), or rank plus suit (small).
 */
@Composable
fun PlayingCardView(
    card: Card,
    width: Dp,
    height: Dp,
    modifier: Modifier = Modifier,
    size: CardSize = CardSize.LARGE,
    best: Boolean = false,
    dimmed: Boolean = false,
) {
    val radius = if (size == CardSize.SMALL) 5.dp else if (width < 50.dp) 5.dp else 7.dp
    val shape = RoundedCornerShape(radius)
    val measurer = rememberTextMeasurer()
    val ink = if (SuitPaths.isRed(card.suit)) Noir.CardRed else Noir.CardInk
    val outlined = if (best) {
        Modifier
            .drawBehind {
                val inset = -4.dp.toPx()
                drawRoundRect(
                    color = Noir.Mint,
                    topLeft = Offset(inset, inset),
                    size = Size(this.size.width - 2 * inset, this.size.height - 2 * inset),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(radius.toPx() + 3.dp.toPx()),
                    style = Stroke(2.dp.toPx()),
                )
            }
            .shadow(10.dp, shape, ambientColor = Noir.Mint, spotColor = Noir.Mint)
    } else {
        Modifier.shadow(3.dp, shape)
    }
    Box(
        modifier
            .then(if (dimmed) Modifier.desaturated(saturation = 0.4f, alpha = 0.42f) else Modifier)
            .size(width, height)
            .then(outlined)
            .clip(shape)
            .background(faceBrush)
            .border(1.dp, Noir.CardEdge, shape)
            .semantics { contentDescription = card.spokenName() },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            if (size == CardSize.LARGE) drawLargeFace(card, ink, measurer) else drawSmallFace(card, ink, measurer)
        }
    }
}

private fun DrawScope.drawLargeFace(card: Card, ink: Color, measurer: TextMeasurer) {
    val u = size.width / 64f
    val v = size.height / 92f
    drawRoundRect(
        Noir.CardRule,
        topLeft = Offset(2 * u, 2 * v),
        size = Size(60 * u, 88 * v),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(6 * u),
        style = Stroke(1f),
    )
    val rankStyle = TextStyle(fontFamily = NoirType.family, fontWeight = FontWeight.Bold, color = ink, fontSize = (15 * u / density).sp)
    val layout = measurer.measure(com.august.noirpoker.core.rankText(card.rank), rankStyle)
    // Baseline at (10, 19), centered horizontally.
    val topLeft = Offset(10 * u - layout.size.width / 2f, 19 * v - layout.firstBaseline)
    drawText(layout, topLeft = topLeft)
    rotate(180f, pivot = Offset(32 * u, 46 * v)) { drawText(layout, topLeft = topLeft) }
    drawSuit(card.suit, Offset(32 * u, 46 * v), 29 * u, ink)
}

private fun DrawScope.drawSmallFace(card: Card, ink: Color, measurer: TextMeasurer) {
    val u = size.width / 36f
    val v = size.height / 50f
    val rankStyle = TextStyle(fontFamily = NoirType.family, fontWeight = FontWeight.Bold, color = ink, fontSize = (16 * u / density).sp)
    val layout = measurer.measure(com.august.noirpoker.core.rankText(card.rank), rankStyle)
    drawText(layout, topLeft = Offset(5 * u, 18 * v - layout.firstBaseline))
    drawSuit(card.suit, Offset(20 * u, 33 * v), 17 * u, ink)
}

/** The card back: dark teal with a light diagonal lattice and a pale border. */
@Composable
fun CardBackView(width: Dp, height: Dp, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(4.dp)
    Box(
        modifier
            .size(width, height)
            .shadow(2.dp, shape)
            .clip(shape)
            .background(Noir.BackBase)
            .border(2.dp, Noir.BackBorder, shape),
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val step = 4.dp.toPx()
            val stroke = 1.dp.toPx()
            val span = size.width + size.height
            var d = -size.height
            while (d < span) {
                drawLine(Noir.BackLineB, Offset(d, 0f), Offset(d + size.height, size.height), stroke)
                drawLine(Noir.BackLineA, Offset(d + size.height, 0f), Offset(d, size.height), stroke)
                d += step
            }
        }
    }
}

/** An undealt board slot with its faint suit glyph. */
@Composable
fun EmptySlotView(glyph: String, width: Dp, height: Dp, modifier: Modifier = Modifier, a11y: String) {
    val shape = RoundedCornerShape(if (width < 50.dp) 5.dp else 7.dp)
    val suit = com.august.noirpoker.core.SUITS.indexOf(glyph).coerceAtLeast(0)
    Box(
        modifier
            .size(width, height)
            .clip(shape)
            .background(Noir.SlotBg)
            .border(1.dp, Noir.SlotBorder, shape)
            .semantics { contentDescription = a11y },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(width * 0.45f, height * 0.36f)) {
            drawSuit(suit, center, size.width, Noir.SlotGlyph)
        }
    }
}
