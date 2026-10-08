import SwiftUI
import PokerCore

/// Turn glow and blink, disabled under reduced motion.
private struct TurnGlow: ViewModifier {
    let active: Bool
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.phaseAnimator([false, true]) { view, phase in
                view.shadow(color: Noir.mint.opacity(phase ? 0.27 : 0.14), radius: phase ? 12 : 9)
            } animation: { _ in .easeInOut(duration: 1) }
        } else {
            content.shadow(color: active ? Noir.mint.opacity(0.14) : .clear, radius: 9)
        }
    }
}

private struct Blink: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.phaseAnimator([1.0, 0.3]) { view, opacity in view.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.6) }
        }
    }
}

extension View {
    func turnGlow(_ active: Bool, cornerRadius: CGFloat) -> some View { modifier(TurnGlow(active: active, cornerRadius: cornerRadius)) }
    func blinking() -> some View { modifier(Blink()) }
}

/// The last-action line under a plate or the hero.
struct ActionLine: View {
    let chip: ActionChip
    var winner = false
    var compact = false
    var maxWidth: CGFloat = 106

    var body: some View {
        Group {
            if chip.isDeciding {
                Text(chip.label)
                    .foregroundStyle(Noir.mint)
                    .blinking()
            } else {
                HStack(spacing: 4) {
                    Text(chip.label).foregroundStyle(winner ? Noir.goldAction : Noir.seatAction)
                    if let amount = chip.amountText {
                        Text(amount)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(winner ? Color(hex: "#e0c885") : Noir.seatAmount)
                    }
                }
            }
        }
        .noirFont(compact ? 11 : 12, relativeTo: .caption)
        .multilineTextAlignment(.center)
        .lineLimit(3)
        .frame(maxWidth: maxWidth, minHeight: compact ? 21 : 25)
    }
}

struct SeatView: View {
    let seat: SeatState
    let metrics: TableMetrics
    let newHandKey: String
    let onPeek: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var done: Bool { seat.peek != nil }

    var body: some View {
        VStack(spacing: 0) {
            cards
                .zIndex(0)
            plate
                .zIndex(1)
            if let badge = seat.badge {
                RankBadgeView(badge: badge, compact: metrics.compact)
                    .padding(.top, 5)
            }
            ActionLine(chip: seat.action, winner: seat.isWinner, compact: metrics.compact,
                       maxWidth: done ? 106 : max(metrics.plateMinWidth + 20, 100))
                .padding(.top, 3)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(seat.actionA11y)
                .accessibilityValue(actionSpoken)
        }
        .opacity(seat.folded && !done ? 0.4 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: seat.folded)
        .accessibilityElement(children: .contain)
    }

    private var actionSpoken: String {
        var parts = [seat.action.label]
        if let amount = seat.action.amountText { parts.append(amount) }
        if let meaning = seat.action.meaning { parts.append(meaning) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var cards: some View {
        if seat.revealed && !seat.cards.isEmpty {
            HStack(spacing: metrics.compact ? 4 : 5) {
                ForEach(Array(seat.cards.enumerated()), id: \.offset) { _, face in
                    CardFaceView(card: face.card, width: metrics.seatCard.width, height: metrics.seatCard.height,
                                 small: true, best: face.best)
                }
            }
            .padding(.bottom, 4)
            .transition(.opacity)
            .id("faces-\(newHandKey)-\(seat.id)")
        } else if seat.cardBacks > 0 {
            HStack(spacing: metrics.compact ? 2 : 3) {
                ForEach(0..<seat.cardBacks, id: \.self) { i in
                    CardBackView(width: metrics.cardBack.width, height: metrics.cardBack.height)
                        .rotationEffect(.degrees(i == 0 ? -6 : 6), anchor: .bottom)
                        .dealIn(style: .deal, animate: seat.dealAnimation,
                                delayMs: seat.cardBackDelaysMs.indices.contains(i) ? seat.cardBackDelaysMs[i] : 0)
                }
            }
            .opacity(seat.folded ? 0.4 : 1)
            .padding(.bottom, -(metrics.compact ? 6 : 8))
            .id("backs-\(newHandKey)-\(seat.id)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(seat.cardBackA11y)
        }
    }

    private var plate: some View {
        let radius: CGFloat = metrics.compact ? 8 : 10
        let border: Color = seat.isWinner ? (done ? Noir.gold : Noir.goldSeat)
            : seat.isActor ? Noir.mint
            : (seat.folded && done ? Noir.plateFoldedBorder : Noir.plateBorder)
        let fadeDetails = seat.folded && done
        return HStack(spacing: metrics.compact ? 6 : 8) {
            if metrics.showAvatars {
                avatar.opacity(fadeDetails ? 0.45 : 1)
            }
            VStack(alignment: metrics.showAvatars ? .leading : .center, spacing: 3) {
                HStack(spacing: 4) {
                    Text(seat.name)
                        .noirFont(metrics.tiny ? 11 : (metrics.compact ? 12 : 13), .medium, relativeTo: .footnote)
                        .foregroundStyle(Noir.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    PositionBadgeView(badge: seat.position, compact: metrics.compact)
                }
                .opacity(fadeDetails ? 0.45 : 1)
                Text(seat.styleShort)
                    .noirFont(metrics.dense ? 10 : 12, relativeTo: .caption)
                    .foregroundStyle(Noir.styleChipText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .frame(maxWidth: metrics.compact ? 72 : 120)
                    .background(Noir.styleChipBg, in: RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Noir.styleChipBorder, lineWidth: 1))
                HStack(spacing: 5) {
                    Text(seat.stackText)
                        .noirFont(12, relativeTo: .caption, digits: true)
                        .foregroundStyle(Noir.seatStack)
                        .opacity(fadeDetails ? 0.45 : 1)
                    if seat.peek != nil { Color.clear.frame(width: 21, height: 21) }
                }
            }
        }
        .padding(.horizontal, metrics.dense ? 4 : (metrics.compact ? 7 : 10))
        .padding(.vertical, 7)
        .frame(minWidth: metrics.plateMinWidth)
        .background(seat.folded && done ? Noir.plateFolded : Noir.plate, in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(border, lineWidth: 1))
        .turnGlow(seat.isActor, cornerRadius: radius)
        .shadow(color: seat.isWinner ? Noir.goldSeat.opacity(0.2) : .black.opacity(0.27), radius: seat.isWinner ? 10 : 7, y: seat.isWinner ? 0 : 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(seat.name), \(seat.position.name)")
        .accessibilityValue("\(seat.styleA11y). \(seat.stackText) chips\(seat.folded ? ". Folded" : "")")
        .overlay(alignment: .bottomTrailing) {
            if let peek = seat.peek {
                PeekButton(peek: peek, action: onPeek)
                    .padding(.trailing, metrics.dense ? 4 : (metrics.compact ? 7 : 10))
                    .padding(.bottom, 7)
            }
        }
    }

    private var avatar: some View {
        let colors = Noir.avatar(seat.id)
        return Text(seat.avatar)
            .noirFont(metrics.compact ? 12 : 14, .semibold, relativeTo: .caption)
            .foregroundStyle(colors.fg)
            .frame(width: metrics.avatarSize, height: metrics.avatarSize)
            .background(colors.bg, in: Circle())
            .overlay {
                if let ring = Noir.moodRing(seat.mood.rawValue) {
                    Circle().stroke(ring, lineWidth: 2).padding(-4)
                }
            }
            .accessibilityHidden(true)
    }
}

/// The post-settlement eye toggle (21×21 visual, 44×44 hit area).
struct PeekButton: View {
    let peek: PeekToggle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EyeShape()
                .stroke(peek.pressed ? Noir.mint : Noir.seatStack, lineWidth: 1.4)
                .frame(width: 15, height: 15)
                .frame(width: 21, height: 21)
                .background(peek.pressed ? Noir.peekPressedBg : .clear, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(peek.pressed ? Noir.peekPressedBorder : Noir.peekBorder, lineWidth: 1))
                .padding(11)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .padding(-11)
        .accessibilityLabel(peek.a11y)
        .accessibilityAddTraits(peek.pressed ? .isSelected : [])
        .accessibilityIdentifier("peek-toggle")
    }
}
