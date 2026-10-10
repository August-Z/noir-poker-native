package com.august.noirpoker.core

// These are training controls inferred from a few public examples, not measured
// statistics of the named players. Emotions are a separate synthetic layer.

data class BotSource(val label: String, val url: String)

data class BotProfile(
    val id: String,
    val name: String,
    val short: String,
    val tag: String,
    val description: String,
    /** `[width, attack, bluff, callDown, trap]`, each 0..100. */
    val axes: List<Int>,
    /** `[low, high]` fraction of the pot for postflop raise sizing. */
    val sizing: List<Double>,
    val evidence: String,
    val sources: List<BotSource>,
)

private const val TRITON = "https://tritonpokerseries.com/en-US/news/headlines/"
private const val BLUFFS_RETROSPECTIVE = "https://www.pokerstars.com/poker/learn/news/the-best-and-worst-poker-bluffs-ever/"

val BOT_PROFILES: List<BotProfile> = listOf(
    BotProfile(
        id = "balanced",
        name = "Balanced Practice",
        short = "Balanced",
        tag = "Steady baseline opponent",
        description = "Medium range and standard sizing, mixing value bets with occasional bluffs.",
        axes = listOf(50, 50, 40, 50, 20),
        sizing = listOf(0.45, 0.8),
        evidence = "Baseline training strategy; it does not represent any real player.",
        sources = emptyList(),
    ),
    BotProfile(
        id = "tan",
        name = "Johnny Tan · Tan Xuan",
        short = "Johnny Tan",
        tag = "Wide range · Multi-street pressure",
        description = "Contests more pots with a wider range, takes the same aggressive lines with weak and strong hands, and prefers sustained pressure.",
        axes = listOf(85, 90, 82, 70, 25),
        sizing = listOf(0.65, 1.15),
        evidence = "Triton cash-game coverage documents a light 4-bet and multi-street bluffs; in a short deck interview he also says he likes playing loose and bluffing. Short deck frequencies are not carried over to this table.",
        sources = listOf(
            BotSource("Triton · Cash-game aggression sample", TRITON + "st-wang-shows-million-dollar-class-as-cash-game-invitational-raises-stakes"),
            BotSource("Triton · Player interview (short deck)", TRITON + "tan-xuan-completes-short-deck-double-with-jeju-main-event-success"),
        ),
    ),
    BotProfile(
        id = "st",
        name = "ST Wang",
        short = "ST Wang",
        tag = "Selective aggression · Value traps",
        description = "Tightens up marginal entries, slow-plays strong hands on safe boards, and still cuts losses against big bets.",
        axes = listOf(40, 65, 43, 42, 78),
        sizing = listOf(0.45, 0.9),
        evidence = "In official coverage he still folded AQ on the river right after losing a big pot; in another hand he set a river check-shove value trap with AA.",
        sources = listOf(
            BotSource("Triton · Discipline after a big loss", TRITON + "ferdinand-takes-most-as-phil-ivey-and-dan-cates-land-big-cash-game-profits"),
            BotSource("Triton · Trapping with a strong hand", TRITON + "more-brilliance-from-elton-tsang-as-cash-game-invitational-gets-serious"),
        ),
    ),
    BotProfile(
        id = "zang",
        name = "Aaron Zang",
        short = "Aaron Zang",
        tag = "Seasoned aggression · River battles",
        description = "Medium-wide range; fights for pots in position and keeps both river raising and bluff-catching lines.",
        axes = listOf(63, 75, 62, 63, 50),
        sizing = listOf(0.6, 1.0),
        evidence = "Triton recorded a river bluff that raised a 23k bet to 105k. A single hand says nothing about long-run frequencies.",
        sources = listOf(
            BotSource("Triton · River aggression sample", TRITON + "brilliant-rui-cao-and-steady-andy-ni-win-big-on-day-2-in-jeju"),
        ),
    ),
    BotProfile(
        id = "peter",
        name = "Peter · HCL",
        short = "Peter",
        tag = "Wide range · Big-bet brawler",
        description = "More willing to call in, extracts big-bet value with strong hands, and occasionally fights back hard with small pocket pairs.",
        axes = listOf(92, 88, 72, 84, 18),
        sizing = listOf(0.75, 1.25),
        evidence = "HCL footage shows a pot-sized river re-raise with a set; another session shows a big shove with a small pocket pair. The latter was played under a Stand-Up side-game rule, so its frequencies cannot be copied over. \"Peter\" here refers to the HCL regular.",
        sources = listOf(
            BotSource("HCL · River value raise", "https://hustlercasinolive.com/2024/06/12/the-rematch-we-didnt-know-we-needed/"),
            BotSource("PokerNews · Small-pair counterattack (side-game rule)", "https://www.pokernews.com/news/2025/01/poker-player-goes-all-in-for-thousands-47684.htm"),
        ),
    ),
    BotProfile(
        id = "abao",
        name = "A Bao · KPC",
        short = "A Bao",
        tag = "Selective pressure · Semi-bluffs",
        description = "More aggressive with draw equity; can follow a small flop bet with a big turn bet to keep up the pressure.",
        axes = listOf(55, 82, 72, 50, 34),
        sizing = listOf(0.5, 1.0),
        evidence = "In detailed KPC hand coverage, suited AJ bet about 31% pot on the flop and semi-bluffed 90% pot on the turn; another sample shows a shove with a 98 flush draw. The player's real name has not been reliably confirmed.",
        sources = listOf(
            BotSource("Pokerati · AJ semi-bluff hand", "https://pokerati.com/2026/08/top-streamed-hands-of-the-week-winston-sets-the-perfect-trap-a-bao-bluffs-big/"),
            BotSource("Pokerati · Flush-draw counterattack", "https://pokerati.com/2026/08/top-streamed-hands-of-the-week-malinowski-and-dwan-take-on-the-kpc-high-rollers/"),
        ),
    ),
    BotProfile(
        id = "viktor",
        name = "Viktor Blom",
        short = "Viktor Blom",
        tag = "Loose-aggressive pressure · Wide-range battles",
        description = "Contests late-position and cheap pots more widely, takes the same aggressive lines with draws and value hands, and prefers larger sizes.",
        axes = listOf(90, 94, 88, 70, 18),
        sizing = listOf(0.7, 1.25),
        evidence = "An original PokerStars interview and an official retrospective support his historical loose-aggressive style. This is a training archetype, not his current play or real frequencies; heads-up experience is not translated directly into precise multiway parameters.",
        sources = listOf(
            BotSource("PokerStars · Original Viktor interview", "https://www.pokerstars.com/poker/learn/news/finding-isildur1-viktor-blom-cops-to-his-077269/"),
            BotSource("PokerStars · Historic bluffs retrospective", BLUFFS_RETROSPECTIVE),
        ),
    ),
    BotProfile(
        id = "jungleman",
        name = "Daniel Cates",
        short = "Daniel Cates",
        tag = "Calculated aggression · Trapping strong hands",
        description = "Defends when the price is right and balances proactive pressure with trapping strong hands; large continues must still pass the equity and stack-pressure checks.",
        axes = listOf(65, 82, 66, 64, 72),
        sizing = listOf(0.45, 0.95),
        evidence = "His own interviews stress calculation, watching what opponents actually do, and adjusting rather than balancing mechanically. This bot approximates those ideas with ranges and prices; it does not reproduce professional-level reads or dynamic learning.",
        sources = listOf(
            BotSource("Card Player · Daniel Cates interview", "https://www.cardplayer.com/cardplayer-poker-magazines/65799-poker-hall-of-fame-23-20/articles/19757-capture-the-flag-daniel-jungleman12-cates"),
            BotSource("Card Player · Interview on adjusting to opponents", "https://www.cardplayer.com/cardplayer-poker-magazines/66315-jason-mercier-28-23/articles/22601-head-games-heads-up-cash-game-advice-from-the-best-in-the-world"),
        ),
    ),
    BotProfile(
        id = "dwan",
        name = "Tom Dwan",
        short = "Tom Dwan",
        tag = "Creative pressure · Multi-street bluffs",
        description = "Fights harder for pots in position, mixes in multi-street pressure when he has a credible story or a draw, and can keep opponents' ranges wide with strong hands.",
        axes = listOf(85, 90, 85, 75, 55),
        sizing = listOf(0.65, 1.2),
        evidence = "Original interviews, peer assessments, and a PokerStars retrospective support his historical creative, multi-street bluffing style. The parameters are only adjustable simulation tendencies; they do not infer the real player's VPIP or state of mind.",
        sources = listOf(
            BotSource("Card Player · Original Dwan interview", "https://www.cardplayer.com/cardplayer-poker-magazines/65739-tom-dwan-6-4/articles/18288-the-won-39-durrrr-39-ful-life-of-tom-dwan"),
            BotSource("PokerStars · Historic bluffs retrospective", BLUFFS_RETROSPECTIVE),
        ),
    ),
)

val PROFILE_AXES: List<String> = listOf("Range Width", "Aggression", "Bluffing", "Calling Down", "Trapping")

/** Emotion simulation strength. [id] is the persisted identifier; entry order is the UI order. */
enum class EmotionMode(val id: String, val label: String) {
    OFF("off", "Off"), SUBTLE("subtle", "Subtle"), LIVELY("lively", "Pronounced");

    companion object {
        fun fromId(id: Any?): EmotionMode? = entries.firstOrNull { it.id == id }
    }
}

enum class MoodKind(val id: String, val label: String) {
    STEADY("steady", "Steady"),
    FRUSTRATED("frustrated", "Chasing Losses"),
    CAUTIOUS("cautious", "Playing Safe"),
    CONFIDENT("confident", "On a Heater"),
    REACTIVE("reactive", "Fighting Back"),
}

fun getBotProfile(id: String?): BotProfile = BOT_PROFILES.firstOrNull { it.id == id } ?: BOT_PROFILES[0]

/** Seat assignments always cover seats 1..8, even at a smaller table. */
data class BotSettings(val emotionMode: EmotionMode, val assignments: Map<Int, String>)

fun defaultBotSettings(): BotSettings =
    BotSettings(EmotionMode.SUBTLE, (1..8).associateWith { "balanced" })

/**
 * Accepts untrusted input and never throws: a [BotSettings], or a map shaped
 * like the persisted JSON (`emotionMode`, `assignments` keyed by seat id as an
 * integer or string, or a list indexed by seat id). Anything unrecognized falls back to the defaults.
 */
fun sanitizeBotSettings(value: Any?): BotSettings {
    val defaults = defaultBotSettings()
    val rawMode: Any?
    val rawAssignments: Any?
    when (value) {
        is BotSettings -> {
            rawMode = value.emotionMode.id
            rawAssignments = value.assignments
        }
        is Map<*, *> -> {
            rawMode = value["emotionMode"]
            rawAssignments = value["assignments"]
        }
        else -> {
            rawMode = null
            rawAssignments = null
        }
    }
    val mode = EmotionMode.fromId(rawMode) ?: defaults.emotionMode
    val assignments = LinkedHashMap<Int, String>()
    for (id in 1..8) {
        // `value?.assignments?.[id]` indexes an object by key or an array by seat.
        val profile = when (rawAssignments) {
            is Map<*, *> -> rawAssignments[id] ?: rawAssignments[id.toString()]
            is List<*> -> rawAssignments.getOrNull(id)
            else -> null
        }
        assignments[id] = if (profile is String && BOT_PROFILES.any { it.id == profile }) profile else "balanced"
    }
    return BotSettings(mode, assignments)
}

fun freshBotMood(): BotMood = BotMood()

fun freshBotStats(): BotStats = BotStats()

fun decayBotMood(mood: BotMood) {
    mood.cooldown = maxOf(0, mood.cooldown - 1)
    mood.remaining = maxOf(0, mood.remaining - 1)
    if (mood.remaining == 0) {
        mood.kind = MoodKind.STEADY
        mood.reason = ""
    }
}

/** A mood change, for the activity log. */
data class MoodEvent(val kind: MoodKind, val reason: String)

private fun setMood(mood: BotMood, kind: MoodKind, reason: String): MoodEvent {
    mood.kind = kind
    mood.reason = reason
    mood.remaining = 3
    mood.cooldown = 4
    return MoodEvent(kind, reason)
}

fun recordPressureFold(mood: BotMood, raiser: Int?, mode: EmotionMode): MoodEvent? {
    if (raiser == null || mode == EmotionMode.OFF) return null
    if (mood.lastPressureRaiser != raiser) mood.pressureFolds = java.util.TreeMap()
    mood.lastPressureRaiser = raiser
    val count = (mood.pressureFolds[raiser] ?: 0) + 1
    mood.pressureFolds[raiser] = count
    if (count >= 3 && mood.cooldown == 0) {
        mood.pressureFolds[raiser] = 0
        return setMood(mood, MoodKind.REACTIVE, EngineCopy.reasonPressure)
    }
    return null
}

fun finishBotHand(player: Player, profit: Int, mode: EmotionMode): MoodEvent? {
    val mood = player.botMood
    mood.losses = if (profit <= -250) mood.losses + 1 else 0
    mood.wins = if (profit >= 250) mood.wins + 1 else 0
    if (mode == EmotionMode.OFF || mood.cooldown != 0) return null
    // Both reactions are synthetic; no emotional trait is assigned to a person.
    if (profit <= -1250 || mood.losses >= 3) {
        return setMood(
            mood,
            if (player.id % 2 != 0) MoodKind.FRUSTRATED else MoodKind.CAUTIOUS,
            if (profit <= -1250) EngineCopy.reasonBigLoss else EngineCopy.reasonLosingStreak,
        )
    }
    if (mood.wins >= 2 && profit >= 500) return setMood(mood, MoodKind.CONFIDENT, EngineCopy.reasonWinningStreak)
    return null
}

// A simple, deterministic starting-hand ordering, weighted by the 1,326 actual
// combinations. This is a range-selection heuristic, not an equity table.
private fun startingValue(rankA: Int, suitA: Int, rankB: Int, suitB: Int): Double {
    val high = maxOf(rankA, rankB)
    val low = minOf(rankA, rankB)
    if (high == low) return (30 + high * 2).toDouble()
    val suited = suitA == suitB
    val gap = high - low
    // Strict left-to-right double arithmetic: several classes differ by one ulp.
    return high * 1.9 + low * 0.9 + (if (suited) 4 else 0) +
        (if (gap == 1) 3 else if (gap == 2) 1 else 0) + (if (high == 14) 3 else 0)
}

private val combinations: DoubleArray by lazy {
    val values = ArrayList<Double>(1326)
    for (a in 0 until 52) for (b in a + 1 until 52) {
        values.add(startingValue(a % 13 + 2, a / 13, b % 13 + 2, b / 13))
    }
    values.toDoubleArray()
}

/** Fraction of the 1,326 combinations strictly stronger than [hole] (AA = 0). */
fun startingPercentile(hole: List<Card>): Double {
    val v = startingValue(hole[0].rank, hole[0].suit, hole[1].rank, hole[1].suit)
    return combinations.count { it > v }.toDouble() / combinations.size
}

data class BoardFeatures(val wet: Boolean = false, val draw: Boolean = false, val overpair: Boolean = false)

private val WINDOWS: List<List<Int>> = (0 until 10).map { i -> (0 until 5).map { j -> i + j + 1 } }

fun botBoardFeatures(hole: List<Card>, board: List<Card>, score: List<Int>): BoardFeatures {
    val known = hole + board
    val ranks = known.map { it.rank }.toMutableSet()
    if (14 in ranks) ranks.add(1)
    val suits = (0..3).map { s -> board.count { it.suit == s } }
    val connected = maxOf(0, WINDOWS.maxOf { run ->
        run.count { r -> board.any { c -> c.rank == r || (r == 1 && c.rank == 14) } }
    })
    val maxSuit = maxOf(0, suits.max())
    val wet = maxSuit >= 3 || connected >= 3 || (board.size == 3 && suits.max() == 2)
    val flushDraw = board.size >= 3 && board.size < 5 && score[0] < 5 &&
        (0..3).any { s -> known.count { it.suit == s } == 4 && hole.any { it.suit == s } }
    val straightDraw = board.size >= 3 && board.size < 5 && score[0] < 4 &&
        WINDOWS.any { run ->
            run.count { it in ranks } == 4 &&
                hole.any { c ->
                    (c.rank in run || (c.rank == 14 && 1 in run)) && board.none { b -> b.rank == c.rank }
                }
        }
    val highBoard = maxOf(0, board.maxOfOrNull { it.rank } ?: 0)
    val overpair = hole[0].rank == hole[1].rank && hole[0].rank > highBoard
    return BoardFeatures(wet, flushDraw || straightDraw, overpair)
}

private val MOOD_OFFSETS: Map<MoodKind, List<Int>> = mapOf(
    MoodKind.FRUSTRATED to listOf(14, 12, 10, 15, -10),
    MoodKind.CAUTIOUS to listOf(-14, -12, -12, -16, 5),
    MoodKind.CONFIDENT to listOf(8, 10, 5, 8, -5),
    MoodKind.REACTIVE to listOf(5, 16, 14, 4, -8),
    MoodKind.STEADY to listOf(0, 0, 0, 0, 0),
)

fun effectiveBotAxes(profile: BotProfile, mood: BotMood?, mode: EmotionMode): List<Double> {
    val strength = when (mode) {
        EmotionMode.OFF -> 0.0
        EmotionMode.LIVELY -> 1.0
        EmotionMode.SUBTLE -> 0.5
    }
    val offsets = mood?.let { MOOD_OFFSETS[it.kind] } ?: listOf(0, 0, 0, 0, 0)
    return profile.axes.mapIndexed { i, v -> maxOf(0.0, minOf(100.0, v + offsets[i] * strength)) }
}

/** An opponent as the bot may see it: public stack, bet and all-in state only. */
data class BotOpponent(val id: Int, val stack: Int, val bet: Int, val allin: Boolean)

/**
 * The white-listed actor view. No other hole cards, future deck, review
 * decisions or eventual winners can enter the bot policy.
 */
data class BotView(
    val id: Int,
    val hole: List<Card>,
    val board: List<Card> = emptyList(),
    val street: Int = 0,
    val position: String = "BTN",
    val count: Int = 6,
    /** `null` when unknown; timing then falls back to the position list. */
    val inPosition: Boolean? = null,
    val stack: Int = STARTING_STACK,
    val bet: Int = 0,
    val pot: Int = 0,
    val currentBet: Int = 0,
    val difficulty: Difficulty = Difficulty.NORMAL,
    val legal: LegalActions,
    val rivals: Int = 1,
    /** `null` is the reference's absent `opponents`. */
    val opponents: List<BotOpponent>? = emptyList(),
    val equity: Double = 0.0,
    val equityTrials: Int = 0,
    val contestable: Int = 0,
    val history: List<HistoryEntry> = emptyList(),
    val features: BoardFeatures = BoardFeatures(),
    val playsBoard: Boolean = false,
)

data class RollCheck(val code: String, val value: Double, val threshold: Double, val selected: Boolean)

data class EntryContext(
    val limpers: Int = 0,
    val openCallers: Int = 0,
    val effectiveBehind: Int = 0,
    val speculative: Boolean = false,
    val suitedHigh: Boolean = false,
)

data class BotSizing(
    val fraction: Double,
    val desired: Int,
    val actual: Int,
    val minimum: Int,
    val maximum: Int,
    val opening: Boolean,
    val executed: Boolean,
)

data class TraceMood(val kind: MoodKind = MoodKind.STEADY, val reason: String = "")

/** The private record of why a bot chose an action. Never graded or shown during play. */
data class BotTrace(
    val reason: String = "",
    val profile: String = "balanced",
    val profileName: String = "",
    val mode: EmotionMode = EmotionMode.OFF,
    val mood: TraceMood = TraceMood(),
    val axes: List<Double> = listOf(50.0, 50.0, 40.0, 50.0, 20.0),
    val baseAxes: List<Int> = emptyList(),
    val equityModel: String = "random-opponents",
    val trials: Int = 0,
    val rawEquity: Double = 0.0,
    val noise: Double = 0.0,
    val equity: Double = 0.0,
    val odds: Double = 0.0,
    val pressure: Double = 0.0,
    val percentile: Double = 0.0,
    val range: Double = 0.0,
    val openingRange: Double = 0.0,
    val raiseRange: Double = 0.0,
    val cheapEntry: Boolean = false,
    val cheapRangePassed: Boolean = false,
    val affordableOpen: Boolean = false,
    /** `null` only for hand-built traces; timing then uses `cheapEntry && admitted`. */
    val affordableRangePassed: Boolean? = null,
    val entryContext: EntryContext = EntryContext(),
    val premium: Boolean = false,
    val admitted: Boolean = false,
    val callTolerance: Double = 0.0,
    val checks: List<RollCheck> = emptyList(),
    val exceptions: List<String> = emptyList(),
    val sizing: BotSizing? = null,
    val value: Boolean = false,
    val semiBluff: Boolean = false,
    val pureBluff: Boolean = false,
    val draw: Boolean = false,
    val playsBoard: Boolean = false,
    /** Added by `botDecision`. */
    val view: BotView? = null,
    /** Added to the private execution record by `executeBotTurn`. */
    val thinking: BotThinkingRecord? = null,
)

/** `amount` is present only for a raise (the raise-to total). */
data class BotDecision(val action: Action, val amount: Int? = null, val trace: BotTrace)

// No complete game object is accepted: the caller supplies a white-listed view.
fun chooseBotAction(
    view: BotView,
    profile: BotProfile,
    mood: BotMood?,
    mode: EmotionMode,
    random: RandomSource = SystemRandom,
): BotDecision {
    val legal = view.legal
    if (!legal.enabled) throw PokerException(EngineError.BOT_CANNOT_ACT)
    val axes = effectiveBotAxes(profile, mood, mode)
    val width = axes[0] / 100
    val attack = axes[1] / 100
    val bluff = axes[2] / 100
    val callDown = axes[3] / 100
    val trap = axes[4] / 100
    val checks = mutableListOf<RollCheck>()
    val exceptions = mutableListOf<String>()
    fun roll(code: String, threshold: Double): Double {
        val value = random.next()
        val inclusive = code == "outside-range" || code == "insufficient-equity" || code == "stack-pressure"
        checks.add(RollCheck(code, value, threshold, if (inclusive) value <= threshold else value < threshold))
        return value
    }
    val percentile = startingPercentile(view.hole)
    val odds = legal.callAmount.toDouble() / maxOf(1, view.contestable)
    val pressure = legal.toCall.toDouble() / maxOf(1, view.stack + view.bet)
    val noise = (random.next() - 0.5) * when (view.difficulty) {
        Difficulty.EASY -> 0.16
        Difficulty.HARD -> 0.04
        Difficulty.NORMAL -> 0.08
    }
    val equity = maxOf(0.0, minOf(1.0, view.equity + noise))
    val positionScale = when (view.position) {
        "BTN" -> 1.35
        "CO" -> 1.18
        "SB", "BB" -> 1.05
        "HJ" -> 0.95
        else -> 0.75
    }
    val raises = view.history.filter { it.street == view.street && it.action == Action.RAISE }
    val baseRange = (0.16 + width * 0.42) * positionScale * (if (view.count >= 8) 0.9 else 1.0)
    var range = baseRange
    if (raises.isNotEmpty()) range *= if (raises.size == 1) 0.68 else 0.42
    if (view.position == "BB" && legal.toCall <= 50) range += 0.1
    val openingRange = range
    val preflopHistory = view.history.filter { it.street == 0 }
    val firstOpen = preflopHistory.indexOfFirst { it.action == Action.RAISE }
    val opener = preflopHistory.getOrNull(firstOpen)?.id
    fun callers(history: List<HistoryEntry>): Int = history.filter { a ->
        a.action == Action.CALL && a.amount > 0 && a.id != view.id && a.id != opener &&
            view.opponents?.any { it.id == a.id } == true
    }.map { it.id }.toSet().size
    val limpers = callers(if (firstOpen < 0) preflopHistory else preflopHistory.subList(0, firstOpen))
    val openCallers = if (firstOpen < 0) 0 else callers(preflopHistory.drop(firstOpen + 1))
    val high = maxOf(view.hole[0].rank, view.hole[1].rank)
    val low = minOf(view.hole[0].rank, view.hole[1].rank)
    val suited = view.hole[0].suit == view.hole[1].suit
    val pair = high == low
    val speculative = pair || (suited && (high == 14 || (high - low <= 2 && low >= 5)))
    val suitedHigh = suited && high >= 11 && low >= 7
    val lastRaiserId = raises.lastOrNull()?.id
    val lastRaiser = view.opponents?.firstOrNull { lastRaiserId != null && it.id == lastRaiserId }
    val effectiveBehind = maxOf(0, minOf(view.stack - legal.callAmount, lastRaiser?.stack ?: 0))
    val lowCommitment = pressure <= 0.08 && legal.callAmount < view.stack
    val allInPressure = view.opponents?.any { it.allin } ?: false
    val cheapEntry = view.street == 0 && raises.isEmpty() && view.currentBet <= 50 && legal.toCall <= 50 &&
        lowCommitment && !allInPressure
    // Small single opens are a different price from 3-bets and shoves. This
    // bounded calling branch does not compare an all-players showdown estimate
    // with today's price before anyone behind has actually entered the pot.
    val affordableOpen = view.street == 0 && lastRaiser != null && raises.size == 1 && raises[0].id != view.id &&
        legal.toCall > 0 && view.currentBet <= 200 && legal.callAmount <= 200 && lowCommitment &&
        !allInPressure && effectiveBehind >= maxOf(1000, legal.callAmount * 15)
    if (cheapEntry) {
        range += 0.14 + width * 0.2 + (if (speculative || suitedHigh) minOf(2, limpers) * 0.04 else 0.0)
    }
    if (affordableOpen) {
        val priceScale = maxOf(0.65, 1.1 - (view.currentBet / 50.0) * 0.08)
        val playability = if (speculative) 0.09 else if (suitedHigh) 0.07 else 0.0
        val callerBonus = if (speculative || suitedHigh) minOf(2, openCallers) * 0.04 else 0.0
        val blindDiscount = if (view.position == "BB") 0.08 else 0.0
        val dominatedAce = if (!suited && high == 14 && low <= 8) 0.08 else 0.0
        range = baseRange * priceScale + 0.12 + width * 0.18 + playability + callerBonus + blindDiscount - dominatedAce
    }
    range = minOf(0.95, range)
    // Entering a pot is not automatically a reason to raise again. Separate the
    // value re-raising candidates so ordinary calls do not start a raise cascade.
    val raiseRange = if (raises.isNotEmpty()) {
        minOf(
            openingRange,
            (0.035 + width * 0.085) * (if (raises.size == 1) 1.0 else 0.58) *
                (if (view.position == "BTN" || view.position == "CO") 1.15 else 1.0),
        )
    } else {
        openingRange
    }
    val premium = percentile < 0.07
    val admitted = percentile <= range
    val affordableRangePassed = (cheapEntry || affordableOpen) && admitted
    val callTolerance = (callDown - 0.5) * 0.1
    var sizing: BotSizing? = null
    var value = false
    var semiBluff = false
    var pureBluff = false
    fun finish(action: Action, reason: String, amount: Int? = null) = BotDecision(
        action,
        amount,
        BotTrace(
            reason = reason,
            profile = profile.id,
            profileName = profile.name,
            mode = mode,
            mood = TraceMood(mood?.kind ?: MoodKind.STEADY, mood?.reason ?: ""),
            axes = axes,
            baseAxes = profile.axes.toList(),
            trials = if (view.equityTrials != 0) view.equityTrials else if (view.difficulty == Difficulty.HARD) 52 else 28,
            rawEquity = view.equity,
            noise = noise,
            equity = equity,
            odds = odds,
            pressure = pressure,
            percentile = percentile,
            range = range,
            openingRange = openingRange,
            raiseRange = raiseRange,
            cheapEntry = cheapEntry,
            cheapRangePassed = cheapEntry && admitted,
            affordableOpen = affordableOpen,
            affordableRangePassed = affordableRangePassed,
            entryContext = EntryContext(limpers, openCallers, effectiveBehind, speculative, suitedHigh),
            premium = premium,
            admitted = admitted,
            callTolerance = callTolerance,
            checks = checks.toList(),
            exceptions = exceptions.toList(),
            sizing = sizing,
            value = value,
            semiBluff = semiBluff,
            pureBluff = pureBluff,
            draw = view.features.draw,
            playsBoard = view.playsBoard,
        ),
    )
    fun passive(): BotDecision = finish(
        if (legal.canCheck) Action.CHECK else Action.CALL,
        when {
            legal.canCheck -> "free-check"
            exceptions.isNotEmpty() -> "loose-exception"
            cheapEntry && admitted -> "affordable-entry"
            affordableOpen && admitted -> "affordable-open"
            premium && view.street == 0 -> "premium-continue"
            else -> "price-continue"
        },
    )
    if (legal.toCall > 0) {
        if (view.street == 0 && !admitted && !premium && odds > 0.09) {
            val t = 0.06 * width
            if (roll("outside-range", t) > t) return finish(Action.FOLD, "outside-range")
            exceptions.add("outside-range")
        }
        if ((!premium || view.street > 0) && !affordableRangePassed) {
            if (equity + callTolerance < odds + 0.02) {
                val t = 0.03 + callDown * 0.1
                if (roll("insufficient-equity", t) > t) return finish(Action.FOLD, "insufficient-equity")
                exceptions.add("insufficient-equity")
            }
            if (pressure > 0.4 && equity + callTolerance < (if (view.street == 0) 0.38 else 0.32)) {
                val t = 0.03 + callDown * 0.07
                if (roll("stack-pressure", t) > t) return finish(Action.FOLD, "stack-pressure")
                exceptions.add("stack-pressure")
            }
        }
    }
    if (!legal.canRaise) return passive()
    val headsUp = view.rivals == 1
    val features = view.features
    val ownLastRaise = view.history.lastOrNull { it.action == Action.RAISE }?.id == view.id
    semiBluff = view.street > 0 && features.draw && view.rivals <= 2 && run {
        val t = (0.12 + bluff * 0.42) * (if (headsUp) 1.0 else 0.45)
        roll("semi-bluff", t) < t
    }
    val story = if (view.street == 0) view.position == "BTN" || view.position == "CO" else ownLastRaise || !features.wet
    pureBluff = !view.playsBoard && view.rivals <= 2 && story && pressure < 0.25 && run {
        val t = (0.015 + bluff * 0.17) * (if (headsUp) 1.0 else 0.2)
        roll("pure-bluff", t) < t
    }
    value = if (view.street == 0) {
        premium || percentile <= raiseRange
    } else {
        !view.playsBoard &&
            (equity > (if (headsUp) 0.53 else 1.0 / (view.rivals + 1) + 0.23) || (features.overpair && equity > 0.4))
    }
    if (value && view.street > 0 && legal.canCheck && !features.wet && equity > 0.65 &&
        roll("trap", trap * 0.52) < trap * 0.52
    ) {
        return finish(Action.CHECK, "trap")
    }
    if ((value || semiBluff || pureBluff) && roll("attack", 0.2 + attack * 0.72) < 0.2 + attack * 0.72) {
        var fraction = profile.sizing[0] + random.next() * (profile.sizing[1] - profile.sizing[0])
        if (profile.id == "abao" && view.street == 1 && ownLastRaise) fraction = 0.33
        if (profile.id == "abao" && view.street == 2 && semiBluff) fraction = 0.9
        if (mode != EmotionMode.OFF && mood?.kind in setOf(MoodKind.FRUSTRATED, MoodKind.CONFIDENT, MoodKind.REACTIVE)) {
            fraction *= if (mode == EmotionMode.LIVELY) 1.2 else 1.1
        }
        var desired = view.currentBet +
            jsRound(maxOf(50.0, (view.pot + legal.callAmount) * fraction) / 25).toInt() * 25
        val opening = view.street == 0 && raises.isEmpty()
        if (opening) {
            desired = 125 + (if (attack > 0.8) 25 else 0) +
                view.history.count { it.street == 0 && it.action == Action.CALL } * 50
        }
        if (view.street == 0 && profile.id == "peter" && view.hole[0].rank == view.hole[1].rank &&
            view.hole[0].rank <= 6 && admitted && headsUp && roll("rare-pocket-shove", 0.04) < 0.04
        ) {
            desired = legal.maxRaiseTo
        }
        val amount = maxOf(legal.minRaiseTo, minOf(legal.maxRaiseTo, desired))
        sizing = BotSizing(fraction, desired, amount, legal.minRaiseTo, legal.maxRaiseTo, opening, false)
        if (amount != legal.maxRaiseTo || value || semiBluff || view.stack <= 500) {
            sizing = sizing.copy(executed = true)
            return finish(
                Action.RAISE,
                if (value) "value-raise" else if (semiBluff) "semi-bluff" else "pure-bluff",
                amount,
            )
        }
    }
    return passive()
}
