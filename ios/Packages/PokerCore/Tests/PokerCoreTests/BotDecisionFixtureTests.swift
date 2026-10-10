import XCTest
@testable import PokerCore

/// Compares `botDecision` and `botThinkingTime` with `fixtures/bot-decisions.json`
/// field by field, including every double in the trace.
final class BotDecisionFixtureTests: XCTestCase {
    private func int(_ v: Any?) -> Int { fixtureInt(v) }
    private func optInt(_ v: Any?) -> Int? { v == nil || v is NSNull ? nil : fixtureInt(v) }
    private func dbl(_ v: Any?) -> Double { fixtureDouble(v) }
    private func dict(_ v: Any?) -> [String: Any] { v as! [String: Any] }
    private func keys(_ v: Any?) -> [Card] { (v as! [String]).map { Card(key: $0)! } }

    private func game(_ state: [String: Any]) throws -> Game {
        let players = state["players"] as! [[String: Any]]
        let g = try newGame(players.count)
        g.hand = int(state["hand"])
        g.phase = Phase(rawValue: state["phase"] as! String)!
        g.street = int(state["street"])
        g.dealer = int(state["dealer"])
        g.actor = int(state["actor"])
        g.pending = (state["pending"] as! [Any]).map(int)
        g.currentBet = int(state["currentBet"])
        g.minRaise = int(state["minRaise"])
        g.board = keys(state["board"])
        g.difficulty = Difficulty(rawValue: state["difficulty"] as! String)!
        g.emotionMode = EmotionMode(rawValue: state["emotionMode"] as! String)!
        g.replayAttempt = int(state["replayAttempt"])
        g.history = (state["history"] as! [[String: Any]]).map {
            HistoryEntry(street: int($0["street"]), id: int($0["id"]), action: PokerAction(rawValue: $0["action"] as! String)!,
                         amount: int($0["amount"]), betLabel: $0["betLabel"] as? String)
        }
        for (i, p) in players.enumerated() {
            g.players[i].name = p["name"] as! String
            g.players[i].stack = int(p["stack"])
            g.players[i].bet = int(p["bet"])
            g.players[i].total = int(p["total"])
            g.players[i].folded = p["folded"] as! Bool
            g.players[i].allin = p["allin"] as! Bool
            g.players[i].actedTo = optInt(p["actedTo"])
            g.players[i].checked = p["checked"] as! Bool
            g.players[i].action = p["action"] as! String
            g.players[i].hole = keys(p["hole"])
            g.players[i].botProfile = p["botProfile"] as! String
            let m = dict(p["botMood"])
            var mood = BotMood()
            mood.kind = MoodKind(rawValue: m["kind"] as! String)!
            mood.remaining = int(m["remaining"])
            mood.cooldown = int(m["cooldown"])
            mood.reason = m["reason"] as! String
            mood.losses = int(m["losses"])
            mood.wins = int(m["wins"])
            mood.pressureFolds = Dictionary(uniqueKeysWithValues: dict(m["pressureFolds"]).map { (Int($0.key)!, int($0.value)) })
            mood.lastPressureRaiser = optInt(m["lastPressureRaiser"])
            g.players[i].botMood = mood
        }
        return g
    }

    private func legal(_ v: Any?) -> LegalActions {
        let l = dict(v)
        guard l["enabled"] as! Bool else { return .disabled }
        return LegalActions(enabled: true, toCall: int(l["toCall"]), callAmount: int(l["callAmount"]),
                            canCheck: l["canCheck"] as! Bool, raiseReopened: l["raiseReopened"] as! Bool,
                            canRaise: l["canRaise"] as! Bool, minRaiseTo: int(l["minRaiseTo"]),
                            fullRaiseTo: int(l["fullRaiseTo"]), maxRaiseTo: int(l["maxRaiseTo"]),
                            isShortAllin: l["isShortAllin"] as! Bool)
    }

    func testBotDecisionsMatchTheReference() throws {
        let fixture = try loadFixture("bot-decisions.json")
        let cases = fixture["cases"] as! [[String: Any]]
        XCTAssertGreaterThan(cases.count, 100)
        var passed = 0
        for c in cases {
            let name = c["name"] as! String
            let g = try game(dict(c["state"]))
            let random = CountingRandom(SeededRandom(seed: int(c["decisionSeed"])))
            let d = try botDecision(g, random: random, trials: optInt(c["trials"]))
            var diffs: [String] = []
            var decision: [String: Any] = ["action": d.action.rawValue]
            if let a = d.amount { decision["amount"] = a }
            jsonDiff(c["decision"], decision, "decision", &diffs)
            jsonDiff(c["decisionDraws"], random.draws, "decisionDraws", &diffs)
            jsonDiff(c["trace"], enc(d.trace, includeView: false), "trace", &diffs)
            if let v = d.trace.view {
                jsonDiff(c["view"], enc(v, full: false), "view", &diffs)
                // The view's hole, board and history are the state's.
                let state = dict(c["state"]), actor = int(state["actor"])
                let players = state["players"] as! [[String: Any]]
                let hole = players.first { int($0["id"]) == actor }!["hole"]
                jsonDiff(hole, enc(v.hole), "view.hole", &diffs)
                jsonDiff(state["board"], enc(v.board), "view.board", &diffs)
                jsonDiff(state["history"], v.history.map(enc), "view.history", &diffs)
            } else {
                diffs.append("view: missing")
            }
            let timing = CountingRandom(SeededRandom(seed: int(c["timingSeed"])))
            let thinking = botThinkingTime(d, random: timing)
            jsonDiff(c["thinking"], enc(thinking), "thinking", &diffs)
            jsonDiff(c["timingDraws"], timing.draws, "timingDraws", &diffs)
            if !diffs.isEmpty { XCTFail("\(name):\n  " + diffs.joined(separator: "\n  ")) } else { passed += 1 }
        }
        print("bot-decisions.json: \(passed)/\(cases.count) cases passed")
        for e in fixture["errors"] as! [[String: Any]] {
            let g = try game(dict(e["state"]))
            assertThrowsPoker(PokerError.Code(rawValue: e["error"] as! String)!) {
                _ = try botDecision(g, random: SeededRandom(1), trials: optInt(e["trials"]))
            }
        }
    }
}
