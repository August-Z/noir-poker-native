package com.august.noirpoker.ui.table

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.clickable
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.august.noirpoker.core.session.ActionPanelState
import com.august.noirpoker.ui.components.Dot
import com.august.noirpoker.ui.theme.LocalNoirMetrics
import com.august.noirpoker.ui.theme.Noir
import com.august.noirpoker.ui.theme.NoirType
import kotlin.math.roundToInt

/** Commands the action panel sends to the session. */
interface ActionPanelCallbacks {
    fun fold()
    fun callOrCheck()
    fun raise()
    fun setBet(value: Int)
    fun nudgeBet(steps: Int)
    fun preset(preset: com.august.noirpoker.core.session.BetPreset)
    fun finishHand()
    fun nextHand()
    fun replayHand()
    fun openReview()
}

/** The decision strip under the arena (hidden once the hand is over). */
@Composable
fun DecisionStrip(actions: ActionPanelState, modifier: Modifier = Modifier) {
    if (!actions.decisionStripVisible) return
    val metrics = LocalNoirMetrics.current
    Row(
        modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp)
            .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Dot()
        Text(actions.decisionText, style = NoirType.style(if (metrics.compact) 12.sp else 14.sp, color = Noir.TextStrip))
    }
}

/** Fold / Check or Call / Raise to with the slider and presets, or the between-hand buttons. */
@Composable
fun ActionPanel(actions: ActionPanelState, callbacks: ActionPanelCallbacks, modifier: Modifier = Modifier) {
    val metrics = LocalNoirMetrics.current
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (actions.controlsVisible) {
            if (metrics.compact || metrics.largeText || metrics.narrowPane) {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    BetControls(actions, callbacks, labelWidth = if (metrics.compact) 83.dp else 100.dp)
                    ActionButtons(actions, callbacks)
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(0.4f)) { BetControls(actions, callbacks, labelWidth = 100.dp) }
                    Box(Modifier.weight(0.6f)) { ActionButtons(actions, callbacks) }
                }
            }
        }
        if (actions.finishHandVisible) {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                NoirButton(
                    text = actions.finishHandLabel,
                    onClick = callbacks::finishHand,
                    enabled = actions.finishHandEnabled,
                    bg = Noir.FinishBg,
                    fg = Noir.FinishText,
                    border = Noir.FinishBorder,
                    a11y = actions.finishHandTitle,
                    modifier = (if (metrics.compact) Modifier.fillMaxWidth() else Modifier.width(240.dp)).testTag("continue-deal"),
                    disabledAlpha = 0.6f,
                )
            }
        }
        if (actions.nextHandVisible || actions.replayVisible || actions.reviewVisible) {
            SettledButtons(actions, callbacks)
        }
    }
}

@Composable
private fun BetControls(actions: ActionPanelState, callbacks: ActionPanelCallbacks, labelWidth: Dp) {
    val metrics = LocalNoirMetrics.current
    val min = actions.sliderMin
    val max = actions.sliderMax
    val enabled = actions.raiseEnabled && min != null && max != null && max > min
    val slider: @Composable () -> Unit = {
        NoirSlider(
            value = actions.bet,
            min = min ?: 0,
            max = max ?: 0,
            enabled = enabled,
            a11y = actions.sliderA11y,
            stateText = actions.betText,
            onChange = callbacks::setBet,
            onNudge = callbacks::nudgeBet,
        )
    }
    val amountStyle = NoirType.tabular(NoirType.style(if (metrics.compact) 16.sp else 18.sp, FontWeight.SemiBold))
    if (metrics.largeText || metrics.console) {
        // Large text and the landscape rail: label and amount on one line, the slider full width, presets 2 × 2.
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(actions.sliderLabel, style = NoirType.style(12.sp, color = Noir.TextSliderLabel))
                Text(actions.betText, style = amountStyle)
            }
            slider()
            actions.presets.chunked(2).forEach { pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    pair.forEach { PresetButton(it, callbacks, Modifier.weight(1f)) }
                }
            }
        }
        return
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.width(labelWidth)) {
            Text(actions.sliderLabel, style = NoirType.style(12.sp, color = Noir.TextSliderLabel))
            Text(actions.betText, style = amountStyle)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            slider()
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                actions.presets.forEach { PresetButton(it, callbacks, Modifier.weight(1f)) }
            }
        }
    }
}

/** Min, ½ Pot, Pot, All-In: the session computes and clamps the amount (spoken as the state). */
@Composable
private fun PresetButton(p: com.august.noirpoker.core.session.PresetState, callbacks: ActionPanelCallbacks, modifier: Modifier) {
    val metrics = LocalNoirMetrics.current
    val shape = RoundedCornerShape(4.dp)
    Box(
        modifier
            .testTag("preset-" + p.preset.id)
            .heightIn(min = 36.dp)
            .alpha(if (p.enabled) 1f else 0.46f)
            .background(Noir.PresetBg, shape)
            .border(1.dp, Noir.PresetBorder, shape)
            .clickable(enabled = p.enabled, role = Role.Button) { callbacks.preset(p.preset) }
            .padding(horizontal = 4.dp, vertical = 6.dp)
            .semantics {
                val amount = p.amount
                if (amount != null) stateDescription = com.august.noirpoker.core.formatChips(amount)
            },
        contentAlignment = Alignment.Center,
    ) {
        Text(p.label, style = NoirType.style(if (metrics.compact) 11.sp else 12.sp, color = Noir.TextStrip), maxLines = 1, softWrap = false)
    }
}

@Composable
private fun ActionButtons(actions: ActionPanelState, callbacks: ActionPanelCallbacks) {
    val metrics = LocalNoirMetrics.current
    if (metrics.largeText) {
        // Large text: one full-width button per row, in the same order.
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row { RaiseFoldCall(actions, callbacks, only = 0) }
            Row { RaiseFoldCall(actions, callbacks, only = 1) }
            Row { RaiseFoldCall(actions, callbacks, only = 2) }
        }
        return
    }
    Row(
        horizontalArrangement = Arrangement.spacedBy(if (metrics.compact) 8.dp else 9.dp),
        modifier = Modifier.height(androidx.compose.foundation.layout.IntrinsicSize.Min),
    ) {
        RaiseFoldCall(actions, callbacks, only = null)
    }
}

/** Raise, Fold and Call/Check in the reference order; [only] picks one of them. */
@Composable
private fun RowScope.RaiseFoldCall(actions: ActionPanelState, callbacks: ActionPanelCallbacks, only: Int?) {
    val metrics = LocalNoirMetrics.current
    if (only == null || only == 0) {
        TwoLineButton(
            label = actions.raiseCaption,
            amount = actions.betText,
            a11y = actions.raiseA11y,
            enabled = actions.raiseEnabled,
            bg = Noir.Mint,
            fg = Noir.RaiseText,
            border = Noir.Mint,
            onClick = callbacks::raise,
            tag = "raise",
        )
    }
    if (only == null || only == 1) {
        TwoLineButton(
            label = actions.foldLabel,
            amount = null,
            a11y = actions.foldLabel,
            enabled = actions.foldEnabled,
            bg = Noir.FoldBg,
            fg = Noir.FoldText,
            border = Noir.FoldBorder,
            onClick = callbacks::fold,
            tag = "fold",
            labelSize = if (metrics.compact) 14 else 15,
        )
    }
    if (only == null || only == 2) {
        TwoLineButton(
            label = actions.callLabel,
            amount = actions.callAmountText,
            a11y = actions.callA11y,
            enabled = actions.callEnabled,
            bg = Noir.CallBg,
            fg = Noir.CallText,
            border = Noir.CallBorder,
            onClick = callbacks::callOrCheck,
            tag = "call",
        )
    }
}

@Composable
private fun RowScope.TwoLineButton(
    label: String,
    amount: String?,
    a11y: String,
    enabled: Boolean,
    bg: Color,
    fg: Color,
    border: Color,
    onClick: () -> Unit,
    labelSize: Int = 13,
    tag: String,
) {
    val metrics = LocalNoirMetrics.current
    val shape = RoundedCornerShape(if (metrics.compact) 7.dp else 9.dp)
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Column(
        Modifier
            .weight(1f)
            .testTag(tag)
            .fillMaxHeight()
            .heightIn(min = if (metrics.compact) 62.dp else 69.dp)
            .scale(if (pressed) 0.98f else 1f)
            .alpha(if (enabled) 1f else 0.46f)
            .background(bg, shape)
            .border(1.dp, border, shape)
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 6.dp, vertical = 8.dp)
            .semantics(mergeDescendants = true) { contentDescription = a11y },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            label,
            style = NoirType.style(if (metrics.compact) (labelSize - 1).sp else labelSize.sp, FontWeight.Medium, fg),
            textAlign = TextAlign.Center,
        )
        if (amount != null) {
            Text(amount, style = NoirType.tabular(NoirType.style(if (metrics.tiny) 16.sp else if (metrics.compact) 17.sp else 18.sp, FontWeight.SemiBold, fg)))
        }
    }
}

@Composable
private fun SettledButtons(actions: ActionPanelState, callbacks: ActionPanelCallbacks) {
    val metrics = LocalNoirMetrics.current
    val next: @Composable (Modifier) -> Unit = { m ->
        NoirButton(actions.nextHandLabel, callbacks::nextHand, bg = Noir.Mint, fg = Noir.OnMint, border = Noir.Mint, modifier = m.testTag("next-hand"))
    }
    val replay: @Composable (Modifier) -> Unit = { m ->
        NoirButton(actions.replayLabel, callbacks::replayHand, bg = Noir.ReplayBg, fg = Noir.ReplayText, border = Noir.ReplayBorder, a11y = actions.replayTitle, modifier = m.testTag("replay-hand"))
    }
    val review: @Composable (Modifier) -> Unit = { m ->
        NoirButton(actions.reviewLabel, callbacks::openReview, bg = Noir.ReviewBg, fg = Noir.ReviewText, border = Noir.ReviewBorder, modifier = m.testTag("review-hand"))
    }
    if (metrics.console) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (actions.nextHandVisible) next(Modifier.fillMaxWidth())
            if (actions.replayVisible) replay(Modifier.fillMaxWidth())
            if (actions.reviewVisible) review(Modifier.fillMaxWidth())
        }
    } else if (metrics.compact || metrics.largeText) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (actions.nextHandVisible) next(Modifier.weight(1f))
                if (actions.replayVisible) replay(Modifier.weight(1f))
            }
            if (actions.reviewVisible) review(Modifier.fillMaxWidth())
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally), modifier = Modifier.fillMaxWidth()) {
            if (actions.nextHandVisible) next(Modifier.defaultMinSize(minWidth = 160.dp))
            if (actions.replayVisible) replay(Modifier)
            if (actions.reviewVisible) review(Modifier.defaultMinSize(minWidth = 220.dp))
        }
    }
}

/** A NOIR text button: 8 dp radius, ≥48 dp high. */
@Composable
fun NoirButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    bg: Color = Noir.Mint,
    fg: Color = Noir.OnMint,
    border: Color = bg,
    a11y: String? = null,
    disabledAlpha: Float = 0.46f,
) {
    val shape = RoundedCornerShape(8.dp)
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Box(
        modifier
            .heightIn(min = 48.dp)
            .scale(if (pressed) 0.98f else 1f)
            .alpha(if (enabled) 1f else disabledAlpha)
            .background(bg, shape)
            .border(1.dp, border, shape)
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 12.dp)
            .then(if (a11y != null) Modifier.semantics { stateDescription = a11y } else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = NoirType.style(14.sp, FontWeight.SemiBold, fg), textAlign = TextAlign.Center)
    }
}

/**
 * The raise-to slider: a 5 dp track with a mint fill and a round thumb, 44 dp of
 * touch height. Values go to the session, which snaps them to 25 (exact all-in
 * kept); TalkBack gets the range, set-progress and ±25 actions.
 */
@Composable
fun NoirSlider(
    value: Int,
    min: Int,
    max: Int,
    enabled: Boolean,
    a11y: String,
    stateText: String,
    onChange: (Int) -> Unit,
    onNudge: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val range = (max - min).coerceAtLeast(1)
    val fraction = ((value - min).toFloat() / range).coerceIn(0f, 1f)
    val latest by rememberUpdatedState(Triple(min, range, onChange))
    val thumbRadius = 9.dp
    fun update(x: Float, width: Float, pad: Float) {
        val (lo, span, cb) = latest
        val f = ((x - pad) / (width - 2 * pad).coerceAtLeast(1f)).coerceIn(0f, 1f)
        cb(lo + (f * span).roundToInt())
    }
    Box(
        modifier
            .fillMaxWidth()
            .height(44.dp)
            .alpha(if (enabled) 1f else 0.46f)
            .then(
                if (enabled) {
                    Modifier
                        .pointerInput(Unit) {
                            detectTapGestures { o -> update(o.x, size.width.toFloat(), thumbRadius.toPx()) }
                        }
                        .pointerInput(Unit) {
                            detectHorizontalDragGestures(
                                onDragStart = { o -> update(o.x, size.width.toFloat(), thumbRadius.toPx()) },
                            ) { change, _ ->
                                change.consume()
                                update(change.position.x, size.width.toFloat(), thumbRadius.toPx())
                            }
                        }
                } else {
                    Modifier
                },
            )
            .semantics {
                contentDescription = a11y
                stateDescription = stateText
                progressBarRangeInfo = ProgressBarRangeInfo(value.toFloat(), min.toFloat()..max.coerceAtLeast(min + 1).toFloat())
                if (!enabled) disabled()
                if (enabled) {
                    setProgress { target ->
                        onChange(target.roundToInt())
                        true
                    }
                    customActions = listOf(
                        CustomAccessibilityAction("+25") { onNudge(1); true },
                        CustomAccessibilityAction("−25") { onNudge(-1); true },
                    )
                }
            },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val pad = thumbRadius.toPx()
            val track = 5.dp.toPx()
            val y = size.height / 2f
            val left = pad
            val right = size.width - pad
            val x = left + (right - left) * fraction
            drawRoundRect(Noir.SliderTrack, Offset(left, y - track / 2), Size(right - left, track), CornerRadius(track / 2))
            drawRoundRect(if (enabled) Noir.Mint else Noir.TextSubtle, Offset(left, y - track / 2), Size(x - left, track), CornerRadius(track / 2))
            drawCircle(Noir.Bg.copy(alpha = 0.6f), pad + 1.dp.toPx(), Offset(x, y + 1.dp.toPx()))
            drawCircle(if (enabled) Noir.Mint else Noir.TextSubtle, pad, Offset(x, y))
        }
    }
}
