import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testOpensNativeRulesSheet() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["NOIR"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["pot-details"].waitForExistence(timeout: 10))
        app.buttons["How to Play"].tap()
        XCTAssertTrue(app.buttons["Back to Table"].waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["How to Play"].waitForExistence(timeout: 5))
    }

    /// Plays hand 1 to the end (folding when it is our turn) and deals hand 2.
    func testPlaysAHandAndDealsTheNext() {
        let app = XCUIApplication()
        app.launch()
        let handLabel = app.descendants(matching: .any)["hand-label"]
        XCTAssertTrue(handLabel.waitForExistence(timeout: 10))
        let fold = app.buttons["fold"]
        let finish = app.buttons["finish-hand"]
        let next = app.buttons["next-hand"]
        let deadline = Date().addingTimeInterval(150)
        var dealtNext = false
        while Date() < deadline {
            if next.exists && next.isHittable {
                next.tap()
                dealtNext = true
                break
            }
            if fold.exists && fold.isEnabled && fold.isHittable {
                fold.tap()
            } else if finish.exists && finish.isEnabled && finish.isHittable {
                finish.tap()
            }
            _ = next.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(dealtNext, "The first hand never reached Next Hand")
        let secondHand = NSPredicate(format: "label CONTAINS %@", "Hand 02")
        expectation(for: secondHand, evaluatedWith: handLabel)
        waitForExpectations(timeout: 10)
    }

    /// Opens Opponent Styles, applies the Mixed Lineup, saves, and checks that
    /// the surface summary reports the change for the next hand.
    func testSavesOpponentStylesForNextHand() {
        let app = XCUIApplication()
        // Start from the default all-Balanced lineup whatever an earlier run saved.
        app.launchArguments += ["-noir-opponents-v1", "{}"]
        app.launch()
        let styles = app.buttons["opponent-styles"]
        XCTAssertTrue(styles.waitForExistence(timeout: 10))
        styles.tap()
        let mixed = app.buttons["mixed-lineup"]
        XCTAssertTrue(mixed.waitForExistence(timeout: 5))
        var tries = 0
        while !mixed.isHittable && tries < 8 { app.swipeUp(); tries += 1 }
        mixed.tap()
        let save = app.buttons["save-opponents"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        tries = 0
        while !save.isHittable && tries < 12 { app.swipeUp(); tries += 1 }
        save.tap()
        XCTAssertTrue(styles.waitForExistence(timeout: 5))
        let pending = NSPredicate(format: "value == %@", "Next Hand")
        expectation(for: pending, evaluatedWith: styles)
        waitForExpectations(timeout: 5)
    }

    /// Finishes hand 1, opens Hand Review, switches between Your Decisions and
    /// Opponent Decisions, and returns to the table.
    func testReviewsAFinishedHand() {
        let app = XCUIApplication()
        app.launch()
        let fold = app.buttons["fold"]
        let finish = app.buttons["finish-hand"]
        let review = app.buttons["review-hand"]
        let deadline = Date().addingTimeInterval(150)
        while Date() < deadline && !(review.exists && review.isHittable) {
            if fold.exists && fold.isEnabled && fold.isHittable {
                fold.tap()
            } else if finish.exists && finish.isEnabled && finish.isHittable {
                finish.tap()
            }
            _ = review.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(review.exists, "The first hand never offered Review This Hand")
        review.tap()
        let opponentsTab = app.buttons["review-tab-opponents"]
        XCTAssertTrue(opponentsTab.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["review-status"].exists)
        opponentsTab.tap()
        XCTAssertTrue(app.buttons["review-opponent-filter"].waitForExistence(timeout: 5))
        app.buttons["review-tab-hero"].tap()
        app.buttons["Close Hand Review"].firstMatch.tap()
        XCTAssertTrue(app.buttons["next-hand"].waitForExistence(timeout: 5))
    }

    /// Opens the Settings sheet and the Start New Session confirmation, then
    /// dismisses both without changing anything.
    func testOpensSettingsAndResetConfirmation() {
        let app = XCUIApplication()
        app.launch()
        let settings = app.buttons["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.switches["settings-hints"].waitForExistence(timeout: 5))
        app.buttons["Close settings"].firstMatch.tap()
        let reset = app.buttons["start-new-session"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        var tries = 0
        while !reset.isHittable && tries < 10 { app.swipeUp(); tries += 1 }
        reset.tap()
        let keep = app.buttons["reset-cancel"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        keep.tap()
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
    }
}
