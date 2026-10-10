import XCTest
@testable import PokerCore

final class BotProfileTests: XCTestCase {
    func testNineProfilesWithParametersAndEnglishCopy() {
        XCTAssertEqual(BOT_PROFILES.map(\.id), ["balanced", "tan", "st", "zang", "peter", "abao", "viktor", "jungleman", "dwan"])
        for p in BOT_PROFILES {
            XCTAssertEqual(p.axes.count, 5)
            XCTAssertEqual(p.sizing.count, 2)
            XCTAssertLessThan(p.sizing[0], p.sizing[1])
            for text in [p.name, p.short, p.tag, p.description, p.evidence] + p.sources.map(\.label) {
                XCTAssertFalse(text.unicodeScalars.contains { (0x3000...0x9FFF).contains($0.value) || (0xFF00...0xFFEF).contains($0.value) },
                               "Untranslated copy: \(text)")
            }
        }
        XCTAssertEqual(getBotProfile("unknown").id, "balanced")
        XCTAssertEqual(getBotProfile("peter").axes, [92, 88, 72, 84, 18])
        XCTAssertEqual(PROFILE_AXES, ["Range Width", "Aggression", "Bluffing", "Calling Down", "Trapping"])
        XCTAssertEqual(MoodKind.frustrated.label, "Chasing Losses")
        XCTAssertEqual(EmotionMode.lively.label, "Pronounced")
    }

    func testSavedSettingsRejectUnknownProfilesAndMalformedModes() {
        let defaults = defaultBotSettings()
        XCTAssertEqual(defaults.emotionMode, .subtle)
        XCTAssertEqual(defaults.assignments, Dictionary(uniqueKeysWithValues: (1...8).map { ($0, "balanced") }))
        XCTAssertEqual(sanitizeBotSettings(nil), defaults)
        XCTAssertEqual(sanitizeBotSettings(42), defaults)
        XCTAssertEqual(sanitizeBotSettings("lively"), defaults)
        XCTAssertEqual(sanitizeBotSettings(["emotionMode": "toString"]), defaults)
        XCTAssertEqual(sanitizeBotSettings(["emotionMode": "Lively"]).emotionMode, .subtle)
        XCTAssertEqual(sanitizeBotSettings(["emotionMode": "off"]).emotionMode, .off)
        let mixed = sanitizeBotSettings([
            "emotionMode": "lively",
            "assignments": ["0": "tan", "1": "unknown", "2": "TAN", "3": "dwan", "5": 7, "9": "st", "8": "viktor"] as [String: Any],
        ] as [String: Any])
        XCTAssertEqual(mixed.emotionMode, .lively)
        XCTAssertEqual(mixed.assignments[3], "dwan")
        XCTAssertEqual(mixed.assignments[8], "viktor")
        XCTAssertEqual(mixed.assignments.filter { $0.value == "balanced" }.count, 6)
        XCTAssertNil(mixed.assignments[0])
        XCTAssertNil(mixed.assignments[9])
        XCTAssertEqual(sanitizeBotSettings(["assignments": ["x", "tan", "st"]]).assignments[2], "st")
        XCTAssertEqual(sanitizeBotSettings(BotSettings(emotionMode: .off, assignments: [4: "abao"])).assignments[4], "abao")
    }

    func testSanitizeFixture() throws {
        let fixture = try loadFixture("bot-profiles.json")
        let cases = try XCTUnwrap(fixture["sanitizeBotSettings"] as? [[String: Any]])
        for c in cases {
            let output = c["output"] as! [String: Any]
            let result = sanitizeBotSettings(c["input"] is NSNull ? nil : c["input"])
            XCTAssertEqual(result.emotionMode.rawValue, output["emotionMode"] as! String, "\(c)")
            let assignments = output["assignments"] as! [String: String]
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: assignments.map { (Int($0.key)!, $0.value) }), result.assignments, "\(c)")
        }
        for entry in try XCTUnwrap(fixture["startingPercentile"] as? [[String: Any]]) {
            let hole = (entry["hole"] as! [String]).map { Card(key: $0)! }
            XCTAssertEqual(startingPercentile(hole), fixtureDouble(entry["percentile"]), entry["hand"] as! String)
        }
    }

    func testAReassignedProfileStartsASeparateSample() throws {
        let g = try newGame()
        g.players[1].botStats.hands = 20
        g.players[1].botStats.vpip = 10
        try applyBotSettings(g, ["assignments": ["1": "peter"]])
        XCTAssertEqual(g.players[1].botProfile, "peter")
        XCTAssertEqual(g.players[1].botStats, freshBotStats())
        try applyBotSettings(g, ["assignments": ["1": "peter"], "emotionMode": "off"])
        XCTAssertEqual(g.emotionMode, .off)
    }
}

final class MoodTests: XCTestCase {
    func testLossWinAndPressureTriggersAreBoundedCooledAndCanBeDisabled() {
        var p = try! newGame().players[1]
        XCTAssertNil(finishBotHand(&p, profit: -1249, mode: .subtle))
        XCTAssertEqual(finishBotHand(&p, profit: -1250, mode: .subtle)?.kind, .frustrated)
        XCTAssertNil(finishBotHand(&p, profit: -5000, mode: .subtle), "Cooldown prevents repeated triggers")
        var q = BotMood()
        XCTAssertEqual(finishBotHand(playerId: 2, mood: &q, profit: -1250, mode: .lively),
                       MoodEvent(kind: .cautious, reason: "Lost at least 25 BB net in a single hand"))
        var off = BotMood()
        XCTAssertNil(finishBotHand(playerId: 1, mood: &off, profit: -5000, mode: .off))
        XCTAssertEqual(off.kind, .steady)
        var winner = BotMood()
        XCTAssertNil(finishBotHand(playerId: 1, mood: &winner, profit: 500, mode: .subtle))
        XCTAssertEqual(finishBotHand(playerId: 1, mood: &winner, profit: 500, mode: .subtle)?.kind, .confident)
        var streak = BotMood()
        for _ in 0..<2 { XCTAssertNil(finishBotHand(playerId: 3, mood: &streak, profit: -250, mode: .subtle)) }
        XCTAssertEqual(finishBotHand(playerId: 3, mood: &streak, profit: -250, mode: .subtle)?.reason,
                       "Lost at least 5 BB net in each of three straight hands")
        var mood = freshBotMood()
        recordPressureFold(&mood, raiser: 2, mode: .subtle)
        recordPressureFold(&mood, raiser: 3, mode: .subtle)
        XCTAssertNil(recordPressureFold(&mood, raiser: 2, mode: .subtle))
        XCTAssertNil(recordPressureFold(&mood, raiser: 2, mode: .subtle))
        XCTAssertEqual(recordPressureFold(&mood, raiser: 2, mode: .subtle)?.kind, .reactive)
        XCTAssertEqual(mood.pressureFolds, [2: 0])
        XCTAssertNil(recordPressureFold(&mood, raiser: nil, mode: .subtle))
    }

    func testMoodDecaysBackToSteady() {
        var mood = BotMood()
        _ = finishBotHand(playerId: 1, mood: &mood, profit: -2000, mode: .lively)
        XCTAssertEqual(mood.remaining, 3)
        for _ in 0..<2 { decayBotMood(&mood) }
        XCTAssertEqual(mood.kind, .frustrated)
        decayBotMood(&mood)
        XCTAssertEqual(mood.kind, .steady)
        XCTAssertEqual(mood.reason, "")
        XCTAssertEqual(mood.cooldown, 1)
    }

    func testEmotionsAdjustPolicyControlsWithASmallerSubtleEffect() {
        let profile = BOT_PROFILES[1]
        var mood = BotMood()
        mood.kind = .frustrated
        XCTAssertEqual(effectiveBotAxes(profile, mood, .off), profile.axes.map(Double.init))
        let mild = effectiveBotAxes(profile, mood, .subtle), strong = effectiveBotAxes(profile, mood, .lively)
        XCTAssertGreaterThan(mild[0], Double(profile.axes[0]))
        XCTAssertGreaterThan(strong[0], mild[0])
        XCTAssertLessThan(strong[4], mild[4])
        XCTAssertEqual(strong[1], 100, "axes are clamped to 0...100")
    }

    func testAnInterveningHandWithoutPressureBreaksTheFoldStreak() throws {
        let g = try newGame()
        let rng = SeededRandom(41)
        for hand in 0..<5 {
            g.dealer = 2
            try startHand(g, random: rng)
            XCTAssertEqual(g.actor, 0)
            if hand % 2 == 1 { try act(g, 0, .fold) } else { try act(g, 0, .raise, 100) }
            while g.phase != .done { try act(g, g.actor, .fold) }
        }
        XCTAssertEqual(g.players[1].botMood.kind, .steady)
    }

    func testConsecutivePressureFoldsLogASimulatedMood() throws {
        let g = try newGame()
        let rng = SeededRandom(42)
        for _ in 0..<3 {
            g.dealer = 2
            try startHand(g, random: rng)
            try act(g, 0, .raise, 100)
            while g.phase != .done { try act(g, g.actor, .fold) }
        }
        XCTAssertEqual(g.players[1].botMood.kind, .reactive)
        XCTAssertTrue(g.logs.contains {
            $0.text == "Mia simulated mood: Fighting Back · Folded to the same opponent's raise three hands in a row" && $0.player == 1
        })
    }

    func testUncalledShoveRefundsAreNotLossesAndBlindsAreNotVPIP() throws {
        let g = try newGame()
        g.dealer = 3
        try startHand(g, random: SeededRandom(43))
        XCTAssertEqual(g.actor, 1)
        try act(g, 1, .raise, 5000)
        while g.phase != .done { try act(g, g.actor, .fold) }
        XCTAssertTrue(g.refunds.contains { $0.id == 1 })
        XCTAssertEqual(g.players[1].botMood.kind, .steady)
        XCTAssertEqual([g.players[1].botStats.hands, g.players[1].botStats.vpip, g.players[1].botStats.pfr], [1, 1, 1])
        for p in g.players.dropFirst(2) { XCTAssertEqual(p.botStats.vpip, 0) }
    }
}

final class BotDecisionTests: XCTestCase {
    func testAllProfilesAndEmotionStrengthsPlayLegalHandsAndConserveChips() throws {
        for count in 5...9 {
            for mode in EmotionMode.allCases {
                let g = try newGame(count)
                var assignments: [String: Any] = [:]
                for id in 1..<count { assignments[String(id)] = BOT_PROFILES[id % BOT_PROFILES.count].id }
                try applyBotSettings(g, ["assignments": assignments, "emotionMode": mode.rawValue])
                for hand in 0..<4 {
                    // Unequal stacks exercise short raises, capped calls and multiple pots.
                    for i in g.players.indices { g.players[i].stack = 300 + i * 175 }
                    try startHand(g, random: SeededRandom(seed: count * 1000 + hand))
                    let before = chips(g) + potSize(g)
                    try finishWithBots(g, LCGRandom(UInt32(100 + count + hand)))
                    XCTAssertEqual(chips(g), before)
                }
            }
        }
    }

    func testNoProfileRaisesWhenAShortAllInHasNotReopenedAction() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(51))
        let first = g.actor
        try act(g, first, .raise, 100)
        let second = g.actor
        g.players[second].stack = 125 - g.players[second].bet
        try act(g, second, .raise, 125)
        while g.actor != first { try act(g, g.actor, .call) }
        XCTAssertFalse(legalActions(g).canRaise)
        for profile in BOT_PROFILES {
            g.players[first].botProfile = profile.id
            for seed in 0..<10 {
                XCTAssertNotEqual(try botDecision(g, random: LCGRandom(UInt32(seed))).action, .raise)
            }
        }
    }

    func testDecisionViewIsTheActorsPublicPerspective() throws {
        let g = try newGame(9)
        try startHand(g, random: SeededRandom(52))
        let expected = try botDecision(g, random: SeededRandom(50))
        // Rewriting every hidden card and the future deck cannot change the decision.
        for i in g.players.indices where i != g.actor { g.players[i].hole = cards("2c 3d") }
        g.deck = Array(g.deck.reversed())
        let again = try botDecision(g, random: SeededRandom(50))
        XCTAssertEqual(again, expected)
        let view = try XCTUnwrap(expected.trace.view)
        XCTAssertEqual(view.hole, g.players[g.actor].hole)
        XCTAssertEqual(view.opponents?.count, 8)
        XCTAssertEqual(view.equityTrials, 28)
        XCTAssertEqual(view.position, "UTG")
    }

    func testEquitySamplingConsumesTheDocumentedNumberOfDraws() {
        let counter = CountingRandom(SeededRandom(53))
        let equity = estimateEquity(cards("As Ah"), cards("2c 7d Js"), rivals: 2, trials: 10, random: counter)
        XCTAssertEqual(counter.draws, 10 * 46)
        XCTAssertGreaterThan(equity, 0.5)
        XCTAssertEqual(estimateEquity(cards("As Ah"), cards("Ac Ad Kc Kd 2h"), rivals: 1, trials: 5, random: SeededRandom(1)), 1)
    }

    func testInvalidBotRequestsThrow() throws {
        let g = try newGame()
        assertThrowsPoker(.botCannotAct) { _ = try botDecision(g) }
        try startHand(g, random: SeededRandom(54))
        assertThrowsPoker(.invalidTrials) { _ = try botDecision(g, random: SeededRandom(1), trials: 0) }
        g.dealer = 2
        g.actor = 0
        assertThrowsPoker(.heroBotExecutor) { _ = try planBotTurn(g, random: SeededRandom(1)) }
    }

    func testStartingPercentileOrdering() {
        XCTAssertEqual(startingPercentile(cards("As Ah")), 0)
        XCTAssertLessThan(startingPercentile(cards("As Ks")), startingPercentile(cards("As Kd")))
        XCTAssertGreaterThan(startingPercentile(cards("7c 2d")), startingPercentile(cards("As Kd")))
    }

    func testBoardFeatures() {
        let flushDraw = botBoardFeatures(cards("As 5s"), cards("Ks 9s 2d"), evaluate(cards("As 5s Ks 9s 2d")).score)
        XCTAssertTrue(flushDraw.draw)
        XCTAssertTrue(flushDraw.wet)
        let overpair = botBoardFeatures(cards("Qs Qh"), cards("9c 5d 2h"), evaluate(cards("Qs Qh 9c 5d 2h")).score)
        XCTAssertTrue(overpair.overpair)
        XCTAssertFalse(overpair.draw)
        let wheelDraw = botBoardFeatures(cards("Ac 2c"), cards("3d 4h 9s"), evaluate(cards("Ac 2c 3d 4h 9s")).score)
        XCTAssertTrue(wheelDraw.draw)
    }
}

final class BotPlanTests: XCTestCase {
    func testPlanningDoesNotMutateTheGameAndExecutionReusesTheSelectedAction() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(61))
        let before = g.state
        let expected = try botDecision(g, random: LCGRandom(42))
        let plan = try planBotTurn(g, random: LCGRandom(42), timingRandom: LCGRandom(55))
        XCTAssertEqual(g.state, before)
        XCTAssertGreaterThanOrEqual(plan.delayMs, BOT_THINK_LIMITS.minimum)
        XCTAssertLessThanOrEqual(plan.delayMs, BOT_THINK_LIMITS.maximum)
        let result = try executeBotTurn(g, plan, waitedMs: plan.delayMs)
        XCTAssertEqual(result.action, expected.action)
        XCTAssertEqual(result.amount, expected.amount)
        XCTAssertEqual(g.botDecisions.count, 1)
        XCTAssertEqual(g.history.count, before.history.count + 1)
        let thinking = try XCTUnwrap(g.botDecisions[0].trace.thinking)
        XCTAssertEqual(thinking.durationMs, plan.delayMs)
        XCTAssertEqual(thinking.waitedMs, plan.delayMs)
        XCTAssertFalse(thinking.expedited)
        XCTAssertEqual(g.botDecisions[0].sequence, 1)
        XCTAssertNotNil(g.botDecisions[0].trace.view)
        assertThrowsPoker(.staleBotPlan) { try executeBotTurn(g, plan) }
    }

    func testDifferentTimingRandomnessLeavesTheActionUnchanged() throws {
        let first = try newGame()
        try startHand(first, random: SeededRandom(62))
        let second = first.deepCopy()
        let p1 = try planBotTurn(first, random: LCGRandom(44), timingRandom: ConstantRandom(0.1))
        let p2 = try planBotTurn(second, random: LCGRandom(44), timingRandom: ConstantRandom(0.8))
        XCTAssertNotEqual(p1.delayMs, p2.delayMs)
        let a = try executeBotTurn(first, p1), b = try executeBotTurn(second, p2)
        XCTAssertEqual(a, b)
    }

    func testPlansAreRejectedAfterAnotherActionGameDifficultyChangeOrReplay() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(63))
        let plan = try planBotTurn(g, random: LCGRandom(90))
        XCTAssertTrue(isBotTurnCurrent(g, plan))
        XCTAssertFalse(isBotTurnCurrent(g.deepCopy(), plan))
        g.difficulty = .hard
        XCTAssertFalse(isBotTurnCurrent(g, plan))
        g.difficulty = .normal
        XCTAssertTrue(isBotTurnCurrent(g, plan))
        try act(g, g.actor, .call)
        XCTAssertFalse(isBotTurnCurrent(g, plan))
        while g.phase == .playing { try act(g, g.actor, .fold) }
        try restartHand(g)
        XCTAssertFalse(isBotTurnCurrent(g, plan))
        assertThrowsPoker(.staleBotPlan) { try executeBotTurn(g, plan) }
        XCTAssertTrue(g.botDecisions.isEmpty)
    }

    func testPlanFromAnEarlierReplayAttemptIsStale() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(64))
        try finish(g, .fold)
        try restartHand(g)
        let plan = try planBotTurn(g, random: SeededRandom(1))
        try finish(g, .fold)
        try restartHand(g)
        XCTAssertFalse(isBotTurnCurrent(g, plan), "same seat, street and sequence, but a later attempt")
    }

    func testInstantExecutionRecordsExpeditedThinking() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(65))
        try playBotTurn(g, random: LCGRandom(88))
        XCTAssertEqual(g.botDecisions.count, 1)
        XCTAssertEqual(g.botDecisions[0].trace.thinking?.expedited, true)
        XCTAssertEqual(g.botDecisions[0].trace.thinking?.waitedMs, 0)
    }

    func testThinkingTimeIsBoundedAndConsumesFourOrFiveDraws() throws {
        let g = try newGame()
        try startHand(g, random: SeededRandom(66))
        let decision = try botDecision(g, random: SeededRandom(2))
        for seed in UInt32(0)..<50 {
            let counter = CountingRandom(SeededRandom(seed))
            let thinking = botThinkingTime(decision, random: counter)
            XCTAssertTrue((BOT_THINK_LIMITS.minimum...BOT_THINK_LIMITS.maximum).contains(thinking.durationMs))
            XCTAssertEqual(counter.draws, thinking.acting == .deliberate ? 5 : 4)
            XCTAssertEqual(thinking.model, "context-pacing-v1")
        }
    }

    func testManySeededAllBotHandsConserveChips() throws {
        let rng = SeededRandom(2025)
        for count in 5...9 {
            let g = try newGame(count)
            try applyBotSettings(g, ["emotionMode": "lively",
                                     "assignments": Dictionary(uniqueKeysWithValues: (1...8).map { (String($0), BOT_PROFILES[$0].id) })])
            g.difficulty = Difficulty.allCases[count % 3]
            var total = chips(g)
            for _ in 0..<25 {
                let rebuys = g.players.filter { $0.stack == 0 }.count
                try startHand(g, random: rng)
                total += rebuys * STARTING_STACK
                while g.phase != .done {
                    XCTAssertEqual(wealth(g), total)
                    if g.phase == .between {
                        try advanceStreet(g)
                    } else if g.actor == 0 {
                        let d = try botDecision(g, random: rng)
                        try act(g, 0, d.action, d.amount)
                    } else {
                        let plan = try planBotTurn(g, random: rng, timingRandom: rng)
                        try executeBotTurn(g, plan)
                    }
                }
                XCTAssertEqual(chips(g), total)
                XCTAssertEqual(g.payouts.reduce(0, +), potSize(g))
            }
        }
    }
}

/// Behavioral invariants ported from Android `BotsTest` and `BotTimingTest` (themselves ports of the
/// reference `bot-timing`, `bot-entry` and `bot-profiles` unit tests). The shared decision fixture
/// covers the arithmetic case by case; these cover the cross-sample properties.
final class BotBehaviorTests: XCTestCase {
    private let raiseLegal = LegalActions(enabled: true, toCall: 50, callAmount: 50, canCheck: false, canRaise: true,
                                          minRaiseTo: 100, fullRaiseTo: 100, maxRaiseTo: 5000)

    /// View V from the reference profile tests: 9♠7♠ in the cutoff facing the big blind.
    private var viewV: BotView {
        var v = BotView(id: 1, hole: cards("9s 7s"), legal: raiseLegal)
        v.street = 0
        v.position = "CO"
        v.count = 6
        v.stack = 5000
        v.bet = 0
        v.pot = 75
        v.currentBet = 50
        v.contestable = 125
        v.rivals = 5
        v.equity = 0.35
        v.difficulty = .hard
        v.opponents = nil
        return v
    }

    /// The reference `smallOpen` view: a 3 BB open from seat 0, deep stacks, action on the cutoff.
    private func smallOpen(_ hole: String = "7s 6s", count: Int = 6) -> BotView {
        var v = BotView(id: 1, hole: cards(hole),
                        legal: LegalActions(enabled: true, toCall: 150, callAmount: 150, canRaise: true,
                                            minRaiseTo: 250, fullRaiseTo: 250, maxRaiseTo: 5000))
        v.street = 0
        v.position = "CO"
        v.count = count
        v.stack = 5000
        v.bet = 0
        v.pot = 225
        v.currentBet = 150
        v.contestable = 375
        v.rivals = 5
        v.equity = 0.05
        v.difficulty = .hard
        v.history = [HistoryEntry(street: 0, id: 0, action: .raise, amount: 150)]
        v.opponents = [0, 2, 3, 4, 5].map {
            BotOpponent(id: $0, stack: $0 == 0 ? 4850 : 5000, bet: $0 == 0 ? 150 : 0, allin: false)
        }
        return v
    }

    private func decide(_ view: BotView, _ profile: String = "balanced",
                        _ random: RandomSource = ConstantRandom(0.9)) throws -> BotDecision {
        try chooseBotAction(view, getBotProfile(profile), freshBotMood(), .off, random: random)
    }

    /// The reference timing sample: a cheap button call, heads-up.
    private func sample(_ action: PokerAction = .call, _ amount: Int? = nil,
                        trace: (inout BotTrace) -> Void = { _ in },
                        view: (inout BotView) -> Void = { _ in }) -> BotDecision {
        var v = BotView(id: 1, hole: cards("Ah Kd"), legal: LegalActions(enabled: true, toCall: 50, callAmount: 50))
        v.street = 0
        v.position = "BTN"
        v.rivals = 1
        v.stack = 5000
        v.bet = 0
        v.pot = 100
        v.currentBet = 50
        v.contestable = 150
        v.opponents = [BotOpponent(id: 2, stack: 5000, bet: 50, allin: false)]
        view(&v)
        var t = BotTrace()
        t.equity = 0.6
        t.odds = 0.1
        t.callTolerance = 0
        t.percentile = 0.05
        t.range = 0.45
        t.axes = [50, 50, 40, 50, 20]
        t.mode = .off
        t.reason = "price-continue"
        t.cheapEntry = false
        t.admitted = true
        t.view = v
        trace(&t)
        return BotDecision(action: action, amount: amount, trace: t)
    }

    private func half(_ d: BotDecision) -> BotThinking { botThinkingTime(d, random: ConstantRandom(0.5)) }

    // MARK: Timing

    func testTimingMatchesTheReferenceSamples() {
        let base = half(sample())
        XCTAssertEqual(base.durationMs, 2154)
        XCTAssertEqual(base.acting, .neutral)
        XCTAssertEqual(base.factors, ThinkingFactors(closeness: 0, texture: 0, route: 0, position: 0,
                                                     commitment: 0.006999999999999999, sizing: 0,
                                                     effectiveStack: 4950, spr: 33))
        let deliberate = botThinkingTime(sample(), random: ConstantRandom(0.1))
        XCTAssertEqual(deliberate.durationMs, 1992)
        XCTAssertEqual(deliberate.acting, .deliberate)
        let seeded = botThinkingTime(sample(), random: LCGRandom(2341))
        XCTAssertEqual(seeded.durationMs, 2271)
        XCTAssertEqual(seeded.acting, .neutral)
    }

    func testTimingRespondsToClosenessDrawsTextureActionLinePositionAndCommitment() {
        let base = half(sample()).durationMs
        XCTAssertGreaterThan(half(sample(trace: { $0.equity = 0.12 })).durationMs, base)
        let draw = sample(view: {
            $0.features = BoardFeatures(wet: true, draw: true, overpair: true)
            $0.board = cards("8s 9s Th")
        })
        XCTAssertGreaterThan(half(draw).durationMs, base)
        let line = sample(view: {
            $0.street = 1
            $0.history = [HistoryEntry(street: 0, id: 2, action: .raise),
                          HistoryEntry(street: 1, id: 2, action: .check),
                          HistoryEntry(street: 1, id: 2, action: .raise)]
        })
        XCTAssertGreaterThan(half(line).factors.route, 0.6)
        XCTAssertGreaterThan(half(sample(view: { $0.position = "SB"; $0.rivals = 5 })).durationMs, base)
        let pressure = sample(view: { $0.legal.toCall = 4000; $0.legal.callAmount = 4000 })
        XCTAssertGreaterThan(half(pressure).factors.commitment, half(sample()).factors.commitment)
    }

    func testAReRaiseAfterTheActorsOwnRaiseAddsRouteAndPositionFollowsActionOrder() {
        let single = [HistoryEntry(street: 1, id: 2, action: .raise)]
        let without = half(sample(view: { $0.street = 1; $0.history = single }))
        let withOwn = half(sample(view: {
            $0.street = 1
            $0.history = [HistoryEntry(street: 1, id: 1, action: .raise)] + single
        }))
        XCTAssertGreaterThan(withOwn.factors.route, without.factors.route)
        let inPosition = half(sample(view: { $0.street = 1; $0.history = single; $0.inPosition = true }))
        let outOfPosition = half(sample(view: { $0.street = 1; $0.history = single; $0.inPosition = false }))
        XCTAssertGreaterThan(outOfPosition.durationMs, inPosition.durationMs)
    }

    func testAShortAllInDoesNotCollapseADeepOpponentsEffectiveStack() {
        let d = sample(view: {
            $0.history = [HistoryEntry(street: 0, id: 2, action: .raise)]
            $0.opponents = [BotOpponent(id: 2, stack: 0, bet: 50, allin: true),
                            BotOpponent(id: 3, stack: 3000, bet: 50, allin: false)]
        })
        XCTAssertEqual(half(d).factors.effectiveStack, 3000)
    }

    func testPacingIsBoundedAndVariedWithOverlappingValueBluffTrapAndFoldPauses() {
        var ranges: [(Int, Int)] = []
        for reason in ["value-raise", "pure-bluff", "trap", "outside-range"] {
            let action: PokerAction = reason == "trap" ? .check : reason == "outside-range" ? .fold : .raise
            var times: [Int] = []
            var acting = Set<Acting>()
            for seed in 1...150 {
                let result = botThinkingTime(sample(action, 150, trace: { $0.reason = reason }),
                                             random: LCGRandom(UInt32(seed * 2341)))
                XCTAssertTrue((BOT_THINK_LIMITS.minimum...BOT_THINK_LIMITS.maximum).contains(result.durationMs))
                times.append(result.durationMs)
                acting.insert(result.acting)
            }
            XCTAssertGreaterThan(Set(times).count, 100, reason)
            XCTAssertEqual(acting, [.deliberate, .quick, .neutral], reason)
            ranges.append((times.min()!, times.max()!))
        }
        XCTAssertLessThan(ranges.map(\.0).max()!, ranges.map(\.1).min()!, "pause ranges overlap")
        let cautious = { (mode: EmotionMode) in
            self.sample(trace: { $0.mode = mode; $0.mood = TraceMood(kind: .cautious) })
        }
        XCTAssertGreaterThan(half(cautious(.lively)).durationMs, half(sample()).durationMs)
        XCTAssertEqual(half(cautious(.off)), half(sample()))
    }

    // MARK: Entry

    func testTheReferenceProfileFixturesChooseTheSameActions() throws {
        let balanced = try decide(viewV, "balanced", LCGRandom(100))
        XCTAssertEqual(balanced.action, .call)
        XCTAssertEqual(balanced.trace.reason, "affordable-entry")
        XCTAssertEqual(balanced.trace.range, 0.6766, accuracy: 1e-12)
        XCTAssertTrue(balanced.trace.cheapEntry)
        let st = try decide(viewV, "st", LCGRandom(100))
        XCTAssertEqual(st.action, .call)
        XCTAssertEqual(st.trace.range, 0.60704, accuracy: 1e-12)
        let peter = try decide(viewV, "peter", LCGRandom(100))
        XCTAssertEqual(peter.action, .raise)
        XCTAssertEqual(peter.amount, 150)
        XCTAssertEqual(peter.trace.reason, "value-raise")
        XCTAssertEqual(peter.trace.range, 0.95)
    }

    func testStyleDifferencesChangeEntryAndValueTrapBehavior() throws {
        func count(_ profile: String, _ view: BotView, _ action: PokerAction) throws -> Int {
            try (0..<300).filter { try decide(view, profile, LCGRandom(UInt32($0 + 100))).action == action }.count
        }
        XCTAssertGreaterThan(try count("peter", viewV, .raise), try count("st", viewV, .raise))
        var value = viewV
        value.street = 2
        value.equity = 0.9
        value.rivals = 1
        value.legal.toCall = 0
        value.legal.callAmount = 0
        value.legal.canCheck = true
        XCTAssertGreaterThan(try count("st", value, .check), try count("peter", value, .check))
    }

    func testDeepSmallOpensKeepPlayableCallsWithoutTurningAdmissionsInto3Bets() throws {
        for count in [6, 9] {
            for hole in ["7s 6s", "Qs 7s", "2s 2h", "As 5s", "Ks Jh"] {
                let d = try decide(smallOpen(hole, count: count))
                XCTAssertEqual(d.action, .call, "\(count) players, \(hole)")
                XCTAssertEqual(d.trace.reason, "affordable-open")
                XCTAssertTrue(d.trace.affordableRangePassed)
                XCTAssertFalse(d.trace.cheapRangePassed)
                XCTAssertFalse(d.trace.value)
                XCTAssertFalse(d.trace.checks.contains { $0.code == "insufficient-equity" })
            }
        }
        let aces = try decide(smallOpen("As Ah"), "balanced", ConstantRandom(0.1))
        XCTAssertEqual(aces.action, .raise)
        XCTAssertGreaterThanOrEqual(aces.amount ?? 0, 250)
    }

    func testTheSmallOpenBranchStopsAtSizeStackAllInAndReRaiseBoundaries() throws {
        let base = smallOpen()
        func with(_ change: (inout BotView) -> Void) -> BotView {
            var v = base
            change(&v)
            return v
        }
        func raiser(stack: Int, allin: Bool = false) -> [BotOpponent] {
            base.opponents!.map { $0.id == 0 ? BotOpponent(id: 0, stack: stack, bet: $0.bet, allin: allin) : $0 }
        }
        let unsafe: [BotView] = [
            with { $0.opponents = nil },
            with { $0.opponents = base.opponents!.filter { $0.id != 0 } },
            with { $0.currentBet = 201; $0.legal.toCall = 201; $0.legal.callAmount = 201 },
            with { $0.stack = 1000 },
            with { $0.opponents = raiser(stack: 2249) },
            with { $0.opponents = raiser(stack: 0, allin: true) },
            with { $0.history = base.history + [HistoryEntry(street: 0, id: 2, action: .raise, amount: 175)] },
            with { $0.street = 1; $0.board = cards("2s 4h Jd") },
            with { $0.history = [HistoryEntry(street: 0, id: 1, action: .raise, amount: 150)] },
        ]
        for (i, view) in unsafe.enumerated() {
            let d = try decide(view)
            XCTAssertFalse(d.trace.affordableOpen, "case \(i)")
            XCTAssertFalse(d.trace.affordableRangePassed, "case \(i)")
            XCTAssertEqual(d.action, .fold, "case \(i)")
        }
        XCTAssertTrue(try decide(with { $0.currentBet = 200; $0.legal.toCall = 200; $0.legal.callAmount = 200 })
            .trace.affordableOpen)
        XCTAssertTrue(try decide(with { $0.opponents = raiser(stack: 2250) }).trace.affordableOpen)
    }

    func testACheapCompletionIsNotACheapAllInWithATinyRemainingStack() throws {
        var v = viewV
        v.hole = cards("9s 8s")
        v.stack = 625
        XCTAssertTrue(try decide(v).trace.cheapRangePassed)
        v.stack = 624
        XCTAssertFalse(try decide(v).trace.cheapRangePassed)
        v.stack = 25
        v.legal.callAmount = 25
        v.legal.canRaise = false
        XCTAssertFalse(try decide(v).trace.affordableRangePassed)
    }

    func testSmallOpenContinuationKeepsStyleAndPositionOrderAcrossAll1326Holes() throws {
        var v = smallOpen(count: 9)
        XCTAssertEqual(try decide(v).action, .call)
        v.position = "UTG"
        XCTAssertEqual(try decide(v).action, .fold)
        XCTAssertEqual(try decide(smallOpen("7s 2h")).action, .fold)
        let deck = deckOfCards()
        let continues = try ["st", "balanced", "peter"].map { profile -> Int in
            var n = 0
            var view = smallOpen(count: 9)
            for a in deck.indices {
                for b in (a + 1)..<deck.count {
                    view.hole = [deck[a], deck[b]]
                    if try decide(view, profile).action != .fold { n += 1 }
                }
            }
            return n
        }
        XCTAssertTrue(continues[0] < continues[1] && continues[1] < continues[2], "ST / balanced / Peter: \(continues)")
    }

    // MARK: Policy wiring and hidden information

    func testEveryMixedAssignmentReachesTheExecutedPolicyWithItsParameters() throws {
        let lineup = [1: "tan", 2: "st", 3: "zang", 4: "peter", 5: "abao", 6: "viktor", 7: "jungleman", 8: "dwan"]
        for id in 1...8 {
            let g = try newGame(9)
            try applyBotSettings(g, BotSettings(emotionMode: .off, assignments: lineup))
            try startHand(g, random: SeededRandom(UInt32(id)))
            while g.actor != id { try act(g, g.actor, .call) }
            let decision = try playBotTurn(g, random: LCGRandom(UInt32(id)))
            let record = try XCTUnwrap(g.botDecisions.last)
            let profile = getBotProfile(lineup[id]!)
            XCTAssertEqual(record.id, id)
            XCTAssertEqual(record.action, decision.action)
            XCTAssertEqual(record.trace.profile, profile.id)
            XCTAssertEqual(record.trace.profileName, profile.name)
            XCTAssertEqual(record.trace.baseAxes, profile.axes)
            XCTAssertEqual(record.trace.axes, profile.axes.map(Double.init))
            XCTAssertEqual(wealth(g), 45000)
        }
    }

    func testBotDecisionsIgnoreOpponentHolesTheFutureDeckAndFinalResultsForEveryProfile() throws {
        for profile in BOT_PROFILES {
            let g = try newGame(9)
            try startHand(g, random: SeededRandom(51))
            g.players[g.actor].botProfile = profile.id
            let expected = try botDecision(g, random: LCGRandom(50))
            for i in g.players.indices where i != g.actor { g.players[i].hole = cards("2c 2d") }
            g.deck = deckOfCards()
            g.winners = [Winner(id: 3, name: "River", amount: 1, profit: 1, label: "x")]
            g.result = "rigged"
            XCTAssertEqual(try botDecision(g, random: LCGRandom(50)), expected, profile.id)
        }
    }
}
