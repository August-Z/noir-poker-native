import Foundation
import XCTest
@testable import PokerCore

/// Replays fixtures/review-decisions.json and fixtures/review-hands.json (generated
/// from the reference review modules, English copy from scripts/review-copy.mjs)
/// against the native review port. Every number and string must match exactly.
///
/// Optimized builds (`swift test -c release -Xswiftc -enable-testing`) or
/// `REVIEW_FIXTURES_FULL=1` check every case. Debug builds are roughly ten times
/// slower, so the expensive variants (600 samples, engine rollouts) run on a
/// fixed stride of cases there; the cheap functions always run on every case.
final class ReviewFixtureTests: XCTestCase {
    struct DecisionCase {
        let index: Int
        let name: String
        let raw: [String: Any]
        let snapshot: ReviewDecision?
    }

    static let decisionFile: [String: Any] = try! loadFixture("review-decisions.json")
    static let handFile: [String: Any] = try! loadFixture("review-hands.json")
    static let cases: [DecisionCase] = (decisionFile["cases"] as! [Any]).enumerated().map { i, item in
        let o = item as! [String: Any]
        return DecisionCase(index: i, name: o["name"] as! String, raw: o, snapshot: decodeDecision(o["snapshot"]))
    }
    #if DEBUG
    static let optimized = false
    #else
    static let optimized = true
    #endif
    static let full = optimized || ProcessInfo.processInfo.environment["REVIEW_FIXTURES_FULL"] == "1"
    static func sampled(_ index: Int, every stride: Int) -> Bool { full || index % stride == 0 }
    static let handStride = 3
    /// Decision cases referenced by the hands whose summaries are checked.
    static let summaryCases: Set<Int> = Set((handFile["hands"] as! [Any]).enumerated().flatMap { i, h in
        sampled(i, every: handStride) ? ((h as! [String: Any])["decisions"] as! [Any]).map(fixtureInt) : []
    })

    /// Cases whose snapshot has fractional chip totals (hand-built `pot: 75`) cannot be
    /// represented with integer chips; they are skipped and covered by unit tests.
    static var supported: [DecisionCase] { cases.filter { $0.snapshot != nil } }

    private static var reducedCache: [Int: DecisionAnalysis] = [:]
    private static var defaultCache: [Int: DecisionAnalysis] = [:]

    static func reduced(_ c: DecisionCase) throws -> DecisionAnalysis {
        if let hit = reducedCache[c.index] { return hit }
        let result = try analyzeDecision(c.snapshot!, trials: 60)
        reducedCache[c.index] = result
        return result
    }

    static func defaultAnalysis(_ c: DecisionCase) throws -> DecisionAnalysis {
        if let hit = defaultCache[c.index] { return hit }
        let result = try analyzeDecision(c.snapshot!)
        defaultCache[c.index] = result
        return result
    }

    static func runsDefault(_ index: Int) -> Bool { sampled(index, every: 24) }

    func testFixturesAreLoadedAndOnlyFractionalSnapshotsAreSkipped() {
        XCTAssertEqual(Self.cases.count, 164)
        let skipped = Self.cases.filter { $0.snapshot == nil }.map(\.name)
        XCTAssertEqual(skipped, ["review-context: deep pocket queens shove", "review-context: short aces shove"])
    }

    /// The functions that never read chip totals, on one case.
    private func checkTotalIndependent(_ c: DecisionCase, _ s: ReviewDecision) {
        let o = c.raw
        let label = "\(c.index) \(c.name)"
        XCTAssertEqual(startingTier(s.hole), fixtureInt(o["startingTier"]), "\(label) startingTier")
        assertReviewJSON(o["drawInfo"], enc(drawInfo(s.hole, s.board)), "\(label) drawInfo")
        assertReviewJSON(o["boardTexture"], enc(boardTexture(s.board)), "\(label) boardTexture")
        assertReviewJSON(o["decisionContext"], enc(decisionContext(s)), "\(label) decisionContext")
        assertReviewJSON(o["preflopContext"], enc(preflopContext(s)), "\(label) preflopContext")
        for item in o["rangeWeight"] as! [Any] {
            let r = item as! [String: Any]
            let pair = decodeCards(r["pair"])
            XCTAssertEqual(rangeWeight(pair, s, opponent: fixtureInt(r["opponent"])), fixtureDouble(r["weight"]),
                           "\(label) rangeWeight \(r["pair"]!)")
        }
        for item in o["candidateActions"] as! [Any] {
            let r = item as! [String: Any]
            let alternatives = (r["alternatives"] as! [Any]).map(decodeCandidate)
            assertReviewJSON(r["result"], candidateActions(s, alternatives).map(enc), "\(label) candidateActions")
        }
        let ctx = decisionContext(s)
        for item in o["comparisonRoutes"] as! [Any] {
            let r = item as! [String: Any], args = r["args"] as! [String: Any]
            let routes = comparisonRoutes(
                s, ctx, code: ReviewCode(rawValue: args["code"] as! String)!,
                status: ReviewStatus(rawValue: args["status"] as! String)!,
                alternative: decodeCandidate(args["alternative"])!,
                pre: args["withPreflopContext"] as! Bool ? preflopContext(s) : nil)
            assertReviewJSON(r["result"], enc(routes), "\(label) comparisonRoutes \(args["code"]!)")
        }
    }

    /// The two hand-built snapshots with 37.5-chip totals cannot be represented with
    /// integer chips. Every output that never reads the totals (everything except the
    /// snapshot seed, the call price and what is sampled or priced from them) is still
    /// compared, with the totals rounded down.
    func testFractionalTotalSnapshotsOnTotalIndependentFunctions() {
        let fractional = Self.cases.filter { $0.snapshot == nil }
        XCTAssertEqual(fractional.count, 2)
        for c in fractional {
            let s = decodeDecision(c.raw["snapshot"], lenient: true)!
            XCTAssertEqual(s.total, 37, c.name)
            checkTotalIndependent(c, s)
        }
    }

    func testContextPriceRangeAndEquityFunctions() throws {
        for c in Self.supported {
            let s = c.snapshot!, o = c.raw
            let label = "\(c.index) \(c.name)"
            XCTAssertEqual(snapshotSeed(s), fixtureInt(o["snapshotSeed"]), "\(label) snapshotSeed")
            checkTotalIndependent(c, s)
            let price = try callPrice(s)
            assertReviewJSON(o["callPrice"], enc(price), "\(label) callPrice")
            for item in o["sampleValue"] as! [Any] {
                let r = item as! [String: Any]
                let trials = fixtureInt(r["trials"]), weighted = r["weighted"] as! Bool
                guard trials < 600 || Self.sampled(c.index, every: 4) else { continue }
                assertReviewJSON(r["result"], enc(sampleValue(s, price, trials: trials, weighted: weighted)),
                                "\(label) sampleValue \(trials) \(weighted)")
            }
        }
    }

    func testCompareCandidateActionsWithFewTrials() throws {
        var checked = 0
        for c in Self.supported where Self.sampled(c.index, every: 2) {
            for item in c.raw["compareCandidateActions"] as! [Any] {
                let r = item as! [String: Any]
                let trials = fixtureInt(r["trials"])
                guard trials < 40 || Self.full else { continue }
                let alternatives = (r["alternatives"] as! [Any]).map(decodeCandidate)
                let result = try compareCandidateActions(c.snapshot!, alternatives, trials: trials)
                assertReviewJSON(r["result"], enc(result), "\(c.index) \(c.name) compareCandidateActions \(trials)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, Self.full ? 100 : 50)
    }

    func testAnalyzeDecisionWithoutSimulation() throws {
        for c in Self.supported where Self.sampled(c.index, every: 4) {
            var s = c.snapshot!
            s.dealer = nil
            let expected = (c.raw["analyzeDecision"] as! [String: Any])["noSimulation"]
            assertReviewJSON(expected, enc(try analyzeDecision(s)), "\(c.index) \(c.name) noSimulation")
        }
    }

    func testAnalyzeDecisionReducedOptions() throws {
        for c in Self.supported where Self.sampled(c.index, every: 3) || Self.summaryCases.contains(c.index) {
            let variant = (c.raw["analyzeDecision"] as! [String: Any])["reduced"] as! [String: Any]
            assertReviewJSON(variant["result"], enc(try Self.reduced(c)), "\(c.index) \(c.name) reduced")
        }
    }

    func testAnalyzeDecisionReferenceTestOptions() throws {
        var checked = 0
        for c in Self.supported {
            guard let variant = (c.raw["analyzeDecision"] as! [String: Any])["test"] as? [String: Any] else { continue }
            let trials = fixtureInt((variant["options"] as! [String: Any])["trials"])
            assertReviewJSON(variant["result"], enc(try analyzeDecision(c.snapshot!, trials: trials)),
                            "\(c.index) \(c.name) test options")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 25)
    }

    func testAnalyzeDecisionDefaultOptions() throws {
        for c in Self.supported where Self.runsDefault(c.index) {
            let expected = (c.raw["analyzeDecision"] as! [String: Any])["default"]
            assertReviewJSON(expected, enc(try Self.defaultAnalysis(c)), "\(c.index) \(c.name) default")
        }
    }

    func testHandSummariesAndOpponentExplanations() throws {
        let hands = Self.handFile["hands"] as! [Any]
        XCTAssertGreaterThan(hands.count, 40)
        for (i, item) in hands.enumerated() {
            let h = item as! [String: Any]
            let name = h["name"] as! String
            let input = decodeInput(h["input"])
            let decisions = input.decisions
            let refs = (h["decisions"] as! [Any]).map(fixtureInt)
            XCTAssertEqual(refs.count, decisions.count, name)
            for (k, ref) in refs.enumerated() {
                XCTAssertEqual(Self.cases[ref].snapshot, decisions[k], "\(name) decision \(k) matches its case")
            }
            if Self.sampled(i, every: Self.handStride) {
                let reducedSteps = try refs.map { try Self.reduced(Self.cases[$0]) }
                let reduced = (h["analyzeReviewReduced"] as! [String: Any])["summary"]
                assertReviewJSON(reduced, enc(summarizeReview(input, reducedSteps), steps: false),
                                 "\(name) reduced summary")
            }
            if refs.allSatisfy(Self.runsDefault) {
                let steps = try refs.map { try Self.defaultAnalysis(Self.cases[$0]) }
                assertReviewJSON((h["analyzeReview"] as! [String: Any])["summary"],
                                enc(summarizeReview(input, steps), steps: false), "\(name) summary")
            }
            let records = input.opponents
            let expected = h["explainOpponent"] as! [Any]
            XCTAssertEqual(records.count, expected.count, name)
            for (k, record) in records.enumerated() {
                assertReviewJSON(expected[k], enc(explainOpponent(record)), "\(name) explainOpponent \(k)")
            }
        }
    }

    func testReferenceExplainOpponentRecord() {
        for item in Self.handFile["explainOpponent"] as! [Any] {
            let o = item as! [String: Any]
            assertReviewJSON(o["result"], enc(explainOpponent(decodeRecord(o["record"]))), o["name"] as! String)
        }
    }

    func testPrivacyVariantsGetIdenticalReviews() throws {
        let cases = Self.handFile["privacy"] as! [Any]
        XCTAssertEqual(cases.count, 3)
        for item in cases {
            let o = item as! [String: Any]
            let name = o["name"] as! String
            let variants = (o["variants"] as! [Any]).map { $0 as! [String: Any] }
            XCTAssertEqual(variants.count, 2)
            let trials = fixtureInt((o["options"] as! [String: Any])["trials"])
            var results: [Any] = []
            for v in variants {
                results.append(enc(try analyzeReview(decodeInput(v), trials: trials), steps: true))
            }
            let inputs = variants.map(decodeInput)
            XCTAssertEqual(inputs[0].decisions, inputs[1].decisions, "\(name) decoded public decisions")
            XCTAssertNotEqual(inputs[0].outcome, inputs[1].outcome, "\(name) decoded outcomes differ")
            // The two variants differ only in hidden cards, the deck and the outcome.
            assertReviewJSON(variants[0]["decisions"], variants[1]["decisions"], "\(name) public decisions")
            XCTAssertFalse(NSDictionary(dictionary: variants[0]["outcome"] as! [String: Any])
                .isEqual(to: variants[1]["outcome"] as! [String: Any]), "\(name) outcomes differ")
            assertReviewJSON(o["result"], results[0], "\(name) variant A")
            assertReviewJSON(o["result"], results[1], "\(name) variant B")
        }
    }

    func testSyntheticReviewInputs() throws {
        for item in Self.handFile["reviewInputs"] as! [Any] {
            let o = item as! [String: Any]
            let name = o["name"] as! String
            let trials = (o["options"] as! [String: Any])["trials"].map(fixtureInt) ?? 600
            let result = try analyzeReview(decodeInput(o["input"]), trials: trials)
            assertReviewJSON(o["result"], enc(result, steps: true), name)
        }
    }

    /// Engine snapshots reach review through `ReviewDecision.init(_:)`; fixture
    /// snapshots through the JSON decoder above. Both must give the same value, so
    /// the fixture checks also hold for snapshots the app records.
    func testEngineSnapshotsConvertLikeTheirFixtureJSON() throws {
        var checked = 0
        for (seats, seed) in [(6, 101), (9, 202), (5, 303)] {
            let g = try newGame(seats)
            let rng = SeededRandom(seed: seed)
            try startHand(g, random: rng)
            var steps = 0
            while g.phase != .done {
                steps += 1
                XCTAssertLessThan(steps, 400)
                if g.phase == .between {
                    try advanceStreet(g)
                } else if g.actor == 0 {
                    let legal = legalActions(g, 0)
                    try act(g, 0, legal.canCheck ? .check : .call)
                } else {
                    let d = try botDecision(g, random: rng, trials: 8)
                    try act(g, g.actor, d.action, d.amount)
                }
            }
            for d in g.decisions {
                let native = ReviewDecision(d)
                let viaJSON = try XCTUnwrap(decodeDecision(enc(d)))
                XCTAssertEqual(native, viaJSON, "\(seats) seats, decision \(d.index)")
                XCTAssertEqual(snapshotSeedJSON(native), snapshotSeedJSON(viaJSON))
                checked += 1
            }
            let input = try createReviewInput(g)
            XCTAssertEqual(input.decisions, g.decisions.map(ReviewDecision.init))
        }
        XCTAssertGreaterThan(checked, 3)
    }

    func testErrorCasesTablesAndMessages() throws {
        let messages = Self.handFile["errors"] as! [String: Any]
        XCTAssertEqual(Set(messages.keys), Set(ReviewError.Code.allCases.map(\.rawValue)))
        for code in ReviewError.Code.allCases {
            XCTAssertEqual(ReviewError(code).message, messages[code.rawValue] as? String, code.rawValue)
        }
        let tables = Self.handFile["tables"] as! [String: Any]
        assertReviewJSON(tables["streetNames"], STREET_NAMES, "streetNames")
        assertReviewJSON(tables["botReasonNames"], BOT_REASON_NAMES, "botReasonNames")
        assertReviewJSON(tables["botCheckNames"], BOT_CHECK_NAMES, "botCheckNames")

        let first = Self.cases[0].snapshot!
        for item in Self.handFile["errorCases"] as! [Any] {
            let o = item as! [String: Any]
            let code = ReviewError.Code(rawValue: o["error"] as! String)!
            let fn = o["fn"] as! String
            // Non-integer trial counts cannot be passed to the typed native API.
            guard let trials = (o["options"] as? [String: Any])?["trials"] as? Int ?? (fn == "createReviewInput" ? 0 : nil)
            else { continue }
            XCTAssertEqual(o["decision"].map(fixtureInt) ?? 0, 0)
            do {
                switch fn {
                case "createReviewInput":
                    let g = try newGame()
                    try startHand(g, random: SeededRandom(75001))
                    _ = try createReviewInput(g)
                case "analyzeDecision": _ = try analyzeDecision(first, trials: trials)
                default: _ = try compareCandidateActions(first, [], trials: trials)
                }
                XCTFail("\(o["name"]!) should throw")
            } catch let error as ReviewError {
                XCTAssertEqual(error.code, code, o["name"] as! String)
            }
        }
    }
}
