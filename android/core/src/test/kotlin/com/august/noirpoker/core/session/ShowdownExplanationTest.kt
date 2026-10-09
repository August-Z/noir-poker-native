package com.august.noirpoker.core.session

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Every hand category's showdown explanation, winner motion and highlighted
 * cards, mirroring iOS `testShowdownExplanationsCoverEveryCategory`. Each case
 * settles a heads-up showdown (seats 1–5 folded) so the hero's scene is the
 * only one evaluated.
 */
class ShowdownExplanationTest {
    private class Case(
        val hole: String,
        val board: String,
        val explanation: String,
        val motion: HandMotion,
        val highlights: List<Boolean>,
    )

    private val all = listOf(true, true, true, true, true)

    private val cases = listOf(
        Case("Ah 9d", "2c 5s 7h Jd Kc", "Ace-high · Kickers compared in order", HandMotion.HIGH, listOf(true, false, false, false, false)),
        Case("Qh Qc", "4d 6s Kh 2h 8s", "Pair of Queens", HandMotion.PAIR, listOf(true, true, false, false, false)),
        Case("Ah Ad", "Kc Ks 7h 3d 2c", "Aces and Kings", HandMotion.TWO_PAIR, listOf(true, true, true, true, false)),
        Case("7h 7d", "7c Ks Qh 3d 2c", "Three Sevens", HandMotion.TRIPS, listOf(true, true, true, false, false)),
        Case("8c 4d", "5h 6s 7h Kd 2c", "Eight-high straight", HandMotion.STRAIGHT, all),
        Case("Ah 2h", "9h 5h Kh 3d 2c", "♥ flush · Ace-high", HandMotion.FLUSH, all),
        Case("Ah Ad", "Ac Ks Kh 3d 2c", "Aces full of Kings", HandMotion.FULL_HOUSE, all),
        Case("9h 9d", "9c 9s Kh 3d 2c", "Four Nines", HandMotion.QUADS, listOf(true, true, true, true, false)),
        Case("9h 8h", "7h 6h 5h 3d 2c", "♥ straight flush · Nine-high", HandMotion.STRAIGHT_FLUSH, all),
        Case("As Ks", "Qs Js Ts 3d 2c", "10 · J · Q · K · A of one suit", HandMotion.ROYAL, all),
    )

    @Test
    fun `showdown explanations cover every category`() {
        val h = Harness()
        assertEquals(HandMotion.entries.toSet(), cases.map { it.motion }.toSet(), "Every motion has a case")
        for (case in cases) {
            h.scene(case.hole, case.board, folded = listOf(1, 2, 3, 4, 5))
            val scene = handScene(h.game, h.game.players[0])
            assertEquals(case.explanation, scene.explanation, case.hole)
            assertEquals(case.motion, scene.motion, case.hole)
            assertEquals(case.highlights, scene.highlights, case.hole)
            assertEquals(5, scene.cards.size, case.hole)
            // The session's showdown stage shows the same scene for the hero.
            val staged = h.state.showdown!!.scenes.single { it.scene.id == 0 }.scene
            assertEquals(scene.explanation, staged.explanation, case.hole)
            assertEquals(scene.cards.map { it.key }, staged.cards.map { it.key }, case.hole)
        }
    }
}
