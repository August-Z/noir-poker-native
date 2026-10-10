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
/// - `-noir-player-count <n>`: saves a 5–9 seat table preference before the
///   session starts (the saved difficulty is kept), so the first hand deals
///   `n` seats.
/// - `-noir-defaults-suite <name>`: keeps preferences in that `UserDefaults`
///   suite. UI-test launches use the `noir-ui-tests` suite by default, so
///   tests never read or clear the app's real preferences.
struct LaunchOptions {
    static let uiTestSuite = "noir-ui-tests"

    var uiTesting = false
    var seed: Int?
    var speed: Double = 1
    var resetPreferences = false
    var playerCount: Int?
    var defaultsSuite: String?

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
        playerCount = value(after: "-noir-player-count").flatMap { Int($0) }.flatMap { (5...9).contains($0) ? $0 : nil }
        defaultsSuite = value(after: "-noir-defaults-suite") ?? (uiTesting ? Self.uiTestSuite : nil)
        #endif
    }

    /// Where preferences live: `.standard`, or the UI-test suite.
    var defaults: UserDefaults {
        guard let defaultsSuite, let suite = UserDefaults(suiteName: defaultsSuite) else { return .standard }
        return suite
    }

    /// The session's random source.
    func makeRandom() -> RandomSource {
        if let seed { return SeededRandom(seed: seed) }
        return SystemRandom.shared
    }

    /// Clears the reference preference keys when asked, then saves the
    /// requested seat count, in `defaults` (the launch's preference domain
    /// unless a caller passes another).
    func prepareStorage(_ defaults: UserDefaults? = nil) {
        let target = defaults ?? self.defaults
        if resetPreferences {
            for key in [PreferencesStore.tableKey, PreferencesStore.opponentsKey,
                        PreferencesStore.soundKey, PreferencesStore.hintsKey] {
                target.removeObject(forKey: key)
            }
        }
        if let playerCount {
            let store = PreferencesStore(UserDefaultsStorage(target))
            var table = store.loadTable()
            table.playerCount = playerCount
            store.saveTable(table)
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
