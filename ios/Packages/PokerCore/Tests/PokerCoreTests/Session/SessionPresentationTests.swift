import XCTest
@testable import PokerCore

final class SessionPresentationTests: XCTestCase {
    private func presets(_ h: Harness) -> [BetPreset: Int?] {
        Dictionary(uniqueKeysWithValues: h.state.actions.presets.map { ($0.preset, $0.amount) })
    }

    func testPresetsSelectTheExactReferenceAmounts() throws {
        let h = Harness()
        try h.heroTurn(6)
        // Preflop, unraised: currentBet 50, minRaise 50, pot 75.
        XCTAssertEqual(presets(h), [.min: 100, .halfPot: 100, .pot: 125, .allIn: 5000])
        XCTAssertEqual(h.state.actions.presets.map(\.label), ["Min", "½ Pot", "Pot", "All-In"])
        XCTAssertTrue(h.session.preset(.pot))
        XCTAssertEqual(h.state.actions.bet, 125)
        XCTAssertEqual(h.state.actions.raiseCaption, "2-bet open to")
        XCTAssertEqual(h.state.actions.raiseA11y, "2-bet open to 125")
        h.session.preset(.allIn)
        XCTAssertEqual(h.state.actions.raiseCaption, "2-bet all-in to")
        // Facing an open to 150: Min is 250.
        try h.bettingTurn(3)
        XCTAssertEqual(presets(h)[.min], 250)
        // Pot 225 (SB 25 + BB 50 + 150): half = 150 + max(100, round(4.5) * 25 = 125) = 275.
        XCTAssertEqual(presets(h)[.halfPot], 275)
        XCTAssertEqual(presets(h)[.pot], 150 + 225)
        h.session.preset(.min)
        XCTAssertEqual(h.state.actions.raiseCaption, "3-bet raise to")
        // Postflop first bet.
        try h.bettingTurn(1, 1)
        h.session.preset(.min)
        XCTAssertEqual(h.state.actions.raiseCaption, "1-bet bet to")
        XCTAssertEqual(h.state.actions.bet, 50)
        try h.bettingTurn(3, 2)
        XCTAssertEqual(h.state.actions.raiseCaption, "3-bet raise to")
    }

    func testTheSliderSnapsTo25ExceptForTheExactAllInAndBetIsClampedOnRender() throws {
        let h = Harness()
        try h.heroTurn(6)
        XCTAssertEqual(h.state.actions.bet, 150)
        XCTAssertEqual(h.state.actions.sliderMin, 100)
        XCTAssertEqual(h.state.actions.sliderMax, 5000)
        h.session.setBet(137)
        XCTAssertEqual(h.state.actions.bet, 125)
        h.session.setBet(138)
        XCTAssertEqual(h.state.actions.bet, 150)
        h.session.setBet(4999)
        XCTAssertEqual(h.state.actions.bet, 5000)
        h.session.setBet(5000)
        XCTAssertEqual(h.state.actions.bet, 5000)
        h.session.setBet(10)
        XCTAssertEqual(h.state.actions.bet, 100)
        h.session.nudgeBet(3)
        XCTAssertEqual(h.state.actions.bet, 175)
        XCTAssertEqual(h.session.currentBet, 175)
        h.session.nudgeBet(-10)
        XCTAssertEqual(h.state.actions.bet, 100)
        // Short stack: the bet is clamped into the legal range on the next render.
        try h.bettingTurn(3, 0, short: true)
        XCTAssertEqual(h.state.actions.bet, 175)
        XCTAssertEqual(h.state.actions.raiseCaption, "3-bet short all-in to")
    }

    func testCallButtonAndDecisionTextFollowTheLegalActions() throws {
        let h = Harness()
        try h.heroTurn(6)
        let a = h.state.actions
        XCTAssertEqual(a.callLabel, "Call")
        XCTAssertEqual(a.callAmountText, "50")
        XCTAssertEqual(a.callA11y, "Call 50")
        XCTAssertEqual(a.decisionText, "Your turn. 50 chips to call.")
        XCTAssertTrue(a.controlsVisible && a.decisionStripVisible && a.raiseEnabled)
        XCTAssertFalse(a.nextHandVisible)
        try h.bettingTurn(1, 1)
        XCTAssertEqual(h.state.actions.callLabel, "Check")
        XCTAssertNil(h.state.actions.callAmountText)
        XCTAssertEqual(h.state.actions.decisionText, SessionCopy.decisionCanCheck)
        try h.bettingTurn(3, 0, short: true)
        XCTAssertEqual(h.state.actions.decisionText, "Your turn. 150 chips to call.")
        h.session.fold()
        XCTAssertTrue(h.state.actions.decisionText.hasSuffix("is acting. You can watch the rest of this hand.") || h.game.phase == .done)
        XCTAssertFalse(h.state.actions.controlsVisible)
        try h.foldWin()
        XCTAssertEqual(h.state.actions.decisionText, "")
        XCTAssertFalse(h.state.actions.decisionStripVisible)
        XCTAssertTrue(h.state.actions.nextHandVisible)
        XCTAssertEqual(h.state.actions.nextHandLabel, "Next Hand")
        XCTAssertTrue(h.state.actions.replayVisible)
    }

    func testACallThatDoesNotReopenRaisingSaysSo() throws {
        let h = Harness()
        try h.heroTurn(6)
        h.session.raise(100)
        h.hooks.stop()
        try h.hooks.mutate { g in
            g.players[5].stack = 75
            while g.actor != 5 { try act(g, g.actor, .call) }
            try act(g, 5, .raise, 125)
            while g.actor != 0 { try act(g, g.actor, .call) }
        }
        XCTAssertFalse(legalActions(h.game, 0).raiseReopened)
        XCTAssertEqual(h.state.actions.decisionText, "Your turn. 25 chips to call." + SessionCopy.decisionNotReopened)
        XCTAssertFalse(h.state.actions.raiseEnabled)
        XCTAssertTrue(h.state.actions.presets.allSatisfy { !$0.enabled && $0.amount == nil })
        XCTAssertFalse(h.session.preset(.pot))
    }

    func testSeatChipsShowBetOrdinalsAndCallMeanings() throws {
        let h = Harness()
        try h.bettingTurn(4)
        let seats = h.state.seats
        XCTAssertEqual(seats.seat(3).action.label, "2-bet")
        XCTAssertEqual(seats.seat(3).action.amountText, "150")
        XCTAssertEqual(seats.seat(3).action.meaning, "2-bet open to 150 · 150 in this round")
        XCTAssertEqual(seats.seat(4).action.label, "3-bet")
        XCTAssertEqual(seats.seat(1).action.label, "SB")
        XCTAssertEqual(seats.seat(2).action.label, "BB")
        XCTAssertEqual(seats.seat(5).action.label, "Fold")
        XCTAssertTrue(h.state.activity.entries.contains { $0.text == "River: 2-bet open to 150" })
        h.session.preset(.min)
        XCTAssertEqual(h.state.actions.raiseCaption, "4-bet raise to")
        try h.bettingTurn(3, 1)
        let s = h.state.seats
        XCTAssertEqual(s.seat(1).action.label, "1-bet")
        XCTAssertEqual(s.seat(2).action.label, "2-bet")
        XCTAssertEqual(s.seat(3).action.label, "Fold")
    }

    func testSeatActionChipParsingCoversEveryEngineActionText() throws {
        let h = Harness()
        try h.heroTurn(6)
        let g = h.game
        func chip(_ text: String, recent: Bool = false, bet: Int = 0) -> ActionChip {
            var p = Player(id: 1, name: "Mia")
            p.action = text
            p.bet = bet
            p.lastAction = LastAction(text: text, street: 1, bet: bet)
            return seatActionChip(g, p, recent: recent)
        }
        XCTAssertEqual(chip("SB 25"), ActionChip("SB", amount: 25, amountText: "25", meaning: "SB 25 · 25 in this round"))
        XCTAssertEqual(chip("Call 1,800", bet: 2000).label, "Call")
        XCTAssertEqual(chip("Call 1,800", bet: 2000).amount, 1800)
        XCTAssertEqual(chip("Call 1,800", bet: 2000).meaning, "Added 1,800 · 2,000 in this round")
        XCTAssertEqual(chip("Call 1,800", recent: true, bet: 2000).meaning, "Flop · Added 1,800 · 2,000 in this round")
        XCTAssertEqual(chip("All-In 500").label, "All-In")
        XCTAssertEqual(chip("2-bet short all-in to 125").label, "2-bet Short All-In")
        XCTAssertEqual(chip("4-bet all-in to 4,000").label, "4-bet All-In")
        XCTAssertEqual(chip("4-bet all-in to 4,000").amount, 4000)
        XCTAssertEqual(chip("2-bet open to 150").label, "2-bet")
        XCTAssertEqual(chip("2-bet open to 150", recent: true).label, "2-bet Open")
        XCTAssertEqual(chip("1-bet bet to 100", recent: true).label, "1-bet Bet")
        XCTAssertEqual(chip("3-bet raise to 650", recent: true).label, "3-bet Raise")
        XCTAssertEqual(chip("12-bet raise to 4,650", recent: true).label, "12-bet Raise")
        XCTAssertEqual(chip("raise to 300").label, "Raise")
        XCTAssertEqual(chip("Fold"), ActionChip("Fold"))
        XCTAssertEqual(chip("Check"), ActionChip("Check"))
        XCTAssertEqual(chip("All-In"), ActionChip("All-In"))
        XCTAssertEqual(chip("Shove 300"), ActionChip("Shove 300"))
        XCTAssertEqual(chip("x-bet raise to 300"), ActionChip("x-bet raise to 300"))
        XCTAssertEqual(chip(""), ActionChip("Waiting"))
        XCTAssertEqual(seatActionChip(g, g.players[0]), ActionChip("Thinking", isDeciding: true))
    }

    func testActivityIsChronologicalNumberedAndMarksTheHero() throws {
        for count in [6, 9] {
            let h = Harness(seed: count)
            try h.river(count)
            try h.finish()
            let entries = h.state.activity.entries
            XCTAssertEqual(entries.count, h.game.logs.count)
            XCTAssertEqual(entries.map(\.number), Array(1...entries.count))
            XCTAssertEqual(entries.map(\.text), h.game.logs.reversed().map(\.text))
            func idx(_ pred: (ActivityEntryState) -> Bool) -> Int { entries.firstIndex(where: pred) ?? -1 }
            let milestones = [
                idx { $0.text.hasPrefix("Hand 1 begins") },
                idx { $0.type == .blind },
                idx { $0.text.hasPrefix("Flop · ") },
                idx { $0.text.hasPrefix("Turn · ") },
                idx { $0.text.hasPrefix("River · ") },
                idx { $0.text == h.game.result },
            ]
            XCTAssertEqual(milestones[0], 0)
            XCTAssertEqual(milestones.sorted(), milestones)
            XCTAssertTrue(milestones.allSatisfy { $0 >= 0 })
            XCTAssertTrue(entries.filter { $0.playerId == 0 }.allSatisfy(\.isHero))
            XCTAssertTrue(entries.filter { $0.playerId != 0 }.allSatisfy { !$0.isHero })
            XCTAssertEqual(h.state.activity.badge, "FINISHED")
            // Eye toggles never change the activity.
            h.session.toggleReveal(1)
            XCTAssertEqual(h.state.activity.entries.map(\.text), entries.map(\.text))
        }
    }

    func testActivityShowsAssignedPersonasWithoutRelabelingTheCurrentHand() throws {
        let h = Harness()
        h.session.start()
        h.session.openOpponentSettings()
        h.session.assignSeatStyle(1, "viktor")
        h.session.assignSeatStyle(2, "st")
        h.session.assignSeatStyle(3, "jungleman")
        h.session.assignSeatStyle(4, "dwan")
        h.session.saveOpponentSettings()
        try h.river(6)
        try h.finish()
        XCTAssertTrue(h.state.hasFullPlayerNames)
        let texts = h.state.activity.entries.map(\.text)
        let blinds = h.state.activity.entries.first { $0.type == .blind }!
        XCTAssertEqual(blinds.text, "Mia (Viktor Blom): SB 25 · Alex (ST Wang): BB 50")
        XCTAssertEqual(blinds.segments, [
            TextSegment("Mia"), TextSegment(" (Viktor Blom)", isPersona: true), TextSegment(": SB 25 · Alex"),
            TextSegment(" (ST Wang)", isPersona: true), TextSegment(": BB 50"),
        ])
        XCTAssertTrue(texts.contains { $0.contains("River (Daniel Cates)") })
        XCTAssertTrue(texts.contains { $0.contains("Kai (Tom Dwan)") })
        XCTAssertFalse(texts.contains { $0.contains("Luna (") || $0.contains("You (") })
        // The street log is not mistaken for the player River.
        XCTAssertTrue(texts.contains { $0.hasPrefix("River · ") })
        XCTAssertTrue(h.state.showdown!.scenes.contains { $0.nameSegments.plainText == "River (Daniel Cates)" })

        try h.foldPotRefund()
        XCTAssertTrue(h.game.result.hasPrefix("Alex wins"))
        XCTAssertTrue(h.state.activity.entries.last!.text.hasPrefix("Alex (ST Wang) wins"))
        XCTAssertTrue(h.state.activity.entries.contains { $0.text == "Uncalled 75 chips returned to Alex (ST Wang)" })
        h.session.openOpponentSettings()
        h.session.assignSeatStyle(2, "abao")
        h.session.saveOpponentSettings()
        h.session.toggleReveal(2)
        XCTAssertFalse(h.state.activity.entries.contains { $0.text.contains("(A Bao)") })
        h.session.nextHand()
        try h.foldRest()
        XCTAssertTrue(h.state.activity.entries.contains { $0.text.contains("Alex (A Bao)") })
        XCTAssertFalse(h.state.activity.entries.contains { $0.text.contains("(ST Wang)") })
    }

    func testActivityFormatterMatchesWholeNamesOnlyAndKeepsIdentitiesFromCreation() {
        var players = [Player(id: 0, name: "You"), Player(id: 1, name: "Mia"), Player(id: 2, name: "Alex"), Player(id: 3, name: "River")]
        players[0].botProfile = "tan"
        players[2].botProfile = "st"
        players[3].botProfile = "jungleman"
        let f = ActivityFormatter(players)
        XCTAssertEqual(f.format("You: Call 50 · Mia: Fold").plainText, "You: Call 50 · Mia: Fold")
        XCTAssertEqual(f.format("Hand 1 begins · Button: Alex").plainText, "Hand 1 begins · Button: Alex (ST Wang)")
        XCTAssertEqual(f.format("Main Pot 125 → Alex 125").plainText, "Main Pot 125 → Alex (ST Wang) 125")
        XCTAssertEqual(f.format("Uncalled 75 chips returned to River").plainText, "Uncalled 75 chips returned to River (Daniel Cates)")
        XCTAssertEqual(f.format("Alex simulated mood: Chasing Losses").plainText, "Alex (ST Wang) simulated mood: Chasing Losses")
        XCTAssertEqual(f.format("Alexandra: Fold · RIVER · xAlex").plainText, "Alexandra: Fold · RIVER · xAlex")
        XCTAssertEqual(f.format("Alex (ST Wang): Check").plainText, "Alex (ST Wang): Check")
        XCTAssertEqual(f.format("Alex（ST Wang）").plainText, "Alex（ST Wang）")
        XCTAssertEqual(f.format("River · 7♠", skipLeadingStreetName: true).plainText, "River · 7♠")
        XCTAssertEqual(f.format("River · 7♠ · River", skipLeadingStreetName: true).plainText, "River · 7♠ · River (Daniel Cates)")
        players[2].botProfile = "dwan"
        XCTAssertEqual(f.format("Alex").plainText, "Alex (ST Wang)")
        XCTAssertEqual(ActivityFormatter(players).format("Alex").plainText, "Alex (Tom Dwan)")
        XCTAssertEqual(ActivityFormatter([Player(id: 0, name: "You"), Player(id: 1, name: "Mia")]).format("Mia: Fold"), [TextSegment("Mia: Fold")])
    }

    func testShowdownScenesHighlightExactlyTheEvaluatedBestFive() throws {
        for count in 5...9 {
            let h = Harness(seed: 100 + count)
            try h.river(count)
            XCTAssertNil(h.state.showdown)
            XCTAssertEqual(h.state.seats.filter { $0.revealed && $0.cards.count == 2 }.count, count - 1)
            XCTAssertTrue(h.state.seats.allSatisfy { $0.peek == nil })
            try h.finish()
            let sd = try XCTUnwrap(h.state.showdown)
            XCTAssertEqual(sd.scenes.count, count)
            XCTAssertEqual(h.state.seats.filter { $0.peek != nil }.count, h.state.seats.count)
            for scene in sd.scenes {
                let p = h.game.players[scene.scene.id]
                XCTAssertEqual(Set(scene.scene.cards.map(\.key)), Set(evaluate(p.hole + h.game.board).cards.map(\.key)))
                XCTAssertEqual(scene.isWinner, !scene.scene.awards.isEmpty)
            }
            // Rendering again keeps the same key (animations do not replay).
            let key = sd.key
            h.session.toggleReveal(1)
            XCTAssertEqual(h.state.showdown?.key, key)
        }
    }

    func testHandScenesOrderCardsAndExplainTheCategory() throws {
        let h = Harness()
        try h.scene("Qh Qc", "4d 6s Kh 5h 3s", count: 9, totals: [500, 50, 100, 200, 300, 400, 500, 600, 700],
                    folded: [3, 7], otherHoles: [1: "7c 8d"])
        let scenes = h.state.showdown!.scenes
        XCTAssertEqual(scenes.count, 7)
        let hero = scenes.first { $0.scene.id == 0 }!
        XCTAssertEqual(hero.scene.explanation, "Pair of Queens")
        XCTAssertEqual(hero.scene.cards.map(\.rank), [12, 12, 13, 6, 5])
        XCTAssertEqual(hero.scene.highlights, [true, true, false, false, false])
        XCTAssertEqual(hero.scene.motion, .pair)
        let mia = scenes.first { $0.scene.id == 1 }!
        XCTAssertEqual(mia.scene.label, "Straight")
        XCTAssertEqual(mia.scene.explanation, "Eight-high straight")
        XCTAssertEqual(mia.scene.cards.map(\.rank), [4, 5, 6, 7, 8])
        XCTAssertEqual(mia.scene.motion, .straight)
        XCTAssertTrue(mia.isWinner)
        XCTAssertEqual(hero.statusText, "No pot won")
        XCTAssertEqual(hero.footerText, "Best five cards")
        XCTAssertTrue(h.state.showdown!.context.hasPrefix("7 players at showdown · Main Pot and Side Pots settled separately"))
        // Folded seats have no scene.
        XCTAssertFalse(scenes.contains { $0.scene.id == 3 || $0.scene.id == 7 })
        XCTAssertEqual(winningScenes(h.game).count, h.game.pots.reduce(0) { $0 + $1.awards.count })

        try h.scene("Ah 2d", "As Kd 2c 7h 9s", folded: [0, 2, 3, 4, 5], otherHoles: [1: "Ac Qd"])
        XCTAssertEqual(h.state.seats.seat(1).badge?.text, "One Pair")
        XCTAssertEqual(h.state.seats.seat(1).badge?.isWinner, true)
        XCTAssertEqual(h.state.hero.rankBadge?.text, "Folded · Two Pair")
        XCTAssertFalse(h.state.actions.decisionStripVisible)
        XCTAssertEqual(h.state.boardCaption, SessionCopy.captionShowdownFolded)
        XCTAssertTrue(h.state.board.allSatisfy { $0.card?.best == false })

        try h.scene("5c 4d", "Ah 2s 3h 9c Kd", folded: [2, 3, 4, 5], otherHoles: [1: "Qs Qd"])
        let wheel = h.state.showdown!.scenes.first { $0.scene.id == 0 }!
        XCTAssertEqual(wheel.scene.cards.map(\.rank), [14, 2, 3, 4, 5])
        XCTAssertEqual(wheel.scene.explanation, "Five-high straight")
        XCTAssertEqual(wheel.statusText, "Won +600")
        XCTAssertEqual(wheel.footerText, "Main Pot +600")
        XCTAssertEqual(h.state.boardCaption, SessionCopy.captionShowdownHero)
        XCTAssertEqual(h.state.board.filter { $0.card?.best == true }.count, 3)
        XCTAssertEqual(h.state.hero.cards.filter(\.best).count, 2)

        try h.scene("2c 3d", "As Ks Qs Js Ts", count: 5, totals: [100, 100, 1, 1, 1], folded: [2, 3, 4])
        let royal = h.state.showdown!.scenes[0].scene
        XCTAssertEqual(royal.motion, .royal)
        XCTAssertEqual(royal.explanation, "10 · J · Q · K · A of one suit")
        let pot = h.state.potDetails.pots[0]
        XCTAssertEqual(h.state.potDetails.pots.count, 1)
        XCTAssertEqual(pot.splitTotalText, "203 chips · Split")
        XCTAssertEqual(Set(pot.awards.map(\.amountText)), ["+101", "+102"])
        XCTAssertEqual(pot.oddChipNote, SessionCopy.potOddChipNote)
        XCTAssertEqual(Set(pot.awards.map(\.winnerText)), ["You", "Mia"])
        XCTAssertTrue(h.state.showdown!.scenes.allSatisfy { $0.footerText.hasPrefix("Main Pot · Split +10") })
    }

    func testShowdownExplanationsCoverEveryCategory() throws {
        let h = Harness()
        let cases: [(String, String, String, HandMotion)] = [
            ("Ah 9d", "2c 5s 7h Jd Kc", "Ace-high · Kickers compared in order", .high),
            ("Ah Ad", "Kc Ks 7h 3d 2c", "Aces and Kings", .twoPair),
            ("7h 7d", "7c Ks Qh 3d 2c", "Three Sevens", .trips),
            ("Ah 2h", "9h 5h Kh 3d 2c", "♥ flush · Ace-high", .flush),
            ("Ah Ad", "Ac Ks Kh 3d 2c", "Aces full of Kings", .fullHouse),
            ("9h 9d", "9c 9s Kh 3d 2c", "Four Nines", .quads),
            ("9h 8h", "7h 6h 5h 3d 2c", "♥ straight flush · Nine-high", .straightFlush),
        ]
        for (hole, board, explanation, motion) in cases {
            try h.scene(hole, board, folded: [1, 2, 3, 4, 5])
            let scene = handScene(h.game, h.game.players[0])
            XCTAssertEqual(scene.explanation, explanation, hole)
            XCTAssertEqual(scene.motion, motion, hole)
        }
        try h.scene("Ah 9d", "2c 5s 7h Jd Kc", folded: [1, 2, 3, 4, 5])
        XCTAssertEqual(handScene(h.game, h.game.players[0]).highlights, [true, false, false, false, false])
    }

    func testWinnerCrownsFollowPotAwardsAndRefundsAloneAreNotWins() throws {
        let h = Harness()
        try h.scene("As Ac", "2s 3h 4c 8d 9s", totals: [100, 200, 300, 300, 0, 0], folded: [4, 5],
                    otherHoles: [1: "Ks Kc", 2: "Qd Qh", 3: "Jh Jd"])
        XCTAssertEqual(h.game.pots.map(\.label), ["Main Pot", "Side Pot 1", "Side Pot 2"])
        XCTAssertEqual(h.state.potButtonLabel, "Total Pot · 2 Side Pots")
        XCTAssertEqual(h.state.hero.rankBadge?.a11y, "You win 400 chips")
        XCTAssertEqual(h.state.seats.filter(\.isWinner).map(\.id), [1, 2])
        XCTAssertEqual(h.state.seats.seat(1).badge?.a11y, "Mia wins 300 chips")
        XCTAssertEqual(h.state.boardCaption, "Settled separately · Main Pot 400 + 2 Side Pots")
        h.session.toggleReveal(1)
        XCTAssertEqual(h.state.seats.seat(1).badge?.text, "Winner")
        XCTAssertTrue(h.state.seats.seat(1).isWinner)

        try h.scene("7c 8d", "2h 4s 6d 9c Kh", totals: [1000, 200, 100, 100, 100, 100], folded: [2, 3, 4, 5], otherHoles: [1: "As Ad"])
        XCTAssertEqual(h.session.publicSnapshot().uncalled.map(\.name), ["You"])
        XCTAssertNotEqual(h.state.hero.rankBadge?.isWinner, true)
        XCTAssertEqual(h.state.potDetails.refunds.map(\.text), ["Uncalled bet returned · You"])
    }

    func testSettledPotDetailsKeepAwardsAndRefundsSeparate() throws {
        let h = Harness()
        try h.foldPotRefund()
        let s = h.state
        XCTAssertTrue(s.activity.entries.contains { $0.text == "Alex wins 125 chips" })
        let alex = s.seats.seat(2)
        XCTAssertEqual(alex.badge?.text, "Winner")
        XCTAssertEqual(alex.badge?.title, "All other players folded · Won 125 chips")
        XCTAssertEqual(s.potButtonLabel, "Pot · Details")
        h.session.openPotDetails()
        let d = h.state.potDetails
        XCTAssertTrue(d.open)
        XCTAssertEqual(d.title, "Hand Settlement")
        XCTAssertNil(d.note)
        let pot = d.pots[0]
        XCTAssertEqual(d.pots.count, 1)
        XCTAssertNil(pot.splitTotalText)
        XCTAssertEqual(pot.awards.map(\.winnerText), ["Alex wins"])
        XCTAssertEqual(pot.awards[0].label, "All other players folded")
        XCTAssertEqual(pot.awards[0].amountText, "+125")
        XCTAssertEqual(d.refunds.map(\.text), ["Uncalled bet returned · Alex"])
        XCTAssertEqual(d.refunds[0].amount, 75)
        XCTAssertEqual(d.refunds[0].a11y, "Alex's uncalled 75 chips were returned")
        XCTAssertFalse(pot.expanded)
        XCTAssertEqual(pot.distributionEligibility, "You're not in this pot · Eligible at settlement: Alex")
        XCTAssertEqual(pot.contributions.map(\.text).sorted(), ["Alex", "Kai · Folded", "Luna · Folded"])
        h.session.togglePotDistribution(0)
        XCTAssertTrue(h.state.potDetails.pots[0].expanded)
        try h.finish()
        XCTAssertTrue(h.state.potDetails.pots[0].expanded)
        h.session.closePotDetails()
        XCTAssertFalse(h.state.potDetails.open)
        XCTAssertFalse(h.state.potDetails.pots[0].expanded)
    }

    func testLivePotDetailsShowConditionalEligibility() throws {
        let h = Harness()
        try h.heroTurn(6, unequal: true)
        h.session.preset(.allIn)
        h.session.raise()
        h.hooks.stop()
        try h.hooks.mutate { g in if g.phase == .playing && g.actor != 0 { try act(g, g.actor, .call) } }
        h.session.openPotDetails()
        let d = h.state.potDetails
        XCTAssertEqual(d.title, "Main Pot and Side Pots")
        XCTAssertEqual(d.note, SessionCopy.potNoteLive)
        XCTAssertTrue(d.pots.contains { $0.heroEligible && $0.eligibilityLabel == "You're eligible" })
        XCTAssertTrue(d.pots.allSatisfy { $0.awards.isEmpty })
        XCTAssertFalse(d.refunds.isEmpty)
        XCTAssertTrue(d.refunds.allSatisfy { $0.text.hasPrefix("To be called or returned · ") && !$0.returned })
        // Next Hand closes the dialog.
        try h.foldWin()
        h.session.nextHand()
        XCTAssertFalse(h.state.potDetails.open)
    }

    func testObservedVPIPAndPFRRoundHalfUpAndRestartAfterARestyle() throws {
        func stats(_ hands: Int, _ vpip: Int, _ pfr: Int) -> BotStats {
            var s = BotStats()
            s.hands = hands
            s.vpip = vpip
            s.pfr = pfr
            return s
        }
        let h = Harness()
        try h.foldWin(6)
        h.hooks.mutate { g in
            g.players[1].botStats = stats(3, 1, 2)
            g.players[2].botStats = stats(8, 1, 3)
            g.players[3].botStats = BotStats()
            g.players[4].botStats = stats(1, 1, 0)
        }
        h.session.openOpponentSettings()
        let roster = try XCTUnwrap(h.state.opponentsDialog).roster
        XCTAssertEqual(roster[0].observed, "3 hands · VPIP 33% · PFR 67%")
        // 1/8 = 12.5% and 3/8 = 37.5% round half up.
        XCTAssertEqual(roster[1].observed, "8 hands · VPIP 13% · PFR 38%")
        XCTAssertEqual(roster[2].observed, "0 hands · VPIP — · PFR —")
        XCTAssertEqual(roster[3].observed, "1 hand · VPIP 100% · PFR 0%")
        // Off-table seats have no counters yet.
        XCTAssertEqual(roster[7].observed, "0 hands · VPIP — · PFR —")
        XCTAssertTrue(roster.allSatisfy { $0.observedTitle == SessionCopy.rosterObservedTitle })

        // A style change restarts that seat's counters at the next deal only.
        h.session.assignSeatStyle(1, "tan")
        XCTAssertTrue(h.session.saveOpponentSettings())
        h.session.openOpponentSettings()
        XCTAssertEqual(h.state.opponentsDialog?.roster[0].observed, "3 hands · VPIP 33% · PFR 67%")
        h.session.discardOpponentSettings()
        h.session.nextHand()
        h.hooks.stop()
        h.session.openOpponentSettings()
        let next = try XCTUnwrap(h.state.opponentsDialog).roster
        XCTAssertEqual(next[0].observed, "0 hands · VPIP — · PFR —")
        XCTAssertEqual(next[1].observed, "8 hands · VPIP 13% · PFR 38%")
    }

    func testSessionStatsCoachAndHeaderCopy() throws {
        let h = Harness()
        try h.foldPotRefund()
        let s = h.state
        XCTAssertEqual(s.streetLabel, "Hand Over")
        XCTAssertEqual(s.session.hands, 1)
        XCTAssertEqual(s.session.wins, 0)
        XCTAssertEqual(s.session.winRateText, "0%")
        XCTAssertEqual(s.session.changeText, "+0 chips · Net this session")
        XCTAssertEqual(s.coach.stage, "Hand Recap")
        XCTAssertEqual(s.coach.tip, SessionCopy.tipDoneFolded)
        XCTAssertEqual(s.potText, "125")
        XCTAssertNil(s.hero.turnText)
        try h.foldWin(6, winner: 0)
        XCTAssertEqual(h.state.hero.rankBadge?.text, "Winner")
        XCTAssertEqual(h.state.coach.tip, SessionCopy.tipDoneUncontested)
        XCTAssertEqual(h.state.session.winRateText, "100%")
        try h.heroTurn(6)
        XCTAssertEqual(h.state.coach.stage, "Preflop Strategy")
        let pct = Int(jsRound(50.0 / Double(contestableAfterCall(h.game, 0, 50)) * 100))
        XCTAssertTrue(h.state.coach.tip.hasSuffix(" This call is about \(pct)% of the pot you can win."))
        XCTAssertEqual(h.state.hero.position.code, "UTG")
        XCTAssertEqual(h.state.hero.position.name, "Under the Gun")
        XCTAssertEqual(h.state.hero.cards.map(\.delayMs), [420, 550])
        XCTAssertTrue(h.state.seats.allSatisfy { $0.dealAnimation && $0.cardBackDelaysMs == [$0.id * 65, $0.id * 65 + 140] })
        h.session.toggleHints()
        XCTAssertFalse(h.state.coach.visible)
        XCTAssertEqual(h.state.coach.toggleLabel, "Off")
        XCTAssertFalse(h.state.coach.tip.isEmpty)
        XCTAssertEqual(h.storage.values[PreferencesStore.hintsKey], "false")
        // A later render of the same hand does not replay the deal animation.
        XCTAssertFalse(h.state.hero.cards.contains(where: \.animate))
    }

    func testCoachTipsFollowTheHeroHand() throws {
        let h = Harness()
        try h.scene("Ah Ad", "Ac Ks Kh 3d 2c", folded: [1, 2, 3, 4, 5])
        XCTAssertEqual(h.state.coach.tip, SessionCopy.tipDoneShowdown("a full house"))
        XCTAssertTrue(h.state.coach.tip.hasPrefix("Your best hand was a full house."))
        try h.heroTurn(6)
        h.hooks.mutate { g in g.players[0].hole = parseCards("7h 7d") }
        XCTAssertTrue(h.state.coach.tip.hasPrefix(SessionCopy.tipPrePair))
        h.hooks.mutate { g in g.players[0].hole = parseCards("Kh Jd") }
        XCTAssertTrue(h.state.coach.tip.hasPrefix(SessionCopy.tipPreBroadway))
        h.hooks.mutate { g in g.players[0].hole = parseCards("9h 4h") }
        XCTAssertTrue(h.state.coach.tip.hasPrefix(SessionCopy.tipPreSuited))
        h.hooks.mutate { g in g.players[0].hole = parseCards("9h 4d") }
        XCTAssertTrue(h.state.coach.tip.hasPrefix(SessionCopy.tipPreOther))
        try h.bettingTurn(1, 1)
        h.hooks.mutate { g in
            g.players[0].hole = parseCards("Ah Ad")
            g.board = parseCards("Ac 7s 2h")
        }
        XCTAssertEqual(h.state.coach.tip, "You've made three of a kind. Consider betting for value, but watch for stronger hands the board makes possible.")
        h.hooks.mutate { g in g.board = parseCards("Kc 7s 2h") }
        XCTAssertTrue(h.state.coach.tip.hasPrefix("You have one pair."))
        XCTAssertEqual(h.state.coach.stage, "Flop Strategy")
    }

    func testThePublicSnapshotNeverExposesPrivateTracesOrHiddenCards() throws {
        let h = Harness(seed: 77)
        try h.heroTurn(9)
        h.session.fold()
        h.session.finishHand()
        h.scheduler.runCurrent()
        let snapshot = h.session.publicSnapshot()
        let text = String(describing: snapshot)
        for banned in ["thinking", "closeness", "acting", "rawEquity", "trace", "botDecisions"] {
            XCTAssertFalse(text.contains(banned), banned)
        }
        for p in snapshot.players.dropFirst() {
            let seat = h.game.players[p.id]
            if h.game.phase != .done && !h.game.revealed { XCTAssertNil(p.cards) }
            if let cards = p.cards { XCTAssertEqual(cards, seat.hole.map(\.description)) }
        }
        try h.heroTurn(6)
        XCTAssertTrue(h.session.publicSnapshot().players.dropFirst().allSatisfy { $0.cards == nil })
        XCTAssertTrue(h.state.seats.allSatisfy { $0.cards.isEmpty && $0.cardBacks == 2 })
        XCTAssertEqual(h.session.publicSnapshot().actor, "You")
        XCTAssertEqual(h.session.publicSnapshot().seatOrder, "clockwise")
    }

    func testTableMetaAndSeatLayoutsForEverySize() throws {
        for count in 5...9 {
            let h = Harness(seed: count)
            try h.heroTurn(count)
            XCTAssertEqual(h.state.tableTag, "\(count)-MAX")
            XCTAssertEqual(h.state.seats.count, count - 1)
            XCTAssertEqual(h.state.seats.map(\.layoutX), SEAT_LAYOUTS[count]!.map(\.x))
            XCTAssertEqual(h.state.seats.map(\.avatar), Array(SessionCopy.avatarLetters[1..<count]))
            XCTAssertEqual(Set(h.state.seats.map(\.position.code) + [h.state.hero.position.code]), Set(POSITION_ROLES[count]!))
            XCTAssertTrue(h.state.seats.allSatisfy { $0.avatarTitle == "\($0.name) · Balanced (training archetype) · Simulated mood: Steady" })
            XCTAssertEqual(h.state.potButtonA11y, "View pot details")
        }
    }
}
