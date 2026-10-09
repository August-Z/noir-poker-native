package com.august.noirpoker

import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.august.noirpoker.core.Phase
import com.august.noirpoker.ui.UiCopy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The Settings sheet: table size chosen there is applied by the next deal and
 * kept across relaunches, and its rows use the shared UI copy.
 */
@RunWith(AndroidJUnit4::class)
class SettingsPersistenceTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val app = NoirAppRobot(compose)

    @After fun tearDown() = app.close()

    private val seatOption9 = hasText("9") and hasClickAction() and hasAnyAncestor(hasTestTag("settings-seats"))

    @Test fun nineSeatsApplyOnTheNextHandAndPersistAcrossRelaunch() {
        val preferences = "noir-ui-test-seats"
        app.launch(preferences = preferences, clearPreferences = true)
        assertEquals(6, app.state.playerCount)

        app.tap("settings")
        compose.onNodeWithText(UiCopy.settingsTitle).assertIsDisplayed()
        app.tap(seatOption9)
        compose.onNode(seatOption9).assertIsSelected()
        assertEquals(9, app.state.settings.requestedSeatCount)
        assertNotNull("A note says the new size applies next hand", app.state.settings.tableChangeNote)
        assertEquals("The current hand keeps its seats", 6, app.state.playerCount)
        app.tap(hasText(UiCopy.backToTable) and hasClickAction())

        // Finish the current hand: fold at the first turn and let the bots play it out.
        app.waitForHeroTurnOrSettlement()
        if (app.state.phase != Phase.DONE) app.tap("fold")
        app.waitForSettlement()
        assertEquals(6, app.state.playerCount)

        app.tap("next-hand")
        assertEquals("Nine seats from the next hand", 9, app.state.playerCount)
        assertEquals(8, app.state.seats.size)
        assertNull(app.state.settings.tableChangeNote)
        app.state.seats.forEach { app.node("seat-${it.id}").assertExists() }

        // Relaunch with the same preferences file: the table opens with nine seats.
        app.close()
        app.launch(preferences = preferences, clearPreferences = false)
        assertEquals(9, app.state.playerCount)
        assertEquals(9, app.state.settings.requestedSeatCount)
        app.tap("settings")
        compose.onNode(seatOption9).assertIsSelected()
    }

    @Test fun settingsSheetUsesTheSharedCopyAndOpensOpponentStyles() {
        app.launch(preferences = "noir-ui-test-settings-copy", clearPreferences = true)

        app.tap("settings")
        compose.onNodeWithText(UiCopy.settingsTitle).assertIsDisplayed()
        app.node("settings-hints").assert(hasText(UiCopy.settingsHints))
        app.node("settings-sound").assert(hasText(UiCopy.settingsSound))
        app.node("settings-opponents").assert(hasText(UiCopy.opponentsButton))
        app.node("settings-opponents").assert(hasText(app.state.opponents.text))

        // The Opponent Styles row closes Settings and opens the opponents sheet.
        assertNull(app.state.opponentsDialog)
        app.tap("settings-opponents")
        app.waitFor("the opponents sheet") { it.opponentsDialog != null }
        compose.onNodeWithText(UiCopy.oppTitle).assertIsDisplayed()
        assertTrue("Settings closed", compose.onAllNodesWithText(UiCopy.settingsTitle).fetchSemanticsNodes().isEmpty())
    }
}
