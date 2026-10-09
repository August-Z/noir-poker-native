package com.august.noirpoker.core.session

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.BotStats
import com.august.noirpoker.core.LogType
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.Player
import com.august.noirpoker.core.act
import com.august.noirpoker.core.evaluate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SessionPresentationTest {
    private fun presets(h: Harness) = h.state.actions.presets.associate { it.preset to it.amount }

    @Test
    fun `presets select the exact reference amounts`() {
        val h = Harness()
        h.heroTurn(6)
        // Preflop, unraised: currentBet 50, minRaise 50, pot 75.
        assertEquals(
            mapOf(BetPreset.MIN to 100, BetPreset.HALF_POT to 100, BetPreset.POT to 125, BetPreset.ALL_IN to 5000),
            presets(h),
        )
        assertEquals(listOf("Min", "½ Pot", "Pot", "All-In"), h.state.actions.presets.map { it.label })
        assertTrue(h.session.preset(BetPreset.POT))
        assertEquals(125, h.state.actions.bet)
        assertEquals("2-bet open to", h.state.actions.raiseCaption)
        assertEquals("2-bet open to 125", h.state.actions.raiseA11y)
        h.session.preset(BetPreset.ALL_IN)
        assertEquals("2-bet all-in to", h.state.actions.raiseCaption)
        // Facing an open to 150: Min is 250.
        h.bettingTurn(3)
        assertEquals(250, presets(h)[BetPreset.MIN])
        // Pot 225 (SB 25 + BB 50 + 150): half = 150 + max(100, round(4.5) * 25 = 125) = 275.
        assertEquals(275, presets(h)[BetPreset.HALF_POT])
        assertEquals(150 + 225, presets(h)[BetPreset.POT])
        assertEquals("3-bet raise to", run { h.session.preset(BetPreset.MIN); h.state.actions.raiseCaption })
        // Postflop first bet.
        h.bettingTurn(1, 1)
        h.session.preset(BetPreset.MIN)
        assertEquals("1-bet bet to", h.state.actions.raiseCaption)
        assertEquals(50, h.state.actions.bet)
        h.bettingTurn(3, 2)
        assertEquals("3-bet raise to", h.state.actions.raiseCaption)
    }

    @Test
    fun `the slider snaps to 25 except for the exact all-in and bet is clamped on render`() {
        val h = Harness()
        h.heroTurn(6)
        assertEquals(150, h.state.actions.bet)
        assertEquals(100, h.state.actions.sliderMin)
        assertEquals(5000, h.state.actions.sliderMax)
        h.session.setBet(137)
        assertEquals(125, h.state.actions.bet)
        h.session.setBet(138)
        assertEquals(150, h.state.actions.bet)
        h.session.setBet(4999)
        assertEquals(5000, h.state.actions.bet)
        h.session.setBet(5000)
        assertEquals(5000, h.state.actions.bet)
        h.session.setBet(10)
        assertEquals(100, h.state.actions.bet)
        h.session.nudgeBet(3)
        assertEquals(175, h.state.actions.bet)
        h.session.nudgeBet(-10)
        assertEquals(100, h.state.actions.bet)
        // Short stack: the bet is clamped into the legal range on the next render.
        h.bettingTurn(3, 0, short = true)
        assertEquals(175, h.state.actions.bet)
        assertEquals("3-bet short all-in to", h.state.actions.raiseCaption)
    }

    @Test
    fun `call button and decision text follow the legal actions`() {
        val h = Harness()
        h.heroTurn(6)
        val a = h.state.actions
        assertEquals("Call", a.callLabel)
        assertEquals("50", a.callAmountText)
        assertEquals("Call 50", a.callA11y)
        assertEquals("Your turn. 50 chips to call.", a.decisionText)
        assertTrue(a.controlsVisible && a.decisionStripVisible && a.raiseEnabled)
        assertFalse(a.nextHandVisible)
        h.bettingTurn(1, 1)
        assertEquals("Check", h.state.actions.callLabel)
        assertNull(h.state.actions.callAmountText)
        assertEquals(SessionCopy.decisionCanCheck, h.state.actions.decisionText)
        h.bettingTurn(3, 0, short = true)
        assertEquals("Your turn. 150 chips to call.", h.state.actions.decisionText)
        h.session.fold()
        assertTrue(h.state.actions.decisionText.endsWith("is acting. You can watch the rest of this hand.") ||
            h.game.phase == Phase.DONE)
        h.foldWin()
        assertEquals("", h.state.actions.decisionText)
        assertFalse(h.state.actions.decisionStripVisible)
        assertTrue(h.state.actions.nextHandVisible)
        assertEquals("Next Hand", h.state.actions.nextHandLabel)
        assertTrue(h.state.actions.replayVisible)
    }

    @Test
    fun `a call that does not reopen raising says so`() {
        val h = Harness()
        h.heroTurn(6)
        h.session.raise(100)
        h.hooks.stop()
        h.hooks.mutate { g ->
            // Seat 4 calls, seat 5 (CO? the button chain) short-raises all-in below a full raise.
            g.players[5].stack = 75
            while (g.actor != 5) act(g, g.actor, Action.CALL)
            act(g, 5, Action.RAISE, 125)
            while (g.actor != 0) act(g, g.actor, Action.CALL)
        }
        val legal = com.august.noirpoker.core.legalActions(h.game, 0)
        assertFalse(legal.raiseReopened)
        assertEquals("Your turn. 25 chips to call." + SessionCopy.decisionNotReopened, h.state.actions.decisionText)
        assertFalse(h.state.actions.raiseEnabled)
        assertTrue(h.state.actions.presets.all { !it.enabled && it.amount == null })
    }

    @Test
    fun `seat chips show bet ordinals and call meanings`() {
        val h = Harness()
        h.bettingTurn(4)
        val seats = h.state.seats.associateBy { it.id }
        assertEquals("2-bet", seats.getValue(3).action.label)
        assertEquals("150", seats.getValue(3).action.amountText)
        assertEquals("2-bet open to 150 · 150 in this round", seats.getValue(3).action.meaning)
        assertEquals("3-bet", seats.getValue(4).action.label)
        assertEquals("SB", seats.getValue(1).action.label)
        assertEquals("BB", seats.getValue(2).action.label)
        assertEquals("Fold", seats.getValue(5).action.label)
        assertTrue(h.state.activity.entries.any { it.text == "River: 2-bet open to 150" })
        h.session.preset(BetPreset.MIN)
        assertEquals("4-bet raise to", h.state.actions.raiseCaption)
        h.bettingTurn(3, 1)
        val s = h.state.seats.associateBy { it.id }
        assertEquals("1-bet", s.getValue(1).action.label)
        assertEquals("2-bet", s.getValue(2).action.label)
        // Waiting seats and the hero's chip before acting.
        assertEquals("Fold", s.getValue(3).action.label)
    }

    @Test
    fun `seat action chip parsing covers every engine action text`() {
        val h = Harness()
        h.heroTurn(6)
        val g = h.game
        fun chip(text: String, recent: Boolean = false, bet: Int = 0): ActionChip {
            val p = Player(id = 1, name = "Mia", action = text, bet = bet)
            p.lastAction = com.august.noirpoker.core.LastAction(text, 1, bet)
            return seatActionChip(g, p, recent)
        }
        assertEquals(ActionChip("SB", 25, "25", "SB 25 · 25 in this round"), chip("SB 25"))
        assertEquals("Call", chip("Call 1,800", bet = 2000).label)
        assertEquals("Added 1,800 · 2,000 in this round", chip("Call 1,800", bet = 2000).meaning)
        assertEquals("Flop · Added 1,800 · 2,000 in this round", chip("Call 1,800", recent = true, bet = 2000).meaning)
        assertEquals("All-In", chip("All-In 500").label)
        assertEquals("2-bet Short All-In", chip("2-bet short all-in to 125").label)
        assertEquals("4-bet All-In", chip("4-bet all-in to 4,000").label)
        assertEquals(4000, chip("4-bet all-in to 4,000").amount)
        assertEquals("2-bet", chip("2-bet open to 150").label)
        assertEquals("2-bet Open", chip("2-bet open to 150", recent = true).label)
        assertEquals("1-bet Bet", chip("1-bet bet to 100", recent = true).label)
        assertEquals("3-bet Raise", chip("3-bet raise to 650", recent = true).label)
        assertEquals(ActionChip("Fold"), chip("Fold"))
        assertEquals(ActionChip("Check"), chip("Check"))
        assertEquals(ActionChip("All-In"), chip("All-In"))
        assertEquals(ActionChip("Waiting"), chip(""))
        assertEquals(ActionChip("Thinking", isDeciding = true), seatActionChip(g, g.players[0]))
    }

    @Test
    fun `activity is chronological, numbered and marks the hero`() {
        for (count in listOf(6, 9)) {
            val h = Harness(seed = count.toLong())
            h.river(count)
            h.finish()
            val entries = h.state.activity.entries
            assertEquals(h.game.logs.size, entries.size)
            assertEquals((1..entries.size).toList(), entries.map { it.number })
            assertEquals(h.game.logs.reversed().map { it.text }, entries.map { it.text })
            fun idx(pred: (ActivityEntryState) -> Boolean) = entries.indexOfFirst(pred)
            val milestones = listOf(
                idx { it.text.startsWith("Hand 1 begins") },
                idx { it.type == LogType.BLIND },
                idx { it.text.startsWith("Flop · ") },
                idx { it.text.startsWith("Turn · ") },
                idx { it.text.startsWith("River · ") },
                idx { it.text == h.game.result },
            )
            assertEquals(0, milestones[0])
            assertEquals(milestones.sorted(), milestones)
            assertTrue(milestones.all { it >= 0 })
            assertTrue(entries.filter { it.playerId == 0 }.all { it.isHero })
            assertEquals("FINISHED", h.state.activity.badge)
            // Eye toggles never change the activity.
            h.session.toggleReveal(1)
            assertEquals(entries.map { it.text }, h.state.activity.entries.map { it.text })
        }
    }

    @Test
    fun `activity shows assigned personas without relabeling the current hand`() {
        val h = Harness()
        h.session.start()
        h.session.openOpponentSettings()
        h.session.assignSeatStyle(1, "viktor")
        h.session.assignSeatStyle(2, "st")
        h.session.assignSeatStyle(3, "jungleman")
        h.session.assignSeatStyle(4, "dwan")
        h.session.saveOpponentSettings()
        h.river(6)
        h.finish()
        val texts = h.state.activity.entries.map { it.text }
        val blinds = h.state.activity.entries.first { it.type == LogType.BLIND }
        assertEquals("Mia (Viktor Blom): SB 25 · Alex (ST Wang): BB 50", blinds.text)
        assertEquals(
            listOf(TextSegment("Mia"), TextSegment(" (Viktor Blom)", true), TextSegment(": SB 25 · Alex"), TextSegment(" (ST Wang)", true), TextSegment(": BB 50")),
            blinds.segments,
        )
        assertTrue(texts.any { "River (Daniel Cates)" in it })
        assertTrue(texts.any { "Kai (Tom Dwan)" in it })
        assertTrue(texts.none { "Luna (" in it || "You (" in it })
        // The street log is not mistaken for the player River.
        assertTrue(texts.any { it.startsWith("River · ") })
        assertTrue(h.state.showdown!!.scenes.any { it.nameSegments.plainText() == "River (Daniel Cates)" })

        h.foldPotRefund()
        assertTrue(h.game.result.startsWith("Alex wins"))
        assertTrue(h.state.activity.entries.last().text.startsWith("Alex (ST Wang) wins"))
        assertTrue(h.state.activity.entries.any { it.text == "Uncalled 75 chips returned to Alex (ST Wang)" })
        h.session.openOpponentSettings()
        h.session.assignSeatStyle(2, "abao")
        h.session.saveOpponentSettings()
        h.session.toggleReveal(2)
        assertTrue(h.state.activity.entries.none { "(A Bao)" in it.text })
        h.session.nextHand()
        h.foldRest()
        assertTrue(h.state.activity.entries.any { "Alex (A Bao)" in it.text })
        assertTrue(h.state.activity.entries.none { "(ST Wang)" in it.text })
    }

    @Test
    fun `activity formatter matches whole names only and keeps identities from creation`() {
        val players = listOf(
            Player(0, "You", botProfile = "tan"),
            Player(1, "Mia"),
            Player(2, "Alex", botProfile = "st"),
            Player(3, "River", botProfile = "jungleman"),
        )
        val f = ActivityFormatter(players)
        assertEquals("You: Call 50 · Mia: Fold", f.format("You: Call 50 · Mia: Fold").plainText())
        assertEquals("Hand 1 begins · Button: Alex (ST Wang)", f.format("Hand 1 begins · Button: Alex").plainText())
        assertEquals("Main Pot 125 → Alex (ST Wang) 125", f.format("Main Pot 125 → Alex 125").plainText())
        assertEquals("Uncalled 75 chips returned to River (Daniel Cates)", f.format("Uncalled 75 chips returned to River").plainText())
        assertEquals("Alexandra: Fold · RIVER", f.format("Alexandra: Fold · RIVER").plainText())
        assertEquals("Alex (ST Wang): Check", f.format("Alex (ST Wang): Check").plainText())
        assertEquals("River · 7♠", f.format("River · 7♠", skipLeadingStreetName = true).plainText())
        players[2].botProfile = "dwan"
        assertEquals("Alex (ST Wang)", f.format("Alex").plainText())
        assertEquals("Alex (Tom Dwan)", ActivityFormatter(players).format("Alex").plainText())
    }

    @Test
    fun `showdown scenes highlight exactly the evaluated best five`() {
        for (count in 5..9) {
            val h = Harness(seed = 100L + count)
            h.river(count)
            assertNull(h.state.showdown)
            assertEquals(count - 1, h.state.seats.count { it.revealed && it.cards.size == 2 })
            assertTrue(h.state.seats.all { it.peek == null })
            h.finish()
            val sd = assertNotNull(h.state.showdown)
            assertEquals(count, sd.scenes.size)
            assertEquals(h.state.seats.size, h.state.seats.count { it.peek != null })
            for (scene in sd.scenes) {
                val p = h.game.players[scene.scene.id]
                assertEquals(evaluate(p.hole + h.game.board).cards.map { it.key }.toSet(), scene.scene.cards.map { it.key }.toSet())
                assertEquals(scene.scene.awards.isNotEmpty(), scene.isWinner)
            }
            // Rendering again keeps the same key (animations do not replay).
            val key = sd.key
            h.session.toggleReveal(1)
            assertEquals(key, h.state.showdown!!.key)
        }
    }

    @Test
    fun `hand scenes order cards and explain the category`() {
        val h = Harness()
        h.scene("Qh Qc", "4d 6s Kh 5h 3s", count = 9, totals = listOf(500, 50, 100, 200, 300, 400, 500, 600, 700), folded = listOf(3, 7), otherHoles = mapOf(1 to "7c 8d"))
        val scenes = h.state.showdown!!.scenes
        assertEquals(7, scenes.size)
        val hero = scenes.first { it.scene.id == 0 }.scene
        // 3-4-5-6 plus... the hero has a pair of queens; Mia has a straight 4-8.
        assertEquals("Pair of Queens", hero.explanation)
        assertEquals(listOf(12, 12, 13, 6, 5), hero.cards.map { it.rank })
        assertEquals(listOf(true, true, false, false, false), hero.highlights)
        val mia = scenes.first { it.scene.id == 1 }.scene
        assertEquals("Straight", mia.label)
        assertEquals("Eight-high straight", mia.explanation)
        assertEquals(listOf(4, 5, 6, 7, 8), mia.cards.map { it.rank })
        assertEquals(HandMotion.STRAIGHT, mia.motion)
        assertTrue(scenes.first { it.scene.id == 1 }.isWinner)
        assertEquals("No pot won", scenes.first { it.scene.id == 0 }.statusText)
        assertEquals("Best five cards", scenes.first { it.scene.id == 0 }.footerText)
        assertTrue(h.state.showdown!!.context.startsWith("7 players at showdown · Main Pot and Side Pots settled separately"))
        // Folded seats have no scene but can be revealed.
        assertTrue(scenes.none { it.scene.id == 3 || it.scene.id == 7 })

        h.scene("Ah 2d", "As Kd 2c 7h 9s", folded = listOf(0, 2, 3, 4, 5), otherHoles = mapOf(1 to "Ac Qd"))
        assertEquals("One Pair", h.state.seats.first { it.id == 1 }.badge!!.text)
        assertTrue(h.state.seats.first { it.id == 1 }.badge!!.isWinner)
        assertEquals("Folded · Two Pair", h.state.hero.rankBadge!!.text)
        assertFalse(h.state.actions.decisionStripVisible)
        assertEquals(SessionCopy.captionShowdownFolded, h.state.boardCaption)

        h.scene("5c 4d", "Ah 2s 3h 9c Kd", otherHoles = mapOf(1 to "Qs Qd"), folded = listOf(2, 3, 4, 5))
        val wheel = h.state.showdown!!.scenes.first { it.scene.id == 0 }.scene
        assertEquals(listOf(14, 2, 3, 4, 5), wheel.cards.map { it.rank })
        assertEquals("Five-high straight", wheel.explanation)
        assertEquals("Won +600", h.state.showdown!!.scenes.first { it.scene.id == 0 }.statusText)
        assertEquals("Main Pot +600", h.state.showdown!!.scenes.first { it.scene.id == 0 }.footerText)
        assertEquals(SessionCopy.captionShowdownHero, h.state.boardCaption)
        assertTrue(h.state.board.filter { it.card != null }.count { it.card!!.best } == 3)

        h.scene("2c 3d", "As Ks Qs Js Ts", count = 5, totals = listOf(100, 100, 1, 1, 1), folded = listOf(2, 3, 4))
        val royal = h.state.showdown!!.scenes.first().scene
        assertEquals(HandMotion.ROYAL, royal.motion)
        assertEquals("10 · J · Q · K · A of one suit", royal.explanation)
        val pot = h.state.potDetails.pots.single()
        assertEquals("203 chips · Split", pot.splitTotalText)
        assertEquals(setOf("+101", "+102"), pot.awards.map { it.amountText }.toSet())
        assertEquals(SessionCopy.potOddChipNote, pot.oddChipNote)
        assertEquals(setOf("You", "Mia"), pot.awards.map { it.winnerText }.toSet())
        assertTrue(h.state.showdown!!.scenes.all { it.footerText.startsWith("Main Pot · Split +10") })
    }

    @Test
    fun `winner crowns follow pot awards and refunds alone are not wins`() {
        val h = Harness()
        h.scene("As Ac", "2s 3h 4c 8d 9s", totals = listOf(100, 200, 300, 300, 0, 0), folded = listOf(4, 5), otherHoles = mapOf(1 to "Ks Kc", 2 to "Qd Qh", 3 to "Jh Jd"))
        assertEquals(listOf("Main Pot", "Side Pot 1", "Side Pot 2"), h.game.pots.map { it.label })
        assertEquals("Total Pot · 2 Side Pots", h.state.potButtonLabel)
        assertEquals("You win 400 chips", h.state.hero.rankBadge!!.a11y)
        assertEquals(listOf(1, 2), h.state.seats.filter { it.isWinner }.map { it.id })
        assertEquals("Mia wins 300 chips", h.state.seats.first { it.id == 1 }.badge!!.a11y)
        assertEquals("Settled separately · Main Pot 400 + 2 Side Pots", h.state.boardCaption)
        h.session.toggleReveal(1)
        assertEquals("Winner", h.state.seats.first { it.id == 1 }.badge!!.text)
        assertTrue(h.state.seats.first { it.id == 1 }.isWinner)

        h.scene("7c 8d", "2h 4s 6d 9c Kh", totals = listOf(1000, 200, 100, 100, 100, 100), folded = listOf(2, 3, 4, 5), otherHoles = mapOf(1 to "As Ad"))
        assertEquals("You", h.session.publicSnapshot().uncalled.single().name)
        assertNull(h.state.hero.rankBadge?.takeIf { it.isWinner })
        assertEquals("Uncalled bet returned · You", h.state.potDetails.refunds.single().text)
    }

    @Test
    fun `settled pot details keep awards and refunds separate`() {
        val h = Harness()
        h.foldPotRefund()
        val s = h.state
        assertTrue(s.activity.entries.any { it.text == "Alex wins 125 chips" })
        val alex = s.seats.first { it.id == 2 }
        assertEquals("Winner", alex.badge!!.text)
        assertEquals("All other players folded · Won 125 chips", alex.badge!!.title)
        h.session.openPotDetails()
        val d = h.state.potDetails
        assertTrue(d.open)
        assertEquals("Hand Settlement", d.title)
        assertNull(d.note)
        val pot = d.pots.single()
        assertNull(pot.splitTotalText)
        assertEquals(listOf("Alex wins"), pot.awards.map { it.winnerText })
        assertEquals("All other players folded", pot.awards.single().label)
        assertEquals("+125", pot.awards.single().amountText)
        assertEquals("Uncalled bet returned · Alex", d.refunds.single().text)
        assertEquals(75, d.refunds.single().amount)
        assertEquals("Alex's uncalled 75 chips were returned", d.refunds.single().a11y)
        assertFalse(pot.expanded)
        assertEquals("You're not in this pot · Eligible at settlement: Alex", pot.distributionEligibility)
        assertEquals(3, pot.contributions.size)
        assertEquals(listOf("Alex", "Kai · Folded", "Luna · Folded"), pot.contributions.map { it.text }.sortedBy { it })
        h.session.togglePotDistribution(0)
        assertTrue(h.state.potDetails.pots.single().expanded)
        h.finish()
        assertTrue(h.state.potDetails.pots.single().expanded)
        h.session.closePotDetails()
        assertFalse(h.state.potDetails.open)
        assertFalse(h.state.potDetails.pots.single().expanded)
    }

    @Test
    fun `live pot details show conditional eligibility`() {
        val h = Harness()
        h.heroTurn(6, unequal = true)
        h.session.preset(BetPreset.ALL_IN)
        h.session.raise()
        h.hooks.stop()
        h.hooks.mutate { g -> if (g.phase == Phase.PLAYING && g.actor != 0) act(g, g.actor, Action.CALL) }
        h.session.openPotDetails()
        val d = h.state.potDetails
        assertEquals("Main Pot and Side Pots", d.title)
        assertEquals(SessionCopy.potNoteLive, d.note)
        assertTrue(d.pots.any { it.heroEligible && it.eligibilityLabel == "You're eligible" })
        assertTrue(d.pots.all { it.awards.isEmpty() })
        assertTrue(d.refunds.all { it.text.startsWith("To be called or returned · ") && !it.returned })
        assertTrue(d.refunds.isNotEmpty())
    }

    @Test
    fun `observed VPIP and PFR round half up and restart after a restyle`() {
        val h = Harness()
        h.foldWin(6)
        h.hooks.mutate { g ->
            g.players[1].botStats = BotStats(hands = 3, vpip = 1, pfr = 2)
            g.players[2].botStats = BotStats(hands = 8, vpip = 1, pfr = 3)
            g.players[3].botStats = BotStats()
            g.players[4].botStats = BotStats(hands = 1, vpip = 1, pfr = 0)
        }
        h.session.openOpponentSettings()
        val roster = h.state.opponentsDialog!!.roster
        assertEquals("3 hands · VPIP 33% · PFR 67%", roster[0].observed)
        // 1/8 = 12.5% and 3/8 = 37.5% round half up.
        assertEquals("8 hands · VPIP 13% · PFR 38%", roster[1].observed)
        assertEquals("0 hands · VPIP — · PFR —", roster[2].observed)
        assertEquals("1 hand · VPIP 100% · PFR 0%", roster[3].observed)
        // Off-table seats have no counters yet.
        assertEquals("0 hands · VPIP — · PFR —", roster[7].observed)
        assertTrue(roster.all { it.observedTitle == SessionCopy.rosterObservedTitle })

        // A style change restarts that seat's counters at the next deal only.
        h.session.assignSeatStyle(1, "tan")
        assertTrue(h.session.saveOpponentSettings())
        h.session.openOpponentSettings()
        assertEquals("3 hands · VPIP 33% · PFR 67%", h.state.opponentsDialog!!.roster[0].observed)
        h.session.discardOpponentSettings()
        h.session.nextHand()
        h.hooks.stop()
        h.session.openOpponentSettings()
        val next = h.state.opponentsDialog!!.roster
        assertEquals("0 hands · VPIP — · PFR —", next[0].observed)
        assertEquals("8 hands · VPIP 13% · PFR 38%", next[1].observed)
    }

    @Test
    fun `session stats, coach and header copy`() {
        val h = Harness()
        h.foldPotRefund()
        val s = h.state
        assertEquals("Hand Over", s.streetLabel)
        assertEquals(1, s.session.hands)
        assertEquals(0, s.session.wins)
        assertEquals("0%", s.session.winRateText)
        assertEquals("+0 chips · Net this session", s.session.changeText)
        assertEquals("Hand Recap", s.coach.stage)
        assertEquals(SessionCopy.tipDoneFolded, s.coach.tip)
        assertEquals("125", s.potText)
        h.foldWin(6, 0)
        assertEquals("Winner", h.state.hero.rankBadge!!.text)
        assertEquals(SessionCopy.tipDoneUncontested, h.state.coach.tip)
        assertEquals("100%", h.state.session.winRateText)
        h.heroTurn(6)
        assertEquals("Preflop Strategy", h.state.coach.stage)
        assertTrue(h.state.coach.tip.endsWith(" This call is about ${com.august.noirpoker.core.jsRound(50.0 / com.august.noirpoker.core.contestableAfterCall(h.game, 0, 50) * 100).toInt()}% of the pot you can win."))
        h.session.toggleHints()
        assertFalse(h.state.coach.visible)
        assertEquals("Off", h.state.coach.toggleLabel)
        assertEquals("false", h.storage.values[PreferencesStore.HINTS_KEY])
    }

    @Test
    fun `the public snapshot never exposes private traces or hidden cards`() {
        val h = Harness(seed = 77)
        h.heroTurn(9)
        h.session.fold()
        h.session.finishHand()
        h.scheduler.runCurrent()
        for (snapshot in listOf(h.session.publicSnapshot())) {
            val text = snapshot.toString()
            for (banned in listOf("thinking", "closeness", "acting", "rawEquity", "trace", "botDecisions")) {
                assertFalse(text.contains(banned), banned)
            }
            for (p in snapshot.players.drop(1)) {
                val seat = h.game.players[p.id]
                if (h.game.phase != Phase.DONE && !h.game.revealed) assertNull(p.cards)
                if (p.cards != null) assertEquals(seat.hole.map { it.toString() }, p.cards)
            }
        }
        h.heroTurn(6)
        assertTrue(h.session.publicSnapshot().players.drop(1).all { it.cards == null })
        assertTrue(h.state.seats.all { it.cards.isEmpty() && it.cardBacks == 2 })
    }
}
