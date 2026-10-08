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
}
