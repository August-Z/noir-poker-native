package com.august.noirpoker.core

import kotlin.test.Test
import kotlin.test.assertEquals

class CardsTest {
    private fun rank(text: String) = evaluate(cards(text)).score[0]

    @Test
    fun `deck has 52 unique cards in suit-major order`() {
        val deck = deckOfCards()
        assertEquals(52, deck.map { it.key }.toSet().size)
        assertEquals("0-2", deck.first().key)
        assertEquals("3-14", deck.last().key)
        assertEquals("♦", deck.last().symbol)
    }

    @Test
    fun `every hand category is recognized`() {
        assertEquals(8, rank("As Ks Qs Js Ts 2h 3c"))
        assertEquals(7, rank("Ac Ah As Ad Kh 2s 3s"))
        assertEquals(6, rank("Ac Ah As Kd Kh Qs Qh"))
        assertEquals(5, rank("As Js 9s 5s 3s Kh Qh"))
        assertEquals(4, rank("As 2h 3c 4d 5s Kh Qh"))
        assertEquals(3, rank("As Ah Ac 9d 8s 2h 3h"))
        assertEquals(2, rank("As Ah Kc Kd Qs 2h 3h"))
        assertEquals(1, rank("As Ah Kc Qd 9s 2h 3h"))
        assertEquals(0, rank("As Kh Qc Jd 9s 2h 3h"))
        assertEquals("Royal Flush", evaluate(cards("As Ks Qs Js Ts 2h 3c")).label)
        assertEquals("Pocket Pair", evaluate(cards("7s 7h")).label)
        assertEquals(listOf(1, 7, 7), evaluate(cards("7s 7h")).score)
    }

    @Test
    fun `aces play low but never wrap around`() {
        assertEquals(0, rank("Ks Ah 2c 3d 4s"))
        assertEquals(-1, compare(evaluate(cards("As 2h 3c 4d 5s")).score, evaluate(cards("2h 3c 4d 5s 6h")).score))
    }

    @Test
    fun `kickers count only within the best five cards`() {
        assertEquals(listOf(6, 14, 13), evaluate(cards("As Ah Ac Ks Kh Kc 2s")).score)
        assertEquals(1, compare(evaluate(cards("As Ah Kc Qd 9s")).score, evaluate(cards("Ad Ac Kd Jh 9h")).score))
        assertEquals(
            1,
            compare(evaluate(cards("As Ah Ks Qs Js 2c 3c")).score, evaluate(cards("Ad Ac Kc Qc Tc 9h 8h")).score),
        )
        assertEquals(listOf(7, 14, 13), evaluate(cards("As Ah Ac Ad Ks Qh Jc")).score)
        val board = "As Kd Qc Jh Ts"
        assertEquals(0, compare(evaluate(cards("$board 2s 3s")).score, evaluate(cards("$board 9h 8h")).score))
    }

    @Test
    fun `chip formatting uses en-US grouping and JavaScript rounding`() {
        assertEquals("5,000", formatChips(5000))
        assertEquals("1,234,567", formatChips(1234567))
        assertEquals("125", formatChips(125))
        assertEquals(3.0, jsRound(2.5))
        assertEquals(-2.0, jsRound(-2.5))
        assertEquals(0.0, jsRound(0.49999999999999994))
    }
}
