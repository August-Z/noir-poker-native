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
        XCTAssertEqual(content.title, "Hand #\(input.hand) · Review")
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
            XCTAssertEqual(table.caption, "\(sim.trials) hands simulated per action and range · Net chip change from this decision on")
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
        XCTAssertEqual(detail.holeLabel, "\(record.name)'s hole cards at the time")
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

    func testRunningMeansTheJobIsRunning() throws {
        let runner = FakeReviewRunner()
        let h = try settledHarness(runner: runner)
        h.session.openReview()
        XCTAssertTrue(try XCTUnwrap(presentReviewDialog(h.state.review)).running)
        // After a background pause the dialog stays open with an idle job: no spinner.
        var paused = h.state.review
        paused.status = .idle
        paused.progress = 1
        let content = try XCTUnwrap(presentReviewDialog(paused))
        XCTAssertFalse(content.running)
        XCTAssertEqual(content.statusText, ReviewDialogCopy.statePreparing)
    }

    func testSimulationCellsCarryTheirSpokenText() throws {
        let h = try settledHarness(runner: analyzingRunner())
        h.session.openReview()
        let summary = try XCTUnwrap(h.state.review.analysis as? ReviewSummary)
        for (i, step) in summary.steps.enumerated() where step.simulation != nil {
            h.session.selectReviewStep(i)
            let table = try XCTUnwrap(presentReviewDialog(h.state.review)?.hero.detail?.simulation)
            for row in table.rows {
                for (k, cell) in row.cells.enumerated() {
                    XCTAssertEqual(cell.a11y, "\(row.label), \(table.columns[k + 1]): \(cell.value) chips, \(cell.margin)")
                }
            }
        }
    }

    /// `fixtures/review-dialog.json`, recorded from the Kotlin presenter: the copy
    /// table, templated copy and both panels for settled fixture hands.
    func testPresenterOutputMatchesTheSharedReviewDialogFixture() throws {
        let fixture = try loadFixture("review-dialog.json")
        let hands = try loadFixture("review-hands.json")
        let trials = fixtureInt(fixture["trials"])

        let copy = dialogCopyJSON()
        let expectedCopy = try XCTUnwrap(fixture["copy"] as? [String: Any])
        XCTAssertEqual(Set(expectedCopy.keys), Set(copy.keys), "copy keys")
        assertJSONEqual(expectedCopy, copy, "copy")
        for item in try XCTUnwrap(fixture["templates"] as? [Any]) {
            let t = try XCTUnwrap(item as? [String: Any])
            let fn = try XCTUnwrap(t["fn"] as? String)
            let args = try XCTUnwrap(t["args"] as? [Any])
            XCTAssertEqual(dialogTemplate(fn, args), t["result"] as? String, "template \(fn) \(args)")
        }

        var analyses: [String: ReviewSummary] = [:]
        let cases = try XCTUnwrap(fixture["cases"] as? [Any])
        XCTAssertGreaterThan(cases.count, 30)
        for item in cases {
            let c = try XCTUnwrap(item as? [String: Any])
            let name = try XCTUnwrap(c["name"] as? String)
            let inputName = try XCTUnwrap(c["input"] as? String)
            let group = try XCTUnwrap(hands[try XCTUnwrap(c["source"] as? String)] as? [Any])
            let source = try XCTUnwrap(group.compactMap { $0 as? [String: Any] }.first { $0["name"] as? String == inputName })
            let input = handReviewInput(decodeInput(source["input"]))
            let spec = try XCTUnwrap(c["state"] as? [String: Any])
            let state = try dialogState(input, spec) {
                if let hit = analyses[inputName] { return hit }
                let summary = try analyzeHeroReview(input.heroInput, trials: trials)
                analyses[inputName] = summary
                return summary
            }
            let content = try XCTUnwrap(presentReviewDialog(state), name)
            let panel = try XCTUnwrap(c["panel"] as? String)
            let actual = panel == "hero" ? heroJSON(content) : opponentJSON(content.opponents)
            assertJSONEqual(c[panel], actual, name)
        }
    }

    /// Hidden cards, the future deck and the winners never change the graded
    /// hero panel: the privacy variants of review-hands.json differ only there.
    func testTheHeroPanelIsIdenticalAcrossHiddenCardVariants() throws {
        let privacy = try XCTUnwrap(try loadFixture("review-hands.json")["privacy"] as? [Any])
        XCTAssertEqual(privacy.count, 3)
        for item in privacy {
            let p = try XCTUnwrap(item as? [String: Any])
            let trials = fixtureInt((p["options"] as? [String: Any])?["trials"])
            var views: [[Any]] = []
            for v in try XCTUnwrap(p["variants"] as? [Any]) {
                let input = handReviewInput(decodeInput(v))
                let summary = try analyzeHeroReview(input.heroInput, trials: trials)
                views.append(input.decisions.indices.map { k in
                    var state = baseReviewState(input)
                    state.status = .done
                    state.progress = input.decisions.count
                    state.analysis = summary
                    state.selected = k
                    // The header reports the outcome (chip change and context); everything graded must match.
                    var hero = heroJSON(presentReviewDialog(state)!)
                    hero["change"] = nil
                    hero["context"] = nil
                    return hero
                })
            }
            XCTAssertEqual(views.count, 2)
            assertJSONEqual(views[0], views[1], p["name"] as? String ?? "privacy")
        }
    }
}

// MARK: review-dialog.json support

private func handReviewInput(_ input: ReviewInput) -> HandReviewInput {
    let decisions = input.decisions.map { d in
        DecisionSnapshot(
            index: d.index, hand: d.hand, street: d.street, position: d.position, hole: d.hole, board: d.board,
            stack: d.stack, bet: d.bet, total: d.total, pot: d.pot, currentBet: d.currentBet, minRaise: d.minRaise,
            dealer: d.dealer!, emotionMode: d.emotionMode ?? .off, legal: d.legal, pending: d.pending, action: d.action,
            amount: d.amount,
            players: d.players.map { p in
                SnapshotPlayer(id: p.id, name: p.name, position: p.position, stack: p.stack, bet: p.bet, total: p.total,
                               folded: p.folded, allin: p.allin, action: p.action, botProfile: p.state?.botProfile,
                               publicAxes: p.publicAxes, botMoodKind: p.state?.botMoodKind, actedTo: p.state?.actedTo,
                               checked: p.state?.checked ?? false)
            },
            history: d.history)
    }
    let o = input.outcome
    let outcome = HandReviewOutcome(
        profit: o.profit, paid: o.paid, returned: o.returned, folded: o.folded, wonPot: o.wonPot, board: o.board,
        pots: o.pots.map { pot in
            HandReviewPot(label: pot.label, amount: pot.amount, eligible: pot.eligible,
                          awards: pot.awards.map { HandReviewAward(name: $0.name, amount: $0.amount, label: $0.label) })
        },
        result: o.result)
    return HandReviewInput(hand: input.hand, hole: input.hole, decisions: decisions, opponents: input.opponents,
                           outcome: outcome)
}

private func baseReviewState(_ input: HandReviewInput) -> HandReviewState {
    HandReviewState(buttonVisible: true, dialogOpen: true, key: "1:\(input.hand)", input: input, status: .idle,
                    progress: 0, analysis: nil, selected: 0, perspective: .hero, opponentFilter: nil,
                    opponentSelected: 0, opponentRecords: input.opponents, jobId: 1)
}

private func dialogState(_ input: HandReviewInput, _ spec: [String: Any],
                         analysis: () throws -> ReviewSummary) throws -> HandReviewState {
    var state = baseReviewState(input)
    if spec.keys.contains("opponentSelected") {
        state.perspective = .opponents
        state.opponentSelected = fixtureInt(spec["opponentSelected"])
        if let seat = spec["opponentFilter"], !(seat is NSNull) {
            let id = fixtureInt(seat)
            state.opponentFilter = id
            state.opponentRecords = input.opponents.filter { $0.id == id }
        }
        return state
    }
    state.status = HandReviewStatus(rawValue: spec["status"] as! String)!
    state.progress = fixtureInt(spec["progress"])
    state.selected = fixtureInt(spec["selected"])
    if spec["analyzed"] as? Bool == true {
        var summary = try analysis()
        if let k = spec["dropSimulation"], !(k is NSNull) { summary.steps[fixtureInt(k)].simulation = nil }
        state.analysis = summary
    }
    return state
}

private func dialogNull(_ v: String?) -> Any { v ?? jsonNull }
private func dialogPairs(_ v: [(String, String)]) -> [Any] { v.map { [$0.0, $0.1] } }

private func timelineJSON(_ items: [ReviewTimelineItem]) -> [Any] {
    items.map {
        ["number": String($0.number), "meta": $0.meta, "action": $0.label, "chip": $0.chip,
         "tone": $0.chipKind.rawValue, "selected": $0.selected, "a11y": $0.a11y] as [String: Any]
    }
}

private func heroJSON(_ c: ReviewDialogContent) -> [String: Any] {
    typealias C = ReviewDialogCopy
    var step: Any = jsonNull
    if let s = c.hero.detail {
        var simulation: Any = jsonNull
        if let t = s.simulation {
            simulation = [
                "heading": t.heading, "stability": t.stability, "stable": t.stable, "caption": t.caption,
                "columns": t.columns,
                "rows": t.rows.map { r in
                    ["label": r.label, "cells": r.cells.map { [$0.value, $0.margin, $0.a11y] }] as [String: Any]
                },
                "detailsSummary": t.detailsSummary, "details": [t.note, t.detailsBody],
            ] as [String: Any]
        }
        step = [
            "title": s.title, "statusText": s.status, "tone": s.statusKind.rawValue,
            "hole": s.hole.map(\.key), "board": s.board.map(\.key),
            "meta": dialogPairs([(C.positionLabel, s.position), (C.potLabel, s.pot), (C.stackLabel, s.stack)]),
            "yourChoice": s.yourChoice, "suggestion": s.suggestion,
            "routes": s.routes.map { [$0.kicker, $0.label, $0.condition, $0.tradeoff] },
            "simulation": simulation, "simulationNote": dialogNull(s.simulationNote),
            "decisionTitle": s.decisionTitle, "reason": s.reason, "evidence": s.evidence,
            "confidence": s.confidence, "lesson": s.lesson, "plan": s.plan,
            "metrics": dialogPairs(s.metrics.map { ($0.label, $0.value) }), "modelNote": dialogNull(s.modelNote),
            "priceNote": s.priceNote, "publicActions": dialogPairs(s.publicActions.map { ($0.name, $0.label) }),
            "publicActionsEmpty": dialogNull(s.publicActionsEmpty), "position": s.stepPosition,
            "canPrevious": s.canGoPrevious, "canNext": s.canGoNext,
        ] as [String: Any]
    }
    return [
        "title": c.title, "change": c.resultChange, "context": c.resultContext, "stateText": c.statusText,
        "running": c.running, "progress": c.progressDone, "total": c.progressTotal, "summaryTitle": c.summaryTitle,
        "priorityButton": dialogNull(c.priorityLabel),
        "priorityIndex": c.priorityLabel == nil ? jsonNull : (c.priorityIndex.map { $0 as Any } ?? jsonNull),
        "retryVisible": c.retryVisible, "stepCount": c.hero.count, "timeline": timelineJSON(c.hero.items),
        "empty": dialogNull(c.hero.empty), "step": step,
    ]
}

private func opponentJSON(_ p: OpponentReviewPanel) -> [String: Any] {
    typealias C = ReviewDialogCopy
    var step: Any = jsonNull
    if let s = p.detail {
        step = [
            "title": s.title, "statusText": s.chip, "tone": s.chipKind.rawValue, "holeLabel": s.holeLabel,
            "hole": s.hole.map(\.key), "board": s.board.map(\.key),
            "meta": dialogPairs([(C.positionLabel, s.position), (C.potLabel, s.pot), (C.stackLabel, s.stack)]),
            "choiceLabel": s.choiceLabel, "choice": s.action, "explanationTitle": s.explanationTitle,
            "explanation": s.explanationDetail, "profileName": s.profileName, "reasons": s.reasons,
            "warning": s.warning, "branches": dialogPairs(s.branches.map { ($0.label, $0.value) }),
            "branchesEmpty": dialogNull(s.branchesEmpty), "position": s.sequenceText,
            "canPrevious": s.canGoPrevious, "canNext": s.canGoNext,
        ] as [String: Any]
    }
    return [
        "filters": p.filters.map {
            ["seat": $0.seat.map { $0 as Any } ?? jsonNull, "label": $0.label, "selected": $0.selected] as [String: Any]
        },
        "count": p.count, "timeline": timelineJSON(p.items), "empty": dialogNull(p.empty), "step": step,
    ]
}

/// The static dialog copy under the fixture's platform-neutral keys (the Kotlin names).
private func dialogCopyJSON() -> [String: Any] {
    typealias C = ReviewDialogCopy
    return [
        "eyebrow": C.eyebrow, "closeA11y": C.closeA11y, "titleDefault": C.titleDefault, "tabsA11y": C.tabsA11y,
        "tabHero": C.tabHero, "tabOpponents": C.tabOpponents, "tabOpponentsSubtitle": C.tabOpponentsSubtitle,
        "timelineA11y": C.timelineA11y, "timelineTitle": C.timelineTitle, "contextFolded": C.contextFolded,
        "contextPartialWin": C.contextPartialWin, "contextWon": C.contextWon, "contextLost": C.contextLost,
        "stateError": C.stateError, "statePreparing": C.statePreparing, "summaryTitleDefault": C.summaryTitleDefault,
        "priorityButton": C.priorityButton, "fromFirstButton": C.fromFirstButton, "retry": C.retryButton,
        "empty": C.empty, "statusAttention": C.statusAttention, "statusConsider": C.statusConsider,
        "statusSound": C.statusSound, "statusPending": C.statusPending, "statusAnalyzing": C.statusAnalyzing,
        "holeLabel": C.holeLabel, "boardLabel": C.boardLabel, "noBoard": C.noBoard, "positionLabel": C.positionLabel,
        "potLabel": C.potLabel, "stackLabel": C.stackLabel, "yourChoice": C.yourChoice,
        "suggestedLine": C.suggestedLine, "suggestionPending": C.suggestionPending, "routesA11y": C.routesA11y,
        "routePrimary": C.routePrimary, "routeSecondary": C.routeSecondary, "simA11y": C.simulationA11y,
        "simHeading": C.simulationHeading, "simStable": C.simulationStable, "simUnstable": C.simulationUnstable,
        "simColumns": C.simulationColumns, "simDetailsSummary": C.simulationDetailsSummary,
        "simDetailsBody": C.simulationDetailsBody, "simUnavailable": C.simulationUnavailable,
        "simRunning": C.simulationRunning, "decisionTitleDefault": C.decisionTitleDefault,
        "reasonDefault": C.reasonDefault, "evidenceHeading": C.evidenceHeading,
        "confidenceDefault": C.confidenceDefault, "lessonHeading": C.lessonLabel, "lessonDefault": C.lessonDefault,
        "planHeading": C.planHeading, "planDefault": C.planDefault, "metricRequired": C.metricPrice,
        "metricEquity": C.metricEquity, "metricContestable": C.metricContestable, "pricePending": C.metricPending,
        "priceNoCall": C.metricNoCall, "equityNone": C.metricNone, "priceNoteSidePots": C.priceNoteSidePots,
        "priceNoteClosing": C.priceNoteClosing, "priceNoteDefault": C.priceNoteDefault,
        "publicActionsSummary": C.publicActionsSummary, "publicActionsEmpty": C.publicActionsEmpty,
        "previous": C.previous, "next": C.next, "scope": C.scope, "methodSummary": C.methodSummary,
        "methodParagraphs": C.methodParagraphs, "methodReferencesLabel": C.methodRefsPrefix,
        "methodReferences": C.methodRefs.map { [$0.label, $0.url] },
        "methodClosingParagraphs": C.methodClosingParagraphs, "backToTable": C.backToTable,
        "oppEmpty": C.opponentEmpty, "oppIntro": C.opponentIntro, "oppFilterLabel": C.opponentFilterLabel,
        "oppFilterAll": C.opponentFilterAll, "oppTimelineA11y": C.opponentTimelineA11y,
        "oppTimelineTitle": C.opponentTimelineTitle, "oppRecordStatus": C.opponentRecordChip,
        "oppEvidenceHeading": C.opponentEvidenceHeading, "oppBranchesSummary": C.opponentBranchesSummary,
        "oppBranchesEmpty": C.opponentBranchesEmpty,
    ]
}

/// One templated copy function applied to fixture arguments.
private func dialogTemplate(_ fn: String, _ a: [Any]) -> String? {
    typealias C = ReviewDialogCopy
    func s(_ k: Int) -> String { a[k] as! String }
    func n(_ k: Int) -> Int { fixtureInt(a[k]) }
    func d(_ k: Int) -> Double { fixtureDouble(a[k]) }
    switch fn {
    case "title": return C.title(n(0))
    case "change": return C.resultChange(n(0))
    case "stateProgress": return C.stateProgress(n(0), n(1))
    case "actionCount": return C.actionCount(n(0))
    case "detailTitle": return C.detailTitle(n(0), s(1))
    case "simCaption": return C.simulationCaption(n(0))
    case "simMargin": return C.simulationMargin(d(0))
    case "modelEnumeration": return C.modelEnumeration(n(0))
    case "modelSampling": return C.modelSampling(n(0), n(1))
    case "modelEquity": return C.modelEquity(s(0), s(1))
    case "equityAbout": return C.equityAbout(s(0))
    case "stepPosition": return C.stepPosition(n(0), n(1))
    case "heroStepA11y": return C.heroStepA11y(n(0), s(1), s(2), s(3))
    case "oppStepA11y": return C.opponentStepA11y(n(0), s(1), s(2), s(3))
    case "simCellA11y": return C.simulationCellA11y(s(0), s(1), s(2), s(3))
    case "oppHoleLabel": return C.opponentHoleLabel(s(0))
    case "oppChoiceLabel": return C.opponentChoice(s(0))
    case "oppBranch": return C.opponentBranch(d(0), d(1), a[2] as! Bool)
    case "oppPublicAction": return C.opponentPublicAction(n(0))
    default: return nil
    }
}
