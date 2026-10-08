import XCTest
@testable import PokerCore

/// Replays `fixtures/simulations.json` (all-bot sessions generated from the
/// reference with one seeded stream) and compares every hand.
final class SimulationFixtureTests: XCTestCase {
    private func int(_ v: Any?) -> Int { fixtureInt(v) }
    private func optInt(_ v: Any?) -> Int? { v == nil || v is NSNull ? nil : int(v) }
    private func cardList(_ v: Any?) -> [Card] { (v as! [String]).map { Card(key: $0)! } }
    private func dict(_ v: Any?) -> [String: Any] { v as! [String: Any] }
    private func list(_ v: Any?) -> [[String: Any]] { v as! [[String: Any]] }

    private func history(_ v: Any?) -> [HistoryEntry] {
        list(v).map {
            HistoryEntry(street: int($0["street"]), id: int($0["id"]), action: PokerAction(rawValue: $0["action"] as! String)!,
                         amount: int($0["amount"]), betLabel: $0["betLabel"] as? String)
        }
    }

    private func pots(_ v: Any?) -> [Pot] {
        list(v).map { p in
            Pot(index: int(p["index"]), label: p["label"] as! String, amount: int(p["amount"]),
                eligible: (p["eligible"] as! [Any]).map(int),
                contributions: list(p["contributions"]).map { PotContribution(id: int($0["id"]), amount: int($0["amount"])) },
                awards: list(p["awards"]).map { PotAward(id: int($0["id"]), amount: int($0["amount"]), label: $0["label"] as! String) })
        }
    }

    private func mood(_ v: Any?) -> BotMood {
        let m = dict(v)
        var mood = BotMood()
        mood.kind = MoodKind(rawValue: m["kind"] as! String)!
        mood.remaining = int(m["remaining"])
        mood.cooldown = int(m["cooldown"])
        mood.reason = m["reason"] as! String
        mood.losses = int(m["losses"])
        mood.wins = int(m["wins"])
        mood.pressureFolds = Dictionary(uniqueKeysWithValues: dict(m["pressureFolds"]).map { (Int($0.key)!, int($0.value)) })
        mood.lastPressureRaiser = optInt(m["lastPressureRaiser"])
        return mood
    }

    private func stats(_ v: Any?) -> BotStats {
        let s = dict(v)
        var stats = BotStats()
        stats.hands = int(s["hands"])
        stats.vpip = int(s["vpip"])
        stats.pfr = int(s["pfr"])
        stats.postActions = int(s["postActions"])
        stats.postRaises = int(s["postRaises"])
        stats.postCalls = int(s["postCalls"])
        return stats
    }

    func testSimulationsMatchTheReference() throws {
        let fixture = try loadFixture("simulations.json")
        let cases = list(fixture["cases"])
        XCTAssertFalse(cases.isEmpty)
        var passed = 0
        defer { print("simulations.json: \(passed)/\(cases.count) cases passed") }
        for c in cases {
            let name = c["name"] as! String
            let failuresBefore = testRun?.failureCount ?? 0
            defer { if (testRun?.failureCount ?? 0) == failuresBefore { passed += 1 } }
            let rng = CountingRandom(SeededRandom(seed: int(c["seed"])))
            let g = try newGame(int(c["playerCount"]))
            try applyBotSettings(g, c["settings"])
            g.difficulty = Difficulty(rawValue: c["difficulty"] as! String)!
            if let stacks = c["stacks"] as? [Any] {
                for (i, s) in stacks.enumerated() { g.players[i].stack = int(s) }
            }
            for (handIndex, expected) in list(c["hands"]).enumerated() {
                let label = "\(name) hand \(handIndex + 1)"
                try startHand(g, random: rng)
                XCTAssertEqual(g.hand, int(expected["hand"]), label)
                XCTAssertEqual(g.dealer, int(expected["dealer"]), label)
                XCTAssertEqual(g.players.map(\.hole), (expected["holes"] as! [Any]).map(cardList), label)
                XCTAssertEqual(g.players.map { $0.stack + $0.total }, (expected["stacksAtDeal"] as! [Any]).map(int), label)
                XCTAssertEqual(rng.draws, int(expected["drawsAfterDeal"]), label)
                var actions: [[String: Any]] = []
                var thinking: [Int] = []
                var guardCount = 0
                while g.phase != .done {
                    guardCount += 1
                    if guardCount > 500 { XCTFail("stalled \(label)"); return }
                    if g.phase == .between {
                        try advanceStreet(g)
                    } else if g.actor == 0 {
                        let d = try botDecision(g, random: rng)
                        try act(g, 0, d.action, d.amount)
                        actions.append(["id": 0, "action": d.action.rawValue, "amount": d.amount as Any,
                                        "reason": d.trace.reason, "draws": rng.draws])
                    } else {
                        let id = g.actor
                        let plan = try planBotTurn(g, random: rng, timingRandom: rng)
                        let d = try executeBotTurn(g, plan)
                        thinking.append(plan.delayMs)
                        actions.append(["id": id, "action": d.action.rawValue, "amount": d.amount as Any,
                                        "reason": d.trace.reason, "delayMs": plan.delayMs, "draws": rng.draws])
                    }
                }
                let expectedActions = list(expected["actions"])
                XCTAssertEqual(actions.count, expectedActions.count, label)
                for (a, e) in zip(actions, expectedActions) {
                    XCTAssertEqual(a["id"] as? Int, int(e["id"]), label)
                    XCTAssertEqual(a["action"] as? String, e["action"] as? String, label)
                    XCTAssertEqual(a["amount"] as? Int, optInt(e["amount"]), label)
                    XCTAssertEqual(a["reason"] as? String, e["reason"] as? String, label)
                    XCTAssertEqual(a["delayMs"] as? Int, optInt(e["delayMs"]), label)
                    XCTAssertEqual(a["draws"] as? Int, int(e["draws"]), label)
                }
                XCTAssertEqual(g.board, cardList(expected["board"]), label)
                XCTAssertEqual(g.history, history(expected["history"]), label)
                XCTAssertEqual(g.showdown, expected["showdown"] as? Bool, label)
                XCTAssertEqual(g.pots, pots(expected["pots"]), label)
                XCTAssertEqual(g.refunds, list(expected["refunds"]).map { Refund(id: int($0["id"]), amount: int($0["amount"])) }, label)
                XCTAssertEqual(g.payouts, (expected["payouts"] as! [Any]).map(int), label)
                XCTAssertEqual(g.winners, list(expected["winners"]).map {
                    Winner(id: int($0["id"]), name: $0["name"] as! String, amount: int($0["amount"]),
                           profit: int($0["profit"]), label: $0["label"] as! String)
                }, label)
                XCTAssertEqual(g.result, expected["result"] as? String, label)
                XCTAssertEqual(g.players.map(\.stack), (expected["stacks"] as! [Any]).map(int), label)
                XCTAssertEqual(chips(g), int(expected["totalChips"]), label)
                let s = dict(expected["stats"])
                XCTAssertEqual(g.stats, GameStats(hands: int(s["hands"]), wins: int(s["wins"]), buyin: int(s["buyin"])), label)
                XCTAssertEqual(g.players.map(\.botStats), (expected["botStats"] as! [Any]).map(stats), label)
                XCTAssertEqual(g.players.map(\.botMood), (expected["moods"] as! [Any]).map(mood), label)
                XCTAssertEqual(g.decisions.count, int(expected["decisions"]), label)
                XCTAssertEqual(thinking, (expected["thinkingMs"] as! [Any]).map(int), label)
                XCTAssertEqual(g.logs, list(expected["logs"]).map {
                    LogEntry(text: $0["text"] as! String, player: optInt($0["player"]),
                             type: LogType(rawValue: $0["type"] as! String)!, street: int($0["street"]))
                }, label)
                XCTAssertEqual(rng.draws, int(expected["drawsAfterHand"]), label)
                if g.logs.map(\.text) != list(expected["logs"]).map({ $0["text"] as! String }) || actions.count != expectedActions.count {
                    break // Later hands would only repeat the first divergence.
                }
            }
        }
    }
}
