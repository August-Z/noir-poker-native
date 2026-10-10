package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.Card
import com.august.noirpoker.core.EmotionMode
import com.august.noirpoker.core.Game
import com.august.noirpoker.core.MoodKind
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.RandomSource
import com.august.noirpoker.core.act
import com.august.noirpoker.core.advanceStreet
import com.august.noirpoker.core.botDecision
import com.august.noirpoker.core.deckOfCards
import com.august.noirpoker.core.freshBotMood
import com.august.noirpoker.core.getBotProfile
import com.august.noirpoker.core.jsRound
import com.august.noirpoker.core.newGame
import kotlin.math.floor
import kotlin.math.sqrt

/** Up to seven distinct legal candidates: fold, check/call, two sizes, the actual action, then [alternatives]. */
fun candidateActions(s: ReviewDecision, alternatives: List<CandidateAction?> = emptyList()): List<CandidateAction> {
    val candidates = mutableListOf(
        CandidateAction(Action.FOLD, 0),
        CandidateAction(if (s.legal.canCheck) Action.CHECK else Action.CALL, s.legal.callAmount),
    )
    if (s.legal.canRaise) {
        val targets = if (s.street == 0 && s.currentBet <= 50) {
            listOf(100.0, 150.0)
        } else if (s.currentBet > 0) {
            listOf(s.currentBet * 2.5, s.currentBet * 3.5)
        } else {
            listOf(s.pot * 0.33, s.pot * 0.65)
        }
        for (value in targets) {
            candidates.add(
                CandidateAction(
                    Action.RAISE,
                    minOf(s.legal.maxRaiseTo, maxOf(s.legal.minRaiseTo, (jsRound(value / 25) * 25).toInt())),
                ),
            )
        }
    }
    candidates.add(CandidateAction(s.action, s.amount))
    candidates.addAll(alternatives.filterNotNull())
    val unique = LinkedHashMap<String, CandidateAction>()
    for (a in candidates) {
        val legal = (a.action != Action.RAISE ||
            (s.legal.canRaise && a.amount >= s.legal.minRaiseTo && a.amount <= s.legal.maxRaiseTo)) &&
            (a.action != Action.CHECK || s.legal.canCheck)
        if (!legal) continue
        unique[a.action.id + (if (a.action == Action.RAISE) a.amount.toString() else "")] = CandidateAction(
            a.action,
            when (a.action) {
                Action.RAISE -> a.amount
                Action.CALL -> s.legal.callAmount
                else -> 0
            },
        )
    }
    return unique.values.take(7)
}

private class SampledDeal(val holes: Map<Int, List<Card>>, val deck: List<Card>)

private fun sampledDeal(s: ReviewDecision, rng: RandomSource, weighted: Boolean): SampledDeal {
    val known = (s.hole + s.board).map { it.key }.toSet()
    val pool = deckOfCards().filter { it.key !in known }.toMutableList()
    val holes = HashMap<Int, List<Card>>()
    holes[0] = s.hole.toList()
    val order = s.players.filter { it.id != 0 && !it.folded } + s.players.filter { it.id != 0 && it.folded }
    for (p in order) {
        var a: Int
        var b: Int
        while (true) {
            a = floor(rng.next() * pool.size).toInt()
            b = floor(rng.next() * (pool.size - 1)).toInt()
            if (b >= a) b++
            if (!weighted || p.folded) break
            if (rng.next() < rangeWeight(listOf(pool[a], pool[b]), s, p) / 6) break
        }
        holes[p.id] = listOf(pool[a], pool[b])
        pool.removeAt(maxOf(a, b))
        pool.removeAt(minOf(a, b))
    }
    for (i in pool.size - 1 downTo 1) {
        val j = floor(rng.next() * (i + 1)).toInt()
        val t = pool[i]
        pool[i] = pool[j]
        pool[j] = t
    }
    return SampledDeal(holes, pool)
}

/** A fresh game resumed from the public snapshot with sampled private cards. */
private fun resume(s: ReviewDecision, deal: SampledDeal): Game {
    val g = newGame(s.players.size)
    val button = s.players.firstOrNull { it.position == "BTN" }?.id
    g.phase = Phase.PLAYING
    g.hand = s.hand
    g.street = s.street
    g.actor = 0
    g.dealer = s.dealer ?: button ?: 0
    g.currentBet = s.currentBet
    g.minRaise = s.minRaise
    g.pending = s.pending.toMutableList()
    g.board = s.board.toMutableList()
    g.deck = deal.deck.toMutableList()
    g.history = s.history.toMutableList()
    g.decisions = mutableListOf()
    g.botDecisions = mutableListOf()
    g.logs = mutableListOf()
    g.emotionMode = s.emotionMode ?: EmotionMode.OFF
    for (p in s.players) {
        val mood = freshBotMood()
        mood.kind = p.state?.botMoodKind ?: MoodKind.STEADY
        val seat = g.players[p.id]
        seat.stack = p.stack
        seat.bet = p.bet
        seat.total = p.total
        seat.folded = p.folded
        seat.allin = p.allin
        seat.actedTo = p.state?.actedTo
        seat.checked = p.state?.checked ?: false
        seat.hole = deal.holes.getValue(p.id).toMutableList()
        seat.botProfile = getBotProfile(p.state?.botProfile).id
        seat.botMood = mood
    }
    return g
}

data class SimulationScenario(
    /** English scenario name (accessibility label). */
    val name: String,
    /** Mean net chip change from this decision onward. */
    val ev: Double,
    /** 1.96 × standard error. */
    val margin: Double,
    /** Share of trials in which this raise won the pot immediately. */
    val immediateFoldWin: Double,
)

/** One candidate's results: the random-range scenario, then the public-action-weighted one. */
data class SimulationRow(val action: CandidateAction, val scenarios: List<SimulationScenario>)

data class CounterfactualResult(
    /** In candidate order. */
    val rows: List<SimulationRow>,
    val trials: Int,
    val policyTrials: Int,
    val best: CandidateAction,
    val stable: Boolean,
    val method: String,
    val note: String,
)

private const val POLICY_TRIALS = 8

/**
 * Plays every candidate out from sampled private cards with the bot policies. Only the
 * public snapshot is read: original opponent holes, recorded traces, the future deck and
 * the outcome never enter these counterfactual hands. [checkpoint] runs between trials so
 * a caller can cancel stale work.
 */
fun compareCandidateActions(
    s: ReviewDecision,
    alternatives: List<CandidateAction?> = emptyList(),
    trials: Int = 40,
    checkpoint: () -> Unit = {},
): CounterfactualResult {
    if (trials < 2) throw ReviewException(ReviewCopy.errorSimTrials)
    val candidates = candidateActions(s, alternatives)
    val scenarios = candidates.map { mutableListOf<SimulationScenario>() }
    for (weighted in listOf(false, true)) {
        val rng = seedRandom(snapshotSeed(s) + (if (weighted) 11071 else 2003))
        val values = candidates.map { IntArray(trials) }
        val immediate = IntArray(candidates.size)
        for (i in 0 until trials) {
            checkpoint()
            val deal = sampledDeal(s, rng, weighted)
            val policySeed = floor(rng.next() * 4294967295.0).toLong()
            for (c in candidates.indices) {
                val g = resume(s, deal)
                val policy = seedRandom(policySeed)
                act(g, 0, candidates[c].action, candidates[c].amount)
                var actions = 0
                while (g.phase != Phase.DONE) {
                    if (++actions > 400) throw ReviewException(ReviewCopy.errorSimRunaway)
                    if (g.phase == Phase.BETWEEN) {
                        advanceStreet(g)
                    } else {
                        val d = botDecision(g, policy, POLICY_TRIALS)
                        act(g, g.actor, d.action, d.amount)
                    }
                }
                values[c][i] = g.players[0].stack - s.stack
                if (g.winners.any { it.id == 0 } && !g.showdown && g.street == s.street && candidates[c].action == Action.RAISE) {
                    immediate[c]++
                }
            }
        }
        for (c in candidates.indices) {
            var total = 0.0
            for (v in values[c]) total += v
            val mean = total / trials
            var squares = 0.0
            for (v in values[c]) squares += (v - mean) * (v - mean)
            val variance = squares / (trials - 1)
            scenarios[c].add(
                SimulationScenario(
                    name = if (weighted) ReviewCopy.simScenarioWeighted else ReviewCopy.simScenarioRandom,
                    ev = mean,
                    margin = 1.96 * sqrt(variance / trials),
                    immediateFoldWin = immediate[c].toDouble() / trials,
                ),
            )
        }
    }
    val rows = candidates.mapIndexed { c, a -> SimulationRow(a, scenarios[c].toList()) }
    // Stable sort by the worse of the two scenario means, descending; ties keep candidate order.
    val ranked = rows.sortedWith { a, b ->
        val d = b.scenarios.minOf { it.ev } - a.scenarios.minOf { it.ev }
        if (d > 0) 1 else if (d < 0) -1 else 0
    }
    val best = ranked[0]
    val stable = ranked.drop(1).all { other ->
        best.scenarios.withIndex().all { (i, v) -> v.ev - v.margin > other.scenarios[i].ev + other.scenarios[i].margin }
    }
    return CounterfactualResult(
        rows = rows,
        trials = trials,
        policyTrials = POLICY_TRIALS,
        best = best.action,
        stable = stable,
        method = "sampled-engine-rollout",
        note = ReviewCopy.simNote(POLICY_TRIALS),
    )
}
