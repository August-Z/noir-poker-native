package com.august.noirpoker.core.session

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.BotSettings
import com.august.noirpoker.core.Difficulty
import com.august.noirpoker.core.EmotionMode
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.STARTING_STACK
import com.august.noirpoker.core.SeededRandom
import com.august.noirpoker.core.applyBotSettings
import com.august.noirpoker.core.defaultBotSettings
import com.august.noirpoker.core.newGame
import com.august.noirpoker.core.planBotTurn
import com.august.noirpoker.core.startHand
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TableSessionFlowTest {
    @Test
    fun `first launch deals hand one with safe defaults`() {
        val h = Harness()
        h.session.start()
        val s = h.state
        assertEquals(1, s.hand)
        assertEquals("01", s.handNumber)
        assertEquals(6, s.playerCount)
        assertEquals("6-MAX", s.tableTag)
        assertEquals("6-Handed No-Limit", s.tableSize)
        assertEquals(Difficulty.NORMAL, s.settings.difficulty)
        assertTrue(s.settings.hints)
        assertFalse(s.settings.sound)
        assertEquals(EmotionMode.SUBTLE, h.game.emotionMode)
        assertEquals("Balanced", s.opponents.text)
        assertNull(s.opponents.changeNote)
        assertTrue(s.seats.all { it.styleShort == "Balanced" })
        assertEquals("Build experience, starting this hand", s.session.changeText)
        assertEquals("—", s.session.winRateText)
        assertEquals("Preflop", s.streetLabel)
        assertEquals(SessionCopy.captionPreflop, s.boardCaption)
        assertEquals(5, s.board.size)
        assertTrue(s.board.all { it.card == null && it.a11y == "Undealt community card" })
        // Starting again does not deal a second hand.
        h.session.start()
        assertEquals(1, h.state.hand)
    }

    @Test
    fun `the session consumes randomness exactly like the reference controller`() {
        val h = Harness(seed = 7)
        h.session.start()
        // Reference: newGame, applyBotSettings, startHand (51 draws), then planBotTurn
        // for the first actor (decision and timing from the same stream).
        val rng = SeededRandom(7)
        val g = newGame(6)
        applyBotSettings(g, defaultBotSettings())
        startHand(g, rng)
        assertEquals(g.players.map { it.hole }, h.game.players.map { it.hole })
        val plan = planBotTurn(g, rng, rng)
        assertEquals(plan.delayMs, h.hooks.thinking()!!.delayMs)
        // Re-scheduling a current plan draws nothing.
        val draws = h.random.draws
        assertEquals(h.hooks.thinking(), h.hooks.resumeBots())
        assertEquals(draws, h.random.draws)
    }

    @Test
    fun `relaunch restores every saved option before the first fresh hand`() {
        val storage = InMemoryStorage()
        val first = Harness(storage = storage)
        first.session.start()
        first.session.setSeatCount(9)
        first.session.setDifficulty(Difficulty.HARD)
        first.session.toggleHints()
        first.session.toggleSound()
        first.session.openOpponentSettings()
        first.session.mixLineup()
        first.session.setEmotionMode(EmotionMode.LIVELY)
        first.session.saveOpponentSettings()
        // The current hand is unchanged and shows the pending note.
        assertEquals(6, first.state.playerCount)
        assertEquals("balanced", first.game.players[1].botProfile)
        assertEquals("Applies Next Hand", first.state.opponents.text)
        assertNotNull(first.state.opponents.changeNote)
        assertEquals(SessionCopy.tableChangeNote(9), first.state.settings.tableChangeNote)

        val second = Harness(storage = storage)
        second.session.start()
        val s = second.state
        assertEquals(9, s.playerCount)
        assertEquals(Difficulty.HARD, s.settings.difficulty)
        assertFalse(s.settings.hints)
        assertFalse(s.coach.visible)
        assertTrue(s.settings.sound)
        assertEquals("8 Styled Opponents", s.opponents.text)
        assertNull(s.opponents.changeNote)
        assertNull(s.settings.tableChangeNote)
        assertEquals(1, s.hand)
        assertEquals(0, s.session.hands)
        assertEquals(EmotionMode.LIVELY, second.game.emotionMode)
        assertEquals(MIXED_LINEUP.values.toList(), second.game.players.drop(1).map { it.botProfile })
        assertTrue(second.game.players.all { it.stack + it.bet == STARTING_STACK })
        assertEquals("""{"playerCount":9,"difficulty":"hard"}""", storage.values[PreferencesStore.TABLE_KEY])
    }

    @Test
    fun `next hand keeps session totals while replay reverses only this hand`() {
        val h = Harness()
        h.foldPotRefund()
        assertEquals(Phase.DONE, h.game.phase)
        assertEquals(1, h.state.session.hands)
        val stacksAfterHand = h.game.players.map { it.stack }
        val dealer = h.game.dealer
        val hand = h.game.hand
        val holes = h.game.players.map { it.hole }

        // Replay: same hand number, holes and button; stats and payouts reversed.
        assertTrue(h.state.actions.replayVisible)
        assertTrue(h.session.replayHand())
        h.hooks.stop()
        assertEquals(hand, h.game.hand)
        assertEquals(dealer, h.game.dealer)
        assertEquals(holes, h.game.players.map { it.hole })
        assertEquals(0, h.state.session.hands)
        assertEquals(1, h.game.replayAttempt)
        assertEquals("Replay 1", h.state.replayBadge)
        assertEquals(SessionCopy.replayNote, h.state.replayNote)
        assertFalse(h.state.actions.replayVisible)
        assertEquals(6 * STARTING_STACK, h.wealth())

        // Replay the same scripted line again: the result is identical to the first attempt.
        h.foldRest()
        assertEquals(Phase.DONE, h.game.phase)
        assertEquals(1, h.state.session.hands)

        // Next Hand: totals kept, button moves, fresh shuffle.
        h.session.nextHand()
        h.hooks.stop()
        assertEquals(hand + 1, h.game.hand)
        assertEquals((dealer + 1) % 6, h.game.dealer)
        assertEquals(1, h.state.session.hands)
        assertEquals(0, h.game.replayAttempt)
        assertNull(h.state.replayBadge)

        // Start New Session: fresh table and stats.
        h.session.startNewSession()
        h.hooks.stop()
        assertEquals(1, h.game.hand)
        assertEquals(0, h.state.session.hands)
        assertTrue(h.game.players.all { it.stack + it.total == STARTING_STACK })
        assertNotEquals(stacksAfterHand, h.game.players.map { it.stack + it.total })
    }

    @Test
    fun `replaying twice reverses the payout exactly once`() {
        val h = Harness(seed = 3)
        h.heroTurn(6)
        val baseline = h.game.players.map { it.stack + it.total }
        h.session.fold()
        h.session.finishHand()
        h.scheduler.runUntilIdle()
        assertEquals(Phase.DONE, h.game.phase)
        assertEquals(1, h.game.stats.hands)
        repeat(2) {
            assertTrue(h.session.replayHand())
            h.hooks.stop()
            assertEquals(baseline, h.game.players.map { it.stack + it.total })
            assertEquals(0, h.game.stats.hands)
            assertTrue(h.game.players.drop(1).all { it.botStats.hands == 0 })
            h.session.fold()
            h.session.finishHand()
            h.scheduler.runUntilIdle()
            assertEquals(1, h.game.stats.hands)
            assertEquals(6 * STARTING_STACK, h.wealth())
        }
        assertEquals(2, h.game.replayAttempt)
    }

    @Test
    fun `seat count changes apply at the next deal and never on replay`() {
        val h = Harness()
        h.session.start()
        h.foldWin()
        assertTrue(h.session.setSeatCount(5))
        assertFalse(h.session.setSeatCount(4))
        assertFalse(h.session.setSeatCount(10))
        assertEquals(6, h.state.playerCount)
        assertEquals("Switches to 5 players next hand · Stacks reset to 5,000 and stats start over", h.state.settings.tableChangeNote)
        h.session.replayHand()
        assertEquals(6, h.state.playerCount)
        h.foldRest()
        h.session.nextHand()
        h.hooks.stop()
        assertEquals(5, h.state.playerCount)
        assertEquals(1, h.game.hand)
        assertEquals(0, h.state.session.hands)
        assertNull(h.state.settings.tableChangeNote)
        assertEquals(5, h.state.seats.size + 1)
        assertEquals(listOf(15.0 to 59.0, 23.0 to 0.0, 77.0 to 0.0, 85.0 to 59.0), h.state.seats.map { it.layoutX to it.layoutY })
    }

    @Test
    fun `difficulty applies immediately and is kept by replay and new sessions`() {
        val h = Harness()
        h.session.start()
        h.session.setDifficulty(Difficulty.EASY)
        assertEquals(Difficulty.EASY, h.game.difficulty)
        h.foldWin()
        h.session.replayHand()
        assertEquals(Difficulty.EASY, h.game.difficulty)
        h.session.startNewSession()
        assertEquals(Difficulty.EASY, h.game.difficulty)
        assertEquals("Easy", h.state.settings.difficultyOptions.first { it.value == Difficulty.EASY }.label)
    }

    @Test
    fun `reveal toggles change one seat only and clear on next hand, replay and reset`() {
        for (reset in listOf("replay", "next", "session")) {
            val h = Harness()
            h.foldWin(9)
            val winner = 8
            assertTrue(h.state.seats.none { it.revealed })
            assertTrue(h.state.seats.all { it.peek != null && !it.peek!!.pressed })
            assertFalse(h.session.toggleReveal(0))
            assertTrue(h.session.toggleReveal(winner))
            val seat = h.state.seats.first { it.id == winner }
            assertTrue(seat.revealed)
            assertEquals(h.game.players[winner].hole.map { it.toString() }, seat.cards.map { it.text })
            assertEquals("Hide Leo's hole cards", seat.peek!!.a11y)
            assertEquals(1, h.state.seats.count { it.revealed })
            assertEquals(SessionEffect.RevealToggled(winner, true), h.effects.last())
            // A folded seat can be revealed too, and the board stays untouched.
            assertTrue(h.session.toggleReveal(3))
            assertEquals(2, h.state.seats.count { it.revealed })
            assertEquals(h.game.players[winner].hole.map { it.toString() }, h.publicSnapshot().players[winner].cards)
            when (reset) {
                "replay" -> h.session.replayHand()
                "next" -> h.session.nextHand()
                else -> h.session.startNewSession()
            }
            h.hooks.stop()
            assertTrue(h.state.seats.none { it.revealed || it.peek != null }, reset)
            if (reset != "session") h.foldRest() else h.foldWin(9)
            assertTrue(h.state.seats.none { it.revealed }, reset)
            assertEquals(null, h.publicSnapshot().players[winner].cards)
        }
    }

    @Test
    fun `reveal toggles are unavailable during play`() {
        val h = Harness()
        h.heroTurn()
        assertFalse(h.session.toggleReveal(2))
        assertTrue(h.state.seats.all { it.peek == null })
    }

    @Test
    fun `hero last action appears at once and persists through streets until the hero acts again`() {
        val h = Harness()
        h.heroTurn(9)
        assertNull(h.state.hero.lastAction)
        assertEquals("Your Turn", h.state.hero.turnText)
        assertTrue(h.session.callOrCheck())
        h.hooks.stop()
        assertEquals("Call", h.state.hero.lastAction!!.label)
        assertEquals("50", h.state.hero.lastAction!!.amountText)
        assertEquals("Waiting", h.state.hero.turnText)
        h.respondToHero(150)
        assertEquals("Your Turn", h.state.hero.turnText)
        assertEquals("Call", h.state.hero.lastAction!!.label)
        assertTrue(h.session.preset(BetPreset.MIN))
        assertEquals(250, h.state.actions.bet)
        assertTrue(h.session.raise())
        h.hooks.stop()
        val raise = h.state.hero.lastAction!!
        assertEquals("3-bet Raise", raise.label)
        assertEquals(250, raise.amount)
        assertTrue(raise.meaning!!.startsWith("Preflop · "))
        h.respondToHero(0, nextStreet = true)
        assertEquals(3, h.game.board.size)
        assertEquals(0, h.game.players[0].bet)
        assertEquals("3-bet Raise", h.state.hero.lastAction!!.label)
        assertTrue(h.session.callOrCheck())
        h.hooks.stop()
        assertEquals("Check", h.state.hero.lastAction!!.label)
        assertNull(h.state.hero.lastAction!!.amount)
        h.respondToHero(0, nextStreet = true)
        assertTrue(h.session.fold())
        h.hooks.stop()
        assertEquals("Fold", h.state.hero.lastAction!!.label)
        assertEquals("Folded", h.state.hero.turnText)
        h.session.finishHand()
        h.scheduler.runUntilIdle()
        assertEquals(Phase.DONE, h.game.phase)
        assertEquals("Fold", h.state.hero.lastAction!!.label)
        assertNull(h.state.hero.turnText)
        h.session.replayHand()
        h.hooks.stop()
        assertNull(h.state.hero.lastAction)
        assertTrue(h.session.preset(BetPreset.ALL_IN))
        assertTrue(h.session.raise())
        h.hooks.stop()
        assertEquals("2-bet All-In", h.state.hero.lastAction!!.label)
        assertEquals("5,000", h.state.hero.lastAction!!.amountText)
        assertEquals("All-In", h.state.hero.turnText)
        h.bettingTurn(3, 0, short = true)
        assertEquals("3-bet short all-in to", run { h.session.preset(BetPreset.ALL_IN); h.state.actions.raiseCaption })
        h.session.raise()
        h.hooks.stop()
        assertEquals("3-bet Short All-In", h.state.hero.lastAction!!.label)
        assertEquals(175, h.state.hero.lastAction!!.amount)
    }

    @Test
    fun `settled seats keep their final actions until next hand leaves only the blinds`() {
        val h = Harness()
        h.retainedRiver(9)
        h.finish()
        assertEquals(Phase.DONE, h.game.phase)
        val chips = h.state.seats.map { it.action } + h.state.hero.lastAction!!
        val call = chips.first { it.label == "Call" }
        assertTrue(call.meaning!!.endsWith("300 in this round"), call.meaning)
        assertEquals("2-bet Raise", h.state.hero.lastAction!!.label)
        assertEquals(300, h.state.hero.lastAction!!.amount)
        assertTrue(chips.any { it.label == "Fold" })
        h.session.nextHand()
        h.hooks.stop()
        assertEquals(2, h.game.players.count { it.lastAction != null })
        assertTrue(h.game.players.mapNotNull { it.lastAction?.text }.all { it.startsWith("SB ") || it.startsWith("BB ") })
    }

    @Test
    fun `all-in sizes survive settlement and eye toggles`() {
        for (count in 5..9) {
            val h = Harness(seed = count.toLong())
            h.heroTurn(count)
            h.session.preset(BetPreset.ALL_IN)
            h.session.raise()
            h.allinRest()
            val before = h.game.players.map { it.lastAction }
            while (h.game.phase != Phase.DONE) h.finish()
            assertEquals(5, h.game.board.size)
            assertEquals(before, h.game.players.map { it.lastAction })
            assertEquals("2-bet All-In", h.state.hero.lastAction!!.label)
            assertTrue(h.state.seats.all { it.action.label == "All-In" && it.action.amountText == "5,000" })
            h.session.toggleReveal(1)
            assertEquals(before, h.game.players.map { it.lastAction })
            h.session.replayHand()
            h.hooks.stop()
            assertNull(h.state.hero.lastAction)
            assertEquals(2, h.game.players.count { it.lastAction != null })
        }
    }

    @Test
    fun `next hand rebuys a busted hero and labels the button accordingly`() {
        val h = Harness()
        h.scene("2c 3d", "As Ks Qs Js 9h", totals = List(6) { 5000 }, otherHoles = mapOf(1 to "Ts 4h"))
        assertEquals(0, h.game.players[0].stack)
        assertEquals("Rebuy and Keep Practicing", h.state.actions.nextHandLabel)
        h.session.nextHand()
        h.hooks.stop()
        assertEquals(STARTING_STACK, h.game.players[0].stack + h.game.players[0].total)
        assertEquals(10_000, h.game.stats.buyin)
        assertTrue(h.state.activity.entries.any { it.text == "You rebuy 5,000 virtual chips" })
    }

    @Test
    fun `hero actions are rejected when illegal and leave the game unchanged`() {
        val h = Harness()
        h.heroTurn()
        assertFalse(h.session.raise(60))
        assertFalse(h.session.heroAction(Action.CHECK))
        assertEquals(0, h.game.actor)
        h.foldWin()
        assertFalse(h.session.fold())
    }

    @Test
    fun `opponent settings apply next hand and freeze on replay`() {
        val h = Harness()
        h.foldWin(6)
        h.session.openOpponentSettings()
        val dialog = h.state.opponentsDialog!!
        assertEquals(8, dialog.roster.size)
        assertEquals(9, dialog.profileCards.size)
        assertEquals("balanced", dialog.selectedProfile)
        assertTrue(dialog.roster.drop(5).all { it.offTable && it.subtitle == "Not seated · Steady" })
        assertEquals("Seat 1 · Steady", dialog.roster[0].subtitle)
        assertEquals("Style this hand: Balanced", dialog.roster[0].currentStyle)
        assertEquals("Not seated yet; uses the saved next-hand setting", dialog.roster[7].currentStyle)
        assertEquals("1 hand · VPIP 0% · PFR 0%", dialog.roster[0].observed)
        listOf(1 to "tan", 2 to "st", 3 to "zang", 4 to "peter", 5 to "abao", 8 to "st").forEach { (seat, p) ->
            h.session.assignSeatStyle(seat, p)
        }
        assertEquals("st", h.state.opponentsDialog!!.selectedProfile)
        h.session.setEmotionMode(EmotionMode.LIVELY)
        assertTrue(h.session.saveOpponentSettings())
        assertNull(h.state.opponentsDialog)
        assertEquals("Applies Next Hand", h.state.opponents.text)
        assertEquals("balanced", h.game.players[1].botProfile)
        h.session.replayHand()
        assertEquals("balanced", h.game.players[1].botProfile)
        assertEquals("Applies Next Hand", h.state.opponents.text)
        h.foldRest()
        h.session.nextHand()
        h.hooks.stop()
        assertEquals(listOf("tan", "st", "zang", "peter", "abao"), h.game.players.drop(1).map { it.botProfile })
        assertEquals(EmotionMode.LIVELY, h.game.emotionMode)
        assertEquals("5 Styled Opponents", h.state.opponents.text)
        // Off-table assignments are preserved for larger tables.
        h.foldWin(6)
        h.session.setSeatCount(9)
        h.session.nextHand()
        h.hooks.stop()
        assertEquals("st", h.game.players[8].botProfile)
    }

    @Test
    fun `closing the opponent dialog without saving discards the draft`() {
        val h = Harness()
        h.session.start()
        h.session.openOpponentSettings()
        h.session.mixLineup()
        assertEquals("tan", h.state.opponentsDialog!!.selectedProfile)
        assertEquals("tan", h.state.opponentsDialog!!.roster[0].assignment)
        h.session.discardOpponentSettings()
        assertNull(h.state.opponentsDialog)
        assertEquals(defaultBotSettings(), h.session.savedBotSettings)
        h.session.openOpponentSettings()
        assertEquals("balanced", h.state.opponentsDialog!!.roster[0].assignment)
        // The previewed profile persists across opens.
        assertEquals("tan", h.state.opponentsDialog!!.selectedProfile)
        assertEquals(null, h.storage.values[PreferencesStore.OPPONENTS_KEY])
    }

    @Test
    fun `loss mood is visible and emotion off resets every mood next hand`() {
        val h = Harness()
        h.scene("As Ah", "Ac 2h 3d 4c 8s", totals = listOf(5000, 5000, 50, 50, 50, 50), folded = listOf(2, 3, 4, 5), otherHoles = mapOf(1 to "Ks Kd"))
        val seat = h.state.seats.first { it.id == 1 }
        assertEquals(com.august.noirpoker.core.MoodKind.FRUSTRATED, seat.mood)
        h.session.openOpponentSettings()
        assertTrue(h.state.opponentsDialog!!.roster[0].subtitle.contains("Chasing Losses"))
        assertNotNull(h.state.opponentsDialog!!.roster[0].moodReason)
        h.session.setEmotionMode(EmotionMode.OFF)
        h.session.saveOpponentSettings()
        h.session.nextHand()
        h.hooks.stop()
        assertEquals(EmotionMode.OFF, h.game.emotionMode)
        assertTrue(h.state.seats.all { it.mood == com.august.noirpoker.core.MoodKind.STEADY })
        assertTrue(h.publicSnapshot().players.drop(1).all { it.mood == "steady" })
    }

    @Test
    fun `saved settings with bot settings object round trip into the next deal`() {
        val storage = InMemoryStorage()
        PreferencesStore(storage).saveBotSettings(BotSettings(EmotionMode.OFF, (1..8).associateWith { "abao" }))
        val h = Harness(storage = storage)
        h.session.start()
        assertTrue(h.game.players.drop(1).all { it.botProfile == "abao" })
        assertEquals("5 Styled Opponents", h.state.opponents.text)
    }
}

private fun Harness.publicSnapshot() = session.publicSnapshot()
