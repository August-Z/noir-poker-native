package com.august.noirpoker.core

/** Suit symbols by suit index: 0 spades, 1 hearts, 2 clubs, 3 diamonds. */
val SUITS: List<String> = listOf("♠", "♥", "♣", "♦")

/** A card. `rank` is 2..14 (ace = 14); equality of cards is by [key]. */
data class Card(val rank: Int, val suit: Int) {
    val symbol: String get() = SUITS[suit]
    val key: String get() = "$suit-$rank"

    override fun toString(): String = rankText(rank) + symbol
}

fun rankText(r: Int): String = when (r) {
    11 -> "J"
    12 -> "Q"
    13 -> "K"
    14 -> "A"
    else -> r.toString()
}

/** Suit-major, rank-ascending order: `0-2 … 0-14, 1-2 … 3-14`. */
fun deckOfCards(): MutableList<Card> {
    val deck = ArrayList<Card>(52)
    for (suit in 0 until 4) for (i in 0 until 13) deck.add(Card(i + 2, suit))
    return deck
}

/** Fisher–Yates in place; consumes exactly `a.size - 1` random values. */
fun <T> shuffle(a: MutableList<T>, random: RandomSource = SystemRandom): MutableList<T> {
    for (i in a.size - 1 downTo 1) {
        val j = kotlin.math.floor(random.next() * (i + 1)).toInt()
        val t = a[i]
        a[i] = a[j]
        a[j] = t
    }
    return a
}

/**
 * Parses the compact test notation `"As Kd Tc 2h"`: rank from `23456789TJQKA`,
 * suit from `shcd`.
 */
fun parseCards(text: String): List<Card> =
    text.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.map { token ->
        val rank = "23456789TJQKA".indexOf(token[0].uppercaseChar()) + 2
        val suit = "shcd".indexOf(token[1].lowercaseChar())
        require(rank >= 2 && suit >= 0) { "Invalid card: $token" }
        Card(rank, suit)
    }

/** Hand category names indexed by `score[0]`. */
val RANK_NAMES: List<String> get() = EngineCopy.rankNames

/** Lexicographic score comparison; missing positions count as 0. */
fun compare(a: List<Int>, b: List<Int>): Int {
    for (i in 0 until maxOf(a.size, b.size)) {
        val d = a.getOrElse(i) { 0 } - b.getOrElse(i) { 0 }
        if (d != 0) return Integer.signum(d)
    }
    return 0
}

data class HandEvaluation(val score: List<Int>, val label: String, val cards: List<Card>)

private fun evaluateFive(cards: List<Card>): List<Int> {
    val ranks = cards.map { it.rank }.sortedDescending()
    val unique = ranks.distinct()
    val flush = cards.all { it.suit == cards[0].suit }
    var straight = if (unique.size == 5 && unique[0] - unique[4] == 4) unique[0] else 0
    if (unique == listOf(14, 5, 4, 3, 2)) straight = 5
    val groups = unique.map { r -> r to ranks.count { it == r } }
        .sortedWith(compareByDescending<Pair<Int, Int>> { it.second }.thenByDescending { it.first })
    if (flush && straight != 0) return listOf(8, straight)
    if (groups[0].second == 4) return listOf(7, groups[0].first, groups[1].first)
    if (groups[0].second == 3 && groups[1].second == 2) return listOf(6, groups[0].first, groups[1].first)
    if (flush) return listOf(5) + ranks
    if (straight != 0) return listOf(4, straight)
    if (groups[0].second == 3) return listOf(3, groups[0].first) + groups.drop(1).map { it.first }
    if (groups[0].second == 2 && groups[1].second == 2) {
        return listOf(
            2,
            maxOf(groups[0].first, groups[1].first),
            minOf(groups[0].first, groups[1].first),
            groups[2].first,
        )
    }
    if (groups[0].second == 2) return listOf(1, groups[0].first) + groups.drop(1).map { it.first }
    return listOf(0) + ranks
}

/**
 * Best five-card hand. With fewer than five cards (preflop hole cards) the
 * score is `[1, r, r]` for a pocket pair, otherwise `[0, ...ranks]`. Among equal
 * best scores the earliest combination in input order supplies [HandEvaluation.cards].
 */
fun evaluate(cards: List<Card>): HandEvaluation {
    if (cards.size < 5) {
        val ranks = cards.map { it.rank }.sortedDescending()
        val pair = ranks.size == 2 && ranks[0] == ranks[1]
        return HandEvaluation(
            listOf(if (pair) 1 else 0) + ranks,
            if (pair) EngineCopy.pocketPair else EngineCopy.rankNames[0],
            cards.toList(),
        )
    }
    var best: List<Int>? = null
    var bestCards: List<Card> = emptyList()
    val n = cards.size
    for (a in 0 until n - 4) for (b in a + 1 until n - 3) for (c in b + 1 until n - 2)
        for (d in c + 1 until n - 1) for (e in d + 1 until n) {
            val picked = listOf(cards[a], cards[b], cards[c], cards[d], cards[e])
            val score = evaluateFive(picked)
            if (best == null || compare(score, best) > 0) {
                best = score
                bestCards = picked
            }
        }
    val score = best!!
    return HandEvaluation(
        score,
        if (score[0] == 8 && score[1] == 14) EngineCopy.royalFlush else EngineCopy.rankNames[score[0]],
        bestCards,
    )
}
