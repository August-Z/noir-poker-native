package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.act
import com.august.noirpoker.core.advanceStreet
import com.august.noirpoker.core.session.Harness
import com.august.noirpoker.core.session.ReviewAnalysis
import com.august.noirpoker.core.session.ReviewJob
import com.august.noirpoker.core.session.ReviewSink
import com.august.noirpoker.core.session.ReviewStatus as SessionReviewStatus
import java.util.concurrent.Executor
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class SessionReviewTest {
    private val trials = 40

    /** A queue standing in for both the worker thread and the main thread. */
    private class Queue : Executor {
        val tasks = ArrayDeque<Runnable>()
        override fun execute(command: Runnable) {
            tasks.addLast(command)
        }
        fun drain() {
            while (tasks.isNotEmpty()) tasks.removeFirst().run()
        }
    }

    private class RecordingSink : ReviewSink {
        val progress = mutableListOf<Pair<Int, Int>>()
        var completed: ReviewAnalysis? = null
        var failed: Throwable? = null
        var failures = 0
        override fun progress(done: Int, total: Int) {
            progress.add(done to total)
        }
        override fun complete(analysis: ReviewAnalysis) {
            completed = analysis
        }
        override fun fail(error: Throwable?) {
            failed = error
            failures++
        }
    }

    private fun settled(): Harness {
        val h = Harness(seed = 1)
        h.heroTurn(6)
        h.session.callOrCheck()
        h.respondToHero()
        h.hooks.mutate { g ->
            while (g.phase != Phase.DONE) {
                if (g.phase == Phase.BETWEEN) advanceStreet(g) else act(g, g.actor, Action.CALL)
            }
        }
        return h
    }

    @Test
    fun `the adapter grades the same decisions as the review module`() {
        val h = settled()
        val input = assertNotNull(h.state.review.input)
        val direct = analyzeReview(input.toReviewInput(), trials = trials)
        val adapted = analyzeHeroReview(input.heroInput, trials = trials)
        assertEquals(direct, adapted.summary)
        assertEquals(direct.priorityIndex, adapted.priorityIndex)
        assertEquals(input.decisions.size, adapted.decisions.size)
        assertEquals(input.decisions.map { it.toReviewDecision() }, adapted.decisions)
    }

    @Test
    fun `the session outcome converts field for field`() {
        val h = settled()
        val input = assertNotNull(h.state.review.input)
        val outcome = input.outcome.toReviewOutcome()
        assertEquals(input.outcome.profit, outcome.profit)
        assertEquals(input.outcome.board, outcome.board)
        assertEquals(input.outcome.pots.map { it.label to it.amount }, outcome.pots.map { it.label to it.amount })
        assertEquals(input.outcome.pots.flatMap { p -> p.awards.map { it.name } }, outcome.pots.flatMap { p -> p.awards.map { it.name } })
        assertEquals(input.opponents, input.toReviewInput().opponents)
    }

    @Test
    fun `the executor runner analyzes on the worker and delivers through the main queue`() {
        val h = settled()
        val input = assertNotNull(h.state.review.input)
        val worker = Queue()
        val main = Queue()
        val runner = ExecutorReviewRunner(worker, { main.execute(it) }, trials)
        val sink = RecordingSink()
        runner.start(ReviewJob(1, "0:1", input.heroInput), sink)
        assertTrue(sink.progress.isEmpty())
        worker.drain()
        // Nothing reaches the sink until the main queue runs.
        assertTrue(sink.progress.isEmpty())
        assertEquals(null, sink.completed)
        main.drain()
        val n = input.decisions.size
        assertEquals((1..n).map { it to n }, sink.progress)
        val analysis = assertIs<HeroReviewAnalysis>(sink.completed)
        assertEquals(analyzeHeroReview(input.heroInput, trials = trials).summary, analysis.summary)
        assertEquals(0, sink.failures)
    }

    @Test
    fun `cancelling before the worker runs skips the analysis`() {
        val h = settled()
        val input = assertNotNull(h.state.review.input)
        val worker = Queue()
        val main = Queue()
        val sink = RecordingSink()
        ExecutorReviewRunner(worker, { main.execute(it) }, trials).start(ReviewJob(1, "k", input.heroInput), sink).cancel()
        worker.drain()
        assertTrue(main.tasks.isEmpty())
        assertTrue(sink.progress.isEmpty())
        assertEquals(null, sink.completed)
    }

    @Test
    fun `cancelling while results are queued drops them`() {
        val h = settled()
        val input = assertNotNull(h.state.review.input)
        val worker = Queue()
        val main = Queue()
        val sink = RecordingSink()
        val handle = ExecutorReviewRunner(worker, { main.execute(it) }, trials).start(ReviewJob(1, "k", input.heroInput), sink)
        worker.drain()
        assertTrue(main.tasks.isNotEmpty())
        handle.cancel()
        main.drain()
        assertTrue(sink.progress.isEmpty())
        assertEquals(null, sink.completed)
        assertEquals(0, sink.failures)
    }

    @Test
    fun `cancelling during the analysis stops at the next checkpoint without failing`() {
        val h = settled()
        val input = assertNotNull(h.state.review.input)
        val main = Queue()
        val sink = RecordingSink()
        var handle: com.august.noirpoker.core.session.Cancellable? = null
        var firstProgress = true
        val worker = Queue()
        var delivered = 0
        // The first progress delivery cancels the job while the worker is still analyzing.
        val runner = ExecutorReviewRunner(worker, { block ->
            delivered++
            if (firstProgress) {
                firstProgress = false
                handle?.cancel()
            }
            main.execute(block)
        }, trials)
        handle = runner.start(ReviewJob(1, "k", input.heroInput), sink)
        worker.drain()
        main.drain()
        // Either the checkpoint stopped the loop or the queued results were dropped.
        assertTrue(delivered <= input.decisions.size + 1)
        assertTrue(sink.progress.isEmpty())
        assertEquals(null, sink.completed)
        assertEquals(0, sink.failures)
    }

    @Test
    fun `an analysis error is reported through the sink`() {
        val h = settled()
        val input = assertNotNull(h.state.review.input)
        val sink = RecordingSink()
        ExecutorReviewRunner({ it.run() }, { it() }, trials = 0).start(ReviewJob(1, "k", input.heroInput), sink)
        assertEquals(1, sink.failures)
        assertIs<ReviewException>(sink.failed)
    }

    @Test
    fun `the session drives the executor runner to a finished review`() {
        val worker = Queue()
        val main = Queue()
        val runner = ExecutorReviewRunner(worker, { main.execute(it) }, trials)
        val h = Harness(seed = 1, runner = runner)
        h.heroTurn(6)
        h.session.callOrCheck()
        h.respondToHero()
        h.hooks.mutate { g ->
            while (g.phase != Phase.DONE) {
                if (g.phase == Phase.BETWEEN) advanceStreet(g) else act(g, g.actor, Action.CALL)
            }
        }
        h.session.openReview()
        assertEquals(SessionReviewStatus.RUNNING, h.state.review.status)
        worker.drain()
        main.drain()
        assertEquals(SessionReviewStatus.DONE, h.state.review.status)
        val analysis = assertIs<HeroReviewAnalysis>(h.state.review.analysis)
        assertEquals(analysis.priorityIndex, h.state.review.selected)
    }

    @Test
    fun `without a runner opening the review reports an error`() {
        val h = Harness(seed = 1, runner = null)
        h.heroTurn(6)
        h.session.callOrCheck()
        h.respondToHero()
        h.hooks.mutate { g ->
            while (g.phase != Phase.DONE) {
                if (g.phase == Phase.BETWEEN) advanceStreet(g) else act(g, g.actor, Action.CALL)
            }
        }
        assertNotNull(h.state.review.input)
        h.session.openReview()
        assertEquals(SessionReviewStatus.ERROR, h.state.review.status)
        val view = assertNotNull(presentHeroReview(h.state.review))
        assertTrue(view.retryVisible)
        assertEquals(ReviewDialogCopy.stateError, view.stateText)
        assertEquals(false, view.running)
    }
}
