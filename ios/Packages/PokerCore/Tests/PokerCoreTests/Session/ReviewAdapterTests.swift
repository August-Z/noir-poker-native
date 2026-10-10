import XCTest
@testable import PokerCore

/// The adapter between the session's review job and the review port.
final class ReviewAdapterTests: XCTestCase {
    private let trials = 40

    /// A settled hand in which the hero made at least one decision.
    private func settledInput(seed: Int = 7) throws -> HandReviewInput {
        let h = Harness(seed: seed, runner: FakeReviewRunner())
        try h.heroTurn(6)
        h.session.callOrCheck()
        try h.respondToHero()
        try h.hooks.mutate { g in
            while g.phase != .done {
                if g.phase == .between { try advanceStreet(g) } else { try act(g, g.actor, .call) }
            }
        }
        return try XCTUnwrap(h.state.review.input)
    }

    func testTheHeroAnalysisMatchesTheReviewPortOnTheSameDecisions() throws {
        let input = try settledInput()
        XCTAssertFalse(input.decisions.isEmpty)
        var reported: [(Int, Int)] = []
        let summary = try analyzeHeroReview(input.heroInput, trials: trials) { reported.append(($0, $1)) }
        let decisions = input.decisions.map(ReviewDecision.init)
        let steps = try decisions.map { try analyzeDecision($0, trials: trials) }
        XCTAssertEqual(summary, summarizeReview(decisions: decisions, steps: steps))
        XCTAssertEqual(reported.map(\.0), Array(1...input.decisions.count))
        XCTAssertTrue(reported.allSatisfy { $0.1 == input.decisions.count })
        // The summary is what the session stores as its analysis.
        let analysis: HandReviewAnalysis = summary
        XCTAssertEqual(analysis.priorityIndex, summary.priorityIndex)
    }

    func testTheAdapterOnlyPassesBeforeActionSnapshots() throws {
        let input = try settledInput()
        let converted = input.heroInput.reviewDecisions
        XCTAssertEqual(converted.count, input.decisions.count)
        for (snapshot, decision) in zip(input.decisions, converted) {
            XCTAssertEqual(decision.hole, snapshot.hole)
            XCTAssertEqual(decision.board, snapshot.board)
            XCTAssertEqual(decision.pot, snapshot.pot)
            XCTAssertEqual(decision.action, snapshot.action)
        }
    }

    func testCancellationStopsBeforeTheNextDecision() throws {
        let input = try settledInput()
        var progressCalls = 0
        XCTAssertThrowsError(try analyzeHeroReview(input.heroInput, trials: trials, isCancelled: { true }) { _, _ in
            progressCalls += 1
        }) { error in
            XCTAssertEqual(error as? ReviewCancelledError, ReviewCancelledError())
        }
        XCTAssertEqual(progressCalls, 0)

        var cancelled = false
        XCTAssertThrowsError(try analyzeHeroReview(input.heroInput, trials: trials, isCancelled: { cancelled }) { _, _ in
            cancelled = true
        })
    }

    func testAnEmptyInputSummarizesWithoutDecisions() throws {
        let input = try settledInput()
        var hero = input.heroInput
        hero.decisions = []
        let summary = try analyzeHeroReview(hero, trials: trials)
        XCTAssertTrue(summary.steps.isEmpty)
        XCTAssertEqual(summary.priorityIndex, 0)
    }

    func testARunnerBuiltOnTheAdapterDrivesTheSessionToADoneReview() throws {
        // A synchronous runner: the session must accept a job that completes inside `start`.
        let runner = ClosureReviewRunner { job, sink in
            do {
                let summary = try analyzeHeroReview(job.input, trials: 40) { sink.progress(done: $0, total: $1) }
                sink.complete(summary)
            } catch {
                sink.fail(error)
            }
            return CancelHandle()
        }
        let h = Harness(seed: 7, runner: runner)
        try h.heroTurn(6)
        h.session.callOrCheck()
        try h.respondToHero()
        try h.hooks.mutate { g in
            while g.phase != .done {
                if g.phase == .between { try advanceStreet(g) } else { try act(g, g.actor, .call) }
            }
        }
        h.session.openReview()
        let review = h.state.review
        XCTAssertEqual(review.status, .done)
        let summary = try XCTUnwrap(review.analysis as? ReviewSummary)
        XCTAssertEqual(summary.steps.count, review.input?.decisions.count)
        XCTAssertEqual(review.selected, summary.priorityIndex)
    }
}
