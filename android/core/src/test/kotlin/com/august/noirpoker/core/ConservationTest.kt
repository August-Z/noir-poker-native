package com.august.noirpoker.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ConservationTest {
    @Test
    fun `many seeded all-bot hands conserve every chip at every step`() {
        val modes = EmotionMode.entries
        for (count in 5..9) {
            val random = SeededRandom(count * 7919L)
            val g = newGame(count)
            applyBotSettings(g, BotSettings(modes[count % 3], (1..8).associateWith { BOT_PROFILES[(it + count) % 9].id }))
            g.difficulty = Difficulty.entries[count % 3]
            var chips = totalStacks(g)
            repeat(40) {
                startHand(g, random)
                chips += g.logs.count { it.type == LogType.INFO && it.text.endsWith("virtual chips") } * STARTING_STACK
                assertEquals(chips, wealth(g))
                var guard = 0
                while (g.phase != Phase.DONE) {
                    assertTrue(++guard < 1000)
                    when {
                        g.phase == Phase.BETWEEN -> advanceStreet(g)
                        g.actor == 0 -> {
                            val d = botDecision(g, random)
                            act(g, 0, d.action, d.amount)
                        }
                        else -> {
                            val plan = planBotTurn(g, random)
                            assertTrue(plan.delayMs in BotThinkLimits.MINIMUM..BotThinkLimits.MAXIMUM)
                            executeBotTurn(g, plan, expedited = true)
                        }
                    }
                    assertTrue(g.players.all { it.stack >= 0 && it.total >= 0 })
                    assertEquals(chips, wealth(g))
                    val live = currentPots(g)
                    assertEquals(potSize(g), live.pots.sumOf { it.amount } + live.refunds.sumOf { it.amount })
                }
                assertConserved(g, chips)
                assertEquals(potSize(g), g.payouts.sum())
                assertEquals(g.history.count { it.id != 0 }, g.botDecisions.size)
            }
        }
    }
}
