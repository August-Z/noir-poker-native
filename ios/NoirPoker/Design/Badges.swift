import SwiftUI
import PokerCore

/// Crown icon (viewBox 20×16).
struct CrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 20, sy = rect.height / 16
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(2, 4))
        path.addLine(to: p(6, 7))
        path.addLine(to: p(10, 2))
        path.addLine(to: p(14, 7))
        path.addLine(to: p(18, 4))
        path.addLine(to: p(16, 12))
        path.addLine(to: p(4, 12))
        path.closeSubpath()
        path.addRect(CGRect(x: rect.minX + 4 * sx, y: rect.minY + 14.2 * sy, width: 12 * sx, height: 1.6 * sy))
        return path
    }
}

/// Eye icon (viewBox 20×20) for the reveal toggle.
struct EyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 20
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(2, 10))
        path.addCurve(to: p(10, 5), control1: p(4, 6), control2: p(7, 5))
        path.addCurve(to: p(18, 10), control1: p(13, 5), control2: p(16, 6))
        path.addCurve(to: p(10, 15), control1: p(16, 14), control2: p(13, 15))
        path.addCurve(to: p(2, 10), control1: p(7, 15), control2: p(4, 14))
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: rect.minX + 7.5 * s, y: rect.minY + 7.5 * s, width: 5 * s, height: 5 * s))
        return path
    }
}

/// A duotone poker chip drawn natively (stands in for the Phosphor icon).
struct ChipIcon: View {
    var size: CGFloat = 28
    var color: Color = Noir.mint

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.2))
            Circle().strokeBorder(color, lineWidth: size * 0.075)
            Circle().strokeBorder(color, lineWidth: size * 0.06).padding(size * 0.27)
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(color)
                    .frame(width: size * 0.075, height: size * 0.2)
                    .offset(y: -size * 0.36)
                    .rotationEffect(.degrees(Double(i) * 90 + 45))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// BTN / SB / BB / other position badge.
struct PositionBadgeView: View {
    let badge: PositionBadge
    var compact = false

    var body: some View {
        let colors: (Color, Color) = {
            switch badge.code {
            case "BTN": return (Noir.btnBg, Noir.btnText)
            case "SB": return (Noir.sbBg, Noir.sbText)
            case "BB": return (Noir.bbBg, Noir.bbText)
            default: return (Noir.badgeBg, Noir.badgeText)
            }
        }()
        let isButton = badge.code == "BTN"
        Text(badge.code)
            .noirFont(compact ? 10 : 11, isButton ? .bold : .medium, relativeTo: .caption2)
            .foregroundStyle(colors.1)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, isButton ? 4 : 5)
            .padding(.vertical, 1)
            .frame(minWidth: isButton ? (compact ? 25 : 28) : nil)
            .background(colors.0, in: isButton ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 4)))
            .accessibilityLabel(badge.name)
    }
}

/// Hand-rank or winner badge under a seat or the hero.
struct RankBadgeView: View {
    let badge: RankBadge
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            if badge.isWinner {
                CrownShape().fill(Noir.winText).frame(width: 13, height: 10)
            }
            Text(badge.text)
                .noirFont(compact ? 11 : 12, .semibold, relativeTo: .caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(badge.isWinner ? Noir.winText : Noir.rankText)
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 3 : 4)
        .background(badge.isWinner ? Noir.winBg : Noir.rankBg, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(badge.isWinner ? Noir.gold : Noir.rankBorder, lineWidth: 1))
        .shadow(color: badge.isWinner ? Noir.gold.opacity(0.16) : .clear, radius: 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.a11y ?? badge.text)
    }
}

/// Small rounded "pill" label used for the replay badge, the 6-MAX tag and toggles.
struct TagLabel: View {
    let text: String
    var foreground: Color = Noir.muted
    var border: Color = Color(hex: "#35434e")
    var background: Color = .clear

    var body: some View {
        Text(text)
            .noirFont(12, .medium, relativeTo: .caption)
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(background, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(border, lineWidth: 1))
    }
}

/// Button press feedback: scale 0.98, no hover lift.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

/// Primary mint button (Next Hand, Back to Table).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .noirFont(14, .semibold, relativeTo: .body)
            .foregroundStyle(Noir.primaryText)
            .padding(.horizontal, 22)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? Color(hex: "#95efd5") : Noir.mint, in: RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Outlined button with configurable colors (Replay Hand, Review This Hand, Finish Hand).
struct OutlineButtonStyle: ButtonStyle {
    var foreground: Color
    var border: Color
    var background: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .noirFont(14, .medium, relativeTo: .body)
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// A rounded card container for sidebar sections.
struct SidebarCard<Content: View>: View {
    var coach = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(coach ? AnyShapeStyle(NoirSurface.coach) : AnyShapeStyle(NoirSurface.sidebar),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(coach ? Noir.coachBorder : Noir.sidebarBorder, lineWidth: 1))
    }
}
