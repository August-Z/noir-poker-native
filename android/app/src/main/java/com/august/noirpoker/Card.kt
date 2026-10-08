package com.august.noirpoker

data class Card(val rank: Int, val suit: Int) {
    init { require(rank in 2..14 && suit in 0..3) }
    val key: String get() = "$suit-$rank"
    val symbol: String get() = listOf("♠", "♥", "♣", "♦")[suit]
    val rankText: String get() = when (rank) { 11 -> "J"; 12 -> "Q"; 13 -> "K"; 14 -> "A"; else -> rank.toString() }
    companion object { fun fullDeck(): List<Card> = (0..3).flatMap { suit -> (2..14).map { Card(it, suit) } } }
}
