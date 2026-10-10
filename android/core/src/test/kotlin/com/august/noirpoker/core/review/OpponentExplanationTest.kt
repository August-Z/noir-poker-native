package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.BOT_PROFILES
import com.august.noirpoker.core.BotDecisionRecord
import com.august.noirpoker.core.BotView
import com.august.noirpoker.core.EmotionMode
import com.august.noirpoker.core.HistoryEntry
import com.august.noirpoker.core.LegalActions
import com.august.noirpoker.core.RandomSource
import com.august.noirpoker.core.chooseBotAction
import com.august.noirpoker.core.freshBotMood
import com.august.noirpoker.core.parseCards
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Port of the opponent-explanation case in the reference `review-lines.test.js`. */
class OpponentExplanationTest {
    @Test
    fun `a weak all-in call is explained as a randomized exception, not as good odds`() {
        val v = BotView(
            id = 1,
            hole = parseCards("7s 2h"),
            street = 0,
            position = "UTG",
            count = 6,
            stack = 5000,
            pot = 5000,
            currentBet = 5000,
            rivals = 1,
            equity = 0.07,
            contestable = 10000,
            history = listOf(HistoryEntry(0, 0, Action.RAISE, 5000)),
            legal = LegalActions(enabled = true, toCall = 5000, callAmount = 5000, minRaiseTo = 10000, maxRaiseTo = 5000),
        )
        val d = chooseBotAction(v, BOT_PROFILES[0], freshBotMood(), EmotionMode.OFF, RandomSource { 0.0 })
        assertEquals(Action.CALL, d.action)
        assertEquals("loose-exception", d.trace.reason)
        assertTrue("insufficient-equity" in d.trace.exceptions)
        val e = explainOpponent(BotDecisionRecord(1, "Mia", 1, 1, d.action, d.amount, d.trace.copy(view = v)))
        assertTrue("mistake" in e.detail, e.detail)
        assertTrue("random range" in e.warning, e.warning)
        assertTrue(d.trace.checks.all { it.selected })
    }
}
