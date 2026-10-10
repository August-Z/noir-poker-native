package com.august.noirpoker.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Golden values recorded by running the pinned reference engine under Node with
 * `Math.random` replaced by `seedRandom(seed)` (Mulberry32). One stream feeds
 * the deck shuffle, equity sampling, bot policy and thinking time in call order,
 * so any difference in random consumption order or count changes the digest.
 */
class ReferenceParityTest {
    @Test
    fun `seeded random matches the reference Mulberry32 stream`() {
        val r1 = SeededRandom(1)
        assertEquals(listOf(0.6270739405881613, 0.002735721180215478, 0.5274470399599522), List(3) { r1.next() })
        val r42 = SeededRandom(42)
        assertEquals(listOf(0.6011037519201636, 0.44829055899754167, 0.8524657934904099), List(3) { r42.next() })
        val max = SeededRandom(0xFFFF_FFFFL)
        assertEquals(listOf(0.8964226141106337, 0.189478256739676), List(2) { max.next() })
    }

    @Test
    fun `equity sampling consumes the same values as the reference`() {
        val random = SeededRandom(11)
        val equity = estimateEquity(cards("As Ks"), cards("2h 7c Kd"), 3, 40, random)
        assertEquals(0.575, equity)
        assertEquals(0.7010517623275518, random.next())
    }

    private data class Golden(
        val count: Int,
        val seed: Long,
        val hands: Int,
        val mode: String,
        val difficulty: Difficulty,
        val length: Int,
        val hash: String,
        val head: String,
        val stacks: String,
        val buyin: Int,
        val wins: Int,
    )

    private val lineup = mapOf(
        1 to "tan", 2 to "st", 3 to "zang", 4 to "peter", 5 to "abao", 6 to "viktor", 7 to "jungleman", 8 to "dwan",
    )

    private fun session(golden: Golden): Pair<String, Game> {
        val random = SeededRandom(golden.seed)
        val g = newGame(golden.count)
        applyBotSettings(g, mapOf("emotionMode" to golden.mode, "assignments" to lineup))
        g.difficulty = golden.difficulty
        val events = mutableListOf<String>()
        repeat(golden.hands) {
            startHand(g, random)
            events.add("H${g.hand}:${g.dealer}:" + g.deck.takeLast(6).joinToString(".") { it.key })
            var guard = 0
            while (g.phase != Phase.DONE) {
                check(++guard <= 1000)
                if (g.phase == Phase.BETWEEN) {
                    advanceStreet(g)
                    events.add("S${g.street}")
                    continue
                }
                if (g.actor == 0) {
                    val d = botDecision(g, random)
                    act(g, 0, d.action, d.amount)
                    events.add("0" + d.action.id[0] + (d.amount?.toString() ?: ""))
                } else {
                    val id = g.actor
                    val plan = planBotTurn(g, random)
                    val d = executeBotTurn(g, plan, expedited = true)
                    events.add("$id" + d.action.id[0] + (d.amount?.toString() ?: "") + "@" + plan.delayMs)
                }
            }
            events.add(
                "R" + g.players.joinToString(",") { it.stack.toString() } + "|" +
                    g.players.drop(1).joinToString(",") {
                        "${it.botMood.kind.id[0]}${it.botStats.vpip}.${it.botStats.pfr}.${it.botStats.postActions}"
                    },
            )
        }
        return events.joinToString(" ") to g
    }

    private val sessions = listOf(
        Golden(
            6, 7, 12, "lively", Difficulty.NORMAL, 2758, "46384acd",
            "H1:0:1-7.3-4.1-2.0-9.1-9.2-6 3r125@3148 4c@3257 5c@3328 0r475 1f@3231 2f@2882 3f@4463 4f@2622 5c@3960 S1 5r725@2810 0r2600 5c@4501 S2 5r1925@5150 0c S3 S3 R10325,4975,4950,4875,4875,0|s0.0.0,s0.0.0,s1.1.0,s1.0.0,f1.0.3 H2:1:2-2.2-3.0-12.3-4.2-5.2-7 4c@3074 5r200@2392 0c 1c@3494 2r975@4108 3f@3590 4f",
            "875,3025,14700,2875,29375,4150", 5000, 4,
        ),
        Golden(
            9, 2024, 10, "subtle", Difficulty.HARD, 2461, "743e8c9f",
            "H1:0:2-2.0-10.2-4.3-9.3-2.0-2 3c@2714 4c@2853 5c@2312 6f@3462 7f@2567 8r300@3149 0f 1f@2640 2f@3723 3f@3557 4f@4454 5f@1991 R5000,4975,4950,4950,4950,4950,5000,5000,5225|s0.0.0,s0.0.0,s1.0.0,s1.0.0,s1.0.0,s0.0.0,s0.0.0,s1.1.0 H2:1:0-6.3-14.3-12.2-7.0-12.3-8 4r150@2962 5f@3121 6f@2914 7r425@2998 8f@2",
            "4725,13125,150,4350,16200,525,6275,4800,4850", 5000, 0,
        ),
        Golden(
            5, 99, 15, "off", Difficulty.EASY, 2790, "d0501082",
            "H1:0:0-8.0-11.3-5.3-14.0-4.1-4 3f@1673 4c@2408 0f 1c@2643 2c@2440 S1 1r100@3302 2r300@4695 4f@3162 1r1100@5927 2c@4483 S2 1r2275@3504 2r3850@4713 1c@4317 S3 S3 R5000,10050,0,5000,4950|s1.0.4,s0.0.3,s0.0.0,s1.0.0 H2:1:3-9.3-5.0-8.0-11.3-13.1-6 4c@3633 0c 1r250@4179 2f@2321 3f@2443 4f@5256 0f R4950,10",
            "3425,4425,5100,25625,11425", 10000, 0,
        ),
        Golden(
            7, 31337, 8, "lively", Difficulty.HARD, 2112, "b38e723c",
            "H1:0:3-12.1-13.1-6.1-7.2-7.3-13 3r125@3297 4c@3768 5c@1903 6f@3774 0f 1c@2704 2c@4140 S1 1c@2785 2c@2771 3c@3972 4c@2888 5c@3545 S2 1c@1832 2c@2671 3c@2521 4c@5041 5c@3223 S3 1r575@4332 2c@5510 3f@4091 4f@4679 5f@3739 S3 R5000,6075,4300,4875,4875,4875,5000|s1.0.3,s1.0.3,s1.1.2,s1.0.2,s1.0.2,s0.0.0 H",
            "9625,6262,8875,4750,5163,5650,4675", 5000, 1,
        ),
        Golden(
            8, 5, 8, "subtle", Difficulty.NORMAL, 1788, "f0318899",
            "H1:0:2-14.0-10.1-12.1-14.3-12.3-4 3c@3197 4c@2856 5f@2728 6c@2662 7c@4468 0c 1r400@2494 2f@3105 3f@3170 4f@2984 6f@2083 7f@4917 0c S1 1r825@4717 0c S2 1c@2541 0c S3 1c@2442 0r1575 1r3775@4171 0c S3 R5125,5125,4950,4950,4950,5000,4950,4950|s1.1.4,s0.0.0,s1.0.0,s1.0.0,s0.0.0,s1.0.0,s1.0.0 H2:1:1-5.3-1",
            "5000,775,5050,4600,15225,4700,4825,4825", 5000, 1,
        ),
    )

    @Test
    fun `seeded all-bot sessions reproduce the reference decisions, decks and thinking times`() {
        for (golden in sessions) {
            val (events, g) = session(golden)
            assertEquals(golden.head, events.take(300), "first events, ${golden.count} seats seed ${golden.seed}")
            assertEquals(golden.length, events.length, "event length, seed ${golden.seed}")
            assertEquals(golden.hash, fnv(events), "event digest, seed ${golden.seed}")
            assertEquals(golden.stacks, g.players.joinToString(",") { it.stack.toString() })
            assertEquals(golden.buyin, g.stats.buyin)
            assertEquals(golden.hands, g.stats.hands)
            assertEquals(golden.wins, g.stats.wins)
            assertTrue(g.botDecisions.isNotEmpty() || g.history.none { it.id != 0 })
        }
    }
}
