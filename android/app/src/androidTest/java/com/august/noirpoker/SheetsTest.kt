package com.august.noirpoker

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isPopup
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.august.noirpoker.core.review.ReviewDialogCopy
import com.august.noirpoker.core.review.presentHeroReview
import com.august.noirpoker.core.review.presentOpponentReview
import com.august.noirpoker.core.session.MIXED_LINEUP
import com.august.noirpoker.core.session.ReviewPerspective
import com.august.noirpoker.core.session.ReviewStatus
import com.august.noirpoker.core.session.SessionCopy
import com.august.noirpoker.ui.UiCopy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The native sheets: Hand Review (both tabs) and Opponent Styles (discard and save). */
@RunWith(AndroidJUnit4::class)
class SheetsTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val app = NoirAppRobot(compose)

    @After fun tearDown() = app.close()

    @Test fun handReviewAnalyzesTheHandAndShowsBothTabs() {
        app.launch()
        app.heroFirstHand()
        app.callDown()
        assertTrue(app.state.actions.reviewVisible)

        app.tap("review-hand")
        assertTrue(app.state.review.dialogOpen)
        app.waitFor("the review analysis", timeoutMs = 120_000) { it.review.status == ReviewStatus.DONE || it.review.status == ReviewStatus.ERROR }
        assertEquals(ReviewStatus.DONE, app.state.review.status)

        // Your Decisions: the analysis summary and the priority decision.
        app.node("review-tab-hero").assertIsSelected()
        val hero = checkNotNull(presentHeroReview(app.state.review))
        assertFalse(hero.running)
        val priority = checkNotNull(hero.priorityButton) { "The analysis names a priority decision" }
        app.tapFirst(hasText(priority) and hasClickAction())
        assertEquals(hero.priorityIndex, app.state.review.selected)

        // Opponent Decisions: the execution records with the seat filter.
        app.tap("review-tab-opponents")
        assertEquals(ReviewPerspective.OPPONENTS, app.state.review.perspective)
        app.node("review-tab-opponents").assertIsSelected()
        val opponents = checkNotNull(presentOpponentReview(app.state.review))
        assertTrue("Bots acted in this hand", opponents.timeline.isNotEmpty())
        compose.onNodeWithText(opponents.intro).assertExists()
        app.node("review-opponent-filter").assertExists()

        app.tap("review-tab-hero")
        assertEquals(ReviewPerspective.HERO, app.state.review.perspective)

        app.tap(hasContentDescription(ReviewDialogCopy.closeA11y) and hasClickAction())
        assertFalse(app.state.review.dialogOpen)
    }

    @Test fun opponentStylesDiscardDropsTheDraftAndSaveAppliesNextHand() {
        val preferences = "noir-ui-test-opponents"
        app.launch(preferences = preferences, clearPreferences = true)
        assertEquals(SessionCopy.opponentsSummaryBalanced, app.state.opponents.text)

        // Discard: change seat 2, then close without saving.
        app.tap("opponents")
        var dialog = checkNotNull(app.state.opponentsDialog)
        assertEquals(8, dialog.roster.size)
        assertTrue(dialog.roster.all { it.assignment == "balanced" })
        val seat2 = dialog.roster.first { it.id == 2 }
        val choice = seat2.options.first { it.value != "balanced" }
        app.tap("bot-seat-2")
        app.tap(hasText(choice.label) and hasClickAction() and hasAnyAncestor(isPopup()))
        assertEquals(choice.value, checkNotNull(app.state.opponentsDialog).roster.first { it.id == 2 }.assignment)
        app.tap(hasContentDescription(UiCopy.oppCloseA11y) and hasClickAction())
        assertNull(app.state.opponentsDialog)
        assertEquals(SessionCopy.opponentsSummaryBalanced, app.state.opponents.text)
        assertFalse(app.state.opponents.changePending)

        app.tap("opponents")
        dialog = checkNotNull(app.state.opponentsDialog)
        assertTrue("The discarded draft is gone", dialog.roster.all { it.assignment == "balanced" })

        // Save: the mixed lineup is pending until the next deal.
        app.tap("mix-opponents")
        dialog = checkNotNull(app.state.opponentsDialog)
        MIXED_LINEUP.forEach { (seat, profile) -> assertEquals(profile, dialog.roster.first { it.id == seat }.assignment) }
        app.tap("save-opponents")
        assertNull(app.state.opponentsDialog)
        assertTrue(app.state.opponents.changePending)
        assertEquals(SessionCopy.opponentsSummaryPending, app.state.opponents.text)
        assertNotNull(app.state.opponents.changeNote)
        assertTrue("The current hand keeps its styles", app.snapshot().players.drop(1).all { it.botProfile == "balanced" })

        // Relaunch: the saved styles are applied to the first hand.
        app.close()
        app.launch(preferences = preferences, clearPreferences = false)
        val profiles = app.snapshot().players.drop(1).associate { it.id to it.botProfile }
        (1..5).forEach { seat -> assertEquals(MIXED_LINEUP[seat], profiles[seat]) }
        assertFalse(app.state.opponents.changePending)
        assertNotEquals(SessionCopy.opponentsSummaryBalanced, app.state.opponents.text)
        compose.onNodeWithText(app.state.opponents.text).assertIsDisplayed()
    }
}
