// Review input types (src/review/analysis.js `createReviewInput`).
//
// Privacy boundary. Decision review grades the hero only from what was public
// (plus the hero's own hole cards) before each decision. `ReviewDecision` and
// `ReviewSeat` have no field for opponents' hole cards, the remaining deck,
// future community cards, settlement results, or final winners, so grading code
// cannot read them. The settled outcome travels separately in `ReviewOutcome`,
// which carries only the display fields the reference copies, and is never
// passed to `analyzeDecision`.

/// Seat keys every engine snapshot carries. Hand-built snapshots (reference unit
/// tests) omit all four; that absence changes the decision seed and disables the
/// candidate simulation, exactly like an absent JavaScript key.
public struct SeatState: Equatable, Sendable {
    /// The bet level this seat last acted at this street; `nil` before acting.
    public var actedTo: Int?
    public var checked: Bool
    /// Public style id; `nil` for the hero.
    public var botProfile: String?
    /// Public mood kind; `nil` for the hero.
    public var botMoodKind: MoodKind?

    public init(actedTo: Int?, checked: Bool, botProfile: String?, botMoodKind: MoodKind?) {
        self.actedTo = actedTo
        self.checked = checked
        self.botProfile = botProfile
        self.botMoodKind = botMoodKind
    }
}

/// One seat at the moment of a hero decision: public chip state only, never hole cards.
public struct ReviewSeat: Equatable, Sendable {
    public var id: Int
    public var name: String
    public var position: String
    public var stack: Int
    public var bet: Int
    public var total: Int
    public var folded: Bool
    public var allin: Bool
    /// Current-street public action text.
    public var action: String
    public var publicAxes: [Double]?
    /// `nil` when the snapshot omits these keys (hand-built snapshots).
    public var state: SeatState?

    public init(id: Int, name: String, position: String, stack: Int, bet: Int, total: Int, folded: Bool,
                allin: Bool, action: String = "", publicAxes: [Double]? = nil, state: SeatState? = nil) {
        self.id = id
        self.name = name
        self.position = position
        self.stack = stack
        self.bet = bet
        self.total = total
        self.folded = folded
        self.allin = allin
        self.action = action
        self.publicAxes = publicAxes
        self.state = state
    }

    public init(_ p: SnapshotPlayer) {
        self.init(id: p.id, name: p.name, position: p.position, stack: p.stack, bet: p.bet, total: p.total,
                  folded: p.folded, allin: p.allin, action: p.action, publicAxes: p.publicAxes,
                  state: SeatState(actedTo: p.actedTo, checked: p.checked, botProfile: p.botProfile,
                                   botMoodKind: p.botMoodKind))
    }
}

/// A hero decision snapshot as review reads it (the reference `g.decisions[i]`).
/// `dealer` and `emotionMode` are `nil` where a hand-built snapshot omits them.
public struct ReviewDecision: Equatable, Sendable {
    public var index: Int
    public var hand: Int
    public var street: Int
    public var position: String
    /// The hero's own hole cards.
    public var hole: [Card]
    /// Community cards dealt before this decision.
    public var board: [Card]
    public var stack: Int
    public var bet: Int
    public var total: Int
    public var pot: Int
    public var currentBet: Int
    public var minRaise: Int
    public var dealer: Int?
    public var emotionMode: EmotionMode?
    public var legal: LegalActions
    /// Seats still to act this round, including the hero.
    public var pending: [Int]
    /// The normalized hero action (`call` with nothing owed is `check`).
    public var action: PokerAction
    /// Raise-to total, call amount, or 0.
    public var amount: Int
    /// Every seat; the array index equals the seat id.
    public var players: [ReviewSeat]
    /// Public actions before this decision.
    public var history: [HistoryEntry]

    public init(index: Int, hand: Int, street: Int, position: String, hole: [Card], board: [Card], stack: Int,
                bet: Int, total: Int, pot: Int, currentBet: Int, minRaise: Int, dealer: Int?,
                emotionMode: EmotionMode?, legal: LegalActions, pending: [Int], action: PokerAction, amount: Int,
                players: [ReviewSeat], history: [HistoryEntry]) {
        self.index = index
        self.hand = hand
        self.street = street
        self.position = position
        self.hole = hole
        self.board = board
        self.stack = stack
        self.bet = bet
        self.total = total
        self.pot = pot
        self.currentBet = currentBet
        self.minRaise = minRaise
        self.dealer = dealer
        self.emotionMode = emotionMode
        self.legal = legal
        self.pending = pending
        self.action = action
        self.amount = amount
        self.players = players
        self.history = history
    }

    /// The review view of an engine decision snapshot; every key is present.
    public init(_ d: DecisionSnapshot) {
        self.init(index: d.index, hand: d.hand, street: d.street, position: d.position, hole: d.hole, board: d.board,
                  stack: d.stack, bet: d.bet, total: d.total, pot: d.pot, currentBet: d.currentBet,
                  minRaise: d.minRaise, dealer: d.dealer, emotionMode: d.emotionMode, legal: d.legal,
                  pending: d.pending, action: d.action, amount: d.amount, players: d.players.map(ReviewSeat.init),
                  history: d.history)
    }

    /// The label step `actionLabel(s, …)` reads.
    public var labelStep: LabelStep {
        LabelStep(street: street, history: history, currentBet: currentBet, minRaise: minRaise,
                  legal: LabelLegal(legal), stack: stack, action: action, amount: amount)
    }

    func seat(_ id: Int) -> ReviewSeat? { players.indices.contains(id) ? players[id] : nil }
}

// Settlement display fields the reference copies into the review input. They are
// shown next to the review and never graded.

public struct OutcomeAward: Equatable, Sendable {
    public var name: String
    public var amount: Int
    public var label: String
    public init(name: String, amount: Int, label: String) {
        self.name = name
        self.amount = amount
        self.label = label
    }
}

public struct OutcomePot: Equatable, Sendable {
    public var label: String
    public var amount: Int
    /// Display names of the eligible players.
    public var eligible: [String]
    public var awards: [OutcomeAward]
    public init(label: String, amount: Int, eligible: [String], awards: [OutcomeAward]) {
        self.label = label
        self.amount = amount
        self.eligible = eligible
        self.awards = awards
    }
}

public struct ReviewOutcome: Equatable, Sendable {
    public var profit: Int
    public var paid: Int
    public var returned: Int
    public var folded: Bool
    public var wonPot: Bool
    public var board: [Card]
    public var pots: [OutcomePot]
    public var result: String
    public init(profit: Int, paid: Int, returned: Int, folded: Bool, wonPot: Bool, board: [Card],
                pots: [OutcomePot], result: String) {
        self.profit = profit
        self.paid = paid
        self.returned = returned
        self.folded = folded
        self.wonPot = wonPot
        self.board = board
        self.pots = pots
        self.result = result
    }
}

/// `createReviewInput(g)`. `decisions` are the only grading input. `opponents`
/// are the executed bot records (the reference passes `g.botDecisions`), read only
/// by `explainOpponent` after the hand; `outcome` is display data only.
public struct ReviewInput: Equatable, Sendable {
    public var hand: Int
    public var hole: [Card]
    public var decisions: [ReviewDecision]
    public var opponents: [BotDecisionRecord]
    public var outcome: ReviewOutcome
    public init(hand: Int, hole: [Card], decisions: [ReviewDecision], opponents: [BotDecisionRecord],
                outcome: ReviewOutcome) {
        self.hand = hand
        self.hole = hole
        self.decisions = decisions
        self.opponents = opponents
        self.outcome = outcome
    }
}

/// Thrown wherever the reference review throws. `code` is the stable fixture
/// identifier; `message` is the English copy.
public struct ReviewError: Error, Equatable, CustomStringConvertible, Sendable {
    public enum Code: String, Sendable, CaseIterable {
        case reviewNotReady = "review-not-ready"
        case invalidReviewTrials = "invalid-review-trials"
        case invalidSimulationTrials = "invalid-simulation-trials"
        case simulationRunaway = "simulation-runaway"
    }

    public let code: Code
    public var message: String { ReviewCopy.errorMessage(code) }
    public var description: String { message }
    public init(_ code: Code) { self.code = code }
}

/// An immutable value copy of a settled hand; later engine mutations never reach it.
public func createReviewInput(_ g: Game) throws -> ReviewInput {
    guard g.phase == .done else { throw ReviewError(.reviewNotReady) }
    let hero = g.players[0]
    let returned = g.payouts.first ?? 0
    return ReviewInput(
        hand: g.hand,
        hole: hero.hole,
        decisions: g.decisions.map(ReviewDecision.init),
        opponents: g.botDecisions,
        outcome: ReviewOutcome(
            profit: returned - hero.total,
            paid: hero.total,
            returned: returned,
            folded: hero.folded,
            wonPot: g.winners.contains { $0.id == 0 },
            board: g.board,
            pots: g.pots.map { p in
                OutcomePot(label: p.label, amount: p.amount, eligible: p.eligible.map { g.players[$0].name },
                           awards: p.awards.map { OutcomeAward(name: g.players[$0.id].name, amount: $0.amount,
                                                               label: $0.label) })
            },
            result: g.result))
}
