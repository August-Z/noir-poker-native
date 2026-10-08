package com.august.noirpoker.core.session

import com.august.noirpoker.core.BotDecisionRecord
import com.august.noirpoker.core.Card
import com.august.noirpoker.core.DecisionSnapshot
import com.august.noirpoker.core.Game
import com.august.noirpoker.core.Phase

// Scheduling and lifecycle of the hand review (`review-controller.js`). The
// analysis itself (`analyzeDecision`, `summarizeReview`) lives in the review
// module; this file only depends on the [ReviewRunner] interface.

data class ReviewAward(val name: String, val amount: Int, val label: String)

data class ReviewPot(val label: String, val amount: Int, val eligible: List<String>, val awards: List<ReviewAward>)

/** The hero's result for the hand (`createReviewInput(g).outcome`). */
data class ReviewOutcome(
    val profit: Int,
    val paid: Int,
    val returned: Int,
    val folded: Boolean,
    val wonPot: Boolean,
    val board: List<Card>,
    val pots: List<ReviewPot>,
    val result: String,
)

/**
 * What the hero analysis may read: the hand number, the hero's decision
 * snapshots (public information before each decision only) and the outcome
 * used for the summary header. Opponent execution records are deliberately
 * absent.
 */
data class HeroReviewInput(val hand: Int, val decisions: List<DecisionSnapshot>, val outcome: ReviewOutcome)

/**
 * An immutable copy of a settled hand (`createReviewInput`). [opponents] are the
 * private bot execution records, shown only in the opponent panel after
 * settlement and never sent to the hero analysis.
 */
data class HandReviewInput(
    val hand: Int,
    val hole: List<Card>,
    val decisions: List<DecisionSnapshot>,
    val opponents: List<BotDecisionRecord>,
    val outcome: ReviewOutcome,
) {
    val heroInput: HeroReviewInput get() = HeroReviewInput(hand, decisions, outcome)
}

fun createHandReviewInput(g: Game): HandReviewInput {
    check(g.phase == Phase.DONE) { "A hand can be reviewed only after it ends." }
    val hero = g.players[0]
    val returned = g.payouts.getOrElse(0) { 0 }
    return HandReviewInput(
        hand = g.hand,
        hole = hero.hole.toList(),
        decisions = g.decisions.toList(),
        opponents = g.botDecisions.toList(),
        outcome = ReviewOutcome(
            profit = returned - hero.total,
            paid = hero.total,
            returned = returned,
            folded = hero.folded,
            wonPot = g.winners.any { it.id == 0 },
            board = g.board.toList(),
            pots = g.pots.map { p ->
                ReviewPot(
                    p.label,
                    p.amount,
                    p.eligible.map { g.players[it].name },
                    p.awards.map { ReviewAward(g.players[it.id].name, it.amount, it.label) },
                )
            },
            result = g.result,
        ),
    )
}

/** The finished analysis. The review module's summary type implements this. */
interface ReviewAnalysis {
    /** The step to select when the analysis completes. */
    val priorityIndex: Int
}

/** A unit of review work handed to the [ReviewRunner]. */
data class ReviewJob(val id: Int, val key: String, val input: HeroReviewInput)

/**
 * Results of one [ReviewJob]. Calls must be delivered on the session's thread
 * (post them back to the main thread). Calls for a stale job are dropped.
 */
interface ReviewSink {
    fun progress(done: Int, total: Int)
    fun complete(analysis: ReviewAnalysis)
    fun fail(error: Throwable?)
}

/**
 * Runs the hero analysis off the main thread (a `Dispatchers.Default`
 * coroutine on Android, a detached task on iOS). The returned handle is
 * cancelled when the job becomes stale: a new hand settles, Replay Hand, Start
 * New Session, a seat-count change, or the app moving to the background. The
 * runner should check for cancellation between decisions.
 */
fun interface ReviewRunner {
    fun start(job: ReviewJob, sink: ReviewSink): Cancellable
}

enum class ReviewStatus { IDLE, RUNNING, DONE, ERROR }

enum class ReviewPerspective { HERO, OPPONENTS }

/** Review state for the UI. [input] is null when there is nothing to review. */
data class ReviewState(
    val buttonVisible: Boolean,
    val dialogOpen: Boolean,
    val key: String?,
    val input: HandReviewInput?,
    val status: ReviewStatus,
    val progress: Int,
    val analysis: ReviewAnalysis?,
    val selected: Int,
    val perspective: ReviewPerspective,
    /** `null` shows every opponent; otherwise a seat id. */
    val opponentFilter: Int?,
    val opponentSelected: Int,
    /** Opponent records after the filter, in hand order. */
    val opponentRecords: List<BotDecisionRecord>,
    /** The id of the current job (for diagnostics and tests). */
    val jobId: Int,
)

/**
 * The review job lifecycle. The input is captured as soon as a hand settles;
 * analysis is lazy and starts when the dialog opens. Keys are `"{token}:{hand}"`
 * with the session's view token, exactly like the reference.
 */
class HandReviewController(private val runner: ReviewRunner?, private val onChange: () -> Unit) {
    private class Entry(val key: String, val input: HandReviewInput) {
        var status = ReviewStatus.IDLE
        var progress = 0
        var analysis: ReviewAnalysis? = null
    }

    private var last: Entry? = null
    private var seen = ""
    private var job = 0
    private var handle: Cancellable? = null
    private var selected = 0
    private var perspective = ReviewPerspective.HERO
    private var dialogOpen = false
    private var buttonVisible = false
    private var opponentFilter: Int? = null
    private var opponentSelected = 0

    val jobId: Int get() = job

    private fun terminate() {
        handle?.cancel()
        handle = null
    }

    private fun resetOpponents() {
        opponentFilter = null
        opponentSelected = 0
    }

    /** Called on every render (`handReview.update(game, epoch)`). */
    fun update(g: Game, token: Int) {
        val key = "$token:${g.hand}"
        if (g.phase == Phase.DONE && key != seen) {
            seen = key
            val input = createHandReviewInput(g)
            terminate()
            job++
            last = Entry(key, input)
            selected = 0
            perspective = ReviewPerspective.HERO
            resetOpponents()
            if (dialogOpen) analyze()
        }
        buttonVisible = g.phase == Phase.DONE && last?.key == key
    }

    /** Replay Hand, called with the token from before the replay. */
    fun rollback(g: Game, token: Int) {
        val key = "$token:${g.hand}"
        if (last?.key == key) {
            terminate()
            job++
            last = null
            selected = 0
        }
        if (seen == key) seen = ""
        dialogOpen = false
        buttonVisible = false
    }

    /** Start New Session or a seat-count change. */
    fun reset() {
        terminate()
        job++
        last = null
        seen = ""
        selected = 0
        perspective = ReviewPerspective.HERO
        dialogOpen = false
        buttonVisible = false
    }

    /** Review This Hand. Opening resets the opponent panel's filter and selection. */
    fun open() {
        if (last == null) return
        resetOpponents()
        dialogOpen = true
        analyze()
        onChange()
    }

    fun close() {
        dialogOpen = false
        onChange()
    }

    /** Starts the analysis if it is not running and has not finished (also Re-analyze). */
    fun analyze() {
        val entry = last ?: return
        if (entry.status == ReviewStatus.RUNNING || entry.analysis != null) return
        val id = ++job
        entry.status = ReviewStatus.RUNNING
        entry.progress = 0
        val r = runner
        if (r == null) {
            entry.status = ReviewStatus.ERROR
            return
        }
        val sink = object : ReviewSink {
            override fun progress(done: Int, total: Int) {
                if (id != job || last !== entry) return
                entry.progress = done
                onChange()
            }

            override fun complete(analysis: ReviewAnalysis) {
                if (id != job || last !== entry) return
                entry.analysis = analysis
                entry.status = ReviewStatus.DONE
                val n = entry.input.decisions.size
                selected = if (n == 0) 0 else analysis.priorityIndex.coerceIn(0, n - 1)
                handle = null
                onChange()
            }

            override fun fail(error: Throwable?) {
                if (id != job || last !== entry) return
                entry.status = ReviewStatus.ERROR
                handle = null
                onChange()
            }
        }
        val started = try {
            r.start(ReviewJob(id, entry.key, entry.input.heroInput), sink)
        } catch (e: Exception) {
            sink.fail(e)
            null
        }
        // A synchronous runner may already have finished this job.
        if (id == job && entry.status == ReviewStatus.RUNNING) handle = started
    }

    fun retry() {
        analyze()
        onChange()
    }

    /** Selects a hero decision; out-of-range values are ignored. */
    fun select(index: Int) {
        val n = last?.input?.decisions?.size ?: return
        if (index < 0 || index >= n) return
        selected = index
        onChange()
    }

    fun previous() {
        if (selected > 0) {
            selected--
            onChange()
        }
    }

    fun next() {
        val n = last?.input?.decisions?.size ?: return
        if (selected < n - 1) {
            selected++
            onChange()
        }
    }

    fun setPerspective(value: ReviewPerspective) {
        perspective = value
        onChange()
    }

    /** Filters the opponent timeline by seat (`null` = all) and selects its first step. */
    fun setOpponentFilter(seat: Int?) {
        opponentFilter = seat
        opponentSelected = 0
        onChange()
    }

    fun selectOpponent(index: Int) {
        val n = visibleOpponents().size
        opponentSelected = if (n == 0) 0 else index.coerceIn(0, n - 1)
        onChange()
    }

    private fun visibleOpponents(): List<BotDecisionRecord> =
        last?.input?.opponents?.filter { opponentFilter == null || it.id == opponentFilter } ?: emptyList()

    /** App background: cancel a running job; the result of a cancelled job is dropped. */
    fun pause() {
        val entry = last ?: return
        if (entry.status == ReviewStatus.RUNNING) {
            terminate()
            job++
            entry.status = ReviewStatus.IDLE
            entry.progress = 0
        }
    }

    /** App foreground: restart the analysis if the dialog is still open. */
    fun resume() {
        if (dialogOpen) analyze()
    }

    fun state(): ReviewState {
        val entry = last
        val visible = visibleOpponents()
        return ReviewState(
            buttonVisible = buttonVisible,
            dialogOpen = dialogOpen && entry != null,
            key = entry?.key,
            input = entry?.input,
            status = entry?.status ?: ReviewStatus.IDLE,
            progress = entry?.progress ?: 0,
            analysis = entry?.analysis,
            selected = selected,
            perspective = perspective,
            opponentFilter = opponentFilter,
            opponentSelected = if (visible.isEmpty()) 0 else opponentSelected.coerceIn(0, visible.size - 1),
            opponentRecords = visible,
            jobId = job,
        )
    }
}
