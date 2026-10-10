import SwiftUI

/// Shared sheet frame: eyebrow, title, close button, scrolling body and an
/// optional bottom action.
struct NoirSheet<Content: View>: View {
    let eyebrow: String
    let title: String
    var eyebrowColor: Color = Noir.eyebrow
    var closeLabel = UiCopy.closeA11y
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(eyebrow).eyebrowStyle(eyebrowColor)
                    Text(title)
                        .noirFont(21, .medium, relativeTo: .title2)
                        .foregroundStyle(Noir.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 12)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Noir.muted)
                        .frame(width: 32, height: 32)
                        .overlay(Circle().strokeBorder(Noir.line, lineWidth: 1))
                        .minimumHitTarget()
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(closeLabel)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Noir.dialogBg.ignoresSafeArea())
        .presentationBackground(Noir.dialogBg)
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

/// Dialog body paragraph.
struct SheetParagraph: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .noirFont(14, relativeTo: .body)
            .foregroundStyle(Noir.dialogBody)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Dialog section heading.
struct SheetHeading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .noirFont(14, .medium, relativeTo: .headline)
            .foregroundStyle(Noir.text)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Large sheets (Hand Review, Opponent Styles) use the page size on iPad,
    /// so their tables and timelines get room instead of the narrow form sheet.
    /// Phones present them full height either way.
    @ViewBuilder
    func widePresentation() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.page)
        } else {
            self
        }
    }
}
