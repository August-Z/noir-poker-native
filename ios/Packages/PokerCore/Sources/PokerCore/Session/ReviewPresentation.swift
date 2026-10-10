// The Hand Review dialog content: a port of the rendering half of
// `src/ui/review-controller.js` (hero panel) and `src/ui/opponent-review.js`
// (opponent panel). It turns `HandReviewState` into final English strings and
// plain values so the SwiftUI sheet only lays them out. Hero grading never
// reads the opponent records; they appear only in the opponent panel, which
// exists only after settlement because the review input does.

/// Static and templated Hand Review copy. The strings match the Kotlin
/// `ReviewDialogCopy` (review copy catalog §8, §9, Appendix B) one for one;
/// `fixtures/review-dialog.json` locks both tables.
public enum ReviewDialogCopy {
    public static let eyebrow = "HAND REVIEW"
    public static let closeA11y = "Close review"
    public static let titleDefault = "Hand Review"
    public static let tabsA11y = "Review perspective"
    public static let tabHero = "Your Decisions"
    public static let tabOpponents = "Opponent Decisions"
    public static let tabOpponentsSubtitle = "Why they played it that way"
    public static let timelineA11y = "Decision timeline for this hand"
    public static let routesA11y = "Conditions and trade-offs for both lines"
    public static let simulationA11y = "Candidate action simulation comparison"
    public static let scope = "Reviewed with the information available at each decision · Ranges are assumptions, and winning or losing doesn't decide whether a choice was good."
    public static let methodSummary = "How the analysis works"
    public static let methodInfo = "Only the hole cards, community cards, public actions, and stacks at the moment of each decision are used. Opponents' hidden cards, later cards, and the final winners play no part in grading decisions."
    public static let methodPrice = "Required equity = effective call cost ÷ the pot you can win after calling. The Main Pot and Side Pots are estimated separately by eligibility, and uncalled refunds don't count as winnings."
    public static let methodRanges = "The \"two-range estimate\" comes from sampling a random range and a stronger range for whoever bet or raised. These range assumptions are not the opponents' actual hands, and they are not an error interval. Later betting, fold rates, and potential winnings are not fully modeled. The analysis accounts for hand type, kicker, draws, position, board texture, number of players, and betting pressure. Direct completion cards are not guaranteed winning outs; only the chance of hitting on the next card is shown, because seeing both the turn and the river from the flop usually costs more than one payment. Heads-up on the river, every legal hole-card combo is enumerated; everything else uses fixed-seed sampling. Enumeration removes sampling error but not the error in the range assumptions. Candidate bet sizes are practice lines, not a GTO solution."
    public static let methodRefsPrefix = "References:"
    /// Optional external references; open them in the system browser.
    public static let methodRefs: [ReviewReference] = [
        ReviewReference(label: "Pot Odds", url: "https://www.pokerstars.com/poker/learn/lesson/pot-odds/"),
        ReviewReference(label: "Starting Hands and Position",
                        url: "https://www.pokerstars.com/poker/learn/lesson/poker-starting-hands/"),
    ]
    public static let methodSimulation = "The candidate action simulation samples the unknown cards from the position at the time and plays the hand out with the rules engine, including further bets, folds, side pots, and refunds. Your later decisions use a balanced simulated strategy, opponents keep their public styles, and each simulated decision uses 8 equity samples. It compares chip results under these strategies, not the value of an optimal follow-up strategy, and sampling error doesn't cover range or model errors."
    public static let methodOpponents = "Opponent explanations read the actual decision records after settlement and show the price, range, mood, and random branches each bot used at the time. These private records never feed into grading your decisions."
    /// The method paragraphs before the references, in order.
    public static var methodParagraphs: [String] { [methodInfo, methodPrice, methodRanges] }
    /// The method paragraphs after the references, in order.
    public static var methodClosingParagraphs: [String] { [methodSimulation, methodOpponents] }
    public static let backToTable = "Back to Table"
    public static let previous = "Previous"
    public static let next = "Next"

    // Header
    public static func title(_ hand: Int) -> String { "Hand #\(hand) · Review" }
    public static func resultChange(_ profit: Int) -> String {
        profit < 0 ? "\(formatChips(profit)) chips" : profit > 0 ? "+\(formatChips(profit)) chips" : "0 chips"
    }
    public static let contextFolded = "You folded this hand"
    public static let contextPartialWin = "Won part of the pot, net loss for the hand"
    public static let contextWon = "You won the pot"
    public static let contextLost = "You didn't win the pot"

    // Summary box
    public static let stateError = "Analysis didn't finish. You can try again."
    public static func stateProgress(_ done: Int, _ total: Int) -> String { "Analyzing decision \(done) of \(total)…" }
    public static let statePreparing = "Preparing this hand's decision snapshots…"
    public static let summaryTitleDefault = "Back to the decisions as they were"
    public static let priorityButton = "Go to the priority decision"
    public static let fromFirstButton = "Review from step 1"
    public static let retryButton = "Analyze Again"

    // Status chips
    public static let statusAttention = "Needs Work"
    public static let statusConsider = "Worth Discussing"
    public static let statusSound = "Well Reasoned"
    public static func status(_ status: ReviewStatus) -> String {
        switch status {
        case .attention: return statusAttention
        case .consider: return statusConsider
        case .sound: return statusSound
        }
    }
    public static let statusPending = "Pending"
    public static let statusAnalyzing = "Analyzing"

    // Hero timeline and detail
    public static let timelineTitle = "Your Decisions"
    public static func actionCount(_ n: Int) -> String { n == 1 ? "1 action" : "\(n) actions" }
    public static let empty = "You made no decisions this hand, so there's nothing to evaluate. Blinds are forced bets and never count as mistakes."
    public static func detailTitle(_ step: Int, _ street: String) -> String { "Step \(step) · \(street)" }
    public static let holeLabel = "Your hole cards"
    public static let boardLabel = "Community cards at the time"
    public static let noBoard = "No community cards yet"
    public static let positionLabel = "Position"
    public static let potLabel = "Pot at the time"
    public static let stackLabel = "Stack remaining"
    public static let yourChoice = "Your choice"
    public static let suggestedLine = "Suggested Line"
    public static let suggestionPending = "Comparing available actions…"
    public static let routePrimary = "When the main line holds"
    public static let routeSecondary = "Conditional alternative"
    public static let simulationHeading = "Candidate Action Simulation"
    public static let simulationStable = "In this sample, one line clearly led under both ranges; it still depends on assumptions about later play."
    public static let simulationUnstable = "Ranges or sampling error could change the order; no single best action has been shown."
    public static func simulationCaption(_ trials: Int) -> String {
        "\(trials) hands simulated per action and range · Net chip change from this decision on"
    }
    public static let simulationColumns = ["Action", "Random Range", "Action-Weighted"]
    public static func simulationMargin(_ margin: Double) -> String { "≈ ±\(formatChips(margin))" }
    public static let simulationDetailsSummary = "How the simulation handles later action"
    public static let simulationDetailsBody = "Results include immediate folds, calls, later raises, and showdowns; the real hidden hole cards, the actual card order that followed, and the final winners are never used. The two range results are not a range of optimal returns."
    public static let simulationUnavailable = "This older snapshot lacks the full action state, so later action can't be simulated; the range and price analysis from public information still applies."
    public static let simulationRunning = "Simulating each legal action and the rest of the hand…"
    public static let decisionTitleDefault = "Analysis based on what you knew then"
    public static let reasonDefault = "Uses your hole cards, the community cards, public actions, and stacks at the time, never opponents' hidden cards or cards dealt later."
    public static let evidenceHeading = "Key factors at the time"
    public static let confidenceDefault = "Waiting for analysis"
    public static let lessonLabel = "Focus for next practice"
    public static let lessonDefault = "Judge the decision separately from the result; a specific practice focus appears when the review is done."
    public static let planHeading = "Plan for later streets"
    public static let planDefault = "The follow-up plan appears when analysis finishes."
    public static let metricPrice = "Equity needed to call"
    public static let metricEquity = "Two-range estimate"
    public static let metricContestable = "Winnable after calling"
    public static let metricPending = "…"
    public static let metricNoCall = "No call needed"
    public static let metricNone = "—"
    public static func equityAbout(_ p: String) -> String { "≈\(p)" }
    public static func modelEnumeration(_ trials: Int) -> String {
        "River heads-up: all \(trials) legal opponent hole-card combos were enumerated; there's no sampling error across combos, but the real range is still unknown."
    }
    public static func modelSampling(_ trials: Int, _ points: Int) -> String {
        "\(trials) samples per range, with a conservative sampling-error band of about ±\(points) percentage points; this isn't the error in the opponent's real range."
    }
    public static func modelEquity(_ random: String, _ weighted: String) -> String {
        "Random / action-weighted equity: \(random) / \(weighted). The gap between the two ranges is not a confidence interval."
    }
    public static let priceNoteSidePots = "Estimated separately for each pot you're eligible for; side pots beyond your all-in amount are excluded."
    public static let priceNoteClosing = "The call price uses the amount you can currently win, after removing uncalled refunds."
    public static let priceNoteDefault = "The price is only a guide; later bets, other players' actions, and potential winnings aren't included."
    public static let publicActionsSummary = "Earlier public actions"
    public static let publicActionsEmpty = "No other actions yet this round."
    public static func stepPosition(_ step: Int, _ total: Int) -> String { "\(step) / \(total)" }

    // Accessibility text of timeline items and simulation cells (shared with Android).
    public static func heroStepA11y(_ step: Int, _ meta: String, _ action: String, _ chip: String) -> String {
        "Step \(step), \(meta), \(action), \(chip)"
    }
    public static func opponentStepA11y(_ sequence: Int, _ meta: String, _ action: String, _ profile: String) -> String {
        "\(opponentPublicAction(sequence)), \(meta), \(action), \(profile)"
    }
    public static func simulationCellA11y(_ action: String, _ column: String, _ value: String, _ margin: String) -> String {
        "\(action), \(column): \(value) chips, \(margin)"
    }

    // Opponent panel
    public static let opponentIntro = "Step through how each bot decided at the time. Hole cards enter this panel only after the hand ends; your own decision ratings still use only the public information at the time."
    public static let opponentFilterLabel = "Show opponent"
    public static let opponentFilterAll = "All Opponents"
    public static let opponentTimelineA11y = "Opponent decision timeline"
    public static let opponentTimelineTitle = "What Opponents Actually Did"
    public static let opponentEmpty = "No bot decision records for this hand. Reasons are never invented for actions that can't be reconstructed; the next hand will record the actual decisions."
    public static let opponentRecordChip = "Actual decision record"
    public static func opponentHoleLabel(_ name: String) -> String { "\(name)'s hole cards at the time" }
    public static func opponentChoice(_ made: String) -> String { "It chose · \(made)" }
    public static let opponentEvidenceHeading = "What it actually used"
    public static let opponentBranchesSummary = "Show the actual random branches (0–1 rolls)"
    public static func opponentBranch(_ value: Double, _ threshold: Double, _ hit: Bool) -> String {
        "\(jsToFixed(value, 3)) / threshold \(jsToFixed(threshold * 100, 1))% · \(hit ? "Hit" : "Miss")"
    }
    public static let opponentBranchesEmpty = "No extra random branches on this step."
    public static func opponentPublicAction(_ sequence: Int) -> String { "Public action #\(sequence)" }
}

public struct ReviewReference: Equatable, Sendable {
    public var label: String
    public var url: String
}

/// Status chip styles. `pending` covers both "Pending" and "Analyzing".
public enum ReviewChipKind: String, Equatable, Sendable {
    case attention, consider, sound, pending

    init(_ status: ReviewStatus?) {
        switch status {
        case .attention?: self = .attention
        case .consider?: self = .consider
        case .sound?: self = .sound
        case nil: self = .pending
        }
    }
}

public struct ReviewTimelineItem: Equatable, Sendable {
    /// Position in the visible list (the value to select).
    public var index: Int
    /// The number badge: the step (hero) or the public action sequence (opponents).
    public var number: Int
    public var meta: String
    public var label: String
    public var chip: String
    public var chipKind: ReviewChipKind
    public var selected: Bool
    public var a11y: String
}

public struct ReviewRouteCard: Equatable, Sendable {
    public var kicker: String
    public var label: String
    public var condition: String
    public var tradeoff: String
}

public struct ReviewSimulationCell: Equatable, Sendable {
    public var value: String
    public var margin: String
    /// Spoken text of the cell: action, column, value and margin.
    public var a11y: String
}

public struct ReviewSimulationRow: Equatable, Sendable {
    public var label: String
    public var cells: [ReviewSimulationCell]
}

public struct ReviewSimulationTable: Equatable, Sendable {
    public var heading: String
    public var stability: String
    public var stable: Bool
    public var caption: String
    public var trials: Int
    public var columns: [String]
    public var rows: [ReviewSimulationRow]
    public var detailsSummary: String
    public var note: String
    public var detailsBody: String
}

public struct ReviewMetric: Equatable, Sendable {
    public var label: String
    public var value: String
}

public struct ReviewPublicAction: Equatable, Sendable {
    public var name: String
    public var label: String
}

public struct HeroReviewDetail: Equatable, Sendable {
    public var title: String
    public var status: String
    public var statusKind: ReviewChipKind
    public var hole: [Card]
    public var board: [Card]
    public var position: String
    public var pot: String
    public var stack: String
    public var yourChoice: String
    public var suggestion: String
    public var routes: [ReviewRouteCard]
    /// The simulation table, when the analysis produced one.
    public var simulation: ReviewSimulationTable?
    /// Shown in place of the table: still running, or unavailable for this snapshot.
    public var simulationNote: String?
    public var decisionTitle: String
    public var reason: String
    public var evidence: [String]
    public var confidence: String
    public var lesson: String
    public var plan: String
    public var metrics: [ReviewMetric]
    public var modelNote: String?
    public var priceNote: String
    public var publicActions: [ReviewPublicAction]
    public var publicActionsEmpty: String?
    public var canGoPrevious: Bool
    public var canGoNext: Bool
    public var stepPosition: String
}

public struct HeroReviewPanel: Equatable, Sendable {
    public var count: String
    public var items: [ReviewTimelineItem]
    /// Non-nil when the hero made no voluntary decision.
    public var empty: String?
    public var detail: HeroReviewDetail?
}

public struct ReviewFilterOption: Equatable, Sendable {
    /// `nil` = all opponents.
    public var seat: Int?
    public var label: String
    public var selected: Bool
}

public struct ReviewBranch: Equatable, Sendable {
    public var label: String
    public var value: String
    public var hit: Bool
}

public struct OpponentReviewDetail: Equatable, Sendable {
    public var title: String
    public var chip: String
    public var chipKind: ReviewChipKind
    public var holeLabel: String
    public var hole: [Card]
    public var board: [Card]
    public var position: String
    public var pot: String
    public var stack: String
    public var choiceLabel: String
    public var action: String
    public var explanationTitle: String
    public var explanationDetail: String
    public var profileName: String
    public var reasons: [String]
    public var warning: String
    public var branches: [ReviewBranch]
    public var branchesEmpty: String?
    public var canGoPrevious: Bool
    public var canGoNext: Bool
    public var sequenceText: String
}

public struct OpponentReviewPanel: Equatable, Sendable {
    public var filters: [ReviewFilterOption]
    public var count: String
    public var items: [ReviewTimelineItem]
    public var empty: String?
    public var detail: OpponentReviewDetail?
}

public struct ReviewDialogContent: Equatable, Sendable {
    public var title: String
    public var resultChange: String
    public var resultContext: String
    public var summaryTitle: String
    public var statusText: String
    /// The analysis job is running (show a spinner and progress). An idle
    /// review, for example after a background pause, shows no spinner.
    public var running: Bool
    public var progressDone: Int
    public var progressTotal: Int
    public var retryVisible: Bool
    /// The priority button's label and the step it selects.
    public var priorityLabel: String?
    public var priorityIndex: Int?
    public var perspective: HandReviewPerspective
    public var hero: HeroReviewPanel
    public var opponents: OpponentReviewPanel
}

/// Builds the review dialog content from the session's review state, or nil
/// when there is no settled hand to review.
public func presentReviewDialog(_ state: HandReviewState) -> ReviewDialogContent? {
    guard let input = state.input else { return nil }
    typealias C = ReviewDialogCopy
    let outcome = input.outcome
    let summary = state.analysis as? ReviewSummary
    let steps = input.decisions
    let total = steps.count

    let context = outcome.folded ? C.contextFolded
        : outcome.wonPot ? (outcome.profit < 0 ? C.contextPartialWin : C.contextWon)
        : C.contextLost
    let statusText: String
    if state.status == .error {
        statusText = C.stateError
    } else if let summary {
        statusText = summary.summary
    } else if state.status == .running {
        statusText = C.stateProgress(state.progress, total)
    } else {
        statusText = C.statePreparing
    }

    var priorityLabel: String?
    var priorityIndex: Int?
    if let summary, total > 0 {
        priorityLabel = summary.attention > 0 || summary.consider > 0 ? C.priorityButton : C.fromFirstButton
        priorityIndex = summary.priorityIndex
    }

    let selected = state.selected
    let items: [ReviewTimelineItem] = steps.enumerated().map { i, s in
        let status = summary?.steps.indices.contains(i) == true ? summary?.steps[i].status : nil
        let chip = status.map(C.status) ?? C.statusPending
        let meta = "\(reviewStreet(s.street)) · \(s.position)"
        let label = actionLabel(LabelStep(s))
        return ReviewTimelineItem(index: i, number: i + 1, meta: meta, label: label, chip: chip,
                                  chipKind: ReviewChipKind(status), selected: i == selected,
                                  a11y: C.heroStepA11y(i + 1, meta, label, chip))
    }
    var detail: HeroReviewDetail?
    if steps.indices.contains(selected) {
        let result = summary?.steps.indices.contains(selected) == true ? summary?.steps[selected] : nil
        detail = heroDetail(steps[selected], result: result, index: selected, total: total)
    }

    return ReviewDialogContent(
        title: C.title(input.hand),
        resultChange: C.resultChange(outcome.profit),
        resultContext: context,
        summaryTitle: summary?.title ?? C.summaryTitleDefault,
        statusText: statusText,
        running: state.status == .running,
        progressDone: state.progress,
        progressTotal: total,
        retryVisible: state.status == .error,
        priorityLabel: priorityLabel,
        priorityIndex: priorityIndex,
        perspective: state.perspective,
        hero: HeroReviewPanel(count: C.actionCount(total), items: items,
                              empty: detail == nil ? C.empty : nil, detail: detail),
        opponents: opponentPanel(state, all: input.opponents)
    )
}

private func reviewStreet(_ street: Int) -> String {
    ReviewCopy.streetNames.indices.contains(street) ? ReviewCopy.streetNames[street] : ""
}

private func percentText(_ v: Double) -> String { String(Int(jsRound(v * 100))) + "%" }

private func signedChips(_ v: Double) -> String { (v > 0 ? "+" : "") + formatChips(v) }

private func heroDetail(_ d: DecisionSnapshot, result: DecisionAnalysis?, index: Int, total: Int) -> HeroReviewDetail {
    typealias C = ReviewDialogCopy
    let step = LabelStep(d)
    let routes: [ReviewRouteCard] = result.map { r in
        [r.routes.primary, r.routes.secondary].compactMap { $0 }.enumerated().map { i, route in
            ReviewRouteCard(kicker: i == 0 ? C.routePrimary : C.routeSecondary, label: route.label,
                            condition: route.condition, tradeoff: route.tradeoff)
        }
    } ?? []

    var simulation: ReviewSimulationTable?
    var simulationNote: String?
    if let sim = result?.simulation {
        simulation = ReviewSimulationTable(
            heading: C.simulationHeading,
            stability: sim.stable ? C.simulationStable : C.simulationUnstable,
            stable: sim.stable,
            caption: C.simulationCaption(sim.trials),
            trials: sim.trials,
            columns: C.simulationColumns,
            rows: sim.rows.map { row in
                let label = actionLabel(step, row.action.action, row.action.amount)
                return ReviewSimulationRow(label: label, cells: row.scenarios.enumerated().map { i, scenario in
                    let column = C.simulationColumns[i == 0 ? 1 : 2]
                    let value = signedChips(scenario.ev)
                    let margin = C.simulationMargin(scenario.margin)
                    return ReviewSimulationCell(value: value, margin: margin,
                                                a11y: C.simulationCellA11y(label, column, value, margin))
                })
            },
            detailsSummary: C.simulationDetailsSummary,
            note: sim.note,
            detailsBody: C.simulationDetailsBody)
    } else {
        simulationNote = result == nil ? C.simulationRunning : C.simulationUnavailable
    }

    let callAmount = d.legal.enabled ? d.legal.callAmount : 0
    var metrics: [ReviewMetric] = []
    metrics.append(ReviewMetric(label: C.metricPrice,
                                value: callAmount != 0 ? (result.map { percentText($0.metrics.required) } ?? C.metricPending) : C.metricNoCall))
    var equity = C.metricNone
    if let m = result?.metrics, m.contestable != 0 {
        let low = percentText(m.equityLow), high = percentText(m.equityHigh)
        equity = low == high ? C.equityAbout(low) : "\(low)–\(high)"
    }
    metrics.append(ReviewMetric(label: C.metricEquity, value: equity))
    metrics.append(ReviewMetric(label: C.metricContestable,
                                value: result.map { formatChips($0.metrics.contestable) } ?? C.metricPending))

    var modelNote: String?
    if let m = result?.metrics {
        let method = m.method == .enumeration
            ? C.modelEnumeration(m.trials)
            : C.modelSampling(m.trials, Int((m.uncertainty * 100).rounded(.up)))
        modelNote = method + " " + C.modelEquity(percentText(m.randomEquity), percentText(m.weightedEquity))
    }
    let priceNote = result?.metrics.sidePots == true ? C.priceNoteSidePots
        : result?.metrics.closing == true ? C.priceNoteClosing
        : C.priceNoteDefault

    let publicActions: [ReviewPublicAction] = d.history.enumerated()
        .filter { $0.element.street == d.street }
        .suffix(6)
        .map { i, a in
            let name = d.players.first { $0.id == a.id }?.name ?? ""
            return ReviewPublicAction(name: name, label: historyActionLabel(d.history, i))
        }

    return HeroReviewDetail(
        title: C.detailTitle(index + 1, reviewStreet(d.street)),
        status: result.map { C.status($0.status) } ?? C.statusAnalyzing,
        statusKind: ReviewChipKind(result?.status),
        hole: d.hole,
        board: d.board,
        position: d.position,
        pot: formatChips(d.pot),
        stack: formatChips(d.stack),
        yourChoice: actionLabel(step),
        suggestion: result.map { $0.recommendation.isEmpty ? C.suggestionPending : $0.recommendation } ?? C.suggestionPending,
        routes: routes,
        simulation: simulation,
        simulationNote: simulationNote,
        decisionTitle: result.map { $0.title.isEmpty ? C.decisionTitleDefault : $0.title } ?? C.decisionTitleDefault,
        reason: result.map { $0.reason.isEmpty ? C.reasonDefault : $0.reason } ?? C.reasonDefault,
        evidence: result?.evidence ?? [],
        confidence: result.map { $0.confidence.isEmpty ? C.confidenceDefault : $0.confidence } ?? C.confidenceDefault,
        lesson: result.map { $0.lesson.isEmpty ? C.lessonDefault : $0.lesson } ?? C.lessonDefault,
        plan: result.map { $0.plan.isEmpty ? C.planDefault : $0.plan } ?? C.planDefault,
        metrics: metrics,
        modelNote: modelNote,
        priceNote: priceNote,
        publicActions: publicActions,
        publicActionsEmpty: publicActions.isEmpty ? C.publicActionsEmpty : nil,
        canGoPrevious: index > 0,
        canGoNext: index < total - 1,
        stepPosition: C.stepPosition(index + 1, total))
}

private func opponentStep(_ r: BotDecisionRecord) -> LabelStep {
    guard let v = r.trace.view else { return LabelStep(street: 0, action: r.action, amount: r.amount) }
    return LabelStep(street: v.street, history: v.history, currentBet: v.currentBet, legal: v.legal,
                     stack: v.stack, action: r.action, amount: r.amount)
}

private func opponentPanel(_ state: HandReviewState, all: [BotDecisionRecord]) -> OpponentReviewPanel {
    typealias C = ReviewDialogCopy
    var seen: [Int] = []
    var names: [Int: String] = [:]
    for r in all {
        if names[r.id] == nil { seen.append(r.id) }
        names[r.id] = r.name
    }
    var filters = [ReviewFilterOption(seat: nil, label: C.opponentFilterAll, selected: state.opponentFilter == nil)]
    filters += seen.map { ReviewFilterOption(seat: $0, label: names[$0] ?? "", selected: state.opponentFilter == $0) }

    let visible = state.opponentRecords
    let selected = visible.isEmpty ? 0 : min(max(state.opponentSelected, 0), visible.count - 1)
    let items: [ReviewTimelineItem] = visible.enumerated().map { i, r in
        let meta = "\(r.name) · \(reviewStreet(r.trace.view?.street ?? 0))"
        let label = actionLabel(opponentStep(r))
        return ReviewTimelineItem(index: i, number: r.sequence, meta: meta, label: label, chip: r.trace.profileName,
                                  chipKind: .pending, selected: i == selected,
                                  a11y: C.opponentStepA11y(r.sequence, meta, label, r.trace.profileName))
    }
    var detail: OpponentReviewDetail?
    if visible.indices.contains(selected) {
        let r = visible[selected]
        let e = explainOpponent(r)
        let t = r.trace
        let v = t.view
        detail = OpponentReviewDetail(
            title: "\(r.name) · \(reviewStreet(v?.street ?? 0))",
            chip: C.opponentRecordChip,
            chipKind: t.exceptions.isEmpty ? .sound : .consider,
            holeLabel: C.opponentHoleLabel(r.name),
            hole: v?.hole ?? [],
            board: v?.board ?? [],
            position: v?.position ?? "",
            pot: formatChips(v?.pot ?? 0),
            stack: formatChips(v?.stack ?? 0),
            choiceLabel: C.opponentChoice(e.made),
            action: actionLabel(opponentStep(r)),
            explanationTitle: e.title,
            explanationDetail: e.detail,
            profileName: t.profileName,
            reasons: e.reasons,
            warning: e.warning,
            branches: t.checks.map {
                ReviewBranch(label: BOT_CHECK_NAMES[$0.code] ?? $0.code,
                             value: C.opponentBranch($0.value, $0.threshold, $0.selected), hit: $0.selected)
            },
            branchesEmpty: t.checks.isEmpty ? C.opponentBranchesEmpty : nil,
            canGoPrevious: selected > 0,
            canGoNext: selected < visible.count - 1,
            sequenceText: C.opponentPublicAction(r.sequence))
    }
    return OpponentReviewPanel(filters: filters, count: C.actionCount(visible.count), items: items,
                               empty: visible.isEmpty ? C.opponentEmpty : nil, detail: detail)
}
