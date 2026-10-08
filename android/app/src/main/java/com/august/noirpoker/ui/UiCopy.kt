package com.august.noirpoker.ui

/**
 * UI-only English copy: the reference's static page chrome and dialog text
 * (copy catalog section 6). Everything dynamic comes from the session's render
 * state (`SessionCopy` and engine copy).
 */
object UiCopy {
    // Header and page chrome.
    const val brandNoir = "NOIR"
    const val brandPoker = "POKER"
    const val brandA11y = "NOIR Poker"
    const val headerMode = "Solo Practice"
    const val soundOnA11y = "Turn sound on"
    const val soundOffA11y = "Turn sound off"
    const val rulesButton = "How to Play"
    const val tableRegionA11y = "Texas Hold'em table"
    const val tableEyebrow = "THE PRACTICE ROOM"
    const val tableHeadline = "Every hand is a fresh chance"
    const val tableBlinds = "Blinds 25 / 50"
    const val watermark = "N O I R"
    const val watermarkSub = "POKER CLUB"
    const val heroAvatar = "YOU"
    const val footerLocal = "Offline computer opponents · No login required"
    const val footerVirtual = "Virtual chips only"
    const val resetButton = "Start New Session"
    const val opponentsButton = "Opponent Styles"
    const val playersLabel = "Players"
    const val difficultyLabel = "Opponent Difficulty"

    // Sidebar.
    const val sessionTitle = "Your Practice"
    const val sessionSubtitle = "This Table"
    const val sessionStackLabel = "Current Stack"
    const val statHands = "Hands Played"
    const val statWins = "Hands Won"
    const val statWinRate = "Win Rate"
    const val coachTitle = "✧ Table Tips"
    const val coachFooter = "Every hand, practice one good decision"
    const val activityTitle = "Activity"
    const val activityListA11y = "This hand's activity, in chronological order"
    const val activityEmpty = "Once cards are dealt, every action is logged here."
    const val footnoteA = "Stay patient."
    const val footnoteB = "Good cards will come. Good decisions are up to you."

    // Showdown.
    const val showdownEyebrow = "SHOWDOWN"
    const val showdownRegionA11y = "Showdown hand comparison"

    // Dialog common.
    const val closeA11y = "Close"
    const val backToTable = "Back to Table"

    // How to Play.
    const val rulesEyebrow = "QUICK GUIDE"
    const val rulesTitle = "Five minutes to a seat at the table."
    const val rulesIntro =
        "Each player gets two hole cards and combines them with five community cards to make the best five-card hand. The table defaults to 6 players, with 5–9 available, and every game uses virtual chips."
    val rulesFlow = listOf("Hole cards", "Flop: 3 cards", "Turn: 1 card", "River: 1 card")
    val rulesActions = listOf(
        "Fold" to "Give up the hand; chips already bet stay in the pot.",
        "Check / Call" to "Check when there's nothing to call; otherwise match the current bet.",
        "Bet / Raise" to "Choose your total for this betting round; it must be at least the minimum raise.",
        "All-In" to "Put in all your remaining chips; side pots are calculated automatically when stacks differ.",
    )
    const val rulesPositionHeading = "Positions and Action Order"
    val rulesPositionBody = listOf(
        "This table plays No-Limit Hold'em with 5–9 players and 25 / 50 blinds. The seat after the button is the SB and the next is the BB; the other positions depend on table size. At a 6-player table, clockwise order is BTN, SB, BB, UTG, HJ, CO. The button moves one seat clockwise after every hand.",
        "Preflop action starts with the player after the BB; if nobody raises, the big blind can still check or raise last. After a raise, action continues until every player who hasn't folded or gone all-in has matched the bet and acted. On the flop, turn, and river, action starts with the first player left of the button who hasn't folded or gone all-in, and moves clockwise.",
        "The minimum bet is 50. A raise must increase the bet by at least the size of the last full bet or raise in this round. Less than the minimum is only possible as an all-in, and an all-in short of a full raise does not reopen raising for players who already acted and haven't faced a full raise.",
    )
    const val rulesReplayHeading = "Replaying a Hand"
    const val rulesReplayBody =
        "After a hand ends, tap “Replay Hand” to keep everyone's hole cards, the button, starting stacks, and the upcoming deal order, and make your decisions again from preflop. The original settlement and this hand's stats are reversed and replaced by the latest result. The computer responds to your new choices, so winning more is not guaranteed; this is strategy practice on a known hand."
    const val rulesRanksHeading = "Hand Rankings, Strongest First"
    const val rulesRanks = "Straight Flush · Four of a Kind · Full House · Flush · Straight · Three of a Kind · Two Pair · One Pair · High Card"
    val rulesNotes = listOf(
        "BTN = Button · SB = Small Blind · BB = Big Blind",
        "Use any five of your hole cards and the community cards, including playing the board. Identical hands and kickers split the pot; suits never break ties. Each side pot is settled separately, and any uncalled excess is returned.",
        "Computer players decide using only their own hole cards and public information. Tips are a basic practice aid.",
    )

    // Start New Session confirmation.
    const val resetEyebrow = "FRESH START"
    const val resetTitle = "Start a new session?"
    const val resetBody = "This session will end, every player returns to 5,000 chips, and your practice stats reset to zero."
    const val resetCancel = "Keep Practicing"
    const val resetConfirm = "Start New Session"

    fun playersOption(n: Int) = "$n players"
}
