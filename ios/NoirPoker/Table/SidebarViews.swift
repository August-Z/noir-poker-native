import SwiftUI
import PokerCore

/// Your Practice: current stack, net change and the hand counters.
struct SessionStatsCard: View {
    let stats: SessionStatsState
    var compact = false

    var body: some View {
        SidebarCard(compact: compact) {
            HStack {
                Text("Your Practice").noirFont(compact ? 12 : 14, .medium, relativeTo: .headline).foregroundStyle(Noir.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 6)
                Text("This Table").noirFont(11, relativeTo: .caption).foregroundStyle(Noir.subtle)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Stack").noirFont(12, relativeTo: .caption).foregroundStyle(Noir.subtle)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(stats.stackText)
                        .noirFont(compact ? 26 : 32, .semibold, relativeTo: .largeTitle, digits: true, tracking: -1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Noir.text)
                        .contentTransition(.numericText())
                    Text(stats.chipsUnit).noirFont(10, relativeTo: .caption2, tracking: 1.5).foregroundStyle(Noir.subtle)
                }
                Text(stats.changeText)
                    .noirFont(12, relativeTo: .caption)
                    .foregroundStyle(stats.negative ? Noir.negative : Noir.mint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Rectangle().fill(Noir.statsDivider).frame(height: 1)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) {
                    stat("\(stats.hands)", "Hands Played")
                    Spacer(minLength: 6)
                    stat("\(stats.wins)", "Hands Won")
                    Spacer(minLength: 6)
                    stat(stats.winRateText, "Win Rate")
                }
                VStack(alignment: .leading, spacing: 10) {
                    stat("\(stats.hands)", "Hands Played")
                    stat("\(stats.wins)", "Hands Won")
                    stat(stats.winRateText, "Win Rate")
                }
            }
        }
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).noirFont(18, .medium, relativeTo: .headline, digits: true).foregroundStyle(Noir.text)
            Text(caption).noirFont(compact ? 10 : 12, relativeTo: .caption2).foregroundStyle(Noir.subtle)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(value)
    }
}

/// Table Tips: the coach toggle, stage and tip.
struct CoachCard: View {
    let coach: CoachState
    var compact = false
    let toggle: () -> Void

    var body: some View {
        SidebarCard(coach: true, compact: compact) {
            HStack {
                Text("✧ Table Tips").noirFont(compact ? 12 : 14, .medium, relativeTo: .headline).foregroundStyle(Noir.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 6)
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
                    .noirFont(compact ? 12 : 14, relativeTo: .body)
                    .foregroundStyle(Color(hex: "#d3e2e6"))
                    .lineSpacing(compact ? 5 : 6)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if !compact {
                HStack(spacing: 8) {
                    Rectangle().fill(Noir.coachBorder).frame(width: 18, height: 1)
                    Text("Every hand, practice one good decision").noirFont(11, relativeTo: .caption2).foregroundStyle(Noir.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Hand Activity: the complete chronological log, never truncated and never
/// in a fixed-height scroller. Two columns read top to bottom, left column
/// first, so the order stays chronological for sight and for VoiceOver.
struct ActivityCard: View {
    let activity: ActivityState
    var columns = 1
    var compact = false

    var body: some View {
        SidebarCard(compact: compact) {
            HStack {
                Text("Activity").noirFont(compact ? 12 : 14, .medium, relativeTo: .headline).foregroundStyle(Noir.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(activity.badge).noirFont(11, relativeTo: .caption, tracking: 1).foregroundStyle(Noir.subtle)
            }
            if activity.entries.isEmpty {
                Text("Once cards are dealt, every action is logged here.")
                    .noirFont(compact ? 12 : 13, relativeTo: .body)
                    .foregroundStyle(Noir.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Group {
                    if columns > 1 && activity.entries.count > 1 {
                        let split = (activity.entries.count + 1) / 2
                        HStack(alignment: .top, spacing: 16) {
                            column(Array(activity.entries[..<split]))
                            column(Array(activity.entries[split...]))
                        }
                    } else {
                        column(activity.entries)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("This hand's activity, in chronological order")
                .accessibilityIdentifier("activity-list")
            }
        }
    }

    private func column(_ entries: [ActivityEntryState]) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            ForEach(entries, id: \.number) { entry in
                row(entry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ entry: ActivityEntryState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(entry.number).")
                .noirFont(11, relativeTo: .caption2, digits: true)
                .foregroundStyle(color(entry).opacity(0.65))
                .frame(minWidth: 22, alignment: .trailing)
            segmentsText(entry)
                .noirFont(compact ? 12 : 14, relativeTo: .body)
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
