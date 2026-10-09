package com.august.noirpoker

import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.session.TableRenderState
import com.august.noirpoker.ui.UiCopy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class LaunchTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    private val state: TableRenderState get() = compose.runOnUiThread { compose.activity.tableModel.state }

    private val activityRows = hasTestTag("activity-entry") and hasAnyAncestor(hasTestTag("activity-list"))

    @Test fun opensTheTableAndTheNativeRulesSheet() {
        compose.onNodeWithText("NOIR").assertIsDisplayed()
        // The first hand is dealt at launch and the action panel is on screen.
        compose.onNodeWithText("Hand 01").assertExists()
        assertTrue(compose.onAllNodesWithText("Fold").fetchSemanticsNodes().isNotEmpty())
        compose.onNodeWithText("How to Play").performClick()
        compose.onNodeWithText("Five minutes to a seat at the table.").assertIsDisplayed()
        compose.onNodeWithText("Back to Table").assertIsDisplayed().performClick()
        compose.waitForIdle()
        assertTrue(compose.onAllNodesWithText("Back to Table").fetchSemanticsNodes().isEmpty())
    }

    @Test fun handActivityListsEveryLoggedEntry() {
        compose.onNodeWithText(UiCopy.activityTitle).assertExists()
        assertOneRowPerActivityEntry()

        // Play the hand out quickly, then compare again against the complete log.
        compose.runOnUiThread { compose.activity.tableScheduler.timeScale = 25.0 }
        compose.waitUntil(60_000) {
            state.let { it.phase == Phase.DONE || (it.phase == Phase.PLAYING && it.actions.controlsVisible && it.actions.foldEnabled) }
        }
        if (state.phase != Phase.DONE) {
            val fold = compose.onNodeWithTag("fold")
            runCatching { fold.performScrollTo() }
            fold.performClick()
        }
        compose.waitUntil(60_000) { state.let { it.phase == Phase.DONE && it.actions.nextHandVisible } }
        assertTrue("A finished hand logs several entries", state.activity.entries.size > 2)
        assertOneRowPerActivityEntry()
    }

    /** The list is complete and untruncated: one row per render-state entry. */
    private fun assertOneRowPerActivityEntry() {
        fun rows() = compose.onAllNodes(activityRows).fetchSemanticsNodes().size
        // A bot may act between reading the state and the next frame; wait for them to agree.
        try {
            compose.waitUntil(5_000) { rows() == state.activity.entries.size }
        } catch (timeout: ComposeTimeoutException) {
            // Fall through to the assertion, which reports both counts.
        }
        assertEquals("One activity row per logged entry", state.activity.entries.size, rows())
    }
}
