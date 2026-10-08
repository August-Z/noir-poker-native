import SwiftUI
import PokerCore

/// The reference suit vectors (viewBox 0 0 20 22), drawn natively.
struct SuitShape: Shape {
    let suit: Int

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 20, sy = rect.height / 22
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        func curve(_ c1: (CGFloat, CGFloat), _ c2: (CGFloat, CGFloat), _ to: (CGFloat, CGFloat)) {
            path.addCurve(to: p(to.0, to.1), control1: p(c1.0, c1.1), control2: p(c2.0, c2.1))
        }
        func stem(_ top: CGFloat) {
            path.move(to: p(9, top))
            path.addLine(to: p(6, 22))
            path.addLine(to: p(14, 22))
            path.addLine(to: p(11, top))
            path.closeSubpath()
        }
        switch suit {
        case 0: // spade
            path.move(to: p(10, 0))
            curve((7, 5), (0, 8), (0, 14))
            curve((0, 19), (7, 21), (10, 16))
            curve((13, 21), (20, 19), (20, 14))
            curve((20, 8), (13, 5), (10, 0))
            path.closeSubpath()
            stem(16)
        case 1: // heart
            path.move(to: p(10, 22))
            curve((7, 18), (0, 12), (0, 6))
            curve((0, -1), (8, -2), (10, 4))
            curve((12, -2), (20, -1), (20, 6))
            curve((20, 12), (13, 18), (10, 22))
            path.closeSubpath()
        case 2: // club
            path.move(to: p(10, 0))
            curve((3, 0), (3, 8), (6, 10))
            curve((-2, 7), (-2, 19), (5, 19))
            curve((7, 19), (9, 18), (10, 15))
            curve((11, 18), (13, 19), (15, 19))
            curve((22, 19), (22, 7), (14, 10))
            curve((17, 8), (17, 0), (10, 0))
            path.closeSubpath()
            stem(15)
        default: // diamond
            path.move(to: p(10, 0))
            path.addLine(to: p(20, 11))
            path.addLine(to: p(10, 22))
            path.addLine(to: p(0, 11))
            path.closeSubpath()
        }
        return path
    }
}

enum CardNames {
    private static let ranks = [2: "Two", 3: "Three", 4: "Four", 5: "Five", 6: "Six", 7: "Seven", 8: "Eight",
                                9: "Nine", 10: "Ten", 11: "Jack", 12: "Queen", 13: "King", 14: "Ace"]
    private static let suits = ["spades", "hearts", "clubs", "diamonds"]
    /// VoiceOver name: "Ace of spades".
    static func spoken(_ card: Card) -> String { "\(ranks[card.rank] ?? card.rankText) of \(suits[card.suit])" }
}

/// A face-up card. `small` uses the 36×50 layout (rank top-left, one suit); the
/// large layout is 64×92 with mirrored corner ranks and a center pip.
struct CardFaceView: View {
    let card: Card
    var width: CGFloat
    var height: CGFloat
    var small = false
    var best = false
    var dimmed = false

    private var ink: Color { card.suit == 1 || card.suit == 3 ? Noir.cardRed : Noir.cardInk }

    var body: some View {
        let radius: CGFloat = small ? 5 : (width < 50 ? 5 : 7)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(stops: [.init(color: Noir.cardFace[0], location: 0),
                                             .init(color: Noir.cardFace[1], location: 0.58),
                                             .init(color: Noir.cardFace[2], location: 1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if small { smallArt } else { largeArt }
        }
        .frame(width: width, height: height)
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Noir.cardBorder, lineWidth: 1))
        .overlay {
            if best {
                RoundedRectangle(cornerRadius: radius + 2).stroke(Noir.mint, lineWidth: 2).padding(-3)
            }
        }
        .shadow(color: best ? Noir.mint.opacity(0.26) : .black.opacity(0.27), radius: best ? 11 : 3.5, y: best ? 0 : 3)
        .opacity(dimmed ? 0.42 : 1)
        .saturation(dimmed ? 0.4 : 1)
        .accessibilityElement()
        .accessibilityLabel(CardNames.spoken(card))
    }

    private var largeArt: some View {
        let s = width / 64, v = height / 92
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6 * s)
                .stroke(Color(hex: "#344d60").opacity(0.1), lineWidth: 1)
                .frame(width: 60 * s, height: 88 * v)
                .offset(x: 2 * s, y: 2 * v)
            rank(size: 15 * s).position(x: 10 * s, y: 14 * v)
            rank(size: 15 * s).rotationEffect(.degrees(180)).position(x: 54 * s, y: 78 * v)
            SuitShape(suit: card.suit).fill(ink)
                .frame(width: 29 * s, height: 31.9 * v)
                .position(x: 32 * s, y: 46 * v)
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private var smallArt: some View {
        let s = width / 36, v = height / 50
        return ZStack(alignment: .topLeading) {
            rank(size: 16 * s).fixedSize().position(x: 5 * s + (card.rank == 10 ? 9 : 5) * s, y: 12.5 * v)
            SuitShape(suit: card.suit).fill(ink)
                .frame(width: 17 * s, height: 18.7 * v)
                .position(x: 20 * s, y: 33 * v)
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func rank(size: CGFloat) -> some View {
        Text(card.rankText)
            .font(.system(size: size, weight: .bold))
            .tracking(card.rank == 10 ? -0.8 : 0)
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
    }
}

/// The card back: dark teal with a light diagonal lattice.
struct CardBackView: View {
    var width: CGFloat = 29
    var height: CGFloat = 41

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Noir.cardBackBase))
            var a = Path(), b = Path()
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                a.move(to: CGPoint(x: x, y: size.height))
                a.addLine(to: CGPoint(x: x + size.height, y: 0))
                b.move(to: CGPoint(x: x, y: 0))
                b.addLine(to: CGPoint(x: x + size.height, y: size.height))
                x += 4 * 1.414
            }
            context.stroke(b, with: .color(Noir.cardBackLineB), lineWidth: 1)
            context.stroke(a, with: .color(Noir.cardBackLineA), lineWidth: 1)
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Noir.cardBackBorder, lineWidth: 2))
        .shadow(color: .black.opacity(0.33), radius: 2.5, y: 2)
    }
}

/// An empty board position with the faint suit glyph.
struct BoardSlotView: View {
    let glyph: String
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        let radius: CGFloat = width < 50 ? 5 : 7
        RoundedRectangle(cornerRadius: radius)
            .fill(Noir.slotFill)
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Noir.slotBorder, lineWidth: 1))
            .overlay(Text(glyph).font(.system(size: width < 50 ? 22 : 28)).foregroundStyle(Noir.slotGlyph))
            .frame(width: width, height: height)
    }
}
