import Foundation
import XCTest
@testable import PokerCore

/// Replays `fixtures/engine-scenarios.json` with the protocol in
/// `fixtures/README.md`: every step's full snapshot (rebuilt from the deltas),
/// every query result, every hero decision snapshot and bot decision record,
/// and every expected error (which must leave the game and stream unchanged).
final class EngineScenarioFixtureTests: XCTestCase {
    private func int(_ v: Any?) -> Int { fixtureInt(v) }
    private func optInt(_ v: Any?) -> Int? { v == nil || v is NSNull ? nil : fixtureInt(v) }
    private func cardList(_ v: Any?) -> [Card] { (v as! [Any]).map { Card(key: $0 as! String)! } }

    /// The README "Full snapshot".
    private func snapshot(_ g: Game, _ rng: CountingRandom) -> [String: Any] {
        [
            "hand": g.hand, "phase": g.phase.rawValue, "street": g.street, "dealer": g.dealer, "actor": g.actor,
            "pending": g.pending, "currentBet": g.currentBet, "minRaise": g.minRaise, "board": enc(g.board),
            "practiceBoard": g.practiceBoard.map(enc) ?? jsonNull, "deckSize": g.deck.count,
            "revealed": g.revealed, "showdown": g.showdown, "replayAttempt": g.replayAttempt,
            "potAtShowdown": g.potAtShowdown, "potSize": potSize(g), "difficulty": g.difficulty.rawValue,
            "emotionMode": g.emotionMode.rawValue, "canRestartHand": canRestartHand(g),
            "positions": g.players.map { seatPosition(g, $0.id) },
            "players": g.players.map(enc),
            "legal": enc(legalActions(g)),
            "currentPots": enc(currentPots(g)),
            "pots": g.pots.map(enc), "refunds": g.refunds.map(enc), "payouts": g.payouts,
            "winners": g.winners.map(enc), "result": g.result,
            "stats": ["hands": g.stats.hands, "wins": g.stats.wins, "buyin": g.stats.buyin] as [String: Any],
            "history": g.history.map(enc), "logs": g.logs.map(enc),
            "decisionCount": g.decisions.count, "botDecisionCount": g.botDecisions.count,
            "randomDraws": rng.draws,
        ]
    }

    /// Applies a README snapshot delta to the previous expected snapshot.
    private func apply(_ delta: [String: Any], to base: [String: Any]) -> [String: Any] {
        var s = base
        for (key, value) in delta {
            switch key {
            case "players":
                var players = s["players"] as! [[String: Any]]
                for partial in value as! [[String: Any]] {
                    let id = int(partial["id"])
                    let i = players.firstIndex { int($0["id"]) == id }!
                    for (k, v) in partial where k != "id" { players[i][k] = v }
                }
                s["players"] = players
            case "logsAdded":
                s["logs"] = (value as! [Any]) + (s["logs"] as! [Any])
            case "historyAdded":
                s["history"] = (s["history"] as! [Any]) + (value as! [Any])
            default:
                s[key] = value
            }
        }
        // A whole-array replacement wins over additions in the same delta.
        if let logs = delta["logs"] { s["logs"] = logs }
        if let history = delta["history"] { s["history"] = history }
        return s
    }

    private func patch(_ g: Game, _ step: [String: Any]) {
        if let game = step["game"] as? [String: Any] {
            for (key, v) in game {
                switch key {
                case "board": g.board = cardList(v)
                case "deck": g.deck = cardList(v)
                case "practiceBoard": g.practiceBoard = v is NSNull ? nil : cardList(v)
                case "stats":
                    let s = v as! [String: Any]
                    g.stats = GameStats(hands: int(s["hands"]), wins: int(s["wins"]), buyin: int(s["buyin"]))
                case "dealer": g.dealer = int(v)
                case "phase": g.phase = Phase(rawValue: v as! String)!
                case "street": g.street = int(v)
                case "currentBet": g.currentBet = int(v)
                case "minRaise": g.minRaise = int(v)
                case "pending": g.pending = (v as! [Any]).map(int)
                case "actor": g.actor = int(v)
                case "difficulty": g.difficulty = Difficulty(rawValue: v as! String)!
                default: XCTFail("Unknown patch field \(key)")
                }
            }
        }
        for p in (step["players"] as? [[String: Any]]) ?? [] {
            let i = int(p["id"])
            for (key, v) in p where key != "id" {
                switch key {
                case "hole": g.players[i].hole = cardList(v)
                case "stack": g.players[i].stack = int(v)
                case "bet": g.players[i].bet = int(v)
                case "total": g.players[i].total = int(v)
                case "folded": g.players[i].folded = v as! Bool
                case "allin": g.players[i].allin = v as! Bool
                case "actedTo": g.players[i].actedTo = optInt(v)
                default: XCTFail("Unknown player patch field \(key)")
                }
            }
        }
    }

    private enum StepOutcome {
        case none
        case newGame(Game)
    }

    /// Performs one operation. Returns comparison problems in `diffs`.
    private func perform(_ step: [String: Any], _ g: Game, _ rng: CountingRandom, _ diffs: inout [String]) throws -> StepOutcome {
        let op = step["op"] as! String
        switch op {
        case "patch":
            patch(g, step)
        case "newGame":
            return .newGame(try newGame(int(step["playerCount"])))
        case "startHand":
            if let c = step["randomConstant"] {
                try startHand(g, random: ConstantRandom(fixtureDouble(c)))
            } else {
                try startHand(g, random: rng)
            }
        case "act":
            try act(g, int(step["id"]), step["action"] as! String, optInt(step["amount"]))
        case "advanceStreet":
            try advanceStreet(g)
        case "settle":
            try settle(g, showdown: step["showdown"] as! Bool)
        case "restartHand":
            try restartHand(g)
        case "completeBoardForPractice":
            try completeBoardForPractice(g)
        case "applyBotSettings":
            try applyBotSettings(g, step["settings"])
        case "botAct":
            let actor = g.actor
            let d = try botDecision(g, random: rng)
            try act(g, actor, d.action, d.amount)
            var result: [String: Any] = ["id": actor, "action": d.action.rawValue, "reason": d.trace.reason]
            if let a = d.amount { result["amount"] = a }
            jsonDiff(step["result"], result, "result", &diffs)
        case "botTurn":
            let plan = try planBotTurn(g, random: rng, timingRandom: rng)
            try executeBotTurn(g, plan, expedited: false, waitedMs: 0)
            jsonDiff(step["result"], ["delayMs": plan.delayMs] as [String: Any], "result", &diffs)
        default:
            XCTFail("Unknown op \(op)")
        }
        return .none
    }

    private func query(_ step: [String: Any], _ g: Game) throws -> Any {
        let args = (step["args"] as? [String: Any]) ?? [:]
        switch step["fn"] as! String {
        case "partitionPots":
            return enc(try partitionPots(g))
        case "contestableAfterCall":
            return contestableAfterCall(g, int(args["id"]), int(args["amount"]))
        case "legalActions":
            return enc(legalActions(g, int(args["id"])))
        case "nextBetLevel":
            return nextBetLevel(street: g.street, history: g.history)
        case "raiseLabel":
            return actionLabel(LabelStep(street: g.street, history: g.history, currentBet: g.currentBet,
                                         minRaise: g.minRaise, legal: legalActions(g)),
                               .raise, int(args["amount"]))
        case "historyActionLabel":
            return historyActionLabel(g.history, int(args["index"]))
        case "decisionActionLabel":
            let d = g.decisions[int(args["index"])]
            let action = (args["action"] as? String).flatMap(PokerAction.init(rawValue:))
            return actionLabel(LabelStep(d), action ?? d.action, optInt(args["amount"]) ?? d.amount)
        case let fn:
            XCTFail("Unknown query \(fn)")
            return jsonNull
        }
    }

    func testEngineScenariosMatchTheReference() throws {
        let fixture = try loadFixture("engine-scenarios.json")
        let messages = fixture["errors"] as! [String: Any]
        for code in PokerError.Code.allCases {
            XCTAssertEqual(PokerError(code).message, messages[code.rawValue] as? String, "error message \(code.rawValue)")
        }
        XCTAssertEqual(Set(messages.keys), Set(PokerError.Code.allCases.map(\.rawValue)))

        let cases = fixture["cases"] as! [[String: Any]]
        XCTAssertGreaterThan(cases.count, 200)
        var passed = 0
        for c in cases {
            let name = c["name"] as! String
            if try runCase(c, name) { passed += 1 }
        }
        print("engine-scenarios.json: \(passed)/\(cases.count) cases passed")
    }

    /// Returns true when the case matched completely. Stops at the first failing step.
    private func runCase(_ c: [String: Any], _ name: String) throws -> Bool {
        let rng = CountingRandom(SeededRandom(seed: int(c["seed"])))
        let g = try newGame(int(c["playerCount"]))
        var expected = c["initial"] as! [String: Any]
        var diffs: [String] = []
        jsonDiff(expected, snapshot(g, rng), "initial", &diffs)
        if !diffs.isEmpty {
            XCTFail("\(name) initial:\n  " + diffs.joined(separator: "\n  "))
            return false
        }
        for (index, step) in (c["steps"] as! [[String: Any]]).enumerated() {
            let op = step["op"] as! String
            let label = "\(name) · step \(index) (\(op))"
            var diffs: [String] = []
            let decisionsBefore = g.decisions.count, botDecisionsBefore = g.botDecisions.count
            switch op {
            case "query":
                let result: Any
                do { result = try query(step, g) } catch {
                    XCTFail("\(label): threw \(error)")
                    return false
                }
                jsonDiff(step["result"], result, "result", &diffs)
            case "expectError":
                let inner = step["step"] as! [String: Any]
                let before = snapshot(g, rng)
                let beforeState = g.state
                let code = step["error"] as! String
                do {
                    _ = try perform(inner, g, rng, &diffs)
                    diffs.append("expected error \(code), nothing thrown")
                } catch let error as PokerError {
                    if error.code.rawValue != code { diffs.append("expected error \(code), got \(error.code.rawValue)") }
                } catch {
                    diffs.append("expected error \(code), got \(error)")
                }
                jsonDiff(before, snapshot(g, rng), "unchanged", &diffs)
                if g.state != beforeState { diffs.append("game state changed by a rejected operation") }
            default:
                do {
                    _ = try perform(step, g, rng, &diffs)
                } catch {
                    XCTFail("\(label): threw \(error)")
                    return false
                }
            }
            if let delta = step["snapshot"] as? [String: Any] {
                expected = apply(delta, to: expected)
                jsonDiff(expected, snapshot(g, rng), "snapshot", &diffs)
            }
            if let decision = step["decision"] {
                if g.decisions.count == decisionsBefore + 1 {
                    jsonDiff(decision, enc(g.decisions.last!), "decision", &diffs)
                } else {
                    diffs.append("decision: expected one appended hero decision snapshot")
                }
            }
            if let record = step["botDecision"] {
                if g.botDecisions.count == botDecisionsBefore + 1 {
                    jsonDiff(record, enc(g.botDecisions.last!), "botDecision", &diffs)
                } else {
                    diffs.append("botDecision: expected one appended bot decision record")
                }
            }
            if !diffs.isEmpty {
                XCTFail("\(label):\n  " + diffs.prefix(40).joined(separator: "\n  "))
                return false // Later steps would only repeat the divergence.
            }
        }
        return true
    }
}
