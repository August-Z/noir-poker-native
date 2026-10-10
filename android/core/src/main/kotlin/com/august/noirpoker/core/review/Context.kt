package com.august.noirpoker.core.review

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.Card
import com.august.noirpoker.core.HandEvaluation
import com.august.noirpoker.core.HistoryEntry
import com.august.noirpoker.core.compare
import com.august.noirpoker.core.deckOfCards
import com.august.noirpoker.core.evaluate
import com.august.noirpoker.core.rankText

/** Starting-hand tier 0 (weak) … 3 (premium). */
fun startingTier(hole: List<Card>): Int {
    if (hole.size != 2) return 0
    val high = maxOf(hole[0].rank, hole[1].rank)
    val low = minOf(hole[0].rank, hole[1].rank)
    val suited = hole[0].suit == hole[1].suit
    val gap = high - low
    if ((high == low && high >= 11) || (high == 14 && low == 13)) return 3
    if ((high == low && high >= 8) || (high == 14 && low >= 10) || (suited && high >= 12 && low >= 10)) return 2
    if (high == low ||
        (suited && high == 14) ||
        (high >= 11 && low >= 10) ||
        (suited && gap <= 2 && low >= 5) ||
        (high == 14 && low >= 8)
    ) {
        return 1
    }
    return 0
}

/** Direct straight / flush completion cards. They are not guaranteed winning outs. */
data class DrawInfo(
    val flush: Boolean = false,
    val straight: Boolean = false,
    val flushOuts: Int = 0,
    val straightOuts: Int = 0,
    val outs: Int = 0,
    val nextChance: Double = 0.0,
)

// Completion cards are not guaranteed winning outs. Public information only.
fun drawInfo(hole: List<Card>, board: List<Card>): DrawInfo {
    if (board.size < 3 || board.size >= 5) return DrawInfo()
    val known = hole + board
    val keys = known.map { it.key }.toSet()
    val holeKeys = hole.map { it.key }.toSet()
    val made = evaluate(known)
    val flush = LinkedHashSet<String>()
    val straight = LinkedHashSet<String>()
    for (c in deckOfCards()) {
        if (c.key in keys) continue
        val next = evaluate(known + c)
        if (compare(next.score, made.score) <= 0 || next.cards.none { it.key in holeKeys }) continue
        if (made.score[0] < 5 && (next.score[0] == 5 || next.score[0] == 8)) flush.add(c.key)
        if (made.score[0] < 4 && (next.score[0] == 4 || next.score[0] == 8)) straight.add(c.key)
    }
    val outs = (flush + straight).size
    return DrawInfo(
        flush = flush.isNotEmpty(),
        straight = straight.isNotEmpty(),
        flushOuts = flush.size,
        straightOuts = straight.size,
        outs = outs,
        nextChance = outs.toDouble() / (52 - keys.size),
    )
}

data class BoardTexture(
    val paired: Boolean,
    val trips: Boolean,
    val maxSuit: Int,
    val connected: Int,
    val wet: Boolean,
    /** Mid-sentence description, e.g. `"paired, three to a flush"`. */
    val phrase: String,
) {
    /** Standalone form: `"Paired, three to a flush"`. */
    val label: String get() = cap(phrase)
}

fun boardTexture(board: List<Card>): BoardTexture {
    val suits = (0 until 4).map { s -> board.count { it.suit == s } }
    val counts = LinkedHashMap<Int, Int>()
    for (c in board) counts[c.rank] = (counts[c.rank] ?: 0) + 1
    val ranks = board.map { it.rank }.toMutableSet()
    if (14 in ranks) ranks.add(1)
    val connected = maxOf(0, (0 until 10).maxOf { i -> (1..5).count { j -> (i + j) in ranks } })
    val maxSuit = maxOf(0, suits.max())
    val paired = counts.values.any { it >= 2 }
    val trips = counts.values.any { it >= 3 }
    val tags = mutableListOf<String>()
    if (paired) tags.add(if (trips) ReviewCopy.boardTrips else ReviewCopy.boardPaired)
    if (maxSuit >= 4) {
        tags.add(ReviewCopy.boardFourFlush)
    } else if (maxSuit == 3) {
        tags.add(ReviewCopy.boardThreeFlush)
    } else if (board.size == 3 && maxSuit == 2) {
        tags.add(ReviewCopy.boardTwoTone)
    }
    if (connected >= 4) tags.add(ReviewCopy.boardFourConnected) else if (connected == 3) tags.add(ReviewCopy.boardThreeConnected)
    return BoardTexture(
        paired = paired,
        trips = trips,
        maxSuit = maxSuit,
        connected = connected,
        wet = maxSuit >= 3 || connected >= 3 || (board.size == 3 && maxSuit == 2),
        phrase = tags.joinToString(", ").ifEmpty { ReviewCopy.boardDry },
    )
}

/** The reference `handClass` identifiers. */
/**
 * A hero hand description: [phrase] reads mid-sentence (`"two pair"`, `"pocket Nines"`);
 * [start] begins a sentence or stands alone (`"Two Pair"`, `"Pocket Nines"`).
 */
data class HandLabel(val phrase: String, val start: String = cap(phrase)) {
    override fun toString(): String = start
}

enum class HandClass(val id: String) {
    HIGH("high"),
    POCKET("pocket"),
    UNPAIRED("unpaired"),
    BOARD("board"),
    STRONG("strong"),
    SET("set"),
    TRIPS("trips"),
    OVERPAIR("overpair"),
    TWO_PAIR("two-pair"),
    UNDERPAIR("underpair"),
    BOARD_PAIR("board-pair"),
    TOP_PAIR("top-pair"),
    MIDDLE_PAIR("middle-pair"),
}

data class DecisionContext(
    val made: HandEvaluation,
    val texture: BoardTexture,
    val draw: DrawInfo,
    /** Non-folded opponents, all-in ones included. */
    val opponents: Int,
    val handClass: HandClass,
    val handLabel: HandLabel,
    val inPosition: Boolean,
    val pendingOthers: Int,
    val effective: Int,
    val spr: Double,
    val extra: Int,
    val betRatio: Double,
    val preflopRaises: Int,
    val facingRaise: HistoryEntry?,
    /** Distinct earlier streets on which the hero called. */
    val pastCalls: Int,
    val pastCallActions: Int,
    val nutFlushBlocker: Boolean,
    val missedDraw: Boolean,
    val tier: Int,
)

private val ACTION_ORDER = listOf("SB", "BB", "UTG", "UTG+1", "MP", "LJ", "HJ", "CO", "BTN")

fun decisionContext(s: ReviewDecision): DecisionContext {
    val made = evaluate(s.hole + s.board)
    val texture = boardTexture(s.board)
    val draw = drawInfo(s.hole, s.board)
    val opponents = s.players.filter { it.id != 0 && !it.folded }
    val high = maxOf(0, s.board.maxOfOrNull { it.rank } ?: 0)
    val pocket = s.hole.size == 2 && s.hole[0].rank == s.hole[1].rank
    val holeRank = s.hole.getOrNull(0)?.rank ?: 0
    val playsBoard = s.board.size == 5 && compare(made.score, evaluate(s.board).score) == 0
    val madeLabel = HandLabel(ReviewCopy.engineHandPhrase(made.label), made.label)
    var handClass = HandClass.HIGH
    var handLabel = madeLabel
    if (s.street == 0) {
        handClass = if (pocket) HandClass.POCKET else HandClass.UNPAIRED
        handLabel = if (pocket) {
            HandLabel(ReviewCopy.handPocket(holeRank))
        } else {
            HandLabel(
                ReviewCopy.handUnpaired(
                    s.hole.map { rankText(it.rank) },
                    s.hole.getOrNull(0)?.suit == s.hole.getOrNull(1)?.suit,
                ),
            )
        }
    } else if (playsBoard) {
        handClass = HandClass.BOARD
        handLabel = HandLabel(ReviewCopy.handPlaysBoard)
    } else if (made.score[0] >= 4) {
        handClass = HandClass.STRONG
    } else if (pocket && made.score[0] == 3) {
        handClass = HandClass.SET
        handLabel = HandLabel(ReviewCopy.handSet(holeRank))
    } else if (made.score[0] == 3) {
        handClass = HandClass.TRIPS
    } else if (pocket && holeRank > high) {
        handClass = HandClass.OVERPAIR
        handLabel = HandLabel(ReviewCopy.handOverpair(holeRank, texture.paired))
    } else if (made.score[0] == 2) {
        handClass = HandClass.TWO_PAIR
    } else if (made.score[0] == 1) {
        if (pocket) {
            handClass = HandClass.UNDERPAIR
            handLabel = HandLabel(ReviewCopy.handUnderpair(holeRank))
        } else {
            val pairedIndex = s.hole.indexOfFirst { c -> s.board.any { it.rank == c.rank } }
            val paired = s.hole.getOrNull(pairedIndex)
            val kicker = s.hole.filterIndexed { i, _ -> i != pairedIndex }.firstOrNull()
            handClass = when {
                paired == null -> HandClass.BOARD_PAIR
                paired.rank == high -> HandClass.TOP_PAIR
                else -> HandClass.MIDDLE_PAIR
            }
            handLabel = if (paired == null) {
                HandLabel(ReviewCopy.handBoardPair(made.score[1]))
            } else {
                val kickerRank = kicker?.rank?.takeIf { it != 0 } ?: made.score[2]
                HandLabel(ReviewCopy.handPair(handClass == HandClass.TOP_PAIR, rankText(made.score[1]), rankText(kickerRank)))
            }
        }
    }
    val heroOrder = ACTION_ORDER.indexOf(s.position)
    val inPosition = opponents.all { ACTION_ORDER.indexOf(it.position) < heroOrder }
    val pendingOthers = s.pending.count { id ->
        val p = s.players.getOrNull(id)
        id != 0 && p?.folded != true && p?.allin != true
    }
    val effective = minOf(s.stack, maxOf(0, opponents.maxOfOrNull { it.stack } ?: 0))
    val spr = if (s.pot != 0) effective.toDouble() / s.pot else 0.0
    val extra = when (s.action) {
        Action.RAISE -> s.amount - s.bet
        Action.CALL -> s.legal.callAmount
        else -> 0
    }
    val raises = s.history.filter { it.action == Action.RAISE }
    val earlierCalls = s.history.filter { it.id == 0 && it.action == Action.CALL && it.street < s.street }
    val flushSuit = if (texture.maxSuit >= 3) (0 until 4).firstOrNull { suit -> s.board.count { it.suit == suit } >= 3 } else null
    val previousDraw = if (s.street == 3) drawInfo(s.hole, s.board.take(4)) else null
    return DecisionContext(
        made = made,
        texture = texture,
        draw = draw,
        opponents = opponents.size,
        handClass = handClass,
        handLabel = handLabel,
        inPosition = inPosition,
        pendingOthers = pendingOthers,
        effective = effective,
        spr = spr,
        extra = extra,
        betRatio = if (s.pot != 0) extra.toDouble() / s.pot else 0.0,
        preflopRaises = raises.count { it.street == 0 },
        facingRaise = raises.lastOrNull { it.street == s.street },
        pastCalls = earlierCalls.map { it.street }.toSet().size,
        pastCallActions = earlierCalls.size,
        nutFlushBlocker = flushSuit != null && s.hole.any { it.suit == flushSuit && it.rank == 14 },
        missedDraw = (previousDraw?.outs ?: 0) != 0 && made.score[0] < 4,
        tier = startingTier(s.hole),
    )
}
