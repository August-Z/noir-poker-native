package com.august.noirpoker.ui

/**
 * UI-only English copy: the reference's static page chrome and dialog text
 * (copy catalog section 6). Everything dynamic comes from the session's render
 * state (`SessionCopy` and engine copy).
 *
 * iOS mirrors this table key for key in `ios/NoirPoker/Design/UiCopy.swift`;
 * `node scripts/check-ui-copy.mjs` fails when the two drift apart.
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
    const val tableInfoA11y = "Table and Session"
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
    const val coachToggleA11y = "Table Tips"
    const val coachFooter = "Every hand, practice one good decision"
    const val activityTitle = "Hand Activity"
    const val activityListA11y = "This hand's activity, in chronological order"
    const val activityEmpty = "Once cards are dealt, every action is logged here."
    const val footnoteA = "Stay patient."
    const val footnoteB = "Good cards will come. Good decisions are up to you."

    // Showdown.
    const val showdownEyebrow = "SHOWDOWN"
    const val showdownRegionA11y = "Showdown hand comparison"

    // Dialog common.
    const val closeA11y = "Close"
    /** Accessibility state of external links (native addition). */
    const val opensInBrowser = "Opens in your browser"
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
        "After a hand ends, tap “Replay Hand” to keep everyone's hole cards, the button, starting stacks, and the upcoming deal order, and make your decisions again from preflop. The original settlement and this hand's stats are reversed and replaced by the latest result. The computer opponents respond to your new choices, so a better result isn't guaranteed. This is strategy practice on a known hand."
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

    // Opponent Styles (copy catalog section 6.1).
    const val oppEyebrow = "OPPONENT LAB"
    const val oppCloseA11y = "Close opponent settings"
    const val oppTitle = "Give every opponent a style of their own"
    const val oppIntro =
        "Training archetypes distilled from publicly reported hands, not replicas of the real players. The 0–100 values are tendency scores, not anyone's actual VPIP or PFR; highlight hands don't represent long-run frequencies."
    const val oppResearchA11y = "Player archetype research"
    const val oppAssignA11y = "Assign opponent styles"
    const val oppRosterHeading = "Assign by Seat"
    const val oppMixButton = "Mixed Lineup"
    const val oppEmotionLabel = "Human-like emotion simulation"
    const val oppEmotionA11y = "Emotion simulation strength"
    const val oppEmotionHelp =
        "Losing a big pot, a winning streak, or being pushed off hands repeatedly by the same opponent can trigger a brief urge to chase losses, play it safe, or fight back. The effect fades after two hands and has a cooldown. Every archetype uses the same synthetic mechanism; it does not represent anyone's real personality."
    const val oppCompareSummary = "Compare all parameters and stat definitions"
    const val oppCompareCaption = "Training parameters for all archetypes (0–100)"
    const val oppCompareArchetype = "Archetype"
    const val oppCompareSizing = "Bet / Pot"
    const val oppCompareNoteAxes =
        "Range Width shapes starting-hand ranges; Aggression and Bluffing set raise probability in suitable spots; Calling Down affects marginal calls; Trapping raises the slow-play tendency only on safe boards. Position, player count, hand strength, and legal actions take priority over style."
    const val oppCompareNoteStats =
        "The VPIP / PFR shown for each seat are actual stats from hands completed this session: hands with money voluntarily put in / total hands, and hands raised preflop / total hands. Forced blinds don't count; switching a style restarts the count, and relaunching the app or starting a new session resets it to zero. Bet ranges are typical postflop sizes and don't limit special raises, short stacks, or all-ins."
    const val oppSaveButton = "Save · Applies Next Hand"
    const val playerCountA11y = "Table size"

    // Settings sheet (native grouping of the surface controls, tips and sound).
    const val settingsEyebrow = "TABLE SETTINGS"
    const val settingsTitle = "Settings"
    const val settingsCloseA11y = "Close settings"
    const val settingsHints = "Table Tips"
    const val settingsSound = "Sound"
    const val expanded = "Expanded"
    const val collapsed = "Collapsed"

    fun playersOption(n: Int) = "$n players"
}
