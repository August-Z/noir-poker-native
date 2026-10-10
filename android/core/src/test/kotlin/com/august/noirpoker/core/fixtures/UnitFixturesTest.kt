package com.august.noirpoker.core.fixtures

import com.august.noirpoker.core.BOT_PROFILES
import com.august.noirpoker.core.BotThinkLimits
import com.august.noirpoker.core.EmotionMode
import com.august.noirpoker.core.LabelLegal
import com.august.noirpoker.core.LabelStep
import com.august.noirpoker.core.MoodKind
import com.august.noirpoker.core.PROFILE_AXES
import com.august.noirpoker.core.Player
import com.august.noirpoker.core.SeededRandom
import com.august.noirpoker.core.actionLabel
import com.august.noirpoker.core.compare
import com.august.noirpoker.core.decayBotMood
import com.august.noirpoker.core.defaultBotSettings
import com.august.noirpoker.core.effectiveBotAxes
import com.august.noirpoker.core.evaluate
import com.august.noirpoker.core.finishBotHand
import com.august.noirpoker.core.freshBotMood
import com.august.noirpoker.core.freshBotStats
import com.august.noirpoker.core.getBotProfile
import com.august.noirpoker.core.historyActionLabel
import com.august.noirpoker.core.nextBetLevel
import com.august.noirpoker.core.raiseCaption
import com.august.noirpoker.core.recordPressureFold
import com.august.noirpoker.core.sanitizeBotSettings
import com.august.noirpoker.core.startingPercentile
import com.august.noirpoker.core.BotSettings
import com.august.noirpoker.core.MoodEvent
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test

class UnitFixturesTest {
    @Test
    fun `rng fixture`() {
        val report = FixtureReport("rng.json")
        for (c in loadFixture("rng.json").getValue("cases").arr) {
            val seed = c.obj.getValue("seed").jsonLong()
            report.case("seed $seed") {
                val r = SeededRandom(seed)
                jsonDiff(c.obj.getValue("values"), jDoubles(List(20) { r.next() }))
            }
        }
        report.finish()
    }

    @Test
    fun `hand-ranks fixture`() {
        val report = FixtureReport("hand-ranks.json")
        for (c in loadFixture("hand-ranks.json").getValue("cases").arr) {
            val o = c.obj
            report.case(o.getValue("name").str) {
                val input = o.getValue("cards").arr.map { com.august.noirpoker.core.Card(it.obj.getValue("rank").i, it.obj.getValue("suit").i) }
                val result = evaluate(input)
                jsonDiff(o.getValue("score"), jInts(result.score), "score")
                    ?: jsonDiff(o.getValue("bestCardKeys"), jCards(result.cards), "bestCardKeys")
            }
        }
        report.finish()
    }

    @Test
    fun `hand-eval fixture`() {
        val report = FixtureReport("hand-eval.json")
        val root = loadFixture("hand-eval.json")
        for (c in root.getValue("cases").arr) {
            val o = c.obj
            report.case(o.getValue("name").str) {
                val result = evaluate(cardsOf(o.getValue("cards")))
                jsonDiff(o.getValue("score"), jInts(result.score), "score")
                    ?: jsonDiff(o.getValue("label"), j(result.label), "label")
                    ?: jsonDiff(o.getValue("bestCardKeys"), jCards(result.cards), "bestCardKeys")
            }
        }
        root.getValue("compare").arr.forEachIndexed { index, c ->
            val o = c.obj
            report.case("compare ${index + 1}") {
                val a = o.getValue("a").arr.map { it.i }
                val b = o.getValue("b").arr.map { it.i }
                jsonDiff(o.getValue("result"), j(compare(a, b)), "result")
            }
        }
        report.finish()
    }

    private fun labelStepOf(e: JsonElement): LabelStep {
        val o = e.obj
        val legal = o.opt("legal")?.obj?.let { l ->
            LabelLegal(l.opt("callAmount")?.i, l.opt("fullRaiseTo")?.i, l.opt("maxRaiseTo")?.i)
        }
        return LabelStep(
            street = o.getValue("street").i,
            history = o.opt("history")?.let(::historyOf) ?: emptyList(),
            currentBet = o.opt("currentBet")?.i ?: 0,
            minRaise = o.opt("minRaise")?.i,
            legal = legal,
            stack = o.opt("stack")?.i,
            action = o.opt("action")?.str?.let(::actionOf),
            amount = o.opt("amount")?.d,
        )
    }

    @Test
    fun `action-labels fixture`() {
        val report = FixtureReport("action-labels.json")
        loadFixture("action-labels.json").getValue("cases").arr.forEachIndexed { index, c ->
            val o = c.obj
            val fn = o.getValue("fn").str
            report.case("case ${index + 1} ($fn)") {
                val actual: String = when (fn) {
                    "nextBetLevel" -> nextBetLevel(labelStepOf(o.getValue("step"))).toString()
                    "raiseCaption" -> raiseCaption(labelStepOf(o.getValue("step")), o.getValue("amount").d)
                    "actionLabel" -> {
                        val step = labelStepOf(o.getValue("step"))
                        actionLabel(
                            step,
                            o.opt("action")?.str?.let(::actionOf) ?: step.action,
                            o.opt("amount")?.d ?: step.amount,
                        )
                    }
                    "historyActionLabel" -> historyActionLabel(historyOf(o.getValue("history")), o.getValue("index").i)
                    else -> error("unknown fn $fn")
                }
                val expected = o.getValue("result")
                if (fn == "nextBetLevel") jsonDiff(expected, j(actual.toInt()), "result") else jsonDiff(expected, j(actual), "result")
            }
        }
        report.finish()
    }

    private fun settingsJson(s: BotSettings): JsonObject = jObj(
        "emotionMode" to j(s.emotionMode.id),
        "assignments" to JsonObject(s.assignments.entries.associate { (k, v) -> k.toString() to j(v) }),
    )

    @Test
    fun `bot-profiles fixture`() {
        val report = FixtureReport("bot-profiles.json")
        val root = loadFixture("bot-profiles.json")
        report.case("profiles") {
            val actual = JsonArray(
                BOT_PROFILES.map { p ->
                    jObj(
                        "id" to j(p.id),
                        "name" to j(p.name),
                        "short" to j(p.short),
                        "tag" to j(p.tag),
                        "description" to j(p.description),
                        "axes" to jInts(p.axes),
                        "sizing" to jDoubles(p.sizing),
                        "evidence" to j(p.evidence),
                        "sources" to JsonArray(p.sources.map { jObj("label" to j(it.label), "url" to j(it.url)) }),
                    )
                },
            )
            jsonDiff(root.getValue("profiles"), actual, "profiles")
        }
        report.case("axes") { jsonDiff(root.getValue("axes"), jStrings(PROFILE_AXES)) }
        report.case("emotionModes") {
            jsonDiff(root.getValue("emotionModes"), JsonArray(EmotionMode.entries.map { jObj("id" to j(it.id), "label" to j(it.label)) }))
        }
        report.case("moodLabels") {
            jsonDiff(root.getValue("moodLabels"), JsonArray(MoodKind.entries.map { jObj("kind" to j(it.id), "label" to j(it.label)) }))
        }
        report.case("defaultBotSettings") { jsonDiff(root.getValue("defaultBotSettings"), settingsJson(defaultBotSettings())) }
        report.case("freshBotMood") { jsonDiff(root.getValue("freshBotMood"), moodJson(freshBotMood())) }
        report.case("freshBotStats") {
            jsonDiff(root.getValue("freshBotStats"), statsJson(Player(id = 1, name = "", botStats = freshBotStats())))
        }
        report.case("botThinkLimits") {
            jsonDiff(root.getValue("botThinkLimits"), jObj("minimum" to j(BotThinkLimits.MINIMUM), "maximum" to j(BotThinkLimits.MAXIMUM)))
        }
        root.getValue("sanitizeBotSettings").arr.forEachIndexed { index, c ->
            report.case("sanitizeBotSettings ${index + 1}: ${c.obj.getValue("input")}") {
                jsonDiff(c.obj.getValue("output"), settingsJson(sanitizeBotSettings(toPlain(c.obj.getValue("input")))))
            }
        }
        for (c in root.getValue("startingPercentile").arr) {
            report.case("startingPercentile ${c.obj.getValue("hand").str}") {
                jsonDiff(c.obj.getValue("percentile"), j(startingPercentile(cardsOf(c.obj.getValue("hole")))))
            }
        }
        report.finish()
    }

    private fun eventJson(e: MoodEvent?): JsonElement =
        e?.let { jObj("kind" to j(it.kind.id), "reason" to j(it.reason)) } ?: JsonNull

    @Test
    fun `mood fixture`() {
        val report = FixtureReport("mood.json")
        for (seq in loadFixture("mood.json").getValue("sequences").arr) {
            val name = seq.obj.getValue("name").str
            report.case(name) {
                val mood = freshBotMood()
                var problem: String? = null
                for ((k, s) in seq.obj.getValue("steps").arr.withIndex()) {
                    val o = s.obj
                    val mode = o.opt("mode")?.str?.let { m -> EmotionMode.fromId(m)!! }
                    val result: JsonElement = when (val op = o.getValue("op").str) {
                        "decay" -> {
                            decayBotMood(mood)
                            JsonNull
                        }
                        "pressureFold" -> eventJson(recordPressureFold(mood, o.opt("raiser")?.i, mode!!))
                        "finish" -> eventJson(
                            finishBotHand(Player(id = o.getValue("playerId").i, name = "", botMood = mood), o.getValue("profit").i, mode!!),
                        )
                        "resetPressure" -> {
                            mood.pressureFolds[o.getValue("raiser").i] = 0
                            JsonNull
                        }
                        "clearPressure" -> {
                            mood.pressureFolds = java.util.TreeMap()
                            mood.lastPressureRaiser = null
                            JsonNull
                        }
                        "axes" -> jDoubles(effectiveBotAxes(getBotProfile(o.getValue("profile").str), mood, mode!!))
                        else -> error("unknown op $op")
                    }
                    problem = jsonDiff(o.getValue("result"), result, "step ${k + 1} (${o.getValue("op").str}).result")
                        ?: jsonDiff(o.getValue("mood"), moodJson(mood), "step ${k + 1} (${o.getValue("op").str}).mood")
                    if (problem != null) break
                }
                problem
            }
        }
        report.finish()
    }
}

fun JsonElement.jsonLong(): Long = str.toLong()
