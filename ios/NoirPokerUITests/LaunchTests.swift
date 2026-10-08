import XCTest

final class LaunchTests: XCTestCase {
    func testOpensNativeRulesSheet() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["NOIR"].waitForExistence(timeout: 10))
        app.buttons["How to Play"].tap()
        XCTAssertTrue(app.buttons["Got It"].waitForExistence(timeout: 5))
        app.buttons["Got It"].tap()
    }
}
