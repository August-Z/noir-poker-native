// Port of src/review/context.js: starting-hand tiers, direct draws, board
// texture and the hero's decision context. Public information only.

/// Starting-hand tier 0 (weak) … 3 (premium).
public func startingTier(_ hole: [Card]) -> Int {
    guard hole.count == 2 else { return 0 }
    let high = max(hole[0].rank, hole[1].rank), low = min(hole[0].rank, hole[1].rank)
    let suited = hole[0].suit == hole[1].suit, gap = high - low
    if (high == low && high >= 11) || (high == 14 && low == 13) { return 3 }
    if (high == low && high >= 8) || (high == 14 && low >= 10) || (suited && high >= 12 && low >= 10) { return 2 }
    if high == low || (suited && high == 14) || (high >= 11 && low >= 10) || (suited && gap <= 2 && low >= 5) ||
        (high == 14 && low >= 8) {
        return 1
    }
    return 0
}

/// Direct straight / flush completion cards. They are not guaranteed winning outs.
public struct DrawInfo: Equatable, Sendable {
    public var flush = false
    public var straight = false
    public var flushOuts = 0
    public var straightOuts = 0
    public var outs = 0
    public var nextChance = 0.0
    public init() {}
}

// Completion cards are not guaranteed winning outs. Public information only.
public func drawInfo(_ hole: [Card], _ board: [Card]) -> DrawInfo {
    guard board.count >= 3, board.count < 5 else { return DrawInfo() }
    let known = hole + board
    let keys = Set(known.map(\.key)), holeKeys = Set(hole.map(\.key))
    let made = evaluate(known)
    var flush: [String] = [], straight: [String] = []
    for c in deckOfCards() where !keys.contains(c.key) {
        let next = evaluate(known + [c])
        if compare(next.score, made.score) <= 0 || !next.cards.contains(where: { holeKeys.contains($0.key) }) { continue }
        if made.score[0] < 5 && [5, 8].contains(next.score[0]) { flush.append(c.key) }
        if made.score[0] < 4 && [4, 8].contains(next.score[0]) { straight.append(c.key) }
    }
    let outs = Set(flush + straight).count
    var d = DrawInfo()
    d.flush = !flush.isEmpty
    d.straight = !straight.isEmpty
    d.flushOuts = flush.count
    d.straightOuts = straight.count
    d.outs = outs
    d.nextChance = Double(outs) / Double(52 - keys.count)
    return d
}

/// Board texture tags, in the order the reference pushes them.
public enum TextureTag: String, Sendable, CaseIterable {
    case trips, paired, fourFlush, threeFlush, twoTone, fourConnected, threeConnected

    /// Lower-case catalog phrase.
    public var phrase: String { ReviewCopy.textureTag(self) }
}

public struct BoardTexture: Equatable, Sendable {
    public var paired: Bool
    public var trips: Bool
    public var maxSuit: Int
    public var connected: Int
    public var wet: Bool
    public var tags: [TextureTag]

    /// Mid-sentence description, e.g. `"paired, three to a flush"`.
    public var phrase: String {
        tags.isEmpty ? ReviewCopy.textureDry : tags.map(\.phrase).joined(separator: ", ")
    }

    /// Standalone form (the reference `label`): `"Paired, three to a flush"`.
    public var label: String { ReviewFormat.cap(phrase) }
}

public func boardTexture(_ board: [Card]) -> BoardTexture {
    let suits = (0..<4).map { s in board.filter { $0.suit == s }.count }
    var counts: [Int: Int] = [:]
    for c in board { counts[c.rank, default: 0] += 1 }
    var ranks = Set(board.map(\.rank))
    if ranks.contains(14) { ranks.insert(1) }
    let connected = max(0, (0..<10).map { i in (1...5).filter { ranks.contains(i + $0) }.count }.max() ?? 0)
    let maxSuit = max(0, suits.max() ?? 0)
    let paired = counts.values.contains { $0 >= 2 }, trips = counts.values.contains { $0 >= 3 }
    var tags: [TextureTag] = []
    if paired { tags.append(trips ? .trips : .paired) }
    if maxSuit >= 4 { tags.append(.fourFlush) }
    else if maxSuit == 3 { tags.append(.threeFlush) }
    else if board.count == 3 && maxSuit == 2 { tags.append(.twoTone) }
    if connected >= 4 { tags.append(.fourConnected) }
    else if connected == 3 { tags.append(.threeConnected) }
    return BoardTexture(paired: paired, trips: trips, maxSuit: maxSuit, connected: connected,
                        wet: maxSuit >= 3 || connected >= 3 || (board.count == 3 && maxSuit == 2), tags: tags)
}

/// A hero hand description. `phrase` reads mid-sentence (`"two pair"`,
/// `"pocket Nines"`); `label` begins a sentence or stands alone (`"Two Pair"`,
/// `"Pocket Nines"`), and is the reference `handLabel`.
public struct HandLabel: Equatable, Sendable, CustomStringConvertible {
    public var phrase: String
    public var label: String
    public init(phrase: String, label: String? = nil) {
        self.phrase = phrase
        self.label = label ?? ReviewFormat.cap(phrase)
    }
    public var description: String { label }
}

/// The reference `handClass` identifiers.
public enum HandClass: String, Sendable, CaseIterable {
    case high, pocket, unpaired, board, strong, set, trips, overpair
    case twoPair = "two-pair"
    case underpair
    case boardPair = "board-pair"
    case topPair = "top-pair"
    case middlePair = "middle-pair"
}

public struct DecisionContext: Equatable, Sendable {
    public var made: HandEvaluation
    public var texture: BoardTexture
    public var draw: DrawInfo
    /// Non-folded opponents, all-in ones included.
    public var opponents: Int
    public var handClass: HandClass
    public var handLabel: HandLabel
    public var inPosition: Bool
    public var pendingOthers: Int
    public var effective: Int
    public var spr: Double
    public var extra: Int
    public var betRatio: Double
    public var preflopRaises: Int
    /// The latest raise on this street, if any.
    public var facingRaise: HistoryEntry?
    public var pastCalls: Int
    public var pastCallActions: Int
    public var nutFlushBlocker: Bool
    public var missedDraw: Bool
    public var tier: Int
}

let ACTION_ORDER = ["SB", "BB", "UTG", "UTG+1", "MP", "LJ", "HJ", "CO", "BTN"]

public func decisionContext(_ s: ReviewDecision) -> DecisionContext {
    let made = evaluate(s.hole + s.board)
    let texture = boardTexture(s.board), draw = drawInfo(s.hole, s.board)
    let opponents = s.players.filter { $0.id != 0 && !$0.folded }
    let high = max(0, s.board.map(\.rank).max() ?? 0)
    let pocket = s.hole.count == 2 && s.hole[0].rank == s.hole[1].rank
    let holeRank = s.hole.first?.rank ?? 0
    let playsBoard = s.board.count == 5 && compare(made.score, evaluate(s.board).score) == 0
    let engineLabel = ReviewCopy.engineHand(made.label)
    var handClass = HandClass.high
    var handLabel = engineLabel
    if s.street == 0 {
        handClass = pocket ? .pocket : .unpaired
        handLabel = pocket
            ? ReviewCopy.pocket(holeRank)
            : ReviewCopy.unpaired(s.hole.map(\.rank), suited: s.hole.count == 2 && s.hole[0].suit == s.hole[1].suit)
    } else if playsBoard {
        handClass = .board
        handLabel = ReviewCopy.playsBoard
    } else if made.score[0] >= 4 {
        handClass = .strong
    } else if pocket && made.score[0] == 3 {
        handClass = .set
        handLabel = ReviewCopy.set(holeRank)
    } else if made.score[0] == 3 {
        handClass = .trips
    } else if pocket && holeRank > high {
        handClass = .overpair
        handLabel = ReviewCopy.overpair(holeRank, pairedBoard: texture.paired)
    } else if made.score[0] == 2 {
        handClass = .twoPair
    } else if made.score[0] == 1 {
        if pocket {
            handClass = .underpair
            handLabel = ReviewCopy.underpair(holeRank)
        } else {
            let paired = s.hole.first { c in s.board.contains { $0.rank == c.rank } }
            if let paired {
                let kicker = s.hole.first { $0 != paired }
                handClass = paired.rank == high ? .topPair : .middlePair
                handLabel = ReviewCopy.pair(top: handClass == .topPair, rank: made.score[1],
                                            kicker: kicker?.rank ?? made.score[2])
            } else {
                handClass = .boardPair
                handLabel = ReviewCopy.boardPair(made.score[1])
            }
        }
    }
    let heroOrder = ACTION_ORDER.firstIndex(of: s.position) ?? -1
    let inPosition = opponents.allSatisfy { (ACTION_ORDER.firstIndex(of: $0.position) ?? -1) < heroOrder }
    let pendingOthers = s.pending.filter { id in
        id != 0 && !(s.seat(id)?.folded ?? false) && !(s.seat(id)?.allin ?? false)
    }.count
    let effective = min(s.stack, max(0, opponents.map(\.stack).max() ?? 0))
    let spr = s.pot != 0 ? Double(effective) / Double(s.pot) : 0
    let extra = s.action == .raise ? s.amount - s.bet : s.action == .call ? s.legal.callAmount : 0
    let raises = s.history.filter { $0.action == .raise }
    let heroEarlierCalls = s.history.filter { $0.id == 0 && $0.action == .call && $0.street < s.street }
    var flushSuit: Int? = nil
    if texture.maxSuit >= 3 {
        flushSuit = (0..<4).first { suit in s.board.filter { $0.suit == suit }.count >= 3 }
    }
    let nutFlushBlocker = flushSuit.map { suit in s.hole.contains { $0.suit == suit && $0.rank == 14 } } ?? false
    let previousDraw = s.street == 3 ? drawInfo(s.hole, Array(s.board.prefix(4))) : nil
    return DecisionContext(
        made: made, texture: texture, draw: draw, opponents: opponents.count, handClass: handClass,
        handLabel: handLabel, inPosition: inPosition, pendingOthers: pendingOthers, effective: effective, spr: spr,
        extra: extra, betRatio: s.pot != 0 ? Double(extra) / Double(s.pot) : 0,
        preflopRaises: raises.filter { $0.street == 0 }.count,
        facingRaise: raises.last { $0.street == s.street },
        pastCalls: Set(heroEarlierCalls.map(\.street)).count,
        pastCallActions: heroEarlierCalls.count,
        nutFlushBlocker: nutFlushBlocker,
        missedDraw: (previousDraw?.outs ?? 0) != 0 && made.score[0] < 4,
        tier: startingTier(s.hole))
}
