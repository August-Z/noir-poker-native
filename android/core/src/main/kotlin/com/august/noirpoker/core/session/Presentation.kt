package com.august.noirpoker.core.session

import com.august.noirpoker.core.Card
import com.august.noirpoker.core.Game
import com.august.noirpoker.core.LogEntry
import com.august.noirpoker.core.LogType
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.Player
import com.august.noirpoker.core.contestableAfterCall
import com.august.noirpoker.core.evaluate
import com.august.noirpoker.core.formatChips
import com.august.noirpoker.core.getBotProfile
import com.august.noirpoker.core.jsRound
import com.august.noirpoker.core.legalActions

// Pure projections of engine state used by the render state. None of these
// mutate the game or draw random numbers.

/** A run of display text; persona suffixes are marked so the UI can style them. */
data class TextSegment(val text: String, val isPersona: Boolean = false)

fun List<TextSegment>.plainText(): String = joinToString("") { it.text }

/**
 * The reference `createActivityFormatter(players)`: every whole-word mention of
 * an opponent whose style is not Balanced gets the style's short name as a
 * suffix, e.g. `Alex (ST Wang): Call 50`. The identities are captured when the
 * formatter is created, so saved-but-pending settings never relabel the current
 * hand. The hero is never annotated.
 */
class ActivityFormatter(players: List<Player>) {
    private val personas: Map<String, String> = players
        .filter { it.id != 0 }
        .map { it.name to getBotProfile(it.botProfile) }
        .filter { it.second.id != "balanced" }
        .associate { it.first to it.second.short }

    private val pattern: Regex? = if (personas.isEmpty()) {
        null
    } else {
        // ASCII word boundaries like JavaScript's `\b`; skip names that are already annotated.
        Regex("(?<![A-Za-z0-9_])(" + personas.keys.joinToString("|") { Regex.escape(it) } + ")(?![A-Za-z0-9_])(?! ?[（(])")
    }

    /**
     * [skipLeadingStreetName]: in English the bot "River" collides with the
     * street name in `River · 7♠`; a street log's leading street name is never a
     * player mention.
     */
    fun format(text: String, skipLeadingStreetName: Boolean = false): List<TextSegment> {
        val regex = pattern ?: return listOf(TextSegment(text))
        val out = mutableListOf<TextSegment>()
        var last = 0
        for (m in regex.findAll(text)) {
            if (skipLeadingStreetName && m.range.first == 0 && text.startsWith(m.value + " · ")) continue
            val end = m.range.last + 1
            if (end > last) out.add(TextSegment(text.substring(last, end)))
            out.add(TextSegment(SessionCopy.personaSuffix(personas.getValue(m.value)), isPersona = true))
            last = end
        }
        if (last < text.length) out.add(TextSegment(text.substring(last)))
        return out.ifEmpty { listOf(TextSegment(text)) }
    }

    fun formatLog(entry: LogEntry): List<TextSegment> =
        format(entry.text, skipLeadingStreetName = entry.type == LogType.STREET)
}

/** The seat's action chip (`seatAction`): a label, an optional amount and its meaning. */
data class ActionChip(
    val label: String,
    val amount: Int? = null,
    val amountText: String? = null,
    /** The tooltip / accessibility hint for the amount. */
    val meaning: String? = null,
    /** The seat is the current actor and is deciding (blinking dots). */
    val isDeciding: Boolean = false,
)

private val ACTION_PATTERN =
    Regex("^(?:(\\d+-bet) )?(SB|BB|Call|short all-in to|all-in to|open to|raise to|bet to|All-In) ([\\d,]+)$")

/**
 * The reference `seatAction(p, {recent})`. Seats show the current-street action
 * during play and the retained last action after settlement; the hero area
 * ([recent] = true) always shows the retained last action, with the street.
 */
fun seatActionChip(g: Game, p: Player, recent: Boolean = false): ActionChip {
    if (!recent && g.actor == p.id) return ActionChip(SessionCopy.thinking, isDeciding = true)
    val retained = if (recent || g.phase == Phase.DONE) p.lastAction else null
    val action = retained?.text ?: p.action
    val match = ACTION_PATTERN.matchEntire(action)
        ?: return ActionChip(action.ifEmpty { if (g.phase == Phase.DONE) SessionCopy.noAction else SessionCopy.waiting })
    val level = match.groupValues[1]
    val verb = match.groupValues[2]
    val amount = match.groupValues[3].replace(",", "").toIntOrNull() ?: return ActionChip(action)
    val label = if (level.isNotEmpty()) {
        when (verb) {
            "short all-in to" -> "$level ${SessionCopy.labelShortAllIn}"
            "all-in to" -> "$level ${SessionCopy.labelAllIn}"
            else -> if (recent) "$level ${SessionCopy.recentVerbs[verb] ?: verb}" else level
        }
    } else if (verb == "raise to") {
        SessionCopy.bareRaise
    } else {
        verb
    }
    val prefix = if (recent && retained != null) (SessionCopy.street(retained.street)?.let { "$it · " } ?: "") else ""
    val meaning = prefix + if (verb == "Call") {
        SessionCopy.meaningCall(amount, retained?.bet ?: p.bet)
    } else {
        SessionCopy.meaningOther(action, amount)
    }
    return ActionChip(label, amount, formatChips(amount), meaning)
}

/** The coaching hint (`updateCoach`), computed whether or not hints are shown. */
fun coachTip(g: Game): String {
    val p = g.players[0]
    val e = evaluate(p.hole + g.board)
    var tip = when {
        g.phase == Phase.DONE -> when {
            p.folded -> SessionCopy.tipDoneFolded
            g.showdown -> SessionCopy.tipDoneShowdown(SessionCopy.handNoun(e.label))
            else -> SessionCopy.tipDoneUncontested
        }
        g.street == 0 -> {
            val a = p.hole.getOrNull(0)
            val b = p.hole.getOrNull(1)
            when {
                a?.rank == b?.rank -> SessionCopy.tipPrePair
                a != null && b != null && a.rank >= 11 && b.rank >= 11 -> SessionCopy.tipPreBroadway
                a?.suit == b?.suit -> SessionCopy.tipPreSuited
                else -> SessionCopy.tipPreOther
            }
        }
        e.score[0] >= 3 -> SessionCopy.tipMadeStrong(SessionCopy.handNoun(e.label))
        e.score[0] >= 1 -> SessionCopy.tipMadePair(SessionCopy.handNoun(e.label))
        else -> SessionCopy.tipUnpaired
    }
    val legal = legalActions(g, 0)
    if (legal.enabled && legal.toCall > 0) {
        val pct = jsRound(legal.callAmount.toDouble() / contestableAfterCall(g, 0, legal.callAmount) * 100).toInt()
        tip += SessionCopy.tipPriceSuffix(pct)
    }
    return tip
}

fun coachStage(g: Game): String =
    if (g.phase == Phase.DONE) SessionCopy.coachStageDone else SessionCopy.coachStage(SessionCopy.street(g.street) ?: "")

/** Showdown card motion (`HAND_MOTIONS`, plus `royal`). [id] is the reference class suffix. */
enum class HandMotion(val id: String) {
    HIGH("high"), PAIR("pair"), TWO_PAIR("two-pair"), TRIPS("trips"), STRAIGHT("straight"), FLUSH("flush"),
    FULL_HOUSE("full-house"), QUADS("quads"), STRAIGHT_FLUSH("straight-flush"), ROYAL("royal"),
}

data class ShowdownAward(val pot: String, val amount: Int, val split: Boolean)

/**
 * One player's best five at showdown (`handScene` in `showdown.js`). [cards] are
 * in display order (groups first, straights ascending with a wheel ace low) and
 * [highlights] marks the cards that make the category.
 */
data class HandScene(
    val id: Int,
    val name: String,
    val label: String,
    val motion: HandMotion,
    val cards: List<Card>,
    val highlights: List<Boolean>,
    val explanation: String,
    /** Awards to this player in pot order (empty for a winning-scene entry). */
    val awards: List<ShowdownAward> = emptyList(),
    val amount: Int = 0,
    /** For [winningScenes] entries only: the pot label and whether it was split. */
    val pot: String? = null,
    val split: Boolean = false,
)

fun handScene(g: Game, p: Player): HandScene {
    val rank = evaluate(p.hole + g.board)
    val score = rank.score
    val category = score[0]
    val royal = category == 8 && score[1] == 14
    val counts = HashMap<Int, Int>()
    for (c in rank.cards) counts[c.rank] = (counts[c.rank] ?: 0) + 1
    val wheel = score.getOrNull(1) == 5
    // A stable sort, like JavaScript's Array.prototype.sort.
    val cards = if (category == 4 || category == 8) {
        rank.cards.sortedWith(compareBy { if (wheel && it.rank == 14) 1 else it.rank })
    } else {
        rank.cards.sortedWith(compareByDescending<Card> { counts.getValue(it.rank) }.thenByDescending { it.rank })
    }
    val highlights = cards.map { c ->
        when (category) {
            0 -> c.rank == score[1]
            1, 2, 3, 7 -> counts.getValue(c.rank) > 1
            else -> true
        }
    }
    val explanation = when (category) {
        0 -> SessionCopy.sdHigh(score[1])
        1 -> SessionCopy.sdPair(score[1])
        2 -> SessionCopy.sdTwoPair(score[1], score[2])
        3 -> SessionCopy.sdTrips(score[1])
        4 -> SessionCopy.sdStraight(score[1])
        5 -> SessionCopy.sdFlush(cards[0].symbol, score[1])
        6 -> SessionCopy.sdFullHouse(score[1], score[2])
        7 -> SessionCopy.sdQuads(score[1])
        else -> if (royal) SessionCopy.sdRoyal else SessionCopy.sdStraightFlush(cards[0].symbol, score[1])
    }
    return HandScene(
        id = p.id,
        name = p.name,
        label = rank.label,
        motion = if (royal) HandMotion.ROYAL else HandMotion.entries[category],
        cards = cards,
        highlights = highlights,
        explanation = explanation,
    )
}

/** One scene per non-folded player, in seat order; empty unless settled at a five-card showdown. */
fun showdownScenes(g: Game): List<HandScene> {
    if (g.phase != Phase.DONE || !g.showdown || g.board.size != 5) return emptyList()
    return g.players.filter { !it.folded }.map { p ->
        val awards = g.pots.flatMap { pot ->
            pot.awards.filter { it.id == p.id }.map { ShowdownAward(pot.label, it.amount, pot.awards.size > 1) }
        }
        handScene(g, p).copy(awards = awards, amount = awards.sumOf { it.amount })
    }
}

/** One scene per pot award (`winningScenes`, used by tests). */
fun winningScenes(g: Game): List<HandScene> {
    if (g.phase != Phase.DONE || !g.showdown || g.board.size != 5) return emptyList()
    return g.pots.flatMap { pot ->
        pot.awards.map { a ->
            handScene(g, g.players[a.id]).copy(pot = pot.label, amount = a.amount, split = pot.awards.size > 1)
        }
    }
}
