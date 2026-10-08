package com.august.noirpoker.core

import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlin.test.fail

/** The reference unit tests' 32-bit LCG (`seeded(seed)`). */
class Lcg(seed: Long) : RandomSource {
    private var n: Int = seed.toInt()
    override fun next(): Double {
        n = n * 1664525 + 1013904223
        return (n.toLong() and 0xFFFF_FFFFL).toDouble() / 4294967296.0
    }
}

/** `Math.random = () => 0.999999`: the shuffle swaps nothing, so the deck stays in order. */
val UNSHUFFLED = RandomSource { 0.999999 }

fun cards(text: String): MutableList<Card> = parseCards(text).toMutableList()

fun wealth(g: Game): Int = g.players.sumOf { it.stack } + (if (g.phase == Phase.DONE) 0 else potSize(g))

fun totalStacks(g: Game): Int = g.players.sumOf { it.stack }

/** Plays to settlement: `between` → advance, otherwise the actor takes [action]. */
fun finish(g: Game, action: Action = Action.CALL) {
    var guard = 0
    while (g.phase != Phase.DONE) {
        if (++guard > 1000) fail("hand did not finish")
        if (g.phase == Phase.BETWEEN) advanceStreet(g) else act(g, g.actor, action)
    }
}

/** Plays to settlement with bot decisions for every seat, checking legality. */
fun finishWithBots(g: Game, random: RandomSource) {
    var guard = 0
    while (g.phase != Phase.DONE) {
        if (++guard > 1000) fail("hand did not finish")
        if (g.phase == Phase.BETWEEN) {
            advanceStreet(g)
            continue
        }
        val legal = legalActions(g)
        val d = botDecision(g, random)
        when (d.action) {
            Action.RAISE -> {
                assertTrue(legal.canRaise)
                val amount = d.amount!!
                assertTrue(amount in legal.minRaiseTo..legal.maxRaiseTo)
            }
            Action.CHECK -> assertTrue(legal.canCheck)
            else -> {}
        }
        act(g, g.actor, d.action, d.amount)
    }
}

/** The `postflop(stacks)` setup from the reference rules audit. */
fun postflop(stacks: List<Int> = List(6) { 1000 }): Game {
    val g = newGame()
    g.dealer = 5
    g.phase = Phase.PLAYING
    g.street = 1
    g.currentBet = 0
    g.minRaise = 50
    g.pending = (0..5).toMutableList()
    g.actor = 0
    for (p in g.players) p.stack = stacks.getOrElse(p.id) { 1000 }
    return g
}

/** The `fixture(totals, folded, holes)` setup from the reference multi-pot tests. */
fun potFixture(
    totals: List<Int>,
    folded: List<Int> = emptyList(),
    holes: List<String> = listOf("As Ah", "Ks Kh", "Qs Qh", "Js Jh", "Ts Th", "9s 9h"),
): Game {
    val g = newGame()
    g.phase = Phase.BETWEEN
    g.street = 3
    g.board = cards("2c 3d 4h 7s 8c")
    for (p in g.players) {
        val total = totals.getOrElse(p.id) { 0 }
        p.total = total
        p.bet = total
        p.stack = STARTING_STACK - total
        p.hole = if (p.id < holes.size) cards(holes[p.id]) else mutableListOf()
        p.folded = total == 0 || p.id in folded
    }
    return g
}

/** Every chip is accounted for after settlement. */
fun assertConserved(g: Game, before: Int) {
    assertEquals(before, totalStacks(g))
    assertEquals(potSize(g), g.pots.sumOf { it.amount } + g.refunds.sumOf { it.amount })
    for (pot in g.pots) {
        assertEquals(pot.amount, pot.awards.sumOf { it.amount })
        assertEquals(pot.amount, pot.contributions.sumOf { it.amount })
        for (award in pot.awards) assertTrue(award.id in pot.eligible)
    }
}

/** Asserts that [block] throws a [PokerException] and leaves [g] unchanged. */
fun assertRejected(g: Game, block: () -> Unit): PokerException {
    val before = g.deepCopy()
    val error = assertFailsWith<PokerException> { block() }
    assertTrue(g.sameState(before), "state changed after a rejected call")
    return error
}

fun fnv(s: String): String {
    var h = 2166136261L.toInt()
    for (c in s) h = (h xor c.code) * 16777619
    return (h.toLong() and 0xFFFF_FFFFL).toString(16)
}
