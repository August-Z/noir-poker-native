package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.Card
import com.august.noirpoker.core.Game
import com.august.noirpoker.core.Player
import com.august.noirpoker.core.Pot
import com.august.noirpoker.core.RandomSource
import com.august.noirpoker.core.SeededRandom
import com.august.noirpoker.core.compare
import com.august.noirpoker.core.deckOfCards
import com.august.noirpoker.core.evaluate
import com.august.noirpoker.core.partitionPots
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.sqrt

/** Mulberry32 (`seedRandom`). The seed is reduced modulo 2^32, like `seed >>> 0`. */
fun seedRandom(seed: Long): RandomSource = SeededRandom(seed)

// ---------------------------------------------------------------------------
// snapshotSeed: FNV-1a over the exact JSON text the reference builds.
// ---------------------------------------------------------------------------

private fun StringBuilder.jsonString(s: String) {
    append('"')
    for (c in s) {
        when {
            c == '"' -> append("\\\"")
            c == '\\' -> append("\\\\")
            c == '\b' -> append("\\b")
            c == '\u000C' -> append("\\f")
            c == '\n' -> append("\\n")
            c == '\r' -> append("\\r")
            c == '\t' -> append("\\t")
            c < ' ' -> append("\\u").append(String.format("%04x", c.code))
            else -> append(c)
        }
    }
    append('"')
}

private fun StringBuilder.jsonCards(cards: List<Card>) {
    append('[')
    cards.forEachIndexed { i, c ->
        if (i > 0) append(',')
        append("{\"rank\":").append(c.rank).append(",\"suit\":").append(c.suit).append(",\"symbol\":")
        jsonString(c.symbol)
        append(",\"key\":")
        jsonString(c.key)
        append('}')
    }
    append(']')
}

/**
 * The JSON text `snapshotSeed` hashes, byte for byte: `JSON.stringify` of
 * `[hole, board, players(id, position, stack, bet, total, folded, allin, actedTo, checked,
 * botProfile, botMoodKind), history(id, street, action, amount), street, legal.callAmount]`.
 * Seat keys a hand-built snapshot omits are left out, as JavaScript drops `undefined`.
 */
fun snapshotSeedJson(s: ReviewDecision): String {
    val b = StringBuilder()
    b.append('[')
    b.jsonCards(s.hole)
    b.append(',')
    b.jsonCards(s.board)
    b.append(",[")
    s.players.forEachIndexed { i, p ->
        if (i > 0) b.append(',')
        b.append("{\"id\":").append(p.id).append(",\"position\":")
        b.jsonString(p.position)
        b.append(",\"stack\":").append(p.stack)
        b.append(",\"bet\":").append(p.bet)
        b.append(",\"total\":").append(p.total)
        b.append(",\"folded\":").append(p.folded)
        b.append(",\"allin\":").append(p.allin)
        val state = p.state
        if (state != null) {
            b.append(",\"actedTo\":").append(state.actedTo?.toString() ?: "null")
            b.append(",\"checked\":").append(state.checked)
            b.append(",\"botProfile\":")
            if (state.botProfile == null) b.append("null") else b.jsonString(state.botProfile)
            b.append(",\"botMoodKind\":")
            if (state.botMoodKind == null) b.append("null") else b.jsonString(state.botMoodKind.id)
        }
        b.append('}')
    }
    b.append("],[")
    s.history.forEachIndexed { i, a ->
        if (i > 0) b.append(',')
        b.append("{\"id\":").append(a.id).append(",\"street\":").append(a.street).append(",\"action\":")
        b.jsonString(a.action.id)
        b.append(",\"amount\":").append(a.amount).append('}')
    }
    b.append("],").append(s.street).append(',').append(s.legal.callAmount).append(']')
    return b.toString()
}

/** 32-bit FNV-1a over the UTF-16 code units of [snapshotSeedJson]; an unsigned 32-bit value. */
fun snapshotSeed(s: ReviewDecision): Long {
    var seed = 2166136261L.toInt()
    for (c in snapshotSeedJson(s)) seed = (seed xor c.code) * 16777619
    return seed.toLong() and 0xFFFF_FFFFL
}

// ---------------------------------------------------------------------------
// Call price
// ---------------------------------------------------------------------------

data class CallPrice(
    /** Pots the hero is eligible for after a call, in pot order. */
    val pots: List<Pot>,
    val contestable: Int,
    val cost: Int,
    val refundBefore: Int,
    val refundAfter: Int,
    /** Break-even pot equity, `cost / contestable` (0 when nothing is contestable). */
    val required: Double,
    /** No later betting decision follows this call. */
    val closing: Boolean,
)

/** `partitionPots` over the snapshot's public totals only. */
private fun partitionTotals(seats: List<Triple<Int, Int, Boolean>>) = partitionPots(
    Game(
        seats.map { (id, total, folded) -> Player(id = id, name = "", total = total, folded = folded) }.toMutableList(),
        dealer = 0,
    ),
)

// A call has different eligible opponents in each side pot. Exclude uncalled
// refunds and compare its extra cost with what folding would return already.
fun callPrice(s: ReviewDecision): CallPrice {
    val original = partitionTotals(s.players.map { Triple(it.id, it.total, it.folded) })
    val projected = partitionTotals(
        s.players.map { Triple(it.id, it.total + (if (it.id == 0) s.legal.callAmount else 0), it.folded) },
    )
    val refundBefore = original.refunds.filter { it.id == 0 }.sumOf { it.amount }
    val refundAfter = projected.refunds.filter { it.id == 0 }.sumOf { it.amount }
    val pots = projected.pots.filter { 0 in it.eligible }
    val contestable = pots.sumOf { it.amount }
    val cost = maxOf(0, s.legal.callAmount - refundAfter + refundBefore)
    val otherPending = s.pending.any { id -> id != 0 && !s.players[id].folded && !s.players[id].allin }
    val opponents = s.players.filter { it.id != 0 && !it.folded }
    val allInCovered = s.legal.callAmount == s.stack &&
        opponents.all { it.allin || it.total >= s.total + s.legal.callAmount }
    return CallPrice(
        pots = pots,
        contestable = contestable,
        cost = cost,
        refundBefore = refundBefore,
        refundAfter = refundAfter,
        required = if (contestable != 0) cost.toDouble() / contestable else 0.0,
        closing = (s.street == 3 && !otherPending) || allInCovered || opponents.all { it.allin },
    )
}

// ---------------------------------------------------------------------------
// Public-action range weighting and sampled pot equity
// ---------------------------------------------------------------------------

private fun drawPair(pool: List<Card>, rng: RandomSource): IntArray {
    val a = floor(rng.next() * pool.size).toInt()
    var b = floor(rng.next() * (pool.size - 1)).toInt()
    if (b >= a) b++
    return intArrayOf(a, b)
}

private val RAISE_TABLES = listOf(
    doubleArrayOf(1.0, 2.0, 4.0, 6.0),
    doubleArrayOf(0.15, 0.7, 3.0, 6.0),
    doubleArrayOf(0.04, 0.2, 1.5, 6.0),
)
private val CALL_TABLES = listOf(
    doubleArrayOf(1.0, 2.0, 3.0, 4.0),
    doubleArrayOf(0.2, 0.8, 3.0, 6.0),
    doubleArrayOf(0.08, 0.3, 2.0, 6.0),
)

private fun isCallOrRaise(a: Action) = a == Action.CALL || a == Action.RAISE

/**
 * Relative likelihood (0, 6] of [pair] for [opponent] given its public actions:
 * preflop raise depth when it last entered, and the strength of a postflop bet or large call.
 */
fun rangeWeight(pair: List<Card>, s: ReviewDecision, opponent: ReviewSeat): Double {
    val prefix = s.history.filter { it.street == 0 }
    val informativeIndex = prefix.indexOfLast { it.id == opponent.id && isCallOrRaise(it.action) }
    var preWeight = 1.0
    if (informativeIndex >= 0) {
        val informative = prefix[informativeIndex]
        val level = prefix.subList(0, informativeIndex + 1).count { it.action == Action.RAISE && it.amount > 50 }
        val tables = if (informative.action == Action.RAISE) RAISE_TABLES else CALL_TABLES
        val table = if (level >= 3) tables[2] else if (level == 2) tables[1] else tables[0]
        preWeight = table[startingTier(pair)]
    }
    if (s.street == 0) return preWeight
    val current = s.history.lastOrNull { it.street == s.street && it.id == opponent.id && isCallOrRaise(it.action) }
        ?: return preWeight
    val all = pair + s.board
    val score = evaluate(all).score[0]
    val suitedDraw = (0 until 4).any { suit -> all.count { it.suit == suit } == 4 && pair.any { it.suit == suit } }
    val madeWeight: Double = if (current.action == Action.RAISE) {
        if (score >= 4) 6.0 else if (score >= 2) 5.0 else if (score == 1) 3.0 else if (suitedDraw) 2.0 else 1.0
    } else if (current.amount >= maxOf(100.0, s.pot * 0.2)) {
        if (score >= 2) 5.0 else if (score == 1) 3.0 else if (suitedDraw) 2.0 else 1.0
    } else {
        return preWeight
    }
    // Prior preflop information remains relevant; max stays at six for rejection sampling.
    return if (informativeIndex >= 0) (preWeight * madeWeight) / 6 else madeWeight
}

enum class EquityMethod(val id: String) { ENUMERATION("enumeration"), SAMPLING("sampling") }

/**
 * Expected share of `price.contestable` returned to the hero. [method] and [samples] are
 * `null` when nothing is contestable (the reference omits them).
 */
data class SampledValue(
    val equity: Double,
    val margin: Double,
    val ev: Double,
    val method: EquityMethod? = null,
    val samples: Int? = null,
)

/** `Math.log(80)`, as a literal so every platform uses the same double. */
internal const val LN_80 = 4.382026634673881

fun sampleValue(s: ReviewDecision, price: CallPrice, trials: Int, weighted: Boolean): SampledValue {
    if (price.contestable == 0) return SampledValue(0.0, 0.0, 0.0)
    val rng = seedRandom(snapshotSeed(s) + (if (weighted) 7919 else 0))
    val known = (s.hole + s.board).map { it.key }.toSet()
    val available = deckOfCards().filter { it.key !in known }
    val opponents = s.players.filter { it.id != 0 && !it.folded }
    if (s.board.size == 5 && opponents.size == 1) {
        val hero = evaluate(s.hole + s.board).score
        val opponent = opponents[0]
        var weightSum = 0.0
        var valueSum = 0.0
        var combinations = 0
        for (i in 0 until available.size - 1) {
            for (j in i + 1 until available.size) {
                val pair = listOf(available[i], available[j])
                val c = compare(hero, evaluate(pair + s.board).score)
                var share = 0.0
                for (pot in price.pots) {
                    val factor = if (opponent.id !in pot.eligible) 1.0 else if (c > 0) 1.0 else if (c == 0) 0.5 else 0.0
                    share += pot.amount * factor
                }
                val fraction = share / price.contestable
                val weight = if (weighted) rangeWeight(pair, s, opponent) else 1.0
                weightSum += weight
                valueSum += fraction * weight
                combinations++
            }
        }
        val equity = valueSum / weightSum
        return SampledValue(equity, 0.0, equity * price.contestable - price.cost, EquityMethod.ENUMERATION, combinations)
    }
    var sum = 0.0
    for (t in 0 until trials) {
        val pool = available.toMutableList()
        val holes = HashMap<Int, List<Card>>()
        for (opponent in opponents) {
            var indices = drawPair(pool, rng)
            if (weighted) {
                while (rng.next() >= rangeWeight(listOf(pool[indices[0]], pool[indices[1]]), s, opponent) / 6) {
                    indices = drawPair(pool, rng)
                }
            }
            holes[opponent.id] = listOf(pool[indices[0]], pool[indices[1]])
            pool.removeAt(maxOf(indices[0], indices[1]))
            pool.removeAt(minOf(indices[0], indices[1]))
        }
        val board = s.board.toMutableList()
        while (board.size < 5) board.add(pool.removeAt(floor(rng.next() * pool.size).toInt()))
        val hero = evaluate(s.hole + board).score
        val scores = opponents.associate { it.id to evaluate(holes.getValue(it.id) + board).score }
        var returned = 0.0
        for (pot in price.pots) {
            var ties = 1
            var lost = false
            for (id in pot.eligible) {
                if (id == 0) continue
                val c = compare(scores.getValue(id), hero)
                if (c > 0) {
                    lost = true
                    break
                }
                if (c == 0) ties++
            }
            if (!lost) returned += pot.amount.toDouble() / ties
        }
        sum += returned / price.contestable
    }
    val equity = sum / trials
    val margin = min(1.0, sqrt(LN_80 / (2 * trials)))
    return SampledValue(equity, margin, equity * price.contestable - price.cost, EquityMethod.SAMPLING, trials)
}
