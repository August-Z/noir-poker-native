package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action

data class PreflopContext(
    /** Raises above the big blind (blind posts never count). */
    val raises: Int,
    val limpers: Int,
    val callersAfterOpen: Int,
    val late: Boolean,
    val unopened: Boolean,
    val ace: Boolean,
    val kicker: Int,
    val suited: Boolean,
    val weakAce: Boolean,
    val ownOpen: Boolean,
    val lastRaiser: Int?,
    val openTo: Int,
    val ratio: Double,
    val openingCandidate: Boolean,
    /** Mid-sentence situation phrase, e.g. `"facing a 3-bet"`. */
    val phrase: String,
) {
    /** Standalone form: `"Facing a 3-bet"`. */
    val label: String get() = cap(phrase)
}

/** Called only for preflop decisions (two hole cards). */
fun preflopContext(s: ReviewDecision): PreflopContext {
    val history = s.history.filter { it.street == 0 }
    val isRaise = { a: com.august.noirpoker.core.HistoryEntry -> a.action == Action.RAISE && a.amount > 50 }
    val raises = history.filter(isRaise)
    val firstRaise = history.indexOfFirst(isRaise)
    val limpers = (if (firstRaise < 0) history else history.subList(0, firstRaise))
        .filter { it.action == Action.CALL && it.id != 0 }
        .map { it.id }
        .toSet()
        .size
    val open = raises.firstOrNull()
    val last = raises.lastOrNull()
    val callersAfterOpen = if (open != null) {
        history.drop(firstRaise + 1).count { it.action == Action.CALL && it.id != 0 && it.id != open.id }
    } else {
        0
    }
    val ranks = s.hole.map { it.rank }.sortedDescending()
    val suited = s.hole[0].suit == s.hole[1].suit
    val late = s.position == "BTN" || s.position == "CO"
    val unopened = raises.isEmpty() && s.currentBet <= 50
    val previousRaise = raises.getOrNull(raises.size - 2)?.amount?.takeIf { it != 0 } ?: 50
    return PreflopContext(
        raises = raises.size,
        limpers = limpers,
        callersAfterOpen = callersAfterOpen,
        late = late,
        unopened = unopened,
        ace = ranks[0] == 14,
        kicker = ranks[1],
        suited = suited,
        weakAce = ranks[0] == 14 && ranks[1] <= 9 && ranks[0] != ranks[1],
        ownOpen = open?.id == 0,
        lastRaiser = last?.id,
        openTo = open?.amount?.takeIf { it != 0 } ?: 50,
        ratio = if (last != null) last.amount.toDouble() / previousRaise else 1.0,
        openingCandidate = startingTier(s.hole) >= 1 || (late && (ranks[0] == 14 || (ranks[0] >= 13 && ranks[1] >= 7))),
        phrase = when {
            raises.isEmpty() -> if (limpers != 0) ReviewCopy.preUnopenedLimped else ReviewCopy.preUnopened
            raises.size == 1 -> if (callersAfterOpen != 0) ReviewCopy.preOpenCalled else ReviewCopy.preFacingOpen
            raises.size == 2 -> ReviewCopy.preFacing3Bet
            else -> ReviewCopy.preFacing4BetPlus
        },
    )
}
