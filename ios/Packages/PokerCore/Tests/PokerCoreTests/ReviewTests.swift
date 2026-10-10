import XCTest
@testable import PokerCore

// Native ports of the reference review unit tests (tests/unit/review-context,
// review-check, review-lines and counterfactual), plus privacy, determinism and
// cancellation checks of the typed review API.

/// The reference review-context test snapshot: hero on the BTN against the BB.
/// The reference halves `pot` for each total; with `pot: 75` that is 37.5 chips,
/// which native integer chips round down to 37.
private func contextDecision(hole: String = "Qs Qh", board: String = "Js 7h 2c", street: Int = 1,
                             action: PokerAction = .check, amount: Int = 0, stack: Int = 5000, currentBet: Int = 0,
                             pot: Int = 300) -> ReviewDecision {
    let players = [
        ReviewSeat(id: 0, name: "You", position: "BTN", stack: stack, bet: 0, total: pot / 2, folded: false, allin: false),
        ReviewSeat(id: 1, name: "Mia", position: "BB", stack: stack, bet: currentBet, total: pot / 2, folded: false,
                   allin: false),
    ]
    let legal = LegalActions(enabled: true, toCall: currentBet, callAmount: currentBet, canCheck: currentBet == 0,
                             canRaise: true, minRaiseTo: currentBet + 50,
                             fullRaiseTo: currentBet == 0 ? 50 : currentBet + 50, maxRaiseTo: stack)
    return ReviewDecision(index: 0, hand: 1, street: street, position: "BTN", hole: cards(hole), board: cards(board),
                          stack: stack, bet: 0, total: pot / 2, pot: pot, currentBet: currentBet, minRaise: 50,
                          dealer: nil, emotionMode: nil, legal: legal, pending: [0], action: action, amount: amount,
                          players: players, history: [])
}

/// The reference review-check test snapshot.
private func checkSnapshot(hole: String = "7s 2h", board: String = "2s 6h 9c Jd Qs", street: Int = 3,
                           action: PokerAction = .call, amount: Int = 100, position: String = "BTN",
                           totals: [Int] = [100, 200, 0, 0, 0, 0], stacks: [Int] = [1000, 1000, 0, 0, 0, 0],
                           allins: [Int] = [], pending: [Int] = [0], currentBet: Int = 200, canCheck: Bool = false,
                           canRaise: Bool = true) -> ReviewDecision {
    let names = ["You", "Mia", "Alex", "River", "Kai", "Luna"]
    let players = totals.enumerated().map { id, total in
        ReviewSeat(id: id, name: names[id], position: position, stack: stacks[id], bet: total, total: total,
                   folded: id > 1 && total == 0, allin: allins.contains(id), action: id == 1 ? "Bet \(currentBet)" : "")
    }
    let legal = LegalActions(enabled: true, toCall: canCheck ? 0 : amount, callAmount: canCheck ? 0 : amount,
                             canCheck: canCheck, raiseReopened: canRaise, canRaise: canRaise,
                             minRaiseTo: currentBet + 50, fullRaiseTo: currentBet == 0 ? 50 : currentBet + 50,
                             maxRaiseTo: totals[0] + stacks[0])
    return ReviewDecision(index: 0, hand: 1, street: street, position: position, hole: cards(hole),
                          board: board.isEmpty ? [] : cards(board), stack: stacks[0], bet: totals[0], total: totals[0],
                          pot: totals.reduce(0, +), currentBet: currentBet, minRaise: 50, dealer: nil, emotionMode: nil,
                          legal: legal, pending: pending, action: action, amount: amount, players: players,
                          history: [HistoryEntry(street: street, id: 1, action: .raise, amount: currentBet)])
}

private func outcome(profit: Int, board: String, result: String = "") -> ReviewOutcome {
    ReviewOutcome(profit: profit, paid: 0, returned: 0, folded: false, wonPot: profit > 0, board: cards(board), pots: [],
                  result: result)
}

/// A six-handed hand with the hero on the button; everyone before the hero folds
/// (or seat 5 limps).
private func buttonGame(_ hole: String = "Ac 7h", limp: Bool = false, seed: UInt32 = 7) throws -> Game {
    let g = try newGame()
    g.dealer = 5
    try startHand(g, random: SeededRandom(seed))
    g.players[0].hole = cards(hole)
    while g.actor != 0 { try act(g, g.actor, limp && g.actor == 5 ? .call : .fold) }
    return g
}

private func decision(_ g: Game, _ i: Int) -> ReviewDecision { ReviewDecision(g.decisions[i]) }

final class ReviewContextTests: XCTestCase {
    let trials = 120

    func testOpenEndedDrawHasEightDistinctDirectCompletionCards() {
        let draw = drawInfo(cards("8s 9h"), cards("6c 7d Kc"))
        XCTAssertEqual(draw.straightOuts, 8)
        XCTAssertEqual(draw.outs, 8)
        XCTAssertEqual(draw.nextChance, 8.0 / 47)
    }

    func testCombinedFlushAndStraightDrawDeduplicatesTheSharedCard() {
        let draw = drawInfo(cards("As Ks"), cards("Qs Js 2h"))
        XCTAssertEqual(draw.flushOuts, 9)
        XCTAssertEqual(draw.straightOuts, 4)
        XCTAssertEqual(draw.outs, 12)
        XCTAssertEqual(draw.nextChance, 12.0 / 47)
    }

    func testMadeStraightIsNotADrawAndTheRiverHasNoNextCard() {
        let draw = drawInfo(cards("8s 9h"), cards("6c 7d Tc"))
        XCTAssertFalse(draw.straight)
        XCTAssertEqual(draw.outs, 0)
        XCTAssertEqual(drawInfo(cards("As Ks"), cards("Qs Js 2h 4d 5c")).outs, 0)
    }

    func testOverpairTopPairAndBoardPairGetDifferentDescriptions() throws {
        XCTAssertEqual(decisionContext(contextDecision()).handClass, .overpair)
        XCTAssertEqual(decisionContext(contextDecision()).handLabel.label, "An overpair (Queens)")
        let top = decisionContext(contextDecision(hole: "As Jh"))
        XCTAssertEqual(top.handClass, .topPair)
        XCTAssertEqual(top.handLabel.phrase, "top pair (J) with an A kicker")
        let boardPair = contextDecision(hole: "As Kh", board: "7s 7h 2c")
        XCTAssertEqual(decisionContext(boardPair).handClass, .boardPair)
        XCTAssertEqual(decisionContext(boardPair).handLabel.phrase, "a board pair of Sevens, hole cards as kickers")
        XCTAssertNotEqual(try analyzeDecision(boardPair, trials: trials).code, .valueCheck)
    }

    func testDeepQueensShoveSuggestsALegalSmallerValueRouteButShortAcesDoNot() throws {
        let q = contextDecision(board: "", street: 0, action: .raise, amount: 5000, currentBet: 50, pot: 75)
        let r = try analyzeDecision(q, trials: trials)
        XCTAssertEqual(r.code, .deepValueShove)
        XCTAssertEqual(r.alternative, CandidateAction(.raise, 150))
        XCTAssertTrue(r.reason.contains("100 BB"), r.reason)
        let a = try analyzeDecision(contextDecision(hole: "As Ah", board: "", street: 0, action: .raise, amount: 1000,
                                                    stack: 1000, currentBet: 50, pot: 75), trials: trials)
        XCTAssertEqual(a.code, .valueBet)
        XCTAssertFalse(a.lesson.contains("which opponent ranges will fold"))
    }

    func testFourSuitBoardWithoutAFlushIsNotAValueCheck() throws {
        let r = try analyzeDecision(contextDecision(hole: "Kh Kc", board: "Ks 7s 2s 4s", street: 2), trials: trials)
        XCTAssertNotEqual(r.code, .valueCheck)
        XCTAssertTrue(r.evidence.joined(separator: " ").contains("Four to a flush"))
    }

    func testRiverHeadsUpEnumeratesAll990PairsAndTiesOnARoyalBoard() throws {
        let r = try analyzeDecision(contextDecision(hole: "2h 3h", board: "As Ks Qs Js Ts", street: 3), trials: trials)
        XCTAssertEqual(r.metrics.method, .enumeration)
        XCTAssertEqual(r.metrics.trials, 990)
        XCTAssertEqual(r.metrics.uncertainty, 0)
        XCTAssertEqual(r.metrics.randomEquity, 0.5)
        XCTAssertEqual(r.metrics.weightedEquity, 0.5)
    }

    func testSamplingKeepsANonzeroBandEvenForAnAllWinSample() throws {
        let r = try analyzeDecision(contextDecision(hole: "As Ah", board: "Ac Ad 2s", street: 1), trials: 10)
        XCTAssertEqual(r.metrics.method, .sampling)
        XCTAssertGreaterThan(r.metrics.uncertainty, 0)
    }

    func testSnapshotSeedHashesTheReferenceJSONText() {
        let s = contextDecision()
        XCTAssertEqual(
            snapshotSeedJSON(s),
            #"[[{"rank":12,"suit":0,"symbol":"♠","key":"0-12"},{"rank":12,"suit":1,"symbol":"♥","key":"1-12"}],[{"rank":11,"suit":0,"symbol":"♠","key":"0-11"},{"rank":7,"suit":1,"symbol":"♥","key":"1-7"},{"rank":2,"suit":2,"symbol":"♣","key":"2-2"}],[{"id":0,"position":"BTN","stack":5000,"bet":0,"total":150,"folded":false,"allin":false},{"id":1,"position":"BB","stack":5000,"bet":0,"total":150,"folded":false,"allin":false}],[],1,0]"#)
        XCTAssertEqual(snapshotSeed(s), 2_583_955_511)
        let rng = seedRandom(2_583_955_511)
        XCTAssertEqual([rng.next(), rng.next(), rng.next()], [0.275968698784709, 0.8002593538258225, 0.1536247490439564])
        XCTAssertEqual(seedRandom(4_294_967_295 + 11071).next(), 0.5067068429198116)
    }

    func testSampleValueMatchesTheReferenceValues() throws {
        let s = contextDecision()
        let price = try callPrice(s)
        let random = sampleValue(s, price, trials: 120, weighted: false)
        XCTAssertEqual(random.equity, 0.8583333333333333)
        XCTAssertEqual(random.ev, 257.5)
        XCTAssertEqual(random.margin, 0.13512381104432028)
        XCTAssertEqual(sampleValue(s, price, trials: 120, weighted: true).equity, 0.7916666666666666)
        XCTAssertEqual(sampleValue(s, price, trials: 600, weighted: false).ev, 244)
    }

    func testToFixedRoundsExactBinaryTiesUpAndKeepsNegativeZero() {
        XCTAssertEqual(jsToFixed(0.25, 1), "0.3")
        XCTAssertEqual(jsToFixed(-0.25, 1), "-0.3")
        XCTAssertEqual(jsToFixed(2.25, 1), "2.3")
        XCTAssertEqual(jsToFixed(0.35, 1), "0.3") // 0.35 is slightly below the tie in binary
        XCTAssertEqual(jsToFixed(-0.04, 1), "-0.0")
        XCTAssertEqual(jsToFixed(-0.0, 1), "0.0")
        XCTAssertEqual(jsToFixed(66.66666666666667, 1), "66.7")
        XCTAssertEqual(jsToFixed(1e-300, 1), "0.0")
        XCTAssertEqual(jsToFixed(12345.678, 3), "12345.678")
        XCTAssertEqual(jsNumberString(79), "79")
        XCTAssertEqual(jsNumberString(79.80000000000001), "79.80000000000001")
    }

    /// Mood axes are interpolated raw (`String(x)`); the expected texts are
    /// Node's output for the same doubles.
    func testRawNumbersFollowJavaScriptNumberToString() {
        let cases: [(Double, String)] = [
            (1e-7, "1e-7"), (1.5e-7, "1.5e-7"), (0.000001, "0.000001"), (0.0000012, "0.0000012"),
            (1.23e-18, "1.23e-18"), (1e21, "1e+21"), (1.5e21, "1.5e+21"), (1e16, "10000000000000000"),
            (123456789012345680000, "123456789012345680000"), (-0.5, "-0.5"), (-0.0, "0"), (100, "100"),
            (0.1 + 0.2, "0.30000000000000004"), (5e-324, "5e-324"),
            (1.7976931348623157e308, "1.7976931348623157e+308"), (-2.5e-8, "-2.5e-8"), (4.35, "4.35"),
            (.nan, "NaN"), (-.infinity, "-Infinity"),
        ]
        for (x, text) in cases { XCTAssertEqual(jsNumberString(x), text, "\(x)") }
        XCTAssertEqual(jsToFixed(1.5e21, 1), "1.5e+21")
    }
}

final class ReviewCheckTests: XCTestCase {
    let trials = 100

    func testEveryHeroActionRecordsABeforeActionSnapshotWithoutHiddenData() throws {
        let g = try newGame()
        g.dealer = 2
        try startHand(g, random: SeededRandom(1))
        XCTAssertEqual(g.actor, 0)
        let beforeStack = g.players[0].stack, beforePot = potSize(g)
        try act(g, 0, .call)
        let s = decision(g, 0)
        XCTAssertEqual(s.stack, beforeStack)
        XCTAssertEqual(s.pot, beforePot)
        XCTAssertEqual(s.action, .call)
        XCTAssertEqual(s.amount, 50)
        XCTAssertTrue(s.board.isEmpty)
        XCTAssertTrue(s.history.isEmpty)
        let saved = s
        g.players[0].hole[0] = Card(rank: 2, suit: 0)
        g.players[1].stack = 1
        g.board += cards("As Kh Qc")
        g.history[0].amount = 999
        XCTAssertEqual(decision(g, 0), saved)
        XCTAssertEqual(s, saved)
    }

    func testReviewTypesHaveNoFieldForHiddenCardsTheDeckOrTheOutcome() throws {
        let g = try newGame()
        g.dealer = 2
        try startHand(g, random: SeededRandom(2))
        try act(g, 0, .call)
        let s = decision(g, 0)
        let hidden: Set<String> = ["deck", "winners", "result", "outcome", "opponents", "payouts", "showdown", "pots"]
        XCTAssertTrue(Set(Mirror(reflecting: s).children.compactMap(\.label)).isDisjoint(with: hidden))
        for p in s.players {
            let labels = Set(Mirror(reflecting: p).children.compactMap(\.label))
            XCTAssertFalse(labels.contains("hole"))
            XCTAssertFalse(labels.contains("botMood"))
        }
    }

    func testAllFourStreetsAreRecordedAndAnEmptyCallNormalizesToCheck() throws {
        let g = try newGame()
        g.dealer = 2
        let rng = SeededRandom(3)
        try startHand(g, random: rng)
        try finish(g)
        XCTAssertEqual(g.decisions.map(\.street), [0, 1, 2, 3])
        XCTAssertEqual(g.decisions.map(\.board.count), [0, 3, 4, 5])
        XCTAssertEqual(g.decisions.map(\.action), [.call, .check, .check, .check])
        let input = try createReviewInput(g)
        try startHand(g, random: rng)
        XCTAssertTrue(g.decisions.isEmpty)
        XCTAssertEqual(input.decisions.count, 4)
        XCTAssertEqual(input.outcome.board.count, 5)
    }

    func testReviewCannotStartBeforeSettlement() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(4))
        XCTAssertThrowsError(try createReviewInput(g)) { error in
            XCTAssertEqual(error as? ReviewError, ReviewError(.reviewNotReady))
            XCTAssertEqual((error as? ReviewError)?.message, "You can review a hand only after it ends.")
        }
    }

    func testFoldingWhenAFreeCheckExistsRecommendsTheFreeCheck() throws {
        let s = checkSnapshot(action: .fold, amount: 0, totals: [50, 50, 0, 0, 0, 0], currentBet: 0, canCheck: true)
        let r = try analyzeDecision(s, trials: trials)
        XCTAssertEqual(r.status, .attention)
        XCTAssertEqual(r.code, .freeFold)
        XCTAssertEqual(r.alternative.action, .check)
    }

    func testWeakEarlyPositionPreflopEntryRecommendsFolding() throws {
        let s = checkSnapshot(board: "", street: 0, amount: 50, position: "UTG", totals: [0, 50, 25, 0, 0, 0],
                              stacks: [1000, 1000, 1000, 1000, 1000, 1000], currentBet: 50)
        XCTAssertEqual(try analyzeDecision(s, trials: trials).alternative.action, .fold)
    }

    func testStrongAllInLosingToALaterRunoutIsNotAutomaticallyAMistake() throws {
        let s = checkSnapshot(hole: "As Ah", board: "", street: 0, action: .raise, amount: 1000,
                              totals: [0, 50, 25, 0, 0, 0], stacks: [1000, 1000, 1000, 0, 0, 0], currentBet: 50)
        let input = ReviewInput(hand: 1, hole: s.hole, decisions: [s], opponents: [],
                                outcome: outcome(profit: -1000, board: "Ks Kh Kc Qd 2s"))
        let r = try analyzeReview(input, trials: trials)
        XCTAssertEqual(r.attention, 0)
        XCTAssertEqual(r.title, "No obvious decision mistakes found")
    }

    func testVerdictsDoNotChangeWithTheShowdownWinnerOrFutureBoard() throws {
        let s = checkSnapshot(board: "2s 6h 9c", street: 1)
        let a = ReviewInput(hand: 1, hole: s.hole, decisions: [s], opponents: [],
                            outcome: outcome(profit: -200, board: "2s 6h 9c As Ah", result: "Mia wins"))
        var b = a
        b.outcome = outcome(profit: 500, board: "2s 6h 9c 7h 7c", result: "You win")
        XCTAssertEqual(try analyzeReview(a, trials: trials).steps, try analyzeReview(b, trials: trials).steps)
    }

    func testRecommendationsNeverReopenALegallyClosedRaise() throws {
        let s = checkSnapshot(hole: "As Ah", board: "", street: 0, canRaise: false)
        XCTAssertNotEqual(try analyzeDecision(s, trials: trials).alternative.action, .raise)
    }

    func testARecommendedRaiseRespectsTheLegalRange() throws {
        let s = checkSnapshot(hole: "As Ah", board: "", street: 0, amount: 50, totals: [0, 50, 25, 0, 0, 0], currentBet: 50)
        let r = try analyzeDecision(s, trials: trials)
        XCTAssertEqual(r.alternative.action, .raise)
        XCTAssertTrue((s.legal.minRaiseTo...s.legal.maxRaiseTo).contains(r.alternative.amount))
    }

    func testShortStackCallPriceExcludesUnreachableSidePots() throws {
        var s = checkSnapshot(amount: 50, totals: [50, 300, 300, 0, 0, 0], stacks: [50, 1000, 1000, 0, 0, 0],
                              pending: [0], currentBet: 300)
        s.players[2].folded = false
        let p = try callPrice(s)
        XCTAssertEqual(p.contestable, 300)
        XCTAssertEqual(p.cost, 50)
        XCTAssertEqual(p.required, 1.0 / 6)
        XCTAssertEqual(p.pots.count, 1)
        XCTAssertEqual(p.pots[0].eligible, [0, 1, 2])
    }

    func testMainAndSidePotsHaveDistinctEligibleOpponents() throws {
        var s = checkSnapshot(amount: 200, totals: [100, 100, 300, 300, 0, 0], stacks: [200, 0, 1000, 1000, 0, 0],
                              allins: [1], currentBet: 300)
        s.players[2].folded = false
        s.players[3].folded = false
        let p = try callPrice(s)
        XCTAssertEqual(p.pots.map(\.amount), [400, 600])
        XCTAssertEqual(p.pots.map(\.eligible), [[0, 1, 2, 3], [0, 2, 3]])
        XCTAssertEqual(p.contestable, 1000)
        XCTAssertEqual(p.required, 0.2)
    }

    func testUncalledRefundsAreNotRiskOrWinnings() throws {
        let s = checkSnapshot(amount: 25, totals: [25, 20, 0, 0, 0, 0], stacks: [1000, 0, 0, 0, 0, 0], allins: [1],
                              currentBet: 50, canRaise: false)
        let p = try callPrice(s)
        XCTAssertEqual(p.refundBefore, 5)
        XCTAssertEqual(p.refundAfter, 30)
        XCTAssertEqual(p.cost, 0)
        XCTAssertEqual(p.contestable, 40)
    }

    func testFoldedContributionsStayInTheCallPriceButCannotWin() throws {
        var s = checkSnapshot(amount: 100, totals: [100, 200, 200, 0, 0, 0], stacks: [1000, 1000, 0, 0, 0, 0])
        s.players[2].folded = true
        let p = try callPrice(s)
        XCTAssertEqual(p.contestable, 600)
        XCTAssertEqual(p.pots[0].eligible, [0, 1])
    }

    func testARoyalFlushOnTheBoardTiesInsteadOfInventingAnEdge() throws {
        let s = checkSnapshot(hole: "2h 3h", board: "As Ks Qs Js Ts", amount: 100, totals: [100, 200, 0, 0, 0, 0])
        let r = try analyzeDecision(s, trials: trials)
        XCTAssertEqual(r.metrics.equityLow, 0.5)
        XCTAssertEqual(r.metrics.equityHigh, 0.5)
        XCTAssertEqual(r.status, .sound)
    }

    func testReopeningAReviewGivesTheSameResult() throws {
        let s = checkSnapshot()
        XCTAssertEqual(try analyzeDecision(s, trials: trials), try analyzeDecision(s, trials: trials))
    }

    func testABlindOnlyLossHasNoFabricatedMistakes() throws {
        let input = ReviewInput(hand: 1, hole: [], decisions: [], opponents: [], outcome: outcome(profit: -25, board: ""))
        let r = try analyzeReview(input, trials: trials)
        XCTAssertTrue(r.steps.isEmpty)
        XCTAssertEqual(r.attention, 0)
        XCTAssertEqual(r.summary, "You made no decisions this hand; forced blinds can't count as mistakes.")
    }

    func testShortAllInRaiseAndAllInCallLabels() {
        var s = checkSnapshot(action: .raise, amount: 125, totals: [100, 100, 0, 0, 0, 0], stacks: [25, 1000, 0, 0, 0, 0],
                              currentBet: 100)
        XCTAssertEqual(actionLabel(s.labelStep), "2-bet short all-in to 125")
        s.action = .call
        s.legal.callAmount = 25
        XCTAssertEqual(actionLabel(s.labelStep), "All-In Call 25")
    }

    func testStartingTiersSeparatePremiumAndWeakHands() {
        XCTAssertEqual(startingTier(cards("As Ah")), 3)
        XCTAssertEqual(startingTier(cards("7s 2h")), 0)
    }

    func testInvalidTrialCountsAreRejected() {
        let s = checkSnapshot()
        for trials in [0, -5] {
            XCTAssertThrowsError(try analyzeDecision(s, trials: trials)) {
                XCTAssertEqual(($0 as? ReviewError)?.code, .invalidReviewTrials)
            }
        }
        for trials in [1, 0] {
            XCTAssertThrowsError(try compareCandidateActions(s, trials: trials)) {
                XCTAssertEqual(($0 as? ReviewError)?.code, .invalidSimulationTrials)
            }
        }
    }
}

final class ReviewLineTests: XCTestCase {
    let trials = 120

    func testButtonA7OffsuitOpenHasPositionRationaleAndDistinctSizing() throws {
        let g = try buttonGame()
        try act(g, 0, .raise, 150)
        let s = decision(g, 0)
        let r = try analyzeDecision(s, trials: trials)
        XCTAssertEqual(r.code, .lateOpen)
        XCTAssertEqual(r.status, .sound)
        XCTAssertTrue(r.reason.contains("blocks") || r.reason.contains("Late position"), r.reason)
        XCTAssertTrue(r.reason.contains("open / steal"), r.reason)
        XCTAssertFalse(r.reason.contains("No direct straight or flush draw"))
        XCTAssertNotEqual(r.recommendation, "2-bet open to 150")
        let secondary = try XCTUnwrap(r.routes.secondary)
        XCTAssertEqual(secondary.action, .raise)
        XCTAssertNotEqual(r.routes.primary.amount, secondary.amount)
        XCTAssertGreaterThanOrEqual(secondary.amount, s.legal.minRaiseTo)
        XCTAssertTrue(secondary.tradeoff.contains("range") || secondary.tradeoff.contains("risk"))
    }

    func testButtonIsolationOfALimperIsDistinctFromASteal() throws {
        let g = try buttonGame(limp: true)
        try act(g, 0, .raise, 200)
        let r = try analyzeDecision(decision(g, 0), trials: trials)
        XCTAssertEqual(r.code, .lateIsolation)
        XCTAssertTrue(r.reason.contains("limper") || r.reason.contains("isolation"), r.reason)
        XCTAssertTrue(r.plan.contains("multiway") || r.plan.contains("a lot"), r.plan)
    }

    private func threeBetAndFourBetLine() throws -> Game {
        let g = try buttonGame()
        try act(g, 0, .raise, 150)
        try act(g, 1, .call)
        try act(g, 2, .raise, 650)
        try act(g, 0, .call)
        try act(g, 1, .raise, 1800)
        try act(g, 2, .call)
        try act(g, 0, .call)
        return g
    }

    func testOpenThenCallsOfA3BetAndA4BetGetDistinctVerdicts() throws {
        let g = try threeBetAndFourBetLine()
        let a = try g.decisions.map { try analyzeDecision(ReviewDecision($0), trials: trials) }
        XCTAssertEqual(a.map(\.code), [.lateOpen, .weakThreeBetDefense, .weakFourBetDefense])
        XCTAssertEqual(a[1].alternative.action, .fold)
        XCTAssertEqual(a[2].status, .attention)
        XCTAssertTrue(a[1].reason.contains("Your earlier open was reasonable"), a[1].reason)
        XCTAssertTrue(a[2].lesson.contains("4-bet"))
        XCTAssertNotEqual(a[1].plan, a[2].plan)
    }

    func testSuitedWeakAceDefenseDiscussesRealization() throws {
        let steps = try ["Ac 7h", "Ac 7c"].map { hole -> DecisionAnalysis in
            let g = try buttonGame(hole)
            try act(g, 0, .raise, 150)
            try act(g, 1, .raise, 350)
            try act(g, 2, .fold)
            try act(g, 0, .call)
            return try analyzeDecision(decision(g, 1), trials: trials)
        }
        XCTAssertTrue(steps[0].plan.contains("offsuit"), steps[0].plan)
        XCTAssertTrue(steps[1].plan.contains("flush potential"), steps[1].plan)
        XCTAssertEqual(steps[0].status, .consider)
    }

    func testSameStreetRepeatedCallsCountAsOneEarlierStreet() throws {
        let g = try threeBetAndFourBetLine()
        try advanceStreet(g)
        while g.actor != 0 { try act(g, g.actor, .check) }
        try act(g, 0, .check)
        let c = decisionContext(decision(g, g.decisions.count - 1))
        XCTAssertEqual(c.pastCalls, 1)
        XCTAssertEqual(c.pastCallActions, 2)
    }

    func testCallingASoleAllInOpponentClosesBettingWithChipsBehind() throws {
        let g = try buttonGame()
        try act(g, 0, .raise, 150)
        g.players[1].stack = 850
        try act(g, 1, .raise, 875)
        try act(g, 2, .fold)
        try act(g, 0, .call)
        XCTAssertTrue(try callPrice(decision(g, g.decisions.count - 1)).closing)
        XCTAssertFalse(g.players[0].allin)
    }

    func testAnAllInDoesNotCloseBettingWhileAnotherLiveOpponentCanAct() throws {
        let g = try buttonGame()
        try act(g, 0, .raise, 150)
        g.players[1].stack = 850
        try act(g, 1, .raise, 875)
        try act(g, 2, .call)
        try act(g, 0, .call)
        XCTAssertFalse(try callPrice(decision(g, g.decisions.count - 1)).closing)
    }

    func testAWeakAllInCallIsExplainedAsARandomizedException() throws {
        var view = BotView(id: 1, hole: cards("7s 2h"),
                           legal: LegalActions(enabled: true, toCall: 5000, callAmount: 5000, canCheck: false,
                                               canRaise: false, minRaiseTo: 10000, fullRaiseTo: 10000, maxRaiseTo: 5000))
        view.street = 0
        view.position = "UTG"
        view.count = 6
        view.stack = 5000
        view.pot = 5000
        view.currentBet = 5000
        view.rivals = 1
        view.equity = 0.07
        view.contestable = 10000
        view.history = [HistoryEntry(street: 0, id: 0, action: .raise, amount: 5000)]
        let d = try chooseBotAction(view, BOT_PROFILES[0], freshBotMood(), .off, random: ConstantRandom(0))
        XCTAssertEqual(d.action, .call)
        XCTAssertEqual(d.trace.reason, "loose-exception")
        XCTAssertTrue(d.trace.exceptions.contains("insufficient-equity"))
        XCTAssertTrue(d.trace.checks.allSatisfy(\.selected))
        var trace = d.trace
        trace.view = view
        let e = explainOpponent(BotDecisionRecord(id: 1, name: "Mia", hand: 1, sequence: 1, action: d.action,
                                                  amount: d.amount, trace: trace))
        XCTAssertTrue(e.detail.contains("mistake"), e.detail)
        XCTAssertTrue(e.warning.contains("random range"), e.warning)
        XCTAssertEqual(e.title, "Random leeway kept a marginal action")
        XCTAssertEqual(e.made, "Preflop hand")
    }

    func testSettledBotTracesAreSeparateFromHeroGrading() throws {
        let g = try newGame()
        g.dealer = 2
        try startHand(g, random: SeededRandom(91))
        let rng = LCGRandom(91), before = wealth(g)
        while g.phase != .done {
            if g.phase == .between { try advanceStreet(g) }
            else if g.actor == 0 { try act(g, 0, legalActions(g).canCheck ? .check : .call) }
            else { try playBotTurn(g, random: rng) }
        }
        XCTAssertEqual(chips(g), before)
        let input = try createReviewInput(g)
        XCTAssertFalse(input.opponents.isEmpty)
        let steps = try analyzeReview(input, trials: trials).steps
        var altered = input
        var fake = BotTrace()
        fake.reason = "fake"
        fake.view = BotView(id: 1, hole: cards("As Ah"), legal: .disabled)
        altered.opponents = [BotDecisionRecord(id: 1, name: "Mia", hand: 1, sequence: 1, action: .call, amount: nil,
                                               trace: fake)]
        altered.outcome.profit = -9999
        altered.outcome.board = cards("2s 3h 4c 5d 6s")
        XCTAssertEqual(steps, try analyzeReview(altered, trials: trials).steps)
        try restartHand(g)
        XCTAssertTrue(g.botDecisions.isEmpty)
        XCTAssertTrue(g.decisions.isEmpty)
        XCTAssertFalse(input.opponents.isEmpty)
        // Every executed bot record can be explained after the hand.
        for record in input.opponents {
            let e = explainOpponent(record)
            XCTAssertFalse(e.title.isEmpty)
            XCTAssertFalse(e.reasons.isEmpty)
        }
    }

    func testQ7SuitedUnderTheGunAcknowledgesTheSuitAndSimulatesTheOpen() throws {
        let g = try newGame()
        g.dealer = 2
        try startHand(g, random: SeededRandom(5))
        g.players[0].hole = cards("Qs 7s")
        try act(g, 0, .raise, 150)
        let r = try analyzeDecision(decision(g, 0), trials: trials)
        XCTAssertEqual(r.code, .earlySuitedEntry)
        XCTAssertEqual(r.status, .consider)
        XCTAssertTrue(r.reason.contains("genuinely suited"), r.reason)
        XCTAssertFalse(r.reason.contains("marginal offsuit hands have a harder time"))
        XCTAssertEqual(r.routes.secondary?.action, .raise)
        let simulation = try XCTUnwrap(r.simulation)
        XCTAssertGreaterThanOrEqual(simulation.rows.count, 4)
    }
}

final class CounterfactualTests: XCTestCase {
    private func limpSnapshot(seed: UInt32 = 11) throws -> ReviewDecision {
        let g = try newGame()
        g.dealer = 2
        try startHand(g, random: SeededRandom(seed))
        try act(g, 0, .call)
        return decision(g, 0)
    }

    func testSimulationIsDeterministicPublicOnlyAndDoesNotMutateTheSnapshot() throws {
        let s = try limpSnapshot()
        let saved = s
        let a = try compareCandidateActions(s, [], trials: 6)
        XCTAssertEqual(s, saved)
        XCTAssertEqual(a, try compareCandidateActions(s, [], trials: 6))
        XCTAssertEqual(a.rows[0].action.action, .fold)
        XCTAssertTrue(a.rows[0].scenarios.allSatisfy { $0.ev == 0 && $0.margin == 0 })
        XCTAssertTrue(a.rows.allSatisfy { $0.scenarios.allSatisfy { $0.ev.isFinite && $0.margin.isFinite } })
        XCTAssertEqual(a.rows[0].scenarios.map(\.name), ["Random range", "Public-action-weighted range"])
    }

    func testCandidatesRespectClosedRaisingAndCappedShortStackCalls() throws {
        var s = try limpSnapshot()
        s.legal.canRaise = false
        s.legal.callAmount = 25
        s.stack = 25
        let actions = candidateActions(s, [CandidateAction(.raise, 5000)])
        XCTAssertTrue(actions.allSatisfy { $0.action != .raise })
        XCTAssertEqual(actions.first { $0.action == .call }?.amount, 25)
    }

    func testAnEarlierFlatCallerIsNotTreatedAsDefendingALaterUnanswered3Bet() throws {
        var s = try limpSnapshot()
        let h = cards("Qs 7s")
        s.history = [HistoryEntry(street: 0, id: 2, action: .raise, amount: 150),
                     HistoryEntry(street: 0, id: 1, action: .call, amount: 125)]
        let before = rangeWeight(h, s, opponent: 1)
        s.history.append(HistoryEntry(street: 0, id: 3, action: .raise, amount: 650))
        XCTAssertEqual(rangeWeight(h, s, opponent: 1), before)
        s.history.append(HistoryEntry(street: 0, id: 1, action: .call, amount: 500))
        XCTAssertLessThan(rangeWeight(h, s, opponent: 1), before)
    }

    func testAnOpenerWhoCallsA3BetGetsTheDefenseRange() throws {
        var s = try limpSnapshot()
        let h = cards("Qs 7s")
        s.history = [HistoryEntry(street: 0, id: 1, action: .raise, amount: 150)]
        let before = rangeWeight(h, s, opponent: 1)
        s.history += [HistoryEntry(street: 0, id: 2, action: .raise, amount: 650),
                      HistoryEntry(street: 0, id: 1, action: .call, amount: 500)]
        XCTAssertLessThan(rangeWeight(h, s, opponent: 1), before)
    }

    func testARoyalBoardSplitsExactlyInTheRolloutUsingPotEligibility() throws {
        let g = try newGame()
        g.dealer = 2
        try startHand(g, random: SeededRandom(13))
        while g.street < 3 {
            if g.phase == .between { try advanceStreet(g) } else { try act(g, g.actor, .call) }
        }
        g.board = cards("As Ks Qs Js Ts")
        g.players[0].hole = cards("2h 3h")
        while g.actor != 0 { try act(g, g.actor, .check) }
        try act(g, 0, .check)
        let s = decision(g, g.decisions.count - 1)
        let result = try compareCandidateActions(s, [], trials: 6)
        let row = try XCTUnwrap(result.rows.first { $0.action.action == .check })
        XCTAssertTrue(row.scenarios.allSatisfy { $0.ev == 50 }, "\(row.scenarios.map(\.ev))")
    }

    func testCancellationStopsAReviewBetweenTrials() throws {
        let s = try limpSnapshot()
        struct Cancelled: Error {}
        var calls = 0
        XCTAssertThrowsError(try analyzeDecision(s, trials: 30, checkCancellation: {
            calls += 1
            if calls > 3 { throw Cancelled() }
        })) { XCTAssertTrue($0 is Cancelled) }
        XCTAssertEqual(calls, 4)
        let input = ReviewInput(hand: 1, hole: s.hole, decisions: [s], opponents: [], outcome: outcome(profit: 0, board: ""))
        XCTAssertThrowsError(try analyzeReview(input, trials: 30, checkCancellation: { throw Cancelled() }))
    }
}
