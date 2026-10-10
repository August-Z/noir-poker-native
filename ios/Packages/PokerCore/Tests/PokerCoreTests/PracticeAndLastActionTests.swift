import XCTest
@testable import PokerCore

final class PracticeRunoutTests: XCTestCase {
    func withoutDisplay(_ g: Game) -> GameState {
        var s = g.state
        s.practiceBoard = nil
        s.logs = []
        s.replayAttempt = 0
        return s
    }

    func testFoldWinRunoutMatchesOriginalRiverAndLeavesSettlementUntouched() throws {
        for street in 0...3 {
            let g = try newGame(9)
            g.dealer = 5
            try startHand(g, random: SeededRandom(seed: 700 + street))
            let original = withoutDisplay(g)
            let river = g.deepCopy()
            try finish(river)
            while g.street < street {
                while g.phase == .playing { try act(g, g.actor, .call) }
                try advanceStreet(g)
            }
            if street > 0 { try act(g, g.actor, .raise, 100) }
            while g.actor != 0 { try act(g, g.actor, .fold) }
            try act(g, 0, .fold)
            while g.phase == .playing { try act(g, g.actor, .fold) }
            XCTAssertEqual(g.phase, .done)
            XCTAssertFalse(g.showdown)
            let settled = withoutDisplay(g)
            let decisions = g.decisions
            let stacks = chips(g)
            try completeBoardForPractice(g)
            let shown = g.practiceBoard ?? g.board
            XCTAssertEqual(shown, river.board, "street \(street)")
            XCTAssertEqual(Set(shown).count, 5)
            XCTAssertEqual(withoutDisplay(g), settled)
            XCTAssertEqual(g.decisions, decisions)
            XCTAssertEqual(chips(g), stacks)
            XCTAssertEqual(stacks, 45000)
            if street < 3 {
                XCTAssertEqual(g.logs.first?.text, "Practice runout · all five community cards shown; the fold-win result is unchanged")
            }
            let once = g.state
            try completeBoardForPractice(g)
            XCTAssertEqual(g.state, once)
            assertThrowsPoker(.roundNotFinished) { try advanceStreet(g) }
            try restartHand(g)
            XCTAssertNil(g.practiceBoard)
            XCTAssertEqual(withoutDisplay(g), original)
            try finish(g)
            XCTAssertEqual(g.board, river.board)
            try startHand(g, random: SeededRandom(1))
            XCTAssertNil(g.practiceBoard)
        }
    }

    func testPracticeRunoutCannotExposeALiveDeck() throws {
        let g = try newGame()
        assertThrowsPoker(.handNotSettled) { try completeBoardForPractice(g) }
        try startHand(g, random: SeededRandom(21))
        var before = g.state
        assertThrowsPoker(.handNotSettled) { try completeBoardForPractice(g) }
        XCTAssertEqual(g.state, before)
        while g.phase == .playing { try act(g, g.actor, .call) }
        before = g.state
        assertThrowsPoker(.handNotSettled) { try completeBoardForPractice(g) }
        XCTAssertEqual(g.state, before)
        try finish(g)
        before = g.state
        try completeBoardForPractice(g)
        XCTAssertEqual(g.state, before)
    }

    func testShortBoardShowdownCannotBeCompleted() throws {
        let g = try PotTests.fixture([100, 100])
        g.board = cards("2c 3d 4h")
        g.phase = .between
        try settle(g, showdown: true)
        assertThrowsPoker(.showdownNeedsBoard) { try completeBoardForPractice(g) }
    }
}

final class LastActionTests: XCTestCase {
    func testPreflopAllInSurvivesEveryRunoutStreet() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(31))
        let raiser = g.actor
        try act(g, raiser, .raise, 5000)
        while g.phase == .playing { try act(g, g.actor, .call) }
        let final = g.players.map(\.lastAction)
        XCTAssertEqual(final[raiser]?.text, "2-bet all-in to 5,000")
        while g.phase != .done {
            try advanceStreet(g)
            XCTAssertEqual(g.players.map(\.lastAction), final)
        }
        XCTAssertEqual(g.board.count, 5)
        XCTAssertEqual(wealth(g), 30000)
        for p in g.players {
            XCTAssertEqual(p.lastAction?.street, 0)
            XCTAssertEqual(p.lastAction?.bet, 5000)
            XCTAssertEqual(p.bet, 0)
            XCTAssertTrue(p.lastAction?.text.hasSuffix("5,000") ?? false)
        }
    }

    func testLaterActionReplacesRetainedActionAndResetsPreserveContext() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(32))
        try act(g, 3, .raise, 150)
        try act(g, 4, .call)
        try act(g, 5, .fold)
        while g.phase == .playing { try act(g, g.actor, .call) }
        try advanceStreet(g)
        XCTAssertEqual(g.players[4].action, "")
        XCTAssertEqual(g.players[4].lastAction, LastAction(text: "Call 150", street: 0, bet: 150))
        try act(g, 1, .raise, 100)
        XCTAssertEqual(g.players[1].action, "1-bet bet to 100")
        try act(g, 2, .call)
        try act(g, 3, .fold)
        try act(g, 4, .call)
        try act(g, 0, .call)
        try advanceStreet(g)
        XCTAssertEqual(g.players[4].lastAction, LastAction(text: "Call 100", street: 1, bet: 100))
        XCTAssertEqual(g.players[3].lastAction, LastAction(text: "Fold", street: 1, bet: 0))
        XCTAssertEqual(g.players[5].lastAction, LastAction(text: "Fold", street: 0, bet: 0))
        try act(g, 1, .check)
        XCTAssertEqual(g.players[1].lastAction, LastAction(text: "Check", street: 2, bet: 0))
        XCTAssertEqual(g.logs.first?.text, "Mia: Check")
        XCTAssertEqual(wealth(g), 30000)
    }

    func testRefundsAndPracticeCardsKeepTheShoveWhileReplayAndNextHandReset() throws {
        let g = try newGame()
        let rng = SeededRandom(33)
        try startHand(g, random: rng)
        let raiser = g.actor
        try act(g, raiser, .raise, 5000)
        let shoved = g.players[raiser].lastAction
        while g.phase == .playing { try act(g, g.actor, .fold) }
        XCTAssertEqual(g.phase, .done)
        XCTAssertTrue(g.refunds.contains { $0.id == raiser && $0.amount > 0 })
        XCTAssertEqual(g.players[raiser].lastAction, shoved)
        XCTAssertTrue(g.board.isEmpty)
        try completeBoardForPractice(g)
        XCTAssertEqual(g.practiceBoard?.count, 5)
        XCTAssertTrue(g.board.isEmpty)
        XCTAssertEqual(g.players[raiser].lastAction, shoved)
        try restartHand(g)
        XCTAssertNil(g.players[raiser].lastAction)
        XCTAssertNil(g.practiceBoard)
        XCTAssertEqual(g.players.filter { $0.lastAction != nil }.count, 2)
        while g.phase == .playing { try act(g, g.actor, .fold) }
        try startHand(g, random: rng)
        let retained = g.players.compactMap(\.lastAction)
        XCTAssertEqual(retained.count, 2)
        XCTAssertTrue(retained.allSatisfy { $0.text.hasPrefix("SB ") || $0.text.hasPrefix("BB ") })
        XCTAssertEqual(wealth(g), 30000)
    }
}

final class BetLabelTests: XCTestCase {
    func nextLabel(_ g: Game, _ amount: Int) -> String {
        actionLabel(LabelStep(game: g, action: .raise, amount: amount))
    }

    func testPreflopTwoThreeFourBetsSurviveCallsAndDecisionSnapshots() throws {
        let g = try newGame()
        g.dealer = 5
        try startHand(g, random: ConstantRandom(0.5))
        while g.actor != 0 { try act(g, g.actor, .fold) }
        XCTAssertEqual(nextLabel(g, 150), "2-bet open to 150")
        try act(g, 0, .raise, 150)
        try act(g, 1, .call)
        XCTAssertEqual(nextLabel(g, 650), "3-bet raise to 650")
        try act(g, 2, .raise, 650)
        try act(g, 0, .call)
        XCTAssertEqual(nextLabel(g, 1800), "4-bet raise to 1,800")
        try act(g, 1, .raise, 1800)
        try act(g, 2, .call)
        try act(g, 0, .call)
        XCTAssertEqual(actionLabel(LabelStep(g.decisions[0])), "2-bet open to 150")
        XCTAssertEqual(actionLabel(LabelStep(g.decisions[2]), .raise, 3000), "5-bet raise to 3,000")
        XCTAssertEqual(actionLabel(LabelStep(g.decisions[1])), "Call 500")
        XCTAssertEqual(g.history.filter { $0.action == .raise }.map(\.betLabel),
                       ["2-bet open to", "3-bet raise to", "4-bet raise to"])
        XCTAssertTrue(g.logs.contains { $0.text == "Alex: 3-bet raise to 650" })
        XCTAssertEqual(wealth(g), 30000)

        try advanceStreet(g)
        XCTAssertEqual(nextLabel(g, 100), "1-bet bet to 100")
        try act(g, 1, .check)
        try act(g, 2, .raise, 100)
        try act(g, 0, .call)
        XCTAssertEqual(nextLabel(g, 300), "2-bet raise to 300")
        try act(g, 1, .raise, 300)
        try act(g, 2, .call)
        try act(g, 0, .call)
        try advanceStreet(g)
        XCTAssertEqual(nextLabel(g, 100), "1-bet bet to 100")
        XCTAssertEqual(wealth(g), 30000)
    }

    func testShortAllInHasAnOrdinalWithoutReopeningAndAllInCallsAddNoLevel() throws {
        let g = try newGame()
        g.dealer = 5
        g.players[2].stack = 175
        g.players[3].stack = 100
        let total = wealth(g)
        try startHand(g, random: ConstantRandom(0.5))
        while g.phase == .playing { try act(g, g.actor, .call) }
        try advanceStreet(g)
        try act(g, 1, .raise, 100)
        XCTAssertEqual(nextLabel(g, 125), "2-bet short all-in to 125")
        try act(g, 2, .raise, 125)
        XCTAssertEqual(g.players[2].action, "2-bet short all-in to 125")
        XCTAssertEqual(g.minRaise, 100)
        try act(g, 3, .call)
        XCTAssertEqual(g.players[3].action, "All-In 50")
        XCTAssertEqual(nextBetLevel(street: g.street, history: g.history), 3)
        try act(g, 4, .call)
        try act(g, 5, .call)
        try act(g, 0, .call)
        XCTAssertEqual(g.actor, 1)
        XCTAssertFalse(legalActions(g).raiseReopened)
        XCTAssertFalse(legalActions(g).canRaise)
        let index = try XCTUnwrap(g.history.firstIndex { $0.betLabel?.contains("short all-in") ?? false })
        XCTAssertEqual(historyActionLabel(g.history, index), "2-bet short all-in to 125")
        XCTAssertEqual(wealth(g), total)
    }

    func testHistoricalOrdinalsCountOnlyTheSameStreet() {
        var history = [HistoryEntry(street: 0, id: 0, action: .raise, amount: 150)]
        for i in 1...6 {
            history.append(HistoryEntry(street: 1, id: 0, action: .raise, amount: 100 * i))
            history.append(HistoryEntry(street: 1, id: 0, action: .call, amount: 100))
            history.append(HistoryEntry(street: 1, id: 0, action: .fold, amount: 0))
        }
        let tail = history.indices.map { historyActionLabel(history, $0) }.suffix(6)
        XCTAssertEqual(Array(tail), ["5-bet raise to 500", "Call 100", "Fold", "6-bet raise to 600", "Call 100", "Fold"])
        XCTAssertEqual(historyActionLabel(history, 0), "2-bet open to 150")
        XCTAssertEqual(historyActionLabel(history, 1), "1-bet bet to 100")
        XCTAssertEqual(nextBetLevel(street: 2, history: history), 1)
    }

    func testAllInCallLabelAndCaptionFallbacks() {
        let legal = LegalActions(enabled: true, toCall: 900, callAmount: 400, maxRaiseTo: 400)
        XCTAssertEqual(actionLabel(LabelStep(street: 1, currentBet: 900, legal: legal, stack: 400), .call), "All-In Call 400")
        XCTAssertEqual(actionLabel(LabelStep(street: 1, currentBet: 900, legal: legal, stack: 4000), .call), "Call 400")
        XCTAssertEqual(actionLabel(LabelStep(street: 1, legal: legal), .fold), "Fold")
        XCTAssertEqual(actionLabel(LabelStep(street: 1, legal: legal), .check), "Check")
        // Partial legal: only maxRaiseTo; the full raise falls back to currentBet + minRaise.
        let partial = LabelStep(street: 2, currentBet: 200, minRaise: 200, legal: LabelLegal(maxRaiseTo: 350))
        XCTAssertEqual(raiseCaption(partial, 350), "1-bet short all-in to")
        XCTAssertEqual(raiseCaption(partial, 300), "1-bet raise to")
    }

    func testReplayClearsPriorRaiseSequence() throws {
        let g = try newGame()
        g.dealer = 2
        try startHand(g, random: ConstantRandom(0.5))
        try act(g, 0, .raise, 150)
        while g.phase == .playing { try act(g, g.actor, .fold) }
        try restartHand(g)
        XCTAssertTrue(g.history.isEmpty)
        XCTAssertEqual(nextLabel(g, 150), "2-bet open to 150")
        XCTAssertEqual(wealth(g), 30000)
    }
}
