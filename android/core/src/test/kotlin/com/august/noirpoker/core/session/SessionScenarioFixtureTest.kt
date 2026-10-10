package com.august.noirpoker.core.session

import com.august.noirpoker.core.Card
import com.august.noirpoker.core.Difficulty
import com.august.noirpoker.core.EmotionMode
import com.august.noirpoker.core.fixtures.arr
import com.august.noirpoker.core.fixtures.b
import com.august.noirpoker.core.fixtures.i
import com.august.noirpoker.core.fixtures.loadFixture
import com.august.noirpoker.core.fixtures.obj
import com.august.noirpoker.core.fixtures.opt
import com.august.noirpoker.core.fixtures.str
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.fail

/**
 * Replays `fixtures/session-scenarios.json`: scripted session commands on a
 * virtual clock with a seeded stream, checking render-state excerpts after
 * each `expect` step. The Swift `SessionScenarioFixtureTests` consumes the same
 * file with the same projection (`fixtures/README.md` → `session-scenarios.json`).
 */
class SessionScenarioFixtureTest {
    @Test
    fun sessionScenariosMatchTheSharedFixture() {
        val fixture = loadFixture("session-scenarios.json")
        val record = System.getenv("NOIR_SESSION_RECORD")
        val recorded = mutableListOf<JsonElement>()
        val failures = mutableListOf<String>()
        val scenarios = fixture.getValue("scenarios").arr
        for (scenario in scenarios.map { it.obj }) {
            val name = scenario.getValue("name").str
            val runner = ScenarioRunner(scenario)
            val dumps = mutableListOf<JsonElement>()
            for ((index, step) in scenario.getValue("steps").arr.map { it.obj }.withIndex()) {
                val label = "$name · step $index"
                val expect = step["expect"]
                if (expect == null) {
                    runner.run(step, label)
                    continue
                }
                val actual = runner.project()
                runner.effects.clear()
                if (record != null) {
                    dumps.add(actual)
                } else {
                    val diffs = mutableListOf<String>()
                    matchJson(expect, actual, "", diffs)
                    if (diffs.isNotEmpty()) failures.add("$label:\n  " + diffs.take(20).joinToString("\n  "))
                }
            }
            recorded.add(JsonObject(mapOf("name" to JsonPrimitive(name), "dumps" to JsonArray(dumps))))
        }
        if (record != null) {
            File(record).writeText(Json.encodeToString(JsonElement.serializer(), JsonArray(recorded)))
            return
        }
        if (failures.isNotEmpty()) fail(failures.joinToString("\n"))
        assertEquals(scenarios.size, recorded.size)
    }
}

/** Expected values are partial: objects check only their keys, arrays check length and each element. */
fun matchJson(expected: JsonElement, actual: JsonElement?, path: String, out: MutableList<String>) {
    when (expected) {
        is JsonObject -> {
            if (actual !is JsonObject) {
                out.add("$path: expected an object, got $actual")
                return
            }
            for ((k, v) in expected) {
                if (!actual.containsKey(k)) out.add("$path.$k: missing") else matchJson(v, actual[k], "$path.$k", out)
            }
        }
        is JsonArray -> {
            if (actual !is JsonArray || actual.size != expected.size) {
                out.add("$path: expected $expected, got $actual")
                return
            }
            expected.forEachIndexed { i, e -> matchJson(e, actual[i], "$path[$i]", out) }
        }
        is JsonNull -> if (actual !is JsonNull) out.add("$path: expected null, got $actual")
        is JsonPrimitive -> {
            val a = actual as? JsonPrimitive
            val same = when {
                a == null || a is JsonNull -> false
                expected.isString -> a.isString && a.content == expected.content
                expected.booleanOrNull != null -> !a.isString && a.booleanOrNull == expected.booleanOrNull
                else -> !a.isString && a.doubleOrNull != null && a.doubleOrNull == expected.doubleOrNull
            }
            if (!same) out.add("$path: expected $expected, got $actual")
        }
    }
}

/** Runs one scenario's commands against a [Harness] and projects its state. */
class ScenarioRunner(scenario: JsonObject) {
    private val storage = InMemoryStorage(
        scenario["storage"]?.obj?.mapValues { it.value.str } ?: emptyMap(),
    )
    private val runner: FakeReviewRunner? = if (scenario["reviewRunner"]?.b == true) FakeReviewRunner() else null
    val h = Harness(seed = scenario.getValue("seed").i.toLong(), storage = storage, runner = runner)
    val effects: MutableList<SessionEffect> get() = h.effects

    fun run(step: JsonObject, label: String) {
        val s = h.session
        val op = step.getValue("do").str
        fun int(key: String) = step.getValue(key).i
        val result: Boolean? = when (op) {
            "start" -> { s.start(); null }
            "nextHand" -> s.nextHand()
            "replayHand" -> s.replayHand()
            "startNewSession" -> { s.startNewSession(); null }
            "finishHand" -> s.finishHand()
            "fold" -> s.fold()
            "callOrCheck" -> s.callOrCheck()
            "raise" -> step.opt("amount")?.let { s.raise(it.i) } ?: s.raise()
            "setBet" -> { s.setBet(int("value")); null }
            "nudgeBet" -> { s.nudgeBet(int("steps")); null }
            "preset" -> s.preset(BetPreset.entries.first { it.id == step.getValue("preset").str })
            "toggleReveal" -> s.toggleReveal(int("seat"))
            "setSeatCount" -> s.setSeatCount(int("count"))
            "setDifficulty" -> { s.setDifficulty(Difficulty.fromId(step.getValue("difficulty").str)!!); null }
            "toggleHints" -> { s.toggleHints(); null }
            "toggleSound" -> { s.toggleSound(); null }
            "openOpponentSettings" -> { s.openOpponentSettings(); null }
            "previewProfile" -> { s.previewProfile(step.getValue("id").str); null }
            "assignSeatStyle" -> { s.assignSeatStyle(int("seat"), step.getValue("profile").str); null }
            "setEmotionMode" -> { s.setEmotionMode(EmotionMode.fromId(step.getValue("mode").str)!!); null }
            "mixLineup" -> { s.mixLineup(); null }
            "saveOpponentSettings" -> s.saveOpponentSettings()
            "discardOpponentSettings" -> { s.discardOpponentSettings(); null }
            "openPotDetails" -> { s.openPotDetails(); null }
            "closePotDetails" -> { s.closePotDetails(); null }
            "togglePotDistribution" -> { s.togglePotDistribution(int("index")); null }
            "openReview" -> { s.openReview(); null }
            "closeReview" -> { s.closeReview(); null }
            "completeReview" -> {
                val job = runner!!.started.last()
                job.sink.complete(FakeAnalysis(int("priorityIndex")))
                null
            }
            "background" -> { s.onBackground(); null }
            "foreground" -> { s.onForeground(); null }
            "advance" -> { h.scheduler.advanceBy(step.getValue("ms").i.toLong()); null }
            "runCurrent" -> { h.scheduler.runCurrent(); null }
            "runBots" -> { h.runBots(); null }
            "runUntilIdle" -> { h.scheduler.runUntilIdle(); null }
            "stop" -> { h.hooks.stop(); null }
            "resumeBots" -> { h.hooks.resumeBots(); null }
            "playOut" -> { playOut(step.getValue("hero").str, label); null }
            "qa" -> { qa(step); null }
            else -> fail("$label: unknown command $op")
        }
        step["returns"]?.let { assertEquals(it.b, result, "$label: $op return value") }
    }

    /** Runs bots on the virtual clock; on each hero turn takes [heroAction] (`fold` or `callOrCheck`), until the hand is over. */
    private fun playOut(heroAction: String, label: String) {
        repeat(200) {
            h.runBots()
            val g = h.game
            if (g.phase == com.august.noirpoker.core.Phase.DONE) return
            if (g.phase == com.august.noirpoker.core.Phase.PLAYING && g.actor == 0) {
                if (heroAction == "fold") h.session.fold() else h.session.callOrCheck()
            } else if (h.scheduler.nextDueAt == null) {
                fail("$label: playOut stalled")
            }
        }
        fail("$label: playOut did not finish")
    }

    private fun qa(step: JsonObject) {
        fun intOr(key: String, default: Int) = step.opt(key)?.i ?: default
        fun boolOr(key: String) = step.opt(key)?.b ?: false
        when (val name = step.getValue("fixture").str) {
            "heroTurn" -> h.heroTurn(intOr("count", 6), boolOr("unequal"))
            "bettingTurn" -> h.bettingTurn(intOr("level", 2), intOr("street", 0), boolOr("short"))
            "foldFinished" -> h.foldFinished(intOr("street", 0))
            "allinRest" -> h.allinRest()
            "respondToHero" -> h.respondToHero(intOr("raiseTo", 0), boolOr("nextStreet"))
            "river" -> h.river(intOr("count", 6))
            "retainedRiver" -> h.retainedRiver(intOr("count", 6))
            "finish" -> h.finish()
            "foldWin" -> h.foldWin(intOr("count", 6), intOr("winner", intOr("count", 6) - 1))
            "foldRest" -> h.foldRest()
            "foldPotRefund" -> h.foldPotRefund(intOr("count", 6))
            "scene" -> h.scene(
                hole = step.getValue("hole").str,
                board = step.getValue("board").str,
                count = intOr("count", 6),
                totals = step.opt("totals")?.arr?.map { it.i },
                folded = step.opt("folded")?.arr?.map { it.i } ?: emptyList(),
                otherHoles = step.opt("otherHoles")?.obj?.entries?.associate { it.key.toInt() to it.value.str } ?: emptyMap(),
            )
            else -> fail("unknown QA fixture $name")
        }
    }

    // ---- Projection (the shape documented in fixtures/README.md) -----------------

    fun project(): JsonObject {
        val st = h.state
        val thinking = h.hooks.thinking()
        return o(
            "state" to state(st),
            "clock" to n(h.scheduler.nowMs),
            "pending" to n(h.scheduler.pendingCount),
            "nextDueAt" to (h.scheduler.nextDueAt?.let { n(it) } ?: JsonNull),
            "draws" to n(h.random.draws),
            "thinking" to (thinking?.let { o("actor" to n(it.actor), "delayMs" to n(it.delayMs), "startedAt" to n(it.startedAt), "deadline" to n(it.deadline)) } ?: JsonNull),
            "effects" to JsonArray(h.effects.map { JsonPrimitive(effect(it)) }),
            "storage" to JsonObject(storage.values.mapValues { JsonPrimitive(it.value) }),
            "wealth" to n(h.wealth()),
            "epoch" to n(h.session.epoch),
            "viewToken" to n(h.session.viewToken),
            "canFinishHand" to b(h.session.canFinishHand()),
        )
    }

    private fun effect(e: SessionEffect): String = when (e) {
        is SessionEffect.Sound -> "sound:" + e.kind.name.lowercase()
        is SessionEffect.ChipFlight -> "chipFlight:${e.seat}"
        SessionEffect.CancelChipFlights -> "cancelChipFlights"
        is SessionEffect.RevealToggled -> "revealToggled:${e.seat}:${e.visible}"
    }

    private fun state(st: TableRenderState): JsonObject = o(
        "hand" to n(st.hand), "handNumber" to s(st.handNumber), "handHeading" to s(st.handHeading),
        "playerCount" to n(st.playerCount), "tableTag" to s(st.tableTag), "tableSize" to s(st.tableSize),
        "hasFullPlayerNames" to b(st.hasFullPlayerNames), "phase" to s(st.phase.id), "street" to n(st.street),
        "streetLabel" to s(st.streetLabel), "dealer" to n(st.dealer), "replayAttempt" to n(st.replayAttempt),
        "replayBadge" to s(st.replayBadge), "replayNote" to s(st.replayNote), "pot" to n(st.pot),
        "potText" to s(st.potText), "potPulse" to b(st.potPulse), "potButtonLabel" to s(st.potButtonLabel),
        "potButtonA11y" to s(st.potButtonA11y),
        "board" to JsonArray(st.board.map { slot ->
            o("card" to s(slot.card?.card?.key), "best" to b(slot.card?.best ?: false), "animate" to b(slot.card?.animate ?: false),
              "delayMs" to n(slot.card?.delayMs ?: 0), "a11y" to s(slot.a11y))
        }),
        "boardCaption" to s(st.boardCaption), "practiceRunout" to b(st.practiceRunout),
        "seats" to JsonArray(st.seats.map { seat(it) }),
        "hero" to st.hero.let { hero ->
            o("name" to s(hero.name), "cards" to JsonArray(hero.cards.map { face(it) }), "rankBadge" to badge(hero.rankBadge),
              "folded" to b(hero.folded), "isActive" to b(hero.isActive), "stack" to n(hero.stack), "stackText" to s(hero.stackText),
              "position" to s(hero.position.code), "positionName" to s(hero.position.name), "turnText" to s(hero.turnText),
              "lastAction" to (hero.lastAction?.let { chip(it) } ?: JsonNull))
        },
        "session" to st.session.let {
            o("stack" to n(it.stack), "stackText" to s(it.stackText), "changeText" to s(it.changeText), "negative" to b(it.negative),
              "hands" to n(it.hands), "wins" to n(it.wins), "winRateText" to s(it.winRateText))
        },
        "activity" to o(
            "badge" to s(st.activity.badge),
            "texts" to JsonArray(st.activity.entries.map { JsonPrimitive(it.text) }),
            "entries" to JsonArray(st.activity.entries.map { e ->
                o("number" to n(e.number), "text" to s(e.text), "type" to s(e.type.id), "playerId" to (e.playerId?.let { n(it) } ?: JsonNull),
                  "isHero" to b(e.isHero), "street" to n(e.street),
                  "personas" to JsonArray(e.segments.filter { it.isPersona }.map { JsonPrimitive(it.text) }))
            }),
        ),
        "actions" to st.actions.let { a ->
            o("decisionStripVisible" to b(a.decisionStripVisible), "decisionText" to s(a.decisionText),
              "controlsVisible" to b(a.controlsVisible), "foldEnabled" to b(a.foldEnabled), "callEnabled" to b(a.callEnabled),
              "callLabel" to s(a.callLabel), "callAmount" to (a.callAmount?.let { n(it) } ?: JsonNull), "callA11y" to s(a.callA11y),
              "raiseEnabled" to b(a.raiseEnabled), "raiseCaption" to s(a.raiseCaption), "bet" to n(a.bet), "betText" to s(a.betText),
              "raiseA11y" to s(a.raiseA11y), "sliderMin" to (a.sliderMin?.let { n(it) } ?: JsonNull),
              "sliderMax" to (a.sliderMax?.let { n(it) } ?: JsonNull),
              "presets" to JsonArray(a.presets.map {
                  o("preset" to s(it.preset.id), "label" to s(it.label), "amount" to (it.amount?.let { v -> n(v) } ?: JsonNull), "enabled" to b(it.enabled))
              }),
              "nextHandVisible" to b(a.nextHandVisible), "nextHandLabel" to s(a.nextHandLabel),
              "finishHandVisible" to b(a.finishHandVisible), "finishHandEnabled" to b(a.finishHandEnabled),
              "finishHandLabel" to s(a.finishHandLabel), "replayVisible" to b(a.replayVisible), "replayLabel" to s(a.replayLabel),
              "reviewVisible" to b(a.reviewVisible), "reviewLabel" to s(a.reviewLabel))
        },
        "coach" to o("visible" to b(st.coach.visible), "toggleLabel" to s(st.coach.toggleLabel), "stage" to s(st.coach.stage), "tip" to s(st.coach.tip)),
        "showdown" to (st.showdown?.let { sd ->
            o("key" to s(sd.key), "context" to s(sd.context), "scenes" to JsonArray(sd.scenes.map { sc ->
                o("id" to n(sc.scene.id), "name" to s(sc.nameSegments.plainText()), "label" to s(sc.scene.label),
                  "motion" to s(sc.scene.motion.id), "cards" to cards(sc.scene.cards),
                  "highlights" to JsonArray(sc.scene.highlights.map { JsonPrimitive(it) }), "explanation" to s(sc.scene.explanation),
                  "amount" to n(sc.scene.amount), "isWinner" to b(sc.isWinner), "statusText" to s(sc.statusText),
                  "footerText" to s(sc.footerText), "a11y" to s(sc.a11y))
            }))
        } ?: JsonNull),
        "potDetails" to st.potDetails.let { pd ->
            o("open" to b(pd.open), "settled" to b(pd.settled), "title" to s(pd.title), "note" to s(pd.note),
              "pots" to JsonArray(pd.pots.map { p ->
                  o("index" to n(p.index), "label" to s(p.label), "amount" to n(p.amount), "amountText" to s(p.amountText),
                    "eligibilityLabel" to s(p.eligibilityLabel), "heroEligible" to b(p.heroEligible),
                    "contributions" to JsonArray(p.contributions.map { c -> o("playerId" to n(c.playerId), "text" to s(c.text), "amount" to n(c.amount)) }),
                    "splitTotalText" to s(p.splitTotalText),
                    "awards" to JsonArray(p.awards.map { a ->
                        o("playerId" to n(a.playerId), "name" to s(a.name), "winnerText" to s(a.winnerText), "label" to s(a.label), "amountText" to s(a.amountText))
                    }),
                    "distributionEligibility" to s(p.distributionEligibility), "oddChipNote" to s(p.oddChipNote),
                    "expanded" to b(p.expanded), "playerCountText" to s(p.playerCountText), "participantsText" to s(p.participantsText))
              }),
              "refunds" to JsonArray(pd.refunds.map { r ->
                  o("playerId" to n(r.playerId), "amount" to n(r.amount), "text" to s(r.text), "a11y" to s(r.a11y), "returned" to b(r.returned))
              }))
        },
        "opponents" to o("text" to s(st.opponents.text), "changePending" to b(st.opponents.changePending), "changeNote" to s(st.opponents.changeNote)),
        "opponentsDialog" to (st.opponentsDialog?.let { d ->
            o("emotionMode" to s(d.emotionMode.id), "selectedProfile" to s(d.selectedProfile), "detailName" to s(d.detail.profile.name),
              "sizingText" to s(d.detail.sizingText),
              "roster" to JsonArray(d.roster.map { r ->
                  o("id" to n(r.id), "name" to s(r.name), "offTable" to b(r.offTable), "subtitle" to s(r.subtitle),
                    "assignment" to s(r.assignment), "currentStyle" to s(r.currentStyle), "observed" to s(r.observed))
              }))
        } ?: JsonNull),
        "review" to st.review.let { r ->
            o("buttonVisible" to b(r.buttonVisible), "dialogOpen" to b(r.dialogOpen), "key" to s(r.key),
              "status" to s(r.status.name.lowercase()), "progress" to n(r.progress), "selected" to n(r.selected),
              "perspective" to s(r.perspective.name.lowercase()), "jobId" to n(r.jobId),
              "decisions" to n(r.input?.decisions?.size ?: 0), "opponentRecords" to n(r.opponentRecords.size))
        },
        "settings" to st.settings.let { se ->
            o("requestedSeatCount" to n(se.requestedSeatCount), "tableChangeNote" to s(se.tableChangeNote),
              "difficulty" to s(se.difficulty.id), "hints" to b(se.hints), "sound" to b(se.sound), "soundA11y" to s(se.soundA11y),
              "soundTitle" to s(se.soundTitle),
              "seatCountOptions" to JsonArray(se.seatCountOptions.map { JsonPrimitive(it.label) }),
              "difficultyOptions" to JsonArray(se.difficultyOptions.map { JsonPrimitive(it.label) }),
              "emotionOptions" to JsonArray(se.emotionOptions.map { JsonPrimitive(it.label) }))
        },
        "finishing" to b(st.finishing),
        "backgrounded" to b(st.backgrounded),
    )

    private fun seat(p: SeatState): JsonObject = o(
        "id" to n(p.id), "name" to s(p.name), "layoutX" to JsonPrimitive(p.layoutX), "layoutY" to JsonPrimitive(p.layoutY),
        "position" to s(p.position.code), "positionName" to s(p.position.name), "folded" to b(p.folded), "isActor" to b(p.isActor),
        "isWinner" to b(p.isWinner), "revealed" to b(p.revealed), "cards" to JsonArray(p.cards.map { face(it) }),
        "cardBacks" to n(p.cardBacks), "dealAnimation" to b(p.dealAnimation),
        "cardBackDelaysMs" to JsonArray(p.cardBackDelaysMs.map { JsonPrimitive(it) }), "badge" to badge(p.badge),
        "avatar" to s(p.avatar), "avatarTitle" to s(p.avatarTitle), "profileId" to s(p.profileId), "styleShort" to s(p.styleShort),
        "styleTitle" to s(p.styleTitle), "styleA11y" to s(p.styleA11y), "mood" to s(p.mood.id), "moodLabel" to s(p.moodLabel),
        "stack" to n(p.stack), "stackText" to s(p.stackText),
        "peek" to (p.peek?.let { o("pressed" to b(it.pressed), "title" to s(it.title), "a11y" to s(it.a11y)) } ?: JsonNull),
        "action" to chip(p.action), "actionA11y" to s(p.actionA11y),
    )

    private fun chip(c: ActionChip): JsonObject = o(
        "label" to s(c.label), "amount" to (c.amount?.let { n(it) } ?: JsonNull), "amountText" to s(c.amountText),
        "meaning" to s(c.meaning), "isDeciding" to b(c.isDeciding),
    )

    private fun badge(r: RankBadge?): JsonElement =
        r?.let { o("text" to s(it.text), "isWinner" to b(it.isWinner), "a11y" to s(it.a11y), "title" to s(it.title)) } ?: JsonNull

    private fun face(c: CardFace): JsonObject =
        o("card" to s(c.card.key), "best" to b(c.best), "animate" to b(c.animate), "delayMs" to n(c.delayMs))

    private fun cards(cs: List<Card>) = JsonArray(cs.map { JsonPrimitive(it.key) })
    private fun o(vararg pairs: Pair<String, JsonElement>) = JsonObject(linkedMapOf(*pairs))
    private fun n(v: Number) = JsonPrimitive(v)
    private fun s(v: String?): JsonElement = if (v == null) JsonNull else JsonPrimitive(v)
    private fun b(v: Boolean) = JsonPrimitive(v)
}
