// Timers for the table session: the reference's `setTimeout` and
// `performance.now()`, behind an interface the UI layer implements.

/// A handle to scheduled work. Cancelling twice, or after the work ran, is harmless.
///
/// Named `SessionCancellable` (not `Cancellable`) so that it never clashes
/// with Combine's `Cancellable` in app code that imports both.
public protocol SessionCancellable: AnyObject {
    func cancel()
}

/// A cancellable handle backed by a closure.
public final class CancelHandle: SessionCancellable {
    private var onCancel: (() -> Void)?
    public init(_ onCancel: @escaping () -> Void = {}) { self.onCancel = onCancel }
    public func cancel() {
        let body = onCancel
        onCancel = nil
        body?()
    }
}

/// The single-threaded timer the table session uses for street advances, bot
/// thinking pauses, and the Finish Hand loop.
///
/// Every action must run on the thread that owns the session (the main actor
/// in the app). The app can back it with a main-actor `Task` that sleeps on a
/// `ContinuousClock`; tests use `ManualScheduler`.
///
/// Named `SessionScheduler` (not `Scheduler`) to avoid Combine's `Scheduler`.
public protocol SessionScheduler: AnyObject {
    /// A monotonic clock in milliseconds.
    var nowMs: Int { get }

    /// Runs `action` once after at least `delayMs` milliseconds (0 = next turn of the run loop).
    func schedule(delayMs: Int, _ action: @escaping () -> Void) -> SessionCancellable
}

/// A deterministic virtual clock for tests. Nothing runs until the test advances
/// time. Tasks due at the same time run in scheduling order, and tasks scheduled
/// while advancing run in the same call if they fall due before the target time.
public final class ManualScheduler: SessionScheduler {
    private final class Task {
        let at: Int
        let seq: Int
        let action: () -> Void
        var cancelled = false
        init(at: Int, seq: Int, action: @escaping () -> Void) {
            self.at = at
            self.seq = seq
            self.action = action
        }
    }

    private var queue: [Task] = []
    private var seq = 0

    public private(set) var nowMs: Int

    public init(start: Int = 0) { nowMs = start }

    /// Number of tasks that are scheduled and not cancelled.
    public var pendingCount: Int { queue.filter { !$0.cancelled }.count }

    /// The due time of the next live task, or `nil` when idle.
    public var nextDueAt: Int? { queue.filter { !$0.cancelled }.map(\.at).min() }

    public func schedule(delayMs: Int, _ action: @escaping () -> Void) -> SessionCancellable {
        let task = Task(at: nowMs + max(0, delayMs), seq: seq, action: action)
        seq += 1
        // Keep the queue sorted by (due time, scheduling order).
        let index = queue.firstIndex { $0.at > task.at } ?? queue.count
        queue.insert(task, at: index)
        return CancelHandle { task.cancelled = true }
    }

    private func popDue(_ limit: Int) -> Task? {
        guard let first = queue.first, first.at <= limit else { return nil }
        queue.removeFirst()
        return first
    }

    /// Advances the clock by `ms`, running every task that falls due on the way.
    public func advance(by ms: Int) { advance(to: nowMs + ms) }

    public func advance(to target: Int) {
        precondition(target >= nowMs, "Time cannot go backwards")
        while let next = popDue(target) {
            if next.cancelled { continue }
            nowMs = next.at
            next.action()
        }
        nowMs = target
    }

    /// Runs only the tasks due now (zero-delay work), without moving the clock.
    public func runCurrent() { advance(to: nowMs) }

    /// Runs tasks in due order until nothing is scheduled or `maxMs` of virtual
    /// time has passed. Returns the number of tasks run.
    @discardableResult
    public func runUntilIdle(maxMs: Int = 10 * 60_000) -> Int {
        let limit = nowMs + maxMs
        var ran = 0
        while let next = popDue(limit) {
            if next.cancelled { continue }
            nowMs = next.at
            next.action()
            ran += 1
        }
        return ran
    }
}
