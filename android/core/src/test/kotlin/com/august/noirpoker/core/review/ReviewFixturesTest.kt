package com.august.noirpoker.core.review

import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.SeededRandom
import com.august.noirpoker.core.fixtures.FixtureReport
import com.august.noirpoker.core.fixtures.arr
import com.august.noirpoker.core.fixtures.b
import com.august.noirpoker.core.fixtures.cardsOf
import com.august.noirpoker.core.fixtures.d
import com.august.noirpoker.core.fixtures.i
import com.august.noirpoker.core.fixtures.j
import com.august.noirpoker.core.fixtures.jsonDiff
import com.august.noirpoker.core.fixtures.loadFixture
import com.august.noirpoker.core.fixtures.obj
import com.august.noirpoker.core.fixtures.opt
import com.august.noirpoker.core.fixtures.str
import com.august.noirpoker.core.newGame
import com.august.noirpoker.core.startHand
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import kotlin.test.Test

/**
 * Replays `fixtures/review-decisions.json` and `fixtures/review-hands.json` (generated from
 * the pinned reference the `src/review` modules) against the native review port. Every recorded
 * field is compared exactly: strings byte for byte, numbers as exact doubles. The one
 * normalization is `routes.secondary`: undefined (absent) and `null` both mean "none".
 */
class ReviewFixturesTest {
    private val unrepresentable = java.util.Collections.synchronizedList(mutableListOf<String>())

    private val decisionsFixture by lazy { loadFixture("review-decisions.json") }
    private val handsFixture by lazy { loadFixture("review-hands.json") }

    /** Runs checks on a worker pool (every review call is pure), then reports in fixture order. */
    private fun runAll(file: String, checks: List<Pair<String, () -> String?>>) {
        val pool = Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors().coerceIn(1, 8))
        try {
            val futures = checks.map { (_, body) ->
                pool.submit(
                    Callable<Result<String?>> { runCatching(body) },
                )
            }
            val report = FixtureReport(file)
            checks.forEachIndexed { k, (name, _) ->
                report.case(name) { futures[k].get().getOrThrow() }
            }
            report.finish()
        } finally {
            pool.shutdownNow()
        }
    }

    private fun diff(expected: JsonElement, actual: JsonElement): String? =
        jsonDiff(normalizeRoutes(expected), normalizeRoutes(actual))

    private fun options(e: JsonElement?): Pair<Int, Int> {
        val o = e?.obj ?: JsonObject(emptyMap())
        val trials = o.opt("trials")?.i ?: 600
        val rollout = o.opt("rolloutTrials")?.i ?: defaultRolloutTrials(trials)
        return trials to rollout
    }

    private fun analyze(s: ReviewDecision, opts: JsonElement?): DecisionAnalysis {
        val (trials, rollout) = options(opts)
        return analyzeDecision(s, trials, rollout)
    }

    private fun decisionChecks(c: JsonObject): List<Pair<String, () -> String?>> {
        val name = c.getValue("name").str
        val fractional = hasFractionalChips(c.getValue("snapshot"))
        val s = lenientDecisionOf(c.getValue("snapshot"))
        val out = mutableListOf<Pair<String, () -> String?>>()
        fun check(field: String, body: () -> String?) {
            if (fractional && field.substringBefore('[').substringBefore('.') in TOTAL_DEPENDENT) {
                unrepresentable.add("$name › $field")
            } else {
                out.add("$name › $field" to body)
            }
        }

        check("startingTier") { diff(c.getValue("startingTier"), j(startingTier(s.hole))) }
        check("drawInfo") { diff(c.getValue("drawInfo"), drawJson(drawInfo(s.hole, s.board))) }
        check("boardTexture") { diff(c.getValue("boardTexture"), textureJson(boardTexture(s.board))) }
        check("decisionContext") { diff(c.getValue("decisionContext"), contextJson(decisionContext(s))) }
        check("preflopContext") { diff(c.getValue("preflopContext"), preflopJson(preflopContext(s))) }
        check("snapshotSeed") { diff(c.getValue("snapshotSeed"), JsonPrimitive(snapshotSeed(s))) }
        check("callPrice") { diff(c.getValue("callPrice"), callPriceJson(callPrice(s))) }
        check("rangeWeight") {
            c.getValue("rangeWeight").arr.withIndex().firstNotNullOfOrNull { (k, r) ->
                val o = r.obj
                val opponent = s.players[o.getValue("opponent").i]
                diff(o.getValue("weight"), j(rangeWeight(cardsOf(o.getValue("pair")), s, opponent)))?.let { "[$k] $it" }
            }
        }
        check("sampleValue") {
            val price = callPrice(s)
            c.getValue("sampleValue").arr.withIndex().firstNotNullOfOrNull { (k, r) ->
                val o = r.obj
                diff(o.getValue("result"), sampledJson(sampleValue(s, price, o.getValue("trials").i, o.getValue("weighted").b)))
                    ?.let { "[$k] $it" }
            }
        }
        check("candidateActions") {
            c.getValue("candidateActions").arr.withIndex().firstNotNullOfOrNull { (k, r) ->
                val o = r.obj
                val alts = o.getValue("alternatives").arr.map(::candidateOf)
                diff(o.getValue("result"), JsonArray(candidateActions(s, alts).map(::candidateJson)))?.let { "[$k] $it" }
            }
        }
        check("comparisonRoutes") {
            val ctx = decisionContext(s)
            val pre = preflopContext(s)
            c.getValue("comparisonRoutes").arr.withIndex().firstNotNullOfOrNull { (k, r) ->
                val a = r.obj.getValue("args").obj
                val status = ReviewStatus.entries.first { it.id == a.getValue("status").str }
                val routes = comparisonRoutes(
                    s,
                    ctx,
                    a.getValue("code").str,
                    status,
                    candidateOf(a.getValue("alternative"))!!,
                    if (a.getValue("withPreflopContext").b) pre else null,
                )
                diff(r.obj.getValue("result"), routesJson(routes))?.let { "[$k] args=$a $it" }
            }
        }
        c.getValue("compareCandidateActions").arr.forEachIndexed { k, r ->
            check("compareCandidateActions[$k]") {
                val o = r.obj
                val alts = o.getValue("alternatives").arr.map(::candidateOf)
                diff(o.getValue("result"), simulationJson(compareCandidateActions(s, alts, o.getValue("trials").i)))
            }
        }
        val ad = c.getValue("analyzeDecision").obj
        check("analyzeDecision.default") { diff(ad.getValue("default"), analysisJson(analyze(s, null))) }
        ad.opt("reduced")?.let { r ->
            check("analyzeDecision.reduced") { diff(r.obj.getValue("result"), analysisJson(analyze(s, r.obj["options"]))) }
        }
        ad.opt("noSimulation")?.let { r ->
            check("analyzeDecision.noSimulation") { diff(r, analysisJson(analyze(s.copy(dealer = null), null))) }
        }
        ad.opt("test")?.let { r ->
            check("analyzeDecision.test") { diff(r.obj.getValue("result"), analysisJson(analyze(s, r.obj["options"]))) }
        }
        return out
    }

    @Test
    fun reviewDecisionFixtures() {
        val checks = decisionsFixture.getValue("cases").arr.flatMap { decisionChecks(it.obj) }
        if (unrepresentable.isNotEmpty()) {
            println("review-decisions.json: ${unrepresentable.size} checks skipped (fractional chip totals in hand-built snapshots): $unrepresentable")
        }
        runAll("review-decisions.json", checks)
    }

    @Test
    fun reviewHandFixtures() {
        val f = handsFixture
        val cases = decisionsFixture.getValue("cases").arr
        val checks = mutableListOf<Pair<String, () -> String?>>()
        fun check(name: String, body: () -> String?) = checks.add(name to body)

        val tables = f.getValue("tables").obj
        check("tables.streetNames") { diff(tables.getValue("streetNames"), JsonArray(ReviewCopy.streetNames.map(::j))) }
        check("tables.botReasonNames") {
            diff(tables.getValue("botReasonNames"), JsonObject(BOT_REASON_NAMES.mapValues { j(it.value) }))
        }
        check("tables.botCheckNames") {
            diff(tables.getValue("botCheckNames"), JsonObject(BOT_CHECK_NAMES.mapValues { j(it.value) }))
        }
        val errors = f.getValue("errors").obj
        check("errors") {
            diff(
                errors,
                JsonObject(
                    mapOf(
                        "review-not-ready" to j(ReviewCopy.errorInputNotDone),
                        "invalid-review-trials" to j(ReviewCopy.errorTrials),
                        "invalid-simulation-trials" to j(ReviewCopy.errorSimTrials),
                        "simulation-runaway" to j(ReviewCopy.errorSimRunaway),
                    ),
                ),
            )
        }

        for (h in f.getValue("hands").arr) {
            val o = h.obj
            val name = o.getValue("name").str
            val input = reviewInputOf(o.getValue("input"))
            val indices = o.getValue("decisions").arr.map { it.i }
            check("$name › decisions") {
                // Each input decision is the same public snapshot as its review-decisions case.
                indices.withIndex().firstNotNullOfOrNull { (k, idx) ->
                    if (reviewDecisionOf(cases[idx].obj.getValue("snapshot")) == input.decisions[k]) null else "decision $k differs from case $idx"
                }
            }
            for ((key, opts) in listOf("analyzeReview" to null, "analyzeReviewReduced" to "reduced")) {
                val rec = o.getValue(key).obj
                check("$name › $key") {
                    val (trials, rollout) = options(rec["options"])
                    // Steps come from the per-decision cases; recompute only the summary here.
                    val steps = indices.map { idx ->
                        val ad = cases[idx].obj.getValue("analyzeDecision").obj
                        val s = reviewDecisionOf(cases[idx].obj.getValue("snapshot"))
                        val expectedStep = if (opts == null) ad.getValue("default") else ad.getValue("reduced").obj.getValue("result")
                        val step = analyzeDecision(s, trials, rollout)
                        diff(expectedStep, analysisJson(step))?.let { return@check "step ${s.index}: $it" }
                        step
                    }
                    diff(rec.getValue("summary"), summaryJson(summarizeReview(input, steps), withSteps = false))
                }
            }
            o.getValue("explainOpponent").arr.forEachIndexed { k, e ->
                check("$name › explainOpponent[$k]") { diff(e, explanationJson(explainOpponent(input.opponents[k]))) }
            }
        }

        for (p in f.getValue("privacy").arr) {
            val o = p.obj
            val name = o.getValue("name").str
            o.getValue("variants").arr.forEachIndexed { k, v ->
                check("$name › variant ${"AB"[k]}") {
                    val (trials, rollout) = options(o["options"])
                    diff(o.getValue("result"), summaryJson(analyzeReview(reviewInputOf(v), trials, rollout), withSteps = true))
                }
            }
        }

        for (r in f.getValue("reviewInputs").arr) {
            val o = r.obj
            check(o.getValue("name").str) {
                val (trials, rollout) = options(o["options"])
                diff(o.getValue("result"), summaryJson(analyzeReview(reviewInputOf(o.getValue("input")), trials, rollout), withSteps = true))
            }
        }

        for (e in f.getValue("explainOpponent").arr) {
            val o = e.obj
            check(o.getValue("name").str) { diff(o.getValue("result"), explanationJson(explainOpponent(botRecordOf(o.getValue("record"))))) }
        }

        for (e in f.getValue("errorCases").arr) {
            val o = e.obj
            check(o.getValue("name").str) {
                val expected = errors.getValue(o.getValue("error").str).str
                val opts = o.opt("options")?.obj
                val trials = opts?.get("trials")
                // A non-integer count cannot reach the native API (its parameter is an Int).
                if (trials != null && trials.d != Math.floor(trials.d)) return@check null
                val message = try {
                    when (o.getValue("fn").str) {
                        "createReviewInput" -> {
                            val g = newGame()
                            startHand(g, SeededRandom(1))
                            check(g.phase == Phase.PLAYING)
                            createReviewInput(g)
                        }
                        "analyzeDecision" -> analyzeDecision(reviewDecisionOf(cases[o.getValue("decision").i].obj.getValue("snapshot")), trials!!.i)
                        "compareCandidateActions" ->
                            compareCandidateActions(reviewDecisionOf(cases[o.getValue("decision").i].obj.getValue("snapshot")), trials = trials!!.i)
                        else -> return@check "unknown fn"
                    }
                    return@check "did not throw"
                } catch (x: ReviewException) {
                    x.message
                }
                if (message == expected) null else "expected \"$expected\" actual \"$message\""
            }
        }

        runAll("review-hands.json", checks)
    }
}

/** Outputs that read the snapshot's chip totals directly or through the snapshot seed. */
private val TOTAL_DEPENDENT = setOf("snapshotSeed", "callPrice", "sampleValue", "compareCandidateActions", "analyzeDecision")
