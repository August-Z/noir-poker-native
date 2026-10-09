package com.august.noirpoker

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.august.noirpoker.NoirAppRobot.Companion.REAL_TIME
import com.august.noirpoker.NoirAppRobot.Companion.STARTING_STACK
import com.august.noirpoker.core.Phase
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

/** Plays real hands through the native table: settlement, Finish Hand, Replay, Next Hand, reset and reveals. */
@RunWith(AndroidJUnit4::class)
class HandFlowTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val app = NoirAppRobot(compose)

    @After fun tearDown() = app.close()

    private fun assertChipsConserved() {
        val snapshot = app.snapshot()
        assertEquals("Chips are conserved", snapshot.playerCount * STARTING_STACK, snapshot.wealth)
    }

    @Test fun launchesAndPlaysAHandToSettlement() {
        app.launch()
        compose.onNodeWithText(UiCopy.brandNoir).assertIsDisplayed()
        assertEquals(1, app.state.hand)
        assertEquals(6, app.state.playerCount)

        app.callDown()

        val state = app.state
        assertEquals(Phase.DONE, state.phase)
        assertEquals(1, state.session.hands)
        assertFalse("The decision strip hides once the hand is over", state.actions.decisionStripVisible)
        assertNull(state.hero.turnText)
        app.node("next-hand").assertExists()
        app.node("replay-hand").assertExists()
        assertNotNull("The settled hand reports a result", app.snapshot().result)
        assertChipsConserved()
    }

    @Test fun foldThenFinishHandSettlesAtOnce() {
        app.launch(timeScale = REAL_TIME)
        app.heroFirstHand()
        assertTrue(app.heroToAct)

        app.tap("fold")
        assertTrue(app.state.hero.folded)
        assertTrue("Finish Hand is offered after the hero folds", app.state.actions.finishHandVisible)
        app.tap("continue-deal")

        app.waitForSettlement()
        val snapshot = app.snapshot()
        assertEquals("done", snapshot.phase)
        assertEquals("Finish Hand fills the five community cards", 5, snapshot.board.size)
        assertFalse(snapshot.canContinue)
        assertFalse(app.exists("continue-deal"))
        assertEquals(1, app.state.session.hands)
        assertEquals("Folding UTG costs nothing", STARTING_STACK, snapshot.stack)
        val records = app.onTable { it.session.testHooks.timingRecords() }
        assertTrue("Bots played the rest of the hand", records.isNotEmpty())
        assertTrue("Finish Hand expedites every bot decision", records.all { it.trace.thinking?.expedited == true })
        assertChipsConserved()
    }

    @Test fun replayHandRestoresTheHoleCardsAndReversesTheResultOnce() {
        app.launch()
        app.heroFirstHand()
        val hole = app.snapshot().hole
        val hand = app.state.hand
        app.callDown()
        assertEquals(1, app.state.session.hands)

        app.tap("replay-hand")
        var snapshot = app.snapshot()
        assertEquals("Replay keeps the hand number", hand, snapshot.hand)
        assertEquals("Replay restores the same hole cards", hole, snapshot.hole)
        assertEquals(1, snapshot.replayAttempt)
        assertEquals("Replay restores the starting stack", STARTING_STACK, snapshot.stack)
        assertEquals("The settlement is reversed", 0, app.state.session.hands)
        assertNotNull(app.state.replayBadge)
        assertChipsConserved()

        // Play the replay differently: fold at once. The stats count the hand once.
        app.waitForHeroTurnOrSettlement()
        assertTrue(app.heroToAct)
        app.tap("fold")
        app.waitForSettlement()
        snapshot = app.snapshot()
        assertEquals(hole, snapshot.hole)
        assertEquals(STARTING_STACK, snapshot.stack)
        assertEquals("The replayed hand is counted once", 1, app.state.session.hands)
        assertEquals(STARTING_STACK, app.state.session.stack)
        assertChipsConserved()
    }

    @Test fun nextHandKeepsTheStacks() {
        app.launch()
        app.callDown()
        val before = app.snapshot()
        assertNotEquals("The settled hand moved chips", List(before.playerCount) { STARTING_STACK }, before.players.map { it.stack })

        // Real time from here: no bot can act before the new hand is read.
        app.setTimeScale(REAL_TIME)
        app.tap("next-hand")
        val after = app.snapshot()
        assertEquals(before.hand + 1, after.hand)
        assertEquals(before.playerCount, after.playerCount)
        // A busted player rebuys to the starting stack, as in the reference.
        val carried = before.players.associate { it.id to if (it.stack == 0) STARTING_STACK else it.stack }
        after.players.forEach { p ->
            assertEquals("${p.name} carries the stack into the next hand (only blinds are posted)", carried.getValue(p.id), p.stack + p.bet)
        }
        assertEquals(1, app.state.session.hands)
        assertEquals(carried.values.sum(), after.wealth)
    }

    @Test fun startNewSessionResetsTheStats() {
        app.launch()
        app.callDown()
        assertEquals(1, app.state.session.hands)

        app.setTimeScale(REAL_TIME)
        app.tap("reset")
        compose.onNodeWithText(UiCopy.resetTitle).assertIsDisplayed()
        app.tap("confirm-reset")

        val state = app.state
        assertEquals(0, state.session.hands)
        assertEquals(0, state.session.wins)
        assertEquals(STARTING_STACK, state.session.stack)
        assertEquals(1, state.hand)
        assertFalse(app.exists(hasText(UiCopy.resetTitle)))
        app.snapshot().players.forEach { assertEquals(STARTING_STACK, it.stack + it.bet) }
    }

    @Test fun revealTogglesAppearAfterSettlementAndClearOnNextHand() {
        app.launch()
        app.heroFirstHand()
        assertTrue("No eye toggles while the hand is live", app.state.seats.all { it.peek == null })
        app.tap("fold")
        app.waitForSettlement()

        val seats = app.state.seats
        assertTrue("Every opponent seat has an eye toggle after settlement", seats.all { it.peek != null })
        val seat = seats.first()
        val wasRevealed = seat.revealed
        val toggle = hasTestTag("seat-peek-${seat.id}") or hasTestTag("seat-list-peek-${seat.id}")
        app.tap(toggle)
        val toggled = app.state.seats.first { it.id == seat.id }
        assertNotEquals("The eye toggles that seat's cards", wasRevealed, toggled.revealed)
        assertEquals(toggled.revealed, app.exists("seat-hand-${seat.id}"))
        assertEquals(toggled.revealed, app.snapshot().players.first { it.id == seat.id }.cards != null)
        assertEquals("Other seats are unchanged", seats.drop(1).map { it.revealed }, app.state.seats.drop(1).map { it.revealed })

        app.setTimeScale(REAL_TIME)
        app.tap("next-hand")
        assertTrue("Reveal toggles clear on the next hand", app.state.seats.all { it.peek == null && !it.revealed })
        assertFalse(app.exists(toggle))
        assertTrue(app.snapshot().players.drop(1).all { it.cards == null })
    }
}
