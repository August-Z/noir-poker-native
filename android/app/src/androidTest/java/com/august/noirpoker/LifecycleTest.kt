package com.august.noirpoker

import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.august.noirpoker.core.BotDecisionRecord
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.SeededRandom
import com.august.noirpoker.core.session.BotWaitInfo
import com.august.noirpoker.core.session.PublicTableSnapshot
import com.august.noirpoker.core.session.ReviewStatus
import com.august.noirpoker.core.session.TableRenderState
import com.august.noirpoker.core.startHand
import com.august.noirpoker.platform.LaunchOptions
import com.august.noirpoker.ui.UiCopy
import com.august.noirpoker.ui.table.TableModel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Activity recreation, rotation and process background / foreground while a
 * bot is thinking or a review is running.
 *
 * The table model lives in the activity's view model, so a configuration change
 * keeps the hand, the stacks, the thinking bot's plan and its deadline, and the
 * open sheet. Only the process lifecycle backgrounds the table: Home stops the
 * process (about 700 ms after the activity stops), which cancels the bot timer
 * and pauses the review job; returning runs the kept plan once and restarts the
 * review. A Finish Hand fast-forward is cancelled by the background and must be
 * tapped again (see docs/SESSION.md).
 *
 * The bot is made to think on a slowed session clock (1/50 of real time), so no
 * decision can land while the test recreates, rotates or leaves the activity.
 * The plan and the bot execution records are read through the session's test
 * hooks; everything else is the public table snapshot.
 */
@RunWith(AndroidJUnit4::class)
class LifecycleTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val app = LifecycleApp(compose)

    @After fun tearDown() = app.close()

    private fun assertChipsConserved() {
        val snapshot = app.snapshot()
        assertEquals("Chips are conserved", snapshot.playerCount * STARTING_STACK, snapshot.wealth)
    }

    /** Hero first to act preflop; calling hands the turn to a bot that thinks on the slow clock. */
    private fun startSlowBotThinking(): BotWaitInfo {
        app.launch(timeScale = REAL_TIME)
        app.onTable { it.session.testHooks.fixture(6, heroFirst = true) { game -> startHand(game, SeededRandom(SEED)) } }
        compose.waitForIdle()
        app.setTimeScale(SLOW)
        app.tap(hasTestTag("call"))
        val plan = checkNotNull(app.thinking()) { "A bot thinks after the hero calls" }
        assertNotEquals("The thinking seat is an opponent", 0, plan.actor)
        assertTrue(app.onTable { it.session.testHooks.hasPendingTimer })
        return plan
    }

    /**
     * Lets the kept plan run on the real-time clock and checks that it ran
     * exactly once. The next bot needs at least 1.2 s, so the count is read
     * before anyone else can act.
     */
    private fun assertPlanRunsOnce(plan: BotWaitInfo, recordsBefore: Int) {
        app.pollUntil("the thinking bot to act", 15_000) { app.records().size > recordsBefore }
        val records = app.records()
        assertEquals("The kept plan runs exactly once (no duplicate action)", recordsBefore + 1, records.size)
        val executed = records.last()
        assertEquals("The bot that was thinking is the one that acts", plan.actor, executed.id)
        assertEquals("The kept plan runs: no new thinking time was drawn", plan.delayMs, executed.trace.thinking?.durationMs)
        assertChipsConserved()
    }

    @Test fun recreatingTheActivityKeepsTheHandThePlanAndTheOpenSheet() {
        val plan = startSlowBotThinking()
        app.tap(hasTestTag("settings"))
        assertTrue(app.exists(hasText(UiCopy.settingsTitle)))
        val snapshot = app.snapshot()
        val records = app.records().size
        val settings = app.state.settings
        val before = app.activityId()

        app.recreate()

        assertNotEquals("The activity was recreated", before, app.activityId())
        assertEquals("Hand, stacks, actor and board are unchanged", snapshot, app.snapshot())
        assertEquals("The same plan keeps its deadline (no restart, no new draws)", plan, app.thinking())
        assertEquals("No bot acted during the recreation", records, app.records().size)
        assertFalse("A configuration change never backgrounds the table", app.state.backgrounded)
        assertEquals(settings, app.state.settings)
        assertTrue("The Settings sheet is still open", app.exists(hasText(UiCopy.settingsTitle)))

        app.setTimeScale(REAL_TIME)
        app.onTable { it.session.testHooks.resumeBots() }
        assertPlanRunsOnce(plan, records)
    }

    @Test fun rotatingWhileABotThinksKeepsTheTableAndThePotSheet() {
        val plan = startSlowBotThinking()
        app.tap(hasTestTag("pot-details"))
        assertTrue(app.state.potDetails.open)
        val title = app.state.potDetails.title
        assertTrue(app.exists(hasText(title)))
        val snapshot = app.snapshot()
        val records = app.records().size
        val before = app.activityId()

        app.rotate(landscape = true)
        assertNotEquals("Rotation recreated the activity", before, app.activityId())
        assertEquals(snapshot, app.snapshot())
        assertEquals("The thinking bot keeps its plan and deadline", plan, app.thinking())
        assertEquals(records, app.records().size)
        assertFalse(app.state.backgrounded)
        assertTrue("The pot sheet is still open", app.state.potDetails.open)
        assertTrue(app.exists(hasText(title)))

        app.rotate(landscape = false)
        assertEquals(snapshot, app.snapshot())
        assertEquals(plan, app.thinking())
        assertTrue(app.state.potDetails.open)

        app.setTimeScale(REAL_TIME)
        app.onTable { it.session.testHooks.resumeBots() }
        assertPlanRunsOnce(plan, records)
    }

    @Test fun backgroundPausesTheThinkingBotAndTheSamePlanRunsAfterReturn() {
        val plan = startSlowBotThinking()
        val snapshot = app.snapshot()
        val records = app.records().size
        val hand = app.state.hand

        app.pressHome()
        assertTrue(app.state.backgrounded)
        assertFalse("No bot timer runs in the background", app.onTable { it.session.testHooks.hasPendingTimer })
        assertEquals("The thinking bot keeps its plan", plan.actor, app.thinking()?.actor)
        assertEquals(plan.delayMs, app.thinking()?.delayMs)

        // Run the session clock fast while away: far past any thinking time.
        app.setTimeScale(FAST)
        SystemClock.sleep(1_500)
        assertEquals("No bot acts while the app is in the background", records, app.records().size)
        assertEquals(snapshot, app.snapshot())

        app.setTimeScale(REAL_TIME)
        app.bringToFront()
        assertFalse(app.state.backgrounded)
        val resumed = checkNotNull(app.thinking()) { "The bot is still thinking after the return" }
        assertEquals("The same bot resumes", plan.actor, resumed.actor)
        assertEquals("The same plan resumes without new random draws", plan.delayMs, resumed.delayMs)
        assertEquals(hand, app.state.hand)
        assertPlanRunsOnce(plan, records)
    }

    @Test fun backgroundDuringAReviewRestartsTheAnalysisOnReturn() {
        app.launch(timeScale = FAST)
        app.onTable { it.session.testHooks.fixture(6, heroFirst = true) { game -> startHand(game, SeededRandom(SEED)) } }
        compose.waitForIdle()
        app.callDown()
        app.setTimeScale(REAL_TIME)
        val snapshot = app.snapshot()
        app.tap(hasTestTag("review-hand"))
        assertTrue(app.state.review.dialogOpen)
        val jobAtOpen = app.state.review.jobId

        app.pressHome()
        val away = app.state.review
        assertTrue("The review stays open in the background", away.dialogOpen)
        when (away.status) {
            ReviewStatus.IDLE -> {
                // The running job was cancelled and its id moved on, so a late result is dropped.
                assertTrue("The paused job is replaced", away.jobId > jobAtOpen)
                assertEquals(0, away.progress)
                SystemClock.sleep(2_000)
                assertEquals("No analysis runs in the background", ReviewStatus.IDLE, app.state.review.status)
                assertEquals(away.jobId, app.state.review.jobId)

                app.bringToFront()
                assertTrue("The analysis restarts with a new job", app.state.review.jobId > away.jobId)
            }
            ReviewStatus.DONE -> {
                // The analysis finished before the process stopped: a finished review survives.
                SystemClock.sleep(2_000)
                app.bringToFront()
                assertEquals(away.jobId, app.state.review.jobId)
            }
            else -> fail("Unexpected review status in the background: ${away.status}")
        }
        app.pollUntil("the review analysis", 120_000) { it.review.status == ReviewStatus.DONE || it.review.status == ReviewStatus.ERROR }
        val review = app.state.review
        assertEquals(ReviewStatus.DONE, review.status)
        assertNotNull(review.analysis)
        assertTrue(review.dialogOpen)
        assertTrue("The review sheet is shown again", app.exists(hasTestTag("review-tab-hero")))
        assertEquals("The settled table is unchanged", snapshot, app.snapshot())
        assertChipsConserved()
    }

    private companion object {
        const val SEED = 20_260_101L
        const val STARTING_STACK = 5_000
        const val REAL_TIME = 1.0
        const val FAST = 25.0
        /** Bot thinking (1.2–8 s) takes 1–7 minutes of real time. */
        const val SLOW = 0.02
    }
}

/**
 * Launches the app like [NoirAppRobot] and adds the lifecycle controls this
 * suite needs: recreation, rotation, Home and return. While the activity is
 * stopped, Compose is not drawing, so these helpers poll the model on the main
 * thread instead of waiting for Compose to be idle.
 */
private class LifecycleApp(private val compose: ComposeTestRule) {
    private var scenario: ActivityScenario<MainActivity>? = null
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    fun launch(timeScale: Double) {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(LaunchOptions.EXTRA_SEED, NoirAppRobot.DEFAULT_SEED)
            .putExtra(LaunchOptions.EXTRA_PREFERENCES, "noir-ui-test-lifecycle")
            .putExtra(LaunchOptions.EXTRA_CLEAR_PREFERENCES, true)
            .putExtra(LaunchOptions.EXTRA_TIME_SCALE, timeScale)
        scenario = ActivityScenario.launch(intent)
        compose.waitForIdle()
    }

    fun close() {
        scenario?.let { s ->
            runCatching { s.onActivity { it.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED } }
            s.close()
        }
        scenario = null
    }

    private val current: ActivityScenario<MainActivity> get() = checkNotNull(scenario) { "Launch the app first" }

    fun <T> onTable(block: (TableModel) -> T): T = onActivity { block(it.tableModel) }

    fun <T> onActivity(block: (MainActivity) -> T): T {
        var result: Result<T>? = null
        current.onActivity { result = runCatching { block(it) } }
        return checkNotNull(result).getOrThrow()
    }

    val state: TableRenderState get() = onTable { it.state }

    fun snapshot(): PublicTableSnapshot = onTable { it.session.publicSnapshot() }

    fun thinking(): BotWaitInfo? = onTable { it.session.testHooks.thinking() }

    fun records(): List<BotDecisionRecord> = onTable { it.session.testHooks.timingRecords() }

    fun activityId(): Int = onActivity { System.identityHashCode(it) }

    fun setTimeScale(scale: Double) = onActivity { it.tableScheduler.timeScale = scale }

    fun exists(matcher: SemanticsMatcher): Boolean =
        compose.onAllNodes(matcher, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    fun tap(matcher: SemanticsMatcher) {
        val node = compose.onNode(matcher)
        runCatching { node.performScrollTo() }
        node.performClick()
        compose.waitForIdle()
    }

    /** Polls [condition] on the main thread without waiting for Compose. */
    fun pollUntil(description: String, timeoutMs: Long, condition: (TableRenderState) -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + timeoutMs
        while (!condition(state)) {
            if (SystemClock.uptimeMillis() > deadline) throw AssertionError("Timed out waiting for $description")
            SystemClock.sleep(20)
        }
    }

    private fun pollFor(description: String, timeoutMs: Long, condition: () -> Boolean) =
        pollUntil(description, timeoutMs) { _ -> condition() }

    /** Plays the current hand to settlement, checking or calling at every hero turn. */
    fun callDown() {
        while (true) {
            compose.waitUntil(60_000) {
                state.let { (it.phase == Phase.PLAYING && it.actions.controlsVisible && it.actions.foldEnabled) || it.phase == Phase.DONE }
            }
            if (state.phase == Phase.DONE) break
            tap(hasTestTag("call"))
        }
        compose.waitUntil(60_000) { state.phase == Phase.DONE && state.actions.nextHandVisible }
        compose.waitForIdle()
    }

    /** Recreates the activity, as a configuration change does. */
    fun recreate() {
        current.recreate()
        compose.waitForIdle()
    }

    fun rotate(landscape: Boolean) {
        val wanted = if (landscape) Configuration.ORIENTATION_LANDSCAPE else Configuration.ORIENTATION_PORTRAIT
        onActivity {
            it.requestedOrientation = if (landscape) ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
        pollFor("the rotation", 10_000) {
            current.state == Lifecycle.State.RESUMED && onActivity { a -> a.resources.configuration.orientation } == wanted
        }
        compose.waitForIdle()
    }

    /** Presses Home and waits until the process lifecycle backgrounds the table. */
    fun pressHome() {
        shell("input keyevent KEYCODE_HOME")
        pollUntil("the process to move to the background", 10_000) { it.backgrounded }
    }

    /** Brings the existing activity back to the front and waits for the table to return. */
    fun bringToFront() {
        val component = "${instrumentation.targetContext.packageName}/${MainActivity::class.java.name}"
        shell("am start -n $component --activity-reorder-to-front")
        pollFor("the app to return to the foreground", 10_000) {
            current.state == Lifecycle.State.RESUMED && !state.backgrounded
        }
        compose.waitForIdle()
    }

    private fun shell(command: String) {
        val output = instrumentation.uiAutomation.executeShellCommand(command)
        ParcelFileDescriptor.AutoCloseInputStream(output).use { it.readBytes() }
    }
}
