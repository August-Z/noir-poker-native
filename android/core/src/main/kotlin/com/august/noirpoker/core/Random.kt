package com.august.noirpoker.core

import kotlin.math.floor

/**
 * The single source of randomness for the engine. [next] returns a value in
 * `[0, 1)`, like JavaScript's `Math.random()`. Every engine function consumes
 * values in exactly the same order and count as the reference.
 */
fun interface RandomSource {
    fun next(): Double
}

/** Production randomness. Not reproducible. */
object SystemRandom : RandomSource {
    override fun next(): Double = kotlin.random.Random.nextDouble()
}

/**
 * Exact port of the reference `seedRandom` (Mulberry32, `src/review/equity.js`).
 *
 * The reference keeps its counter as a JavaScript number that grows without
 * wrapping; every bitwise operator then reduces it modulo 2^32. The counter is
 * kept as a [Double] here so the stream stays identical even after the counter
 * passes 2^53, where JavaScript addition starts rounding.
 */
class SeededRandom(seed: Long) : RandomSource {
    constructor(seed: Int) : this(seed.toLong())

    private var value: Double = (seed and 0xFFFF_FFFFL).toDouble()

    override fun next(): Double {
        value += 0x6d2b79f5.toDouble()
        var x = toInt32(value)
        x = (x xor (x ushr 15)) * (x or 1)
        x = x xor (x + (x xor (x ushr 7)) * (x or 61))
        return ((x xor (x ushr 14)).toLong() and 0xFFFF_FFFFL).toDouble() / 4294967296.0
    }

    private fun toInt32(n: Double): Int {
        val m = n % 4294967296.0
        return m.toLong().toInt()
    }
}

/** JavaScript `Math.round`: halves round toward positive infinity. */
fun jsRound(x: Double): Double {
    if (x.isNaN() || x.isInfinite()) return x
    val r = floor(x)
    return if (x - r >= 0.5) r + 1 else r
}

/** `Math.round(n).toLocaleString('en-US')` for chip amounts: `1800` → `1,800`. */
fun formatChips(n: Number): String {
    val value = jsRound(n.toDouble()).toLong()
    val digits = kotlin.math.abs(value).toString()
    val grouped = StringBuilder()
    for ((i, c) in digits.withIndex()) {
        if (i > 0 && (digits.length - i) % 3 == 0) grouped.append(',')
        grouped.append(c)
    }
    return (if (value < 0) "-" else "") + grouped
}

/**
 * Every error the engine throws. [code] is the stable identifier shared with the
 * fixtures (`engine-scenarios.json` → `errors`); [message] is the English copy.
 */
enum class EngineError(val code: String, val message: String) {
    INVALID_PLAYER_COUNT("invalid-player-count", EngineCopy.tableSize),
    SETTINGS_LOCKED("settings-locked", EngineCopy.settingsNextHand),
    HAND_IN_PROGRESS("hand-in-progress", EngineCopy.handNotFinished),
    REPLAY_UNAVAILABLE("replay-unavailable", EngineCopy.replayUnavailable),
    NOT_YOUR_TURN("not-your-turn", EngineCopy.notYourTurn),
    UNKNOWN_ACTION("unknown-action", EngineCopy.unknownAction),
    CANNOT_CHECK("cannot-check", EngineCopy.mustCall),
    ILLEGAL_RAISE("illegal-raise", EngineCopy.illegalRaise),
    ROUND_NOT_FINISHED("round-not-finished", EngineCopy.roundNotFinished),
    HAND_NOT_SETTLED("hand-not-settled", EngineCopy.settleFirst),
    SHOWDOWN_NEEDS_BOARD("showdown-needs-board", EngineCopy.showdownNeedsBoard),
    ALREADY_SETTLED("already-settled", EngineCopy.alreadySettled),
    NO_ELIGIBLE_PLAYER("no-eligible-player", EngineCopy.noEligiblePlayer),
    POT_MISMATCH("pot-mismatch", EngineCopy.potMismatch),
    INVALID_TRIALS("invalid-trials", EngineCopy.trialsPositive),
    BOT_CANNOT_ACT("bot-cannot-act", EngineCopy.botCannotAct),
    HERO_BOT_EXECUTOR("hero-bot-executor", EngineCopy.heroUsesBotExecutor),
    STALE_BOT_PLAN("stale-bot-plan", EngineCopy.stalePlan),
}

/** Thrown wherever the reference engine throws. */
class PokerException(val error: EngineError) : RuntimeException(error.message) {
    val code: String get() = error.code
}
