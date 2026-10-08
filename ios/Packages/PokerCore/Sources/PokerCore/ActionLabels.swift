/// The `legal` fields the label functions read. Fields may be absent, like a
/// partial `legal` object in the reference (a disabled `legalActions` result has none).
public struct LabelLegal: Equatable, Sendable {
    public var callAmount: Int?
    public var fullRaiseTo: Int?
    public var maxRaiseTo: Int?
    public init(callAmount: Int? = nil, fullRaiseTo: Int? = nil, maxRaiseTo: Int? = nil) {
        self.callAmount = callAmount
        self.fullRaiseTo = fullRaiseTo
        self.maxRaiseTo = maxRaiseTo
    }
    public init(_ legal: LegalActions) {
        if legal.enabled {
            self.init(callAmount: legal.callAmount, fullRaiseTo: legal.fullRaiseTo, maxRaiseTo: legal.maxRaiseTo)
        } else {
            self.init()
        }
    }
}

/// The fields the label functions read. In the reference this is any object
/// with these keys: a hero decision snapshot, or the game plus `legal`,
/// `action` and `amount`.
public struct LabelStep: Equatable, Sendable {
    public var street: Int
    public var history: [HistoryEntry]
    public var currentBet: Int
    public var minRaise: Int?
    public var legal: LabelLegal?
    public var stack: Int?
    public var action: PokerAction?
    public var amount: Int?

    public init(street: Int, history: [HistoryEntry] = [], currentBet: Int = 0, minRaise: Int? = nil,
                legal: LabelLegal? = nil, stack: Int? = nil, action: PokerAction? = nil, amount: Int? = nil) {
        self.street = street
        self.history = history
        self.currentBet = currentBet
        self.minRaise = minRaise
        self.legal = legal
        self.stack = stack
        self.action = action
        self.amount = amount
    }

    public init(street: Int, history: [HistoryEntry] = [], currentBet: Int = 0, minRaise: Int? = nil,
                legal: LegalActions, stack: Int? = nil, action: PokerAction? = nil, amount: Int? = nil) {
        self.init(street: street, history: history, currentBet: currentBet, minRaise: minRaise,
                  legal: LabelLegal(legal), stack: stack, action: action, amount: amount)
    }

    /// A hero decision snapshot as a label step.
    public init(_ d: DecisionSnapshot) {
        self.init(street: d.street, history: d.history, currentBet: d.currentBet, minRaise: d.minRaise,
                  legal: LabelLegal(d.legal), stack: d.stack, action: d.action, amount: d.amount)
    }

    /// The label step for the actor's next action in a live game.
    public init(game g: Game, action: PokerAction? = nil, amount: Int? = nil) {
        let stack = g.players.indices.contains(g.actor) ? g.players[g.actor].stack : nil
        self.init(street: g.street, history: g.history, currentBet: g.currentBet, minRaise: g.minRaise,
                  legal: LabelLegal(legalActions(g)), stack: stack, action: action, amount: amount)
    }
}

// This is an action ordinal, not a test of whether betting has reopened.
// The big blind is the first bet preflop; every later street starts at zero.
public func nextBetLevel(street: Int, history: [HistoryEntry] = []) -> Int {
    (street == 0 ? 1 : 0) + history.filter { $0.street == street && $0.action == .raise }.count + 1
}

public func nextBetLevel(_ step: LabelStep) -> Int { nextBetLevel(street: step.street, history: step.history) }

public func raiseCaption(_ step: LabelStep, _ amount: Int) -> String {
    let level = nextBetLevel(step)
    let allin = step.legal?.maxRaiseTo != nil && amount == step.legal?.maxRaiseTo
    let fullRaiseTo = step.legal?.fullRaiseTo
        ?? (step.currentBet == 0 ? 50 : step.currentBet + (step.minRaise ?? 50))
    let verb: String
    if allin && amount < fullRaiseTo { verb = EngineCopy.shortAllInTo }
    else if allin { verb = EngineCopy.allInTo }
    else if step.currentBet == 0 { verb = EngineCopy.betTo }
    else if step.street == 0 && level == 2 { verb = EngineCopy.openTo }
    else { verb = EngineCopy.raiseTo }
    return EngineCopy.betCaption(level, verb)
}

/// `actionLabel(step, action = step.action, amount = step.amount)`.
public func actionLabel(_ step: LabelStep, _ action: PokerAction? = nil, _ amount: Int? = nil) -> String {
    let action = action ?? step.action
    let amount = amount ?? step.amount
    if action == .raise {
        let n = amount ?? 0
        return raiseCaption(step, n) + " " + formatChips(n)
    }
    if action == .call {
        let callAmount = step.legal?.callAmount ?? 0
        let allIn = step.stack != nil && step.legal?.callAmount == step.stack
        return (allIn ? EngineCopy.allInCallPrefix : EngineCopy.callPrefix) + formatChips(callAmount)
    }
    return action == .fold ? EngineCopy.fold : EngineCopy.check
}

public func historyActionLabel(_ history: [HistoryEntry], _ index: Int) -> String {
    let a = history[index]
    if a.action != .raise {
        switch a.action {
        case .call: return EngineCopy.callPrefix + formatChips(a.amount)
        case .fold: return EngineCopy.fold
        default: return EngineCopy.check
        }
    }
    if let betLabel = a.betLabel, !betLabel.isEmpty { return betLabel + " " + formatChips(a.amount) }
    let before = Array(history[0..<index])
    let previous = before.last { $0.street == a.street && $0.action == .raise }
    return actionLabel(LabelStep(street: a.street, history: before,
                                 currentBet: previous?.amount ?? (a.street == 0 ? 50 : 0),
                                 action: a.action, amount: a.amount))
}
