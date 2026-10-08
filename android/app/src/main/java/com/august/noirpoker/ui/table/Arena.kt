package com.august.noirpoker.ui.table

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.PointMode
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.august.noirpoker.core.MoodKind
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.session.ActionChip
import com.august.noirpoker.core.session.HeroState
import com.august.noirpoker.core.session.SeatState
import com.august.noirpoker.core.session.SessionEffect
import com.august.noirpoker.core.session.TableRenderState
import kotlinx.coroutines.flow.Flow
import com.august.noirpoker.ui.UiCopy
import com.august.noirpoker.ui.components.CardBackView
import com.august.noirpoker.ui.components.CardEntrance
import com.august.noirpoker.ui.components.CardSize
import com.august.noirpoker.ui.components.ChipIcon
import com.august.noirpoker.ui.components.EmptySlotView
import com.august.noirpoker.ui.components.EyeIcon
import com.august.noirpoker.ui.components.PlayingCardView
import com.august.noirpoker.ui.components.PositionBadgeView
import com.august.noirpoker.ui.components.RankBadgeView
import com.august.noirpoker.ui.components.StyleChipView
import com.august.noirpoker.ui.components.cardEntrance
import com.august.noirpoker.ui.theme.LocalNoirMetrics
import com.august.noirpoker.ui.theme.LocalReducedMotion
import com.august.noirpoker.ui.theme.Noir
import com.august.noirpoker.ui.theme.NoirMetrics
import com.august.noirpoker.ui.theme.NoirType

/** Arena geometry for one table state (visual spec section 5). */
data class ArenaGeometry(
    val height: Dp,
    val railTop: Dp,
    val railSide: Float,
    val railBottom: Dp,
    val centerTop: Float,
)

fun arenaGeometry(count: Int, done: Boolean, longNames: Boolean, metrics: NoirMetrics, fontScale: Float): ArenaGeometry {
    val dense = count >= 8
    val base = if (metrics.compact) {
        when {
            count <= 6 -> if (done) 600 else 490
            count == 7 -> 620
            longNames && count == 8 -> 800
            longNames && count == 9 -> 900
            else -> 720
        }
    } else {
        when {
            count <= 6 -> if (done) 620 else 550
            count == 7 -> 620
            else -> 690
        }
    }
    // Large text grows the plates; give the arena room instead of overlapping seats.
    val grow = 1f + (fontScale - 1f).coerceIn(0f, 1f) * 0.55f
    val centerTop = when {
        dense -> 0.33f
        count <= 6 && done -> if (metrics.compact) 0.34f else 0.36f
        else -> 0.30f
    }
    return if (metrics.compact) {
        ArenaGeometry((base * grow).dp, if (dense) 56.dp else 58.dp, 0.015f, if (dense) 75.dp else 76.dp, centerTop)
    } else {
        ArenaGeometry((base * grow).dp, if (dense) 56.dp else 57.dp, if (dense) 0.05f else 0.055f, if (dense) 74.dp else 60.dp, centerTop)
    }
}

/** Card sizes for the current density (visual spec section 7.5). */
data class CardMetrics(
    val boardW: Dp,
    val boardH: Dp,
    val boardGap: Dp,
    val heroW: Dp,
    val heroH: Dp,
    val backW: Dp,
    val backH: Dp,
    val smallW: Dp,
    val smallH: Dp,
)

fun cardMetrics(count: Int, metrics: NoirMetrics, arenaWidth: Dp): CardMetrics = if (metrics.compact) {
    val dense = count >= 7
    val (bw, bh) = when {
        dense -> (arenaWidth.value * 0.09f).coerceIn(28f, 37f).dp to (arenaWidth.value * 0.13f).coerceIn(41f, 54f).dp
        metrics.tiny -> 39.dp to 58.dp
        else -> 43.dp to 63.dp
    }
    CardMetrics(bw, bh, if (dense) 4.dp else 5.dp, 55.dp, 79.dp, 25.dp, 36.dp, 33.dp, 46.dp)
} else {
    CardMetrics(55.dp, 78.dp, 8.dp, 63.dp, 91.dp, 29.dp, 41.dp, 38.dp, 53.dp)
}

/**
 * The table arena: rail and felt, opponent seats placed by the session's layout
 * percentages (top-center anchors), the center (pot, board, caption) and the hero.
 */
@Composable
fun Arena(
    state: TableRenderState,
    onTogglePeek: (Int) -> Unit,
    onPotDetails: () -> Unit,
    modifier: Modifier = Modifier,
    effects: Flow<SessionEffect>? = null,
) {
    // The arena is a spatial diagram: its text scales up to 1.3× so seats keep their
    // places; above that the full-size seat list below the table carries the details.
    val outer = androidx.compose.ui.platform.LocalDensity.current
    val fontScale = outer.fontScale.coerceAtMost(ARENA_MAX_FONT_SCALE)
    androidx.compose.runtime.CompositionLocalProvider(
        androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(outer.density, fontScale),
    ) {
        ArenaContent(state, onTogglePeek, onPotDetails, modifier, effects, fontScale)
    }
}

/** Largest text scale used inside the arena. */
const val ARENA_MAX_FONT_SCALE = 1.3f

@Composable
private fun ArenaContent(
    state: TableRenderState,
    onTogglePeek: (Int) -> Unit,
    onPotDetails: () -> Unit,
    modifier: Modifier,
    effects: Flow<SessionEffect>?,
    fontScale: Float,
) {
    val metrics = LocalNoirMetrics.current
    val anchors = remember { ArenaAnchors() }
    val done = state.phase == Phase.DONE
    val geo = arenaGeometry(state.playerCount, done, state.hasFullPlayerNames, metrics, fontScale)
    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .height(geo.height)
            .then(anchors.rootModifier())
            .semantics { contentDescription = UiCopy.tableRegionA11y },
    ) {
        val cards = cardMetrics(state.playerCount, metrics, maxWidth)
        val sideInset = maxWidth * geo.railSide
        Felt(
            Modifier
                .padding(start = sideInset, end = sideInset, top = geo.railTop, bottom = geo.railBottom)
                .fillMaxSize(),
            compact = metrics.compact,
        )
        TableCenter(
            state,
            cards,
            onPotDetails,
            anchors,
            Modifier
                .align(Alignment.TopCenter)
                .offset(y = geo.height * geo.centerTop),
        )
        // Settled 6-max on phones: the two upper side seats move up 20 dp to clear the badges.
        val lift = if (metrics.compact && done && state.playerCount == 6) setOf(2, 4) else emptySet()
        SeatsLayout(state.seats, lift, 20.dp, Modifier.fillMaxSize()) { seat ->
            SeatView(seat, state, cards, onTogglePeek, anchors)
        }
        // The hero sits above the seats (z 4 over z 3), bottom-anchored 20 dp above the arena edge.
        HeroArea(
            state.hero,
            state,
            cards,
            anchors,
            Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 20.dp),
        )
        ChipFlightLayer(effects, anchors)
    }
}

/** Places each seat's top-center at (layoutX %, layoutY %) of the arena, clamped inside it. */
@Composable
private fun SeatsLayout(seats: List<SeatState>, lifted: Set<Int>, lift: Dp, modifier: Modifier, content: @Composable (SeatState) -> Unit) {
    Layout(
        content = { seats.forEach { seat -> Box { content(seat) } } },
        modifier = modifier,
    ) { measurables, constraints ->
        val w = constraints.maxWidth
        val h = constraints.maxHeight
        val maxSeatWidth = (w * 0.34f).toInt().coerceAtLeast(1)
        val placeables = measurables.map { it.measure(Constraints(maxWidth = maxSeatWidth, maxHeight = h)) }
        layout(w, h) {
            placeables.forEachIndexed { i, p ->
                val seat = seats[i]
                val x = (seat.layoutX / 100.0 * w - p.width / 2.0).toInt().coerceIn(0, (w - p.width).coerceAtLeast(0))
                val dy = if (seat.id in lifted) lift.roundToPx() else 0
                val y = (seat.layoutY / 100.0 * h - dy).toInt().coerceIn(0, (h - p.height).coerceAtLeast(0))
                p.place(x, y, zIndex = 3f)
            }
        }
    }
}

@Composable
private fun Felt(modifier: Modifier, compact: Boolean) {
    Box(
        modifier
            .shadow(18.dp, androidx.compose.foundation.shape.GenericShape { size, _ -> addOval(androidx.compose.ui.geometry.Rect(Offset.Zero, size)) })
            .drawBehind {
                // Rail.
                drawOval(Brush.linearGradient(listOf(Noir.RailA, Noir.RailB, Noir.RailC), Offset.Zero, Offset(size.width, size.height)))
                drawOval(Noir.RailBorder, style = Stroke(1.dp.toPx()))
                val pad = (if (compact) 9.dp else 13.dp).toPx()
                val inner = Size(size.width - 2 * pad, size.height - 2 * pad)
                val tl = Offset(pad, pad)
                // Felt: an elliptical radial gradient (circular gradient scaled vertically).
                val ratio = inner.height / inner.width
                scale(1f, ratio, pivot = Offset(size.width / 2f, tl.y + inner.height * 0.6f)) {
                    drawOval(
                        Brush.radialGradient(
                            0f to Noir.FeltLight,
                            0.68f to Noir.Felt,
                            1f to Noir.FeltDark,
                            center = Offset(size.width / 2f, tl.y + inner.height * 0.6f),
                            radius = inner.width * 0.62f,
                        ),
                        topLeft = Offset(tl.x, tl.y + inner.height * 0.6f - (inner.height * 0.6f) / ratio),
                        size = Size(inner.width, inner.height / ratio),
                    )
                }
                drawOval(Noir.FeltBorder, tl, inner, style = Stroke(2.dp.toPx()))
                val o = (if (compact) 7.dp else 10.dp).toPx()
                drawOval(Noir.FeltOutline, Offset(tl.x + o, tl.y + o), Size(inner.width - 2 * o, inner.height - 2 * o), style = Stroke(1.dp.toPx()))
            },
    ) {
        // Dot texture, clipped to the felt ellipse; the points are built once per size.
        val pad = if (compact) 9.dp else 13.dp
        Box(
            Modifier
                .padding(pad)
                .fillMaxSize()
                .graphicsLayer {
                    clip = true
                    shape = androidx.compose.foundation.shape.GenericShape { s, _ -> addOval(androidx.compose.ui.geometry.Rect(Offset.Zero, s)) }
                }
                .drawWithCache {
                    val step = 4.dp.toPx()
                    val points = ArrayList<Offset>()
                    var y = 0f
                    while (y < size.height) {
                        var x = 0f
                        while (x < size.width) {
                            points.add(Offset(x, y))
                            x += step
                        }
                        y += step
                    }
                    val width = 1.4.dp.toPx()
                    onDrawBehind { drawPoints(points, PointMode.Points, Noir.FeltDot, width, StrokeCap.Round) }
                },
        )
        Column(
            Modifier
                .align(Alignment.TopCenter)
                .padding(top = if (compact) 28.dp else 30.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(UiCopy.watermark, style = NoirType.style(if (compact) 14.sp else 18.sp, FontWeight.Bold, Noir.Watermark, if (compact) 5.sp else 8.sp))
            Spacer(Modifier.height(7.dp))
            Text(UiCopy.watermarkSub, style = NoirType.style(if (compact) 8.sp else 10.sp, color = Noir.Watermark, tracking = if (compact) 2.sp else 3.sp))
        }
    }
}

@Composable
private fun TableCenter(state: TableRenderState, cards: CardMetrics, onPotDetails: () -> Unit, anchors: ArenaAnchors, modifier: Modifier) {
    val metrics = LocalNoirMetrics.current
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            state.potButtonLabel,
            style = NoirType.style(if (metrics.compact) 11.sp else 12.sp, color = Color(0xFF9FBBB1)),
            modifier = Modifier
                .clickable(role = Role.Button, onClick = onPotDetails)
                .testTag("pot-details")
                .semantics { contentDescription = state.potButtonA11y }
                .drawBehind {
                    val y = size.height
                    val dash = 3.dp.toPx()
                    var x = 0f
                    while (x < size.width) {
                        drawLine(Color(0x356EE7C5), Offset(x, y), Offset((x + dash).coerceAtMost(size.width), y), 1.dp.toPx())
                        x += dash * 2
                    }
                }
                .padding(vertical = 2.dp),
        )
        PotAmount(state, if (metrics.compact) 25 else 29, anchors)
        Spacer(Modifier.height(if (metrics.compact) 8.dp else 12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(cards.boardGap)) {
            state.board.forEach { slot ->
                val face = slot.card
                if (face == null) {
                    EmptySlotView(slot.placeholderGlyph, cards.boardW, cards.boardH, a11y = slot.a11y)
                } else {
                    PlayingCardView(
                        face.card,
                        cards.boardW,
                        cards.boardH,
                        best = face.best,
                        modifier = Modifier.cardEntrance(
                            if (face.animate) CardEntrance.FLIP else CardEntrance.NONE,
                            face.delayMs,
                            Triple(state.hand, state.replayAttempt, slot.index.toString() + face.card.key),
                        ),
                    )
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            state.boardCaption,
            style = NoirType.style(if (metrics.compact) 10.sp else 12.sp, color = Color(0xFF89A99C), tracking = if (metrics.compact) 0.sp else 1.sp),
            textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(max = cards.boardW * 5 + cards.boardGap * 4 + 24.dp),
        )
    }
}

@Composable
private fun PotAmount(state: TableRenderState, sizeSp: Int, anchors: ArenaAnchors) {
    val reduced = LocalReducedMotion.current
    val bump = remember { Animatable(0f) }
    // Bump on new community cards (`potPulse`), once per state version.
    LaunchedEffect(state.version) {
        if (state.potPulse && !reduced) {
            bump.snapTo(0f)
            bump.animateTo(1f, keyframes { durationMillis = 400; 1f at 200; 0f at 400 })
        }
    }
    val pulse = bump.value
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.semantics(mergeDescendants = true) {
            liveRegion = LiveRegionMode.Polite
        },
    ) {
        ChipIcon(28.dp, modifier = anchors.anchor(ArenaAnchors.POT))
        Text(
            state.potText,
            style = NoirType.tabular(
                NoirType.style(sizeSp.sp, FontWeight.SemiBold, androidx.compose.ui.graphics.lerp(Noir.Text, Noir.Mint, pulse), 1.sp),
            ),
            modifier = Modifier.scale(1f + 0.08f * pulse),
        )
    }
}

/** The mint turn glow: a pulsing outer shadow for the acting seat or hero (drawn in the layer, no recomposition). */
@Composable
fun Modifier.turnGlow(active: Boolean, shape: androidx.compose.ui.graphics.Shape): Modifier {
    if (!active) return this
    if (LocalReducedMotion.current) return this.shadow(10.dp, shape, ambientColor = Noir.Mint, spotColor = Noir.Mint)
    val t = rememberInfiniteTransition(label = "turn-glow")
    val glow = t.animateFloat(
        initialValue = 8f,
        targetValue = 18f,
        animationSpec = infiniteRepeatable(tween(1000, easing = FastOutSlowInEasing), RepeatMode.Reverse),
        label = "turn-glow-radius",
    )
    return this.graphicsLayer {
        shadowElevation = glow.value * density
        this.shape = shape
        clip = false
        ambientShadowColor = Noir.Mint
        spotShadowColor = Noir.Mint
    }
}

@Composable
private fun SeatView(seat: SeatState, state: TableRenderState, cards: CardMetrics, onTogglePeek: (Int) -> Unit, anchors: ArenaAnchors) {
    val metrics = LocalNoirMetrics.current
    val done = state.phase == Phase.DONE
    val dense = state.playerCount >= 7
    val showAvatar = !metrics.largeText && !metrics.tiny && !(metrics.compact && dense)
    val foldedLive = seat.folded && !done
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.testTag("seat-${seat.id}").alpha(if (foldedLive) 0.4f else 1f),
    ) {
        // Hole cards: backs (rotated ±6° around bottom center) or revealed small faces.
        Box(Modifier.offset(y = if (metrics.compact) 6.dp else 8.dp).padding(horizontal = 4.dp)) {
            if (seat.revealed && seat.cards.isNotEmpty()) {
                // The eye toggle fades shown cards in from 0.2 over 180 ms (focus stays on the toggle).
                val reduced = LocalReducedMotion.current
                val fade = remember(state.hand, state.replayAttempt, seat.id) { Animatable(1f) }
                LaunchedEffect(seat.revealed, seat.peek?.pressed) {
                    if (seat.peek?.pressed == true && !reduced) {
                        fade.snapTo(0.2f)
                        fade.animateTo(1f, tween(180, easing = androidx.compose.animation.core.LinearOutSlowInEasing))
                    }
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(if (metrics.compact) 4.dp else 5.dp),
                    modifier = Modifier.testTag("seat-hand-${seat.id}").graphicsLayer { alpha = fade.value },
                ) {
                    seat.cards.forEach { face ->
                        PlayingCardView(face.card, cards.smallW, cards.smallH, size = CardSize.SMALL, best = face.best)
                    }
                }
            } else if (seat.cardBacks > 0) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(if (metrics.compact) 2.dp else 3.dp),
                    modifier = Modifier
                        .alpha(if (seat.folded) 0.4f else 1f)
                        .semantics(mergeDescendants = true) { contentDescription = seat.cardBackA11y },
                ) {
                    repeat(seat.cardBacks) { i ->
                        CardBackView(
                            cards.backW,
                            cards.backH,
                            Modifier
                                .graphicsLayer {
                                    rotationZ = if (i == 0) -6f else 6f
                                    transformOrigin = TransformOrigin(0.5f, 1f)
                                }
                                .cardEntrance(
                                    if (seat.dealAnimation) CardEntrance.DEAL else CardEntrance.NONE,
                                    seat.cardBackDelaysMs.getOrElse(i) { 0 },
                                    Triple(state.hand, state.replayAttempt, "${seat.id}-$i"),
                                ),
                        )
                    }
                }
            }
        }
        SeatPlate(seat, showAvatar, done, onTogglePeek, anchors.anchor(seat.id))
        seat.badge?.let {
            Spacer(Modifier.height(4.dp))
            RankBadgeView(it, metrics.compact)
        }
        ActionLine(
            seat.action,
            seat.actionA11y,
            winner = seat.isWinner,
            maxWidth = if (done) 106.dp else 140.dp,
        )
    }
}

@Composable
private fun SeatPlate(seat: SeatState, showAvatar: Boolean, done: Boolean, onTogglePeek: (Int) -> Unit, anchor: Modifier) {
    val metrics = LocalNoirMetrics.current
    val shape = RoundedCornerShape(if (metrics.compact) 8.dp else 10.dp)
    val foldedDone = seat.folded && done
    val border = when {
        seat.isWinner -> if (done) Noir.GoldSettled else Noir.Gold
        seat.isActor -> Noir.Mint
        foldedDone -> Noir.PlateFoldedBorder
        else -> Noir.PlateBorder
    }
    Row(
        modifier = anchor
            .turnGlow(seat.isActor && !done, shape)
            .then(if (seat.isWinner) Modifier.shadow(12.dp, shape, ambientColor = Noir.GoldSettled, spotColor = Noir.GoldSettled) else Modifier)
            .background(if (foldedDone) Noir.PlateFoldedBg else Noir.PlateBg, shape)
            .border(1.dp, border, shape)
            .defaultMinSize(minWidth = if (metrics.compact) (if (showAvatar) 84.dp else 78.dp) else 98.dp)
            .padding(horizontal = if (showAvatar) (if (metrics.compact) 7.dp else 9.dp) else 4.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(if (metrics.compact) 4.dp else 7.dp, Alignment.CenterHorizontally),
    ) {
        if (showAvatar) {
            Avatar(seat, if (metrics.compact) 24.dp else 30.dp, Modifier.alpha(if (foldedDone) 0.45f else 1f))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    seat.name,
                    style = NoirType.style(if (metrics.tiny) 11.sp else if (metrics.compact) 12.sp else 13.sp, FontWeight.Medium),
                    modifier = Modifier.alpha(if (foldedDone) 0.45f else 1f),
                    maxLines = 1,
                )
                PositionBadgeView(seat.position, metrics.compact)
            }
            StyleChipView(seat.styleShort, seat.styleA11y, metrics.compact, Modifier.widthIn(max = if (metrics.compact) 72.dp else 120.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(
                    seat.stackText,
                    style = NoirType.tabular(NoirType.style(12.sp, color = Noir.SeatStack)),
                    modifier = Modifier.alpha(if (foldedDone) 0.45f else 1f),
                )
                seat.peek?.let { peek -> PeekButton(peek.pressed, peek.a11y, "seat-peek-${seat.id}") { onTogglePeek(seat.id) } }
            }
        }
    }
}

@Composable
private fun Avatar(seat: SeatState, size: Dp, modifier: Modifier = Modifier) {
    val (bg, fg) = Noir.avatar(seat.id)
    val mood = when (seat.mood) {
        MoodKind.FRUSTRATED, MoodKind.REACTIVE -> Noir.MoodHot
        MoodKind.CAUTIOUS -> Noir.MoodCautious
        MoodKind.CONFIDENT -> Noir.MoodConfident
        MoodKind.STEADY -> null
    }
    Box(
        modifier
            .size(size + 8.dp)
            .semantics { contentDescription = seat.avatarTitle },
        contentAlignment = Alignment.Center,
    ) {
        if (mood != null) Box(Modifier.size(size + 8.dp).border(2.dp, mood, CircleShape))
        Box(Modifier.size(size).background(bg, CircleShape), contentAlignment = Alignment.Center) {
            Text(seat.avatar, style = NoirType.style(if (size < 28.dp) 12.sp else 14.sp, FontWeight.SemiBold, fg))
        }
    }
}

@Composable
private fun PeekButton(pressed: Boolean, a11y: String, tag: String, onClick: () -> Unit) {
    val shape = RoundedCornerShape(4.dp)
    Box(
        Modifier
            .testTag(tag)
            .size(22.dp)
            .background(if (pressed) Noir.PeekPressedBg else Color.Transparent, shape)
            .border(1.dp, if (pressed) Noir.PeekPressedBorder else Noir.PeekBorder, shape)
            .clickable(role = Role.Switch, onClick = onClick)
            .semantics {
                contentDescription = a11y
                selected = pressed
            },
        contentAlignment = Alignment.Center,
    ) {
        EyeIcon(15.dp, if (pressed) Noir.Mint else Noir.SeatActionLabel, crossed = pressed)
    }
}

/** The last-action line under a plate or the hero: label + amount, or blinking `Thinking`. */
@Composable
fun ActionLine(chip: ActionChip?, a11y: String, winner: Boolean, maxWidth: Dp, modifier: Modifier = Modifier) {
    val metrics = LocalNoirMetrics.current
    val size = if (metrics.tiny) 10.sp else if (metrics.compact) 11.sp else 12.sp
    Box(
        modifier
            .defaultMinSize(minHeight = 25.dp)
            .widthIn(max = maxWidth)
            .padding(top = 4.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = a11y
                if (chip != null) stateDescription = listOfNotNull(chip.label, chip.amountText, chip.meaning).joinToString(", ")
            },
        contentAlignment = Alignment.TopCenter,
    ) {
        if (chip == null) return@Box
        if (chip.isDeciding) {
            ThinkingText(chip.label, size)
            return@Box
        }
        val labelColor = if (winner) Noir.GoldText else Noir.SeatActionLabel
        val amountColor = if (winner) Color(0xFFE0C885) else Noir.SeatActionAmount
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(chip.label, style = NoirType.style(size, color = labelColor), textAlign = TextAlign.Center)
            chip.amountText?.let {
                Text(it, style = NoirType.tabular(NoirType.style(size, FontWeight.SemiBold, amountColor)))
            }
        }
    }
}

@Composable
private fun ThinkingText(label: String, size: androidx.compose.ui.unit.TextUnit) {
    val reduced = LocalReducedMotion.current
    val style = NoirType.style(size, FontWeight.Medium, Noir.Mint)
    if (reduced) {
        Text(label, style = style)
        return
    }
    val t = rememberInfiniteTransition(label = "thinking")
    val a = t.animateFloat(1f, 0.3f, infiniteRepeatable(tween(600), RepeatMode.Reverse), label = "thinking-alpha")
    Text(label, style = style, modifier = Modifier.graphicsLayer { alpha = a.value })
}

@Composable
private fun HeroArea(hero: HeroState, state: TableRenderState, cards: CardMetrics, anchors: ArenaAnchors, modifier: Modifier) {
    val metrics = LocalNoirMetrics.current
    val done = state.phase == Phase.DONE
    Column(modifier.widthIn(max = 320.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Bottom,
            modifier = Modifier.defaultMinSize(minHeight = if (metrics.compact) 79.dp else 94.dp),
        ) {
            hero.cards.forEachIndexed { i, face ->
                PlayingCardView(
                    face.card,
                    cards.heroW,
                    cards.heroH,
                    best = face.best,
                    dimmed = hero.folded,
                    modifier = Modifier
                        .rotate(if (i == 0) -4f else 4f)
                        .cardEntrance(
                            if (face.animate) CardEntrance.DEAL else CardEntrance.NONE,
                            face.delayMs,
                            Triple(state.hand, state.replayAttempt, "hero-$i"),
                        ),
                )
            }
        }
        hero.rankBadge?.let {
            Spacer(Modifier.height(6.dp))
            RankBadgeView(it, metrics.compact, Modifier.testTag("hero-hand-rank"))
        }
        Spacer(Modifier.height(6.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val avatarSize = if (metrics.compact) 30.dp else 36.dp
            val shape = CircleShape
            Box(
                anchors.anchor(0)
                    .turnGlow(hero.isActive && !done, shape)
                    .size(avatarSize)
                    .background(Color(0xFF18372F), shape)
                    .border(1.dp, Noir.Mint, shape),
                contentAlignment = Alignment.Center,
            ) {
                Text(UiCopy.heroAvatar, style = NoirType.style(if (metrics.compact) 8.sp else 9.sp, FontWeight.Bold, Noir.Mint))
            }
            Column {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(hero.name, style = NoirType.style(if (metrics.compact) 12.sp else 14.sp, FontWeight.Medium))
                    PositionBadgeView(hero.position, metrics.compact)
                }
                Text(hero.stackText, style = NoirType.tabular(NoirType.style(if (metrics.compact) 12.sp else 14.sp, color = Color(0xFF99BAAE))))
            }
            val turn = hero.turnText
            if (turn != null && !metrics.tiny) {
                val active = hero.isActive
                Text(
                    turn,
                    style = NoirType.style(if (metrics.compact) 10.sp else 12.sp, color = if (active) Noir.Mint else Noir.TextSubtle),
                    modifier = Modifier
                        .testTag("hero-turn")
                        .background(if (active) Color(0x226EE7C5) else Color(0x22FFFFFF), RoundedCornerShape(5.dp))
                        .border(1.dp, if (active) Color(0x556EE7C5) else Color(0x33FFFFFF), RoundedCornerShape(5.dp))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                        .semantics { liveRegion = LiveRegionMode.Polite },
                )
            }
        }
        ActionLine(hero.lastAction, hero.lastActionA11y, winner = false, maxWidth = 200.dp, modifier = Modifier.testTag("hero-last-action"))
    }
}

/** Section heading semantics helper. */
fun Modifier.headingSemantics(): Modifier = semantics { heading() }

/**
 * Large-text companion to the arena (font scale above [ARENA_MAX_FONT_SCALE]):
 * every opponent as a full-size row with position, style, stack, last action,
 * hand badge and the reveal toggle, so nothing on the scaled-down diagram is
 * only readable there.
 */
@Composable
fun SeatList(state: TableRenderState, onTogglePeek: (Int) -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        state.seats.forEach { seat ->
            val shape = RoundedCornerShape(8.dp)
            Row(
                Modifier
                    .fillMaxWidth()
                    .alpha(if (seat.folded && state.phase != Phase.DONE) 0.6f else 1f)
                    .background(Noir.PlateBg, shape)
                    .border(1.dp, if (seat.isWinner) Noir.GoldSettled else if (seat.isActor) Noir.Mint else Noir.PlateBorder, shape)
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(
                    Modifier
                        .weight(1f)
                        .semantics(mergeDescendants = true) {},
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(seat.name, style = NoirType.style(14.sp, FontWeight.Medium))
                        PositionBadgeView(seat.position, compact = false)
                    }
                    Text("${seat.styleShort} · ${seat.stackText}", style = NoirType.tabular(NoirType.style(13.sp, color = Noir.SeatStack)))
                    val chip = seat.action
                    Text(
                        listOfNotNull(chip.label, chip.amountText).joinToString(" "),
                        style = NoirType.style(13.sp, color = if (chip.isDeciding) Noir.Mint else if (seat.isWinner) Noir.GoldText else Noir.SeatActionAmount),
                    )
                    seat.badge?.let { RankBadgeView(it, compact = false) }
                }
                seat.peek?.let { peek ->
                    Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) {
                        PeekButton(peek.pressed, peek.a11y, "seat-list-peek-${seat.id}") { onTogglePeek(seat.id) }
                    }
                }
            }
        }
    }
}
