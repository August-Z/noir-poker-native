package com.august.noirpoker.core

import java.util.TreeMap

/** Table actions. [id] is the reference's string identifier. */
enum class Action(val id: String) {
    FOLD("fold"), CHECK("check"), CALL("call"), RAISE("raise");

    companion object {
        fun fromId(id: String): Action? = entries.firstOrNull { it.id == id }
    }
}

enum class Phase(val id: String) { IDLE("idle"), PLAYING("playing"), BETWEEN("between"), DONE("done") }

enum class Difficulty(val id: String) {
    EASY("easy"), NORMAL("normal"), HARD("hard");

    companion object {
        fun fromId(id: String): Difficulty? = entries.firstOrNull { it.id == id }
    }
}

enum class LogType(val id: String) { STREET("street"), BLIND("blind"), ACTION("action"), INFO("info"), RESULT("result") }

data class LastAction(val text: String, val street: Int, val bet: Int)

data class LogEntry(val text: String, val player: Int?, val type: LogType, val street: Int)

/** One public betting action. `amount` is the raise-to total, the call amount, or 0. */
data class HistoryEntry(
    val street: Int,
    val id: Int,
    val action: Action,
    val amount: Int = 0,
    val betLabel: String? = null,
)

data class BotStats(
    var hands: Int = 0,
    var vpip: Int = 0,
    var pfr: Int = 0,
    var postActions: Int = 0,
    var postRaises: Int = 0,
    var postCalls: Int = 0,
)

data class BotHand(var vpip: Boolean = false, var pfr: Boolean = false, var pressureRecorded: Boolean = false)

/**
 * Synthetic mood. `pressureFolds` maps raiser seat id to a consecutive
 * pressure-fold count, ordered by seat like a JavaScript object with integer keys.
 */
data class BotMood(
    var kind: MoodKind = MoodKind.STEADY,
    var remaining: Int = 0,
    var cooldown: Int = 0,
    var reason: String = "",
    var losses: Int = 0,
    var wins: Int = 0,
    var pressureFolds: MutableMap<Int, Int> = TreeMap(),
    /** Absent in a fresh mood; the reference treats absent and `null` alike. */
    var lastPressureRaiser: Int? = null,
) {
    fun deepCopy(): BotMood = copy(pressureFolds = TreeMap(pressureFolds))
}

data class Player(
    val id: Int,
    var name: String,
    var stack: Int = STARTING_STACK,
    var hole: MutableList<Card> = mutableListOf(),
    var folded: Boolean = false,
    var allin: Boolean = false,
    /** Chips put in on the current street. */
    var bet: Int = 0,
    /** Chips put in this hand, across streets. */
    var total: Int = 0,
    /** The `currentBet` level this player last acted at; `null` before acting this street. */
    var actedTo: Int? = null,
    var checked: Boolean = false,
    /** Current-street public action text. */
    var action: String = "",
    /** Retained public snapshot of the latest action. */
    var lastAction: LastAction? = null,
    var botProfile: String = "balanced",
    var botMood: BotMood = freshBotMood(),
    var botStats: BotStats = freshBotStats(),
    var botHand: BotHand = BotHand(),
) {
    fun deepCopy(): Player = copy(
        hole = hole.toMutableList(),
        botMood = botMood.deepCopy(),
        botStats = botStats.copy(),
        botHand = botHand.copy(),
    )
}

data class GameStats(var hands: Int = 0, var wins: Int = 0, var buyin: Int = STARTING_STACK)

data class PotContribution(val id: Int, val amount: Int)

data class PotAward(val id: Int, val amount: Int, val label: String)

data class Pot(
    val index: Int,
    val label: String,
    val amount: Int,
    val eligible: List<Int>,
    val contributions: List<PotContribution>,
    val awards: List<PotAward> = emptyList(),
)

data class Refund(val id: Int, val amount: Int)

data class PotSet(val pots: List<Pot>, val refunds: List<Refund>)

data class Winner(val id: Int, val name: String, val amount: Int, val profit: Int, val label: String)

/** `legalActions` result. When [enabled] is false every other field is meaningless. */
data class LegalActions(
    val enabled: Boolean,
    val toCall: Int = 0,
    val callAmount: Int = 0,
    val canCheck: Boolean = false,
    val raiseReopened: Boolean = false,
    val canRaise: Boolean = false,
    val minRaiseTo: Int = 0,
    val fullRaiseTo: Int = 0,
    val maxRaiseTo: Int = 0,
    val isShortAllin: Boolean = false,
) {
    companion object {
        val DISABLED = LegalActions(enabled = false)
    }
}

/** Public state of one seat at the moment of a hero decision. */
data class SnapshotPlayer(
    val id: Int,
    val name: String,
    val position: String,
    val stack: Int,
    val bet: Int,
    val total: Int,
    val folded: Boolean,
    val allin: Boolean,
    val action: String,
    val botProfile: String?,
    val publicAxes: List<Double>?,
    val botMoodKind: MoodKind?,
    val actedTo: Int?,
    val checked: Boolean,
)

/** Hero decision snapshot: only information available before the decision. */
data class DecisionSnapshot(
    val index: Int,
    val hand: Int,
    val street: Int,
    val position: String,
    val hole: List<Card>,
    val board: List<Card>,
    val stack: Int,
    val bet: Int,
    val total: Int,
    val pot: Int,
    val currentBet: Int,
    val minRaise: Int,
    val dealer: Int,
    val emotionMode: EmotionMode,
    val legal: LegalActions,
    val pending: List<Int>,
    val action: Action,
    val amount: Int,
    val players: List<SnapshotPlayer>,
    val history: List<HistoryEntry>,
)

/**
 * The live table. A mutable reference type, mutated in place by the engine like
 * the reference's game object. Private engine data (replay baseline, bot plans)
 * is kept outside this class.
 */
class Game internal constructor(
    var players: MutableList<Player>,
    var dealer: Int,
) {
    var hand: Int = 0
    var street: Int = -1
    var board: MutableList<Card> = mutableListOf()
    var practiceBoard: List<Card>? = null
    var deck: MutableList<Card> = mutableListOf()
    var currentBet: Int = 0
    var minRaise: Int = BIG_BLIND
    var pending: MutableList<Int> = mutableListOf()
    var actor: Int = -1
    var phase: Phase = Phase.IDLE
    var revealed: Boolean = false
    var pots: List<Pot> = emptyList()
    var refunds: List<Refund> = emptyList()
    /** Newest first, like the reference's `unshift`. */
    var logs: MutableList<LogEntry> = mutableListOf()
    var winners: List<Winner> = emptyList()
    var payouts: List<Int> = emptyList()
    var stats: GameStats = GameStats()
    var difficulty: Difficulty = Difficulty.NORMAL
    var emotionMode: EmotionMode = EmotionMode.SUBTLE
    var replayAttempt: Int = 0
    var potAtShowdown: Int = 0
    var showdown: Boolean = false
    var result: String = ""
    var decisions: MutableList<DecisionSnapshot> = mutableListOf()
    var botDecisions: MutableList<BotDecisionRecord> = mutableListOf()
    var history: MutableList<HistoryEntry> = mutableListOf()

    /** A deep copy (the reference's `JSON.parse(JSON.stringify(g))`). */
    fun deepCopy(): Game {
        val g = Game(players.map { it.deepCopy() }.toMutableList(), dealer)
        g.restoreFrom(this)
        return g
    }

    /** Replaces every field with a deep copy of [other]'s. */
    internal fun restoreFrom(other: Game) {
        players = other.players.map { it.deepCopy() }.toMutableList()
        dealer = other.dealer
        hand = other.hand
        street = other.street
        board = other.board.toMutableList()
        practiceBoard = other.practiceBoard?.toList()
        deck = other.deck.toMutableList()
        currentBet = other.currentBet
        minRaise = other.minRaise
        pending = other.pending.toMutableList()
        actor = other.actor
        phase = other.phase
        revealed = other.revealed
        pots = other.pots.toList()
        refunds = other.refunds.toList()
        logs = other.logs.toMutableList()
        winners = other.winners.toList()
        payouts = other.payouts.toList()
        stats = other.stats.copy()
        difficulty = other.difficulty
        emotionMode = other.emotionMode
        replayAttempt = other.replayAttempt
        potAtShowdown = other.potAtShowdown
        showdown = other.showdown
        result = other.result
        decisions = other.decisions.toMutableList()
        botDecisions = other.botDecisions.toMutableList()
        history = other.history.toMutableList()
    }

    /** Every field in the reference's key order, for structural comparison. */
    fun stateFields(): List<Any?> = listOf(
        players, dealer, hand, street, board, practiceBoard, deck, currentBet, minRaise, pending, actor,
        phase, revealed, pots, refunds, logs, winners, payouts, stats, difficulty, emotionMode,
        replayAttempt, potAtShowdown, showdown, result, decisions, botDecisions, history,
    )

    /** Structural equality of the whole public state (like comparing JSON). */
    fun sameState(other: Game): Boolean = stateFields() == other.stateFields()
}
