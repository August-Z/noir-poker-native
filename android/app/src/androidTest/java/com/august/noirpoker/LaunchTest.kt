package com.august.noirpoker

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.performClick
import org.junit.Rule
import org.junit.Test

class LaunchTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    @Test fun opensNativeRulesDialog() {
        compose.onNodeWithText("NOIR").assertIsDisplayed()
        compose.onNodeWithText("How to Play").performClick()
        compose.onNodeWithText("Got It").assertIsDisplayed().performClick()
    }
}
