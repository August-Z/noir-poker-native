package com.august.noirpoker.core

/**
 * Every user-visible string the engine produces. The reference produces these in
 * Chinese; this is the English translation. `scripts/reference-copy.mjs` is the
 * authority for engine copy (fixtures carry its output), so keep this table
 * aligned with it. Error messages are thrown, not part of the fixtures.
 */
object EngineCopy {
    val heroName = "You"
    val botNames = listOf("Mia", "Alex", "River", "Kai", "Luna", "Theo", "Jade", "Leo")

    val rankNames = listOf(
        "High Card",
        "One Pair",
        "Two Pair",
        "Three of a Kind",
        "Straight",
        "Flush",
        "Full House",
        "Four of a Kind",
        "Straight Flush",
    )
    val royalFlush = "Royal Flush"
    val pocketPair = "Pocket Pair"

    // Errors.
    val tableSize = "Table size must be 5–9 players."
    val settingsNextHand = "Opponent settings take effect at the start of the next hand."
    val handNotFinished = "The current hand isn't finished yet."
    val replayUnavailable = "You can replay a hand after it ends; the original deal is required."
    val notYourTurn = "It's not your turn yet."
    val unknownAction = "Unknown table action."
    val mustCall = "You must call; checking isn't allowed."
    val illegalRaise = "Choose a legal raise-to amount."
    val roundNotFinished = "This betting round isn't finished."
    val settleFirst = "Settle this hand first."
    val showdownNeedsBoard = "A showdown settlement requires all five community cards."
    val alreadySettled = "This hand has already been settled."
    val noEligiblePlayer = "No eligible player for this pot."
    val potMismatch = "Pot distribution doesn't add up."
    val trialsPositive = "Equity trial count must be a positive integer."
    val botCannotAct = "The bot can't act right now."
    val heroUsesBotExecutor = "The hero's turn can't use the bot executor."
    val stalePlan = "This bot action plan is stale."

    private fun isHero(name: String) = name == heroName
    private fun subjectVerb(name: String, third: String, base: String) = "$name ${if (isHero(name)) base else third}"

    // Table text. Every chip amount and hand number uses en-US grouping.
    fun handStarts(hand: Int, button: String) = "Hand ${formatChips(hand)} begins · Button: $button"
    fun rebuy(name: String) = "${subjectVerb(name, "rebuys", "rebuy")} ${formatChips(STARTING_STACK)} virtual chips"
    fun smallBlindAction(amount: Int) = "SB ${formatChips(amount)}"
    fun bigBlindAction(amount: Int) = "BB ${formatChips(amount)}"
    fun blindsLog(sb: String, sbAmount: Int, bb: String, bbAmount: Int) =
        "$sb: ${smallBlindAction(sbAmount)} · $bb: ${bigBlindAction(bbAmount)}"
    val fold = "Fold"
    val check = "Check"
    fun call(amount: Int) = "Call ${formatChips(amount)}"
    fun allIn(amount: Int) = "All-In ${formatChips(amount)}"
    fun raiseAction(betLabel: String, amount: Int) = "$betLabel ${formatChips(amount)}"
    val allInReset = "All-In"
    fun actionLog(name: String, action: String) = "$name: $action"
    val streetNames = listOf("", "Flop", "Turn", "River")
    fun replayLog(hand: Int, attempt: Int) =
        "Hand ${formatChips(hand)} · Replay #${formatChips(attempt)} · previous settlement reversed"
    val practiceRunout = "Practice runout · all five community cards shown; the fold-win result is unchanged"
    val mainPot = "Main Pot"
    fun sidePot(index: Int) = "Side Pot ${formatChips(index)}"
    val othersFolded = "All other players folded"
    val splitPots = "Split pots · "
    fun foldWinResult(name: String, amount: Int) = "${subjectVerb(name, "wins", "win")} ${formatChips(amount)} chips"
    fun showdownResult(name: String, label: String, amount: Int) =
        "${subjectVerb(name, "wins", "win")} ${formatChips(amount)} chips · $label"
    fun refundLog(name: String, amount: Int) = "Uncalled ${formatChips(amount)} chips returned to $name"
    fun moodLog(name: String, label: String, reason: String) = "$name simulated mood: $label · $reason"

    // Bet captions (action-labels.js): "{level}-bet {verb}", e.g. "3-bet raise to".
    val shortAllInTo = "short all-in to"
    val allInTo = "all-in to"
    val betTo = "bet to"
    val openTo = "open to"
    val raiseTo = "raise to"
    fun betCaption(level: Int, verb: String) = "$level-bet $verb"
    val allInCallPrefix = "All-In Call "
    val callPrefix = "Call "

    // Moods.
    val reasonBigLoss = "Lost at least 25 BB net in a single hand"
    val reasonLosingStreak = "Lost at least 5 BB net in each of three straight hands"
    val reasonWinningStreak = "Won two hands in a row, at least 10 BB net this hand"
    val reasonPressure = "Folded to the same opponent's raise three hands in a row"
}
