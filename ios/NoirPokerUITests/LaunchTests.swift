import XCTest

/// Launch, sheets and the main hand flow on the phone layout.
final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testOpensNativeRulesSheet() {
        let app = Noir.launch()
        XCTAssertTrue(app.staticTexts["NOIR"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["pot-details"].waitForExistence(timeout: 10))
        app.buttons["How to Play"].tap()
        XCTAssertTrue(app.buttons["Back to Table"].waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["How to Play"].waitForExistence(timeout: 5))
    }

    /// Checks or calls through hand 1 to settlement and verifies chip
    /// conservation and the session counters.
    func testPlaysAHandToSettlement() {
        let app = Noir.launch()
        XCTAssertEqual(app.state.hand, 1)
        XCTAssertEqual(app.state.players, 6)
        if app.waitForHeroTurn() { Noir.snapshot("phone-hero-turn", in: self) }
        app.playToSettlement(fold: false)
        Noir.snapshot("phone-settled", in: self)
        let settled = app.state
        XCTAssertTrue(settled.isDone)
        XCTAssertEqual(settled.wealth, 30_000, "Chips were created or lost: \(app.probe.label)")
        XCTAssertEqual(settled.totals.reduce(0, +), 30_000)
        XCTAssertEqual(app.handsPlayed, "1")
        XCTAssertTrue(app.replayButton.exists)
        XCTAssertTrue(app.reviewButton.exists)
    }

    /// Folds at the first decision, then Finish Hand deals the rest at once.
    /// Runs on the real-time clock so opponents are still thinking (at least
    /// 1.2 s each) when Finish Hand is tapped.
    func testFoldThenFinishHand() {
        let app = Noir.launch(speed: 1)
        XCTAssertTrue(app.waitForHeroTurn(), "The hero never got a decision: \(app.probe.label)")
        app.foldButton.tap()
        // Finish Hand appears while opponents are still playing; with the fast
        // clock the hand may settle first, which is also correct.
        XCTAssertTrue(app.finishButton.waitForExistence(timeout: 5), "Finish Hand appears after a fold")
        XCTAssertTrue(app.finishButton.isEnabled)
        app.finishButton.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.state.isDone }, "Finish Hand did not settle the hand: \(app.probe.label)")
        XCTAssertEqual(app.state.boardCount, 5, "Finish Hand deals all five board cards")
        XCTAssertEqual(app.state.wealth, 30_000)
        XCTAssertTrue(app.nextButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.finishButton.exists)
        XCTAssertEqual(app.handsPlayed, "1")
    }

    /// Replay Hand deals the same hole cards again, reverses the result, and a
    /// second settlement counts the hand only once.
    func testReplayHandRestoresHoleCardsAndReversesOnce() {
        let app = Noir.launch()
        XCTAssertTrue(app.waitForHeroTurn())
        let first = app.state
        XCTAssertFalse(first.hole.isEmpty)
        XCTAssertEqual(first.totals, Array(repeating: 5_000, count: 6))
        app.playToSettlement(fold: true)
        XCTAssertEqual(app.handsPlayed, "1")

        app.tapWhenReady(app.replayButton)
        XCTAssertTrue(app.waitUntil { !app.state.isDone && app.state.replayAttempt == 1 }, app.probe.label)
        let replay = app.state
        XCTAssertEqual(replay.hand, first.hand)
        XCTAssertEqual(replay.hole, first.hole, "Replay Hand must deal the same hole cards")
        XCTAssertEqual(app.handsPlayed, "0", "Replay Hand reverses the settled result")
        XCTAssertTrue(app.waitForHeroTurn())
        XCTAssertEqual(app.state.totals, Array(repeating: 5_000, count: 6), "Stacks return to their start-of-hand values")

        app.playToSettlement(fold: true)
        XCTAssertEqual(app.handsPlayed, "1", "The replayed hand is counted once")
        XCTAssertEqual(app.state.wealth, 30_000)
        XCTAssertEqual(app.state.hand, first.hand)
    }

    /// Next Hand deals hand 2 from the settled stacks of hand 1.
    func testNextHandKeepsStacks() {
        let app = Noir.launch()
        app.playToSettlement(fold: true)
        let settled = app.state.totals
        XCTAssertEqual(settled.reduce(0, +), 30_000)
        app.tapWhenReady(app.nextButton)
        XCTAssertTrue(app.waitUntil { app.state.hand == 2 }, app.probe.label)
        let handLabel = app.element("hand-label")
        XCTAssertTrue(handLabel.label.contains("Hand 02"), handLabel.label)
        XCTAssertTrue(app.waitForHeroTurn(), "The hero never got a decision in hand 2")
        // Preflop, each player's stack plus street bet equals the stack carried over.
        XCTAssertEqual(app.state.totals, settled)
        XCTAssertEqual(app.handsPlayed, "1")
    }

    /// Start New Session resets stacks, the hand number and the counters.
    func testStartNewSessionResetsStats() {
        let app = Noir.launch()
        app.playToSettlement(fold: true)
        app.tapWhenReady(app.nextButton)
        XCTAssertTrue(app.waitUntil { app.state.hand == 2 })
        XCTAssertEqual(app.handsPlayed, "1")

        app.tap(app.buttons["start-new-session"], until: app.resetConfirmButton)
        app.resetConfirmButton.tap()
        XCTAssertTrue(app.waitUntil { app.state.hand == 1 }, app.probe.label)
        XCTAssertEqual(app.handsPlayed, "0")
        XCTAssertEqual(app.element("stat-wins").value as? String, "0")
        XCTAssertTrue(app.waitForHeroTurn())
        XCTAssertEqual(app.state.totals, Array(repeating: 5_000, count: 6))
    }

    /// The eye toggles appear only after settlement, switch one seat without
    /// touching stacks, and are cleared by the next deal.
    func testRevealTogglesClearOnNextHand() {
        let app = Noir.launch()
        XCTAssertTrue(app.waitForHeroTurn())
        XCTAssertFalse(app.buttons["peek-toggle-1"].exists, "No eye toggles before settlement")
        app.playToSettlement(fold: true)

        let toggles = (1...5).map { app.buttons["peek-toggle-\($0)"] }
        XCTAssertTrue(toggles[0].waitForExistence(timeout: 5))
        XCTAssertEqual(toggles.filter { $0.exists }.count, 5, "Every opponent gets an eye toggle")
        let eye = toggles[0]
        app.reveal(eye)
        let before = eye.isSelected
        let totalsBefore = app.state.totals
        eye.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { eye.isSelected != before }, "The eye toggle did not switch")
        XCTAssertEqual(app.state.totals, totalsBefore, "Revealing cards never changes stacks")
        XCTAssertEqual(app.state.wealth, 30_000)
        eye.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { eye.isSelected == before })
        if !before { eye.tap() }

        app.tapWhenReady(app.nextButton)
        XCTAssertTrue(app.waitUntil { app.state.hand == 2 })
        XCTAssertTrue(app.waitUntil(timeout: 5) { toggles.allSatisfy { !$0.exists } },
                      "Eye toggles are cleared on the next hand")
    }

    /// Opens Hand Review after a settled hand, waits for the analysis to
    /// finish, checks the verdict chips and the candidate action simulation,
    /// and visits both tabs.
    func testReviewsAFinishedHand() {
        let app = Noir.launch()
        app.playToSettlement(fold: true)
        app.tapWhenReady(app.reviewButton)
        let opponentsTab = app.buttons["review-tab-opponents"]
        XCTAssertTrue(opponentsTab.waitForExistence(timeout: 10))
        XCTAssertTrue(app.element("review-status").exists)
        XCTAssertTrue(app.waitForReviewAnalysis(), "The review analysis never finished")
        if let probe = app.visibleState {
            XCTAssertEqual(probe.reviewStatus, "done", probe.fields.description)
            XCTAssertTrue(probe.reviewOpen)
        }
        XCTAssertFalse(app.reviewRetryButton.exists, "The analysis did not fail")
        // The hero folded at a decision, so there is a step to grade.
        XCTAssertFalse(app.reviewEmptyNote.firstMatch.exists)
        XCTAssertTrue(app.reviewVerdicts.firstMatch.exists, "Each graded step shows a verdict chip")
        XCTAssertTrue(app.reviewSimulation.firstMatch.exists,
                      "The step shows the candidate action simulation, or the note that it can't run")
        Noir.snapshot("phone-review-hero", in: self)
        opponentsTab.tap()
        XCTAssertTrue(app.buttons["review-opponent-filter"].waitForExistence(timeout: 5))
        Noir.snapshot("phone-review-opponents", in: self)
        app.buttons["review-tab-hero"].tap()
        XCTAssertTrue(app.element("review-status").waitForExistence(timeout: 5))
        app.reviewCloseButton.tap()
        XCTAssertTrue(app.waitForReviewClosed(), "The review sheet did not close: \(app.probe.label)")
    }

    // MARK: Fold-win, repeated requests and interrupted review

    /// After the hero folds and an opponent wins before the river, Finish Hand
    /// (a practice runout) is offered beside Next Hand and Replay Hand. The
    /// runout shows five community cards but leaves the settled result alone.
    func testFoldWinOffersFinishHandBesideSettledButtons() {
        let app = Noir.launch()
        XCTAssertTrue(app.foldUntilFoldWinBeforeRiver(), "No hand ended before the river: \(app.probe.label)")
        let settled = app.state
        let handsPlayed = app.handsPlayed
        XCTAssertTrue(settled.isDone)
        XCTAssertLessThan(settled.boardCount, 5)
        XCTAssertTrue(app.finishButton.waitForExistence(timeout: 5), "Finish Hand is offered after a fold-win")
        XCTAssertTrue(app.finishButton.isEnabled)
        XCTAssertTrue(app.nextButton.exists, "Next Hand sits beside Finish Hand")
        XCTAssertTrue(app.replayButton.exists, "Replay Hand sits beside Finish Hand")
        XCTAssertTrue(app.reviewButton.exists, "Review Hand sits beside Finish Hand")
        Noir.snapshot("phone-fold-win", in: self)

        app.tapWhenReady(app.finishButton)
        XCTAssertTrue(app.waitUntil(timeout: 10) { app.state.practiceRunout }, "No practice runout: \(app.probe.label)")
        let runout = app.state
        XCTAssertEqual(runout.boardCount, 5, "The practice runout shows all five community cards")
        XCTAssertEqual(runout.settlementCount, settled.settlementCount, "The settled board is unchanged")
        XCTAssertEqual(runout.totals, settled.totals, "The practice runout never moves chips")
        XCTAssertEqual(runout.wealth, 30_000)
        XCTAssertEqual(runout.hand, settled.hand)
        XCTAssertEqual(app.handsPlayed, handsPlayed, "The fold-win is counted once")
        XCTAssertTrue(app.waitUntil(timeout: 5) { !app.finishButton.exists }, "Finish Hand is gone after the runout")
        XCTAssertTrue(app.nextButton.exists)
        XCTAssertTrue(app.replayButton.exists)
    }

    /// Double-tapping Finish Hand settles the hand once and creates no chips.
    /// Runs on the real-time clock so Finish Hand is tapped mid-hand. Finish
    /// Hand can settle the hand between the two taps, and Next Hand can then
    /// take the second tap, so the hand number may advance once, never twice.
    func testDoubleTapOnFinishHandSettlesOnce() {
        let app = Noir.launch(speed: 1)
        XCTAssertTrue(app.waitForHeroTurn(), "The hero never got a decision: \(app.probe.label)")
        app.foldButton.tap()
        XCTAssertTrue(app.finishButton.waitForExistence(timeout: 5))
        app.doubleTapWhenReady(app.finishButton)
        XCTAssertTrue(app.waitUntil(timeout: 10) { app.state.isDone || app.state.hand == 2 },
                      "Finish Hand did not settle the hand: \(app.probe.label)")
        Thread.sleep(forTimeInterval: 1)
        let state = app.state
        XCTAssertLessThanOrEqual(state.hand, 2, "The hand number advances at most once")
        XCTAssertEqual(state.wealth, 30_000, "Chips were created or lost: \(app.probe.label)")
        XCTAssertEqual(state.totals.reduce(0, +), 30_000)
        XCTAssertEqual(app.handsPlayed, "1", "The hand is settled once")
    }

    /// Double-tapping Next Hand deals once, and double-tapping Replay Hand
    /// restarts the hand once; the replayed hand is counted once.
    func testDoubleTapsOnNextHandAndReplayHandActOnce() {
        let app = Noir.launch()
        app.playToSettlement(fold: true)
        XCTAssertEqual(app.handsPlayed, "1")

        app.doubleTapWhenReady(app.nextButton)
        XCTAssertTrue(app.waitUntil { app.state.hand == 2 }, app.probe.label)
        // A second deal would need hand 2 to settle first; give a stray tap time to land.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(app.state.hand, 2, "Next Hand deals once")
        XCTAssertEqual(app.state.wealth, 30_000)
        XCTAssertEqual(app.state.totals.reduce(0, +), 30_000)
        XCTAssertEqual(app.handsPlayed, "1")

        app.playToSettlement(fold: true)
        XCTAssertEqual(app.state.hand, 2)
        XCTAssertEqual(app.handsPlayed, "2")
        app.doubleTapWhenReady(app.replayButton)
        XCTAssertTrue(app.waitUntil { app.state.replayAttempt >= 1 }, app.probe.label)
        Thread.sleep(forTimeInterval: 1)
        let replay = app.state
        XCTAssertEqual(replay.replayAttempt, 1, "Replay Hand restarts the hand once")
        XCTAssertEqual(replay.hand, 2)
        XCTAssertEqual(replay.wealth, 30_000)

        app.playToSettlement(fold: true)
        XCTAssertEqual(app.state.replayAttempt, 1)
        XCTAssertEqual(app.state.hand, 2)
        XCTAssertEqual(app.handsPlayed, "2", "The replayed hand is counted once")
        XCTAssertEqual(app.state.wealth, 30_000)
    }

    /// Replaying the same hand a second time returns to the same starting
    /// point as the first replay: hand number, hole cards and stacks.
    func testReplayingTwiceReturnsToTheSameStart() {
        let app = Noir.launch()
        app.playToSettlement(fold: true)

        app.tapWhenReady(app.replayButton)
        XCTAssertTrue(app.waitUntil { !app.state.isDone && app.state.replayAttempt == 1 }, app.probe.label)
        XCTAssertTrue(app.waitForHeroTurn(), "The hero never got a decision in the replay")
        let first = app.state
        // Play the first replay differently from the original hand.
        app.playToSettlement(fold: false)
        XCTAssertEqual(app.handsPlayed, "1")

        app.tapWhenReady(app.replayButton)
        XCTAssertTrue(app.waitUntil { !app.state.isDone && app.state.replayAttempt == 2 }, app.probe.label)
        XCTAssertTrue(app.waitForHeroTurn(), "The hero never got a decision in the second replay")
        let second = app.state
        XCTAssertEqual(second.hand, first.hand, "Replay keeps the hand number")
        XCTAssertEqual(second.hole, first.hole, "Replay deals the same hole cards")
        XCTAssertEqual(second.totals, first.totals, "Stacks match the first replay")
        XCTAssertEqual(second.totals, Array(repeating: 5_000, count: 6))
        XCTAssertEqual(app.handsPlayed, "0", "The second settlement is reversed too")
        XCTAssertEqual(second.wealth, 30_000)
    }

    /// Closing Hand Review before the analysis finishes and dealing the next
    /// hand leaves no sheet behind, and the next hand's review still works.
    func testClosingReviewMidAnalysisThenNextHand() {
        let app = Noir.launch()
        app.playToSettlement(fold: true)
        app.tapWhenReady(app.reviewButton)
        XCTAssertTrue(app.buttons["review-tab-hero"].waitForExistence(timeout: 10))
        app.reviewCloseButton.tap()
        XCTAssertTrue(app.waitForReviewClosed(), "The review sheet did not close: \(app.probe.label)")

        app.tapWhenReady(app.nextButton)
        XCTAssertTrue(app.waitUntil { app.state.hand == 2 }, app.probe.label)
        // A late analysis result must not reopen the sheet.
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(app.buttons["review-tab-hero"].exists, "No stale review sheet")
        XCTAssertFalse(app.state.reviewOpen)
        XCTAssertEqual(app.state.hand, 2)
        XCTAssertEqual(app.state.wealth, 30_000)

        app.playToSettlement(fold: true)
        app.tapWhenReady(app.reviewButton)
        XCTAssertTrue(app.buttons["review-tab-hero"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.waitForReviewAnalysis(), "Hand 2's review never finished")
        XCTAssertFalse(app.reviewRetryButton.exists)
        app.reviewCloseButton.tap()
        XCTAssertTrue(app.waitForReviewClosed(), "The review sheet did not close: \(app.probe.label)")
    }

    /// Opening Hand Review and then replaying the hand closes the sheet and
    /// resets the review: the replayed hand has nothing to review until it
    /// settles again.
    func testReplayAfterOpeningReviewResetsIt() {
        let app = Noir.launch()
        app.playToSettlement(fold: true)
        app.tapWhenReady(app.reviewButton)
        XCTAssertTrue(app.buttons["review-tab-hero"].waitForExistence(timeout: 10))
        // The sheet is modal, so close it first; the analysis may still be running.
        app.reviewCloseButton.tap()
        XCTAssertTrue(app.waitForReviewClosed(), "The review sheet did not close: \(app.probe.label)")
        app.tapWhenReady(app.replayButton)
        XCTAssertTrue(app.waitUntil { app.state.replayAttempt == 1 }, app.probe.label)
        let replay = app.state
        XCTAssertEqual(replay.reviewStatus, "idle", "Replay resets the review status")
        XCTAssertFalse(replay.reviewOpen)
        XCTAssertFalse(app.buttons["review-tab-hero"].exists, "No review sheet after the replay")
        XCTAssertFalse(app.reviewButton.exists, "Nothing to review until the replay settles")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(app.buttons["review-tab-hero"].exists, "A late analysis result does not reopen the sheet")

        app.playToSettlement(fold: true)
        XCTAssertEqual(app.state.reviewStatus, "idle", "The replayed hand starts a fresh review")
        app.tapWhenReady(app.reviewButton)
        XCTAssertTrue(app.buttons["review-tab-hero"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.waitForReviewAnalysis(), "The replayed hand's review never finished")
        XCTAssertFalse(app.reviewRetryButton.exists)
        app.reviewCloseButton.tap()
        XCTAssertTrue(app.waitForReviewClosed(), "The review sheet did not close: \(app.probe.label)")
    }

    /// Opens Settings and the Start New Session confirmation, then dismisses
    /// both without changing anything.
    func testOpensSettingsAndResetConfirmation() {
        let app = Noir.launch()
        app.tapWhenReady(app.buttons["settings"])
        XCTAssertTrue(app.switches["settings-hints"].waitForExistence(timeout: 5))
        app.buttons["Close settings"].firstMatch.tap()
        app.tap(app.buttons["start-new-session"], until: app.buttons["reset-cancel"])
        app.buttons["reset-cancel"].tap()
        XCTAssertTrue(app.buttons["start-new-session"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state.hand, 1)
    }
}
