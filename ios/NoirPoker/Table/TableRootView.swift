import SwiftUI
import PokerCore

/// The table screen. Phones in portrait use one scrolling column with the
/// action panel docked above the home indicator; tablets wider than 900 pt and
/// phones in landscape use two panes (table + sidebar), as in the reference
/// desktop layout. Large accessibility text keeps the action panel inline so it
/// never covers the table.
struct TableRootView: View {
    let model: TableModel
    @State private var showRules = false
    @State private var confirmReset = false
    @State private var showSettings = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var state: TableRenderState { model.state }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let landscapePhone = verticalSizeClass == .compact && width > geo.size.height
            let wide = width >= 900 || (landscapePhone && width >= 640)
            let sidebarWidth: CGFloat = width >= 1150 ? 284 : 245
            let gap: CGFloat = width >= 1150 ? 28 : 20
            let gutter: CGFloat = width < 600 ? 12 : (width < 1150 ? 16 : 24)
            VStack(spacing: 0) {
                HeaderView(state: state, width: width, toggleSound: { model.session.toggleSound() },
                           showSettings: { showSettings = true }, showRules: { showRules = true })
                if wide {
                    HStack(alignment: .top, spacing: gap) {
                        ScrollView {
                            mainColumn(width: width - sidebarWidth - gap - gutter * 2, docked: false, wide: true)
                                .padding(.vertical, 20)
                        }
                        ScrollView {
                            sidebar(width: sidebarWidth, sideColumn: true)
                                .padding(.vertical, 20)
                        }
                        .frame(width: sidebarWidth)
                    }
                    .padding(.horizontal, gutter)
                } else {
                    let docked = width < 600 && !typeSize.isAccessibilitySize
                    ScrollView {
                        VStack(spacing: 20) {
                            mainColumn(width: width - gutter * 2, docked: docked, wide: false)
                            sidebar(width: width - gutter * 2, sideColumn: false)
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
        .overlay(alignment: .topLeading) {
            if model.showsTestProbe { TestProbe(text: model.probeText) }
        }
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
        .sheet(isPresented: Binding(get: { state.opponentsDialog != nil },
                                    set: { if !$0 && model.state.opponentsDialog != nil { model.session.discardOpponentSettings() } })) {
            OpponentsSheet(model: model)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(model: model) { showSettings = false }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $confirmReset) {
            ResetSheet(onCancel: { confirmReset = false },
                       onConfirm: {
                           confirmReset = false
                           model.session.startNewSession()
                       })
                .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        }
    }

    // MARK: Main column

    private func mainColumn(width: CGFloat, docked: Bool, wide: Bool) -> some View {
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
                    ShowdownView(showdown: showdown, columns: width >= 700 ? 2 : 1, compact: compact)
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
            footer(showVirtual: wide && width >= 600)
        }
    }

    private func footer(showVirtual: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(Noir.mint).frame(width: 4, height: 4)
                Text("Offline computer opponents · No login required")
            }
            .accessibilityElement(children: .combine)
            if showVirtual {
                Spacer(minLength: 8)
                Text("Virtual chips only")
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

    /// Side column: stacked cards and the footnote. Below the table: stats and
    /// tips two-up, then the activity log across the full width in two
    /// columns (one column at the narrowest widths and accessibility sizes).
    @ViewBuilder
    private func sidebar(width: CGFloat, sideColumn: Bool) -> some View {
        let large = typeSize.isAccessibilitySize
        let twoUp = !sideColumn && width >= 330 && !large
        VStack(spacing: 18) {
            if twoUp {
                HStack(alignment: .top, spacing: width < 600 ? 12 : 18) {
                    SessionStatsCard(stats: state.session, compact: width < 600)
                    CoachCard(coach: state.coach, compact: width < 600) { model.session.toggleHints() }
                }
            } else {
                SessionStatsCard(stats: state.session, compact: sideColumn ? false : width < 600)
                CoachCard(coach: state.coach, compact: sideColumn ? false : width < 600) { model.session.toggleHints() }
            }
            ActivityCard(activity: state.activity, columns: !sideColumn && width >= 340 && !large ? 2 : 1,
                         compact: !sideColumn && width < 600)
            if sideColumn {
                HStack(alignment: .top, spacing: 10) {
                    SuitShape(suit: 0).fill(Noir.mint.opacity(0.2)).frame(width: 22, height: 24)
                    Text("Stay patient.\nGood cards will come. Good decisions are up to you.")
                        .noirFont(11, relativeTo: .caption)
                        .foregroundStyle(Noir.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The public table snapshot for UI tests (debug UI-test launches only).
private struct TestProbe: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 1))
            .frame(width: 1, height: 1)
            .clipped()
            .opacity(0.02)
            .allowsHitTesting(false)
            .accessibilityLabel(text)
            .accessibilityIdentifier("qa-state")
    }
}

// MARK: Header

private struct HeaderView: View {
    let state: TableRenderState
    let width: CGFloat
    let toggleSound: () -> Void
    let showSettings: () -> Void
    let showRules: () -> Void

    private var compact: Bool { width < 600 }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                SuitShape(suit: 0).fill(Noir.mint)
                    .frame(width: compact ? 22 : 26, height: compact ? 24 : 29)
                    .accessibilityHidden(true)
                Text("NOIR")
                    .noirFont(compact ? 18 : 22, .heavy, relativeTo: .title3, tracking: compact ? 2 : 3)
                    .foregroundStyle(Noir.text)
                if width > 360 {
                    Text("POKER")
                        .noirFont(compact ? 11 : 15, relativeTo: .footnote, tracking: compact ? 2 : 4)
                        .foregroundStyle(Noir.brandLight)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("NOIR Poker")
            .accessibilityAddTraits(.isHeader)
            if !compact {
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    Circle().fill(Noir.mint).frame(width: 6, height: 6)
                    Text("Solo Practice")
                    if width > 900 {
                        Rectangle().fill(Color(hex: "#35424e")).frame(width: 1, height: 14)
                        Text(state.tableSize)
                    }
                }
                .noirFont(13, relativeTo: .footnote)
                .foregroundStyle(Noir.headerCenter)
                .lineLimit(1)
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
            .accessibilityAddTraits(state.settings.sound ? .isSelected : [])
            .accessibilityIdentifier("sound-toggle")
            Button(action: showSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Noir.muted)
                    .frame(width: compact ? 32 : 38, height: compact ? 32 : 38)
                    .overlay(Circle().strokeBorder(Noir.line, lineWidth: 1))
                    .minimumHitTarget()
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings")
            Button(action: showRules) {
                HStack(spacing: 6) {
                    Text("How to Play")
                        .noirFont(14, .medium, relativeTo: .subheadline)
                        .foregroundStyle(Noir.text)
                        .lineLimit(1)
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
    @Environment(\.dynamicTypeSize) private var typeSize

    private var state: TableRenderState { model.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    handLabel
                    opponentsButton
                    playersMenu
                    difficulty
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        handLabel
                        Spacer(minLength: 8)
                        opponentsButton
                        playersMenu
                        difficulty
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        handLabel
                        HStack(spacing: 12) {
                            opponentsButton
                            Spacer(minLength: 8)
                            playersMenu
                        }
                        difficulty
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        handLabel
                        opponentsButton
                        playersMenu
                        difficulty
                    }
                }
            }
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .noirFont(compact ? 11 : 12, relativeTo: .caption)
                    .foregroundStyle(Noir.note)
                    .lineSpacing(3)
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
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hand-label")
    }

    private var opponentsButton: some View {
        Button {
            model.session.openOpponentSettings()
        } label: {
            HStack(spacing: 8) {
                Text("Opponent Styles")
                    .noirFont(14, relativeTo: .subheadline)
                    .foregroundStyle(Color(hex: "#d0e4df"))
                Text(state.opponents.text)
                    .noirFont(12, relativeTo: .caption)
                    .foregroundStyle(state.opponents.changePending ? Noir.note : Color(hex: "#8daea6"))
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .background(Color(hex: "#17272b"), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(hex: "#43504f"), lineWidth: 1))
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Opponent Styles")
        .accessibilityValue(state.opponents.text)
        .accessibilityIdentifier("opponent-styles")
    }

    private var playersLabel: String {
        state.settings.seatCountOptions.first { $0.value == state.settings.requestedSeatCount }?.label ?? ""
    }

    private var playersMenu: some View {
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
                Text(playersLabel).foregroundStyle(Noir.selectText)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Noir.selectText)
            }
            .noirFont(12, relativeTo: .caption)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(Noir.selectBg, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Noir.selectBorder, lineWidth: 1))
            .minimumHitTarget()
        }
        .accessibilityLabel("Table size")
        .accessibilityValue(playersLabel)
        .accessibilityIdentifier("table-size")
    }

    private var difficulty: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: compact ? 5 : 10) {
                difficultyLabel
                difficultySegments
            }
            VStack(alignment: .leading, spacing: 6) {
                difficultyLabel
                difficultySegments
            }
        }
    }

    private var difficultyLabel: some View {
        Text("Opponent Difficulty")
            .noirFont(compact ? 11 : 12, relativeTo: .caption)
            .foregroundStyle(Noir.subtle)
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var difficultySegments: some View {
            HStack(spacing: 2) {
                ForEach(state.settings.difficultyOptions, id: \.value) { option in
                    let selected = option.value == state.settings.difficulty
                    Button {
                        model.session.setDifficulty(option.value)
                    } label: {
                        Text(option.label)
                            .noirFont(12, selected ? .semibold : .regular, relativeTo: .caption)
                            .foregroundStyle(selected ? Noir.mint : Noir.subtle)
                            .lineLimit(1)
                            .fixedSize()
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
