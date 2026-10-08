package com.august.noirpoker.core.session

import java.util.PriorityQueue

/** A handle to scheduled work. Cancelling twice, or after the work ran, is harmless. */
fun interface Cancellable {
    fun cancel()
}

/**
 * The single-threaded timer the table session uses for street advances, bot
 * thinking pauses, and the Finish Hand loop (the reference's `setTimeout` and
 * `performance.now()`).
 *
 * Every action must run on the thread that owns the session (the main thread in
 * the apps). Android can back it with a `Handler` or a main-dispatcher coroutine
 * and `SystemClock.elapsedRealtime()`; tests use [ManualScheduler].
 */
interface Scheduler {
    /** A monotonic clock in milliseconds. */
    val nowMs: Long

    /** Runs [action] once after at least [delayMs] milliseconds (0 = next turn of the loop). */
    fun schedule(delayMs: Long, action: () -> Unit): Cancellable
}

/**
 * A deterministic virtual clock for tests. Nothing runs until the test advances
 * time. Tasks due at the same time run in scheduling order, and tasks scheduled
 * while advancing run in the same call if they fall due before the target time.
 */
class ManualScheduler(start: Long = 0) : Scheduler {
    private class Task(val at: Long, val seq: Long, val action: () -> Unit) {
        var cancelled = false
    }

    private val queue = PriorityQueue<Task>(compareBy<Task>({ it.at }, { it.seq }))
    private var seq = 0L

    override var nowMs: Long = start
        private set

    /** Number of tasks that are scheduled and not cancelled. */
    val pendingCount: Int get() = queue.count { !it.cancelled }

    /** The due time of the next live task, or `null` when idle. */
    val nextDueAt: Long? get() = queue.filter { !it.cancelled }.minByOrNull { it.at }?.at

    override fun schedule(delayMs: Long, action: () -> Unit): Cancellable {
        val task = Task(nowMs + maxOf(0L, delayMs), seq++, action)
        queue.add(task)
        return Cancellable { task.cancelled = true }
    }

    /** Advances the clock by [ms], running every task that falls due on the way. */
    fun advanceBy(ms: Long) = advanceTo(nowMs + ms)

    fun advanceTo(target: Long) {
        require(target >= nowMs) { "Time cannot go backwards" }
        while (true) {
            val next = queue.peek() ?: break
            if (next.at > target) break
            queue.poll()
            if (next.cancelled) continue
            nowMs = next.at
            next.action()
        }
        nowMs = target
    }

    /** Runs only the tasks due now (zero-delay work), without moving the clock. */
    fun runCurrent() = advanceTo(nowMs)

    /**
     * Runs tasks in due order until nothing is scheduled or [maxMs] of virtual
     * time has passed. Returns the number of tasks run.
     */
    fun runUntilIdle(maxMs: Long = 10 * 60_000L): Int {
        val limit = nowMs + maxMs
        var ran = 0
        while (true) {
            val next = queue.peek() ?: break
            if (next.at > limit) break
            queue.poll()
            if (next.cancelled) continue
            nowMs = next.at
            next.action()
            ran++
        }
        return ran
    }
}
