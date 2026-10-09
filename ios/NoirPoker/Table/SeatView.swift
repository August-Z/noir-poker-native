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
    /// Bumped when the eye toggle shows this seat's cards: they fade in from
    /// 0.2 over 180 ms (the reference's `toggleOpponentHand`). Hiding, and the
    /// automatic reveal at showdown, change nothing gradually.
    @State private var revealFade = 0

    private var done: Bool { seat.peek != nil }

    var body: some View {
        VStack(spacing: 0) {
            cards
                .zIndex(0)
            plate
                .zIndex(1)
            if let badge = seat.badge {
                RankBadgeView(badge: badge, compact: metrics.compact)
                    .padding(.top, 6)
                    .transition(.opacity)
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
        .onChange(of: seat.peek?.pressed) { old, new in
            // Only a toggle on a settled table: the toggle existed before (the
            // showdown reveal creates it already pressed).
            if old == false, new == true, !reduceMotion { revealFade += 1 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("seat-\(seat.id)")
    }

    private var actionSpoken: String { seat.actionSpoken }

    @ViewBuilder
    private var cards: some View {
        if seat.revealed && !seat.cards.isEmpty {
            HStack(spacing: metrics.compact ? 4 : 5) {
                ForEach(Array(seat.cards.enumerated()), id: \.offset) { _, face in
                    CardFaceView(card: face.card, width: metrics.seatCard.width, height: metrics.seatCard.height,
                                 small: true, best: face.best)
                }
            }
            .padding(.bottom, 6)
            .keyframeAnimator(initialValue: 1.0, trigger: revealFade) { content, opacity in
                content.opacity(opacity)
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(0.2)
                    LinearKeyframe(1.0, duration: 0.18, timingCurve: .easeOut)
                }
            }
            .id("faces-\(newHandKey)-\(seat.id)")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(seat.name)'s hole cards")
            .accessibilityValue(seat.cards.map { CardNames.spoken($0.card) }.joined(separator: ", "))
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
            .transition(.opacity)
            .id("backs-\(newHandKey)-\(seat.id)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(seat.cardBackA11y)
            .accessibilityValue("\(seat.cardBacks)")
        }
    }

    private var plateA11yValue: String { seat.plateA11yValue }

    private var plate: some View {
        let radius: CGFloat = metrics.compact ? 8 : 10
        let border: Color = seat.isWinner ? (done ? Noir.gold : Noir.goldSeat)
            : seat.isActor ? Noir.mint
            : (seat.folded && done ? Noir.plateFoldedBorder : Noir.plateBorder)
        let fadeDetails = seat.folded && done
        let avatars = metrics.showAvatars
        return HStack(spacing: metrics.compact ? 6 : 8) {
            if avatars {
                avatar.opacity(fadeDetails ? 0.45 : 1)
            }
            VStack(alignment: seat.peek != nil ? .trailing : .center, spacing: 3) {
                HStack(spacing: 4) {
                    Text(seat.name)
                        .noirFont(metrics.tiny ? 11 : (metrics.compact ? 12 : 13), .medium, relativeTo: .footnote)
                        .foregroundStyle(Noir.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    PositionBadgeView(badge: seat.position, compact: metrics.compact, dense: metrics.dense)
                }
                .opacity(fadeDetails ? 0.45 : 1)
                Text(seat.styleShort)
                    .noirFont(metrics.dense ? 10 : 12, relativeTo: .caption)
                    .foregroundStyle(Noir.styleChipText)
                    .multilineTextAlignment(.center)
                    // Multi-word styles wrap between words; a single word
                    // shrinks instead of breaking mid-word at large sizes.
                    .lineLimit(seat.styleShort.contains(" ") ? 2 : 1)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: seat.styleShort.contains(" "))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .frame(maxWidth: metrics.compact ? 72 : 120)
                    .background(Noir.styleChipBg, in: RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Noir.styleChipBorder, lineWidth: 1))
                HStack(spacing: 5) {
                    Text(seat.stackText)
                        .noirFont(12, relativeTo: .caption, digits: true)
                        .foregroundStyle(Noir.seatStack)
                        .lineLimit(1)
                        .opacity(fadeDetails ? 0.45 : 1)
                        .contentTransition(.numericText())
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
        .shadow(color: seat.isWinner ? (done ? Noir.gold.opacity(0.21) : Noir.goldSeat.opacity(0.14)) : .black.opacity(0.27),
                radius: seat.isWinner ? 10 : 7, y: seat.isWinner ? 0 : 7)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: seat.isWinner)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: seat.isActor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(seat.name), \(seat.position.name)")
        .accessibilityValue(plateA11yValue)
        .accessibilityHint(seat.avatarTitle)
        .accessibilityIdentifier("seat-plate-\(seat.id)")
        .overlay(alignment: .bottomTrailing) {
            if let peek = seat.peek {
                PeekButton(peek: peek, seat: seat.id, action: onPeek)
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

extension SeatState {
    /// The spoken details of a seat plate (and of its large-text row).
    var plateA11yValue: String {
        var parts = [styleA11y, "\(stackText) chips"]
        if mood != .steady { parts.append("Simulated mood: \(moodLabel)") }
        if folded { parts.append("Folded") }
        if isActor { parts.append(action.label) }
        return parts.joined(separator: ". ")
    }

    /// The last action as one line: label, amount and meaning.
    var actionSpoken: String {
        if action.isDeciding { return action.label }
        var parts = [action.label]
        if let amount = action.amountText { parts.append(amount) }
        if let meaning = action.meaning { parts.append(meaning) }
        return parts.joined(separator: ", ")
    }
}

/// The large-text companion to the arena (accessibility text sizes, where the
/// felt caps its own text): every opponent as a full-size row with name,
/// position, style, stack, last action, hand badge and the reveal toggle, so
/// nothing is only readable on the scaled diagram. Mirrors Android's `SeatList`.
struct SeatListView: View {
    let seats: [SeatState]
    let done: Bool
    let onPeek: (Int) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(seats) { seat in
                SeatListRow(seat: seat, done: done) { onPeek(seat.id) }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("seat-list")
    }
}

private struct SeatListRow: View {
    let seat: SeatState
    let done: Bool
    let onPeek: () -> Void

    var body: some View {
        let border: Color = seat.isWinner ? (done ? Noir.gold : Noir.goldSeat) : seat.isActor ? Noir.mint : Noir.plateBorder
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { name; PositionBadgeView(badge: seat.position) }
                    VStack(alignment: .leading, spacing: 4) { name; PositionBadgeView(badge: seat.position) }
                }
                Text("\(seat.styleShort) · \(seat.stackText)")
                    .noirFont(13, relativeTo: .subheadline, digits: true)
                    .foregroundStyle(Noir.seatStack)
                    .fixedSize(horizontal: false, vertical: true)
                Text(actionText)
                    .noirFont(13, relativeTo: .subheadline)
                    .foregroundStyle(seat.action.isDeciding ? Noir.mint : (seat.isWinner ? Noir.goldAction : Noir.seatAction))
                    .fixedSize(horizontal: false, vertical: true)
                if let badge = seat.badge {
                    RankBadgeView(badge: badge)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(seat.name), \(seat.position.name)")
            .accessibilityValue(spoken)
            .accessibilityIdentifier("seat-list-\(seat.id)")
            if let peek = seat.peek {
                PeekButton(peek: peek, seat: seat.id, identifier: "seat-list-peek-\(seat.id)", action: onPeek)
                    .padding(11.5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(seat.folded && !done ? 0.6 : 1)
        .background(Noir.plate, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border, lineWidth: 1))
    }

    private var name: some View {
        Text(seat.name)
            .noirFont(14, .medium, relativeTo: .body)
            .foregroundStyle(Noir.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionText: String {
        [seat.action.label, seat.action.amountText].compactMap { $0 }.joined(separator: " ")
    }

    private var spoken: String {
        var parts = [seat.plateA11yValue, "\(seat.actionA11y): \(seat.actionSpoken)"]
        if let badge = seat.badge { parts.append(badge.a11y ?? badge.text) }
        return parts.joined(separator: ". ")
    }
}

/// The post-settlement eye toggle (21×21 visual, 44×44 hit area).
struct PeekButton: View {
    let peek: PeekToggle
    let seat: Int
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EyeShape()
                .stroke(peek.pressed ? Noir.mint : Noir.seatStack, lineWidth: 1.4)
                .frame(width: 15, height: 15)
                .frame(width: 21, height: 21)
                .background(peek.pressed ? Noir.peekPressedBg : .clear, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(peek.pressed ? Noir.peekPressedBorder : Noir.peekBorder, lineWidth: 1))
                .padding(11.5)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .padding(-11.5)
        .accessibilityLabel(peek.a11y)
        .accessibilityAddTraits(peek.pressed ? .isSelected : [])
        .accessibilityIdentifier(identifier ?? "peek-toggle-\(seat)")
    }
}
