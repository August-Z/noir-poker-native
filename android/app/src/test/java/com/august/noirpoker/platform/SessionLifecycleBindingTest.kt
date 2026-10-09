package com.august.noirpoker.platform

import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.august.noirpoker.core.SeededRandom
import com.august.noirpoker.core.session.InMemoryStorage
import com.august.noirpoker.core.session.ManualScheduler
import com.august.noirpoker.core.startHand
import com.august.noirpoker.ui.table.TableModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The [TableViewModel] lifecycle wiring: a fake process lifecycle drives the
 * real table model and session on a virtual clock. Backgrounding cancels the
 * thinking bot's timer without dropping its plan; returning runs that same plan
 * exactly once.
 */
class SessionLifecycleBindingTest {
    private class FakeProcess : LifecycleOwner {
        // No main-thread checks: the test runs on a plain JVM thread.
        val registry = LifecycleRegistry.createUnsafe(this)
        override val lifecycle: Lifecycle get() = registry
    }

    private val scheduler = ManualScheduler()
    private val model = TableModel(
        scheduler = scheduler,
        storage = InMemoryStorage(),
        reviewRunner = null,
        random = SeededRandom(SEED),
    )
    private val process = FakeProcess().apply { registry.currentState = Lifecycle.State.RESUMED }
    private val session get() = model.session

    /** Hero first to act preflop; calling hands the turn to a thinking bot. */
    private fun startBotThinking() {
        session.testHooks.fixture(6, heroFirst = true) { startHand(it, SeededRandom(SEED)) }
        assertTrue("The hero acts first", session.callOrCheck())
        assertNotNull("A bot is thinking after the hero calls", session.testHooks.thinking())
    }

    @Test fun attachingToAStartedProcessDoesNotPauseTheTable() {
        SessionLifecycleBinding.attach(process.lifecycle, model)
        assertFalse(model.state.backgrounded)
        startBotThinking()
        assertTrue(session.testHooks.hasPendingTimer)
    }

    @Test fun processStopPausesTheBotAndStartRunsTheSamePlanOnce() {
        SessionLifecycleBinding.attach(process.lifecycle, model)
        startBotThinking()
        val plan = checkNotNull(session.testHooks.thinking())
        val records = session.testHooks.timingRecords().size
        val table = session.publicSnapshot()

        process.registry.currentState = Lifecycle.State.CREATED // ON_PAUSE, ON_STOP
        assertTrue("ON_STOP backgrounds the session", model.state.backgrounded)
        assertFalse("No bot timer runs in the background", session.testHooks.hasPendingTimer)
        scheduler.advanceBy(60_000)
        assertEquals("No bot acts while the app is in the background", records, session.testHooks.timingRecords().size)
        assertEquals(table, session.publicSnapshot())

        process.registry.currentState = Lifecycle.State.RESUMED // ON_START, ON_RESUME
        assertFalse("ON_START brings the session back", model.state.backgrounded)
        val resumed = checkNotNull(session.testHooks.thinking())
        assertEquals("The same bot is still thinking", plan.actor, resumed.actor)
        assertEquals("The plan is kept: no new thinking time is drawn", plan.delayMs, resumed.delayMs)

        scheduler.advanceBy(plan.delayMs.toLong())
        val after = session.testHooks.timingRecords()
        assertEquals("The kept plan runs exactly once", records + 1, after.size)
        assertEquals(plan.actor, after.last().id)
        assertEquals(plan.delayMs, after.last().trace.thinking?.durationMs)
        assertEquals(session.publicSnapshot().playerCount * 5_000, session.publicSnapshot().wealth)
    }

    @Test fun pausingWithoutStoppingKeepsTheBotRunning() {
        SessionLifecycleBinding.attach(process.lifecycle, model)
        startBotThinking()
        process.registry.currentState = Lifecycle.State.STARTED // ON_PAUSE only
        assertFalse(model.state.backgrounded)
        assertTrue(session.testHooks.hasPendingTimer)
    }

    @Test fun detachedBindingNoLongerForwardsTransitions() {
        val binding = SessionLifecycleBinding.attach(process.lifecycle, model)
        startBotThinking()
        binding.detach()
        process.registry.currentState = Lifecycle.State.CREATED
        assertFalse(model.state.backgrounded)
        assertTrue(session.testHooks.hasPendingTimer)
    }

    @Test fun forwardsEachTransitionInOrder() {
        val calls = mutableListOf<String>()
        SessionLifecycleBinding.attach(process.lifecycle, onForeground = { calls += "foreground" }, onBackground = { calls += "background" })
        assertEquals("A started process replays ON_START once", listOf("foreground"), calls)
        process.registry.currentState = Lifecycle.State.CREATED
        process.registry.currentState = Lifecycle.State.RESUMED
        process.registry.currentState = Lifecycle.State.CREATED
        assertEquals(listOf("foreground", "background", "foreground", "background"), calls)
    }

    private companion object {
        const val SEED = 20_260_101L
    }
}
