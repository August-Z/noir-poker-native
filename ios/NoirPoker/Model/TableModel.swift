import SwiftUI
import Observation
import PokerCore

/// The observable table model: wraps `TableSession`, republishes its render
/// state, plays its effects, and forwards lifecycle transitions. All game
/// logic, copy and scheduling stay in the session.
@MainActor
@Observable
final class TableModel {
    /// The latest session render state.
    private(set) var state: TableRenderState
    /// Increments for every chip flight so views can animate it once.
    private(set) var chipFlights: [ChipFlight] = []

    let session: TableSession
    @ObservationIgnored private var subscription: SessionCancellable?
    private let tones = ToneSynth()
    @ObservationIgnored private var nextFlightId = 0

    struct ChipFlight: Identifiable, Equatable {
        let id: Int
        let seat: Int
    }

    /// Whether the UI-test probe is shown (debug UI-test launches only).
    let showsTestProbe: Bool

    /// The app's model: system randomness, real time and `UserDefaults`,
    /// unless a debug UI-test launch asks for a seed or a faster clock.
    convenience init(options: LaunchOptions = .current) {
        options.prepareStorage()
        self.init(storage: UserDefaultsStorage(),
                  scheduler: MainScheduler(speed: options.speed),
                  random: options.makeRandom(),
                  reviewRunner: DetachedReviewRunner(),
                  showsTestProbe: options.uiTesting)
    }

    init(storage: KeyValueStorage,
         scheduler: SessionScheduler,
         random: RandomSource,
         reviewRunner: ReviewRunner?,
         showsTestProbe: Bool = false) {
        self.showsTestProbe = showsTestProbe
        let session = TableSession(scheduler: scheduler, storage: storage,
                                   random: random, reviewRunner: reviewRunner)
        self.session = session
        state = session.state
        session.effectListener = { [weak self] effect in
            MainActor.assumeIsolated { self?.handle(effect) }
        }
        subscription = session.addListener { [weak self] next in
            MainActor.assumeIsolated { self?.state = next }
        }
        session.start()
    }

    // MARK: Lifecycle

    func didEnterBackground() {
        session.onBackground()
        chipFlights.removeAll()
        tones.stop()
    }

    func willEnterForeground() {
        session.onForeground()
    }

    // MARK: Effects

    private func handle(_ effect: SessionEffect) {
        switch effect {
        case .sound(let kind):
            tones.play(kind)
        case .chipFlight(let seat):
            nextFlightId += 1
            chipFlights.append(ChipFlight(id: nextFlightId, seat: seat))
            if chipFlights.count > 12 { chipFlights.removeFirst(chipFlights.count - 12) }
        case .cancelChipFlights:
            chipFlights.removeAll()
        case .revealToggled:
            break
        }
    }

    /// The public table snapshot as one line for UI tests, plus the settled
    /// board size, whether a practice runout is shown, and the Hand Review
    /// status. Reads `state` so SwiftUI refreshes it after every change.
    var probeText: String {
        let review = state.review
        let snapshot = session.publicSnapshot()
        return [
            snapshot.probeText,
            "settlement=\(snapshot.settlementBoard.count)",
            "practice=\(snapshot.practiceRunout ? 1 : 0)",
            "review=\(review.status.rawValue)",
            "reviewOpen=\(review.dialogOpen ? 1 : 0)",
        ].joined(separator: ";")
    }

    func finishFlight(_ id: Int) {
        chipFlights.removeAll { $0.id == id }
    }
}
