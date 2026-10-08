// Bridges the session's review lifecycle (`ReviewJob`, `HeroReviewInput`,
// `HandReviewAnalysis`) to the review port (`ReviewDecision`,
// `analyzeDecision`, `summarizeReview`). This mirrors the reference worker
// (`src/review/worker.js`): analyze each hero decision in order, report
// progress after each one, then summarize. Platform runners call
// `analyzeHeroReview` from a background task and hop back to the main thread
// for every `ReviewSink` call.

/// The review module's summary is the analysis the session stores.
extension ReviewSummary: HandReviewAnalysis {}

/// Thrown by `analyzeHeroReview` when `isCancelled` reports a stale job.
public struct ReviewCancelledError: Error, Equatable, Sendable {
    public init() {}
}

public extension HeroReviewInput {
    /// The before-action snapshots in the review port's input type. Only public
    /// information (plus the hero's own hole cards) crosses this boundary.
    var reviewDecisions: [ReviewDecision] { decisions.map(ReviewDecision.init) }
}

/// Analyzes every hero decision of `input` and summarizes the hand.
///
/// - `isCancelled` is checked before each decision and between simulation
///   trials; once it returns true the call throws `ReviewCancelledError`.
/// - `progress(done, total)` is called after each analyzed decision, like the
///   reference worker's `progress` message.
/// - `trials` defaults to the reference worker's `analyzeDecision` default (600).
public func analyzeHeroReview(_ input: HeroReviewInput, trials: Int = 600, rolloutTrials: Int? = nil,
                              isCancelled: () -> Bool = { false },
                              progress: (_ done: Int, _ total: Int) -> Void = { _, _ in }) throws -> ReviewSummary {
    let decisions = input.reviewDecisions
    func check() throws { if isCancelled() { throw ReviewCancelledError() } }
    var steps: [DecisionAnalysis] = []
    steps.reserveCapacity(decisions.count)
    for decision in decisions {
        try check()
        steps.append(try analyzeDecision(decision, trials: trials, rolloutTrials: rolloutTrials, checkCancellation: check))
        progress(steps.count, decisions.count)
    }
    try check()
    return summarizeReview(decisions: decisions, steps: steps)
}
