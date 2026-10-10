package com.august.noirpoker.core.review

import com.august.noirpoker.core.formatChips
import com.august.noirpoker.core.jsRound
import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode

// Number formatting that reproduces the reference's JavaScript output exactly.
// Every formatter uses fixed en-US conventions, never the device locale.

/**
 * `Math.round(v).toLocaleString('en-US')`. Negative zero is normalized to `"0"` on both
 * platforms; `NaN` prints `"NaN"` like JavaScript.
 */
internal fun number(v: Number): String = if (v.toDouble().isNaN()) "NaN" else formatChips(v)

/** `Math.round(v)` as an integer string without grouping (big-blind counts). */
internal fun roundedInt(v: Double): String = if (v.isNaN()) "NaN" else jsRound(v).toLong().toString()

/** Analysis `percent`: `Math.round(v * 100) + '%'`. */
internal fun percent(v: Double): String = (if (v.isNaN()) "NaN" else jsRound(v * 100).toLong().toString()) + "%"

/**
 * JavaScript `Number.prototype.toFixed(digits)`: the exact binary value rounded half away
 * from zero, keeping the minus sign of negative values that round to zero (`"-0.0"`).
 * Magnitudes of 1e21 and above print like `String(x)`, as in JavaScript.
 */
fun jsToFixed(x: Double, digits: Int): String {
    if (x.isNaN()) return "NaN"
    if (x.isInfinite()) return if (x > 0) "Infinity" else "-Infinity"
    if (kotlin.math.abs(x) >= 1e21) return jsNumber(x)
    val text = BigDecimal(x).setScale(digits, RoundingMode.HALF_UP).abs().toPlainString()
    return if (x < 0) "-$text" else text
}

/** Opponent `pct`: `(v * 100).toFixed(1) + '%'`. */
internal fun pct(v: Double): String = jsToFixed(v * 100, 1) + "%"

/** `(x >= 0 ? '+' : '') + pct(x)`. */
internal fun signedPct(v: Double): String = (if (v >= 0) "+" else "") + pct(v)

/**
 * JavaScript `String(x)` (ECMAScript `Number::toString`) for the values the review
 * interpolates raw (style axes): the shortest round-trip digits, printed in plain notation
 * for 1e-7 < |x| < 1e21 and in exponent notation (`1e-7`, `1.5e+21`) otherwise. The digits
 * are computed with `BigDecimal`, not `Double.toString`, whose output differs between JVMs.
 */
fun jsNumber(x: Double): String {
    if (x.isNaN()) return "NaN"
    if (x.isInfinite()) return if (x > 0) "Infinity" else "-Infinity"
    if (x == 0.0) return "0"
    val exact = BigDecimal(kotlin.math.abs(x))
    var shortest = exact
    for (precision in 1..17) {
        val candidate = exact.round(MathContext(precision, RoundingMode.HALF_EVEN))
        if (candidate.toDouble() == kotlin.math.abs(x)) {
            shortest = candidate
            break
        }
    }
    val stripped = shortest.stripTrailingZeros()
    val digits = stripped.unscaledValue().toString()
    val k = digits.length
    // x = 0.digits × 10^n
    val n = k - stripped.scale()
    val body = when {
        n in k..21 -> digits + "0".repeat(n - k)
        n in 1..21 -> digits.substring(0, n) + "." + digits.substring(n)
        n in -5..0 -> "0." + "0".repeat(-n) + digits
        else -> {
            val e = n - 1
            val mantissa = if (k == 1) digits else digits[0] + "." + digits.substring(1)
            mantissa + "e" + (if (e < 0) "-" else "+") + kotlin.math.abs(e)
        }
    }
    return if (x < 0) "-$body" else body
}

/** Upper-cases the first character, for a catalog phrase that starts a sentence. */
internal fun cap(s: String): String = if (s.isEmpty()) s else s[0].uppercaseChar() + s.substring(1)

/** Lower-cases the first character, for a catalog phrase used mid-sentence. */
internal fun lower(s: String): String = if (s.isEmpty()) s else s[0].lowercaseChar() + s.substring(1)

/**
 * English port of the reference's direct sentence concatenation: non-empty fragments are
 * trimmed and joined with a single space.
 */
internal fun sentences(vararg parts: String?): String =
    parts.filterNotNull().map { it.trim() }.filter { it.isNotEmpty() }.joinToString(" ")

/** `"1 player"` / `"2 players"`. */
internal fun count(n: Int, one: String, many: String): String = "$n ${if (n == 1) one else many}"
