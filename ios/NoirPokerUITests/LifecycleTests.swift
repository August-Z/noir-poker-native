import XCTest

/// Background, foreground and rotation on the phone, read through the
/// `qa-lifecycle` probe (debug UI-test launches only). The probe repeats the
/// public `qa-state` fields and adds what the app recorded when the scene left
/// and returned: the thinking bot (`seat:delayMs`), the count of bot actions,
/// whether the public table changed, and the review job (`status:jobId`).
/// Those moments are recorded in the app because the test can read the app
/// again only once it is active, when a resumed bot may already have acted.
///
/// `.inactive` alone does not pause the table: it covers moments when the table
/// stays on screen (Control Center, Notification Center, a system alert, the
/// app switcher before another app is chosen), like a visible browser tab in
/// the reference. Every real departure reaches `.background`, which these tests
/// exercise with the Home button. XCUITest has no reliable way to hold the
/// scene in `.inactive`, so that choice is documented here and in
/// `NoirPokerApp.swift` rather than tested.
///
/// A Finish Hand fast-forward is cancelled by the background and must be
/// tapped again (see docs/SESSION.md); a thinking bot keeps its plan.
final class LifecycleTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// Plays on (calling at the hero's turns, dealing the next hand after a
    /// settlement) until an opponent is thinking. Real time: thinking takes
    /// 1.2–8 s, long enough to leave the app before the bot acts.
    @discardableResult
    private func waitForThinkingBot(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> TableProbe {
        let found = app.waitUntil(timeout: 90) {
            let probe = app.lifecycle
            if probe.think != "-" { return true }
            if probe.isDone, app.nextButton.exists, app.nextButton.isHittable {
                app.nextButton.tap()
            } else if !probe.isDone, app.callButton.exists, app.callButton.isEnabled, app.callButton.isHittable {
                app.callButton.tap()
            }
            return false
        }
        XCTAssertTrue(found, "No opponent started thinking: \(app.lifecycleProbe.label)", file: file, line: line)
        return app.lifecycle
    }

    /// Leaves with Home, stays away for `seconds`, and returns. Pass
    /// `underSheet` when a sheet covers the table (and its probe): the return
    /// is then checked once the sheet is closed.
    private func background(_ app: XCUIApplication, for seconds: TimeInterval, underSheet: Bool = false,
                            file: StaticString = #filePath, line: UInt = #line) {
        let returns = underSheet ? -1 : app.lifecycle.foregrounds
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: seconds)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "The app did not return", file: file, line: line)
        guard !underSheet else { return }
        XCTAssertTrue(app.lifecycleProbe.waitForExistence(timeout: 15), "The lifecycle probe is missing", file: file, line: line)
        XCTAssertTrue(app.waitUntil(timeout: 10) { app.lifecycle.foregrounds == returns + 1 },
                      "The app never returned to the foreground: \(app.lifecycleProbe.label)", file: file, line: line)
    }

    /// Home while a bot is thinking: no bot acts and the table does not change
    /// while away, and on return the same plan (seat and thinking time, no new
    /// random draws) resumes and runs exactly once.
    func testBackgroundWhileABotThinksResumesTheSamePlan() {
        let app = Noir.launch(speed: 1)
        XCTAssertTrue(app.lifecycleProbe.waitForExistence(timeout: 10))

        // The bot may act just before Home lands; then try with the next one.
        var leftDuringThinking: TableProbe?
        for _ in 0..<5 {
            let thinking = waitForThinkingBot(app)
            XCTAssertEqual(thinking.backgrounds, thinking.foregrounds)
            // Away longer than most thinking times.
            background(app, for: 4)
            let probe = app.lifecycle
            if probe.planBg != "-" {
                leftDuringThinking = probe
                break
            }
        }
        guard let away = leftDuringThinking else {
            XCTFail("Home never landed while a bot was thinking: \(app.lifecycleProbe.label)")
            return
        }
        XCTAssertEqual(away.actsAway, 0, "A bot acted in the background: \(away.fields)")
        XCTAssertTrue(away.tableKept, "The public table changed in the background: \(away.fields)")
        XCTAssertEqual(away.planFg, away.planBg, "The thinking bot keeps its plan across the background")

        XCTAssertTrue(app.waitUntil(timeout: 20) { app.lifecycle.firstAfterBg != "-" },
                      "The resumed bot never acted: \(app.lifecycleProbe.label)")
        let after = app.lifecycle
        XCTAssertEqual(after.firstAfterBg, away.planBg, "The kept plan is the one that runs")
        XCTAssertEqual(after.hand, away.hand)
        XCTAssertTrue(after.sequencesAreUnique, "A bot action was recorded twice: \(after.fields)")
        XCTAssertEqual(after.wealth, 30_000, "Chips were created or lost: \(app.lifecycleProbe.label)")
        XCTAssertEqual(after.backgroundedFlag, 0)
    }

    /// Home while Hand Review is analyzing: the job is cancelled (no result
    /// arrives while away), the sheet stays open, and the analysis restarts
    /// and finishes on return. If the analysis finished before Home, the
    /// finished review survives the round trip unchanged.
    func testBackgroundDuringReviewRestartsTheAnalysis() {
        let app = Noir.launch()
        app.playToSettlement(fold: false)
        let settled = app.lifecycle
        app.tap(app.reviewButton, until: app.element("review-status"))

        background(app, for: 3, underSheet: true)
        XCTAssertTrue(app.element("review-status").waitForExistence(timeout: 10), "The review sheet closed in the background")
        XCTAssertTrue(app.waitUntil(timeout: 120) { app.element("review-priority").exists || app.element("review-retry").exists },
                      "The review never finished after the return")
        XCTAssertTrue(app.element("review-priority").exists, "The analysis failed after the return")

        app.buttons["Close Hand Review"].firstMatch.tap()
        XCTAssertTrue(app.nextButton.waitForExistence(timeout: 10))
        XCTAssertTrue(app.lifecycleProbe.waitForExistence(timeout: 5))
        let probe = app.lifecycle
        XCTAssertEqual(probe.backgrounds, 1)
        XCTAssertEqual(probe.foregrounds, 1)
        let atBackground = probe.reviewBg, whileAway = probe.reviewAway, final = probe.review
        XCTAssertEqual(final.status, "done", probe.fields.description)
        switch atBackground.status {
        case "running":
            XCTAssertEqual(whileAway.status, "idle", "The running job is cancelled in the background: \(probe.fields)")
            XCTAssertGreaterThan(whileAway.job, atBackground.job, "The cancelled job's late result is dropped")
            XCTAssertGreaterThan(final.job, whileAway.job, "The analysis restarts with a new job on return")
        case "done":
            XCTAssertEqual(whileAway.status, "done", "A finished review survives the background")
            XCTAssertEqual(final.job, atBackground.job)
        default:
            XCTFail("Unexpected review status when leaving: \(probe.fields)")
        }
        XCTAssertTrue(probe.tableKept)
        XCTAssertEqual(probe.totals, settled.totals, "The settled stacks are unchanged")
        XCTAssertEqual(probe.hand, settled.hand)
        XCTAssertEqual(probe.wealth, 30_000)
    }

    /// Rotating the iPhone while a bot thinks and a sheet is open keeps the
    /// hand, the stacks, the bot's plan and the sheet, and never backgrounds
    /// the table.
    func testRotationKeepsTheTableThePlanAndTheOpenSheet() {
        let app = Noir.launch(speed: 1)
        XCTAssertTrue(app.lifecycleProbe.waitForExistence(timeout: 10))
        let before = waitForThinkingBot(app)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.waitUntil(timeout: 10) { app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height },
                      "The app did not rotate to landscape")
        let rotated = app.lifecycle
        XCTAssertEqual(rotated.backgrounds, 0, "Rotation never backgrounds the table")
        XCTAssertEqual(rotated.hand, before.hand)
        XCTAssertEqual(rotated.hole, before.hole, "The hero keeps the same hole cards")
        XCTAssertEqual(rotated.wealth, 30_000)
        XCTAssertTrue(rotated.sequencesAreUnique, "A bot action was recorded twice: \(rotated.fields)")
        if rotated.records == before.records {
            // Nobody acted during the rotation: the same bot is still thinking
            // with the same plan, and the table is unchanged.
            XCTAssertEqual(rotated.think, before.think, "The thinking bot keeps its plan")
            XCTAssertEqual(rotated.totals, before.totals)
            XCTAssertEqual(rotated.actor, before.actor)
            XCTAssertEqual(rotated.boardCount, before.boardCount)
        } else {
            // The thinking bot acted during the rotation: its plan ran once.
            XCTAssertGreaterThan(rotated.records, before.records)
            XCTAssertTrue(rotated.recordList[before.records].hasPrefix(before.think + ":"),
                          "The kept plan is the one that ran: \(rotated.fields)")
        }

        // An open sheet survives rotating back.
        app.tapWhenReady(app.buttons["settings"])
        XCTAssertTrue(app.switches["settings-hints"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.waitUntil(timeout: 10) { app.windows.firstMatch.frame.height > app.windows.firstMatch.frame.width },
                      "The app did not rotate back to portrait")
        XCTAssertTrue(app.switches["settings-hints"].waitForExistence(timeout: 5), "The Settings sheet closed on rotation")
        app.buttons["Close settings"].firstMatch.tap()
        XCTAssertTrue(app.lifecycleProbe.waitForExistence(timeout: 5))
        let back = app.lifecycle
        XCTAssertEqual(back.backgrounds, 0)
        XCTAssertEqual(back.hand, before.hand)
        XCTAssertEqual(back.wealth, 30_000, "Chips were created or lost: \(app.lifecycleProbe.label)")
        XCTAssertTrue(back.sequencesAreUnique)
    }
}

private extension XCUIApplication {
    var lifecycleProbe: XCUIElement { descendants(matching: .any)["qa-lifecycle"] }
    var lifecycle: TableProbe { TableProbe(lifecycleProbe.label) }
}

/// A review job as `status:jobId`.
private struct ReviewJobField {
    let status: String
    let job: Int

    init(_ raw: String) {
        let parts = raw.split(separator: ":").map(String.init)
        status = parts.first ?? ""
        job = parts.count > 1 ? Int(parts[1]) ?? -1 : -1
    }
}

/// The lifecycle fields of the `qa-lifecycle` probe.
private extension TableProbe {
    var backgroundedFlag: Int { Int(fields["backgrounded"] ?? "") ?? -1 }
    var backgrounds: Int { Int(fields["backgrounds"] ?? "") ?? -1 }
    var foregrounds: Int { Int(fields["foregrounds"] ?? "") ?? -1 }
    var think: String { fields["think"] ?? "-" }
    var records: Int { Int(fields["records"] ?? "") ?? -1 }
    /// `seat:delayMs:sequence` per bot action of this hand.
    var recordList: [String] { (fields["recordList"] ?? "").split(separator: ",").map(String.init) }
    var sequencesAreUnique: Bool {
        let sequences = recordList.compactMap { $0.split(separator: ":").last.map(String.init) }
        return Set(sequences).count == sequences.count
    }
    var planBg: String { fields["planBg"] ?? "-" }
    var planFg: String { fields["planFg"] ?? "-" }
    var firstAfterBg: String { fields["firstAfterBg"] ?? "-" }
    var actsAway: Int { Int(fields["actsAway"] ?? "") ?? -1 }
    var tableKept: Bool { fields["tableKept"] == "1" }
    var review: ReviewJobField { ReviewJobField(fields["review"] ?? "") }
    var reviewBg: ReviewJobField { ReviewJobField(fields["reviewBg"] ?? "") }
    var reviewAway: ReviewJobField { ReviewJobField(fields["reviewAway"] ?? "") }
}
