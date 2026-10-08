package com.august.noirpoker.core.fixtures

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.BotDecision
import com.august.noirpoker.core.BotDecisionRecord
import com.august.noirpoker.core.BotMood
import com.august.noirpoker.core.BotThinking
import com.august.noirpoker.core.BotTrace
import com.august.noirpoker.core.BotView
import com.august.noirpoker.core.Card
import com.august.noirpoker.core.DecisionSnapshot
import com.august.noirpoker.core.HistoryEntry
import com.august.noirpoker.core.LegalActions
import com.august.noirpoker.core.LogEntry
import com.august.noirpoker.core.MoodKind
import com.august.noirpoker.core.Player
import com.august.noirpoker.core.Pot
import com.august.noirpoker.core.PotSet
import com.august.noirpoker.core.RandomSource
import com.august.noirpoker.core.Refund
import com.august.noirpoker.core.SeededRandom
import com.august.noirpoker.core.Winner
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import java.io.File
import kotlin.test.fail

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

fun fixtureDir(): File = File(System.getProperty("noir.fixtures") ?: "../../fixtures")

fun loadFixture(name: String): JsonObject = Json.parseToJsonElement(File(fixtureDir(), name).readText()).jsonObject

// ---------------------------------------------------------------------------
// Randomness
// ---------------------------------------------------------------------------

/** A [SeededRandom] that counts the values drawn (the generator's `stream.draws`). */
class CountingRandom(seed: Long) : RandomSource {
    private val source = SeededRandom(seed)
    var draws = 0
        private set

    override fun next(): Double {
        draws++
        return source.next()
    }
}

// ---------------------------------------------------------------------------
// JSON access helpers
// ---------------------------------------------------------------------------

val JsonElement.obj: JsonObject get() = jsonObject
val JsonElement.arr: JsonArray get() = jsonArray
val JsonElement.str: String get() = jsonPrimitive.content
val JsonElement.i: Int get() = jsonPrimitive.int
val JsonElement.d: Double get() = jsonPrimitive.double
val JsonElement.b: Boolean get() = jsonPrimitive.boolean
val JsonElement.isNull: Boolean get() = this is JsonNull

fun JsonObject.opt(key: String): JsonElement? = this[key]?.takeUnless { it is JsonNull }

fun cardOf(key: String): Card {
    val (suit, rank) = key.split("-").map { it.toInt() }
    return Card(rank, suit)
}

fun cardsOf(e: JsonElement): MutableList<Card> = e.arr.map { cardOf(it.str) }.toMutableList()

fun actionOf(id: String): Action = Action.fromId(id) ?: error("Unknown action $id")

fun historyOf(e: JsonElement): MutableList<HistoryEntry> = e.arr.map { h ->
    val o = h.obj
    HistoryEntry(
        street = o.getValue("street").i,
        id = o["id"]?.i ?: -1,
        action = actionOf(o.getValue("action").str),
        amount = o["amount"]?.i ?: 0,
        betLabel = o.opt("betLabel")?.str,
    )
}.toMutableList()

fun moodOf(e: JsonElement): BotMood {
    val o = e.obj
    val folds = java.util.TreeMap<Int, Int>()
    for ((k, v) in o.getValue("pressureFolds").obj) folds[k.toInt()] = v.i
    return BotMood(
        kind = moodKindOf(o.getValue("kind").str),
        remaining = o.getValue("remaining").i,
        cooldown = o.getValue("cooldown").i,
        reason = o.getValue("reason").str,
        losses = o.getValue("losses").i,
        wins = o.getValue("wins").i,
        pressureFolds = folds,
        lastPressureRaiser = o.opt("lastPressureRaiser")?.i,
    )
}

fun moodKindOf(id: String): MoodKind = MoodKind.entries.first { it.id == id }

/** Converts arbitrary JSON into plain Kotlin values (maps, lists, strings, numbers, booleans, null). */
fun toPlain(e: JsonElement): Any? = when (e) {
    is JsonNull -> null
    is JsonObject -> LinkedHashMap<String, Any?>().apply { for ((k, v) in e) put(k, toPlain(v)) }
    is JsonArray -> e.map { toPlain(it) }
    is JsonPrimitive -> when {
        e.isString -> e.content
        e.booleanOrNull != null -> e.boolean
        e.intOrNull != null -> e.int
        else -> e.double
    }
}

// ---------------------------------------------------------------------------
// Native → JSON (the generator's plain shapes)
// ---------------------------------------------------------------------------

fun j(v: Int?): JsonElement = if (v == null) JsonNull else JsonPrimitive(v)
fun j(v: Long): JsonElement = JsonPrimitive(v)
fun j(v: Double): JsonElement = JsonPrimitive(v)
fun j(v: Boolean): JsonElement = JsonPrimitive(v)
fun j(v: String?): JsonElement = if (v == null) JsonNull else JsonPrimitive(v)
fun jInts(v: List<Int>): JsonArray = JsonArray(v.map { JsonPrimitive(it) })
fun jDoubles(v: List<Double>): JsonArray = JsonArray(v.map { JsonPrimitive(it) })
fun jStrings(v: List<String>): JsonArray = JsonArray(v.map { JsonPrimitive(it) })
fun jCards(v: List<Card>): JsonArray = jStrings(v.map { it.key })
fun jObj(vararg pairs: Pair<String, JsonElement>): JsonObject = JsonObject(linkedMapOf(*pairs))

fun legalJson(l: LegalActions): JsonObject =
    if (!l.enabled) {
        jObj("enabled" to j(false))
    } else {
        jObj(
            "enabled" to j(true),
            "toCall" to j(l.toCall),
            "callAmount" to j(l.callAmount),
            "canCheck" to j(l.canCheck),
            "raiseReopened" to j(l.raiseReopened),
            "canRaise" to j(l.canRaise),
            "minRaiseTo" to j(l.minRaiseTo),
            "fullRaiseTo" to j(l.fullRaiseTo),
            "maxRaiseTo" to j(l.maxRaiseTo),
            "isShortAllin" to j(l.isShortAllin),
        )
    }

fun moodJson(m: BotMood): JsonObject = jObj(
    "kind" to j(m.kind.id),
    "remaining" to j(m.remaining),
    "cooldown" to j(m.cooldown),
    "reason" to j(m.reason),
    "losses" to j(m.losses),
    "wins" to j(m.wins),
    "pressureFolds" to JsonObject(m.pressureFolds.entries.associate { (k, v) -> k.toString() to j(v) }),
    "lastPressureRaiser" to j(m.lastPressureRaiser),
)

fun statsJson(p: Player): JsonObject = jObj(
    "hands" to j(p.botStats.hands),
    "vpip" to j(p.botStats.vpip),
    "pfr" to j(p.botStats.pfr),
    "postActions" to j(p.botStats.postActions),
    "postRaises" to j(p.botStats.postRaises),
    "postCalls" to j(p.botStats.postCalls),
)

fun playerJson(p: Player): JsonObject = jObj(
    "id" to j(p.id),
    "name" to j(p.name),
    "stack" to j(p.stack),
    "bet" to j(p.bet),
    "total" to j(p.total),
    "folded" to j(p.folded),
    "allin" to j(p.allin),
    "actedTo" to j(p.actedTo),
    "checked" to j(p.checked),
    "action" to j(p.action),
    "lastAction" to (p.lastAction?.let { jObj("text" to j(it.text), "street" to j(it.street), "bet" to j(it.bet)) } ?: JsonNull),
    "hole" to jCards(p.hole),
    "botProfile" to j(p.botProfile),
    "botMood" to moodJson(p.botMood),
    "botStats" to statsJson(p),
    "botHand" to jObj(
        "vpip" to j(p.botHand.vpip),
        "pfr" to j(p.botHand.pfr),
        "pressureRecorded" to j(p.botHand.pressureRecorded),
    ),
)

fun potJson(p: Pot): JsonObject = jObj(
    "index" to j(p.index),
    "label" to j(p.label),
    "amount" to j(p.amount),
    "eligible" to jInts(p.eligible),
    "contributions" to JsonArray(p.contributions.map { jObj("id" to j(it.id), "amount" to j(it.amount)) }),
    "awards" to JsonArray(p.awards.map { jObj("id" to j(it.id), "amount" to j(it.amount), "label" to j(it.label)) }),
)

fun refundsJson(r: List<Refund>): JsonArray = JsonArray(r.map { jObj("id" to j(it.id), "amount" to j(it.amount)) })

fun potSetJson(s: PotSet): JsonObject = jObj("pots" to JsonArray(s.pots.map(::potJson)), "refunds" to refundsJson(s.refunds))

fun winnerJson(w: Winner): JsonObject = jObj(
    "id" to j(w.id),
    "name" to j(w.name),
    "amount" to j(w.amount),
    "profit" to j(w.profit),
    "label" to j(w.label),
)

fun historyJson(h: HistoryEntry): JsonObject {
    val m = linkedMapOf<String, JsonElement>(
        "street" to j(h.street),
        "id" to j(h.id),
        "action" to j(h.action.id),
        "amount" to j(h.amount),
    )
    if (h.betLabel != null) m["betLabel"] = j(h.betLabel)
    return JsonObject(m)
}

fun logJson(l: LogEntry): JsonObject = jObj(
    "text" to j(l.text),
    "player" to j(l.player),
    "type" to j(l.type.id),
    "street" to j(l.street),
)

fun decisionJson(d: DecisionSnapshot): JsonObject = jObj(
    "index" to j(d.index),
    "hand" to j(d.hand),
    "street" to j(d.street),
    "position" to j(d.position),
    "hole" to jCards(d.hole),
    "board" to jCards(d.board),
    "stack" to j(d.stack),
    "bet" to j(d.bet),
    "total" to j(d.total),
    "pot" to j(d.pot),
    "currentBet" to j(d.currentBet),
    "minRaise" to j(d.minRaise),
    "dealer" to j(d.dealer),
    "emotionMode" to j(d.emotionMode.id),
    "legal" to legalJson(d.legal),
    "pending" to jInts(d.pending),
    "action" to j(d.action.id),
    "amount" to j(d.amount),
    "players" to JsonArray(
        d.players.map { o ->
            jObj(
                "id" to j(o.id),
                "name" to j(o.name),
                "position" to j(o.position),
                "stack" to j(o.stack),
                "bet" to j(o.bet),
                "total" to j(o.total),
                "folded" to j(o.folded),
                "allin" to j(o.allin),
                "action" to j(o.action),
                "botProfile" to j(o.botProfile),
                "publicAxes" to (o.publicAxes?.let(::jDoubles) ?: JsonNull),
                "botMoodKind" to j(o.botMoodKind?.id),
                "actedTo" to j(o.actedTo),
                "checked" to j(o.checked),
            )
        },
    ),
    "history" to JsonArray(d.history.map(::historyJson)),
)

/** The complete decision view, as the reference stores it in a trace. */
fun viewJson(v: BotView, full: Boolean = true): JsonObject {
    val m = linkedMapOf<String, JsonElement>("id" to j(v.id))
    if (full) {
        m["hole"] = jCards(v.hole)
        m["board"] = jCards(v.board)
    }
    m["street"] = j(v.street)
    m["position"] = j(v.position)
    m["count"] = j(v.count)
    if (v.inPosition != null) m["inPosition"] = j(v.inPosition)
    m["stack"] = j(v.stack)
    m["bet"] = j(v.bet)
    m["pot"] = j(v.pot)
    m["currentBet"] = j(v.currentBet)
    m["difficulty"] = j(v.difficulty.id)
    m["legal"] = legalJson(v.legal)
    m["rivals"] = j(v.rivals)
    if (v.opponents != null) {
        m["opponents"] = JsonArray(
            v.opponents!!.map { jObj("id" to j(it.id), "stack" to j(it.stack), "bet" to j(it.bet), "allin" to j(it.allin)) },
        )
    }
    m["equity"] = j(v.equity)
    m["equityTrials"] = j(v.equityTrials)
    m["contestable"] = j(v.contestable)
    if (full) m["history"] = JsonArray(v.history.map(::historyJson))
    m["features"] = jObj("wet" to j(v.features.wet), "draw" to j(v.features.draw), "overpair" to j(v.features.overpair))
    m["playsBoard"] = j(v.playsBoard)
    return JsonObject(m)
}

fun thinkingJson(t: BotThinking): JsonObject = jObj(
    "durationMs" to j(t.durationMs),
    "model" to j(t.model),
    "acting" to j(t.acting.id),
    "factors" to jObj(
        "closeness" to j(t.factors.closeness),
        "texture" to j(t.factors.texture),
        "route" to j(t.factors.route),
        "position" to j(t.factors.position),
        "commitment" to j(t.factors.commitment),
        "sizing" to j(t.factors.sizing),
        "effectiveStack" to j(t.factors.effectiveStack),
        "spr" to j(t.factors.spr),
    ),
)

/** The `chooseBotAction` trace; `view` and `thinking` only when present and requested. */
fun traceJson(t: BotTrace, withView: Boolean): JsonObject {
    val m = linkedMapOf<String, JsonElement>(
        "reason" to j(t.reason),
        "profile" to j(t.profile),
        "profileName" to j(t.profileName),
        "mode" to j(t.mode.id),
        "mood" to jObj("kind" to j(t.mood.kind.id), "reason" to j(t.mood.reason)),
        "axes" to jDoubles(t.axes),
        "baseAxes" to jInts(t.baseAxes),
        "equityModel" to j(t.equityModel),
        "trials" to j(t.trials),
        "rawEquity" to j(t.rawEquity),
        "noise" to j(t.noise),
        "equity" to j(t.equity),
        "odds" to j(t.odds),
        "pressure" to j(t.pressure),
        "percentile" to j(t.percentile),
        "range" to j(t.range),
        "openingRange" to j(t.openingRange),
        "raiseRange" to j(t.raiseRange),
        "cheapEntry" to j(t.cheapEntry),
        "cheapRangePassed" to j(t.cheapRangePassed),
        "affordableOpen" to j(t.affordableOpen),
    )
    if (t.affordableRangePassed != null) m["affordableRangePassed"] = j(t.affordableRangePassed!!)
    m["entryContext"] = jObj(
        "limpers" to j(t.entryContext.limpers),
        "openCallers" to j(t.entryContext.openCallers),
        "effectiveBehind" to j(t.entryContext.effectiveBehind),
        "speculative" to j(t.entryContext.speculative),
        "suitedHigh" to j(t.entryContext.suitedHigh),
    )
    m["premium"] = j(t.premium)
    m["admitted"] = j(t.admitted)
    m["callTolerance"] = j(t.callTolerance)
    m["checks"] = JsonArray(
        t.checks.map { jObj("code" to j(it.code), "value" to j(it.value), "threshold" to j(it.threshold), "selected" to j(it.selected)) },
    )
    m["exceptions"] = jStrings(t.exceptions)
    m["sizing"] = t.sizing?.let {
        jObj(
            "fraction" to j(it.fraction),
            "desired" to j(it.desired),
            "actual" to j(it.actual),
            "minimum" to j(it.minimum),
            "maximum" to j(it.maximum),
            "opening" to j(it.opening),
            "executed" to j(it.executed),
        )
    } ?: JsonNull
    m["value"] = j(t.value)
    m["semiBluff"] = j(t.semiBluff)
    m["pureBluff"] = j(t.pureBluff)
    m["draw"] = j(t.draw)
    m["playsBoard"] = j(t.playsBoard)
    if (withView) {
        t.view?.let { m["view"] = viewJson(it) }
        t.thinking?.let {
            m["thinking"] = jObj(
                "durationMs" to j(it.durationMs),
                "model" to j(it.model),
                "acting" to j(it.acting.id),
                "factors" to thinkingJson(BotThinking(it.durationMs, it.model, it.acting, it.factors)).getValue("factors"),
                "expedited" to j(it.expedited),
                "waitedMs" to j(it.waitedMs),
            )
        }
    }
    return JsonObject(m)
}

fun decisionResultJson(d: BotDecision): JsonObject {
    val m = linkedMapOf<String, JsonElement>("action" to j(d.action.id))
    if (d.amount != null) m["amount"] = j(d.amount)
    return JsonObject(m)
}

fun botRecordJson(r: BotDecisionRecord): JsonObject {
    val m = linkedMapOf<String, JsonElement>(
        "id" to j(r.id),
        "name" to j(r.name),
        "hand" to j(r.hand),
        "sequence" to j(r.sequence),
        "action" to j(r.action.id),
    )
    if (r.amount != null) m["amount"] = j(r.amount)
    m["trace"] = traceJson(r.trace, withView = true)
    return JsonObject(m)
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

private fun JsonPrimitive.isNumber(): Boolean = !isString && booleanOrNull == null && content.toDoubleOrNull() != null

/**
 * Structural comparison. Object key order is ignored; numbers compare as exact
 * doubles (so `57` equals `57.0`); strings, booleans and null compare exactly.
 * Returns the first difference as `path: expected … actual …`, or null.
 */
fun jsonDiff(expected: JsonElement?, actual: JsonElement?, path: String = "$"): String? {
    if (expected == null || actual == null) {
        return if (expected == actual) null else "$path: expected ${expected ?: "<absent>"} actual ${actual ?: "<absent>"}"
    }
    when (expected) {
        is JsonObject -> {
            if (actual !is JsonObject) return "$path: expected object $expected actual $actual"
            for (k in expected.keys) jsonDiff(expected[k], actual[k], "$path.$k")?.let { return it }
            for (k in actual.keys) if (k !in expected) return "$path.$k: unexpected key, actual ${actual[k]}"
            return null
        }
        is JsonArray -> {
            if (actual !is JsonArray) return "$path: expected array $expected actual $actual"
            for (i in 0 until minOf(expected.size, actual.size)) jsonDiff(expected[i], actual[i], "$path[$i]")?.let { return it }
            if (expected.size != actual.size) {
                return "$path: expected ${expected.size} items actual ${actual.size}: expected $expected actual $actual"
            }
            return null
        }
        is JsonNull -> return if (actual is JsonNull) null else "$path: expected null actual $actual"
        is JsonPrimitive -> {
            if (actual !is JsonPrimitive || actual is JsonNull) return "$path: expected $expected actual $actual"
            if (expected.isNumber() && actual.isNumber()) {
                val a = expected.content.toDouble()
                val b = actual.content.toDouble()
                return if (a == b) null else "$path: expected ${expected.content} actual ${actual.content}"
            }
            if (expected.isString != actual.isString || expected.content != actual.content) {
                return "$path: expected $expected actual $actual"
            }
            return null
        }
    }
}

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

/** Collects per-case outcomes for one fixture file and fails with every case name that differs. */
class FixtureReport(private val file: String) {
    private var passed = 0
    private val failures = mutableListOf<String>()

    fun case(name: String, body: () -> String?) {
        val problem = try {
            body()
        } catch (e: Throwable) {
            "threw ${e::class.simpleName}: ${e.message}\n" + e.stackTrace.take(6).joinToString("\n") { "    at $it" }
        }
        if (problem == null) passed++ else failures.add("[$name] $problem")
    }

    fun finish() {
        val total = passed + failures.size
        val summary = "$file: $passed/$total cases passed, ${failures.size} failed"
        println(summary)
        val out = File("build/fixture-report").apply { mkdirs() }
        File(out, "$file.txt").writeText(summary + "\n" + failures.joinToString("\n") + "\n")
        if (total == 0) fail("$file: no cases")
        if (failures.isNotEmpty()) fail(summary + "\n" + failures.take(15).joinToString("\n"))
    }
}
