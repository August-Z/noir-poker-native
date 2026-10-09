package com.august.noirpoker.ui.table

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.august.noirpoker.core.EmotionMode
import com.august.noirpoker.core.PROFILE_AXES
import com.august.noirpoker.core.session.OpponentsDialogState
import com.august.noirpoker.core.session.ProfileCardState
import com.august.noirpoker.core.session.RosterRowState
import com.august.noirpoker.ui.UiCopy
import com.august.noirpoker.ui.theme.Noir
import com.august.noirpoker.ui.theme.NoirType

/** Commands of the Opponent Styles draft. */
interface OpponentsCallbacks {
    fun preview(id: String)
    fun assign(seat: Int, profile: String)
    fun emotion(mode: EmotionMode)
    fun mix()
    fun save()
    fun discard()
}

/**
 * Opponent Styles (OPPONENT LAB): archetype cards and detail, per-seat
 * assignment for all eight opponents, emotion intensity, the comparison table,
 * and Save. Dismissing the sheet discards the draft, as closing the reference
 * dialog does.
 */
@Composable
fun OpponentsSheet(dialog: OpponentsDialogState, callbacks: OpponentsCallbacks) {
    NoirSheet(
        eyebrow = UiCopy.oppEyebrow,
        onDismiss = callbacks::discard,
        maxWidth = 970.dp,
        closeA11y = UiCopy.oppCloseA11y,
        footer = {
            Box(Modifier.fillMaxWidth().height(1.dp).background(Color(0xFF354B49)))
            Spacer(Modifier.height(12.dp))
            Text(dialog.saveNote, style = NoirType.style(12.sp, color = Noir.TextDialogBody).copy(lineHeight = 19.sp))
            Spacer(Modifier.height(12.dp))
            NoirButton(UiCopy.oppSaveButton, callbacks::save, Modifier.fillMaxWidth().testTag("save-opponents"))
        },
    ) {
        SheetTitle(UiCopy.oppTitle)
        SheetBody(UiCopy.oppIntro)
        Spacer(Modifier.height(18.dp))
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val wide = maxWidth >= 720.dp
            val narrow = maxWidth < 380.dp
            if (wide) {
                Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                    Column(Modifier.weight(1.25f), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        ProfileResearch(dialog, callbacks, columns = 3)
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        Roster(dialog, callbacks, columns = 1)
                    }
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    ProfileResearch(dialog, callbacks, columns = if (narrow) 2 else 3)
                    Roster(dialog, callbacks, columns = if (narrow) 1 else 2)
                }
            }
        }
        Spacer(Modifier.height(14.dp))
        Comparison(dialog)
    }
}

@Composable
private fun ColumnScope.ProfileResearch(dialog: OpponentsDialogState, callbacks: OpponentsCallbacks, columns: Int) {
    Column(
        Modifier.semantics { contentDescription = UiCopy.oppResearchA11y },
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        dialog.profileCards.chunked(columns).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.height(androidx.compose.foundation.layout.IntrinsicSize.Max)) {
                row.forEach { ProfileCard(it, Modifier.weight(1f).fillMaxHeight()) { callbacks.preview(it.id) } }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
    ProfileDetail(dialog)
}

@Composable
private fun ProfileCard(card: ProfileCardState, modifier: Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(9.dp)
    Column(
        modifier
            .heightIn(min = 86.dp)
            .background(if (card.selected) Color(0xFF1A3833) else Color(0xFF111A23), shape)
            .border(1.dp, if (card.selected) Color(0xFF73C9AD) else Color(0xFF35434A), shape)
            .clickable(role = Role.RadioButton, onClick = onClick)
            .padding(12.dp)
            .semantics(mergeDescendants = true) { selected = card.selected },
        verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
    ) {
        Text(card.short, style = NoirType.style(15.sp, FontWeight.SemiBold, if (card.selected) Color(0xFF8FE1C5) else Noir.Text))
        Text(card.tag, style = NoirType.style(12.sp, color = Color(0xFF93A6AE)).copy(lineHeight = 18.sp))
    }
}

@Composable
private fun ProfileDetail(dialog: OpponentsDialogState) {
    val detail = dialog.detail
    val profile = detail.profile
    val uri = LocalUriHandler.current
    val shape = RoundedCornerShape(12.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .background(Color(0xFF13282A), shape)
            .border(1.dp, Color(0xFF354B49), shape)
            .padding(17.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(profile.name, style = NoirType.style(17.sp, FontWeight.Medium), modifier = Modifier.weight(1f).semantics { heading() })
            Text(detail.badge, style = NoirType.style(12.sp, color = Color(0xFF86CCB8)))
        }
        Text(profile.description, style = NoirType.style(13.sp, color = Noir.TextDialogBody).copy(lineHeight = 21.sp))
        detail.axes.forEach { axis ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.semantics(mergeDescendants = true) {
                    contentDescription = axis.label
                    progressBarRangeInfo = ProgressBarRangeInfo(axis.value.toFloat(), 0f..100f)
                },
            ) {
                Text(axis.label, style = NoirType.style(12.sp, color = Noir.TextDialogBody), modifier = Modifier.width(100.dp))
                Box(
                    Modifier
                        .weight(1f)
                        .height(12.dp)
                        .background(Color(0xFF223C3B), RoundedCornerShape(8.dp)),
                ) {
                    Box(
                        Modifier
                            .fillMaxWidth(axis.value.coerceIn(0, 100) / 100f)
                            .height(12.dp)
                            .background(Color(0xFF69C7A9), RoundedCornerShape(8.dp)),
                    )
                }
                Text(
                    axis.value.toString(),
                    style = NoirType.tabular(NoirType.style(12.sp, color = Noir.Text)),
                    textAlign = TextAlign.End,
                    modifier = Modifier.width(30.dp),
                )
            }
        }
        Text(detail.sizingText, style = NoirType.style(13.sp, FontWeight.Medium, Color(0xFFDFC98F)))
        Text(profile.evidence, style = NoirType.style(12.sp, color = Noir.TextSubtle).copy(lineHeight = 19.sp))
        profile.sources.forEach { source ->
            Text(
                source.label,
                style = NoirType.style(12.sp, color = Color(0xFF86CCB8)).copy(textDecoration = TextDecoration.Underline),
                modifier = Modifier
                    .heightIn(min = 44.dp)
                    .clickable(role = Role.Button) { runCatching { uri.openUri(source.url) } }
                    .semantics { stateDescription = UiCopy.opensInBrowser }
                    .padding(vertical = 12.dp),
            )
        }
    }
}

@Composable
private fun Roster(dialog: OpponentsDialogState, callbacks: OpponentsCallbacks, columns: Int) {
    Column(Modifier.semantics { contentDescription = UiCopy.oppAssignA11y }, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(UiCopy.oppRosterHeading, style = NoirType.style(15.sp, FontWeight.Medium), modifier = Modifier.weight(1f).semantics { heading() })
            val shape = RoundedCornerShape(7.dp)
            Box(
                Modifier
                    .heightIn(min = 44.dp)
                    .background(Color(0xFF1D3630), shape)
                    .border(1.dp, Color(0xFF52796C), shape)
                    .clickable(role = Role.Button, onClick = callbacks::mix)
                    .testTag("mix-opponents")
                    .padding(horizontal = 14.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(UiCopy.oppMixButton, style = NoirType.style(13.sp, FontWeight.Medium, Color(0xFF9CD7C3)))
            }
        }
        dialog.roster.chunked(columns).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.height(androidx.compose.foundation.layout.IntrinsicSize.Max)) {
                row.forEach { RosterCard(it, callbacks, Modifier.weight(1f).fillMaxHeight()) }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        EmotionBox(dialog, callbacks)
    }
}

@Composable
private fun RosterCard(row: RosterRowState, callbacks: OpponentsCallbacks, modifier: Modifier) {
    val shape = RoundedCornerShape(9.dp)
    val border = Color(0xFF33424B)
    Column(
        modifier
            .background(if (row.offTable) Color(0xFF121A20) else Color(0xFF111B24), shape)
            .then(
                if (row.offTable) {
                    Modifier.drawBehind {
                        drawRoundRect(
                            border,
                            cornerRadius = CornerRadius(9.dp.toPx()),
                            style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))),
                        )
                    }
                } else {
                    Modifier.border(1.dp, border, shape)
                },
            )
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Column(Modifier.semantics(mergeDescendants = true) {}) {
            Text(row.name, style = NoirType.style(15.sp, FontWeight.Medium))
            Text(row.subtitle, style = NoirType.style(12.sp, color = Noir.TextSubtle))
        }
        StyleSelect(row) { callbacks.assign(row.id, it) }
        Text(row.currentStyle, style = NoirType.style(12.sp, color = Noir.TextDialogBody))
        Text(
            row.observed,
            style = NoirType.tabular(NoirType.style(12.sp, color = Noir.TextSubtle)),
            // The explanation is a description, not a state: read it after the figures.
            modifier = Modifier.semantics { contentDescription = "${row.observed}. ${row.observedTitle}" },
        )
        row.moodReason?.let { Text(it, style = NoirType.style(12.sp, color = Color(0xFFD6B887))) }
    }
}

@Composable
private fun StyleSelect(row: RosterRowState, onSelect: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val current = row.options.firstOrNull { it.value == row.assignment }?.label ?: row.assignment
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 44.dp)
                .background(Noir.SelectBg, RoundedCornerShape(6.dp))
                .border(1.dp, Noir.SelectBorder, RoundedCornerShape(6.dp))
                .clickable(role = Role.DropdownList) { open = true }
                .testTag("bot-seat-${row.id}")
                .padding(horizontal = 10.dp)
                .semantics {
                    contentDescription = row.selectA11y
                    stateDescription = current
                },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(current, style = NoirType.style(13.sp, color = Noir.SelectText), modifier = Modifier.weight(1f), maxLines = 2)
            Text("▾", style = NoirType.style(12.sp, color = Noir.SelectText))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.background(Noir.SelectBg)) {
            row.options.forEach { option ->
                DropdownMenuItem(
                    text = {
                        Text(
                            option.label,
                            style = NoirType.style(14.sp, color = if (option.value == row.assignment) Noir.Mint else Noir.SelectText),
                        )
                    },
                    onClick = {
                        open = false
                        onSelect(option.value)
                    },
                )
            }
        }
    }
}

@Composable
private fun EmotionBox(dialog: OpponentsDialogState, callbacks: OpponentsCallbacks) {
    val shape = RoundedCornerShape(10.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .background(Color(0x442A251D), shape)
            .border(1.dp, Color(0xFF554938), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(UiCopy.oppEmotionLabel, style = NoirType.style(13.sp, FontWeight.Medium, Color(0xFFE3C588)))
        Segmented(
            options = dialog.emotionOptions.map { it to it.label },
            selected = dialog.emotionMode,
            a11y = UiCopy.oppEmotionA11y,
            onSelect = callbacks::emotion,
            modifier = Modifier.fillMaxWidth().testTag("emotion-mode"),
        )
        Text(UiCopy.oppEmotionHelp, style = NoirType.style(12.sp, color = Noir.TextDialogBody).copy(lineHeight = 19.sp))
    }
}

@Composable
private fun Comparison(dialog: OpponentsDialogState) {
    var open by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clickable(role = Role.Button) { open = !open }
                .semantics { stateDescription = if (open) UiCopy.expanded else UiCopy.collapsed },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(if (open) "▾" else "▸", style = NoirType.style(12.sp, color = Noir.Mint))
            Spacer(Modifier.width(8.dp))
            Text(UiCopy.oppCompareSummary, style = NoirType.style(13.sp, color = Noir.Mint))
        }
        if (!open) return@Column
        Text(UiCopy.oppCompareCaption, style = NoirType.style(12.sp, FontWeight.Medium, Noir.TextDialogBody))
        val headers = listOf(UiCopy.oppCompareArchetype) + PROFILE_AXES + UiCopy.oppCompareSizing
        val widths: List<Dp> = listOf(108.dp) + PROFILE_AXES.map { 74.dp } + 78.dp
        Column(Modifier.horizontalScroll(rememberScrollState())) {
            Row(Modifier.padding(vertical = 6.dp)) {
                headers.forEachIndexed { i, h ->
                    Text(h, style = NoirType.style(11.sp, FontWeight.Medium, Noir.TextSubtle), modifier = Modifier.width(widths[i]).padding(end = 6.dp))
                }
            }
            dialog.comparison.forEach { row ->
                Box(Modifier.widthIn(min = widths.fold(0.dp) { a, b -> a + b }).height(1.dp).background(Color(0xFF26343B)))
                Row(Modifier.padding(vertical = 8.dp).semantics(mergeDescendants = true) {}) {
                    Text(row.short, style = NoirType.style(12.sp, FontWeight.Medium), modifier = Modifier.width(widths[0]).padding(end = 6.dp))
                    row.axes.forEachIndexed { i, v ->
                        Text(v.toString(), style = NoirType.tabular(NoirType.style(12.sp, color = Noir.TextDialogBody)), modifier = Modifier.width(widths[i + 1]))
                    }
                    Text(row.sizingText, style = NoirType.tabular(NoirType.style(12.sp, color = Color(0xFFDFC98F))), modifier = Modifier.width(widths.last()))
                }
            }
        }
        Text(UiCopy.oppCompareNoteAxes, style = NoirType.style(12.sp, color = Noir.TextSubtle).copy(lineHeight = 19.sp))
        Text(UiCopy.oppCompareNoteStats, style = NoirType.style(12.sp, color = Noir.TextSubtle).copy(lineHeight = 19.sp))
    }
}

/** A NOIR segmented control (difficulty, emotion intensity): radio semantics, ≥44 dp segments. */
@Composable
fun <T> Segmented(
    options: List<Pair<T, String>>,
    selected: T,
    a11y: String,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
    fill: Boolean = true,
) {
    Row(
        modifier
            .border(1.dp, Noir.SelectBorder, RoundedCornerShape(8.dp))
            .padding(3.dp)
            .semantics { contentDescription = a11y },
    ) {
        options.forEach { (value, label) ->
            val on = value == selected
            Box(
                (if (fill) Modifier.weight(1f) else Modifier)
                    .heightIn(min = 44.dp)
                    .widthIn(min = 52.dp)
                    .background(if (on) Color(0xFF1F4A40) else Color.Transparent, RoundedCornerShape(6.dp))
                    .clickable(role = Role.RadioButton) { onSelect(value) }
                    .padding(horizontal = 10.dp)
                    .semantics { this.selected = on },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    label,
                    style = NoirType.style(12.sp, if (on) FontWeight.SemiBold else FontWeight.Normal, if (on) Noir.Mint else Noir.TextStrip),
                    maxLines = 1,
                    softWrap = false,
                )
            }
        }
    }
}
