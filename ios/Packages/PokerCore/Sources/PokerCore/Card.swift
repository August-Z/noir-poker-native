/// Suit symbols by suit index: 0 spades, 1 hearts, 2 clubs, 3 diamonds.
public let SUITS: [String] = ["♠", "♥", "♣", "♦"]

/// A card. `rank` is 2...14 (ace = 14); equality of cards is equality of `key`.
public struct Card: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rank: Int
    public let suit: Int
    public init(rank: Int, suit: Int) {
        precondition((2...14).contains(rank) && (0...3).contains(suit))
        self.rank = rank
        self.suit = suit
    }

    /// Parses the reference key `"{suit}-{rank}"`, for example `"0-14"` (A♠).
    public init?(key: String) {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let suit = Int(parts[0]), let rank = Int(parts[1]),
              (2...14).contains(rank), (0...3).contains(suit) else { return nil }
        self.init(rank: rank, suit: suit)
    }

    public var key: String { "\(suit)-\(rank)" }
    public var symbol: String { SUITS[suit] }
    public var rankText: String { PokerCore.rankText(rank) }
    public var description: String { rankText + symbol }

    public static func fullDeck() -> [Card] { deckOfCards() }
}

public func rankText(_ r: Int) -> String {
    switch r {
    case 11: return "J"
    case 12: return "Q"
    case 13: return "K"
    case 14: return "A"
    default: return String(r)
    }
}

/// Suit-major, rank-ascending order: `0-2 … 0-14, 1-2 … 3-14`.
public func deckOfCards() -> [Card] {
    (0...3).flatMap { suit in (0..<13).map { Card(rank: $0 + 2, suit: suit) } }
}

/// Fisher–Yates in place; consumes exactly `a.count - 1` random values.
@discardableResult
public func shuffle<T>(_ a: inout [T], random: RandomSource = SystemRandom.shared) -> [T] {
    var i = a.count - 1
    while i > 0 {
        let j = Int((random.next() * Double(i + 1)).rounded(.down))
        a.swapAt(i, j)
        i -= 1
    }
    return a
}

/// Parses the compact test notation `"As Kd Tc 2h"`: rank from `23456789TJQKA`,
/// suit from `shcd`.
public func parseCards(_ text: String) -> [Card] {
    let ranks = Array("23456789TJQKA"), suits = Array("shcd")
    return text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map { token in
        let chars = Array(token)
        guard chars.count == 2,
              let r = ranks.firstIndex(of: Character(chars[0].uppercased())),
              let s = suits.firstIndex(of: Character(chars[1].lowercased())) else {
            preconditionFailure("Invalid card: \(token)")
        }
        return Card(rank: r + 2, suit: s)
    }
}

/// Hand category names indexed by `score[0]`.
public var RANK_NAMES: [String] { EngineCopy.rankNames }

/// Lexicographic score comparison; missing positions count as 0.
public func compare(_ a: [Int], _ b: [Int]) -> Int {
    for i in 0..<max(a.count, b.count) {
        let d = (i < a.count ? a[i] : 0) - (i < b.count ? b[i] : 0)
        if d != 0 { return d > 0 ? 1 : -1 }
    }
    return 0
}

public struct HandEvaluation: Equatable, Sendable {
    public let score: [Int]
    public let label: String
    public let cards: [Card]
}

private func evaluateFive(_ cards: [Card]) -> [Int] {
    let ranks = cards.map(\.rank).sorted(by: >)
    var unique: [Int] = []
    for r in ranks where !unique.contains(r) { unique.append(r) }
    let flush = cards.allSatisfy { $0.suit == cards[0].suit }
    var straight = unique.count == 5 && unique[0] - unique[4] == 4 ? unique[0] : 0
    if unique == [14, 5, 4, 3, 2] { straight = 5 }
    let groups = unique.map { r in (r, ranks.filter { $0 == r }.count) }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 > $1.0 }
    if flush && straight != 0 { return [8, straight] }
    if groups[0].1 == 4 { return [7, groups[0].0, groups[1].0] }
    if groups[0].1 == 3 && groups[1].1 == 2 { return [6, groups[0].0, groups[1].0] }
    if flush { return [5] + ranks }
    if straight != 0 { return [4, straight] }
    if groups[0].1 == 3 { return [3, groups[0].0] + groups.dropFirst().map(\.0) }
    if groups[0].1 == 2 && groups[1].1 == 2 {
        return [2, max(groups[0].0, groups[1].0), min(groups[0].0, groups[1].0), groups[2].0]
    }
    if groups[0].1 == 2 { return [1, groups[0].0] + groups.dropFirst().map(\.0) }
    return [0] + ranks
}

/// Best five-card hand. With fewer than five cards (preflop hole cards) the
/// score is `[1, r, r]` for a pocket pair, otherwise `[0, ...ranks]`. Among equal
/// best scores the earliest combination in input order supplies `cards`.
public func evaluate(_ cards: [Card]) -> HandEvaluation {
    if cards.count < 5 {
        let ranks = cards.map(\.rank).sorted(by: >)
        let pair = ranks.count == 2 && ranks[0] == ranks[1]
        return HandEvaluation(score: [pair ? 1 : 0] + ranks,
                              label: pair ? EngineCopy.pocketPair : EngineCopy.rankNames[0],
                              cards: cards)
    }
    var best: [Int]? = nil
    var bestCards: [Card] = []
    let n = cards.count
    for a in 0..<(n - 4) {
        for b in (a + 1)..<(n - 3) {
            for c in (b + 1)..<(n - 2) {
                for d in (c + 1)..<(n - 1) {
                    for e in (d + 1)..<n {
                        let picked = [cards[a], cards[b], cards[c], cards[d], cards[e]]
                        let score = evaluateFive(picked)
                        if best == nil || compare(score, best!) > 0 {
                            best = score
                            bestCards = picked
                        }
                    }
                }
            }
        }
    }
    let score = best!
    return HandEvaluation(score: score,
                          label: score[0] == 8 && score[1] == 14 ? EngineCopy.royalFlush : EngineCopy.rankNames[score[0]],
                          cards: bestCards)
}
