import SwiftUI
import PokerCore

/// The hero area: hole cards, hand-rank badge, YOU row with status pill, and
/// the retained last action.
struct HeroView: View {
    let hero: HeroState
    let metrics: TableMetrics
    let dealKey: String

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ForEach(Array(hero.cards.enumerated()), id: \.offset) { i, face in
                    CardFaceView(card: face.card, width: metrics.heroCard.width, height: metrics.heroCard.height,
                                 best: face.best, dimmed: hero.folded)
                        .rotationEffect(.degrees(i == 0 ? -4 : 4))
                        .dealIn(style: .deal, animate: face.animate, delayMs: face.delayMs)
                }
            }
            .id("hero-\(dealKey)")
            .frame(minHeight: metrics.compact ? 79 : 94)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your hole cards")
            .accessibilityValue(hero.cards.map { CardNames.spoken($0.card) }.joined(separator: ", ")
                                + (hero.folded ? ". Folded" : ""))
            .accessibilityIdentifier("hero-cards")

            if let badge = hero.rankBadge {
                RankBadgeView(badge: badge, compact: metrics.compact, hero: true)
                    .padding(.top, 3)
                    .transition(.opacity)
                    .accessibilityIdentifier("hero-rank")
            }

            HStack(spacing: 8) {
                Text("YOU")
                    .noirFont(metrics.compact ? 8 : 9, .bold, relativeTo: .caption2)
                    .foregroundStyle(Noir.mint)
                    .frame(width: metrics.compact ? 30 : 36, height: metrics.compact ? 30 : 36)
                    .background(Noir.heroAvatarBg, in: Circle())
                    .overlay(Circle().strokeBorder(Noir.mint, lineWidth: 1))
                    .turnGlow(hero.isActive, cornerRadius: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(hero.name)
                            .noirFont(metrics.compact ? 12 : 14, .medium, relativeTo: .footnote)
                            .foregroundStyle(Noir.text)
                        PositionBadgeView(badge: hero.position, compact: metrics.compact)
                    }
                    Text(hero.stackText)
                        .noirFont(metrics.compact ? 12 : 14, relativeTo: .footnote, digits: true)
                        .foregroundStyle(Noir.heroStack)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(hero.name), \(hero.position.name)")
                .accessibilityValue("\(hero.stackText) chips")
                if let turn = hero.turnText, !metrics.tiny {
                    Text(turn)
                        .noirFont(metrics.compact ? 10 : 12, .medium, relativeTo: .caption)
                        .foregroundStyle(hero.isActive ? Noir.mint : Noir.subtle)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Noir.mint.opacity(hero.isActive ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Noir.mint.opacity(hero.isActive ? 0.35 : 0.12), lineWidth: 1))
                        .accessibilityIdentifier("hero-turn")
                }
            }
            if let last = hero.lastAction {
                ActionLine(chip: last, compact: metrics.compact, maxWidth: 200)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(hero.lastActionA11y)
                    .accessibilityValue([last.label, last.amountText, last.meaning].compactMap { $0 }.joined(separator: ", "))
            }
        }
    }
}
