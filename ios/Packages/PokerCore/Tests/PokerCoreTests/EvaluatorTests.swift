import XCTest
@testable import PokerCore

final class EvaluatorTests: XCTestCase {
    func testCategories() {
        let cases: [(String, Int)] = [
            ("As Ks Qs Js Ts 2h 3c", 8), ("Ac Ah As Ad Kh 2s 3s", 7), ("Ac Ah As Kd Kh Qs Qh", 6),
            ("As Js 9s 5s 3s Kh Qh", 5), ("As 2h 3c 4d 5s Kh Qh", 4), ("As Ah Ac 9d 8s 2h 3h", 3),
            ("As Ah Kc Kd Qs 2h 3h", 2), ("As Ah Kc Qd 9s 2h 3h", 1), ("As Kh Qc Jd 9s 2h 3h", 0),
        ]
        for (input, category) in cases { XCTAssertEqual(evaluate(cards(input)).score[0], category, input) }
        XCTAssertEqual(evaluate(cards("As Ks Qs Js Ts 2h 3c")).label, "Royal Flush")
        XCTAssertEqual(evaluate(cards("9s Ks Qs Js Ts 2h 3c")).label, "Straight Flush")
        XCTAssertEqual(evaluate(cards("Ac Ah As Kd Kh Qs Qh")).label, "Full House")
    }

    func testWheelLosesToSixHigh() {
        XCTAssertEqual(compare(evaluate(cards("As 2h 3c 4d 5s")).score, evaluate(cards("2s 3h 4c 5d 6s")).score), -1)
        XCTAssertEqual(evaluate(cards("As 2h 3c 4d 5s")).score, [4, 5])
    }

    func testBestFullHouseFromTwoTrips() {
        XCTAssertEqual(evaluate(cards("As Ah Ac Ks Kh Kc 2s")).score, [6, 14, 13])
    }

    func testKickerDecides() {
        XCTAssertEqual(compare(evaluate(cards("As Ah Kc Qd 9s")).score, evaluate(cards("Ad Ac Kd Jh 9h")).score), 1)
    }

    func testShortHandsAndCompareMissingPositions() {
        XCTAssertEqual(evaluate(cards("Qs Qh")).score, [1, 12, 12])
        XCTAssertEqual(evaluate(cards("Qs Qh")).label, "Pocket Pair")
        XCTAssertEqual(evaluate(cards("Ks 2h")).label, "High Card")
        XCTAssertEqual(compare([1, 2], [1, 2, 0]), 0)
        XCTAssertEqual(compare([1], [1, 1]), -1)
    }

    func testCardKeysAndDeck() {
        XCTAssertEqual(Card(key: "0-14"), Card(rank: 14, suit: 0))
        XCTAssertNil(Card(key: "4-2"))
        XCTAssertEqual(deckOfCards().map(\.key).prefix(2), ["0-2", "0-3"])
        XCTAssertEqual(Card(rank: 10, suit: 1).description, "10♥")
    }

    func testShuffleConsumesOneValuePerSwap() {
        let counter = CountingRandom(SeededRandom(7))
        var deck = deckOfCards()
        shuffle(&deck, random: counter)
        XCTAssertEqual(counter.draws, 51)
        XCTAssertEqual(Set(deck).count, 52)
    }

    func testHandEvalFixture() throws {
        let fixture = try loadFixture("hand-eval.json")
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 300)
        let failuresBefore = testRun?.failureCount ?? 0
        defer {
            let comparisons = (fixture["compare"] as? [Any])?.count ?? 0
            print("hand-eval.json: \(cases.count) cases + \(comparisons) comparisons, failures: \((testRun?.failureCount ?? 0) - failuresBefore)")
        }
        for c in cases {
            let input = (c["cards"] as! [String]).map { Card(key: $0)! }
            let result = evaluate(input)
            XCTAssertEqual(result.score, c["score"] as! [Int], c["name"] as! String)
            XCTAssertEqual(result.label, c["label"] as! String, c["name"] as! String)
            XCTAssertEqual(result.cards.map(\.key), c["bestCardKeys"] as! [String], c["name"] as! String)
        }
        for c in try XCTUnwrap(fixture["compare"] as? [[String: Any]]) {
            XCTAssertEqual(compare(c["a"] as! [Int], c["b"] as! [Int]), c["result"] as! Int)
        }
    }
}
