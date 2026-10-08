import Foundation
import XCTest
@testable import PokerCore

/// `fixtures/bot-profiles.json` and `fixtures/hand-ranks.json`.
final class ProfileFixtureTests: XCTestCase {
    private func enc(_ p: BotProfile) -> Any {
        [
            "id": p.id, "name": p.name, "short": p.short, "tag": p.tag, "description": p.description,
            "axes": p.axes, "sizing": p.sizing, "evidence": p.evidence,
            "sources": p.sources.map { ["label": $0.label, "url": $0.url] as [String: Any] },
        ] as [String: Any]
    }

    func testBotProfilesMatchTheReference() throws {
        let f = try loadFixture("bot-profiles.json")
        assertJSONEqual(f["profiles"], BOT_PROFILES.map(enc), "profiles")
        assertJSONEqual(f["axes"], PROFILE_AXES, "axes")
        assertJSONEqual(f["emotionModes"], EmotionMode.allCases.map { ["id": $0.rawValue, "label": $0.label] as [String: Any] },
                        "emotionModes")
        assertJSONEqual(f["moodLabels"], MoodKind.allCases.map { ["kind": $0.rawValue, "label": moodLabel($0)] as [String: Any] },
                        "moodLabels")
        assertJSONEqual(f["defaultBotSettings"], PokerCoreTests.enc(defaultBotSettings()), "defaultBotSettings")
        assertJSONEqual(f["freshBotMood"], PokerCoreTests.enc(freshBotMood()), "freshBotMood")
        assertJSONEqual(f["freshBotStats"], PokerCoreTests.enc(freshBotStats()), "freshBotStats")
        assertJSONEqual(f["botThinkLimits"], ["minimum": BOT_THINK_LIMITS.minimum, "maximum": BOT_THINK_LIMITS.maximum] as [String: Any],
                        "botThinkLimits")

        let sanitize = f["sanitizeBotSettings"] as! [[String: Any]]
        var passed = 0
        for (i, c) in sanitize.enumerated() {
            let input = c["input"]
            var diffs: [String] = []
            jsonDiff(c["output"], PokerCoreTests.enc(sanitizeBotSettings(input is NSNull ? nil : input)), "output", &diffs)
            if diffs.isEmpty { passed += 1 } else { XCTFail("sanitizeBotSettings[\(i)]:\n  " + diffs.joined(separator: "\n  ")) }
        }
        print("bot-profiles.json sanitizeBotSettings: \(passed)/\(sanitize.count) cases passed")

        let percentiles = f["startingPercentile"] as! [[String: Any]]
        XCTAssertEqual(percentiles.count, 169)
        passed = 0
        for c in percentiles {
            let hole = (c["hole"] as! [String]).map { Card(key: $0)! }
            let value = startingPercentile(hole)
            if value == fixtureDouble(c["percentile"]) { passed += 1 } else {
                XCTFail("startingPercentile \(c["hand"]!): expected \(fixtureDouble(c["percentile"])), got \(value)")
            }
        }
        print("bot-profiles.json startingPercentile: \(passed)/\(percentiles.count) cases passed")
    }

    func testLegacyHandRanksMatchTheReference() throws {
        let f = try loadFixture("hand-ranks.json")
        let cases = f["cases"] as! [[String: Any]]
        XCTAssertFalse(cases.isEmpty)
        var passed = 0
        for c in cases {
            let name = c["name"] as! String
            let input = (c["cards"] as! [[String: Any]]).map { Card(rank: fixtureInt($0["rank"]), suit: fixtureInt($0["suit"])) }
            let result = evaluate(input)
            var diffs: [String] = []
            jsonDiff(c["score"], result.score, "score", &diffs)
            jsonDiff(c["bestCardKeys"], result.cards.map(\.key), "bestCardKeys", &diffs)
            if diffs.isEmpty { passed += 1 } else { XCTFail("\(name):\n  " + diffs.joined(separator: "\n  ")) }
        }
        print("hand-ranks.json: \(passed)/\(cases.count) cases passed")
    }

    /// The fixture comparator itself must not be vacuous.
    func testJSONDiffReportsEveryKindOfDifference() {
        func diffs(_ e: Any?, _ a: Any?) -> Int {
            var out: [String] = []
            jsonDiff(e, a, "", &out)
            return out.count
        }
        XCTAssertEqual(diffs(["a": 1, "b": "x"] as [String: Any], ["a": 1, "b": "x"] as [String: Any]), 0)
        XCTAssertEqual(diffs(1, 1.0), 0)
        XCTAssertEqual(diffs(0.1, 0.1), 0)
        XCTAssertEqual(diffs(0.1, 0.30000000000000004 - 0.2), 1)
        XCTAssertEqual(diffs(1, 2), 1)
        XCTAssertEqual(diffs("Call 1,000", "Call 1000"), 1)
        XCTAssertEqual(diffs(true, 1), 1)
        XCTAssertEqual(diffs(false, true), 1)
        XCTAssertEqual(diffs(jsonNull, 0), 1)
        XCTAssertEqual(diffs(0, jsonNull), 1)
        XCTAssertEqual(diffs(["a": 1] as [String: Any], ["a": 1, "b": 2] as [String: Any]), 1)
        XCTAssertEqual(diffs(["a": 1, "b": jsonNull] as [String: Any], ["a": 1] as [String: Any]), 1)
        XCTAssertEqual(diffs([1, 2], [1, 2, 3]), 1)
        XCTAssertEqual(diffs([1, 2], [2, 1]), 2)
        XCTAssertEqual(diffs([["x": [1]]] as [Any], [["x": [2]]] as [Any]), 1)
    }
}
