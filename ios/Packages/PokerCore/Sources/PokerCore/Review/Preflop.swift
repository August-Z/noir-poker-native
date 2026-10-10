// Port of src/review/preflop.js: the preflop betting situation before a hero decision.

/// The preflop situation label.
public enum PreflopSituation: String, Sendable, CaseIterable {
    case limped, unopened, openWithCallers, facingOpen, facingThreeBet, facingFourBetPlus

    /// Lower-case catalog phrase, used mid-sentence.
    public var phrase: String { ReviewCopy.preflopSituation(self) }
    /// Standalone form (the reference `label`).
    public var label: String { ReviewFormat.cap(phrase) }
}

public struct PreflopContext: Equatable, Sendable {
    /// Raises above the big blind.
    public var raises: Int
    public var limpers: Int
    public var callersAfterOpen: Int
    public var late: Bool
    public var unopened: Bool
    public var ace: Bool
    public var kicker: Int
    public var suited: Bool
    public var weakAce: Bool
    public var ownOpen: Bool
    /// Seat of the latest raiser; `nil` without a raise.
    public var lastRaiser: Int?
    public var openTo: Int
    public var ratio: Double
    public var openingCandidate: Bool
    public var situation: PreflopSituation

    public var label: String { situation.label }
}

public func preflopContext(_ s: ReviewDecision) -> PreflopContext {
    let history = s.history.filter { $0.street == 0 }
    let raiseIndices = history.indices.filter { history[$0].action == .raise && history[$0].amount > 50 }
    let raises = raiseIndices.map { history[$0] }
    let firstRaise = raiseIndices.first
    let beforeOpen = history[..<(firstRaise ?? history.count)]
    let limpers = Set(beforeOpen.filter { $0.action == .call && $0.id != 0 }.map(\.id)).count
    let open = raises.first, last = raises.last
    var callersAfterOpen = 0
    if let open, let firstRaise {
        callersAfterOpen = history[(firstRaise + 1)...].filter { $0.action == .call && $0.id != 0 && $0.id != open.id }.count
    }
    let ranks = s.hole.map(\.rank).sorted(by: >)
    let suited = s.hole[0].suit == s.hole[1].suit
    let late = ["BTN", "CO"].contains(s.position)
    let unopened = raises.isEmpty && s.currentBet <= 50
    let previous = raises.count >= 2 ? raises[raises.count - 2].amount : 0
    let situation: PreflopSituation
    if raises.isEmpty { situation = limpers != 0 ? .limped : .unopened }
    else if raises.count == 1 { situation = callersAfterOpen != 0 ? .openWithCallers : .facingOpen }
    else if raises.count == 2 { situation = .facingThreeBet }
    else { situation = .facingFourBetPlus }
    return PreflopContext(
        raises: raises.count,
        limpers: limpers,
        callersAfterOpen: callersAfterOpen,
        late: late,
        unopened: unopened,
        ace: ranks[0] == 14,
        kicker: ranks[1],
        suited: suited,
        weakAce: ranks[0] == 14 && ranks[1] <= 9 && ranks[0] != ranks[1],
        ownOpen: open?.id == 0,
        lastRaiser: last?.id,
        openTo: (open?.amount ?? 0) != 0 ? open!.amount : 50,
        ratio: last.map { Double($0.amount) / Double(previous != 0 ? previous : 50) } ?? 1,
        openingCandidate: startingTier(s.hole) >= 1 || (late && (ranks[0] == 14 || (ranks[0] >= 13 && ranks[1] >= 7))),
        situation: situation)
}
