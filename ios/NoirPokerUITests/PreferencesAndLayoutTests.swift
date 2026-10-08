import UIKit
import XCTest

/// Saved preferences (seat count, opponent styles) and layout variants: large
/// accessibility text and the tablet two-pane table.
final class PreferencesAndLayoutTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Choosing 9 players keeps the current hand at 6, deals 9 on the next
    /// hand, and survives a relaunch.
    func testSeatCountAppliesNextHandAndPersists() {
        let app = Noir.launch()
        XCTAssertEqual(app.state.players, 6)
        app.tapWhenReady(app.buttons["settings"])
        app.tapWhenReady(app.buttons["Table size: 9 players"], timeout: 5)
        XCTAssertTrue(app.buttons["Table size: 9 players"].isSelected)
        app.buttons["Close settings"].firstMatch.tap()
        XCTAssertEqual(app.state.players, 6, "The seat count applies at the next deal")
        XCTAssertEqual(app.element("table-size").value as? String, "9 players")
        XCTAssertFalse(app.element("seat-8").exists)

        app.playToSettlement(fold: true)
        app.tapWhenReady(app.nextButton)
        XCTAssertTrue(app.waitUntil { app.state.players == 9 }, app.probe.label)
        XCTAssertEqual(app.state.totals.count, 9)
        XCTAssertEqual(app.state.wealth, 45_000, "A new table seats nine stacks of 5,000")
        XCTAssertTrue(app.element("seat-8").waitForExistence(timeout: 5))

        app.terminate()
        let relaunched = Noir.launch(resetPreferences: false)
        XCTAssertEqual(relaunched.state.players, 9, "The seat count is saved")
        XCTAssertEqual(relaunched.element("table-size").value as? String, "9 players")
        XCTAssertTrue(relaunched.element("seat-8").waitForExistence(timeout: 5))
    }

    /// Closing Opponent Styles discards the draft; saving applies it next hand.
    func testOpponentStylesDiscardAndSave() {
        let app = Noir.launch()
        let styles = app.buttons["opponent-styles"]
        XCTAssertTrue(styles.waitForExistence(timeout: 10))
        let initial = styles.value as? String

        // Discard: Mixed Lineup, then close without saving.
        styles.tap()
        app.tapWhenReady(app.buttons["mixed-lineup"], timeout: 5)
        app.buttons["Close opponent settings"].firstMatch.tap()
        XCTAssertTrue(styles.waitForExistence(timeout: 5))
        XCTAssertTrue(app.waitUntil(timeout: 5) { !app.buttons["save-opponents"].exists })
        XCTAssertEqual(styles.value as? String, initial, "A discarded draft changes nothing")

        // Save: Mixed Lineup, then Save · Applies Next Hand.
        styles.tap()
        app.tapWhenReady(app.buttons["mixed-lineup"], timeout: 5)
        app.tapWhenReady(app.buttons["save-opponents"], timeout: 5)
        XCTAssertTrue(styles.waitForExistence(timeout: 5))
        XCTAssertTrue(app.waitUntil(timeout: 5) { (styles.value as? String) == "Next Hand" },
                      "Saved styles are pending until the next hand: \(styles.value ?? "")")
    }

    /// At the largest accessibility text size the action buttons and the
    /// settled-hand buttons still render and can be used.
    func testLargeAccessibilityTextShowsActionButtons() {
        let app = Noir.launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.waitForHeroTurn(), app.probe.label)
        for button in [app.raiseButton, app.foldButton, app.callButton] {
            XCTAssertTrue(button.exists)
            app.reveal(button)
            XCTAssertTrue(button.isHittable, "\(button) is not reachable at accessibility sizes")
            XCTAssertFalse(button.label.isEmpty)
        }
        app.foldButton.tap()
        app.playToSettlement(fold: true)
        app.reveal(app.nextButton)
        XCTAssertTrue(app.nextButton.isHittable)
        app.reveal(app.replayButton)
        XCTAssertTrue(app.replayButton.isHittable)
    }
}

/// The tablet layout. Runs on an iPad destination and skips on phones.
final class TabletLayoutTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// In landscape the table and the sidebar sit side by side, with the
    /// sidebar footnote; nine seats fit on the felt and the hand can be played.
    func testTabletLandscapeShowsTableAndSidebar() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Tablet layout runs on iPad only")
        let app = Noir.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Stay patient")).firstMatch
            .waitForExistence(timeout: 10), "The wide layout shows the sidebar footnote")
        XCTAssertTrue(app.waitForHeroTurn(), app.probe.label)
        XCTAssertTrue(app.foldButton.isHittable, "The action panel is visible without scrolling")
        XCTAssertTrue(app.element("stat-hands").isHittable, "The sidebar is visible next to the table")

        app.tapWhenReady(app.buttons["settings"])
        app.tapWhenReady(app.buttons["Table size: 9 players"], timeout: 5)
        app.buttons["Close settings"].firstMatch.tap()
        app.playToSettlement(fold: true)
        app.tapWhenReady(app.nextButton)
        XCTAssertTrue(app.waitUntil { app.state.players == 9 }, app.probe.label)
        for seat in 1...8 {
            XCTAssertTrue(app.element("seat-\(seat)").waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.waitForHeroTurn(), app.probe.label)
        XCTAssertTrue(app.foldButton.isHittable)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.waitUntil(timeout: 10) { app.foldButton.exists && app.element("hand-label").exists })
    }
}
