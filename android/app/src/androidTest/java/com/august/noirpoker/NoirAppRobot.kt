package com.august.noirpoker

import android.content.Intent
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.SeededRandom
import com.august.noirpoker.core.session.PublicTableSnapshot
import com.august.noirpoker.core.session.TableRenderState
import com.august.noirpoker.core.startHand
import com.august.noirpoker.platform.LaunchOptions
import com.august.noirpoker.ui.table.TableModel

/**
 * Drives the real app for instrumented UI tests. The activity is launched with
 * debug-only [LaunchOptions] extras: a fixed seed, a private preferences file
 * cleared at the first launch, and a faster session clock. Everything the tests
 * read comes from the session's render state and public snapshot, never from
 * hidden opponent cards.
 */
class NoirAppRobot(private val compose: ComposeTestRule) {
    private var scenario: ActivityScenario<MainActivity>? = null

    fun launch(
        seed: Long = DEFAULT_SEED,
        preferences: String = "noir-ui-test",
        clearPreferences: Boolean = true,
        timeScale: Double = FAST,
    ) {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(LaunchOptions.EXTRA_SEED, seed)
            .putExtra(LaunchOptions.EXTRA_PREFERENCES, preferences)
            .putExtra(LaunchOptions.EXTRA_CLEAR_PREFERENCES, clearPreferences)
            .putExtra(LaunchOptions.EXTRA_TIME_SCALE, timeScale)
        scenario = ActivityScenario.launch(intent)
        compose.waitForIdle()
    }

    /** Closes the activity (its view model and session are destroyed). */
    fun close() {
        scenario?.close()
        scenario = null
    }

    /** Runs [block] on the main thread with the live table model. */
    fun <T> onTable(block: (TableModel) -> T): T {
        var result: Result<T>? = null
        checkNotNull(scenario) { "Launch the app first" }.onActivity { activity ->
            result = runCatching { block(activity.tableModel) }
        }
        return checkNotNull(result).getOrThrow()
    }

    val state: TableRenderState get() = onTable { it.state }

    fun snapshot(): PublicTableSnapshot = onTable { it.session.publicSnapshot() }

    /** Changes how fast the session clock runs (1 = real time). */
    fun setTimeScale(scale: Double) {
        checkNotNull(scenario).onActivity { it.tableScheduler.timeScale = scale }
    }

    fun waitFor(description: String, timeoutMs: Long = 60_000, condition: (TableRenderState) -> Boolean) {
        try {
            compose.waitUntil(timeoutMs) { condition(state) }
        } catch (e: ComposeTimeoutException) {
            throw AssertionError("Timed out waiting for $description", e)
        }
        compose.waitForIdle()
    }

    val heroToAct: Boolean get() = state.let { it.phase == Phase.PLAYING && it.actions.controlsVisible && it.actions.foldEnabled }

    fun waitForHeroTurnOrSettlement() =
        waitFor("the hero's turn or the settlement") { (it.phase == Phase.PLAYING && it.actions.controlsVisible && it.actions.foldEnabled) || it.phase == Phase.DONE }

    fun waitForSettlement() = waitFor("the settlement") { it.phase == Phase.DONE && it.actions.nextHandVisible }

    /** Taps Check / Call at every hero turn until the hand settles. */
    fun callDown() {
        while (true) {
            waitForHeroTurnOrSettlement()
            if (state.phase == Phase.DONE) break
            tap("call")
        }
        waitForSettlement()
    }

    /**
     * The reference's `heroTurn` fixture: a fresh 6-seat table where the hero is
     * UTG and first to act preflop, dealt from a seeded deck. Bots are not
     * scheduled until the hero acts.
     */
    fun heroFirstHand(count: Int = 6, seed: Long = DEFAULT_SEED) {
        onTable { model ->
            model.session.testHooks.fixture(count, heroFirst = true) { game -> startHand(game, SeededRandom(seed)) }
        }
        compose.waitForIdle()
    }

    fun node(tag: String): SemanticsNodeInteraction = compose.onNode(hasTestTag(tag))

    fun exists(matcher: SemanticsMatcher): Boolean =
        compose.onAllNodes(matcher, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    fun exists(tag: String): Boolean = exists(hasTestTag(tag))

    /** Scrolls a node into view when it sits in a scrolling container, then taps it. */
    fun tap(matcher: SemanticsMatcher) {
        val node = compose.onNode(matcher)
        runCatching { node.performScrollTo() }
        node.performClick()
        compose.waitForIdle()
    }

    fun tap(tag: String) = tap(hasTestTag(tag))

    /** Taps the first match, for text that appears more than once (a link and its timeline card). */
    fun tapFirst(matcher: SemanticsMatcher) {
        val node = compose.onAllNodes(matcher)[0]
        runCatching { node.performScrollTo() }
        node.performClick()
        compose.waitForIdle()
    }

    companion object {
        const val DEFAULT_SEED = 20_260_101L

        /** Bot thinking (1.2–8 s) and street delays run 25× faster. */
        const val FAST = 25.0
        const val REAL_TIME = 1.0
        const val STARTING_STACK = 5_000
    }
}
