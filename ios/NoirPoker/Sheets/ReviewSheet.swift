import SwiftUI
import PokerCore

/// Hand Review (first version): analysis status, summary and the hero's graded
/// steps. Analysis runs off the main thread in `DetachedReviewRunner`.
struct ReviewSheet: View {
    let model: TableModel
    let onClose: () -> Void

    private var review: HandReviewState { model.state.review }

    var body: some View {
        NoirSheet(eyebrow: "HAND REVIEW", title: title, eyebrowColor: Color(hex: "#b3a0ca"), onClose: onClose) {
            if let input = review.input {
                Text(resultText(input.outcome.profit))
                    .noirFont(20, .medium, relativeTo: .title3, digits: true)
                    .foregroundStyle(Color(hex: "#e69bab"))
                statusBox(input)
                if let summary = review.analysis as? ReviewSummary {
                    ForEach(summary.steps, id: \.index) { step in
                        stepCard(step, selected: step.index == review.selected)
                    }
                }
            }
            Text("Reviewed with the information available at each decision · Ranges are assumptions; winning or losing does not by itself make a choice good or bad.")
                .noirFont(12, relativeTo: .footnote)
                .foregroundStyle(Noir.subtle)
                .fixedSize(horizontal: false, vertical: true)
            Button("Back to Table", action: onClose)
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var title: String {
        guard let hand = review.input?.hand else { return "Hand Review" }
        return "Hand \(hand) · Hand Review"
    }

    private func resultText(_ profit: Int) -> String {
        (profit > 0 ? "+" : "") + formatChips(profit) + " chips"
    }

    private func statusBox(_ input: HandReviewInput) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch review.status {
            case .done:
                if let summary = review.analysis as? ReviewSummary {
                    Text(summary.title).noirFont(15, .medium, relativeTo: .headline).foregroundStyle(Color(hex: "#eadbf9"))
                    Text(summary.summary).noirFont(13, relativeTo: .body).foregroundStyle(Noir.dialogBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .error:
                Text("Analysis didn't finish. You can try again.").noirFont(13, relativeTo: .body).foregroundStyle(Noir.dialogBody)
                Button("Analyze Again") { model.session.retryReview() }
                    .foregroundStyle(Color(hex: "#ddcafa"))
                    .minimumHitTarget()
            case .running, .idle:
                HStack(spacing: 10) {
                    ProgressView().tint(Color(hex: "#ddcafa"))
                    Text(review.progress > 0 || !input.decisions.isEmpty
                         ? "Analyzing decision \(review.progress) / \(input.decisions.count)…"
                         : "Preparing this hand's decision snapshots…")
                        .noirFont(13, relativeTo: .body)
                        .foregroundStyle(Noir.dialogBody)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: "#362e4777"), Color(hex: "#28324544")], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: "#5c4c71"), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func stepCard(_ step: DecisionAnalysis, selected: Bool) -> some View {
        let chip: (String, Color, Color) = {
            switch step.status {
            case .attention: return ("Needs Work", Color(hex: "#64394388"), Color(hex: "#f0b5bc"))
            case .consider: return ("Worth Discussing", Color(hex: "#65573266"), Color(hex: "#e4cea0"))
            case .sound: return ("Well Reasoned", Color(hex: "#284e4266"), Color(hex: "#a7d6bd"))
            }
        }()
        return Button {
            model.session.selectReviewStep(step.index)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Step \(step.index + 1)").noirFont(12, relativeTo: .caption).foregroundStyle(Noir.subtle)
                    Spacer()
                    Text(chip.0).noirFont(11, .medium, relativeTo: .caption2).foregroundStyle(chip.2)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(chip.1, in: RoundedRectangle(cornerRadius: 4))
                }
                Text(step.title).noirFont(15, .medium, relativeTo: .headline).foregroundStyle(Noir.text)
                Text(step.reason).noirFont(13, relativeTo: .body).foregroundStyle(Noir.dialogBody)
                if selected {
                    Text(step.recommendation).noirFont(13, .medium, relativeTo: .body).foregroundStyle(Noir.mint)
                    Text(step.lesson).noirFont(13, relativeTo: .body).foregroundStyle(Color(hex: "#eadbf9"))
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color(hex: "#41374e55") : Color(hex: "#10212c"), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color(hex: "#a690c1") : Color(hex: "#405061"), lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
