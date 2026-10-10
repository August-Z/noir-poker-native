import Foundation

/// Runs the hero review off the main thread in a detached task. The analysis
/// checks for cancellation before each decision and between simulation trials;
/// progress and results are delivered on the main actor. A cancelled handle
/// suppresses every later delivery, including a result the analysis already
/// produced, and the session also drops results of stale jobs by job id.
public final class DetachedReviewRunner: ReviewRunner {
    /// The analysis a job runs: the hero input, a cancellation check and a
    /// progress callback. Called once per job on the detached task.
    public typealias Analyze = @Sendable (
        _ input: HeroReviewInput,
        _ isCancelled: () -> Bool,
        _ progress: (_ done: Int, _ total: Int) -> Void
    ) throws -> ReviewSummary

    private let priority: TaskPriority
    private let analyze: Analyze

    /// - Parameters:
    ///   - priority: The detached task's priority (`.userInitiated` in the app).
    ///   - analyze: The analysis; the full `analyzeHeroReview` by default. Tests
    ///     inject a controllable one.
    public init(priority: TaskPriority = .userInitiated,
                analyze: @escaping Analyze = { input, isCancelled, progress in
                    try analyzeHeroReview(input, isCancelled: isCancelled, progress: progress)
                }) {
        self.priority = priority
        self.analyze = analyze
    }

    public func start(_ job: ReviewJob, _ sink: ReviewSink) -> SessionCancellable {
        let input = job.input
        let box = SinkBox(sink)
        let cancelled = CancelFlag()
        let analyze = self.analyze
        let task = Task.detached(priority: priority) {
            let stop = { cancelled.isSet || Task.isCancelled }
            do {
                let summary = try analyze(input, stop) { done, total in
                    Task { @MainActor in
                        if !cancelled.isSet { box.progress(done, total) }
                    }
                }
                await MainActor.run {
                    if !cancelled.isSet { box.complete(summary) }
                }
            } catch is ReviewCancelledError {
                // A cancelled job reports nothing.
            } catch {
                await MainActor.run {
                    if !cancelled.isSet { box.fail(error) }
                }
            }
        }
        return CancelHandle {
            cancelled.set()
            task.cancel()
        }
    }
}

/// A thread-safe one-way flag: set once the job's handle is cancelled.
private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

/// Holds the session's sink; it is only touched on the main actor.
private final class SinkBox: @unchecked Sendable {
    private let sink: ReviewSink
    init(_ sink: ReviewSink) { self.sink = sink }
    @MainActor func progress(_ done: Int, _ total: Int) { sink.progress(done: done, total: total) }
    @MainActor func complete(_ summary: ReviewSummary) { sink.complete(summary) }
    @MainActor func fail(_ error: Error) { sink.fail(error) }
}
