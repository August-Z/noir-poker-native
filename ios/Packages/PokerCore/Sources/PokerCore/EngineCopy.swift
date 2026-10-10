/// Every user-visible string the engine produces. The reference produces these
/// in Chinese; this is the English translation. `scripts/reference-copy.mjs` is
/// the authority for engine copy (the fixtures carry its output), so keep this
/// table aligned with it. Every chip amount and hand number uses en-US grouping.
public enum EngineCopy {
    public static let heroName = "You"
    public static let botNames = ["Mia", "Alex", "River", "Kai", "Luna", "Theo", "Jade", "Leo"]

    public static let rankNames = [
        "High Card", "One Pair", "Two Pair", "Three of a Kind", "Straight",
        "Flush", "Full House", "Four of a Kind", "Straight Flush",
    ]
    public static let royalFlush = "Royal Flush"
    public static let pocketPair = "Pocket Pair"

    public static func errorMessage(_ code: PokerError.Code) -> String {
        switch code {
        case .invalidPlayerCount: return "Table size must be 5–9 players."
        case .settingsLocked: return "Opponent settings take effect at the start of the next hand."
        case .handInProgress: return "The current hand isn't finished yet."
        case .replayUnavailable: return "You can replay a hand after it ends; the original deal is required."
        case .notYourTurn: return "It's not your turn yet."
        case .unknownAction: return "Unknown table action."
        case .cannotCheck: return "You must call; checking isn't allowed."
        case .illegalRaise: return "Choose a legal raise-to amount."
        case .roundNotFinished: return "This betting round isn't finished."
        case .handNotSettled: return "Settle this hand first."
        case .showdownNeedsBoard: return "A showdown settlement requires all five community cards."
        case .alreadySettled: return "This hand has already been settled."
        case .noEligiblePlayer: return "No eligible player for this pot."
        case .potMismatch: return "Pot distribution doesn't add up."
        case .invalidTrials: return "Equity trial count must be a positive integer."
        case .botCannotAct: return "The bot can't act right now."
        case .heroBotExecutor: return "The hero's turn can't use the bot executor."
        case .staleBotPlan: return "This bot action plan is stale."
        }
    }

    private static func subjectVerb(_ name: String, _ third: String, _ base: String) -> String {
        "\(name) \(name == heroName ? base : third)"
    }

    // Table text.
    public static func handStarts(_ hand: Int, button: String) -> String {
        "Hand \(formatChips(hand)) begins · Button: \(button)"
    }
    public static func rebuy(_ name: String) -> String {
        "\(subjectVerb(name, "rebuys", "rebuy")) \(formatChips(STARTING_STACK)) virtual chips"
    }
    public static func smallBlindAction(_ amount: Int) -> String { "SB \(formatChips(amount))" }
    public static func bigBlindAction(_ amount: Int) -> String { "BB \(formatChips(amount))" }
    public static func blindsLog(_ sb: String, _ sbAmount: Int, _ bb: String, _ bbAmount: Int) -> String {
        "\(sb): \(smallBlindAction(sbAmount)) · \(bb): \(bigBlindAction(bbAmount))"
    }
    public static let fold = "Fold"
    public static let check = "Check"
    public static func call(_ amount: Int) -> String { "Call \(formatChips(amount))" }
    public static func allIn(_ amount: Int) -> String { "All-In \(formatChips(amount))" }
    public static func raiseAction(_ betLabel: String, _ amount: Int) -> String { "\(betLabel) \(formatChips(amount))" }
    /// Street reset text of an all-in player.
    public static let allInReset = "All-In"
    public static func actionLog(_ name: String, _ action: String) -> String { "\(name): \(action)" }
    public static let streetNames = ["", "Flop", "Turn", "River"]
    public static func replayLog(_ hand: Int, _ attempt: Int) -> String {
        "Hand \(formatChips(hand)) · Replay #\(formatChips(attempt)) · previous settlement reversed"
    }
    public static let practiceRunout =
        "Practice runout · all five community cards shown; the fold-win result is unchanged"
    public static let mainPot = "Main Pot"
    public static func sidePot(_ index: Int) -> String { "Side Pot \(formatChips(index))" }
    public static let othersFolded = "All other players folded"
    public static let splitPots = "Split pots · "
    public static func foldWinResult(_ name: String, _ amount: Int) -> String {
        "\(subjectVerb(name, "wins", "win")) \(formatChips(amount)) chips"
    }
    public static func showdownResult(_ name: String, _ label: String, _ amount: Int) -> String {
        "\(subjectVerb(name, "wins", "win")) \(formatChips(amount)) chips · \(label)"
    }
    public static func potLog(_ label: String, _ amount: Int, _ awards: [(name: String, amount: Int)]) -> String {
        "\(label) \(formatChips(amount)) → " + awards.map { "\($0.name) \(formatChips($0.amount))" }.joined(separator: " / ")
    }
    public static func refundLog(_ name: String, _ amount: Int) -> String {
        "Uncalled \(formatChips(amount)) chips returned to \(name)"
    }
    public static func moodLog(_ name: String, _ label: String, _ reason: String) -> String {
        "\(name) simulated mood: \(label) · \(reason)"
    }

    // Bet captions (action-labels.js): "{level}-bet {verb}", e.g. "3-bet raise to".
    public static let shortAllInTo = "short all-in to"
    public static let allInTo = "all-in to"
    public static let betTo = "bet to"
    public static let openTo = "open to"
    public static let raiseTo = "raise to"
    public static func betCaption(_ level: Int, _ verb: String) -> String { "\(level)-bet \(verb)" }
    public static let allInCallPrefix = "All-In Call "
    public static let callPrefix = "Call "

    // Moods.
    public static let reasonBigLoss = "Lost at least 25 BB net in a single hand"
    public static let reasonLosingStreak = "Lost at least 5 BB net in each of three straight hands"
    public static let reasonWinningStreak = "Won two hands in a row, at least 10 BB net this hand"
    public static let reasonPressure = "Folded to the same opponent's raise three hands in a row"
}
