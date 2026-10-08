import XCTest
@testable import PokerCore

/// The Hand Review dialog content built from the session's review state.
final class ReviewPresentationTests: XCTestCase {
    /// Plays seeded hands with real bots, calling or checking on every hero
    /// turn, until a hand settles in which the hero acted and bots acted.
    private func settledHarness(runner: ReviewRunner) throws -> Harness {
        for seed in 1...40 {
            let h = Harness(seed: seed, runner: runner)
            h.session.start()
            for _ in 0..<200 {
                h.runBots()
                let g = h.game
                if g.phase == .done { break }
                if g.phase == .playing && g.actor == 0 {
                    h.session.callOrCheck()
                } else if h.scheduler.nextDueAt == nil {
                    break
                }
            }
            if h.game.phase == .done, let input = h.state.review.input,
               !input.decisions.isEmpty, !input.opponents.isEmpty {
                return h
            }
        }
        XCTFail("No seed produced a settled hand with hero and bot decisions")
        throw TestFailure()
    }

    private func analyzingRunner(trials: Int = 40) -> ClosureReviewRunner {
        ClosureReviewRunner { job, sink in
            do {
                let summary = try analyzeHeroReview(job.input, trials: trials, progress: { sink.progress(done: $0, total: $1) })
                sink.complete(summary)
            } catch {
                sink.fail(error)
            }
            return CancelHandle()
        }
    }

    func testNoContentWithoutASettledHand() {
        let h = Harness(seed: 3, runner: FakeReviewRunner())
        h.session.start()
        XCTAssertNil(presentReviewDialog(h.state.review))
    }

    func testRunningReviewShowsProgressAndPendingSteps() throws {
        let runner = FakeReviewRunner()
        let h = try settledHarness(runner: runner)
        h.session.openReview()
        var content = try XCTUnwrap(presentReviewDialog(h.state.review))
        let input = try XCTUnwrap(h.state.review.input)
        let n = input.decisions.count
        XCTAssertEqual(content.title, "Hand \(input.hand) · Hand Review")
        XCTAssertTrue(content.running)
        XCTAssertEqual(content.statusText, "Analyzing decision 0 of \(n)…")
        XCTAssertEqual(content.summaryTitle, ReviewDialogCopy.summaryTitleDefault)
        XCTAssertNil(content.priorityLabel)
        XCTAssertFalse(content.retryVisible)
        XCTAssertEqual(content.hero.items.count, n)
        XCTAssertTrue(content.hero.items.allSatisfy { $0.chip == "Pending" && $0.chipKind == .pending })
        XCTAssertEqual(content.hero.items.first?.selected, true)
        let detail = try XCTUnwrap(content.hero.detail)
        XCTAssertEqual(detail.status, "Analyzing")
        XCTAssertEqual(detail.title, "Step 1 · \(ReviewCopy.streetNames[input.decisions[0].street])")
        XCTAssertEqual(detail.suggestion, ReviewDialogCopy.suggestionPending)
        XCTAssertEqual(detail.simulationNote, ReviewDialogCopy.simulationRunning)
        XCTAssertNil(detail.simulation)
        XCTAssertNil(detail.modelNote)
        XCTAssertEqual(detail.metrics[2].value, "…")
        XCTAssertEqual(detail.stepPosition, "1 / \(n)")
        XCTAssertFalse(detail.canGoPrevious)
        XCTAssertEqual(detail.hole, input.hole)

        runner.started.last?.sink.progress(done: 1, total: n)
        content = try XCTUnwrap(presentReviewDialog(h.state.review))
        XCTAssertEqual(content.statusText, "Analyzing decision 1 of \(n)…")
        XCTAssertEqual(content.progressDone, 1)
        XCTAssertEqual(content.progressTotal, n)

        runner.started.last?.sink.fail(TestFailure())
        content = try XCTUnwrap(presentReviewDialog(h.state.review))
        XCTAssertTrue(content.retryVisible)
        XCTAssertFalse(content.running)
        XCTAssertEqual(content.statusText, ReviewDialogCopy.stateError)
    }

    func testFinishedReviewShowsGradesSimulationAndMetrics() throws {
        let h = try settledHarness(runner: analyzingRunner())
        h.session.openReview()
        let review = h.state.review
        XCTAssertEqual(review.status, .done)
        let summary = try XCTUnwrap(review.analysis as? ReviewSummary)
        let content = try XCTUnwrap(presentReviewDialog(review))
        XCTAssertFalse(content.running)
        XCTAssertEqual(content.summaryTitle, summary.title)
        XCTAssertEqual(content.statusText, summary.summary)
        XCTAssertEqual(content.priorityIndex, summary.priorityIndex)
        XCTAssertEqual(content.priorityLabel, summary.attention + summary.consider > 0
                       ? ReviewDialogCopy.priorityButton : ReviewDialogCopy.fromFirstButton)
        for (item, step) in zip(content.hero.items, summary.steps) {
            XCTAssertEqual(item.chip, ReviewDialogCopy.status(step.status))
            XCTAssertEqual(item.chipKind.rawValue, step.status.rawValue)
        }
        let selected = review.selected
        XCTAssertEqual(selected, summary.priorityIndex)
        let step = summary.steps[selected]
        let decision = try XCTUnwrap(review.input?.decisions[selected])
        let detail = try XCTUnwrap(content.hero.detail)
        XCTAssertEqual(detail.decisionTitle, step.title)
        XCTAssertEqual(detail.evidence, step.evidence)
        XCTAssertEqual(detail.routes.first?.kicker, ReviewDialogCopy.routePrimary)
        XCTAssertEqual(detail.routes.first?.label, step.routes.primary.label)
        XCTAssertEqual(detail.routes.count, step.routes.secondary == nil ? 1 : 2)
        XCTAssertEqual(detail.yourChoice, actionLabel(LabelStep(decision)))
        if let sim = step.simulation {
            let table = try XCTUnwrap(detail.simulation)
            XCTAssertNil(detail.simulationNote)
            XCTAssertEqual(table.rows.count, sim.rows.count)
            XCTAssertEqual(table.caption, "\(sim.trials) hands simulated per action and range · Net chip change from this decision")
            XCTAssertTrue(table.rows.allSatisfy { $0.cells.count == 2 && $0.cells.allSatisfy { $0.margin.hasPrefix("≈ ±") } })
        } else {
            XCTAssertEqual(detail.simulationNote, ReviewDialogCopy.simulationUnavailable)
        }
        let model = try XCTUnwrap(detail.modelNote)
        XCTAssertTrue(model.contains("Random / action-weighted equity: "))
        XCTAssertTrue(model.contains("\(step.metrics.trials)"))
        XCTAssertEqual(detail.metrics.map(\.label),
                       [ReviewDialogCopy.metricPrice, ReviewDialogCopy.metricEquity, ReviewDialogCopy.metricContestable])
        XCTAssertEqual(detail.metrics[0].value, decision.legal.callAmount != 0
                       ? "\(Int(jsRound(step.metrics.required * 100)))%" : ReviewDialogCopy.metricNoCall)
        XCTAssertEqual(detail.metrics[2].value, formatChips(step.metrics.contestable))
        XCTAssertLessThanOrEqual(detail.publicActions.count, 6)
        XCTAssertEqual(detail.publicActionsEmpty == nil, !detail.publicActions.isEmpty)

        // Navigation mirrors the session's selection.
        h.session.selectReviewStep(0)
        let first = try XCTUnwrap(presentReviewDialog(h.state.review))
        XCTAssertEqual(first.hero.items.firstIndex { $0.selected }, 0)
        XCTAssertFalse(try XCTUnwrap(first.hero.detail).canGoPrevious)
    }

    func testOpponentPanelListsExecutedRecordsAndFilters() throws {
        let h = try settledHarness(runner: FakeReviewRunner())
        h.session.openReview()
        h.session.setReviewPerspective(.opponents)
        let input = try XCTUnwrap(h.state.review.input)
        var content = try XCTUnwrap(presentReviewDialog(h.state.review))
        XCTAssertEqual(content.perspective, .opponents)
        let panel = content.opponents
        XCTAssertEqual(panel.items.count, input.opponents.count)
        XCTAssertEqual(panel.items.map(\.number), input.opponents.map(\.sequence))
        XCTAssertEqual(panel.filters.first?.label, ReviewDialogCopy.opponentFilterAll)
        XCTAssertEqual(panel.filters.first?.selected, true)
        var ids: [Int] = []
        for r in input.opponents where !ids.contains(r.id) { ids.append(r.id) }
        XCTAssertEqual(panel.filters.dropFirst().map(\.seat), ids)
        let detail = try XCTUnwrap(panel.detail)
        let record = input.opponents[0]
        XCTAssertEqual(detail.chip, ReviewDialogCopy.opponentRecordChip)
        XCTAssertEqual(detail.holeLabel, "\(record.name)'s Hole Cards at the Time")
        XCTAssertEqual(detail.reasons, explainOpponent(record).reasons)
        XCTAssertEqual(detail.sequenceText, "Public action #\(record.sequence)")
        XCTAssertEqual(detail.branches.count, record.trace.checks.count)
        XCTAssertEqual(detail.branchesEmpty == nil, !record.trace.checks.isEmpty)

        let seat = try XCTUnwrap(ids.last)
        h.session.setOpponentReviewFilter(seat)
        content = try XCTUnwrap(presentReviewDialog(h.state.review))
        XCTAssertTrue(content.opponents.items.allSatisfy { $0.meta.hasPrefix(input.opponents.first { $0.id == seat }!.name) })
        XCTAssertEqual(content.opponents.filters.first { $0.selected }?.seat, seat)
        XCTAssertEqual(content.opponents.items.first?.selected, true)

        // The hero panel never depends on opponent records.
        var stripped = h.state.review
        stripped.input?.opponents = []
        stripped.opponentRecords = []
        let hero = try XCTUnwrap(presentReviewDialog(stripped))
        XCTAssertEqual(hero.hero, content.hero)
        XCTAssertEqual(hero.opponents.empty, ReviewDialogCopy.opponentEmpty)
    }

    func testFormattingOfResultAndBranches() {
        XCTAssertEqual(ReviewDialogCopy.resultChange(-1500), "-1,500 chips")
        XCTAssertEqual(ReviewDialogCopy.resultChange(300), "+300 chips")
        XCTAssertEqual(ReviewDialogCopy.resultChange(0), "0 chips")
        XCTAssertEqual(ReviewDialogCopy.opponentBranch(0.0421, 0.125, true), "0.042 / threshold 12.5% · Hit")
        XCTAssertEqual(ReviewDialogCopy.opponentBranch(0.5, 0.3, false), "0.500 / threshold 30.0% · Miss")
        XCTAssertEqual(ReviewDialogCopy.actionCount(1), "1 action")
        XCTAssertEqual(ReviewDialogCopy.actionCount(4), "4 actions")
        XCTAssertEqual(ReviewDialogCopy.simulationMargin(1234.5), "≈ ±1,235")
    }
}
