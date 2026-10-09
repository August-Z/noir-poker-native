import Foundation
import PokerCore

/// Preference storage over `UserDefaults` (the reference's localStorage keys).
/// By default it uses the launch's preference domain: `.standard`, or the
/// UI-test suite in debug UI-test launches (see `LaunchOptions`).
final class UserDefaultsStorage: KeyValueStorage {
    private let defaults: UserDefaults

    init(_ defaults: UserDefaults = LaunchOptions.current.defaults) { self.defaults = defaults }

    func getString(_ key: String) throws -> String? { defaults.string(forKey: key) }

    func putString(_ key: String, _ value: String) throws { defaults.set(value, forKey: key) }
}
