import Foundation
import XCTest
@testable import PokerCore

/// Port of the reference `measure:bots` harness (`scripts/measure-bots.mjs`) and its documented
/// calibration table (see docs/BOTS.md). Every seat, the hero included, plays the bot policy for
/// 250 hands with policy seed 781 and deck seed 711, emotions off, and 100 BB stacks reset before
/// each hand. The engine is fixture-exact, so the reference numbers must reproduce exactly.
///
/// Each measurement plays 250 simulated hands with equity sampling; this is the slowest test
/// class in the package. Mirrors Android `BotCalibrationTest`.
final class BotCalibrationTests: XCTestCase {
    struct Measurement: Equatable {
        var samples: Int
        var vpip: Int
        var pfr: Int
        var flopHands: Int
        var flopPlayers: Int
        var threePlusFlopHands: Int
        var flopPlayerDistribution: [Int: Int]
        var preflopReraisedHands: Int

        var vpipPercent: Double { 100 * Double(vpip) / Double(samples) }
        var pfrPercent: Double { 100 * Double(pfr) / Double(samples) }
        var averageFlopPlayers: Double { flopHands == 0 ? 0 : Double(flopPlayers) / Double(flopHands) }
    }

    private func measureBots(players: Int, hands: Int = 250, profile: String = "balanced",
                             policySeed: UInt32 = 781, deckSeed: UInt32 = 711) throws -> Measurement {
        let random = LCGRandom(policySeed)
        let deckRandom = LCGRandom(deckSeed)
        let g = try newGame(players)
        var assignments: [String: Any] = [:]
        for id in 1..<players { assignments[String(id)] = profile }
        try applyBotSettings(g, ["emotionMode": "off", "assignments": assignments] as [String: Any])
        var m = Measurement(samples: 0, vpip: 0, pfr: 0, flopHands: 0, flopPlayers: 0, threePlusFlopHands: 0,
                            flopPlayerDistribution: [:], preflopReraisedHands: 0)
        for _ in 0..<hands {
            for i in g.players.indices { g.players[i].stack = STARTING_STACK }
            try startHand(g, random: deckRandom)
            var actions = 0
            while g.phase != .done {
                actions += 1
                guard actions <= 1000 else {
                    XCTFail("unfinished hand")
                    return m
                }
                if g.phase == .between {
                    if g.street == 0 {
                        let entrants = g.players.filter { !$0.folded }.count
                        m.flopHands += 1
                        m.flopPlayers += entrants
                        if entrants >= 3 { m.threePlusFlopHands += 1 }
                        m.flopPlayerDistribution[entrants, default: 0] += 1
                    }
                    try advanceStreet(g)
                } else {
                    let d = try botDecision(g, random: random)
                    try act(g, g.actor, d.action, d.amount)
                }
            }
            if g.history.filter({ $0.street == 0 && $0.action == .raise }).count >= 2 { m.preflopReraisedHands += 1 }
        }
        for p in g.players.dropFirst() {
            m.samples += p.botStats.hands
            m.vpip += p.botStats.vpip
            m.pfr += p.botStats.pfr
        }
        return m
    }

    private func fixed(_ value: Double, _ digits: Int) -> String { String(format: "%.\(digits)f", value) }

    // Expected values are the raw `node scripts/measure-bots.mjs` output of the pinned reference.

    func testSixMaxBalancedCalibrationReproducesTheDocumentedReferenceStatistics() throws {
        let m = try measureBots(players: 6)
        XCTAssertEqual(m, Measurement(samples: 1250, vpip: 677, pfr: 181, flopHands: 217, flopPlayers: 712,
                                      threePlusFlopHands: 148,
                                      flopPlayerDistribution: [2: 69, 3: 59, 4: 55, 5: 27, 6: 7],
                                      preflopReraisedHands: 33))
        XCTAssertEqual(fixed(m.vpipPercent, 2), "54.16")
        XCTAssertEqual(fixed(m.pfrPercent, 2), "14.48")
        XCTAssertEqual(fixed(m.averageFlopPlayers, 3), "3.281")
    }

    func testNineMaxBalancedCalibrationReproducesTheDocumentedReferenceStatistics() throws {
        let m = try measureBots(players: 9)
        XCTAssertEqual(m, Measurement(samples: 2000, vpip: 919, pfr: 252, flopHands: 192, flopPlayers: 741,
                                      threePlusFlopHands: 141,
                                      flopPlayerDistribution: [2: 51, 3: 36, 4: 42, 5: 33, 6: 17, 7: 8, 8: 5],
                                      preflopReraisedHands: 52))
        XCTAssertEqual(fixed(m.vpipPercent, 2), "45.95")
        XCTAssertEqual(fixed(m.pfrPercent, 2), "12.60")
        XCTAssertEqual(fixed(m.averageFlopPlayers, 3), "3.859")
    }

    func testTightAndLooseArchetypesKeepTheirDocumentedSixMaxEntryRates() throws {
        let st = try measureBots(players: 6, profile: "st")
        let peter = try measureBots(players: 6, profile: "peter")
        XCTAssertEqual(st, Measurement(samples: 1250, vpip: 629, pfr: 206, flopHands: 216, flopPlayers: 662,
                                       threePlusFlopHands: 139,
                                       flopPlayerDistribution: [2: 77, 3: 74, 4: 42, 5: 20, 6: 3],
                                       preflopReraisedHands: 38))
        XCTAssertEqual(peter, Measurement(samples: 1250, vpip: 889, pfr: 276, flopHands: 214, flopPlayers: 775,
                                          threePlusFlopHands: 144,
                                          flopPlayerDistribution: [2: 70, 3: 34, 4: 37, 5: 53, 6: 20],
                                          preflopReraisedHands: 65))
        XCTAssertEqual(fixed(st.vpipPercent, 2), "50.32")
        XCTAssertEqual(fixed(peter.vpipPercent, 2), "71.12")
        XCTAssertTrue(st.vpipPercent < 54.16 && 54.16 < peter.vpipPercent)
    }

    func testSecondSixMaxSeedPairReproducesTheDocumentedFlopStatistics() throws {
        let m = try measureBots(players: 6, policySeed: 9182, deckSeed: 123)
        XCTAssertEqual(m, Measurement(samples: 1250, vpip: 715, pfr: 203, flopHands: 205, flopPlayers: 684,
                                      threePlusFlopHands: 138,
                                      flopPlayerDistribution: [2: 67, 3: 51, 4: 47, 5: 31, 6: 9],
                                      preflopReraisedHands: 36))
        XCTAssertEqual(fixed(m.averageFlopPlayers, 3), "3.337")
    }
}
