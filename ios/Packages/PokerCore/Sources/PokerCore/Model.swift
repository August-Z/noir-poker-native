public let STARTING_STACK = 5000
public let SMALL_BLIND = 25
public let BIG_BLIND = 50
public let MIN_PLAYERS = 5
public let MAX_PLAYERS = 9

/// Table actions. `rawValue` is the reference's string identifier.
public enum PokerAction: String, Codable, Sendable, CaseIterable {
    case fold, check, call, raise
}

public enum Phase: String, Codable, Sendable {
    case idle, playing, between, done
}

public enum Difficulty: String, Codable, Sendable, CaseIterable {
    case easy, normal, hard
}

public enum LogType: String, Codable, Sendable {
    case street, blind, action, info, result
}

/// Emotion simulation strength. `rawValue` is the persisted identifier; case order is the UI order.
public enum EmotionMode: String, Codable, Sendable, CaseIterable {
    case off, subtle, lively

    public var label: String {
        switch self {
        case .off: return "Off"
        case .subtle: return "Subtle"
        case .lively: return "Pronounced"
        }
    }
}

public enum MoodKind: String, Codable, Sendable, CaseIterable {
    case steady, frustrated, cautious, confident, reactive

    public var label: String {
        switch self {
        case .steady: return "Steady"
        case .frustrated: return "Chasing Losses"
        case .cautious: return "Playing Safe"
        case .confident: return "On a Heater"
        case .reactive: return "Fighting Back"
        }
    }
}

public struct LastAction: Equatable, Sendable {
    public var text: String
    public var street: Int
    public var bet: Int
    public init(text: String, street: Int, bet: Int) {
        self.text = text
        self.street = street
        self.bet = bet
    }
}

public struct LogEntry: Equatable, Sendable {
    public var text: String
    public var player: Int?
    public var type: LogType
    public var street: Int
    public init(text: String, player: Int?, type: LogType, street: Int) {
        self.text = text
        self.player = player
        self.type = type
        self.street = street
    }
}

/// One public betting action. `amount` is the raise-to total, the call amount, or 0.
public struct HistoryEntry: Equatable, Sendable {
    public var street: Int
    public var id: Int
    public var action: PokerAction
    public var amount: Int
    /// The raise caption without the amount, e.g. `"2-bet open to"`; raises only.
    public var betLabel: String?
    public init(street: Int, id: Int, action: PokerAction, amount: Int = 0, betLabel: String? = nil) {
        self.street = street
        self.id = id
        self.action = action
        self.amount = amount
        self.betLabel = betLabel
    }
}

public struct BotStats: Equatable, Sendable {
    public var hands = 0
    public var vpip = 0
    public var pfr = 0
    public var postActions = 0
    public var postRaises = 0
    public var postCalls = 0
    public init() {}
}

public struct BotHand: Equatable, Sendable {
    public var vpip = false
    public var pfr = false
    public var pressureRecorded = false
    public init() {}
}

/// Synthetic mood. `pressureFolds` maps a raiser seat id to a consecutive
/// pressure-fold count.
public struct BotMood: Equatable, Sendable {
    public var kind: MoodKind = .steady
    public var remaining = 0
    public var cooldown = 0
    public var reason = ""
    public var losses = 0
    public var wins = 0
    public var pressureFolds: [Int: Int] = [:]
    /// Absent in a fresh mood; the reference treats absent and `null` alike.
    public var lastPressureRaiser: Int? = nil
    public init() {}
}

public struct Player: Equatable, Sendable, Identifiable {
    public let id: Int
    public var name: String
    public var stack: Int = STARTING_STACK
    public var hole: [Card] = []
    public var folded = false
    public var allin = false
    /// Chips put in on the current street.
    public var bet = 0
    /// Chips put in this hand, across streets.
    public var total = 0
    /// The `currentBet` level this player last acted at; `nil` before acting this street.
    public var actedTo: Int? = nil
    public var checked = false
    /// Current-street public action text.
    public var action = ""
    /// Retained public snapshot of the latest action.
    public var lastAction: LastAction? = nil
    public var botProfile = "balanced"
    public var botMood = freshBotMood()
    public var botStats = freshBotStats()
    public var botHand = BotHand()

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct GameStats: Equatable, Sendable {
    public var hands = 0
    public var wins = 0
    public var buyin = STARTING_STACK
    public init(hands: Int = 0, wins: Int = 0, buyin: Int = STARTING_STACK) {
        self.hands = hands
        self.wins = wins
        self.buyin = buyin
    }
}

public struct PotContribution: Equatable, Sendable {
    public var id: Int
    public var amount: Int
    public init(id: Int, amount: Int) {
        self.id = id
        self.amount = amount
    }
}

public struct PotAward: Equatable, Sendable {
    public var id: Int
    public var amount: Int
    public var label: String
    public init(id: Int, amount: Int, label: String) {
        self.id = id
        self.amount = amount
        self.label = label
    }
}

public struct Pot: Equatable, Sendable {
    public var index: Int
    public var label: String
    public var amount: Int
    public var eligible: [Int]
    public var contributions: [PotContribution]
    /// Empty until settlement.
    public var awards: [PotAward] = []
    public init(index: Int, label: String, amount: Int, eligible: [Int], contributions: [PotContribution], awards: [PotAward] = []) {
        self.index = index
        self.label = label
        self.amount = amount
        self.eligible = eligible
        self.contributions = contributions
        self.awards = awards
    }
}

public struct Refund: Equatable, Sendable {
    public var id: Int
    public var amount: Int
    public init(id: Int, amount: Int) {
        self.id = id
        self.amount = amount
    }
}

public struct PotSet: Equatable, Sendable {
    public var pots: [Pot]
    public var refunds: [Refund]
}

public struct Winner: Equatable, Sendable {
    public var id: Int
    public var name: String
    public var amount: Int
    public var profit: Int
    public var label: String
}

/// `legalActions` result. When `enabled` is false every other field is meaningless.
public struct LegalActions: Equatable, Sendable {
    public var enabled: Bool
    public var toCall = 0
    public var callAmount = 0
    public var canCheck = false
    public var raiseReopened = false
    public var canRaise = false
    public var minRaiseTo = 0
    public var fullRaiseTo = 0
    public var maxRaiseTo = 0
    public var isShortAllin = false

    public static let disabled = LegalActions(enabled: false)

    public init(enabled: Bool, toCall: Int = 0, callAmount: Int = 0, canCheck: Bool = false,
                raiseReopened: Bool = false, canRaise: Bool = false, minRaiseTo: Int = 0,
                fullRaiseTo: Int = 0, maxRaiseTo: Int = 0, isShortAllin: Bool = false) {
        self.enabled = enabled
        self.toCall = toCall
        self.callAmount = callAmount
        self.canCheck = canCheck
        self.raiseReopened = raiseReopened
        self.canRaise = canRaise
        self.minRaiseTo = minRaiseTo
        self.fullRaiseTo = fullRaiseTo
        self.maxRaiseTo = maxRaiseTo
        self.isShortAllin = isShortAllin
    }
}

/// Public state of one seat at the moment of a hero decision.
public struct SnapshotPlayer: Equatable, Sendable {
    public var id: Int
    public var name: String
    public var position: String
    public var stack: Int
    public var bet: Int
    public var total: Int
    public var folded: Bool
    public var allin: Bool
    public var action: String
    public var botProfile: String?
    public var publicAxes: [Double]?
    public var botMoodKind: MoodKind?
    public var actedTo: Int?
    public var checked: Bool
}

/// Hero decision snapshot: only information available before the decision.
public struct DecisionSnapshot: Equatable, Sendable {
    public var index: Int
    public var hand: Int
    public var street: Int
    public var position: String
    public var hole: [Card]
    public var board: [Card]
    public var stack: Int
    public var bet: Int
    public var total: Int
    public var pot: Int
    public var currentBet: Int
    public var minRaise: Int
    public var dealer: Int
    public var emotionMode: EmotionMode
    public var legal: LegalActions
    public var pending: [Int]
    public var action: PokerAction
    public var amount: Int
    public var players: [SnapshotPlayer]
    public var history: [HistoryEntry]
}

/// A private bot execution record: the action and its full trace, including thinking time.
public struct BotDecisionRecord: Equatable, Sendable {
    public var id: Int
    public var name: String
    public var hand: Int
    public var sequence: Int
    public var action: PokerAction
    /// Present only for raises.
    public var amount: Int?
    public var trace: BotTrace
}

/// An immutable value copy of the whole public game state (the reference's
/// `JSON.parse(JSON.stringify(g))`). Safe to hand to background work.
public struct GameState: Equatable, Sendable {
    public var players: [Player]
    public var dealer: Int
    public var hand = 0
    public var street = -1
    public var board: [Card] = []
    public var practiceBoard: [Card]? = nil
    public var deck: [Card] = []
    public var currentBet = 0
    public var minRaise = BIG_BLIND
    public var pending: [Int] = []
    public var actor = -1
    public var phase: Phase = .idle
    public var revealed = false
    public var pots: [Pot] = []
    public var refunds: [Refund] = []
    /// Newest first, like the reference's `unshift`.
    public var logs: [LogEntry] = []
    public var winners: [Winner] = []
    public var payouts: [Int] = []
    public var stats = GameStats()
    public var difficulty: Difficulty = .normal
    public var emotionMode: EmotionMode = .subtle
    public var replayAttempt = 0
    public var potAtShowdown = 0
    public var showdown = false
    public var result = ""
    public var decisions: [DecisionSnapshot] = []
    public var botDecisions: [BotDecisionRecord] = []
    public var history: [HistoryEntry] = []

    public init(players: [Player], dealer: Int) {
        self.players = players
        self.dealer = dealer
    }
}

/// The live table. A mutable reference type, mutated in place by the engine like
/// the reference's game object. Engine-private data (the replay baseline) is
/// internal to this module and never part of `state`.
public final class Game {
    public var players: [Player]
    public var dealer: Int
    public var hand = 0
    public var street = -1
    public var board: [Card] = []
    public var practiceBoard: [Card]? = nil
    public var deck: [Card] = []
    public var currentBet = 0
    public var minRaise = BIG_BLIND
    public var pending: [Int] = []
    public var actor = -1
    public var phase: Phase = .idle
    public var revealed = false
    public var pots: [Pot] = []
    public var refunds: [Refund] = []
    /// Newest first, like the reference's `unshift`.
    public var logs: [LogEntry] = []
    public var winners: [Winner] = []
    public var payouts: [Int] = []
    public var stats = GameStats()
    public var difficulty: Difficulty = .normal
    public var emotionMode: EmotionMode = .subtle
    public var replayAttempt = 0
    public var potAtShowdown = 0
    public var showdown = false
    public var result = ""
    public var decisions: [DecisionSnapshot] = []
    public var botDecisions: [BotDecisionRecord] = []
    public var history: [HistoryEntry] = []

    /// The private deal of the current hand (after the blinds, before any action).
    var handStart: GameState? = nil

    init(players: [Player], dealer: Int) {
        self.players = players
        self.dealer = dealer
    }

    /// Builds a live game from a value state. The copy has no replay baseline.
    public convenience init(state: GameState) {
        self.init(players: state.players, dealer: state.dealer)
        self.state = state
    }

    /// The whole public state as a value. Setting it replaces every public field
    /// (never the private replay baseline).
    public var state: GameState {
        get {
            var s = GameState(players: players, dealer: dealer)
            s.hand = hand
            s.street = street
            s.board = board
            s.practiceBoard = practiceBoard
            s.deck = deck
            s.currentBet = currentBet
            s.minRaise = minRaise
            s.pending = pending
            s.actor = actor
            s.phase = phase
            s.revealed = revealed
            s.pots = pots
            s.refunds = refunds
            s.logs = logs
            s.winners = winners
            s.payouts = payouts
            s.stats = stats
            s.difficulty = difficulty
            s.emotionMode = emotionMode
            s.replayAttempt = replayAttempt
            s.potAtShowdown = potAtShowdown
            s.showdown = showdown
            s.result = result
            s.decisions = decisions
            s.botDecisions = botDecisions
            s.history = history
            return s
        }
        set {
            players = newValue.players
            dealer = newValue.dealer
            hand = newValue.hand
            street = newValue.street
            board = newValue.board
            practiceBoard = newValue.practiceBoard
            deck = newValue.deck
            currentBet = newValue.currentBet
            minRaise = newValue.minRaise
            pending = newValue.pending
            actor = newValue.actor
            phase = newValue.phase
            revealed = newValue.revealed
            pots = newValue.pots
            refunds = newValue.refunds
            logs = newValue.logs
            winners = newValue.winners
            payouts = newValue.payouts
            stats = newValue.stats
            difficulty = newValue.difficulty
            emotionMode = newValue.emotionMode
            replayAttempt = newValue.replayAttempt
            potAtShowdown = newValue.potAtShowdown
            showdown = newValue.showdown
            result = newValue.result
            decisions = newValue.decisions
            botDecisions = newValue.botDecisions
            history = newValue.history
        }
    }

    /// A deep copy of the public state. Like a JSON clone in the reference, the
    /// copy carries no replay baseline and no bot plan is valid for it.
    public func deepCopy() -> Game { Game(state: state) }
}
