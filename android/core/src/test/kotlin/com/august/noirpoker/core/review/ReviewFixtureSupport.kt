package com.august.noirpoker.core.review

import com.august.noirpoker.core.Acting
import com.august.noirpoker.core.BoardFeatures
import com.august.noirpoker.core.BotDecisionRecord
import com.august.noirpoker.core.BotOpponent
import com.august.noirpoker.core.BotSizing
import com.august.noirpoker.core.BotThinkingRecord
import com.august.noirpoker.core.BotTrace
import com.august.noirpoker.core.BotView
import com.august.noirpoker.core.Difficulty
import com.august.noirpoker.core.EmotionMode
import com.august.noirpoker.core.EntryContext
import com.august.noirpoker.core.HandEvaluation
import com.august.noirpoker.core.LegalActions
import com.august.noirpoker.core.RollCheck
import com.august.noirpoker.core.ThinkingFactors
import com.august.noirpoker.core.TraceMood
import com.august.noirpoker.core.fixtures.actionOf
import com.august.noirpoker.core.fixtures.arr
import com.august.noirpoker.core.fixtures.b
import com.august.noirpoker.core.fixtures.cardsOf
import com.august.noirpoker.core.fixtures.d
import com.august.noirpoker.core.fixtures.historyJson
import com.august.noirpoker.core.fixtures.historyOf
import com.august.noirpoker.core.fixtures.i
import com.august.noirpoker.core.fixtures.j
import com.august.noirpoker.core.fixtures.jCards
import com.august.noirpoker.core.fixtures.jInts
import com.august.noirpoker.core.fixtures.jObj
import com.august.noirpoker.core.fixtures.jStrings
import com.august.noirpoker.core.fixtures.moodKindOf
import com.august.noirpoker.core.fixtures.obj
import com.august.noirpoker.core.fixtures.opt
import com.august.noirpoker.core.fixtures.potJson
import com.august.noirpoker.core.fixtures.str
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// Fixture <-> native conversion for review-decisions.json and review-hands.json.
// Parsing keeps absent keys absent where the reference distinguishes them (partial
// hand-built snapshots); serialization reproduces the reference output shapes.

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/** A snapshot `legal`; hand-built snapshots may omit `fullRaiseTo`, `raiseReopened`, `isShortAllin`. */
fun reviewLegalOf(e: JsonElement): LegalActions {
    val o = e.obj
    return LegalActions(
        enabled = o.getValue("enabled").b,
        toCall = o["toCall"]?.i ?: 0,
        callAmount = o["callAmount"]?.i ?: 0,
        canCheck = o["canCheck"]?.b ?: false,
        raiseReopened = o["raiseReopened"]?.b ?: false,
        canRaise = o["canRaise"]?.b ?: false,
        minRaiseTo = o["minRaiseTo"]?.i ?: 0,
        fullRaiseTo = o["fullRaiseTo"]?.i ?: 0,
        maxRaiseTo = o["maxRaiseTo"]?.i ?: 0,
        isShortAllin = o["isShortAllin"]?.b ?: false,
    )
}

fun reviewDecisionOf(e: JsonElement): ReviewDecision {
    val o = e.obj
    val legal = o.getValue("legal").obj
    return ReviewDecision(
        index = o.getValue("index").i,
        hand = o.getValue("hand").i,
        street = o.getValue("street").i,
        position = o.getValue("position").str,
        hole = cardsOf(o.getValue("hole")),
        board = cardsOf(o.getValue("board")),
        stack = o.getValue("stack").i,
        bet = o.getValue("bet").i,
        total = o.getValue("total").i,
        pot = o.getValue("pot").i,
        currentBet = o.getValue("currentBet").i,
        minRaise = o.getValue("minRaise").i,
        dealer = o.opt("dealer")?.i,
        emotionMode = o.opt("emotionMode")?.let { EmotionMode.fromId(it.str) },
        legal = reviewLegalOf(legal),
        pending = o.getValue("pending").arr.map { it.i },
        action = actionOf(o.getValue("action").str),
        amount = o.getValue("amount").i,
        players = o.getValue("players").arr.map { pe ->
            val p = pe.obj
            ReviewSeat(
                id = p.getValue("id").i,
                name = p.getValue("name").str,
                position = p.getValue("position").str,
                stack = p.getValue("stack").i,
                bet = p.getValue("bet").i,
                total = p.getValue("total").i,
                folded = p.getValue("folded").b,
                allin = p.getValue("allin").b,
                action = p.opt("action")?.str ?: "",
                publicAxes = p.opt("publicAxes")?.arr?.map { it.d },
                state = if ("actedTo" in p) {
                    SeatState(
                        actedTo = p.opt("actedTo")?.i,
                        checked = p.getValue("checked").b,
                        botProfile = p.opt("botProfile")?.str,
                        botMoodKind = p.opt("botMoodKind")?.let { moodKindOf(it.str) },
                    )
                } else {
                    null
                },
            )
        },
        history = historyOf(o.getValue("history")),
        labelFullRaiseTo = legal.opt("fullRaiseTo")?.i,
    )
}

fun candidateOf(e: JsonElement?): CandidateAction? {
    if (e == null || e is JsonNull) return null
    val o = e.obj
    return CandidateAction(actionOf(o.getValue("action").str), o.getValue("amount").i)
}

private fun viewOf(e: JsonElement): BotView {
    val o = e.obj
    val f = o.opt("features")?.obj
    return BotView(
        id = o.getValue("id").i,
        hole = cardsOf(o.getValue("hole")),
        board = cardsOf(o.getValue("board")),
        street = o.getValue("street").i,
        position = o.getValue("position").str,
        count = o.getValue("count").i,
        inPosition = o.opt("inPosition")?.b,
        stack = o.getValue("stack").i,
        bet = o.getValue("bet").i,
        pot = o.getValue("pot").i,
        currentBet = o.getValue("currentBet").i,
        difficulty = Difficulty.fromId(o.getValue("difficulty").str)!!,
        legal = reviewLegalOf(o.getValue("legal")),
        rivals = o.getValue("rivals").i,
        opponents = o.opt("opponents")?.arr?.map {
            val p = it.obj
            BotOpponent(p.getValue("id").i, p.getValue("stack").i, p.getValue("bet").i, p.getValue("allin").b)
        },
        equity = o.getValue("equity").d,
        equityTrials = o["equityTrials"]?.i ?: 0,
        contestable = o.getValue("contestable").i,
        history = historyOf(o.getValue("history")),
        features = BoardFeatures(
            wet = f?.get("wet")?.b ?: false,
            draw = f?.get("draw")?.b ?: false,
            overpair = f?.get("overpair")?.b ?: false,
        ),
        playsBoard = o["playsBoard"]?.b ?: false,
    )
}

fun traceOf(e: JsonElement): BotTrace {
    val o = e.obj
    val ec = o.getValue("entryContext").obj
    return BotTrace(
        reason = o.getValue("reason").str,
        profile = o.getValue("profile").str,
        profileName = o.getValue("profileName").str,
        mode = EmotionMode.fromId(o.getValue("mode").str)!!,
        mood = o.getValue("mood").obj.let { TraceMood(moodKindOf(it.getValue("kind").str), it.getValue("reason").str) },
        axes = o.getValue("axes").arr.map { it.d },
        baseAxes = o.getValue("baseAxes").arr.map { it.i },
        equityModel = o.getValue("equityModel").str,
        trials = o.getValue("trials").i,
        rawEquity = o.getValue("rawEquity").d,
        noise = o.getValue("noise").d,
        equity = o.getValue("equity").d,
        odds = o.getValue("odds").d,
        pressure = o.getValue("pressure").d,
        percentile = o.getValue("percentile").d,
        range = o.getValue("range").d,
        openingRange = o.getValue("openingRange").d,
        raiseRange = o.getValue("raiseRange").d,
        cheapEntry = o.getValue("cheapEntry").b,
        cheapRangePassed = o.getValue("cheapRangePassed").b,
        affordableOpen = o.getValue("affordableOpen").b,
        affordableRangePassed = o.opt("affordableRangePassed")?.b,
        entryContext = EntryContext(
            limpers = ec.getValue("limpers").i,
            openCallers = ec.getValue("openCallers").i,
            effectiveBehind = ec.getValue("effectiveBehind").i,
            speculative = ec.getValue("speculative").b,
            suitedHigh = ec.getValue("suitedHigh").b,
        ),
        premium = o.getValue("premium").b,
        admitted = o.getValue("admitted").b,
        callTolerance = o.getValue("callTolerance").d,
        checks = o.getValue("checks").arr.map {
            val c = it.obj
            RollCheck(c.getValue("code").str, c.getValue("value").d, c.getValue("threshold").d, c.getValue("selected").b)
        },
        exceptions = o.getValue("exceptions").arr.map { it.str },
        sizing = o.opt("sizing")?.obj?.let {
            BotSizing(
                fraction = it.getValue("fraction").d,
                desired = it.getValue("desired").i,
                actual = it.getValue("actual").i,
                minimum = it.getValue("minimum").i,
                maximum = it.getValue("maximum").i,
                opening = it.getValue("opening").b,
                executed = it.getValue("executed").b,
            )
        },
        value = o.getValue("value").b,
        semiBluff = o.getValue("semiBluff").b,
        pureBluff = o.getValue("pureBluff").b,
        draw = o.getValue("draw").b,
        playsBoard = o.getValue("playsBoard").b,
        view = o.opt("view")?.let(::viewOf),
        thinking = o.opt("thinking")?.obj?.let { t ->
            val f = t.getValue("factors").obj
            BotThinkingRecord(
                durationMs = t.getValue("durationMs").i,
                model = t.getValue("model").str,
                acting = Acting.entries.first { it.id == t.getValue("acting").str },
                factors = ThinkingFactors(
                    closeness = f.getValue("closeness").d,
                    texture = f.getValue("texture").d,
                    route = f.getValue("route").d,
                    position = f.getValue("position").d,
                    commitment = f.getValue("commitment").d,
                    sizing = f.getValue("sizing").d,
                    effectiveStack = f.getValue("effectiveStack").i,
                    spr = f.getValue("spr").d,
                ),
                expedited = t.getValue("expedited").b,
                waitedMs = t.getValue("waitedMs").d.toLong(),
            )
        },
    )
}

fun botRecordOf(e: JsonElement): BotDecisionRecord {
    val o = e.obj
    return BotDecisionRecord(
        id = o.getValue("id").i,
        name = o.getValue("name").str,
        hand = o["hand"]?.i ?: 0,
        sequence = o["sequence"]?.i ?: 0,
        action = actionOf(o.getValue("action").str),
        amount = o.opt("amount")?.i,
        trace = traceOf(o.getValue("trace")),
    )
}

/**
 * `createReviewInput` output. The reference review tests build partial inputs (no `hole`,
 * a partial `outcome`); missing display fields default to empty values, since the
 * outcome is never passed to the analysis.
 */
fun reviewInputOf(e: JsonElement): ReviewInput {
    val o = e.obj
    val out = o.getValue("outcome").obj
    return ReviewInput(
        hand = o.getValue("hand").i,
        hole = o.opt("hole")?.let(::cardsOf) ?: emptyList(),
        decisions = o.getValue("decisions").arr.map(::reviewDecisionOf),
        opponents = o.opt("opponents")?.arr?.map(::botRecordOf) ?: emptyList(),
        outcome = ReviewOutcome(
            profit = out.getValue("profit").i,
            paid = out.opt("paid")?.i ?: 0,
            returned = out.opt("returned")?.i ?: 0,
            folded = out.getValue("folded").b,
            wonPot = out.opt("wonPot")?.b ?: false,
            board = out.opt("board")?.let(::cardsOf) ?: emptyList(),
            pots = out.opt("pots")?.arr?.map { pe ->
                val p = pe.obj
                OutcomePot(
                    label = p.getValue("label").str,
                    amount = p.getValue("amount").i,
                    eligible = p.getValue("eligible").arr.map { it.str },
                    awards = p.getValue("awards").arr.map {
                        val a = it.obj
                        OutcomeAward(a.getValue("name").str, a.getValue("amount").i, a.getValue("label").str)
                    },
                )
            } ?: emptyList(),
            result = out.opt("result")?.str ?: "",
        ),
    )
}

/**
 * True when a snapshot carries a fractional chip amount. Two reference unit tests build
 * `total = pot / 2 = 37.5`; native chip amounts are integers, so outputs that read the
 * totals (call price, the snapshot seed and everything sampled from it) cannot be reproduced.
 */
fun hasFractionalChips(e: JsonElement): Boolean {
    val o = e.obj
    fun frac(x: JsonElement?) = x != null && x !is JsonNull && x.d != Math.floor(x.d)
    return listOf("stack", "bet", "total", "pot", "currentBet").any { frac(o[it]) } ||
        o.getValue("players").arr.any { p -> listOf("stack", "bet", "total").any { frac(p.obj[it]) } }
}

/** Parses [e], truncating fractional chip amounts (see [hasFractionalChips]). */
fun lenientDecisionOf(e: JsonElement): ReviewDecision {
    fun fix(x: JsonElement): JsonElement = when (x) {
        is JsonObject -> JsonObject(x.mapValues { (k, v) -> if (k in CHIP_KEYS && v is JsonPrimitive && !v.isString) JsonPrimitive(Math.floor(v.d).toInt()) else fix(v) })
        is JsonArray -> JsonArray(x.map(::fix))
        else -> x
    }
    return reviewDecisionOf(fix(e))
}

private val CHIP_KEYS = setOf("stack", "bet", "total", "pot", "currentBet")

// ---------------------------------------------------------------------------
// Serialization (reference output shapes)
// ---------------------------------------------------------------------------

fun drawJson(d: DrawInfo): JsonObject = jObj(
    "flush" to j(d.flush),
    "straight" to j(d.straight),
    "flushOuts" to j(d.flushOuts),
    "straightOuts" to j(d.straightOuts),
    "outs" to j(d.outs),
    "nextChance" to j(d.nextChance),
)

fun textureJson(t: BoardTexture): JsonObject = jObj(
    "paired" to j(t.paired),
    "trips" to j(t.trips),
    "maxSuit" to j(t.maxSuit),
    "connected" to j(t.connected),
    "wet" to j(t.wet),
    "label" to j(t.label),
)

fun madeJson(m: HandEvaluation): JsonObject = jObj("score" to jInts(m.score), "label" to j(m.label), "cards" to jCards(m.cards))

fun contextJson(c: DecisionContext): JsonObject {
    val m = linkedMapOf<String, JsonElement>(
        "made" to madeJson(c.made),
        "texture" to textureJson(c.texture),
        "draw" to drawJson(c.draw),
        "opponents" to j(c.opponents),
        "handClass" to j(c.handClass.id),
        "handLabel" to j(c.handLabel.start),
        "inPosition" to j(c.inPosition),
        "pendingOthers" to j(c.pendingOthers),
        "effective" to j(c.effective),
        "spr" to j(c.spr),
        "extra" to j(c.extra),
        "betRatio" to j(c.betRatio),
        "preflopRaises" to j(c.preflopRaises),
    )
    c.facingRaise?.let { m["facingRaise"] = historyJson(it) }
    m["pastCalls"] = j(c.pastCalls)
    m["pastCallActions"] = j(c.pastCallActions)
    m["nutFlushBlocker"] = j(c.nutFlushBlocker)
    m["missedDraw"] = j(c.missedDraw)
    m["tier"] = j(c.tier)
    return JsonObject(m)
}

fun preflopJson(p: PreflopContext): JsonObject {
    val m = linkedMapOf<String, JsonElement>(
        "raises" to j(p.raises),
        "limpers" to j(p.limpers),
        "callersAfterOpen" to j(p.callersAfterOpen),
        "late" to j(p.late),
        "unopened" to j(p.unopened),
        "ace" to j(p.ace),
        "kicker" to j(p.kicker),
        "suited" to j(p.suited),
        "weakAce" to j(p.weakAce),
        "ownOpen" to j(p.ownOpen),
    )
    p.lastRaiser?.let { m["lastRaiser"] = j(it) }
    m["openTo"] = j(p.openTo)
    m["ratio"] = j(p.ratio)
    m["openingCandidate"] = j(p.openingCandidate)
    m["label"] = j(p.label)
    return JsonObject(m)
}

fun callPriceJson(p: CallPrice): JsonObject = jObj(
    "pots" to JsonArray(p.pots.map(::potJson)),
    "contestable" to j(p.contestable),
    "cost" to j(p.cost),
    "refundBefore" to j(p.refundBefore),
    "refundAfter" to j(p.refundAfter),
    "required" to j(p.required),
    "closing" to j(p.closing),
)

fun sampledJson(v: SampledValue): JsonObject {
    val m = linkedMapOf<String, JsonElement>("equity" to j(v.equity), "margin" to j(v.margin), "ev" to j(v.ev))
    v.method?.let { m["method"] = j(it.id) }
    v.samples?.let { m["samples"] = j(it) }
    return JsonObject(m)
}

fun candidateJson(a: CandidateAction): JsonObject = jObj("action" to j(a.action.id), "amount" to j(a.amount))

fun routeJson(r: Route): JsonObject {
    val m = linkedMapOf<String, JsonElement>("action" to j(r.action.id), "amount" to j(r.amount), "label" to j(r.label))
    r.summary?.let { m["summary"] = j(it) }
    m["condition"] = j(r.condition)
    m["tradeoff"] = j(r.tradeoff)
    return JsonObject(m)
}

fun routesJson(r: Routes): JsonObject = jObj(
    "primary" to routeJson(r.primary),
    "secondary" to (r.secondary?.let(::routeJson) ?: JsonNull),
)

fun simulationJson(r: CounterfactualResult): JsonObject = jObj(
    "rows" to JsonArray(
        r.rows.map { row ->
            jObj(
                "action" to candidateJson(row.action),
                "scenarios" to JsonArray(
                    row.scenarios.map {
                        jObj(
                            "name" to j(it.name),
                            "ev" to j(it.ev),
                            "margin" to j(it.margin),
                            "immediateFoldWin" to j(it.immediateFoldWin),
                        )
                    },
                ),
            )
        },
    ),
    "trials" to j(r.trials),
    "policyTrials" to j(r.policyTrials),
    "best" to candidateJson(r.best),
    "stable" to j(r.stable),
    "method" to j(r.method),
    "note" to j(r.note),
)

fun metricsJson(m: ReviewMetrics): JsonObject = jObj(
    "required" to j(m.required),
    "equityLow" to j(m.equityLow),
    "equityHigh" to j(m.equityHigh),
    "randomEquity" to j(m.randomEquity),
    "weightedEquity" to j(m.weightedEquity),
    "uncertainty" to j(m.uncertainty),
    "callCost" to j(m.callCost),
    "contestable" to j(m.contestable),
    "closing" to j(m.closing),
    "sidePots" to j(m.sidePots),
    "trials" to j(m.trials),
    "method" to j(m.method.id),
    "randomEV" to j(m.randomEV),
    "weightedEV" to j(m.weightedEV),
)

fun analysisJson(a: DecisionAnalysis): JsonObject = jObj(
    "index" to j(a.index),
    "status" to j(a.status.id),
    "code" to j(a.code),
    "title" to j(a.title),
    "reason" to j(a.reason),
    "lesson" to j(a.lesson),
    "plan" to j(a.plan),
    "confidence" to j(a.confidence),
    "evidence" to jStrings(a.evidence),
    "alternative" to candidateJson(a.alternative),
    "alternativeLabel" to j(a.alternativeLabel),
    "routes" to routesJson(a.routes),
    "recommendation" to j(a.recommendation),
    "simulation" to (a.simulation?.let(::simulationJson) ?: JsonNull),
    "metrics" to metricsJson(a.metrics),
    "draw" to drawJson(a.draw),
    "context" to contextJson(a.context),
)

fun summaryJson(s: ReviewSummary, withSteps: Boolean): JsonObject {
    val m = linkedMapOf<String, JsonElement>()
    if (withSteps) m["steps"] = JsonArray(s.steps.map(::analysisJson))
    m["priorityIndex"] = j(s.priorityIndex)
    m["attention"] = j(s.attention)
    m["consider"] = j(s.consider)
    m["themes"] = jStrings(s.themes)
    m["title"] = j(s.title)
    m["summary"] = j(s.summary)
    return JsonObject(m)
}

fun explanationJson(e: OpponentExplanation): JsonObject = jObj(
    "title" to j(e.title),
    "detail" to j(e.detail),
    "reasons" to jStrings(e.reasons),
    "made" to j(e.made),
    "warning" to j(e.warning),
)

/**
 * The reference leaves `routes.secondary` undefined (absent from JSON) on paths that never
 * assign it, and `null` where a candidate is unavailable. Both mean "no secondary route";
 * native code has a single `null`. Normalizes every `routes` object in [e] to an explicit null.
 */
fun normalizeRoutes(e: JsonElement): JsonElement = when (e) {
    is JsonObject -> {
        val m = LinkedHashMap<String, JsonElement>()
        for ((k, v) in e) m[k] = normalizeRoutes(v)
        if ("primary" in m && "secondary" !in m) m["secondary"] = JsonNull
        JsonObject(m)
    }
    is JsonArray -> JsonArray(e.map(::normalizeRoutes))
    else -> e
}
