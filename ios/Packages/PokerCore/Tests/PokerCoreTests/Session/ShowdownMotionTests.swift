import XCTest
@testable import PokerCore

/// The showdown card motions against the reference keyframes (`showdown.css`).
final class ShowdownMotionTests: XCTestCase {
    private func assertPose(_ pose: CardPose, _ expected: CardPose, _ message: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let pairs: [(String, Double, Double)] = [
            ("tx", pose.tx, expected.tx), ("ty", pose.ty, expected.ty), ("rz", pose.rz, expected.rz),
            ("ry", pose.ry, expected.ry), ("scale", pose.scale, expected.scale),
            ("alpha", pose.alpha, expected.alpha), ("brightness", pose.brightness, expected.brightness),
        ]
        for (name, actual, wanted) in pairs {
            XCTAssertEqual(actual, wanted, accuracy: 1e-9, "\(message) \(name)", file: file, line: line)
        }
    }

    func testEveryMotionEndsAtItsReferenceRestingPose() {
        for motion in HandMotion.allCases {
            for i in 0..<5 {
                let final = CardMotion.winner(motion, index: i).final
                var expected = CardPose.identity
                switch motion {
                case .high: expected.ty = -5
                case .royal: expected.rz = Double(i - 2) * 2
                default: break
                }
                assertPose(final, expected, "\(motion.rawValue) card \(i)")
            }
        }
        for i in 0..<5 {
            assertPose(CardMotion.arrive(i).final, .identity, "rank-arrive card \(i)")
        }
    }

    func testFirstFramesHoldTheFromKeyframeThroughTheDelay() {
        // fill-mode: both — the card holds its 0 % keyframe until its delay ends.
        let straight = CardMotion.winner(.straight, index: 3)
        XCTAssertEqual(straight.delayMs, 420)
        assertPose(straight.pose(atMs: 0), CardPose(ty: 20, ry: 90, alpha: 0), "straight before the delay")
        assertPose(straight.pose(atMs: 420), CardPose(ty: 20, ry: 90, alpha: 0), "straight at the delay")
        assertPose(CardMotion.arrive(2).pose(atMs: 100), CardPose(ty: 18, ry: 45, alpha: 0), "rank-arrive")
        assertPose(CardMotion.winner(.royal, index: 0).pose(atMs: 0), CardPose(tx: 80, rz: -28, alpha: 0), "royal")
        assertPose(CardMotion.winner(.high, index: 0).pose(atMs: 0), CardPose(scale: 0.7, brightness: 0.6), "high")
    }

    func testKeyframesAreHitAtTheirReferenceTimes() {
        // high-spotlight 40 %: translateY(-10px) scale(1.12), brightness 1.12.
        assertPose(CardMotion.winner(.high, index: 0).pose(atMs: 1700 * 0.4),
                   CardPose(ty: -10, scale: 1.12, brightness: 1.12), "high peak")
        // pair-heartbeat 30 % and 65 % share the lift; 45 % is at rest.
        let pair = CardMotion.winner(.pair, index: 1)
        XCTAssertEqual(pair.delayMs, 60)
        XCTAssertEqual(pair.pose(atMs: 60 + 1500 * 0.3).ty, -4, accuracy: 1e-9)
        XCTAssertEqual(pair.pose(atMs: 60 + 1500 * 0.3).scale, 1.08, accuracy: 1e-9)
        XCTAssertEqual(pair.pose(atMs: 60 + 1500 * 0.45).ty, 0, accuracy: 1e-9)
        XCTAssertEqual(pair.pose(atMs: 60 + 1500 * 0.65).scale, 1.08, accuracy: 1e-9)
        // Opacity is only set at 0 % and 45 %, so it is still rising at 30 %.
        let alpha30 = pair.pose(atMs: 60 + 1500 * 0.3).alpha
        XCTAssertGreaterThan(alpha30, 0)
        XCTAssertLessThan(alpha30, 1)
        XCTAssertEqual(pair.pose(atMs: 60 + 1500 * 0.45).alpha, 1, accuracy: 1e-9)
        // trips-rise 45 % and 70 %.
        let trips = CardMotion.winner(.trips, index: 2)
        XCTAssertEqual(trips.delayMs, 300)
        XCTAssertEqual(trips.pose(atMs: 300 + 1600 * 0.45).ty, -12, accuracy: 1e-9)
        XCTAssertEqual(trips.pose(atMs: 300 + 1600 * 0.7).ty, 3, accuracy: 1e-9)
        // straight-flush-arc 40 %: the arc peaks at the middle card.
        XCTAssertEqual(CardMotion.winner(.straightFlush, index: 2).pose(atMs: 200 + 1900 * 0.4).ty, -7, accuracy: 1e-9)
        XCTAssertEqual(CardMotion.winner(.straightFlush, index: 0).pose(atMs: 1900 * 0.4).ty, -19, accuracy: 1e-9)
        // royal-fan 50 %.
        assertPose(CardMotion.winner(.royal, index: 4).pose(atMs: 240 + 2000 * 0.5),
                   CardPose(ty: -10, rz: 10, brightness: 1.14), "royal peak")
        // quads-impact 25 %, flush-wave 35 %.
        XCTAssertEqual(CardMotion.winner(.quads, index: 0).pose(atMs: 1800 * 0.25).scale, 1.14, accuracy: 1e-9)
        XCTAssertEqual(CardMotion.winner(.quads, index: 0).pose(atMs: 1800 * 0.25).brightness, 1.16, accuracy: 1e-9)
        let flush = CardMotion.winner(.flush, index: 0).pose(atMs: 1800 * 0.35)
        XCTAssertEqual(flush.rz, 5, accuracy: 1e-9)
        XCTAssertEqual(flush.ty, -10, accuracy: 1e-9)
    }

    func testDurationsDelaysAndTimingFunctionsMatchTheReference() {
        let expected: [HandMotion: (Int, Int, MotionCurve)] = [
            .high: (1700, 0, .easeOut), .pair: (1500, 60, .easeOut), .twoPair: (1600, 90, .easeOut),
            .trips: (1600, 150, .easeOut), .straight: (1600, 140, .easeOut), .flush: (1800, 100, .easeInOut),
            .fullHouse: (1800, 80, MotionCurve(0.2, 0.8, 0.2, 1)), .quads: (1800, 60, .easeOut),
            .straightFlush: (1900, 100, .easeOut), .royal: (2000, 60, .easeOut),
        ]
        for motion in HandMotion.allCases {
            let (duration, step, curve) = expected[motion]!
            for i in 0..<5 {
                let plan = CardMotion.winner(motion, index: i)
                XCTAssertEqual(plan.durationMs, duration, motion.rawValue)
                // high-spotlight has no per-card delay.
                XCTAssertEqual(plan.delayMs, motion == .high ? 0 : step * i, motion.rawValue)
                XCTAssertEqual(plan.curve, curve, motion.rawValue)
            }
        }
        let arrive = CardMotion.arrive(4)
        XCTAssertEqual(arrive.durationMs, 800)
        XCTAssertEqual(arrive.delayMs, 320)
        XCTAssertEqual(arrive.curve, MotionCurve(0.18, 0.7, 0.25, 1))
    }

    func testOnlyCardsThatMakeTheCategoryMoveForGroupedHands() {
        let all: Set<HandMotion> = [.straight, .flush, .fullHouse, .straightFlush, .royal]
        for motion in HandMotion.allCases {
            XCTAssertEqual(CardMotion.appliesToAll(motion), all.contains(motion), motion.rawValue)
            // A kicker keeps rank-arrive unless the motion moves every card.
            let kicker = CardMotion.forCard(3, motion: motion, winner: true, match: false)
            XCTAssertEqual(kicker, all.contains(motion) ? CardMotion.winner(motion, index: 3) : CardMotion.arrive(3),
                           motion.rawValue)
            XCTAssertEqual(CardMotion.forCard(1, motion: motion, winner: true, match: true),
                           CardMotion.winner(motion, index: 1), motion.rawValue)
            // Losing panels always arrive.
            XCTAssertEqual(CardMotion.forCard(1, motion: motion, winner: false, match: true), CardMotion.arrive(1))
        }
    }

    func testTimingFunctionsFollowTheCssCubicBezier() {
        for curve in [MotionCurve.easeOut, .easeInOut, .arrive, .fullHouse] {
            XCTAssertEqual(curve.transform(0), 0)
            XCTAssertEqual(curve.transform(1), 1)
            var last = 0.0
            for step in 1...20 {
                let value = curve.transform(Double(step) / 20)
                XCTAssertGreaterThanOrEqual(value, last - 1e-9, "monotone")
                last = value
            }
        }
        // ease-in-out is symmetric around the midpoint; ease-out runs ahead of linear.
        XCTAssertEqual(MotionCurve.easeInOut.transform(0.5), 0.5, accuracy: 1e-6)
        XCTAssertEqual(MotionCurve.easeInOut.transform(0.25) + MotionCurve.easeInOut.transform(0.75), 1, accuracy: 1e-6)
        XCTAssertGreaterThan(MotionCurve.easeOut.transform(0.3), 0.3)
        // A linear bezier is the identity.
        XCTAssertEqual(MotionCurve(0.25, 0.25, 0.75, 0.75).transform(0.37), 0.37, accuracy: 1e-6)
    }
}
