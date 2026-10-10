import XCTest
@testable import PokerCore

final class LabelAndMoodFixtureTests: XCTestCase {
    private func int(_ v: Any?) -> Int { fixtureInt(v) }
    private func optInt(_ v: Any?) -> Int? { v == nil || v is NSNull ? nil : fixtureInt(v) }

    private func history(_ v: Any?) -> [HistoryEntry] {
        ((v as? [[String: Any]]) ?? []).map {
            HistoryEntry(street: int($0["street"]), id: optInt($0["id"]) ?? 0,
                         action: PokerAction(rawValue: $0["action"] as! String)!,
                         amount: int($0["amount"]), betLabel: $0["betLabel"] as? String)
        }
    }

    /// Fixture amounts are integers except one synthetic `1234.5`, which the
    /// reference rounds for display; native amounts are always integers.
    private func amount(_ v: Any?) -> Int? {
        guard let v, !(v is NSNull) else { return nil }
        if let i = v as? Int { return i }
        return Int(jsRound(v as! Double))
    }

    private func step(_ v: Any?) -> LabelStep {
        let s = v as! [String: Any]
        var legal: LabelLegal? = nil
        if let l = s["legal"] as? [String: Any] {
            legal = (l["enabled"] as? Bool) == false
                ? LabelLegal()
                : LabelLegal(callAmount: optInt(l["callAmount"]), fullRaiseTo: optInt(l["fullRaiseTo"]),
                             maxRaiseTo: optInt(l["maxRaiseTo"]))
        }
        return LabelStep(street: int(s["street"]), history: history(s["history"]), currentBet: optInt(s["currentBet"]) ?? 0,
                         minRaise: optInt(s["minRaise"]), legal: legal, stack: optInt(s["stack"]),
                         action: (s["action"] as? String).flatMap(PokerAction.init(rawValue:)), amount: amount(s["amount"]))
    }

    func testActionLabelsMatchTheReference() throws {
        let fixture = try loadFixture("action-labels.json")
        let cases = fixture["cases"] as! [[String: Any]]
        XCTAssertGreaterThan(cases.count, 600)
        var passed = 0
        defer { print("action-labels.json: \(passed)/\(cases.count) cases passed") }
        for (index, c) in cases.enumerated() {
            let fn = c["fn"] as! String
            let label = "action-labels case \(index) (\(fn))"
            let failuresBefore = testRun?.failureCount ?? 0
            defer { if (testRun?.failureCount ?? 0) == failuresBefore { passed += 1 } }
            switch fn {
            case "nextBetLevel":
                XCTAssertEqual(nextBetLevel(step(c["step"])), int(c["result"]), label)
            case "raiseCaption":
                XCTAssertEqual(raiseCaption(step(c["step"]), amount(c["amount"])!), c["result"] as? String, label)
            case "actionLabel":
                let action = (c["action"] as? String).flatMap(PokerAction.init(rawValue:))
                XCTAssertEqual(actionLabel(step(c["step"]), action, amount(c["amount"])), c["result"] as? String, label)
            case "historyActionLabel":
                XCTAssertEqual(historyActionLabel(history(c["history"]), int(c["index"])), c["result"] as? String, label)
            default:
                XCTFail("Unknown fn \(fn)")
            }
        }
    }

    func testMoodSequencesMatchTheReference() throws {
        let fixture = try loadFixture("mood.json")
        let sequences = fixture["sequences"] as! [[String: Any]]
        var passed = 0
        defer { print("mood.json: \(passed)/\(sequences.count) sequences passed") }
        for sequence in sequences {
            let name = sequence["name"] as! String
            let failuresBefore = testRun?.failureCount ?? 0
            defer { if (testRun?.failureCount ?? 0) == failuresBefore { passed += 1 } }
            var mood = freshBotMood()
            for step in sequence["steps"] as! [[String: Any]] {
                let mode = (step["mode"] as? String).flatMap(EmotionMode.init(rawValue:)) ?? .subtle
                var event: MoodEvent? = nil
                switch step["op"] as! String {
                case "decay": decayBotMood(&mood)
                case "pressureFold": event = recordPressureFold(&mood, raiser: optInt(step["raiser"]), mode: mode)
                case "finish":
                    event = finishBotHand(playerId: int(step["playerId"]), mood: &mood, profit: int(step["profit"]), mode: mode)
                case "resetPressure": mood.pressureFolds[int(step["raiser"])] = 0
                case "clearPressure":
                    mood.pressureFolds = [:]
                    mood.lastPressureRaiser = nil
                case "axes":
                    let axes = effectiveBotAxes(getBotProfile(step["profile"] as? String), mood, mode)
                    XCTAssertEqual(axes, (step["result"] as! [Any]).map(fixtureDouble), name)
                default: XCTFail("Unknown op")
                }
                if step["op"] as! String != "axes" {
                    if let r = step["result"] as? [String: Any] {
                        XCTAssertEqual(event, MoodEvent(kind: MoodKind(rawValue: r["kind"] as! String)!, reason: r["reason"] as! String), name)
                    } else {
                        XCTAssertNil(event, name)
                    }
                }
                let m = step["mood"] as! [String: Any]
                XCTAssertEqual(mood.kind.rawValue, m["kind"] as? String, name)
                XCTAssertEqual([mood.remaining, mood.cooldown, mood.losses, mood.wins],
                               ["remaining", "cooldown", "losses", "wins"].map { int(m[$0]) }, name)
                XCTAssertEqual(mood.reason, m["reason"] as? String, name)
                XCTAssertEqual(mood.pressureFolds,
                               Dictionary(uniqueKeysWithValues: (m["pressureFolds"] as! [String: Any]).map { (Int($0.key)!, int($0.value)) }), name)
                XCTAssertEqual(mood.lastPressureRaiser, optInt(m["lastPressureRaiser"]), name)
            }
        }
    }
}
