// Port of src/review/opponents.js: explains an executed bot decision from the
// simulator's own record. It describes what the model did, not real player
// psychology, and never uses cards dealt after the decision.

/// `BOT_REASON_NAMES`: display names of bot trace reasons.
public var BOT_REASON_NAMES: [String: String] { ReviewCopy.botReasonNames }
/// `BOT_CHECK_NAMES`: display names of bot roll checks.
public var BOT_CHECK_NAMES: [String: String] { ReviewCopy.botCheckNames }

public struct OpponentExplanation: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var reasons: [String]
    /// The bot's made hand, or "Preflop hand".
    public var made: String
    public var warning: String
}

public func explainOpponent(_ record: BotDecisionRecord) -> OpponentExplanation {
    typealias C = ReviewCopy
    let t = record.trace
    let v = t.view ?? BotView(id: record.id, hole: [], legal: .disabled)
    let made = evaluate(v.hole + v.board)
    let draw = drawInfo(v.hole, v.board)
    let call = record.action == .call
    let raises = v.history.filter { $0.street == v.street && $0.action == .raise }
    let comparison = t.equity + t.callTolerance
    var reasons: [String] = []
    if v.street == 0 {
        reasons.append(C.opponentRange(percentile: t.percentile, range: t.range, admitted: t.admitted, premium: t.premium))
    }
    reasons.append(C.opponentPrice(rivals: v.rivals, callAmount: v.legal.callAmount, contestable: v.contestable,
                                   odds: t.odds))
    if !t.exceptions.isEmpty && t.reason != "loose-exception" { reasons.append(C.opponentExceptions(t.exceptions)) }
    if t.cheapRangePassed { reasons.append(C.opponentCheapEntry) }
    if t.affordableOpen && t.affordableRangePassed {
        reasons.append(C.opponentAffordableOpen(
            effectiveBehind: t.entryContext.effectiveBehind, openCallers: t.entryContext.openCallers,
            playable: t.entryContext.speculative || t.entryContext.suitedHigh))
    }
    reasons.append(C.opponentEquity(trials: t.trials, raw: t.rawEquity, noise: t.noise, equity: t.equity,
                                    tolerance: t.callTolerance, comparison: comparison, threshold: t.odds + 0.02))
    let detail: String
    switch t.reason {
    case "loose-exception": detail = C.opponentLoose(t.exceptions, call: call)
    case "premium-continue": detail = C.opponentPremium
    case "affordable-entry": detail = C.opponentAffordableEntry
    case "affordable-open": detail = C.opponentAffordableOpenDetail
    case "price-continue": detail = C.opponentPriceContinue
    case "value-raise":
        detail = v.street == 0
            ? C.opponentPreflopValue(reraise: !raises.isEmpty, range: t.raiseRange)
            : C.opponentPostflopValue(threshold: v.rivals == 1 ? 0.53 : 1 / Double(v.rivals + 1) + 0.23)
    case "semi-bluff": detail = C.opponentSemiBluff
    case "pure-bluff": detail = C.opponentPureBluff
    case "trap": detail = C.opponentTrap
    case "free-check": detail = C.opponentFreeCheck
    default: detail = C.opponentExecuted(t.reason)
    }
    if draw.outs != 0 { reasons.append(C.opponentDraw(draw)) }
    let moodActive = t.mode != .off && t.mood.kind != .steady
    reasons.append(moodActive
        ? C.opponentMood(t.mood.kind, reason: t.mood.reason, base: t.baseAxes, axes: t.axes)
        : C.opponentNoMood)
    if let sizing = t.sizing {
        reasons.append(sizing.executed ? C.opponentSizing(sizing) : C.opponentSizingBlocked(actual: sizing.actual, call: call))
    }
    let warn = call && (!t.exceptions.isEmpty || (!t.affordableRangePassed && comparison < t.odds + 0.02) || raises.count > 1)
    return OpponentExplanation(
        title: C.reasonName(t.reason),
        detail: detail,
        reasons: reasons,
        made: v.street != 0 ? made.label : C.opponentPreflopMade,
        warning: warn ? C.opponentWarning : C.opponentNote)
}
