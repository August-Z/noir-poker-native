// Persisted options (`preferences.js`, the storage half of
// `opponents-controller.js`, and the sound and hints toggles).

/// String key-value storage (`UserDefaults` in the app). Either call may throw;
/// the store treats a failure as "unavailable" and falls back to defaults, like
/// the reference's `localStorage` wrappers.
public protocol KeyValueStorage: AnyObject {
    func getString(_ key: String) throws -> String?
    func putString(_ key: String, _ value: String) throws
}

/// A plain in-memory storage, for tests and previews.
public final class InMemoryStorage: KeyValueStorage {
    public var values: [String: String]
    public init(_ initial: [String: String] = [:]) { values = initial }
    public func getString(_ key: String) throws -> String? { values[key] }
    public func putString(_ key: String, _ value: String) throws { values[key] = value }
}

/// Seat count and difficulty, persisted as `{"playerCount":6,"difficulty":"normal"}`.
public struct TablePreferences: Equatable, Sendable {
    public static let defaultPlayerCount = 6

    public var playerCount: Int
    public var difficulty: Difficulty

    public init(playerCount: Int = TablePreferences.defaultPlayerCount, difficulty: Difficulty = .normal) {
        self.playerCount = playerCount
        self.difficulty = difficulty
    }

    /// The reference `tablePreferences(value)`: each field is validated on its
    /// own. `playerCount` must be an integral JSON number 5–9 (`6.0` counts,
    /// `"9"` and `6.5` do not); `difficulty` must be `easy`, `normal` or `hard`.
    public static func sanitize(_ value: MiniJSON.Value?) -> TablePreferences {
        var result = TablePreferences()
        guard case .object(let fields)? = value else { return result }
        if case .number(let n)? = fields.last(where: { $0.key == "playerCount" })?.value,
           n.isFinite, n == n.rounded(.down), n >= Double(MIN_PLAYERS), n <= Double(MAX_PLAYERS) {
            result.playerCount = Int(n)
        }
        if case .string(let s)? = fields.last(where: { $0.key == "difficulty" })?.value,
           let d = Difficulty(rawValue: s) {
            result.difficulty = d
        }
        return result
    }
}

/// The reference's persisted options. Only these four keys are ever written;
/// cards, stacks, history and statistics are never persisted.
public final class PreferencesStore {
    public static let tableKey = "noir-table-v1"
    public static let opponentsKey = "noir-opponents-v1"
    public static let soundKey = "noir-sound"
    public static let hintsKey = "noir-hints"

    private let storage: KeyValueStorage

    public init(_ storage: KeyValueStorage) { self.storage = storage }

    private func read(_ key: String) -> String? { (try? storage.getString(key)) ?? nil }

    private func write(_ key: String, _ value: String) {
        // Storage can be unavailable; the current table keeps the selection.
        try? storage.putString(key, value)
    }

    /// `JSON.parse(getItem(key))`: a missing value parses as `null`; invalid JSON yields `nil`.
    private func parse(_ key: String) -> MiniJSON.Value? { try? MiniJSON.parse(read(key) ?? "null") }

    public func loadTable() -> TablePreferences { TablePreferences.sanitize(parse(Self.tableKey)) }

    /// Writes only `playerCount` and `difficulty`, sanitized.
    public func saveTable(_ value: TablePreferences) {
        let clean = TablePreferences.sanitize(.object([
            (key: "playerCount", value: .number(Double(value.playerCount))),
            (key: "difficulty", value: .string(value.difficulty.rawValue)),
        ]))
        write(Self.tableKey, MiniJSON.stringify(.object([
            (key: "playerCount", value: .number(Double(clean.playerCount))),
            (key: "difficulty", value: .string(clean.difficulty.rawValue)),
        ])))
    }

    public func loadBotSettings() -> BotSettings {
        guard let value = parse(Self.opponentsKey) else { return defaultBotSettings() }
        return sanitizeBotSettings(value.anyValue)
    }

    public func saveBotSettings(_ settings: BotSettings) {
        let clean = sanitizeBotSettings(settings)
        let assignments = (1...8).map { (key: String($0), value: MiniJSON.Value.string(clean.assignments[$0] ?? "balanced")) }
        write(Self.opponentsKey, MiniJSON.stringify(.object([
            (key: "emotionMode", value: .string(clean.emotionMode.rawValue)),
            (key: "assignments", value: .object(assignments)),
        ])))
    }

    /// Sound is on only when the stored value is exactly `true`.
    public func loadSound() -> Bool { read(Self.soundKey) == "true" }

    public func saveSound(_ on: Bool) { write(Self.soundKey, on ? "true" : "false") }

    /// Hints are off only when the stored value is exactly `false`.
    public func loadHints() -> Bool { read(Self.hintsKey) != "false" }

    public func saveHints(_ on: Bool) { write(Self.hintsKey, on ? "true" : "false") }
}

/// A JSON `null` inside an array handed to `sanitizeBotSettings` (keeps indexes).
public struct JSONNull: Equatable, Sendable {}

/// A minimal JSON reader and writer for the persisted preferences, so the domain
/// package needs no Foundation. Numbers parse as `Double` like JavaScript;
/// objects keep their key order.
public enum MiniJSON {
    public indirect enum Value: Equatable, Sendable {
        case null
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([Value])
        case object([(key: String, value: Value)])

        public static func == (a: Value, b: Value) -> Bool {
            switch (a, b) {
            case (.null, .null): return true
            case (.bool(let x), .bool(let y)): return x == y
            case (.number(let x), .number(let y)): return x == y
            case (.string(let x), .string(let y)): return x == y
            case (.array(let x), .array(let y)): return x == y
            case (.object(let x), .object(let y)):
                return x.count == y.count && zip(x, y).allSatisfy { $0.key == $1.key && $0.value == $1.value }
            default: return false
            }
        }

        /// The value as untyped Swift data (`[String: Any]`, `[Any]`, `String`,
        /// `Double`, `Bool`), the shape `sanitizeBotSettings` accepts. Object
        /// members that are `null` are dropped (the same as absent); array nulls
        /// become `JSONNull` so indexes are kept. A repeated key keeps the last
        /// value, like `JSON.parse`.
        public var anyValue: Any {
            switch self {
            case .null: return JSONNull()
            case .bool(let b): return b
            case .number(let n): return n
            case .string(let s): return s
            case .array(let items): return items.map(\.anyValue)
            case .object(let fields):
                var out: [String: Any] = [:]
                for (k, v) in fields {
                    if case .null = v { out[k] = nil } else { out[k] = v.anyValue }
                }
                return out
            }
        }
    }

    public struct ParseError: Error, Equatable, Sendable {
        public let message: String
    }

    public static func parse(_ text: String) throws -> Value {
        var p = Parser(Array(text.unicodeScalars))
        p.ws()
        let v = try p.value()
        p.ws()
        if !p.end { throw ParseError(message: "Unexpected trailing input") }
        return v
    }

    public static func stringify(_ value: Value) -> String {
        var out = ""
        write(&out, value)
        return out
    }

    private static func write(_ out: inout String, _ value: Value) {
        switch value {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n):
            if n.isFinite, n == n.rounded(.down), abs(n) < 1e15 { out += String(Int(n)) } else { out += String(n) }
        case .string(let s): quote(&out, s)
        case .array(let items):
            out += "["
            for (i, v) in items.enumerated() {
                if i > 0 { out += "," }
                write(&out, v)
            }
            out += "]"
        case .object(let fields):
            out += "{"
            for (i, f) in fields.enumerated() {
                if i > 0 { out += "," }
                quote(&out, f.key)
                out += ":"
                write(&out, f.value)
            }
            out += "}"
        }
    }

    private static let hexDigits = Array("0123456789abcdef")

    private static func quote(_ out: inout String, _ s: String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 {
                    out += "\\u00" + String(hexDigits[Int(u.value >> 4)]) + String(hexDigits[Int(u.value & 15)])
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
    }

    private struct Parser {
        let s: [Unicode.Scalar]
        var i = 0
        init(_ s: [Unicode.Scalar]) { self.s = s }

        var end: Bool { i >= s.count }

        mutating func ws() {
            while i < s.count, s[i] == " " || s[i] == "\t" || s[i] == "\n" || s[i] == "\r" { i += 1 }
        }

        func fail(_ what: String) -> ParseError { ParseError(message: "\(what) at \(i)") }

        static func isDigit(_ c: Unicode.Scalar) -> Bool { c >= "0" && c <= "9" }

        mutating func value() throws -> Value {
            guard !end else { throw fail("Unexpected end") }
            switch s[i] {
            case "{": return try object()
            case "[": return try array()
            case "\"": return .string(try string())
            case "t": return try literal("true", .bool(true))
            case "f": return try literal("false", .bool(false))
            case "n": return try literal("null", .null)
            default:
                if s[i] == "-" || Parser.isDigit(s[i]) { return .number(try number()) }
                throw fail("Unexpected character")
            }
        }

        mutating func literal(_ word: String, _ v: Value) throws -> Value {
            for u in word.unicodeScalars {
                guard i < s.count, s[i] == u else { throw fail("Invalid literal") }
                i += 1
            }
            return v
        }

        mutating func object() throws -> Value {
            var fields: [(key: String, value: Value)] = []
            i += 1
            ws()
            if !end, s[i] == "}" {
                i += 1
                return .object(fields)
            }
            while true {
                ws()
                guard !end, s[i] == "\"" else { throw fail("Expected key") }
                let k = try string()
                ws()
                guard !end, s[i] == ":" else { throw fail("Expected ':'") }
                i += 1
                ws()
                fields.append((key: k, value: try value()))
                ws()
                guard !end else { throw fail("Unterminated object") }
                if s[i] == "," {
                    i += 1
                    continue
                }
                if s[i] == "}" {
                    i += 1
                    return .object(fields)
                }
                throw fail("Expected ',' or '}'")
            }
        }

        mutating func array() throws -> Value {
            var items: [Value] = []
            i += 1
            ws()
            if !end, s[i] == "]" {
                i += 1
                return .array(items)
            }
            while true {
                ws()
                items.append(try value())
                ws()
                guard !end else { throw fail("Unterminated array") }
                if s[i] == "," {
                    i += 1
                    continue
                }
                if s[i] == "]" {
                    i += 1
                    return .array(items)
                }
                throw fail("Expected ',' or ']'")
            }
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= s.count else { throw fail("Bad unicode escape") }
            var v: UInt32 = 0
            for _ in 0..<4 {
                let c = s[i]
                let d: UInt32
                if c >= "0" && c <= "9" { d = c.value - 48 }
                else if c >= "a" && c <= "f" { d = c.value - 87 }
                else if c >= "A" && c <= "F" { d = c.value - 55 }
                else { throw fail("Bad unicode escape") }
                v = v * 16 + d
                i += 1
            }
            return v
        }

        mutating func string() throws -> String {
            var out = String.UnicodeScalarView()
            i += 1
            while true {
                guard !end else { throw fail("Unterminated string") }
                let c = s[i]
                i += 1
                if c == "\"" { return String(out) }
                if c == "\\" {
                    guard !end else { throw fail("Bad escape") }
                    let e = s[i]
                    i += 1
                    switch e {
                    case "\"": out.append("\"")
                    case "\\": out.append("\\")
                    case "/": out.append("/")
                    case "b": out.append("\u{08}")
                    case "f": out.append("\u{0C}")
                    case "n": out.append("\n")
                    case "r": out.append("\r")
                    case "t": out.append("\t")
                    case "u":
                        var code = try hex4()
                        // A surrogate pair encodes one scalar; a lone surrogate becomes U+FFFD.
                        if code >= 0xD800 && code < 0xDC00, i + 6 <= s.count, s[i] == "\\", s[i + 1] == "u" {
                            let save = i
                            i += 2
                            let low = try hex4()
                            if low >= 0xDC00 && low < 0xE000 {
                                code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                            } else {
                                i = save
                            }
                        }
                        out.append(Unicode.Scalar(code) ?? "\u{FFFD}")
                    default: throw fail("Bad escape")
                    }
                } else if c.value < 0x20 {
                    throw fail("Control character in string")
                } else {
                    out.append(c)
                }
            }
        }

        mutating func number() throws -> Double {
            let start = i
            if s[i] == "-" { i += 1 }
            guard !end else { throw fail("Bad number") }
            if s[i] == "0" {
                i += 1
            } else if Parser.isDigit(s[i]) {
                while !end, Parser.isDigit(s[i]) { i += 1 }
            } else {
                throw fail("Bad number")
            }
            if !end, s[i] == "." {
                i += 1
                guard !end, Parser.isDigit(s[i]) else { throw fail("Bad fraction") }
                while !end, Parser.isDigit(s[i]) { i += 1 }
            }
            if !end, s[i] == "e" || s[i] == "E" {
                i += 1
                if !end, s[i] == "+" || s[i] == "-" { i += 1 }
                guard !end, Parser.isDigit(s[i]) else { throw fail("Bad exponent") }
                while !end, Parser.isDigit(s[i]) { i += 1 }
            }
            var text = ""
            text.unicodeScalars.append(contentsOf: s[start..<i])
            guard let n = Double(text) else { throw fail("Bad number") }
            return n
        }
    }
}
