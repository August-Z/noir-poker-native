import SwiftUI
import PokerCore

/// The showdown stage below the arena: one panel per live player with their
/// own best five. Cards arrive once per settled hand (keyed by `showdown.key`).
struct ShowdownView: View {
    let showdown: ShowdownState
    let columns: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SHOWDOWN").eyebrowStyle(Noir.goldMuted, compact: true)
                Text(showdown.context)
                    .noirFont(13, relativeTo: .subheadline)
                    .foregroundStyle(Noir.text)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: max(columns, 1)),
                      spacing: 14) {
                ForEach(Array(showdown.scenes.enumerated()), id: \.offset) { _, scene in
                    ScenePanel(scene: scene)
                }
            }
        }
        .padding(.horizontal, columns > 1 ? 25 : 14)
        .padding(.vertical, columns > 1 ? 22 : 19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                Noir.showdownBg
                RadialGradient(colors: [Color(hex: "#7b61351f"), .clear], center: .bottom, startRadius: 0, endRadius: 400)
            }
        )
        .overlay(alignment: .top) { Rectangle().fill(Noir.showdownBorder).frame(height: 1) }
        .id(showdown.key)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Showdown hand comparison")
    }
}

private struct ScenePanel: View {
    let scene: ShowdownSceneState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(scene.nameSegments.plainText)
                    .noirFont(14, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(Noir.sceneName)
                Spacer(minLength: 8)
                Text(scene.statusText)
                    .noirFont(12, relativeTo: .caption)
                    .foregroundStyle(scene.isWinner ? Noir.goldWon : Noir.sceneNoPot)
            }
            Text(scene.scene.label)
                .noirFont(24, relativeTo: .title2, tracking: 1)
                .foregroundStyle(scene.isWinner ? Noir.goldLight : Noir.sceneHand)
            Text(scene.scene.explanation)
                .noirFont(12, relativeTo: .caption)
                .foregroundStyle(Noir.subtle)
            HStack(spacing: 7) {
                ForEach(Array(scene.scene.cards.enumerated()), id: \.offset) { i, card in
                    let match = scene.scene.highlights.indices.contains(i) && scene.scene.highlights[i]
                    CardFaceView(card: card, width: 43, height: 62, small: true)
                        .overlay {
                            if match {
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(scene.isWinner ? Noir.sceneMatch : Noir.sceneMatchLoser, lineWidth: 1)
                                    .padding(-3)
                            }
                        }
                        .shadow(color: match && scene.isWinner ? Color(hex: "#cfad6525") : .clear, radius: 8)
                        .opacity(match ? 1 : 0.7)
                        .opacity(arrived || reduceMotion ? 1 : 0)
                        .offset(y: arrived || reduceMotion ? (match && scene.isWinner && scene.scene.motion == .high ? -5 : 0) : 18)
                        .rotation3DEffect(.degrees(arrived || reduceMotion ? 0 : 45), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                        .animation(reduceMotion ? nil : .timingCurve(0.18, 0.7, 0.25, 1, duration: 0.8).delay(Double(i) * 0.08), value: arrived)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            Rectangle().fill(Color(hex: "#34504466")).frame(height: 1)
            Text(scene.footerText)
                .noirFont(12, relativeTo: .caption)
                .foregroundStyle(scene.isWinner ? Noir.goldWon : Noir.subtle)
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
        .accessibilityValue("\(scene.statusText). \(scene.scene.explanation). \(scene.footerText)")
        .onAppear { DispatchQueue.main.async { arrived = true } }
    }
}
