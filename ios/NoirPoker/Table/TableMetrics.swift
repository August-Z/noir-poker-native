import SwiftUI

/// Reference arena geometry (visual spec §5–7) for a given arena width, seat
/// count and hand state. Heights are fixed per state; seat x is a percentage
/// of the width and seat y a percentage of the height.
struct TableMetrics {
    let width: CGFloat
    let count: Int
    let done: Bool
    let longNames: Bool
    /// Dynamic Type is at an accessibility size: plates drop their avatars.
    let largeText: Bool

    var compact: Bool { width <= 600 }
    var dense: Bool { compact && count >= 7 }
    var tiny: Bool { width <= 360 }

    var height: CGFloat {
        let base: CGFloat
        switch count {
        case ...6: base = compact ? (done ? 600 : 490) : (done ? 620 : 550)
        case 7: base = 620
        default:
            if compact && longNames { base = count == 8 ? 800 : 900 } else { base = compact ? 720 : 690 }
        }
        return base + (largeText ? 90 : 0)
    }

    /// Rail ellipse insets: top, horizontal, bottom.
    var railInsets: (top: CGFloat, side: CGFloat, bottom: CGFloat) {
        if count >= 8 {
            return compact ? (56, width * 0.015, 75) : (56, width * 0.05, 74)
        }
        return compact ? (58, width * 0.015, 76) : (57, width * 0.055, 60)
    }

    var railPadding: CGFloat { compact ? 9 : 13 }
    var feltOutlineInset: CGFloat { compact ? 7 : 10 }

    var centerTop: CGFloat {
        if count >= 8 { return height * 0.33 }
        if done && count <= 6 { return height * (compact ? 0.34 : 0.36) }
        return height * 0.30
    }

    var heroBottom: CGFloat { height - 20 }

    var boardCard: CGSize {
        if dense {
            if tiny { return done && count == 9 ? CGSize(width: 26, height: 38) : CGSize(width: 32, height: 47) }
            let w = min(max(28, width * 0.09), 37)
            let h = min(max(41, width * 0.13), 54)
            return CGSize(width: w, height: h)
        }
        if tiny { return CGSize(width: 39, height: 58) }
        return compact ? CGSize(width: 43, height: 63) : CGSize(width: 55, height: 78)
    }

    var boardGap: CGFloat { dense ? 4 : (compact ? 5 : 8) }
    var heroCard: CGSize { compact ? CGSize(width: 55, height: 79) : CGSize(width: 63, height: 91) }
    var cardBack: CGSize { compact ? CGSize(width: 25, height: 36) : CGSize(width: 29, height: 41) }
    var seatCard: CGSize { compact ? CGSize(width: 33, height: 46) : CGSize(width: 38, height: 53) }
    var showAvatars: Bool { !dense && !tiny && !largeText }
    var plateMinWidth: CGFloat { dense ? (tiny ? 72 : 78) : (tiny ? 77 : (compact ? 84 : 98)) }
    var avatarSize: CGFloat { compact ? 24 : 30 }

    func seatPoint(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: width * x / 100, y: height * y / 100)
    }
}
