import XCTest
@testable import PokerCore

final class CardTests: XCTestCase {
    func testDeckMatchesReferenceOrderingAndHas52DistinctCards() {
        let deck = Card.fullDeck()
        XCTAssertEqual(Set(deck.map(\.key)).count, 52)
        XCTAssertEqual(deck.first, Card(rank: 2, suit: 0))
        XCTAssertEqual(deck.last, Card(rank: 14, suit: 3))
    }
    func testStandardPokerRanksAreEnglish() {
        XCTAssertEqual(Card(rank: 14, suit: 0).rankText, "A")
        XCTAssertEqual(Card(rank: 10, suit: 1).rankText, "10")
    }
}
