import XCTest
@testable import PokerCore

final class SessionSchedulingTests: XCTestCase {
    func testManualSchedulerRunsTasksInDueOrderAndHonoursCancellation() {
        let s = ManualScheduler()
        var log: [String] = []
        _ = s.schedule(delayMs: 10) { log.append("b") }
        _ = s.schedule(delayMs: 5) {
            log.append("a")
            _ = s.schedule(delayMs: 0) { log.append("a0") }
        }
        let c = s.schedule(delayMs: 7) { log.append("never") }
        _ = s.schedule(delayMs: 10) { log.append("c") }
        c.cancel()
        c.cancel()
        s.advance(by: 9)
        XCTAssertEqual(log, ["a", "a0"])
        XCTAssertEqual(s.nowMs, 9)
        XCTAssertEqual(s.nextDueAt, 10)
        s.advance(by: 1)
        XCTAssertEqual(log, ["a", "a0", "b", "c"])
        XCTAssertEqual(s.pendingCount, 0)
        XCTAssertNil(s.nextDueAt)
    }

    func testBotsActExactlyAtTheirDeadlineAndReschedulingReusesThePlan() throws {
        let h = Harness(seed: 11)
        try h.heroTurn(9)
        XCTAssertTrue(h.session.callOrCheck())
        let plan = try XCTUnwrap(h.hooks.thinking())
        XCTAssertTrue((BOT_THINK_LIMITS.minimum...BOT_THINK_LIMITS.maximum).contains(plan.delayMs))
        XCTAssertEqual(h.game.actor, plan.actor)
        XCTAssertTrue(h.state.seats.seat(plan.actor).isActor)
        XCTAssertEqual(h.state.seats.seat(plan.actor).action.label, "Thinking")
        XCTAssertTrue(h.state.seats.seat(plan.actor).action.isDeciding)
        XCTAssertEqual(h.state.actions.decisionText, "\(h.game.players[plan.actor].name) is thinking…")
        let draws = h.random.draws
        XCTAssertEqual(h.hooks.resumeBots(), plan)
        XCTAssertEqual(h.random.draws, draws)

        h.scheduler.advance(by: plan.delayMs - 1)
        XCTAssertTrue(h.hooks.timingRecords().isEmpty)
        XCTAssertEqual(h.hooks.thinking()?.actor, plan.actor)
        h.scheduler.advance(by: 1)
        let records = h.hooks.timingRecords()
        XCTAssertEqual(records.count, 1)
        let thinking = try XCTUnwrap(records[0].trace.thinking)
        XCTAssertEqual(thinking.durationMs, plan.delayMs)
        XCTAssertGreaterThanOrEqual(thinking.waitedMs, plan.delayMs)
        XCTAssertFalse(thinking.expedited)
    }

    func testADifficultyChangeReplansTheThinkingBotWithALaterStart() throws {
        let h = Harness(seed: 12)
        try h.heroTurn(9)
        h.session.callOrCheck()
        let first = try XCTUnwrap(h.hooks.thinking())
        h.scheduler.advance(by: first.delayMs)
        XCTAssertEqual(h.hooks.timingRecords().count, 1)
        let next = try XCTUnwrap(h.hooks.thinking())
        h.scheduler.advance(by: 300)
        let draws = h.random.draws
        h.session.setDifficulty(.hard)
        let updated = try XCTUnwrap(h.hooks.thinking())
        XCTAssertEqual(updated.actor, next.actor)
        XCTAssertGreaterThan(updated.startedAt, next.startedAt)
        XCTAssertGreaterThan(h.random.draws, draws)
        h.scheduler.advance(by: updated.delayMs + 1)
        XCTAssertEqual(h.hooks.timingRecords().count, 2)
    }

    func testStreetAdvancesWaitOneSecondAndTheRiverSettlement850Ms() throws {
        let h = Harness()
        try h.river()
        XCTAssertEqual(h.game.phase, .between)
        XCTAssertTrue(h.game.revealed)
        // The fixture does not schedule; resume to start the settlement timer.
        h.hooks.resumeBots()
        XCTAssertEqual(h.state.actions.decisionText, SessionCopy.decisionShowdownSettling)
        h.scheduler.advance(by: 849)
        XCTAssertEqual(h.game.phase, .between)
        h.scheduler.advance(by: 1)
        XCTAssertEqual(h.game.phase, .done)

        let g = Harness()
        try g.bettingTurn(1, 0)
        g.session.callOrCheck()
        try g.respondToHero()
        XCTAssertEqual(g.game.phase, .between)
        XCTAssertEqual(g.state.actions.decisionText, SessionCopy.decisionDealingNext)
        g.hooks.resumeBots()
        g.scheduler.advance(by: 999)
        XCTAssertEqual(g.game.street, 0)
        g.scheduler.advance(by: 1)
        XCTAssertEqual(g.game.street, 1)
        XCTAssertEqual(g.state.board.filter { $0.card != nil }.count, 3)
        XCTAssertTrue(g.state.potPulse)
        XCTAssertEqual(g.state.board.prefix(3).map { $0.card!.delayMs }, [0, 140, 280])
        XCTAssertTrue(g.state.board.prefix(3).allSatisfy { $0.card!.animate })
    }

    func testFinishHandConsumesThePendingPlanImmediatelyAndAllRecordsAreExpedited() throws {
        let h = Harness(seed: 20)
        try h.heroTurn(9)
        XCTAssertTrue(h.session.fold())
        let waiting = try XCTUnwrap(h.hooks.thinking())
        XCTAssertTrue(h.state.actions.finishHandVisible)
        let draws = h.random.draws
        XCTAssertTrue(h.session.finishHand())
        XCTAssertFalse(h.session.finishHand())
        XCTAssertTrue(h.state.finishing)
        XCTAssertEqual(h.state.actions.finishHandLabel, "Dealing…")
        XCTAssertFalse(h.state.actions.finishHandEnabled)
        // The first step consumes the waiting plan without new draws.
        h.scheduler.runCurrent()
        let first = try XCTUnwrap(h.hooks.timingRecords().first)
        XCTAssertEqual(first.id, waiting.actor)
        XCTAssertEqual(first.trace.thinking?.durationMs, waiting.delayMs)
        XCTAssertEqual(first.trace.thinking?.expedited, true)
        h.scheduler.advance(by: 1000)
        XCTAssertEqual(h.game.phase, .done)
        XCTAssertEqual((h.game.practiceBoard ?? h.game.board).count, 5)
        XCTAssertTrue(h.hooks.timingRecords().allSatisfy { $0.trace.thinking?.expedited == true })
        XCTAssertGreaterThan(h.random.draws, draws)
        XCTAssertFalse(h.state.finishing)
        XCTAssertFalse(h.state.actions.finishHandVisible)
        let snapshot = h.session.publicSnapshot()
        h.scheduler.advance(by: 20_000)
        XCTAssertEqual(h.session.publicSnapshot(), snapshot)
        // Replay cancels every old deadline.
        h.session.replayHand()
        h.hooks.stop()
        h.scheduler.advance(by: 20_000)
        XCTAssertTrue(h.hooks.timingRecords().isEmpty)
        XCTAssertEqual(h.tableWealth(), 9 * STARTING_STACK)
    }

    func testFinishHandAfterAFoldWinAddsAPracticeRunoutWithoutChangingTheResult() throws {
        for street in 0...2 {
            let h = Harness(seed: 30 + street)
            try h.foldFinished(street)
            XCTAssertEqual(h.game.phase, .done)
            XCTAssertEqual(h.game.board.count, [0, 3, 4][street])
            XCTAssertTrue(h.session.publicSnapshot().canContinue)
            let before = h.session.publicSnapshot()
            let stats = h.game.players.map(\.botStats)
            let board = h.game.board
            let draws = h.random.draws
            XCTAssertTrue(h.session.finishHand())
            XCTAssertFalse(h.session.finishHand())
            XCTAssertEqual(h.random.draws, draws)
            let after = h.session.publicSnapshot()
            XCTAssertEqual(after.board.count, 5)
            XCTAssertEqual(Array(after.board.prefix(board.count)), board.map(\.description))
            XCTAssertEqual(after.settlementBoard, before.settlementBoard)
            XCTAssertTrue(after.practiceRunout)
            XCTAssertFalse(after.canContinue)
            XCTAssertEqual(after.players.map(\.stack), before.players.map(\.stack))
            XCTAssertEqual(after.pots, before.pots)
            XCTAssertEqual(after.uncalled, before.uncalled)
            XCTAssertEqual(after.result, before.result)
            XCTAssertEqual(h.game.players.map(\.botStats), stats)
            XCTAssertEqual(after.wealth, 30_000)
            XCTAssertEqual(h.state.session.hands, 1)
            XCTAssertEqual(h.state.boardCaption, SessionCopy.captionPractice)
            XCTAssertTrue(h.state.board.allSatisfy { $0.card != nil })
            XCTAssertNil(h.state.showdown)
            XCTAssertFalse(h.state.actions.finishHandVisible)
            h.session.replayHand()
            h.hooks.stop()
            XCTAssertTrue(h.state.board.allSatisfy { $0.card == nil })
            XCTAssertFalse(h.session.publicSnapshot().practiceRunout)
            XCTAssertEqual(h.state.session.hands, 0)
        }
    }

    func testFoldContinuationSettlesUnequalAllInsOnceAndReplayRestoresTheHand() throws {
        let h = Harness(seed: 5)
        try h.heroTurn(9, unequal: true)
        let wealth = h.tableWealth()
        let hole = h.game.players[0].hole
        h.session.fold()
        try h.allinRest()
        XCTAssertTrue(h.state.actions.finishHandVisible)
        h.session.finishHand()
        h.session.finishHand()
        h.scheduler.runUntilIdle()
        XCTAssertEqual(h.game.phase, .done)
        XCTAssertEqual(h.game.board.count, 5)
        XCTAssertGreaterThan(h.game.pots.count, 1)
        let potLines = h.state.activity.entries.filter { $0.type == .result && $0.text != h.game.result }
        XCTAssertEqual(potLines.count, h.game.pots.count)
        for (line, pot) in zip(potLines, h.game.pots) { XCTAssertTrue(line.text.hasPrefix(pot.label + " "), line.text) }
        XCTAssertEqual(h.game.players.reduce(0) { $0 + $1.stack }, wealth)
        XCTAssertEqual(h.game.stats.hands, 1)
        XCTAssertEqual(h.state.showdown?.scenes.count, 8)
        let hand = h.game.hand
        h.session.replayHand()
        h.hooks.stop()
        XCTAssertEqual(h.game.hand, hand)
        XCTAssertEqual(h.game.players[0].hole, hole)
        XCTAssertEqual(h.game.stats.hands, 0)
        XCTAssertNil(h.state.showdown)
        XCTAssertFalse(h.state.review.buttonVisible)
    }

    func testStartNewSessionDuringAThinkingPauseCancelsTheOldAction() throws {
        let h = Harness(seed: 8)
        try h.heroTurn(9)
        h.session.callOrCheck()
        h.scheduler.advance(by: 500)
        h.session.startNewSession()
        h.hooks.stop()
        let snapshot = h.session.publicSnapshot()
        h.scheduler.advance(by: 20_000)
        XCTAssertEqual(h.session.publicSnapshot(), snapshot)
        XCTAssertTrue(h.hooks.timingRecords().isEmpty)
    }

    func testStartNewSessionCancelsAQueuedFinishHandContinuation() throws {
        let h = Harness(seed: 9)
        try h.heroTurn(9)
        h.session.fold()
        h.hooks.stop()
        XCTAssertTrue(h.session.finishHand())
        h.session.startNewSession()
        h.hooks.stop()
        XCTAssertEqual(h.state.session.hands, 0)
        XCTAssertFalse(h.state.finishing)
        h.scheduler.advance(by: 50)
        XCTAssertFalse(h.game.players[0].folded)
        XCTAssertTrue(h.hooks.timingRecords().isEmpty)
    }

    func testBackgroundCancelsStaleTimersAndForegroundResumesTheSamePlanForTheRestOfItsDelay() throws {
        let h = Harness(seed: 14)
        try h.heroTurn(9)
        h.session.callOrCheck()
        let plan = try XCTUnwrap(h.hooks.thinking())
        h.scheduler.advance(by: plan.delayMs - 10)
        let epoch = h.session.epoch
        h.session.onBackground()
        XCTAssertGreaterThan(h.session.epoch, epoch)
        XCTAssertTrue(h.state.backgrounded)
        let snapshot = h.session.publicSnapshot()
        h.scheduler.advance(by: 20_000)
        XCTAssertEqual(h.session.publicSnapshot(), snapshot)
        XCTAssertTrue(h.hooks.timingRecords().isEmpty)
        // Commands that would schedule do not start timers while backgrounded.
        h.session.setDifficulty(.normal)
        XCTAssertEqual(h.scheduler.pendingCount, 0)

        let draws = h.random.draws
        h.session.onForeground()
        let resumed = try XCTUnwrap(h.hooks.thinking())
        XCTAssertEqual(resumed.actor, plan.actor)
        XCTAssertEqual(resumed.delayMs, plan.delayMs)
        // The original start is kept and the deadline moves by the time spent away.
        XCTAssertEqual(resumed.startedAt, plan.startedAt)
        XCTAssertEqual(resumed.deadline, h.scheduler.nowMs + 10)
        XCTAssertEqual(h.random.draws, draws)
        h.scheduler.advance(by: 9)
        XCTAssertTrue(h.hooks.timingRecords().isEmpty)
        h.scheduler.advance(by: 1)
        let records = h.hooks.timingRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, plan.actor)
        let thinking = try XCTUnwrap(records.first?.trace.thinking)
        // Only foreground time counts as waiting.
        XCTAssertEqual(thinking.waitedMs, plan.delayMs)
        XCTAssertEqual(thinking.durationMs, plan.delayMs)
        XCTAssertFalse(thinking.expedited)
    }

    func testRepeatedBackgroundTransitionsAddUpTheTimeSpentAway() throws {
        let h = Harness(seed: 14)
        try h.heroTurn(9)
        h.session.callOrCheck()
        let plan = try XCTUnwrap(h.hooks.thinking())
        h.scheduler.advance(by: 100)
        h.session.onBackground()
        h.scheduler.advance(by: 5_000)
        h.session.onForeground()
        h.scheduler.advance(by: 200)
        h.session.onBackground()
        h.scheduler.advance(by: 7_000)
        h.session.onForeground()
        let resumed = try XCTUnwrap(h.hooks.thinking())
        XCTAssertEqual(resumed.startedAt, plan.startedAt)
        XCTAssertEqual(resumed.deadline, plan.deadline + 12_000)
        h.scheduler.advance(by: plan.delayMs - 301)
        XCTAssertTrue(h.hooks.timingRecords().isEmpty)
        h.scheduler.advance(by: 1)
        XCTAssertEqual(h.hooks.timingRecords().count, 1)
        XCTAssertEqual(h.hooks.timingRecords().first?.trace.thinking?.waitedMs, plan.delayMs)
    }

    func testAStaleCallbackCapturedBeforeTheBackgroundIsANoOp() throws {
        // A platform scheduler might still deliver a callback after cancel(); the epoch check drops it.
        final class LeakyScheduler: SessionScheduler {
            var nowMs = 0
            var actions: [() -> Void] = []
            func schedule(delayMs: Int, _ action: @escaping () -> Void) -> SessionCancellable {
                actions.append(action)
                return CancelHandle()  // ignores cancellation
            }
        }
        let scheduler = LeakyScheduler()
        let session = TableSession(scheduler: scheduler, storage: InMemoryStorage(), random: SeededRandom(seed: 21))
        session.start()
        XCTAssertNotEqual(session.testHooks.game.actor, 0)
        let stale = scheduler.actions
        XCTAssertFalse(stale.isEmpty)
        session.onBackground()
        let before = session.publicSnapshot()
        scheduler.nowMs = 60_000
        stale.forEach { $0() }
        XCTAssertEqual(session.publicSnapshot(), before)
        XCTAssertTrue(session.testHooks.timingRecords().isEmpty)
        // Returning to the foreground schedules a fresh timer.
        session.onForeground()
        let afterForeground = scheduler.actions.count
        XCTAssertGreaterThan(afterForeground, stale.count)
    }

    func testBackgroundStopsARunningFinishHandLoopAndForegroundResumesNormalPacing() throws {
        let h = Harness(seed: 15)
        try h.heroTurn(9)
        h.session.fold()
        let waiting = try XCTUnwrap(h.hooks.thinking())
        h.session.finishHand()
        h.session.onBackground()
        XCTAssertFalse(h.state.finishing)
        h.scheduler.advance(by: 10_000)
        XCTAssertTrue(h.hooks.timingRecords().isEmpty)
        XCTAssertFalse(h.session.finishHand())
        let draws = h.random.draws
        h.session.onForeground()
        // The unexecuted pending plan is kept, so no decision is re-drawn, and
        // its wait resumes where it stopped.
        XCTAssertEqual(h.hooks.thinking()?.actor, waiting.actor)
        XCTAssertEqual(h.hooks.thinking()?.delayMs, waiting.delayMs)
        XCTAssertEqual(h.hooks.thinking()?.startedAt, waiting.startedAt)
        XCTAssertEqual(h.hooks.thinking()?.deadline, waiting.deadline + 10_000)
        XCTAssertEqual(h.random.draws, draws)
        // Finish Hand does not resume by itself; it is offered again instead.
        XCTAssertFalse(h.state.finishing)
        XCTAssertTrue(h.state.actions.finishHandVisible)
        XCTAssertTrue(h.session.canFinishHand())
        h.runBots(maxMs: 200_000)
        h.scheduler.runUntilIdle()
        XCTAssertEqual(h.game.phase, .done)
        XCTAssertEqual(h.hooks.timingRecords().first?.id, waiting.actor)
        XCTAssertEqual(h.tableWealth(), 9 * STARTING_STACK)
    }

    func testLongSessionsOnTheVirtualClockConserveEveryChip() {
        for count in [5, 6, 9] {
            let h = Harness(seed: 1000 + count)
            h.session.setSeatCount(count)
            h.session.openOpponentSettings()
            h.session.mixLineup()
            h.session.saveOpponentSettings()
            h.session.start()
            var chips = count * STARTING_STACK
            for handIndex in 0..<30 {
                var guardCount = 0
                while h.game.phase != .done {
                    guardCount += 1
                    XCTAssertLessThan(guardCount, 500)
                    if guardCount >= 500 { return }
                    XCTAssertEqual(h.tableWealth(), chips)
                    if h.game.phase == .playing && h.game.actor == 0 {
                        let legal = legalActions(h.game, 0)
                        switch (handIndex + guardCount) % 5 {
                        case 0: h.session.fold()
                        case 1:
                            if legal.canRaise {
                                h.session.preset(guardCount % 2 == 0 ? .halfPot : .pot)
                                XCTAssertTrue(h.session.raise())
                            } else {
                                h.session.callOrCheck()
                            }
                        default: h.session.callOrCheck()
                        }
                        if h.game.players[0].folded && h.game.phase != .done && guardCount % 3 == 0 { h.session.finishHand() }
                    } else {
                        h.runBots()
                        if h.game.phase != .done && h.game.actor != 0 { h.scheduler.runCurrent() }
                    }
                }
                h.scheduler.runUntilIdle()
                XCTAssertEqual(h.game.players.reduce(0) { $0 + $1.stack }, chips)
                XCTAssertEqual(h.game.payouts.reduce(0, +), h.game.players.reduce(0) { $0 + $1.total })
                h.session.nextHand()
                let rebuys = h.state.activity.entries.filter { $0.text.hasSuffix("5,000 virtual chips") }.count
                chips += rebuys * STARTING_STACK
                XCTAssertEqual(h.tableWealth(), chips)
            }
            XCTAssertEqual(h.game.hand, 31)
            XCTAssertEqual(h.state.session.hands, 30)
            XCTAssertEqual(h.state.playerCount, count)
        }
    }

    func testChipActionsEmitFlightsAndSoundsOnlyWhileSoundIsOn() throws {
        let h = Harness(seed: 16)
        h.session.toggleSound()
        XCTAssertEqual(h.effects.last, .sound(.deal))
        h.effects.removeAll()
        try h.heroTurn(6)
        h.session.callOrCheck()
        XCTAssertTrue(h.effects.contains(.chipFlight(seat: 0)))
        XCTAssertTrue(h.effects.contains(.sound(.chip)))
        h.session.toggleSound()
        h.effects.removeAll()
        h.session.fold()
        XCTAssertFalse(h.effects.contains { if case .sound = $0 { return true } else { return false } })
    }

    func testHeroActionIsANoOpWhileABotIsToAct() {
        let h = Harness(seed: 2)
        h.session.start()
        XCTAssertNotEqual(h.game.actor, 0)
        XCTAssertFalse(h.session.heroAction(.call))
    }
}
