import Foundation

/// UI-only English copy: the reference's static page chrome and dialog text
/// (copy catalog section 6). Everything dynamic comes from the session's render
/// state (`SessionCopy` and engine copy).
///
/// This table mirrors Android's `UiCopy.kt` key for key and string for string;
/// `node scripts/check-ui-copy.mjs` fails when the two drift apart. Views read
/// their fixed copy from here instead of hard-coding it.
enum UiCopy {
    // Header and page chrome.
    static let brandNoir = "NOIR"
    static let brandPoker = "POKER"
    static let brandA11y = "NOIR Poker"
    static let headerMode = "Solo Practice"
    static let soundOnA11y = "Turn sound on"
    static let soundOffA11y = "Turn sound off"
    static let rulesButton = "How to Play"
    static let tableRegionA11y = "Texas Hold'em table"
    static let tableEyebrow = "THE PRACTICE ROOM"
    static let tableHeadline = "Every hand is a fresh chance"
    static let tableBlinds = "Blinds 25 / 50"
    static let watermark = "N O I R"
    static let watermarkSub = "POKER CLUB"
    static let heroAvatar = "YOU"
    static let footerLocal = "Offline computer opponents · No login required"
    static let footerVirtual = "Virtual chips only"
    static let resetButton = "Start New Session"
    static let opponentsButton = "Opponent Styles"
    static let playersLabel = "Players"
    static let difficultyLabel = "Opponent Difficulty"

    // Sidebar.
    static let sessionTitle = "Your Practice"
    static let sessionSubtitle = "This Table"
    static let sessionStackLabel = "Current Stack"
    static let statHands = "Hands Played"
    static let statWins = "Hands Won"
    static let statWinRate = "Win Rate"
    static let coachTitle = "✧ Table Tips"
    static let coachToggleA11y = "Table Tips"
    static let coachFooter = "Every hand, practice one good decision"
    static let activityTitle = "Hand Activity"
    static let activityListA11y = "This hand's activity, in chronological order"
    static let activityEmpty = "Once cards are dealt, every action is logged here."
    static let footnoteA = "Stay patient."
    static let footnoteB = "Good cards will come. Good decisions are up to you."

    // Showdown.
    static let showdownEyebrow = "SHOWDOWN"
    static let showdownRegionA11y = "Showdown hand comparison"

    // Dialog common.
    static let closeA11y = "Close"
    /** Accessibility state of external links (native addition). */
    static let opensInBrowser = "Opens in your browser"
    static let backToTable = "Back to Table"

    // How to Play.
    static let rulesEyebrow = "QUICK GUIDE"
    static let rulesTitle = "Five minutes to a seat at the table."
    static let rulesIntro =
        "Each player gets two hole cards and combines them with five community cards to make the best five-card hand. The table defaults to 6 players, with 5–9 available, and every game uses virtual chips."
    static let rulesFlow = ["Hole cards", "Flop: 3 cards", "Turn: 1 card", "River: 1 card"]
    static let rulesActions: [(title: String, detail: String)] = [
        ("Fold", "Give up the hand; chips already bet stay in the pot."),
        ("Check / Call", "Check when there's nothing to call; otherwise match the current bet."),
        ("Bet / Raise", "Choose your total for this betting round; it must be at least the minimum raise."),
        ("All-In", "Put in all your remaining chips; side pots are calculated automatically when stacks differ."),
    ]
    static let rulesPositionHeading = "Positions and Action Order"
    static let rulesPositionBody = [
        "This table plays No-Limit Hold'em with 5–9 players and 25 / 50 blinds. The seat after the button is the SB and the next is the BB; the other positions depend on table size. At a 6-player table, clockwise order is BTN, SB, BB, UTG, HJ, CO. The button moves one seat clockwise after every hand.",
        "Preflop action starts with the player after the BB; if nobody raises, the big blind can still check or raise last. After a raise, action continues until every player who hasn't folded or gone all-in has matched the bet and acted. On the flop, turn, and river, action starts with the first player left of the button who hasn't folded or gone all-in, and moves clockwise.",
        "The minimum bet is 50. A raise must increase the bet by at least the size of the last full bet or raise in this round. Less than the minimum is only possible as an all-in, and an all-in short of a full raise does not reopen raising for players who already acted and haven't faced a full raise.",
    ]
    static let rulesReplayHeading = "Replaying a Hand"
    static let rulesReplayBody =
        "After a hand ends, tap “Replay Hand” to keep everyone's hole cards, the button, starting stacks, and the upcoming deal order, and make your decisions again from preflop. The original settlement and this hand's stats are reversed and replaced by the latest result. The computer opponents respond to your new choices, so a better result isn't guaranteed. This is strategy practice on a known hand."
    static let rulesRanksHeading = "Hand Rankings, Strongest First"
    static let rulesRanks = "Straight Flush · Four of a Kind · Full House · Flush · Straight · Three of a Kind · Two Pair · One Pair · High Card"
    static let rulesNotes = [
        "BTN = Button · SB = Small Blind · BB = Big Blind",
        "Use any five of your hole cards and the community cards, including playing the board. Identical hands and kickers split the pot; suits never break ties. Each side pot is settled separately, and any uncalled excess is returned.",
        "Computer players decide using only their own hole cards and public information. Tips are a basic practice aid.",
    ]

    // Start New Session confirmation.
    static let resetEyebrow = "FRESH START"
    static let resetTitle = "Start a new session?"
    static let resetBody = "This session will end, every player returns to 5,000 chips, and your practice stats reset to zero."
    static let resetCancel = "Keep Practicing"
    static let resetConfirm = "Start New Session"

    // Opponent Styles (copy catalog section 6.1).
    static let oppEyebrow = "OPPONENT LAB"
    static let oppCloseA11y = "Close opponent settings"
    static let oppTitle = "Give every opponent a style of their own"
    static let oppIntro =
        "Training archetypes distilled from publicly reported hands, not replicas of the real players. The 0–100 values are tendency scores, not anyone's actual VPIP or PFR; highlight hands don't represent long-run frequencies."
    static let oppResearchA11y = "Player archetype research"
    static let oppAssignA11y = "Assign opponent styles"
    static let oppRosterHeading = "Assign by Seat"
    static let oppMixButton = "Mixed Lineup"
    static let oppEmotionLabel = "Human-like emotion simulation"
    static let oppEmotionA11y = "Emotion simulation strength"
    static let oppEmotionHelp =
        "Losing a big pot, a winning streak, or being pushed off hands repeatedly by the same opponent can trigger a brief urge to chase losses, play it safe, or fight back. The effect fades after two hands and has a cooldown. Every archetype uses the same synthetic mechanism; it does not represent anyone's real personality."
    static let oppCompareSummary = "Compare all parameters and stat definitions"
    static let oppCompareCaption = "Training parameters for all archetypes (0–100)"
    static let oppCompareArchetype = "Archetype"
    static let oppCompareSizing = "Bet / Pot"
    static let oppCompareNoteAxes =
        "Range Width shapes starting-hand ranges; Aggression and Bluffing set raise probability in suitable spots; Calling Down affects marginal calls; Trapping raises the slow-play tendency only on safe boards. Position, player count, hand strength, and legal actions take priority over style."
    static let oppCompareNoteStats =
        "The VPIP / PFR shown for each seat are actual stats from hands completed this session: hands with money voluntarily put in / total hands, and hands raised preflop / total hands. Forced blinds don't count; switching a style restarts the count, and relaunching the app or starting a new session resets it to zero. Bet ranges are typical postflop sizes and don't limit special raises, short stacks, or all-ins."
    static let oppSaveButton = "Save · Applies Next Hand"
    static let playerCountA11y = "Table size"

    // Settings sheet (native grouping of the surface controls, tips and sound).
    static let settingsEyebrow = "TABLE SETTINGS"
    static let settingsTitle = "Settings"
    static let settingsCloseA11y = "Close settings"
    static let settingsHints = "Table Tips"
    static let settingsSound = "Sound"
    static let expanded = "Expanded"
    static let collapsed = "Collapsed"

    static func playersOption(_ n: Int) -> String { "\(n) players" }
}
