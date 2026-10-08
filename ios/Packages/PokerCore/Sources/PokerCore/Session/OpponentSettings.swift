// Opponent Styles settings logic (`opponents-controller.js`), without views.

/// The Mixed Lineup preset.
public let MIXED_LINEUP: [Int: String] = [
    1: "tan", 2: "st", 3: "zang", 4: "peter", 5: "abao", 6: "viktor", 7: "jungleman", 8: "dwan",
]

/// A selectable option: a value and its English label.
public struct OptionItem<Value: Equatable & Sendable>: Equatable, Sendable {
    public var value: Value
    public var label: String
    public init(_ value: Value, _ label: String) {
        self.value = value
        self.label = label
    }
}

/// The summary chip on the Opponent Styles button and the pending-change note (`refresh()`).
public struct OpponentsSummary: Equatable, Sendable {
    public var text: String
    public var changePending: Bool
    public var changeNote: String?
}

public func opponentsSummary(_ g: Game, _ pending: BotSettings) -> OpponentsSummary {
    let bots = g.players.dropFirst()
    let named = bots.filter { $0.botProfile != "balanced" }.count
    let p = sanitizeBotSettings(pending)
    let changed = g.emotionMode != p.emotionMode || bots.contains { $0.botProfile != p.assignments[$0.id] }
    let text = changed ? SessionCopy.opponentsSummaryPending
        : named > 0 ? SessionCopy.opponentsSummaryNamed(named)
        : SessionCopy.opponentsSummaryBalanced
    return OpponentsSummary(text: text, changePending: changed, changeNote: changed ? SessionCopy.opponentsChangeNote : nil)
}

public struct ProfileCardState: Equatable, Sendable {
    public var id: String
    public var short: String
    public var tag: String
    public var selected: Bool
}

public struct ProfileAxisState: Equatable, Sendable {
    public var label: String
    public var value: Int
}

public struct ProfileDetailState: Equatable, Sendable {
    public var profile: BotProfile
    public var badge: String
    public var axes: [ProfileAxisState]
    public var sizingText: String
}

public struct ProfileComparisonRow: Equatable, Sendable {
    public var id: String
    public var short: String
    public var axes: [Int]
    public var sizingText: String
}

public struct RosterRowState: Equatable, Sendable {
    public var id: Int
    public var name: String
    public var offTable: Bool
    /// `Seat 3 · Steady` / `Not Seated · Steady`.
    public var subtitle: String
    public var selectA11y: String
    /// The draft assignment for this seat.
    public var assignment: String
    /// Profile ids with `"{short} · {first tag segment}"`, in catalog order.
    public var options: [OptionItem<String>]
    public var currentStyle: String
    public var observed: String
    public var observedTitle: String
    public var moodReason: String?
}

public struct OpponentsDialogState: Equatable, Sendable {
    public var saveNote: String
    public var emotionMode: EmotionMode
    public var emotionOptions: [EmotionMode]
    public var selectedProfile: String
    public var profileCards: [ProfileCardState]
    public var detail: ProfileDetailState
    public var comparison: [ProfileComparisonRow]
    public var roster: [RosterRowState]
}

private func sizingPercent(_ x: Double) -> Int { Int(jsRound(x * 100)) }

private func firstTagSegment(_ tag: String) -> String {
    if let r = tag.firstRange(of: " · ") { return String(tag[..<r.lowerBound]) }
    return tag
}

/// The opponent-settings draft. `open` copies the saved settings; edits change
/// only the draft; `save` returns sanitized settings for the caller to persist
/// and apply at the next deal; `discard` drops the draft. The previewed profile
/// persists across opens and starts as Balanced.
public final class OpponentSettingsEditor {
    private var draftMode: EmotionMode?
    private var draftAssignments: [Int: String] = [:]
    public private(set) var selectedProfile = "balanced"

    public init() {}

    public var isOpen: Bool { draftMode != nil }

    public func open(_ saved: BotSettings) {
        let clean = sanitizeBotSettings(saved)
        draftMode = clean.emotionMode
        draftAssignments = clean.assignments
    }

    public func draft() -> BotSettings? {
        draftMode.map { BotSettings(emotionMode: $0, assignments: draftAssignments) }
    }

    public func previewProfile(_ id: String) {
        guard isOpen else { return }
        selectedProfile = id
    }

    public func assignSeat(_ seat: Int, _ profile: String) {
        guard isOpen, (1...8).contains(seat) else { return }
        draftAssignments[seat] = profile
        selectedProfile = profile
    }

    public func setEmotionMode(_ mode: EmotionMode) {
        guard isOpen else { return }
        draftMode = mode
    }

    public func mixLineup() {
        guard isOpen else { return }
        for (seat, profile) in MIXED_LINEUP { draftAssignments[seat] = profile }
        selectedProfile = "tan"
    }

    /// Sanitizes and closes the draft. Returns `nil` when no draft is open.
    public func save() -> BotSettings? {
        guard let d = draft() else { return nil }
        draftMode = nil
        return sanitizeBotSettings(d)
    }

    public func discard() { draftMode = nil }

    public func state(_ g: Game, requestedCount: Int) -> OpponentsDialogState? {
        guard let mode = draftMode else { return nil }
        let profile = getBotProfile(selectedProfile)
        let options = BOT_PROFILES.map { OptionItem($0.id, "\($0.short) · \(firstTagSegment($0.tag))") }
        let roster = EngineCopy.botNames.enumerated().map { i, name -> RosterRowState in
            let id = i + 1
            let player: Player? = g.players.indices.contains(id) ? g.players[id] : nil
            let stats = player?.botStats
            func ratio(_ v: Int) -> String {
                guard let stats, stats.hands > 0 else { return SessionCopy.statEmpty }
                return "\(Int(jsRound(Double(v) / Double(stats.hands) * 100)))%"
            }
            let mood = player != nil && g.emotionMode != .off ? player!.botMood.kind.label : SessionCopy.moodSteady
            let offTable = id >= requestedCount
            let reason = player?.botMood.reason ?? ""
            return RosterRowState(
                id: id,
                name: name,
                offTable: offTable,
                subtitle: (offTable ? SessionCopy.rosterOffTable : SessionCopy.rosterSeat(id)) + " · " + mood,
                selectA11y: SessionCopy.rosterSelectA11y(name),
                assignment: draftAssignments[id] ?? "balanced",
                options: options,
                currentStyle: player.map { SessionCopy.rosterCurrentStyle(getBotProfile($0.botProfile).short) } ?? SessionCopy.rosterNotSeated,
                observed: SessionCopy.rosterObserved(stats?.hands ?? 0, ratio(stats?.vpip ?? 0), ratio(stats?.pfr ?? 0)),
                observedTitle: SessionCopy.rosterObservedTitle,
                moodReason: !reason.isEmpty && g.emotionMode != .off ? reason : nil
            )
        }
        return OpponentsDialogState(
            saveNote: SessionCopy.opponentsSaveNote,
            emotionMode: mode,
            emotionOptions: EmotionMode.allCases,
            selectedProfile: selectedProfile,
            profileCards: BOT_PROFILES.map { ProfileCardState(id: $0.id, short: $0.short, tag: $0.tag, selected: $0.id == selectedProfile) },
            detail: ProfileDetailState(
                profile: profile,
                badge: SessionCopy.profileBadge,
                axes: PROFILE_AXES.enumerated().map { ProfileAxisState(label: $0.element, value: profile.axes[$0.offset]) },
                sizingText: SessionCopy.profileSizing(sizingPercent(profile.sizing[0]), sizingPercent(profile.sizing[1]))
            ),
            comparison: BOT_PROFILES.map {
                ProfileComparisonRow(id: $0.id, short: $0.short, axes: $0.axes,
                                     sizingText: SessionCopy.profileSizingCell(sizingPercent($0.sizing[0]), sizingPercent($0.sizing[1])))
            },
            roster: roster
        )
    }
}
