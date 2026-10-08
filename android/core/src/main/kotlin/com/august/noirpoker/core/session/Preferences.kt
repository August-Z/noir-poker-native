package com.august.noirpoker.core.session

import com.august.noirpoker.core.BotSettings
import com.august.noirpoker.core.Difficulty
import com.august.noirpoker.core.MAX_PLAYERS
import com.august.noirpoker.core.MIN_PLAYERS
import com.august.noirpoker.core.defaultBotSettings
import com.august.noirpoker.core.sanitizeBotSettings

/**
 * String key-value storage (SharedPreferences / DataStore on Android,
 * UserDefaults on iOS). Either call may throw; the store treats a failure as
 * "unavailable" and falls back to defaults, like the reference's `localStorage`
 * wrappers.
 */
interface KeyValueStorage {
    fun getString(key: String): String?
    fun putString(key: String, value: String)
}

/** A plain in-memory storage, for tests and previews. */
class InMemoryStorage(initial: Map<String, String> = emptyMap()) : KeyValueStorage {
    val values: MutableMap<String, String> = LinkedHashMap(initial)
    override fun getString(key: String): String? = values[key]
    override fun putString(key: String, value: String) {
        values[key] = value
    }
}

/** Seat count and difficulty, persisted as `{"playerCount":6,"difficulty":"normal"}`. */
data class TablePreferences(val playerCount: Int = DEFAULT_PLAYER_COUNT, val difficulty: Difficulty = Difficulty.NORMAL) {
    companion object {
        const val DEFAULT_PLAYER_COUNT = 6

        /**
         * The reference `tablePreferences(value)`: each field is validated on its
         * own. `playerCount` must be an integral JSON number 5–9 (`6.0` counts,
         * `"9"` and `6.5` do not); `difficulty` must be `easy`, `normal` or `hard`.
         */
        fun sanitize(value: Any?): TablePreferences {
            val map = value as? Map<*, *>
            val rawCount = map?.get("playerCount")
            val count = (rawCount as? Double)?.takeIf { it == Math.floor(it) && !it.isInfinite() && it in MIN_PLAYERS.toDouble()..MAX_PLAYERS.toDouble() }
                ?.toInt()
                ?: (rawCount as? Int)?.takeIf { it in MIN_PLAYERS..MAX_PLAYERS }
                ?: DEFAULT_PLAYER_COUNT
            val difficulty = (map?.get("difficulty") as? String)?.let { Difficulty.fromId(it) } ?: Difficulty.NORMAL
            return TablePreferences(count, difficulty)
        }
    }
}

/**
 * The reference's persisted options (`preferences.js`, `opponents-controller.js`,
 * and the sound and hints toggles). Only these four keys are ever written;
 * cards, stacks, history and statistics are never persisted.
 */
class PreferencesStore(private val storage: KeyValueStorage) {
    companion object {
        const val TABLE_KEY = "noir-table-v1"
        const val OPPONENTS_KEY = "noir-opponents-v1"
        const val SOUND_KEY = "noir-sound"
        const val HINTS_KEY = "noir-hints"
    }

    private fun read(key: String): String? = try {
        storage.getString(key)
    } catch (_: Exception) {
        null
    }

    private fun write(key: String, value: String) {
        try {
            storage.putString(key, value)
        } catch (_: Exception) {
            // Storage can be unavailable; the current table keeps the selection.
        }
    }

    /** `JSON.parse(getItem(key))`; a missing value parses as `null`, invalid JSON throws. */
    private fun parse(key: String): Any? = MiniJson.parse(read(key) ?: "null")

    fun loadTable(): TablePreferences = try {
        TablePreferences.sanitize(parse(TABLE_KEY))
    } catch (_: Exception) {
        TablePreferences()
    }

    /** Writes only `playerCount` and `difficulty`, sanitized. */
    fun saveTable(value: TablePreferences) {
        val clean = TablePreferences.sanitize(mapOf("playerCount" to value.playerCount, "difficulty" to value.difficulty.id))
        write(TABLE_KEY, MiniJson.stringify(linkedMapOf("playerCount" to clean.playerCount, "difficulty" to clean.difficulty.id)))
    }

    fun loadBotSettings(): BotSettings = try {
        sanitizeBotSettings(parse(OPPONENTS_KEY))
    } catch (_: Exception) {
        defaultBotSettings()
    }

    fun saveBotSettings(settings: BotSettings) {
        val clean = sanitizeBotSettings(settings)
        val json = linkedMapOf<String, Any?>(
            "emotionMode" to clean.emotionMode.id,
            "assignments" to (1..8).associate { it.toString() to clean.assignments.getValue(it) },
        )
        write(OPPONENTS_KEY, MiniJson.stringify(json))
    }

    /** Sound is on only when the stored value is exactly `true`. */
    fun loadSound(): Boolean = read(SOUND_KEY) == "true"

    fun saveSound(on: Boolean) = write(SOUND_KEY, on.toString())

    /** Hints are off only when the stored value is exactly `false`. */
    fun loadHints(): Boolean = read(HINTS_KEY) != "false"

    fun saveHints(on: Boolean) = write(HINTS_KEY, on.toString())
}

/**
 * A minimal JSON reader and writer for the persisted preferences, so the domain
 * module needs no serialization dependency. Numbers parse as [Double], objects as
 * insertion-ordered maps with string keys, arrays as lists.
 */
object MiniJson {
    class ParseException(message: String) : IllegalArgumentException(message)

    fun parse(text: String): Any? {
        val p = Parser(text)
        p.ws()
        val v = p.value()
        p.ws()
        if (!p.end()) throw ParseException("Unexpected trailing input")
        return v
    }

    fun stringify(value: Any?): String = buildString { write(this, value) }

    private fun write(out: StringBuilder, value: Any?) {
        when (value) {
            null -> out.append("null")
            is Boolean -> out.append(value.toString())
            is Int, is Long -> out.append(value.toString())
            is Double -> if (value == Math.floor(value) && !value.isInfinite() && kotlin.math.abs(value) < 1e15) {
                out.append(value.toLong().toString())
            } else {
                out.append(value.toString())
            }
            is String -> quote(out, value)
            is Map<*, *> -> {
                out.append('{')
                var first = true
                for ((k, v) in value) {
                    if (!first) out.append(',')
                    first = false
                    quote(out, k.toString())
                    out.append(':')
                    write(out, v)
                }
                out.append('}')
            }
            is Iterable<*> -> {
                out.append('[')
                var first = true
                for (v in value) {
                    if (!first) out.append(',')
                    first = false
                    write(out, v)
                }
                out.append(']')
            }
            else -> quote(out, value.toString())
        }
    }

    private fun quote(out: StringBuilder, s: String) {
        out.append('"')
        for (c in s) {
            when (c) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                '\b' -> out.append("\\b")
                '\u000C' -> out.append("\\f")
                else -> if (c < ' ') out.append("\\u%04x".format(c.code)) else out.append(c)
            }
        }
        out.append('"')
    }

    private class Parser(val s: String) {
        var i = 0
        fun end() = i >= s.length
        fun ws() {
            while (i < s.length && s[i] in " \t\n\r") i++
        }

        fun fail(what: String): Nothing = throw ParseException("$what at $i")

        fun value(): Any? {
            if (end()) fail("Unexpected end")
            return when (val c = s[i]) {
                '{' -> obj()
                '[' -> arr()
                '"' -> str()
                't' -> literal("true", true)
                'f' -> literal("false", false)
                'n' -> literal("null", null)
                else -> if (c == '-' || c in '0'..'9') num() else fail("Unexpected '$c'")
            }
        }

        fun literal(word: String, v: Any?): Any? {
            if (!s.startsWith(word, i)) fail("Invalid literal")
            i += word.length
            return v
        }

        fun obj(): Map<String, Any?> {
            val m = LinkedHashMap<String, Any?>()
            i++
            ws()
            if (!end() && s[i] == '}') {
                i++
                return m
            }
            while (true) {
                ws()
                if (end() || s[i] != '"') fail("Expected key")
                val k = str()
                ws()
                if (end() || s[i] != ':') fail("Expected ':'")
                i++
                ws()
                m[k] = value()
                ws()
                if (end()) fail("Unterminated object")
                if (s[i] == ',') {
                    i++
                    continue
                }
                if (s[i] == '}') {
                    i++
                    return m
                }
                fail("Expected ',' or '}'")
            }
        }

        fun arr(): List<Any?> {
            val l = ArrayList<Any?>()
            i++
            ws()
            if (!end() && s[i] == ']') {
                i++
                return l
            }
            while (true) {
                ws()
                l.add(value())
                ws()
                if (end()) fail("Unterminated array")
                if (s[i] == ',') {
                    i++
                    continue
                }
                if (s[i] == ']') {
                    i++
                    return l
                }
                fail("Expected ',' or ']'")
            }
        }

        fun str(): String {
            val sb = StringBuilder()
            i++
            while (true) {
                if (end()) fail("Unterminated string")
                val c = s[i++]
                when {
                    c == '"' -> return sb.toString()
                    c == '\\' -> {
                        if (end()) fail("Bad escape")
                        when (val e = s[i++]) {
                            '"' -> sb.append('"')
                            '\\' -> sb.append('\\')
                            '/' -> sb.append('/')
                            'b' -> sb.append('\b')
                            'f' -> sb.append('\u000C')
                            'n' -> sb.append('\n')
                            'r' -> sb.append('\r')
                            't' -> sb.append('\t')
                            'u' -> {
                                if (i + 4 > s.length) fail("Bad unicode escape")
                                val hex = s.substring(i, i + 4)
                                sb.append(hex.toIntOrNull(16)?.toChar() ?: fail("Bad unicode escape"))
                                i += 4
                            }
                            else -> fail("Bad escape '$e'")
                        }
                    }
                    c < ' ' -> fail("Control character in string")
                    else -> sb.append(c)
                }
            }
        }

        fun num(): Double {
            val start = i
            if (s[i] == '-') i++
            if (end()) fail("Bad number")
            if (s[i] == '0') {
                i++
            } else if (s[i] in '1'..'9') {
                while (!end() && s[i] in '0'..'9') i++
            } else {
                fail("Bad number")
            }
            if (!end() && s[i] == '.') {
                i++
                if (end() || s[i] !in '0'..'9') fail("Bad fraction")
                while (!end() && s[i] in '0'..'9') i++
            }
            if (!end() && (s[i] == 'e' || s[i] == 'E')) {
                i++
                if (!end() && (s[i] == '+' || s[i] == '-')) i++
                if (end() || s[i] !in '0'..'9') fail("Bad exponent")
                while (!end() && s[i] in '0'..'9') i++
            }
            return s.substring(start, i).toDouble()
        }
    }
}
