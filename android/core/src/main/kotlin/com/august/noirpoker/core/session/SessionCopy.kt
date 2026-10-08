package com.august.noirpoker.core.session

import com.august.noirpoker.core.Difficulty
import com.august.noirpoker.core.formatChips

/**
 * English UI copy produced by the table session (keys and wording from the
 * master copy catalog). Engine-generated text (action captions, logs, results,
 * hand and mood labels) comes from [com.august.noirpoker.core.EngineCopy] and is
 * never rewritten here.
 */
object SessionCopy {
    private fun g(n: Int) = formatChips(n)

    val streets = listOf("Preflop", "Flop", "Turn", "River")
    fun street(index: Int): String? = streets.getOrNull(index)

    // Header and table meta.
    fun tableTag(count: Int) = "$count-MAX"
    fun tableSize(count: Int) = "$count-Handed No-Limit"
    fun handNumber(hand: Int) = hand.toString().padStart(2, '0')
    fun handHeading(hand: Int) = "Hand ${handNumber(hand)}"
    val streetReady = "Ready to Deal"
    val streetDone = "Hand Over"
    fun replayBadge(n: Int) = "Replay $n"
    val replayNote = "Replaying this hand · Same hole cards and deal order; the original settlement has been reversed."

    // Board.
    val undealtCard = "Undealt community card"
    val boardSlotGlyphs = listOf("♠", "♣", "♥", "♦", "♠")
    val captionPractice = "Practice runout · Five community cards; settlement unchanged"
    val captionShowdownFolded = "Showdown · Opponents show their cards"
    val captionShowdownHero = "Showdown · Highlighted cards make your best hand"
    val captionPreflop = "Waiting for the flop"
    val captionFlop = "FLOP · Three community cards"
    val captionTurn = "TURN · The fourth community card"
    val captionRiver = "RIVER · Final decision"
    fun sidePots(k: Int) = if (k == 1) "1 Side Pot" else "$k Side Pots"
    fun captionMultiPot(done: Boolean, main: Int, sideCount: Int) =
        (if (done) "Settled separately" else "Current bets") + " · Main Pot ${g(main)} + ${sidePots(sideCount)}"
    val potButtonSingle = "Pot · Details"
    fun potButtonMulti(sideCount: Int) = "Total Pot · ${sidePots(sideCount)}"
    val potDetailsA11y = "View pot details"

    // Positions.
    val positionNames = mapOf(
        "BTN" to "Button (Dealer)",
        "SB" to "Small Blind",
        "BB" to "Big Blind",
        "UTG" to "Under the Gun",
        "UTG+1" to "Under the Gun +1",
        "MP" to "Middle Position",
        "LJ" to "Lojack",
        "HJ" to "Hijack",
        "CO" to "Cutoff",
    )

    // Seats.
    val avatarLetters = listOf("YOU", "M", "A", "R", "K", "L", "T", "J", "L")
    val thinking = "Thinking"
    val noAction = "No Action"
    val waiting = "Waiting"
    fun meaningCall(added: Int, streetTotal: Int) = "Added ${g(added)} · ${g(streetTotal)} in this round"
    fun meaningOther(actionText: String, amount: Int) = "$actionText · ${g(amount)} in this round"
    fun winnerA11y(name: String, amount: Int) = "$name wins ${g(amount)} chips"
    fun heroWinnerA11y(amount: Int) = "You win ${g(amount)} chips"
    fun winnerTitle(label: String, amount: Int) = "$label · Won ${g(amount)} chips"
    val winnerFallback = "Winner"
    fun avatarTitle(name: String, short: String, mood: String) =
        "$name · $short (training archetype) · Simulated mood: $mood"
    val cardBackA11y = "Opponent's hole card"
    fun styleTitle(profileName: String, tag: String) = "$profileName · $tag"
    fun styleA11y(name: String, profileName: String) = "$name's style this hand: $profileName"
    val peekHide = "Hide Hole Cards"
    val peekShow = "Show Hole Cards"
    fun peekA11y(reveal: Boolean, name: String) = if (reveal) "Hide $name's hole cards" else "Show $name's hole cards"
    fun seatActionA11y(name: String) = "$name's last action"

    // Seat action labels (parsed from engine action text).
    val labelShortAllIn = "Short All-In"
    val labelAllIn = "All-In"
    val recentVerbs = mapOf("open to" to "Open", "raise to" to "Raise", "bet to" to "Bet")
    val bareRaise = "Raise"

    // Hero.
    val heroName = "You"
    val heroFoldedPrefix = "Folded · "
    val heroTurnYours = "Your Turn"
    val heroTurnFolded = "Folded"
    val heroTurnAllIn = "All-In"
    val heroLastActionA11y = "Your last action"

    // Session panel.
    val chipsUnit = "CHIPS"
    fun sessionChange(diff: Int) = (if (diff >= 0) "+" else "") + g(diff) + " chips · Net this session"
    val sessionChangeInitial = "Build experience, starting this hand"
    val statEmpty = "—"
    fun winRate(pct: Int) = "$pct%"

    // Activity.
    val activityLive = "LIVE"
    val activityFinished = "FINISHED"
    fun personaSuffix(short: String) = " ($short)"

    // Action panel.
    val fold = "Fold"
    val check = "Check"
    val call = "Call"
    val callAllIn = "Call All-In"
    val finishHand = "Finish Hand"
    val finishHandBusy = "Dealing…"
    val finishHandTitle = "Fast-forward the remaining opponent actions and settle the hand"
    val nextHand = "Next Hand"
    val nextHandRebuy = "Rebuy and Keep Practicing"
    val replayHand = "↺ Replay Hand"
    val replayHandTitle = "Restore this hand's starting stacks, hole cards, and deal order, and reverse the original settlement"
    val reviewHand = "Review This Hand"
    val betSliderLabel = "Raise to"
    val betSliderA11y = "Raise-to amount"
    val presetLabels = mapOf(
        BetPreset.MIN to "Min",
        BetPreset.HALF_POT to "½ Pot",
        BetPreset.POT to "Pot",
        BetPreset.ALL_IN to "All-In",
    )

    // Decision strip.
    val decisionCanCheck = "Your turn. You can check or bet."
    fun decisionToCall(amount: Int) = "Your turn. ${g(amount)} chips to call."
    val decisionNotReopened = " Raising is not reopened this round; you can only call or fold."
    val decisionShowdownSettling = "Showdown · Cards are face up; settling each pot…"
    val decisionAllInRunout = "All-in action complete · Cards are face up; waiting for the remaining community cards…"
    val decisionDealingNext = "Betting round complete; dealing the next community cards…"
    val opponentFallback = "An opponent"
    fun decisionObserve(name: String) = "$name is acting. You can watch the rest of this hand."
    fun decisionWait(name: String) = "$name is thinking…"

    // Coach.
    val coachOn = "On"
    val coachOff = "Off"
    val coachStageDone = "Hand Recap"
    fun coachStage(street: String) = "$street Strategy"
    val tipDoneFolded =
        "Folding is part of good decision-making too. Look at the cards opponents showed and think back over the betting in this hand."
    fun tipDoneShowdown(label: String) =
        "Your best hand was $label. As you review, ask: on which street did opponents start raising? Did the community cards change how strong your hand was?"
    val tipDoneUncontested = "Getting opponents to fold wins pots too. Next hand, keep watching position and bet sizing."
    val tipPrePair = "A pocket pair can flop a set. With a small pair facing a big raise, weigh the cost of calling."
    val tipPreBroadway =
        "Two high cards make a solid starting hand. Raising narrows opponents' ranges, but watch out for big raises ahead of you."
    val tipPreSuited =
        "Suited hole cards add potential, but they don't justify calling any price. Watch how connected the cards are and where you act from."
    val tipPreOther =
        "You don't have to play every hand. The earlier you act, the more selective you should be; later positions let you use more information."
    fun tipMadeStrong(label: String) =
        "You've made $label. Consider betting for value, but watch for stronger hands the board makes possible."
    fun tipMadePair(label: String) =
        "You have $label. Against several opponents, be careful facing repeated big raises; one pair doesn't always hold up."
    val tipUnpaired =
        "No pair yet. Don't just ask whether you might hit; consider the price to call and how strongly opponents are betting."
    fun tipPriceSuffix(pct: Int) = " This call is about $pct% of the pot you can win."

    /** Hand-category labels as nouns inside coach sentences, keyed by the engine label. */
    val handNouns = mapOf(
        "High Card" to "high card",
        "One Pair" to "one pair",
        "Two Pair" to "two pair",
        "Three of a Kind" to "three of a kind",
        "Straight" to "a straight",
        "Flush" to "a flush",
        "Full House" to "a full house",
        "Four of a Kind" to "four of a kind",
        "Straight Flush" to "a straight flush",
        "Royal Flush" to "a royal flush",
        "Pocket Pair" to "a pocket pair",
    )
    fun handNoun(label: String) = handNouns[label] ?: label

    // Settings.
    fun tableChangeNote(n: Int) = "Switches to $n players next hand · Stacks reset to 5,000 and stats start over"
    fun playerCountOption(n: Int) = "$n players"
    val difficultyLabels = mapOf(
        Difficulty.EASY to "Easy",
        Difficulty.NORMAL to "Standard",
        Difficulty.HARD to "Advanced",
    )
    val soundOnA11y = "Turn sound on"
    val soundOffA11y = "Turn sound off"
    val soundStateOn = "Sound on"
    val soundStateOff = "Sound off"

    // Opponent settings.
    val opponentsSummaryPending = "Next Hand"
    fun opponentsSummaryNamed(n: Int) = if (n == 1) "1 Styled Opponent" else "$n Styled Opponents"
    val opponentsSummaryBalanced = "Balanced"
    val opponentsChangeNote =
        "Opponent styles saved and will apply next hand. This hand and any replay use the current styles shown at each seat."
    val opponentsSaveNote =
        "Saved on this device and restored next time. Changes apply from the next hand; replays keep the original opponents."
    val profileBadge = "Training Archetype"
    fun profileSizing(lo: Int, hi: Int) = "Typical postflop bet: $lo–$hi% pot"
    fun profileSizingCell(lo: Int, hi: Int) = "$lo–$hi%"
    val rosterOffTable = "Not Seated"
    fun rosterSeat(id: Int) = "Seat $id"
    val moodSteady = "Steady"
    fun rosterSelectA11y(name: String) = "$name's training style"
    fun rosterCurrentStyle(short: String) = "Style this hand: $short"
    val rosterNotSeated = "Not seated yet; uses the saved next-hand setting"
    val rosterObservedTitle = "Hands this bot has completed this session; restarts from zero after a style change"
    fun rosterObserved(hands: Int, vpip: String, pfr: String) =
        (if (hands == 1) "1 hand" else "$hands hands") + " · VPIP $vpip · PFR $pfr"

    // Pot dialog.
    val potEligHero = "You're eligible"
    val potEligNotIn = "You're not in this pot"
    val potEligOverAllIn = "Above your all-in amount"
    val potEligNotYet = "You haven't matched this pot yet"
    val potContribFolded = " · Folded"
    val potContribAllIn = " · All-In"
    val potTitleSettled = "Hand Settlement"
    val potTitleLive = "Main Pot and Side Pots"
    val potNoteLive =
        "Amounts reflect chips committed so far; players yet to act must call to stay eligible. Only all-in amounts create side pots; any uncalled portion is waiting to be called or refunded."
    val listJoiner = ", "
    fun potSplitTotal(amount: Int) = "${g(amount)} chips · Split"
    fun potAwardWinner(name: String) = "$name wins"
    fun potAwardAmount(amount: Int) = "+${g(amount)}"
    val chips = "chips"
    val potDistributionSummary = "View Distribution Details"
    fun potDistributionEligibility(label: String, names: String) = "$label · Eligible at settlement: $names"
    val potContribHeading = "Contributions to This Pot"
    val potOddChipNote = "Odd chips go out in seat order starting left of the button."
    fun potLiveCount(n: Int) = if (n == 1) " · 1 player" else " · $n players"
    fun potLiveParticipants(names: String) = "Eligible: $names"
    val potContribSummary = "View Contributions"
    fun refundDoneA11y(name: String, amount: Int) = "$name's uncalled ${g(amount)} chips were returned"
    fun refundDone(name: String) = "Uncalled bet returned · $name"
    fun refundLive(name: String) = "To be called or returned · $name"

    // Showdown.
    private val rankWords = mapOf(
        2 to "Two", 3 to "Three", 4 to "Four", 5 to "Five", 6 to "Six", 7 to "Seven", 8 to "Eight",
        9 to "Nine", 10 to "Ten", 11 to "Jack", 12 to "Queen", 13 to "King", 14 to "Ace",
    )
    private val rankPlurals = mapOf(
        2 to "Twos", 3 to "Threes", 4 to "Fours", 5 to "Fives", 6 to "Sixes", 7 to "Sevens", 8 to "Eights",
        9 to "Nines", 10 to "Tens", 11 to "Jacks", 12 to "Queens", 13 to "Kings", 14 to "Aces",
    )
    fun rankWord(r: Int) = rankWords.getValue(r)
    fun rankPlural(r: Int) = rankPlurals.getValue(r)
    fun sdHigh(r: Int) = "${rankWord(r)}-high · Kickers compared in order"
    fun sdPair(r: Int) = "Pair of ${rankPlural(r)}"
    fun sdTwoPair(r1: Int, r2: Int) = "${rankPlural(r1)} and ${rankPlural(r2)}"
    fun sdTrips(r: Int) = "Three ${rankPlural(r)}"
    fun sdStraight(r: Int) = "${rankWord(r)}-high straight"
    fun sdFlush(suit: String, r: Int) = "$suit flush · ${rankWord(r)}-high"
    fun sdFullHouse(r1: Int, r2: Int) = "${rankPlural(r1)} full of ${rankPlural(r2)}"
    fun sdQuads(r: Int) = "Four ${rankPlural(r)}"
    val sdRoyal = "10 · J · Q · K · A of one suit"
    fun sdStraightFlush(suit: String, r: Int) = "$suit straight flush · ${rankWord(r)}-high"
    fun sdContext(n: Int, multiPot: Boolean) =
        "$n players at showdown" + if (multiPot) " · Main Pot and Side Pots settled separately" else ""
    fun sdPlayerA11y(name: String, label: String) = "$name · $label"
    fun sdWon(amount: Int) = "Won +${g(amount)}"
    val sdNoPot = "No pot won"
    fun sdAwardItem(pot: String, split: Boolean, amount: Int) = pot + (if (split) " · Split" else "") + " +${g(amount)}"
    val sdBestFive = "Best five cards"
}
