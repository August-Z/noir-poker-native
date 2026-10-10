import SwiftUI
import PokerCore

/// Opponent Styles (reference `opponents-dialog`): archetype cards and detail,
/// per-seat assignment for all eight opponents, emotion simulation, Mixed
/// Lineup, the comparison table, and Save. Every edit changes the session's
/// draft; closing without saving discards it.
struct OpponentsSheet: View {
    let model: TableModel
    @State private var compareExpanded = false

    private var dialog: OpponentsDialogState? { model.state.opponentsDialog }
    private var session: TableSession { model.session }

    var body: some View {
        NoirSheet(eyebrow: UiCopy.oppEyebrow, title: UiCopy.oppTitle,
                  closeLabel: UiCopy.oppCloseA11y, onClose: { session.discardOpponentSettings() }) {
            if let dialog {
                SheetParagraph(UiCopy.oppIntro)
                profileCards(dialog)
                ProfileDetailPanel(detail: dialog.detail)
                roster(dialog)
                emotionBox(dialog)
                comparison(dialog)
                saveRow(dialog)
            }
        }
    }

    // MARK: Profiles

    private func profileCards(_ dialog: OpponentsDialogState) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8, alignment: .top)], spacing: 8) {
            ForEach(dialog.profileCards, id: \.id) { card in
                Button {
                    session.previewProfile(card.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.short)
                            .noirFont(15, .semibold, relativeTo: .headline)
                            .foregroundStyle(card.selected ? Color(hex: "#8fe1c5") : Noir.text)
                        Text(card.tag)
                            .noirFont(12, relativeTo: .caption)
                            .foregroundStyle(Color(hex: "#93a6ae"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.leading)
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                    .background(card.selected ? Color(hex: "#1a3833") : Color(hex: "#111a23"), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(card.selected ? Color(hex: "#73c9ad") : Color(hex: "#35434a"), lineWidth: 1))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityAddTraits(card.selected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(UiCopy.oppResearchA11y)
    }

    // MARK: Roster

    private func roster(_ dialog: OpponentsDialogState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SheetHeading(UiCopy.oppRosterHeading)
                Spacer(minLength: 8)
                Button(UiCopy.oppMixButton) { session.mixLineup() }
                    .noirFont(13, .medium, relativeTo: .subheadline)
                    .foregroundStyle(Color(hex: "#9cd7c3"))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(Color(hex: "#1d3630"), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(hex: "#52796c"), lineWidth: 1))
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("mixed-lineup")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10, alignment: .top)], spacing: 10) {
                ForEach(dialog.roster, id: \.id) { row in
                    RosterCard(row: row) { session.assignSeatStyle(row.id, $0) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(UiCopy.oppAssignA11y)
        }
    }

    // MARK: Emotion

    private func emotionBox(_ dialog: OpponentsDialogState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(UiCopy.oppEmotionLabel)
                .noirFont(14, .medium, relativeTo: .headline)
                .foregroundStyle(Noir.text)
            Picker(UiCopy.oppEmotionA11y, selection: Binding(get: { dialog.emotionMode },
                                                                       set: { session.setEmotionMode($0) })) {
                ForEach(dialog.emotionOptions, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(UiCopy.oppEmotionA11y)
            Text(UiCopy.oppEmotionHelp)
                .noirFont(12, relativeTo: .footnote)
                .foregroundStyle(Noir.dialogBody)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(hex: "#2a251d44"), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: "#554938"), lineWidth: 1))
    }

    // MARK: Comparison

    private func comparison(_ dialog: OpponentsDialogState) -> some View {
        DisclosureGroup(isExpanded: $compareExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text(UiCopy.oppCompareCaption)
                    .noirFont(12, .medium, relativeTo: .caption)
                    .foregroundStyle(Noir.dialogBody)
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                        GridRow {
                            Text(UiCopy.oppCompareArchetype).fontWeight(.semibold).foregroundStyle(Noir.subtle)
                            ForEach(PROFILE_AXES, id: \.self) { axis in
                                Text(axis).fontWeight(.semibold).foregroundStyle(Noir.subtle)
                            }
                            Text(UiCopy.oppCompareSizing).fontWeight(.semibold).foregroundStyle(Noir.subtle)
                        }
                        ForEach(dialog.comparison, id: \.id) { row in
                            GridRow {
                                Text(row.short).foregroundStyle(Noir.text)
                                ForEach(Array(row.axes.enumerated()), id: \.offset) { _, value in
                                    Text("\(value)").monospacedDigit().foregroundStyle(Noir.dialogBody)
                                }
                                Text(row.sizingText).monospacedDigit().foregroundStyle(Noir.dialogBody)
                            }
                        }
                    }
                    .noirFont(12, relativeTo: .caption)
                    .padding(.vertical, 4)
                }
                Text(UiCopy.oppCompareNoteAxes)
                Text(UiCopy.oppCompareNoteStats)
            }
            .noirFont(12, relativeTo: .footnote)
            .foregroundStyle(Noir.dialogBody)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
        } label: {
            Text(UiCopy.oppCompareSummary)
                .noirFont(13, relativeTo: .body)
                .foregroundStyle(Color(hex: "#86ccb8"))
        }
        .tint(Color(hex: "#86ccb8"))
    }

    // MARK: Save

    private func saveRow(_ dialog: OpponentsDialogState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Color(hex: "#354b49")).frame(height: 1)
            Text(dialog.saveNote)
                .noirFont(12, relativeTo: .footnote)
                .foregroundStyle(Noir.subtle)
                .fixedSize(horizontal: false, vertical: true)
            Button(UiCopy.oppSaveButton) { session.saveOpponentSettings() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("save-opponents")
        }
    }
}

/// The selected archetype: name, badge, description, five axis meters, bet
/// sizing, evidence and research links (opened in the system browser).
private struct ProfileDetailPanel: View {
    let detail: ProfileDetailState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(detail.profile.name)
                    .noirFont(17, .medium, relativeTo: .headline)
                    .foregroundStyle(Noir.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(detail.badge)
                    .noirFont(11, relativeTo: .caption2)
                    .foregroundStyle(Color(hex: "#9cd7c3"))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(hex: "#52796c"), lineWidth: 1))
            }
            Text(detail.profile.description)
                .noirFont(13, relativeTo: .body)
                .foregroundStyle(Noir.dialogBody)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(detail.axes, id: \.label) { axis in
                    HStack(spacing: 10) {
                        Text(axis.label)
                            .noirFont(12, relativeTo: .caption)
                            .foregroundStyle(Noir.dialogBody)
                            .frame(minWidth: 100, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#223c3b"))
                                RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#69c7a9"))
                                    .frame(width: geo.size.width * CGFloat(axis.value) / 100)
                            }
                        }
                        .frame(height: 12)
                        Text("\(axis.value)")
                            .noirFont(12, relativeTo: .caption, digits: true)
                            .foregroundStyle(Noir.text)
                            .frame(minWidth: 24, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(axis.label)
                    .accessibilityValue("\(axis.value) of 100")
                }
            }
            Text(detail.sizingText)
                .noirFont(13, relativeTo: .body)
                .foregroundStyle(Color(hex: "#dfc98f"))
            Text(detail.profile.evidence)
                .noirFont(12, relativeTo: .footnote)
                .foregroundStyle(Noir.subtle)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(detail.profile.sources, id: \.url) { source in
                if let url = URL(string: source.url) {
                    Link(destination: url) {
                        Text(source.label)
                            .noirFont(12, relativeTo: .footnote)
                            .underline()
                            .foregroundStyle(Color(hex: "#86ccb8"))
                            .multilineTextAlignment(.leading)
                            .minimumHitTarget()
                    }
                    .accessibilityHint(UiCopy.opensInBrowser)
                }
            }
        }
        .padding(17)
        .background(Color(hex: "#13282a"), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: "#354b49"), lineWidth: 1))
    }
}

/// One opponent in the roster: seat and mood, the style picker, this hand's
/// style, observed stats and the mood reason.
private struct RosterCard: View {
    let row: RosterRowState
    let assign: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name).noirFont(15, .medium, relativeTo: .headline).foregroundStyle(Noir.text)
                Spacer(minLength: 6)
                Text(row.subtitle).noirFont(12, relativeTo: .caption).foregroundStyle(Noir.subtle)
                    .multilineTextAlignment(.trailing)
            }
            Picker(row.selectA11y, selection: Binding(get: { row.assignment }, set: { assign($0) })) {
                ForEach(row.options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .tint(Noir.selectText)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Noir.selectBg, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Noir.selectBorder, lineWidth: 1))
            .accessibilityLabel(row.selectA11y)
            .accessibilityIdentifier("roster-style-\(row.id)")
            Text(row.currentStyle).noirFont(12, relativeTo: .caption).foregroundStyle(Noir.dialogBody)
                .fixedSize(horizontal: false, vertical: true)
            Text(row.observed).noirFont(12, relativeTo: .caption, digits: true).foregroundStyle(Noir.subtle)
                .accessibilityHint(row.observedTitle)
            if let reason = row.moodReason {
                Text(reason).noirFont(12, relativeTo: .caption).foregroundStyle(Color(hex: "#d6b887"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(row.offTable ? Color(hex: "#121a20") : Color(hex: "#111b24"), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color(hex: "#33424b"),
                                                                style: StrokeStyle(lineWidth: 1, dash: row.offTable ? [4, 3] : [])))
    }
}
