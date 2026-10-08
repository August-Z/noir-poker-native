package com.august.noirpoker.ui.table

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.august.noirpoker.core.Difficulty
import com.august.noirpoker.core.session.BetPreset
import com.august.noirpoker.core.session.SettingsState
import com.august.noirpoker.core.session.TableRenderState
import com.august.noirpoker.ui.UiCopy
import com.august.noirpoker.ui.components.drawSuit
import com.august.noirpoker.ui.theme.LocalNoirMetrics
import com.august.noirpoker.ui.theme.Noir
import com.august.noirpoker.ui.theme.NoirMetrics
import com.august.noirpoker.ui.theme.NoirType

/** Width at which the sidebar moves beside the table (the reference's 901 px breakpoint). */
private val TWO_PANE_MIN = 900.dp

/** The table root: header, the table surface, the sidebar cards and the sheets. */
@Composable
fun NoirTableScreen(model: TableModel) {
    val state = model.state
    val session = model.session
    var showRules by rememberSaveable { mutableStateOf(false) }
    var showReset by rememberSaveable { mutableStateOf(false) }
    val callbacks = remember(session) {
        object : ActionPanelCallbacks {
            override fun fold() { session.fold() }
            override fun callOrCheck() { session.callOrCheck() }
            override fun raise() { session.raise() }
            override fun setBet(value: Int) = session.setBet(value)
            override fun nudgeBet(steps: Int) = session.nudgeBet(steps)
            override fun preset(preset: BetPreset) { session.preset(preset) }
            override fun finishHand() { session.finishHand() }
            override fun nextHand() { session.nextHand() }
            override fun replayHand() { session.replayHand() }
            override fun openReview() = session.openReview()
        }
    }
    val opponentCallbacks = remember(session) {
        object : OpponentsCallbacks {
            override fun preview(id: String) = session.previewProfile(id)
            override fun assign(seat: Int, profile: String) = session.assignSeatStyle(seat, profile)
            override fun emotion(mode: com.august.noirpoker.core.EmotionMode) = session.setEmotionMode(mode)
            override fun mix() = session.mixLineup()
            override fun save() { session.saveOpponentSettings() }
            override fun discard() = session.discardOpponentSettings()
        }
    }
    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .background(Noir.Bg)
            .windowInsetsPadding(WindowInsets.safeDrawing),
    ) {
        val fontScale = LocalDensity.current.fontScale
        val width = maxWidth
        val metrics = NoirMetrics(
            compact = maxWidth <= 600.dp,
            twoPane = maxWidth >= TWO_PANE_MIN,
            largeText = fontScale >= 1.3f,
            tiny = maxWidth <= 360.dp,
            narrowPane = maxWidth >= TWO_PANE_MIN && maxWidth < 1150.dp,
        )
        CompositionLocalProvider(LocalNoirMetrics provides metrics) {
            Column(Modifier.fillMaxSize()) {
                Header(state, onToggleSound = session::toggleSound, onRules = { showRules = true })
                if (metrics.twoPane) {
                    Row(
                        Modifier
                            .fillMaxSize()
                            .padding(horizontal = 24.dp),
                        horizontalArrangement = Arrangement.spacedBy(if (width < 1150.dp) 20.dp else 28.dp),
                    ) {
                        Column(
                            Modifier
                                .weight(1f)
                                .verticalScroll(rememberScrollState())
                                .padding(vertical = 24.dp),
                        ) {
                            TableColumn(state, model, callbacks) { showReset = true }
                        }
                        Column(
                            Modifier
                                .width(if (width < 1150.dp) 245.dp else 284.dp)
                                .verticalScroll(rememberScrollState())
                                .padding(vertical = 24.dp),
                            verticalArrangement = Arrangement.spacedBy(18.dp),
                        ) {
                            SidebarCards(state, session::toggleHints, stacked = true)
                        }
                    }
                } else {
                    Column(
                        Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = if (metrics.compact) 12.dp else 24.dp, vertical = 18.dp),
                        verticalArrangement = Arrangement.spacedBy(18.dp),
                    ) {
                        TableColumn(state, model, callbacks) { showReset = true }
                        SidebarCards(state, session::toggleHints, stacked = metrics.tiny || metrics.largeText)
                    }
                }
            }
            if (showRules) RulesSheet { showRules = false }
            if (showReset) {
                ResetSheet(onDismiss = { showReset = false }, onConfirm = {
                    showReset = false
                    session.startNewSession()
                })
            }
            if (state.potDetails.open) {
                PotSheet(state.potDetails, onDismiss = session::closePotDetails, onToggle = session::togglePotDistribution)
            }
            state.opponentsDialog?.let { OpponentsSheet(it, opponentCallbacks) }
            if (state.review.dialogOpen) {
                ReviewSheet(state.review, onDismiss = session::closeReview, onRetry = session::retryReview, onSelect = session::selectReviewStep)
            }
        }
    }
}

@Composable
private fun TableColumn(state: TableRenderState, model: TableModel, callbacks: ActionPanelCallbacks, onReset: () -> Unit) {
    val session = model.session
    val metrics = LocalNoirMetrics.current
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        TableHeading(state)
        val shape = RoundedCornerShape(if (metrics.compact) 14.dp else 18.dp)
        Column(
            Modifier
                .fillMaxWidth()
                .background(
                    Brush.radialGradient(listOf(Noir.SurfaceTop, Noir.SurfaceMid, Noir.SurfaceEdge), radius = 1400f),
                    shape,
                )
                .border(1.dp, Noir.SurfaceBorder, shape)
                .padding(horizontal = if (metrics.compact) 8.dp else 20.dp, vertical = if (metrics.compact) 14.dp else 20.dp),
        ) {
            SurfaceTopBar(state, session::setSeatCount, session::setDifficulty, session::openOpponentSettings)
            Notes(state)
            Spacer(Modifier.height(8.dp))
            Arena(state, onTogglePeek = { session.toggleReveal(it) }, onPotDetails = session::openPotDetails, effects = model.effects)
            if (LocalDensity.current.fontScale > ARENA_MAX_FONT_SCALE) {
                SeatList(state, onTogglePeek = { session.toggleReveal(it) }, modifier = Modifier.padding(top = 12.dp))
            }
            state.showdown?.let { ShowdownStage(it, Modifier.padding(top = 12.dp)) }
            HorizontalDivider(color = Noir.StripDivider, modifier = Modifier.padding(top = 12.dp))
            DecisionStrip(state.actions, Modifier.padding(horizontal = 8.dp))
            ActionPanel(state.actions, callbacks, Modifier.padding(horizontal = 8.dp, vertical = 8.dp))
        }
        TableFooter(onReset)
    }
}

@Composable
private fun Header(state: TableRenderState, onToggleSound: () -> Unit, onRules: () -> Unit) {
    val metrics = LocalNoirMetrics.current
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = if (metrics.compact) 64.dp else 76.dp)
            .padding(horizontal = if (metrics.compact) 16.dp else 32.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.semantics(mergeDescendants = true) {
                contentDescription = UiCopy.brandA11y
                heading()
            },
        ) {
            Canvas(Modifier.size(if (metrics.compact) 24.dp else 30.dp)) {
                drawSuit(0, center, size.width * 0.9f, Noir.Mint)
            }
            Spacer(Modifier.width(10.dp))
            Text(UiCopy.brandNoir, style = NoirType.style(if (metrics.compact) 18.sp else 22.sp, FontWeight.ExtraBold, tracking = if (metrics.compact) 2.sp else 3.sp))
            if (!metrics.tiny && !metrics.largeText) {
                Spacer(Modifier.width(8.dp))
                Text(UiCopy.brandPoker, style = NoirType.style(if (metrics.compact) 11.sp else 15.sp, color = Noir.BrandLight, tracking = if (metrics.compact) 2.sp else 4.sp))
            }
        }
        Spacer(Modifier.weight(1f))
        if (!metrics.compact && !metrics.largeText) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.size(6.dp).background(Noir.Mint, CircleShape))
                Text(UiCopy.headerMode, style = NoirType.style(13.sp, color = Noir.HeaderCenter))
                Text("|", style = NoirType.style(13.sp, color = Noir.HeaderDivider))
                Text(state.tableSize, style = NoirType.style(13.sp, color = Noir.HeaderCenter))
            }
            Spacer(Modifier.weight(1f))
        }
        SoundButton(state.settings, onToggleSound)
        Spacer(Modifier.width(8.dp))
        Box(
            Modifier
                .heightIn(min = 48.dp)
                .clickable(role = Role.Button, onClick = onRules)
                .padding(horizontal = 8.dp),
            contentAlignment = Alignment.Center,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(UiCopy.rulesButton, style = NoirType.style(14.sp, color = Noir.Text), maxLines = 1, softWrap = false)
                if (!metrics.compact) {
                    Spacer(Modifier.width(8.dp))
                    Box(Modifier.size(20.dp).border(1.dp, Noir.Muted, CircleShape), contentAlignment = Alignment.Center) {
                        Text("?", style = NoirType.style(11.sp, color = Noir.Muted))
                    }
                }
            }
        }
    }
    HorizontalDivider(color = Noir.HeaderBorder)
}

@Composable
private fun SoundButton(settings: SettingsState, onClick: () -> Unit) {
    val metrics = LocalNoirMetrics.current
    val visual = if (metrics.compact) 32.dp else 38.dp
    Box(
        Modifier
            .size(48.dp)
            .clickable(role = Role.Switch, onClick = onClick)
            .semantics {
                contentDescription = settings.soundA11y
                stateDescription = settings.soundTitle
                selected = settings.sound
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(visual).border(1.dp, Noir.Line, CircleShape), contentAlignment = Alignment.Center) {
            Canvas(Modifier.size(visual * 0.5f)) {
                val w = size.width
                val h = size.height
                val color = if (settings.sound) Noir.Mint else Noir.TextDialogBody
                val speaker = Path().apply {
                    moveTo(w * 0.08f, h * 0.36f); lineTo(w * 0.28f, h * 0.36f); lineTo(w * 0.52f, h * 0.14f)
                    lineTo(w * 0.52f, h * 0.86f); lineTo(w * 0.28f, h * 0.64f); lineTo(w * 0.08f, h * 0.64f); close()
                }
                drawPath(speaker, color, style = Stroke(w * 0.08f))
                if (settings.sound) {
                    drawArc(color, -45f, 90f, false, Offset(w * 0.45f, h * 0.25f), androidx.compose.ui.geometry.Size(w * 0.3f, h * 0.5f), style = Stroke(w * 0.08f, cap = StrokeCap.Round))
                } else {
                    drawLine(color, Offset(w * 0.68f, h * 0.36f), Offset(w * 0.92f, h * 0.64f), w * 0.08f, StrokeCap.Round)
                    drawLine(color, Offset(w * 0.92f, h * 0.36f), Offset(w * 0.68f, h * 0.64f), w * 0.08f, StrokeCap.Round)
                }
            }
        }
    }
}

@Composable
private fun TableHeading(state: TableRenderState) {
    val metrics = LocalNoirMetrics.current
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
        Column(Modifier.weight(1f)) {
            Text(UiCopy.tableEyebrow, style = NoirType.style(if (metrics.compact) 10.sp else 12.sp, FontWeight.SemiBold, Noir.TextEyebrow, if (metrics.compact) 2.sp else 3.sp))
            Spacer(Modifier.height(8.dp))
            Text(
                buildAnnotatedString {
                    append(UiCopy.tableHeadline)
                    withStyle(SpanStyle(color = Noir.Mint)) { append(".") }
                },
                style = NoirType.style(if (metrics.tiny) 16.sp else if (metrics.compact) 17.sp else 23.sp, FontWeight.Medium, tracking = if (metrics.compact) 0.sp else 1.sp),
                modifier = Modifier.semantics { heading() },
            )
        }
        if (!metrics.tiny) {
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    state.tableTag,
                    style = NoirType.style(12.sp, color = Noir.Muted, tracking = 1.sp),
                    modifier = Modifier
                        .border(1.dp, Color(0xFF35434E), RoundedCornerShape(4.dp))
                        .padding(horizontal = 9.dp, vertical = 5.dp),
                )
                Spacer(Modifier.height(6.dp))
                Text(UiCopy.tableBlinds, style = NoirType.style(12.sp, color = Noir.Muted))
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SurfaceTopBar(state: TableRenderState, onSeatCount: (Int) -> Unit, onDifficulty: (Difficulty) -> Unit, onOpponents: () -> Unit) {
    val metrics = LocalNoirMetrics.current
    if (metrics.compact || metrics.largeText) {
        // Phone: the hand label, then Opponent Styles + Players, then the difficulty control.
        Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            HandLabel(state)
            FlowRow(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                itemVerticalAlignment = Alignment.CenterVertically,
            ) {
                OpponentsButton(state, onOpponents)
                Spacer(Modifier.weight(1f))
                SeatCountPicker(state.settings, onSeatCount)
            }
            DifficultyPicker(state.settings, onDifficulty)
        }
    } else {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.Top) {
            Box(Modifier.weight(1f).padding(top = 8.dp)) { HandLabel(state) }
            FlowRow(
                Modifier.weight(3f, fill = false),
                horizontalArrangement = Arrangement.spacedBy(14.dp, Alignment.End),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                itemVerticalAlignment = Alignment.CenterVertically,
            ) {
                OpponentsButton(state, onOpponents)
                SeatCountPicker(state.settings, onSeatCount)
                DifficultyPicker(state.settings, onDifficulty)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HandLabel(state: TableRenderState) {
    val metrics = LocalNoirMetrics.current
    FlowRow(
        verticalArrangement = Arrangement.spacedBy(6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        itemVerticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .heightIn(min = 28.dp)
            .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
    ) {
        Text(state.handHeading, style = NoirType.style(if (metrics.compact) 12.sp else 13.sp, FontWeight.Medium, Noir.TextSurfaceTop))
        Text("·", style = NoirType.style(13.sp, color = Noir.TextSubtle))
        Text(state.streetLabel, style = NoirType.style(if (metrics.compact) 12.sp else 13.sp, color = Noir.TextSurfaceTop))
        state.replayBadge?.let {
            Text(
                it,
                style = NoirType.style(11.sp, FontWeight.SemiBold, Noir.ReplayText),
                modifier = Modifier
                    .background(Noir.ReplayBg, RoundedCornerShape(10.dp))
                    .border(1.dp, Noir.ReplayBorder, RoundedCornerShape(10.dp))
                    .padding(horizontal = 8.dp, vertical = 2.dp),
            )
        }
    }
}

/** Opponent Styles with its summary chip (`Balanced`, `3 Styled Opponents`, `Next Hand`). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun OpponentsButton(state: TableRenderState, onClick: () -> Unit) {
    val summary = state.opponents
    val shape = RoundedCornerShape(7.dp)
    FlowRow(
        Modifier
            .heightIn(min = 44.dp)
            .background(Noir.SelectBg, shape)
            .border(1.dp, if (summary.changePending) Noir.ReplayBorder else Noir.SelectBorder, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .testTag("opponents")
            .padding(horizontal = 10.dp, vertical = 6.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = UiCopy.opponentsButton
                stateDescription = summary.text
            },
        itemVerticalAlignment = Alignment.CenterVertically,
        verticalArrangement = Arrangement.Center,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(UiCopy.opponentsButton, style = NoirType.style(13.sp, FontWeight.Medium, Noir.SelectText), maxLines = 1, softWrap = false)
        Text(
            summary.text,
            style = NoirType.style(11.sp, color = if (summary.changePending) Noir.GoldNote else Noir.TextSubtle),
            maxLines = 1,
            softWrap = false,
        )
    }
}

@Composable
private fun SeatCountPicker(settings: SettingsState, onSeatCount: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val current = settings.seatCountOptions.firstOrNull { it.value == settings.requestedSeatCount }?.label ?: UiCopy.playersOption(settings.requestedSeatCount)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(UiCopy.playersLabel, style = NoirType.style(12.sp, color = Noir.TextSubtle))
        Box {
            Row(
                Modifier
                    .heightIn(min = 44.dp)
                    .background(Noir.SelectBg, RoundedCornerShape(6.dp))
                    .border(1.dp, Noir.SelectBorder, RoundedCornerShape(6.dp))
                    .clickable(role = Role.DropdownList) { open = true }
                    .padding(horizontal = 10.dp)
                    .semantics {
                        contentDescription = UiCopy.playerCountA11y
                        stateDescription = current
                    },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(current, style = NoirType.style(13.sp, color = Noir.SelectText))
                Spacer(Modifier.width(8.dp))
                Text("▾", style = NoirType.style(12.sp, color = Noir.SelectText))
            }
            DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.background(Noir.SelectBg)) {
                settings.seatCountOptions.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(option.label, style = NoirType.style(14.sp, color = if (option.value == settings.requestedSeatCount) Noir.Mint else Noir.SelectText)) },
                        onClick = {
                            open = false
                            onSeatCount(option.value)
                        },
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DifficultyPicker(settings: SettingsState, onDifficulty: (Difficulty) -> Unit) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        Text(UiCopy.difficultyLabel, style = NoirType.style(12.sp, color = Noir.TextSubtle))
        Segmented(
            options = settings.difficultyOptions.map { it.value to it.label },
            selected = settings.difficulty,
            a11y = UiCopy.difficultyLabel,
            onSelect = onDifficulty,
            fill = false,
        )
    }
}

@Composable
private fun Notes(state: TableRenderState) {
    val notes = listOfNotNull(state.settings.tableChangeNote, state.opponents.changeNote, state.replayNote)
    if (notes.isEmpty()) return
    Column(
        Modifier
            .padding(horizontal = 8.dp, vertical = 6.dp)
            .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        notes.forEach { Text(it, style = NoirType.style(12.sp, color = Noir.GoldNote)) }
    }
}

@Composable
private fun TableFooter(onReset: () -> Unit) {
    val metrics = LocalNoirMetrics.current
    Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(4.dp).background(Noir.Mint, CircleShape))
        Spacer(Modifier.width(6.dp))
        Text(UiCopy.footerLocal, style = NoirType.style(11.sp, color = Noir.TextFooter), modifier = Modifier.weight(1f))
        if (!metrics.compact) {
            Text(UiCopy.footerVirtual, style = NoirType.style(11.sp, color = Noir.TextFooter), modifier = Modifier.weight(1f))
        }
        Box(
            Modifier
                .heightIn(min = 48.dp)
                .clickable(role = Role.Button, onClick = onReset)
                .testTag("reset")
                .padding(horizontal = 8.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(UiCopy.resetButton, style = NoirType.style(11.sp, color = Color(0xFF8FA0AE)))
        }
    }
}

@Composable
private fun SidebarCards(state: TableRenderState, onToggleHints: () -> Unit, stacked: Boolean) {
    val metrics = LocalNoirMetrics.current
    if (stacked || metrics.twoPane) {
        Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
            SessionCard(state.session, Modifier.fillMaxWidth())
            CoachCard(state.coach, onToggleHints, Modifier.fillMaxWidth())
            ActivityCard(state.activity, Modifier.fillMaxWidth())
            if (metrics.twoPane) SidebarFootnote()
        }
    } else {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.height(androidx.compose.foundation.layout.IntrinsicSize.Max)) {
                SessionCard(state.session, Modifier.weight(1f).fillMaxSize())
                CoachCard(state.coach, onToggleHints, Modifier.weight(1f).fillMaxSize())
            }
            ActivityCard(state.activity, Modifier.fillMaxWidth())
        }
    }
}
