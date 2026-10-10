import XCTest
@testable import PokerCore

/// Replay Hand (`restartHand`): restores the private deal and rolls back stats once.
final class ReplayTests: XCTestCase {
    /// The state without fields that legitimately differ after a replay.
    func withoutRetry(_ s: GameState) -> GameState {
        var s = s
        s.logs = []
        s.replayAttempt = 0
        return s
    }

    func testRestartRejectsIdleActiveAndBetweenStreets() throws {
        let g = try newGame()
        XCTAssertFalse(canRestartHand(g))
        assertThrowsPoker(.replayUnavailable) { try restartHand(g) }
        try startHand(g, random: SeededRandom(1))
        let before = g.state
        assertThrowsPoker(.replayUnavailable) { try restartHand(g) }
        XCTAssertEqual(g.state, before)
        while g.phase == .playing { try act(g, g.actor, .call) }
        let between = g.state
        assertThrowsPoker(.replayUnavailable) { try restartHand(g) }
        XCTAssertEqual(g.state, between)
    }

    func testAllInFoldAroundRestoresDealButtonStacksAndStatistics() throws {
        let g = try newGame()
        g.dealer = 2
        g.stats = GameStats(hands: 9, wins: 4, buyin: 10000)
        g.players[0].stack = 14000
        try startHand(g, random: SeededRandom(5))
        XCTAssertEqual(g.actor, 0)
        let baseline = g.state
        try act(g, 0, .raise, legalActions(g).maxRaiseTo)
        while g.phase == .playing { try act(g, g.actor, .fold) }
        XCTAssertEqual(g.phase, .done)
        XCTAssertFalse(g.showdown)
        XCTAssertEqual(g.stats.hands, 10)
        XCTAssertFalse(g.refunds.isEmpty)
        XCTAssertGreaterThan(g.players[0].stack, baseline.players[0].stack)
        XCTAssertTrue(canRestartHand(g))
        try restartHand(g)
        XCTAssertEqual(withoutRetry(g.state), withoutRetry(baseline))
        XCTAssertEqual(g.replayAttempt, 1)
        XCTAssertEqual(g.logs.first?.text, "Hand 1 · Replay #1 · previous settlement reversed")
        XCTAssertEqual(g.players[0].total, 0)
        XCTAssertEqual(potSize(g), 75)
        XCTAssertEqual(g.stats, GameStats(hands: 9, wins: 4, buyin: 10000))
        XCTAssertEqual(g.players[0].stack, 14000)
        XCTAssertFalse(g.revealed)
        XCTAssertTrue(g.decisions.isEmpty)
        XCTAssertTrue(g.history.isEmpty)
        XCTAssertTrue(g.payouts.isEmpty)
        XCTAssertTrue(g.winners.isEmpty)
        try act(g, 0, .raise, 150)
        XCTAssertEqual(g.decisions.count, 1)
        XCTAssertEqual(g.decisions[0].amount, 150)
        XCTAssertFalse(g.players[0].allin)
    }

    func testAllButtonRotationsReplayForFiveToNineSeats() throws {
        for n in 5...9 {
            for d in 0..<n {
                let g = try newGame(n)
                g.dealer = (d + n - 1) % n
                for i in g.players.indices { g.players[i].stack = 1000 + i * 123 }
                g.stats = GameStats(hands: 7, wins: 3, buyin: 1000)
                try startHand(g, random: SeededRandom(seed: n * 100 + d))
                let baseline = g.state
                let total = chips(g) + potSize(g)
                try finish(g, .fold)
                XCTAssertTrue(canRestartHand(g))
                try restartHand(g)
                XCTAssertEqual(withoutRetry(g.state), withoutRetry(baseline))
                XCTAssertEqual(g.dealer, d)
                XCTAssertEqual(g.hand, 1)
                XCTAssertEqual(chips(g) + potSize(g), total)
            }
        }
    }

    func testRunoutStaysIdenticalAfterDifferentChoices() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(11))
        let deck = g.deck
        try finish(g)
        let board = g.board
        let firstDecision = g.decisions[0]
        try restartHand(g)
        XCTAssertEqual(g.deck, deck)
        try act(g, g.actor, .raise, 100)
        try finish(g)
        XCTAssertEqual(g.board, board)
        XCTAssertEqual(g.stats.hands, 1)
        XCTAssertEqual(g.decisions[0].history[0].action, .raise)
        XCTAssertEqual(firstDecision.history[0].action, .call)
        XCTAssertEqual(g.decisions[0].currentBet, 100)
        XCTAssertEqual(firstDecision.currentBet, 50)
    }

    func testNineUnequalAllInsRetractEightPotsAndOneRefund() throws {
        let g = try newGame(9)
        for i in g.players.indices { g.players[i].stack = (i + 1) * 100 }
        try startHand(g, random: SeededRandom(12))
        let baseline = g.state
        while g.phase == .playing {
            let legal = legalActions(g)
            if legal.canRaise { try act(g, g.actor, .raise, legal.maxRaiseTo) } else { try act(g, g.actor, .call) }
        }
        try finish(g)
        XCTAssertEqual(g.pots.count, 8)
        XCTAssertEqual(g.refunds.count, 1)
        XCTAssertEqual(chips(g), 4500)
        try restartHand(g)
        XCTAssertEqual(withoutRetry(g.state), withoutRetry(baseline))
        XCTAssertEqual(chips(g) + potSize(g), 4500)
    }

    func testRebuyAndShortBlindRestoreOnce() throws {
        let g = try newGame()
        g.players[0].stack = 0
        g.players[1].stack = 20
        g.players[2].stack = 35
        try startHand(g, random: SeededRandom(13))
        let baseline = g.state
        try finish(g)
        try restartHand(g)
        XCTAssertEqual(withoutRetry(g.state), withoutRetry(baseline))
        XCTAssertEqual(g.stats.buyin, 10000)
        XCTAssertTrue(g.players[1].allin)
        XCTAssertEqual(potSize(g), 55)
    }

    func testRepeatedRetriesKeepBaselineAndCountOnlyLatestAttempt() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(14))
        let baseline = g.state
        for attempt in 1...20 {
            try finish(g, attempt % 2 == 1 ? .fold : .call)
            XCTAssertEqual(g.stats.hands, 1)
            try restartHand(g)
            XCTAssertEqual(g.replayAttempt, attempt)
            XCTAssertEqual(withoutRetry(g.state), withoutRetry(baseline))
            if attempt == 1 {
                // Mutating the live table never reaches the private baseline.
                g.players[0].hole = cards("2s 3s")
                g.deck[0] = Card(rank: 2, suit: 0)
            }
        }
        g.difficulty = .hard
        try finish(g)
        try restartHand(g)
        XCTAssertEqual(g.difficulty, .hard)
        XCTAssertEqual(g.replayAttempt, 21)
        XCTAssertEqual(g.stats.hands, 0)
        try finish(g)
        XCTAssertEqual(g.stats.hands, 1)
    }

    func testNextHandReplacesBaselineAndResetsAttempt() throws {
        let g = try newGame()
        let rng = SeededRandom(15)
        try startHand(g, random: rng)
        try finish(g, .fold)
        try restartHand(g)
        try finish(g, .fold)
        let previousDealer = g.dealer
        try startHand(g, random: rng)
        let second = g.state
        XCTAssertEqual(g.hand, 2)
        XCTAssertEqual(g.dealer, (previousDealer + 1) % 6)
        XCTAssertEqual(g.replayAttempt, 0)
        try finish(g)
        try restartHand(g)
        XCTAssertEqual(withoutRetry(g.state), withoutRetry(second))
        XCTAssertEqual(g.hand, 2)
        XCTAssertEqual(g.stats.hands, 1)
    }

    func testReplayDrawsNoRandomnessAndCopiesHaveNoBaseline() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(16))
        try finish(g, .fold)
        XCTAssertFalse(canRestartHand(g.deepCopy()))
        XCTAssertFalse(canRestartHand(Game(state: g.state)))
        try restartHand(g) // restartHand takes no random source by construction.
        XCTAssertEqual(g.replayAttempt, 1)
    }

    func testReplayRestoresFrozenProfilesMoodsAndStatisticsExactlyOnce() throws {
        let g = try newGame()
        try applyBotSettings(g, ["assignments": ["1": "tan", "2": "st"], "emotionMode": "lively"])
        g.players[1].botMood.kind = .frustrated
        g.players[1].botMood.remaining = 3
        g.players[1].botMood.cooldown = 4
        g.players[1].botMood.reason = "Test public loss"
        try startHand(g, random: SeededRandom(17))
        let baseline = g.players.map { [$0.botProfile, "\($0.botMood)", "\($0.botStats)"] }
        for attempt in 0..<4 {
            try finishWithBots(g, LCGRandom(UInt32(attempt + 5)))
            try applyBotSettings(g, ["assignments": ["1": "peter"], "emotionMode": "off"])
            try restartHand(g)
            XCTAssertEqual(g.emotionMode, .lively)
            XCTAssertEqual(g.players.map { [$0.botProfile, "\($0.botMood)", "\($0.botStats)"] }, baseline)
            XCTAssertEqual(g.stats.hands, 0)
        }
        assertThrowsPoker(.settingsLocked) { try applyBotSettings(g, [String: Any]()) }
    }
}
