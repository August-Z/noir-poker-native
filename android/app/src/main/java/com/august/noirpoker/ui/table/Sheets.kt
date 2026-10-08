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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.august.noirpoker.core.formatChips
import com.august.noirpoker.core.review.HeroReviewAnalysis
import com.august.noirpoker.core.review.ReviewStatus as StepStatus
import com.august.noirpoker.core.session.ReviewState
import com.august.noirpoker.core.session.ReviewStatus
import com.august.noirpoker.ui.UiCopy
import com.august.noirpoker.ui.theme.LocalNoirMetrics
import com.august.noirpoker.ui.theme.Noir
import com.august.noirpoker.ui.theme.NoirType

/**
 * The NOIR modal sheet (the reference's dialogs): eyebrow, close button, a
 * scrolling body, and an optional footer pinned below it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NoirSheet(
    eyebrow: String,
    onDismiss: () -> Unit,
    eyebrowColor: Color = Noir.TextEyebrow,
    maxWidth: androidx.compose.ui.unit.Dp = 640.dp,
    footer: (@Composable ColumnScope.() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val metrics = LocalNoirMetrics.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        sheetMaxWidth = maxWidth,
        containerColor = Noir.DialogBg,
        contentColor = Noir.Text,
        scrimColor = Color(0xD905090E),
        shape = RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp),
    ) {
        val pad = if (metrics.compact) 22.dp else 28.dp
        Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = pad), verticalAlignment = Alignment.CenterVertically) {
                Text(eyebrow, style = NoirType.style(if (metrics.compact) 10.sp else 12.sp, FontWeight.SemiBold, eyebrowColor, if (metrics.compact) 2.sp else 3.sp), modifier = Modifier.weight(1f))
                CloseButton(onDismiss)
            }
            Column(
                Modifier
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = pad, vertical = 8.dp),
                content = content,
            )
            if (footer != null) {
                Column(Modifier.fillMaxWidth().padding(horizontal = pad, vertical = 16.dp), content = footer)
            }
        }
    }
}

@Composable
private fun CloseButton(onClick: () -> Unit) {
    Box(
        Modifier
            .size(48.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = UiCopy.closeA11y },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(32.dp).border(1.dp, Noir.Line, CircleShape), contentAlignment = Alignment.Center) {
            Text("×", style = NoirType.style(18.sp, color = Noir.TextDialogBody))
        }
    }
}

@Composable
fun SheetTitle(text: String) {
    val metrics = LocalNoirMetrics.current
    Text(
        text,
        style = NoirType.style(if (metrics.compact) 21.sp else 23.sp, FontWeight.Medium),
        modifier = Modifier.padding(top = 6.dp, bottom = 12.dp).semantics { heading() },
    )
}

@Composable
fun SheetBody(text: String, modifier: Modifier = Modifier) {
    Text(text, style = NoirType.style(14.sp, color = Noir.TextDialogBody).copy(lineHeight = 25.sp), modifier = modifier)
}

@Composable
private fun SheetHeading(text: String) {
    Text(
        text,
        style = NoirType.style(14.sp, FontWeight.Medium),
        modifier = Modifier.padding(top = 18.dp, bottom = 6.dp).semantics { heading() },
    )
}

/** How to Play (the reference rules dialog). */
@Composable
fun RulesSheet(onDismiss: () -> Unit) {
    NoirSheet(
        eyebrow = UiCopy.rulesEyebrow,
        onDismiss = onDismiss,
        footer = { NoirButton(UiCopy.backToTable, onDismiss, Modifier.fillMaxWidth()) },
    ) {
        SheetTitle(UiCopy.rulesTitle)
        SheetBody(UiCopy.rulesIntro)
        Spacer(Modifier.height(12.dp))
        Text(UiCopy.rulesFlow.joinToString("  ·  "), style = NoirType.style(12.sp, color = Noir.Mint))
        Spacer(Modifier.height(14.dp))
        UiCopy.rulesActions.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.padding(bottom = 10.dp)) {
                row.forEach { (title, body) ->
                    Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                        Text(title, style = NoirType.style(14.sp, FontWeight.SemiBold))
                        Text(body, style = NoirType.style(13.sp, color = Noir.TextDialogBody).copy(lineHeight = 20.sp))
                    }
                }
            }
        }
        SheetHeading(UiCopy.rulesPositionHeading)
        UiCopy.rulesPositionBody.forEach { SheetBody(it, Modifier.padding(bottom = 8.dp)) }
        SheetHeading(UiCopy.rulesReplayHeading)
        SheetBody(UiCopy.rulesReplayBody)
        SheetHeading(UiCopy.rulesRanksHeading)
        Text(UiCopy.rulesRanks, style = NoirType.style(13.sp, color = Noir.TextDialogBody).copy(lineHeight = 27.sp))
        Spacer(Modifier.height(14.dp))
        HorizontalDivider(color = Noir.SelectBorder)
        Spacer(Modifier.height(10.dp))
        UiCopy.rulesNotes.forEach {
            Text(it, style = NoirType.style(12.sp, color = Noir.TextSubtle).copy(lineHeight = 19.sp), modifier = Modifier.padding(bottom = 6.dp))
        }
    }
}

/** Start New Session confirmation. */
@Composable
fun ResetSheet(onDismiss: () -> Unit, onConfirm: () -> Unit) {
    NoirSheet(
        eyebrow = UiCopy.resetEyebrow,
        onDismiss = onDismiss,
        footer = {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                NoirButton(UiCopy.resetCancel, onDismiss, Modifier.weight(1f), bg = Color.Transparent, fg = Noir.TextDialogBody, border = Noir.SelectBorder)
                NoirButton(UiCopy.resetConfirm, onConfirm, Modifier.weight(1f))
            }
        },
    ) {
        SheetTitle(UiCopy.resetTitle)
        SheetBody(UiCopy.resetBody)
    }
}

/** Review copy used by this first review sheet (copy catalog section 10). */
private object ReviewSheetCopy {
    const val eyebrow = "HAND REVIEW"
    fun title(hand: Int) = "Hand $hand · Hand Review"
    fun progress(done: Int, total: Int) = "Analyzing decision $done / $total…"
    const val preparing = "Preparing this hand's decision snapshots…"
    const val error = "Analysis didn't finish. You can try again."
    const val retry = "Analyze Again"
    const val analyzing = "Analyzing"
    const val pending = "Pending"
    fun status(s: StepStatus) = when (s) {
        StepStatus.ATTENTION -> "Needs Work"
        StepStatus.CONSIDER -> "Worth Discussing"
        StepStatus.SOUND -> "Well Reasoned"
    }
    fun change(profit: Int) = (if (profit > 0) "+" else "") + formatChips(profit) + " chips"
}

/**
 * A first Hand Review sheet: status, progress, the summary and every step's
 * verdict. The full timeline, routes and simulation views come in a later step.
 */
@Composable
fun ReviewSheet(review: ReviewState, onDismiss: () -> Unit, onRetry: () -> Unit, onSelect: (Int) -> Unit) {
    val input = review.input ?: return
    NoirSheet(
        eyebrow = ReviewSheetCopy.eyebrow,
        eyebrowColor = Noir.ReviewEyebrow,
        onDismiss = onDismiss,
        maxWidth = 980.dp,
        footer = { NoirButton(UiCopy.backToTable, onDismiss, Modifier.fillMaxWidth()) },
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { SheetTitle(ReviewSheetCopy.title(input.hand)) }
            Text(ReviewSheetCopy.change(input.outcome.profit), style = NoirType.style(20.sp, FontWeight.Medium, Color(0xFFE69BAB)))
        }
        val total = input.decisions.size
        val statusText = when (review.status) {
            ReviewStatus.RUNNING -> if (review.progress == 0) ReviewSheetCopy.preparing else ReviewSheetCopy.progress(review.progress, total)
            ReviewStatus.ERROR -> ReviewSheetCopy.error
            else -> null
        }
        val analysis = review.analysis as? HeroReviewAnalysis
        val boxShape = RoundedCornerShape(10.dp)
        Column(
            Modifier
                .fillMaxWidth()
                .background(Color(0x77362E47), boxShape)
                .border(1.dp, Color(0xFF5C4C71), boxShape)
                .padding(16.dp)
                .semantics { liveRegion = LiveRegionMode.Polite },
        ) {
            if (analysis != null) {
                Text(analysis.summary.title, style = NoirType.style(15.sp, FontWeight.Medium, Color(0xFFEADBF9)))
                Spacer(Modifier.height(6.dp))
                SheetBody(analysis.summary.summary)
            }
            if (statusText != null) SheetBody(statusText)
            if (review.status == ReviewStatus.ERROR) {
                Text(
                    ReviewSheetCopy.retry,
                    style = NoirType.style(14.sp, FontWeight.Medium, Noir.ReviewText),
                    modifier = Modifier.clickable(role = Role.Button, onClick = onRetry).padding(vertical = 12.dp),
                )
            }
        }
        Spacer(Modifier.height(14.dp))
        input.decisions.forEachIndexed { i, d ->
            val step = analysis?.summary?.steps?.getOrNull(i)
            val selected = i == review.selected
            val shape = RoundedCornerShape(9.dp)
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(bottom = 8.dp)
                    .background(if (selected) Color(0x5541374E) else Color.Transparent, shape)
                    .border(1.dp, if (selected) Color(0xFFA690C1) else Noir.SelectBorder, shape)
                    .clickable(role = Role.Tab) { onSelect(i) }
                    .padding(12.dp)
                    .semantics(mergeDescendants = true) {},
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("${i + 1}", style = NoirType.style(12.sp, FontWeight.SemiBold, Noir.ReviewText), modifier = Modifier.width(22.dp))
                    Text(
                        "${com.august.noirpoker.core.session.SessionCopy.street(d.street) ?: ""} · ${d.position}",
                        style = NoirType.style(12.sp, color = Noir.TextSubtle),
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        when {
                            step != null -> ReviewSheetCopy.status(step.status)
                            review.status == ReviewStatus.RUNNING -> ReviewSheetCopy.analyzing
                            else -> ReviewSheetCopy.pending
                        },
                        style = NoirType.style(11.sp, FontWeight.Medium, Noir.TextStrip),
                    )
                }
                if (step != null && selected) {
                    Spacer(Modifier.height(8.dp))
                    Text(step.title, style = NoirType.style(14.sp, FontWeight.Medium))
                    Spacer(Modifier.height(4.dp))
                    SheetBody(step.reason)
                    Spacer(Modifier.height(4.dp))
                    Text(step.recommendation, style = NoirType.style(13.sp, color = Noir.Mint))
                }
            }
        }
    }
}

/** Pot Breakdown: live pots with eligibility and contributions, or the settlement per pot. */
@Composable
fun PotSheet(details: com.august.noirpoker.core.session.PotDetailsState, onDismiss: () -> Unit, onToggle: (Int) -> Unit) {
    NoirSheet(
        eyebrow = "POT BREAKDOWN",
        onDismiss = onDismiss,
        maxWidth = 560.dp,
        footer = { NoirButton(UiCopy.backToTable, onDismiss, Modifier.fillMaxWidth()) },
    ) {
        SheetTitle(details.title)
        details.note?.let {
            Text(it, style = NoirType.style(12.sp, color = Noir.TextSubtle).copy(lineHeight = 19.sp))
            Spacer(Modifier.height(12.dp))
        }
        details.pots.forEach { pot ->
            val shape = RoundedCornerShape(10.dp)
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(bottom = 12.dp)
                    .background(if (pot.settled) Color(0xFF102522) else Color(0x44112B24), shape)
                    .border(1.dp, if (pot.settled) Color(0xFF33564A) else Color(0xFF365149), shape)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(pot.label, style = NoirType.style(14.sp, FontWeight.Medium), modifier = Modifier.weight(1f).semantics { heading() })
                    Text(pot.amountText, style = NoirType.tabular(NoirType.style(22.sp, FontWeight.SemiBold)))
                    Spacer(Modifier.width(4.dp))
                    Text(pot.unit, style = NoirType.style(11.sp, color = Noir.TextSubtle))
                }
                if (pot.settled) {
                    pot.splitTotalText?.let { Text(it, style = NoirType.style(12.sp, color = Noir.TextSubtle)) }
                    pot.awards.forEach { award ->
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.semantics(mergeDescendants = true) {}) {
                            com.august.noirpoker.ui.components.CrownIcon(17.dp)
                            Spacer(Modifier.width(8.dp))
                            Column(Modifier.weight(1f)) {
                                Text(award.name + award.winnerText, style = NoirType.style(16.sp, FontWeight.SemiBold))
                                Text(award.label, style = NoirType.style(12.sp, color = Noir.TextSubtle))
                            }
                            Text(award.amountText, style = NoirType.tabular(NoirType.style(22.sp, FontWeight.SemiBold, Noir.Mint)))
                            Spacer(Modifier.width(4.dp))
                            Text(award.unit, style = NoirType.style(11.sp, color = Noir.TextSubtle))
                        }
                    }
                    Disclosure(pot.distributionSummary, pot.expanded, { onToggle(pot.index) }) {
                        Text(pot.distributionEligibility, style = NoirType.style(12.sp, color = Noir.TextDialogBody))
                        Text(pot.contributionsHeading, style = NoirType.style(12.sp, FontWeight.Medium))
                        pot.contributions.forEach { ContributionRow(it) }
                        pot.oddChipNote?.let { Text(it, style = NoirType.style(12.sp, color = Noir.TextSubtle)) }
                    }
                } else {
                    Text(
                        pot.eligibilityLabel + pot.playerCountText,
                        style = NoirType.style(12.sp, color = if (pot.heroEligible) Noir.Mint else Color(0xFF9AAFBC)),
                        modifier = Modifier
                            .background(if (pot.heroEligible) Color(0x77235448) else Color(0xFF26333E), RoundedCornerShape(5.dp))
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                    )
                    Text(pot.participantsText, style = NoirType.style(12.sp, color = Noir.TextDialogBody))
                    Disclosure(pot.contributionsSummary, pot.expanded, { onToggle(pot.index) }) {
                        pot.contributions.forEach { ContributionRow(it) }
                    }
                }
            }
        }
        details.refunds.forEach { refund ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(bottom = 8.dp)
                    .background(Color(0x8825303C), RoundedCornerShape(8.dp))
                    .border(1.dp, Color(0xFF455462), RoundedCornerShape(8.dp))
                    .padding(12.dp)
                    .semantics(mergeDescendants = true) { refund.a11y?.let { contentDescription = it } },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(refund.text, style = NoirType.style(13.sp, color = Noir.TextDialogBody), modifier = Modifier.weight(1f))
                Text(refund.amountText, style = NoirType.tabular(NoirType.style(14.sp, FontWeight.SemiBold)))
            }
        }
    }
}

@Composable
private fun ContributionRow(row: com.august.noirpoker.core.session.PotContributionRow) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}) {
        Text(row.text, style = NoirType.style(12.sp, color = Noir.TextDialogBody), modifier = Modifier.weight(1f))
        Text(row.amountText, style = NoirType.tabular(NoirType.style(12.sp, FontWeight.SemiBold, Noir.SeatActionAmount)))
    }
}

@Composable
private fun Disclosure(summary: String, expanded: Boolean, onToggle: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            Modifier
                .heightIn(min = 44.dp)
                .clickable(role = Role.Button, onClick = onToggle)
                .semantics { stateDescription = if (expanded) "Expanded" else "Collapsed" },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(if (expanded) "▾" else "▸", style = NoirType.style(12.sp, color = Noir.Mint))
            Spacer(Modifier.width(6.dp))
            Text(summary, style = NoirType.style(13.sp, color = Noir.Mint))
        }
        if (expanded) content()
    }
}
