import SwiftUI

/// NOIR type scale with Dynamic Type: each size is a reference px value scaled
/// relative to a text style, so large accessibility text grows the UI.
private struct NoirFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let monospacedDigits: Bool
    private let tracking: CGFloat

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle, monospacedDigits: Bool, tracking: CGFloat) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.monospacedDigits = monospacedDigits
        self.tracking = tracking
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size, weight: weight)
        return content
            .font(monospacedDigits ? font.monospacedDigit() : font)
            .tracking(tracking)
    }
}

extension View {
    /// A reference-sized font that scales with Dynamic Type.
    func noirFont(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body,
                  digits: Bool = false, tracking: CGFloat = 0) -> some View {
        modifier(NoirFont(size: size, weight: weight, relativeTo: style, monospacedDigits: digits, tracking: tracking))
    }

    /// Uppercase eyebrow label (THE PRACTICE ROOM, SHOWDOWN, …).
    func eyebrowStyle(_ color: Color = Noir.eyebrow, compact: Bool = false) -> some View {
        noirFont(compact ? 10 : 12, .semibold, relativeTo: .caption, tracking: compact ? 2 : 3)
            .foregroundStyle(color)
    }

    /// Expands the hit area to at least 44×44 pt without changing the visual size.
    func minimumHitTarget(_ side: CGFloat = 44) -> some View {
        frame(minWidth: side, minHeight: side).contentShape(Rectangle())
    }
}
