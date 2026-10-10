import Foundation
import XCTest
@testable import PokerCore

/// The linear congruential generator the reference unit tests use (`seeded`).
final class LCGRandom: RandomSource {
    private var n: UInt32
    init(_ seed: UInt32) { n = seed }
    func next() -> Double {
        n = n &* 1_664_525 &+ 1_013_904_223
        return Double(n) / 4_294_967_296
    }
}

/// A random source backed by a closure.
final class ClosureRandom: RandomSource {
    private let body: () -> Double
    init(_ body: @escaping () -> Double) { self.body = body }
    func next() -> Double { body() }
}

/// Fails the test if the engine draws any value.
final class ForbiddenRandom: RandomSource {
    func next() -> Double {
        XCTFail("This operation must not draw randomness")
        return 0
    }
}

func cards(_ s: String) -> [Card] { parseCards(s) }

func chips(_ g: Game) -> Int { g.players.reduce(0) { $0 + $1.stack } }

/// Stacks plus chips still in the pot.
func wealth(_ g: Game) -> Int { chips(g) + (g.phase == .done ? 0 : potSize(g)) }

/// Plays the hand out with one fixed action (call, check or fold), advancing streets.
func finish(_ g: Game, _ action: PokerAction = .call, file: StaticString = #filePath, line: UInt = #line) throws {
    var limit = 0
    while g.phase != .done {
        limit += 1
        XCTAssertLessThan(limit, 1000, "hand stalled", file: file, line: line)
        if limit >= 1000 { return }
        if g.phase == .between { try advanceStreet(g) } else { try act(g, g.actor, action) }
    }
}

/// Plays the hand out with bot decisions for every seat, checking legality.
func finishWithBots(_ g: Game, _ random: RandomSource, file: StaticString = #filePath, line: UInt = #line) throws {
    var actions = 0
    while g.phase != .done {
        actions += 1
        XCTAssertLessThan(actions, 1000, "A hand must finish", file: file, line: line)
        if actions >= 1000 { return }
        if g.phase == .between {
            try advanceStreet(g)
            continue
        }
        let d = try botDecision(g, random: random)
        let legal = legalActions(g)
        if d.action == .raise {
            XCTAssertTrue(legal.canRaise, file: file, line: line)
            XCTAssertTrue((legal.minRaiseTo...legal.maxRaiseTo).contains(d.amount ?? -1), file: file, line: line)
        }
        if d.action == .check { XCTAssertTrue(legal.canCheck, file: file, line: line) }
        try act(g, g.actor, d.action, d.amount)
    }
}

func assertThrowsPoker(_ code: PokerError.Code, file: StaticString = #filePath, line: UInt = #line,
                       _ body: () throws -> Void) {
    do {
        try body()
        XCTFail("Expected \(code.rawValue)", file: file, line: line)
    } catch let error as PokerError {
        XCTAssertEqual(error.code, code, file: file, line: line)
    } catch {
        XCTFail("Unexpected error \(error)", file: file, line: line)
    }
}

/// Repository root (fixtures live in `fixtures/`; they are test inputs, never bundled).
let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

func loadFixture(_ name: String) throws -> [String: Any] {
    let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("fixtures").appendingPathComponent(name))
    var parser = FixtureJSON(Array(data))
    return try XCTUnwrap(try parser.parseDocument() as? [String: Any])
}

/// A small JSON reader for fixtures. `JSONSerialization` on Linux does not
/// round every double correctly, while fixtures compare doubles exactly.
/// Integers become `Int`, other numbers `Double` (via correctly rounded
/// `Double(String)`), `null` becomes `NSNull`.
struct FixtureJSON {
    struct ParseError: Error { let offset: Int }
    private let bytes: [UInt8]
    private var i = 0
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func parseDocument() throws -> Any {
        let value = try parseValue()
        skipSpace()
        guard i == bytes.count else { throw ParseError(offset: i) }
        return value
    }

    private mutating func skipSpace() {
        while i < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[i]) { i += 1 }
    }

    private mutating func expect(_ literal: String) throws {
        for b in literal.utf8 {
            guard i < bytes.count, bytes[i] == b else { throw ParseError(offset: i) }
            i += 1
        }
    }

    private mutating func parseValue() throws -> Any {
        skipSpace()
        guard i < bytes.count else { throw ParseError(offset: i) }
        switch bytes[i] {
        case UInt8(ascii: "{"):
            i += 1
            var object: [String: Any] = [:]
            skipSpace()
            if bytes[i] == UInt8(ascii: "}") { i += 1; return object }
            while true {
                skipSpace()
                let key = try parseString()
                skipSpace()
                try expect(":")
                object[key] = try parseValue()
                skipSpace()
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                try expect("}")
                return object
            }
        case UInt8(ascii: "["):
            i += 1
            var array: [Any] = []
            skipSpace()
            if bytes[i] == UInt8(ascii: "]") { i += 1; return array }
            while true {
                array.append(try parseValue())
                skipSpace()
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                try expect("]")
                return array
            }
        case UInt8(ascii: "\""):
            return try parseString()
        case UInt8(ascii: "t"):
            try expect("true")
            return true
        case UInt8(ascii: "f"):
            try expect("false")
            return false
        case UInt8(ascii: "n"):
            try expect("null")
            return NSNull()
        default:
            let start = i
            var integral = true
            while i < bytes.count, let c = Optional(bytes[i]),
                  (c >= 0x30 && c <= 0x39) || c == UInt8(ascii: "-") || c == UInt8(ascii: "+") ||
                  c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E") {
                if c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E") { integral = false }
                i += 1
            }
            let text = String(decoding: bytes[start..<i], as: UTF8.self)
            if integral, let n = Int(text) { return n }
            guard let d = Double(text) else { throw ParseError(offset: start) }
            return d
        }
    }

    private mutating func parseString() throws -> String {
        try expect("\"")
        var scalars = String.UnicodeScalarView()
        var raw: [UInt8] = []
        func flush() {
            if !raw.isEmpty {
                scalars.append(contentsOf: String(decoding: raw, as: UTF8.self).unicodeScalars)
                raw.removeAll()
            }
        }
        while true {
            guard i < bytes.count else { throw ParseError(offset: i) }
            let c = bytes[i]
            i += 1
            if c == UInt8(ascii: "\"") { break }
            if c != UInt8(ascii: "\\") {
                raw.append(c)
                continue
            }
            flush()
            let e = bytes[i]
            i += 1
            switch e {
            case UInt8(ascii: "n"): scalars.append("\n")
            case UInt8(ascii: "t"): scalars.append("\t")
            case UInt8(ascii: "r"): scalars.append("\r")
            case UInt8(ascii: "b"): scalars.append("\u{08}")
            case UInt8(ascii: "f"): scalars.append("\u{0C}")
            case UInt8(ascii: "u"):
                var code = try hex4()
                if (0xD800...0xDBFF).contains(code) {
                    try expect("\\u")
                    let low = try hex4()
                    code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                }
                scalars.append(Unicode.Scalar(code) ?? "\u{FFFD}")
            default: scalars.append(Unicode.Scalar(e))
            }
        }
        flush()
        return String(scalars)
    }

    private mutating func hex4() throws -> UInt32 {
        guard i + 4 <= bytes.count, let v = UInt32(String(decoding: bytes[i..<(i + 4)], as: UTF8.self), radix: 16) else {
            throw ParseError(offset: i)
        }
        i += 4
        return v
    }
}

/// Fixture numbers: `Int` or `Double`.
func fixtureInt(_ v: Any?) -> Int { (v as? Int) ?? Int((v as! Double)) }
func fixtureDouble(_ v: Any?) -> Double { (v as? Double) ?? Double(v as! Int) }
