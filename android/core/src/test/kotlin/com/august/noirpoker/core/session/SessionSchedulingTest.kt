package com.august.noirpoker.core.session

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.BotThinkLimits
import com.august.noirpoker.core.Difficulty
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.STARTING_STACK
import com.august.noirpoker.core.legalActions
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SessionSchedulingTest {
    @Test
    fun `manual scheduler runs tasks in due order and honours cancellation`() {
        val s = ManualScheduler()
        val log = mutableListOf<String>()
        s.schedule(10) { log.add("b") }
        s.schedule(5) { log.add("a"); s.schedule(0) { log.add("a0") } }
        val c = s.schedule(7) { log.add("never") }
        s.schedule(10) { log.add("c") }
        c.cancel()
        s.advanceBy(9)
        assertEquals(listOf("a", "a0"), log)
        assertEquals(9, s.nowMs)
        s.advanceBy(1)
        assertEquals(listOf("a", "a0", "b", "c"), log)
        assertEquals(0, s.pendingCount)
    }

    @Test
    fun `bots act exactly at their deadline and rescheduling reuses the plan`() {
        val h = Harness(seed = 11)
        h.heroTurn(9)
        assertTrue(h.session.callOrCheck())
        val plan = assertNotNull(h.hooks.thinking())
        assertTrue(plan.delayMs in BotThinkLimits.MINIMUM..BotThinkLimits.MAXIMUM)
        assertEquals(plan.actor, h.game.actor)
        assertTrue(h.state.seats.first { it.id == plan.actor }.isActor)
        assertEquals("Thinking", h.state.seats.first { it.id == plan.actor }.action.label)
        val draws = h.random.draws
        assertEquals(plan, h.hooks.resumeBots())
        assertEquals(draws, h.random.draws)

        h.scheduler.advanceBy(plan.delayMs - 1L)
        assertTrue(h.hooks.timingRecords().isEmpty())
        assertEquals(plan.actor, h.hooks.thinking()!!.actor)
        h.scheduler.advanceBy(1)
        val records = h.hooks.timingRecords()
        assertEquals(1, records.size)
        val thinking = records[0].trace.thinking!!
        assertEquals(plan.delayMs, thinking.durationMs)
        assertTrue(thinking.waitedMs >= plan.delayMs)
        assertFalse(thinking.expedited)
    }

    @Test
    fun `a difficulty change re-plans the thinking bot with a later start`() {
        val h = Harness(seed = 12)
        h.heroTurn(9)
        h.session.callOrCheck()
        val first = h.hooks.thinking()!!
        h.scheduler.advanceBy(first.delayMs.toLong())
        assertEquals(1, h.hooks.timingRecords().size)
        val next = h.hooks.thinking()!!
        h.scheduler.advanceBy(300)
        val draws = h.random.draws
        h.session.setDifficulty(Difficulty.HARD)
        val updated = h.hooks.thinking()!!
        assertEquals(next.actor, updated.actor)
        assertTrue(updated.startedAt > next.startedAt)
        assertTrue(h.random.draws > draws)
        h.scheduler.advanceBy(updated.delayMs + 1L)
        assertEquals(2, h.hooks.timingRecords().size)
    }

    @Test
    fun `street advances wait one second and the river settlement 850 ms`() {
        val h = Harness()
        h.river()
        assertEquals(Phase.BETWEEN, h.game.phase)
        assertTrue(h.game.revealed)
        // The fixture does not schedule; resume to start the settlement timer.
        h.hooks.resumeBots()
        assertEquals(SessionCopy.decisionShowdownSettling, h.state.actions.decisionText)
        h.scheduler.advanceBy(849)
        assertEquals(Phase.BETWEEN, h.game.phase)
        h.scheduler.advanceBy(1)
        assertEquals(Phase.DONE, h.game.phase)

        val g = Harness()
        g.bettingTurn(1, 0)
        g.session.callOrCheck()
        g.respondToHero()
        assertEquals(Phase.BETWEEN, g.game.phase)
        assertEquals(SessionCopy.decisionDealingNext, g.state.actions.decisionText)
        g.hooks.resumeBots()
        g.scheduler.advanceBy(999)
        assertEquals(0, g.game.street)
        g.scheduler.advanceBy(1)
        assertEquals(1, g.game.street)
        assertEquals(3, g.state.board.count { it.card != null })
        assertTrue(g.state.potPulse)
    }

    @Test
    fun `finish hand consumes the pending plan immediately and all records are expedited`() {
        val h = Harness(seed = 20)
        h.heroTurn(9)
        assertTrue(h.session.fold())
        val waiting = h.hooks.thinking()!!
        assertTrue(h.state.actions.finishHandVisible)
        val draws = h.random.draws
        assertTrue(h.session.finishHand())
        assertFalse(h.session.finishHand())
        assertTrue(h.state.finishing)
        assertEquals("Dealing…", h.state.actions.finishHandLabel)
        assertFalse(h.state.actions.finishHandEnabled)
        // The first step consumes the waiting plan without new draws.
        h.scheduler.runCurrent()
        val first = h.hooks.timingRecords().first()
        assertEquals(waiting.actor, first.id)
        assertEquals(waiting.delayMs, first.trace.thinking!!.durationMs)
        assertTrue(first.trace.thinking!!.expedited)
        h.scheduler.advanceBy(1000)
        assertEquals(Phase.DONE, h.game.phase)
        assertEquals(5, (h.game.practiceBoard ?: h.game.board).size)
        assertTrue(h.hooks.timingRecords().all { it.trace.thinking!!.expedited })
        assertTrue(h.random.draws > draws)
        assertFalse(h.state.finishing)
        assertFalse(h.state.actions.finishHandVisible)
        val snapshot = h.session.publicSnapshot()
        h.scheduler.advanceBy(20_000)
        assertEquals(snapshot, h.session.publicSnapshot())
        // Replay cancels every old deadline.
        h.session.replayHand()
        h.hooks.stop()
        h.scheduler.advanceBy(20_000)
        assertTrue(h.hooks.timingRecords().isEmpty())
        assertEquals(9 * STARTING_STACK, h.wealth())
    }

    @Test
    fun `finish hand after a fold-win adds a practice runout without changing the result`() {
        for (street in 0..2) {
            val h = Harness(seed = 30L + street)
            h.foldFinished(street)
            assertEquals(Phase.DONE, h.game.phase)
            assertEquals(listOf(0, 3, 4)[street], h.game.board.size)
            assertTrue(h.session.publicSnapshot().canContinue)
            val before = h.session.publicSnapshot()
            val stats = h.game.players.map { it.botStats.copy() }
            val board = h.game.board.toList()
            assertTrue(h.session.finishHand())
            assertFalse(h.session.finishHand())
            val after = h.session.publicSnapshot()
            assertEquals(5, after.board.size)
            assertEquals(board.map { it.toString() }, after.board.take(board.size))
            assertEquals(before.settlementBoard, after.settlementBoard)
            assertTrue(after.practiceRunout)
            assertFalse(after.canContinue)
            assertEquals(before.players.map { it.stack }, after.players.map { it.stack })
            assertEquals(before.pots, after.pots)
            assertEquals(before.uncalled, after.uncalled)
            assertEquals(before.result, after.result)
            assertEquals(stats, h.game.players.map { it.botStats })
            assertEquals(30_000, after.wealth)
            assertEquals(1, h.state.session.hands)
            assertEquals(SessionCopy.captionPractice, h.state.boardCaption)
            assertTrue(h.state.board.all { it.card != null })
            assertNull(h.state.showdown)
            assertFalse(h.state.actions.finishHandVisible)
            h.session.replayHand()
            h.hooks.stop()
            assertTrue(h.state.board.all { it.card == null })
            assertFalse(h.session.publicSnapshot().practiceRunout)
            assertEquals(0, h.state.session.hands)
        }
    }

    @Test
    fun `fold continuation settles unequal all-ins once and replay restores the hand`() {
        val h = Harness(seed = 5)
        h.heroTurn(9, unequal = true)
        val wealth = h.wealth()
        val hole = h.game.players[0].hole.toList()
        h.session.fold()
        h.allinRest()
        assertTrue(h.state.actions.finishHandVisible)
        h.session.finishHand()
        h.session.finishHand()
        h.scheduler.runUntilIdle()
        assertEquals(Phase.DONE, h.game.phase)
        assertEquals(5, h.game.board.size)
        assertTrue(h.game.pots.size > 1)
        val potLines = h.state.activity.entries.filter { it.type == com.august.noirpoker.core.LogType.RESULT && it.text != h.game.result }
        assertEquals(h.game.pots.map { it.label }, potLines.map { it.text.substringBefore(" → ").substringBeforeLast(" ") })
        assertEquals(wealth, h.game.players.sumOf { it.stack })
        assertEquals(1, h.game.stats.hands)
        assertEquals(8, h.state.showdown!!.scenes.size)
        val hand = h.game.hand
        h.session.replayHand()
        h.hooks.stop()
        assertEquals(hand, h.game.hand)
        assertEquals(hole, h.game.players[0].hole)
        assertEquals(0, h.game.stats.hands)
        assertNull(h.state.showdown)
        assertFalse(h.state.review.buttonVisible)
    }

    @Test
    fun `start new session during a thinking pause cancels the old action`() {
        val h = Harness(seed = 8)
        h.heroTurn(9)
        h.session.callOrCheck()
        h.scheduler.advanceBy(500)
        h.session.startNewSession()
        h.hooks.stop()
        val snapshot = h.session.publicSnapshot()
        h.scheduler.advanceBy(20_000)
        assertEquals(snapshot, h.session.publicSnapshot())
        assertTrue(h.hooks.timingRecords().isEmpty())
    }

    @Test
    fun `start new session cancels a queued finish-hand continuation`() {
        val h = Harness(seed = 9)
        h.heroTurn(9)
        h.session.fold()
        h.hooks.stop()
        assertTrue(h.session.finishHand())
        h.session.startNewSession()
        h.hooks.stop()
        assertEquals(0, h.state.session.hands)
        assertFalse(h.state.finishing)
        h.scheduler.advanceBy(50)
        assertFalse(h.game.players[0].folded)
        assertTrue(h.hooks.timingRecords().isEmpty())
    }

    @Test
    fun `background cancels stale timers and foreground restarts the same plan`() {
        val h = Harness(seed = 14)
        h.heroTurn(9)
        h.session.callOrCheck()
        val plan = h.hooks.thinking()!!
        h.scheduler.advanceBy(plan.delayMs - 10L)
        val epoch = h.session.epoch
        h.session.onBackground()
        assertTrue(h.session.epoch > epoch)
        assertTrue(h.state.backgrounded)
        val snapshot = h.session.publicSnapshot()
        h.scheduler.advanceBy(20_000)
        assertEquals(snapshot, h.session.publicSnapshot())
        assertTrue(h.hooks.timingRecords().isEmpty())
        // Commands that would schedule do not start timers while backgrounded.
        h.session.setDifficulty(Difficulty.NORMAL)
        assertEquals(0, h.scheduler.pendingCount)

        val draws = h.random.draws
        h.session.onForeground()
        val resumed = h.hooks.thinking()!!
        assertEquals(plan.actor, resumed.actor)
        assertEquals(plan.delayMs, resumed.delayMs)
        assertEquals(h.scheduler.nowMs, resumed.startedAt)
        assertEquals(draws, h.random.draws)
        h.scheduler.advanceBy(plan.delayMs - 1L)
        assertTrue(h.hooks.timingRecords().isEmpty())
        h.scheduler.advanceBy(1)
        assertEquals(1, h.hooks.timingRecords().size)
    }

    @Test
    fun `background stops a running finish-hand loop and foreground resumes normal pacing`() {
        val h = Harness(seed = 15)
        h.heroTurn(9)
        h.session.fold()
        val waiting = h.hooks.thinking()!!
        h.session.finishHand()
        h.session.onBackground()
        assertFalse(h.state.finishing)
        h.scheduler.advanceBy(10_000)
        assertTrue(h.hooks.timingRecords().isEmpty())
        assertFalse(h.session.finishHand())
        h.session.onForeground()
        // The unexecuted pending plan is kept, so no decision is re-drawn.
        assertEquals(waiting.actor, h.hooks.thinking()!!.actor)
        assertEquals(waiting.delayMs, h.hooks.thinking()!!.delayMs)
        h.runBots(200_000)
        h.scheduler.runUntilIdle()
        assertEquals(Phase.DONE, h.game.phase)
        assertEquals(waiting.actor, h.hooks.timingRecords().first().id)
        assertEquals(9 * STARTING_STACK, h.wealth())
    }

    @Test
    fun `long sessions on the virtual clock conserve every chip`() {
        for (count in listOf(5, 6, 9)) {
            val h = Harness(seed = 1000L + count)
            h.session.setSeatCount(count)
            h.session.openOpponentSettings()
            h.session.mixLineup()
            h.session.saveOpponentSettings()
            h.session.start()
            var chips = count * STARTING_STACK
            var rebuys = 0
            repeat(30) { handIndex ->
                var guard = 0
                while (h.game.phase != Phase.DONE) {
                    assertTrue(++guard < 500)
                    assertEquals(chips, h.wealth())
                    if (h.game.phase == Phase.PLAYING && h.game.actor == 0) {
                        val legal = legalActions(h.game, 0)
                        when ((handIndex + guard) % 5) {
                            0 -> h.session.fold()
                            1 -> if (legal.canRaise) {
                                h.session.preset(if (guard % 2 == 0) BetPreset.HALF_POT else BetPreset.POT)
                                assertTrue(h.session.raise())
                            } else {
                                h.session.callOrCheck()
                            }
                            else -> h.session.callOrCheck()
                        }
                        if (h.game.players[0].folded && h.game.phase != Phase.DONE && guard % 3 == 0) h.session.finishHand()
                    } else {
                        h.runBots()
                        if (h.game.phase != Phase.DONE && h.game.actor != 0) h.scheduler.runCurrent()
                    }
                }
                h.scheduler.runUntilIdle()
                assertEquals(chips, h.game.players.sumOf { it.stack })
                assertEquals(potSum(h), h.game.payouts.sum())
                h.session.nextHand()
                val newRebuys = h.state.activity.entries.count { it.text.endsWith("5,000 virtual chips") }
                rebuys += newRebuys
                chips += newRebuys * STARTING_STACK
                assertEquals(chips, h.wealth())
            }
            assertEquals(31, h.game.hand)
            assertEquals(30, h.state.session.hands)
            assertEquals(count, h.state.playerCount)
        }
    }

    private fun potSum(h: Harness) = h.game.players.sumOf { it.total }

    @Test
    fun `bot chip actions emit flights and sounds only while sound is on`() {
        val h = Harness(seed = 16)
        h.session.toggleSound()
        h.effects.clear()
        h.heroTurn(6)
        h.session.callOrCheck()
        assertTrue(h.effects.contains(SessionEffect.ChipFlight(0)))
        assertTrue(h.effects.contains(SessionEffect.Sound(SoundKind.CHIP)))
        h.session.toggleSound()
        h.effects.clear()
        h.session.fold()
        assertTrue(h.effects.none { it is SessionEffect.Sound })
    }

    @Test
    fun `heroAction is a no-op while a bot is to act`() {
        val h = Harness(seed = 2)
        h.session.start()
        assertTrue(h.game.actor != 0)
        assertFalse(h.session.heroAction(Action.CALL))
    }
}
