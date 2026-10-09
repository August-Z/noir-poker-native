import SwiftUI
import PokerCore

/// Table settings in one sheet: seat count (5–9, applied by the next deal),
/// opponent difficulty (applies now), opponent styles, table tips and sound,
/// in the same order as Android's Settings sheet. The same controls also sit on
/// the table surface and in the sidebar, as in the reference; this sheet gathers
/// them for phones and large text. Every value and option label comes from
/// `SettingsState`, and the session persists the changes.
struct SettingsSheet: View {
    let model: TableModel
    let onClose: () -> Void
    /// Set when the Opponent Styles row closes this sheet: the opponents sheet
    /// opens once this one has finished disappearing, because SwiftUI cannot
    /// present a second sheet while the first is still being dismissed.
    @State private var opensOpponentsOnDismiss = false

    private var settings: SettingsState { model.state.settings }
    private var coach: CoachState { model.state.coach }
    private var session: TableSession { model.session }
    private var opponents: OpponentsSummary { model.state.opponents }

    var body: some View {
        NoirSheet(eyebrow: UiCopy.settingsEyebrow, title: UiCopy.settingsTitle, closeLabel: UiCopy.settingsCloseA11y,
                  onClose: onClose) {
            section(UiCopy.playersLabel) {
                OptionGrid(options: settings.seatCountOptions.map { ($0.value, $0.label) },
                           selected: settings.requestedSeatCount, minimum: 92,
                           a11yPrefix: UiCopy.playerCountA11y) { session.setSeatCount($0) }
                if let note = settings.tableChangeNote {
                    Text(note)
                        .noirFont(12, relativeTo: .caption)
                        .foregroundStyle(Noir.note)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            section(UiCopy.difficultyLabel) {
                OptionGrid(options: settings.difficultyOptions.map { ($0.value, $0.label) },
                           selected: settings.difficulty, minimum: 92,
                           a11yPrefix: UiCopy.difficultyLabel) { session.setDifficulty($0) }
            }
            section(UiCopy.opponentsButton) {
                opponentsRow
                if let note = opponents.changeNote {
                    Text(note)
                        .noirFont(12, relativeTo: .caption)
                        .foregroundStyle(Noir.note)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 0) {
                toggleRow(title: UiCopy.settingsHints, detail: coach.toggleLabel, isOn: settings.hints,
                          id: "settings-hints") { session.toggleHints() }
                Rectangle().fill(Noir.line).frame(height: 1)
                toggleRow(title: UiCopy.settingsSound, detail: settings.soundTitle, isOn: settings.sound,
                          id: "settings-sound") { session.toggleSound() }
            }
            .padding(.horizontal, 14)
            .background(Color(hex: "#111b24"), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: "#33424b"), lineWidth: 1))
            Button(UiCopy.backToTable, action: onClose)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
        }
        .onDisappear {
            guard opensOpponentsOnDismiss else { return }
            opensOpponentsOnDismiss = false
            session.openOpponentSettings()
        }
    }

    /// Opponent Styles with the pending-change summary; opens the opponents sheet.
    private var opponentsRow: some View {
        Button {
            opensOpponentsOnDismiss = true
            onClose()
        } label: {
            HStack(spacing: 8) {
                Text(UiCopy.opponentsButton)
                    .noirFont(14, relativeTo: .body)
                    .foregroundStyle(Noir.selectText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(opponents.text)
                    .noirFont(12, relativeTo: .caption)
                    .foregroundStyle(opponents.changePending ? Noir.note : Noir.subtle)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Noir.selectText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Noir.selectBg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Noir.selectBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UiCopy.opponentsButton)
        .accessibilityValue(opponents.text)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("settings-opponents")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetHeading(title)
            content()
        }
    }

    private func toggleRow(title: String, detail: String, isOn: Bool, id: String, toggle: @escaping () -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { if $0 != isOn { toggle() } })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .noirFont(15, .medium, relativeTo: .body)
                    .foregroundStyle(Noir.text)
                Text(detail)
                    .noirFont(12, relativeTo: .caption)
                    .foregroundStyle(Noir.subtle)
            }
        }
        .tint(Noir.mint)
        .frame(minHeight: 56)
        .accessibilityIdentifier(id)
    }
}

/// A wrapping row of selectable options with 44 pt targets.
private struct OptionGrid<Value: Equatable>: View {
    let options: [(Value, String)]
    let selected: Value
    let minimum: CGFloat
    let a11yPrefix: String
    let select: (Value) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 8)], spacing: 8) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.0 == selected
                Button {
                    select(option.0)
                } label: {
                    Text(option.1)
                        .noirFont(13, isSelected ? .semibold : .regular, relativeTo: .subheadline)
                        .foregroundStyle(isSelected ? Noir.mint : Noir.selectText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isSelected ? Noir.mintDark : Noir.selectBg, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color(hex: "#73c9ad") : Noir.selectBorder, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(a11yPrefix + ": " + option.1)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Start New Session confirmation (reference `reset-dialog`).
struct ResetSheet: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NoirSheet(eyebrow: UiCopy.resetEyebrow, title: UiCopy.resetTitle, onClose: onCancel) {
            SheetParagraph(UiCopy.resetBody)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { buttons }
                VStack(spacing: 12) { buttons }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button(UiCopy.resetCancel, action: onCancel)
            .buttonStyle(OutlineButtonStyle(foreground: Noir.selectText, border: Noir.selectBorder, background: Noir.selectBg))
            .accessibilityIdentifier("reset-cancel")
        Button(UiCopy.resetConfirm, action: onConfirm)
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("confirm-reset")
    }
}
