import SwiftUI
import PokerCore

/// Your Practice: current stack, net change and the hand counters.
struct SessionStatsCard: View {
    let stats: SessionStatsState

    var body: some View {
        SidebarCard {
            HStack {
                Text("Your Practice").noirFont(14, .medium, relativeTo: .headline).foregroundStyle(Noir.text)
                Spacer()
                Text("This Table").noirFont(11, relativeTo: .caption).foregroundStyle(Noir.subtle)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Stack").noirFont(12, relativeTo: .caption).foregroundStyle(Noir.subtle)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(stats.stackText)
                        .noirFont(30, .semibold, relativeTo: .largeTitle, digits: true, tracking: -1)
                        .foregroundStyle(Noir.text)
                        .contentTransition(.numericText())
                    Text(stats.chipsUnit).noirFont(10, relativeTo: .caption2, tracking: 1.5).foregroundStyle(Noir.subtle)
                }
                Text(stats.changeText)
                    .noirFont(12, relativeTo: .caption)
                    .foregroundStyle(stats.negative ? Noir.negative : Noir.mint)
            }
            .accessibilityElement(children: .combine)
            Rectangle().fill(Noir.statsDivider).frame(height: 1)
            HStack(alignment: .top) {
                stat("\(stats.hands)", "Hands Played")
                Spacer()
                stat("\(stats.wins)", "Hands Won")
                Spacer()
                stat(stats.winRateText, "Win Rate")
            }
        }
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).noirFont(18, .medium, relativeTo: .headline, digits: true).foregroundStyle(Noir.text)
            Text(caption).noirFont(11, relativeTo: .caption2).foregroundStyle(Noir.subtle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(value)
    }
}

/// Table Tips: the coach toggle, stage and tip.
struct CoachCard: View {
    let coach: CoachState
    let toggle: () -> Void

    var body: some View {
        SidebarCard(coach: true) {
            HStack {
                Text("✧ Table Tips").noirFont(14, .medium, relativeTo: .headline).foregroundStyle(Noir.text)
                Spacer()
                Button(action: toggle) {
                    Text(coach.toggleLabel)
                        .noirFont(12, .medium, relativeTo: .caption)
                        .foregroundStyle(coach.toggleOn ? Noir.mint : Noir.subtle)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(coach.toggleOn ? Noir.mintDark : Noir.selectBg, in: RoundedRectangle(cornerRadius: 5))
                        .minimumHitTarget()
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Table Tips")
                .accessibilityValue(coach.toggleLabel)
                .accessibilityAddTraits(coach.toggleOn ? .isSelected : [])
                .accessibilityIdentifier("hints-toggle")
            }
            if coach.visible {
                Text(coach.stage).noirFont(12, relativeTo: .caption).foregroundStyle(Noir.mint.opacity(0.8))
                Text(coach.tip)
                    .noirFont(14, relativeTo: .body)
                    .foregroundStyle(Color(hex: "#d3e2e6"))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Rectangle().fill(Noir.coachBorder).frame(width: 18, height: 1)
                Text("Every hand, practice one good decision").noirFont(11, relativeTo: .caption2).foregroundStyle(Noir.subtle)
            }
        }
    }
}

/// Hand Activity: the complete chronological log, never truncated.
struct ActivityCard: View {
    let activity: ActivityState
    var columns = 1

    var body: some View {
        SidebarCard {
            HStack {
                Text("Activity").noirFont(14, .medium, relativeTo: .headline).foregroundStyle(Noir.text)
                Spacer()
                Text(activity.badge).noirFont(11, relativeTo: .caption, tracking: 1).foregroundStyle(Noir.subtle)
            }
            if activity.entries.isEmpty {
                Text("Once cards are dealt, every action is logged here.")
                    .noirFont(13, relativeTo: .body)
                    .foregroundStyle(Noir.subtle)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .topLeading), count: max(columns, 1)),
                          alignment: .leading, spacing: 10) {
                    ForEach(activity.entries, id: \.number) { entry in
                        row(entry)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("This hand's activity, in chronological order")
            }
        }
    }

    private func row(_ entry: ActivityEntryState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(entry.number).")
                .noirFont(11, relativeTo: .caption2, digits: true)
                .foregroundStyle(color(entry).opacity(0.65))
                .frame(minWidth: 22, alignment: .trailing)
            segmentsText(entry)
                .noirFont(14, relativeTo: .body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.number). \(entry.text)")
    }

    private func segmentsText(_ entry: ActivityEntryState) -> Text {
        let base = color(entry)
        return entry.segments.reduce(Text("")) { text, segment in
            text + Text(segment.text).foregroundColor(segment.isPersona ? base.opacity(0.75) : base)
        }
    }

    private func color(_ entry: ActivityEntryState) -> Color {
        if entry.isHero { return Noir.logHero }
        switch entry.type {
        case .result: return Noir.logResult
        case .street: return Noir.logStreet
        default: return Noir.logDefault
        }
    }
}
