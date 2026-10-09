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
import com.august.noirpoker.NoirAppRobot.Companion.FAST
import com.august.noirpoker.NoirAppRobot.Companion.REAL_TIME
import com.august.noirpoker.NoirAppRobot.Companion.STARTING_STACK
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

/**
 * The native sheets: Hand Review (both tabs, and interrupted by Next Hand or
 * Replay Hand) and Opponent Styles (discard and save).
 */
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

    private fun closeReview() = app.tap(hasContentDescription(ReviewDialogCopy.closeA11y) and hasClickAction())

    private fun assertNoReviewSheet(message: String) {
        assertFalse(message, app.state.review.dialogOpen)
        assertFalse(message, app.exists("review-tab-hero"))
        assertFalse(message, app.exists("review-tab-opponents"))
    }

    private fun assertChipsConserved() {
        val snapshot = app.snapshot()
        assertEquals("Chips are conserved", snapshot.playerCount * STARTING_STACK, snapshot.wealth)
    }

    /** Opens the settled hand's review, waits for the analysis, and closes it again. */
    private fun reviewToCompletion() {
        app.tap("review-hand")
        assertTrue(app.state.review.dialogOpen)
        app.waitFor("the review analysis", timeoutMs = 120_000) { it.review.status == ReviewStatus.DONE || it.review.status == ReviewStatus.ERROR }
        assertEquals(ReviewStatus.DONE, app.state.review.status)
        closeReview()
        assertNoReviewSheet("The review closes")
    }

    @Test fun closingTheReviewMidAnalysisThenNextHandLeavesNoStaleSheet() {
        app.launch()
        app.heroFirstHand()
        app.callDown()
        val hand = app.state.hand

        app.tap("review-hand")
        assertTrue(app.state.review.dialogOpen)
        val firstKey = app.state.review.key
        // Close at once: the analysis runs off the main thread and may still be going.
        closeReview()
        assertNoReviewSheet("Closing hides the review")

        app.setTimeScale(REAL_TIME)
        app.tap("next-hand")
        assertEquals(hand + 1, app.state.hand)
        assertNoReviewSheet("Next Hand leaves no review sheet")
        // A late analysis result for the previous hand must not reopen the sheet.
        Thread.sleep(3_000)
        compose.waitForIdle()
        assertNoReviewSheet("A late analysis result does not reopen the sheet")
        assertFalse("Nothing to review while hand ${hand + 1} is live", app.state.actions.reviewVisible)
        assertEquals(hand + 1, app.state.hand)
        assertChipsConserved()

        // The next hand's review starts fresh and completes.
        app.setTimeScale(FAST)
        app.callDown()
        assertNotEquals(firstKey, app.state.review.key)
        reviewToCompletion()
        assertChipsConserved()
    }

    /**
     * A replay that arrives while Hand Review is open closes the sheet and resets
     * the review. The sheet is modal, so the Replay Hand button sits behind it;
     * the test sends the request through the same session call the button uses.
     */
    @Test fun replayWithTheReviewOpenClosesTheSheetAndResetsTheStatus() {
        app.launch()
        app.heroFirstHand()
        app.callDown()
        val hand = app.state.hand

        app.tap("review-hand")
        assertTrue(app.state.review.dialogOpen)
        app.node("review-tab-hero").assertExists()
        val firstKey = app.state.review.key

        app.setTimeScale(REAL_TIME)
        assertTrue("Replay Hand is accepted", app.onTable { it.session.replayHand() })
        compose.waitForIdle()
        assertEquals(1, app.snapshot().replayAttempt)
        assertEquals(hand, app.state.hand)
        assertNoReviewSheet("Replay closes the review sheet")
        assertEquals("Replay resets the review status", ReviewStatus.IDLE, app.state.review.status)
        assertNull(app.state.review.key)
        assertFalse(app.state.actions.reviewVisible)
        Thread.sleep(3_000)
        compose.waitForIdle()
        assertNoReviewSheet("A late analysis result does not reopen the sheet")
        assertEquals(ReviewStatus.IDLE, app.state.review.status)

        // The replayed hand gets a fresh review once it settles.
        app.setTimeScale(FAST)
        app.callDown()
        assertEquals(1, app.snapshot().replayAttempt)
        assertNotEquals(firstKey, app.state.review.key)
        assertEquals(ReviewStatus.IDLE, app.state.review.status)
        reviewToCompletion()
        assertChipsConserved()
    }

    /**
     * The same interruption through the visible controls: close the review
     * while it may still be analyzing, then tap Replay Hand.
     */
    @Test fun closingTheReviewThenReplayHandResetsTheStatus() {
        app.launch()
        app.heroFirstHand()
        app.callDown()

        app.tap("review-hand")
        assertTrue(app.state.review.dialogOpen)
        closeReview()
        assertNoReviewSheet("Closing hides the review")

        app.setTimeScale(REAL_TIME)
        app.tap("replay-hand")
        assertEquals(1, app.snapshot().replayAttempt)
        assertEquals(ReviewStatus.IDLE, app.state.review.status)
        assertNoReviewSheet("Replay leaves no review sheet")
        assertChipsConserved()
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
