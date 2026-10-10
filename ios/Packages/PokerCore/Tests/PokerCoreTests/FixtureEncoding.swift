import Foundation
import XCTest
@testable import PokerCore

// Encodes native domain values into the JSON shapes the shared fixtures use
// (`fixtures/README.md` → "Shared object shapes"), so a fixture value can be
// compared field by field with `jsonDiff`.

let jsonNull: Any = NSNull()

func orNull(_ v: Any?) -> Any { v ?? jsonNull }

func enc(_ c: Card) -> Any { c.key }
func enc(_ cs: [Card]) -> Any { cs.map(\.key) }

func enc(_ l: LegalActions) -> Any {
    guard l.enabled else { return ["enabled": false] as [String: Any] }
    return [
        "enabled": true, "toCall": l.toCall, "callAmount": l.callAmount, "canCheck": l.canCheck,
        "raiseReopened": l.raiseReopened, "canRaise": l.canRaise, "minRaiseTo": l.minRaiseTo,
        "fullRaiseTo": l.fullRaiseTo, "maxRaiseTo": l.maxRaiseTo, "isShortAllin": l.isShortAllin,
    ] as [String: Any]
}

func enc(_ p: Pot) -> Any {
    [
        "index": p.index, "label": p.label, "amount": p.amount, "eligible": p.eligible,
        "contributions": p.contributions.map { ["id": $0.id, "amount": $0.amount] as [String: Any] },
        "awards": p.awards.map { ["id": $0.id, "amount": $0.amount, "label": $0.label] as [String: Any] },
    ] as [String: Any]
}

func enc(_ r: Refund) -> Any { ["id": r.id, "amount": r.amount] as [String: Any] }

func enc(_ s: PotSet) -> Any { ["pots": s.pots.map(enc), "refunds": s.refunds.map(enc)] as [String: Any] }

func enc(_ w: Winner) -> Any {
    ["id": w.id, "name": w.name, "amount": w.amount, "profit": w.profit, "label": w.label] as [String: Any]
}

func enc(_ l: LogEntry) -> Any {
    ["text": l.text, "player": orNull(l.player), "type": l.type.rawValue, "street": l.street] as [String: Any]
}

func enc(_ h: HistoryEntry) -> Any {
    var o: [String: Any] = ["street": h.street, "id": h.id, "action": h.action.rawValue, "amount": h.amount]
    if let b = h.betLabel { o["betLabel"] = b }
    return o
}

func enc(_ m: BotMood) -> Any {
    [
        "kind": m.kind.rawValue, "remaining": m.remaining, "cooldown": m.cooldown, "reason": m.reason,
        "losses": m.losses, "wins": m.wins,
        "pressureFolds": Dictionary(uniqueKeysWithValues: m.pressureFolds.map { (String($0.key), $0.value as Any) }),
        "lastPressureRaiser": orNull(m.lastPressureRaiser),
    ] as [String: Any]
}

func enc(_ s: BotStats) -> Any {
    ["hands": s.hands, "vpip": s.vpip, "pfr": s.pfr, "postActions": s.postActions,
     "postRaises": s.postRaises, "postCalls": s.postCalls] as [String: Any]
}

func enc(_ h: BotHand) -> Any { ["vpip": h.vpip, "pfr": h.pfr, "pressureRecorded": h.pressureRecorded] as [String: Any] }

func enc(_ p: Player) -> Any {
    [
        "id": p.id, "name": p.name, "stack": p.stack, "bet": p.bet, "total": p.total, "folded": p.folded,
        "allin": p.allin, "actedTo": orNull(p.actedTo), "checked": p.checked, "action": p.action,
        "lastAction": p.lastAction.map { ["text": $0.text, "street": $0.street, "bet": $0.bet] as [String: Any] } ?? jsonNull,
        "hole": enc(p.hole), "botProfile": p.botProfile, "botMood": enc(p.botMood),
        "botStats": enc(p.botStats), "botHand": enc(p.botHand),
    ] as [String: Any]
}

func enc(_ d: DecisionSnapshot) -> Any {
    [
        "index": d.index, "hand": d.hand, "street": d.street, "position": d.position, "hole": enc(d.hole),
        "board": enc(d.board), "stack": d.stack, "bet": d.bet, "total": d.total, "pot": d.pot,
        "currentBet": d.currentBet, "minRaise": d.minRaise, "dealer": d.dealer, "emotionMode": d.emotionMode.rawValue,
        "legal": enc(d.legal), "pending": d.pending, "action": d.action.rawValue, "amount": d.amount,
        "players": d.players.map { p in
            [
                "id": p.id, "name": p.name, "position": p.position, "stack": p.stack, "bet": p.bet, "total": p.total,
                "folded": p.folded, "allin": p.allin, "action": p.action, "botProfile": orNull(p.botProfile),
                "publicAxes": orNull(p.publicAxes), "botMoodKind": orNull(p.botMoodKind?.rawValue),
                "actedTo": orNull(p.actedTo), "checked": p.checked,
            ] as [String: Any]
        },
        "history": d.history.map(enc),
    ] as [String: Any]
}

/// The decision view; `full` adds `hole`, `board` and `history`.
func enc(_ v: BotView, full: Bool) -> Any {
    var o: [String: Any] = [
        "id": v.id, "street": v.street, "position": v.position, "count": v.count, "inPosition": orNull(v.inPosition),
        "stack": v.stack, "bet": v.bet, "pot": v.pot, "currentBet": v.currentBet, "difficulty": v.difficulty.rawValue,
        "legal": enc(v.legal), "rivals": v.rivals,
        "equity": v.equity, "equityTrials": v.equityTrials, "contestable": v.contestable,
        "features": ["wet": v.features.wet, "draw": v.features.draw, "overpair": v.features.overpair] as [String: Any],
        "playsBoard": v.playsBoard,
    ]
    if let opponents = v.opponents {
        o["opponents"] = opponents.map { ["id": $0.id, "stack": $0.stack, "bet": $0.bet, "allin": $0.allin] as [String: Any] }
    }
    if full {
        o["hole"] = enc(v.hole)
        o["board"] = enc(v.board)
        o["history"] = v.history.map(enc)
    }
    return o
}

func enc(_ f: ThinkingFactors) -> Any {
    ["closeness": f.closeness, "texture": f.texture, "route": f.route, "position": f.position,
     "commitment": f.commitment, "sizing": f.sizing, "effectiveStack": f.effectiveStack, "spr": f.spr] as [String: Any]
}

func enc(_ t: BotThinking) -> Any {
    ["durationMs": t.durationMs, "model": t.model, "acting": t.acting.rawValue, "factors": enc(t.factors)] as [String: Any]
}

func enc(_ t: BotThinkingRecord) -> Any {
    ["durationMs": t.durationMs, "model": t.model, "acting": t.acting.rawValue, "factors": enc(t.factors),
     "expedited": t.expedited, "waitedMs": t.waitedMs] as [String: Any]
}

/// The `chooseBotAction` trace; `view` and `thinking` are added when present and requested.
func enc(_ t: BotTrace, includeView: Bool) -> Any {
    var o: [String: Any] = [
        "reason": t.reason, "profile": t.profile, "profileName": t.profileName, "mode": t.mode.rawValue,
        "mood": ["kind": t.mood.kind.rawValue, "reason": t.mood.reason] as [String: Any],
        "axes": t.axes, "baseAxes": t.baseAxes, "equityModel": t.equityModel, "trials": t.trials,
        "rawEquity": t.rawEquity, "noise": t.noise, "equity": t.equity, "odds": t.odds, "pressure": t.pressure,
        "percentile": t.percentile, "range": t.range, "openingRange": t.openingRange, "raiseRange": t.raiseRange,
        "cheapEntry": t.cheapEntry, "cheapRangePassed": t.cheapRangePassed, "affordableOpen": t.affordableOpen,
        "affordableRangePassed": t.affordableRangePassed,
        "entryContext": [
            "limpers": t.entryContext.limpers, "openCallers": t.entryContext.openCallers,
            "effectiveBehind": t.entryContext.effectiveBehind, "speculative": t.entryContext.speculative,
            "suitedHigh": t.entryContext.suitedHigh,
        ] as [String: Any],
        "premium": t.premium, "admitted": t.admitted, "callTolerance": t.callTolerance,
        "checks": t.checks.map {
            ["code": $0.code, "value": $0.value, "threshold": $0.threshold, "selected": $0.selected] as [String: Any]
        },
        "exceptions": t.exceptions,
        "sizing": t.sizing.map {
            ["fraction": $0.fraction, "desired": $0.desired, "actual": $0.actual, "minimum": $0.minimum,
             "maximum": $0.maximum, "opening": $0.opening, "executed": $0.executed] as [String: Any]
        } ?? jsonNull,
        "value": t.value, "semiBluff": t.semiBluff, "pureBluff": t.pureBluff, "draw": t.draw, "playsBoard": t.playsBoard,
    ]
    if includeView {
        if let v = t.view { o["view"] = enc(v, full: true) }
        if let th = t.thinking { o["thinking"] = enc(th) }
    }
    return o
}

func enc(_ r: BotDecisionRecord) -> Any {
    var o: [String: Any] = ["id": r.id, "name": r.name, "hand": r.hand, "sequence": r.sequence,
                            "action": r.action.rawValue, "trace": enc(r.trace, includeView: true)]
    if let a = r.amount { o["amount"] = a }
    return o
}

func enc(_ s: BotSettings) -> Any {
    ["emotionMode": s.emotionMode.rawValue,
     "assignments": Dictionary(uniqueKeysWithValues: s.assignments.map { (String($0.key), $0.value as Any) })] as [String: Any]
}

// MARK: - Deep comparison

private func isNumber(_ v: Any) -> Bool { (v is Int || v is Double) && !(v is Bool) }

private func number(_ v: Any) -> Double? {
    if v is Bool { return nil }
    if let i = v as? Int { return Double(i) }
    if let d = v as? Double { return d }
    return nil
}

private func describe(_ v: Any?) -> String {
    guard let v else { return "<absent>" }
    if v is NSNull { return "null" }
    if let s = v as? String { return "\"\(s)\"" }
    if let d = v as? Double { return "\(d)" }
    if let a = v as? [Any] { return "[" + a.map { describe($0) }.joined(separator: ", ") + "]" }
    if let o = v as? [String: Any] {
        return "{" + o.keys.sorted().map { "\($0): \(describe(o[$0]))" }.joined(separator: ", ") + "}"
    }
    return "\(v)"
}

/// Appends a line for every difference between a fixture value and a native
/// encoded value. Numbers compare by exact `Double` value (integers in either
/// form are equal); strings, booleans, `null` and key sets compare exactly.
func jsonDiff(_ expected: Any?, _ actual: Any?, _ path: String, _ out: inout [String], limit: Int = 40) {
    if out.count >= limit { return }
    switch (expected, actual) {
    case (nil, nil): return
    case (nil, _), (_, nil):
        out.append("\(path): expected \(describe(expected)), got \(describe(actual))")
    case let (e as [String: Any], a as [String: Any]):
        for key in Set(e.keys).union(a.keys).sorted() {
            jsonDiff(e[key], a[key], path + "." + key, &out, limit: limit)
        }
    case let (e as [Any], a as [Any]):
        if e.count != a.count {
            out.append("\(path): expected \(e.count) elements, got \(a.count): expected \(describe(e)), got \(describe(a))")
            return
        }
        for i in e.indices { jsonDiff(e[i], a[i], "\(path)[\(i)]", &out, limit: limit) }
    case let (e?, a?):
        if e is NSNull || a is NSNull {
            if !(e is NSNull && a is NSNull) { out.append("\(path): expected \(describe(e)), got \(describe(a))") }
        } else if let eb = e as? Bool {
            if (a as? Bool) != eb || isNumber(a) { out.append("\(path): expected \(eb), got \(describe(a))") }
        } else if let en = number(e) {
            if number(a) != en { out.append("\(path): expected \(describe(e)), got \(describe(a))") }
        } else if let es = e as? String {
            if (a as? String) != es { out.append("\(path): expected \(describe(e)), got \(describe(a))") }
        } else {
            out.append("\(path): unsupported value \(describe(e)) vs \(describe(a))")
        }
    }
}

func assertJSONEqual(_ expected: Any?, _ actual: Any?, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
    var diffs: [String] = []
    jsonDiff(expected, actual, "", &diffs)
    if !diffs.isEmpty {
        XCTFail("\(label):\n  " + diffs.joined(separator: "\n  "), file: file, line: line)
    }
}
