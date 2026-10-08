// Port of src/review/equity.js: seeded streams, the snapshot seed, the
// eligible-pot call price, the public-action range model and pot-equity sampling.

/// Mulberry32 (`seedRandom`). The seed is reduced modulo 2^32, like `seed >>> 0`.
public func seedRandom(_ seed: Int) -> SeededRandom { SeededRandom(seed: seed) }

// MARK: - snapshotSeed

private func appendJSONString(_ s: String, to out: inout String) {
    out.append("\"")
    for scalar in s.unicodeScalars {
        switch scalar {
        case "\"": out.append("\\\"")
        case "\\": out.append("\\\\")
        case "\u{08}": out.append("\\b")
        case "\u{0C}": out.append("\\f")
        case "\n": out.append("\\n")
        case "\r": out.append("\\r")
        case "\t": out.append("\\t")
        default:
            if scalar.value < 0x20 {
                let hex = String(scalar.value, radix: 16)
                out.append("\\u" + String(repeating: "0", count: 4 - hex.count) + hex)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
    }
    out.append("\"")
}

private func appendJSONCards(_ cards: [Card], to out: inout String) {
    out.append("[")
    for (i, c) in cards.enumerated() {
        if i > 0 { out.append(",") }
        out.append("{\"rank\":\(c.rank),\"suit\":\(c.suit),\"symbol\":")
        appendJSONString(c.symbol, to: &out)
        out.append(",\"key\":")
        appendJSONString(c.key, to: &out)
        out.append("}")
    }
    out.append("]")
}

/// The JSON text `snapshotSeed` hashes, byte for byte: `JSON.stringify` of
/// `[hole, board, players(id, position, stack, bet, total, folded, allin, actedTo,
/// checked, botProfile, botMoodKind), history(id, street, action, amount), street,
/// legal.callAmount]`. Seat keys a hand-built snapshot omits are left out, as
/// JavaScript drops `undefined`; `null` prints `null`.
public func snapshotSeedJSON(_ s: ReviewDecision) -> String {
    var out = "["
    appendJSONCards(s.hole, to: &out)
    out.append(",")
    appendJSONCards(s.board, to: &out)
    out.append(",[")
    for (i, p) in s.players.enumerated() {
        if i > 0 { out.append(",") }
        out.append("{\"id\":\(p.id),\"position\":")
        appendJSONString(p.position, to: &out)
        out.append(",\"stack\":\(p.stack),\"bet\":\(p.bet),\"total\":\(p.total),\"folded\":\(p.folded),\"allin\":\(p.allin)")
        if let state = p.state {
            out.append(",\"actedTo\":" + (state.actedTo.map(String.init) ?? "null"))
            out.append(",\"checked\":\(state.checked)")
            out.append(",\"botProfile\":")
            if let profile = state.botProfile { appendJSONString(profile, to: &out) } else { out.append("null") }
            out.append(",\"botMoodKind\":")
            if let kind = state.botMoodKind { appendJSONString(kind.rawValue, to: &out) } else { out.append("null") }
        }
        out.append("}")
    }
    out.append("],[")
    for (i, a) in s.history.enumerated() {
        if i > 0 { out.append(",") }
        out.append("{\"id\":\(a.id),\"street\":\(a.street),\"action\":")
        appendJSONString(a.action.rawValue, to: &out)
        out.append(",\"amount\":\(a.amount)}")
    }
    out.append("],\(s.street),\(s.legal.callAmount)]")
    return out
}

/// FNV-1a over the UTF-16 code units of `snapshotSeedJSON(s)`, with 32-bit
/// wrapping multiplication (`Math.imul`). Returns an unsigned 32-bit value.
public func snapshotSeed(_ s: ReviewDecision) -> Int {
    var seed: UInt32 = 2_166_136_261
    for unit in snapshotSeedJSON(s).utf16 { seed = (seed ^ UInt32(unit)) &* 16_777_619 }
    return Int(seed)
}

// MARK: - callPrice

/// The price of calling: only pots the hero can win, uncalled refunds excluded.
public struct CallPrice: Equatable, Sendable {
    /// Pots after the call that the hero is eligible for, in pot order.
    public var pots: [Pot]
    public var contestable: Int
    public var cost: Int
    public var refundBefore: Int
    public var refundAfter: Int
    /// Break-even pot equity: `cost / contestable`, or 0.
    public var required: Double
    /// No later betting can follow this call.
    public var closing: Bool
}

private func partition(_ s: ReviewDecision, heroExtra: Int) throws -> PotSet {
    let players = s.players.map { p -> Player in
        var q = Player(id: p.id, name: p.name)
        q.total = p.total + (p.id == 0 ? heroExtra : 0)
        q.folded = p.folded
        return q
    }
    return try partitionPots(Game(players: players, dealer: 0))
}

// A call has different eligible opponents in each side pot. Exclude uncalled
// refunds and compare its extra cost with what folding would return already.
public func callPrice(_ s: ReviewDecision) throws -> CallPrice {
    let original = try partition(s, heroExtra: 0)
    let projected = try partition(s, heroExtra: s.legal.callAmount)
    let refundBefore = original.refunds.filter { $0.id == 0 }.reduce(0) { $0 + $1.amount }
    let refundAfter = projected.refunds.filter { $0.id == 0 }.reduce(0) { $0 + $1.amount }
    let pots = projected.pots.filter { $0.eligible.contains(0) }
    let contestable = pots.reduce(0) { $0 + $1.amount }
    let cost = max(0, s.legal.callAmount - refundAfter + refundBefore)
    let otherPending = s.pending.contains { id in
        id != 0 && !(s.seat(id)?.folded ?? false) && !(s.seat(id)?.allin ?? false)
    }
    let live = s.players.filter { $0.id != 0 && !$0.folded }
    let allInCovered = s.legal.callAmount == s.stack &&
        live.allSatisfy { $0.allin || $0.total >= s.total + s.legal.callAmount }
    return CallPrice(
        pots: pots, contestable: contestable, cost: cost, refundBefore: refundBefore, refundAfter: refundAfter,
        required: contestable != 0 ? Double(cost) / Double(contestable) : 0,
        closing: (s.street == 3 && !otherPending) || allInCovered || live.allSatisfy(\.allin))
}

// MARK: - Range model

private func drawPair(_ count: Int, _ rng: RandomSource) -> (Int, Int) {
    let a = Int((rng.next() * Double(count)).rounded(.down))
    var b = Int((rng.next() * Double(count - 1)).rounded(.down))
    if b >= a { b += 1 }
    return (a, b)
}

private let RAISE_WEIGHTS: [[Double]] = [[0.04, 0.2, 1.5, 6], [0.15, 0.7, 3, 6], [1, 2, 4, 6]]
private let CALL_WEIGHTS: [[Double]] = [[0.08, 0.3, 2, 6], [0.2, 0.8, 3, 6], [1, 2, 3, 4]]

/// Relative weight (0, 6] of an opponent holding `pair`, from that opponent's
/// public actions only.
public func rangeWeight(_ pair: [Card], _ s: ReviewDecision, opponent: Int) -> Double {
    let prefix = s.history.filter { $0.street == 0 }
    let informative = prefix.indices.last { prefix[$0].id == opponent && [.call, .raise].contains(prefix[$0].action) }
    var preWeight = 1.0
    if let i = informative {
        let level = prefix[...i].filter { $0.action == .raise && $0.amount > 50 }.count
        let tables = prefix[i].action == .raise ? RAISE_WEIGHTS : CALL_WEIGHTS
        preWeight = tables[level >= 3 ? 0 : level == 2 ? 1 : 2][startingTier(pair)]
    }
    if s.street == 0 { return preWeight }
    guard let current = s.history.last(where: {
        $0.street == s.street && $0.id == opponent && [.call, .raise].contains($0.action)
    }) else { return preWeight }
    let cards = pair + s.board
    let score = evaluate(cards).score[0]
    let suitedDraw = (0..<4).contains { suit in
        cards.filter { $0.suit == suit }.count == 4 && pair.contains { $0.suit == suit }
    }
    var madeWeight = 1.0
    if current.action == .raise {
        madeWeight = score >= 4 ? 6 : score >= 2 ? 5 : score == 1 ? 3 : suitedDraw ? 2 : 1
    } else if Double(current.amount) >= max(100, Double(s.pot) * 0.2) {
        madeWeight = score >= 2 ? 5 : score == 1 ? 3 : suitedDraw ? 2 : 1
    } else {
        return preWeight
    }
    // Prior preflop information remains relevant; max stays at six for rejection sampling.
    return informative != nil ? (preWeight * madeWeight) / 6 : madeWeight
}

// MARK: - sampleValue

public enum EquityMethod: String, Sendable {
    case sampling, enumeration
}

/// Expected share of the contestable pots returned to the hero.
public struct EquityEstimate: Equatable, Sendable {
    public var equity: Double
    /// Hoeffding-style sampling band; 0 for enumeration.
    public var margin: Double
    /// `equity * contestable - cost`, in chips.
    public var ev: Double
    /// `nil` when nothing is contestable (no estimate was made).
    public var method: EquityMethod?
    /// Trials, or the number of enumerated combinations.
    public var samples: Int?
}

/// `Math.log(80)`, as a literal so no platform `log` can differ in the last bit.
let LOG_80 = 4.382026634673881

public func sampleValue(_ s: ReviewDecision, _ price: CallPrice, trials: Int, weighted: Bool) -> EquityEstimate {
    if price.contestable == 0 { return EquityEstimate(equity: 0, margin: 0, ev: 0, method: nil, samples: nil) }
    let rng = seedRandom(snapshotSeed(s) + (weighted ? 7919 : 0))
    let known = Set((s.hole + s.board).map(\.key))
    let available = deckOfCards().filter { !known.contains($0.key) }
    let opponents = s.players.filter { $0.id != 0 && !$0.folded }
    let contestable = Double(price.contestable)
    if s.board.count == 5 && opponents.count == 1 {
        let hero = evaluate(s.hole + s.board).score
        let opponent = opponents[0].id
        var weightSum = 0.0, valueSum = 0.0, combinations = 0
        for i in 0..<(available.count - 1) {
            for j in (i + 1)..<available.count {
                let pair = [available[i], available[j]]
                let c = compare(hero, evaluate(pair + s.board).score)
                var share = 0.0
                for pot in price.pots {
                    share += Double(pot.amount) * (!pot.eligible.contains(opponent) ? 1 : c > 0 ? 1 : c == 0 ? 0.5 : 0)
                }
                let fraction = share / contestable
                let weight = weighted ? rangeWeight(pair, s, opponent: opponent) : 1
                weightSum += weight
                valueSum += fraction * weight
                combinations += 1
            }
        }
        let equity = valueSum / weightSum
        return EquityEstimate(equity: equity, margin: 0, ev: equity * contestable - Double(price.cost),
                              method: .enumeration, samples: combinations)
    }
    var sum = 0.0
    for _ in 0..<max(0, trials) {
        var pool = available
        var holes: [Int: [Card]] = [:]
        for opponent in opponents {
            var (a, b) = drawPair(pool.count, rng)
            if weighted {
                while rng.next() >= rangeWeight([pool[a], pool[b]], s, opponent: opponent.id) / 6 {
                    (a, b) = drawPair(pool.count, rng)
                }
            }
            holes[opponent.id] = [pool[a], pool[b]]
            pool.remove(at: max(a, b))
            pool.remove(at: min(a, b))
        }
        var board = s.board
        while board.count < 5 { board.append(pool.remove(at: Int((rng.next() * Double(pool.count)).rounded(.down)))) }
        let hero = evaluate(s.hole + board).score
        var scores: [Int: [Int]] = [:]
        for p in opponents { scores[p.id] = evaluate(holes[p.id]! + board).score }
        var returned = 0.0
        for pot in price.pots {
            var ties = 1, lost = false
            for id in pot.eligible where id != 0 {
                let c = compare(scores[id] ?? [], hero)
                if c > 0 {
                    lost = true
                    break
                }
                if c == 0 { ties += 1 }
            }
            if !lost { returned += Double(pot.amount) / Double(ties) }
        }
        sum += returned / contestable
    }
    let equity = sum / Double(trials)
    let margin = min(1, (LOG_80 / Double(2 * trials)).squareRoot())
    return EquityEstimate(equity: equity, margin: margin, ev: equity * contestable - Double(price.cost),
                          method: .sampling, samples: trials)
}
