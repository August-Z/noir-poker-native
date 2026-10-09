package com.august.noirpoker.ui.table

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.august.noirpoker.core.Difficulty
import com.august.noirpoker.core.session.CoachState
import com.august.noirpoker.core.session.OpponentsSummary
import com.august.noirpoker.core.session.SettingsState
import com.august.noirpoker.ui.UiCopy
import com.august.noirpoker.ui.theme.LocalNoirMetrics
import com.august.noirpoker.ui.theme.Noir
import com.august.noirpoker.ui.theme.NoirType

/** Commands of the Settings sheet; each one goes straight to the session. */
interface SettingsCallbacks {
    fun seatCount(n: Int)
    fun difficulty(d: Difficulty)
    fun toggleHints()
    fun toggleSound()
    fun openOpponents()
    fun close()
}

/**
 * Table settings in one sheet (a native grouping of the reference's surface
 * controls): table size 5–9 (applies next hand), opponent difficulty, opponent
 * styles, table tips and sound. Every value is persisted by the session.
 */
@Composable
fun SettingsSheet(settings: SettingsState, coach: CoachState, opponents: OpponentsSummary, callbacks: SettingsCallbacks) {
    NoirSheet(
        eyebrow = UiCopy.settingsEyebrow,
        onDismiss = callbacks::close,
        maxWidth = 560.dp,
        footer = { NoirButton(UiCopy.backToTable, callbacks::close, Modifier.fillMaxWidth()) },
    ) {
        SheetTitle(UiCopy.settingsTitle)
        Section(UiCopy.playersLabel) {
            Segmented(
                options = settings.seatCountOptions.map { it.value to it.value.toString() },
                selected = settings.requestedSeatCount,
                a11y = UiCopy.playerCountA11y,
                onSelect = callbacks::seatCount,
                modifier = Modifier.fillMaxWidth().testTag("settings-seats"),
            )
            settings.tableChangeNote?.let {
                Text(
                    it,
                    style = NoirType.style(12.sp, color = Noir.GoldNote),
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                )
            }
        }
        Section(UiCopy.difficultyLabel) {
            Segmented(
                options = settings.difficultyOptions.map { it.value to it.label },
                selected = settings.difficulty,
                a11y = UiCopy.difficultyLabel,
                onSelect = callbacks::difficulty,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Section(UiCopy.opponentsButton) {
            RowButton(UiCopy.opponentsButton, opponents.text, if (opponents.changePending) Noir.GoldNote else Noir.TextSubtle, callbacks::openOpponents)
            opponents.changeNote?.let { Text(it, style = NoirType.style(12.sp, color = Noir.GoldNote).copy(lineHeight = 19.sp)) }
        }
        Section(null) {
            ToggleRow(UiCopy.settingsHints, coach.toggleLabel, coach.toggleOn, callbacks::toggleHints, "settings-hints")
            ToggleRow(UiCopy.settingsSound, settings.soundTitle, settings.sound, callbacks::toggleSound, "settings-sound")
        }
    }
}

@Composable
private fun Section(title: String?, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (title != null) {
            Text(title, style = NoirType.style(13.sp, FontWeight.Medium, Noir.TextDialogBody), modifier = Modifier.semantics { heading() })
        }
        content()
    }
}

@Composable
private fun RowButton(label: String, value: String, valueColor: Color, onClick: () -> Unit) {
    val shape = RoundedCornerShape(8.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .background(Noir.SelectBg, shape)
            .border(1.dp, Noir.SelectBorder, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 14.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = label
                stateDescription = value
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = NoirType.style(14.sp, color = Noir.SelectText), modifier = Modifier.weight(1f))
        Text(value, style = NoirType.style(12.sp, color = valueColor))
        Spacer(Modifier.width(8.dp))
        Text("›", style = NoirType.style(16.sp, color = Noir.SelectText))
    }
}

@Composable
private fun ToggleRow(label: String, state: String, on: Boolean, onToggle: () -> Unit, tag: String) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clickable(role = Role.Switch, onClick = onToggle)
            .testTag(tag)
            .semantics(mergeDescendants = true) {
                contentDescription = label
                stateDescription = state
                toggleableState = ToggleableState(on)
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = NoirType.style(14.sp), modifier = Modifier.weight(1f))
        Text(state, style = NoirType.style(12.sp, color = if (on) Noir.Mint else Noir.TextSubtle))
        Spacer(Modifier.width(12.dp))
        Box(
            Modifier
                .size(width = 40.dp, height = 22.dp)
                .background(if (on) Color(0xFF1D4A3E) else Color(0xFF26323C), RoundedCornerShape(11.dp))
                .border(1.dp, if (on) Noir.Mint else Noir.SelectBorder, RoundedCornerShape(11.dp))
                .padding(3.dp),
            contentAlignment = if (on) Alignment.CenterEnd else Alignment.CenterStart,
        ) {
            Box(Modifier.size(16.dp).background(if (on) Noir.Mint else Noir.TextSubtle, CircleShape))
        }
    }
}

/** The header gear that opens the Settings sheet (≥48 dp target). */
@Composable
fun SettingsButton(onClick: () -> Unit) {
    val metrics = LocalNoirMetrics.current
    val visual = if (metrics.compact) 32.dp else 38.dp
    Box(
        Modifier
            .size(48.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .testTag("settings")
            .semantics { contentDescription = UiCopy.settingsTitle },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(visual).border(1.dp, Noir.Line, CircleShape), contentAlignment = Alignment.Center) {
            Canvas(Modifier.size(visual * 0.5f)) {
                val r = size.minDimension / 2
                val stroke = r * 0.16f
                drawCircle(Noir.TextDialogBody, radius = r * 0.62f, style = Stroke(stroke))
                drawCircle(Noir.TextDialogBody, radius = r * 0.22f, style = Stroke(stroke))
                repeat(8) { i ->
                    rotate(i * 45f) {
                        drawLine(Noir.TextDialogBody, Offset(center.x, center.y - r * 0.68f), Offset(center.x, center.y - r * 0.98f), stroke * 1.4f, StrokeCap.Round)
                    }
                }
            }
        }
    }
}
