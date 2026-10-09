package com.august.noirpoker.ui.table

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.august.noirpoker.core.LogType
import com.august.noirpoker.core.session.ActivityEntryState
import com.august.noirpoker.core.session.ActivityState
import com.august.noirpoker.core.session.CoachState
import com.august.noirpoker.core.session.SessionStatsState
import com.august.noirpoker.ui.UiCopy
import com.august.noirpoker.ui.theme.LocalNoirMetrics
import com.august.noirpoker.ui.theme.Noir
import com.august.noirpoker.ui.theme.NoirType

/** A sidebar card: the translucent navy gradient with a 12 dp radius. */
@Composable
fun SideCard(modifier: Modifier = Modifier, coach: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    val metrics = LocalNoirMetrics.current
    val shape = RoundedCornerShape(if (metrics.compact) 10.dp else 12.dp)
    val brush = if (coach) {
        Brush.linearGradient(listOf(Noir.CoachTop, Noir.CoachBottom))
    } else {
        Brush.linearGradient(listOf(Noir.CardTop, Noir.CardBottom))
    }
    Column(
        modifier
            .background(brush, shape)
            .border(1.dp, if (coach) Noir.CoachBorder else Noir.CardBorder, shape)
            .padding(if (metrics.compact) 16.dp else 20.dp),
        content = content,
    )
}

@Composable
private fun CardTitle(title: String, trailing: @Composable () -> Unit = {}) {
    val metrics = LocalNoirMetrics.current
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            title,
            style = NoirType.style(if (metrics.compact) 12.sp else 14.sp, FontWeight.Medium),
            modifier = Modifier
                .weight(1f)
                .semantics { heading() },
        )
        trailing()
    }
}

@Composable
fun SessionCard(stats: SessionStatsState, modifier: Modifier = Modifier) {
    val metrics = LocalNoirMetrics.current
    SideCard(modifier) {
        CardTitle(UiCopy.sessionTitle) {
            Text(UiCopy.sessionSubtitle, style = NoirType.style(11.sp, color = Noir.TextSubtle))
        }
        Spacer(Modifier.height(16.dp))
        Text(UiCopy.sessionStackLabel, style = NoirType.style(12.sp, color = Noir.TextSubtle))
        Row(
            verticalAlignment = Alignment.Bottom,
            modifier = Modifier.semantics(mergeDescendants = true) {},
        ) {
            Text(
                stats.stackText,
                style = NoirType.tabular(NoirType.style(if (metrics.compact) 26.sp else 35.sp, FontWeight.SemiBold, tracking = (-1).sp)),
            )
            Spacer(Modifier.width(8.dp))
            Text(stats.chipsUnit, style = NoirType.style(10.sp, color = Noir.TextSubtle, tracking = 1.5.sp), modifier = Modifier.padding(bottom = 6.dp))
        }
        Text(stats.changeText, style = NoirType.style(12.sp, color = if (stats.negative) Noir.Negative else Noir.Mint))
        Spacer(Modifier.height(16.dp))
        HorizontalDivider(color = Noir.StatsDivider)
        Spacer(Modifier.height(14.dp))
        Row(Modifier.fillMaxWidth()) {
            Stat(stats.hands.toString(), UiCopy.statHands, Modifier.weight(1f).testTag("stat-hands"))
            Stat(stats.wins.toString(), UiCopy.statWins, Modifier.weight(1f))
            Stat(stats.winRateText, UiCopy.statWinRate, Modifier.weight(1f), TextAlign.End)
        }
    }
}

@Composable
private fun Stat(value: String, caption: String, modifier: Modifier, align: TextAlign = TextAlign.Start) {
    Column(
        modifier.semantics(mergeDescendants = true) {},
        horizontalAlignment = if (align == TextAlign.End) Alignment.End else Alignment.Start,
    ) {
        Text(value, style = NoirType.tabular(NoirType.style(18.sp, FontWeight.Medium)))
        Text(caption, style = NoirType.style(10.sp, color = Noir.TextSubtle), textAlign = align)
    }
}

@Composable
fun CoachCard(coach: CoachState, onToggle: () -> Unit, modifier: Modifier = Modifier) {
    val metrics = LocalNoirMetrics.current
    SideCard(modifier, coach = true) {
        CardTitle(UiCopy.coachTitle) {
            val shape = RoundedCornerShape(5.dp)
            Box(
                Modifier
                    .heightIn(min = 32.dp)
                    .background(if (coach.toggleOn) Color(0xFF1D4A3E) else Color(0xFF26323C), shape)
                    .clickable(role = Role.Switch, onClick = onToggle)
                    .padding(horizontal = 10.dp, vertical = 6.dp)
                    .semantics {
                        contentDescription = UiCopy.coachToggleA11y
                        stateDescription = coach.toggleLabel
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text(coach.toggleLabel, style = NoirType.style(12.sp, color = if (coach.toggleOn) Noir.Mint else Noir.TextSubtle))
            }
        }
        if (coach.visible) {
            Spacer(Modifier.height(14.dp))
            Text(coach.stage, style = NoirType.style(12.sp, color = Noir.Mint))
            Spacer(Modifier.height(8.dp))
            Text(
                coach.tip,
                style = NoirType.style(if (metrics.compact) 12.sp else 14.sp, color = Color(0xFFC9D6DD)).copy(lineHeight = if (metrics.compact) 21.sp else 25.sp),
            )
            if (!metrics.compact) {
                Spacer(Modifier.height(14.dp))
                Text("— " + UiCopy.coachFooter, style = NoirType.style(12.sp, color = Noir.TextFootnote))
            }
        }
    }
}

@Composable
fun ActivityCard(activity: ActivityState, modifier: Modifier = Modifier) {
    val metrics = LocalNoirMetrics.current
    SideCard(modifier) {
        CardTitle(UiCopy.activityTitle) {
            Text(activity.badge, style = NoirType.style(11.sp, color = Noir.TextSubtle, tracking = 1.sp))
        }
        Spacer(Modifier.height(14.dp))
        if (activity.entries.isEmpty()) {
            Text(UiCopy.activityEmpty, style = NoirType.style(12.sp, color = Noir.TextSubtle))
            return@SideCard
        }
        // Chronological and complete: no truncation and no inner scroll. Below the
        // two-pane width the list flows into two text columns (oldest first, top to
        // bottom, then the second column), like the reference's CSS columns.
        val gap = if (metrics.compact) 8.dp else 12.dp
        val split = !metrics.twoPane && !metrics.tiny && !metrics.largeText && activity.entries.size > 1
        if (split) {
            val half = (activity.entries.size + 1) / 2
            Row(
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.testTag("activity-list").semantics(mergeDescendants = false) { contentDescription = UiCopy.activityListA11y },
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(gap)) {
                    activity.entries.take(half).forEach { ActivityRow(it) }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(gap)) {
                    activity.entries.drop(half).forEach { ActivityRow(it) }
                }
            }
        } else {
            Column(
                verticalArrangement = Arrangement.spacedBy(gap),
                modifier = Modifier.testTag("activity-list").semantics { contentDescription = UiCopy.activityListA11y },
            ) {
                activity.entries.forEach { ActivityRow(it) }
            }
        }
    }
}

@Composable
private fun ActivityRow(entry: ActivityEntryState) {
    val metrics = LocalNoirMetrics.current
    val color = when {
        entry.isHero -> Noir.LogHero
        entry.type == LogType.RESULT -> Noir.LogResult
        entry.type == LogType.STREET -> Noir.LogStreet
        else -> Noir.LogDefault
    }
    Row(Modifier.testTag("activity-entry").semantics(mergeDescendants = true) {}) {
        Text(
            "${entry.number}.",
            style = NoirType.tabular(NoirType.style(11.sp, color = color.copy(alpha = 0.65f))),
            textAlign = TextAlign.End,
            modifier = Modifier
                .width(24.dp)
                .padding(top = 2.dp),
        )
        Spacer(Modifier.width(8.dp))
        Text(
            buildAnnotatedString {
                entry.segments.forEach { seg ->
                    if (seg.isPersona) withStyle(SpanStyle(color = color.copy(alpha = 0.75f))) { append(seg.text) } else append(seg.text)
                }
            },
            style = NoirType.style(if (metrics.compact) 12.sp else 14.sp, color = color).copy(lineHeight = if (metrics.compact) 19.sp else 22.sp),
        )
    }
}

@Composable
fun SidebarFootnote(modifier: Modifier = Modifier) {
    Row(modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("♠", style = NoirType.style(30.sp, color = Noir.TextFootnote.copy(alpha = 0.5f)))
        Spacer(Modifier.width(14.dp))
        Column {
            Text(UiCopy.footnoteA, style = NoirType.style(12.sp, color = Noir.TextFootnote))
            Text(UiCopy.footnoteB, style = NoirType.style(12.sp, color = Noir.TextFootnote))
        }
    }
}
