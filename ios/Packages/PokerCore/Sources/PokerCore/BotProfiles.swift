// These are training controls inferred from a few public examples, not measured
// statistics of the named players. Emotions are a separate synthetic layer.

public struct BotSource: Equatable, Sendable {
    public let label: String
    public let url: String
}

public struct BotProfile: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let short: String
    public let tag: String
    public let description: String
    /// `[width, attack, bluff, callDown, trap]`, each 0...100.
    public let axes: [Int]
    /// `[low, high]` fraction of the pot for raise sizing.
    public let sizing: [Double]
    public let evidence: String
    public let sources: [BotSource]
}

private let triton = "https://tritonpokerseries.com/en-US/news/headlines/"
private let bluffsRetrospective = "https://www.pokerstars.com/poker/learn/news/the-best-and-worst-poker-bluffs-ever/"

public let BOT_PROFILES: [BotProfile] = [
    BotProfile(
        id: "balanced",
        name: "Balanced Practice",
        short: "Balanced",
        tag: "Steady baseline opponent",
        description: "Medium range and standard sizing, mixing value bets with occasional bluffs.",
        axes: [50, 50, 40, 50, 20],
        sizing: [0.45, 0.8],
        evidence: "Baseline training strategy; it does not represent any real player.",
        sources: []
    ),
    BotProfile(
        id: "tan",
        name: "Johnny Tan · Tan Xuan",
        short: "Johnny Tan",
        tag: "Wide range · Multi-street pressure",
        description: "Contests more pots with a wider range, takes the same aggressive lines with weak and strong hands, and prefers sustained pressure.",
        axes: [85, 90, 82, 70, 25],
        sizing: [0.65, 1.15],
        evidence: "Triton cash-game coverage documents a light 4-bet and multi-street bluffs; in a short deck interview he also says he likes playing loose and bluffing. Short deck frequencies are not carried over to this table.",
        sources: [
            BotSource(label: "Triton · Cash-game aggression sample", url: triton + "st-wang-shows-million-dollar-class-as-cash-game-invitational-raises-stakes"),
            BotSource(label: "Triton · Player interview (short deck)", url: triton + "tan-xuan-completes-short-deck-double-with-jeju-main-event-success"),
        ]
    ),
    BotProfile(
        id: "st",
        name: "ST Wang",
        short: "ST Wang",
        tag: "Selective aggression · Value traps",
        description: "Tightens up marginal entries, slow-plays strong hands on safe boards, and still cuts losses against big bets.",
        axes: [40, 65, 43, 42, 78],
        sizing: [0.45, 0.9],
        evidence: "In official coverage he still folded AQ on the river right after losing a big pot; in another hand he set a river check-shove value trap with AA.",
        sources: [
            BotSource(label: "Triton · Discipline after a big loss", url: triton + "ferdinand-takes-most-as-phil-ivey-and-dan-cates-land-big-cash-game-profits"),
            BotSource(label: "Triton · Trapping with a strong hand", url: triton + "more-brilliance-from-elton-tsang-as-cash-game-invitational-gets-serious"),
        ]
    ),
    BotProfile(
        id: "zang",
        name: "Aaron Zang",
        short: "Aaron Zang",
        tag: "Seasoned aggression · River battles",
        description: "Medium-wide range; fights for pots in position and keeps both river raising and bluff-catching lines.",
        axes: [63, 75, 62, 63, 50],
        sizing: [0.6, 1.0],
        evidence: "Triton recorded a river bluff that raised a 23k bet to 105k. A single hand says nothing about long-run frequencies.",
        sources: [
            BotSource(label: "Triton · River aggression sample", url: triton + "brilliant-rui-cao-and-steady-andy-ni-win-big-on-day-2-in-jeju"),
        ]
    ),
    BotProfile(
        id: "peter",
        name: "Peter · HCL",
        short: "Peter",
        tag: "Wide range · Big-bet brawler",
        description: "More willing to call in, extracts big-bet value with strong hands, and occasionally fights back hard with small pocket pairs.",
        axes: [92, 88, 72, 84, 18],
        sizing: [0.75, 1.25],
        evidence: "HCL footage shows a pot-sized river re-raise with a set; another session shows a big shove with a small pocket pair. The latter was played under a Stand-Up side-game rule, so its frequencies cannot be copied over. \"Peter\" here refers to the HCL regular.",
        sources: [
            BotSource(label: "HCL · River value raise", url: "https://hustlercasinolive.com/2024/06/12/the-rematch-we-didnt-know-we-needed/"),
            BotSource(label: "PokerNews · Small-pair counterattack (side-game rule)", url: "https://www.pokernews.com/news/2025/01/poker-player-goes-all-in-for-thousands-47684.htm"),
        ]
    ),
    BotProfile(
        id: "abao",
        name: "A Bao · KPC",
        short: "A Bao",
        tag: "Selective pressure · Semi-bluffs",
        description: "More aggressive with draw equity; can follow a small flop bet with a big turn bet to keep up the pressure.",
        axes: [55, 82, 72, 50, 34],
        sizing: [0.5, 1.0],
        evidence: "In detailed KPC hand coverage, suited AJ bet about 31% pot on the flop and semi-bluffed 90% pot on the turn; another sample shows a shove with a 98 flush draw. The player's real name has not been reliably confirmed.",
        sources: [
            BotSource(label: "Pokerati · AJ semi-bluff hand", url: "https://pokerati.com/2026/08/top-streamed-hands-of-the-week-winston-sets-the-perfect-trap-a-bao-bluffs-big/"),
            BotSource(label: "Pokerati · Flush-draw counterattack", url: "https://pokerati.com/2026/08/top-streamed-hands-of-the-week-malinowski-and-dwan-take-on-the-kpc-high-rollers/"),
        ]
    ),
    BotProfile(
        id: "viktor",
        name: "Viktor Blom",
        short: "Viktor Blom",
        tag: "Loose-aggressive pressure · Wide-range battles",
        description: "Contests late-position and cheap pots more widely, takes the same aggressive lines with draws and value hands, and prefers larger sizes.",
        axes: [90, 94, 88, 70, 18],
        sizing: [0.7, 1.25],
        evidence: "An original PokerStars interview and an official retrospective support his historical loose-aggressive style. This is a training archetype, not his current play or real frequencies; heads-up experience is not translated directly into precise multiway parameters.",
        sources: [
            BotSource(label: "PokerStars · Original Viktor interview", url: "https://www.pokerstars.com/poker/learn/news/finding-isildur1-viktor-blom-cops-to-his-077269/"),
            BotSource(label: "PokerStars · Historic bluffs retrospective", url: bluffsRetrospective),
        ]
    ),
    BotProfile(
        id: "jungleman",
        name: "Daniel Cates",
        short: "Daniel Cates",
        tag: "Calculated aggression · Trapping strong hands",
        description: "Defends when the price is right and balances proactive pressure with trapping strong hands; large continues must still pass the equity and stack-pressure checks.",
        axes: [65, 82, 66, 64, 72],
        sizing: [0.45, 0.95],
        evidence: "His own interviews stress calculation, watching what opponents actually do, and adjusting rather than balancing mechanically. This bot approximates those ideas with ranges and prices; it does not reproduce professional-level reads or dynamic learning.",
        sources: [
            BotSource(label: "Card Player · Daniel Cates interview", url: "https://www.cardplayer.com/cardplayer-poker-magazines/65799-poker-hall-of-fame-23-20/articles/19757-capture-the-flag-daniel-jungleman12-cates"),
            BotSource(label: "Card Player · Interview on adjusting to opponents", url: "https://www.cardplayer.com/cardplayer-poker-magazines/66315-jason-mercier-28-23/articles/22601-head-games-heads-up-cash-game-advice-from-the-best-in-the-world"),
        ]
    ),
    BotProfile(
        id: "dwan",
        name: "Tom Dwan",
        short: "Tom Dwan",
        tag: "Creative pressure · Multi-street bluffs",
        description: "Fights harder for pots in position, mixes in multi-street pressure when he has a credible story or a draw, and can keep opponents' ranges wide with strong hands.",
        axes: [85, 90, 85, 75, 55],
        sizing: [0.65, 1.2],
        evidence: "Original interviews, peer assessments, and a PokerStars retrospective support his historical creative, multi-street bluffing style. The parameters are only adjustable simulation tendencies; they do not infer the real player's VPIP or state of mind.",
        sources: [
            BotSource(label: "Card Player · Original Dwan interview", url: "https://www.cardplayer.com/cardplayer-poker-magazines/65739-tom-dwan-6-4/articles/18288-the-won-39-durrrr-39-ful-life-of-tom-dwan"),
            BotSource(label: "PokerStars · Historic bluffs retrospective", url: bluffsRetrospective),
        ]
    ),
]

public let PROFILE_AXES = ["Range Width", "Aggression", "Bluffing", "Calling Down", "Trapping"]

/// Display labels by mood kind (the reference's `MOOD_LABELS`).
public func moodLabel(_ kind: MoodKind) -> String { kind.label }

public func getBotProfile(_ id: String?) -> BotProfile {
    BOT_PROFILES.first { $0.id == id } ?? BOT_PROFILES[0]
}

/// Seat assignments always cover seats 1...8, even at a smaller table.
public struct BotSettings: Equatable, Sendable {
    public var emotionMode: EmotionMode
    public var assignments: [Int: String]
    public init(emotionMode: EmotionMode, assignments: [Int: String]) {
        self.emotionMode = emotionMode
        self.assignments = assignments
    }
}

public func defaultBotSettings() -> BotSettings {
    BotSettings(emotionMode: .subtle, assignments: Dictionary(uniqueKeysWithValues: (1...8).map { ($0, "balanced") }))
}

/// Accepts untrusted input and never throws: a `BotSettings`, or a value shaped
/// like the persisted JSON (`emotionMode`, `assignments` keyed by seat id as an
/// integer or string, or an array indexed by seat id), for example the output of
/// `JSONSerialization`. Anything unrecognized falls back to the defaults.
public func sanitizeBotSettings(_ value: Any?) -> BotSettings {
    var settings = defaultBotSettings()
    var rawMode: Any? = nil
    var rawAssignments: Any? = nil
    if let s = value as? BotSettings {
        rawMode = s.emotionMode.rawValue
        rawAssignments = s.assignments
    } else if let dict = value as? [String: Any] {
        rawMode = dict["emotionMode"]
        rawAssignments = dict["assignments"]
    } else if let dict = value as? [AnyHashable: Any] {
        rawMode = dict["emotionMode"]
        rawAssignments = dict["assignments"]
    }
    if let mode = rawMode as? String, let parsed = EmotionMode(rawValue: mode) { settings.emotionMode = parsed }
    for id in 1...8 {
        var profile: Any? = nil
        if let map = rawAssignments as? [Int: String] {
            profile = map[id]
        } else if let map = rawAssignments as? [String: Any] {
            profile = map[String(id)]
        } else if let map = rawAssignments as? [AnyHashable: Any] {
            profile = map[AnyHashable(String(id))] ?? map[AnyHashable(id)]
        } else if let list = rawAssignments as? [Any], id < list.count {
            profile = list[id]
        }
        if let name = profile as? String, BOT_PROFILES.contains(where: { $0.id == name }) {
            settings.assignments[id] = name
        }
    }
    return settings
}

public func freshBotMood() -> BotMood { BotMood() }

public func freshBotStats() -> BotStats { BotStats() }

public func decayBotMood(_ mood: inout BotMood) {
    mood.cooldown = max(0, mood.cooldown - 1)
    mood.remaining = max(0, mood.remaining - 1)
    if mood.remaining == 0 {
        mood.kind = .steady
        mood.reason = ""
    }
}

/// A mood change, for the activity log.
public struct MoodEvent: Equatable, Sendable {
    public let kind: MoodKind
    public let reason: String
}

private func setMood(_ mood: inout BotMood, _ kind: MoodKind, _ reason: String) -> MoodEvent {
    mood.kind = kind
    mood.reason = reason
    mood.remaining = 3
    mood.cooldown = 4
    return MoodEvent(kind: kind, reason: reason)
}

@discardableResult
public func recordPressureFold(_ mood: inout BotMood, raiser: Int?, mode: EmotionMode) -> MoodEvent? {
    guard let raiser, mode != .off else { return nil }
    if mood.lastPressureRaiser != raiser { mood.pressureFolds = [:] }
    mood.lastPressureRaiser = raiser
    let count = (mood.pressureFolds[raiser] ?? 0) + 1
    mood.pressureFolds[raiser] = count
    if count >= 3 && mood.cooldown == 0 {
        mood.pressureFolds[raiser] = 0
        return setMood(&mood, .reactive, EngineCopy.reasonPressure)
    }
    return nil
}

/// `finishBotHand({id, botMood}, profit, mode)`.
@discardableResult
public func finishBotHand(playerId: Int, mood: inout BotMood, profit: Int, mode: EmotionMode) -> MoodEvent? {
    mood.losses = profit <= -250 ? mood.losses + 1 : 0
    mood.wins = profit >= 250 ? mood.wins + 1 : 0
    if mode == .off || mood.cooldown != 0 { return nil }
    // Both reactions are synthetic; no emotional trait is assigned to a person.
    if profit <= -1250 || mood.losses >= 3 {
        return setMood(&mood, playerId % 2 != 0 ? .frustrated : .cautious,
                       profit <= -1250 ? EngineCopy.reasonBigLoss : EngineCopy.reasonLosingStreak)
    }
    if mood.wins >= 2 && profit >= 500 { return setMood(&mood, .confident, EngineCopy.reasonWinningStreak) }
    return nil
}

@discardableResult
public func finishBotHand(_ player: inout Player, profit: Int, mode: EmotionMode) -> MoodEvent? {
    finishBotHand(playerId: player.id, mood: &player.botMood, profit: profit, mode: mode)
}

// A simple, deterministic starting-hand ordering, weighted by the 1,326 actual
// combinations. This is a range-selection heuristic, not an equity table.
private func startingValue(_ rankA: Int, _ suitA: Int, _ rankB: Int, _ suitB: Int) -> Double {
    let high = max(rankA, rankB), low = min(rankA, rankB)
    if high == low { return Double(30 + high * 2) }
    let suited = suitA == suitB, gap = high - low
    // Strict left-to-right double arithmetic, as in the reference.
    var v = Double(high) * 1.9
    v += Double(low) * 0.9
    v += suited ? 4 : 0
    v += gap == 1 ? 3 : gap == 2 ? 1 : 0
    v += high == 14 ? 3 : 0
    return v
}

private let startingCombinations: [Double] = {
    var values: [Double] = []
    values.reserveCapacity(1326)
    for a in 0..<52 {
        for b in (a + 1)..<52 {
            values.append(startingValue(a % 13 + 2, a / 13, b % 13 + 2, b / 13))
        }
    }
    return values
}()

/// Fraction of the 1,326 combinations strictly stronger than `hole` (AA = 0).
public func startingPercentile(_ hole: [Card]) -> Double {
    let v = startingValue(hole[0].rank, hole[0].suit, hole[1].rank, hole[1].suit)
    return Double(startingCombinations.filter { $0 > v }.count) / Double(startingCombinations.count)
}

public struct BoardFeatures: Equatable, Sendable {
    public var wet: Bool
    public var draw: Bool
    public var overpair: Bool
    public init(wet: Bool = false, draw: Bool = false, overpair: Bool = false) {
        self.wet = wet
        self.draw = draw
        self.overpair = overpair
    }
}

private let straightWindows: [[Int]] = (0..<10).map { i in (0..<5).map { j in i + j + 1 } }

public func botBoardFeatures(_ hole: [Card], _ board: [Card], _ score: [Int]) -> BoardFeatures {
    let known = hole + board
    var ranks = Set(known.map(\.rank))
    if ranks.contains(14) { ranks.insert(1) }
    let suits = (0...3).map { s in board.filter { $0.suit == s }.count }
    let connected = max(0, straightWindows.map { run in
        run.filter { r in board.contains { $0.rank == r || (r == 1 && $0.rank == 14) } }.count
    }.max()!)
    let maxSuit = suits.max()!
    let wet = max(0, maxSuit) >= 3 || connected >= 3 || (board.count == 3 && maxSuit == 2)
    let flushDraw = board.count >= 3 && board.count < 5 && score[0] < 5 &&
        (0...3).contains { s in known.filter { $0.suit == s }.count == 4 && hole.contains { $0.suit == s } }
    let straightDraw = board.count >= 3 && board.count < 5 && score[0] < 4 &&
        straightWindows.contains { run in
            run.filter { ranks.contains($0) }.count == 4 &&
                hole.contains { c in
                    (run.contains(c.rank) || (c.rank == 14 && run.contains(1))) && !board.contains { $0.rank == c.rank }
                }
        }
    let highBoard = max(0, board.map(\.rank).max() ?? 0)
    let overpair = hole[0].rank == hole[1].rank && hole[0].rank > highBoard
    return BoardFeatures(wet: wet, draw: flushDraw || straightDraw, overpair: overpair)
}

private func moodOffsets(_ kind: MoodKind) -> [Double] {
    switch kind {
    case .frustrated: return [14, 12, 10, 15, -10]
    case .cautious: return [-14, -12, -12, -16, 5]
    case .confident: return [8, 10, 5, 8, -5]
    case .reactive: return [5, 16, 14, 4, -8]
    case .steady: return [0, 0, 0, 0, 0]
    }
}

public func effectiveBotAxes(_ profile: BotProfile, _ mood: BotMood?, _ mode: EmotionMode) -> [Double] {
    let strength: Double = mode == .off ? 0 : mode == .lively ? 1 : 0.5
    let offsets = mood.map { moodOffsets($0.kind) } ?? [0, 0, 0, 0, 0]
    return profile.axes.enumerated().map { i, v in max(0, min(100, Double(v) + offsets[i] * strength)) }
}

/// An opponent as the bot may see it: public stack, bet and all-in state only.
public struct BotOpponent: Equatable, Sendable {
    public var id: Int
    public var stack: Int
    public var bet: Int
    public var allin: Bool
    public init(id: Int, stack: Int, bet: Int, allin: Bool) {
        self.id = id
        self.stack = stack
        self.bet = bet
        self.allin = allin
    }
}

/// The white-listed actor view. No other hole cards, future deck, review
/// decisions or eventual winners can enter the bot policy.
public struct BotView: Equatable, Sendable {
    public var id: Int
    public var hole: [Card]
    public var board: [Card] = []
    public var street = 0
    public var position = "BTN"
    public var count = 6
    /// `nil` when unknown; timing then falls back to the position list.
    public var inPosition: Bool? = nil
    public var stack = STARTING_STACK
    public var bet = 0
    public var pot = 0
    public var currentBet = 0
    public var difficulty: Difficulty = .normal
    public var legal: LegalActions
    public var rivals = 1
    /// `nil` is the reference's absent `opponents`.
    public var opponents: [BotOpponent]? = []
    public var equity = 0.0
    public var equityTrials = 0
    public var contestable = 0
    public var history: [HistoryEntry] = []
    public var features = BoardFeatures()
    public var playsBoard = false

    public init(id: Int, hole: [Card], legal: LegalActions) {
        self.id = id
        self.hole = hole
        self.legal = legal
    }
}

public struct RollCheck: Equatable, Sendable {
    public var code: String
    public var value: Double
    public var threshold: Double
    public var selected: Bool
}

public struct EntryContext: Equatable, Sendable {
    public var limpers = 0
    public var openCallers = 0
    public var effectiveBehind = 0
    public var speculative = false
    public var suitedHigh = false
}

public struct BotSizing: Equatable, Sendable {
    public var fraction: Double
    public var desired: Int
    public var actual: Int
    public var minimum: Int
    public var maximum: Int
    public var opening: Bool
    public var executed: Bool
}

public struct TraceMood: Equatable, Sendable {
    public var kind: MoodKind = .steady
    public var reason = ""
}

/// The private record of why a bot chose an action. Never graded or shown during play.
public struct BotTrace: Equatable, Sendable {
    public var reason = ""
    public var profile = "balanced"
    public var profileName = ""
    public var mode: EmotionMode = .off
    public var mood = TraceMood()
    public var axes: [Double] = [50, 50, 40, 50, 20]
    public var baseAxes: [Int] = []
    public var equityModel = "random-opponents"
    public var trials = 0
    public var rawEquity = 0.0
    public var noise = 0.0
    public var equity = 0.0
    public var odds = 0.0
    public var pressure = 0.0
    public var percentile = 0.0
    public var range = 0.0
    public var openingRange = 0.0
    public var raiseRange = 0.0
    public var cheapEntry = false
    public var cheapRangePassed = false
    public var affordableOpen = false
    public var affordableRangePassed = false
    public var entryContext = EntryContext()
    public var premium = false
    public var admitted = false
    public var callTolerance = 0.0
    public var checks: [RollCheck] = []
    public var exceptions: [String] = []
    public var sizing: BotSizing? = nil
    public var value = false
    public var semiBluff = false
    public var pureBluff = false
    public var draw = false
    public var playsBoard = false
    /// Added by `botDecision`.
    public var view: BotView? = nil
    /// Added to the private execution record by `executeBotTurn`.
    public var thinking: BotThinkingRecord? = nil

    public init() {}
}

/// `amount` is present only for a raise (the raise-to total).
public struct BotDecision: Equatable, Sendable {
    public var action: PokerAction
    public var amount: Int?
    public var trace: BotTrace
    public init(action: PokerAction, amount: Int? = nil, trace: BotTrace) {
        self.action = action
        self.amount = amount
        self.trace = trace
    }
}

// No complete game object is accepted: the caller supplies a white-listed view.
public func chooseBotAction(_ view: BotView, _ profile: BotProfile, _ mood: BotMood?, _ mode: EmotionMode,
                            random: RandomSource = SystemRandom.shared) throws -> BotDecision {
    let legal = view.legal
    guard legal.enabled else { throw PokerError(.botCannotAct) }
    let axes = effectiveBotAxes(profile, mood, mode)
    let width = axes[0] / 100, attack = axes[1] / 100, bluff = axes[2] / 100
    let callDown = axes[3] / 100, trap = axes[4] / 100
    var checks: [RollCheck] = []
    var exceptions: [String] = []
    func roll(_ code: String, _ threshold: Double) -> Double {
        let value = random.next()
        let inclusive = code == "outside-range" || code == "insufficient-equity" || code == "stack-pressure"
        checks.append(RollCheck(code: code, value: value, threshold: threshold,
                                selected: inclusive ? value <= threshold : value < threshold))
        return value
    }
    let percentile = startingPercentile(view.hole)
    let odds = Double(legal.callAmount) / Double(max(1, view.contestable))
    let pressure = Double(legal.toCall) / Double(max(1, view.stack + view.bet))
    let noise = (random.next() - 0.5) *
        (view.difficulty == .easy ? 0.16 : view.difficulty == .hard ? 0.04 : 0.08)
    let equity = max(0, min(1, view.equity + noise))
    let positionScale: Double
    switch view.position {
    case "BTN": positionScale = 1.35
    case "CO": positionScale = 1.18
    case "SB", "BB": positionScale = 1.05
    case "HJ": positionScale = 0.95
    default: positionScale = 0.75
    }
    let raises = view.history.filter { $0.street == view.street && $0.action == .raise }
    let baseRange = (0.16 + width * 0.42) * positionScale * (view.count >= 8 ? 0.9 : 1)
    var range = baseRange
    if !raises.isEmpty { range *= raises.count == 1 ? 0.68 : 0.42 }
    if view.position == "BB" && legal.toCall <= 50 { range += 0.1 }
    let openingRange = range
    let preflopHistory = view.history.filter { $0.street == 0 }
    let firstOpen = preflopHistory.firstIndex { $0.action == .raise }
    let opener = firstOpen.map { preflopHistory[$0].id }
    func callers(_ history: ArraySlice<HistoryEntry>) -> Int {
        Set(history.filter { a in
            a.action == .call && a.amount > 0 && a.id != view.id && a.id != opener &&
                (view.opponents?.contains { $0.id == a.id } ?? false)
        }.map(\.id)).count
    }
    let limpers = callers(preflopHistory[0..<(firstOpen ?? preflopHistory.count)])
    let openCallers = firstOpen.map { callers(preflopHistory[($0 + 1)...]) } ?? 0
    let high = max(view.hole[0].rank, view.hole[1].rank), low = min(view.hole[0].rank, view.hole[1].rank)
    let suited = view.hole[0].suit == view.hole[1].suit
    let pair = high == low
    let speculative = pair || (suited && (high == 14 || (high - low <= 2 && low >= 5)))
    let suitedHigh = suited && high >= 11 && low >= 7
    let lastRaiserId = raises.last?.id
    let lastRaiser = lastRaiserId.flatMap { id in view.opponents?.first { $0.id == id } }
    let effectiveBehind = max(0, min(view.stack - legal.callAmount, lastRaiser?.stack ?? 0))
    let lowCommitment = pressure <= 0.08 && legal.callAmount < view.stack
    let allInPressure = view.opponents?.contains { $0.allin } ?? false
    let cheapEntry = view.street == 0 && raises.isEmpty && view.currentBet <= 50 && legal.toCall <= 50 &&
        lowCommitment && !allInPressure
    // Small single opens are a different price from 3-bets and shoves. This
    // bounded calling branch does not compare an all-players showdown estimate
    // with today's price before anyone behind has actually entered the pot.
    let affordableOpen = view.street == 0 && lastRaiser != nil && raises.count == 1 && raises[0].id != view.id &&
        legal.toCall > 0 && view.currentBet <= 200 && legal.callAmount <= 200 && lowCommitment &&
        !allInPressure && effectiveBehind >= max(1000, legal.callAmount * 15)
    if cheapEntry {
        range += 0.14 + width * 0.2 + (speculative || suitedHigh ? Double(min(2, limpers)) * 0.04 : 0)
    }
    if affordableOpen {
        let priceScale = max(0.65, 1.1 - (Double(view.currentBet) / 50) * 0.08)
        let playability = speculative ? 0.09 : suitedHigh ? 0.07 : 0
        let callerBonus = speculative || suitedHigh ? Double(min(2, openCallers)) * 0.04 : 0
        let blindDiscount = view.position == "BB" ? 0.08 : 0
        let dominatedAce = !suited && high == 14 && low <= 8 ? 0.08 : 0
        var r = baseRange * priceScale
        r += 0.12
        r += width * 0.18
        r += playability
        r += callerBonus
        r += blindDiscount
        r -= dominatedAce
        range = r
    }
    range = min(0.95, range)
    // Entering a pot is not automatically a reason to raise again. Separate the
    // value re-raising candidates so ordinary calls do not start a raise cascade.
    let raiseRange = raises.isEmpty ? openingRange : min(
        openingRange,
        (0.035 + width * 0.085) * (raises.count == 1 ? 1 : 0.58) *
            (view.position == "BTN" || view.position == "CO" ? 1.15 : 1)
    )
    let premium = percentile < 0.07
    let admitted = percentile <= range
    let affordableRangePassed = (cheapEntry || affordableOpen) && admitted
    let callTolerance = (callDown - 0.5) * 0.1
    var sizing: BotSizing? = nil
    var value = false, semiBluff = false, pureBluff = false

    func finish(_ action: PokerAction, _ reason: String, _ amount: Int? = nil) -> BotDecision {
        var t = BotTrace()
        t.reason = reason
        t.profile = profile.id
        t.profileName = profile.name
        t.mode = mode
        t.mood = TraceMood(kind: mood?.kind ?? .steady, reason: mood?.reason ?? "")
        t.axes = axes
        t.baseAxes = profile.axes
        t.trials = view.equityTrials != 0 ? view.equityTrials : view.difficulty == .hard ? 52 : 28
        t.rawEquity = view.equity
        t.noise = noise
        t.equity = equity
        t.odds = odds
        t.pressure = pressure
        t.percentile = percentile
        t.range = range
        t.openingRange = openingRange
        t.raiseRange = raiseRange
        t.cheapEntry = cheapEntry
        t.cheapRangePassed = cheapEntry && admitted
        t.affordableOpen = affordableOpen
        t.affordableRangePassed = affordableRangePassed
        t.entryContext = EntryContext(limpers: limpers, openCallers: openCallers, effectiveBehind: effectiveBehind,
                                      speculative: speculative, suitedHigh: suitedHigh)
        t.premium = premium
        t.admitted = admitted
        t.callTolerance = callTolerance
        t.checks = checks
        t.exceptions = exceptions
        t.sizing = sizing
        t.value = value
        t.semiBluff = semiBluff
        t.pureBluff = pureBluff
        t.draw = view.features.draw
        t.playsBoard = view.playsBoard
        return BotDecision(action: action, amount: amount, trace: t)
    }
    func passive() -> BotDecision {
        let reason: String
        if legal.canCheck { reason = "free-check" }
        else if !exceptions.isEmpty { reason = "loose-exception" }
        else if cheapEntry && admitted { reason = "affordable-entry" }
        else if affordableOpen && admitted { reason = "affordable-open" }
        else if premium && view.street == 0 { reason = "premium-continue" }
        else { reason = "price-continue" }
        return finish(legal.canCheck ? .check : .call, reason)
    }

    if legal.toCall > 0 {
        if view.street == 0 && !admitted && !premium && odds > 0.09 {
            let t = 0.06 * width
            if roll("outside-range", t) > t { return finish(.fold, "outside-range") }
            exceptions.append("outside-range")
        }
        if (!premium || view.street > 0) && !affordableRangePassed {
            if equity + callTolerance < odds + 0.02 {
                let t = 0.03 + callDown * 0.1
                if roll("insufficient-equity", t) > t { return finish(.fold, "insufficient-equity") }
                exceptions.append("insufficient-equity")
            }
            if pressure > 0.4 && equity + callTolerance < (view.street == 0 ? 0.38 : 0.32) {
                let t = 0.03 + callDown * 0.07
                if roll("stack-pressure", t) > t { return finish(.fold, "stack-pressure") }
                exceptions.append("stack-pressure")
            }
        }
    }
    if !legal.canRaise { return passive() }
    let headsUp = view.rivals == 1
    let features = view.features
    let ownLastRaise = view.history.last { $0.action == .raise }?.id == view.id
    if view.street > 0 && features.draw && view.rivals <= 2 {
        let t = (0.12 + bluff * 0.42) * (headsUp ? 1 : 0.45)
        semiBluff = roll("semi-bluff", t) < t
    }
    let story = view.street == 0 ? (view.position == "BTN" || view.position == "CO") : (ownLastRaise || !features.wet)
    if !view.playsBoard && view.rivals <= 2 && story && pressure < 0.25 {
        let t = (0.015 + bluff * 0.17) * (headsUp ? 1 : 0.2)
        pureBluff = roll("pure-bluff", t) < t
    }
    if view.street == 0 {
        value = premium || percentile <= raiseRange
    } else {
        value = !view.playsBoard &&
            (equity > (headsUp ? 0.53 : 1 / Double(view.rivals + 1) + 0.23) || (features.overpair && equity > 0.4))
    }
    if value && view.street > 0 && legal.canCheck && !features.wet && equity > 0.65 &&
        roll("trap", trap * 0.52) < trap * 0.52 {
        return finish(.check, "trap")
    }
    if (value || semiBluff || pureBluff) && roll("attack", 0.2 + attack * 0.72) < 0.2 + attack * 0.72 {
        var fraction = profile.sizing[0] + random.next() * (profile.sizing[1] - profile.sizing[0])
        if profile.id == "abao" && view.street == 1 && ownLastRaise { fraction = 0.33 }
        if profile.id == "abao" && view.street == 2 && semiBluff { fraction = 0.9 }
        if mode != .off, let kind = mood?.kind, [.frustrated, .confident, .reactive].contains(kind) {
            fraction *= mode == .lively ? 1.2 : 1.1
        }
        var desired = view.currentBet +
            Int(jsRound(max(50, Double(view.pot + legal.callAmount) * fraction) / 25)) * 25
        let opening = view.street == 0 && raises.isEmpty
        if opening {
            desired = 125 + (attack > 0.8 ? 25 : 0) +
                view.history.filter { $0.street == 0 && $0.action == .call }.count * 50
        }
        if view.street == 0 && profile.id == "peter" && view.hole[0].rank == view.hole[1].rank &&
            view.hole[0].rank <= 6 && admitted && headsUp && roll("rare-pocket-shove", 0.04) < 0.04 {
            desired = legal.maxRaiseTo
        }
        let amount = max(legal.minRaiseTo, min(legal.maxRaiseTo, desired))
        sizing = BotSizing(fraction: fraction, desired: desired, actual: amount, minimum: legal.minRaiseTo,
                           maximum: legal.maxRaiseTo, opening: opening, executed: false)
        if amount != legal.maxRaiseTo || value || semiBluff || view.stack <= 500 {
            sizing?.executed = true
            return finish(.raise, value ? "value-raise" : semiBluff ? "semi-bluff" : "pure-bluff", amount)
        }
    }
    return passive()
}
