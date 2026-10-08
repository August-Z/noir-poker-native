// Native port of the reference engine (src/engine/poker.js). Function names and
// behavior mirror the reference; every random draw happens in the same order.

public func newGame(_ playerCount: Int = 6) throws -> Game {
    guard (MIN_PLAYERS...MAX_PLAYERS).contains(playerCount) else { throw PokerError(.invalidPlayerCount) }
    let names = [EngineCopy.heroName] + EngineCopy.botNames
    let players = names.prefix(playerCount).enumerated().map { Player(id: $0.offset, name: $0.element) }
    return Game(players: players, dealer: playerCount - 1)
}

/// Applies sanitized opponent settings between hands. See `sanitizeBotSettings`
/// for the accepted input.
public func applyBotSettings(_ g: Game, _ value: Any?) throws {
    guard g.phase == .idle || g.phase == .done else { throw PokerError(.settingsLocked) }
    let settings = sanitizeBotSettings(value)
    for i in g.players.indices.dropFirst() {
        let assigned = settings.assignments[g.players[i].id] ?? "balanced"
        if g.players[i].botProfile != assigned {
            g.players[i].botProfile = assigned
            g.players[i].botMood = freshBotMood()
            g.players[i].botStats = freshBotStats()
        }
        if settings.emotionMode == .off { g.players[i].botMood = freshBotMood() }
    }
    g.emotionMode = settings.emotionMode
}

// Seat IDs follow the physical table clockwise, starting at the hero.
public let POSITION_ROLES: [Int: [String]] = [
    5: ["BTN", "SB", "BB", "UTG", "CO"],
    6: ["BTN", "SB", "BB", "UTG", "HJ", "CO"],
    7: ["BTN", "SB", "BB", "UTG", "LJ", "HJ", "CO"],
    8: ["BTN", "SB", "BB", "UTG", "UTG+1", "LJ", "HJ", "CO"],
    9: ["BTN", "SB", "BB", "UTG", "UTG+1", "MP", "LJ", "HJ", "CO"],
]

public func seatPosition(_ g: Game, _ id: Int) -> String {
    let n = g.players.count
    return POSITION_ROLES[n]![(id - g.dealer + n) % n]
}

public func potSize(_ g: Game) -> Int { g.players.reduce(0) { $0 + $1.total } }

private func potLabel(_ index: Int) -> String { index == 0 ? EngineCopy.mainPot : EngineCopy.sidePot(index) }

// Contribution layers determine eligibility. Folded chips stay in the pots;
// adjacent layers with the same eligible players belong to the same pot.
public func partitionPots(_ g: Game) throws -> PotSet {
    let levels = Set(g.players.map(\.total).filter { $0 > 0 }).sorted()
    var pots: [Pot] = []
    var refunds: [Refund] = []
    var previous = 0
    for level in levels {
        let contributors = g.players.filter { $0.total >= level }
        let increment = level - previous
        previous = level
        if contributors.count == 1 {
            refunds.append(Refund(id: contributors[0].id, amount: increment))
            continue
        }
        let eligible = contributors.filter { !$0.folded }.map(\.id)
        let amount = increment * contributors.count
        guard !eligible.isEmpty else { throw PokerError(.noEligiblePlayer) }
        if pots.last == nil || pots[pots.count - 1].eligible != eligible {
            pots.append(Pot(index: pots.count, label: potLabel(pots.count), amount: 0, eligible: eligible, contributions: []))
        }
        let k = pots.count - 1
        pots[k].amount += amount
        for p in contributors {
            if let c = pots[k].contributions.firstIndex(where: { $0.id == p.id }) {
                pots[k].contributions[c].amount += increment
            } else {
                pots[k].contributions.append(PotContribution(id: p.id, amount: increment))
            }
        }
    }
    return PotSet(pots: pots, refunds: refunds)
}

// A live bet difference is not a side pot: callers may still match it.
// Only an all-in contribution cap separates live main and side pots.
public func currentPots(_ g: Game) -> PotSet {
    if g.phase == .done { return PotSet(pots: g.pots, refunds: g.refunds) }
    let totals = g.players.map(\.total).sorted(by: >)
    let ceiling = totals.count > 1 ? totals[1] : 0
    let refunds = g.players.filter { $0.total > ceiling }.map { Refund(id: $0.id, amount: $0.total - ceiling) }
    let levels = Set(g.players.filter { $0.allin && $0.total > 0 && $0.total < ceiling }.map(\.total) + [ceiling])
        .filter { $0 > 0 }.sorted()
    var pots: [Pot] = []
    var previous = 0
    for level in levels {
        let contributions = g.players
            .map { PotContribution(id: $0.id, amount: max(0, min($0.total, level) - previous)) }
            .filter { $0.amount > 0 }
        let eligible = g.players
            .filter { !$0.folded && ($0.total >= level || (!$0.allin && $0.total + $0.stack >= level)) }
            .map(\.id)
        let amount = contributions.reduce(0) { $0 + $1.amount }
        previous = level
        if amount == 0 { continue }
        pots.append(Pot(index: pots.count, label: potLabel(pots.count), amount: amount, eligible: eligible,
                        contributions: contributions))
    }
    return PotSet(pots: pots, refunds: refunds)
}

public func contestableAfterCall(_ g: Game, _ id: Int, _ amount: Int) -> Int {
    let cap = g.players[id].total + amount
    return g.players.reduce(0) { $0 + min($1.total, cap) } + amount
}

private func live(_ g: Game) -> [Player] { g.players.filter { !$0.folded } }

private func canAct(_ p: Player) -> Bool { !p.folded && !p.allin && p.stack > 0 }

private func nextIndex(_ g: Game, _ start: Int, _ list: [Int]) -> Int {
    let n = g.players.count
    for d in stride(from: 1, through: n, by: 1) {
        let id = (start + d) % n
        if list.contains(id) { return id }
    }
    return -1
}

private func log(_ g: Game, _ text: String, _ player: Int? = nil, _ type: LogType = .action) {
    g.logs.insert(LogEntry(text: text, player: player, type: type, street: g.street), at: 0)
}

@discardableResult
private func pay(_ g: Game, _ id: Int, _ amount: Int) -> Int {
    let n = min(g.players[id].stack, amount)
    g.players[id].stack -= n
    g.players[id].bet += n
    g.players[id].total += n
    g.players[id].allin = g.players[id].stack == 0
    return n
}

// Public presentation only; street bet resets and settlement never overwrite it.
private func rememberAction(_ g: Game, _ id: Int) {
    let p = g.players[id]
    g.players[id].lastAction = LastAction(text: p.action, street: g.street, bet: p.bet)
}

/// Replay Hand is available once a hand that this game dealt has been settled.
public func canRestartHand(_ g: Game) -> Bool { g.phase == .done && g.handStart != nil }

public func startHand(_ g: Game, random: RandomSource = SystemRandom.shared) throws {
    guard g.phase == .idle || g.phase == .done else { throw PokerError(.handInProgress) }
    g.replayAttempt = 0
    g.potAtShowdown = 0
    g.hand += 1
    g.dealer = (g.dealer + 1) % g.players.count
    g.board = []
    g.practiceBoard = nil
    var deck = deckOfCards()
    shuffle(&deck, random: random)
    g.deck = deck
    g.street = 0
    g.phase = .playing
    g.currentBet = BIG_BLIND
    g.minRaise = BIG_BLIND
    g.winners = []
    g.payouts = []
    g.pots = []
    g.refunds = []
    g.showdown = false
    g.revealed = false
    g.logs = []
    g.result = ""
    g.decisions = []
    g.botDecisions = []
    g.history = []
    log(g, EngineCopy.handStarts(g.hand, button: g.players[g.dealer].name), nil, .street)
    for i in g.players.indices {
        if g.players[i].id != 0 { decayBotMood(&g.players[i].botMood) }
        g.players[i].botHand = BotHand()
        if g.players[i].stack == 0 {
            g.players[i].stack = STARTING_STACK
            if g.players[i].id == 0 { g.stats.buyin += STARTING_STACK }
            log(g, EngineCopy.rebuy(g.players[i].name), g.players[i].id, .info)
        }
        g.players[i].hole = []
        g.players[i].folded = false
        g.players[i].allin = false
        g.players[i].bet = 0
        g.players[i].total = 0
        g.players[i].actedTo = nil
        g.players[i].checked = false
        g.players[i].action = ""
        g.players[i].lastAction = nil
    }
    let n = g.players.count
    for _ in 0..<2 {
        for i in 1...n { g.players[(g.dealer + i) % n].hole.append(g.deck.removeLast()) }
    }
    let sb = (g.dealer + 1) % n, bb = (g.dealer + 2) % n
    pay(g, sb, SMALL_BLIND)
    g.players[sb].action = EngineCopy.smallBlindAction(g.players[sb].bet)
    rememberAction(g, sb)
    pay(g, bb, BIG_BLIND)
    g.players[bb].action = EngineCopy.bigBlindAction(g.players[bb].bet)
    rememberAction(g, bb)
    log(g, EngineCopy.blindsLog(g.players[sb].name, g.players[sb].bet, g.players[bb].name, g.players[bb].bet), nil, .blind)
    g.pending = g.players.filter(canAct).map(\.id)
    g.actor = nextIndex(g, bb, g.pending)
    g.handStart = g.state
}

/// Replay Hand: restores the state after the blinds were posted, before any
/// action, rolling back this attempt's awards, refunds, decisions and session
/// statistics. Only the current difficulty is kept.
public func restartHand(_ g: Game) throws {
    guard canRestartHand(g), let original = g.handStart else { throw PokerError(.replayUnavailable) }
    let attempt = g.replayAttempt + 1
    let difficulty = g.difficulty
    g.state = original
    g.difficulty = difficulty
    g.replayAttempt = attempt
    log(g, EngineCopy.replayLog(g.hand, attempt), nil, .info)
}

public func legalActions(_ g: Game) -> LegalActions { legalActions(g, g.actor) }

public func legalActions(_ g: Game, _ id: Int) -> LegalActions {
    guard g.phase == .playing, g.actor == id, g.players.indices.contains(id), canAct(g.players[id]) else {
        return .disabled
    }
    let p = g.players[id]
    let owed = max(0, g.currentBet - p.bet)
    let maxTo = p.bet + p.stack
    let minTo = g.currentBet == 0 ? BIG_BLIND : g.currentBet + g.minRaise
    let reopened = p.actedTo.map { g.currentBet - $0 >= g.minRaise } ?? true
    let other = g.players.contains { $0.id != id && canAct($0) }
    return LegalActions(
        enabled: true,
        toCall: owed,
        callAmount: min(p.stack, owed),
        canCheck: owed == 0,
        raiseReopened: reopened,
        canRaise: maxTo > g.currentBet && reopened && other,
        minRaiseTo: min(minTo, maxTo),
        fullRaiseTo: minTo,
        maxRaiseTo: maxTo,
        isShortAllin: maxTo < minTo
    )
}

/// String form of `act` for untrusted input: unknown actions throw like the reference.
public func act(_ g: Game, _ id: Int, _ action: String, _ amount: Int? = nil) throws {
    guard legalActions(g, id).enabled else { throw PokerError(.notYourTurn) }
    guard let parsed = PokerAction(rawValue: action) else { throw PokerError(.unknownAction) }
    try act(g, id, parsed, amount)
}

public func act(_ g: Game, _ id: Int, _ action: PokerAction, _ amount: Int? = nil) throws {
    let legal = legalActions(g, id)
    guard legal.enabled else { throw PokerError(.notYourTurn) }
    if action == .check && !legal.canCheck { throw PokerError(.cannotCheck) }
    if action == .raise {
        guard legal.canRaise, let amount, amount >= legal.minRaiseTo, amount <= legal.maxRaiseTo else {
            throw PokerError(.illegalRaise)
        }
    }
    // Capture only information available before the decision. Opponents' hole
    // cards, the remaining deck and future community cards never enter review.
    let normalized: PokerAction = action == .call && legal.canCheck ? .check : action
    let betLabel = normalized == .raise
        ? raiseCaption(LabelStep(street: g.street, history: g.history, currentBet: g.currentBet, legal: legal), amount!)
        : nil
    let recordedAmount = normalized == .raise ? amount! : normalized == .call ? legal.callAmount : 0
    if id != 0 {
        if g.street == 0 && (normalized == .call || normalized == .raise) { g.players[id].botHand.vpip = true }
        if g.street == 0 && normalized == .raise { g.players[id].botHand.pfr = true }
        if g.street > 0 && normalized != .fold {
            g.players[id].botStats.postActions += 1
            if normalized == .raise { g.players[id].botStats.postRaises += 1 }
            if normalized == .call { g.players[id].botStats.postCalls += 1 }
        }
        let facing = g.history.last { $0.street == g.street && $0.action == .raise }
        if normalized == .fold, let facing, !g.players[id].botHand.pressureRecorded {
            g.players[id].botHand.pressureRecorded = true
            if let event = recordPressureFold(&g.players[id].botMood, raiser: facing.id, mode: g.emotionMode) {
                log(g, EngineCopy.moodLog(g.players[id].name, event.kind.label, event.reason), id, .info)
            }
        } else if normalized != .fold, let facing {
            g.players[id].botMood.pressureFolds[facing.id] = 0
        }
    }
    if id == 0 {
        let p = g.players[id]
        g.decisions.append(DecisionSnapshot(
            index: g.decisions.count,
            hand: g.hand,
            street: g.street,
            position: seatPosition(g, id),
            hole: p.hole,
            board: g.board,
            stack: p.stack,
            bet: p.bet,
            total: p.total,
            pot: potSize(g),
            currentBet: g.currentBet,
            minRaise: g.minRaise,
            dealer: g.dealer,
            emotionMode: g.emotionMode,
            legal: legal,
            pending: g.pending,
            action: normalized,
            amount: recordedAmount,
            players: g.players.map { o in
                SnapshotPlayer(
                    id: o.id,
                    name: o.name,
                    position: seatPosition(g, o.id),
                    stack: o.stack,
                    bet: o.bet,
                    total: o.total,
                    folded: o.folded,
                    allin: o.allin,
                    action: o.action,
                    botProfile: o.id != 0 ? o.botProfile : nil,
                    publicAxes: o.id != 0 ? effectiveBotAxes(getBotProfile(o.botProfile), o.botMood, g.emotionMode) : nil,
                    botMoodKind: o.id != 0 ? o.botMood.kind : nil,
                    actedTo: o.actedTo,
                    checked: o.checked
                )
            },
            history: g.history
        ))
    }
    g.history.append(HistoryEntry(street: g.street, id: id, action: normalized, amount: recordedAmount, betLabel: betLabel))
    g.pending.removeAll { $0 == id }
    let name = g.players[id].name
    if action == .fold {
        g.players[id].folded = true
        g.players[id].action = EngineCopy.fold
    } else if action == .check || (action == .call && legal.toCall == 0) {
        g.players[id].checked = true
        g.players[id].action = EngineCopy.check
        g.players[id].actedTo = g.currentBet
    } else if action == .call {
        let n = pay(g, id, legal.callAmount)
        g.players[id].checked = false
        g.players[id].actedTo = g.currentBet
        g.players[id].action = g.players[id].allin ? EngineCopy.allIn(g.players[id].bet) : EngineCopy.call(n)
    } else {
        let raiseTo = amount!
        let old = g.currentBet
        pay(g, id, raiseTo - g.players[id].bet)
        g.currentBet = raiseTo
        g.players[id].checked = false
        g.players[id].actedTo = raiseTo
        if raiseTo - old >= g.minRaise {
            g.minRaise = raiseTo - old
            g.pending = g.players.filter { $0.id != id && canAct($0) }.map(\.id)
        } else {
            for o in g.players where o.id != id && canAct(o) && o.bet < raiseTo && !g.pending.contains(o.id) {
                g.pending.append(o.id)
            }
        }
        g.players[id].action = EngineCopy.raiseAction(betLabel!, raiseTo)
    }
    log(g, EngineCopy.actionLog(name, g.players[id].action), id)
    rememberAction(g, id)
    try progress(g, id)
}

private func progress(_ g: Game, _ last: Int) throws {
    if live(g).count == 1 {
        try settle(g, showdown: false)
        return
    }
    g.pending = g.pending.filter { canAct(g.players[$0]) }
    if g.pending.count == 1 && g.players[g.pending[0]].bet >= g.currentBet && g.players.filter(canAct).count == 1 {
        g.pending = []
    }
    if !g.pending.isEmpty {
        g.actor = nextIndex(g, last, g.pending)
        g.phase = .playing
    } else {
        g.actor = -1
        g.phase = .between
        if g.street == 3 || (live(g).contains { $0.allin } && g.players.filter(canAct).count <= 1) {
            g.revealed = true
        }
    }
}

private func dealCommunityCards(_ board: inout [Card], _ deck: inout [Card], _ count: Int) {
    deck.removeLast() // Burn one card before each street, including practice runouts.
    for _ in 0..<count { board.append(deck.removeLast()) }
}

public func completeBoardForPractice(_ g: Game) throws {
    guard g.phase == .done else { throw PokerError(.handNotSettled) }
    if g.board.count == 5 || g.practiceBoard != nil { return }
    if g.showdown { throw PokerError(.showdownNeedsBoard) }
    // These cards are a learning preview after a fold-win, not new game actions.
    // Keep the actual board, deck, settlement and review evidence untouched.
    var board = g.board, deck = g.deck
    while board.count < 5 { dealCommunityCards(&board, &deck, board.isEmpty ? 3 : 1) }
    g.practiceBoard = board
    log(g, EngineCopy.practiceRunout, nil, .info)
}

public func advanceStreet(_ g: Game) throws {
    guard g.phase == .between else { throw PokerError(.roundNotFinished) }
    if g.street == 3 {
        try settle(g, showdown: true)
        return
    }
    g.street += 1
    let count = g.street == 1 ? 3 : 1
    dealCommunityCards(&g.board, &g.deck, count)
    g.currentBet = 0
    g.minRaise = BIG_BLIND
    for i in g.players.indices {
        g.players[i].bet = 0
        g.players[i].actedTo = nil
        g.players[i].checked = false
        if !g.players[i].folded { g.players[i].action = g.players[i].allin ? EngineCopy.allInReset : "" }
    }
    log(g, EngineCopy.streetNames[g.street] + " · " +
        g.board.suffix(count).map { rankText($0.rank) + $0.symbol }.joined(separator: " "), nil, .street)
    let active = g.players.filter(canAct)
    if active.count <= 1 {
        g.pending = []
        g.actor = -1
        g.phase = .between
        if live(g).contains(where: { $0.allin }) { g.revealed = true }
    } else {
        g.pending = active.map(\.id)
        g.actor = nextIndex(g, g.dealer, g.pending)
        g.phase = .playing
    }
}

public func settle(_ g: Game, showdown: Bool = true) throws {
    guard g.phase != .done else { throw PokerError(.alreadySettled) }
    let partition = try partitionPots(g)
    var pots = partition.pots
    let refunds = partition.refunds
    let n = g.players.count
    var payouts = Array(repeating: 0, count: n)
    var won = Array(repeating: 0, count: n)
    var ranks: [Int: HandEvaluation] = [:]
    if showdown { for p in live(g) { ranks[p.id] = evaluate(p.hole + g.board) } }
    for refund in refunds { payouts[refund.id] += refund.amount }
    for k in pots.indices {
        let eligible = pots[k].eligible.map { g.players[$0] }
        var winners: [Player] = []
        if !showdown {
            winners = [eligible[0]]
        } else {
            var best: [Int]? = nil
            for p in eligible {
                let score = ranks[p.id]!.score
                let c = best.map { compare(score, $0) } ?? 1
                if c > 0 {
                    best = score
                    winners = [p]
                } else if c == 0 {
                    winners.append(p)
                }
            }
        }
        let order = { (p: Player) in (p.id - g.dealer + n - 1) % n }
        winners = winners.enumerated().sorted { order($0.element) != order($1.element)
            ? order($0.element) < order($1.element) : $0.offset < $1.offset }.map(\.element)
        let share = pots[k].amount / winners.count, remainder = pots[k].amount % winners.count
        pots[k].awards = winners.enumerated().map { i, p in
            PotAward(id: p.id, amount: share + (i < remainder ? 1 : 0),
                     label: showdown ? ranks[p.id]!.label : EngineCopy.othersFolded)
        }
        for award in pots[k].awards {
            payouts[award.id] += award.amount
            won[award.id] += award.amount
        }
    }
    guard payouts.reduce(0, +) == potSize(g) else { throw PokerError(.potMismatch) }
    g.pots = pots
    g.refunds = refunds
    g.payouts = payouts
    g.winners = g.players.filter { won[$0.id] > 0 }.map { p in
        Winner(id: p.id, name: p.name, amount: won[p.id], profit: payouts[p.id] - p.total,
               label: showdown ? evaluate(p.hole + g.board).label : EngineCopy.othersFolded)
    }
    g.potAtShowdown = won.reduce(0, +)
    g.showdown = showdown
    g.phase = .done
    g.actor = -1
    g.stats.hands += 1
    if won[0] > 0 { g.stats.wins += 1 }
    for i in g.players.indices { g.players[i].stack += payouts[g.players[i].id] }
    g.result = (pots.count > 1 ? EngineCopy.splitPots : "") + g.winners.map { w in
        showdown ? EngineCopy.showdownResult(w.name, w.label, w.amount) : EngineCopy.foldWinResult(w.name, w.amount)
    }.joined(separator: " / ")
    for pot in pots {
        log(g, EngineCopy.potLog(pot.label, pot.amount, pot.awards.map { (g.players[$0.id].name, $0.amount) }), nil, .result)
    }
    for refund in refunds {
        log(g, EngineCopy.refundLog(g.players[refund.id].name, refund.amount), refund.id, .info)
    }
    log(g, g.result, nil, .result)
    for i in g.players.indices.dropFirst() {
        g.players[i].botStats.hands += 1
        if g.players[i].botHand.vpip { g.players[i].botStats.vpip += 1 }
        if g.players[i].botHand.pfr { g.players[i].botStats.pfr += 1 }
        if !g.players[i].botHand.pressureRecorded {
            g.players[i].botMood.pressureFolds = [:]
            g.players[i].botMood.lastPressureRaiser = nil
        }
        let profit = payouts[g.players[i].id] - g.players[i].total
        if let event = finishBotHand(&g.players[i], profit: profit, mode: g.emotionMode) {
            log(g, EngineCopy.moodLog(g.players[i].name, event.kind.label, event.reason), g.players[i].id, .info)
        }
    }
}

/// Sampled equity against random opponent hands. Consumes
/// `trials × (available − 1)` random values.
public func estimateEquity(_ hole: [Card], _ board: [Card], rivals: Int = 1, trials: Int = 35,
                           random: RandomSource = SystemRandom.shared) -> Double {
    let known = Set((hole + board).map(\.key))
    let available = deckOfCards().filter { !known.contains($0.key) }
    var wins = 0.0
    for _ in 0..<max(0, trials) {
        var sample = available
        shuffle(&sample, random: random)
        var community = board
        while community.count < 5 { community.append(sample.removeLast()) }
        let score = evaluate(hole + community).score
        var tied = 1
        var lost = false
        for _ in 0..<max(0, rivals) {
            let first = sample.removeLast(), second = sample.removeLast()
            let c = compare(evaluate([first, second] + community).score, score)
            if c > 0 {
                lost = true
                break
            }
            if c == 0 { tied += 1 }
        }
        if !lost { wins += 1 / Double(tied) }
    }
    return wins / Double(trials)
}

/// The current actor's decision, built from the white-listed `BotView` only.
public func botDecision(_ g: Game, random: RandomSource = SystemRandom.shared, trials: Int? = nil) throws -> BotDecision {
    let legal = legalActions(g)
    let rivals = max(1, live(g).count - 1)
    guard g.players.indices.contains(g.actor), legal.enabled else { throw PokerError(.botCannotAct) }
    let p = g.players[g.actor]
    let score = evaluate(p.hole + g.board).score
    let equityTrials = trials ?? (g.difficulty == .hard ? 52 : 28)
    guard equityTrials >= 1 else { throw PokerError(.invalidTrials) }
    let n = g.players.count
    // Explicit actor perspective: no other hole cards, future deck, review
    // decisions or eventual winners can enter this policy.
    var view = BotView(id: p.id, hole: p.hole, legal: legal)
    view.board = g.board
    view.street = g.street
    view.position = seatPosition(g, p.id)
    view.count = n
    view.inPosition = (0..<n).map { g.players[(g.dealer + 1 + $0) % n] }.filter(canAct).last?.id == p.id
    view.stack = p.stack
    view.bet = p.bet
    view.pot = potSize(g)
    view.currentBet = g.currentBet
    view.difficulty = g.difficulty
    view.rivals = rivals
    view.opponents = live(g).filter { $0.id != p.id }.map { BotOpponent(id: $0.id, stack: $0.stack, bet: $0.bet, allin: $0.allin) }
    view.equity = estimateEquity(p.hole, g.board, rivals: rivals, trials: equityTrials, random: random)
    view.equityTrials = equityTrials
    view.contestable = contestableAfterCall(g, p.id, legal.callAmount)
    view.history = g.history
    view.features = botBoardFeatures(p.hole, g.board, score)
    view.playsBoard = g.board.count == 5 && compare(score, evaluate(g.board).score) == 0
    var decision = try chooseBotAction(view, getBotProfile(p.botProfile), p.botMood, g.emotionMode, random: random)
    decision.trace.view = view
    return decision
}

private struct PlanRecord {
    weak var game: Game?
    let id: Int
    let hand: Int
    let attempt: Int
    let street: Int
    let sequence: Int
    let difficulty: Difficulty
    let stack: Int
    let bet: Int
    let decision: BotDecision
    let thinking: BotThinking
}

/// An opaque bot plan. Only the synthetic delay is public; the preselected
/// action and private timing factors stay inside the engine.
public final class BotPlan {
    public let delayMs: Int
    fileprivate var record: PlanRecord?
    fileprivate init(delayMs: Int, record: PlanRecord) {
        self.delayMs = delayMs
        self.record = record
    }
}

// Opaque plans keep preselected actions and private timing factors off the UI.
/// `timingRandom` defaults to `random`, matching a single-stream fixture where
/// the reference draws both from `Math.random`.
public func planBotTurn(_ g: Game, random: RandomSource = SystemRandom.shared,
                        timingRandom: RandomSource? = nil) throws -> BotPlan {
    if g.actor == 0 { throw PokerError(.heroBotExecutor) }
    let decision = try botDecision(g, random: random)
    let thinking = botThinkingTime(decision, random: timingRandom ?? random)
    let record = PlanRecord(game: g, id: g.actor, hand: g.hand, attempt: g.replayAttempt, street: g.street,
                            sequence: g.history.count, difficulty: g.difficulty, stack: g.players[g.actor].stack,
                            bet: g.currentBet, decision: decision, thinking: thinking)
    return BotPlan(delayMs: thinking.durationMs, record: record)
}

public func isBotTurnCurrent(_ g: Game, _ plan: BotPlan) -> Bool {
    guard let p = plan.record, p.game === g, g.phase == .playing, p.id == g.actor,
          g.players.indices.contains(g.actor) else { return false }
    return p.hand == g.hand &&
        p.attempt == g.replayAttempt &&
        p.street == g.street &&
        p.sequence == g.history.count &&
        p.difficulty == g.difficulty &&
        p.stack == g.players[g.actor].stack &&
        p.bet == g.currentBet
}

// Only executing a current plan writes an action and its one private record.
@discardableResult
public func executeBotTurn(_ g: Game, _ plan: BotPlan, expedited: Bool = false, waitedMs: Int = 0) throws -> BotDecision {
    guard isBotTurnCurrent(g, plan), let record = plan.record else { throw PokerError(.staleBotPlan) }
    let decision = record.decision, thinking = record.thinking
    var trace = decision.trace
    trace.thinking = BotThinkingRecord(durationMs: thinking.durationMs, model: thinking.model, acting: thinking.acting,
                                       factors: thinking.factors, expedited: expedited, waitedMs: max(0, waitedMs))
    let entry = BotDecisionRecord(id: record.id, name: g.players[record.id].name, hand: g.hand,
                                  sequence: g.history.count + 1, action: decision.action, amount: decision.amount,
                                  trace: trace)
    try act(g, record.id, decision.action, decision.amount)
    plan.record = nil
    g.botDecisions.append(entry)
    return decision
}

/// Plans and immediately executes a bot turn. The reference's timing roll uses
/// its global `Math.random`; pass the same stream as `random` (the default) to
/// reproduce a single-stream fixture, or a separate `timingRandom`.
@discardableResult
public func playBotTurn(_ g: Game, random: RandomSource = SystemRandom.shared,
                        timingRandom: RandomSource? = nil) throws -> BotDecision {
    try executeBotTurn(g, planBotTurn(g, random: random, timingRandom: timingRandom), expedited: true)
}
