// Pure projections of engine state used by the render state. None of these
// mutate the game or draw random numbers.

/// A run of display text; persona suffixes are marked so the UI can style them.
public struct TextSegment: Equatable, Sendable {
    public var text: String
    public var isPersona: Bool
    public init(_ text: String, isPersona: Bool = false) {
        self.text = text
        self.isPersona = isPersona
    }
}

public extension Array where Element == TextSegment {
    var plainText: String { map(\.text).joined() }
}

private func isWordCharacter(_ c: Character) -> Bool {
    guard c.isASCII, let a = c.asciiValue else { return false }
    return (a >= 48 && a <= 57) || (a >= 65 && a <= 90) || (a >= 97 && a <= 122) || a == 95
}

/// The reference `createActivityFormatter(players)`: every whole-word mention of
/// an opponent whose style is not Balanced gets the style's short name as a
/// suffix, e.g. `Alex (ST Wang): Call 50`. The identities are captured when the
/// formatter is created, so saved-but-pending settings never relabel the current
/// hand. The hero is never annotated.
///
/// Matching follows JavaScript's `\b(names)\b(?![（(])` with ASCII word
/// boundaries, implemented without regular expressions.
public struct ActivityFormatter {
    /// `(name, persona short name)` in seat order (the reference's alternation order).
    private let personas: [(name: [Character], short: String)]

    public init(_ players: [Player]) {
        personas = players
            .filter { $0.id != 0 }
            .map { (name: $0.name, profile: getBotProfile($0.botProfile)) }
            .filter { $0.profile.id != "balanced" }
            .map { (name: Array($0.name), short: $0.profile.short) }
    }

    private func match(_ chars: [Character], at i: Int) -> (end: Int, short: String)? {
        if i > 0 && isWordCharacter(chars[i - 1]) { return nil }
        for persona in personas {
            let end = i + persona.name.count
            guard end <= chars.count, Array(chars[i..<end]) == persona.name else { continue }
            if end < chars.count && isWordCharacter(chars[end]) { continue }
            // Skip names that are already annotated: `Alex (ST Wang)` or `Alex（…）`.
            let next = end < chars.count ? chars[end] : nil
            if next == "(" || next == "（" { continue }
            if next == " ", end + 1 < chars.count, chars[end + 1] == "(" || chars[end + 1] == "（" { continue }
            return (end, persona.short)
        }
        return nil
    }

    /// `skipLeadingStreetName`: in English the bot "River" collides with the
    /// street name in `River · 7♠`; a street log's leading street name is never a
    /// player mention.
    public func format(_ text: String, skipLeadingStreetName: Bool = false) -> [TextSegment] {
        if personas.isEmpty { return [TextSegment(text)] }
        let chars = Array(text)
        var out: [TextSegment] = []
        var plain = ""
        var i = 0
        while i < chars.count {
            if let m = match(chars, at: i) {
                let name = String(chars[i..<m.end])
                if skipLeadingStreetName && i == 0 && text.hasPrefix(name + " · ") {
                    plain += name
                } else {
                    out.append(TextSegment(plain + name))
                    out.append(TextSegment(SessionCopy.personaSuffix(m.short), isPersona: true))
                    plain = ""
                }
                i = m.end
            } else {
                plain.append(chars[i])
                i += 1
            }
        }
        if !plain.isEmpty { out.append(TextSegment(plain)) }
        return out.isEmpty ? [TextSegment(text)] : out
    }

    public func formatLog(_ entry: LogEntry) -> [TextSegment] {
        format(entry.text, skipLeadingStreetName: entry.type == .street)
    }
}

/// The seat's action chip (`seatAction`): a label, an optional amount and its meaning.
public struct ActionChip: Equatable, Sendable {
    public var label: String
    public var amount: Int?
    public var amountText: String?
    /// The tooltip / accessibility hint for the amount.
    public var meaning: String?
    /// The seat is the current actor and is deciding (blinking dots).
    public var isDeciding: Bool

    public init(_ label: String, amount: Int? = nil, amountText: String? = nil, meaning: String? = nil, isDeciding: Bool = false) {
        self.label = label
        self.amount = amount
        self.amountText = amountText
        self.meaning = meaning
        self.isDeciding = isDeciding
    }
}

private let actionVerbs: Set<String> = ["SB", "BB", "Call", "short all-in to", "all-in to", "open to", "raise to", "bet to", "All-In"]

/// Parses `^(?:(\d+-bet) )?(verb) ([\d,]+)$` from an engine action text.
private func parseActionText(_ action: String) -> (level: String, verb: String, amount: Int)? {
    guard let space = action.lastIndex(of: " ") else { return nil }
    let amountText = action[action.index(after: space)...]
    guard !amountText.isEmpty, amountText.allSatisfy({ ($0 >= "0" && $0 <= "9") || $0 == "," }),
          let amount = Int(amountText.filter { $0 != "," }) else { return nil }
    let head = String(action[..<space])
    // With an ordinal prefix first (`3-bet raise to`), then without.
    if let dash = head.firstRange(of: "-bet "), dash.lowerBound > head.startIndex,
       head[..<dash.lowerBound].allSatisfy({ $0 >= "0" && $0 <= "9" }) {
        let verb = String(head[dash.upperBound...])
        if actionVerbs.contains(verb) { return (String(head[..<dash.lowerBound]) + "-bet", verb, amount) }
    }
    if actionVerbs.contains(head) { return ("", head, amount) }
    return nil
}

/// The reference `seatAction(p, {recent})`. Seats show the current-street action
/// during play and the retained last action after settlement; the hero area
/// (`recent` = true) always shows the retained last action, with the street.
public func seatActionChip(_ g: Game, _ p: Player, recent: Bool = false) -> ActionChip {
    if !recent && g.actor == p.id { return ActionChip(SessionCopy.thinking, isDeciding: true) }
    let retained = recent || g.phase == .done ? p.lastAction : nil
    let action = retained?.text ?? p.action
    guard let match = parseActionText(action) else {
        return ActionChip(action.isEmpty ? (g.phase == .done ? SessionCopy.noAction : SessionCopy.waiting) : action)
    }
    let label: String
    if !match.level.isEmpty {
        switch match.verb {
        case "short all-in to": label = "\(match.level) \(SessionCopy.labelShortAllIn)"
        case "all-in to": label = "\(match.level) \(SessionCopy.labelAllIn)"
        default: label = recent ? "\(match.level) \(SessionCopy.recentVerbs[match.verb] ?? match.verb)" : match.level
        }
    } else if match.verb == "raise to" {
        label = SessionCopy.bareRaise
    } else {
        label = match.verb
    }
    let prefix = recent && retained != nil ? (SessionCopy.street(retained!.street).map { "\($0) · " } ?? "") : ""
    let meaning = prefix + (match.verb == "Call"
        ? SessionCopy.meaningCall(added: match.amount, streetTotal: retained?.bet ?? p.bet)
        : SessionCopy.meaningOther(action, match.amount))
    return ActionChip(label, amount: match.amount, amountText: formatChips(match.amount), meaning: meaning)
}

/// The coaching hint (`updateCoach`), computed whether or not hints are shown.
public func coachTip(_ g: Game) -> String {
    let p = g.players[0]
    let e = evaluate(p.hole + g.board)
    var tip: String
    if g.phase == .done {
        tip = p.folded ? SessionCopy.tipDoneFolded
            : g.showdown ? SessionCopy.tipDoneShowdown(SessionCopy.handNoun(e.label))
            : SessionCopy.tipDoneUncontested
    } else if g.street == 0 {
        let a = p.hole.first, b = p.hole.count > 1 ? p.hole[1] : nil
        if a?.rank == b?.rank { tip = SessionCopy.tipPrePair }
        else if let a, let b, a.rank >= 11 && b.rank >= 11 { tip = SessionCopy.tipPreBroadway }
        else if a?.suit == b?.suit { tip = SessionCopy.tipPreSuited }
        else { tip = SessionCopy.tipPreOther }
    } else if e.score[0] >= 3 {
        tip = SessionCopy.tipMadeStrong(SessionCopy.handNoun(e.label))
    } else if e.score[0] >= 1 {
        tip = SessionCopy.tipMadePair(SessionCopy.handNoun(e.label))
    } else {
        tip = SessionCopy.tipUnpaired
    }
    let legal = legalActions(g, 0)
    if legal.enabled && legal.toCall > 0 {
        let pct = Int(jsRound(Double(legal.callAmount) / Double(contestableAfterCall(g, 0, legal.callAmount)) * 100))
        tip += SessionCopy.tipPriceSuffix(pct)
    }
    return tip
}

public func coachStage(_ g: Game) -> String {
    g.phase == .done ? SessionCopy.coachStageDone : SessionCopy.coachStage(SessionCopy.street(g.street) ?? "")
}

/// Showdown card motion (`HAND_MOTIONS`, plus `royal`). `rawValue` is the reference class suffix.
public enum HandMotion: String, Sendable, CaseIterable {
    case high, pair
    case twoPair = "two-pair"
    case trips, straight, flush
    case fullHouse = "full-house"
    case quads
    case straightFlush = "straight-flush"
    case royal
}

public struct ShowdownAward: Equatable, Sendable {
    public var pot: String
    public var amount: Int
    public var split: Bool
    public init(pot: String, amount: Int, split: Bool) {
        self.pot = pot
        self.amount = amount
        self.split = split
    }
}

/// One player's best five at showdown (`handScene` in `showdown.js`). `cards` are
/// in display order (groups first, straights ascending with a wheel ace low) and
/// `highlights` marks the cards that make the category.
public struct HandScene: Equatable, Sendable {
    public var id: Int
    public var name: String
    public var label: String
    public var motion: HandMotion
    public var cards: [Card]
    public var highlights: [Bool]
    public var explanation: String
    /// Awards to this player in pot order (empty for a winning-scene entry).
    public var awards: [ShowdownAward] = []
    public var amount = 0
    /// For `winningScenes` entries only: the pot label and whether it was split.
    public var pot: String? = nil
    public var split = false
}

public func handScene(_ g: Game, _ p: Player) -> HandScene {
    let rank = evaluate(p.hole + g.board)
    let score = rank.score
    let category = score[0]
    let royal = category == 8 && score[1] == 14
    var counts: [Int: Int] = [:]
    for c in rank.cards { counts[c.rank, default: 0] += 1 }
    let wheel = score.count > 1 && score[1] == 5
    // A stable sort, like JavaScript's Array.prototype.sort: ties keep input order.
    let indexed = Array(rank.cards.enumerated())
    let sorted: [(offset: Int, element: Card)]
    if category == 4 || category == 8 {
        func key(_ c: Card) -> Int { wheel && c.rank == 14 ? 1 : c.rank }
        sorted = indexed.sorted { key($0.element) != key($1.element) ? key($0.element) < key($1.element) : $0.offset < $1.offset }
    } else {
        sorted = indexed.sorted {
            let ca = counts[$0.element.rank]!, cb = counts[$1.element.rank]!
            if ca != cb { return ca > cb }
            if $0.element.rank != $1.element.rank { return $0.element.rank > $1.element.rank }
            return $0.offset < $1.offset
        }
    }
    let cards = sorted.map(\.element)
    let highlights = cards.map { c -> Bool in
        switch category {
        case 0: return c.rank == score[1]
        case 1, 2, 3, 7: return counts[c.rank]! > 1
        default: return true
        }
    }
    let explanation: String
    switch category {
    case 0: explanation = SessionCopy.sdHigh(score[1])
    case 1: explanation = SessionCopy.sdPair(score[1])
    case 2: explanation = SessionCopy.sdTwoPair(score[1], score[2])
    case 3: explanation = SessionCopy.sdTrips(score[1])
    case 4: explanation = SessionCopy.sdStraight(score[1])
    case 5: explanation = SessionCopy.sdFlush(cards[0].symbol, score[1])
    case 6: explanation = SessionCopy.sdFullHouse(score[1], score[2])
    case 7: explanation = SessionCopy.sdQuads(score[1])
    default: explanation = royal ? SessionCopy.sdRoyal : SessionCopy.sdStraightFlush(cards[0].symbol, score[1])
    }
    return HandScene(id: p.id, name: p.name, label: rank.label,
                     motion: royal ? .royal : HandMotion.allCases[category],
                     cards: cards, highlights: highlights, explanation: explanation)
}

/// One scene per non-folded player, in seat order; empty unless settled at a five-card showdown.
public func showdownScenes(_ g: Game) -> [HandScene] {
    guard g.phase == .done, g.showdown, g.board.count == 5 else { return [] }
    return g.players.filter { !$0.folded }.map { p in
        let awards = g.pots.flatMap { pot in
            pot.awards.filter { $0.id == p.id }.map { ShowdownAward(pot: pot.label, amount: $0.amount, split: pot.awards.count > 1) }
        }
        var scene = handScene(g, p)
        scene.awards = awards
        scene.amount = awards.reduce(0) { $0 + $1.amount }
        return scene
    }
}

/// One scene per pot award (`winningScenes`, used by tests).
public func winningScenes(_ g: Game) -> [HandScene] {
    guard g.phase == .done, g.showdown, g.board.count == 5 else { return [] }
    return g.pots.flatMap { pot in
        pot.awards.map { a in
            var scene = handScene(g, g.players[a.id])
            scene.pot = pot.label
            scene.amount = a.amount
            scene.split = pot.awards.count > 1
            return scene
        }
    }
}
