import Foundation
import XCTest
@testable import PokerCore

/// The app's review runner: analysis on a detached task, delivery on the main
/// actor, and no delivery once the job's handle is cancelled.
final class DetachedReviewRunnerTests: XCTestCase {
    /// Records what the runner delivers and on which thread.
    private final class RecordingSink: ReviewSink {
        var progress: [(Int, Int)] = []
        var completed = 0
        var failed = 0
        var deliveredOffMain = false
        var onComplete: (() -> Void)?
        var onFail: (() -> Void)?
        var onProgress: (() -> Void)?

        func progress(done: Int, total: Int) {
            if !Thread.isMainThread { deliveredOffMain = true }
            progress.append((done, total))
            onProgress?()
        }

        func complete(_ analysis: HandReviewAnalysis) {
            if !Thread.isMainThread { deliveredOffMain = true }
            completed += 1
            onComplete?()
        }

        func fail(_ error: Error?) {
            if !Thread.isMainThread { deliveredOffMain = true }
            failed += 1
            onFail?()
        }
    }

    /// Facts the analysis closure observes on the worker.
    private final class WorkerLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _onMain: Bool?
        private var _priority: TaskPriority?
        private var _sawCancellation = false

        var onMain: Bool? { lock.lock(); defer { lock.unlock() }; return _onMain }
        var priority: TaskPriority? { lock.lock(); defer { lock.unlock() }; return _priority }
        var sawCancellation: Bool { lock.lock(); defer { lock.unlock() }; return _sawCancellation }

        func record(onMain: Bool, priority: TaskPriority) {
            lock.lock()
            _onMain = onMain
            _priority = priority
            lock.unlock()
        }

        func noteCancellation() {
            lock.lock()
            _sawCancellation = true
            lock.unlock()
        }
    }

    private let emptySummary = summarizeReview(decisions: [], steps: [])

    private func job(_ id: Int = 1) -> ReviewJob {
        let outcome = HandReviewOutcome(profit: -25, paid: 25, returned: 0, folded: true, wonPot: false, board: [],
                                        pots: [], result: "")
        return ReviewJob(id: id, key: "1:\(id)", input: HeroReviewInput(hand: id, decisions: [], outcome: outcome))
    }

    func testAnalyzesOffTheMainThreadAndDeliversOnTheMainThread() {
        XCTAssertTrue(Thread.isMainThread)
        let log = WorkerLog()
        let summary = emptySummary
        let runner = DetachedReviewRunner(priority: .utility) { _, _, progress in
            log.record(onMain: Thread.isMainThread, priority: Task.currentPriority)
            progress(1, 2)
            progress(2, 2)
            return summary
        }
        let sink = RecordingSink()
        let done = expectation(description: "complete")
        sink.onComplete = { done.fulfill() }
        let progressed = expectation(description: "progress")
        progressed.expectedFulfillmentCount = 2
        sink.onProgress = { progressed.fulfill() }

        _ = runner.start(job(), sink)
        // Nothing is delivered synchronously: the work runs on the detached task.
        XCTAssertEqual(sink.completed, 0)
        wait(for: [progressed, done], timeout: 10)

        XCTAssertEqual(log.onMain, false, "the analysis runs off the main thread")
        XCTAssertEqual(log.priority, .utility, "the injected priority reaches the task")
        XCTAssertFalse(sink.deliveredOffMain, "progress and results arrive on the main thread")
        XCTAssertEqual(sink.progress.map(\.0).sorted(), [1, 2])
        XCTAssertEqual(sink.completed, 1)
        XCTAssertEqual(sink.failed, 0)
    }

    func testCancellingSuppressesAResultTheAnalysisStillReturns() {
        let release = DispatchSemaphore(value: 0)
        let started = expectation(description: "analysis started")
        let finished = expectation(description: "analysis returned")
        let log = WorkerLog()
        let summary = emptySummary
        let runner = DetachedReviewRunner { _, isCancelled, progress in
            started.fulfill()
            release.wait()
            if isCancelled() { log.noteCancellation() }
            // An analysis that ignores the check still must not reach the sink.
            progress(1, 1)
            finished.fulfill()
            return summary
        }
        let sink = RecordingSink()
        let delivered = expectation(description: "no delivery")
        delivered.isInverted = true
        sink.onComplete = { delivered.fulfill() }
        sink.onFail = { delivered.fulfill() }
        sink.onProgress = { delivered.fulfill() }

        let handle = runner.start(job(), sink)
        wait(for: [started], timeout: 10)
        handle.cancel()
        release.signal()
        wait(for: [finished], timeout: 10)
        wait(for: [delivered], timeout: 0.5)

        XCTAssertTrue(log.sawCancellation, "the cancellation check reports true after cancel")
        XCTAssertEqual(sink.completed, 0)
        XCTAssertEqual(sink.failed, 0)
        XCTAssertTrue(sink.progress.isEmpty)
    }

    func testACancelledAnalysisStopsAtItsNextCheckpointAndReportsNothing() {
        let started = expectation(description: "analysis started")
        let stopped = expectation(description: "analysis stopped")
        let runner = DetachedReviewRunner { _, isCancelled, _ in
            started.fulfill()
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if isCancelled() {
                    stopped.fulfill()
                    throw ReviewCancelledError()
                }
                Thread.sleep(forTimeInterval: 0.005)
            }
            XCTFail("the analysis never saw the cancellation")
            throw ReviewCancelledError()
        }
        let sink = RecordingSink()
        let delivered = expectation(description: "no delivery")
        delivered.isInverted = true
        sink.onComplete = { delivered.fulfill() }
        sink.onFail = { delivered.fulfill() }

        let handle = runner.start(job(), sink)
        wait(for: [started], timeout: 10)
        handle.cancel()
        wait(for: [stopped], timeout: 10)
        wait(for: [delivered], timeout: 0.5)
        XCTAssertEqual(sink.completed + sink.failed, 0)
    }

    func testAnAnalysisErrorIsReportedAsAFailureOnTheMainThread() {
        struct Broken: Error {}
        let runner = DetachedReviewRunner { _, _, _ in throw Broken() }
        let sink = RecordingSink()
        let failed = expectation(description: "fail")
        sink.onFail = { failed.fulfill() }
        _ = runner.start(job(), sink)
        wait(for: [failed], timeout: 10)
        XCTAssertEqual(sink.failed, 1)
        XCTAssertEqual(sink.completed, 0)
        XCTAssertFalse(sink.deliveredOffMain)
    }

    func testTheRunnerDrivesTheSessionToADoneReview() throws {
        let runner = DetachedReviewRunner(priority: .userInitiated) { input, isCancelled, progress in
            try analyzeHeroReview(input, trials: 40, isCancelled: isCancelled, progress: progress)
        }
        let h = Harness(seed: 3, runner: runner)
        h.session.start()
        for _ in 0..<200 {
            h.runBots()
            if h.game.phase == .done { break }
            if h.game.phase == .playing && h.game.actor == 0 {
                h.session.fold()
            } else if h.scheduler.nextDueAt == nil {
                break
            }
        }
        XCTAssertEqual(h.game.phase, .done)
        XCTAssertNotNil(h.state.review.input)
        h.session.openReview()
        XCTAssertEqual(h.state.review.status, .running, "the detached runner never finishes synchronously")
        let deadline = Date().addingTimeInterval(60)
        while h.state.review.status == .running && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(h.state.review.status, .done)
        XCTAssertNotNil(h.state.review.analysis as? ReviewSummary)
    }
}
