package com.august.noirpoker.core.review

import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.actionLabel
import com.august.noirpoker.core.labelStep
import com.august.noirpoker.core.session.Harness
import com.august.noirpoker.core.session.ReviewState
import com.august.noirpoker.core.session.ReviewStatus as JobStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

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
        assertEquals("Hand ${input.hand} · Hand Review", view.title)
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
}

