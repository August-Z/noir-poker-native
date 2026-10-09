package com.august.noirpoker.core.session

import com.august.noirpoker.core.Action
import com.august.noirpoker.core.BotDecisionRecord
import com.august.noirpoker.core.BotPlan
import com.august.noirpoker.core.BotSettings
import com.august.noirpoker.core.Difficulty
import com.august.noirpoker.core.EmotionMode
import com.august.noirpoker.core.Game
import com.august.noirpoker.core.LabelStep
import com.august.noirpoker.core.MAX_PLAYERS
import com.august.noirpoker.core.MIN_PLAYERS
import com.august.noirpoker.core.MoodKind
import com.august.noirpoker.core.Phase
import com.august.noirpoker.core.Player
import com.august.noirpoker.core.PokerException
import com.august.noirpoker.core.PotSet
import com.august.noirpoker.core.RandomSource
import com.august.noirpoker.core.SystemRandom
import com.august.noirpoker.core.advanceStreet
import com.august.noirpoker.core.act
import com.august.noirpoker.core.applyBotSettings
import com.august.noirpoker.core.canRestartHand
import com.august.noirpoker.core.completeBoardForPractice
import com.august.noirpoker.core.currentPots
import com.august.noirpoker.core.evaluate
import com.august.noirpoker.core.executeBotTurn
import com.august.noirpoker.core.formatChips
import com.august.noirpoker.core.getBotProfile
import com.august.noirpoker.core.isBotTurnCurrent
import com.august.noirpoker.core.jsRound
import com.august.noirpoker.core.legalActions
import com.august.noirpoker.core.newGame
import com.august.noirpoker.core.planBotTurn
import com.august.noirpoker.core.playBotTurn
import com.august.noirpoker.core.potSize
import com.august.noirpoker.core.raiseCaption
import com.august.noirpoker.core.restartHand
import com.august.noirpoker.core.seatPosition
import com.august.noirpoker.core.startHand

/** Reference seat centers per table size, as `[left%, top%]` for seats 1..count-1. */
val SEAT_LAYOUTS: Map<Int, List<Pair<Double, Double>>> = mapOf(
    5 to listOf(15.0 to 59.0, 23.0 to 0.0, 77.0 to 0.0, 85.0 to 59.0),
    6 to listOf(14.0 to 60.0, 17.0 to 14.0, 50.0 to 0.0, 83.0 to 14.0, 86.0 to 60.0),
    7 to listOf(14.0 to 63.0, 11.5 to 27.0, 35.0 to 0.0, 65.0 to 0.0, 88.5 to 27.0, 86.0 to 63.0),
    8 to listOf(14.0 to 68.0, 11.5 to 36.0, 23.0 to 6.0, 50.0 to 0.0, 77.0 to 6.0, 88.5 to 36.0, 86.0 to 68.0),
    9 to listOf(14.0 to 72.0, 13.0 to 45.0, 16.0 to 18.0, 36.0 to 0.0, 64.0 to 0.0, 84.0 to 18.0, 87.0 to 45.0, 86.0 to 72.0),
)

/** The bot currently "thinking": its plan and the virtual-clock deadline. Diagnostic only. */
data class BotWaitInfo(val actor: Int, val delayMs: Int, val startedAt: Long, val deadline: Long)

/**
 * The platform-neutral table session: a port of `table-controller.js` (with the
 * settings logic of `opponents-controller.js` and `preferences.js`, the
 * showdown data of `showdown.js` and the scheduling of `review-controller.js`).
 *
 * It owns the live [Game] and all session state, and publishes an immutable
 * [TableRenderState] after every change. It is single-threaded: call every
 * command, and deliver every [Scheduler] and [ReviewSink] callback, on the same
 * (main) thread. It imports no UI framework; a Compose `ViewModel` or SwiftUI
 * observable model wraps it.
 *
 * Randomness: one [random] stream feeds the shuffle, every bot decision and
 * every thinking time, in the reference's order (`Math.random`).
 *
 * Cancellation: [epoch] is the reference's cancellation token. It increments on
 * Next Hand, Replay Hand, Start New Session, Finish Hand and moving to the
 * background; every scheduled callback captures it and does nothing once it
 * changed, and the timer handle is cancelled as well.
 */
class TableSession(
    private val scheduler: Scheduler,
    storage: KeyValueStorage,
    private val random: RandomSource = SystemRandom,
    reviewRunner: ReviewRunner? = null,
) {
    private val preferences = PreferencesStore(storage)

    /**
     * A planned bot decision waiting for its [deadline]. [pausedMs] is the time
     * the app spent in the background during the wait, so [waitedMs] counts only
     * foreground time.
     */
    private class BotWait(val plan: BotPlan, val startedAt: Long, val deadline: Long, val pausedMs: Long = 0) {
        fun waitedMs(now: Long): Long = now - startedAt - pausedMs
    }

    private var requestedCount: Int
    internal var game: Game
        private set
    private var timer: Cancellable? = null
    private var finishTimer: Cancellable? = null
    private var botWait: BotWait? = null
    private var finishWaiting: BotWait? = null

    /** Cancellation token for scheduled work. */
    var epoch: Int = 0
        private set

    /**
     * The reference's `epoch` as used for the review and showdown keys. It moves
     * with [epoch] except on background transitions, so returning to the app does
     * not rebuild a finished review.
     */
    var viewToken: Int = 0
        private set

    private var lastBoard = 0
    private var lastHand = 0
    private var bet = DEFAULT_BET
    private var finishing = false
    private var hints: Boolean
    private var sound: Boolean
    private var pendingBotSettings: BotSettings
    private val seatHandVisibility = HashMap<Int, Boolean>()
    private var backgrounded = false
    private var backgroundedAt = 0L
    private var potDialogOpen = false
    private val potExpanded = HashSet<Int>()
    private val opponentsEditor = OpponentSettingsEditor()
    private val review = HandReviewController(reviewRunner) { render() }

    private var showdownKey: String? = null
    private var showdownState: ShowdownState? = null

    private data class Animation(val newHand: Boolean, val lastBoard: Int, val boardChanged: Boolean)

    private var pendingAnimation: Animation? = null
    private var version = 0L
    private var rendering = false
    private var dirty = false
    private val listeners = LinkedHashSet<(TableRenderState) -> Unit>()

    /** Receives sounds (only while sound is on), chip flights and focus effects. */
    var effectListener: ((SessionEffect) -> Unit)? = null

    /** The latest published state. */
    lateinit var state: TableRenderState
        private set

    init {
        val table = preferences.loadTable()
        requestedCount = table.playerCount
        game = newGame(requestedCount)
        game.difficulty = table.difficulty
        sound = preferences.loadSound()
        hints = preferences.loadHints()
        pendingBotSettings = preferences.loadBotSettings()
        render()
    }

    companion object {
        const val DEFAULT_BET = 150
        const val STREET_DELAY_MS = 1000L
        const val SHOWDOWN_DELAY_MS = 850L
    }

    // ---- Observation ----------------------------------------------------------

    fun addListener(listener: (TableRenderState) -> Unit): Cancellable {
        listeners.add(listener)
        listener(state)
        return Cancellable { listeners.remove(listener) }
    }

    /** Deals the first hand (the reference deals hand 1 at startup). Does nothing afterwards. */
    fun start() {
        if (game.hand == 0 && game.phase == Phase.IDLE) nextHand()
    }

    // ---- Hero actions -----------------------------------------------------------

    /** `heroAction`: returns false when it is not the hero's turn or the amount is illegal. */
    fun heroAction(action: Action, amount: Int? = null): Boolean {
        val legal = legalActions(game, 0)
        if (!legal.enabled) return false
        try {
            act(game, 0, action, amount)
        } catch (_: PokerException) {
            return false
        }
        if (action == Action.RAISE || (action == Action.CALL && legal.toCall > 0)) {
            emit(SessionEffect.ChipFlight(0))
            playSound(SoundKind.CHIP)
        }
        if (game.phase == Phase.DONE) playSound(SoundKind.WIN)
        render()
        schedule()
        return true
    }

    fun fold() = heroAction(Action.FOLD)

    /** The Call / Check button: the engine turns a call with nothing owed into a check. */
    fun callOrCheck() = heroAction(Action.CALL)

    /** The Raise button with the selected [bet] (or an explicit raise-to total). */
    fun raise(amount: Int = bet) = heroAction(Action.RAISE, amount)

    /** The current raise-to selection. */
    val currentBet: Int get() = bet

    /**
     * Slider input: snaps to multiples of 25 (round half up) within the legal
     * range, except that the exact maximum (all-in) is kept.
     */
    fun setBet(value: Int) {
        val legal = legalActions(game, 0)
        if (!legal.enabled) return
        var b = if (value == legal.maxRaiseTo) value else maxOf(legal.minRaiseTo, (jsRound(value / 25.0) * 25).toInt())
        b = minOf(legal.maxRaiseTo, b)
        bet = b
        render()
    }

    /** Accessibility increment / decrement: moves the bet by 25 per step, clamped to the legal range. */
    fun nudgeBet(steps: Int) {
        val legal = legalActions(game, 0)
        if (!legal.enabled || !legal.canRaise) return
        bet = (bet + steps * 25).coerceIn(legal.minRaiseTo, legal.maxRaiseTo)
        render()
    }

    /** The amount a preset would select, or `null` when raising is unavailable. */
    fun presetAmount(preset: BetPreset): Int? {
        val legal = legalActions(game, 0)
        if (!legal.canRaise) return null
        val raw = when (preset) {
            BetPreset.ALL_IN -> legal.maxRaiseTo
            BetPreset.MIN -> legal.minRaiseTo
            else -> {
                val fraction = if (preset == BetPreset.HALF_POT) 0.5 else 1.0
                game.currentBet + maxOf(game.minRaise, (jsRound(potSize(game) * fraction / 25) * 25).toInt())
            }
        }
        return minOf(legal.maxRaiseTo, maxOf(legal.minRaiseTo, raw))
    }

    /** Min / ½ Pot / Pot / All-In. */
    fun preset(preset: BetPreset): Boolean {
        val amount = presetAmount(preset) ?: return false
        bet = amount
        render()
        return true
    }

    // ---- Hand flow ----------------------------------------------------------------

    /**
     * Next Hand (also Rebuy and Keep Practicing). Applies a pending seat count and
     * opponent styles. Returns false while a hand is in progress (the engine's
     * `startHand` refuses it, and the reference only offers Next Hand once the
     * hand is over).
     */
    fun nextHand(): Boolean {
        if (game.phase != Phase.IDLE && game.phase != Phase.DONE) return false
        botWait = null
        seatHandVisibility.clear()
        finishing = false
        finishWaiting = null
        cancelTimer()
        cancelFinishLoop()
        resetShowdown()
        epoch++
        viewToken++
        lastBoard = 0
        closePotDialog()
        if (requestedCount != game.players.size) {
            val difficulty = game.difficulty
            game = newGame(requestedCount)
            game.difficulty = difficulty
            review.reset()
            lastHand = 0
        }
        applyBotSettings(game, pendingBotSettings)
        startHand(game, random)
        val legal = legalActions(game, 0)
        bet = if (legal.enabled) minOf(legal.maxRaiseTo, maxOf(legal.minRaiseTo, DEFAULT_BET)) else DEFAULT_BET
        render()
        playSound(SoundKind.DEAL)
        schedule()
        return true
    }

    /** Replay Hand: restores the post-blind state of this hand and reverses its settlement once. */
    fun replayHand(): Boolean {
        if (!canRestartHand(game)) return false
        botWait = null
        seatHandVisibility.clear()
        finishing = false
        finishWaiting = null
        cancelTimer()
        cancelFinishLoop()
        resetShowdown()
        review.rollback(game, viewToken)
        epoch++
        viewToken++
        closePotDialog()
        emit(SessionEffect.CancelChipFlights)
        restartHand(game)
        lastHand = 0
        lastBoard = 0
        bet = DEFAULT_BET
        render()
        playSound(SoundKind.DEAL)
        schedule()
        return true
    }

    /** Start New Session (after the confirmation): a new table with the requested size, difficulty and saved styles. */
    fun startNewSession() {
        review.reset()
        val difficulty = game.difficulty
        cancelTimer()
        cancelFinishLoop()
        game = newGame(requestedCount)
        game.difficulty = difficulty
        lastHand = 0
        nextHand()
    }

    /** Whether Finish Hand is available (`canFastFinish`). */
    fun canFinishHand(): Boolean {
        val hero = game.players[0]
        return hero.folded && !finishing && !backgrounded &&
            (game.phase != Phase.DONE || (game.board.size < 5 && game.practiceBoard == null))
    }

    /**
     * Finish Hand (`continueDeal`): executes the pending planned decision at
     * once, plans and executes every later bot turn immediately, deals streets
     * without delay, and adds a practice runout after a fold-win. Each step runs
     * on its own zero-delay tick so it can be cancelled.
     */
    fun finishHand(): Boolean {
        if (!canFinishHand()) return false
        cancelTimer()
        finishWaiting = botWait
        botWait = null
        epoch++
        viewToken++
        val ticket = epoch
        finishing = true
        render()
        if (game.phase == Phase.DONE) {
            finishComplete(ticket)
        } else {
            finishTimer = scheduler.schedule(0) { finishStep(ticket) }
        }
        return true
    }

    private fun finishStep(ticket: Int) {
        finishTimer = null
        if (ticket != epoch) return
        try {
            if (game.phase == Phase.BETWEEN) {
                advanceStreet(game)
            } else {
                val waiting = finishWaiting
                if (waiting != null && isBotTurnCurrent(game, waiting.plan)) {
                    executeBotTurn(game, waiting.plan, expedited = true, waitedMs = waiting.waitedMs(scheduler.nowMs))
                } else {
                    playBotTurn(game, random, random)
                }
            }
            if (game.phase == Phase.BETWEEN) render()
        } catch (e: RuntimeException) {
            finishSettle(ticket)
            throw e
        }
        if (ticket != epoch) return
        if (game.phase != Phase.DONE) {
            finishTimer = scheduler.schedule(0) { finishStep(ticket) }
            return
        }
        finishComplete(ticket)
    }

    private fun finishComplete(ticket: Int) {
        try {
            if (ticket == epoch) completeBoardForPractice(game)
        } finally {
            finishSettle(ticket)
        }
    }

    private fun finishSettle(ticket: Int) {
        if (ticket != epoch) return
        finishing = false
        finishWaiting = null
        render()
        if (game.phase == Phase.DONE) playSound(SoundKind.WIN)
        schedule()
    }

    /** The post-settlement eye toggle: shows or hides one opponent's hole cards (display only). */
    fun toggleReveal(seat: Int): Boolean {
        val p = game.players.getOrNull(seat)
        if (game.phase != Phase.DONE || seat == 0 || p == null) return false
        val visible = !isSeatHandVisible(p)
        seatHandVisibility[seat] = visible
        render()
        emit(SessionEffect.RevealToggled(seat, visible))
        return true
    }

    // ---- Settings -------------------------------------------------------------------

    /** Table size 5–9: saved now, applied by the next Next Hand or Start New Session. */
    fun setSeatCount(count: Int): Boolean {
        if (count < MIN_PLAYERS || count > MAX_PLAYERS) return false
        requestedCount = count
        preferences.saveTable(TablePreferences(requestedCount, game.difficulty))
        render()
        return true
    }

    /** Opponent difficulty takes effect immediately; a thinking bot re-plans under it. */
    fun setDifficulty(difficulty: Difficulty) {
        game.difficulty = difficulty
        preferences.saveTable(TablePreferences(requestedCount, game.difficulty))
        if (game.phase == Phase.PLAYING && game.actor != 0 && !finishing) schedule()
        render()
    }

    fun toggleHints() {
        hints = !hints
        preferences.saveHints(hints)
        render()
    }

    fun toggleSound() {
        sound = !sound
        preferences.saveSound(sound)
        render()
        if (sound) playSound(SoundKind.DEAL)
    }

    /** The saved opponent settings that the next deal applies. */
    val savedBotSettings: BotSettings get() = pendingBotSettings

    fun openOpponentSettings() {
        opponentsEditor.open(pendingBotSettings)
        render()
    }

    fun previewProfile(id: String) {
        opponentsEditor.previewProfile(id)
        render()
    }

    fun assignSeatStyle(seat: Int, profile: String) {
        opponentsEditor.assignSeat(seat, profile)
        render()
    }

    fun setEmotionMode(mode: EmotionMode) {
        opponentsEditor.setEmotionMode(mode)
        render()
    }

    fun mixLineup() {
        opponentsEditor.mixLineup()
        render()
    }

    /** Save (applies next hand): persists the sanitized draft and closes the dialog. */
    fun saveOpponentSettings(): Boolean {
        val settings = opponentsEditor.save() ?: return false
        preferences.saveBotSettings(settings)
        pendingBotSettings = settings
        render()
        return true
    }

    /** Close without saving: the next open starts again from the saved settings. */
    fun discardOpponentSettings() {
        opponentsEditor.discard()
        render()
    }

    // ---- Pot details and review --------------------------------------------------

    fun openPotDetails() {
        potDialogOpen = true
        render()
    }

    fun closePotDetails() {
        closePotDialog()
        render()
    }

    /** Expands or collapses a settled pot's distribution details (kept by pot index). */
    fun togglePotDistribution(index: Int) {
        if (!potExpanded.add(index)) potExpanded.remove(index)
        render()
    }

    private fun closePotDialog() {
        potDialogOpen = false
        potExpanded.clear()
    }

    fun openReview() = review.open()
    fun closeReview() = review.close()
    fun retryReview() = review.retry()
    fun selectReviewStep(index: Int) = review.select(index)
    fun previousReviewStep() = review.previous()
    fun nextReviewStep() = review.next()
    fun setReviewPerspective(perspective: ReviewPerspective) = review.setPerspective(perspective)
    fun setOpponentReviewFilter(seat: Int?) = review.setOpponentFilter(seat)
    fun selectOpponentReviewRecord(index: Int) = review.selectOpponent(index)

    // ---- Lifecycle --------------------------------------------------------------------

    /**
     * The app moved to the background: cancel the timer, stop a running Finish
     * Hand loop and the review job. A thinking bot keeps its plan (no new random
     * draws); on return it waits only for the rest of its delay, and the time
     * spent in the background is excluded from its recorded `waitedMs`. A
     * cancelled Finish Hand is not resumed: the player taps it again.
     */
    fun onBackground() {
        if (backgrounded) return
        backgrounded = true
        backgroundedAt = scheduler.nowMs
        cancelTimer()
        cancelFinishLoop()
        epoch++
        if (finishing) {
            finishing = false
            val waiting = finishWaiting
            if (waiting != null && isBotTurnCurrent(game, waiting.plan)) botWait = waiting
        }
        finishWaiting = null
        review.pause()
        render()
    }

    fun onForeground() {
        if (!backgrounded) return
        backgrounded = false
        val waiting = botWait
        botWait = if (waiting != null && isBotTurnCurrent(game, waiting.plan)) {
            val away = maxOf(0L, scheduler.nowMs - backgroundedAt)
            BotWait(waiting.plan, waiting.startedAt, waiting.deadline + away, waiting.pausedMs + away)
        } else {
            null
        }
        review.resume()
        render()
        schedule()
    }

    // ---- Scheduling ---------------------------------------------------------------------

    private fun cancelTimer() {
        timer?.cancel()
        timer = null
    }

    private fun cancelFinishLoop() {
        finishTimer?.cancel()
        finishTimer = null
    }

    /** The reference `schedule()`: the single pending street advance or bot action. */
    private fun schedule() {
        cancelTimer()
        val ticket = epoch
        if (backgrounded || game.phase == Phase.IDLE) return
        if (game.phase == Phase.DONE || finishing) {
            botWait = null
            return
        }
        if (game.phase == Phase.BETWEEN) {
            botWait = null
            timer = scheduler.schedule(if (game.board.size == 5) SHOWDOWN_DELAY_MS else STREET_DELAY_MS) {
                if (ticket != epoch || game.phase != Phase.BETWEEN || finishing) return@schedule
                timer = null
                advanceStreet(game)
                playSound(if (game.phase == Phase.DONE) SoundKind.WIN else SoundKind.DEAL)
                render()
                schedule()
            }
        } else if (game.actor != 0) {
            val current = botWait
            if (current == null || !isBotTurnCurrent(game, current.plan)) {
                val plan = planBotTurn(game, random, random)
                val startedAt = scheduler.nowMs
                botWait = BotWait(plan, startedAt, startedAt + plan.delayMs)
            }
            val waiting = botWait!!
            timer = scheduler.schedule(maxOf(0L, waiting.deadline - scheduler.nowMs)) {
                if (ticket != epoch || botWait !== waiting || finishing) return@schedule
                timer = null
                if (!isBotTurnCurrent(game, waiting.plan)) {
                    botWait = null
                    schedule()
                    return@schedule
                }
                botWait = null
                val id = game.actor
                val d = executeBotTurn(game, waiting.plan, waitedMs = waiting.waitedMs(scheduler.nowMs))
                if (d.action != Action.FOLD && d.action != Action.CHECK) {
                    emit(SessionEffect.ChipFlight(id))
                    playSound(SoundKind.CHIP)
                }
                if (game.phase == Phase.DONE) playSound(SoundKind.WIN)
                render()
                schedule()
            }
        } else {
            botWait = null
        }
    }

    // ---- Effects ------------------------------------------------------------------------

    private fun emit(effect: SessionEffect) {
        effectListener?.invoke(effect)
    }

    private fun playSound(kind: SoundKind) {
        if (sound) emit(SessionEffect.Sound(kind))
    }

    // ---- Rendering ----------------------------------------------------------------------

    private fun isSeatHandVisible(p: Player): Boolean {
        if (game.phase == Phase.DONE) seatHandVisibility[p.id]?.let { return it }
        return (game.showdown || game.revealed) && !p.folded
    }

    private fun resetShowdown() {
        showdownKey = null
        showdownState = null
    }

    private fun updateShowdown() {
        val g = game
        val nextKey = "$viewToken:${g.hand}"
        if (g.phase != Phase.DONE || !g.showdown) {
            resetShowdown()
            return
        }
        if (showdownKey == nextKey) return
        showdownKey = nextKey
        val scenes = showdownScenes(g)
        val names = ActivityFormatter(g.players)
        showdownState = if (scenes.isEmpty()) {
            null
        } else {
            ShowdownState(
                key = nextKey,
                context = SessionCopy.sdContext(scenes.size, g.pots.size > 1),
                scenes = scenes.map { s ->
                    val won = s.awards.isNotEmpty()
                    ShowdownSceneState(
                        scene = s,
                        nameSegments = names.format(s.name),
                        isWinner = won,
                        statusText = if (won) SessionCopy.sdWon(s.amount) else SessionCopy.sdNoPot,
                        footerText = if (won) {
                            s.awards.joinToString(" · ") { SessionCopy.sdAwardItem(it.pot, it.split, it.amount) }
                        } else {
                            SessionCopy.sdBestFive
                        },
                        a11y = SessionCopy.sdPlayerA11y(s.name, s.label),
                    )
                },
            )
        }
    }

    /** Recomputes and publishes the state. Mutates only the bet clamp, review input and showdown key. */
    private fun render() {
        if (rendering) {
            dirty = true
            return
        }
        rendering = true
        try {
            do {
                dirty = false
                val displayBoardSize = (game.practiceBoard ?: game.board).size
                val animation = pendingAnimation ?: Animation(
                    newHand = game.hand != lastHand,
                    lastBoard = lastBoard,
                    boardChanged = displayBoardSize > lastBoard,
                ).also { pendingAnimation = it }
                val legal = legalActions(game, 0)
                if (legal.enabled) bet = minOf(legal.maxRaiseTo, maxOf(legal.minRaiseTo, bet))
                review.update(game, viewToken)
                updateShowdown()
                if (dirty) continue
                state = buildState(animation)
                lastHand = game.hand
                lastBoard = displayBoardSize
            } while (dirty)
        } finally {
            rendering = false
            pendingAnimation = null
        }
        for (l in listeners.toList()) l(state)
    }

    private fun position(id: Int): PositionBadge {
        val code = seatPosition(game, id)
        return PositionBadge(code, SessionCopy.positionNames[code] ?: code)
    }

    private fun buildState(anim: Animation): TableRenderState {
        val g = game
        val count = g.players.size
        val hero = g.players[0]
        val done = g.phase == Phase.DONE
        val displayBoard = g.practiceBoard ?: g.board
        val heroBest: Set<String> =
            if (g.showdown && !hero.folded) evaluate(hero.hole + g.board).cards.map { it.key }.toSet() else emptySet()
        val details: PotSet = currentPots(g)
        val legal = legalActions(g, 0)

        val board = (0 until 5).map { i ->
            val c = displayBoard.getOrNull(i)
            BoardSlot(
                index = i,
                card = c?.let {
                    CardFace(it, best = it.key in heroBest, animate = i >= anim.lastBoard && anim.boardChanged, delayMs = (i - anim.lastBoard) * 140)
                },
                placeholderGlyph = SessionCopy.boardSlotGlyphs[i],
                a11y = c?.toString() ?: SessionCopy.undealtCard,
            )
        }

        var caption = when {
            g.practiceBoard != null -> SessionCopy.captionPractice
            done && g.showdown -> if (hero.folded) SessionCopy.captionShowdownFolded else SessionCopy.captionShowdownHero
            g.street == 0 -> SessionCopy.captionPreflop
            g.street == 1 -> SessionCopy.captionFlop
            g.street == 2 -> SessionCopy.captionTurn
            else -> SessionCopy.captionRiver
        }
        if (details.pots.size > 1) caption = SessionCopy.captionMultiPot(done, details.pots[0].amount, details.pots.size - 1)

        val seats = g.players.drop(1).map { p -> seatState(p, anim) }

        val heroWinner = g.winners.firstOrNull { it.id == 0 }
        val showHeroRank = g.board.size == 5 && (g.revealed || g.showdown)
        val heroBadge = if (!showHeroRank && heroWinner == null) {
            null
        } else {
            RankBadge(
                text = if (showHeroRank) {
                    (if (hero.folded) SessionCopy.heroFoldedPrefix else "") + evaluate(hero.hole + g.board).label
                } else {
                    SessionCopy.winnerFallback
                },
                isWinner = heroWinner != null,
                a11y = heroWinner?.let { SessionCopy.heroWinnerA11y(it.amount) },
                title = heroWinner?.let { SessionCopy.winnerTitle(it.label, it.amount) },
            )
        }
        val heroState = HeroState(
            name = SessionCopy.heroName,
            cards = hero.hole.mapIndexed { i, c -> CardFace(c, best = c.key in heroBest, animate = anim.newHand, delayMs = 420 + i * 130) },
            rankBadge = heroBadge,
            folded = hero.folded,
            isActive = g.actor == 0,
            stack = hero.stack,
            stackText = formatChips(hero.stack),
            position = position(0),
            turnText = if (done) {
                null
            } else {
                when {
                    g.actor == 0 -> SessionCopy.heroTurnYours
                    hero.folded -> SessionCopy.heroTurnFolded
                    hero.allin -> SessionCopy.heroTurnAllIn
                    else -> SessionCopy.waiting
                }
            },
            lastAction = hero.lastAction?.let { seatActionChip(g, hero, recent = true) },
            lastActionA11y = SessionCopy.heroLastActionA11y,
        )

        val diff = hero.stack - g.stats.buyin
        val session = SessionStatsState(
            stack = hero.stack,
            stackText = formatChips(hero.stack),
            chipsUnit = SessionCopy.chipsUnit,
            changeText = if (g.stats.hands > 0) SessionCopy.sessionChange(diff) else SessionCopy.sessionChangeInitial,
            negative = diff < 0,
            hands = g.stats.hands,
            wins = g.stats.wins,
            winRateText = if (g.stats.hands > 0) {
                SessionCopy.winRate(jsRound(g.stats.wins.toDouble() / g.stats.hands * 100).toInt())
            } else {
                SessionCopy.statEmpty
            },
        )

        val formatter = ActivityFormatter(g.players)
        val activity = ActivityState(
            entries = g.logs.asReversed().mapIndexed { i, l ->
                val segments = formatter.formatLog(l)
                ActivityEntryState(i + 1, segments.plainText(), segments, l.type, l.player, l.player == 0, l.street)
            },
            badge = if (done) SessionCopy.activityFinished else SessionCopy.activityLive,
        )

        val actions = actionPanel(legal, done)

        val coach = CoachState(
            visible = hints,
            toggleOn = hints,
            toggleLabel = if (hints) SessionCopy.coachOn else SessionCopy.coachOff,
            stage = coachStage(g),
            tip = coachTip(g),
        )

        return TableRenderState(
            version = ++version,
            hand = g.hand,
            handNumber = SessionCopy.handNumber(g.hand),
            handHeading = SessionCopy.handHeading(g.hand),
            playerCount = count,
            tableTag = SessionCopy.tableTag(count),
            tableSize = SessionCopy.tableSize(count),
            hasFullPlayerNames = g.players.drop(1).any { it.botProfile in setOf("viktor", "jungleman", "dwan") },
            phase = g.phase,
            street = g.street,
            streetLabel = if (done) SessionCopy.streetDone else SessionCopy.street(g.street) ?: SessionCopy.streetReady,
            dealer = g.dealer,
            replayAttempt = g.replayAttempt,
            replayBadge = if (g.replayAttempt > 0) SessionCopy.replayBadge(g.replayAttempt) else null,
            replayNote = if (g.replayAttempt > 0) SessionCopy.replayNote else null,
            pot = if (done) g.potAtShowdown else potSize(g),
            potText = formatChips(if (done) g.potAtShowdown else potSize(g)),
            potPulse = anim.boardChanged,
            potButtonLabel = if (details.pots.size > 1) SessionCopy.potButtonMulti(details.pots.size - 1) else SessionCopy.potButtonSingle,
            potButtonA11y = SessionCopy.potDetailsA11y,
            board = board,
            boardCaption = caption,
            practiceRunout = g.practiceBoard != null,
            seats = seats,
            hero = heroState,
            session = session,
            activity = activity,
            actions = actions,
            coach = coach,
            showdown = showdownState,
            potDetails = potDetails(details, done),
            opponents = opponentsSummary(g, pendingBotSettings),
            opponentsDialog = opponentsEditor.state(g, requestedCount),
            review = review.state(),
            settings = SettingsState(
                requestedSeatCount = requestedCount,
                seatCountOptions = (MIN_PLAYERS..MAX_PLAYERS).map { OptionItem(it, SessionCopy.playerCountOption(it)) },
                tableChangeNote = if (requestedCount != count) SessionCopy.tableChangeNote(requestedCount) else null,
                difficulty = g.difficulty,
                difficultyOptions = Difficulty.entries.map { OptionItem(it, SessionCopy.difficultyLabels.getValue(it)) },
                hints = hints,
                sound = sound,
                soundA11y = if (sound) SessionCopy.soundOffA11y else SessionCopy.soundOnA11y,
                soundTitle = if (sound) SessionCopy.soundStateOn else SessionCopy.soundStateOff,
                emotionOptions = EmotionMode.entries.map { OptionItem(it, it.label) },
            ),
            finishing = finishing,
            backgrounded = backgrounded,
        )
    }

    private fun seatState(p: Player, anim: Animation): SeatState {
        val g = game
        val winner = g.winners.firstOrNull { it.id == p.id }
        val reveal = isSeatHandVisible(p)
        val rank = if (reveal && !p.folded && g.board.size == 5) evaluate(p.hole + g.board) else null
        val (x, y) = SEAT_LAYOUTS.getValue(g.players.size)[p.id - 1]
        val profile = getBotProfile(p.botProfile)
        val mood = if (g.emotionMode == EmotionMode.OFF) MoodKind.STEADY else p.botMood.kind
        val avatarTitle = SessionCopy.avatarTitle(p.name, profile.short, mood.label)
        val done = g.phase == Phase.DONE
        return SeatState(
            id = p.id,
            name = p.name,
            layoutX = x,
            layoutY = y,
            position = position(p.id),
            folded = p.folded,
            isActor = g.actor == p.id,
            isWinner = winner != null,
            revealed = reveal,
            cards = if (reveal) p.hole.map { c -> CardFace(c, best = rank != null && rank.cards.any { it.key == c.key }) } else emptyList(),
            cardBacks = if (reveal) 0 else p.hole.size,
            dealAnimation = !reveal && anim.newHand,
            cardBackDelaysMs = if (reveal) emptyList() else p.hole.indices.map { i -> p.id * 65 + i * 140 },
            cardBackA11y = SessionCopy.cardBackA11y,
            badge = if (rank != null || winner != null) {
                RankBadge(
                    text = rank?.label ?: SessionCopy.winnerFallback,
                    isWinner = winner != null,
                    a11y = winner?.let { SessionCopy.winnerA11y(p.name, it.amount) },
                    title = winner?.let { SessionCopy.winnerTitle(it.label, it.amount) },
                )
            } else {
                null
            },
            avatar = SessionCopy.avatarLetters[p.id],
            avatarTitle = avatarTitle,
            profileId = profile.id,
            styleShort = profile.short,
            styleTitle = SessionCopy.styleTitle(profile.name, profile.tag),
            styleA11y = SessionCopy.styleA11y(p.name, profile.name),
            mood = mood,
            moodLabel = mood.label,
            stack = p.stack,
            stackText = formatChips(p.stack),
            peek = if (done) {
                PeekToggle(reveal, if (reveal) SessionCopy.peekHide else SessionCopy.peekShow, SessionCopy.peekA11y(reveal, p.name))
            } else {
                null
            },
            action = seatActionChip(g, p),
            actionA11y = SessionCopy.seatActionA11y(p.name),
        )
    }

    private fun actionPanel(legal: com.august.noirpoker.core.LegalActions, done: Boolean): ActionPanelState {
        val g = game
        val hero = g.players[0]
        val decisionText = when {
            legal.enabled -> if (legal.canCheck) {
                SessionCopy.decisionCanCheck
            } else {
                SessionCopy.decisionToCall(legal.callAmount) + if (legal.raiseReopened) "" else SessionCopy.decisionNotReopened
            }
            done -> ""
            g.phase == Phase.BETWEEN -> if (g.revealed) {
                if (g.board.size == 5) SessionCopy.decisionShowdownSettling else SessionCopy.decisionAllInRunout
            } else {
                SessionCopy.decisionDealingNext
            }
            else -> {
                val name = g.players.getOrNull(g.actor)?.name ?: SessionCopy.opponentFallback
                if (hero.folded) SessionCopy.decisionObserve(name) else SessionCopy.decisionWait(name)
            }
        }
        val callLabel = when {
            legal.enabled && legal.canCheck -> SessionCopy.check
            legal.enabled && legal.callAmount < legal.toCall -> SessionCopy.callAllIn
            else -> SessionCopy.call
        }
        val callAmount = if (legal.enabled && !legal.canCheck) legal.callAmount else null
        val caption = raiseCaption(LabelStep(street = g.street, history = g.history.toList(), currentBet = g.currentBet, legal = legal), bet)
        val canRaise = legal.enabled && legal.canRaise
        val canFinish = canFinishHand()
        return ActionPanelState(
            decisionStripVisible = !done,
            decisionText = decisionText,
            controlsVisible = !done && !hero.folded,
            foldLabel = SessionCopy.fold,
            foldEnabled = legal.enabled,
            callEnabled = legal.enabled,
            callLabel = callLabel,
            callAmount = callAmount,
            callAmountText = callAmount?.let { formatChips(it) },
            callA11y = if (callAmount == null) callLabel else "$callLabel ${formatChips(callAmount)}",
            raiseEnabled = canRaise,
            raiseCaption = caption,
            bet = bet,
            betText = formatChips(bet),
            raiseA11y = "$caption ${formatChips(bet)}",
            sliderLabel = SessionCopy.betSliderLabel,
            sliderA11y = SessionCopy.betSliderA11y,
            sliderMin = if (legal.enabled) legal.minRaiseTo else null,
            sliderMax = if (legal.enabled) legal.maxRaiseTo else null,
            presets = BetPreset.entries.map { PresetState(it, SessionCopy.presetLabels.getValue(it), presetAmount(it), canRaise) },
            nextHandVisible = done,
            nextHandLabel = if (hero.stack == 0) SessionCopy.nextHandRebuy else SessionCopy.nextHand,
            finishHandVisible = canFinish || finishing,
            finishHandEnabled = !finishing && canFinish,
            finishHandLabel = if (finishing) SessionCopy.finishHandBusy else SessionCopy.finishHand,
            finishHandTitle = SessionCopy.finishHandTitle,
            replayVisible = canRestartHand(g),
            replayLabel = SessionCopy.replayHand,
            replayTitle = SessionCopy.replayHandTitle,
            reviewVisible = review.state().buttonVisible,
            reviewLabel = SessionCopy.reviewHand,
        )
    }

    private fun potDetails(details: PotSet, done: Boolean): PotDetailsState {
        val g = game
        val hero = g.players[0]
        fun eligibilityLabel(eligible: List<Int>) = when {
            0 in eligible -> SessionCopy.potEligHero
            done || hero.folded -> SessionCopy.potEligNotIn
            hero.allin -> SessionCopy.potEligOverAllIn
            else -> SessionCopy.potEligNotYet
        }
        val pots = details.pots.map { pot ->
            val participants = pot.eligible.joinToString(SessionCopy.listJoiner) { g.players[it].name }
            val split = pot.awards.size > 1
            val label = eligibilityLabel(pot.eligible)
            PotCardState(
                index = pot.index,
                label = pot.label,
                amount = pot.amount,
                amountText = formatChips(pot.amount),
                settled = done,
                eligibilityLabel = label,
                heroEligible = 0 in pot.eligible,
                contributions = pot.contributions.map { c ->
                    val p = g.players[c.id]
                    PotContributionRow(
                        c.id,
                        p.name + when {
                            p.folded -> SessionCopy.potContribFolded
                            p.allin -> SessionCopy.potContribAllIn
                            else -> ""
                        },
                        c.amount,
                        formatChips(c.amount),
                    )
                },
                splitTotalText = if (done && split) SessionCopy.potSplitTotal(pot.amount) else null,
                awards = if (done) {
                    pot.awards.map { a ->
                        val name = g.players[a.id].name
                        PotAwardRow(a.id, name, if (split) name else SessionCopy.potAwardWinner(name), a.label, SessionCopy.potAwardAmount(a.amount), SessionCopy.chips)
                    }
                } else {
                    emptyList()
                },
                distributionSummary = SessionCopy.potDistributionSummary,
                distributionEligibility = SessionCopy.potDistributionEligibility(label, participants),
                contributionsHeading = SessionCopy.potContribHeading,
                oddChipNote = if (done && split) SessionCopy.potOddChipNote else null,
                expanded = pot.index in potExpanded,
                unit = SessionCopy.chips,
                playerCountText = SessionCopy.potLiveCount(pot.eligible.size),
                participantsText = SessionCopy.potLiveParticipants(participants),
                contributionsSummary = SessionCopy.potContribSummary,
            )
        }
        val refunds = details.refunds.map { r ->
            val name = g.players[r.id].name
            RefundRowState(
                playerId = r.id,
                amount = r.amount,
                amountText = formatChips(r.amount),
                text = if (done) SessionCopy.refundDone(name) else SessionCopy.refundLive(name),
                a11y = if (done) SessionCopy.refundDoneA11y(name, r.amount) else null,
                returned = done,
            )
        }
        return PotDetailsState(
            open = potDialogOpen,
            settled = done,
            title = if (done) SessionCopy.potTitleSettled else SessionCopy.potTitleLive,
            note = if (done) null else SessionCopy.potNoteLive,
            pots = pots,
            refunds = refunds,
        )
    }

    // ---- Diagnostics ------------------------------------------------------------------

    /** The reference `publicState()` plus `totalLogs` and `wealth`. Never exposes hidden cards or traces. */
    fun publicSnapshot(): PublicTableSnapshot {
        val g = game
        val details = currentPots(g)
        val done = g.phase == Phase.DONE
        return PublicTableSnapshot(
            playerCount = g.players.size,
            emotionMode = g.emotionMode.id,
            canContinue = canFinishHand(),
            replayAttempt = g.replayAttempt,
            canRestart = canRestartHand(g),
            hand = g.hand,
            dealer = g.players[g.dealer].name,
            seatOrder = "clockwise",
            street = SessionCopy.street(g.street),
            phase = g.phase.id,
            actor = g.players.getOrNull(g.actor)?.name,
            pot = if (done) g.potAtShowdown else potSize(g),
            pots = details.pots.map { p ->
                PublicPot(p.label, p.amount, p.eligible.map { g.players[it].name }, p.awards.map { PublicAward(g.players[it.id].name, it.amount, it.label) })
            },
            uncalled = details.refunds.map { PublicRefund(g.players[it.id].name, it.amount, done) },
            board = (g.practiceBoard ?: g.board).map { it.toString() },
            settlementBoard = g.board.map { it.toString() },
            practiceRunout = g.practiceBoard != null,
            hole = g.players[0].hole.map { it.toString() },
            stack = g.players[0].stack,
            legal = legalActions(g, 0),
            players = g.players.map { p ->
                PublicPlayer(
                    id = p.id,
                    name = p.name,
                    position = seatPosition(g, p.id),
                    stack = p.stack,
                    folded = p.folded,
                    allin = p.allin,
                    bet = p.bet,
                    action = p.action,
                    lastAction = p.lastAction,
                    botProfile = if (p.id != 0) p.botProfile else null,
                    mood = if (p.id != 0) (if (g.emotionMode == EmotionMode.OFF) MoodKind.STEADY else p.botMood.kind).id else null,
                    botStats = if (p.id != 0) p.botStats.copy() else null,
                    cards = if (isSeatHandVisible(p)) p.hole.map { it.toString() } else null,
                )
            },
            result = g.result.ifEmpty { null },
            totalLogs = g.logs.size,
            wealth = g.players.sumOf { it.stack } + if (done) 0 else potSize(g),
        )
    }

    /**
     * Debug and UI-test hooks mirroring the reference's `window.qa` fixtures. Not
     * for production code paths: the apps should only reach them from debug or
     * instrumentation builds.
     */
    val testHooks: TestHooks = TestHooks()

    inner class TestHooks {
        val game: Game get() = this@TableSession.game

        /**
         * `fixtureGame(count, heroFirst)`: cancels all work, builds a fresh game
         * with the saved opponent settings, then runs [setup] (usually a
         * `startHand` plus scripted actions) and renders without scheduling bots.
         * With [heroFirst] the hero is UTG after `startHand`.
         */
        fun fixture(count: Int = 6, heroFirst: Boolean = false, setup: (Game) -> Unit = {}): Game {
            seatHandVisibility.clear()
            cancelTimer()
            cancelFinishLoop()
            botWait = null
            finishWaiting = null
            finishing = false
            resetShowdown()
            review.reset()
            epoch++
            viewToken++
            val difficulty = this@TableSession.game.difficulty
            this@TableSession.game = newGame(count)
            this@TableSession.game.difficulty = difficulty
            if (heroFirst) this@TableSession.game.dealer = count - 4
            applyBotSettings(this@TableSession.game, pendingBotSettings)
            requestedCount = count
            lastHand = 0
            lastBoard = 0
            setup(this@TableSession.game)
            render()
            return this@TableSession.game
        }

        /** Mutates the live game directly (like the fixtures), then renders without scheduling. */
        fun mutate(block: (Game) -> Unit) {
            block(this@TableSession.game)
            render()
        }

        /** `qa.stop()`: freezes bots. */
        fun stop() {
            cancelTimer()
            botWait = null
        }

        /** `qa.thinking()`. */
        fun thinking(): BotWaitInfo? = botWait?.let {
            BotWaitInfo(this@TableSession.game.actor, it.plan.delayMs, it.startedAt, it.deadline)
        }

        /** `qa.resumeBots()`: schedules again, reusing a current plan. */
        fun resumeBots(): BotWaitInfo? {
            schedule()
            return thinking()
        }

        /** `qa.timingRecords()`: the private bot execution records. */
        fun timingRecords(): List<BotDecisionRecord> = this@TableSession.game.botDecisions.toList()

        val hasPendingTimer: Boolean get() = timer != null || finishTimer != null
    }
}
