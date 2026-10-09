package com.august.noirpoker.core.review

import com.august.noirpoker.core.session.Cancellable
import com.august.noirpoker.core.session.HandReviewInput
import com.august.noirpoker.core.session.HeroReviewInput
import com.august.noirpoker.core.session.ReviewAnalysis
import com.august.noirpoker.core.session.ReviewJob
import com.august.noirpoker.core.session.ReviewRunner
import com.august.noirpoker.core.session.ReviewSink
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean
import com.august.noirpoker.core.session.ReviewOutcome as SessionOutcome

// The bridge between the table session's review interface (`session.ReviewRunner`,
// `HeroReviewInput`, `ReviewAnalysis`) and the review port (`analyzeReview`,
// `ReviewSummary`). The session never imports the review module; the apps hand it a
// runner built here.

/**
 * The finished hero analysis the session stores. [decisions] are the review views of
 * the snapshots that were graded, in the same order as [summary]`.steps`.
 */
class HeroReviewAnalysis(val summary: ReviewSummary, val decisions: List<ReviewDecision>) : ReviewAnalysis {
    override val priorityIndex: Int get() = summary.priorityIndex
}

/** The review views of the hero's decision snapshots (public information only). */
fun HeroReviewInput.reviewDecisions(): List<ReviewDecision> = decisions.map { it.toReviewDecision() }

fun SessionOutcome.toReviewOutcome(): ReviewOutcome = ReviewOutcome(
    profit = profit,
    paid = paid,
    returned = returned,
    folded = folded,
    wonPot = wonPot,
    board = board,
    pots = pots.map { p -> OutcomePot(p.label, p.amount, p.eligible, p.awards.map { OutcomeAward(it.name, it.amount, it.label) }) },
    result = result,
)

/** The review module's `ReviewInput` for a hand the session captured (opponent panel included). */
fun HandReviewInput.toReviewInput(): ReviewInput = ReviewInput(
    hand = hand,
    hole = hole,
    decisions = decisions.map { it.toReviewDecision() },
    opponents = opponents,
    outcome = outcome.toReviewOutcome(),
)

/**
 * Analyzes the hero's decisions of [input]. Only the decision snapshots are read;
 * the outcome never reaches the grading. [checkpoint] may throw to cancel.
 */
fun analyzeHeroReview(
    input: HeroReviewInput,
    trials: Int = 600,
    rolloutTrials: Int = defaultRolloutTrials(trials),
    checkpoint: () -> Unit = {},
    progress: (done: Int, total: Int) -> Unit = { _, _ -> },
): HeroReviewAnalysis {
    val decisions = input.reviewDecisions()
    val summary = analyzeReview(decisions, trials, rolloutTrials, checkpoint, progress)
    return HeroReviewAnalysis(summary, decisions)
}

/** Thrown from the checkpoint of a cancelled review job. */
class ReviewCancelledException : RuntimeException("Review cancelled") {
    override fun fillInStackTrace(): Throwable = this
}

/**
 * A [ReviewRunner] that analyzes on [worker] (a background executor) and hands every
 * sink call to [deliver], which must run it on the session's thread (for example a
 * main-thread `Handler.post`). Cancelling stops the analysis at the next checkpoint
 * (between decisions and between simulation trials) and suppresses every later sink
 * call, including ones already queued on the session's thread.
 */
class ExecutorReviewRunner(
    private val worker: Executor,
    private val deliver: (() -> Unit) -> Unit,
    private val trials: Int = 600,
) : ReviewRunner {
    override fun start(job: ReviewJob, sink: ReviewSink): Cancellable {
        val cancelled = AtomicBoolean(false)
        fun post(block: () -> Unit) = deliver { if (!cancelled.get()) block() }
        val checkpoint = { if (cancelled.get() || Thread.currentThread().isInterrupted) throw ReviewCancelledException() }
        worker.execute {
            if (cancelled.get()) return@execute
            try {
                val analysis = analyzeHeroReview(
                    job.input,
                    trials = trials,
                    checkpoint = checkpoint,
                    progress = { done, total -> post { sink.progress(done, total) } },
                )
                post { sink.complete(analysis) }
            } catch (_: ReviewCancelledException) {
                // Stale job: nothing is delivered.
            } catch (e: Throwable) {
                if (e is VirtualMachineError) throw e
                post { sink.fail(e) }
            }
        }
        return Cancellable { cancelled.set(true) }
    }
}
