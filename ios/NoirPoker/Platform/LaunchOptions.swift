import Foundation
import PokerCore

/// Launch options for UI tests. Debug builds only: release builds ignore every
/// argument and always use system randomness, real time and saved preferences.
///
/// - `-noir-ui-testing`: shows the public-state probe (`qa-state`).
/// - `-noir-seed <n>`: one seeded Mulberry32 stream for the shuffle, bots and
///   thinking times, so a test replays the same hands.
/// - `-noir-speed <x>`: runs the session clock `x` times faster (street
///   delays and bot thinking times shrink; their order is unchanged).
/// - `-noir-reset-preferences`: clears the saved table, opponent, hint and
///   sound preferences before the session starts.
struct LaunchOptions {
    var uiTesting = false
    var seed: Int?
    var speed: Double = 1
    var resetPreferences = false

    static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String]) {
        #if DEBUG
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        uiTesting = arguments.contains("-noir-ui-testing")
        seed = value(after: "-noir-seed").flatMap { Int($0) }
        if let raw = value(after: "-noir-speed"), let parsed = Double(raw), parsed >= 1, parsed <= 100 {
            speed = parsed
        }
        resetPreferences = arguments.contains("-noir-reset-preferences")
        #endif
    }

    /// The session's random source.
    func makeRandom() -> RandomSource {
        if let seed { return SeededRandom(seed: seed) }
        return SystemRandom.shared
    }

    /// Clears the reference preference keys from the persistent domain.
    func prepareStorage(_ defaults: UserDefaults = .standard) {
        guard resetPreferences else { return }
        for key in ["noir-table-v1", "noir-opponents-v1", "noir-sound", "noir-hints"] {
            defaults.removeObject(forKey: key)
        }
    }
}

extension PublicTableSnapshot {
    /// A compact, public-only description for UI tests: no hidden hole cards,
    /// bot plans or traces (the snapshot never holds them).
    var probeText: String {
        // Each player's chips before this street's bets: stack + street bet
        // while the hand is live, the stack once it is settled.
        let done = phase == "done"
        let totals = players.map { String(done ? $0.stack : $0.stack + $0.bet) }.joined(separator: ",")
        return [
            "hand=\(hand)",
            "phase=\(phase)",
            "players=\(playerCount)",
            "actor=\(actor ?? "-")",
            "replay=\(replayAttempt)",
            "stack=\(stack)",
            "wealth=\(wealth)",
            "totals=\(totals)",
            "hole=\(hole.joined(separator: " "))",
            "board=\(board.count)",
        ].joined(separator: ";")
    }
}
