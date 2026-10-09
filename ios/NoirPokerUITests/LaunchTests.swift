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

        app.tapWhenReady(app.buttons["start-new-session"])
        app.tapWhenReady(app.buttons["reset-confirm"], timeout: 5)
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

    /// Opens Hand Review after a settled hand and visits both tabs.
    func testReviewsAFinishedHand() {
        let app = Noir.launch()
        app.playToSettlement(fold: true)
        app.tapWhenReady(app.reviewButton)
        let opponentsTab = app.buttons["review-tab-opponents"]
        XCTAssertTrue(opponentsTab.waitForExistence(timeout: 10))
        XCTAssertTrue(app.element("review-status").exists)
        Noir.snapshot("phone-review-hero", in: self)
        opponentsTab.tap()
        XCTAssertTrue(app.buttons["review-opponent-filter"].waitForExistence(timeout: 5))
        Noir.snapshot("phone-review-opponents", in: self)
        app.buttons["review-tab-hero"].tap()
        XCTAssertTrue(app.element("review-status").waitForExistence(timeout: 5))
        app.buttons["Close Hand Review"].firstMatch.tap()
        XCTAssertTrue(app.nextButton.waitForExistence(timeout: 5))
    }

    /// Opens Settings and the Start New Session confirmation, then dismisses
    /// both without changing anything.
    func testOpensSettingsAndResetConfirmation() {
        let app = Noir.launch()
        app.tapWhenReady(app.buttons["settings"])
        XCTAssertTrue(app.switches["settings-hints"].waitForExistence(timeout: 5))
        app.buttons["Close settings"].firstMatch.tap()
        app.tapWhenReady(app.buttons["start-new-session"])
        app.tapWhenReady(app.buttons["reset-cancel"], timeout: 5)
        XCTAssertTrue(app.buttons["start-new-session"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state.hand, 1)
    }
}
