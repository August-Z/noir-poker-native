// The immutable projection of the live game and session state that the UI
// layers bind to. Every string is final English copy; amounts are also given
// as numbers so the UI can format or announce them differently.

/// A face-up card. `animate` and `delayMs` drive the deal and flip animations.
/// (Kotlin: `CardView`; renamed so it never shadows a SwiftUI view.)
public struct CardFace: Equatable, Sendable {
    public var card: Card
    public var best: Bool
    public var animate: Bool
    public var delayMs: Int
    public init(_ card: Card, best: Bool = false, animate: Bool = false, delayMs: Int = 0) {
        self.card = card
        self.best = best
        self.animate = animate
        self.delayMs = delayMs
    }
    /// `A♠`, `10♥`.
    public var text: String { card.description }
}

/// One of the five board positions; `card` is nil for an undealt slot.
public struct BoardSlot: Equatable, Sendable {
    public var index: Int
    public var card: CardFace?
    public var placeholderGlyph: String
    public var a11y: String
}

public struct PositionBadge: Equatable, Sendable {
    public var code: String
    public var name: String
}

/// The hand-rank / winner badge on a seat or the hero.
public struct RankBadge: Equatable, Sendable {
    public var text: String
    public var isWinner: Bool
    public var a11y: String?
    public var title: String?
}

/// The post-settlement eye toggle on an opponent seat.
public struct PeekToggle: Equatable, Sendable {
    public var pressed: Bool
    public var title: String
    public var a11y: String
}

public struct SeatState: Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    /// Reference layout: seat center as a percentage of the arena (left, top).
    public var layoutX: Double
    public var layoutY: Double
    public var position: PositionBadge
    public var folded: Bool
    /// This seat is the current actor (shows the deciding state).
    public var isActor: Bool
    public var isWinner: Bool
    /// Hole cards are face up (showdown, all-in runout, or the eye toggle).
    public var revealed: Bool
    /// Face-up cards when `revealed`; empty otherwise.
    public var cards: [CardFace]
    /// Number of card backs when not revealed.
    public var cardBacks: Int
    /// Card backs play the deal animation (new hand); delays per card.
    public var dealAnimation: Bool
    public var cardBackDelaysMs: [Int]
    public var cardBackA11y: String
    public var badge: RankBadge?
    public var avatar: String
    public var avatarTitle: String
    public var profileId: String
    public var styleShort: String
    public var styleTitle: String
    public var styleA11y: String
    /// `steady` whenever emotion simulation is off.
    public var mood: MoodKind
    public var moodLabel: String
    public var stack: Int
    public var stackText: String
    /// Present only after settlement.
    public var peek: PeekToggle?
    public var action: ActionChip
    public var actionA11y: String
}

public struct HeroState: Equatable, Sendable {
    public var name: String
    public var cards: [CardFace]
    public var rankBadge: RankBadge?
    public var folded: Bool
    public var isActive: Bool
    public var stack: Int
    public var stackText: String
    public var position: PositionBadge
    /// `nil` when the hand is over (the line is hidden).
    public var turnText: String?
    /// The retained last action with its street; `nil` hides the row.
    public var lastAction: ActionChip?
    public var lastActionA11y: String
}

public struct SessionStatsState: Equatable, Sendable {
    public var stack: Int
    public var stackText: String
    public var chipsUnit: String
    public var changeText: String
    public var negative: Bool
    public var hands: Int
    public var wins: Int
    public var winRateText: String
}

public struct ActivityEntryState: Equatable, Sendable {
    /// 1-based, chronological.
    public var number: Int
    public var text: String
    /// `text` split into plain runs and persona suffixes.
    public var segments: [TextSegment]
    public var type: LogType
    public var playerId: Int?
    public var isHero: Bool
    public var street: Int
}

public struct ActivityState: Equatable, Sendable {
    public var entries: [ActivityEntryState]
    public var badge: String
}

public enum BetPreset: String, Sendable, CaseIterable {
    case min
    case halfPot = "half"
    case pot
    case allIn = "all"
}

/// A bet preset; `amount` is the raise-to total it would select (nil when raising is unavailable).
public struct PresetState: Equatable, Sendable {
    public var preset: BetPreset
    public var label: String
    public var amount: Int?
    public var enabled: Bool
}

public struct ActionPanelState: Equatable, Sendable {
    public var decisionStripVisible: Bool
    public var decisionText: String
    /// Bet controls and Fold / Call / Raise (hidden when the hand is over or the hero folded).
    public var controlsVisible: Bool
    public var foldLabel: String
    public var foldEnabled: Bool
    public var callEnabled: Bool
    public var callLabel: String
    public var callAmount: Int?
    public var callAmountText: String?
    public var callA11y: String
    public var raiseEnabled: Bool
    /// `{level}-bet {verb}` for the current bet, e.g. `3-bet raise to`.
    public var raiseCaption: String
    public var bet: Int
    public var betText: String
    public var raiseA11y: String
    public var sliderLabel: String
    public var sliderA11y: String
    public var sliderMin: Int?
    public var sliderMax: Int?
    public var presets: [PresetState]
    public var nextHandVisible: Bool
    public var nextHandLabel: String
    public var finishHandVisible: Bool
    public var finishHandEnabled: Bool
    public var finishHandLabel: String
    public var finishHandTitle: String
    public var replayVisible: Bool
    public var replayLabel: String
    public var replayTitle: String
    public var reviewVisible: Bool
    public var reviewLabel: String
}

public struct CoachState: Equatable, Sendable {
    public var visible: Bool
    public var toggleOn: Bool
    public var toggleLabel: String
    public var stage: String
    public var tip: String
}

public struct ShowdownSceneState: Equatable, Sendable {
    public var scene: HandScene
    /// The player's name with the persona suffix.
    public var nameSegments: [TextSegment]
    public var isWinner: Bool
    public var statusText: String
    public var footerText: String
    public var a11y: String
}

/// The showdown comparison. `key` changes once per settled hand; animate only when it changes.
public struct ShowdownState: Equatable, Sendable {
    public var key: String
    public var context: String
    public var scenes: [ShowdownSceneState]
}

public struct PotAwardRow: Equatable, Sendable {
    public var playerId: Int
    public var name: String
    public var winnerText: String
    public var label: String
    public var amountText: String
    public var unit: String
}

public struct PotContributionRow: Equatable, Sendable {
    public var playerId: Int
    public var text: String
    public var amount: Int
    public var amountText: String
}

public struct PotCardState: Equatable, Sendable {
    public var index: Int
    public var label: String
    public var amount: Int
    public var amountText: String
    public var settled: Bool
    public var eligibilityLabel: String
    public var heroEligible: Bool
    public var contributions: [PotContributionRow]
    // Settled.
    public var splitTotalText: String?
    public var awards: [PotAwardRow]
    public var distributionSummary: String
    public var distributionEligibility: String
    public var contributionsHeading: String
    public var oddChipNote: String?
    public var expanded: Bool
    // Live.
    public var unit: String
    public var playerCountText: String
    public var participantsText: String
    public var contributionsSummary: String
}

public struct RefundRowState: Equatable, Sendable {
    public var playerId: Int
    public var amount: Int
    public var amountText: String
    public var text: String
    public var a11y: String?
    public var returned: Bool
}

public struct PotDetailsState: Equatable, Sendable {
    public var open: Bool
    public var settled: Bool
    public var title: String
    public var note: String?
    public var pots: [PotCardState]
    public var refunds: [RefundRowState]
}

public struct SettingsState: Equatable, Sendable {
    public var requestedSeatCount: Int
    public var seatCountOptions: [OptionItem<Int>]
    /// Shown while a different seat count is pending for the next hand.
    public var tableChangeNote: String?
    public var difficulty: Difficulty
    public var difficultyOptions: [OptionItem<Difficulty>]
    public var hints: Bool
    public var sound: Bool
    public var soundA11y: String
    public var soundTitle: String
    public var emotionOptions: [OptionItem<EmotionMode>]
}

/// Everything the table UI renders. Rebuilt after every change; compare
/// `version` to detect a new state cheaply.
public struct TableRenderState {
    /// Increments with every published state.
    public var version: Int
    public var hand: Int
    public var handNumber: String
    public var handHeading: String
    public var playerCount: Int
    public var tableTag: String
    public var tableSize: String
    /// Some opponent uses a long style name (Viktor Blom, Daniel Cates, Tom Dwan).
    public var hasFullPlayerNames: Bool
    public var phase: Phase
    public var street: Int
    public var streetLabel: String
    public var dealer: Int
    public var replayAttempt: Int
    public var replayBadge: String?
    public var replayNote: String?
    public var pot: Int
    public var potText: String
    /// Play the pot bump: new community cards since the last state.
    public var potPulse: Bool
    public var potButtonLabel: String
    public var potButtonA11y: String
    public var board: [BoardSlot]
    public var boardCaption: String
    public var practiceRunout: Bool
    public var seats: [SeatState]
    public var hero: HeroState
    public var session: SessionStatsState
    public var activity: ActivityState
    public var actions: ActionPanelState
    public var coach: CoachState
    /// `nil` while hidden (not settled at a five-card showdown).
    public var showdown: ShowdownState?
    public var potDetails: PotDetailsState
    public var opponents: OpponentsSummary
    /// `nil` while the Opponent Styles dialog is closed.
    public var opponentsDialog: OpponentsDialogState?
    public var review: HandReviewState
    public var settings: SettingsState
    public var finishing: Bool
    public var backgrounded: Bool
}

// The diagnostic public snapshot (`window.noir.getState()`), for UI tests and
// accessibility checks. It never contains hidden hole cards, plans or traces.

public struct PublicAward: Equatable, Sendable {
    public var name: String
    public var amount: Int
    public var label: String
}

public struct PublicPot: Equatable, Sendable {
    public var label: String
    public var amount: Int
    public var eligible: [String]
    public var awards: [PublicAward]
}

public struct PublicRefund: Equatable, Sendable {
    public var name: String
    public var amount: Int
    public var returned: Bool
}

public struct PublicPlayer: Equatable, Sendable {
    public var id: Int
    public var name: String
    public var position: String
    public var stack: Int
    public var folded: Bool
    public var allin: Bool
    public var bet: Int
    public var action: String
    public var lastAction: LastAction?
    /// Opponents only.
    public var botProfile: String?
    public var mood: String?
    public var botStats: BotStats?
    /// Present only while the seat's hand is visible.
    public var cards: [String]?
}

public struct PublicTableSnapshot: Equatable, Sendable {
    public var playerCount: Int
    public var emotionMode: String
    public var canContinue: Bool
    public var replayAttempt: Int
    public var canRestart: Bool
    public var hand: Int
    public var dealer: String
    public var seatOrder: String
    public var street: String?
    public var phase: String
    public var actor: String?
    public var pot: Int
    public var pots: [PublicPot]
    public var uncalled: [PublicRefund]
    public var board: [String]
    public var settlementBoard: [String]
    public var practiceRunout: Bool
    public var hole: [String]
    public var stack: Int
    public var legal: LegalActions
    public var players: [PublicPlayer]
    public var result: String?
    public var totalLogs: Int
    /// Σ stacks + (pot while the hand is live).
    public var wealth: Int
}

/// Synthesized sounds: notes start every 80 ms; gain 0.0001 → 0.025 at 15 ms → 0.0001 at 160 ms; stop at 200 ms.
public enum SoundKind: String, Sendable, CaseIterable {
    case chip, deal, win

    public var notesHz: [Int] {
        switch self {
        case .chip: return [310]
        case .deal: return [820, 570]
        case .win: return [440, 554, 659]
        }
    }

    public var wave: String { self == .deal ? "triangle" : "sine" }
}

/// One-shot presentation effects (sound, chip flights, focus).
public enum SessionEffect: Equatable, Sendable {
    case sound(SoundKind)
    /// Three chips fly from the seat (0 = hero) to the pot.
    case chipFlight(seat: Int)
    /// Cancel and remove every chip in flight (Replay Hand).
    case cancelChipFlights
    /// Keep focus on the seat's eye toggle and fade its cards in when revealed.
    case revealToggled(seat: Int, visible: Bool)
}

/// The bot currently "thinking": its delay and the virtual-clock deadline. Diagnostic only.
public struct BotWaitInfo: Equatable, Sendable {
    public var actor: Int
    public var delayMs: Int
    public var startedAt: Int
    public var deadline: Int
}
