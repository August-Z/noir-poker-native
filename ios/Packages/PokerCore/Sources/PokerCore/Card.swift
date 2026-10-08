public struct Card: Hashable, Codable, Sendable {
    public let rank: Int
    public let suit: Int
    public init(rank: Int, suit: Int) {
        precondition((2...14).contains(rank) && (0...3).contains(suit))
        self.rank = rank
        self.suit = suit
    }
    public var key: String { "\(suit)-\(rank)" }
    public var symbol: String { ["♠", "♥", "♣", "♦"][suit] }
    public var rankText: String {
        switch rank { case 11: return "J"; case 12: return "Q"; case 13: return "K"; case 14: return "A"; default: return String(rank) }
    }
    public static func fullDeck() -> [Card] {
        (0...3).flatMap { suit in (2...14).map { Card(rank: $0, suit: suit) } }
    }
}
