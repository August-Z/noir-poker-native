import SwiftUI
import PokerCore

/// Hand Review (reference `review-dialog`): the result header, analysis
/// summary and progress, the Your Decisions / Opponent Decisions tabs, each
/// with a step timeline and detail, and the method notes. Every string comes
/// from `presentReviewDialog` (PokerCore); the analysis itself runs off the
/// main thread in `DetachedReviewRunner`, and the session cancels it on next
/// hand, replay, reset and background.
struct ReviewSheet: View {
    let model: TableModel
    let onClose: () -> Void
    @State private var width: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    private var session: TableSession { model.session }
    /// Two columns (timeline beside the detail) on wide sheets, as in the reference above 700 px.
    private var wide: Bool { width >= 660 && !typeSize.isAccessibilitySize }

    var body: some View {
        let content = presentReviewDialog(model.state.review)
        NoirSheet(eyebrow: ReviewDialogCopy.eyebrow, title: content?.title ?? ReviewDialogCopy.titleDefault,
                  eyebrowColor: ReviewColors.eyebrow, closeLabel: ReviewDialogCopy.closeA11y, onClose: onClose) {
            if let content {
                resultRow(content)
                SummaryBox(content: content,
                           selectPriority: { session.selectReviewStep($0) },
                           retry: { session.retryReview() })
                ReviewTabs(perspective: content.perspective) { session.setReviewPerspective($0) }
                if content.perspective == .hero {
                    HeroPanelView(panel: content.hero, wide: wide, session: session)
                } else {
                    OpponentPanelView(panel: content.opponents, wide: wide, session: session)
                }
            }
            Text(ReviewDialogCopy.scope)
                .noirFont(12, relativeTo: .footnote)
                .foregroundStyle(Noir.subtle)
                .fixedSize(horizontal: false, vertical: true)
            MethodDisclosure()
            Button(ReviewDialogCopy.backToTable, action: onClose)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("review-back")
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: SheetWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(SheetWidthKey.self) { width = $0 }
    }

    private func resultRow(_ content: ReviewDialogContent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(content.resultContext)
                .noirFont(13, relativeTo: .subheadline)
                .foregroundStyle(Color(hex: "#8398a8"))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(content.resultChange)
                .noirFont(24, .medium, relativeTo: .title2, digits: true)
                .foregroundStyle(Color(hex: "#e69bab"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("review-result")
    }
}

/// The measured width of a sheet, for choosing one or two columns.
struct SheetWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: Palette

enum ReviewColors {
    static let eyebrow = Color(hex: "#b3a0ca")
    static let accent = Color(hex: "#d1b9f0")
    static let lavender = Color(hex: "#eadbf9")
    static let stepBorder = Color(hex: "#405061")
    static let stepBg = Color(hex: "#10212c")
    static let stepSelectedBorder = Color(hex: "#a690c1")
    static let stepSelectedBg = Color(hex: "#41374e55")
    static let stepMeta = Color(hex: "#8fa3b4")
    static let label = Color(hex: "#8da4b5")
    static let sceneBg = Color(hex: "#0d1c2588")
    static let sceneBorder = Color(hex: "#314454")
    static let sceneDivider = Color(hex: "#2d4150")
    static let note = Color(hex: "#8199a9")
    static let navBg = Color(hex: "#273544")
    static let navBorder = Color(hex: "#455565")

    static func chip(_ kind: ReviewChipKind) -> (bg: Color, fg: Color) {
        switch kind {
        case .attention: return (Color(hex: "#64394388"), Color(hex: "#f0b5bc"))
        case .consider: return (Color(hex: "#65573266"), Color(hex: "#e4cea0"))
        case .sound: return (Color(hex: "#284e4266"), Color(hex: "#a7d6bd"))
        case .pending: return (Color(hex: "#35445788"), Color(hex: "#abbacc"))
        }
    }
}

struct ReviewChip: View {
    let text: String
    let kind: ReviewChipKind

    var body: some View {
        let colors = ReviewColors.chip(kind)
        Text(text)
            .noirFont(11, .medium, relativeTo: .caption2)
            .foregroundStyle(colors.fg)
            .lineLimit(2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(colors.bg, in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: Summary

private struct SummaryBox: View {
    let content: ReviewDialogContent
    let selectPriority: (Int) -> Void
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(content.summaryTitle)
                .noirFont(15, .medium, relativeTo: .headline)
                .foregroundStyle(ReviewColors.lavender)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 10) {
                if content.running {
                    ProgressView()
                        .tint(ReviewColors.accent)
                        .accessibilityHidden(true)
                }
                Text(content.statusText)
                    .noirFont(13, relativeTo: .body)
                    .foregroundStyle(Noir.dialogBody)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("review-status")
            }
            if content.running && content.progressTotal > 0 {
                ProgressView(value: Double(min(content.progressDone, content.progressTotal)),
                             total: Double(content.progressTotal))
                    .tint(ReviewColors.accent)
                    .accessibilityLabel(content.statusText)
            }
            HStack(spacing: 18) {
                if let label = content.priorityLabel, let index = content.priorityIndex {
                    linkButton(label) { selectPriority(index) }
                        .accessibilityIdentifier("review-priority")
                }
                if content.retryVisible {
                    linkButton(ReviewDialogCopy.retryButton, action: retry)
                        .accessibilityIdentifier("review-retry")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: "#362e4777"), Color(hex: "#28324544")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: "#5c4c71"), lineWidth: 1))
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .noirFont(13, .medium, relativeTo: .subheadline)
                .underline()
                .foregroundStyle(ReviewColors.accent)
                .minimumHitTarget()
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: Tabs

private struct ReviewTabs: View {
    let perspective: HandReviewPerspective
    let select: (HandReviewPerspective) -> Void

    var body: some View {
        HStack(spacing: 4) {
            tab(ReviewDialogCopy.tabHero, .hero, id: "review-tab-hero")
            tab(ReviewDialogCopy.tabOpponents, .opponents, id: "review-tab-opponents")
        }
        .padding(3)
        .background(ReviewColors.stepBg, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ReviewColors.stepBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ReviewDialogCopy.tabsA11y)
    }

    private func tab(_ title: String, _ value: HandReviewPerspective, id: String) -> some View {
        let selected = perspective == value
        return Button {
            select(value)
        } label: {
            Text(title)
                .noirFont(13, selected ? .semibold : .regular, relativeTo: .subheadline)
                .foregroundStyle(selected ? ReviewColors.lavender : Color(hex: "#9fb0c0"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Color(hex: "#3c3451") : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(value == .opponents ? ReviewDialogCopy.tabOpponentsSubtitle : "")
        .accessibilityIdentifier(id)
    }
}

// MARK: Timeline

private struct ReviewTimeline: View {
    let title: String
    let count: String
    let a11y: String
    let items: [ReviewTimelineItem]
    let horizontal: Bool
    let select: (Int) -> Void

    private var selectedIndex: Int? { items.first { $0.selected }?.index }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .noirFont(13, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(Color(hex: "#e0e7ee"))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(count)
                    .noirFont(12, relativeTo: .caption)
                    .foregroundStyle(Noir.subtle)
            }
            if horizontal {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(items, id: \.index) { item in
                                stepButton(item)
                                    .frame(width: 184)
                                    .id(item.index)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .onAppear {
                        if let index = selectedIndex { proxy.scrollTo(index, anchor: .center) }
                    }
                    .onChange(of: selectedIndex) { _, index in
                        guard let index else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(index, anchor: .center) }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(items, id: \.index) { item in stepButton(item) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(a11y)
    }

    private func stepButton(_ item: ReviewTimelineItem) -> some View {
        Button {
            select(item.index)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Text("\(item.number)")
                    .noirFont(11, .semibold, relativeTo: .caption2, digits: true)
                    .foregroundStyle(Noir.text)
                    .frame(minWidth: 23, minHeight: 23)
                    .overlay(Circle().strokeBorder(Color(hex: "#536078"), lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.meta)
                        .noirFont(11, relativeTo: .caption)
                        .foregroundStyle(ReviewColors.stepMeta)
                    Text(item.label)
                        .noirFont(13, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(Noir.text)
                    ReviewChip(text: item.chip, kind: item.chipKind)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .background(item.selected ? ReviewColors.stepSelectedBg : ReviewColors.stepBg, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(item.selected ? ReviewColors.stepSelectedBorder : ReviewColors.stepBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.a11y)
        .accessibilityAddTraits(item.selected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// Lays the timeline beside the detail on wide sheets, above it otherwise.
private struct TimelineDetailLayout<Timeline: View, Detail: View>: View {
    let wide: Bool
    @ViewBuilder var timeline: Timeline
    @ViewBuilder var detail: Detail

    var body: some View {
        if wide {
            HStack(alignment: .top, spacing: 24) {
                ScrollView { timeline }
                    .frame(width: 235)
                    .frame(maxHeight: 640)
                VStack(alignment: .leading, spacing: 16) { detail }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                timeline
                detail
            }
        }
    }
}

// MARK: Shared detail pieces

private struct DetailHeader: View {
    let title: String
    let chip: String
    let kind: ReviewChipKind

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .noirFont(17, .medium, relativeTo: .headline)
                .foregroundStyle(Noir.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            ReviewChip(text: chip, kind: kind)
        }
    }
}

private struct SceneBox: View {
    let holeLabel: String
    let hole: [Card]
    let board: [Card]
    let position: String
    let pot: String
    let stack: String
    let wide: Bool

    var body: some View {
        let rows = wide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 22))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        VStack(alignment: .leading, spacing: 12) {
            rows {
                cardGroup(holeLabel, hole, empty: nil)
                cardGroup(ReviewDialogCopy.boardLabel, board, empty: ReviewDialogCopy.noBoard)
            }
            Rectangle().fill(ReviewColors.sceneDivider).frame(height: 1)
            HStack(alignment: .top, spacing: 12) {
                meta(ReviewDialogCopy.positionLabel, position)
                meta(ReviewDialogCopy.potLabel, pot)
                meta(ReviewDialogCopy.stackLabel, stack)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ReviewColors.sceneBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ReviewColors.sceneBorder, lineWidth: 1))
    }

    private func cardGroup(_ label: String, _ cards: [Card], empty: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .noirFont(12, relativeTo: .caption)
                .foregroundStyle(ReviewColors.label)
            if cards.isEmpty, let empty {
                Text(empty)
                    .noirFont(12, relativeTo: .caption)
                    .foregroundStyle(Color(hex: "#667e8b"))
                    .frame(minHeight: 42, alignment: .leading)
            } else {
                HStack(spacing: 5) {
                    ForEach(cards, id: \.self) { card in
                        CardFaceView(card: card, width: 30, height: 42, small: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(cards.isEmpty ? (empty ?? "") : cards.map { CardNames.spoken($0) }.joined(separator: ", "))
    }

    private func meta(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .noirFont(11, relativeTo: .caption2)
                .foregroundStyle(Color(hex: "#7f99ab"))
            Text(value)
                .noirFont(14, .semibold, relativeTo: .subheadline, digits: true)
                .foregroundStyle(Noir.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ChoiceBox: View {
    let label: String
    let value: String
    var suggested = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .noirFont(12, relativeTo: .caption)
                .foregroundStyle(suggested ? Color(hex: "#8eb9a4") : Color(hex: "#9faec1"))
            Text(value)
                .noirFont(15, .semibold, relativeTo: .headline)
                .foregroundStyle(Noir.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(suggested ? Color(hex: "#23453844") : Color(hex: "#22314255"), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(suggested ? Color(hex: "#5c796c") : Color(hex: "#3d4e5c"), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

private struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .foregroundStyle(Noir.subtle)
                        .accessibilityHidden(true)
                    Text(item)
                        .foregroundStyle(Noir.dialogBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .noirFont(13, relativeTo: .body)
            }
        }
    }
}

private struct StepNav: View {
    let canGoPrevious: Bool
    let canGoNext: Bool
    let position: String
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            navButton(ReviewDialogCopy.previous, enabled: canGoPrevious, action: previous)
            Spacer(minLength: 4)
            Text(position)
                .noirFont(12, relativeTo: .caption, digits: true)
                .foregroundStyle(Noir.subtle)
                .multilineTextAlignment(.center)
            Spacer(minLength: 4)
            navButton(ReviewDialogCopy.next, enabled: canGoNext, action: next)
        }
    }

    private func navButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .noirFont(13, .medium, relativeTo: .subheadline)
                .foregroundStyle(enabled ? Noir.text : Noir.subtle)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(ReviewColors.navBg, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ReviewColors.navBorder, lineWidth: 1))
                .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
    }
}

private struct ReviewDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .noirFont(13, .medium, relativeTo: .subheadline)
                .foregroundStyle(Color(hex: "#9dafbf"))
                .frame(minHeight: 44, alignment: .leading)
        }
        .tint(Color(hex: "#9dafbf"))
    }
}

private struct NoteText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .noirFont(12, relativeTo: .footnote)
            .foregroundStyle(ReviewColors.note)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Hero panel

private struct HeroPanelView: View {
    let panel: HeroReviewPanel
    let wide: Bool
    let session: TableSession

    var body: some View {
        TimelineDetailLayout(wide: wide) {
            ReviewTimeline(title: ReviewDialogCopy.timelineTitle, count: panel.count, a11y: ReviewDialogCopy.timelineA11y,
                           items: panel.items, horizontal: !wide, select: { session.selectReviewStep($0) })
        } detail: {
            if let detail = panel.detail {
                HeroDetailView(detail: detail, wide: wide, session: session)
            } else if let empty = panel.empty {
                SheetParagraph(empty)
            }
        }
    }
}

private struct HeroDetailView: View {
    let detail: HeroReviewDetail
    let wide: Bool
    let session: TableSession
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let pair = wide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
        VStack(alignment: .leading, spacing: 16) {
            DetailHeader(title: detail.title, chip: detail.status, kind: detail.statusKind)
            SceneBox(holeLabel: ReviewDialogCopy.holeLabel, hole: detail.hole, board: detail.board,
                     position: detail.position, pot: detail.pot, stack: detail.stack, wide: wide)
            pair {
                ChoiceBox(label: ReviewDialogCopy.yourChoice, value: detail.yourChoice)
                ChoiceBox(label: ReviewDialogCopy.suggestedLine, value: detail.suggestion, suggested: true)
            }
            if !detail.routes.isEmpty {
                pair {
                    ForEach(Array(detail.routes.enumerated()), id: \.offset) { _, route in routeCard(route) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(ReviewDialogCopy.routesA11y)
            }
            simulation
            VStack(alignment: .leading, spacing: 6) {
                Text(detail.decisionTitle)
                    .noirFont(15, .medium, relativeTo: .headline)
                    .foregroundStyle(Noir.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(detail.reason)
                    .noirFont(13, relativeTo: .body)
                    .foregroundStyle(Noir.dialogBody)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            evidence
            lesson
            VStack(alignment: .leading, spacing: 6) {
                SheetHeading(ReviewDialogCopy.planHeading)
                Text(detail.plan)
                    .noirFont(13, relativeTo: .body)
                    .foregroundStyle(Noir.dialogBody)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            metrics
            if let model = detail.modelNote { NoteText(model) }
            NoteText(detail.priceNote)
            ReviewDisclosure(title: ReviewDialogCopy.publicActionsSummary) {
                if let empty = detail.publicActionsEmpty {
                    Text(empty)
                        .noirFont(13, relativeTo: .body)
                        .foregroundStyle(Color(hex: "#9dafbf"))
                } else {
                    ForEach(Array(detail.publicActions.enumerated()), id: \.offset) { _, action in
                        HStack {
                            Text(action.name).foregroundStyle(Noir.text)
                            Spacer(minLength: 8)
                            Text(action.label).foregroundStyle(Color(hex: "#9dafbf"))
                        }
                        .noirFont(13, relativeTo: .body)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            StepNav(canGoPrevious: detail.canGoPrevious, canGoNext: detail.canGoNext, position: detail.stepPosition,
                    previous: { session.previousReviewStep() }, next: { session.nextReviewStep() })
        }
    }

    private func routeCard(_ route: ReviewRouteCard) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(route.kicker)
                .noirFont(11, .medium, relativeTo: .caption)
                .foregroundStyle(Color(hex: "#8eb9a4"))
            Text(route.label)
                .noirFont(14, .semibold, relativeTo: .subheadline)
                .foregroundStyle(Noir.text)
            Text(route.condition)
                .noirFont(13, relativeTo: .body)
                .foregroundStyle(Noir.dialogBody)
            Text(route.tradeoff)
                .noirFont(12, relativeTo: .footnote)
                .foregroundStyle(Noir.subtle)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(hex: "#13232d"), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: "#34495a"), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var simulation: some View {
        if let table = detail.simulation {
            SimulationTableView(table: table, stacked: typeSize.isAccessibilitySize || (!wide && typeSize >= .xxLarge))
        } else if let note = detail.simulationNote {
            NoteText(note)
        }
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SheetHeading(ReviewDialogCopy.evidenceHeading)
                Spacer(minLength: 8)
                Text(detail.confidence)
                    .noirFont(12, relativeTo: .caption)
                    .foregroundStyle(Noir.subtle)
                    .multilineTextAlignment(.trailing)
            }
            BulletList(items: detail.evidence)
        }
    }

    private var lesson: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ReviewDialogCopy.lessonLabel)
                .noirFont(12, .medium, relativeTo: .caption)
                .foregroundStyle(Color(hex: "#9c8dae"))
            Text(detail.lesson)
                .noirFont(13, relativeTo: .body)
                .foregroundStyle(Color(hex: "#c8b8dc"))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) { Rectangle().fill(Color(hex: "#9f84be")).frame(width: 2) }
        .accessibilityElement(children: .combine)
    }

    private var metrics: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return layout {
            ForEach(Array(detail.metrics.enumerated()), id: \.offset) { _, metric in
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.label)
                        .noirFont(11, relativeTo: .caption2)
                        .foregroundStyle(Color(hex: "#8da2b5"))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(metric.value)
                        .noirFont(17, .semibold, relativeTo: .headline, digits: true)
                        .foregroundStyle(Noir.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(hex: "#13222c"), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct SimulationTableView: View {
    let table: ReviewSimulationTable
    let stacked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetHeading(table.heading)
            Text(table.stability)
                .noirFont(13, relativeTo: .body)
                .foregroundStyle(table.stable ? Color(hex: "#a7d6bd") : Color(hex: "#e4cea0"))
                .fixedSize(horizontal: false, vertical: true)
            Text(table.caption)
                .noirFont(12, relativeTo: .caption)
                .foregroundStyle(Noir.subtle)
                .fixedSize(horizontal: false, vertical: true)
            if stacked {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.label)
                                .noirFont(13, .semibold, relativeTo: .subheadline)
                                .foregroundStyle(Noir.text)
                            ForEach(Array(row.cells.enumerated()), id: \.offset) { i, cell in
                                Text(column(i + 1) + ": " + cell.value + " " + cell.margin)
                                    .noirFont(13, relativeTo: .body, digits: true)
                                    .foregroundStyle(Noir.dialogBody)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                grid
            }
            ReviewDisclosure(title: table.detailsSummary) {
                NoteText(table.note)
                NoteText(table.detailsBody)
            }
        }
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                ForEach(Array(table.columns.enumerated()), id: \.offset) { i, title in
                    Text(title)
                        .noirFont(11, .medium, relativeTo: .caption2)
                        .foregroundStyle(Color(hex: "#8da2b5"))
                        .gridColumnAlignment(i == 0 ? .leading : .trailing)
                        .accessibilityHidden(true)
                }
            }
            Divider().overlay(ReviewColors.sceneDivider)
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.label)
                        .noirFont(13, .medium, relativeTo: .subheadline)
                        .foregroundStyle(Noir.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(rowLabel(row))
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(cell.value)
                                .noirFont(14, .semibold, relativeTo: .subheadline, digits: true)
                                .foregroundStyle(Noir.text)
                            Text(cell.margin)
                                .noirFont(11, relativeTo: .caption2, digits: true)
                                .foregroundStyle(Noir.subtle)
                        }
                        .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(hex: "#0f1d26"), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ReviewColors.sceneBorder, lineWidth: 1))
    }

    private func column(_ i: Int) -> String { table.columns.indices.contains(i) ? table.columns[i] : "" }

    private func rowLabel(_ row: ReviewSimulationRow) -> String {
        var parts = [row.label]
        for (i, cell) in row.cells.enumerated() { parts.append(column(i + 1) + " " + cell.value + ", " + cell.margin) }
        return parts.joined(separator: "; ")
    }
}

// MARK: Opponent panel

private struct OpponentPanelView: View {
    let panel: OpponentReviewPanel
    let wide: Bool
    let session: TableSession

    private var filterLabel: String { panel.filters.first { $0.selected }?.label ?? ReviewDialogCopy.opponentFilterAll }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetParagraph(ReviewDialogCopy.opponentIntro)
            Menu {
                ForEach(Array(panel.filters.enumerated()), id: \.offset) { _, option in
                    Button {
                        session.setOpponentReviewFilter(option.seat)
                    } label: {
                        if option.selected {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(ReviewDialogCopy.opponentFilterLabel).foregroundStyle(Noir.subtle)
                    Text(filterLabel).foregroundStyle(Noir.selectText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Noir.selectText)
                }
                .noirFont(13, relativeTo: .subheadline)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Noir.selectBg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Noir.selectBorder, lineWidth: 1))
            }
            .accessibilityLabel(ReviewDialogCopy.opponentFilterLabel)
            .accessibilityValue(filterLabel)
            .accessibilityIdentifier("review-opponent-filter")
            TimelineDetailLayout(wide: wide) {
                ReviewTimeline(title: ReviewDialogCopy.opponentTimelineTitle, count: panel.count,
                               a11y: ReviewDialogCopy.opponentTimelineA11y, items: panel.items,
                               horizontal: !wide, select: { session.selectOpponentReviewRecord($0) })
            } detail: {
                if let detail = panel.detail {
                    OpponentDetailView(detail: detail, wide: wide,
                                       selected: panel.items.first { $0.selected }?.index ?? 0, session: session)
                } else if let empty = panel.empty {
                    SheetParagraph(empty)
                }
            }
        }
    }
}

private struct OpponentDetailView: View {
    let detail: OpponentReviewDetail
    let wide: Bool
    let selected: Int
    let session: TableSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailHeader(title: detail.title, chip: detail.chip, kind: detail.chipKind)
            SceneBox(holeLabel: detail.holeLabel, hole: detail.hole, board: detail.board,
                     position: detail.position, pot: detail.pot, stack: detail.stack, wide: wide)
            ChoiceBox(label: detail.choiceLabel, value: detail.action, suggested: true)
            VStack(alignment: .leading, spacing: 6) {
                Text(detail.explanationTitle)
                    .noirFont(15, .medium, relativeTo: .headline)
                    .foregroundStyle(Noir.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(detail.explanationDetail)
                    .noirFont(13, relativeTo: .body)
                    .foregroundStyle(Noir.dialogBody)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SheetHeading(ReviewDialogCopy.opponentEvidenceHeading)
                    Spacer(minLength: 8)
                    ReviewChip(text: detail.profileName, kind: .pending)
                }
                BulletList(items: detail.reasons)
            }
            NoteText(detail.warning)
            ReviewDisclosure(title: ReviewDialogCopy.opponentBranchesSummary) {
                if let empty = detail.branchesEmpty {
                    Text(empty)
                        .noirFont(13, relativeTo: .body)
                        .foregroundStyle(Color(hex: "#9dafbf"))
                } else {
                    ForEach(Array(detail.branches.enumerated()), id: \.offset) { _, branch in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(branch.label).foregroundStyle(Noir.text)
                            Text(branch.value)
                                .foregroundStyle(branch.hit ? Color(hex: "#a7d6bd") : Color(hex: "#9dafbf"))
                        }
                        .noirFont(13, relativeTo: .body, digits: true)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            StepNav(canGoPrevious: detail.canGoPrevious, canGoNext: detail.canGoNext, position: detail.sequenceText,
                    previous: { session.selectOpponentReviewRecord(selected - 1) },
                    next: { session.selectOpponentReviewRecord(selected + 1) })
        }
    }
}

// MARK: Method

private struct MethodDisclosure: View {
    var body: some View {
        ReviewDisclosure(title: ReviewDialogCopy.methodSummary) {
            NoteText(ReviewDialogCopy.methodInfo)
            NoteText(ReviewDialogCopy.methodPrice)
            NoteText(ReviewDialogCopy.methodRanges)
            HStack(spacing: 10) {
                Text(ReviewDialogCopy.methodRefsPrefix)
                    .noirFont(12, relativeTo: .footnote)
                    .foregroundStyle(ReviewColors.note)
                ForEach(ReviewDialogCopy.methodRefs, id: \.url) { ref in
                    if let url = URL(string: ref.url) {
                        Link(destination: url) {
                            Text(ref.label)
                                .noirFont(12, relativeTo: .footnote)
                                .underline()
                                .foregroundStyle(Color(hex: "#86ccb8"))
                                .minimumHitTarget()
                        }
                        .accessibilityHint("Opens in your browser")
                    }
                }
            }
            NoteText(ReviewDialogCopy.methodSimulation)
            NoteText(ReviewDialogCopy.methodOpponents)
        }
    }
}
