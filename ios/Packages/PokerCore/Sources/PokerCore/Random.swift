/// The single source of randomness for the engine. `next()` returns a value in
/// `[0, 1)`, like JavaScript's `Math.random()`. Every engine function consumes
/// values in exactly the same order and count as the reference.
public protocol RandomSource: AnyObject {
    func next() -> Double
}

/// Production randomness. Not reproducible.
public final class SystemRandom: RandomSource, @unchecked Sendable {
    public static let shared = SystemRandom()
    private var generator = SystemRandomNumberGenerator()
    public init() {}
    public func next() -> Double { Double.random(in: 0..<1, using: &generator) }
}

/// Exact port of the reference `seedRandom` (Mulberry32, `src/review/equity.js`).
///
/// The reference keeps its counter as a JavaScript number that grows without
/// wrapping; every bitwise operator then reduces it modulo 2^32. The counter is
/// kept as a `Double` here so the stream stays identical even after the
/// counter passes 2^53, where JavaScript addition starts rounding.
public final class SeededRandom: RandomSource {
    private var value: Double

    /// `seed` is interpreted as an unsigned 32-bit integer (`seed >>> 0`).
    public init(_ seed: UInt32) {
        value = Double(seed)
    }

    /// Any integer seed, reduced modulo 2^32 like `seed >>> 0`.
    public convenience init(seed: Int) {
        self.init(UInt32(truncatingIfNeeded: seed))
    }

    public func next() -> Double {
        value += 1_831_565_813 // 0x6d2b79f5
        var x = UInt32(value.truncatingRemainder(dividingBy: 4_294_967_296))
        x = (x ^ (x >> 15)) &* (x | 1)
        x ^= x &+ ((x ^ (x >> 7)) &* (x | 61))
        return Double(x ^ (x >> 14)) / 4_294_967_296
    }
}

/// Wraps a source and counts the values drawn from it (fixtures report draw counts).
public final class CountingRandom: RandomSource {
    public let base: RandomSource
    public private(set) var draws = 0
    public init(_ base: RandomSource) { self.base = base }
    public func next() -> Double {
        draws += 1
        return base.next()
    }
}

/// A source that always returns the same value (used by reference tests).
public final class ConstantRandom: RandomSource {
    public let value: Double
    public init(_ value: Double) { self.value = value }
    public func next() -> Double { value }
}

/// JavaScript `Math.round`: halves round toward positive infinity.
public func jsRound(_ x: Double) -> Double {
    if x.isNaN || x.isInfinite { return x }
    let r = x.rounded(.down)
    return x - r >= 0.5 ? r + 1 : r
}

/// `Math.round(n).toLocaleString('en-US')` for chip amounts: `1800` → `1,800`.
public func formatChips(_ n: Int) -> String {
    let digits = String(n.magnitude)
    var grouped = ""
    for (i, c) in digits.enumerated() {
        if i > 0 && (digits.count - i) % 3 == 0 { grouped.append(",") }
        grouped.append(c)
    }
    return (n < 0 ? "-" : "") + grouped
}

public func formatChips(_ n: Double) -> String {
    formatChips(Int(jsRound(n)))
}

/// Thrown wherever the reference engine throws. `code` is the stable identifier
/// used by the shared fixtures; `message` is the English copy.
public struct PokerError: Error, Equatable, CustomStringConvertible, Sendable {
    public enum Code: String, Sendable, CaseIterable {
        case invalidPlayerCount = "invalid-player-count"
        case settingsLocked = "settings-locked"
        case handInProgress = "hand-in-progress"
        case replayUnavailable = "replay-unavailable"
        case notYourTurn = "not-your-turn"
        case unknownAction = "unknown-action"
        case cannotCheck = "cannot-check"
        case illegalRaise = "illegal-raise"
        case roundNotFinished = "round-not-finished"
        case handNotSettled = "hand-not-settled"
        case showdownNeedsBoard = "showdown-needs-board"
        case alreadySettled = "already-settled"
        case noEligiblePlayer = "no-eligible-player"
        case potMismatch = "pot-mismatch"
        case invalidTrials = "invalid-trials"
        case botCannotAct = "bot-cannot-act"
        case heroBotExecutor = "hero-bot-executor"
        case staleBotPlan = "stale-bot-plan"
    }

    public let code: Code
    public var message: String { EngineCopy.errorMessage(code) }
    public var description: String { message }

    public init(_ code: Code) { self.code = code }
}
