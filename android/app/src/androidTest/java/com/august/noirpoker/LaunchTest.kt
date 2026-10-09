package com.august.noirpoker

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class LaunchTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

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
}
