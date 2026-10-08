import SwiftUI
import PokerCore

/// Pot Breakdown: main and side pots, awards, eligibility and refunds.
struct PotSheet: View {
    let details: PotDetailsState
    let toggle: (Int) -> Void
    let onClose: () -> Void

    var body: some View {
        NoirSheet(eyebrow: "POT BREAKDOWN", title: details.title, onClose: onClose) {
            if let note = details.note { SheetParagraph(note) }
            ForEach(details.pots, id: \.index) { pot in
                if pot.settled { settledCard(pot) } else { liveCard(pot) }
            }
            ForEach(details.refunds, id: \.playerId) { refund in
                HStack {
                    Text(refund.text).noirFont(13, relativeTo: .body).foregroundStyle(Noir.dialogBody)
                    Spacer()
                    Text(refund.amountText).noirFont(14, .semibold, relativeTo: .body, digits: true).foregroundStyle(Noir.text)
                }
                .padding(12)
                .background(Color(hex: "#25303c88"), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: "#455462"), lineWidth: 1))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(refund.a11y ?? "\(refund.text), \(refund.amountText)")
            }
            Button("Back to Table", action: onClose)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
        }
    }

    private func liveCard(_ pot: PotCardState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(pot.label).noirFont(14, .medium, relativeTo: .headline).foregroundStyle(Noir.text)
                Spacer()
                Text(pot.amountText).noirFont(22, .semibold, relativeTo: .title3, digits: true).foregroundStyle(Noir.text)
                Text(pot.unit).noirFont(12, relativeTo: .caption).foregroundStyle(Noir.subtle)
            }
            Text(pot.eligibilityLabel + pot.playerCountText)
                .noirFont(12, relativeTo: .caption)
                .foregroundStyle(pot.heroEligible ? Noir.mint : Color(hex: "#9aafbc"))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(pot.heroEligible ? Color(hex: "#23544877") : Color(hex: "#26333e"), in: RoundedRectangle(cornerRadius: 5))
            Text(pot.participantsText).noirFont(13, relativeTo: .body).foregroundStyle(Noir.dialogBody)
            disclosure(pot, summary: pot.contributionsSummary) { contributions(pot) }
        }
        .padding(18)
        .background(Color(hex: "#112b2444"), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: "#365149"), lineWidth: 1))
    }

    private func settledCard(_ pot: PotCardState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(pot.label).noirFont(14, .medium, relativeTo: .headline).foregroundStyle(Noir.text)
                Spacer()
                if let split = pot.splitTotalText {
                    Text(split).noirFont(12, relativeTo: .caption).foregroundStyle(Noir.subtle)
                }
            }
            ForEach(pot.awards, id: \.playerId) { award in
                HStack(alignment: .center, spacing: 10) {
                    CrownShape().fill(Noir.gold).frame(width: 17, height: 15).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(award.winnerText).noirFont(17, .semibold, relativeTo: .headline).foregroundStyle(Noir.text)
                        Text(award.label).noirFont(12, relativeTo: .caption).foregroundStyle(Noir.subtle)
                    }
                    Spacer()
                    Text(award.amountText).noirFont(25, .semibold, relativeTo: .title2, digits: true).foregroundStyle(Noir.mint)
                    Text(award.unit).noirFont(12, relativeTo: .caption).foregroundStyle(Noir.subtle)
                }
                .accessibilityElement(children: .combine)
            }
            disclosure(pot, summary: pot.distributionSummary) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(pot.distributionEligibility).noirFont(12, relativeTo: .caption).foregroundStyle(Noir.dialogBody)
                    Text(pot.contributionsHeading).noirFont(13, .medium, relativeTo: .subheadline).foregroundStyle(Noir.text)
                    contributions(pot)
                    if let odd = pot.oddChipNote {
                        Text(odd).noirFont(12, relativeTo: .caption).foregroundStyle(Noir.subtle)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(hex: "#102522"), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: "#33564a"), lineWidth: 1))
    }

    private func contributions(_ pot: PotCardState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(pot.contributions, id: \.playerId) { row in
                HStack {
                    Text(row.text).noirFont(13, relativeTo: .body).foregroundStyle(Noir.dialogBody)
                    Spacer()
                    Text(row.amountText).noirFont(13, relativeTo: .body, digits: true).foregroundStyle(Noir.text)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func disclosure<Body: View>(_ pot: PotCardState, summary: String, @ViewBuilder body: () -> Body) -> some View {
        let content = body()
        return DisclosureGroup(isExpanded: Binding(get: { pot.expanded }, set: { _ in toggle(pot.index) })) {
            content.padding(.top, 8)
        } label: {
            Text(summary).noirFont(13, relativeTo: .body).foregroundStyle(Color(hex: "#86ccb8"))
        }
        .tint(Color(hex: "#86ccb8"))
    }
}
