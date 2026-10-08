import Foundation
import XCTest
@testable import PokerCore

// Decoders from the review fixture shapes (fixtures/review-*.json) to native
// review types, and encoders from native review results back to those shapes
// for `assertJSONEqual`.

private func dict(_ v: Any?) -> [String: Any] { v as? [String: Any] ?? [:] }
private func list(_ v: Any?) -> [Any] { v as? [Any] ?? [] }
private func bool(_ v: Any?) -> Bool { v as? Bool ?? false }
private func string(_ v: Any?) -> String? { v as? String }
private func optionalInt(_ v: Any?) -> Int? { (v == nil || v is NSNull) ? nil : fixtureInt(v) }

func decodeCards(_ v: Any?) -> [Card] { list(v).map { Card(key: $0 as! String)! } }

func decodeAction(_ v: Any?) -> PokerAction { PokerAction(rawValue: v as! String)! }

func decodeHistory(_ v: Any?) -> [HistoryEntry] {
    list(v).map { item in
        let o = dict(item)
        return HistoryEntry(street: fixtureInt(o["street"]), id: fixtureInt(o["id"]), action: decodeAction(o["action"]),
                            amount: optionalInt(o["amount"]) ?? 0, betLabel: string(o["betLabel"]))
    }
}

/// A fixture `legal` object. Hand-built snapshots omit `fullRaiseTo`; the label
/// functions then fall back to `currentBet == 0 ? 50 : currentBet + minRaise`, so
/// that value is supplied here (identical labels, typed field).
func decodeLegal(_ v: Any?, currentBet: Int, minRaise: Int) -> LegalActions {
    let o = dict(v)
    guard bool(o["enabled"]) else { return .disabled }
    return LegalActions(
        enabled: true, toCall: optionalInt(o["toCall"]) ?? 0, callAmount: optionalInt(o["callAmount"]) ?? 0,
        canCheck: bool(o["canCheck"]), raiseReopened: bool(o["raiseReopened"]), canRaise: bool(o["canRaise"]),
        minRaiseTo: optionalInt(o["minRaiseTo"]) ?? 0,
        fullRaiseTo: optionalInt(o["fullRaiseTo"]) ?? (currentBet == 0 ? 50 : currentBet + minRaise),
        maxRaiseTo: optionalInt(o["maxRaiseTo"]) ?? 0, isShortAllin: bool(o["isShortAllin"]))
}

/// `nil` when the snapshot carries non-integer chip amounts (two hand-built
/// reference snapshots with `pot: 75` give totals of 37.5); native chip amounts
/// are integers. With `lenient`, such amounts are rounded down instead, for the
/// checks that never read them.
func decodeDecision(_ v: Any?, lenient: Bool = false) -> ReviewDecision? {
    let o = dict(v)
    func chips(_ x: Any?) -> Int? {
        if let d = x as? Double, d != d.rounded(.down) { return lenient ? Int(d.rounded(.down)) : nil }
        return fixtureInt(x)
    }
    var players: [ReviewSeat] = []
    for item in list(o["players"]) {
        let p = dict(item)
        guard let stack = chips(p["stack"]), let bet = chips(p["bet"]), let total = chips(p["total"]) else { return nil }
        let state = p.keys.contains("actedTo")
            ? SeatState(actedTo: optionalInt(p["actedTo"]), checked: bool(p["checked"]), botProfile: string(p["botProfile"]),
                        botMoodKind: string(p["botMoodKind"]).flatMap(MoodKind.init(rawValue:)))
            : nil
        players.append(ReviewSeat(
            id: fixtureInt(p["id"]), name: string(p["name"]) ?? "", position: string(p["position"]) ?? "",
            stack: stack, bet: bet, total: total, folded: bool(p["folded"]), allin: bool(p["allin"]),
            action: string(p["action"]) ?? "", publicAxes: (p["publicAxes"] as? [Any])?.map(fixtureDouble), state: state))
    }
    guard let stack = chips(o["stack"]), let bet = chips(o["bet"]), let total = chips(o["total"]),
          let pot = chips(o["pot"]) else { return nil }
    let currentBet = fixtureInt(o["currentBet"]), minRaise = fixtureInt(o["minRaise"])
    return ReviewDecision(
        index: fixtureInt(o["index"]), hand: fixtureInt(o["hand"]), street: fixtureInt(o["street"]),
        position: string(o["position"]) ?? "", hole: decodeCards(o["hole"]), board: decodeCards(o["board"]),
        stack: stack, bet: bet, total: total, pot: pot, currentBet: currentBet, minRaise: minRaise,
        dealer: optionalInt(o["dealer"]), emotionMode: string(o["emotionMode"]).flatMap(EmotionMode.init(rawValue:)),
        legal: decodeLegal(o["legal"], currentBet: currentBet, minRaise: minRaise), pending: list(o["pending"]).map(fixtureInt),
        action: decodeAction(o["action"]), amount: fixtureInt(o["amount"]), players: players,
        history: decodeHistory(o["history"]))
}

/// A fixture `createReviewInput` object. The reference review tests build partial
/// inputs (no `hole` or `opponents`, an outcome with a few keys); absent keys
/// decode as empty values.
func decodeInput(_ v: Any?) -> ReviewInput {
    let o = dict(v)
    let out = dict(o["outcome"])
    return ReviewInput(
        hand: optionalInt(o["hand"]) ?? 0, hole: decodeCards(o["hole"]),
        decisions: list(o["decisions"]).map { decodeDecision($0)! },
        opponents: list(o["opponents"]).map(decodeRecord),
        outcome: ReviewOutcome(
            profit: optionalInt(out["profit"]) ?? 0, paid: optionalInt(out["paid"]) ?? 0,
            returned: optionalInt(out["returned"]) ?? 0,
            folded: bool(out["folded"]), wonPot: bool(out["wonPot"]), board: decodeCards(out["board"]),
            pots: list(out["pots"]).map { item in
                let p = dict(item)
                return OutcomePot(label: string(p["label"]) ?? "", amount: fixtureInt(p["amount"]),
                                  eligible: list(p["eligible"]).compactMap { $0 as? String },
                                  awards: list(p["awards"]).map { a in
                                      let w = dict(a)
                                      return OutcomeAward(name: string(w["name"]) ?? "", amount: fixtureInt(w["amount"]),
                                                          label: string(w["label"]) ?? "")
                                  })
            },
            result: string(out["result"]) ?? ""))
}

func decodeCandidate(_ v: Any?) -> CandidateAction? {
    guard let o = v as? [String: Any] else { return nil }
    return CandidateAction(decodeAction(o["action"]), optionalInt(o["amount"]) ?? 0)
}

func decodeView(_ v: Any?) -> BotView {
    let o = dict(v)
    var view = BotView(id: fixtureInt(o["id"]), hole: decodeCards(o["hole"]),
                       legal: decodeLegal(o["legal"], currentBet: optionalInt(o["currentBet"]) ?? 0, minRaise: 50))
    view.board = decodeCards(o["board"])
    view.street = optionalInt(o["street"]) ?? 0
    view.position = string(o["position"]) ?? "BTN"
    view.count = optionalInt(o["count"]) ?? 6
    view.inPosition = o["inPosition"] as? Bool
    view.stack = optionalInt(o["stack"]) ?? 0
    view.bet = optionalInt(o["bet"]) ?? 0
    view.pot = optionalInt(o["pot"]) ?? 0
    view.currentBet = optionalInt(o["currentBet"]) ?? 0
    view.difficulty = string(o["difficulty"]).flatMap(Difficulty.init(rawValue:)) ?? .normal
    view.rivals = optionalInt(o["rivals"]) ?? 1
    view.opponents = (o["opponents"] as? [Any])?.map { item in
        let p = dict(item)
        return BotOpponent(id: fixtureInt(p["id"]), stack: fixtureInt(p["stack"]), bet: fixtureInt(p["bet"]),
                           allin: bool(p["allin"]))
    }
    view.equity = o["equity"].map(fixtureDouble) ?? 0
    view.equityTrials = optionalInt(o["equityTrials"]) ?? 0
    view.contestable = optionalInt(o["contestable"]) ?? 0
    view.history = decodeHistory(o["history"])
    let f = dict(o["features"])
    view.features.wet = bool(f["wet"])
    view.features.draw = bool(f["draw"])
    view.features.overpair = bool(f["overpair"])
    view.playsBoard = bool(o["playsBoard"])
    return view
}

func decodeTrace(_ v: Any?) -> BotTrace {
    let o = dict(v)
    var t = BotTrace()
    t.reason = string(o["reason"]) ?? ""
    t.profile = string(o["profile"]) ?? "balanced"
    t.profileName = string(o["profileName"]) ?? ""
    t.mode = string(o["mode"]).flatMap(EmotionMode.init(rawValue:)) ?? .off
    let mood = dict(o["mood"])
    t.mood = TraceMood(kind: string(mood["kind"]).flatMap(MoodKind.init(rawValue:)) ?? .steady,
                       reason: string(mood["reason"]) ?? "")
    t.axes = list(o["axes"]).map(fixtureDouble)
    t.baseAxes = list(o["baseAxes"]).map(fixtureInt)
    t.equityModel = string(o["equityModel"]) ?? t.equityModel
    t.trials = optionalInt(o["trials"]) ?? 0
    func d(_ key: String) -> Double { o[key].map(fixtureDouble) ?? 0 }
    t.rawEquity = d("rawEquity")
    t.noise = d("noise")
    t.equity = d("equity")
    t.odds = d("odds")
    t.pressure = d("pressure")
    t.percentile = d("percentile")
    t.range = d("range")
    t.openingRange = d("openingRange")
    t.raiseRange = d("raiseRange")
    t.cheapEntry = bool(o["cheapEntry"])
    t.cheapRangePassed = bool(o["cheapRangePassed"])
    t.affordableOpen = bool(o["affordableOpen"])
    t.affordableRangePassed = bool(o["affordableRangePassed"])
    let e = dict(o["entryContext"])
    t.entryContext = EntryContext(limpers: optionalInt(e["limpers"]) ?? 0, openCallers: optionalInt(e["openCallers"]) ?? 0,
                                  effectiveBehind: optionalInt(e["effectiveBehind"]) ?? 0,
                                  speculative: bool(e["speculative"]), suitedHigh: bool(e["suitedHigh"]))
    t.premium = bool(o["premium"])
    t.admitted = bool(o["admitted"])
    t.callTolerance = d("callTolerance")
    t.checks = list(o["checks"]).map { item in
        let c = dict(item)
        return RollCheck(code: string(c["code"]) ?? "", value: fixtureDouble(c["value"]),
                         threshold: fixtureDouble(c["threshold"]), selected: bool(c["selected"]))
    }
    t.exceptions = list(o["exceptions"]).compactMap { $0 as? String }
    if let s = o["sizing"] as? [String: Any] {
        t.sizing = BotSizing(fraction: fixtureDouble(s["fraction"]), desired: fixtureInt(s["desired"]),
                             actual: fixtureInt(s["actual"]), minimum: fixtureInt(s["minimum"]),
                             maximum: fixtureInt(s["maximum"]), opening: bool(s["opening"]), executed: bool(s["executed"]))
    }
    t.value = bool(o["value"])
    t.semiBluff = bool(o["semiBluff"])
    t.pureBluff = bool(o["pureBluff"])
    t.draw = bool(o["draw"])
    t.playsBoard = bool(o["playsBoard"])
    if o["view"] != nil { t.view = decodeView(o["view"]) }
    return t
}

func decodeRecord(_ v: Any?) -> BotDecisionRecord {
    let o = dict(v)
    return BotDecisionRecord(id: fixtureInt(o["id"]), name: string(o["name"]) ?? "", hand: optionalInt(o["hand"]) ?? 0,
                             sequence: optionalInt(o["sequence"]) ?? 0, action: decodeAction(o["action"]),
                             amount: optionalInt(o["amount"]), trace: decodeTrace(o["trace"]))
}

// MARK: - Encoders

func enc(_ a: CandidateAction) -> Any { ["action": a.action.rawValue, "amount": a.amount] as [String: Any] }

func enc(_ d: DrawInfo) -> Any {
    ["flush": d.flush, "straight": d.straight, "flushOuts": d.flushOuts, "straightOuts": d.straightOuts,
     "outs": d.outs, "nextChance": d.nextChance] as [String: Any]
}

func enc(_ t: BoardTexture) -> Any {
    ["paired": t.paired, "trips": t.trips, "maxSuit": t.maxSuit, "connected": t.connected, "wet": t.wet,
     "label": t.label] as [String: Any]
}

func enc(_ c: DecisionContext) -> Any {
    var o: [String: Any] = [
        "made": ["score": c.made.score, "label": c.made.label, "cards": enc(c.made.cards)] as [String: Any],
        "texture": enc(c.texture), "draw": enc(c.draw), "opponents": c.opponents, "handClass": c.handClass.rawValue,
        "handLabel": c.handLabel.label, "inPosition": c.inPosition, "pendingOthers": c.pendingOthers,
        "effective": c.effective, "spr": c.spr, "extra": c.extra, "betRatio": c.betRatio,
        "preflopRaises": c.preflopRaises, "pastCalls": c.pastCalls, "pastCallActions": c.pastCallActions,
        "nutFlushBlocker": c.nutFlushBlocker, "missedDraw": c.missedDraw, "tier": c.tier,
    ]
    if let f = c.facingRaise { o["facingRaise"] = enc(f) }
    return o
}

func enc(_ p: PreflopContext) -> Any {
    var o: [String: Any] = [
        "raises": p.raises, "limpers": p.limpers, "callersAfterOpen": p.callersAfterOpen, "late": p.late,
        "unopened": p.unopened, "ace": p.ace, "kicker": p.kicker, "suited": p.suited, "weakAce": p.weakAce,
        "ownOpen": p.ownOpen, "openTo": p.openTo, "ratio": p.ratio, "openingCandidate": p.openingCandidate,
        "label": p.label,
    ]
    if let r = p.lastRaiser { o["lastRaiser"] = r }
    return o
}

func enc(_ p: CallPrice) -> Any {
    ["pots": p.pots.map(enc), "contestable": p.contestable, "cost": p.cost, "refundBefore": p.refundBefore,
     "refundAfter": p.refundAfter, "required": p.required, "closing": p.closing] as [String: Any]
}

func enc(_ e: EquityEstimate) -> Any {
    var o: [String: Any] = ["equity": e.equity, "margin": e.margin, "ev": e.ev]
    if let m = e.method { o["method"] = m.rawValue }
    if let s = e.samples { o["samples"] = s }
    return o
}

func enc(_ r: RouteOption) -> Any {
    var o: [String: Any] = ["action": r.action.rawValue, "amount": r.amount, "label": r.label,
                            "condition": r.condition, "tradeoff": r.tradeoff]
    if let s = r.summary { o["summary"] = s }
    return o
}

func enc(_ r: Routes) -> Any { ["primary": enc(r.primary), "secondary": r.secondary.map(enc) ?? jsonNull] as [String: Any] }

/// The reference leaves `routes.secondary` undefined (absent in JSON) on one
/// branch and `null` on others; both mean "no secondary route". Drops a null
/// `secondary` so the two compare equal.
func normalizeRoutes(_ v: Any?) -> Any? {
    if let o = v as? [String: Any] {
        var out: [String: Any] = [:]
        for (k, x) in o where !(k == "secondary" && x is NSNull) { out[k] = normalizeRoutes(x) }
        return out
    }
    if let a = v as? [Any] { return a.map { normalizeRoutes($0) ?? jsonNull } }
    return v
}

func assertReviewJSON(_ expected: Any?, _ actual: Any?, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
    assertJSONEqual(normalizeRoutes(expected), normalizeRoutes(actual), label, file: file, line: line)
}

func enc(_ r: CounterfactualResult) -> Any {
    [
        "rows": r.rows.map { row in
            ["action": enc(row.action),
             "scenarios": row.scenarios.map {
                 ["name": $0.name, "ev": $0.ev, "margin": $0.margin, "immediateFoldWin": $0.immediateFoldWin] as [String: Any]
             }] as [String: Any]
        },
        "trials": r.trials, "policyTrials": r.policyTrials, "best": enc(r.best), "stable": r.stable,
        "method": r.method, "note": r.note,
    ] as [String: Any]
}

func enc(_ m: ReviewMetrics) -> Any {
    ["required": m.required, "equityLow": m.equityLow, "equityHigh": m.equityHigh, "randomEquity": m.randomEquity,
     "weightedEquity": m.weightedEquity, "uncertainty": m.uncertainty, "callCost": m.callCost,
     "contestable": m.contestable, "closing": m.closing, "sidePots": m.sidePots, "trials": m.trials,
     "method": m.method.rawValue, "randomEV": m.randomEV, "weightedEV": m.weightedEV] as [String: Any]
}

func enc(_ a: DecisionAnalysis) -> Any {
    [
        "index": a.index, "status": a.status.rawValue, "code": a.code.rawValue, "title": a.title, "reason": a.reason,
        "lesson": a.lesson, "plan": a.plan, "confidence": a.confidence, "evidence": a.evidence,
        "alternative": enc(a.alternative), "alternativeLabel": a.alternativeLabel, "routes": enc(a.routes),
        "recommendation": a.recommendation, "simulation": a.simulation.map(enc) ?? jsonNull,
        "metrics": enc(a.metrics), "draw": enc(a.draw), "context": enc(a.context),
    ] as [String: Any]
}

func enc(_ s: ReviewSummary, steps: Bool) -> Any {
    var o: [String: Any] = ["priorityIndex": s.priorityIndex, "attention": s.attention, "consider": s.consider,
                            "themes": s.themes, "title": s.title, "summary": s.summary]
    if steps { o["steps"] = s.steps.map(enc) }
    return o
}

func enc(_ e: OpponentExplanation) -> Any {
    ["title": e.title, "detail": e.detail, "reasons": e.reasons, "made": e.made, "warning": e.warning] as [String: Any]
}
