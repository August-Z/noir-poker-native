import SwiftUI
import PokerCore

/// The showdown stage below the arena: one panel per live player with their
/// own best five. Cards arrive once per settled hand (the view is keyed by
/// `showdown.key`), and winner panels play their hand category's motion.
struct ShowdownView: View {
    let showdown: ShowdownState
    let columns: Int
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("SHOWDOWN").eyebrowStyle(Noir.goldMuted, compact: true)
                    .accessibilityAddTraits(.isHeader)
                Text(showdown.context)
                    .noirFont(13, relativeTo: .subheadline)
                    .foregroundStyle(Color(hex: "#b9c8c7"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: max(columns, 1)),
                      spacing: 14) {
                ForEach(Array(showdown.scenes.enumerated()), id: \.offset) { _, scene in
                    ScenePanel(scene: scene, compact: compact)
                }
            }
        }
        .padding(.horizontal, compact ? 14 : 25)
        .padding(.top, compact ? 19 : 22)
        .padding(.bottom, compact ? 19 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                Noir.showdownBg
                EllipticalGradient(colors: [Color(hex: "#7b61351f"), .clear], center: .bottom,
                                   startRadiusFraction: 0, endRadiusFraction: 0.7)
            }
        )
        .overlay(alignment: .top) { Rectangle().fill(Noir.showdownBorder).frame(height: 1) }
        .id(showdown.key)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Showdown hand comparison")
        .accessibilityIdentifier("showdown")
    }
}

private struct ScenePanel: View {
    let scene: ShowdownSceneState
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                nameText
                    .noirFont(14, .semibold, relativeTo: .subheadline)
                Spacer(minLength: 8)
                Text(scene.statusText)
                    .noirFont(12, relativeTo: .caption)
                    .foregroundStyle(scene.isWinner ? Noir.goldWon : Noir.sceneNoPot)
                    .multilineTextAlignment(.trailing)
            }
            Text(scene.scene.label)
                .noirFont(24, relativeTo: .title2, tracking: 1)
                .foregroundStyle(scene.isWinner ? Noir.goldLight : Noir.sceneHand)
                .fixedSize(horizontal: false, vertical: true)
            Text(scene.scene.explanation)
                .noirFont(12, relativeTo: .caption)
                .foregroundStyle(Color(hex: "#99b3ab"))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: compact ? 6 : 7) {
                ForEach(Array(scene.scene.cards.enumerated()), id: \.offset) { i, card in
                    WinningCard(card: card, index: i,
                                match: scene.scene.highlights.indices.contains(i) && scene.scene.highlights[i],
                                winner: scene.isWinner, motion: scene.scene.motion)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            Rectangle().fill(Color(hex: "#34504466")).frame(height: 1)
            Text(scene.footerText)
                .noirFont(12, relativeTo: .caption)
                .foregroundStyle(scene.isWinner ? Noir.goldWon : Noir.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 11).fill(scene.isWinner
                ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#3b382322"), Color(hex: "#14252a")], startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyShapeStyle(Noir.scenePanel))
        )
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(scene.isWinner ? Noir.goldBorder : Noir.scenePanelBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scene.a11y)
        .accessibilityValue(spokenValue)
    }

    private var spokenValue: String {
        let cards = scene.scene.cards.map { CardNames.spoken($0) }.joined(separator: ", ")
        return "\(scene.statusText). \(scene.scene.explanation). \(cards). \(scene.footerText)"
    }

    private var nameText: Text {
        scene.nameSegments.reduce(Text("")) { text, segment in
            text + Text(segment.text).foregroundColor(segment.isPersona ? Noir.sceneName.opacity(0.7) : Noir.sceneName)
        }
    }
}

// MARK: Card motions

/// The animatable transform of one showdown card.
struct CardMotionValue {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rotation: Double = 0
    var rotationY: Double = 0
    var scale: CGFloat = 1
    var opacity: Double = 1
    /// Added brightness (CSS `brightness(1.12)` is about +0.12).
    var brightness: Double = 0
}

/// A reference keyframe animation as five stops (0 … 1) with a duration,
/// per-card delay and segment curve. Every motion uses exactly five stops so
/// the keyframe tracks stay static; intermediate stops interpolate the CSS
/// keyframes where the reference has fewer.
struct CardMotionPlan {
    var times: [Double]
    var values: [CardMotionValue]
    var duration: Double
    var delay: Double
    var curve: UnitCurve

    var final: CardMotionValue { values[4] }

    /// Segment `k` (1…4) duration in seconds.
    func segment(_ k: Int) -> Double { max((times[k] - times[k - 1]) * duration, 0.001) }

    /// `rank-arrive`: every card in every panel unless a winner motion replaces it.
    static func arrive(_ i: Int) -> CardMotionPlan {
        let from = CardMotionValue(y: 18, rotationY: 45, opacity: 0)
        let id = CardMotionValue()
        return CardMotionPlan(times: [0, 0.25, 0.5, 0.75, 1],
                              values: [from, mix(from, id, 0.6), mix(from, id, 0.85), mix(from, id, 0.96), id],
                              duration: 0.8, delay: Double(i) * 0.08, curve: .linear)
    }

    /// The winner motion for card `i`, or nil when this card keeps `rank-arrive`
    /// (kickers of the pair, two pair, trips, quads and high-card motions).
    static func winner(_ motion: HandMotion, index i: Int, match: Bool) -> CardMotionPlan? {
        let fi = Double(i)
        let c = CGFloat(i)
        let id = CardMotionValue()
        switch motion {
        case .high:
            guard match else { return nil }
            return CardMotionPlan(times: [0, 0.2, 0.4, 0.7, 1],
                                  values: [CardMotionValue(scale: 0.7, brightness: -0.25),
                                           CardMotionValue(y: -5, scale: 0.91, brightness: -0.05),
                                           CardMotionValue(y: -10, scale: 1.12, brightness: 0.12),
                                           CardMotionValue(y: -7.5, scale: 1.05, brightness: 0.05),
                                           CardMotionValue(y: -5)],
                                  duration: 1.7, delay: 0, curve: .easeOut)
        case .pair:
            guard match else { return nil }
            let up = CardMotionValue(y: -4, scale: 1.08)
            var rising = up
            rising.opacity = 0.67
            return CardMotionPlan(times: [0, 0.3, 0.45, 0.65, 1],
                                  values: [CardMotionValue(y: 14, opacity: 0), rising, id, up, id],
                                  duration: 1.5, delay: fi * 0.06, curve: .easeOut)
        case .twoPair:
            guard match else { return nil }
            let from = CardMotionValue(x: (1.5 - c) * 14, rotation: (fi - 1.5) * 8, opacity: 0)
            let peak = CardMotionValue(y: -7, opacity: 0.55)
            return CardMotionPlan(times: [0, 0.3, 0.55, 0.8, 1],
                                  values: [from, mix(from, peak, 0.55), peak, mix(peak, id, 0.55), id],
                                  duration: 1.6, delay: fi * 0.09, curve: .easeOut)
        case .trips:
            guard match else { return nil }
            return CardMotionPlan(times: [0, 0.45, 0.7, 0.85, 1],
                                  values: [CardMotionValue(y: 24, opacity: 0), CardMotionValue(y: -12, opacity: 0.45),
                                           CardMotionValue(y: 3, opacity: 0.7), CardMotionValue(y: 1.5, opacity: 0.85), id],
                                  duration: 1.6, delay: fi * 0.15, curve: .easeOut)
        case .straight:
            let from = CardMotionValue(y: 20, rotationY: 90, opacity: 0)
            let mid = CardMotionValue(y: -7)
            return CardMotionPlan(times: [0, 0.25, 0.5, 0.75, 1],
                                  values: [from, mix(from, mid, 0.5), mid, mix(mid, id, 0.5), id],
                                  duration: 1.6, delay: fi * 0.14, curve: .easeOut)
        case .flush:
            return CardMotionPlan(times: [0, 0.35, 0.7, 0.85, 1],
                                  values: [CardMotionValue(y: 10, rotation: -8, opacity: 0),
                                           CardMotionValue(y: -10, rotation: 5, opacity: 0.35, brightness: 0.12),
                                           CardMotionValue(y: 4, rotation: -2, opacity: 0.7, brightness: 0.05),
                                           CardMotionValue(y: 2, rotation: -1, opacity: 0.85, brightness: 0.02),
                                           id],
                                  duration: 1.8, delay: fi * 0.1, curve: .easeInOut)
        case .fullHouse:
            let from = CardMotionValue(x: (c - 2) * 20, y: 14, opacity: 0)
            let mid = CardMotionValue(x: (2 - c) * 3, y: -4, opacity: 0.5)
            return CardMotionPlan(times: [0, 0.25, 0.5, 0.75, 1],
                                  values: [from, mix(from, mid, 0.5), mid, mix(mid, id, 0.5), id],
                                  duration: 1.8, delay: fi * 0.08,
                                  curve: .bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.8), endControlPoint: UnitPoint(x: 0.2, y: 1)))
        case .quads:
            guard match else { return nil }
            return CardMotionPlan(times: [0, 0.25, 0.45, 0.65, 1],
                                  values: [CardMotionValue(scale: 0.6, opacity: 0),
                                           CardMotionValue(scale: 1.14, opacity: 0.25, brightness: 0.16),
                                           CardMotionValue(scale: 0.96, opacity: 0.45, brightness: 0.1),
                                           CardMotionValue(scale: 1.04, opacity: 0.65, brightness: 0.05),
                                           id],
                                  duration: 1.8, delay: fi * 0.06, curve: .easeOut)
        case .straightFlush:
            let from = CardMotionValue(y: 28, rotationY: 100, opacity: 0)
            let peak = CardMotionValue(y: (c - 2) * (c - 2) * -3 - 7, brightness: 0.15)
            return CardMotionPlan(times: [0, 0.2, 0.4, 0.7, 1],
                                  values: [from, mix(from, peak, 0.5), peak, mix(peak, id, 0.5), id],
                                  duration: 1.9, delay: fi * 0.1, curve: .easeOut)
        case .royal:
            let from = CardMotionValue(x: (2 - c) * 40, rotation: (fi - 2) * 14, opacity: 0)
            let peak = CardMotionValue(y: -10, rotation: (fi - 2) * 5, brightness: 0.14)
            let rest = CardMotionValue(rotation: (fi - 2) * 2)
            return CardMotionPlan(times: [0, 0.25, 0.5, 0.75, 1],
                                  values: [from, mix(from, peak, 0.5), peak, mix(peak, rest, 0.5), rest],
                                  duration: 2.0, delay: fi * 0.06, curve: .easeOut)
        }
    }

    private static func mix(_ a: CardMotionValue, _ b: CardMotionValue, _ t: Double) -> CardMotionValue {
        let f = CGFloat(t)
        return CardMotionValue(x: a.x + (b.x - a.x) * f,
                               y: a.y + (b.y - a.y) * f,
                               rotation: a.rotation + (b.rotation - a.rotation) * t,
                               rotationY: a.rotationY + (b.rotationY - a.rotationY) * t,
                               scale: a.scale + (b.scale - a.scale) * f,
                               opacity: a.opacity + (b.opacity - a.opacity) * t,
                               brightness: a.brightness + (b.brightness - a.brightness) * t)
    }
}

/// One card in a showdown panel: the made-hand cards are outlined (gold for
/// winners, mint for others) and kickers are dimmed. Winner panels replace the
/// arrival with their hand category's motion. Reduced motion shows the final
/// layout at once, with no transforms.
private struct WinningCard: View {
    let card: Card
    let index: Int
    let match: Bool
    let winner: Bool
    let motion: HandMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = false

    var body: some View {
        if reduceMotion {
            face
        } else {
            animated(plan: (winner ? CardMotionPlan.winner(motion, index: index, match: match) : nil) ?? .arrive(index))
        }
    }

    private var face: some View {
        CardFaceView(card: card, width: 43, height: 62)
            .overlay {
                if match {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(winner ? Noir.sceneMatch : Noir.sceneMatchLoser, lineWidth: 1)
                        .padding(-3)
                }
            }
            .shadow(color: match && winner ? Color(hex: "#cfad6525") : .clear, radius: 8)
            .opacity(match || reduceMotion ? 1 : 0.7)
    }

    private func animated(plan: CardMotionPlan) -> some View {
        face
            .keyframeAnimator(initialValue: plan.final, trigger: started) { content, v in
                content
                    .brightness(v.brightness)
                    .scaleEffect(v.scale)
                    .rotation3DEffect(.degrees(v.rotationY), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                    .rotationEffect(.degrees(v.rotation))
                    .offset(x: v.x, y: v.y)
                    .opacity(v.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    MoveKeyframe(plan.values[0].x)
                    LinearKeyframe(plan.values[0].x, duration: max(plan.delay, 0.001))
                    LinearKeyframe(plan.values[1].x, duration: plan.segment(1), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[2].x, duration: plan.segment(2), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[3].x, duration: plan.segment(3), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[4].x, duration: plan.segment(4), timingCurve: plan.curve)
                }
                KeyframeTrack(\.y) {
                    MoveKeyframe(plan.values[0].y)
                    LinearKeyframe(plan.values[0].y, duration: max(plan.delay, 0.001))
                    LinearKeyframe(plan.values[1].y, duration: plan.segment(1), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[2].y, duration: plan.segment(2), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[3].y, duration: plan.segment(3), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[4].y, duration: plan.segment(4), timingCurve: plan.curve)
                }
                KeyframeTrack(\.rotation) {
                    MoveKeyframe(plan.values[0].rotation)
                    LinearKeyframe(plan.values[0].rotation, duration: max(plan.delay, 0.001))
                    LinearKeyframe(plan.values[1].rotation, duration: plan.segment(1), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[2].rotation, duration: plan.segment(2), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[3].rotation, duration: plan.segment(3), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[4].rotation, duration: plan.segment(4), timingCurve: plan.curve)
                }
                KeyframeTrack(\.rotationY) {
                    MoveKeyframe(plan.values[0].rotationY)
                    LinearKeyframe(plan.values[0].rotationY, duration: max(plan.delay, 0.001))
                    LinearKeyframe(plan.values[1].rotationY, duration: plan.segment(1), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[2].rotationY, duration: plan.segment(2), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[3].rotationY, duration: plan.segment(3), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[4].rotationY, duration: plan.segment(4), timingCurve: plan.curve)
                }
                KeyframeTrack(\.scale) {
                    MoveKeyframe(plan.values[0].scale)
                    LinearKeyframe(plan.values[0].scale, duration: max(plan.delay, 0.001))
                    LinearKeyframe(plan.values[1].scale, duration: plan.segment(1), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[2].scale, duration: plan.segment(2), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[3].scale, duration: plan.segment(3), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[4].scale, duration: plan.segment(4), timingCurve: plan.curve)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(plan.values[0].opacity)
                    LinearKeyframe(plan.values[0].opacity, duration: max(plan.delay, 0.001))
                    LinearKeyframe(plan.values[1].opacity, duration: plan.segment(1), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[2].opacity, duration: plan.segment(2), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[3].opacity, duration: plan.segment(3), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[4].opacity, duration: plan.segment(4), timingCurve: plan.curve)
                }
                KeyframeTrack(\.brightness) {
                    MoveKeyframe(plan.values[0].brightness)
                    LinearKeyframe(plan.values[0].brightness, duration: max(plan.delay, 0.001))
                    LinearKeyframe(plan.values[1].brightness, duration: plan.segment(1), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[2].brightness, duration: plan.segment(2), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[3].brightness, duration: plan.segment(3), timingCurve: plan.curve)
                    LinearKeyframe(plan.values[4].brightness, duration: plan.segment(4), timingCurve: plan.curve)
                }
            }
            // Hidden until the first frame of the animation (CSS `fill-mode: both`).
            .opacity(started ? 1 : 0)
            .onAppear { started = true }
    }
}
