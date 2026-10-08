// Port of src/review/counterfactual.js: candidate actions replayed through the
// native engine from the public snapshot, with sampled unknown cards.

public func candidateActions(_ s: ReviewDecision, _ alternatives: [CandidateAction?] = []) -> [CandidateAction] {
    var candidates = [CandidateAction(.fold, 0), CandidateAction(s.legal.canCheck ? .check : .call, s.legal.callAmount)]
    if s.legal.canRaise {
        let targets: [Double] = s.street == 0 && s.currentBet <= 50
            ? [100, 150]
            : s.currentBet > 0
                ? [Double(s.currentBet) * 2.5, Double(s.currentBet) * 3.5]
                : [Double(s.pot) * 0.33, Double(s.pot) * 0.65]
        for value in targets { candidates.append(CandidateAction(.raise, roundedRaise(s, value))) }
    }
    candidates.append(CandidateAction(s.action, s.amount))
    candidates += alternatives.compactMap { $0 }
    var keys: [String] = []
    var byKey: [String: CandidateAction] = [:]
    for a in candidates {
        let legal = (a.action != .raise || (s.legal.canRaise && a.amount >= s.legal.minRaiseTo && a.amount <= s.legal.maxRaiseTo)) &&
            (a.action != .check || s.legal.canCheck)
        guard legal else { continue }
        let key = a.action.rawValue + (a.action == .raise ? String(a.amount) : "")
        if byKey[key] == nil { keys.append(key) }
        byKey[key] = CandidateAction(a.action, a.action == .raise ? a.amount : a.action == .call ? s.legal.callAmount : 0)
    }
    return keys.prefix(7).map { byKey[$0]! }
}

public struct CounterfactualScenario: Equatable, Sendable {
    /// `true` for the public-action-weighted range, `false` for the random range.
    public var weighted: Bool
    public var name: String
    /// Mean net chip change from this decision on.
    public var ev: Double
    /// 1.96 standard errors.
    public var margin: Double
    /// Share of trials won by an immediate fold on this street (raises only).
    public var immediateFoldWin: Double
}

public struct CounterfactualRow: Equatable, Sendable {
    public var action: CandidateAction
    /// Random range first, then the weighted range.
    public var scenarios: [CounterfactualScenario]
}

public struct CounterfactualResult: Equatable, Sendable {
    /// In candidate order.
    public var rows: [CounterfactualRow]
    public var trials: Int
    public var policyTrials: Int
    public var best: CandidateAction
    public var stable: Bool
    public var method: String
    public var note: String
}

private struct SampledDeal {
    var holes: [Int: [Card]]
    var deck: [Card]
}

private func sampledDeal(_ s: ReviewDecision, _ rng: RandomSource, weighted: Bool) -> SampledDeal {
    let known = Set((s.hole + s.board).map(\.key))
    var pool = deckOfCards().filter { !known.contains($0.key) }
    var holes: [Int: [Card]] = [0: s.hole]
    let order = s.players.filter { $0.id != 0 && !$0.folded } + s.players.filter { $0.id != 0 && $0.folded }
    for p in order {
        var a = 0, b = 0
        repeat {
            a = Int((rng.next() * Double(pool.count)).rounded(.down))
            b = Int((rng.next() * Double(pool.count - 1)).rounded(.down))
            if b >= a { b += 1 }
        } while weighted && !p.folded && rng.next() >= rangeWeight([pool[a], pool[b]], s, opponent: p.id) / 6
        holes[p.id] = [pool[a], pool[b]]
        pool.remove(at: max(a, b))
        pool.remove(at: min(a, b))
    }
    shuffle(&pool, random: rng)
    return SampledDeal(holes: holes, deck: pool)
}

private func resume(_ s: ReviewDecision, _ deal: SampledDeal) throws -> Game {
    let g = try newGame(s.players.count)
    let button = s.players.first { $0.position == "BTN" }?.id
    g.phase = .playing
    g.hand = s.hand
    g.street = s.street
    g.actor = 0
    g.dealer = s.dealer ?? button ?? 0
    g.currentBet = s.currentBet
    g.minRaise = s.minRaise
    g.pending = s.pending
    g.board = s.board
    g.deck = deal.deck
    g.history = s.history
    g.decisions = []
    g.botDecisions = []
    g.logs = []
    g.emotionMode = s.emotionMode ?? .off
    for p in s.players {
        var mood = freshBotMood()
        mood.kind = p.state?.botMoodKind ?? .steady
        g.players[p.id].stack = p.stack
        g.players[p.id].bet = p.bet
        g.players[p.id].total = p.total
        g.players[p.id].folded = p.folded
        g.players[p.id].allin = p.allin
        g.players[p.id].actedTo = p.state?.actedTo
        g.players[p.id].checked = p.state?.checked ?? false
        g.players[p.id].hole = deal.holes[p.id] ?? []
        g.players[p.id].botProfile = getBotProfile(p.state?.botProfile).id
        g.players[p.id].botMood = mood
    }
    return g
}

let POLICY_TRIALS = 8

// Sampled private information only: original opponent holes, recorded traces,
// future deck and outcome never enter these counterfactual hands.
/// `checkCancellation` runs between trials so a superseded review can stop early.
public func compareCandidateActions(_ s: ReviewDecision, _ alternatives: [CandidateAction?] = [], trials: Int = 40,
                                    checkCancellation: () throws -> Void = {}) throws -> CounterfactualResult {
    guard trials >= 2 else { throw ReviewError(.invalidSimulationTrials) }
    let candidates = candidateActions(s, alternatives)
    var rows = candidates.map { CounterfactualRow(action: $0, scenarios: []) }
    let seed = snapshotSeed(s)
    for weighted in [false, true] {
        let rng = seedRandom(seed + (weighted ? 11071 : 2003))
        var values = Array(repeating: [Int](), count: candidates.count)
        var immediate = Array(repeating: 0, count: candidates.count)
        for _ in 0..<trials {
            try checkCancellation()
            let deal = sampledDeal(s, rng, weighted: weighted)
            let policySeed = Int((rng.next() * 4_294_967_295).rounded(.down))
            for (c, candidate) in candidates.enumerated() {
                let g = try resume(s, deal)
                let policy = seedRandom(policySeed)
                try act(g, 0, candidate.action, candidate.amount)
                var actions = 0
                while g.phase != .done {
                    actions += 1
                    if actions > 400 { throw ReviewError(.simulationRunaway) }
                    if g.phase == .between {
                        try advanceStreet(g)
                    } else {
                        let d = try botDecision(g, random: policy, trials: POLICY_TRIALS)
                        try act(g, g.actor, d.action, d.amount)
                    }
                }
                values[c].append(g.players[0].stack - s.stack)
                if g.winners.contains(where: { $0.id == 0 }) && !g.showdown && g.street == s.street &&
                    candidate.action == .raise {
                    immediate[c] += 1
                }
            }
        }
        for c in rows.indices {
            let mean = values[c].reduce(0.0) { $0 + Double($1) } / Double(trials)
            let variance = values[c].reduce(0.0) { $0 + (Double($1) - mean) * (Double($1) - mean) } / Double(trials - 1)
            rows[c].scenarios.append(CounterfactualScenario(
                weighted: weighted,
                name: weighted ? ReviewCopy.scenarioWeighted : ReviewCopy.scenarioRandom,
                ev: mean,
                margin: 1.96 * (variance / Double(trials)).squareRoot(),
                immediateFoldWin: Double(immediate[c]) / Double(trials)))
        }
    }
    // Stable sort by the worst scenario EV, descending; ties keep candidate order.
    let worst = rows.map { $0.scenarios.map(\.ev).min() ?? 0 }
    let ranked = rows.indices.sorted { worst[$0] != worst[$1] ? worst[$0] > worst[$1] : $0 < $1 }.map { rows[$0] }
    let best = ranked[0]
    let stable = ranked.dropFirst().allSatisfy { other in
        best.scenarios.indices.allSatisfy { i in
            best.scenarios[i].ev - best.scenarios[i].margin > other.scenarios[i].ev + other.scenarios[i].margin
        }
    }
    return CounterfactualResult(rows: rows, trials: trials, policyTrials: POLICY_TRIALS, best: best.action,
                                stable: stable, method: "sampled-engine-rollout", note: ReviewCopy.simulationNote)
}
