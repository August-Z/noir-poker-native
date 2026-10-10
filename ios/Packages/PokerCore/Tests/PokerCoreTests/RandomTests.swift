import XCTest
@testable import PokerCore

final class RandomTests: XCTestCase {
    func testSeededRandomMatchesReferenceStream() throws {
        let fixture = try loadFixture("rng.json")
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let seed = fixtureInt(c["seed"])
            let values = (c["values"] as! [Any]).map(fixtureDouble)
            let rng = SeededRandom(seed: seed)
            XCTAssertEqual(values.map { _ in rng.next() }, values, "seed \(seed)")
        }
        print("rng.json: \(cases.count) seeds checked")
    }

    func testSeedIsReducedModulo2To32() {
        let a = SeededRandom(seed: -1), b = SeededRandom(UInt32.max)
        XCTAssertEqual(a.next(), b.next())
    }

    func testJavaScriptRoundingAndGrouping() {
        XCTAssertEqual(jsRound(2.5), 3)
        XCTAssertEqual(jsRound(-2.5), -2)
        XCTAssertEqual(jsRound(1234.5), 1235)
        XCTAssertEqual(formatChips(1800), "1,800")
        XCTAssertEqual(formatChips(1_234_567), "1,234,567")
        XCTAssertEqual(formatChips(999), "999")
        XCTAssertEqual(formatChips(1234.5), "1,235")
    }
}
