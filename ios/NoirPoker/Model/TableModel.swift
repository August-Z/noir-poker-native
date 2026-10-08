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

    init(storage: KeyValueStorage = UserDefaultsStorage(),
         scheduler: SessionScheduler = MainScheduler(),
         reviewRunner: ReviewRunner? = DetachedReviewRunner()) {
        let session = TableSession(scheduler: scheduler, storage: storage,
                                   random: SystemRandom.shared, reviewRunner: reviewRunner)
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

    func finishFlight(_ id: Int) {
        chipFlights.removeAll { $0.id == id }
    }
}
