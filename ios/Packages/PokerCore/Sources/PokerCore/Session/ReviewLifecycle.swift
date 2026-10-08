// Scheduling and lifecycle of the hand review (`review-controller.js`). The
// analysis itself (`analyzeDecision`, `summarizeReview`) lives in the review
// module; this file only depends on the `ReviewRunner` interface.
//
// Type names carry a `HandReview` prefix where the review module could use the
// plain name (`ReviewOutcome`, `ReviewStatus`, …), because both live in the one
// `PokerCore` module.

public struct HandReviewAward: Equatable, Sendable {
    public var name: String
    public var amount: Int
    public var label: String
}

public struct HandReviewPot: Equatable, Sendable {
    public var label: String
    public var amount: Int
    public var eligible: [String]
    public var awards: [HandReviewAward]
}

/// The hero's result for the hand (`createReviewInput(g).outcome`).
public struct HandReviewOutcome: Equatable, Sendable {
    public var profit: Int
    public var paid: Int
    public var returned: Int
    public var folded: Bool
    public var wonPot: Bool
    public var board: [Card]
    public var pots: [HandReviewPot]
    public var result: String
}

/// What the hero analysis may read: the hand number, the hero's decision
/// snapshots (public information before each decision only) and the outcome
/// used for the summary header. Opponent execution records are deliberately
/// absent.
public struct HeroReviewInput: Equatable, Sendable {
    public var hand: Int
    public var decisions: [DecisionSnapshot]
    public var outcome: HandReviewOutcome
}

/// An immutable copy of a settled hand (`createReviewInput`). `opponents` are
/// the private bot execution records, shown only in the opponent panel after
/// settlement and never sent to the hero analysis.
public struct HandReviewInput: Equatable, Sendable {
    public var hand: Int
    public var hole: [Card]
    public var decisions: [DecisionSnapshot]
    public var opponents: [BotDecisionRecord]
    public var outcome: HandReviewOutcome

    public var heroInput: HeroReviewInput { HeroReviewInput(hand: hand, decisions: decisions, outcome: outcome) }
}

/// Captures a settled hand. Returns `nil` before the hand ends (the reference throws).
public func createHandReviewInput(_ g: Game) -> HandReviewInput? {
    guard g.phase == .done else { return nil }
    let hero = g.players[0]
    let returned = g.payouts.first ?? 0
    return HandReviewInput(
        hand: g.hand,
        hole: hero.hole,
        decisions: g.decisions,
        opponents: g.botDecisions,
        outcome: HandReviewOutcome(
            profit: returned - hero.total,
            paid: hero.total,
            returned: returned,
            folded: hero.folded,
            wonPot: g.winners.contains { $0.id == 0 },
            board: g.board,
            pots: g.pots.map { p in
                HandReviewPot(label: p.label, amount: p.amount, eligible: p.eligible.map { g.players[$0].name },
                              awards: p.awards.map { HandReviewAward(name: g.players[$0.id].name, amount: $0.amount, label: $0.label) })
            },
            result: g.result
        )
    )
}

/// The finished analysis. The review module's summary type conforms to this.
public protocol HandReviewAnalysis: Sendable {
    /// The step to select when the analysis completes.
    var priorityIndex: Int { get }
}

/// A unit of review work handed to the `ReviewRunner`. A value type, safe to
/// send to a background task.
public struct ReviewJob: Equatable, Sendable {
    public var id: Int
    public var key: String
    public var input: HeroReviewInput
}

/// Results of one `ReviewJob`. Calls must be delivered on the session's thread
/// (hop back to the main actor). Calls for a stale job are dropped.
public protocol ReviewSink: AnyObject {
    func progress(done: Int, total: Int)
    func complete(_ analysis: HandReviewAnalysis)
    func fail(_ error: Error?)
}

/// Runs the hero analysis off the main thread (a detached task on iOS). The
/// returned handle is cancelled when the job becomes stale: a new hand settles,
/// Replay Hand, Start New Session, a seat-count change, or the app moving to the
/// background. The runner should check for cancellation between decisions.
public protocol ReviewRunner: AnyObject {
    func start(_ job: ReviewJob, _ sink: ReviewSink) -> SessionCancellable
}

/// A `ReviewRunner` backed by a closure.
public final class ClosureReviewRunner: ReviewRunner {
    private let body: (ReviewJob, ReviewSink) -> SessionCancellable
    public init(_ body: @escaping (ReviewJob, ReviewSink) -> SessionCancellable) { self.body = body }
    public func start(_ job: ReviewJob, _ sink: ReviewSink) -> SessionCancellable { body(job, sink) }
}

public enum HandReviewStatus: String, Sendable {
    case idle, running, done, error
}

public enum HandReviewPerspective: String, Sendable {
    case hero, opponents
}

/// Review state for the UI. `input` is nil when there is nothing to review.
public struct HandReviewState {
    public var buttonVisible: Bool
    public var dialogOpen: Bool
    public var key: String?
    public var input: HandReviewInput?
    public var status: HandReviewStatus
    public var progress: Int
    public var analysis: HandReviewAnalysis?
    public var selected: Int
    public var perspective: HandReviewPerspective
    /// `nil` shows every opponent; otherwise a seat id.
    public var opponentFilter: Int?
    public var opponentSelected: Int
    /// Opponent records after the filter, in hand order.
    public var opponentRecords: [BotDecisionRecord]
    /// The id of the current job (for diagnostics and tests).
    public var jobId: Int
}

/// The review job lifecycle. The input is captured as soon as a hand settles;
/// analysis is lazy and starts when the dialog opens. Keys are `"{token}:{hand}"`
/// with the session's view token, exactly like the reference.
public final class HandReviewController {
    private final class Entry {
        let key: String
        let input: HandReviewInput
        var status = HandReviewStatus.idle
        var progress = 0
        var analysis: HandReviewAnalysis?
        init(key: String, input: HandReviewInput) {
            self.key = key
            self.input = input
        }
    }

    private final class Sink: ReviewSink {
        weak var controller: HandReviewController?
        let id: Int
        let entry: Entry
        init(controller: HandReviewController, id: Int, entry: Entry) {
            self.controller = controller
            self.id = id
            self.entry = entry
        }

        private var current: HandReviewController? {
            guard let c = controller, c.job == id, c.last === entry else { return nil }
            return c
        }

        func progress(done: Int, total: Int) {
            guard let c = current else { return }
            entry.progress = done
            c.onChange()
        }

        func complete(_ analysis: HandReviewAnalysis) {
            guard let c = current else { return }
            entry.analysis = analysis
            entry.status = .done
            let n = entry.input.decisions.count
            c.selected = n == 0 ? 0 : min(max(analysis.priorityIndex, 0), n - 1)
            c.handle = nil
            c.onChange()
        }

        func fail(_ error: Error?) {
            guard let c = current else { return }
            entry.status = .error
            c.handle = nil
            c.onChange()
        }
    }

    private let runner: ReviewRunner?
    /// Called after a change that did not come from a render (sink callbacks, dialog commands).
    var onChange: () -> Void = {}

    private var last: Entry?
    private var seen = ""
    private var job = 0
    private var handle: SessionCancellable?
    private var selected = 0
    private var perspective = HandReviewPerspective.hero
    private var dialogOpen = false
    private var buttonVisible = false
    private var opponentFilter: Int?
    private var opponentSelected = 0

    public init(runner: ReviewRunner?) { self.runner = runner }

    public var jobId: Int { job }

    private func terminate() {
        handle?.cancel()
        handle = nil
    }

    private func resetOpponents() {
        opponentFilter = nil
        opponentSelected = 0
    }

    /// Called on every render (`handReview.update(game, epoch)`).
    func update(_ g: Game, token: Int) {
        let key = "\(token):\(g.hand)"
        if g.phase == .done && key != seen, let input = createHandReviewInput(g) {
            seen = key
            terminate()
            job += 1
            last = Entry(key: key, input: input)
            selected = 0
            perspective = .hero
            resetOpponents()
            if dialogOpen { analyze() }
        }
        buttonVisible = g.phase == .done && last?.key == key
    }

    /// Replay Hand, called with the token from before the replay.
    func rollback(_ g: Game, token: Int) {
        let key = "\(token):\(g.hand)"
        if last?.key == key {
            terminate()
            job += 1
            last = nil
            selected = 0
        }
        if seen == key { seen = "" }
        dialogOpen = false
        buttonVisible = false
    }

    /// Start New Session or a seat-count change.
    func reset() {
        terminate()
        job += 1
        last = nil
        seen = ""
        selected = 0
        perspective = .hero
        dialogOpen = false
        buttonVisible = false
    }

    /// Review This Hand. Opening resets the opponent panel's filter and selection.
    func open() {
        guard last != nil else { return }
        resetOpponents()
        dialogOpen = true
        analyze()
        onChange()
    }

    func close() {
        dialogOpen = false
        onChange()
    }

    /// Starts the analysis if it is not running and has not finished (also Re-analyze).
    func analyze() {
        guard let entry = last, entry.status != .running, entry.analysis == nil else { return }
        job += 1
        let id = job
        entry.status = .running
        entry.progress = 0
        guard let runner else {
            entry.status = .error
            return
        }
        let sink = Sink(controller: self, id: id, entry: entry)
        let started = runner.start(ReviewJob(id: id, key: entry.key, input: entry.input.heroInput), sink)
        // A synchronous runner may already have finished this job.
        if id == job && entry.status == .running { handle = started }
    }

    func retry() {
        analyze()
        onChange()
    }

    /// Selects a hero decision; out-of-range values are ignored.
    func select(_ index: Int) {
        guard let n = last?.input.decisions.count, index >= 0, index < n else { return }
        selected = index
        onChange()
    }

    func previous() {
        guard selected > 0 else { return }
        selected -= 1
        onChange()
    }

    func next() {
        guard let n = last?.input.decisions.count, selected < n - 1 else { return }
        selected += 1
        onChange()
    }

    func setPerspective(_ value: HandReviewPerspective) {
        perspective = value
        onChange()
    }

    /// Filters the opponent timeline by seat (`nil` = all) and selects its first step.
    func setOpponentFilter(_ seat: Int?) {
        opponentFilter = seat
        opponentSelected = 0
        onChange()
    }

    func selectOpponent(_ index: Int) {
        let n = visibleOpponents().count
        opponentSelected = n == 0 ? 0 : min(max(index, 0), n - 1)
        onChange()
    }

    private func visibleOpponents() -> [BotDecisionRecord] {
        (last?.input.opponents ?? []).filter { opponentFilter == nil || $0.id == opponentFilter }
    }

    /// App background: cancel a running job; the result of a cancelled job is dropped.
    func pause() {
        guard let entry = last, entry.status == .running else { return }
        terminate()
        job += 1
        entry.status = .idle
        entry.progress = 0
    }

    /// App foreground: restart the analysis if the dialog is still open.
    func resume() {
        if dialogOpen { analyze() }
    }

    func state() -> HandReviewState {
        let entry = last
        let visible = visibleOpponents()
        return HandReviewState(
            buttonVisible: buttonVisible,
            dialogOpen: dialogOpen && entry != nil,
            key: entry?.key,
            input: entry?.input,
            status: entry?.status ?? .idle,
            progress: entry?.progress ?? 0,
            analysis: entry?.analysis,
            selected: selected,
            perspective: perspective,
            opponentFilter: opponentFilter,
            opponentSelected: visible.isEmpty ? 0 : min(max(opponentSelected, 0), visible.count - 1),
            opponentRecords: visible,
            jobId: job
        )
    }
}
