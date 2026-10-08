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
