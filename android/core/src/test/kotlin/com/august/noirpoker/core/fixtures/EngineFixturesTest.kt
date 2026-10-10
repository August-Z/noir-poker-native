package com.august.noirpoker.core.fixtures

import com.august.noirpoker.core.BotPlan
import com.august.noirpoker.core.Difficulty
import com.august.noirpoker.core.EmotionMode
import com.august.noirpoker.core.Game
import com.august.noirpoker.core.GameStats
import com.august.noirpoker.core.LabelStep
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.PokerException
import com.august.noirpoker.core.RandomSource
import com.august.noirpoker.core.act
import com.august.noirpoker.core.actionLabel
import com.august.noirpoker.core.advanceStreet
import com.august.noirpoker.core.applyBotSettings
import com.august.noirpoker.core.botDecision
import com.august.noirpoker.core.botThinkingTime
import com.august.noirpoker.core.canRestartHand
import com.august.noirpoker.core.completeBoardForPractice
import com.august.noirpoker.core.contestableAfterCall
import com.august.noirpoker.core.currentPots
import com.august.noirpoker.core.executeBotTurn
import com.august.noirpoker.core.historyActionLabel
import com.august.noirpoker.core.labelStep
import com.august.noirpoker.core.legalActions
import com.august.noirpoker.core.newGame
import com.august.noirpoker.core.nextBetLevel
import com.august.noirpoker.core.partitionPots
import com.august.noirpoker.core.planBotTurn
import com.august.noirpoker.core.potSize
import com.august.noirpoker.core.restartHand
import com.august.noirpoker.core.seatPosition
import com.august.noirpoker.core.settle
import com.august.noirpoker.core.startHand
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test

fun phaseOf(id: String): Phase = Phase.entries.first { it.id == id }
fun difficultyOf(id: String): Difficulty = Difficulty.fromId(id) ?: error("difficulty $id")
fun modeOf(id: String): EmotionMode = EmotionMode.fromId(id) ?: error("mode $id")

/** The generator's full public snapshot. */
fun snapshotJson(g: Game, draws: Int): JsonObject = jObj(
    "hand" to j(g.hand),
    "phase" to j(g.phase.id),
    "street" to j(g.street),
    "dealer" to j(g.dealer),
    "actor" to j(g.actor),
    "pending" to jInts(g.pending),
    "currentBet" to j(g.currentBet),
    "minRaise" to j(g.minRaise),
    "board" to jCards(g.board),
    "practiceBoard" to (g.practiceBoard?.let(::jCards) ?: JsonNull),
    "deckSize" to j(g.deck.size),
    "revealed" to j(g.revealed),
    "showdown" to j(g.showdown),
    "replayAttempt" to j(g.replayAttempt),
    "potAtShowdown" to j(g.potAtShowdown),
    "potSize" to j(potSize(g)),
    "difficulty" to j(g.difficulty.id),
    "emotionMode" to j(g.emotionMode.id),
    "canRestartHand" to j(canRestartHand(g)),
    "positions" to jStrings(g.players.map { seatPosition(g, it.id) }),
    "players" to JsonArray(g.players.map(::playerJson)),
    "legal" to legalJson(legalActions(g)),
    "currentPots" to potSetJson(currentPots(g)),
    "pots" to JsonArray(g.pots.map(::potJson)),
    "refunds" to refundsJson(g.refunds),
    "payouts" to jInts(g.payouts),
    "winners" to JsonArray(g.winners.map(::winnerJson)),
    "result" to j(g.result),
    "stats" to jObj("hands" to j(g.stats.hands), "wins" to j(g.stats.wins), "buyin" to j(g.stats.buyin)),
    "history" to JsonArray(g.history.map(::historyJson)),
    "logs" to JsonArray(g.logs.map(::logJson)),
    "decisionCount" to j(g.decisions.size),
    "botDecisionCount" to j(g.botDecisions.size),
    "randomDraws" to j(draws),
)

/** Applies a `patch` step: direct field assignment, no validation. */
fun applyPatch(g: Game, step: JsonObject) {
    step.opt("game")?.obj?.forEach { (k, v) ->
        when (k) {
            "board" -> g.board = cardsOf(v)
            "deck" -> g.deck = cardsOf(v)
            "practiceBoard" -> g.practiceBoard = if (v.isNull) null else cardsOf(v)
            "stats" -> g.stats = GameStats(v.obj.getValue("hands").i, v.obj.getValue("wins").i, v.obj.getValue("buyin").i)
            "dealer" -> g.dealer = v.i
            "phase" -> g.phase = phaseOf(v.str)
            "street" -> g.street = v.i
            "currentBet" -> g.currentBet = v.i
            "minRaise" -> g.minRaise = v.i
            "pending" -> g.pending = v.arr.map { it.i }.toMutableList()
            "actor" -> g.actor = v.i
            "difficulty" -> g.difficulty = difficultyOf(v.str)
            else -> error("unsupported game patch field $k")
        }
    }
    step.opt("players")?.arr?.forEach { entry ->
        val p = g.players[entry.obj.getValue("id").i]
        for ((k, v) in entry.obj) {
            when (k) {
                "id" -> {}
                "hole" -> p.hole = cardsOf(v)
                "stack" -> p.stack = v.i
                "bet" -> p.bet = v.i
                "total" -> p.total = v.i
                "folded" -> p.folded = v.b
                "allin" -> p.allin = v.b
                "actedTo" -> p.actedTo = if (v.isNull) null else v.i
                else -> error("unsupported player patch field $k")
            }
        }
    }
}

/**
 * Applies a snapshot delta to the previous expected full snapshot.
 *
 * Additions extend the value already merged into `next`, and a whole-array
 * `logs` / `history` replacement wins over additions in the same delta,
 * independent of key order (the same rule as the iOS harness).
 */
fun applyDelta(previous: JsonObject, delta: JsonObject): JsonObject {
    val next = LinkedHashMap(previous)
    for ((k, v) in delta) {
        when (k) {
            "players" -> {
                val players = next.getValue("players").arr.map { LinkedHashMap(it.obj) }.toMutableList()
                for (entry in v.arr) {
                    val id = entry.obj.getValue("id").i
                    val target = players.firstOrNull { it.getValue("id").i == id }
                        ?: error("snapshot delta names unknown seat $id")
                    for ((f, value) in entry.obj) target[f] = value
                }
                next["players"] = JsonArray(players.map { JsonObject(it) })
            }
            "logsAdded" -> next["logs"] = JsonArray(v.arr + next.getValue("logs").arr)
            "historyAdded" -> next["history"] = JsonArray(next.getValue("history").arr + v.arr)
            else -> next[k] = v
        }
    }
    delta["logs"]?.let { next["logs"] = it }
    delta["history"]?.let { next["history"] = it }
    return JsonObject(next)
}

/** Builds a game from a declarative `state` (bot-decisions.json). */
fun gameFromState(state: JsonObject): Game {
    val players = state.getValue("players").arr
    val g = newGame(players.size)
    g.hand = state.getValue("hand").i
    g.phase = phaseOf(state.getValue("phase").str)
    g.street = state.getValue("street").i
    g.dealer = state.getValue("dealer").i
    g.actor = state.getValue("actor").i
    g.pending = state.getValue("pending").arr.map { it.i }.toMutableList()
    g.currentBet = state.getValue("currentBet").i
    g.minRaise = state.getValue("minRaise").i
    g.board = cardsOf(state.getValue("board"))
    g.difficulty = difficultyOf(state.getValue("difficulty").str)
    g.emotionMode = modeOf(state.getValue("emotionMode").str)
    g.replayAttempt = state.getValue("replayAttempt").i
    g.history = historyOf(state.getValue("history"))
    for (e in players) {
        val o = e.obj
        val p = g.players[o.getValue("id").i]
        p.name = o.getValue("name").str
        p.stack = o.getValue("stack").i
        p.bet = o.getValue("bet").i
        p.total = o.getValue("total").i
        p.folded = o.getValue("folded").b
        p.allin = o.getValue("allin").b
        p.actedTo = o.opt("actedTo")?.i
        p.checked = o.getValue("checked").b
        p.action = o.getValue("action").str
        p.hole = cardsOf(o.getValue("hole"))
        p.botProfile = o.getValue("botProfile").str
        p.botMood = moodOf(o.getValue("botMood"))
    }
    return g
}

class EngineFixturesTest {
    @Test
    fun `bot-decisions fixture`() {
        val report = FixtureReport("bot-decisions.json")
        val root = loadFixture("bot-decisions.json")
        for (c in root.getValue("cases").arr) {
            val o = c.obj
            report.case(o.getValue("name").str) {
                val g = gameFromState(o.getValue("state").obj)
                val random = CountingRandom(o.getValue("decisionSeed").jsonLong())
                val decision = botDecision(g, random, o.opt("trials")?.i)
                val trace = traceJson(decision.trace, withView = false)
                val view = viewJson(decision.trace.view!!, full = false)
                val timing = CountingRandom(o.getValue("timingSeed").jsonLong())
                val thinking = botThinkingTime(decision, timing)
                jsonDiff(o.getValue("decision"), decisionResultJson(decision), "decision")
                    ?: jsonDiff(o.getValue("trace"), trace, "trace")
                    ?: jsonDiff(o.getValue("view"), view, "view")
                    ?: jsonDiff(o.getValue("decisionDraws"), j(random.draws), "decisionDraws")
                    ?: jsonDiff(o.getValue("thinking"), thinkingJson(thinking), "thinking")
                    ?: jsonDiff(o.getValue("timingDraws"), j(timing.draws), "timingDraws")
            }
        }
        root.getValue("errors").arr.forEachIndexed { index, c ->
            val o = c.obj
            report.case("error ${index + 1}") {
                val g = gameFromState(o.getValue("state").obj)
                val code = try {
                    botDecision(g, com.august.noirpoker.core.SeededRandom(1), o.opt("trials")?.i)
                    null
                } catch (e: PokerException) {
                    e.code
                }
                jsonDiff(o.getValue("error"), j(code), "error")
            }
        }
        report.finish()
    }

    // ------------------------------------------------------------------
    // engine-scenarios.json
    // ------------------------------------------------------------------

    private class Replay(val seed: Long, val playerCount: Int) {
        val rng = CountingRandom(seed)
        val g: Game = newGame(playerCount)

        /** The plan held by the last `planBotTurn` step, for `executeBotTurn`. */
        var plan: BotPlan? = null
    }

    /** Runs one operation; returns the op's `result` JSON when it has one. */
    private fun perform(r: Replay, op: JsonObject): JsonElement? {
        val g = r.g
        return when (val name = op.getValue("op").str) {
            "patch" -> {
                applyPatch(g, op)
                null
            }
            "newGame" -> {
                newGame(op.getValue("playerCount").i)
                null
            }
            "startHand" -> {
                val constant = op.opt("randomConstant")?.d
                startHand(g, if (constant != null) RandomSource { constant } else r.rng)
                null
            }
            "act" -> {
                act(g, op.getValue("id").i, op.getValue("action").str, op.opt("amount")?.i)
                null
            }
            "advanceStreet" -> {
                advanceStreet(g)
                null
            }
            "settle" -> {
                settle(g, op.opt("showdown")?.b ?: true)
                null
            }
            "restartHand" -> {
                restartHand(g)
                null
            }
            "completeBoardForPractice" -> {
                completeBoardForPractice(g)
                null
            }
            "applyBotSettings" -> {
                applyBotSettings(g, toPlain(op.getValue("settings")))
                null
            }
            "planBotTurn" -> {
                val plan = planBotTurn(g, r.rng, r.rng)
                r.plan = plan
                jObj("delayMs" to j(plan.delayMs))
            }
            "executeBotTurn" -> {
                executeBotTurn(g, r.plan ?: error("executeBotTurn without a held plan"), expedited = false, waitedMs = 0)
                null
            }
            "botAct" -> {
                val id = g.actor
                val d = botDecision(g, r.rng)
                act(g, id, d.action, d.amount)
                val m = linkedMapOf<String, JsonElement>("id" to j(id), "action" to j(d.action.id))
                if (d.amount != null) m["amount"] = j(d.amount)
                m["reason"] = j(d.trace.reason)
                JsonObject(m)
            }
            "botTurn" -> {
                val plan = planBotTurn(g, r.rng, r.rng)
                executeBotTurn(g, plan, expedited = false, waitedMs = 0)
                jObj("delayMs" to j(plan.delayMs))
            }
            else -> error("unknown op $name")
        }
    }

    private fun query(g: Game, fn: String, args: JsonObject): JsonElement = when (fn) {
        "partitionPots" -> potSetJson(partitionPots(g))
        "contestableAfterCall" -> j(contestableAfterCall(g, args.getValue("id").i, args.getValue("amount").i))
        "legalActions" -> legalJson(legalActions(g, args.getValue("id").i))
        "nextBetLevel" -> j(nextBetLevel(g))
        "raiseLabel" -> {
            val legal = legalActions(g)
            // The reference passes the whole game: no `stack` field.
            j(actionLabel(LabelStep(g.street, g.history.toList(), g.currentBet, g.minRaise, legal), com.august.noirpoker.core.Action.RAISE, args.getValue("amount").i))
        }
        "historyActionLabel" -> j(historyActionLabel(g.history, args.getValue("index").i))
        "decisionActionLabel" -> {
            val d = g.decisions[args.getValue("index").i]
            val step = d.labelStep()
            val action = args.opt("action")?.str?.let(::actionOf) ?: step.action
            val amount = args.opt("amount")?.d ?: step.amount
            j(actionLabel(step, action, amount))
        }
        else -> error("unknown query $fn")
    }

    @Test
    fun `engine-scenarios fixture`() {
        val report = FixtureReport("engine-scenarios.json")
        val root = loadFixture("engine-scenarios.json")
        val messages = root.getValue("errors").obj
        report.case("error messages") {
            val actual = JsonObject(com.august.noirpoker.core.EngineError.entries.associate { it.code to j(it.message) })
            jsonDiff(messages, actual, "errors")
        }
        for (c in root.getValue("cases").arr) {
            val o = c.obj
            report.case(o.getValue("name").str) {
                val r = Replay(o.getValue("seed").jsonLong(), o.getValue("playerCount").i)
                var expected = o.getValue("initial").obj
                var problem = jsonDiff(expected, snapshotJson(r.g, r.rng.draws), "initial")
                for ((k, s) in o.getValue("steps").arr.withIndex()) {
                    if (problem != null) break
                    val step = s.obj
                    val opName = step.getValue("op").str
                    val label = "step ${k + 1} ($opName${if (opName == "expectError") " " + step.getValue("step").obj.getValue("op").str else ""})"
                    val decisions = r.g.decisions.size
                    val botDecisions = r.g.botDecisions.size
                    when (opName) {
                        "query" -> {
                            problem = jsonDiff(
                                step.getValue("result"),
                                query(r.g, step.getValue("fn").str, step.opt("args")?.obj ?: JsonObject(emptyMap())),
                                "$label.result",
                            )
                            continue
                        }
                        "expectError" -> {
                            val before = r.g.deepCopy()
                            val draws = r.rng.draws
                            val heldPlan = r.plan
                            val code = try {
                                perform(r, step.getValue("step").obj)
                                null
                            } catch (e: PokerException) {
                                e.code
                            }
                            problem = jsonDiff(step.getValue("error"), j(code), "$label.error")
                            if (problem == null && !r.g.sameState(before)) problem = "$label: rejected call changed the game"
                            if (problem == null && r.rng.draws != draws) problem = "$label: rejected call drew random values"
                            if (problem == null && r.plan !== heldPlan) problem = "$label: rejected call replaced the held bot plan"
                        }
                        else -> {
                            val result = perform(r, step)
                            if (step.containsKey("result")) problem = jsonDiff(step["result"], result, "$label.result")
                        }
                    }
                    if (problem != null) break
                    step.opt("decision")?.let { exp ->
                        problem = if (r.g.decisions.size <= decisions) {
                            "$label: expected a hero decision snapshot"
                        } else {
                            jsonDiff(exp, decisionJson(r.g.decisions.last()), "$label.decision")
                        }
                    }
                    if (problem != null) break
                    step.opt("botDecision")?.let { exp ->
                        problem = if (r.g.botDecisions.size <= botDecisions) {
                            "$label: expected a bot decision record"
                        } else {
                            jsonDiff(exp, botRecordJson(r.g.botDecisions.last()), "$label.botDecision")
                        }
                    }
                    if (problem != null) break
                    // A step without a snapshot delta must leave the public snapshot unchanged.
                    expected = applyDelta(expected, step.opt("snapshot")?.obj ?: JsonObject(emptyMap()))
                    problem = jsonDiff(expected, snapshotJson(r.g, r.rng.draws), "$label.snapshot")
                }
                problem
            }
        }
        report.finish()
    }

    // ------------------------------------------------------------------
    // simulations.json
    // ------------------------------------------------------------------

    @Test
    fun `simulations fixture`() {
        val report = FixtureReport("simulations.json")
        for (c in loadFixture("simulations.json").getValue("cases").arr) {
            val o = c.obj
            report.case(o.getValue("name").str) {
                val rng = CountingRandom(o.getValue("seed").jsonLong())
                val g = newGame(o.getValue("playerCount").i)
                applyBotSettings(g, toPlain(o.getValue("settings")))
                g.difficulty = difficultyOf(o.getValue("difficulty").str)
                o.opt("stacks")?.arr?.forEachIndexed { i, s -> g.players[i].stack = s.i }
                var problem: String? = null
                for ((h, expectedHand) in o.getValue("hands").arr.withIndex()) {
                    startHand(g, rng)
                    val dealt = linkedMapOf<String, JsonElement>(
                        "hand" to j(g.hand),
                        "dealer" to j(g.dealer),
                        "holes" to JsonArray(g.players.map { jCards(it.hole) }),
                        "stacksAtDeal" to jInts(g.players.map { it.stack + it.bet }),
                        "drawsAfterDeal" to j(rng.draws),
                    )
                    val actions = mutableListOf<JsonElement>()
                    var guard = 0
                    while (g.phase != Phase.DONE) {
                        check(++guard <= 500) { "simulation stalled" }
                        if (g.phase == Phase.BETWEEN) {
                            advanceStreet(g)
                            continue
                        }
                        val id = g.actor
                        val m = linkedMapOf<String, JsonElement>("id" to j(id))
                        if (id == 0) {
                            val d = botDecision(g, rng)
                            act(g, 0, d.action, d.amount)
                            m["action"] = j(d.action.id)
                            if (d.amount != null) m["amount"] = j(d.amount)
                            m["reason"] = j(d.trace.reason)
                        } else {
                            val plan = planBotTurn(g, rng, rng)
                            val d = executeBotTurn(g, plan)
                            m["action"] = j(d.action.id)
                            if (d.amount != null) m["amount"] = j(d.amount)
                            m["reason"] = j(d.trace.reason)
                            m["delayMs"] = j(plan.delayMs)
                        }
                        m["draws"] = j(rng.draws)
                        actions.add(JsonObject(m))
                    }
                    val actual = JsonObject(
                        dealt + linkedMapOf(
                            "board" to jCards(g.board),
                            "history" to JsonArray(g.history.map(::historyJson)),
                            "actions" to JsonArray(actions),
                            "showdown" to j(g.showdown),
                            "pots" to JsonArray(g.pots.map(::potJson)),
                            "refunds" to refundsJson(g.refunds),
                            "payouts" to jInts(g.payouts),
                            "winners" to JsonArray(g.winners.map(::winnerJson)),
                            "result" to j(g.result),
                            "stacks" to jInts(g.players.map { it.stack }),
                            "totalChips" to j(g.players.sumOf { it.stack }),
                            "stats" to jObj("hands" to j(g.stats.hands), "wins" to j(g.stats.wins), "buyin" to j(g.stats.buyin)),
                            "botStats" to JsonArray(g.players.map(::statsJson)),
                            "moods" to JsonArray(g.players.map { moodJson(it.botMood) }),
                            "decisions" to j(g.decisions.size),
                            "thinkingMs" to jInts(g.botDecisions.map { it.trace.thinking!!.durationMs }),
                            "logs" to JsonArray(g.logs.map(::logJson)),
                            "drawsAfterHand" to j(rng.draws),
                        ),
                    )
                    problem = jsonDiff(expectedHand, actual, "hands[$h]")
                    if (problem != null) break
                }
                problem
            }
        }
        report.finish()
    }
}
