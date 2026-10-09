import XCTest
@testable import PokerCore

final class ReviewLifecycleTests: XCTestCase {
    private func settledHand(_ runner: FakeReviewRunner, seed: Int = 1) throws -> Harness {
        let h = Harness(seed: seed, runner: runner)
        try h.heroTurn(6)
        h.session.callOrCheck()
        try h.respondToHero()
        try h.hooks.mutate { g in
            while g.phase != .done {
                if g.phase == .between { try advanceStreet(g) } else { try act(g, g.actor, .call) }
            }
        }
        return h
    }

    func testTheReviewInputIsCapturedAtSettlementAndAnalysisStartsLazilyOnOpen() throws {
        let runner = FakeReviewRunner()
        let h = try settledHand(runner)
        let review = h.state.review
        XCTAssertTrue(review.buttonVisible)
        XCTAssertTrue(h.state.actions.reviewVisible)
        XCTAssertEqual(review.status, .idle)
        let input = try XCTUnwrap(review.input)
        XCTAssertFalse(input.decisions.isEmpty)
        XCTAssertEqual(input.hand, h.game.hand)
        XCTAssertEqual(input.hole, h.game.players[0].hole)
        XCTAssertTrue(runner.started.isEmpty)
        h.session.openReview()
        XCTAssertTrue(h.state.review.dialogOpen)
        XCTAssertEqual(h.state.review.status, .running)
        XCTAssertEqual(runner.started.count, 1)
        let job = runner.started[0]
        // The hero analysis never receives opponent execution records.
        XCTAssertEqual(job.job.input, input.heroInput)
        XCTAssertEqual(job.job.key, h.state.review.key)
        job.sink.progress(done: 1, total: input.decisions.count)
        XCTAssertEqual(h.state.review.progress, 1)
        job.sink.complete(FakeAnalysis(priorityIndex: input.decisions.count - 1))
        XCTAssertEqual(h.state.review.status, .done)
        XCTAssertEqual(h.state.review.selected, input.decisions.count - 1)
        XCTAssertNotNil(h.state.review.analysis)
        // Opening again does not restart a finished analysis.
        h.session.closeReview()
        XCTAssertFalse(h.state.review.dialogOpen)
        h.session.openReview()
        XCTAssertEqual(runner.started.count, 1)
        h.session.previousReviewStep()
        XCTAssertEqual(h.state.review.selected, max(0, input.decisions.count - 2))
        h.session.selectReviewStep(99)
        XCTAssertEqual(h.state.review.selected, max(0, input.decisions.count - 2))
        h.session.nextReviewStep()
        XCTAssertEqual(h.state.review.selected, input.decisions.count - 1)
        // The stored input is a copy: later engine changes do not alter it.
        h.session.nextHand()
        XCTAssertEqual(h.state.review.input, input)
    }

    func testReplayHandCancelsTheJobDropsItsResultAndHidesTheReview() throws {
        let runner = FakeReviewRunner()
        let h = try settledHand(runner)
        h.session.openReview()
        let job = runner.started[0]
        h.session.replayHand()
        XCTAssertTrue(job.cancelled)
        XCTAssertFalse(h.state.review.buttonVisible)
        XCTAssertFalse(h.state.review.dialogOpen)
        XCTAssertNil(h.state.review.input)
        job.sink.complete(FakeAnalysis(priorityIndex: 0))
        XCTAssertNil(h.state.review.analysis)
        XCTAssertEqual(h.state.review.status, .idle)
    }

    func testANewSettledHandReplacesTheJobAndStaleResultsAreIgnored() throws {
        let runner = FakeReviewRunner()
        let h = try settledHand(runner)
        h.session.openReview()
        let stale = runner.started[0]
        h.session.closeReview()
        h.session.nextHand()
        // Until the next hand ends the review button stays hidden.
        XCTAssertFalse(h.state.review.buttonVisible)
        h.hooks.stop()
        try h.hooks.mutate { g in
            while g.phase != .done {
                if g.phase == .between { try advanceStreet(g) } else { try act(g, g.actor, .fold) }
            }
        }
        XCTAssertTrue(stale.cancelled)
        XCTAssertTrue(h.state.review.buttonVisible)
        XCTAssertEqual(h.state.review.input?.hand, h.game.hand)
        stale.sink.complete(FakeAnalysis(priorityIndex: 0))
        stale.sink.fail(nil)
        XCTAssertEqual(h.state.review.status, .idle)
        XCTAssertNil(h.state.review.analysis)
    }

    func testNextHandCancelsARunningReviewJob() throws {
        // The dialog is still open when Next Hand runs.
        let runner = FakeReviewRunner()
        let h = try settledHand(runner)
        let settled = try XCTUnwrap(h.state.review.input)
        h.session.openReview()
        let job = runner.started[0]
        XCTAssertTrue(h.session.nextHand())
        h.hooks.stop()
        XCTAssertTrue(job.cancelled)
        XCTAssertFalse(h.state.review.dialogOpen)
        XCTAssertFalse(h.state.review.buttonVisible)
        XCTAssertEqual(h.state.review.status, .idle)
        XCTAssertGreaterThan(h.state.review.jobId, job.job.id)
        // A late result or failure from the cancelled job is dropped.
        job.sink.progress(done: 1, total: settled.decisions.count)
        job.sink.complete(FakeAnalysis(priorityIndex: 0))
        job.sink.fail(nil)
        XCTAssertEqual(h.state.review.status, .idle)
        XCTAssertEqual(h.state.review.progress, 0)
        XCTAssertNil(h.state.review.analysis)
        // The settled entry is kept, but nothing restarts it during the new hand.
        XCTAssertEqual(h.state.review.input, settled)
        h.session.onBackground()
        h.session.onForeground()
        h.hooks.stop()
        XCTAssertEqual(runner.started.count, 1)

        // The dialog was closed mid-analysis before Next Hand.
        let closed = FakeReviewRunner()
        let g = try settledHand(closed, seed: 3)
        g.session.openReview()
        g.session.closeReview()
        let running = closed.started[0]
        XCTAssertFalse(running.cancelled)
        g.session.nextHand()
        g.hooks.stop()
        XCTAssertTrue(running.cancelled)
        running.sink.complete(FakeAnalysis(priorityIndex: 0))
        XCTAssertNil(g.state.review.analysis)
        // The next settled hand gets a fresh job when its review opens.
        try g.foldRest()
        g.session.openReview()
        XCTAssertEqual(closed.started.count, 2)
        XCTAssertEqual(closed.started[1].job.input.hand, g.game.hand)
        closed.started[1].sink.complete(FakeAnalysis(priorityIndex: 0))
        XCTAssertEqual(g.state.review.status, .done)
    }

    func testStartNewSessionAndSeatChangesResetTheReview() throws {
        let runner = FakeReviewRunner()
        let h = try settledHand(runner)
        h.session.openReview()
        let job = runner.started[0]
        h.session.startNewSession()
        XCTAssertTrue(job.cancelled)
        XCTAssertNil(h.state.review.input)
        XCTAssertFalse(h.state.review.dialogOpen)

        let g = try settledHand(runner, seed: 2)
        XCTAssertNotNil(g.state.review.input)
        g.session.setSeatCount(8)
        g.session.nextHand()
        XCTAssertNil(g.state.review.input)
    }

    func testBackgroundCancelsARunningJobAndForegroundRestartsItWhenTheDialogIsOpen() throws {
        let runner = FakeReviewRunner()
        let h = try settledHand(runner)
        h.session.openReview()
        let first = runner.started[0]
        h.session.onBackground()
        XCTAssertTrue(first.cancelled)
        XCTAssertEqual(h.state.review.status, .idle)
        first.sink.complete(FakeAnalysis(priorityIndex: 0))
        XCTAssertNil(h.state.review.analysis)
        h.session.onForeground()
        XCTAssertEqual(runner.started.count, 2)
        let second = runner.started[1]
        XCTAssertGreaterThan(second.job.id, first.job.id)
        XCTAssertEqual(second.job.input, first.job.input)
        // The review key is unchanged by the lifecycle transition.
        XCTAssertEqual(second.job.key, first.job.key)
        second.sink.complete(FakeAnalysis(priorityIndex: 0))
        XCTAssertEqual(h.state.review.status, .done)
        // A finished analysis survives later background transitions.
        h.session.onBackground()
        h.session.onForeground()
        XCTAssertEqual(h.state.review.status, .done)
        XCTAssertEqual(runner.started.count, 2)
    }

    func testErrorsCanBeRetriedAndOpponentRecordsAreFilterable() throws {
        let runner = FakeReviewRunner()
        let h = Harness(seed: 4, runner: runner)
        try h.heroTurn(6)
        h.session.fold()
        h.session.finishHand()
        h.scheduler.runUntilIdle()
        XCTAssertEqual(h.game.phase, .done)
        h.session.openReview()
        runner.started.last!.sink.fail(TestFailure())
        XCTAssertEqual(h.state.review.status, .error)
        h.session.retryReview()
        XCTAssertEqual(h.state.review.status, .running)
        XCTAssertEqual(runner.started.count, 2)
        let records = h.state.review.opponentRecords
        XCTAssertEqual(records.count, h.game.botDecisions.count)
        XCTAssertFalse(records.isEmpty)
        let seat = records[0].id
        h.session.setOpponentReviewFilter(seat)
        XCTAssertTrue(h.state.review.opponentRecords.allSatisfy { $0.id == seat })
        h.session.selectOpponentReviewRecord(99)
        XCTAssertEqual(h.state.review.opponentSelected, h.state.review.opponentRecords.count - 1)
        h.session.setReviewPerspective(.opponents)
        XCTAssertEqual(h.state.review.perspective, .opponents)
        h.session.closeReview()
        h.session.openReview()
        XCTAssertNil(h.state.review.opponentFilter)
        XCTAssertEqual(h.state.review.opponentSelected, 0)
    }

    func testASynchronousRunnerCompletesInsideTheRenderWithoutLosingTheState() throws {
        let runner = ClosureReviewRunner { job, sink in
            sink.progress(done: job.input.decisions.count, total: job.input.decisions.count)
            sink.complete(FakeAnalysis(priorityIndex: 0))
            return CancelHandle()
        }
        let h = Harness(seed: 6, runner: runner)
        try h.heroTurn(6)
        h.session.callOrCheck()
        h.hooks.stop()
        h.session.openReview()  // nothing to review yet
        XCTAssertFalse(h.state.review.dialogOpen)
        try h.foldRest()
        h.session.openReview()
        XCTAssertEqual(h.state.review.status, .done)
        XCTAssertTrue(h.state.review.dialogOpen)
    }

    func testWithoutARunnerOpeningTheReviewReportsAnError() throws {
        let h = Harness(seed: 6)
        try h.foldWin()
        h.session.openReview()
        XCTAssertEqual(h.state.review.status, .error)
    }
}
