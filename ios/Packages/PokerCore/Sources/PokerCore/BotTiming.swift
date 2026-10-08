// Synthetic table pacing, not measured timings or tells of named players.
// Accept only the actor's decision view; no full game, hidden rival cards or deck.

private func clamp(_ n: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { max(lo, min(hi, n)) }

public enum BOT_THINK_LIMITS {
    public static let minimum = 1200
    public static let maximum = 8000
}

public enum Acting: String, Codable, Sendable {
    case deliberate, quick, neutral
}

public struct ThinkingFactors: Equatable, Sendable {
    public var closeness: Double
    public var texture: Double
    public var route: Double
    public var position: Double
    public var commitment: Double
    public var sizing: Double
    public var effectiveStack: Int
    public var spr: Double
}

public struct BotThinking: Equatable, Sendable {
    public var durationMs: Int
    public var model: String
    public var acting: Acting
    public var factors: ThinkingFactors
}

/// Thinking time as written to the private execution record.
public struct BotThinkingRecord: Equatable, Sendable {
    public var durationMs: Int
    public var model: String
    public var acting: Acting
    public var factors: ThinkingFactors
    public var expedited: Bool
    public var waitedMs: Int
}

private func moodTempo(_ kind: MoodKind) -> Double {
    switch kind {
    case .cautious: return 450
    case .frustrated: return -300
    case .reactive: return -220
    case .confident: return -140
    case .steady: return 0
    }
}

private let outOfPositionRoles: Set<String> = ["SB", "BB", "UTG", "UTG+1", "MP", "LJ"]

/// Consumes 4 random values, or 5 when the acting style is deliberate.
/// `decision.trace.view` must be present (as `botDecision` returns it).
public func botThinkingTime(_ decision: BotDecision, random: RandomSource = SystemRandom.shared) -> BotThinking {
    let t = decision.trace
    guard let v = t.view else { preconditionFailure("botThinkingTime needs the decision view") }
    let legal = v.legal
    let draw = v.features.draw
    let raises = v.history.filter { $0.action == .raise }
    let streetRaises = raises.filter { $0.street == v.street }
    let lastRaiser = raises.last?.id
    func roll() -> Double { clamp(random.next()) }
    let priceCloseness = legal.toCall > 0 && !(v.street == 0 && t.affordableRangePassed)
        ? clamp(1 - abs(t.equity + t.callTolerance - t.odds - 0.02) / 0.16)
        : 0
    let rangeCloseness = v.street == 0 ? clamp(1 - abs(t.percentile - t.range) / 0.15) : 0
    let closeness = max(priceCloseness, rangeCloseness)
    let suits = (0...3).map { s in v.board.filter { $0.suit == s }.count }
    let paired = Set(v.board.map(\.rank)).count < v.board.count
    var textureSum = v.features.wet ? 0.45 : 0
    textureSum += draw ? 0.35 : 0
    textureSum += paired ? 0.15 : 0
    textureSum += max(0, suits.max()!) >= 4 ? 0.35 : 0
    textureSum += v.features.overpair && v.features.wet ? 0.2 : 0
    let texture = clamp(textureSum)
    let aggressionStreets = Set(raises.filter { $0.id != v.id }.map(\.street)).count
    let lastAction = v.history.last
    let checkRaise = lastAction?.action == .raise &&
        v.history.contains { $0.id == lastAction!.id && $0.street == v.street && $0.action == .check }
    var routeSum = Double(streetRaises.count) * 0.22
    routeSum += Double(max(0, aggressionStreets - 1)) * 0.2
    routeSum += checkRaise ? 0.25 : 0
    routeSum += streetRaises.contains { $0.id == v.id } && legal.toCall > 0 ? 0.2 : 0
    let route = clamp(routeSum)
    let outOfPosition: Bool
    if v.street > 0, let inPosition = v.inPosition { outOfPosition = !inPosition }
    else { outOfPosition = outOfPositionRoles.contains(v.position) }
    let position = clamp((outOfPosition ? 0.3 : 0) + Double(max(0, v.rivals - 1)) * 0.12)
    let callRisk = Double(legal.callAmount) / Double(max(1, v.stack))
    let raiseRisk = decision.action == .raise ? Double((decision.amount ?? 0) - v.bet) / Double(max(1, v.stack)) : 0
    let remaining = max(0, v.stack - legal.callAmount)
    // Exclude all-in rivals from remaining-stack planning, while they still count
    // in multiway complexity. A short all-in must not collapse all other SPRs.
    let opponents = v.opponents ?? []
    let liveStacks = opponents.filter { !$0.allin && $0.stack > 0 }.map { min(remaining, $0.stack) }
    let facingStack = opponents.first { $0.id == lastRaiser && !$0.allin && $0.stack > 0 }?.stack
    let effective = min(remaining, facingStack ?? max(0, liveStacks.max() ?? 0))
    let spr = Double(effective) / Double(max(50, v.contestable))
    var commitmentSum = max(callRisk, raiseRisk) * 0.7
    commitmentSum += legal.toCall > 0 && spr < 2 ? 0.25 : 0
    commitmentSum += v.street > 0 && spr > 6 ? 0.2 : 0
    commitmentSum += v.stack <= 500 && legal.toCall > 0 ? 0.15 : 0
    let commitment = clamp(commitmentSum)
    let sizing = decision.action == .raise
        ? clamp(Double((decision.amount ?? 0) - v.currentBet) / Double(max(50, v.pot + legal.callAmount)))
        : 0
    let routine = (decision.action == .fold && t.reason == "outside-range" && rangeCloseness < 0.15) ||
        (decision.action == .check && t.reason == "free-check" && !draw && !v.features.wet)
    let width = t.axes[0] / 100, attack = t.axes[1] / 100, bluff = t.axes[2] / 100, trap = t.axes[4] / 100
    var styleTempo = 1 + (0.5 - attack) * 0.18
    styleTempo += trap * 0.08
    styleTempo += Double((v.id % 5) - 2) * 0.04
    let moodStrength: Double = t.mode == .off ? 0 : t.mode == .lively ? 1 : 0.5
    let mood = moodTempo(t.mood.kind) * moodStrength * (0.5 + roll())
    // Acting is sampled for every hand strength and action. Never equate a long
    // pause with a bluff, or a quick action with strength.
    var actingChance = 0.12 + trap * 0.12
    actingChance += bluff * 0.06
    actingChance += width * 0.02
    let actingRoll = roll()
    let acting: Acting = actingRoll < actingChance ? .deliberate : actingRoll > 0.91 ? .quick : .neutral
    let actingMs: Double
    switch acting {
    case .deliberate: actingMs = 400 + roll() * 1400
    case .quick: actingMs = -600
    case .neutral: actingMs = 0
    }
    var base = 1300 + roll() * 1100
    base += roll() * 700
    var complexity = closeness * 1400
    complexity += texture * 750
    complexity += route * 1050
    complexity += position * 550
    complexity += commitment * 1050
    complexity += sizing * 400
    complexity += v.street >= 2 ? 350 : v.street == 1 ? 150 : 0
    let durationMs = Int(jsRound(clamp(
        (base + complexity - (routine ? 450 : 0)) * styleTempo + mood + actingMs,
        Double(BOT_THINK_LIMITS.minimum),
        Double(BOT_THINK_LIMITS.maximum)
    )))
    return BotThinking(
        durationMs: durationMs,
        model: "context-pacing-v1",
        acting: acting,
        factors: ThinkingFactors(closeness: closeness, texture: texture, route: route, position: position,
                                 commitment: commitment, sizing: sizing, effectiveStack: effective, spr: spr)
    )
}
