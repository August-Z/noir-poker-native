package com.august.noirpoker.core.review

import com.august.noirpoker.core.rankText

/**
 * Every English string the review domain produces: the translation of the reference's
 * Chinese review copy (the review modules). `scripts/review-copy.mjs` is the authority
 * (the review fixtures are generated from it); keep this object aligned with it on both
 * platforms. Comments name the keys of the review copy catalog.
 *
 * Assembly rules: fragments the reference concatenates are joined with one space
 * ([sentences]). Hand, board and preflop labels have a mid-sentence phrase and a start
 * form used at the start of a sentence, after ": ", and as standalone field values.
 */
object ReviewCopy {
    // street_*
    val streetNames = listOf("Preflop", "Flop", "Turn", "River")

    // Errors (thrown; the UI shows its own retry message).
    val errorInputNotDone = "You can review a hand only after it ends."
    val errorTrials = "The sample count must be a positive integer."
    val errorSimTrials = "The simulation needs at least 2 trials."
    val errorSimRunaway = "The candidate-action simulation did not finish."

    // Rank words for English plurals ("pocket Nines").
    fun rankPlural(r: Int): String = when (r) {
        2 -> "Twos"
        3 -> "Threes"
        4 -> "Fours"
        5 -> "Fives"
        6 -> "Sixes"
        7 -> "Sevens"
        8 -> "Eights"
        9 -> "Nines"
        10 -> "Tens"
        11 -> "Jacks"
        12 -> "Queens"
        13 -> "Kings"
        14 -> "Aces"
        else -> rankText(r)
    }

    /** Indefinite article for a rank symbol: "an A", "an 8", "a J". */
    private fun article(rank: String) = if (rank == "A" || rank == "8") "an" else "a"

    // board_* — noun phrases that read after "The board is …" / "Board: …".
    val boardTrips = "trips on board"
    val boardPaired = "paired"
    val boardFourFlush = "four to a flush"
    val boardThreeFlush = "three to a flush"
    val boardTwoTone = "two-tone"
    val boardFourConnected = "four to a straight"
    val boardThreeConnected = "clearly straight-connected"
    val boardDry = "rainbow and disconnected"

    /** Mid-sentence phrases of the engine hand names (`made.label`); the start form is the engine name. */
    fun engineHandPhrase(label: String): String = when (label) {
        "Straight" -> "a straight"
        "Flush" -> "a flush"
        "Full House" -> "a full house"
        "Straight Flush" -> "a straight flush"
        "Royal Flush" -> "a royal flush"
        else -> label.lowercase()
    }

    // hand_* — hero hand labels (noun phrases; capitalize at the start of a sentence).
    fun handPocket(rank: Int) = "pocket ${rankPlural(rank)}"
    fun handUnpaired(ranks: List<String>, suited: Boolean) =
        ranks.joinToString("/") + " " + (if (suited) "suited" else "offsuit")
    val handPlaysBoard = "a hand that plays the board (hole cards add nothing)"
    fun handSet(rank: Int) = "a set of ${rankPlural(rank)}"
    fun handOverpair(rank: Int, pairedBoard: Boolean) =
        "an overpair (${rankPlural(rank)})" + (if (pairedBoard) ", on a paired board" else "")
    fun handUnderpair(rank: Int) = "pocket ${rankPlural(rank)} with an overcard on board"
    fun handBoardPair(rank: Int) = "a board pair of ${rankPlural(rank)}, hole cards as kickers"
    fun handPair(top: Boolean, pairRank: String, kickerRank: String) =
        (if (top) "top pair" else "second-or-lower pair") + " ($pairRank) with ${article(kickerRank)} $kickerRank kicker"

    // pre_* — preflop situation phrases (mid-sentence form).
    val preUnopenedLimped = "unraised, with limpers"
    val preUnopened = "unopened pot"
    val preOpenCalled = "open with callers"
    val preFacingOpen = "facing an open"
    val preFacing3Bet = "facing a 3-bet"
    val preFacing4BetPlus = "facing a 4-bet or more"

    // route_* — candidate routes.
    val routeKeep = "Keep this line; adjust to opponent ranges"
    val routeDefaultCondition = "Based on what was known at the time; reassess if ranges change."
    val routeDefaultTradeoff = "Candidate actions don't account for the value of a full future strategy."
    val routeLateSummaryIso = "Isolate; scale the size to the number of limpers"
    val routeLateSummaryOpen = "Keep the late-position open; compare 2–3 BB sizes"
    val routeLateConditionIso = "Limpers have wide ranges, and no obviously strong range has shown up behind."
    val routeLateConditionOpen = "No one has opened, the blinds fold often enough to exploit, and you'll have position postflop."
    val routeLateTradeoff = "Fights for the blinds at a controlled cost; once called, stop treating the opponent's hand as random."
    val routeLateAltCondition = "When replaying, try the other open size and note how often the blinds continue; use a larger size to isolate sticky limpers."
    val routeLateAltTradeoff = "A smaller size risks less when it fails but lets more hands defend; a larger size adds pressure but may leave only stronger ranges."
    val routeEarlySuitedSummary = "Tight baseline: fold; compare a conditional small open"
    val routeEarlySuitedCondition = "From early position with several players still to act and no evidence that opponents overfold, avoid building a pot with marginal suited hands."
    val routeEarlySuitedTradeoff = "Gives up flush potential and steal value in exchange for less out-of-position and kicker risk."
    val routeEarlySuitedAltCondition = "When players behind defend too tightly, rarely 3-bet, and you can control the pot or get out once someone continues."
    val routeEarlySuitedAltTradeoff = "Attacks the blinds, but stronger Qx/Kx and re-raises make the flush potential hard to realize; the simulation only compares lines under that assumption."
    val routeSqueezeCondition = "Without evidence that the opener is wide and the callers will fold, tighten up first."
    val routeSqueezeTradeoff = "Keeps a weak ace from being dominated by strong continuing ranges; blocking some strong aces doesn't guarantee enough folds."
    val routeSqueezeAltCondition = "Compare a squeeze only when the opener is wide, the callers look capped, and opponents will fold to a re-raise."
    val routeSqueezeAltTradeoff = "Wins multiway dead money, but costs more when it fails; after a call or a 4-bet, stop applying pressure without a reason."
    val routeWeakDefenseCondition = "Against large sizes, multiple players continuing, or strong ranges with few bluffs, put in as little new money as possible."
    val routeWeakDefenseTradeoff = "Gives up current equity to avoid weak-kicker trouble and later pressure; chips already invested are not a reason to continue."
    val routeWeakDefenseAltCondition4Bet = "Worth discussing only with clear evidence of an extremely wide range and a favorable price and closing action; it doesn't apply against normal strong ranges."
    val routeWeakDefenseAltCondition = "Consider it only against a small size and wide range, with position or a big-blind discount; don't assume it by default."
    val routeWeakDefenseAltTradeoff = "Keeps showdown equity, but the risk of domination by stronger Ax and of facing later bets remains."
    val routeRaiseConditionPressure = "Clearly better hands will fold, and the folds this size generates make up for weak equity when called."
    val routeRaiseConditionDraw = "The draw has equity when called, and the target range folds often enough."
    val routeRaiseConditionValue = "You can name worse hands that will pay, and you're prepared to reassess if raised."
    val routeRaiseTradeoff = "Builds the pot and protects equity; the bigger the size, the stronger the continuing range may be."
    val routeRaiseAltConditionIp = "When the opponent's range is strong or the board is unfavorable, use position to control how much you put in."
    val routeRaiseAltConditionOop = "When the opponent will bet on their own or you lack position, keep an induce / pot-control line."
    val routeRaiseAltTradeoff = "Keeps the pot smaller, but may give draws a free card or miss value."
    val routeFoldCondition = "The current price isn't supported by equity, or the equity is hard to realize."
    val routeFoldTradeoff = "Stops adding chips now; good cards that come later don't make the fold wrong."
    val routeFoldAltCondition = "Only when a wider range, enough bluffs, or a better price would give an equity margin."
    val routeFoldAltTradeoff = "Tests range sensitivity; it doesn't mean the call is already justified."
    val routeCallCondition = "The opponent's range and the price leave enough margin, and later pressure is manageable."
    val routeCallTradeoff = "Keeps your range wide and avoids turning thin-value hands into a raise that only gets called by stronger hands."
    val routeCallAltCondition = "When the opponent's value range is narrower, someone behind may re-raise, or you can't afford later bets."
    val routeCallAltTradeoff = "Gives up some equity for lower risk; having called one street isn't a reason to keep calling."
    val routeCheckConditionIp = "Use last action to see what happens, control the pot with marginal made hands, or keep a free draw."
    val routeCheckConditionOop = "Without the last-to-act advantage, watch the opponent's bets and how the board develops first."
    val routeCheckTradeoff = "Saves chips; it doesn't guarantee a free card, so you still need a plan for later bets."
    val routeCheckAltConditionDraw = "Compare a semi-bluff when the opponent folds enough and your draw can handle being called."
    val routeCheckAltCondition = "When there are clear worse hands that call, or the opponent will fold better hands; without evidence, keep checking."
    val routeCheckAltTradeoff = "Gains value or fold equity but is exposed to calls and raises; it hasn't been shown to earn more."

    // sim_* — candidate-action simulation.
    val simScenarioRandom = "Random range"
    val simScenarioWeighted = "Public-action-weighted range"
    fun simNote(policyTrials: Int) =
        "Unknown cards are sampled from the position at the time, and each hand is played out with the opponents' public styles; " +
            "your later decisions use the balanced bot strategy, with $policyTrials equity samples per decision. " +
            "The figures estimate net chip change under this simulated strategy, treat chips already invested as sunk, " +
            "and include split pots, refunds, and later betting. The error shown is approximate sampling error and does not " +
            "cover errors in the range or strategy model. This is not GTO or a real player's optimal EV."

    // an_* — hero decision analysis.
    fun priced(cost: Int, contestable: Int, required: Double) =
        "Effective call cost ${number(cost)}; after calling you can win ${number(contestable)}; break-even equity is about ${percent(required)}."
    fun estimated(random: Double, weighted: Double) =
        "Pot equity is about ${percent(random)} against a random range and ${percent(weighted)} against an action-weighted range."

    val confRangeDependent = "Depends on range assumptions"
    val confRuleClear = "Clear by rules and cost"
    val confSimUnstable = "Sensitive to ranges and later strategy; no single best line shown"
    val confSimStable = "Both range samples agree, but later play is still a model"

    private fun players(n: Int) = count(n, "player", "players")
    private fun opponents(n: Int) = count(n, "opponent", "opponents")
    private fun cards(n: Int) = count(n, "direct completion card", "direct completion cards")

    // free-fold
    val freeFoldTitle = "Folding when checking was free gave up a free chance"
    fun freeFoldReason(position: String, pendingOthers: Int) =
        "You were in $position and it cost 0 to continue. Checking keeps your equity in the hand without adding chips; " +
            (if (pendingOthers != 0) "${players(pendingOthers)} behind can still act." else "there's no bet to match this round.")
    val freeFoldLesson = "Take the free check first; evaluate the price if someone bets later."
    val freeFoldPlan = "If someone bets next, recalculate with the new amount and player count; don't commit in advance to calling down."

    // late-open / late-isolation
    val lateTitleIso = "Late-position isolation raise: account for the number of limpers and how often they call"
    val lateTitleOpen = "Late-position open is backed by position and fold equity"
    fun lateReason(hand: HandLabel, position: String, limpers: Int, amount: Int, ace: Boolean, weakAce: Boolean, kicker: Int) = sentences(
        "${hand.start} in $position, " +
            (if (limpers != 0) "facing ${count(limpers, "limper", "limpers")}" else "folded to you with no open in front") +
            "; you raised to ${number(amount)} (${jsToFixed(amount / 50.0, 1)} BB).",
        if (ace) {
            "Your ace blocks some AA, AK, and AQ combos, and late position allows a wider opening range than early position."
        } else {
            "Late position can attack the blinds with a wider range and have position postflop."
        },
        "Raising folds out some weak connectors and high cards, and the payoff includes fold equity; once called, the remaining range may be stronger" +
            (if (weakAce) ", and A$kicker that makes top pair is still easily dominated by a better ace kicker" else "") + ".",
        if (limpers != 0) {
            "This is an isolation raise; it's only a squeeze when there's an open plus a caller."
        } else {
            "This is an open / steal, not a squeeze."
        },
    )
    val lateLesson = "Judge whether a hand can open separately from whether it can call a re-raise; ace-high is neither a reason to fold nor a reason to call down."
    fun latePlan(limpers: Boolean) = sentences(
        if (limpers) {
            "When limpers call a lot, size up your isolation raises and tighten your range; after a multiway call, cut back on pressure with no clear reason."
        } else {
            "Compare 2–3 BB opens: a smaller size makes stealing cheaper and a larger size adds immediate pressure, depending on how the blinds continue."
        },
        "Consider defending in position only against small, wide-range 3-bets; tighten up first against large sizes or 4-bets. " +
            "Postflop, play top pair with a weak kicker mainly for pot control, and when you miss, decide whether to continuation-bet based on the board and the opponent's range.",
    )

    // weak-threebet-defense / weak-fourbet-defense
    val weakDefTitle4Bet = "Defending a weak hand against multiple re-raises lacks support"
    val weakDefTitle3Bet = "A hand you can open isn't automatically a hand that can call a 3-bet"
    fun weakDefReason(
        hand: HandLabel,
        position: String,
        prePhrase: String,
        currentBet: Int,
        ratio: Double,
        priced: String,
        estimated: String,
        ownOpen: Boolean,
        weakAce: Boolean,
        pendingOthers: Int,
    ) = sentences(
        "${hand.start} in $position, $prePhrase; the latest bet is ${number(currentBet)}, about ${jsToFixed(ratio, 1)}× the previous one.",
        priced,
        estimated,
        if (ownOpen) "Your earlier open was reasonable, but this call is a new, separate decision." else null,
        if (weakAce) {
            "Stronger Ax dominates your kicker, and the ace blocker alone isn't enough to justify a large call."
        } else {
            "A weak hand is dominated by strong ranges and has no reliable way to realize its equity postflop."
        },
        if (pendingOthers != 0) "${players(pendingOthers)} behind can still act again." else null,
    )
    val weakDefLesson4Bet = "Chips already put in with your open and call are not a reason to call a 4-bet."
    val weakDefLesson3Bet = "Separate your stealing range from your range for defending against re-raises; check sizing, position, flush potential, and how wide the opponent is."
    val weakDefPlan4Bet = "Facing multiple raises without evidence of a wide range, stop adding chips first; revisit defending only with clear evidence of an extremely wide range and a good price."
    fun weakDefPlan3Bet(suited: Boolean) =
        "The alternative is a small in-position call, but it needs a wide enough 3-bet range and a margin on price" +
            (if (suited) "; flush potential helps you realize equity" else "; an offsuit weak ace needs stricter conditions to defend") +
            ". At low SPR or under large sizing, don't continue just to see a flop."

    // late-passive-entry
    val latePassiveTitle = "From late position, compare opening rather than going by hand tier alone"
    fun latePassiveReason(hand: HandLabel, position: String, ace: Boolean, called: Boolean) = sentences(
        "${hand.start} in $position, with no one in the pot yet.",
        if (ace) {
            "Your ace blocks some strong Ax, and late position allows attacking the blinds more widely."
        } else {
            "Postflop position and room for opponents to fold support comparing an open."
        },
        if (called) {
            "A plain limp lets the blinds see a cheap flop and gives up fold equity."
        } else {
            "Folding avoids putting chips in, but also gives up the chance to attack the blinds from late position."
        },
        "This doesn't mean you should continue if raised; adjust separately when the blinds are sticky or effective stacks are short.",
    )
    val latePassiveLesson = "Treat opening and calling a re-raise as two separate sets of conditions to continue."
    val latePassivePlan = "Compare a 2–3 BB open with your conservative line; against a large 3-bet or a 4-bet, tighten up first with a weak ace. With top pair and a weak kicker, don't automatically get all your chips in."

    // squeeze-candidate
    val squeezeTitle = "A squeeze needs a range that will fold; the ace blocker is only one factor"
    fun squeezeReason(hand: HandLabel, position: String, callers: Int, amount: Int) =
        "${hand.start} in $position, after an open and ${count(callers, "call", "calls")}; re-raising to ${number(amount)} is a squeeze. " +
            "The ace blocks some strong ace combos, which helps when choosing bluffs, but an offsuit weak ace can still be dominated by stronger Ax once called. " +
            "Whether to squeeze depends on whether the opener is wide enough, whether the callers will fold, and whether you can stop in time when facing a 4-bet."
    val squeezeLesson = "Thinning the field doesn't prove a profit; evaluate immediate fold equity separately from hand strength once someone continues."
    val squeezePlan = "Without evidence about opponent ranges and folding tendencies, tighten up first; with evidence of wide opens or callers who fold, replay the hand to compare an in-position squeeze with a fold, and don't treat holding an ace as an automatic reason to attack."

    // early-suited-entry
    val earlySuitedTitle = "Marginal suited hand in early position: opening depends on how players behind defend"
    fun earlySuitedReason(hand: HandLabel, position: String, pendingOthers: Int, smallKicker: Boolean) = sentences(
        "${hand.start} is genuinely suited and has flush potential; don't treat it like a weak offsuit hand.",
        "You're in $position with ${players(pendingOthers)} still to act.",
        if (smallKicker) {
            "With a small kicker, top pair is easily dominated by the same high card with a better kicker, and " +
                "flush potential doesn't remove the pressure of being out of position and facing re-raises."
        } else {
            "Flush potential doesn't remove the pressure of being out of position and facing re-raises."
        },
        "A standard tight range can fold here; if players behind are clearly too tight and rarely 3-bet, you can compare a small open to exploit their folds.",
    )
    val earlySuitedLesson = "Weigh suitedness, position, kicker, and defending tendencies together; don't enter just because a hand has \"a high card / is suited,\" and don't call it a mistake based on tier alone."
    val earlySuitedPlan = "Put this open and a fold into the candidate-action simulation to see which line does better as opponent ranges change. Tighten up against a 3-bet, play top pair with a weak kicker for pot control, and judge flush draws on the actual price and what they'll have to pay later."

    // weak-entry
    val weakEntryTitleEarly = "Entering with a weak hand from early position lacks positional support"
    val weakEntryTitleOpen = "Facing an open, check the price and the risk of domination first"
    fun weakEntryReason(hand: HandLabel, position: String, callAmount: Int, pendingOthers: Int, early: Boolean, suited: Boolean) = sentences(
        "You hold ${hand.phrase} in $position and need ${number(callAmount)} to continue; ${players(pendingOthers)} can still act.",
        when {
            !early -> "There's already a raise in front, which raises the risk of a weak hand being dominated by a better top pair or a higher kicker."
            suited -> "Early position lacks a positional advantage, and flush potential still carries kicker, connectivity, and re-raise risk."
            else -> "Early position lacks a positional advantage, and marginal offsuit hands have a harder time realizing equity."
        },
    )
    val weakEntryLesson = "Opening, flatting an open, and defending against a re-raise need different ranges; don't judge by starting-hand tier alone."
    val weakEntryPlan = "If you later face a very small raise in the big blind, judge it again on price; \"weak hand\" doesn't automatically mean \"must fold.\""

    // deep-value-shove
    val deepShoveTitle = "Shoving a strong hand deep-stacked may cut off value"
    fun deepShoveReason(hand: HandLabel, extra: Int, pot: Int, betRatio: Double, effective: Int) =
        "${hand.start} has value, but this put in an extra ${number(extra)} (about ${roundedInt(extra / 50.0)} BB), " +
            "${jsToFixed(betRatio, 1)}× the pot of ${number(pot)} at the time; the effective stack was about ${roundedInt(effective / 50.0)} BB. " +
            "That much pressure can fold out worse hands that would call a normal raise, so a strong hand alone doesn't make shoving best."
    val deepShoveLesson = "Compare a normal open or re-raise with the shove first, so weaker ranges have a chance to pay you."
    fun deepShovePlan(alternative: String) =
        "Practice the line $alternative first; if an opponent re-raises, decide whether to continue based on their range and the effective stack. This size is a practice candidate and isn't guaranteed to earn more."

    // expensive-call
    val expCallTitleClosing = "This call's price isn't supported by equity"
    val expCallTitleOpen = "The call is expensive, and later pressure adds to it"
    fun expCallReason(hand: HandLabel, opponentCount: Int, priced: String, estimated: String, outs: Int, nextChance: Double) = sentences(
        "You had ${hand.phrase} against ${opponents(opponentCount)} still in the hand.",
        priced,
        estimated,
        if (outs != 0) {
            "You have ${cards(outs)}, about ${percent(nextChance)} to hit on the next card; completing can still lose to a stronger hand."
        } else {
            null
        },
    )
    val expCallLessonClosing = "Under both assumptions the price is higher than the estimated equity, so lean toward not putting in more."
    val expCallLessonOpen = "Equity measured to showdown isn't the equity you can actually realize; after calling you may have to pay again."
    val expCallPlanClosing = "This call ends your betting decisions, so focus on whether the opponent has enough bluffs; future winnings can't justify it."
    fun expCallPlanOpen(pendingOthers: Int) =
        "${players(pendingOthers)} behind may still act; if you call, set your exit conditions for a re-raise or a bad turn first."

    // premium-fold
    val premFoldTitle = "Folding a premium hand needs the betting pressure to explain it"
    fun premFoldReason(hand: HandLabel, currentBet: Int, callAmount: Int, effective: Int, preflopRaises: Int) = sentences(
        "You held ${hand.phrase}; the bet was ${number(currentBet)} and you needed ${number(callAmount)} more, with about ${roundedInt(effective / 50.0)} BB effective; " +
            "there had been ${count(preflopRaises, "preflop raise", "preflop raises")} this hand.",
        if (preflopRaises >= 2) {
            "Multiple re-raises narrow the opponent's range, so the \"premium hand\" label alone doesn't make the fold wrong."
        } else {
            "Under normal pressure, this hand is usually worth continuing; compare a call and a re-raise."
        },
    )
    val premFoldLesson = "Judge a strong hand together with the actual betting strength; avoid automatic shoves or automatic folds."
    val premFoldPlanMulti = "Focus on whether this is a wide-range fight or a strong range with few bluffs; without enough evidence, leave the conclusion open for discussion."
    val premFoldPlanNormal = "Replay this hand and compare raising with calling."

    // premium-flat
    val premFlatTitle = "With a premium hand, compare building the pot"
    fun premFlatReason(hand: HandLabel, position: String, callAmount: Int, opponentCount: Int, pendingOthers: Int, raised: Boolean) = sentences(
        "${hand.start} called ${number(callAmount)} in $position; ${opponents(opponentCount)} " +
            (if (opponentCount == 1) "is" else "are") + " still in and $pendingOthers can still act.",
        if (raised) {
            "Against an existing raise, flatting keeps the opponent's range wide but may also make the pot multiway."
        } else {
            "In an unraised pot, just calling lets others in cheaply."
        },
    )
    val premFlatLesson = "Raise for value while keeping alternatives like a trapping flat; choose based on opponent tendencies."
    fun premFlatPlan(alternative: String) =
        "The practice candidate is $alternative; if someone raises again, this suggestion doesn't automatically extend to getting all your chips in."

    // large-unbacked-bet
    val bigBetTitleRiver = "A big river bet needs a clear idea of which hands will fold"
    val bigBetTitle = "A big investment without clear hand strength or a draw to back it"
    fun bigBetReason(hand: HandLabel, extra: Int, betRatio: Double, opponentCount: Int, missedDraw: Boolean, blocker: Boolean) = sentences(
        "You had ${hand.phrase} and bet an extra ${number(extra)}, about ${jsToFixed(betRatio, 1)}× the pot; ${opponents(opponentCount)} hadn't folded.",
        if (missedDraw) "Your earlier draw missed on the river." else null,
        if (blocker) {
            "You hold the ace of that suit, which blocks some nut flushes, but that doesn't mean the opponent will fold."
        } else {
            "No nut-flush ace blocker was detected, so don't assume the opponent will fold often."
        },
    )
    val bigBetLesson = "Give your bluff a clear target range instead of making up for a weak hand with a huge size."
    val bigBetPlan = "Without evidence of the opponent's folding tendencies, compare a check or a smaller line first; the exact value of the bluff isn't calculated here."

    // value-check
    val valueCheckTitle = "Compare this check with a value bet"
    fun valueCheckReason(hand: HandLabel, texture: String, opponentCount: Int, inPosition: Boolean, overpair: Boolean) = sentences(
        "You had ${hand.phrase} on a board that's $texture, with ${opponents(opponentCount)} left.",
        if (inPosition) "You have position and act last." else "You act before the remaining opponents, and checking keeps an inducing line open.",
        if (overpair) {
            "An overpair can get value from worse pairs and some draws, but don't ignore stronger made hands."
        } else {
            "Your made hand has value potential; whether checking is better still depends on how often opponents call and bet on their own."
        },
    )
    val valueCheckLessonWet = "Weigh value against protection: make worse made hands and draws pay, while keeping a plan for facing a raise."
    val valueCheckLessonDry = "On a dry board, consider a smaller value size that leaves room for worse hands to continue."
    fun valueCheckPlan(alternative: String) =
        "Compare with $alternative; if raised, reassess how many strong hands the raiser has, and don't read \"can bet\" as \"must continue.\""

    // multiway-top-pair
    val multiwayTopPairTitle = "Top pair on a wet multiway board must realize equity carefully"
    fun multiwayTopPairReason(hand: HandLabel, opponentCount: Int, texture: String, priced: String, estimated: String) = sentences(
        "${hand.start} against ${opponents(opponentCount)} on a board that's $texture.",
        priced,
        estimated,
        "In a multiway pot, one pair's showdown value is more easily caught by two pair, trips, or draws.",
    )
    val multiwayTopPairLesson = "Keep judging by price, and lean less toward treating top pair as an all-in value hand."
    val multiwayTopPairPlan = "If you face another big bet next street, recalculate on the new board; having called once isn't a reason to keep calling."

    // tight-fold
    val tightFoldTitle = "This fold may be too tight; worth rechecking ranges"
    fun tightFoldReason(hand: HandLabel, priced: String, estimated: String) = sentences(
        "You had ${hand.phrase}.",
        priced,
        estimated,
        "Under both range assumptions your equity beats the price with room to spare, but that hasn't been shown for the opponent's real range.",
    )
    val tightFoldLesson = "Separate an opponent who is actually strong from simply being afraid to lose; without enough range evidence, keep both lines in mind."
    val tightFoldPlanClosing = "Focus on the opponent's value and bluff combinations; don't rely on implied odds from later streets."
    val tightFoldPlanOpen = "If you call, plan for bad cards and re-raises first, and don't treat all of your current equity as realizable."

    // priced-fold
    val pricedFoldTitle = "Recheck this fold against the price and risk at the time"
    fun pricedFoldReason(hand: HandLabel, position: String, callAmount: Int, texture: String?, priced: String?, outs: Int, nextChance: Double) = sentences(
        "You held ${hand.phrase} in $position and needed ${number(callAmount)} more.",
        texture?.let { "The board is $it." },
        priced,
        if (outs != 0) {
            "You have ${cards(outs)}, about ${percent(nextChance)} on the next card, which doesn't guarantee a win."
        } else {
            noDirectDraw
        },
    )
    val noDirectDraw = "No direct straight or flush draw was detected."
    val pricedFoldLesson = "Base your exit conditions on the current price, hand strength, and position; chips already in the pot are no reason you must continue."
    val pricedFoldPlan = "When replaying, you can compare another line, but good cards that come later don't prove you should have called."

    // priced-call / multi-street-call
    val callTitleMulti = "After calling several streets, evaluate the current price on its own"
    val callTitle = "This call depends on price and your ability to realize equity"
    fun callReason(hand: HandLabel, opponentCount: Int, priced: String, estimated: String, pastCalls: Int, outs: Int, nextChance: Double) = sentences(
        "You held ${hand.phrase}, with ${opponents(opponentCount)} still in.",
        priced,
        estimated,
        if (pastCalls >= 2) "You already called on $pastCalls earlier streets; past investment doesn't increase your equity now." else null,
        if (outs != 0) "${cap(cards(outs))}, about ${percent(nextChance)} on the next card." else null,
    )
    val callLessonClosing = "There are no later bets to save chips for, so focus on comparing range assumptions with the price."
    val callLessonOpen = "Having room on the price doesn't mean you can call down automatically; further action and equity realization are still risky."
    val callPlanClosing = "Recalculate this call against different opponent ranges and see whether the conclusion holds."
    fun callPlanOpen(pendingOthers: Int) =
        "Watch the ${players(pendingOthers)} who can still act, and whether the next card brings a stronger straight or flush texture."

    // value-bet / draw-bet / pressure-bet
    val raiseTitleValue = "This bet has value targets you can check"
    val raiseTitleDraw = "Betting with a draw: also consider your equity when called"
    val raiseTitlePressure = "The payoff from applying pressure depends on what folds"
    fun raiseReason(
        hand: HandLabel,
        extra: Int,
        betRatio: Double,
        board: String?,
        opponentCount: Int,
        outs: Int,
        nextChance: Double,
        valueTarget: Boolean,
    ) = sentences(
        "${hand.start}: put in an extra ${number(extra)}, about ${percent(betRatio)} of the pot; the board is ${board ?: "not dealt yet"}, " +
            "with ${opponents(opponentCount)} still in.",
        when {
            outs != 0 -> "You also have ${cards(outs)}, about ${percent(nextChance)} on the next card."
            valueTarget -> "You can try to get value from worse hands; which hands the opponent will call with still needs judging."
            else -> "No direct straight or flush draw was detected, so don't assume you have enough chances to improve when called."
        },
    )
    val raiseLessonValue = "List the specific worse hands that will pay; a hand's name doesn't prove the best size."
    val raiseLessonOther = "First work out which opponent ranges will fold, then judge whether you can continue when called."
    val raisePlanShortAllin = "This is an all-in for less than a full raise, so it doesn't necessarily reopen raising for players who have already acted."
    val raisePlan = "If re-raised, compare the price and ranges again; if called, plan a new value or exit line for the next street's board."

    // board-check / draw-check / pot-control
    val checkTitleBoard = "The board makes the hand; your hole cards add nothing"
    val checkTitleDraw = "Checking keeps the draw without growing the pot early"
    val checkTitleControl = "This check controls the pot"
    fun checkReason(hand: HandLabel, texture: String, outs: Int, nextChance: Double, pendingOthers: Int) = sentences(
        "You had ${hand.phrase} on a board that's $texture, with nothing to call.",
        when {
            outs != 0 -> "You have ${cards(outs)}, about ${percent(nextChance)} on the next card; checking means you don't pay extra for that chance."
            pendingOthers != 0 -> "${cap(players(pendingOthers))} can still act after you, so checking doesn't guarantee a free card."
            else -> "You can see the next card or go to showdown."
        },
    )
    val checkLesson = "After checking, still separate a free chance from your conditions for continuing against a bet."
    val checkPlan = "If someone bets, recalculate with the actual amount; if the board alone makes the hand, think about a split first and don't invent an edge from your hole cards."

    // ev_* — evidence list.
    fun evPosition(position: String, opponentCount: Int, street: Int, inPosition: Boolean) =
        "Position $position · ${opponents(opponentCount)} in the hand" +
            (if (street != 0) " · " + (if (inPosition) "In position" else "Not last to act") else "")
    fun evHand(hand: HandLabel) = "Hand at the time: ${hand.start}"
    fun evBoard(texture: String) = "Board: ${cap(texture)}"
    fun evPreflop(preflopRaises: Int, pendingOthers: Int) = "Preflop raises: $preflopRaises · Still to act: $pendingOthers"
    fun evStack(effective: Int, spr: Double) = "Effective stack ≈ ${number(effective)} · SPR ${jsToFixed(spr, 1)}"
    fun evDraw(outs: Int, nextChance: Double) =
        "Direct completion cards: $outs (deduplicated) · ≈${percent(nextChance)} on the next card, not a win rate"
    fun evPreflopContext(prePhrase: String, limpers: Int, ace: Boolean) =
        "Preflop situation: ${cap(prePhrase)} · Limpers: $limpers" + (if (ace) " · An ace blocker isn't an edge once called" else "")

    // Simulation override.
    fun simReasonSuffix(alternative: String) =
        " In the candidate-action simulation, $alternative showed a fairly clear chip advantage under both ranges and is worth " +
            "practicing instead of the original heuristic suggestion; the edge depends on the simulated follow-up strategy and doesn't prove optimal play."
    fun simSummary(alternative: String) = "Simulation pick: $alternative"
    val simPrimaryCondition = "When this hand's public styles, the two starting ranges, and the balanced follow-up strategy are representative of your practice games."
    val simPrimaryTradeoff = "The samples support comparing this first, but real continuing ranges and better follow-up play could still change the ranking."
    val simSecondaryCondition = "When opponent ranges or the follow-up strategy change, keep the original conservative / value line as a comparison."
    val simSecondaryTradeoff = "Judge using the numbers below and the specific conditions; a simulated lead doesn't mean you must take that line."
    val simPlanSuffix = " When replaying, compare the simulation pick with the original line first; if opponents defend very differently, analyze again."

    // sum_* — review summary.
    fun summary(decisions: Int, extra: Int, step: Int, street: String, title: String, otherThemes: Int) = sentences(
        "${count(decisions, "decision", "decisions")}, ${number(extra)} chips put in. Start with step $step ($street): $title.",
        if (otherThemes > 0) "${count(otherThemes, "other issue", "other issues")} to look through step by step." else null,
    )
    val summaryNoDecisions = "You made no decisions this hand; forced blinds can't count as mistakes."
    fun titleAttention(title: String) = "Check first: $title"
    fun titleConsider(title: String) = "Worth comparing: $title"
    val titleClean = "No obvious decision mistakes found"
}
