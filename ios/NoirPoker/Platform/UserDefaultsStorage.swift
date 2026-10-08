import Foundation
import PokerCore

/// Preference storage over `UserDefaults` (the reference's localStorage keys).
final class UserDefaultsStorage: KeyValueStorage {
    private let defaults: UserDefaults

    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    func getString(_ key: String) throws -> String? { defaults.string(forKey: key) }

    func putString(_ key: String, _ value: String) throws { defaults.set(value, forKey: key) }
}
