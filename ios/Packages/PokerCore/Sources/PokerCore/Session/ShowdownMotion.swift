// The showdown card motions of the reference (`styles/showdown.css`, visual
// spec 10.2–10.3) as keyframes the app samples on every frame. Mirrors the
// Kotlin `com.august.noirpoker.ui.table.CardMotion`.
//
// Values are CSS units: points for translation, degrees for rotation, and a
// factor for scale, opacity and brightness. As in CSS, the timing function
// applies to each keyframe interval, a transform missing from a keyframe is the
// identity, and opacity and brightness interpolate only between the keyframes
// that set them (an unset end is the element's own value, 1).

/// One card's transform at a moment of its showdown motion.
public struct CardPose: Equatable, Sendable {
    public var tx: Double = 0
    public var ty: Double = 0
    /// Rotation in the card plane, in degrees.
    public var rz: Double = 0
    /// Rotation around the vertical axis, in degrees.
    public var ry: Double = 0
    public var scale: Double = 1
    public var alpha: Double = 1
    /// CSS `filter: brightness()` factor; 1 is unchanged.
    public var brightness: Double = 1

    public init(tx: Double = 0, ty: Double = 0, rz: Double = 0, ry: Double = 0,
                scale: Double = 1, alpha: Double = 1, brightness: Double = 1) {
        self.tx = tx
        self.ty = ty
        self.rz = rz
        self.ry = ry
        self.scale = scale
        self.alpha = alpha
        self.brightness = brightness
    }

    public static let identity = CardPose()
}

/// A CSS `cubic-bezier(x1, y1, x2, y2)` timing function.
public struct MotionCurve: Equatable, Sendable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    /// CSS `ease-out`.
    public static let easeOut = MotionCurve(0, 0, 0.58, 1)
    /// CSS `ease-in-out`.
    public static let easeInOut = MotionCurve(0.42, 0, 0.58, 1)
    /// `rank-arrive` (`.winning-card`).
    public static let arrive = MotionCurve(0.18, 0.7, 0.25, 1)
    /// `house-lock`.
    public static let fullHouse = MotionCurve(0.2, 0.8, 0.2, 1)

    private func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }

    private func slopeX(_ t: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * x1 + 6 * u * t * (x2 - x1) + 3 * t * t * (1 - x2)
    }

    /// The eased progress for linear progress `x` (0…1).
    public func transform(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        // Newton's method, then bisection if it does not converge.
        var t = x
        for _ in 0..<8 {
            let error = bezier(t, x1, x2) - x
            if abs(error) < 1e-7 { return bezier(t, y1, y2) }
            let slope = slopeX(t)
            if abs(slope) < 1e-7 { break }
            t -= error / slope
        }
        var low = 0.0
        var high = 1.0
        t = x
        for _ in 0..<64 {
            let value = bezier(t, x1, x2)
            if abs(value - x) < 1e-7 { break }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return bezier(t, y1, y2)
    }
}

/// One keyframe of a showdown motion. `alpha` and `brightness` are nil when the
/// CSS keyframe does not set them.
public struct CardMotionKey: Equatable, Sendable {
    public var at: Double
    public var tx: Double = 0
    public var ty: Double = 0
    public var rz: Double = 0
    public var ry: Double = 0
    public var scale: Double = 1
    public var alpha: Double? = nil
    public var brightness: Double? = nil

    public init(_ at: Double, tx: Double = 0, ty: Double = 0, rz: Double = 0, ry: Double = 0,
                scale: Double = 1, alpha: Double? = nil, brightness: Double? = nil) {
        self.at = at
        self.tx = tx
        self.ty = ty
        self.rz = rz
        self.ry = ry
        self.scale = scale
        self.alpha = alpha
        self.brightness = brightness
    }
}

/// One card's animation: duration, delay, timing function and keyframes.
public struct CardMotion: Equatable, Sendable {
    public let durationMs: Int
    public let delayMs: Int
    public let curve: MotionCurve
    public let keys: [CardMotionKey]

    public init(durationMs: Int, delayMs: Int, curve: MotionCurve, keys: [CardMotionKey]) {
        self.durationMs = durationMs
        self.delayMs = delayMs
        self.curve = curve
        self.keys = keys
    }

    /// When the motion ends, in milliseconds after the scene appears.
    public var endMs: Int { delayMs + durationMs }

    /// The resting pose after the motion (`fill-mode: both`).
    public var final: CardPose { pose(atMs: Double(endMs)) }

    /// The pose `timeMs` after the scene appeared. Before the delay the card
    /// holds the first keyframe (`fill-mode: both`).
    public func pose(atMs timeMs: Double) -> CardPose {
        let t = min(max((timeMs - Double(delayMs)) / Double(durationMs), 0), 1)
        let all = keys.map { (at: $0.at, key: $0) }
        return CardPose(
            tx: sample(t, all.map { ($0.at, $0.key.tx) }),
            ty: sample(t, all.map { ($0.at, $0.key.ty) }),
            rz: sample(t, all.map { ($0.at, $0.key.rz) }),
            ry: sample(t, all.map { ($0.at, $0.key.ry) }),
            scale: sample(t, all.map { ($0.at, $0.key.scale) }),
            alpha: sample(t, sparse(\.alpha)),
            brightness: sample(t, sparse(\.brightness)))
    }

    /// The keyframes that set an optional property, with an implicit 1 at 0 % and 100 %.
    private func sparse(_ property: KeyPath<CardMotionKey, Double?>) -> [(Double, Double)] {
        var list = keys.compactMap { key in key[keyPath: property].map { (key.at, $0) } }
        if !list.contains(where: { $0.0 == 0 }) { list.insert((0, 1), at: 0) }
        if !list.contains(where: { $0.0 == 1 }) { list.append((1, 1)) }
        return list
    }

    private func sample(_ t: Double, _ stops: [(Double, Double)]) -> Double {
        guard let first = stops.first else { return 0 }
        if t <= first.0 { return first.1 }
        for k in 1..<stops.count {
            let a = stops[k - 1]
            let b = stops[k]
            if t <= b.0 {
                let span = b.0 - a.0
                guard span > 0 else { return b.1 }
                return a.1 + (b.1 - a.1) * curve.transform((t - a.0) / span)
            }
        }
        return stops[stops.count - 1].1
    }

    /// `rank-arrive`: every card that has no winner motion.
    public static func arrive(_ i: Int) -> CardMotion {
        CardMotion(durationMs: 800, delayMs: i * 80, curve: .arrive,
                   keys: [CardMotionKey(0, ty: 18, ry: 45, alpha: 0), CardMotionKey(1, alpha: 1)])
    }

    /// Whether `motion` moves every card, or only the cards that make the
    /// category (`.rank-match`) while the kickers keep `rank-arrive`.
    public static func appliesToAll(_ motion: HandMotion) -> Bool {
        switch motion {
        case .straight, .flush, .fullHouse, .straightFlush, .royal: return true
        case .high, .pair, .twoPair, .trips, .quads: return false
        }
    }

    /// The motion of card `i` (0–4) in a showdown panel: the hand category's
    /// motion on a winner's moving cards, `rank-arrive` everywhere else.
    public static func forCard(_ i: Int, motion: HandMotion, winner: Bool, match: Bool) -> CardMotion {
        guard winner, appliesToAll(motion) || match else { return arrive(i) }
        return Self.winner(motion, index: i)
    }

    /// The winner motion for card `i` (0–4) of a `motion` hand.
    public static func winner(_ motion: HandMotion, index i: Int) -> CardMotion {
        let fi = Double(i)
        let c = fi - 2
        switch motion {
        case .high:
            return CardMotion(durationMs: 1700, delayMs: 0, curve: .easeOut, keys: [
                CardMotionKey(0, scale: 0.7, brightness: 0.6),
                CardMotionKey(0.4, ty: -10, scale: 1.12, brightness: 1.12),
                CardMotionKey(1, ty: -5, brightness: 1),
            ])
        case .pair:
            return CardMotion(durationMs: 1500, delayMs: i * 60, curve: .easeOut, keys: [
                CardMotionKey(0, ty: 14, alpha: 0),
                CardMotionKey(0.3, ty: -4, scale: 1.08),
                CardMotionKey(0.45, alpha: 1),
                CardMotionKey(0.65, ty: -4, scale: 1.08),
                CardMotionKey(1, alpha: 1),
            ])
        case .twoPair:
            return CardMotion(durationMs: 1600, delayMs: i * 90, curve: .easeOut, keys: [
                CardMotionKey(0, tx: (1.5 - fi) * 14, rz: (fi - 1.5) * 8, alpha: 0),
                CardMotionKey(0.55, ty: -7),
                CardMotionKey(1, alpha: 1),
            ])
        case .trips:
            return CardMotion(durationMs: 1600, delayMs: i * 150, curve: .easeOut, keys: [
                CardMotionKey(0, ty: 24, alpha: 0),
                CardMotionKey(0.45, ty: -12),
                CardMotionKey(0.7, ty: 3),
                CardMotionKey(1, alpha: 1),
            ])
        case .straight:
            return CardMotion(durationMs: 1600, delayMs: i * 140, curve: .easeOut, keys: [
                CardMotionKey(0, ty: 20, ry: 90, alpha: 0),
                CardMotionKey(0.5, ty: -7, alpha: 1),
                CardMotionKey(1),
            ])
        case .flush:
            return CardMotion(durationMs: 1800, delayMs: i * 100, curve: .easeInOut, keys: [
                CardMotionKey(0, ty: 10, rz: -8, alpha: 0),
                CardMotionKey(0.35, ty: -10, rz: 5, brightness: 1.12),
                CardMotionKey(0.7, ty: 4, rz: -2),
                CardMotionKey(1, alpha: 1, brightness: 1),
            ])
        case .fullHouse:
            return CardMotion(durationMs: 1800, delayMs: i * 80, curve: .fullHouse, keys: [
                CardMotionKey(0, tx: c * 20, ty: 14, alpha: 0),
                CardMotionKey(0.5, tx: -c * 3, ty: -4),
                CardMotionKey(1, alpha: 1),
            ])
        case .quads:
            return CardMotion(durationMs: 1800, delayMs: i * 60, curve: .easeOut, keys: [
                CardMotionKey(0, scale: 0.6, alpha: 0),
                CardMotionKey(0.25, scale: 1.14, brightness: 1.16),
                CardMotionKey(0.45, scale: 0.96),
                CardMotionKey(0.65, scale: 1.04),
                CardMotionKey(1, alpha: 1, brightness: 1),
            ])
        case .straightFlush:
            return CardMotion(durationMs: 1900, delayMs: i * 100, curve: .easeOut, keys: [
                CardMotionKey(0, ty: 28, ry: 100, alpha: 0),
                CardMotionKey(0.4, ty: c * c * -3 - 7, alpha: 1, brightness: 1.15),
                CardMotionKey(1, brightness: 1),
            ])
        case .royal:
            return CardMotion(durationMs: 2000, delayMs: i * 60, curve: .easeOut, keys: [
                CardMotionKey(0, tx: -c * 40, rz: c * 14, alpha: 0),
                CardMotionKey(0.5, ty: -10, rz: c * 5, alpha: 1, brightness: 1.14),
                CardMotionKey(1, rz: c * 2, brightness: 1),
            ])
        }
    }
}
