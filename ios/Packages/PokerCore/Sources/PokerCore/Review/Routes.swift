// Port of src/review/routes.js.
// Candidate routes are conditional practice plans, not solved EV rankings.

/// A hero action with its amount: the raise-to total, the call amount, or 0.
public struct CandidateAction: Equatable, Hashable, Sendable {
    public var action: PokerAction
    public var amount: Int
    public init(_ action: PokerAction, _ amount: Int = 0) {
        self.action = action
        self.amount = amount
    }
}

/// One practice route. `summary` is set on the primary route only.
public struct RouteOption: Equatable, Sendable {
    public var action: PokerAction
    public var amount: Int
    public var label: String
    public var summary: String?
    public var condition: String
    public var tradeoff: String

    public var candidate: CandidateAction { CandidateAction(action, amount) }
}

public struct Routes: Equatable, Sendable {
    public var primary: RouteOption
    public var secondary: RouteOption?
}

/// The classifier codes `analyzeDecision` assigns.
public enum ReviewCode: String, Sendable, CaseIterable {
    case freeFold = "free-fold"
    case lateOpen = "late-open"
    case lateIsolation = "late-isolation"
    case weakThreeBetDefense = "weak-threebet-defense"
    case weakFourBetDefense = "weak-fourbet-defense"
    case latePassiveEntry = "late-passive-entry"
    case squeezeCandidate = "squeeze-candidate"
    case earlySuitedEntry = "early-suited-entry"
    case weakEntry = "weak-entry"
    case deepValueShove = "deep-value-shove"
    case expensiveCall = "expensive-call"
    case premiumFold = "premium-fold"
    case premiumFlat = "premium-flat"
    case largeUnbackedBet = "large-unbacked-bet"
    case valueCheck = "value-check"
    case multiwayTopPair = "multiway-top-pair"
    case tightFold = "tight-fold"
    case pricedFold = "priced-fold"
    case multiStreetCall = "multi-street-call"
    case pricedCall = "priced-call"
    case valueBet = "value-bet"
    case drawBet = "draw-bet"
    case pressureBet = "pressure-bet"
    case boardCheck = "board-check"
    case drawCheck = "draw-check"
    case potControl = "pot-control"
}

/// Review grades.
public enum ReviewStatus: String, Sendable, CaseIterable {
    case attention, consider, sound

    var rank: Int {
        switch self {
        case .attention: return 2
        case .consider: return 1
        case .sound: return 0
        }
    }
}

/// `Math.min(maxRaiseTo, Math.max(minRaiseTo, Math.round(amount / 25) * 25))`.
func roundedRaise(_ s: ReviewDecision, _ amount: Double) -> Int {
    min(s.legal.maxRaiseTo, max(s.legal.minRaiseTo, Int(jsRound(amount / 25)) * 25))
}

private func sameAction(_ a: CandidateAction, _ b: CandidateAction) -> Bool {
    a.action == b.action && (a.action != .raise || a.amount == b.amount)
}

public func comparisonRoutes(_ s: ReviewDecision, _ ctx: DecisionContext, code: ReviewCode, status: ReviewStatus,
                             alternative: CandidateAction, pre: PreflopContext?) -> Routes {
    typealias C = ReviewCopy
    let step = s.labelStep
    func label(_ a: CandidateAction) -> String { actionLabel(step, a.action, a.amount) }
    let actual = CandidateAction(s.action, s.amount)
    var primary = RouteOption(
        action: alternative.action, amount: alternative.amount, label: label(alternative),
        summary: status == .sound && sameAction(actual, alternative) ? C.routeKeep : label(alternative),
        condition: C.routeCondition, tradeoff: C.routeTradeoff)
    func option(_ a: CandidateAction, _ condition: String, _ tradeoff: String) -> RouteOption {
        RouteOption(action: a.action, amount: a.amount, label: "", summary: nil, condition: condition, tradeoff: tradeoff)
    }
    func raise(_ amount: Double, _ condition: String, _ tradeoff: String) -> RouteOption? {
        s.legal.canRaise ? option(CandidateAction(.raise, roundedRaise(s, amount)), condition, tradeoff) : nil
    }
    let callOrCheck = CandidateAction(s.legal.canCheck ? .check : .call, s.legal.callAmount)
    var secondary: RouteOption?
    switch code {
    case .lateOpen, .lateIsolation:
        let limpers = pre?.limpers ?? 0
        primary.summary = limpers != 0 ? C.routeIsolateSummary : C.routeOpenSummary
        primary.condition = limpers != 0 ? C.routeIsolateCondition : C.routeOpenCondition
        primary.tradeoff = C.routeLateTradeoff
        let small = 100 + 50 * limpers
        secondary = raise(Double(alternative.amount > small ? small : 150 + 50 * limpers),
                          C.routeLateAltCondition, C.routeLateAltTradeoff)
    case .earlySuitedEntry:
        primary.summary = C.routeEarlySummary
        primary.condition = C.routeEarlyCondition
        primary.tradeoff = C.routeEarlyTradeoff
        secondary = raise(125, C.routeEarlyAltCondition, C.routeEarlyAltTradeoff)
    case .squeezeCandidate:
        primary.condition = C.routeSqueezeCondition
        primary.tradeoff = C.routeSqueezeTradeoff
        secondary = raise(Double(s.currentBet) * 4.5, C.routeSqueezeAltCondition, C.routeSqueezeAltTradeoff)
    case .weakThreeBetDefense, .weakFourBetDefense, .weakEntry:
        primary.condition = C.routeWeakCondition
        primary.tradeoff = C.routeWeakTradeoff
        secondary = s.legal.canCheck ? nil : option(
            CandidateAction(.call, s.legal.callAmount),
            (pre?.raises ?? 0) >= 3 ? C.routeWeakAltConditionFourBet : C.routeWeakAltCondition,
            C.routeWeakAltTradeoff)
    default:
        switch alternative.action {
        case .raise:
            primary.condition = code == .pressureBet
                ? C.routeRaisePressureCondition
                : ctx.draw.outs != 0 && ![.overpair, .set, .strong, .twoPair].contains(ctx.handClass)
                    ? C.routeRaiseDrawCondition
                    : C.routeRaiseValueCondition
            primary.tradeoff = C.routeRaiseTradeoff
            secondary = option(callOrCheck,
                               ctx.inPosition ? C.routeRaiseAltConditionInPosition : C.routeRaiseAltCondition,
                               C.routeRaiseAltTradeoff)
        case .fold:
            primary.condition = C.routeFoldCondition
            primary.tradeoff = C.routeFoldTradeoff
            secondary = !s.legal.canCheck
                ? option(CandidateAction(.call, s.legal.callAmount), C.routeFoldAltCondition, C.routeFoldAltTradeoff)
                : nil
        case .call:
            primary.condition = C.routeCallCondition
            primary.tradeoff = C.routeCallTradeoff
            secondary = option(CandidateAction(.fold, 0), C.routeCallAltCondition, C.routeCallAltTradeoff)
        case .check:
            primary.condition = ctx.inPosition ? C.routeCheckConditionInPosition : C.routeCheckCondition
            primary.tradeoff = C.routeCheckTradeoff
            if ctx.handClass != .board && s.legal.canRaise {
                secondary = raise(max(50, Double(s.pot) * (ctx.texture.wet ? 0.6 : 0.33)),
                                  ctx.draw.outs != 0 ? C.routeCheckAltDrawCondition : C.routeCheckAltCondition,
                                  C.routeCheckAltTradeoff)
            }
        }
    }
    if let second = secondary, sameAction(primary.candidate, second.candidate) { secondary = nil }
    if secondary != nil { secondary!.label = label(secondary!.candidate) }
    return Routes(primary: primary, secondary: secondary)
}
