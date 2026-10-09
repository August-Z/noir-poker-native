/// English UI copy produced by the table session (wording from the master copy
/// catalog; identical to the Kotlin `SessionCopy`). Engine-generated text
/// (action captions, logs, results, hand and mood labels) comes from
/// `EngineCopy` and is never rewritten here.
public enum SessionCopy {
    private static func g(_ n: Int) -> String { formatChips(n) }

    public static let streets = ["Preflop", "Flop", "Turn", "River"]
    public static func street(_ index: Int) -> String? { streets.indices.contains(index) ? streets[index] : nil }

    // Header and table meta.
    public static func tableTag(_ count: Int) -> String { "\(count)-MAX" }
    public static func tableSize(_ count: Int) -> String { "\(count)-Handed No-Limit" }
    public static func handNumber(_ hand: Int) -> String {
        let s = String(hand)
        return s.count >= 2 ? s : String(repeating: "0", count: 2 - s.count) + s
    }
    public static func handHeading(_ hand: Int) -> String { "Hand \(handNumber(hand))" }
    public static let streetReady = "Ready to Deal"
    public static let streetDone = "Hand Over"
    public static func replayBadge(_ n: Int) -> String { "Replay \(n)" }
    public static let replayNote = "Replaying this hand · Same hole cards and deal order; the original settlement has been reversed."

    // Board.
    public static let undealtCard = "Undealt community card"
    public static let boardSlotGlyphs = ["♠", "♣", "♥", "♦", "♠"]
    public static let captionPractice = "Practice runout · Five community cards; settlement unchanged"
    public static let captionShowdownFolded = "Showdown · Opponents show their cards"
    public static let captionShowdownHero = "Showdown · Highlighted cards make your best hand"
    public static let captionPreflop = "Waiting for the flop"
    public static let captionFlop = "FLOP · Three community cards"
    public static let captionTurn = "TURN · The fourth community card"
    public static let captionRiver = "RIVER · Final decision"
    public static func sidePots(_ k: Int) -> String { k == 1 ? "1 Side Pot" : "\(k) Side Pots" }
    public static func captionMultiPot(done: Bool, main: Int, sideCount: Int) -> String {
        (done ? "Settled separately" : "Current bets") + " · Main Pot \(g(main)) + \(sidePots(sideCount))"
    }
    public static let potButtonSingle = "Pot · Details"
    public static func potButtonMulti(_ sideCount: Int) -> String { "Total Pot · \(sidePots(sideCount))" }
    public static let potDetailsA11y = "View pot details"

    // Positions.
    public static let positionNames: [String: String] = [
        "BTN": "Button (Dealer)",
        "SB": "Small Blind",
        "BB": "Big Blind",
        "UTG": "Under the Gun",
        "UTG+1": "Under the Gun +1",
        "MP": "Middle Position",
        "LJ": "Lojack",
        "HJ": "Hijack",
        "CO": "Cutoff",
    ]

    // Seats.
    public static let avatarLetters = ["YOU", "M", "A", "R", "K", "L", "T", "J", "L"]
    public static let thinking = "Thinking"
    public static let noAction = "No Action"
    public static let waiting = "Waiting"
    public static func meaningCall(added: Int, streetTotal: Int) -> String { "Added \(g(added)) · \(g(streetTotal)) in this round" }
    public static func meaningOther(_ actionText: String, _ amount: Int) -> String { "\(actionText) · \(g(amount)) in this round" }
    public static func winnerA11y(_ name: String, _ amount: Int) -> String { "\(name) wins \(g(amount)) chips" }
    public static func heroWinnerA11y(_ amount: Int) -> String { "You win \(g(amount)) chips" }
    public static func winnerTitle(_ label: String, _ amount: Int) -> String { "\(label) · Won \(g(amount)) chips" }
    public static let winnerFallback = "Winner"
    public static func avatarTitle(_ name: String, _ short: String, _ mood: String) -> String {
        "\(name) · \(short) (training archetype) · Simulated mood: \(mood)"
    }
    public static let cardBackA11y = "Opponent's hole card"
    public static func styleTitle(_ profileName: String, _ tag: String) -> String { "\(profileName) · \(tag)" }
    public static func styleA11y(_ name: String, _ profileName: String) -> String { "\(name)'s style this hand: \(profileName)" }
    public static let peekHide = "Hide Hole Cards"
    public static let peekShow = "Show Hole Cards"
    public static func peekA11y(reveal: Bool, _ name: String) -> String { reveal ? "Hide \(name)'s hole cards" : "Show \(name)'s hole cards" }
    public static func seatActionA11y(_ name: String) -> String { "\(name)'s last action" }

    // Seat action labels (parsed from engine action text).
    public static let labelShortAllIn = "Short All-In"
    public static let labelAllIn = "All-In"
    public static let recentVerbs = ["open to": "Open", "raise to": "Raise", "bet to": "Bet"]
    public static let bareRaise = "Raise"

    // Hero.
    public static let heroName = "You"
    public static let heroFoldedPrefix = "Folded · "
    public static let heroTurnYours = "Your Turn"
    public static let heroTurnFolded = "Folded"
    public static let heroTurnAllIn = "All-In"
    public static let heroLastActionA11y = "Your last action"

    // Session panel.
    public static let chipsUnit = "CHIPS"
    public static func sessionChange(_ diff: Int) -> String { (diff >= 0 ? "+" : "") + g(diff) + " chips · Net this session" }
    public static let sessionChangeInitial = "Build experience, starting this hand"
    public static let statEmpty = "—"
    public static func winRate(_ pct: Int) -> String { "\(pct)%" }

    // Activity.
    public static let activityLive = "LIVE"
    public static let activityFinished = "FINISHED"
    public static func personaSuffix(_ short: String) -> String { " (\(short))" }

    // Action panel.
    public static let fold = "Fold"
    public static let check = "Check"
    public static let call = "Call"
    public static let callAllIn = "Call All-In"
    public static let finishHand = "Finish Hand"
    public static let finishHandBusy = "Dealing…"
    public static let finishHandTitle = "Fast-forward the remaining opponent actions and settle the hand"
    public static let nextHand = "Next Hand"
    public static let nextHandRebuy = "Rebuy and Keep Practicing"
    public static let replayHand = "↺ Replay Hand"
    public static let replayHandTitle = "Restore this hand's starting stacks, hole cards, and deal order, and reverse the original settlement"
    public static let reviewHand = "Review This Hand"
    public static let betSliderLabel = "Raise to"
    public static let betSliderA11y = "Raise-to amount"
    public static func presetLabel(_ preset: BetPreset) -> String {
        switch preset {
        case .min: return "Min"
        case .halfPot: return "½ Pot"
        case .pot: return "Pot"
        case .allIn: return "All-In"
        }
    }

    // Decision strip.
    public static let decisionCanCheck = "Your turn. You can check or bet."
    public static func decisionToCall(_ amount: Int) -> String { "Your turn. \(g(amount)) chips to call." }
    public static let decisionNotReopened = " Raising is not reopened this round; you can only call or fold."
    public static let decisionShowdownSettling = "Showdown · Cards are face up; settling each pot…"
    public static let decisionAllInRunout = "All-in action complete · Cards are face up; waiting for the remaining community cards…"
    public static let decisionDealingNext = "Betting round complete; dealing the next community cards…"
    public static let opponentFallback = "An opponent"
    public static func decisionObserve(_ name: String) -> String { "\(name) is acting. You can watch the rest of this hand." }
    public static func decisionWait(_ name: String) -> String { "\(name) is thinking…" }

    // Coach.
    public static let coachOn = "On"
    public static let coachOff = "Off"
    public static let coachStageDone = "Hand Recap"
    public static func coachStage(_ street: String) -> String { "\(street) Strategy" }
    public static let tipDoneFolded =
        "Folding is part of good decision-making too. Look at the cards opponents showed and think back over the betting in this hand."
    public static func tipDoneShowdown(_ label: String) -> String {
        "Your best hand was \(label). As you review, ask: on which street did opponents start raising? Did the community cards change how strong your hand was?"
    }
    public static let tipDoneUncontested = "Getting opponents to fold wins pots too. Next hand, keep watching position and bet sizing."
    public static let tipPrePair = "A pocket pair can flop a set. With a small pair facing a big raise, weigh the cost of calling."
    public static let tipPreBroadway =
        "Two high cards make a solid starting hand. Raising narrows opponents' ranges, but watch out for big raises ahead of you."
    public static let tipPreSuited =
        "Suited hole cards add potential, but they don't justify calling any price. Watch how connected the cards are and where you act from."
    public static let tipPreOther =
        "You don't have to play every hand. The earlier you act, the more selective you should be; later positions let you use more information."
    public static func tipMadeStrong(_ label: String) -> String {
        "You've made \(label). Consider betting for value, but watch for stronger hands the board makes possible."
    }
    public static func tipMadePair(_ label: String) -> String {
        "You have \(label). Against several opponents, be careful facing repeated big raises; one pair doesn't always hold up."
    }
    public static let tipUnpaired =
        "No pair yet. Don't just ask whether you might hit; consider the price to call and how strongly opponents are betting."
    public static func tipPriceSuffix(_ pct: Int) -> String { " This call is about \(pct)% of the pot you can win." }

    /// Hand-category labels as nouns inside coach sentences, keyed by the engine label.
    public static let handNouns: [String: String] = [
        "High Card": "high card",
        "One Pair": "one pair",
        "Two Pair": "two pair",
        "Three of a Kind": "three of a kind",
        "Straight": "a straight",
        "Flush": "a flush",
        "Full House": "a full house",
        "Four of a Kind": "four of a kind",
        "Straight Flush": "a straight flush",
        "Royal Flush": "a royal flush",
        "Pocket Pair": "a pocket pair",
    ]
    public static func handNoun(_ label: String) -> String { handNouns[label] ?? label }

    // Settings.
    public static func tableChangeNote(_ n: Int) -> String { "Switches to \(n) players next hand · Stacks reset to 5,000 and stats start over" }
    public static func playerCountOption(_ n: Int) -> String { "\(n) players" }
    public static func difficultyLabel(_ d: Difficulty) -> String {
        switch d {
        case .easy: return "Easy"
        case .normal: return "Standard"
        case .hard: return "Advanced"
        }
    }
    public static let soundOnA11y = "Turn sound on"
    public static let soundOffA11y = "Turn sound off"
    public static let soundStateOn = "Sound on"
    public static let soundStateOff = "Sound off"

    // Opponent settings.
    public static let opponentsSummaryPending = "Applies Next Hand"
    public static func opponentsSummaryNamed(_ n: Int) -> String { n == 1 ? "1 Styled Opponent" : "\(n) Styled Opponents" }
    public static let opponentsSummaryBalanced = "Balanced"
    public static let opponentsChangeNote =
        "Opponent styles saved and will apply next hand. This hand and any replay use the current styles shown at each seat."
    public static let opponentsSaveNote =
        "Saved on this device and restored next time. Changes apply from the next hand; replays keep the original opponents."
    public static let profileBadge = "Training Archetype"
    public static func profileSizing(_ lo: Int, _ hi: Int) -> String { "Typical postflop bet: \(lo)–\(hi)% of the pot" }
    public static func profileSizingCell(_ lo: Int, _ hi: Int) -> String { "\(lo)–\(hi)%" }
    public static let rosterOffTable = "Not seated"
    public static func rosterSeat(_ id: Int) -> String { "Seat \(id)" }
    public static let moodSteady = "Steady"
    public static func rosterSelectA11y(_ name: String) -> String { "\(name)'s training style" }
    public static func rosterCurrentStyle(_ short: String) -> String { "Style this hand: \(short)" }
    public static let rosterNotSeated = "Not seated yet; uses the saved next-hand setting"
    public static let rosterObservedTitle = "Hands this bot has completed this session; restarts from zero after a style change"
    public static func rosterObserved(_ hands: Int, _ vpip: String, _ pfr: String) -> String {
        (hands == 1 ? "1 hand" : "\(hands) hands") + " · VPIP \(vpip) · PFR \(pfr)"
    }

    // Pot dialog.
    public static let potEligHero = "You're eligible"
    public static let potEligNotIn = "You're not in this pot"
    public static let potEligOverAllIn = "Above your all-in amount"
    public static let potEligNotYet = "You haven't matched this pot yet"
    public static let potContribFolded = " · Folded"
    public static let potContribAllIn = " · All-In"
    public static let potTitleSettled = "Hand Settlement"
    public static let potTitleLive = "Main Pot and Side Pots"
    public static let potNoteLive =
        "Amounts reflect chips committed so far; players yet to act must call to stay eligible. Only all-in amounts create side pots; any uncalled portion is waiting to be called or refunded."
    public static let listJoiner = ", "
    public static func potSplitTotal(_ amount: Int) -> String { "\(g(amount)) chips · Split" }
    public static func potAwardWinner(_ name: String) -> String { "\(name) wins" }
    public static func potAwardAmount(_ amount: Int) -> String { "+\(g(amount))" }
    public static let chips = "chips"
    public static let potDistributionSummary = "View Distribution Details"
    public static func potDistributionEligibility(_ label: String, _ names: String) -> String { "\(label) · Eligible at settlement: \(names)" }
    public static let potContribHeading = "Contributions to This Pot"
    public static let potOddChipNote = "Odd chips go out in seat order starting left of the button."
    public static func potLiveCount(_ n: Int) -> String { n == 1 ? " · 1 player" : " · \(n) players" }
    public static func potLiveParticipants(_ names: String) -> String { "Eligible: \(names)" }
    public static let potContribSummary = "View Contributions"
    public static func refundDoneA11y(_ name: String, _ amount: Int) -> String { "\(name)'s uncalled \(g(amount)) chips were returned" }
    public static func refundDone(_ name: String) -> String { "Uncalled bet returned · \(name)" }
    public static func refundLive(_ name: String) -> String { "To be called or returned · \(name)" }

    // Showdown.
    private static let rankWords = [
        2: "Two", 3: "Three", 4: "Four", 5: "Five", 6: "Six", 7: "Seven", 8: "Eight",
        9: "Nine", 10: "Ten", 11: "Jack", 12: "Queen", 13: "King", 14: "Ace",
    ]
    private static let rankPlurals = [
        2: "Twos", 3: "Threes", 4: "Fours", 5: "Fives", 6: "Sixes", 7: "Sevens", 8: "Eights",
        9: "Nines", 10: "Tens", 11: "Jacks", 12: "Queens", 13: "Kings", 14: "Aces",
    ]
    public static func rankWord(_ r: Int) -> String { rankWords[r]! }
    public static func rankPlural(_ r: Int) -> String { rankPlurals[r]! }
    public static func sdHigh(_ r: Int) -> String { "\(rankWord(r))-high · Kickers compared in order" }
    public static func sdPair(_ r: Int) -> String { "Pair of \(rankPlural(r))" }
    public static func sdTwoPair(_ r1: Int, _ r2: Int) -> String { "\(rankPlural(r1)) and \(rankPlural(r2))" }
    public static func sdTrips(_ r: Int) -> String { "Three \(rankPlural(r))" }
    public static func sdStraight(_ r: Int) -> String { "\(rankWord(r))-high straight" }
    public static func sdFlush(_ suit: String, _ r: Int) -> String { "\(suit) flush · \(rankWord(r))-high" }
    public static func sdFullHouse(_ r1: Int, _ r2: Int) -> String { "\(rankPlural(r1)) full of \(rankPlural(r2))" }
    public static func sdQuads(_ r: Int) -> String { "Four \(rankPlural(r))" }
    public static let sdRoyal = "10 · J · Q · K · A of one suit"
    public static func sdStraightFlush(_ suit: String, _ r: Int) -> String { "\(suit) straight flush · \(rankWord(r))-high" }
    public static func sdContext(_ n: Int, multiPot: Bool) -> String {
        "\(n) players at showdown" + (multiPot ? " · Main Pot and Side Pots settled separately" : "")
    }
    public static func sdPlayerA11y(_ name: String, _ label: String) -> String { "\(name) · \(label)" }
    public static func sdWon(_ amount: Int) -> String { "Won +\(g(amount))" }
    public static let sdNoPot = "No pot won"
    public static func sdAwardItem(_ pot: String, split: Bool, _ amount: Int) -> String {
        pot + (split ? " · Split" : "") + " +\(g(amount))"
    }
    public static let sdBestFive = "Best five cards"
}
