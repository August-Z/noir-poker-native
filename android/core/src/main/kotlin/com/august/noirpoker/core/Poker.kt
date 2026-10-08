package com.august.noirpoker.core

import java.util.Collections
import java.util.WeakHashMap

const val STARTING_STACK = 5000
const val SMALL_BLIND = 25
const val BIG_BLIND = 50
const val MIN_PLAYERS = 5
const val MAX_PLAYERS = 9

fun newGame(playerCount: Int = 6): Game {
    if (playerCount < MIN_PLAYERS || playerCount > MAX_PLAYERS) throw PokerException(EngineError.INVALID_PLAYER_COUNT)
    val names = listOf(EngineCopy.heroName) + EngineCopy.botNames
    val players = names.take(playerCount).mapIndexed { id, name -> Player(id = id, name = name) }
    return Game(players.toMutableList(), dealer = playerCount - 1)
}

/** Applies sanitized opponent settings between hands. See [sanitizeBotSettings] for accepted input. */
fun applyBotSettings(g: Game, value: Any?) {
    if (g.phase != Phase.IDLE && g.phase != Phase.DONE) throw PokerException(EngineError.SETTINGS_LOCKED)
    val settings = sanitizeBotSettings(value)
    for (p in g.players.drop(1)) {
        val assigned = settings.assignments.getValue(p.id)
        if (p.botProfile != assigned) {
            p.botProfile = assigned
            p.botMood = freshBotMood()
            p.botStats = freshBotStats()
        }
        if (settings.emotionMode == EmotionMode.OFF) p.botMood = freshBotMood()
    }
    g.emotionMode = settings.emotionMode
}

// Seat IDs follow the physical table clockwise, starting at the hero.
val POSITION_ROLES: Map<Int, List<String>> = mapOf(
    5 to listOf("BTN", "SB", "BB", "UTG", "CO"),
    6 to listOf("BTN", "SB", "BB", "UTG", "HJ", "CO"),
    7 to listOf("BTN", "SB", "BB", "UTG", "LJ", "HJ", "CO"),
    8 to listOf("BTN", "SB", "BB", "UTG", "UTG+1", "LJ", "HJ", "CO"),
    9 to listOf("BTN", "SB", "BB", "UTG", "UTG+1", "MP", "LJ", "HJ", "CO"),
)

fun seatPosition(g: Game, id: Int): String {
    val n = g.players.size
    return POSITION_ROLES.getValue(n)[(id - g.dealer + n) % n]
}

fun potSize(g: Game): Int = g.players.sumOf { it.total }

private class PotBuilder(val index: Int, val label: String, val eligible: List<Int>) {
    var amount = 0
    val contributions = mutableListOf<IntArray>() // [id, amount]
    fun build() = Pot(index, label, amount, eligible, contributions.map { PotContribution(it[0], it[1]) })
}

private fun potLabel(index: Int) = if (index == 0) EngineCopy.mainPot else EngineCopy.sidePot(index)

// Contribution layers determine eligibility. Folded chips stay in the pots;
// adjacent layers with the same eligible players belong to the same pot.
fun partitionPots(g: Game): PotSet {
    val levels = g.players.map { it.total }.filter { it > 0 }.distinct().sorted()
    val pots = mutableListOf<PotBuilder>()
    val refunds = mutableListOf<Refund>()
    var previous = 0
    for (level in levels) {
        val contributors = g.players.filter { it.total >= level }
        val increment = level - previous
        previous = level
        if (contributors.size == 1) {
            refunds.add(Refund(contributors[0].id, increment))
            continue
        }
        val eligible = contributors.filter { !it.folded }.map { it.id }
        val amount = increment * contributors.size
        if (eligible.isEmpty()) throw PokerException(EngineError.NO_ELIGIBLE_PLAYER)
        var pot = pots.lastOrNull()
        if (pot == null || pot.eligible != eligible) {
            pot = PotBuilder(pots.size, potLabel(pots.size), eligible)
            pots.add(pot)
        }
        pot.amount += amount
        for (p in contributors) {
            val contribution = pot.contributions.firstOrNull { it[0] == p.id }
            if (contribution != null) contribution[1] += increment else pot.contributions.add(intArrayOf(p.id, increment))
        }
    }
    return PotSet(pots.map { it.build() }, refunds)
}

// A live bet difference is not a side pot: callers may still match it.
// Only an all-in contribution cap separates live main and side pots.
fun currentPots(g: Game): PotSet {
    if (g.phase == Phase.DONE) return PotSet(g.pots, g.refunds)
    val totals = g.players.map { it.total }.sortedDescending()
    val ceiling = totals.getOrElse(1) { 0 }
    val refunds = g.players.filter { it.total > ceiling }.map { Refund(it.id, it.total - ceiling) }
    val levels = (g.players.filter { it.allin && it.total > 0 && it.total < ceiling }.map { it.total } + ceiling)
        .distinct().filter { it > 0 }.sorted()
    val pots = mutableListOf<Pot>()
    var previous = 0
    for (level in levels) {
        val contributions = g.players
            .map { PotContribution(it.id, maxOf(0, minOf(it.total, level) - previous)) }
            .filter { it.amount > 0 }
        val eligible = g.players
            .filter { !it.folded && (it.total >= level || (!it.allin && it.total + it.stack >= level)) }
            .map { it.id }
        val amount = contributions.sumOf { it.amount }
        previous = level
        if (amount == 0) continue
        pots.add(Pot(pots.size, potLabel(pots.size), amount, eligible, contributions))
    }
    return PotSet(pots, refunds)
}

fun contestableAfterCall(g: Game, id: Int, amount: Int): Int {
    val cap = g.players[id].total + amount
    return g.players.sumOf { minOf(it.total, cap) } + amount
}

private fun live(g: Game) = g.players.filter { !it.folded }

private fun canAct(p: Player) = !p.folded && !p.allin && p.stack > 0

private fun nextIndex(g: Game, start: Int, list: List<Int>): Int {
    for (d in 1..g.players.size) {
        val id = (start + d) % g.players.size
        if (id in list) return id
    }
    return -1
}

private fun log(g: Game, text: String, player: Int? = null, type: LogType = LogType.ACTION) {
    g.logs.add(0, LogEntry(text, player, type, g.street))
}

private fun pay(p: Player, amount: Int): Int {
    val n = minOf(p.stack, amount)
    p.stack -= n
    p.bet += n
    p.total += n
    p.allin = p.stack == 0
    return n
}

// Public presentation only; street bet resets and settlement never overwrite it.
private fun rememberAction(g: Game, p: Player) {
    p.lastAction = LastAction(p.action, g.street, p.bet)
}

// Keep the original deal private to the engine, outside public table and review data.
private val handStarts: MutableMap<Game, Game> = Collections.synchronizedMap(WeakHashMap())

fun canRestartHand(g: Game): Boolean = g.phase == Phase.DONE && handStarts.containsKey(g)

fun startHand(g: Game, random: RandomSource = SystemRandom): Game {
    if (g.phase != Phase.IDLE && g.phase != Phase.DONE) throw PokerException(EngineError.HAND_IN_PROGRESS)
    g.replayAttempt = 0
    g.potAtShowdown = 0
    g.hand++
    g.dealer = (g.dealer + 1) % g.players.size
    g.board = mutableListOf()
    g.practiceBoard = null
    g.deck = shuffle(deckOfCards(), random)
    g.street = 0
    g.phase = Phase.PLAYING
    g.currentBet = BIG_BLIND
    g.minRaise = BIG_BLIND
    g.winners = emptyList()
    g.payouts = emptyList()
    g.pots = emptyList()
    g.refunds = emptyList()
    g.showdown = false
    g.revealed = false
    g.logs = mutableListOf()
    g.result = ""
    g.decisions = mutableListOf()
    g.botDecisions = mutableListOf()
    g.history = mutableListOf()
    log(g, EngineCopy.handStarts(g.hand, g.players[g.dealer].name), null, LogType.STREET)
    for (p in g.players) {
        if (p.id != 0) decayBotMood(p.botMood)
        p.botHand = BotHand()
        if (p.stack == 0) {
            p.stack = STARTING_STACK
            if (p.id == 0) g.stats.buyin += STARTING_STACK
            log(g, EngineCopy.rebuy(p.name), p.id, LogType.INFO)
        }
        p.hole = mutableListOf()
        p.folded = false
        p.allin = false
        p.bet = 0
        p.total = 0
        p.actedTo = null
        p.checked = false
        p.action = ""
        p.lastAction = null
    }
    val n = g.players.size
    for (round in 0 until 2) for (i in 1..n) g.players[(g.dealer + i) % n].hole.add(g.deck.removeAt(g.deck.lastIndex))
    val sb = g.players[(g.dealer + 1) % n]
    val bb = g.players[(g.dealer + 2) % n]
    pay(sb, SMALL_BLIND)
    sb.action = EngineCopy.smallBlindAction(sb.bet)
    rememberAction(g, sb)
    pay(bb, BIG_BLIND)
    bb.action = EngineCopy.bigBlindAction(bb.bet)
    rememberAction(g, bb)
    log(g, EngineCopy.blindsLog(sb.name, sb.bet, bb.name, bb.bet), null, LogType.BLIND)
    g.pending = g.players.filter(::canAct).map { it.id }.toMutableList()
    g.actor = nextIndex(g, bb.id, g.pending)
    handStarts[g] = g.deepCopy()
    return g
}

/**
 * Replay Hand: restores the state after the blinds were posted, before any
 * action, rolling back this attempt's awards, refunds, decisions and session
 * statistics. Only the current difficulty is kept.
 */
fun restartHand(g: Game): Game {
    if (!canRestartHand(g)) throw PokerException(EngineError.REPLAY_UNAVAILABLE)
    val original = handStarts.getValue(g)
    val attempt = g.replayAttempt + 1
    val difficulty = g.difficulty
    g.restoreFrom(original)
    g.difficulty = difficulty
    g.replayAttempt = attempt
    log(g, EngineCopy.replayLog(g.hand, attempt), null, LogType.INFO)
    return g
}

fun legalActions(g: Game, id: Int = g.actor): LegalActions {
    val p = g.players.getOrNull(id)
    if (g.phase != Phase.PLAYING || g.actor != id || p == null || !canAct(p)) return LegalActions.DISABLED
    val owed = maxOf(0, g.currentBet - p.bet)
    val max = p.bet + p.stack
    val min = if (g.currentBet == 0) BIG_BLIND else g.currentBet + g.minRaise
    val actedTo = p.actedTo
    val reopened = actedTo == null || g.currentBet - actedTo >= g.minRaise
    val other = g.players.any { it.id != id && canAct(it) }
    return LegalActions(
        enabled = true,
        toCall = owed,
        callAmount = minOf(p.stack, owed),
        canCheck = owed == 0,
        raiseReopened = reopened,
        canRaise = max > g.currentBet && reopened && other,
        minRaiseTo = minOf(min, max),
        fullRaiseTo = min,
        maxRaiseTo = max,
        isShortAllin = max < min,
    )
}

/** String form of [act] for untrusted input: unknown actions throw like the reference. */
fun act(g: Game, id: Int, action: String, amount: Int? = null): Game {
    if (!legalActions(g, id).enabled) throw PokerException(EngineError.NOT_YOUR_TURN)
    val parsed = Action.fromId(action) ?: throw PokerException(EngineError.UNKNOWN_ACTION)
    return act(g, id, parsed, amount)
}

fun act(g: Game, id: Int, action: Action, amount: Int? = null): Game {
    val legal = legalActions(g, id)
    if (!legal.enabled) throw PokerException(EngineError.NOT_YOUR_TURN)
    val p = g.players[id]
    if (action == Action.CHECK && !legal.canCheck) throw PokerException(EngineError.CANNOT_CHECK)
    if (action == Action.RAISE &&
        (!legal.canRaise || amount == null || amount < legal.minRaiseTo || amount > legal.maxRaiseTo)
    ) {
        throw PokerException(EngineError.ILLEGAL_RAISE)
    }
    // Capture only information available before the decision. Opponents' hole
    // cards, the remaining deck and future community cards never enter review.
    val normalized = if (action == Action.CALL && legal.canCheck) Action.CHECK else action
    val betLabel = if (normalized == Action.RAISE) {
        raiseCaption(LabelStep(street = g.street, history = g.history.toList(), currentBet = g.currentBet, legal = legal), amount!!)
    } else {
        null
    }
    val recordedAmount = when (normalized) {
        Action.RAISE -> amount!!
        Action.CALL -> legal.callAmount
        else -> 0
    }
    if (id != 0) {
        if (g.street == 0 && (normalized == Action.CALL || normalized == Action.RAISE)) p.botHand.vpip = true
        if (g.street == 0 && normalized == Action.RAISE) p.botHand.pfr = true
        if (g.street > 0 && normalized != Action.FOLD) {
            p.botStats.postActions++
            if (normalized == Action.RAISE) p.botStats.postRaises++
            if (normalized == Action.CALL) p.botStats.postCalls++
        }
        val facing = g.history.lastOrNull { it.street == g.street && it.action == Action.RAISE }
        if (normalized == Action.FOLD && facing != null && !p.botHand.pressureRecorded) {
            p.botHand.pressureRecorded = true
            val event = recordPressureFold(p.botMood, facing.id, g.emotionMode)
            if (event != null) log(g, EngineCopy.moodLog(p.name, event.kind.label, event.reason), id, LogType.INFO)
        } else if (normalized != Action.FOLD && facing != null) {
            p.botMood.pressureFolds[facing.id] = 0
        }
    }
    if (id == 0) {
        g.decisions.add(
            DecisionSnapshot(
                index = g.decisions.size,
                hand = g.hand,
                street = g.street,
                position = seatPosition(g, id),
                hole = p.hole.toList(),
                board = g.board.toList(),
                stack = p.stack,
                bet = p.bet,
                total = p.total,
                pot = potSize(g),
                currentBet = g.currentBet,
                minRaise = g.minRaise,
                dealer = g.dealer,
                emotionMode = g.emotionMode,
                legal = legal,
                pending = g.pending.toList(),
                action = normalized,
                amount = recordedAmount,
                players = g.players.map { o ->
                    SnapshotPlayer(
                        id = o.id,
                        name = o.name,
                        position = seatPosition(g, o.id),
                        stack = o.stack,
                        bet = o.bet,
                        total = o.total,
                        folded = o.folded,
                        allin = o.allin,
                        action = o.action,
                        botProfile = if (o.id != 0) o.botProfile else null,
                        publicAxes = if (o.id != 0) {
                            effectiveBotAxes(getBotProfile(o.botProfile), o.botMood, g.emotionMode)
                        } else {
                            null
                        },
                        botMoodKind = if (o.id != 0) o.botMood.kind else null,
                        actedTo = o.actedTo,
                        checked = o.checked,
                    )
                },
                history = g.history.toList(),
            ),
        )
    }
    g.history.add(HistoryEntry(g.street, id, normalized, recordedAmount, betLabel))
    g.pending.removeAll { it == id }
    if (action == Action.FOLD) {
        p.folded = true
        p.action = EngineCopy.fold
        log(g, EngineCopy.actionLog(p.name, p.action), id)
    } else if (action == Action.CHECK || (action == Action.CALL && legal.toCall == 0)) {
        p.checked = true
        p.action = EngineCopy.check
        p.actedTo = g.currentBet
        log(g, EngineCopy.actionLog(p.name, p.action), id)
    } else if (action == Action.CALL) {
        val n = pay(p, legal.callAmount)
        p.checked = false
        p.actedTo = g.currentBet
        p.action = if (p.allin) EngineCopy.allIn(p.bet) else EngineCopy.call(n)
        log(g, EngineCopy.actionLog(p.name, p.action), id)
    } else {
        val raiseTo = amount!!
        val old = g.currentBet
        pay(p, raiseTo - p.bet)
        g.currentBet = raiseTo
        p.checked = false
        p.actedTo = raiseTo
        val full = raiseTo - old >= g.minRaise
        if (full) {
            g.minRaise = raiseTo - old
            g.pending = g.players.filter { it.id != id && canAct(it) }.map { it.id }.toMutableList()
        } else {
            for (o in g.players) {
                if (o.id != id && canAct(o) && o.bet < raiseTo && o.id !in g.pending) g.pending.add(o.id)
            }
        }
        p.action = EngineCopy.raiseAction(betLabel!!, raiseTo)
        log(g, EngineCopy.actionLog(p.name, p.action), id)
    }
    rememberAction(g, p)
    progress(g, id)
    return g
}

private fun progress(g: Game, last: Int) {
    if (live(g).size == 1) {
        settle(g, false)
        return
    }
    g.pending = g.pending.filter { canAct(g.players[it]) }.toMutableList()
    if (g.pending.size == 1 &&
        g.players[g.pending[0]].bet >= g.currentBet &&
        g.players.count(::canAct) == 1
    ) {
        g.pending = mutableListOf()
    }
    if (g.pending.isNotEmpty()) {
        g.actor = nextIndex(g, last, g.pending)
        g.phase = Phase.PLAYING
    } else {
        g.actor = -1
        g.phase = Phase.BETWEEN
        if (g.street == 3 || (live(g).any { it.allin } && g.players.count(::canAct) <= 1)) g.revealed = true
    }
}

private fun dealCommunityCards(board: MutableList<Card>, deck: MutableList<Card>, count: Int) {
    deck.removeAt(deck.lastIndex) // Burn one card before each street, including practice runouts.
    repeat(count) { board.add(deck.removeAt(deck.lastIndex)) }
}

fun completeBoardForPractice(g: Game): Game {
    if (g.phase != Phase.DONE) throw PokerException(EngineError.HAND_NOT_SETTLED)
    if (g.board.size == 5 || g.practiceBoard != null) return g
    if (g.showdown) throw PokerException(EngineError.SHOWDOWN_NEEDS_BOARD)
    // These cards are a learning preview after a fold-win, not new game actions.
    // Keep the actual board, deck, settlement and review evidence untouched.
    val board = g.board.toMutableList()
    val deck = g.deck.toMutableList()
    while (board.size < 5) dealCommunityCards(board, deck, if (board.isEmpty()) 3 else 1)
    g.practiceBoard = board
    log(g, EngineCopy.practiceRunout, null, LogType.INFO)
    return g
}

fun advanceStreet(g: Game): Game {
    if (g.phase != Phase.BETWEEN) throw PokerException(EngineError.ROUND_NOT_FINISHED)
    if (g.street == 3) {
        settle(g, true)
        return g
    }
    g.street++
    val count = if (g.street == 1) 3 else 1
    dealCommunityCards(g.board, g.deck, count)
    g.currentBet = 0
    g.minRaise = BIG_BLIND
    for (p in g.players) {
        p.bet = 0
        p.actedTo = null
        p.checked = false
        if (!p.folded) p.action = if (p.allin) EngineCopy.allInReset else ""
    }
    log(
        g,
        EngineCopy.streetNames[g.street] + " · " + g.board.takeLast(count).joinToString(" ") { rankText(it.rank) + it.symbol },
        null,
        LogType.STREET,
    )
    val active = g.players.filter(::canAct)
    if (active.size <= 1) {
        g.pending = mutableListOf()
        g.actor = -1
        g.phase = Phase.BETWEEN
        if (live(g).any { it.allin }) g.revealed = true
    } else {
        g.pending = active.map { it.id }.toMutableList()
        g.actor = nextIndex(g, g.dealer, g.pending)
        g.phase = Phase.PLAYING
    }
    return g
}

fun settle(g: Game, showdown: Boolean = true): Game {
    if (g.phase == Phase.DONE) throw PokerException(EngineError.ALREADY_SETTLED)
    val (pots, refunds) = partitionPots(g)
    val n = g.players.size
    val payouts = IntArray(n)
    val won = IntArray(n)
    val ranks: Map<Int, HandEvaluation> =
        if (showdown) live(g).associate { it.id to evaluate(it.hole + g.board) } else emptyMap()
    for (refund in refunds) payouts[refund.id] += refund.amount
    val awarded = pots.map { pot ->
        val eligible = pot.eligible.map { g.players[it] }
        var winners = mutableListOf<Player>()
        if (!showdown) {
            winners = mutableListOf(eligible[0])
        } else {
            var best: List<Int>? = null
            for (p in eligible) {
                val score = ranks.getValue(p.id).score
                val c = if (best != null) compare(score, best) else 1
                if (c > 0) {
                    best = score
                    winners = mutableListOf(p)
                } else if (c == 0) {
                    winners.add(p)
                }
            }
        }
        val ordered = winners.sortedBy { (it.id - g.dealer + n - 1) % n }
        val share = pot.amount / ordered.size
        val remainder = pot.amount % ordered.size
        val awards = ordered.mapIndexed { i, p ->
            PotAward(
                p.id,
                share + (if (i < remainder) 1 else 0),
                if (showdown) ranks.getValue(p.id).label else EngineCopy.othersFolded,
            )
        }
        for (award in awards) {
            payouts[award.id] += award.amount
            won[award.id] += award.amount
        }
        pot.copy(awards = awards)
    }
    if (payouts.sum() != potSize(g)) throw PokerException(EngineError.POT_MISMATCH)
    g.pots = awarded
    g.refunds = refunds
    g.payouts = payouts.toList()
    g.winners = g.players.filter { won[it.id] > 0 }.map { p ->
        Winner(
            id = p.id,
            name = p.name,
            amount = won[p.id],
            profit = payouts[p.id] - p.total,
            label = if (showdown) evaluate(p.hole + g.board).label else EngineCopy.othersFolded,
        )
    }
    g.potAtShowdown = won.sum()
    g.showdown = showdown
    g.phase = Phase.DONE
    g.actor = -1
    g.stats.hands++
    if (won[0] > 0) g.stats.wins++
    for (p in g.players) p.stack += payouts[p.id]
    g.result = (if (awarded.size > 1) EngineCopy.splitPots else "") +
        g.winners.joinToString(" / ") { w ->
            if (showdown) EngineCopy.showdownResult(w.name, w.label, w.amount) else EngineCopy.foldWinResult(w.name, w.amount)
        }
    for (pot in awarded) {
        log(
            g,
            pot.label + " " + formatChips(pot.amount) + " → " +
                pot.awards.joinToString(" / ") { g.players[it.id].name + " " + formatChips(it.amount) },
            null,
            LogType.RESULT,
        )
    }
    for (refund in refunds) {
        log(g, EngineCopy.refundLog(g.players[refund.id].name, refund.amount), refund.id, LogType.INFO)
    }
    log(g, g.result, null, LogType.RESULT)
    for (p in g.players.drop(1)) {
        p.botStats.hands++
        if (p.botHand.vpip) p.botStats.vpip++
        if (p.botHand.pfr) p.botStats.pfr++
        if (!p.botHand.pressureRecorded) {
            p.botMood.pressureFolds = java.util.TreeMap()
            p.botMood.lastPressureRaiser = null
        }
        val event = finishBotHand(p, payouts[p.id] - p.total, g.emotionMode)
        if (event != null) log(g, EngineCopy.moodLog(p.name, event.kind.label, event.reason), p.id, LogType.INFO)
    }
    return g
}

/**
 * Sampled equity against random opponent hands. Consumes
 * `trials × (available − 1)` random values.
 */
fun estimateEquity(
    hole: List<Card>,
    board: List<Card>,
    rivals: Int = 1,
    trials: Int = 35,
    random: RandomSource = SystemRandom,
): Double {
    val known = (hole + board).map { it.key }.toSet()
    val available = deckOfCards().filter { it.key !in known }
    var wins = 0.0
    for (t in 0 until trials) {
        val sample = shuffle(available.toMutableList(), random)
        val community = board.toMutableList()
        while (community.size < 5) community.add(sample.removeAt(sample.lastIndex))
        val score = evaluate(hole + community).score
        var tied = 1
        var lost = false
        for (i in 0 until rivals) {
            val first = sample.removeAt(sample.lastIndex)
            val second = sample.removeAt(sample.lastIndex)
            val enemy = evaluate(listOf(first, second) + community).score
            val c = compare(enemy, score)
            if (c > 0) {
                lost = true
                break
            }
            if (c == 0) tied++
        }
        if (!lost) wins += 1.0 / tied
    }
    return wins / trials
}

/** The current actor's decision, built from the white-listed [BotView] only. */
fun botDecision(g: Game, random: RandomSource = SystemRandom, trials: Int? = null): BotDecision {
    val p = g.players.getOrNull(g.actor)
    val legal = legalActions(g)
    val rivals = maxOf(1, live(g).size - 1)
    if (p == null || !legal.enabled) throw PokerException(EngineError.BOT_CANNOT_ACT)
    val score = evaluate(p.hole + g.board).score
    val equityTrials = trials ?: if (g.difficulty == Difficulty.HARD) 52 else 28
    if (equityTrials < 1) throw PokerException(EngineError.INVALID_TRIALS)
    val n = g.players.size
    // Explicit actor perspective: no other hole cards, future deck, review
    // decisions or eventual winners can enter this policy.
    val view = BotView(
        id = p.id,
        hole = p.hole.toList(),
        board = g.board.toList(),
        street = g.street,
        position = seatPosition(g, p.id),
        count = n,
        inPosition = (0 until n).map { g.players[(g.dealer + 1 + it) % n] }.filter(::canAct).lastOrNull()?.id == p.id,
        stack = p.stack,
        bet = p.bet,
        pot = potSize(g),
        currentBet = g.currentBet,
        difficulty = g.difficulty,
        legal = legal,
        rivals = rivals,
        opponents = live(g).filter { it.id != p.id }.map { BotOpponent(it.id, it.stack, it.bet, it.allin) },
        equity = estimateEquity(p.hole, g.board, rivals, equityTrials, random),
        equityTrials = equityTrials,
        contestable = contestableAfterCall(g, p.id, legal.callAmount),
        history = g.history.toList(),
        features = botBoardFeatures(p.hole, g.board, score),
        playsBoard = g.board.size == 5 && compare(score, evaluate(g.board).score) == 0,
    )
    val decision = chooseBotAction(view, getBotProfile(p.botProfile), p.botMood, g.emotionMode, random)
    return decision.copy(trace = decision.trace.copy(view = view))
}

/** A private bot execution record: the action and its trace, including thinking time. */
data class BotDecisionRecord(
    val id: Int,
    val name: String,
    val hand: Int,
    val sequence: Int,
    val action: Action,
    val amount: Int?,
    val trace: BotTrace,
)

private class PlanRecord(
    val game: Game,
    val id: Int,
    val hand: Int,
    val attempt: Int,
    val street: Int,
    val sequence: Int,
    val difficulty: Difficulty,
    val stack: Int,
    val bet: Int,
    val decision: BotDecision,
    val thinking: BotThinking,
)

/**
 * An opaque bot plan. Only the synthetic delay is public; the preselected
 * action and private timing factors stay inside the engine.
 */
class BotPlan internal constructor(val delayMs: Int) {
    internal var record: Any? = null
}

// Opaque plans keep preselected actions and private timing factors off the UI.
fun planBotTurn(g: Game, random: RandomSource = SystemRandom, timingRandom: RandomSource = random): BotPlan {
    if (g.actor == 0) throw PokerException(EngineError.HERO_BOT_EXECUTOR)
    val decision = botDecision(g, random)
    val thinking = botThinkingTime(decision, timingRandom)
    val plan = BotPlan(thinking.durationMs)
    plan.record = PlanRecord(
        game = g,
        id = g.actor,
        hand = g.hand,
        attempt = g.replayAttempt,
        street = g.street,
        sequence = g.history.size,
        difficulty = g.difficulty,
        stack = g.players[g.actor].stack,
        bet = g.currentBet,
        decision = decision,
        thinking = thinking,
    )
    return plan
}

fun isBotTurnCurrent(g: Game, plan: BotPlan): Boolean {
    val p = plan.record as? PlanRecord ?: return false
    return p.game === g &&
        g.phase == Phase.PLAYING &&
        p.id == g.actor &&
        p.hand == g.hand &&
        p.attempt == g.replayAttempt &&
        p.street == g.street &&
        p.sequence == g.history.size &&
        p.difficulty == g.difficulty &&
        p.stack == g.players[g.actor].stack &&
        p.bet == g.currentBet
}

// Only executing a current plan writes an action and its one private record.
fun executeBotTurn(g: Game, plan: BotPlan, expedited: Boolean = false, waitedMs: Long = 0): BotDecision {
    if (!isBotTurnCurrent(g, plan)) throw PokerException(EngineError.STALE_BOT_PLAN)
    val record = plan.record as PlanRecord
    val decision = record.decision
    val thinking = record.thinking
    val entry = BotDecisionRecord(
        id = record.id,
        name = g.players[record.id].name,
        hand = g.hand,
        sequence = g.history.size + 1,
        action = decision.action,
        amount = decision.amount,
        trace = decision.trace.copy(
            thinking = BotThinkingRecord(
                thinking.durationMs,
                thinking.model,
                thinking.acting,
                thinking.factors,
                expedited,
                maxOf(0L, waitedMs),
            ),
        ),
    )
    act(g, record.id, decision.action, decision.amount)
    plan.record = null
    g.botDecisions.add(entry)
    return decision
}

/**
 * Plans and immediately executes a bot turn. The reference's timing roll uses
 * its global `Math.random`; pass the same stream as [random] (the default) to
 * reproduce a single-stream fixture, or a separate [timingRandom].
 */
fun playBotTurn(g: Game, random: RandomSource = SystemRandom, timingRandom: RandomSource = random): BotDecision =
    executeBotTurn(g, planBotTurn(g, random, timingRandom), expedited = true)
