import Foundation
import PokerCore

/// The session's timer on the main actor: a sleeping `Task` per callback on a
/// monotonic `ContinuousClock`. Cancelling the handle cancels the task; the
/// session also drops stale callbacks by epoch.
final class MainScheduler: SessionScheduler {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    init() { origin = clock.now }

    var nowMs: Int {
        let elapsed = clock.now - origin
        let parts = elapsed.components
        return Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000)
    }

    func schedule(delayMs: Int, _ action: @escaping () -> Void) -> SessionCancellable {
        let work = MainWork(action)
        let task = Task { @MainActor in
            if delayMs > 0 {
                do { try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000) } catch { return }
            } else {
                await Task.yield()
            }
            if Task.isCancelled { return }
            work.run()
        }
        return CancelHandle { task.cancel() }
    }
}

/// Carries a main-thread callback into a main-actor task.
private final class MainWork: @unchecked Sendable {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @MainActor func run() { action() }
}
