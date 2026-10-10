import XCTest
@testable import PokerCore

final class RulesTests: XCTestCase {
    func testNewGameValidatesTableSize() throws {
        assertThrowsPoker(.invalidPlayerCount) { _ = try newGame(4) }
        assertThrowsPoker(.invalidPlayerCount) { _ = try newGame(10) }
        let g = try newGame()
        XCTAssertEqual(g.players.map(\.name), ["You", "Mia", "Alex", "River", "Kai", "Luna"])
        XCTAssertEqual(g.dealer, 5)
        XCTAssertEqual(g.phase, .idle)
        XCTAssertEqual(g.players.map(\.stack), Array(repeating: 5000, count: 6))
    }

    func testPositionsForFiveToNineSeatsFollowTheButton() throws {
        let expected: [Int: [String]] = [
            5: ["BTN", "SB", "BB", "UTG", "CO"],
            6: ["BTN", "SB", "BB", "UTG", "HJ", "CO"],
            7: ["BTN", "SB", "BB", "UTG", "LJ", "HJ", "CO"],
            8: ["BTN", "SB", "BB", "UTG", "UTG+1", "LJ", "HJ", "CO"],
            9: ["BTN", "SB", "BB", "UTG", "UTG+1", "MP", "LJ", "HJ", "CO"],
        ]
        for n in 5...9 {
            let g = try newGame(n)
            for dealer in 0..<n {
                g.dealer = dealer
                for offset in 0..<n {
                    XCTAssertEqual(seatPosition(g, (dealer + offset) % n), expected[n]![offset], "n=\(n) d=\(dealer)")
                }
            }
        }
    }

    func testBlindsAndFirstActorForEveryTableSizeAndButton() throws {
        for n in 5...9 {
            for d in 0..<n {
                let g = try newGame(n)
                g.dealer = (d + n - 1) % n
                try startHand(g, random: SeededRandom(seed: n * 10 + d))
                XCTAssertEqual(g.dealer, d)
                let sb = (d + 1) % n, bb = (d + 2) % n
                XCTAssertEqual(g.players[sb].bet, 25)
                XCTAssertEqual(g.players[bb].bet, 50)
                XCTAssertEqual(g.players[sb].action, "SB 25")
                XCTAssertEqual(g.players[bb].action, "BB 50")
                XCTAssertEqual(g.actor, (d + 3) % n)
                XCTAssertEqual(seatPosition(g, g.actor), "UTG")
                XCTAssertEqual(potSize(g), 75)
                XCTAssertEqual(g.players.map(\.hole.count), Array(repeating: 2, count: n))
                XCTAssertEqual(g.deck.count, 52 - 2 * n)
                XCTAssertEqual(g.logs.map(\.text), [
                    "\(g.players[sb].name): SB 25 · \(g.players[bb].name): BB 50",
                    "Hand 1 begins · Button: \(g.players[d].name)",
                ])
            }
        }
    }

    func testBlindsAndBigBlindOption() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(1))
        XCTAssertEqual(g.actor, 3)
        XCTAssertEqual(potSize(g), 75)
        for _ in 0..<5 { try act(g, g.actor, .call) }
        XCTAssertEqual(g.actor, 2, "the big blind keeps the option")
        XCTAssertTrue(legalActions(g).canCheck)
        try act(g, g.actor, .call)
        XCTAssertEqual(g.phase, .between)
        XCTAssertEqual(potSize(g), 300)
        XCTAssertEqual(g.history.last?.action, .check, "calling nothing is recorded as a check")
        try advanceStreet(g)
        XCTAssertEqual(g.board.count, 3)
        XCTAssertEqual(g.actor, 1)
        XCTAssertEqual(g.logs[0].type, .street)
        XCTAssertTrue(g.logs[0].text.hasPrefix("Flop · "))
    }

    func testFoldsAwardPotWithoutBoard() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(2))
        for _ in 0..<5 { try act(g, g.actor, .fold) }
        XCTAssertEqual(g.phase, .done)
        XCTAssertEqual(g.winners.first?.id, 2)
        XCTAssertEqual(g.winners.first?.label, "All other players folded")
        XCTAssertEqual(g.result, "Alex wins 50 chips")
        XCTAssertEqual(g.refunds, [Refund(id: 2, amount: 25)])
        XCTAssertEqual(chips(g), 30000)
    }

    func testShortAllInDoesNotReopenCompletedRaise() throws {
        let g = try newGame()
        g.phase = .playing
        g.street = 1
        g.currentBet = 100
        g.minRaise = 100
        g.actor = 1
        g.pending = [1, 2]
        for i in g.players.indices {
            g.players[i].folded = i > 2
            g.players[i].bet = i < 3 ? 100 : 0
            g.players[i].total = g.players[i].bet
            g.players[i].stack = i == 1 ? 50 : 1000
            g.players[i].actedTo = i == 0 ? 100 : nil
        }
        try act(g, 1, .raise, 150)
        XCTAssertEqual(g.players[1].action, "1-bet short all-in to 150")
        XCTAssertEqual(g.minRaise, 100)
        try act(g, 2, .call)
        XCTAssertEqual(g.actor, 0)
        let legal = legalActions(g, 0)
        XCTAssertFalse(legal.raiseReopened)
        XCTAssertFalse(legal.canRaise)
        assertThrowsPoker(.illegalRaise) { try act(g, 0, .raise, 250) }
        try act(g, 0, .call)
        XCTAssertEqual(g.phase, .between)
    }

    func testSeveralShortAllInsCanCumulativelyReopenRaising() throws {
        let g = try PotTests.fixture([100, 100, 100, 100])
        g.phase = .playing
        g.currentBet = 100
        g.minRaise = 100
        g.actor = 1
        g.pending = [1, 2, 3]
        g.players[0].actedTo = 100
        g.players[1].stack = 40
        g.players[2].stack = 100
        try act(g, 1, .raise, 140)
        try act(g, 2, .raise, 200)
        try act(g, 3, .call)
        XCTAssertEqual(g.actor, 0)
        XCTAssertTrue(legalActions(g, 0).canRaise)
        XCTAssertEqual(legalActions(g, 0).fullRaiseTo, 300)
    }

    func testInvalidActionsThrowTypedErrorsAndPreserveState() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(3))
        let before = g.state
        assertThrowsPoker(.notYourTurn) { try act(g, 0, .call) }
        assertThrowsPoker(.cannotCheck) { try act(g, 3, .check) }
        assertThrowsPoker(.unknownAction) { try act(g, 3, "bet") }
        assertThrowsPoker(.notYourTurn) { try act(g, 0, "bet") }
        assertThrowsPoker(.illegalRaise) { try act(g, 3, .raise, 90) }
        assertThrowsPoker(.illegalRaise) { try act(g, 3, .raise, 6000) }
        assertThrowsPoker(.illegalRaise) { try act(g, 3, .raise) }
        assertThrowsPoker(.roundNotFinished) { try advanceStreet(g) }
        assertThrowsPoker(.handInProgress) { try startHand(g) }
        assertThrowsPoker(.settingsLocked) { try applyBotSettings(g, nil) }
        XCTAssertEqual(g.state, before)
        XCTAssertEqual(PokerError(.notYourTurn).message, "It's not your turn yet.")
    }

    func testRandomizedHandsConserveChipsAndEnd() throws {
        let rng = SeededRandom(2024)
        for trial in 0..<200 {
            let g = try newGame(5 + trial % 5)
            let total = chips(g)
            try startHand(g, random: rng)
            var turns = 0
            while g.phase != .done {
                turns += 1
                XCTAssertLessThan(turns, 600, "hand stalled")
                if g.phase == .between {
                    try advanceStreet(g)
                    continue
                }
                let id = g.actor, l = legalActions(g), r = rng.next()
                XCTAssertTrue(l.enabled)
                if r < 0.16 { try act(g, id, .fold) }
                else if r < 0.43 && l.canRaise { try act(g, id, .raise, rng.next() < 0.25 ? l.maxRaiseTo : l.minRaiseTo) }
                else { try act(g, id, .call) }
                XCTAssertTrue(g.players.allSatisfy { $0.stack >= 0 })
                XCTAssertEqual(wealth(g), total)
            }
            XCTAssertEqual(chips(g), total)
            XCTAssertEqual(g.pots.reduce(0) { $0 + $1.amount } + g.refunds.reduce(0) { $0 + $1.amount }, potSize(g))
        }
    }

    func testRebuyAndShortBlinds() throws {
        let g = try newGame()
        g.players[0].stack = 0
        g.players[1].stack = 20
        g.players[2].stack = 35
        try startHand(g, random: SeededRandom(4))
        XCTAssertEqual(g.stats.buyin, 10000)
        XCTAssertEqual(g.players[0].stack, 5000)
        XCTAssertEqual(g.players[1].bet, 20)
        XCTAssertEqual(g.players[1].action, "SB 20")
        XCTAssertTrue(g.players[1].allin)
        XCTAssertEqual(g.players[2].bet, 35)
        XCTAssertEqual(g.currentBet, 50)
        XCTAssertTrue(g.logs.contains { $0.text == "You rebuy 5,000 virtual chips" && $0.type == .info })
        XCTAssertEqual(g.logs.first?.text, "Mia: SB 20 · Alex: BB 35")
    }
}
