import XCTest
@testable import PokerCore

final class PotTests: XCTestCase {
    static let hands = ["As Ah", "Ks Kh", "Qs Qh", "Js Jh", "Ts Th", "9s 9h"]

    /// The reference `fixture(totals, folded, custom)`: a river spot with committed totals.
    static func fixture(_ totals: [Int], folded: [Int] = [], custom: [String] = hands) throws -> Game {
        let g = try newGame()
        g.phase = .between
        g.street = 3
        g.board = cards("2c 3d 4h 7s 8c")
        for i in g.players.indices {
            let total = i < totals.count ? totals[i] : 0
            g.players[i].total = total
            g.players[i].bet = total
            g.players[i].stack = 5000 - total
            g.players[i].hole = cards(i < custom.count ? custom[i] : hands[i])
            g.players[i].folded = total == 0 || folded.contains(i)
        }
        return g
    }

    func conserve(_ g: Game, _ before: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(chips(g), before, file: file, line: line)
        XCTAssertEqual(g.pots.reduce(0) { $0 + $1.amount } + g.refunds.reduce(0) { $0 + $1.amount }, potSize(g),
                       file: file, line: line)
        for pot in g.pots {
            XCTAssertEqual(pot.awards.reduce(0) { $0 + $1.amount }, pot.amount, file: file, line: line)
            XCTAssertEqual(pot.contributions.reduce(0) { $0 + $1.amount }, pot.amount, file: file, line: line)
            XCTAssertTrue(pot.awards.allSatisfy { pot.eligible.contains($0.id) }, file: file, line: line)
        }
    }

    func testSidePotsAndUncalledReturn() throws {
        let g = try newGame()
        g.board = cards("2c 3d 7s 9h Jc")
        let holes = ["As Ah", "Ks Kh", "Qs Qh"]
        for i in g.players.indices {
            g.players[i].folded = i > 2
            g.players[i].total = [100, 300, 500, 0, 0, 0][i]
            g.players[i].stack = 5000 - g.players[i].total
            g.players[i].hole = cards(i < 3 ? holes[i] : "4s 5h")
        }
        try settle(g, showdown: true)
        XCTAssertEqual(g.payouts, [300, 400, 200, 0, 0, 0])
        XCTAssertEqual(chips(g), 30000)
    }

    func testBoardTieSplitsMainPot() throws {
        let g = try newGame()
        g.board = cards("As Ks Qs Js Ts")
        for i in g.players.indices {
            g.players[i].folded = i > 1
            g.players[i].total = i < 2 ? 101 : 0
            g.players[i].stack = 5000 - g.players[i].total
            g.players[i].hole = cards(i == 0 ? "2h 3h" : "4c 5c")
        }
        try settle(g, showdown: true)
        XCTAssertEqual(g.payouts, [101, 101, 0, 0, 0, 0])
        XCTAssertEqual(g.result, "You win 101 chips · Royal Flush / Mia wins 101 chips · Royal Flush")
    }

    func testOneMainPotAndTwoSidePotsHaveDifferentWinners() throws {
        let g = try Self.fixture([100, 300, 500, 500])
        let preview = try partitionPots(g)
        XCTAssertEqual(preview.pots.map(\.amount), [400, 600, 400])
        XCTAssertEqual(preview.pots.map(\.eligible), [[0, 1, 2, 3], [1, 2, 3], [2, 3]])
        XCTAssertEqual(preview.pots.map(\.label), ["Main Pot", "Side Pot 1", "Side Pot 2"])
        try settle(g)
        XCTAssertEqual(g.payouts, [400, 600, 400, 0, 0, 0])
        XCTAssertEqual(g.pots.map { $0.awards[0].id }, [0, 1, 2])
        XCTAssertTrue(g.result.hasPrefix("Split pots · "))
        XCTAssertTrue(g.logs.contains { $0.text == "Main Pot 400 → You 400" && $0.type == .result })
        conserve(g, 30000)
    }

    func testFiveContestedPotsPlusARefund() throws {
        let g = try Self.fixture([100, 200, 300, 400, 500, 600])
        try settle(g)
        XCTAssertEqual(g.pots.map(\.amount), [600, 500, 400, 300, 200])
        XCTAssertEqual(g.payouts, [600, 500, 400, 300, 200, 100])
        XCTAssertEqual(g.refunds, [Refund(id: 5, amount: 100)])
        XCTAssertFalse(g.winners.contains { $0.id == 5 })
        XCTAssertTrue(g.logs.contains { $0.text == "Uncalled 100 chips returned to Luna" && $0.player == 5 })
        conserve(g, 30000)
    }

    func testFoldedChipsRemainWithoutASpuriousExtraPot() throws {
        let g = try Self.fixture([100, 300, 500, 500, 200], folded: [4])
        try settle(g)
        XCTAssertEqual(g.pots.map(\.amount), [500, 700, 400])
        XCTAssertTrue(g.pots.allSatisfy { !$0.eligible.contains(4) })
        XCTAssertEqual(g.payouts[4], 0)
        XCTAssertEqual(g.pots[1].contributions.first { $0.id == 4 }?.amount, 100)
        conserve(g, 30000)
    }

    func testFoldedContributionsWithoutAllInStayInOnePot() throws {
        let g = try Self.fixture([25, 50, 100, 100], folded: [0, 1])
        XCTAssertEqual(try partitionPots(g).pots.count, 1)
        try settle(g)
        XCTAssertEqual(g.pots[0].amount, 275)
        conserve(g, 30000)
    }

    func testSidePotSplitsIndependently() throws {
        let g = try Self.fixture([100, 300, 500, 500], custom: ["As Ah", "Ks Kh", "Qs Qh", "Qc Qd"])
        try settle(g)
        XCTAssertEqual(g.payouts, [400, 600, 200, 200, 0, 0])
        XCTAssertEqual(g.pots.map(\.awards.count), [1, 1, 2])
        conserve(g, 30000)
    }

    func testOddChipGoesToFirstTiedWinnerLeftOfTheButton() throws {
        for (dealer, expected) in [(0, [400, 202, 201, 0, 0, 0]), (1, [400, 201, 202, 0, 0, 0])] {
            let g = try Self.fixture([100, 301, 301, 101], folded: [3], custom: ["As Ah", "Ks Kh", "Kc Kd"])
            g.dealer = dealer
            try settle(g)
            XCTAssertEqual(g.pots.map(\.amount), [400, 403])
            XCTAssertEqual(g.payouts, expected)
            conserve(g, 30000)
        }
    }

    func testUncalledReturnIsNotAWin() throws {
        let g = try Self.fixture([800, 100, 300, 500], custom: ["Js Jh", "As Ah", "Ks Kh", "Qs Qh"])
        try settle(g)
        XCTAssertEqual(g.pots.map(\.amount), [400, 600, 400])
        XCTAssertEqual(g.refunds, [Refund(id: 0, amount: 300)])
        XCTAssertEqual(g.payouts, [300, 400, 600, 400, 0, 0])
        XCTAssertEqual(g.stats.wins, 0)
        XCTAssertEqual(g.potAtShowdown, 1400)
        conserve(g, 30000)
    }

    func testFourLegalAllInsFormThreePotsBeforeSettlement() throws {
        let g = try Self.fixture([0, 0, 0, 0])
        g.phase = .playing
        g.currentBet = 0
        g.actor = 0
        g.pending = [0, 1, 2, 3]
        for i in g.players.indices {
            g.players[i].folded = i > 3
            g.players[i].allin = false
            g.players[i].total = 0
            g.players[i].bet = 0
            g.players[i].stack = [100, 300, 500, 500, 5000, 5000][i]
            g.players[i].actedTo = nil
        }
        try act(g, 0, .raise, 100)
        try act(g, 1, .raise, 300)
        try act(g, 2, .raise, 500)
        try act(g, 3, .call)
        XCTAssertEqual(g.phase, .between)
        XCTAssertTrue(g.revealed)
        XCTAssertEqual(try partitionPots(g).pots.map(\.amount), [400, 600, 400])
        XCTAssertEqual(currentPots(g).pots.map(\.amount), [400, 600, 400])
        try advanceStreet(g)
        XCTAssertEqual(g.payouts, [400, 600, 400, 0, 0, 0])
        conserve(g, 11400)
    }

    func testShortStackIsExposedOnlyWhenDeepStacksCannotBet() throws {
        let g = try Self.fixture([0, 0, 0])
        g.phase = .playing
        g.street = 1
        g.board = cards("2c 3d 4h")
        g.deck = cards("5s 6s 7s 8s 9s Ts")
        g.currentBet = 0
        g.actor = 0
        g.dealer = 5
        g.pending = [0, 1, 2]
        for i in g.players.indices {
            g.players[i].folded = i > 2
            g.players[i].stack = [100, 300, 500, 5000, 5000, 5000][i]
            g.players[i].bet = 0
            g.players[i].total = 0
            g.players[i].actedTo = nil
        }
        try act(g, 0, .raise, 100)
        try act(g, 1, .call)
        try act(g, 2, .call)
        XCTAssertFalse(g.revealed)
        try advanceStreet(g)
        XCTAssertEqual(g.actor, 1)
        try act(g, 1, .raise, 200)
        try act(g, 2, .call)
        XCTAssertTrue(g.revealed)
        XCTAssertEqual(try partitionPots(g).pots.map(\.amount), [300, 400])
        XCTAssertEqual(g.players[2].stack, 200)
        try advanceStreet(g)
        XCTAssertEqual(g.phase, .between)
        try advanceStreet(g)
        conserve(g, 15900)
    }

    func testLiveBetDifferenceIsNotASidePot() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(9))
        try act(g, g.actor, .raise, 150)
        let live = currentPots(g)
        XCTAssertEqual(live.pots.count, 1)
        XCTAssertEqual(live.pots[0].amount, 125)
        XCTAssertEqual(live.refunds, [Refund(id: 3, amount: 100)])
    }

    func testPotOddsExcludeSidePotsBeyondTheShortStackCap() throws {
        let g = try Self.fixture([0, 100, 100])
        XCTAssertEqual(contestableAfterCall(g, 0, 20), 60)
        XCTAssertEqual(contestableAfterCall(g, 0, 100), 300)
    }

    func testFoldedPlayersDoNotCreateExtraOddChipAwards() throws {
        let g = try Self.fixture([5, 5, 1, 2, 3, 4], folded: [2, 3, 4, 5], custom: ["As Ah", "Ac Ad"])
        try settle(g)
        XCTAssertEqual(g.pots.count, 1)
        XCTAssertEqual(g.pots[0].amount, 20)
        XCTAssertEqual(g.payouts, [10, 10, 0, 0, 0, 0])
        conserve(g, 30000)
    }

    func testSettlementCannotAwardChipsTwice() throws {
        let g = try Self.fixture([100, 300, 500, 500])
        try settle(g)
        let before = g.state
        assertThrowsPoker(.alreadySettled) { try settle(g) }
        XCTAssertEqual(g.state, before)
    }
}
