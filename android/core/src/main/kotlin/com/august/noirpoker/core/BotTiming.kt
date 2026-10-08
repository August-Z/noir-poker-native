package com.august.noirpoker.core

// Synthetic table pacing, not measured timings or tells of named players.
// Accept only the actor's decision view; no full game, hidden rival cards or deck.

private fun clamp(n: Double, lo: Double = 0.0, hi: Double = 1.0): Double = maxOf(lo, minOf(hi, n))

object BotThinkLimits {
    const val MINIMUM = 1200
    const val MAXIMUM = 8000
}

enum class Acting(val id: String) { DELIBERATE("deliberate"), QUICK("quick"), NEUTRAL("neutral") }

data class ThinkingFactors(
    val closeness: Double,
    val texture: Double,
    val route: Double,
    val position: Double,
    val commitment: Double,
    val sizing: Double,
    val effectiveStack: Int,
    val spr: Double,
)

data class BotThinking(
    val durationMs: Int,
    val model: String,
    val acting: Acting,
    val factors: ThinkingFactors,
)

/** Thinking time as written to the private execution record. */
data class BotThinkingRecord(
    val durationMs: Int,
    val model: String,
    val acting: Acting,
    val factors: ThinkingFactors,
    val expedited: Boolean,
    val waitedMs: Long,
)

private val MOOD_TEMPO: Map<MoodKind, Int> = mapOf(
    MoodKind.CAUTIOUS to 450,
    MoodKind.FRUSTRATED to -300,
    MoodKind.REACTIVE to -220,
    MoodKind.CONFIDENT to -140,
)

private val OUT_OF_POSITION = setOf("SB", "BB", "UTG", "UTG+1", "MP", "LJ")

/** Consumes 4 random values, or 5 when the acting style is deliberate. */
fun botThinkingTime(decision: BotDecision, random: RandomSource = SystemRandom): BotThinking {
    val t = decision.trace
    val v = requireNotNull(t.view) { "botThinkingTime needs the decision view" }
    val legal = v.legal
    val draw = v.features.draw
    val raises = v.history.filter { it.action == Action.RAISE }
    val streetRaises = raises.filter { it.street == v.street }
    val lastRaiser = raises.lastOrNull()?.id
    fun roll(): Double = clamp(random.next())
    val affordable = t.affordableRangePassed ?: (t.cheapEntry && t.admitted)
    val priceCloseness = if (legal.toCall > 0 && !(v.street == 0 && affordable)) {
        clamp(1 - kotlin.math.abs(t.equity + t.callTolerance - t.odds - 0.02) / 0.16)
    } else {
        0.0
    }
    val rangeCloseness = if (v.street == 0) clamp(1 - kotlin.math.abs(t.percentile - t.range) / 0.15) else 0.0
    val closeness = maxOf(priceCloseness, rangeCloseness)
    val suits = (0..3).map { s -> v.board.count { it.suit == s } }
    val paired = v.board.map { it.rank }.toSet().size < v.board.size
    val texture = clamp(
        (if (v.features.wet) 0.45 else 0.0) +
            (if (draw) 0.35 else 0.0) +
            (if (paired) 0.15 else 0.0) +
            (if (maxOf(0, suits.max()) >= 4) 0.35 else 0.0) +
            (if (v.features.overpair && v.features.wet) 0.2 else 0.0),
    )
    val aggressionStreets = raises.filter { it.id != v.id }.map { it.street }.toSet().size
    val lastAction = v.history.lastOrNull()
    val checkRaise = lastAction?.action == Action.RAISE &&
        v.history.any { it.id == lastAction.id && it.street == v.street && it.action == Action.CHECK }
    val route = clamp(
        streetRaises.size * 0.22 +
            maxOf(0, aggressionStreets - 1) * 0.2 +
            (if (checkRaise) 0.25 else 0.0) +
            (if (streetRaises.any { it.id == v.id } && legal.toCall > 0) 0.2 else 0.0),
    )
    val outOfPosition = if (v.street > 0 && v.inPosition != null) !v.inPosition else v.position in OUT_OF_POSITION
    val position = clamp((if (outOfPosition) 0.3 else 0.0) + maxOf(0, v.rivals - 1) * 0.12)
    val callRisk = legal.callAmount.toDouble() / maxOf(1, v.stack)
    val raiseRisk = if (decision.action == Action.RAISE) {
        ((decision.amount ?: 0) - v.bet).toDouble() / maxOf(1, v.stack)
    } else {
        0.0
    }
    val remaining = maxOf(0, v.stack - legal.callAmount)
    // Exclude all-in rivals from remaining-stack planning, while they still count
    // in multiway complexity. A short all-in must not collapse all other SPRs.
    val opponents = v.opponents ?: emptyList()
    val liveStacks = opponents.filter { !it.allin && it.stack > 0 }.map { minOf(remaining, it.stack) }
    val facingStack = opponents.firstOrNull { it.id == lastRaiser && !it.allin && it.stack > 0 }?.stack
    val effective = minOf(remaining, facingStack ?: maxOf(0, liveStacks.maxOrNull() ?: 0))
    val spr = effective.toDouble() / maxOf(50, v.contestable)
    val commitment = clamp(
        maxOf(callRisk, raiseRisk) * 0.7 +
            (if (legal.toCall > 0 && spr < 2) 0.25 else 0.0) +
            (if (v.street > 0 && spr > 6) 0.2 else 0.0) +
            (if (v.stack <= 500 && legal.toCall > 0) 0.15 else 0.0),
    )
    val sizing = if (decision.action == Action.RAISE) {
        clamp(((decision.amount ?: 0) - v.currentBet).toDouble() / maxOf(50, v.pot + legal.callAmount))
    } else {
        0.0
    }
    val routine =
        (decision.action == Action.FOLD && t.reason == "outside-range" && rangeCloseness < 0.15) ||
            (decision.action == Action.CHECK && t.reason == "free-check" && !draw && !v.features.wet)
    val width = t.axes[0] / 100
    val attack = t.axes[1] / 100
    val bluff = t.axes[2] / 100
    val trap = t.axes[4] / 100
    val styleTempo = 1 + (0.5 - attack) * 0.18 + trap * 0.08 + ((v.id % 5) - 2) * 0.04
    val moodStrength = when (t.mode) {
        EmotionMode.OFF -> 0.0
        EmotionMode.LIVELY -> 1.0
        EmotionMode.SUBTLE -> 0.5
    }
    val mood = (MOOD_TEMPO[t.mood.kind] ?: 0) * moodStrength * (0.5 + roll())
    // Acting is sampled for every hand strength and action. Never equate a long
    // pause with a bluff, or a quick action with strength.
    val actingChance = 0.12 + trap * 0.12 + bluff * 0.06 + width * 0.02
    val actingRoll = roll()
    val acting = if (actingRoll < actingChance) Acting.DELIBERATE else if (actingRoll > 0.91) Acting.QUICK else Acting.NEUTRAL
    val actingMs = when (acting) {
        Acting.DELIBERATE -> 400 + roll() * 1400
        Acting.QUICK -> -600.0
        Acting.NEUTRAL -> 0.0
    }
    val base = 1300 + roll() * 1100 + roll() * 700
    val complexity = closeness * 1400 +
        texture * 750 +
        route * 1050 +
        position * 550 +
        commitment * 1050 +
        sizing * 400 +
        (if (v.street >= 2) 350 else if (v.street == 1) 150 else 0)
    val durationMs = jsRound(
        clamp(
            (base + complexity - (if (routine) 450 else 0)) * styleTempo + mood + actingMs,
            BotThinkLimits.MINIMUM.toDouble(),
            BotThinkLimits.MAXIMUM.toDouble(),
        ),
    ).toInt()
    return BotThinking(
        durationMs,
        "context-pacing-v1",
        acting,
        ThinkingFactors(closeness, texture, route, position, commitment, sizing, effective, spr),
    )
}
