import SwiftUI
import PokerCore

/// The decision strip and the hero's action panel (bet controls and buttons,
/// Finish Hand after a fold, or the settled-hand buttons).
struct ActionPanelView: View {
    let model: TableModel
    var compact: Bool
    var onReview: () -> Void

    private var a: ActionPanelState { model.state.actions }
    private var session: TableSession { model.session }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            if a.decisionStripVisible {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Noir.mint).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { d in d.height + 2 }
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
                if compact {
                    VStack(spacing: 12) {
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
                    .frame(maxWidth: compact ? CGFloat.infinity : 260)
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

    private var betControls: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(a.sliderLabel)
                    .noirFont(12, relativeTo: .caption)
                    .foregroundStyle(Noir.sliderLabel)
                Text(a.betText)
                    .noirFont(compact ? 16 : 18, .semibold, relativeTo: .headline, digits: true)
                    .foregroundStyle(Noir.text)
                    .contentTransition(.numericText())
            }
            .frame(width: compact ? 83 : 100, alignment: .leading)
            .accessibilityHidden(true)
            VStack(spacing: 8) {
                slider
                HStack(spacing: 6) {
                    ForEach(a.presets, id: \.preset) { preset in
                        Button {
                            session.preset(preset.preset)
                        } label: {
                            Text(preset.label)
                                .noirFont(compact ? 11 : 12, relativeTo: .caption)
                                .foregroundStyle(Noir.selectText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
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
                        .accessibilityValue(preset.amount.map { "Raise to \(formatChips($0))" } ?? "")
                    }
                }
            }
        }
        .disabled(!a.raiseEnabled)
        .opacity(a.raiseEnabled ? 1 : 0.46)
    }

    @ViewBuilder
    private var slider: some View {
        if let lo = a.sliderMin, let hi = a.sliderMax, hi > lo {
            Slider(value: Binding(get: { Double(a.bet) }, set: { session.setBet(Int($0.rounded())) }),
                   in: Double(lo)...Double(hi))
                .tint(Noir.mint)
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
                .disabled(true)
                .accessibilityLabel(a.sliderA11y)
                .accessibilityValue(a.betText)
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack(spacing: compact ? 8 : 9) {
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
    }

    private func actionButton(caption: String, amount: String?, enabled: Bool, fill: Color, text: Color, border: Color,
                              a11y: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(caption)
                    .noirFont(amount == nil ? (compact ? 14 : 15) : (compact ? 12 : 13), .medium, relativeTo: .subheadline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let amount {
                    Text(amount)
                        .noirFont(compact ? 17 : 18, .semibold, relativeTo: .headline, digits: true)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(text)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: compact ? 62 : 69)
            .background(fill, in: RoundedRectangle(cornerRadius: compact ? 7 : 9))
            .overlay(RoundedRectangle(cornerRadius: compact ? 7 : 9).strokeBorder(border, lineWidth: 1))
            .shadow(color: id == "raise" ? Noir.mint.opacity(0.1) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.46)
        .accessibilityLabel(a11y)
        .accessibilityIdentifier(id)
    }

    // MARK: Settled

    private var settledButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if a.nextHandVisible {
                    Button(a.nextHandLabel) { session.nextHand() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("next-hand")
                }
                if a.replayVisible {
                    Button(a.replayLabel) { session.replayHand() }
                        .buttonStyle(OutlineButtonStyle(foreground: Noir.replayText, border: Noir.replayBorder, background: Noir.replayBg))
                        .accessibilityHint(a.replayTitle)
                        .accessibilityIdentifier("replay-hand")
                }
                if a.reviewVisible && !compact {
                    reviewButton
                }
            }
            if a.reviewVisible && compact {
                reviewButton
            }
        }
    }

    private var reviewButton: some View {
        Button(a.reviewLabel) { onReview() }
            .buttonStyle(OutlineButtonStyle(foreground: Noir.reviewText, border: Noir.reviewBorder, background: Noir.reviewBg))
            .accessibilityIdentifier("review-hand")
    }
}
