import SwiftUI

/// How to Play (reference `rules-dialog`), with the English copy catalog text
/// from `UiCopy`.
struct RulesSheet: View {
    let onClose: () -> Void

    var body: some View {
        NoirSheet(eyebrow: UiCopy.rulesEyebrow, title: UiCopy.rulesTitle, onClose: onClose) {
            SheetParagraph(UiCopy.rulesIntro)
            flow
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .topLeading)], alignment: .leading, spacing: 12) {
                ForEach(UiCopy.rulesActions.indices, id: \.self) { index in
                    let item = UiCopy.rulesActions[index]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).noirFont(14, .semibold, relativeTo: .headline).foregroundStyle(Noir.text)
                        Text(item.detail).noirFont(13, relativeTo: .body).foregroundStyle(Noir.dialogBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(Color(hex: "#182630"), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .combine)
                }
            }
            Group {
                SheetHeading(UiCopy.rulesPositionHeading)
                ForEach(UiCopy.rulesPositionBody, id: \.self) { paragraph in
                    SheetParagraph(paragraph)
                }
                SheetHeading(UiCopy.rulesReplayHeading)
                SheetParagraph(UiCopy.rulesReplayBody)
            }
            SheetHeading(UiCopy.rulesRanksHeading)
            Text(UiCopy.rulesRanks)
                .noirFont(13, relativeTo: .body)
                .foregroundStyle(Noir.dialogBody)
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(Noir.selectBorder).frame(height: 1)
                ForEach(UiCopy.rulesNotes, id: \.self) { note in
                    Text(note)
                        .noirFont(12, relativeTo: .footnote)
                        .foregroundStyle(Noir.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(UiCopy.backToTable, action: onClose)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
        }
    }

    private var flow: some View {
        HStack(spacing: 6) {
            ForEach(Array(UiCopy.rulesFlow.enumerated()), id: \.offset) { i, step in
                if i > 0 { Text("·").foregroundStyle(Color(hex: "#557366")) }
                Text(step).foregroundStyle(Noir.mint)
            }
        }
        .noirFont(12, relativeTo: .caption)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }
}
