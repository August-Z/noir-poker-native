package com.august.noirpoker

import androidx.compose.runtime.Composable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.click
import androidx.compose.ui.test.isOff
import androidx.compose.ui.test.isOn
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import com.august.noirpoker.core.Action
import com.august.noirpoker.core.Game
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.act
import com.august.noirpoker.core.advanceStreet
import org.junit.Assert.assertEquals
import kotlin.math.roundToInt
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.ForcedSize
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.then
import androidx.compose.ui.unit.DpRect
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.august.noirpoker.core.SeededRandom
import com.august.noirpoker.core.session.InMemoryStorage
import com.august.noirpoker.core.startHand
import com.august.noirpoker.platform.HandlerScheduler
import com.august.noirpoker.ui.UiCopy
import com.august.noirpoker.ui.table.NoirTableScreen
import com.august.noirpoker.ui.table.TableModel
import com.august.noirpoker.ui.theme.ManropeFamily
import com.august.noirpoker.ui.theme.NoirTheme
import com.august.noirpoker.ui.theme.NoirType
import org.junit.After
import kotlin.math.hypot
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The table at fixed window sizes and text scales: phones with the largest
 * accessibility text at six and nine seats, and tablet portrait and landscape
 * at six and nine seats; settled hands for the eye toggles and the showdown
 * grid; and one pass with full motion.
 * Each case deals a seeded hand where the hero acts first, so the action panel
 * is live and no bot moves while the layout is checked.
 */
@RunWith(AndroidJUnit4::class)
class AdaptiveLayoutTest {
    @get:Rule val compose = createComposeRule()
    private var model: TableModel? = null

    @After fun tearDown() {
        compose.runOnUiThread { model?.close() }
    }

    /**
     * Shows the table at [size] and [fontScale] with a seeded [seats]-handed deal
     * where the hero acts first. With [settled] every player calls down to a
     * five-card showdown (no bot is ever scheduled), so the eye toggles and the
     * showdown stage are on screen. [reducedMotion] false runs the full motion path.
     */
    private fun show(
        size: DpSize,
        fontScale: Float = 1f,
        seats: Int = 6,
        settled: Boolean = false,
        reducedMotion: Boolean = true,
    ) {
        lateinit var created: TableModel
        compose.runOnUiThread {
            NoirType.install(ManropeFamily)
            created = TableModel(HandlerScheduler(), InMemoryStorage(), reviewRunner = null, random = SeededRandom(NoirAppRobot.DEFAULT_SEED))
            created.session.testHooks.fixture(seats, heroFirst = true) { game ->
                startHand(game, SeededRandom(NoirAppRobot.DEFAULT_SEED))
                if (settled) callDownToShowdown(game)
            }
        }
        model = created
        compose.setContent {
            Configured(size, fontScale) {
                NoirTheme(reducedMotion = reducedMotion) { NoirTableScreen(created) }
            }
        }
        compose.waitForIdle()
    }

    /** Every player checks or calls each street; the river settles at a showdown. */
    private fun callDownToShowdown(game: Game) {
        var steps = 0
        while (game.phase != Phase.DONE) {
            check(steps++ < 500) { "The call-down did not settle" }
            if (game.phase == Phase.BETWEEN) advanceStreet(game) else act(game, game.actor, Action.CALL)
        }
        check(game.showdown && game.board.size == 5) { "The call-down ends at a five-card showdown" }
    }

    @Composable
    private fun Configured(size: DpSize, fontScale: Float, content: @Composable () -> Unit) {
        DeviceConfigurationOverride(DeviceConfigurationOverride.ForcedSize(size) then DeviceConfigurationOverride.FontScale(fontScale), content)
    }

    private fun bounds(tag: String): DpRect = compose.onNodeWithTag(tag).getBoundsInRoot()

    /**
     * The node's laid-out rectangle in the root, in dp, not clipped to the visible
     * viewport. `getBoundsInRoot` clips to the scrolling column, so a seat scrolled
     * below the window edge (a 9-seat arena on a phone, or after scrolling to the
     * action panel) would report an empty rectangle although it is laid out.
     */
    private fun layoutBounds(matcher: SemanticsMatcher): DpRect {
        val node = compose.onNode(matcher).fetchSemanticsNode()
        val position = node.positionInRoot
        return with(node.layoutInfo.density) {
            DpRect(
                position.x.toDp(),
                position.y.toDp(),
                (position.x + node.size.width).toDp(),
                (position.y + node.size.height).toDp(),
            )
        }
    }

    private fun layoutBounds(tag: String): DpRect = layoutBounds(hasTestTag(tag))

    private fun tableBounds(): DpRect = layoutBounds(hasContentDescription(UiCopy.tableRegionA11y))

    private fun DpRect.overlaps(other: DpRect) = left < other.right && other.left < right && top < other.bottom && other.top < bottom

    /** Fold, Check / Call and Raise are on screen, at least 48 dp tall, enabled, labelled and side by side or stacked without overlap. */
    private fun assertActionButtons() {
        val actions = checkNotNull(model).state.actions
        listOf("fold" to actions.foldLabel, "call" to actions.callLabel, "raise" to actions.raiseCaption).forEach { (tag, label) ->
            val node = compose.onNodeWithTag(tag)
            node.performScrollTo().assertIsDisplayed().assertIsEnabled()
            compose.onNode(hasTestTag(tag) and hasText(label, substring = true, ignoreCase = true)).assertExists()
            val b = bounds(tag)
            assertTrue("$tag is at least 48 dp tall (${b.bottom - b.top})", b.bottom - b.top >= 48.dp)
        }
        val rects = listOf("fold", "call", "raise").map(::bounds)
        rects.forEachIndexed { i, a ->
            rects.drop(i + 1).forEach { b -> assertTrue("Action buttons do not overlap", !a.overlaps(b)) }
        }
    }

    /** Every opponent seat is laid out inside the table, each in its own place. */
    private fun assertSeats(count: Int) {
        val table = tableBounds()
        val rects = (1 until count).map { id -> layoutBounds("seat-$id") }
        rects.forEachIndexed { i, a ->
            val seat = i + 1
            assertTrue("Seat $seat has a size", a.right > a.left && a.bottom > a.top)
            assertTrue("Seat $seat is inside the table horizontally", a.left >= table.left - 1.dp && a.right <= table.right + 1.dp)
            rects.drop(i + 1).forEachIndexed { j, b ->
                val dx = ((a.left + a.right - b.left - b.right) / 2).value
                val dy = ((a.top + a.bottom - b.top - b.bottom) / 2).value
                assertTrue("Seats $seat and ${seat + j + 1} have distinct places", hypot(dx, dy) >= 24f)
            }
        }
    }

    private fun seat(id: Int) = checkNotNull(model).state.seats.first { it.id == id }

    /** Lets the session's render reach the screen (the clock is advanced by hand while auto-advance is off). */
    private fun settleFrames() {
        if (compose.mainClock.autoAdvance) compose.waitForIdle() else compose.mainClock.advanceTimeBy(FRAME_MS)
    }

    /**
     * Every opponent's eye toggle (tags `[prefix]1` … `[prefix]count-1`) is a
     * switch with a touch and accessibility target of at least 48 × 48 dp, reports
     * On / Off, and toggles only its own seat, also when tapped outside the 22 dp
     * icon but inside the 48 dp target.
     */
    private fun assertRevealToggles(count: Int, prefix: String) {
        for (id in 1 until count) {
            val tag = "$prefix$id"
            val node = compose.onNodeWithTag(tag)
            runCatching { node.performScrollTo() }
            settleFrames()
            node.assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch))
            val semantics = node.fetchSemanticsNode()
            val touch = with(semantics.layoutInfo.density) {
                semantics.touchBoundsInRoot.let { DpSize(it.width.toDp(), it.height.toDp()) }
            }
            assertTrue("$tag touch target is at least 48 dp wide ($touch)", touch.width >= 47.5.dp)
            assertTrue("$tag touch target is at least 48 dp tall ($touch)", touch.height >= 47.5.dp)

            val before = seat(id).revealed
            val others = checkNotNull(model).state.seats.filter { it.id != id }.map { it.id to it.revealed }
            node.assert(if (before) isOn() else isOff())
            node.performClick()
            settleFrames()
            assertEquals("$tag toggles seat $id", !before, seat(id).revealed)
            compose.onNodeWithTag(tag).assert(if (before) isOff() else isOn())
            assertEquals("$tag leaves the other seats unchanged", others, checkNotNull(model).state.seats.filter { it.id != id }.map { it.id to it.revealed })

            // 16 dp left of the icon's center is outside the 22 dp icon, inside the 48 dp target.
            compose.onNodeWithTag(tag).performTouchInput { click(center - Offset(16.dp.toPx(), 0f)) }
            settleFrames()
            assertEquals("A tap beside the icon toggles seat $id back", before, seat(id).revealed)
            compose.onNodeWithTag(tag).assert(if (before) isOn() else isOff())
        }
    }

    @Test fun largeAccessibilityTextKeepsTheActionButtonsUsable() {
        show(DpSize(390.dp, 844.dp), fontScale = 2f)
        assertActionButtons()
        // Above 1.3× the arena keeps its scale and the full-size seat list carries the details.
        compose.onNodeWithText(UiCopy.brandNoir).assertIsDisplayed()
        assertSeats(6)
    }

    @Test fun compactPhoneSeatsNinePlayers() {
        show(DpSize(360.dp, 740.dp), seats = 9)
        assertSeats(9)
        assertActionButtons()
    }

    @Test fun tabletLandscapePlacesTheSidebarBesideTheTable() {
        show(DpSize(1280.dp, 800.dp), seats = 9)
        val table = tableBounds()
        val sidebar = layoutBounds(hasText(UiCopy.sessionTitle))
        assertTrue("The sidebar sits to the right of the table", sidebar.left >= table.right)
        compose.onNodeWithText(UiCopy.sessionTitle).assertIsDisplayed()
        assertSeats(9)
        assertActionButtons()
    }

    @Test fun tabletPortraitStacksTheSidebarBelowTheTable() {
        show(DpSize(800.dp, 1280.dp), seats = 6)
        val table = tableBounds()
        val sidebar = layoutBounds(hasText(UiCopy.sessionTitle))
        assertTrue("The sidebar sits below the table", sidebar.top >= table.bottom)
        assertSeats(6)
        assertActionButtons()
    }

    @Test fun nineSeatsWithLargeAccessibilityText() {
        show(DpSize(390.dp, 844.dp), fontScale = 2f, seats = 9)
        assertActionButtons()
        assertSeats(9)
        // The full-size seat list below the arena names every opponent.
        checkNotNull(model).state.seats.forEach { seat ->
            assertTrue("${seat.name} appears in the arena and the seat list", compose.onAllNodes(hasText(seat.name)).fetchSemanticsNodes().size >= 2)
        }
    }

    @Test fun tabletPortraitSeatsNinePlayers() {
        show(DpSize(800.dp, 1280.dp), seats = 9)
        val table = tableBounds()
        val sidebar = layoutBounds(hasText(UiCopy.sessionTitle))
        assertTrue("The sidebar sits below the table", sidebar.top >= table.bottom)
        assertSeats(9)
        assertActionButtons()
    }

    @Test fun settledRevealTogglesHaveFullSizeTouchTargets() {
        show(DpSize(360.dp, 740.dp), seats = 9, settled = true)
        assertTrue("Every opponent has an eye toggle after settlement", checkNotNull(model).state.seats.all { it.peek != null })
        assertSeats(9)
        assertRevealToggles(9, "seat-peek-")
    }

    @Test fun settledRevealTogglesWithLargeTextInTheSeatList() {
        show(DpSize(390.dp, 844.dp), fontScale = 2f, seats = 6, settled = true)
        assertRevealToggles(6, "seat-list-peek-")
        assertRevealToggles(6, "seat-peek-")
    }

    @Test fun tabletPortraitShowdownUsesTwoColumns() {
        show(DpSize(800.dp, 1280.dp), seats = 6, settled = true)
        assertShowdownColumns(2)
    }

    @Test fun tabletLandscapeShowdownUsesOneColumnBesideTheSidebar() {
        show(DpSize(1000.dp, 800.dp), seats = 6, settled = true)
        assertShowdownColumns(1)
    }

    /** The scene panels (one per player at showdown) sit in [columns] distinct columns. */
    private fun assertShowdownColumns(columns: Int) {
        val scenes = checkNotNull(model).state.showdown!!.scenes
        val lefts = scenes.map { scene ->
            val node = compose.onNode(hasContentDescription(scene.a11y))
            runCatching { node.performScrollTo() }
            layoutBounds(hasContentDescription(scene.a11y)).left.value.roundToInt()
        }
        assertEquals("Showdown columns", columns, lefts.distinct().size)
    }

    /**
     * The full motion path (every other test runs with reduced motion): the deal,
     * the winner motions and the reveal fade play on the test clock, and the
     * layout, showdown and eye toggles end up the same as with reduced motion.
     */
    @Test fun fullMotionPlaysTheShowdownAndKeepsTheLayout() {
        compose.mainClock.autoAdvance = false
        show(DpSize(390.dp, 844.dp), seats = 9, settled = true, reducedMotion = false)
        compose.mainClock.advanceTimeBy(FRAME_MS)
        compose.onNode(hasContentDescription(UiCopy.showdownRegionA11y)).assertExists()
        // Mid-motion and after the longest winner motion (2,800 ms).
        compose.mainClock.advanceTimeBy(400)
        assertSeats(9)
        compose.mainClock.advanceTimeBy(3_000)
        compose.onNode(hasContentDescription(UiCopy.showdownRegionA11y)).assertExists()
        assertSeats(9)
        assertRevealToggles(9, "seat-peek-")
        // Toggle a seat on and let its 180 ms fade finish: its cards are shown.
        val id = 1
        if (seat(id).revealed) {
            compose.onNodeWithTag("seat-peek-$id").performClick()
            compose.mainClock.advanceTimeBy(FRAME_MS)
        }
        compose.onNodeWithTag("seat-peek-$id").performClick()
        compose.mainClock.advanceTimeBy(300)
        assertTrue(seat(id).revealed)
        compose.onNodeWithTag("seat-hand-$id").assertExists()
    }

    private companion object {
        const val FRAME_MS = 32L
    }
}
