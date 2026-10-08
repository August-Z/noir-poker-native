package com.august.noirpoker.core.session

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.Card
import com.august.noirpoker.core.Game
import com.august.noirpoker.core.LastAction
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.RandomSource
import com.august.noirpoker.core.SeededRandom
import com.august.noirpoker.core.advanceStreet
import com.august.noirpoker.core.act
import com.august.noirpoker.core.deckOfCards
import com.august.noirpoker.core.legalActions
import com.august.noirpoker.core.potSize
import com.august.noirpoker.core.settle
import com.august.noirpoker.core.startHand

/** Counts draws from a seeded stream so tests can assert random consumption. */
class CountingRandom(seed: Long) : RandomSource {
    private val inner = SeededRandom(seed)
    var draws = 0
        private set

    override fun next(): Double {
        draws++
        return inner.next()
    }
}

/** A table session on a virtual clock with in-memory storage. */
class Harness(
    seed: Long = 42,
    val storage: InMemoryStorage = InMemoryStorage(),
    runner: ReviewRunner? = null,
) {
    val scheduler = ManualScheduler()
    val random = CountingRandom(seed)
    val session = TableSession(scheduler, storage, random, runner)
    val effects = mutableListOf<SessionEffect>()

    init {
        session.effectListener = { effects.add(it) }
    }

    val hooks get() = session.testHooks
    val game: Game get() = session.testHooks.game
    val state: TableRenderState get() = session.state

    fun wealth(): Int = game.players.sumOf { it.stack } + if (game.phase == Phase.DONE) 0 else potSize(game)

    /** Advances virtual time until the hero must act or the hand is over. */
    fun runBots(maxMs: Long = 120_000) {
        val limit = scheduler.nowMs + maxMs
        while (scheduler.nowMs < limit) {
            if (game.phase == Phase.DONE) return
            if (game.phase == Phase.PLAYING && game.actor == 0) return
            val next = scheduler.nextDueAt ?: return
            scheduler.advanceTo(next)
        }
    }

    // The reference QA fixtures (`tests/fixtures/table-fixtures.js`), driving the real session.

    fun heroTurn(count: Int = 6, unequal: Boolean = false) = hooks.fixture(count, heroFirst = true) { g ->
        if (unequal) g.players.drop(1).forEach { it.stack = 100 + it.id * 100 }
        startHand(g, random)
    }

    fun bettingTurn(level: Int = 2, street: Int = 0, short: Boolean = false) = hooks.fixture(6) { g ->
        g.dealer = 5
        if (short) g.players[0].stack = 175
        startHand(g, random)
        if (street == 0) {
            if (level >= 3) act(g, 3, Action.RAISE, 150)
            if (level >= 4) act(g, 4, Action.RAISE, 350)
            while (g.actor != 0) act(g, g.actor, Action.FOLD)
        } else {
            while (g.street < street) {
                while (g.phase == Phase.PLAYING) act(g, g.actor, Action.CALL)
                advanceStreet(g)
            }
            if (level >= 2) act(g, 1, Action.RAISE, 100)
            if (level >= 3) act(g, 2, Action.RAISE, 300)
            while (g.actor != 0) act(g, g.actor, if (level == 1) Action.CHECK else Action.FOLD)
        }
    }

    fun foldFinished(street: Int = 0) = hooks.fixture(6, heroFirst = true) { g ->
        startHand(g, random)
        while (g.street < street) {
            while (g.phase == Phase.PLAYING) act(g, g.actor, Action.CALL)
            advanceStreet(g)
        }
        if (street > 0) act(g, g.actor, Action.RAISE, 100)
        while (g.actor != 0) act(g, g.actor, Action.FOLD)
        act(g, 0, Action.FOLD)
        while (g.phase == Phase.PLAYING) act(g, g.actor, Action.FOLD)
    }

    fun allinRest() {
        hooks.stop()
        hooks.mutate { g ->
            while (g.phase == Phase.PLAYING) {
                val legal = legalActions(g)
                act(g, g.actor, if (legal.canRaise) Action.RAISE else Action.CALL, legal.maxRaiseTo)
            }
        }
    }

    fun respondToHero(raiseTo: Int = 0, nextStreet: Boolean = false) {
        hooks.stop()
        hooks.mutate { g ->
            var amount = raiseTo
            fun callUntilHero() {
                while (g.phase == Phase.PLAYING && g.actor != 0) {
                    act(g, g.actor, if (amount != 0) Action.RAISE else Action.CALL, if (amount != 0) amount else null)
                    amount = 0
                }
            }
            callUntilHero()
            if (nextStreet && g.phase == Phase.BETWEEN) {
                advanceStreet(g)
                callUntilHero()
            }
        }
    }

    fun river(count: Int = 6) = hooks.fixture(count) { g ->
        startHand(g, random)
        while (g.street < 3 || g.phase == Phase.PLAYING) {
            if (g.phase == Phase.BETWEEN) advanceStreet(g) else act(g, g.actor, Action.CALL)
        }
    }

    fun retainedRiver(count: Int = 6) = hooks.fixture(count, heroFirst = true) { g ->
        startHand(g, random)
        while (g.street < 3) {
            if (g.phase == Phase.BETWEEN) advanceStreet(g) else act(g, g.actor, Action.CALL)
        }
        act(g, g.actor, Action.RAISE, 100)
        act(g, g.actor, Action.CALL)
        act(g, g.actor, Action.RAISE, 300)
        act(g, g.actor, Action.FOLD)
        while (g.phase == Phase.PLAYING) act(g, g.actor, Action.CALL)
    }

    fun finish() {
        hooks.stop()
        hooks.mutate { g -> if (g.phase == Phase.BETWEEN) advanceStreet(g) }
    }

    fun foldWin(count: Int = 6, winner: Int = count - 1) = hooks.fixture(count, heroFirst = true) { g ->
        startHand(g, random)
        while (g.phase == Phase.PLAYING) act(g, g.actor, if (g.actor == winner) Action.CALL else Action.FOLD)
    }

    fun foldRest() {
        hooks.stop()
        hooks.mutate { g -> while (g.phase == Phase.PLAYING) act(g, g.actor, Action.FOLD) }
    }

    fun foldPotRefund(count: Int = 6) = hooks.fixture(count, heroFirst = true) { g ->
        startHand(g, random)
        while (g.actor != 2) act(g, g.actor, Action.FOLD)
        act(g, 2, Action.RAISE, 125)
        while (g.phase == Phase.PLAYING) act(g, g.actor, Action.FOLD)
    }

    fun scene(
        hole: String,
        board: String,
        count: Int = 6,
        totals: List<Int>? = null,
        folded: List<Int> = emptyList(),
        otherHoles: Map<Int, String> = emptyMap(),
    ) = hooks.fixture(count) { g ->
        startHand(g, random)
        val deck = deckOfCards()
        fun parse(s: String): MutableList<Card> = s.split(" ").map { v ->
            deck.first { it.rank == "23456789TJQKA".indexOf(v[0]) + 2 && it.suit == "shcd".indexOf(v[1]) }
        }.toMutableList()
        g.board = parse(board)
        g.players[0].hole = parse(hole)
        val used = (g.board + g.players[0].hole).map { it.key }.toMutableSet()
        for ((id, h) in otherHoles) {
            g.players[id].hole = parse(h)
            g.players[id].hole.forEach { used.add(it.key) }
        }
        val rest = deck.filter { it.key !in used }.toMutableList()
        for (p in g.players) {
            if (p.id != 0 && p.id !in otherHoles) {
                p.hole = mutableListOf(rest.removeAt(0), rest.removeAt(0))
            }
            p.total = totals?.getOrNull(p.id) ?: 100
            p.bet = p.total
            p.stack = 5000 - p.total
            p.folded = p.id in folded
            p.allin = false
            p.action = if (p.folded) "Fold" else "Check"
            p.lastAction = LastAction(p.action, 3, p.bet)
        }
        g.street = 3
        g.phase = Phase.BETWEEN
        g.revealed = true
        settle(g, true)
    }
}

/** A review runner that completes only when the test says so. */
class FakeReviewRunner : ReviewRunner {
    class Started(val job: ReviewJob, val sink: ReviewSink) {
        var cancelled = false
    }

    val started = mutableListOf<Started>()

    override fun start(job: ReviewJob, sink: ReviewSink): Cancellable {
        val s = Started(job, sink)
        started.add(s)
        return Cancellable { s.cancelled = true }
    }
}

data class FakeAnalysis(override val priorityIndex: Int, val label: String = "") : ReviewAnalysis
