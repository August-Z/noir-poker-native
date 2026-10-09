import UIKit
import XCTest

/// Saved preferences (seat count, opponent styles) and layout variants: seat
/// geometry at 6 and 9 seats, large accessibility text, the showdown stage
/// and the tablet table in both orientations.
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
        Noir.snapshot("phone-opponents", in: self)
        app.tapWhenReady(app.buttons["save-opponents"], timeout: 5)
        XCTAssertTrue(styles.waitForExistence(timeout: 5))
        XCTAssertTrue(app.waitUntil(timeout: 5) { (styles.value as? String) == "Applies Next Hand" },
                      "Saved styles are pending until the next hand: \(styles.value ?? "")")
    }

    /// At the largest accessibility text size the action buttons and the
    /// settled-hand buttons still render and can be used.
    func testLargeAccessibilityTextShowsActionButtons() {
        let app = Noir.launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.waitForHeroTurn(), app.probe.label)
        Noir.snapshot("phone-large-text-top", in: self)
        for button in [app.raiseButton, app.foldButton, app.callButton] {
            XCTAssertTrue(button.exists)
            app.reveal(button)
            XCTAssertTrue(button.isHittable, "\(button) is not reachable at accessibility sizes")
            XCTAssertFalse(button.label.isEmpty)
        }
        Noir.snapshot("phone-large-text-actions", in: self)
        app.foldButton.tap()
        app.playToSettlement(fold: true)
        app.reveal(app.nextButton)
        XCTAssertTrue(app.nextButton.isHittable)
        app.reveal(app.replayButton)
        XCTAssertTrue(app.replayButton.isHittable)
    }

    /// Six seats on a phone sit inside the felt at distinct places, both while
    /// the hand is live and once it settles (when seats 2 and 4 lift).
    func testPhoneSeatsSixPlayers() {
        let app = Noir.launch()
        XCTAssertTrue(app.waitForHeroTurn(), app.probe.label)
        app.assertSeatGeometry(count: 6)
        app.foldToSettlement()
        app.assertSeatGeometry(count: 6)
        Noir.snapshot("phone-6max-settled", in: self)
    }

    /// Nine seats on a phone fit inside the felt without stacking, and the
    /// action buttons stay reachable.
    func testPhoneSeatsNinePlayers() {
        let app = Noir.launch(extra: ["-noir-player-count", "9"])
        XCTAssertTrue(app.waitUntil { app.state.players == 9 }, app.probe.label)
        XCTAssertTrue(app.waitForHeroTurn(), app.probe.label)
        app.assertSeatGeometry(count: 9)
        Noir.snapshot("phone-9max", in: self)
        for button in [app.foldButton, app.callButton, app.raiseButton] {
            app.reveal(button)
            XCTAssertTrue(button.isHittable, "\(button) is not reachable with nine seats")
        }
        app.foldToSettlement()
        app.assertSeatGeometry(count: 9)
    }

    /// At the largest accessibility size with nine seats, every opponent's
    /// name, position, style, stack and last action is in a full-size row
    /// below the felt, and the row's eye toggle works once the hand settles.
    func testLargeTextNineSeatsListEverySeat() {
        let app = Noir.launch(extra: ["-noir-player-count", "9",
                                      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.waitUntil { app.state.players == 9 }, app.probe.label)
        XCTAssertTrue(app.element("seat-list").waitForExistence(timeout: 10), "The large-text seat list is missing")
        let names = ["Mia", "Alex", "River", "Kai", "Luna", "Theo", "Jade", "Leo"]
        for seat in 1...8 {
            let row = app.element("seat-list-\(seat)")
            XCTAssertTrue(row.waitForExistence(timeout: 5), "Seat \(seat) has no row")
            app.reveal(row)
            XCTAssertTrue(row.isHittable, "Seat \(seat)'s row is not reachable")
            XCTAssertTrue(row.label.hasPrefix(names[seat - 1]), "Row \(seat) names the player: \(row.label)")
            let value = (row.value as? String) ?? ""
            XCTAssertTrue(value.contains("chips"), "Row \(seat) reads the stack: \(value)")
            XCTAssertTrue(value.contains(":"), "Row \(seat) reads the last action: \(value)")
        }
        Noir.snapshot("phone-large-text-9max-seats", in: self)

        app.waitForHeroTurn()
        app.foldToSettlement()
        let toggle = app.buttons["seat-list-peek-1"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Settled rows offer the eye toggle")
        app.reveal(toggle)
        XCTAssertTrue(toggle.isHittable)
        XCTAssertGreaterThanOrEqual(toggle.frame.width, 43.5, "The eye toggle keeps a 44 pt target")
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 43.5, "The eye toggle keeps a 44 pt target")
        let shown = toggle.isSelected
        toggle.tap()
        XCTAssertTrue(app.waitUntil(timeout: 5) { app.buttons["seat-list-peek-1"].isSelected != shown },
                      "The row's eye toggle flips seat 1's cards")
        XCTAssertEqual(app.buttons["peek-toggle-1"].isSelected, !shown, "The felt and the row share one state")
    }

    /// A hand the hero calls down to a five-card showdown shows the showdown
    /// stage below the felt.
    func testCalledDownHandShowsTheShowdownStage() {
        let app = Noir.launch()
        var found = false
        for _ in 0..<12 {
            app.playToSettlement(fold: false)
            if app.state.boardCount == 5 && app.element("showdown").waitForExistence(timeout: 3) {
                found = true
                break
            }
            XCTAssertFalse(app.element("showdown").exists, "Only a five-card showdown has a stage")
            let hand = app.state.hand
            app.tapWhenReady(app.nextButton)
            XCTAssertTrue(app.waitUntil { app.state.hand == hand + 1 }, app.probe.label)
        }
        XCTAssertTrue(found, "No called-down hand reached a showdown: \(app.probe.label)")
        let stage = app.element("showdown")
        app.reveal(stage)
        XCTAssertEqual(stage.label, "Showdown hand comparison")
        Noir.snapshot("phone-showdown", in: self)
    }
}

extension XCUIApplication {
    /// Folds at the hero's decision, wherever the action panel is scrolled,
    /// and waits for the hand to settle.
    func foldToSettlement(file: StaticString = #filePath, line: UInt = #line) {
        if foldButton.exists && foldButton.isEnabled {
            reveal(foldButton)
            if foldButton.isHittable { foldButton.tap() }
        }
        playToSettlement(fold: true, file: file, line: line)
    }

    /// The port of Android's `assertSeats`: every opponent plate sits inside
    /// the arena, and plate centers are at least 24 pt apart. Frames are read
    /// twice and must agree, so a scroll in progress cannot skew them.
    func assertSeatGeometry(count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let arena = element("arena")
        XCTAssertTrue(arena.waitForExistence(timeout: 10), "The arena is missing", file: file, line: line)
        var plates: [CGRect] = []
        var table = CGRect.zero
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.8)
            table = arena.frame
            plates = (1..<count).map { element("seat-plate-\($0)").frame }
            if arena.frame == table && element("seat-plate-1").frame == plates.first { break }
        }
        XCTAssertGreaterThan(table.width, 0, "The arena has a size", file: file, line: line)
        for (i, a) in plates.enumerated() {
            let seat = i + 1
            XCTAssertTrue(element("seat-plate-\(seat)").exists, "Seat \(seat) has a plate", file: file, line: line)
            XCTAssertTrue(a.width > 0 && a.height > 0, "Seat \(seat) has a size", file: file, line: line)
            XCTAssertTrue(a.minX >= table.minX - 1 && a.maxX <= table.maxX + 1,
                          "Seat \(seat) \(a) is inside the table \(table) horizontally", file: file, line: line)
            XCTAssertTrue(a.minY >= table.minY - 1 && a.maxY <= table.maxY + 1,
                          "Seat \(seat) \(a) is inside the table \(table) vertically", file: file, line: line)
            for (j, b) in plates.enumerated() where j > i {
                let distance = hypot(a.midX - b.midX, a.midY - b.midY)
                XCTAssertGreaterThanOrEqual(distance, 24, "Seats \(seat) and \(j + 1) have distinct places",
                                            file: file, line: line)
            }
        }
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
        Noir.snapshot("ipad-landscape-6max", in: self)
        XCTAssertTrue(app.element("hand-label").isHittable, "The table is on screen")
        XCTAssertTrue(app.element("stat-hands").isHittable, "The sidebar is visible next to the table")
        app.reveal(app.foldButton)
        XCTAssertTrue(app.foldButton.isHittable, "The action panel is reachable")

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
        Noir.snapshot("ipad-landscape-9max", in: self)
        app.reveal(app.foldButton)
        XCTAssertTrue(app.foldButton.isHittable)

        app.assertSeatGeometry(count: 9)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.waitUntil(timeout: 10) { app.foldButton.exists && app.element("hand-label").exists })
    }

    /// Landscape seat geometry at six seats, live and settled.
    func testTabletLandscapeSixSeatGeometry() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Tablet layout runs on iPad only")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = Noir.launch()
        XCTAssertTrue(app.waitForHeroTurn(), app.probe.label)
        app.assertSeatGeometry(count: 6)
        app.foldToSettlement()
        app.assertSeatGeometry(count: 6)
    }

    /// In portrait the sidebar stacks below the table (beside it on the
    /// largest iPads, which are 900 pt or wider even in portrait); six and nine
    /// seats sit inside the felt and the hand can be played.
    func testTabletPortraitSeatsSixAndNinePlayers() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Tablet layout runs on iPad only")
        XCUIDevice.shared.orientation = .portrait
        let app = Noir.launch()
        XCTAssertTrue(app.waitForHeroTurn(), app.probe.label)
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(window.width, window.height, "The iPad is in portrait")
        let stats = app.element("stat-hands")
        XCTAssertTrue(stats.waitForExistence(timeout: 5))
        let table = app.element("arena").frame
        if window.width < 900 {
            XCTAssertGreaterThanOrEqual(stats.frame.minY, table.maxY, "The sidebar sits below the table")
        } else {
            XCTAssertGreaterThanOrEqual(stats.frame.minX, table.maxX, "The sidebar sits beside the table")
        }
        app.assertSeatGeometry(count: 6)
        Noir.snapshot("ipad-portrait-6max", in: self)
        app.reveal(app.foldButton)
        XCTAssertTrue(app.foldButton.isHittable)
        app.terminate()

        let nine = Noir.launch(extra: ["-noir-player-count", "9"])
        XCTAssertTrue(nine.waitUntil { nine.state.players == 9 }, nine.probe.label)
        XCTAssertTrue(nine.waitForHeroTurn(), nine.probe.label)
        nine.assertSeatGeometry(count: 9)
        Noir.snapshot("ipad-portrait-9max", in: self)
        nine.foldToSettlement()
        nine.assertSeatGeometry(count: 9)
    }
}
