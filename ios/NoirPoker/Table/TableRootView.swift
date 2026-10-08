import SwiftUI
import PokerCore

/// The table screen. Phones use one scrolling column with the action panel
/// docked above the home indicator; tablets wider than 900 pt use two panes
/// (table + 284 pt sidebar), as in the reference desktop layout.
struct TableRootView: View {
    let model: TableModel
    @State private var showRules = false
    @State private var confirmReset = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var state: TableRenderState { model.state }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let wide = width >= 900
            let gutter: CGFloat = width < 600 ? 12 : 24
            VStack(spacing: 0) {
                HeaderView(state: state, compact: width < 600, toggleSound: { model.session.toggleSound() },
                           showRules: { showRules = true })
                if wide {
                    HStack(alignment: .top, spacing: 24) {
                        ScrollView {
                            mainColumn(width: width - 284 - 24 - gutter * 2, docked: false)
                                .padding(.vertical, 20)
                        }
                        ScrollView {
                            sidebar(width: 284, columnsForActivity: 1)
                                .padding(.vertical, 20)
                        }
                        .frame(width: 284)
                    }
                    .padding(.horizontal, gutter)
                } else {
                    let docked = width < 600
                    ScrollView {
                        VStack(spacing: 20) {
                            mainColumn(width: width - gutter * 2, docked: docked)
                            sidebar(width: width - gutter * 2,
                                    columnsForActivity: width >= 360 && !typeSize.isAccessibilitySize ? 2 : 1)
                        }
                        .padding(.horizontal, gutter)
                        .padding(.vertical, 16)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if docked { actionDock }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Noir.bg.ignoresSafeArea())
        .foregroundStyle(Noir.text)
        .sheet(isPresented: $showRules) {
            RulesSheet { showRules = false }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: Binding(get: { state.potDetails.open }, set: { if !$0 { model.session.closePotDetails() } })) {
            PotSheet(details: model.state.potDetails, toggle: { model.session.togglePotDistribution($0) },
                     onClose: { model.session.closePotDetails() })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: Binding(get: { state.review.dialogOpen }, set: { if !$0 { model.session.closeReview() } })) {
            ReviewSheet(model: model) { model.session.closeReview() }
                .presentationDetents([.large])
        }
        .alert("Start a new session?", isPresented: $confirmReset) {
            Button("Keep Practicing", role: .cancel) {}
            Button("Start New Session") { model.session.startNewSession() }
        } message: {
            Text("This session will end, every player returns to 5,000 chips, and your practice stats reset to zero.")
        }
    }

    // MARK: Main column

    private func mainColumn(width: CGFloat, docked: Bool) -> some View {
        let compact = width < 600
        return VStack(alignment: .leading, spacing: 16) {
            TableHeading(state: state, compact: compact)
            VStack(spacing: 0) {
                SurfaceTopBar(model: model, compact: compact)
                    .padding(.horizontal, compact ? 14 : 24)
                    .padding(.top, compact ? 14 : 20)
                    .padding(.bottom, 8)
                ArenaView(model: model, width: width - 2)
                if let showdown = state.showdown {
                    ShowdownView(showdown: showdown, columns: width >= 700 ? 2 : 1)
                }
                if !docked {
                    ActionPanelView(model: model, compact: compact) { model.session.openReview() }
                        .padding(compact ? 14 : 24)
                        .overlay(alignment: .top) { Rectangle().fill(Noir.stripDivider).frame(height: 1) }
                }
            }
            .frame(width: width)
            .background(NoirSurface.game, in: RoundedRectangle(cornerRadius: compact ? 14 : 18))
            .overlay(RoundedRectangle(cornerRadius: compact ? 14 : 18).strokeBorder(Noir.surfaceBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : 18))
            .shadow(color: .black.opacity(0.2), radius: 40, y: 24)
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(Noir.mint).frame(width: 4, height: 4)
                Text("Offline computer opponents · No login required")
            }
            Spacer(minLength: 8)
            Button("Start New Session") { confirmReset = true }
                .foregroundStyle(Noir.footerButton)
                .minimumHitTarget()
                .accessibilityIdentifier("start-new-session")
        }
        .noirFont(11, relativeTo: .caption)
        .foregroundStyle(Noir.footer)
    }

    private var actionDock: some View {
        ActionPanelView(model: model, compact: true) { model.session.openReview() }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(
                Noir.panel.opacity(0.97)
                    .overlay(alignment: .top) { Rectangle().fill(Noir.stripDivider).frame(height: 1) }
                    .ignoresSafeArea(edges: .bottom)
            )
    }

    // MARK: Sidebar

    @ViewBuilder
    private func sidebar(width: CGFloat, columnsForActivity: Int) -> some View {
        let twoUp = width >= 560 && !typeSize.isAccessibilitySize
        VStack(spacing: 18) {
            if twoUp {
                HStack(alignment: .top, spacing: 18) {
                    SessionStatsCard(stats: state.session)
                    CoachCard(coach: state.coach) { model.session.toggleHints() }
                }
            } else {
                SessionStatsCard(stats: state.session)
                CoachCard(coach: state.coach) { model.session.toggleHints() }
            }
            ActivityCard(activity: state.activity, columns: columnsForActivity)
            if width <= 300 {
                HStack(alignment: .top, spacing: 10) {
                    SuitShape(suit: 0).fill(Noir.mint.opacity(0.2)).frame(width: 22, height: 24)
                    Text("Stay patient.\nGood cards will come. Good decisions are up to you.")
                        .noirFont(11, relativeTo: .caption)
                        .foregroundStyle(Noir.subtle)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: Header

private struct HeaderView: View {
    let state: TableRenderState
    let compact: Bool
    let toggleSound: () -> Void
    let showRules: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                SuitShape(suit: 0).fill(Noir.mint)
                    .frame(width: compact ? 22 : 26, height: compact ? 24 : 29)
                    .accessibilityHidden(true)
                Text("NOIR")
                    .noirFont(compact ? 18 : 22, .heavy, relativeTo: .title3, tracking: compact ? 2 : 3)
                    .foregroundStyle(Noir.text)
                Text("POKER")
                    .noirFont(compact ? 11 : 15, relativeTo: .footnote, tracking: compact ? 2 : 4)
                    .foregroundStyle(Noir.brandLight)
            }
            if !compact {
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    Circle().fill(Noir.mint).frame(width: 6, height: 6)
                    Text("Solo Practice")
                    Rectangle().fill(Color(hex: "#35424e")).frame(width: 1, height: 14)
                    Text(state.tableSize)
                }
                .noirFont(13, relativeTo: .footnote)
                .foregroundStyle(Noir.headerCenter)
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 12)
            Button(action: toggleSound) {
                Image(systemName: state.settings.sound ? "speaker.wave.2" : "speaker.slash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(state.settings.sound ? Noir.mint : Noir.muted)
                    .frame(width: compact ? 32 : 38, height: compact ? 32 : 38)
                    .overlay(Circle().strokeBorder(Noir.line, lineWidth: 1))
                    .minimumHitTarget()
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(state.settings.soundA11y)
            .accessibilityValue(state.settings.soundTitle)
            .accessibilityIdentifier("sound-toggle")
            Button(action: showRules) {
                HStack(spacing: 6) {
                    Text("How to Play")
                        .noirFont(14, .medium, relativeTo: .subheadline)
                        .foregroundStyle(Noir.text)
                    if !compact {
                        Text("?")
                            .noirFont(11, relativeTo: .caption)
                            .foregroundStyle(Noir.muted)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Noir.line, lineWidth: 1))
                    }
                }
                .minimumHitTarget()
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("How to Play")
        }
        .padding(.horizontal, compact ? 16 : 28)
        .frame(minHeight: compact ? 60 : 76)
        .overlay(alignment: .bottom) { Rectangle().fill(Noir.headerBorder).frame(height: 1) }
    }
}

private struct TableHeading: View {
    let state: TableRenderState
    let compact: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("THE PRACTICE ROOM").eyebrowStyle(compact: compact)
                (Text("Every hand is a fresh chance") + Text(".").foregroundColor(Noir.mint))
                    .noirFont(compact ? 17 : 23, .medium, relativeTo: .title2, tracking: compact ? 0 : 1)
                    .foregroundStyle(Noir.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                TagLabel(text: state.tableTag)
                Text("Blinds 25 / 50").noirFont(12, relativeTo: .caption).foregroundStyle(Noir.muted)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: Surface top bar

private struct SurfaceTopBar: View {
    let model: TableModel
    let compact: Bool

    private var state: TableRenderState { model.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    handLabel
                    Spacer(minLength: 8)
                    settings
                }
                VStack(alignment: .leading, spacing: 10) {
                    handLabel
                    settings
                }
            }
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .noirFont(12, relativeTo: .caption)
                    .foregroundStyle(Noir.note)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private var notes: [String] {
        [state.settings.tableChangeNote, state.opponents.changeNote, state.replayNote].compactMap { $0 }
    }

    private var handLabel: some View {
        HStack(spacing: 8) {
            Text(state.handHeading).foregroundStyle(Noir.text)
            Text("·").foregroundStyle(Noir.subtle)
            Text(state.streetLabel).foregroundStyle(Noir.surfaceTopText)
            if let badge = state.replayBadge {
                TagLabel(text: badge, foreground: Noir.replayText, border: Noir.replayBorder, background: Noir.replayBg)
            }
        }
        .noirFont(compact ? 12 : 13, relativeTo: .footnote, digits: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hand-label")
    }

    private var settings: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(state.settings.seatCountOptions, id: \.value) { option in
                    Button {
                        model.session.setSeatCount(option.value)
                    } label: {
                        if option.value == state.settings.requestedSeatCount {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Players").foregroundStyle(Noir.subtle)
                    Text(state.settings.seatCountOptions.first { $0.value == state.settings.requestedSeatCount }?.label ?? "")
                        .foregroundStyle(Noir.selectText)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Noir.selectText)
                }
                .noirFont(12, relativeTo: .caption)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(Noir.selectBg, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Noir.selectBorder, lineWidth: 1))
                .minimumHitTarget()
            }
            .accessibilityLabel("Table size")
            .accessibilityValue(state.settings.seatCountOptions.first { $0.value == state.settings.requestedSeatCount }?.label ?? "")

            HStack(spacing: 2) {
                ForEach(state.settings.difficultyOptions, id: \.value) { option in
                    let selected = option.value == state.settings.difficulty
                    Button {
                        model.session.setDifficulty(option.value)
                    } label: {
                        Text(option.label)
                            .noirFont(12, selected ? .semibold : .regular, relativeTo: .caption)
                            .foregroundStyle(selected ? Noir.mint : Noir.subtle)
                            .padding(.horizontal, 9)
                            .frame(minHeight: 28)
                            .background(selected ? Noir.mintDark : .clear, in: RoundedRectangle(cornerRadius: 5))
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .padding(.vertical, -8)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityLabel("Opponent Difficulty: \(option.label)")
                }
            }
            .padding(2)
            .background(Noir.selectBg.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Noir.selectBorder, lineWidth: 1))
        }
    }
}
