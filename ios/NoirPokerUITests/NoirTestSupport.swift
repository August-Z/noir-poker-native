import XCTest

/// Shared launch and table helpers for the NOIR UI tests.
///
/// Every launch uses a fixed seed (one Mulberry32 stream for the shuffle, bots
/// and thinking times), a session clock 20 times faster than real time, and
/// cleared preferences unless a test asks to keep them. The `qa-state` probe
/// exposes the public table snapshot only: no hidden cards, plans or traces.
enum Noir {
    static let defaultSeed = 20_261_008

    static func makeApp(seed: Int = defaultSeed, speed: Int = 20, resetPreferences: Bool = true,
                        extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-noir-ui-testing", "-noir-seed", "\(seed)", "-noir-speed", "\(speed)"]
        if resetPreferences { app.launchArguments.append("-noir-reset-preferences") }
        app.launchArguments += extra
        return app
    }

    @discardableResult
    static func launch(seed: Int = defaultSeed, speed: Int = 20, resetPreferences: Bool = true,
                       extra: [String] = []) -> XCUIApplication {
        let app = makeApp(seed: seed, speed: speed, resetPreferences: resetPreferences, extra: extra)
        app.launch()
        XCTAssertTrue(app.probe.waitForExistence(timeout: 15), "The UI-test probe is missing")
        return app
    }
}

extension Noir {
    /// Saves a screenshot for the CI visual check when `NOIR_SHOTS_DIR` is set
    /// (CI passes it as `TEST_RUNNER_NOIR_SHOTS_DIR`), and attaches it to the
    /// test result either way.
    static func snapshot(_ name: String, in test: XCTestCase) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["NOIR_SHOTS_DIR"], !dir.isEmpty else { return }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }
}

/// The parsed `qa-state` probe.
struct TableProbe {
    let fields: [String: String]

    init(_ text: String) {
        var parsed: [String: String] = [:]
        for part in text.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { parsed[pair[0]] = pair[1] }
        }
        fields = parsed
    }

    var hand: Int { Int(fields["hand"] ?? "") ?? -1 }
    var phase: String { fields["phase"] ?? "" }
    var players: Int { Int(fields["players"] ?? "") ?? -1 }
    var actor: String { fields["actor"] ?? "" }
    var replayAttempt: Int { Int(fields["replay"] ?? "") ?? -1 }
    var stack: Int { Int(fields["stack"] ?? "") ?? -1 }
    var wealth: Int { Int(fields["wealth"] ?? "") ?? -1 }
    var totals: [Int] { (fields["totals"] ?? "").split(separator: ",").compactMap { Int($0) } }
    var hole: String { fields["hole"] ?? "" }
    var boardCount: Int { Int(fields["board"] ?? "") ?? -1 }
    var isDone: Bool { phase == "done" }
}

extension XCUIApplication {
    var probe: XCUIElement { descendants(matching: .any)["qa-state"] }
    var state: TableProbe { TableProbe(probe.label) }

    func element(_ id: String) -> XCUIElement { descendants(matching: .any)[id] }

    var foldButton: XCUIElement { buttons["fold"] }
    var callButton: XCUIElement { buttons["call"] }
    var raiseButton: XCUIElement { buttons["raise"] }
    var finishButton: XCUIElement { buttons["finish-hand"] }
    var nextButton: XCUIElement { buttons["next-hand"] }
    var replayButton: XCUIElement { buttons["replay-hand"] }
    var reviewButton: XCUIElement { buttons["review-hand"] }

    /// The Hands Played counter in Your Practice.
    var handsPlayed: String { (element("stat-hands").value as? String) ?? "" }

    /// Waits until `condition` holds, polling the UI.
    @discardableResult
    func waitUntil(timeout: TimeInterval = 30, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return condition()
    }

    /// Scrolls until `element` can be tapped, with short drags (no fling)
    /// toward it. Drags start in the page gutter on phones, where no control
    /// sits, and beside the element on wide layouts.
    func reveal(_ element: XCUIElement, maxSteps: Int = 16) {
        var steps = 0
        while element.exists && !element.isHittable && steps < maxSteps {
            let window = windows.firstMatch.frame
            let frame = element.frame
            guard window.width > 0, window.height > 0 else { return }
            let x = window.width > 700 ? max(frame.minX - 10, 30) / window.width : 0.02
            let start = coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5))
            let towardBottom = frame.midY > window.midY
            let end = start.withOffset(CGVector(dx: 0, dy: towardBottom ? -160 : 160))
            start.press(forDuration: 0.05, thenDragTo: end)
            steps += 1
        }
    }

    func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(element) never appeared", file: file, line: line)
        reveal(element)
        element.tap()
    }

    /// Waits for the hero's first decision of the hand (Fold enabled) or for
    /// the hand to end without one. Returns true on the hero's turn.
    @discardableResult
    func waitForHeroTurn(timeout: TimeInterval = 45) -> Bool {
        waitUntil(timeout: timeout) { (foldButton.exists && foldButton.isEnabled) || state.isDone }
        return foldButton.exists && foldButton.isEnabled && !state.isDone
    }

    /// Plays the current hand to settlement. `fold` folds at the first
    /// decision and lets the opponents finish; otherwise the hero checks or
    /// calls. It never taps Finish Hand: on the fast clock the hand can settle
    /// while the button is being tapped (see `testFoldThenFinishHand`).
    func playToSettlement(fold: Bool, timeout: TimeInterval = 120, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if state.isDone && (nextButton.exists || replayButton.exists) { return }
            if fold, foldButton.exists, foldButton.isEnabled, foldButton.isHittable {
                foldButton.tap()
            } else if !fold, callButton.exists, callButton.isEnabled, callButton.isHittable {
                callButton.tap()
            } else {
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        XCTFail("The hand never settled: \(probe.label)", file: file, line: line)
    }
}
