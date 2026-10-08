import SwiftUI
import PokerCore

/// The decision strip and the hero's action panel (bet controls and buttons,
/// Finish Hand after a fold, or the settled-hand buttons).
struct ActionPanelView: View {
    let model: TableModel
    var compact: Bool
    var onReview: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var a: ActionPanelState { model.state.actions }
    private var session: TableSession { model.session }
    private var large: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            if a.decisionStripVisible {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Noir.mint).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { d in d.height + 2 }
                        .accessibilityHidden(true)
                    Text(a.decisionText)
                        .noirFont(compact ? 12 : 14, relativeTo: .subheadline)
                        .foregroundStyle(Noir.stripText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("decision-text")
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            }
            if a.controlsVisible {
                if compact || large {
                    VStack(spacing: compact ? 12 : 14) {
                        betControls
                        buttons
                    }
                } else {
                    HStack(alignment: .center, spacing: 18) {
                        betControls.frame(minWidth: 180).frame(maxWidth: .infinity)
                        buttons.frame(maxWidth: .infinity)
                            .layoutPriority(1)
                    }
                }
            } else if a.finishHandVisible {
                Button(a.finishHandLabel) { session.finishHand() }
                    .buttonStyle(OutlineButtonStyle(foreground: Noir.finishText, border: Noir.finishBorder, background: Noir.finishBg))
                    .frame(minWidth: compact ? nil : 200)
                    .frame(maxWidth: compact || large ? CGFloat.infinity : 260)
                    .frame(maxWidth: .infinity)
                    .disabled(!a.finishHandEnabled)
                    .opacity(a.finishHandEnabled ? 1 : 0.6)
                    .accessibilityHint(a.finishHandTitle)
                    .accessibilityIdentifier("finish-hand")
            } else if a.nextHandVisible || a.replayVisible || a.reviewVisible {
                settledButtons
            }
        }
        .animation(.easeInOut(duration: 0.2), value: a.controlsVisible)
    }

    // MARK: Bet controls

    private var amountLabel: some View {
        Text(a.betText)
            .noirFont(compact ? 16 : 18, .semibold, relativeTo: .headline, digits: true)
            .foregroundStyle(Noir.text)
            .contentTransition(.numericText())
            .lineLimit(1)
    }

    private var sliderCaption: some View {
        Text(a.sliderLabel)
            .noirFont(12, relativeTo: .caption)
            .foregroundStyle(Noir.sliderLabel)
            .lineLimit(1)
    }

    @ViewBuilder
    private var betControls: some View {
        Group {
            if compact && !large {
                // Phone grid: label and amount on the left, slider over presets on the right.
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        sliderCaption
                        amountLabel
                    }
                    .frame(width: 83, alignment: .leading)
                    .accessibilityHidden(true)
                    VStack(spacing: 8) {
                        slider
                        presetRow
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        sliderCaption
                        Spacer(minLength: 8)
                        amountLabel
                    }
                    .accessibilityHidden(true)
                    slider
                    if large {
                        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                            GridRow {
                                ForEach(a.presets.prefix(2), id: \.preset) { presetButton($0) }
                            }
                            GridRow {
                                ForEach(a.presets.dropFirst(2), id: \.preset) { presetButton($0) }
                            }
                        }
                    } else {
                        presetRow
                    }
                }
            }
        }
        .disabled(!a.raiseEnabled)
        .opacity(a.raiseEnabled ? 1 : 0.46)
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            ForEach(a.presets, id: \.preset) { preset in
                presetButton(preset)
            }
        }
    }

    private func presetButton(_ preset: PresetState) -> some View {
        Button {
            session.preset(preset.preset)
        } label: {
            Text(preset.label)
                .noirFont(compact ? 11 : 12, relativeTo: .caption)
                .foregroundStyle(Noir.selectText)
                .lineLimit(1)
                .minimumScaleFactor(large ? 1 : 0.75)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Noir.presetBg, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Noir.presetBorder, lineWidth: 1))
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .padding(.vertical, -7)
        .disabled(!preset.enabled)
        .opacity(preset.enabled ? 1 : 0.46)
        .accessibilityLabel(preset.label)
        .accessibilityValue(preset.amount.map { "\(a.sliderLabel) \(formatChips($0))" } ?? "")
        .accessibilityIdentifier("preset-\(preset.preset.rawValue)")
    }

    @ViewBuilder
    private var slider: some View {
        if let lo = a.sliderMin, let hi = a.sliderMax, hi > lo {
            Slider(value: Binding(get: { Double(a.bet) }, set: { session.setBet(Int($0.rounded())) }),
                   in: Double(lo)...Double(hi))
                .tint(Noir.mint)
                .frame(minHeight: 30)
                .accessibilityLabel(a.sliderA11y)
                .accessibilityValue(a.betText)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: session.nudgeBet(1)
                    case .decrement: session.nudgeBet(-1)
                    @unknown default: break
                    }
                }
                .accessibilityIdentifier("bet-slider")
        } else {
            Slider(value: .constant(0), in: 0...1)
                .tint(Noir.mint)
                .frame(minHeight: 30)
                .disabled(true)
                .accessibilityLabel(a.sliderA11y)
                .accessibilityValue(a.betText)
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttons: some View {
        if large {
            VStack(spacing: 8) { buttonSet }
        } else {
            HStack(spacing: compact ? 8 : 9) { buttonSet }
        }
    }

    @ViewBuilder
    private var buttonSet: some View {
        actionButton(caption: a.raiseCaption, amount: a.betText, enabled: a.raiseEnabled,
                     fill: Noir.mint, text: Noir.raiseText, border: Noir.mint, a11y: a.raiseA11y, id: "raise") {
            session.raise(nil)
        }
        actionButton(caption: a.foldLabel, amount: nil, enabled: a.foldEnabled,
                     fill: Noir.foldBg, text: Noir.foldText, border: Noir.foldBorder, a11y: a.foldLabel, id: "fold") {
            session.fold()
        }
        actionButton(caption: a.callLabel, amount: a.callAmountText, enabled: a.callEnabled,
                     fill: Noir.callBg, text: Noir.callText, border: Noir.callBorder, a11y: a.callA11y, id: "call") {
            session.callOrCheck()
        }
    }

    private func actionButton(caption: String, amount: String?, enabled: Bool, fill: Color, text: Color, border: Color,
                              a11y: String, id: String, action: @escaping () -> Void) -> some View {
        let tight = compact && !large
        return Button(action: action) {
            VStack(spacing: 2) {
                Text(caption)
                    .noirFont(amount == nil ? (tight ? 14 : 15) : (tight ? 12 : 13), .medium, relativeTo: .subheadline)
                    .multilineTextAlignment(.center)
                    .lineLimit(large ? nil : 2)
                    .minimumScaleFactor(large ? 1 : 0.8)
                    .fixedSize(horizontal: false, vertical: large)
                if let amount {
                    Text(amount)
                        .noirFont(tight ? 17 : 18, .semibold, relativeTo: .headline, digits: true)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(text)
            .padding(.horizontal, 6)
            .padding(.vertical, large ? 8 : 0)
            .frame(maxWidth: .infinity, minHeight: tight ? 62 : 69)
            .background(fill, in: RoundedRectangle(cornerRadius: tight ? 7 : 9))
            .overlay(RoundedRectangle(cornerRadius: tight ? 7 : 9).strokeBorder(border, lineWidth: 1))
            .shadow(color: id == "raise" ? Noir.mint.opacity(0.1) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.46)
        .accessibilityLabel(a11y)
        .accessibilityIdentifier(id)
    }

    // MARK: Settled

    @ViewBuilder
    private var settledButtons: some View {
        if large {
            VStack(spacing: 10) {
                nextButton
                replayButton
                reviewButton
            }
        } else if compact {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    nextButton
                    replayButton
                }
                reviewButton
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    nextButton.frame(minWidth: 160)
                    replayButton
                    reviewButton.frame(minWidth: 220)
                }
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        nextButton
                        replayButton
                    }
                    reviewButton
                }
            }
        }
    }

    @ViewBuilder
    private var nextButton: some View {
        if a.nextHandVisible {
            Button(a.nextHandLabel) { session.nextHand() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("next-hand")
        }
    }

    @ViewBuilder
    private var replayButton: some View {
        if a.replayVisible {
            Button(a.replayLabel) { session.replayHand() }
                .buttonStyle(OutlineButtonStyle(foreground: Noir.replayText, border: Noir.replayBorder, background: Noir.replayBg))
                .accessibilityHint(a.replayTitle)
                .accessibilityIdentifier("replay-hand")
        }
    }

    @ViewBuilder
    private var reviewButton: some View {
        if a.reviewVisible {
            Button(a.reviewLabel) { onReview() }
                .buttonStyle(OutlineButtonStyle(foreground: Noir.reviewText, border: Noir.reviewBorder, background: Noir.reviewBg))
                .accessibilityIdentifier("review-hand")
        }
    }
}
