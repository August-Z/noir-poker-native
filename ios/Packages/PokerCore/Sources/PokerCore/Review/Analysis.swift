// Port of src/review/analysis.js: grades each hero decision from its
// before-action snapshot only, and summarizes a hand's review.

/// `STREET_NAMES`.
public var STREET_NAMES: [String] { ReviewCopy.streetNames }

/// Numbers behind a decision analysis.
public struct ReviewMetrics: Equatable, Sendable {
    public var required: Double
    public var equityLow: Double
    public var equityHigh: Double
    public var randomEquity: Double
    public var weightedEquity: Double
    public var uncertainty: Double
    public var callCost: Int
    public var contestable: Int
    public var closing: Bool
    public var sidePots: Bool
    /// Samples per range, or the number of enumerated combinations.
    public var trials: Int
    public var method: EquityMethod
    public var randomEV: Double
    public var weightedEV: Double
}

/// `analyzeDecision` result for one hero decision.
public struct DecisionAnalysis: Equatable, Sendable {
    /// The decision's index in the hand (`s.index`).
    public var index: Int
    public var status: ReviewStatus
    public var code: ReviewCode
    public var title: String
    public var reason: String
    public var lesson: String
    public var plan: String
    public var confidence: String
    public var evidence: [String]
    public var alternative: CandidateAction
    public var alternativeLabel: String
    public var routes: Routes
    public var recommendation: String
    /// `nil` when the snapshot lacks a dealer or seat state (hand-built snapshots).
    public var simulation: CounterfactualResult?
    public var metrics: ReviewMetrics
    public var draw: DrawInfo
    public var context: DecisionContext
}

/// `rolloutTrials` default: `max(12, min(64, Math.round(trials / 15)))`.
public func defaultRolloutTrials(_ trials: Int) -> Int { max(12, min(64, Int(jsRound(Double(trials) / 15)))) }

private let EARLY_POSITIONS: Set<String> = ["UTG", "UTG+1", "MP", "LJ"]
private let WEAK_CLASSES: Set<HandClass> = [.high, .underpair, .middlePair, .board, .boardPair]
private let NO_SIMULATION_OVERRIDE: Set<ReviewCode> = [.freeFold, .expensiveCall, .weakThreeBetDefense, .weakFourBetDefense]

/// Grades one hero decision. Hidden opponent cards, the future deck and the
/// final winners cannot enter: `ReviewDecision` has no field for them.
/// `checkCancellation` runs between simulation trials.
public func analyzeDecision(_ s: ReviewDecision, trials: Int = 600, rolloutTrials: Int? = nil,
                            checkCancellation: () throws -> Void = {}) throws -> DecisionAnalysis {
    typealias C = ReviewCopy
    guard trials >= 1 else { throw ReviewError(.invalidReviewTrials) }
    let rolloutTrials = rolloutTrials ?? defaultRolloutTrials(trials)
    let price = try callPrice(s)
    let wide = sampleValue(s, price, trials: trials, weighted: false)
    let strong = sampleValue(s, price, trials: trials, weighted: true)
    let ctx = decisionContext(s)
    let pre = s.street == 0 ? preflopContext(s) : nil
    let low = min(wide.equity, strong.equity), high = max(wide.equity, strong.equity)
    let uncertainty = max(wide.margin, strong.margin)
    let draw = ctx.draw, texture = ctx.texture, handClass = ctx.handClass, hand = ctx.handLabel, tier = ctx.tier
    let early = EARLY_POSITIONS.contains(s.position)
    let deep = ctx.effective >= 2500
    let step = s.labelStep
    func label(_ a: CandidateAction) -> String { actionLabel(step, a.action, a.amount) }
    let priced = C.priced(price)
    let estimated = C.estimated(wide.equity, strong.equity)
    let strongMade = s.street > 0 && !WEAK_CLASSES.contains(handClass) && !(texture.maxSuit >= 4 && ctx.made.score[0] < 5)
    let valueTarget = strongMade || (s.street == 0 && tier >= 2)
    let callOrCheck = CandidateAction(s.legal.canCheck ? .check : .call, s.legal.callAmount)
    let checkOrFold = CandidateAction(s.legal.canCheck ? .check : .fold, 0)
    var status = ReviewStatus.sound
    let code: ReviewCode
    let title: String, lesson: String
    var reason: String, plan: String
    var confidence = C.confidenceRange
    var alternative = callOrCheck
    func raiseTo() -> CandidateAction {
        let target: Double
        if s.street == 0 {
            let limpers = s.history.filter { $0.street == 0 && $0.action == .call }.count
            target = s.currentBet <= 50 ? Double(150 + 50 * limpers) : Double(s.currentBet) * (ctx.inPosition ? 3 : 4)
        } else if s.currentBet > 0 {
            target = Double(s.currentBet) * (ctx.inPosition ? 2.5 : 3)
        } else {
            target = jsRound(Double(s.pot) * (texture.wet || ctx.opponents > 1 ? 0.65 : 0.4) / 25) * 25
        }
        return CandidateAction(.raise, min(s.legal.maxRaiseTo, max(s.legal.minRaiseTo, Int(jsRound(target)))))
    }
    let isCallOrRaise = s.action == .call || s.action == .raise

    if s.action == .fold && s.legal.canCheck {
        code = .freeFold
        status = .attention
        confidence = C.confidenceRules
        title = C.freeFoldTitle
        reason = C.freeFoldReason(s.position, ctx.pendingOthers)
        alternative = CandidateAction(.check, 0)
        lesson = C.freeFoldLesson
        plan = C.freeFoldPlan
    } else if let pre, pre.unopened && pre.late && pre.openingCandidate && tier < 2 && s.action == .raise &&
        ctx.extra <= 400 && s.amount < s.legal.maxRaiseTo {
        code = pre.limpers != 0 ? .lateIsolation : .lateOpen
        title = pre.limpers != 0 ? C.lateIsolationTitle : C.lateOpenTitle
        reason = C.lateReason(hand, s.position, limpers: pre.limpers, amount: s.amount, ace: pre.ace,
                              weakAce: pre.weakAce, kicker: pre.kicker)
        alternative = CandidateAction(.raise, min(s.legal.maxRaiseTo, max(s.legal.minRaiseTo, 125 + pre.limpers * 50)))
        lesson = C.lateLesson
        plan = C.latePlan(limpers: pre.limpers != 0)
    } else if let pre, pre.raises >= 2 && (pre.weakAce || tier == 0) && isCallOrRaise {
        code = pre.raises >= 3 ? .weakFourBetDefense : .weakThreeBetDefense
        status = pre.raises >= 3 || Double(price.cost) >= Double(s.stack) * 0.1 ? .attention : .consider
        title = pre.raises >= 3 ? C.weakFourBetTitle : C.weakThreeBetTitle
        reason = C.weakDefenseReason(hand, s.position, pre.situation, currentBet: s.currentBet, ratio: pre.ratio,
                                     priced: priced, estimated: estimated, ownOpen: pre.ownOpen, weakAce: pre.weakAce,
                                     pendingOthers: ctx.pendingOthers)
        alternative = CandidateAction(.fold, 0)
        lesson = pre.raises >= 3 ? C.weakFourBetLesson : C.weakThreeBetLesson
        plan = pre.raises >= 3 ? C.weakFourBetPlan : C.weakThreeBetPlan(suited: pre.suited)
    } else if let pre, pre.unopened && pre.late && pre.openingCandidate && tier < 2 && pre.limpers == 0 &&
        ctx.effective >= 500 && s.legal.canRaise && (s.action == .fold || s.action == .call) {
        code = .latePassiveEntry
        status = .consider
        title = C.latePassiveTitle
        reason = C.latePassiveReason(hand, s.position, ace: pre.ace, limped: s.action == .call)
        alternative = CandidateAction(.raise, min(s.legal.maxRaiseTo, max(s.legal.minRaiseTo, 125)))
        lesson = C.latePassiveLesson
        plan = C.latePassivePlan
    } else if let pre, pre.raises == 1 && pre.callersAfterOpen > 0 && pre.late && pre.weakAce && s.action == .raise {
        code = .squeezeCandidate
        status = .consider
        title = C.squeezeTitle
        reason = C.squeezeReason(hand, s.position, callers: pre.callersAfterOpen, amount: s.amount)
        alternative = CandidateAction(.fold, 0)
        lesson = C.squeezeLesson
        plan = C.squeezePlan
    } else if let pre, pre.unopened && early && pre.suited && tier == 0 && isCallOrRaise {
        code = .earlySuitedEntry
        status = .consider
        title = C.earlySuitedTitle
        reason = C.earlySuitedReason(hand, s.position, pendingOthers: ctx.pendingOthers, smallKicker: pre.kicker <= 8)
        alternative = checkOrFold
        lesson = C.earlySuitedLesson
        plan = C.earlySuitedPlan
    } else if let pre, s.street == 0 && tier == 0 && isCallOrRaise && ((pre.raises > 0 && s.currentBet >= 150) || early) {
        code = .weakEntry
        let earlyUnraised = early && pre.raises == 0
        status = earlyUnraised ? .attention : .consider
        title = earlyUnraised ? C.weakEntryEarlyTitle : C.weakEntryOpenTitle
        reason = C.weakEntryReason(hand, s.position, callAmount: s.legal.callAmount, pendingOthers: ctx.pendingOthers,
                                   early: early, suited: pre.suited)
        alternative = checkOrFold
        lesson = C.weakEntryLesson
        plan = C.weakEntryPlan
    } else if s.action == .raise && s.amount == s.legal.maxRaiseTo && deep && ctx.betRatio > 4 && s.street == 0 && tier >= 2 {
        code = .deepValueShove
        status = .consider
        title = C.deepShoveTitle
        reason = C.deepShoveReason(hand, extra: ctx.extra, pot: s.pot, betRatio: ctx.betRatio, effective: ctx.effective)
        alternative = raiseTo()
        lesson = C.deepShoveLesson
        plan = C.deepShovePlan(label(alternative))
    } else if s.action == .call && price.cost > 0 && high + uncertainty + 0.035 < price.required {
        code = .expensiveCall
        status = price.closing ? .attention : .consider
        title = price.closing ? C.expensiveClosingTitle : C.expensiveTitle
        reason = C.expensiveReason(hand, opponents: ctx.opponents, priced: priced, estimated: estimated, draw: draw)
        alternative = CandidateAction(.fold, 0)
        lesson = price.closing ? C.expensiveClosingLesson : C.expensiveLesson
        plan = price.closing ? C.expensiveClosingPlan : C.expensivePlan(pendingOthers: ctx.pendingOthers)
    } else if s.street == 0 && tier == 3 && s.action == .fold {
        code = .premiumFold
        status = .consider
        title = C.premiumFoldTitle
        reason = C.premiumFoldReason(hand, currentBet: s.currentBet, callAmount: s.legal.callAmount,
                                     effective: ctx.effective, preflopRaises: ctx.preflopRaises)
        alternative = CandidateAction(.call, s.legal.callAmount)
        lesson = C.premiumFoldLesson
        plan = ctx.preflopRaises >= 2 ? C.premiumFoldPlanReraised : C.premiumFoldPlan
    } else if s.street == 0 && tier == 3 && s.action == .call && s.legal.canRaise {
        code = .premiumFlat
        status = .consider
        title = C.premiumFlatTitle
        reason = C.premiumFlatReason(hand, s.position, callAmount: s.legal.callAmount, opponents: ctx.opponents,
                                     pendingOthers: ctx.pendingOthers, raised: ctx.preflopRaises != 0)
        alternative = raiseTo()
        lesson = C.premiumFlatLesson
        plan = C.premiumFlatPlan(label(alternative))
    } else if s.action == .raise && Double(ctx.extra) > max(500, Double(s.pot) * 2.5) && !strongMade && draw.outs == 0 &&
        (s.street != 0 || tier < 2) {
        code = .largeUnbackedBet
        status = .consider
        title = s.street == 3 ? C.largeRiverTitle : C.largeTitle
        reason = C.largeReason(hand, extra: ctx.extra, betRatio: ctx.betRatio, opponents: ctx.opponents,
                               missedDraw: ctx.missedDraw, nutFlushBlocker: ctx.nutFlushBlocker)
        alternative = callOrCheck
        lesson = C.largeLesson
        plan = C.largePlan
    } else if s.action == .check && strongMade && s.legal.canRaise &&
        !(handClass == .topPair && ctx.opponents > 1 && texture.wet) {
        code = .valueCheck
        status = .consider
        title = C.valueCheckTitle
        reason = C.valueCheckReason(hand, texture, opponents: ctx.opponents, inPosition: ctx.inPosition,
                                    overpair: handClass == .overpair)
        alternative = raiseTo()
        lesson = texture.wet ? C.valueCheckWetLesson : C.valueCheckDryLesson
        plan = C.valueCheckPlan(label(alternative))
    } else if s.action == .call && handClass == .topPair && ctx.opponents > 1 && texture.wet {
        code = .multiwayTopPair
        status = .consider
        title = C.multiwayTitle
        reason = C.multiwayReason(hand, opponents: ctx.opponents, texture, priced: priced, estimated: estimated)
        lesson = C.multiwayLesson
        plan = C.multiwayPlan
    } else if s.action == .fold && price.cost > 0 && low - uncertainty > price.required + 0.08 {
        code = .tightFold
        status = .consider
        title = C.tightFoldTitle
        reason = C.tightFoldReason(hand, priced: priced, estimated: estimated)
        alternative = CandidateAction(.call, s.legal.callAmount)
        lesson = C.tightFoldLesson
        plan = price.closing ? C.tightFoldClosingPlan : C.tightFoldPlan
    } else if s.action == .fold {
        code = .pricedFold
        title = C.pricedFoldTitle
        reason = C.pricedFoldReason(hand, s.position, callAmount: s.legal.callAmount,
                                    texture: s.street != 0 ? texture : nil, priced: price.cost != 0 ? priced : nil,
                                    draw: draw)
        alternative = CandidateAction(.fold, 0)
        lesson = C.pricedFoldLesson
        plan = C.pricedFoldPlan
    } else if s.action == .call {
        code = ctx.pastCalls >= 2 ? .multiStreetCall : .pricedCall
        title = ctx.pastCalls >= 2 ? C.multiStreetTitle : C.pricedCallTitle
        reason = C.pricedCallReason(hand, opponents: ctx.opponents, priced: priced, estimated: estimated,
                                    pastCalls: ctx.pastCalls, draw: draw)
        lesson = price.closing ? C.pricedCallClosingLesson : C.pricedCallLesson
        plan = price.closing ? C.pricedCallClosingPlan : C.pricedCallPlan(pendingOthers: ctx.pendingOthers)
    } else if s.action == .raise {
        code = valueTarget ? .valueBet : draw.outs != 0 ? .drawBet : .pressureBet
        title = valueTarget ? C.valueBetTitle : draw.outs != 0 ? C.drawBetTitle : C.pressureBetTitle
        reason = C.betReason(hand, extra: ctx.extra, betRatio: ctx.betRatio, texture: s.street != 0 ? texture : nil,
                             opponents: ctx.opponents, draw: draw, valueTarget: valueTarget)
        alternative = CandidateAction(.raise, s.amount)
        lesson = valueTarget ? C.valueBetLesson : C.pressureBetLesson
        plan = s.legal.isShortAllin ? C.shortAllInPlan : C.betPlan
    } else {
        code = handClass == .board ? .boardCheck : draw.outs != 0 ? .drawCheck : .potControl
        title = handClass == .board ? C.boardCheckTitle : draw.outs != 0 ? C.drawCheckTitle : C.potControlTitle
        reason = C.checkReason(hand, texture, draw: draw, pendingOthers: ctx.pendingOthers)
        alternative = CandidateAction(.check, 0)
        lesson = C.checkLesson
        plan = C.checkPlan
    }
    if alternative.action == .raise && !s.legal.canRaise { alternative = callOrCheck }
    if alternative.action == .call && s.legal.canCheck { alternative = CandidateAction(.check, 0) }

    var evidence = [
        C.evidencePosition(s.position, opponents: ctx.opponents, street: s.street, inPosition: ctx.inPosition),
        C.evidenceHand(hand),
        s.street != 0
            ? C.evidenceBoard(texture)
            : C.evidencePreflop(raises: ctx.preflopRaises, pendingOthers: ctx.pendingOthers),
        C.evidenceStack(effective: ctx.effective, spr: ctx.spr),
    ]
    if draw.outs != 0 { evidence.append(C.evidenceDraw(draw)) }
    if price.cost != 0 { evidence.append(priced) }
    if let pre { evidence.append(C.evidenceSituation(pre)) }

    var routes = comparisonRoutes(s, ctx, code: code, status: status, alternative: alternative, pre: pre)
    var simulation: CounterfactualResult? = nil
    if s.dealer != nil && s.players.allSatisfy({ $0.state != nil }) {
        let result = try compareCandidateActions(s, [alternative, routes.secondary?.candidate], trials: rolloutTrials,
                                                 checkCancellation: checkCancellation)
        simulation = result
        if !result.stable && status != .attention { confidence = C.confidenceSensitive }
        if result.stable && !NO_SIMULATION_OVERRIDE.contains(code) &&
            (result.best.action != alternative.action ||
                (result.best.action == .raise && result.best.amount != alternative.amount)) {
            let previous = alternative
            alternative = result.best
            status = .consider
            confidence = C.confidenceSimulated
            reason = ReviewFormat.sentences(reason, C.simulationReason(label(alternative)))
            routes = Routes(
                primary: RouteOption(action: alternative.action, amount: alternative.amount, label: label(alternative),
                                     summary: C.simulationSummary(label(alternative)),
                                     condition: C.simulationCondition, tradeoff: C.simulationTradeoff),
                secondary: RouteOption(action: previous.action, amount: previous.amount, label: label(previous),
                                       summary: nil, condition: C.simulationPreviousCondition,
                                       tradeoff: C.simulationPreviousTradeoff))
            plan = ReviewFormat.sentences(plan, C.simulationPlan)
        }
    }
    return DecisionAnalysis(
        index: s.index, status: status, code: code, title: title, reason: reason, lesson: lesson, plan: plan,
        confidence: confidence, evidence: evidence, alternative: alternative, alternativeLabel: label(alternative),
        routes: routes, recommendation: routes.primary.summary ?? routes.primary.label, simulation: simulation,
        metrics: ReviewMetrics(
            required: price.required, equityLow: low, equityHigh: high, randomEquity: wide.equity,
            weightedEquity: strong.equity, uncertainty: uncertainty, callCost: price.cost,
            contestable: price.contestable, closing: price.closing, sidePots: price.pots.count > 1,
            trials: wide.samples ?? trials, method: wide.method ?? .sampling, randomEV: wide.ev,
            weightedEV: strong.ev),
        draw: draw, context: ctx)
}

/// `summarizeReview(input, steps)` without the step list.
public struct ReviewSummary: Equatable, Sendable {
    public var steps: [DecisionAnalysis]
    /// The `index` of the step to revisit first (0 without decisions).
    public var priorityIndex: Int
    public var attention: Int
    public var consider: Int
    /// Distinct titles of the steps that need attention, then those worth discussing.
    public var themes: [String]
    public var title: String
    public var summary: String
}

/// Summarizes analyzed steps. Only the decision snapshots are read; the outcome
/// never grades a decision.
public func summarizeReview(decisions: [ReviewDecision], steps: [DecisionAnalysis]) -> ReviewSummary {
    typealias C = ReviewCopy
    let attention = steps.filter { $0.status == .attention }
    let consider = steps.filter { $0.status == .consider }
    // First step with the highest status (the reference's stable sort).
    var priority: DecisionAnalysis? = nil
    for step in steps where priority == nil || step.status.rank > priority!.status.rank { priority = step }
    let extra = decisions.reduce(0) { sum, s in
        sum + (s.action == .raise ? s.amount - s.bet : s.action == .call ? s.legal.callAmount : 0)
    }
    var themes: [String] = []
    for step in attention + consider where !themes.contains(step.title) { themes.append(step.title) }
    let summary: String
    if let priority {
        let street = decisions.indices.contains(priority.index) ? decisions[priority.index].street : 0
        summary = C.summary(decisions: decisions.count, extra: extra, step: priority.index + 1,
                            street: C.streetNames[street], title: priority.title, otherThemes: themes.count - 1)
    } else {
        summary = C.noDecisions
    }
    let title: String
    if let priority, !attention.isEmpty { title = C.checkFirst(priority.title) }
    else if let priority, !consider.isEmpty { title = C.worthComparing(priority.title) }
    else { title = C.noMistakes }
    return ReviewSummary(steps: steps, priorityIndex: priority?.index ?? 0, attention: attention.count,
                         consider: consider.count, themes: themes, title: title, summary: summary)
}

public func summarizeReview(_ input: ReviewInput, _ steps: [DecisionAnalysis]) -> ReviewSummary {
    summarizeReview(decisions: input.decisions, steps: steps)
}

/// Analyzes every decision of a settled hand, then summarizes. `checkCancellation`
/// runs before each decision and between simulation trials.
public func analyzeReview(_ input: ReviewInput, trials: Int = 600, rolloutTrials: Int? = nil,
                          checkCancellation: () throws -> Void = {}) throws -> ReviewSummary {
    var steps: [DecisionAnalysis] = []
    for s in input.decisions {
        try checkCancellation()
        steps.append(try analyzeDecision(s, trials: trials, rolloutTrials: rolloutTrials,
                                         checkCancellation: checkCancellation))
    }
    return summarizeReview(input, steps)
}
