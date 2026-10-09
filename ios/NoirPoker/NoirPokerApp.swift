import SwiftUI
import Observation
import PokerCore

@main
struct NoirPokerApp: App {
    @State private var model = TableModel()
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    @State private var lifecycleProbe = LifecycleProbeRecorder()
    #endif

    var body: some Scene {
        WindowGroup {
            TableRootView(model: model)
                .preferredColorScheme(.dark)
                #if DEBUG
                .overlay(alignment: .bottomLeading) {
                    if model.showsTestProbe { LifecycleProbeView(model: model, recorder: lifecycleProbe) }
                }
                #endif
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                #if DEBUG
                if model.showsTestProbe { lifecycleProbe.willEnterBackground(model) }
                #endif
                model.didEnterBackground()
                #if DEBUG
                if model.showsTestProbe { lifecycleProbe.didEnterBackground(model) }
                #endif
            case .active:
                #if DEBUG
                if model.showsTestProbe { lifecycleProbe.willEnterForeground(model) }
                #endif
                model.willEnterForeground()
                #if DEBUG
                if model.showsTestProbe { lifecycleProbe.didEnterForeground(model) }
                #endif
            case .inactive:
                // Not a pause. `.inactive` covers moments when the table stays
                // on screen: Control Center, Notification Center, a system
                // alert, the app switcher before another app is chosen. The
                // reference pauses only when the page is hidden, so the bots
                // keep their timers here. Every real departure also reaches
                // `.background`, which pauses them (see LifecycleTests).
                break
            @unknown default:
                break
            }
        }
    }
}

#if DEBUG
/// UI-test diagnostics for app lifecycle transitions, shown only on debug
/// UI-test launches (`-noir-ui-testing`). The recorder captures the table when
/// the scene leaves and when it returns, because a UI test can read the app
/// only once it is active again, when a resumed bot may already have acted.
///
/// It reads the session's test hooks (the thinking bot's seat and delay, and
/// the count of bot execution records), never hidden cards or decisions.
@MainActor
@Observable
final class LifecycleProbeRecorder {
    private(set) var backgrounds = 0
    private(set) var foregrounds = 0
    /// The thinking bot as `seat:delayMs` when the scene left, or `-`.
    private(set) var planAtBackground = "-"
    /// The thinking bot right after the session resumed, or `-`.
    private(set) var planAtForeground = "-"
    private(set) var recordsAtBackground = 0
    /// Bot actions recorded between leaving and returning.
    private(set) var botActionsWhileAway = 0
    /// Whether the public table was identical when the scene returned.
    private(set) var tableUnchangedWhileAway = true
    private(set) var reviewAtBackground = "-"
    private(set) var reviewWhileAway = "-"
    private(set) var reviewAtForeground = "-"
    @ObservationIgnored private var tableAtBackground = ""
    @ObservationIgnored private var away = false

    func willEnterBackground(_ model: TableModel) {
        let hooks = model.session.testHooks
        planAtBackground = Self.plan(hooks.thinking())
        recordsAtBackground = hooks.timingRecords().count
        tableAtBackground = model.session.publicSnapshot().probeText
        reviewAtBackground = Self.review(model.session.state.review)
    }

    func didEnterBackground(_ model: TableModel) {
        away = true
        backgrounds += 1
        reviewWhileAway = Self.review(model.session.state.review)
    }

    func willEnterForeground(_ model: TableModel) {
        guard away else { return }
        botActionsWhileAway = model.session.testHooks.timingRecords().count - recordsAtBackground
        tableUnchangedWhileAway = model.session.publicSnapshot().probeText == tableAtBackground
        reviewWhileAway = Self.review(model.session.state.review)
    }

    func didEnterForeground(_ model: TableModel) {
        guard away else { return }
        away = false
        foregrounds += 1
        planAtForeground = Self.plan(model.session.testHooks.thinking())
        reviewAtForeground = Self.review(model.session.state.review)
    }

    /// The public `qa-state` fields followed by the lifecycle fields, in the
    /// same `key=value;` format. Reads `state` so SwiftUI refreshes it.
    func probeText(_ model: TableModel) -> String {
        _ = model.state.version
        let hooks = model.session.testHooks
        let records = hooks.timingRecords()
        func describe(_ record: BotDecisionRecord) -> String {
            "\(record.id):\(record.trace.thinking?.durationMs ?? -1)"
        }
        // `seat:delayMs:sequence` for each bot action of this hand, in order.
        let recordList = records.map { describe($0) + ":" + String($0.sequence) }.joined(separator: ",")
        let firstAfter = backgrounds > 0 && records.count > recordsAtBackground ? describe(records[recordsAtBackground]) : "-"
        return [
            model.probeText,
            "backgrounded=\(model.state.backgrounded ? 1 : 0)",
            "backgrounds=\(backgrounds)",
            "foregrounds=\(foregrounds)",
            "think=\(Self.plan(hooks.thinking()))",
            "records=\(records.count)",
            "recordList=\(recordList)",
            "planBg=\(planAtBackground)",
            "planFg=\(planAtForeground)",
            "recordsBg=\(recordsAtBackground)",
            "firstAfterBg=\(firstAfter)",
            "actsAway=\(botActionsWhileAway)",
            "tableKept=\(tableUnchangedWhileAway ? 1 : 0)",
            "review=\(Self.review(model.state.review))",
            "reviewBg=\(reviewAtBackground)",
            "reviewAway=\(reviewWhileAway)",
            "reviewFg=\(reviewAtForeground)",
        ].joined(separator: ";")
    }

    private static func plan(_ info: BotWaitInfo?) -> String {
        info.map { "\($0.actor):\($0.delayMs)" } ?? "-"
    }

    private static func review(_ review: HandReviewState) -> String {
        "\(review.status.rawValue):\(review.jobId)"
    }
}

/// The `qa-lifecycle` probe: invisible, for UI tests only.
private struct LifecycleProbeView: View {
    let model: TableModel
    let recorder: LifecycleProbeRecorder

    var body: some View {
        let text = recorder.probeText(model)
        Text(text)
            .font(.system(size: 1))
            .frame(width: 1, height: 1)
            .clipped()
            .opacity(0.02)
            .allowsHitTesting(false)
            .accessibilityLabel(text)
            .accessibilityIdentifier("qa-lifecycle")
    }
}
#endif
