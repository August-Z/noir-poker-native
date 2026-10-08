import Foundation
import PokerCore

/// The session's timer on the main actor: a sleeping `Task` per callback on a
/// monotonic `ContinuousClock`. Cancelling the handle cancels the task; the
/// session also drops stale callbacks by epoch.
final class MainScheduler: SessionScheduler {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant
    /// Session milliseconds per real millisecond. 1 in the app; UI tests may
    /// run the clock faster so bots and streets advance quickly.
    private let speed: Double

    init(speed: Double = 1) {
        origin = clock.now
        self.speed = max(1, speed)
    }

    var nowMs: Int {
        let elapsed = clock.now - origin
        let parts = elapsed.components
        let realMs = Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
        return Int(realMs * speed)
    }

    func schedule(delayMs: Int, _ action: @escaping () -> Void) -> SessionCancellable {
        let work = MainWork(action)
        let speed = self.speed
        let task = Task { @MainActor in
            if delayMs > 0 {
                do { try await Task.sleep(nanoseconds: UInt64(Double(delayMs) * 1_000_000 / speed)) } catch { return }
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
