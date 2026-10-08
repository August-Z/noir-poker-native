package com.august.noirpoker

import androidx.compose.runtime.Composable
import androidx.compose.ui.test.DeviceConfigurationOverride
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
 * The table at fixed window sizes and text scales: a phone with the largest
 * accessibility text, and tablet portrait and landscape at six and nine seats.
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

    private fun show(size: DpSize, fontScale: Float = 1f, seats: Int = 6) {
        lateinit var created: TableModel
        compose.runOnUiThread {
            NoirType.install(ManropeFamily)
            created = TableModel(HandlerScheduler(), InMemoryStorage(), reviewRunner = null, random = SeededRandom(NoirAppRobot.DEFAULT_SEED))
            created.session.testHooks.fixture(seats, heroFirst = true) { startHand(it, SeededRandom(NoirAppRobot.DEFAULT_SEED)) }
        }
        model = created
        compose.setContent {
            Configured(size, fontScale) {
                NoirTheme(reducedMotion = true) { NoirTableScreen(created) }
            }
        }
        compose.waitForIdle()
    }

    @Composable
    private fun Configured(size: DpSize, fontScale: Float, content: @Composable () -> Unit) {
        DeviceConfigurationOverride(DeviceConfigurationOverride.ForcedSize(size) then DeviceConfigurationOverride.FontScale(fontScale), content)
    }

    private fun bounds(tag: String): DpRect = compose.onNodeWithTag(tag).getBoundsInRoot()

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
        val table = compose.onNode(hasContentDescription(UiCopy.tableRegionA11y)).getBoundsInRoot()
        val rects = (1 until count).map { id -> bounds("seat-$id") }
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
        val table = compose.onNode(hasContentDescription(UiCopy.tableRegionA11y)).getBoundsInRoot()
        val sidebar = compose.onNodeWithText(UiCopy.sessionTitle).getBoundsInRoot()
        assertTrue("The sidebar sits to the right of the table", sidebar.left >= table.right)
        compose.onNodeWithText(UiCopy.sessionTitle).assertIsDisplayed()
        assertSeats(9)
        assertActionButtons()
    }

    @Test fun tabletPortraitStacksTheSidebarBelowTheTable() {
        show(DpSize(800.dp, 1280.dp), seats = 6)
        val table = compose.onNode(hasContentDescription(UiCopy.tableRegionA11y)).getBoundsInRoot()
        val sidebar = compose.onNodeWithText(UiCopy.sessionTitle).getBoundsInRoot()
        assertTrue("The sidebar sits below the table", sidebar.top >= table.bottom)
        assertSeats(6)
        assertActionButtons()
    }
}
