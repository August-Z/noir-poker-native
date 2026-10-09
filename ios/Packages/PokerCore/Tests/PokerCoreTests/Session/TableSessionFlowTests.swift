import XCTest
@testable import PokerCore

final class TableSessionFlowTests: XCTestCase {
    func testFirstLaunchDealsHandOneWithSafeDefaults() {
        let h = Harness()
        h.session.start()
        let s = h.state
        XCTAssertEqual(s.hand, 1)
        XCTAssertEqual(s.handNumber, "01")
        XCTAssertEqual(s.playerCount, 6)
        XCTAssertEqual(s.tableTag, "6-MAX")
        XCTAssertEqual(s.tableSize, "6-Handed No-Limit")
        XCTAssertEqual(s.settings.difficulty, .normal)
        XCTAssertTrue(s.settings.hints)
        XCTAssertFalse(s.settings.sound)
        XCTAssertEqual(h.game.emotionMode, .subtle)
        XCTAssertEqual(s.opponents.text, "Balanced")
        XCTAssertNil(s.opponents.changeNote)
        XCTAssertTrue(s.seats.allSatisfy { $0.styleShort == "Balanced" })
        XCTAssertEqual(s.session.changeText, "Build experience, starting this hand")
        XCTAssertEqual(s.session.winRateText, "—")
        XCTAssertEqual(s.streetLabel, "Preflop")
        XCTAssertEqual(s.boardCaption, SessionCopy.captionPreflop)
        XCTAssertEqual(s.board.count, 5)
        XCTAssertTrue(s.board.allSatisfy { $0.card == nil && $0.a11y == "Undealt community card" })
        // Starting again does not deal a second hand.
        h.session.start()
        XCTAssertEqual(h.state.hand, 1)
    }

    func testSessionConsumesRandomnessExactlyLikeTheReferenceController() throws {
        let h = Harness(seed: 7)
        h.session.start()
        // Reference: newGame, applyBotSettings, startHand (51 draws), then planBotTurn
        // for the first actor (decision and timing from the same stream).
        let rng = SeededRandom(seed: 7)
        let g = try newGame(6)
        try applyBotSettings(g, defaultBotSettings())
        try startHand(g, random: rng)
        XCTAssertEqual(g.players.map(\.hole), h.game.players.map(\.hole))
        let plan = try planBotTurn(g, random: rng, timingRandom: rng)
        XCTAssertEqual(h.hooks.thinking()?.delayMs, plan.delayMs)
        // Re-scheduling a current plan draws nothing.
        let draws = h.random.draws
        XCTAssertEqual(h.hooks.resumeBots(), h.hooks.thinking())
        XCTAssertEqual(h.random.draws, draws)
        XCTAssertEqual(h.random.draws, 51 + CountingRandomProbe.drawsForPlan(seed: 7))
    }

    func testRelaunchRestoresEverySavedOptionBeforeTheFirstFreshHand() {
        let storage = InMemoryStorage()
        let first = Harness(storage: storage)
        first.session.start()
        first.session.setSeatCount(9)
        first.session.setDifficulty(.hard)
        first.session.toggleHints()
        first.session.toggleSound()
        first.session.openOpponentSettings()
        first.session.mixLineup()
        first.session.setEmotionMode(.lively)
        first.session.saveOpponentSettings()
        // The current hand is unchanged and shows the pending note.
        XCTAssertEqual(first.state.playerCount, 6)
        XCTAssertEqual(first.game.players[1].botProfile, "balanced")
        XCTAssertEqual(first.state.opponents.text, "Applies Next Hand")
        XCTAssertNotNil(first.state.opponents.changeNote)
        XCTAssertEqual(first.state.settings.tableChangeNote, SessionCopy.tableChangeNote(9))

        let second = Harness(storage: storage)
        second.session.start()
        let s = second.state
        XCTAssertEqual(s.playerCount, 9)
        XCTAssertEqual(s.settings.difficulty, .hard)
        XCTAssertFalse(s.settings.hints)
        XCTAssertFalse(s.coach.visible)
        XCTAssertTrue(s.settings.sound)
        XCTAssertEqual(s.opponents.text, "8 Styled Opponents")
        XCTAssertNil(s.opponents.changeNote)
        XCTAssertNil(s.settings.tableChangeNote)
        XCTAssertEqual(s.hand, 1)
        XCTAssertEqual(s.session.hands, 0)
        XCTAssertEqual(second.game.emotionMode, .lively)
        XCTAssertEqual(second.game.players.dropFirst().map(\.botProfile), (1...8).map { MIXED_LINEUP[$0]! })
        XCTAssertTrue(second.game.players.allSatisfy { $0.stack + $0.bet == STARTING_STACK })
        XCTAssertEqual(storage.values[PreferencesStore.tableKey], #"{"playerCount":9,"difficulty":"hard"}"#)
    }

    func testNextHandKeepsSessionTotalsWhileReplayReversesOnlyThisHand() throws {
        let h = Harness()
        try h.foldPotRefund()
        XCTAssertEqual(h.game.phase, .done)
        XCTAssertEqual(h.state.session.hands, 1)
        let stacksAfterHand = h.game.players.map(\.stack)
        let dealer = h.game.dealer
        let hand = h.game.hand
        let holes = h.game.players.map(\.hole)

        // Replay: same hand number, holes and button; stats and payouts reversed.
        XCTAssertTrue(h.state.actions.replayVisible)
        XCTAssertTrue(h.session.replayHand())
        h.hooks.stop()
        XCTAssertEqual(h.game.hand, hand)
        XCTAssertEqual(h.game.dealer, dealer)
        XCTAssertEqual(h.game.players.map(\.hole), holes)
        XCTAssertEqual(h.state.session.hands, 0)
        XCTAssertEqual(h.game.replayAttempt, 1)
        XCTAssertEqual(h.state.replayBadge, "Replay 1")
        XCTAssertEqual(h.state.replayNote, SessionCopy.replayNote)
        XCTAssertFalse(h.state.actions.replayVisible)
        XCTAssertEqual(h.tableWealth(), 6 * STARTING_STACK)

        // Replay the same scripted line again: the result matches the first attempt.
        try h.foldRest()
        XCTAssertEqual(h.game.phase, .done)
        XCTAssertEqual(h.state.session.hands, 1)

        // Next Hand: totals kept, button moves, fresh shuffle.
        XCTAssertTrue(h.session.nextHand())
        h.hooks.stop()
        XCTAssertEqual(h.game.hand, hand + 1)
        XCTAssertEqual(h.game.dealer, (dealer + 1) % 6)
        XCTAssertEqual(h.state.session.hands, 1)
        XCTAssertEqual(h.game.replayAttempt, 0)
        XCTAssertNil(h.state.replayBadge)
        XCTAssertNotEqual(h.game.players.map(\.hole), holes)
        // Next Hand is refused while a hand is in progress.
        XCTAssertFalse(h.session.nextHand())
        XCTAssertEqual(h.game.hand, hand + 1)

        // Preferences set before Start New Session: tips off, sound on and
        // saved (pending) opponent styles.
        h.session.toggleHints()
        h.session.toggleSound()
        h.session.openOpponentSettings()
        h.session.mixLineup()
        h.session.setEmotionMode(.lively)
        XCTAssertTrue(h.session.saveOpponentSettings())
        XCTAssertEqual(h.state.opponents.text, "Applies Next Hand")
        let saved = h.session.savedBotSettings
        let savedValues = h.storage.values

        // Start New Session: fresh table and stats.
        h.session.startNewSession()
        h.hooks.stop()
        XCTAssertEqual(h.game.hand, 1)
        XCTAssertEqual(h.state.session.hands, 0)
        XCTAssertTrue(h.game.players.allSatisfy { $0.stack + $0.total == STARTING_STACK })
        XCTAssertNotEqual(h.game.players.map { $0.stack + $0.total }, stacksAfterHand)
        // The preferences survive, and the saved styles are dealt in the new session.
        XCTAssertFalse(h.state.settings.hints)
        XCTAssertFalse(h.state.coach.visible)
        XCTAssertTrue(h.state.settings.sound)
        XCTAssertEqual(h.session.savedBotSettings, saved)
        XCTAssertEqual(h.game.players.dropFirst().map(\.botProfile), (1...5).map { MIXED_LINEUP[$0]! })
        XCTAssertEqual(h.game.emotionMode, .lively)
        XCTAssertEqual(h.state.opponents.text, "5 Styled Opponents")
        XCTAssertNil(h.state.opponents.changeNote)
        XCTAssertEqual(h.storage.values, savedValues)
    }

    func testReplayingTwiceReversesThePayoutExactlyOnce() throws {
        let h = Harness(seed: 3)
        try h.heroTurn(6)
        let baseline = h.game.players.map { $0.stack + $0.total }
        h.session.fold()
        h.session.finishHand()
        h.scheduler.runUntilIdle()
        XCTAssertEqual(h.game.phase, .done)
        XCTAssertEqual(h.game.stats.hands, 1)
        for _ in 0..<2 {
            XCTAssertTrue(h.session.replayHand())
            h.hooks.stop()
            XCTAssertEqual(h.game.players.map { $0.stack + $0.total }, baseline)
            XCTAssertEqual(h.game.stats.hands, 0)
            XCTAssertTrue(h.game.players.dropFirst().allSatisfy { $0.botStats.hands == 0 })
            h.session.fold()
            h.session.finishHand()
            h.scheduler.runUntilIdle()
            XCTAssertEqual(h.game.stats.hands, 1)
            XCTAssertEqual(h.tableWealth(), 6 * STARTING_STACK)
        }
        XCTAssertEqual(h.game.replayAttempt, 2)
    }

    func testSeatCountChangesApplyAtTheNextDealAndNeverOnReplay() throws {
        let h = Harness()
        h.session.start()
        try h.foldWin()
        XCTAssertTrue(h.session.setSeatCount(5))
        XCTAssertFalse(h.session.setSeatCount(4))
        XCTAssertFalse(h.session.setSeatCount(10))
        XCTAssertEqual(h.state.playerCount, 6)
        XCTAssertEqual(h.state.settings.tableChangeNote, "Switches to 5 players next hand · Stacks reset to 5,000 and stats start over")
        h.session.replayHand()
        XCTAssertEqual(h.state.playerCount, 6)
        try h.foldRest()
        h.session.nextHand()
        h.hooks.stop()
        XCTAssertEqual(h.state.playerCount, 5)
        XCTAssertEqual(h.game.hand, 1)
        XCTAssertEqual(h.state.session.hands, 0)
        XCTAssertNil(h.state.settings.tableChangeNote)
        XCTAssertEqual(h.state.seats.count + 1, 5)
        XCTAssertEqual(h.state.seats.map(\.layoutX), [15, 23, 77, 85])
        XCTAssertEqual(h.state.seats.map(\.layoutY), [59, 0, 0, 59])
    }

    func testDifficultyAppliesImmediatelyAndIsKeptByReplayAndNewSessions() throws {
        let h = Harness()
        h.session.start()
        h.session.setDifficulty(.easy)
        XCTAssertEqual(h.game.difficulty, .easy)
        try h.foldWin()
        h.session.replayHand()
        XCTAssertEqual(h.game.difficulty, .easy)
        h.session.startNewSession()
        XCTAssertEqual(h.game.difficulty, .easy)
        XCTAssertEqual(h.state.settings.difficultyOptions.first { $0.value == .easy }?.label, "Easy")
        XCTAssertEqual(h.state.settings.difficultyOptions.map(\.label), ["Easy", "Standard", "Advanced"])
    }

    func testRevealTogglesChangeOneSeatOnlyAndClearOnNextHandReplayAndReset() throws {
        for reset in ["replay", "next", "session"] {
            let h = Harness()
            try h.foldWin(9)
            let winner = 8
            XCTAssertTrue(h.state.seats.allSatisfy { !$0.revealed })
            XCTAssertTrue(h.state.seats.allSatisfy { $0.peek != nil && !$0.peek!.pressed })
            XCTAssertEqual(h.state.seats.seat(winner).badge?.text, "Winner")
            let stacks = h.game.players.map(\.stack)
            XCTAssertFalse(h.session.toggleReveal(0))
            XCTAssertTrue(h.session.toggleReveal(winner))
            let seat = h.state.seats.seat(winner)
            XCTAssertTrue(seat.revealed)
            XCTAssertEqual(seat.cards.map(\.text), h.game.players[winner].hole.map(\.description))
            XCTAssertEqual(seat.peek?.a11y, "Hide Leo's hole cards")
            XCTAssertEqual(h.state.seats.filter(\.revealed).count, 1)
            XCTAssertEqual(h.effects.last, .revealToggled(seat: winner, visible: true))
            // A folded seat can be revealed too; settlement is untouched.
            XCTAssertTrue(h.session.toggleReveal(3))
            XCTAssertEqual(h.state.seats.filter(\.revealed).count, 2)
            XCTAssertEqual(h.session.publicSnapshot().players[winner].cards, h.game.players[winner].hole.map(\.description))
            XCTAssertEqual(h.game.players.map(\.stack), stacks)
            XCTAssertNil(h.state.showdown)
            switch reset {
            case "replay": h.session.replayHand()
            case "next": h.session.nextHand()
            default: h.session.startNewSession()
            }
            h.hooks.stop()
            XCTAssertTrue(h.state.seats.allSatisfy { !$0.revealed && $0.peek == nil }, reset)
            if reset != "session" { try h.foldRest() } else { try h.foldWin(9) }
            XCTAssertTrue(h.state.seats.allSatisfy { !$0.revealed }, reset)
            XCTAssertNil(h.session.publicSnapshot().players[winner].cards)
        }
    }

    func testRevealTogglesAreUnavailableDuringPlay() throws {
        let h = Harness()
        try h.heroTurn()
        XCTAssertFalse(h.session.toggleReveal(2))
        XCTAssertTrue(h.state.seats.allSatisfy { $0.peek == nil })
    }

    func testHeroLastActionAppearsAtOnceAndPersistsThroughStreets() throws {
        let h = Harness()
        try h.heroTurn(9)
        XCTAssertNil(h.state.hero.lastAction)
        XCTAssertEqual(h.state.hero.turnText, "Your Turn")
        XCTAssertTrue(h.session.callOrCheck())
        h.hooks.stop()
        XCTAssertEqual(h.state.hero.lastAction?.label, "Call")
        XCTAssertEqual(h.state.hero.lastAction?.amountText, "50")
        XCTAssertEqual(h.state.hero.turnText, "Waiting")
        try h.respondToHero(150)
        XCTAssertEqual(h.state.hero.turnText, "Your Turn")
        XCTAssertEqual(h.state.hero.lastAction?.label, "Call")
        XCTAssertTrue(h.session.preset(.min))
        XCTAssertEqual(h.state.actions.bet, 250)
        XCTAssertTrue(h.session.raise())
        h.hooks.stop()
        let raise = h.state.hero.lastAction!
        XCTAssertEqual(raise.label, "3-bet Raise")
        XCTAssertEqual(raise.amount, 250)
        XCTAssertTrue(raise.meaning!.hasPrefix("Preflop · "))
        try h.respondToHero(0, nextStreet: true)
        XCTAssertEqual(h.game.board.count, 3)
        XCTAssertEqual(h.game.players[0].bet, 0)
        XCTAssertEqual(h.state.hero.lastAction?.label, "3-bet Raise")
        XCTAssertTrue(h.session.callOrCheck())
        h.hooks.stop()
        XCTAssertEqual(h.state.hero.lastAction?.label, "Check")
        XCTAssertNil(h.state.hero.lastAction?.amount)
        try h.respondToHero(0, nextStreet: true)
        XCTAssertTrue(h.session.fold())
        h.hooks.stop()
        XCTAssertEqual(h.state.hero.lastAction?.label, "Fold")
        XCTAssertEqual(h.state.hero.turnText, "Folded")
        h.session.finishHand()
        h.scheduler.runUntilIdle()
        XCTAssertEqual(h.game.phase, .done)
        XCTAssertEqual(h.state.hero.lastAction?.label, "Fold")
        XCTAssertNil(h.state.hero.turnText)
        h.session.replayHand()
        h.hooks.stop()
        XCTAssertNil(h.state.hero.lastAction)
        XCTAssertTrue(h.session.preset(.allIn))
        XCTAssertTrue(h.session.raise())
        h.hooks.stop()
        XCTAssertEqual(h.state.hero.lastAction?.label, "2-bet All-In")
        XCTAssertEqual(h.state.hero.lastAction?.amountText, "5,000")
        XCTAssertEqual(h.state.hero.turnText, "All-In")
        try h.bettingTurn(3, 0, short: true)
        h.session.preset(.allIn)
        XCTAssertEqual(h.state.actions.raiseCaption, "3-bet short all-in to")
        h.session.raise()
        h.hooks.stop()
        XCTAssertEqual(h.state.hero.lastAction?.label, "3-bet Short All-In")
        XCTAssertEqual(h.state.hero.lastAction?.amount, 175)
    }

    func testSettledSeatsKeepTheirFinalActionsUntilNextHandLeavesOnlyTheBlinds() throws {
        let h = Harness()
        try h.retainedRiver(9)
        try h.finish()
        XCTAssertEqual(h.game.phase, .done)
        let chips = h.state.seats.map(\.action) + [h.state.hero.lastAction!]
        let call = chips.first { $0.label == "Call" }!
        XCTAssertTrue(call.meaning!.hasSuffix("300 in this round"), call.meaning!)
        XCTAssertEqual(h.state.hero.lastAction?.label, "2-bet Raise")
        XCTAssertEqual(h.state.hero.lastAction?.amount, 300)
        XCTAssertTrue(chips.contains { $0.label == "Fold" })
        h.session.nextHand()
        h.hooks.stop()
        XCTAssertEqual(h.game.players.filter { $0.lastAction != nil }.count, 2)
        XCTAssertTrue(h.game.players.compactMap { $0.lastAction?.text }.allSatisfy { $0.hasPrefix("SB ") || $0.hasPrefix("BB ") })
    }

    func testAllInSizesSurviveSettlementAndEyeToggles() throws {
        for count in 5...9 {
            let h = Harness(seed: count)
            try h.heroTurn(count)
            h.session.preset(.allIn)
            h.session.raise()
            try h.allinRest()
            let before = h.game.players.map(\.lastAction)
            while h.game.phase != .done { try h.finish() }
            XCTAssertEqual(h.game.board.count, 5)
            XCTAssertEqual(h.game.players.map(\.lastAction), before)
            XCTAssertEqual(h.state.hero.lastAction?.label, "2-bet All-In")
            XCTAssertTrue(h.state.seats.allSatisfy { $0.action.label == "All-In" && $0.action.amountText == "5,000" })
            h.session.toggleReveal(1)
            XCTAssertEqual(h.game.players.map(\.lastAction), before)
            h.session.replayHand()
            h.hooks.stop()
            XCTAssertNil(h.state.hero.lastAction)
            XCTAssertEqual(h.game.players.filter { $0.lastAction != nil }.count, 2)
        }
    }

    func testNextHandRebuysABustedHeroAndLabelsTheButtonAccordingly() throws {
        let h = Harness()
        try h.scene("2c 3d", "As Ks Qs Js 9h", totals: Array(repeating: 5000, count: 6), otherHoles: [1: "Ts 4h"])
        XCTAssertEqual(h.game.players[0].stack, 0)
        XCTAssertEqual(h.state.actions.nextHandLabel, "Rebuy and Keep Practicing")
        h.session.nextHand()
        h.hooks.stop()
        XCTAssertEqual(h.game.players[0].stack + h.game.players[0].total, STARTING_STACK)
        XCTAssertEqual(h.game.stats.buyin, 10_000)
        XCTAssertTrue(h.state.activity.entries.contains { $0.text == "You rebuy 5,000 virtual chips" })
    }

    func testHeroActionsAreRejectedWhenIllegalAndLeaveTheGameUnchanged() throws {
        let h = Harness()
        try h.heroTurn()
        let before = h.game.state
        XCTAssertFalse(h.session.raise(60))
        XCTAssertFalse(h.session.heroAction(.check))
        XCTAssertEqual(h.game.actor, 0)
        XCTAssertEqual(h.game.state, before)
        try h.foldWin()
        XCTAssertFalse(h.session.fold())
    }

    func testOpponentSettingsApplyNextHandAndFreezeOnReplay() throws {
        let h = Harness()
        try h.foldWin(6)
        h.session.openOpponentSettings()
        let dialog = h.state.opponentsDialog!
        XCTAssertEqual(dialog.roster.count, 8)
        XCTAssertEqual(dialog.profileCards.count, 9)
        XCTAssertEqual(dialog.selectedProfile, "balanced")
        XCTAssertTrue(dialog.roster.dropFirst(5).allSatisfy { $0.offTable && $0.subtitle == "Not seated · Steady" })
        XCTAssertEqual(dialog.roster[0].subtitle, "Seat 1 · Steady")
        XCTAssertEqual(dialog.roster[0].currentStyle, "Style this hand: Balanced")
        XCTAssertEqual(dialog.roster[7].currentStyle, "Not seated yet; uses the saved next-hand setting")
        XCTAssertEqual(dialog.roster[0].observed, "1 hand · VPIP 0% · PFR 0%")
        XCTAssertEqual(dialog.roster[0].options.count, 9)
        XCTAssertEqual(dialog.comparison.count, 9)
        for (seat, p) in [(1, "tan"), (2, "st"), (3, "zang"), (4, "peter"), (5, "abao"), (8, "st")] {
            h.session.assignSeatStyle(seat, p)
        }
        XCTAssertEqual(h.state.opponentsDialog?.selectedProfile, "st")
        h.session.setEmotionMode(.lively)
        XCTAssertTrue(h.session.saveOpponentSettings())
        XCTAssertNil(h.state.opponentsDialog)
        XCTAssertEqual(h.state.opponents.text, "Applies Next Hand")
        XCTAssertEqual(h.game.players[1].botProfile, "balanced")
        h.session.replayHand()
        XCTAssertEqual(h.game.players[1].botProfile, "balanced")
        XCTAssertEqual(h.state.opponents.text, "Applies Next Hand")
        try h.foldRest()
        h.session.nextHand()
        h.hooks.stop()
        XCTAssertEqual(h.game.players.dropFirst().map(\.botProfile), ["tan", "st", "zang", "peter", "abao"])
        XCTAssertEqual(h.game.emotionMode, .lively)
        XCTAssertEqual(h.state.opponents.text, "5 Styled Opponents")
        // Off-table assignments are preserved for larger tables.
        try h.foldWin(6)
        h.session.setSeatCount(9)
        h.session.nextHand()
        h.hooks.stop()
        XCTAssertEqual(h.game.players[8].botProfile, "st")
    }

    func testClosingTheOpponentDialogWithoutSavingDiscardsTheDraft() {
        let h = Harness()
        h.session.start()
        h.session.openOpponentSettings()
        h.session.mixLineup()
        XCTAssertEqual(h.state.opponentsDialog?.selectedProfile, "tan")
        XCTAssertEqual(h.state.opponentsDialog?.roster[0].assignment, "tan")
        h.session.discardOpponentSettings()
        XCTAssertNil(h.state.opponentsDialog)
        XCTAssertEqual(h.session.savedBotSettings, defaultBotSettings())
        h.session.openOpponentSettings()
        XCTAssertEqual(h.state.opponentsDialog?.roster[0].assignment, "balanced")
        // The previewed profile persists across opens.
        XCTAssertEqual(h.state.opponentsDialog?.selectedProfile, "tan")
        XCTAssertNil(h.storage.values[PreferencesStore.opponentsKey])
        h.session.previewProfile("dwan")
        XCTAssertEqual(h.state.opponentsDialog?.detail.profile.id, "dwan")
        XCTAssertEqual(h.state.opponentsDialog?.detail.axes.count, 5)
    }

    func testLossMoodIsVisibleAndEmotionOffResetsEveryMoodNextHand() throws {
        let h = Harness()
        try h.scene("As Ah", "Ac 2h 3d 4c 8s", totals: [5000, 5000, 50, 50, 50, 50], folded: [2, 3, 4, 5], otherHoles: [1: "Ks Kd"])
        XCTAssertEqual(h.state.seats.seat(1).mood, .frustrated)
        h.session.openOpponentSettings()
        XCTAssertTrue(h.state.opponentsDialog!.roster[0].subtitle.contains("Chasing Losses"))
        XCTAssertNotNil(h.state.opponentsDialog!.roster[0].moodReason)
        h.session.setEmotionMode(.off)
        h.session.saveOpponentSettings()
        h.session.nextHand()
        h.hooks.stop()
        XCTAssertEqual(h.game.emotionMode, .off)
        XCTAssertTrue(h.state.seats.allSatisfy { $0.mood == .steady })
        XCTAssertTrue(h.session.publicSnapshot().players.dropFirst().allSatisfy { $0.mood == "steady" })
    }

    func testSavedSettingsRoundTripIntoTheNextDeal() {
        let storage = InMemoryStorage()
        PreferencesStore(storage).saveBotSettings(
            BotSettings(emotionMode: .off, assignments: Dictionary(uniqueKeysWithValues: (1...8).map { ($0, "abao") })))
        let h = Harness(storage: storage)
        h.session.start()
        XCTAssertTrue(h.game.players.dropFirst().allSatisfy { $0.botProfile == "abao" })
        XCTAssertEqual(h.state.opponents.text, "5 Styled Opponents")
    }

    func testListenersReceiveTheCurrentStateAndEveryChange() {
        let h = Harness()
        var versions: [Int] = []
        let subscription = h.session.addListener { versions.append($0.version) }
        XCTAssertEqual(versions.count, 1)
        h.session.start()
        XCTAssertGreaterThan(versions.count, 1)
        XCTAssertEqual(versions, versions.sorted())
        let seen = versions.count
        subscription.cancel()
        h.session.toggleHints()
        XCTAssertEqual(versions.count, seen)
    }
}

/// Counts the draws `planBotTurn` makes for the first actor of a fresh seeded deal.
enum CountingRandomProbe {
    static func drawsForPlan(seed: Int) -> Int {
        let rng = CountingRandom(SeededRandom(seed: seed))
        let g = try! newGame(6)
        try! startHand(g, random: rng)
        let before = rng.draws
        _ = try! planBotTurn(g, random: rng, timingRandom: rng)
        return rng.draws - before
    }
}
