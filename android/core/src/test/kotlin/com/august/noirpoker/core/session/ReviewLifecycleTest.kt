package com.august.noirpoker.core.session

import com.august.noirpoker.core.Phase
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ReviewLifecycleTest {
    private fun settledHand(runner: FakeReviewRunner, seed: Long = 1): Harness {
        val h = Harness(seed = seed, runner = runner)
        h.heroTurn(6)
        h.session.callOrCheck()
        h.respondToHero()
        h.hooks.mutate { g ->
            while (g.phase != Phase.DONE) {
                if (g.phase == Phase.BETWEEN) com.august.noirpoker.core.advanceStreet(g)
                else com.august.noirpoker.core.act(g, g.actor, com.august.noirpoker.core.Action.CALL)
            }
        }
        return h
    }

    @Test
    fun `the review input is captured at settlement and analysis starts lazily on open`() {
        val runner = FakeReviewRunner()
        val h = settledHand(runner)
        val review = h.state.review
        assertTrue(review.buttonVisible)
        assertTrue(h.state.actions.reviewVisible)
        assertEquals(ReviewStatus.IDLE, review.status)
        val input = assertNotNull(review.input)
        assertTrue(input.decisions.isNotEmpty())
        assertEquals(h.game.hand, input.hand)
        assertTrue(runner.started.isEmpty())
        h.session.openReview()
        assertTrue(h.state.review.dialogOpen)
        assertEquals(ReviewStatus.RUNNING, h.state.review.status)
        val job = runner.started.single()
        // The hero analysis never receives opponent execution records.
        assertEquals(input.heroInput, job.job.input)
        job.sink.progress(1, input.decisions.size)
        assertEquals(1, h.state.review.progress)
        job.sink.complete(FakeAnalysis(priorityIndex = input.decisions.size - 1))
        assertEquals(ReviewStatus.DONE, h.state.review.status)
        assertEquals(input.decisions.size - 1, h.state.review.selected)
        // Opening again does not restart a finished analysis.
        h.session.closeReview()
        h.session.openReview()
        assertEquals(1, runner.started.size)
        h.session.previousReviewStep()
        assertEquals(maxOf(0, input.decisions.size - 2), h.state.review.selected)
        h.session.selectReviewStep(99)
        assertEquals(maxOf(0, input.decisions.size - 2), h.state.review.selected)
    }

    @Test
    fun `replay hand cancels the job, drops its result and hides the review`() {
        val runner = FakeReviewRunner()
        val h = settledHand(runner)
        h.session.openReview()
        val job = runner.started.single()
        h.session.replayHand()
        assertTrue(job.cancelled)
        assertFalse(h.state.review.buttonVisible)
        assertFalse(h.state.review.dialogOpen)
        assertNull(h.state.review.input)
        job.sink.complete(FakeAnalysis(0))
        assertNull(h.state.review.analysis)
        assertEquals(ReviewStatus.IDLE, h.state.review.status)
    }

    @Test
    fun `a new settled hand replaces the job and stale results are ignored`() {
        val runner = FakeReviewRunner()
        val h = settledHand(runner)
        h.session.openReview()
        val stale = runner.started.single()
        h.session.closeReview()
        h.session.nextHand()
        // Until the next hand ends the review button stays hidden.
        assertFalse(h.state.review.buttonVisible)
        h.hooks.stop()
        h.hooks.mutate { g ->
            while (g.phase != Phase.DONE) {
                if (g.phase == Phase.BETWEEN) com.august.noirpoker.core.advanceStreet(g)
                else com.august.noirpoker.core.act(g, g.actor, com.august.noirpoker.core.Action.FOLD)
            }
        }
        assertTrue(stale.cancelled)
        assertTrue(h.state.review.buttonVisible)
        assertEquals(h.game.hand, h.state.review.input!!.hand)
        stale.sink.complete(FakeAnalysis(0))
        stale.sink.fail(null)
        assertEquals(ReviewStatus.IDLE, h.state.review.status)
        assertNull(h.state.review.analysis)
    }

    @Test
    fun `start new session and seat changes reset the review`() {
        val runner = FakeReviewRunner()
        val h = settledHand(runner)
        h.session.openReview()
        val job = runner.started.single()
        h.session.startNewSession()
        assertTrue(job.cancelled)
        assertNull(h.state.review.input)
        assertFalse(h.state.review.dialogOpen)

        val g = settledHand(runner, seed = 2)
        g.session.setSeatCount(8)
        g.session.nextHand()
        assertNull(g.state.review.input)
    }

    @Test
    fun `background cancels a running job and foreground restarts it when the dialog is open`() {
        val runner = FakeReviewRunner()
        val h = settledHand(runner)
        h.session.openReview()
        val first = runner.started.single()
        h.session.onBackground()
        assertTrue(first.cancelled)
        assertEquals(ReviewStatus.IDLE, h.state.review.status)
        first.sink.complete(FakeAnalysis(0))
        assertNull(h.state.review.analysis)
        h.session.onForeground()
        assertEquals(2, runner.started.size)
        val second = runner.started.last()
        assertTrue(second.job.id > first.job.id)
        assertEquals(first.job.input, second.job.input)
        // The review key is unchanged by the lifecycle transition.
        assertEquals(first.job.key, second.job.key)
        second.sink.complete(FakeAnalysis(0))
        assertEquals(ReviewStatus.DONE, h.state.review.status)
        // A finished analysis survives later background transitions.
        h.session.onBackground()
        h.session.onForeground()
        assertEquals(ReviewStatus.DONE, h.state.review.status)
        assertEquals(2, runner.started.size)
    }

    @Test
    fun `errors can be retried and opponent records are filterable`() {
        val runner = FakeReviewRunner()
        val h = Harness(seed = 4, runner = runner)
        h.heroTurn(6)
        h.session.fold()
        h.session.finishHand()
        h.scheduler.runUntilIdle()
        assertEquals(Phase.DONE, h.game.phase)
        h.session.openReview()
        runner.started.last().sink.fail(IllegalStateException("boom"))
        assertEquals(ReviewStatus.ERROR, h.state.review.status)
        h.session.retryReview()
        assertEquals(ReviewStatus.RUNNING, h.state.review.status)
        assertEquals(2, runner.started.size)
        val records = h.state.review.opponentRecords
        assertEquals(h.game.botDecisions.size, records.size)
        val seat = records.first().id
        h.session.setOpponentReviewFilter(seat)
        assertTrue(h.state.review.opponentRecords.all { it.id == seat })
        h.session.selectOpponentReviewRecord(99)
        assertEquals(h.state.review.opponentRecords.size - 1, h.state.review.opponentSelected)
        h.session.setReviewPerspective(ReviewPerspective.OPPONENTS)
        assertEquals(ReviewPerspective.OPPONENTS, h.state.review.perspective)
        h.session.closeReview()
        h.session.openReview()
        assertNull(h.state.review.opponentFilter)
    }

    @Test
    fun `a synchronous runner completes inside the render without losing the state`() {
        val runner = ReviewRunner { job, sink ->
            sink.progress(job.input.decisions.size, job.input.decisions.size)
            sink.complete(FakeAnalysis(0))
            Cancellable { }
        }
        val h = Harness(seed = 6, runner = runner)
        h.heroTurn(6)
        h.session.callOrCheck()
        h.hooks.stop()
        h.session.openReview() // nothing to review yet
        assertFalse(h.state.review.dialogOpen)
        h.foldRest()
        h.session.openReview()
        assertEquals(ReviewStatus.DONE, h.state.review.status)
    }
}
