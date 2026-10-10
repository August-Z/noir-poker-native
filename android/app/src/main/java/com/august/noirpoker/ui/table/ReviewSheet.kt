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
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.august.noirpoker.core.Card
import com.august.noirpoker.core.review.HeroReviewView
import com.august.noirpoker.core.review.HeroStepView
import com.august.noirpoker.core.review.OpponentReviewView
import com.august.noirpoker.core.review.OpponentStepView
import com.august.noirpoker.core.review.ReviewDialogCopy as Copy
import com.august.noirpoker.core.review.ReviewMeta
import com.august.noirpoker.core.review.ReviewSceneView
import com.august.noirpoker.core.review.ReviewSimulationView
import com.august.noirpoker.core.review.ReviewTimelineItem
import com.august.noirpoker.core.review.ReviewTone
import com.august.noirpoker.core.review.presentHeroReview
import com.august.noirpoker.core.review.presentOpponentReview
import com.august.noirpoker.core.session.ReviewPerspective
import com.august.noirpoker.core.session.ReviewState
import com.august.noirpoker.ui.UiCopy
import com.august.noirpoker.ui.components.CardSize
import com.august.noirpoker.ui.components.PlayingCardView
import com.august.noirpoker.ui.theme.LocalNoirMetrics
import com.august.noirpoker.ui.theme.LocalReducedMotion
import com.august.noirpoker.ui.theme.Noir
import com.august.noirpoker.ui.theme.NoirType

/** Commands of the Hand Review sheet. */
interface ReviewCallbacks {
    fun close()
    fun retry()
    fun select(index: Int)
    fun previous()
    fun next()
    fun perspective(perspective: ReviewPerspective)
    fun opponentFilter(seat: Int?)
    fun selectOpponent(index: Int)
}

/** Review palette (`review.css`). */
private object RV {
    val SummaryBorder = Color(0xFF5C4C71)
    val SummaryBrush = Brush.linearGradient(listOf(Color(0x77362E47), Color(0x44283245))) // 120deg gradient
    val SummaryLink = Color(0xFFD1B9F0)
    val Change = Color(0xFFE69BAB)
    val TabBorder = Color(0xFF405061)
    val TabBg = Color(0xFF10212C)
    val TabOn = Color(0xFF3C3451)
    val TabOnText = Color(0xFFEADBF9)
    val TabOffText = Color(0xFFA3B4C4)
    val StepBg = Color(0x661A2835)
    val StepBorder = Color(0xFF354554)
    val StepSelBorder = Color(0xFFA690C1)
    val StepSelBg = Color(0x5541374E)
    val StepNumber = Color(0xFF536078)
    val StepMeta = Color(0xFF8FA3B4)
    val SceneBg = Color(0x880D1C25)
    val SceneBorder = Color(0xFF314454)
    val SceneRule = Color(0xFF2D4150)
    val SceneLabel = Color(0xFF7F99AB)
    val ChoiceBg = Color(0x55223142)
    val ChoiceBorder = Color(0xFF3D4E5C)
    val ChoiceLabel = Color(0xFF9FAEC1)
    val SuggestBg = Color(0x44234538)
    val SuggestBorder = Color(0xFF5C796C)
    val SuggestLabel = Color(0xFF8EB9A4)
    val RouteBg = Color(0xFF172832)
    val RouteBorder = Color(0xFF3D505B)
    val RouteKicker = Color(0xFFB6A5CF)
    val RouteBody = Color(0xFFBDCAD2)
    val RouteSmall = Color(0xFF90A6B5)
    val EvidenceBg = Color(0xFF16272B)
    val EvidenceBorder = Color(0xFF374950)
    val EvidenceHeading = Color(0xFFD3E4DC)
    val EvidenceSide = Color(0xFFA0B7AE)
    val EvidenceText = Color(0xFFAEBFB8)
    val PlanText = Color(0xFFB9CFC3)
    val LessonRule = Color(0xFF9F84BE)
    val LessonLabel = Color(0xFF9C8DAE)
    val LessonText = Color(0xFFC8B8DC)
    val MetricRule = Color(0xFF344553)
    val MetricLabel = Color(0xFF8DA2B5)
    val Note = Color(0xFF8199A9)
    val PublicText = Color(0xFF9DAFBF)
    val PublicRule = Color(0xFF2D3E4C)
    val NavBg = Color(0xFF273544)
    val NavBorder = Color(0xFF455565)
    val NavText = Color(0xFF8196A9)
    val MethodRule = Color(0xFF374454)
    val Empty = Color(0xFF8FA5B5)
    val Intro = Color(0xFF9BAFC0)

    fun tone(t: ReviewTone): Pair<Color, Color> = when (t) {
        ReviewTone.ATTENTION -> Color(0x88643943) to Color(0xFFF0B5BC)
        ReviewTone.CONSIDER -> Color(0x66655732) to Color(0xFFE4CEA0)
        ReviewTone.SOUND -> Color(0x66284E42) to Color(0xFFA7D6BD)
        ReviewTone.PENDING -> Color(0x88354457) to Color(0xFFABBACC)
    }
}

/**
 * Hand Review: the summary, the Your Decisions / Opponent Decisions tabs, the
 * step timeline and the per-step detail. All review copy and numbers come from
 * [presentHeroReview] and [presentOpponentReview]; the analysis itself runs off
 * the main thread in the session's review runner.
 */
@Composable
fun ReviewSheet(review: ReviewState, callbacks: ReviewCallbacks) {
    val hero = presentHeroReview(review) ?: return
    NoirSheet(
        eyebrow = Copy.eyebrow,
        eyebrowColor = Noir.ReviewEyebrow,
        onDismiss = callbacks::close,
        maxWidth = 980.dp,
        closeA11y = Copy.closeA11y,
        footer = { NoirButton(Copy.backToTable, callbacks::close, Modifier.fillMaxWidth()) },
    ) {
        Header(hero)
        Spacer(Modifier.height(16.dp))
        Summary(hero, callbacks)
        Spacer(Modifier.height(18.dp))
        Tabs(review.perspective, callbacks::perspective)
        Spacer(Modifier.height(18.dp))
        if (review.perspective == ReviewPerspective.HERO) {
            HeroPanel(hero, review.key, callbacks)
        } else {
            presentOpponentReview(review)?.let { OpponentPanel(it, review.key, callbacks) }
        }
        Spacer(Modifier.height(18.dp))
        Method()
    }
}

@Composable
private fun Header(hero: HeroReviewView) {
    val metrics = LocalNoirMetrics.current
    Row(verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f)) {
            SheetTitle(hero.title)
            Text(hero.context, style = NoirType.style(13.sp, color = Noir.TextSubtle))
        }
        Spacer(Modifier.width(12.dp))
        Text(
            hero.change,
            style = NoirType.tabular(NoirType.style(if (metrics.compact) 20.sp else 24.sp, FontWeight.Medium, RV.Change)),
            modifier = Modifier.padding(top = 6.dp),
        )
    }
}

@Composable
private fun Summary(hero: HeroReviewView, callbacks: ReviewCallbacks) {
    val shape = RoundedCornerShape(10.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .background(RV.SummaryBrush, shape)
            .border(1.dp, RV.SummaryBorder, shape)
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(hero.summaryTitle, style = NoirType.style(17.sp, FontWeight.Medium), modifier = Modifier.semantics { heading() })
        Text(
            hero.stateText,
            style = NoirType.style(14.sp, color = Noir.TextDialogBody).copy(lineHeight = 24.sp),
            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
        )
        if (hero.running && hero.total > 0) {
            val fraction = hero.progress.toFloat() / hero.total
            LinearProgressIndicator(
                progress = { fraction },
                color = RV.SummaryLink,
                trackColor = Color(0xFF2B2F42),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(4.dp)
                    .semantics { progressBarRangeInfo = ProgressBarRangeInfo(hero.progress.toFloat(), 0f..hero.total.toFloat()) },
            )
        }
        hero.priorityButton?.let { LinkButton(it) { callbacks.select(hero.priorityIndex) } }
        if (hero.retryVisible) LinkButton(Copy.retry, callbacks::retry)
    }
}

@Composable
private fun LinkButton(text: String, onClick: () -> Unit) {
    Box(
        Modifier
            .heightIn(min = 44.dp)
            .clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.CenterStart,
    ) {
        Text(text, style = NoirType.style(13.sp, color = RV.SummaryLink).copy(textDecoration = TextDecoration.Underline))
    }
}

@Composable
private fun Tabs(perspective: ReviewPerspective, onSelect: (ReviewPerspective) -> Unit) {
    val metrics = LocalNoirMetrics.current
    val shape = RoundedCornerShape(9.dp)
    Row(
        (if (metrics.compact) Modifier.fillMaxWidth() else Modifier)
            .background(RV.TabBg, shape)
            .border(1.dp, RV.TabBorder, shape)
            .padding(4.dp)
            .semantics { contentDescription = Copy.tabsA11y },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        listOf(ReviewPerspective.HERO to Copy.tabHero, ReviewPerspective.OPPONENTS to Copy.tabOpponents).forEach { (value, label) ->
            val on = value == perspective
            Box(
                (if (metrics.compact) Modifier.weight(1f) else Modifier)
                    .heightIn(min = 44.dp)
                    .background(if (on) RV.TabOn else Color.Transparent, RoundedCornerShape(6.dp))
                    .clickable(role = Role.Tab) { onSelect(value) }
                    .testTag(if (value == ReviewPerspective.HERO) "review-tab-hero" else "review-tab-opponents")
                    .padding(horizontal = 16.dp)
                    .semantics { selected = on },
                contentAlignment = Alignment.Center,
            ) {
                Column(Modifier.padding(vertical = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        label,
                        style = NoirType.style(14.sp, color = if (on) RV.TabOnText else RV.TabOffText),
                        maxLines = 2,
                        textAlign = TextAlign.Center,
                    )
                    // The reference's tab subtitle: why the bots played the way they did.
                    if (value == ReviewPerspective.OPPONENTS) {
                        Text(
                            Copy.tabOpponentsSubtitle,
                            style = NoirType.style(11.sp, color = RV.StepMeta),
                            maxLines = 2,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }
        }
    }
}

// ---- Shared pieces -----------------------------------------------------------------

@Composable
private fun StatusChip(text: String, tone: ReviewTone, modifier: Modifier = Modifier) {
    val (bg, fg) = RV.tone(tone)
    Text(
        text,
        style = NoirType.style(12.sp, color = fg),
        modifier = modifier.background(bg, RoundedCornerShape(4.dp)).padding(horizontal = 7.dp, vertical = 4.dp),
    )
}

/**
 * The step timeline: a column beside the detail on wide sheets, a horizontal
 * scroller of 160–200 dp cards on phones. The selected card is kept in view.
 */
@Composable
private fun Timeline(
    title: String,
    count: String,
    a11y: String,
    items: List<ReviewTimelineItem>,
    horizontal: Boolean,
    key: String?,
    selected: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.semantics { contentDescription = a11y }, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = NoirType.style(15.sp, FontWeight.Medium), modifier = Modifier.weight(1f).semantics { heading() })
            Text(count, style = NoirType.style(13.sp, color = Noir.TextSubtle))
        }
        if (horizontal) {
            val reduced = LocalReducedMotion.current
            val listState = rememberLazyListState()
            // One effect drives every scroll of this list. Two effects that both scroll
            // before the first layout each wait on the lazy list's first-layout signal,
            // and resuming one while the other is cancelled by the scroll mutex crashed
            // the layout pass (IndexOutOfBoundsException in AwaitFirstLayoutModifier).
            val shownKey = remember { arrayOf(key) }
            LaunchedEffect(key, selected) {
                if (shownKey[0] != key) {
                    shownKey[0] = key
                    listState.scrollToItem(0)
                }
                if (selected in items.indices) {
                    val visible = listState.layoutInfo.visibleItemsInfo.map { it.index }
                    if (selected !in visible) {
                        if (reduced) listState.scrollToItem(selected) else listState.animateScrollToItem(selected)
                    }
                }
            }
            LazyRow(state = listState, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                itemsIndexed(items) { _, item ->
                    StepCard(item, Modifier.widthIn(min = 160.dp, max = 200.dp)) { onSelect(item.index) }
                }
            }
        } else {
            items.forEach { item -> StepCard(item, Modifier.fillMaxWidth()) { onSelect(item.index) } }
        }
    }
}

@Composable
private fun StepCard(item: ReviewTimelineItem, modifier: Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(9.dp)
    Row(
        modifier
            .background(if (item.selected) RV.StepSelBg else RV.StepBg, shape)
            .border(1.dp, if (item.selected) RV.StepSelBorder else RV.StepBorder, shape)
            .clickable(role = Role.Tab, onClick = onClick)
            .padding(14.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = item.a11y
                selected = item.selected
            },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // The badge grows with the text size and stays a circle.
        Box(
            Modifier
                .border(1.dp, RV.StepNumber, CircleShape)
                .squareOfLargestSide()
                .sizeIn(minWidth = 23.dp, minHeight = 23.dp)
                .padding(horizontal = 4.dp, vertical = 2.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(item.number, style = NoirType.tabular(NoirType.style(11.sp, color = Noir.TextDialogBody)), maxLines = 1)
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(item.meta, style = NoirType.style(12.sp, color = RV.StepMeta), maxLines = 2)
            Text(item.action, style = NoirType.style(14.sp, FontWeight.Medium))
            Spacer(Modifier.height(2.dp))
            StatusChip(item.chip, item.tone)
        }
    }
}

@Composable
private fun DetailHeader(title: String, status: String, tone: ReviewTone) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = NoirType.style(17.sp, FontWeight.Medium), modifier = Modifier.weight(1f).semantics { heading() })
        StatusChip(status, tone)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Scene(scene: ReviewSceneView) {
    val shape = RoundedCornerShape(10.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .background(RV.SceneBg, shape)
            .border(1.dp, RV.SceneBorder, shape)
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(28.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            CardGroup(scene.holeLabel, scene.hole, null)
            CardGroup(scene.boardLabel, scene.board, scene.noBoard)
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(RV.SceneRule))
        MetaRow(scene.meta, valueSize = 17)
    }
}

@Composable
private fun CardGroup(label: String, cards: List<Card>, empty: String?) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, style = NoirType.style(12.sp, color = RV.SceneLabel))
        if (cards.isEmpty() && empty != null) {
            Box(Modifier.heightIn(min = 52.dp), contentAlignment = Alignment.CenterStart) {
                Text(empty, style = NoirType.style(13.sp, color = RV.SceneLabel))
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = label }) {
                cards.forEach { PlayingCardView(it, 37.dp, 52.dp, size = CardSize.SMALL) }
            }
        }
    }
}

@Composable
private fun MetaRow(items: List<ReviewMeta>, valueSize: Int) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        items.forEach { m ->
            Column(
                Modifier.weight(1f).semantics(mergeDescendants = true) {},
                verticalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Text(m.label, style = NoirType.style(12.sp, color = RV.MetricLabel))
                Text(m.value, style = NoirType.tabular(NoirType.style(valueSize.sp, FontWeight.Medium)))
            }
        }
    }
}

@Composable
private fun ChoiceBox(label: String, value: String, suggested: Boolean, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(8.dp)
    Column(
        modifier
            .background(if (suggested) RV.SuggestBg else RV.ChoiceBg, shape)
            .border(1.dp, if (suggested) RV.SuggestBorder else RV.ChoiceBorder, shape)
            .padding(horizontal = 16.dp, vertical = 14.dp)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Text(label, style = NoirType.style(12.sp, color = if (suggested) RV.SuggestLabel else RV.ChoiceLabel))
        Text(value, style = NoirType.style(16.sp, FontWeight.Medium).copy(lineHeight = 24.sp))
    }
}

/** Two equal cells side by side on wide sheets, stacked on phones. */
@Composable
private fun TwoUp(wide: Boolean, first: @Composable (Modifier) -> Unit, second: (@Composable (Modifier) -> Unit)?) {
    if (wide) {
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Max), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            first(Modifier.weight(1f).fillMaxHeight())
            if (second != null) second(Modifier.weight(1f).fillMaxHeight()) else Spacer(Modifier.weight(1f))
        }
    } else {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            first(Modifier.fillMaxWidth())
            second?.invoke(Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun Disclosure(summary: String, content: @Composable ColumnScope.() -> Unit) {
    var open by remember(summary) { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            Modifier
                .heightIn(min = 44.dp)
                .clickable(role = Role.Button) { open = !open }
                .semantics { stateDescription = if (open) UiCopy.expanded else UiCopy.collapsed },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(if (open) "▾" else "▸", style = NoirType.style(11.sp, color = RV.PublicText))
            Spacer(Modifier.width(8.dp))
            Text(summary, style = NoirType.style(13.sp, color = RV.PublicText))
        }
        if (open) content()
    }
}

@Composable
private fun ListRow(left: String, right: String?) {
    Row(
        Modifier
            .fillMaxWidth()
            .drawBehind {
                drawLine(RV.PublicRule, Offset(0f, size.height), Offset(size.width, size.height), 1.dp.toPx())
            }
            .padding(vertical = 8.dp)
            .semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(15.dp),
    ) {
        Text(left, style = NoirType.style(13.sp, color = RV.PublicText), modifier = Modifier.weight(1f))
        if (right != null) Text(right, style = NoirType.tabular(NoirType.style(13.sp, color = RV.PublicText)))
    }
}

@Composable
private fun StepNav(position: String, canPrevious: Boolean, canNext: Boolean, onPrevious: () -> Unit, onNext: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        NavButton(Copy.previous, canPrevious, onPrevious)
        Text(position, style = NoirType.tabular(NoirType.style(13.sp, color = RV.NavText)), modifier = Modifier.weight(1f).padding(horizontal = 8.dp), textAlign = TextAlign.Center)
        NavButton(Copy.next, canNext, onNext)
    }
}

@Composable
private fun NavButton(text: String, enabled: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(6.dp)
    Box(
        Modifier
            .heightIn(min = 48.dp)
            .alpha(if (enabled) 1f else 0.4f)
            .background(RV.NavBg, shape)
            .border(1.dp, RV.NavBorder, shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 15.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = NoirType.style(13.sp))
    }
}

@Composable
private fun EvidenceBox(heading: String, side: String, items: List<String>) {
    val shape = RoundedCornerShape(9.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .background(RV.EvidenceBg, shape)
            .border(1.dp, RV.EvidenceBorder, shape)
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(heading, style = NoirType.style(14.sp, FontWeight.Medium, RV.EvidenceHeading), modifier = Modifier.weight(1f).semantics { heading() })
            Text(side, style = NoirType.style(12.sp, color = RV.EvidenceSide))
        }
        items.forEach { fact ->
            Row(Modifier.semantics(mergeDescendants = true) {}) {
                Text("•", style = NoirType.style(13.sp, color = RV.EvidenceText), modifier = Modifier.width(14.dp))
                Text(fact, style = NoirType.style(13.sp, color = RV.EvidenceText).copy(lineHeight = 24.sp))
            }
        }
    }
}

// ---- Your Decisions ----------------------------------------------------------------

@Composable
private fun HeroPanel(hero: HeroReviewView, key: String?, callbacks: ReviewCallbacks) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val wide = maxWidth >= 700.dp
        val roomy = maxWidth >= 820.dp
        val selected = hero.step?.index ?: 0
        if (wide) {
            Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                Timeline(Copy.timelineTitle, hero.stepCount, Copy.timelineA11y, hero.timeline, false, key, selected, callbacks::select, Modifier.width(235.dp))
                Column(Modifier.weight(1f)) { HeroDetail(hero, wide = roomy, callbacks) }
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Timeline(Copy.timelineTitle, hero.stepCount, Copy.timelineA11y, hero.timeline, true, key, selected, callbacks::select)
                HeroDetail(hero, wide = false, callbacks)
            }
        }
    }
}

@Composable
private fun HeroDetail(hero: HeroReviewView, wide: Boolean, callbacks: ReviewCallbacks) {
    val step = hero.step
    if (step == null) {
        Text(hero.empty ?: "", style = NoirType.style(14.sp, color = RV.Empty).copy(lineHeight = 24.sp))
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        DetailHeader(step.title, step.statusText, step.tone)
        Scene(step.scene)
        TwoUp(
            wide,
            { m -> ChoiceBox(Copy.yourChoice, step.yourChoice, false, m) },
            { m -> ChoiceBox(Copy.suggestedLine, step.suggestion, true, m) },
        )
        if (step.routes.isNotEmpty()) {
            Box(Modifier.semantics { contentDescription = Copy.routesA11y }) {
                TwoUp(
                    wide,
                    { m -> RouteCard(step.routes[0], m) },
                    step.routes.getOrNull(1)?.let { r -> { m: Modifier -> RouteCard(r, m) } },
                )
            }
        }
        Simulation(step)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(step.decisionTitle, style = NoirType.style(17.sp, FontWeight.Medium), modifier = Modifier.semantics { heading() })
            Text(step.reason, style = NoirType.style(14.sp, color = Noir.TextDialogBody).copy(lineHeight = 26.sp))
        }
        EvidenceBox(Copy.evidenceHeading, step.confidence, step.evidence)
        Lesson(Copy.lessonHeading, step.lesson)
        Plan(step.plan)
        Column(
            Modifier
                .fillMaxWidth()
                .drawBehind {
                    drawLine(RV.MetricRule, Offset(0f, 0f), Offset(size.width, 0f), 1.dp.toPx())
                    drawLine(RV.MetricRule, Offset(0f, size.height), Offset(size.width, size.height), 1.dp.toPx())
                }
                .padding(vertical = 16.dp),
        ) {
            MetaRow(step.metrics, valueSize = 19)
        }
        step.modelNote?.let { Text(it, style = NoirType.style(12.sp, color = RV.Note).copy(lineHeight = 22.sp)) }
        Text(step.priceNote, style = NoirType.style(12.sp, color = RV.Note).copy(lineHeight = 20.sp))
        Disclosure(Copy.publicActionsSummary) {
            if (step.publicActions.isEmpty()) {
                ListRow(step.publicActionsEmpty ?: "", null)
            } else {
                step.publicActions.forEach { ListRow(it.name, it.label) }
            }
        }
        StepNav(step.position, step.canPrevious, step.canNext, callbacks::previous, callbacks::next)
    }
}

@Composable
private fun RouteCard(route: com.august.noirpoker.core.review.ReviewRouteView, modifier: Modifier) {
    val shape = RoundedCornerShape(9.dp)
    Column(
        modifier
            .background(RV.RouteBg, shape)
            .border(1.dp, RV.RouteBorder, shape)
            .padding(15.dp)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(route.kicker, style = NoirType.style(12.sp, color = RV.RouteKicker))
        Text(route.label, style = NoirType.style(14.sp, FontWeight.Medium))
        Text(route.condition, style = NoirType.style(13.sp, color = RV.RouteBody).copy(lineHeight = 23.sp))
        Text(route.tradeoff, style = NoirType.style(12.sp, color = RV.RouteSmall).copy(lineHeight = 20.sp))
    }
}

@Composable
private fun Simulation(step: HeroStepView) {
    val sim = step.simulation
    if (sim == null) {
        step.simulationNote?.let { Text(it, style = NoirType.style(12.sp, color = RV.Note).copy(lineHeight = 20.sp)) }
        return
    }
    SimulationTable(sim)
}

@Composable
private fun SimulationTable(sim: ReviewSimulationView) {
    val shape = RoundedCornerShape(10.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .background(RV.SceneBg, shape)
            .border(1.dp, RV.SceneBorder, shape)
            .padding(18.dp)
            .semantics { contentDescription = Copy.simA11y },
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(sim.heading, style = NoirType.style(15.sp, FontWeight.Medium), modifier = Modifier.semantics { heading() })
        Text(sim.stability, style = NoirType.style(13.sp, color = Noir.TextDialogBody).copy(lineHeight = 22.sp))
        Text(sim.caption, style = NoirType.style(11.sp, color = RV.Note).copy(lineHeight = 18.sp))
        if (LocalDensity.current.fontScale >= LARGE_FONT_SCALE) {
            StackedSimulationRows(sim)
        } else {
            SimulationGrid(sim)
        }
        Disclosure(sim.detailsSummary) {
            sim.details.forEach { Text(it, style = NoirType.style(12.sp, color = RV.Note).copy(lineHeight = 20.sp)) }
        }
    }
}

/** Font scale from which the simulation table stacks each action's results instead of a fixed-width grid. */
private const val LARGE_FONT_SCALE = 1.3f

/** Large text: one block per action, each result on its own lines, so nothing clips or scrolls sideways. */
@Composable
private fun StackedSimulationRows(sim: ReviewSimulationView) {
    Column(Modifier.fillMaxWidth()) {
        sim.rows.forEach { row ->
            Box(Modifier.fillMaxWidth().height(1.dp).background(RV.PublicRule))
            Column(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(row.label, style = NoirType.style(13.sp, FontWeight.Medium))
                row.cells.forEachIndexed { i, cell ->
                    Column(
                        Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = cell.a11y },
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Text(sim.columns.getOrElse(i + 1) { "" }, style = NoirType.style(12.sp, color = RV.MetricLabel))
                        Text(cell.value, style = NoirType.tabular(NoirType.style(13.sp)))
                        Text(cell.margin, style = NoirType.tabular(NoirType.style(11.sp, color = RV.Note)))
                    }
                }
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(RV.PublicRule))
    }
}

/** Default text size: the reference's three-column grid, scrolling sideways on narrow sheets. */
@Composable
private fun SimulationGrid(sim: ReviewSimulationView) {
    Column(Modifier.horizontalScroll(rememberScrollState())) {
        Row(Modifier.padding(vertical = 8.dp)) {
            sim.columns.forEachIndexed { i, c ->
                Text(c, style = NoirType.style(12.sp, color = RV.MetricLabel), modifier = Modifier.width(if (i == 0) 170.dp else 120.dp))
            }
        }
        sim.rows.forEach { row ->
            Box(Modifier.width(410.dp).height(1.dp).background(RV.PublicRule))
            Row(Modifier.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(row.label, style = NoirType.style(13.sp, FontWeight.Medium), modifier = Modifier.width(170.dp).padding(end = 8.dp))
                row.cells.forEach { cell ->
                    Column(
                        Modifier.width(120.dp).semantics(mergeDescendants = true) { contentDescription = cell.a11y },
                        verticalArrangement = Arrangement.spacedBy(3.dp),
                    ) {
                        Text(cell.value, style = NoirType.tabular(NoirType.style(13.sp)))
                        Text(cell.margin, style = NoirType.tabular(NoirType.style(11.sp, color = RV.Note)))
                    }
                }
            }
        }
        Box(Modifier.width(410.dp).height(1.dp).background(RV.PublicRule))
    }
}

/** Lays the content out in a square of its larger side, centered, so a circle border fits any text. */
private fun Modifier.squareOfLargestSide(): Modifier = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints)
    val side = maxOf(placeable.width, placeable.height)
    layout(side, side) { placeable.place((side - placeable.width) / 2, (side - placeable.height) / 2) }
}

@Composable
private fun Lesson(label: String, text: String) {
    Column(
        Modifier
            .fillMaxWidth()
            .drawBehind { drawLine(RV.LessonRule, Offset(0f, 0f), Offset(0f, size.height), 2.dp.toPx()) }
            .padding(start = 13.dp, top = 4.dp, bottom = 4.dp)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(label, style = NoirType.style(12.sp, color = RV.LessonLabel))
        Text(text, style = NoirType.style(14.sp, color = RV.LessonText).copy(lineHeight = 24.sp))
    }
}

@Composable
private fun Plan(text: String) {
    val shape = RoundedCornerShape(9.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .background(RV.EvidenceBg, shape)
            .border(1.dp, RV.EvidenceBorder, shape)
            .padding(horizontal = 18.dp, vertical = 16.dp)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(Copy.planHeading, style = NoirType.style(14.sp, FontWeight.Medium, RV.EvidenceHeading))
        Text(text, style = NoirType.style(14.sp, color = RV.PlanText).copy(lineHeight = 25.sp))
    }
}

// ---- Opponent Decisions ------------------------------------------------------------

@Composable
private fun OpponentPanel(view: OpponentReviewView, key: String?, callbacks: ReviewCallbacks) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val wide = maxWidth >= 700.dp
        val selected = view.step?.index ?: 0
        Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
            if (wide) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                    Text(view.intro, style = NoirType.style(13.sp, color = RV.Intro).copy(lineHeight = 23.sp), modifier = Modifier.weight(1f))
                    OpponentFilter(view, callbacks::opponentFilter)
                }
            } else {
                Text(view.intro, style = NoirType.style(13.sp, color = RV.Intro).copy(lineHeight = 23.sp))
                OpponentFilter(view, callbacks::opponentFilter)
            }
            val timelineKey = "$key:${view.filter}"
            if (wide) {
                Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                    Timeline(view.timelineTitle, view.count, Copy.oppTimelineA11y, view.timeline, false, timelineKey, selected, callbacks::selectOpponent, Modifier.width(235.dp))
                    Column(Modifier.weight(1f)) { OpponentDetail(view, callbacks) }
                }
            } else {
                Timeline(view.timelineTitle, view.count, Copy.oppTimelineA11y, view.timeline, true, timelineKey, selected, callbacks::selectOpponent)
                OpponentDetail(view, callbacks)
            }
        }
    }
}

@Composable
private fun OpponentFilter(view: OpponentReviewView, onSelect: (Int?) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Text(view.filterLabel, style = NoirType.style(12.sp, color = Color(0xFFB7CAD4)))
        Box {
            Row(
                Modifier
                    .widthIn(min = 160.dp)
                    .heightIn(min = 44.dp)
                    .background(Noir.SelectBg, RoundedCornerShape(6.dp))
                    .border(1.dp, Noir.SelectBorder, RoundedCornerShape(6.dp))
                    .clickable(role = Role.DropdownList) { open = true }
                    .testTag("review-opponent-filter")
                    .padding(horizontal = 12.dp)
                    .semantics {
                        contentDescription = view.filterLabel
                        stateDescription = view.filterText
                    },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(view.filterText, style = NoirType.style(13.sp, color = Noir.SelectText), modifier = Modifier.weight(1f, fill = false))
                Spacer(Modifier.width(12.dp))
                Text("▾", style = NoirType.style(12.sp, color = Noir.SelectText))
            }
            DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.background(Noir.SelectBg)) {
                view.filterOptions.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(option.label, style = NoirType.style(14.sp, color = if (option.value == view.filter) Noir.Mint else Noir.SelectText)) },
                        onClick = {
                            open = false
                            onSelect(option.value)
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun OpponentDetail(view: OpponentReviewView, callbacks: ReviewCallbacks) {
    val step: OpponentStepView = view.step ?: run {
        Text(view.empty ?: "", style = NoirType.style(14.sp, color = RV.Empty).copy(lineHeight = 24.sp))
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        DetailHeader(step.title, step.statusText, step.tone)
        Scene(step.scene)
        ChoiceBox(step.choiceLabel, step.choice, true, Modifier.fillMaxWidth())
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(step.explanationTitle, style = NoirType.style(17.sp, FontWeight.Medium), modifier = Modifier.semantics { heading() })
            Text(step.explanation, style = NoirType.style(14.sp, color = Noir.TextDialogBody).copy(lineHeight = 26.sp))
        }
        EvidenceBox(step.evidenceHeading, step.profileName, step.reasons)
        Text(step.warning, style = NoirType.style(12.sp, color = RV.Note).copy(lineHeight = 20.sp))
        Disclosure(step.branchesSummary) {
            if (step.branches.isEmpty()) {
                ListRow(step.branchesEmpty ?: "", null)
            } else {
                step.branches.forEach { ListRow(it.name, it.value) }
            }
        }
        StepNav(
            step.position,
            step.canPrevious,
            step.canNext,
            { callbacks.selectOpponent(step.index - 1) },
            { callbacks.selectOpponent(step.index + 1) },
        )
    }
}

// ---- Scope and method --------------------------------------------------------------

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Method() {
    val uri = LocalUriHandler.current
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(Copy.scope, style = NoirType.style(12.sp, color = Noir.TextSubtle).copy(lineHeight = 20.sp))
        Box(Modifier.fillMaxWidth().height(1.dp).background(RV.MethodRule))
        Disclosure(Copy.methodSummary) {
            Copy.methodParagraphs.forEach { Text(it, style = NoirType.style(12.sp, color = RV.Note).copy(lineHeight = 21.sp)) }
            FlowRow(itemVerticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(Copy.methodReferencesLabel, style = NoirType.style(12.sp, color = RV.Note))
                Copy.methodReferences.forEach { (label, url) ->
                    Box(
                        Modifier
                            .heightIn(min = 44.dp)
                            .clickable(role = Role.Button) { runCatching { uri.openUri(url) } }
                            .semantics { stateDescription = UiCopy.opensInBrowser },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(label, style = NoirType.style(12.sp, color = Color(0xFF86CCB8)).copy(textDecoration = TextDecoration.Underline))
                    }
                }
            }
            Copy.methodClosingParagraphs.forEach { Text(it, style = NoirType.style(12.sp, color = RV.Note).copy(lineHeight = 21.sp)) }
        }
    }
}
