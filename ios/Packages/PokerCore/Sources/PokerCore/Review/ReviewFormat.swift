// Number and text formatting that reproduces the reference review output
// exactly. Every formatter uses fixed en-US conventions, never the device
// locale. See docs/ARCHITECTURE.md ("Numeric rules that must match JavaScript").

enum ReviewFormat {
    /// `Math.round(v).toLocaleString('en-US')`. Negative zero prints as `"0"`
    /// (an intentional normalization shared with the Kotlin port; no review
    /// value the reference formats this way can be negative).
    static func number(_ v: Double) -> String { formatChips(v) }
    static func number(_ v: Int) -> String { formatChips(v) }

    /// `String(Math.round(v))`: an integer without grouping (big-blind counts).
    static func roundedInt(_ v: Double) -> String { String(Int(jsRound(v))) }

    /// Analysis `percent`: `Math.round(v * 100) + '%'`.
    static func percent(_ v: Double) -> String { String(Int(jsRound(v * 100))) + "%" }

    /// Opponent `pct`: `(v * 100).toFixed(1) + '%'`.
    static func pct(_ v: Double) -> String { jsToFixed(v * 100, 1) + "%" }

    /// `(v >= 0 ? '+' : '') + pct(v)`.
    static func signedPct(_ v: Double) -> String { (v >= 0 ? "+" : "") + pct(v) }

    /// `"1 player"` / `"2 players"`.
    static func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }

    static func cap(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    static func lowerFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.lowercased() + s.dropFirst()
    }

    /// The English port of the reference's direct sentence concatenation:
    /// non-empty fragments are trimmed and joined with one space.
    static func sentences(_ parts: String?...) -> String {
        parts.compactMap { $0 }
            .map { $0.trimmingSpaces() }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

extension String {
    fileprivate func trimmingSpaces() -> String {
        var s = Substring(self)
        while s.first == " " { s = s.dropFirst() }
        while s.last == " " { s = s.dropLast() }
        return String(s)
    }
}

/// JavaScript `Number.prototype.toFixed(digits)` for `digits` in `0...6`: the
/// exact binary value rounded half up (away from zero on the magnitude), with a
/// leading minus sign for negative inputs, including values that round to zero
/// (`(-0.0004).toFixed(1) == "-0.0"`). Swift's `%.1f` rounds exact ties to even,
/// so it cannot be used.
public func jsToFixed(_ x: Double, _ digits: Int) -> String {
    precondition((0...6).contains(digits))
    if x.isNaN { return "NaN" }
    if x.isInfinite { return x > 0 ? "Infinity" : "-Infinity" }
    if abs(x) >= 1e21 { return jsNumberString(x) }
    var scale: UInt64 = 1
    for _ in 0..<digits { scale *= 10 }
    let n = roundHalfUpScaled(abs(x), scale)
    var text = String(n)
    if digits > 0 {
        if text.count <= digits { text = String(repeating: "0", count: digits - text.count + 1) + text }
        text.insert(".", at: text.index(text.endIndex, offsetBy: -digits))
    }
    return (x < 0 ? "-" : "") + text
}

/// `floor(a * scale + 0.5)` computed exactly on the binary value of `a`
/// (`a >= 0`, `a * scale < 2^63`).
private func roundHalfUpScaled(_ a: Double, _ scale: UInt64) -> UInt64 {
    if a == 0 { return 0 }
    let fraction = a.significandBitPattern
    let biased = Int(a.exponentBitPattern)
    let mantissa: UInt64 = biased == 0 ? fraction : fraction | (1 << 52)
    let exponent = (biased == 0 ? 1 : biased) - 1075
    if exponent >= 0 { return (mantissa << UInt64(exponent)) * scale }
    // a * scale + 1/2 = (mantissa * 2 * scale + 2^k) / 2^(k + 1) with k = -exponent.
    let k = -exponent
    if k >= 120 { return 0 }
    var (hi, lo) = mantissa.multipliedFullWidth(by: scale * 2)
    // Add 2^k to the 128-bit value (hi, lo).
    if k < 64 {
        let (sum, overflow) = lo.addingReportingOverflow(1 << UInt64(k))
        lo = sum
        if overflow { hi &+= 1 }
    } else {
        hi &+= 1 << UInt64(k - 64)
    }
    // Shift right by k + 1.
    let shift = k + 1
    if shift >= 128 { return 0 }
    if shift >= 64 { return hi >> UInt64(shift - 64) }
    return (lo >> UInt64(shift)) | (hi << UInt64(64 - shift))
}

/// JavaScript `String(x)` (ECMAScript `Number::toString`) for the values the
/// review interpolates raw (style axes): the shortest round-trip digits, in plain
/// notation for `1e-7 <= |x| < 1e21` and in exponent notation (`1e-7`,
/// `1.5e+21`) otherwise. Negative zero prints `"0"`. Swift's `description`
/// supplies the same shortest digits but formats them differently (`1e-07`,
/// `100.0`, `1e+16`), so only its digits are used.
public func jsNumberString(_ x: Double) -> String {
    if x.isNaN { return "NaN" }
    if x.isInfinite { return x > 0 ? "Infinity" : "-Infinity" }
    if x == 0 { return "0" }
    let text = abs(x).description
    let parts = text.split(separator: "e", maxSplits: 1)
    let exponent = parts.count == 2 ? Int(parts[1])! : 0
    let mantissa = parts[0].split(separator: ".", maxSplits: 1)
    let integer = String(mantissa[0]), fraction = mantissa.count == 2 ? String(mantissa[1]) : ""
    // |x| = 0.digits × 10^n
    var digits = Array(integer + fraction)
    var n = integer.count + exponent
    while digits.first == "0" {
        digits.removeFirst()
        n -= 1
    }
    while digits.last == "0" { digits.removeLast() }
    let k = digits.count
    let body: String
    if k <= n && n <= 21 {
        body = String(digits) + String(repeating: "0", count: n - k)
    } else if 0 < n && n <= 21 {
        body = String(digits[..<n]) + "." + String(digits[n...])
    } else if -6 < n && n <= 0 {
        body = "0." + String(repeating: "0", count: -n) + String(digits)
    } else {
        let e = n - 1
        body = String(digits[0]) + (k > 1 ? "." + String(digits[1...]) : "") + "e" + (e < 0 ? "-" : "+") + String(abs(e))
    }
    return (x < 0 ? "-" : "") + body
}
