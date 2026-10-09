import SwiftUI
import PokerCore

/// The showdown stage below the arena: one panel per live player with their
/// own best five. Cards arrive once per settled hand (the stage is keyed by
/// `showdown.key`), and winner panels play their hand category's motion.
struct ShowdownView: View {
    let showdown: ShowdownState
    let columns: Int
    var compact = false

    /// The reference grid (`showdown.css`): two columns above 1150 pt and at
    /// 601–900 pt of window width, one column at 901–1150 pt (beside the
    /// sidebar) and at 600 pt or less. Two panels also need a stage at least
    /// 620 pt wide, so a phone in landscape (whose table shares the window with
    /// the sidebar) keeps one column, and accessibility text sizes always use
    /// one column.
    static func columnCount(windowWidth: CGFloat, stageWidth: CGFloat, largeText: Bool) -> Int {
        let reference = windowWidth > 1150 || (windowWidth > 600 && windowWidth <= 900)
        return reference && stageWidth >= 620 && !largeText ? 2 : 1
    }

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
            SceneGrid(scenes: showdown.scenes, columns: max(columns, 1), compact: compact)
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

/// The panels in rows of `columns`. The grid is not lazy, so scrolling never
/// rebuilds a panel and replays its motion. One clock drives every card: it
/// starts when the stage appears (a new `showdown.key` makes a new stage) and
/// stops once the last card has come to rest. Reduced motion shows the final
/// layout at once, with no transforms.
private struct SceneGrid: View {
    let scenes: [ShowdownSceneState]
    let columns: Int
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var finished = false

    var body: some View {
        if reduceMotion {
            rows(elapsedMs: nil)
        } else {
            TimelineView(.animation(minimumInterval: nil, paused: finished)) { context in
                rows(elapsedMs: finished ? .infinity : context.date.timeIntervalSince(start) * 1000)
            }
            .task {
                try? await Task.sleep(nanoseconds: UInt64(endMs + 100) * 1_000_000)
                finished = true
            }
        }
    }

    /// When the last card of the stage comes to rest.
    private var endMs: Int {
        scenes.flatMap { scene in
            scene.scene.cards.indices.map { i in
                motion(scene, i).endMs
            }
        }.max() ?? 0
    }

    private func motion(_ scene: ShowdownSceneState, _ i: Int) -> CardMotion {
        CardMotion.forCard(i, motion: scene.scene.motion, winner: scene.isWinner, match: match(scene, i))
    }

    private func match(_ scene: ShowdownSceneState, _ i: Int) -> Bool {
        scene.scene.highlights.indices.contains(i) && scene.scene.highlights[i]
    }

    private func poses(_ scene: ShowdownSceneState, elapsedMs: Double?) -> [CardPose?] {
        scene.scene.cards.indices.map { i -> CardPose? in
            guard let elapsedMs else { return nil }
            return motion(scene, i).pose(atMs: elapsedMs)
        }
    }

    private func rows(elapsedMs: Double?) -> some View {
        let chunks = stride(from: 0, to: scenes.count, by: columns).map { Array(scenes[$0..<min($0 + columns, scenes.count)]) }
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(chunks.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(chunks[r].indices, id: \.self) { c in
                        let scene = chunks[r][c]
                        ScenePanel(scene: scene, compact: compact, poses: poses(scene, elapsedMs: elapsedMs))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    ForEach(chunks[r].count..<columns, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    }
                }
            }
        }
    }
}

private struct ScenePanel: View {
    let scene: ShowdownSceneState
    let compact: Bool
    /// Each card's pose on the motion clock, or nil under reduced motion.
    let poses: [CardPose?]

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
                    WinningCard(card: card,
                                match: scene.scene.highlights.indices.contains(i) && scene.scene.highlights[i],
                                winner: scene.isWinner, pose: poses.indices.contains(i) ? poses[i] : nil)
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

/// One card in a showdown panel: the made-hand cards are outlined (gold for
/// winners, mint for others) and kickers are dimmed to 0.7. `pose` is the
/// card's place on the motion clock (`CardMotion`); without one (reduced
/// motion) the card rests untransformed and kickers show at full opacity, as
/// the reference's reduced-motion rule does.
private struct WinningCard: View {
    let card: Card
    let match: Bool
    let winner: Bool
    let pose: CardPose?

    var body: some View {
        let p = pose ?? .identity
        CardFaceView(card: card, width: 43, height: 62)
            .overlay {
                if match {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(winner ? Noir.sceneMatch : Noir.sceneMatchLoser, lineWidth: 1)
                        .padding(-3)
                }
            }
            .shadow(color: match && winner ? Color(hex: "#cfad6525") : .clear, radius: 8)
            .opacity(match || pose == nil ? 1 : 0.7)
            // CSS brightness() multiplies; SwiftUI adds. On the white card
            // face the two agree.
            .brightness(p.brightness - 1)
            .scaleEffect(p.scale)
            .rotation3DEffect(.degrees(p.ry), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
            .rotationEffect(.degrees(p.rz))
            .offset(x: p.tx, y: p.ty)
            .opacity(p.alpha)
    }
}
