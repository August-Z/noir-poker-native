package com.august.noirpoker.core.review

import com.august.noirpoker.core.DecisionSnapshot
import com.august.noirpoker.core.EmotionMode
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.SnapshotPlayer
import com.august.noirpoker.core.actionLabel
import com.august.noirpoker.core.fixtures.arr
import com.august.noirpoker.core.fixtures.b
import com.august.noirpoker.core.fixtures.d
import com.august.noirpoker.core.fixtures.fixtureDir
import com.august.noirpoker.core.fixtures.i
import com.august.noirpoker.core.fixtures.jCards
import com.august.noirpoker.core.fixtures.jObj
import com.august.noirpoker.core.fixtures.jStrings
import com.august.noirpoker.core.fixtures.jsonDiff
import com.august.noirpoker.core.fixtures.loadFixture
import com.august.noirpoker.core.fixtures.obj
import com.august.noirpoker.core.fixtures.opt
import com.august.noirpoker.core.fixtures.str
import com.august.noirpoker.core.labelStep
import com.august.noirpoker.core.session.HandReviewInput
import com.august.noirpoker.core.session.ReviewAward
import com.august.noirpoker.core.session.ReviewPot
import com.august.noirpoker.core.session.ReviewOutcome as SessionOutcome
import com.august.noirpoker.core.session.Harness
import com.august.noirpoker.core.session.ReviewPerspective
import com.august.noirpoker.core.session.ReviewState
import com.august.noirpoker.core.session.ReviewStatus as JobStatus
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

class ReviewDialogTest {
    /** Plays hands with the real bots (hero calls or checks) until one with hero decisions and bot records settles. */
    private fun playedHand(): Harness {
        val h = Harness(seed = 7)
        h.session.start()
        repeat(20) {
            var guard = 0
            while (h.game.phase != Phase.DONE && guard++ < 200) {
                if (h.game.phase == Phase.PLAYING && h.game.actor == 0) h.session.callOrCheck() else h.runBots()
                if (h.game.phase != Phase.DONE && h.scheduler.nextDueAt == null && h.game.actor != 0) break
            }
            val input = h.state.review.input
            if (input != null && input.decisions.size >= 2 && input.opponents.isNotEmpty()) return h
            h.session.nextHand()
        }
        error("No reviewable hand within 20 hands")
    }

    private fun analyzed(review: ReviewState): ReviewState {
        val input = assertNotNull(review.input)
        val analysis = analyzeHeroReview(input.heroInput, trials = 40)
        return review.copy(status = JobStatus.DONE, analysis = analysis, selected = analysis.priorityIndex)
    }

    @Test
    fun `before analysis the hero panel shows placeholders and pending steps`() {
        val review = playedHand().state.review
        val view = assertNotNull(presentHeroReview(review))
        val input = assertNotNull(review.input)
        assertEquals("Hand #${input.hand} · Review", view.title)
        assertEquals(ReviewDialogCopy.statePreparing, view.stateText)
        assertEquals(ReviewDialogCopy.summaryTitleDefault, view.summaryTitle)
        assertNull(view.priorityButton)
        assertEquals(input.decisions.size, view.timeline.size)
        assertTrue(view.timeline.all { it.chip == ReviewDialogCopy.statusPending && it.tone == ReviewTone.PENDING })
        val step = assertNotNull(view.step)
        assertEquals(ReviewDialogCopy.statusAnalyzing, step.statusText)
        assertEquals(ReviewDialogCopy.simRunning, step.simulationNote)
        assertEquals(ReviewDialogCopy.suggestionPending, step.suggestion)
        assertTrue(step.evidence.isEmpty())
        assertNull(step.modelNote)
        assertEquals(ReviewDialogCopy.priceNoteDefault, step.priceNote)
        assertEquals(listOf(ReviewDialogCopy.metricRequired, ReviewDialogCopy.metricEquity, ReviewDialogCopy.metricContestable), step.metrics.map { it.label })
        val first = input.decisions[0]
        assertEquals(actionLabel(first.labelStep()), step.yourChoice)
        assertEquals(first.hole, step.scene.hole)
    }

    @Test
    fun `progress and errors use the reference status lines`() {
        val review = playedHand().state.review
        val n = assertNotNull(review.input).decisions.size
        val running = assertNotNull(presentHeroReview(review.copy(status = JobStatus.RUNNING, progress = 1)))
        assertEquals("Analyzing decision 1 of $n…", running.stateText)
        assertTrue(running.running)
        val failed = assertNotNull(presentHeroReview(review.copy(status = JobStatus.ERROR)))
        assertEquals(ReviewDialogCopy.stateError, failed.stateText)
        assertTrue(failed.retryVisible)
    }

    @Test
    fun `the finished analysis fills every step from the summary`() {
        val review = analyzed(playedHand().state.review)
        val summary = (review.analysis as HeroReviewAnalysis).summary
        val view = assertNotNull(presentHeroReview(review))
        assertEquals(summary.summary, view.stateText)
        assertEquals(summary.title, view.summaryTitle)
        assertNotNull(view.priorityButton)
        assertEquals(summary.priorityIndex, view.priorityIndex)
        view.timeline.forEachIndexed { i, item -> assertEquals(ReviewDialogCopy.status(summary.steps[i].status), item.chip) }
        val step = assertNotNull(view.step)
        val result = summary.steps[review.selected]
        assertEquals(result.recommendation, step.suggestion)
        assertEquals(result.evidence, step.evidence)
        assertEquals(listOfNotNull(result.routes.primary, result.routes.secondary).size, step.routes.size)
        assertEquals(ReviewDialogCopy.routePrimary, step.routes[0].kicker)
        val sim = result.simulation
        if (sim != null) {
            val table = assertNotNull(step.simulation)
            assertEquals(sim.rows.size, table.rows.size)
            assertEquals(ReviewDialogCopy.simCaption(sim.trials), table.caption)
            assertTrue(table.rows.all { it.cells.size == 2 && it.cells.all { c -> c.margin.startsWith("≈ ±") } })
            assertNull(step.simulationNote)
        }
        val note = assertNotNull(step.modelNote)
        assertTrue(note.contains("Random / action-weighted equity:"))
        assertTrue(note.contains("${result.metrics.trials}"))
        assertEquals("${review.selected + 1} / ${view.timeline.size}", step.position)
    }

    @Test
    fun `the hero panel never shows opponents' hole cards`() {
        val review = analyzed(playedHand().state.review)
        val input = assertNotNull(review.input)
        val heroCards = input.hole.toSet()
        input.decisions.indices.forEach { i ->
            val step = assertNotNull(presentHeroReview(review.copy(selected = i))?.step)
            assertEquals(heroCards, step.scene.hole.toSet())
            assertEquals(input.decisions[i].board, step.scene.board)
        }
    }

    @Test
    fun `the opponent panel explains executed records with a filter`() {
        val h = playedHand()
        val review = h.state.review
        val input = assertNotNull(review.input)
        val view = assertNotNull(presentOpponentReview(review))
        assertEquals(ReviewDialogCopy.oppFilterAll, view.filterOptions[0].label)
        assertNull(view.filterOptions[0].value)
        assertEquals(input.opponents.map { it.id }.distinct(), view.filterOptions.drop(1).map { it.value })
        assertEquals(input.opponents.size, view.timeline.size)
        val record = input.opponents[0]
        val step = assertNotNull(view.step)
        assertEquals(explainOpponent(record).title, step.explanationTitle)
        assertEquals(record.trace.view!!.hole, step.scene.hole)
        assertEquals(ReviewDialogCopy.oppPublicAction(record.sequence), step.position)
        assertEquals("${record.sequence}", view.timeline[0].number)
        assertFalse(step.canPrevious)
        assertEquals(record.trace.checks.size, step.branches.size)

        val seat = record.id
        h.session.setOpponentReviewFilter(seat)
        val filtered = assertNotNull(presentOpponentReview(h.state.review))
        assertEquals(input.opponents.count { it.id == seat }, filtered.timeline.size)
        assertEquals(record.name, filtered.filterText)
    }

    @Test
    fun `an empty opponent selection shows the no-records note`() {
        val review = playedHand().state.review.copy(opponentRecords = emptyList())
        val view = assertNotNull(presentOpponentReview(review))
        assertNull(view.step)
        assertEquals(ReviewDialogCopy.oppEmpty, view.empty)
        assertEquals("0 actions", view.count)
    }

    @Test
    fun `formatting follows the reference rules`() {
        assertEquals("-150 chips", ReviewDialogCopy.change(-150))
        assertEquals("+1,200 chips", ReviewDialogCopy.change(1200))
        assertEquals("0 chips", ReviewDialogCopy.change(0))
        assertEquals("+0", reviewSigned(0.3))
        assertEquals("-1,084", reviewSigned(-1084.2))
        assertEquals("≈ ±1,214", ReviewDialogCopy.simMargin(1213.6))
        assertEquals("0.123 / threshold 12.5% · Hit", ReviewDialogCopy.oppBranch(0.1234, 0.125, true))
        assertEquals("1 action", ReviewDialogCopy.actionCount(1))
        assertEquals("34%", reviewPercent(0.336))
    }

    @Test
    fun `a running flag only while the job runs`() {
        val review = playedHand().state.review
        // After a background pause the job is idle with the dialog open: no spinner.
        val paused = assertNotNull(presentHeroReview(review.copy(status = JobStatus.IDLE, progress = 1)))
        assertFalse(paused.running)
        assertEquals(ReviewDialogCopy.statePreparing, paused.stateText)
        assertTrue(assertNotNull(presentHeroReview(review.copy(status = JobStatus.RUNNING))).running)
        assertFalse(assertNotNull(presentHeroReview(analyzed(review))).running)
    }

    @Test
    fun `a bot record without a view still renders in the opponent panel`() {
        val review = playedHand().state.review
        val record = review.opponentRecords.first()
        val bare = record.copy(trace = record.trace.copy(view = null))
        val view = assertNotNull(presentOpponentReview(review.copy(opponentRecords = listOf(bare), opponentSelected = 0)))
        val step = assertNotNull(view.step)
        assertTrue(step.scene.hole.isEmpty())
        assertTrue(step.scene.board.isEmpty())
        assertEquals("${record.name} · Preflop", step.title)
        assertEquals(actionLabel(bare.labelStep()), step.choice)
        assertEquals(1, view.timeline.size)
    }

    @Test
    fun `presenter output matches the shared review dialog fixture`() {
        val fixture = loadFixture("review-dialog.json")
        val record = System.getenv("NOIR_REVIEW_DIALOG_RECORD")
        val hands = loadFixture("review-hands.json")
        val trials = fixture.getValue("trials").i
        val failures = mutableListOf<String>()
        fun check(label: String, expected: JsonElement?, actual: JsonElement) {
            if (record == null) jsonDiff(expected, actual)?.let { failures.add("$label: $it") }
        }

        val copy = dialogCopyJson()
        val expectedCopy = fixture.getValue("copy").obj
        assertEquals(expectedCopy.keys, copy.keys, "copy keys")
        copy.forEach { (k, v) -> check("copy.$k", expectedCopy[k], v) }
        val templates = fixture.getValue("templates").arr.map { t ->
            val o = t.obj
            val result = dialogTemplate(o.getValue("fn").str, o.getValue("args").arr)
            check("template ${o.getValue("fn").str}${o.getValue("args")}", o["result"], JsonPrimitive(result))
            JsonObject(o + ("result" to JsonPrimitive(result)))
        }

        val analyses = HashMap<String, HeroReviewAnalysis>()
        val cases = fixture.getValue("cases").arr.map { c ->
            val o = c.obj
            val name = o.getValue("name").str
            val source = hands.getValue(o.getValue("source").str).arr.first { it.obj.getValue("name").str == o.getValue("input").str }
            val input = reviewInputOf(source.obj.getValue("input")).toHandReviewInput()
            val state = dialogState(input, o.getValue("state").obj) { analyses.getOrPut(o.getValue("input").str) { analyzeHeroReview(input.heroInput, trials) } }
            val panel = o.getValue("panel").str
            val actual = if (panel == "hero") heroJson(assertNotNull(presentHeroReview(state))) else opponentJson(assertNotNull(presentOpponentReview(state)))
            check(name, o[panel], actual)
            JsonObject(o + (panel to actual))
        }
        if (record != null) {
            val out = JsonObject(fixture + mapOf("copy" to JsonObject(copy), "templates" to JsonArray(templates), "cases" to JsonArray(cases)))
            File(record).writeText(Json.encodeToString(JsonElement.serializer(), out))
            return
        }
        if (failures.isNotEmpty()) fail(failures.take(20).joinToString("\n"))
        assertTrue(File(fixtureDir(), "review-dialog.json").exists())
    }

    @Test
    fun `the hero panel is identical across hidden-card variants`() {
        val privacy = loadFixture("review-hands.json").getValue("privacy").arr
        assertEquals(3, privacy.size)
        for (p in privacy.map { it.obj }) {
            val trials = p.getValue("options").obj.getValue("trials").i
            val views = p.getValue("variants").arr.map { v ->
                val input = reviewInputOf(v).toHandReviewInput()
                val analysis = analyzeHeroReview(input.heroInput, trials)
                input.decisions.indices.map { k ->
                    val state = baseState(input).copy(status = JobStatus.DONE, progress = input.decisions.size, analysis = analysis, selected = k)
                    val hero = assertNotNull(presentHeroReview(state))
                    // The header reports the outcome (chip change and context); everything graded must match.
                    heroJson(hero).filterKeys { it != "change" && it != "context" }
                }
            }
            assertEquals(views[0], views[1], p.getValue("name").str)
        }
    }
}


// ---- review-dialog.json support ---------------------------------------------------

private fun ReviewSeat.toSnapshotPlayer() = SnapshotPlayer(
    id, name, position, stack, bet, total, folded, allin, action,
    state?.botProfile, publicAxes, state?.botMoodKind, state?.actedTo, state?.checked ?: false,
)

/** The engine snapshot behind a fixture decision (fixture hands always carry every key). */
private fun ReviewDecision.toSnapshot() = DecisionSnapshot(
    index, hand, street, position, hole, board, stack, bet, total, pot, currentBet, minRaise,
    requireNotNull(dealer), emotionMode ?: EmotionMode.OFF, legal, pending, action, amount,
    players.map { it.toSnapshotPlayer() }, history,
)

private fun ReviewInput.toHandReviewInput() = HandReviewInput(
    hand, hole, decisions.map { it.toSnapshot() }, opponents,
    SessionOutcome(
        outcome.profit, outcome.paid, outcome.returned, outcome.folded, outcome.wonPot, outcome.board,
        outcome.pots.map { p -> ReviewPot(p.label, p.amount, p.eligible, p.awards.map { ReviewAward(it.name, it.amount, it.label) }) },
        outcome.result,
    ),
)

private fun baseState(input: HandReviewInput) = ReviewState(
    buttonVisible = true, dialogOpen = true, key = "1:${input.hand}", input = input, status = JobStatus.IDLE, progress = 0,
    analysis = null, selected = 0, perspective = ReviewPerspective.HERO, opponentFilter = null, opponentSelected = 0,
    opponentRecords = input.opponents, jobId = 1,
)

private fun dialogState(input: HandReviewInput, s: JsonObject, analysis: () -> HeroReviewAnalysis): ReviewState {
    s.opt("opponentFilter")?.let { f ->
        val seat = f.i
        return baseState(input).copy(
            perspective = ReviewPerspective.OPPONENTS,
            opponentFilter = seat,
            opponentSelected = s.getValue("opponentSelected").i,
            opponentRecords = input.opponents.filter { it.id == seat },
        )
    }
    if (s.containsKey("opponentSelected")) {
        return baseState(input).copy(perspective = ReviewPerspective.OPPONENTS, opponentSelected = s.getValue("opponentSelected").i)
    }
    var result: HeroReviewAnalysis? = if (s.getValue("analyzed").b) analysis() else null
    s.opt("dropSimulation")?.let { k ->
        val r = requireNotNull(result)
        val steps = r.summary.steps.toMutableList()
        steps[k.i] = steps[k.i].copy(simulation = null)
        result = HeroReviewAnalysis(r.summary.copy(steps = steps), r.decisions)
    }
    return baseState(input).copy(
        status = JobStatus.valueOf(s.getValue("status").str.uppercase()),
        progress = s.getValue("progress").i,
        analysis = result,
        selected = s.getValue("selected").i,
    )
}

private fun j(v: String?): JsonElement = if (v == null) JsonNull else JsonPrimitive(v)
private fun j(v: Int?): JsonElement = if (v == null) JsonNull else JsonPrimitive(v)
private fun j(v: Boolean): JsonElement = JsonPrimitive(v)
private fun pairs(v: List<Pair<String, String>>) = JsonArray(v.map { jStrings(listOf(it.first, it.second)) })
private fun tone(t: ReviewTone) = j(t.name.lowercase())

private fun timelineJson(items: List<ReviewTimelineItem>) = JsonArray(
    items.map {
        jObj(
            "number" to j(it.number), "meta" to j(it.meta), "action" to j(it.action), "chip" to j(it.chip),
            "tone" to tone(it.tone), "selected" to j(it.selected), "a11y" to j(it.a11y),
        )
    },
)

private fun heroJson(v: HeroReviewView): JsonObject = jObj(
    "title" to j(v.title), "change" to j(v.change), "context" to j(v.context), "stateText" to j(v.stateText),
    "running" to j(v.running), "progress" to j(v.progress), "total" to j(v.total), "summaryTitle" to j(v.summaryTitle),
    "priorityButton" to j(v.priorityButton), "priorityIndex" to j(v.priorityButton?.let { v.priorityIndex }),
    "retryVisible" to j(v.retryVisible), "stepCount" to j(v.stepCount), "timeline" to timelineJson(v.timeline),
    "empty" to j(v.empty),
    "step" to (
        v.step?.let { s ->
            jObj(
                "title" to j(s.title), "statusText" to j(s.statusText), "tone" to tone(s.tone),
                "hole" to jCards(s.scene.hole), "board" to jCards(s.scene.board),
                "meta" to pairs(s.scene.meta.map { it.label to it.value }),
                "yourChoice" to j(s.yourChoice), "suggestion" to j(s.suggestion),
                "routes" to JsonArray(s.routes.map { jStrings(listOf(it.kicker, it.label, it.condition, it.tradeoff)) }),
                "simulation" to (
                    s.simulation?.let { t ->
                        jObj(
                            "heading" to j(t.heading), "stability" to j(t.stability), "stable" to j(t.stable),
                            "caption" to j(t.caption), "columns" to jStrings(t.columns),
                            "rows" to JsonArray(
                                t.rows.map { r ->
                                    jObj(
                                        "label" to j(r.label),
                                        "cells" to JsonArray(r.cells.map { jStrings(listOf(it.value, it.margin, it.a11y)) }),
                                    )
                                },
                            ),
                            "detailsSummary" to j(t.detailsSummary), "details" to jStrings(t.details),
                        )
                    } ?: JsonNull
                    ),
                "simulationNote" to j(s.simulationNote), "decisionTitle" to j(s.decisionTitle), "reason" to j(s.reason),
                "evidence" to jStrings(s.evidence), "confidence" to j(s.confidence), "lesson" to j(s.lesson), "plan" to j(s.plan),
                "metrics" to pairs(s.metrics.map { it.label to it.value }), "modelNote" to j(s.modelNote),
                "priceNote" to j(s.priceNote), "publicActions" to pairs(s.publicActions.map { it.name to it.label }),
                "publicActionsEmpty" to j(s.publicActionsEmpty), "position" to j(s.position),
                "canPrevious" to j(s.canPrevious), "canNext" to j(s.canNext),
            )
        } ?: JsonNull
        ),
)

private fun opponentJson(v: OpponentReviewView): JsonObject = jObj(
    "filters" to JsonArray(
        v.filterOptions.map { jObj("seat" to j(it.value), "label" to j(it.label), "selected" to j(it.value == v.filter)) },
    ),
    "count" to j(v.count), "timeline" to timelineJson(v.timeline), "empty" to j(v.empty),
    "step" to (
        v.step?.let { s ->
            jObj(
                "title" to j(s.title), "statusText" to j(s.statusText), "tone" to tone(s.tone), "holeLabel" to j(s.scene.holeLabel),
                "hole" to jCards(s.scene.hole), "board" to jCards(s.scene.board),
                "meta" to pairs(s.scene.meta.map { it.label to it.value }),
                "choiceLabel" to j(s.choiceLabel), "choice" to j(s.choice), "explanationTitle" to j(s.explanationTitle),
                "explanation" to j(s.explanation), "profileName" to j(s.profileName), "reasons" to jStrings(s.reasons),
                "warning" to j(s.warning), "branches" to pairs(s.branches.map { it.name to it.value }),
                "branchesEmpty" to j(s.branchesEmpty), "position" to j(s.position),
                "canPrevious" to j(s.canPrevious), "canNext" to j(s.canNext),
            )
        } ?: JsonNull
        ),
)

/** The static dialog copy under the fixture's platform-neutral keys. */
private fun dialogCopyJson(): Map<String, JsonElement> {
    val c = ReviewDialogCopy
    return linkedMapOf(
        "eyebrow" to j(c.eyebrow), "closeA11y" to j(c.closeA11y), "titleDefault" to j(c.titleDefault),
        "tabsA11y" to j(c.tabsA11y), "tabHero" to j(c.tabHero), "tabOpponents" to j(c.tabOpponents),
        "tabOpponentsSubtitle" to j(c.tabOpponentsSubtitle), "timelineA11y" to j(c.timelineA11y),
        "timelineTitle" to j(c.timelineTitle), "contextFolded" to j(c.contextFolded),
        "contextPartialWin" to j(c.contextPartialWin), "contextWon" to j(c.contextWon), "contextLost" to j(c.contextLost),
        "stateError" to j(c.stateError), "statePreparing" to j(c.statePreparing),
        "summaryTitleDefault" to j(c.summaryTitleDefault), "priorityButton" to j(c.priorityButton),
        "fromFirstButton" to j(c.fromFirstButton), "retry" to j(c.retry), "empty" to j(c.empty),
        "statusAttention" to j(c.statusAttention), "statusConsider" to j(c.statusConsider), "statusSound" to j(c.statusSound),
        "statusPending" to j(c.statusPending), "statusAnalyzing" to j(c.statusAnalyzing), "holeLabel" to j(c.holeLabel),
        "boardLabel" to j(c.boardLabel), "noBoard" to j(c.noBoard), "positionLabel" to j(c.positionLabel),
        "potLabel" to j(c.potLabel), "stackLabel" to j(c.stackLabel), "yourChoice" to j(c.yourChoice),
        "suggestedLine" to j(c.suggestedLine), "suggestionPending" to j(c.suggestionPending), "routesA11y" to j(c.routesA11y),
        "routePrimary" to j(c.routePrimary), "routeSecondary" to j(c.routeSecondary), "simA11y" to j(c.simA11y),
        "simHeading" to j(c.simHeading), "simStable" to j(c.simStable), "simUnstable" to j(c.simUnstable),
        "simColumns" to jStrings(listOf(c.simColAction, c.simColRandom, c.simColWeighted)),
        "simDetailsSummary" to j(c.simDetailsSummary), "simDetailsBody" to j(c.simDetailsBody),
        "simUnavailable" to j(c.simUnavailable), "simRunning" to j(c.simRunning),
        "decisionTitleDefault" to j(c.decisionTitleDefault), "reasonDefault" to j(c.reasonDefault),
        "evidenceHeading" to j(c.evidenceHeading), "confidenceDefault" to j(c.confidenceDefault),
        "lessonHeading" to j(c.lessonHeading), "lessonDefault" to j(c.lessonDefault), "planHeading" to j(c.planHeading),
        "planDefault" to j(c.planDefault), "metricRequired" to j(c.metricRequired), "metricEquity" to j(c.metricEquity),
        "metricContestable" to j(c.metricContestable), "pricePending" to j(c.pricePending), "priceNoCall" to j(c.priceNoCall),
        "equityNone" to j(c.equityNone), "priceNoteSidePots" to j(c.priceNoteSidePots),
        "priceNoteClosing" to j(c.priceNoteClosing), "priceNoteDefault" to j(c.priceNoteDefault),
        "publicActionsSummary" to j(c.publicActionsSummary), "publicActionsEmpty" to j(c.publicActionsEmpty),
        "previous" to j(c.previous), "next" to j(c.next), "scope" to j(c.scope), "methodSummary" to j(c.methodSummary),
        "methodParagraphs" to jStrings(c.methodParagraphs), "methodReferencesLabel" to j(c.methodReferencesLabel),
        "methodReferences" to pairs(c.methodReferences), "methodClosingParagraphs" to jStrings(c.methodClosingParagraphs),
        "backToTable" to j(c.backToTable), "oppEmpty" to j(c.oppEmpty), "oppIntro" to j(c.oppIntro),
        "oppFilterLabel" to j(c.oppFilterLabel), "oppFilterAll" to j(c.oppFilterAll), "oppTimelineA11y" to j(c.oppTimelineA11y),
        "oppTimelineTitle" to j(c.oppTimelineTitle), "oppRecordStatus" to j(c.oppRecordStatus),
        "oppEvidenceHeading" to j(c.oppEvidenceHeading), "oppBranchesSummary" to j(c.oppBranchesSummary),
        "oppBranchesEmpty" to j(c.oppBranchesEmpty),
    )
}

/** One templated copy function applied to fixture arguments. */
private fun dialogTemplate(fn: String, a: JsonArray): String {
    val c = ReviewDialogCopy
    fun s(k: Int) = a[k].str
    fun n(k: Int) = a[k].i
    return when (fn) {
        "title" -> c.title(n(0))
        "change" -> c.change(n(0))
        "stateProgress" -> c.stateProgress(n(0), n(1))
        "actionCount" -> c.actionCount(n(0))
        "detailTitle" -> c.detailTitle(n(0), s(1))
        "simCaption" -> c.simCaption(n(0))
        "simMargin" -> c.simMargin(a[0].d)
        "modelEnumeration" -> c.modelEnumeration(n(0))
        "modelSampling" -> c.modelSampling(n(0), n(1))
        "modelEquity" -> c.modelEquity(s(0), s(1))
        "equityAbout" -> c.equityAbout(s(0))
        "stepPosition" -> c.stepPosition(n(0), n(1))
        "heroStepA11y" -> c.heroStepA11y(n(0), s(1), s(2), s(3))
        "oppStepA11y" -> c.oppStepA11y(n(0), s(1), s(2), s(3))
        "simCellA11y" -> c.simCellA11y(s(0), s(1), s(2), s(3))
        "oppHoleLabel" -> c.oppHoleLabel(s(0))
        "oppChoiceLabel" -> c.oppChoiceLabel(s(0))
        "oppBranch" -> c.oppBranch(a[0].d, a[1].d, a[2].b)
        "oppPublicAction" -> c.oppPublicAction(n(0))
        else -> error("Unknown template $fn")
    }
}
