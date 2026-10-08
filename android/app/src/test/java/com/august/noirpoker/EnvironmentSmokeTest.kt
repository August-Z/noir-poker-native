package com.august.noirpoker

import org.junit.Assert.assertEquals
import org.junit.Test

class EnvironmentSmokeTest {
    @Test fun deckMatchesReferenceOrderingAndHas52DistinctCards() {
        val deck = Card.fullDeck()
        assertEquals(52, deck.map { it.key }.distinct().size)
        assertEquals(Card(2, 0), deck.first())
        assertEquals(Card(14, 3), deck.last())
    }
    @Test fun standardPokerRanksAreEnglish() {
        assertEquals("A", Card(14, 0).rankText)
        assertEquals("10", Card(10, 1).rankText)
    }
}
