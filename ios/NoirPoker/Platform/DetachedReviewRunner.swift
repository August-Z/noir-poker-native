import Foundation
import PokerCore

/// Runs the hero review off the main thread in a detached task. It checks for
/// cancellation before each decision and between simulation trials, and
/// delivers progress and results on the main actor. The session drops results
/// of stale jobs by job id.
final class DetachedReviewRunner: ReviewRunner {
    func start(_ job: ReviewJob, _ sink: ReviewSink) -> SessionCancellable {
        let input = job.input
        let box = SinkBox(sink)
        let task = Task.detached(priority: .userInitiated) {
            do {
                let summary = try analyzeHeroReview(input, isCancelled: { Task.isCancelled }) { done, total in
                    Task { @MainActor in box.progress(done, total) }
                }
                await MainActor.run {
                    if !Task.isCancelled { box.complete(summary) }
                }
            } catch is ReviewCancelledError {
                // A cancelled job reports nothing.
            } catch {
                await MainActor.run {
                    if !Task.isCancelled { box.fail() }
                }
            }
        }
        return CancelHandle { task.cancel() }
    }
}

/// Holds the session's sink; it is only touched on the main actor.
private final class SinkBox: @unchecked Sendable {
    private let sink: ReviewSink
    init(_ sink: ReviewSink) { self.sink = sink }
    @MainActor func progress(_ done: Int, _ total: Int) { sink.progress(done: done, total: total) }
    @MainActor func complete(_ summary: ReviewSummary) { sink.complete(summary) }
    @MainActor func fail() { sink.fail(nil) }
}
