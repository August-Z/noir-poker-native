// The platform-neutral table session: a port of `table-controller.js` (with
// the settings logic of `opponents-controller.js` and `preferences.js`, the
// showdown data of `showdown.js` and the scheduling of `review-controller.js`).
// Mirrors the Kotlin `com.august.noirpoker.core.session.TableSession`.

/// Reference seat centers per table size, as `(left%, top%)` for seats 1..count-1.
public let SEAT_LAYOUTS: [Int: [(x: Double, y: Double)]] = [
    5: [(15, 59), (23, 0), (77, 0), (85, 59)],
    6: [(14, 60), (17, 14), (50, 0), (83, 14), (86, 60)],
    7: [(14, 63), (11.5, 27), (35, 0), (65, 0), (88.5, 27), (86, 63)],
    8: [(14, 68), (11.5, 36), (23, 6), (50, 0), (77, 6), (88.5, 36), (86, 68)],
    9: [(14, 72), (13, 45), (16, 18), (36, 0), (64, 0), (84, 18), (87, 45), (86, 72)],
]

/// Engine calls the session makes only in states where the engine cannot
/// throw. A thrown error here is a broken invariant, not a user error.
@discardableResult
private func engine<T>(_ body: () throws -> T) -> T {
    do {
        return try body()
    } catch {
        preconditionFailure("Table session invariant violated: \(error)")
    }
}

/// The table session. It owns the live `Game` and all session state, and
/// publishes an immutable `TableRenderState` after every change. It imports no
/// UI framework; the SwiftUI observable model wraps it.
///
/// Threading: single-threaded. Call every command, and deliver every
/// `SessionScheduler` and `ReviewSink` callback, on the same (main) thread.
///
/// Randomness: one `random` stream feeds the shuffle, every bot decision and
/// every thinking time, in the reference's order (`Math.random`).
///
/// Cancellation: `epoch` is the reference's cancellation token. It increments
/// on Next Hand, Replay Hand, Start New Session, Finish Hand and moving to the
/// background; every scheduled callback captures it and does nothing once it
/// changed, and the timer handle is cancelled as well.
public final class TableSession {
    public static let defaultBet = 150
    public static let streetDelayMs = 1000
    public static let showdownDelayMs = 850

    /// A planned bot decision waiting for its `deadline`. `pausedMs` is the
    /// time the app spent in the background during the wait, so `waitedMs`
    /// counts only foreground time.
    private final class BotWait {
        let plan: BotPlan
        let startedAt: Int
        let deadline: Int
        let pausedMs: Int
        init(plan: BotPlan, startedAt: Int, deadline: Int, pausedMs: Int = 0) {
            self.plan = plan
            self.startedAt = startedAt
            self.deadline = deadline
            self.pausedMs = pausedMs
        }

        func waitedMs(_ now: Int) -> Int { now - startedAt - pausedMs }
    }

    private struct Animation {
        let newHand: Bool
        let lastBoard: Int
        let boardChanged: Bool
    }

    private let scheduler: SessionScheduler
    private let preferences: PreferencesStore
    private let random: RandomSource

    private var requestedCount: Int
    fileprivate(set) var game: Game
    private var timer: SessionCancellable?
    private var finishTimer: SessionCancellable?
    private var botWait: BotWait?
    private var finishWaiting: BotWait?

    /// Cancellation token for scheduled work.
    public private(set) var epoch = 0

    /// The reference's `epoch` as used for the review and showdown keys. It moves
    /// with `epoch` except on background transitions, so returning to the app
    /// does not rebuild a finished review.
    public private(set) var viewToken = 0

    private var lastBoard = 0
    private var lastHand = 0
    private var bet = TableSession.defaultBet
    private var finishing = false
    private var hints: Bool
    private var sound: Bool
    private var pendingBotSettings: BotSettings
    private var seatHandVisibility: [Int: Bool] = [:]
    private var backgrounded = false
    private var backgroundedAt = 0
    private var potDialogOpen = false
    private var potExpanded: Set<Int> = []
    private let opponentsEditor = OpponentSettingsEditor()
    private let review: HandReviewController

    private var showdownKey: String?
    private var showdownState: ShowdownState?

    private var pendingAnimation: Animation?
    private var version = 0
    private var rendering = false
    private var dirty = false
    private var listeners: [(id: Int, body: (TableRenderState) -> Void)] = []
    private var nextListenerId = 0

    /// Receives sounds (only while sound is on), chip flights and focus effects.
    public var effectListener: ((SessionEffect) -> Void)?

    /// The latest published state.
    public private(set) var state: TableRenderState!

    public init(scheduler: SessionScheduler, storage: KeyValueStorage,
                random: RandomSource = SystemRandom.shared, reviewRunner: ReviewRunner? = nil) {
        self.scheduler = scheduler
        self.random = random
        preferences = PreferencesStore(storage)
        let table = preferences.loadTable()
        requestedCount = table.playerCount
        game = engine { try newGame(table.playerCount) }
        game.difficulty = table.difficulty
        sound = preferences.loadSound()
        hints = preferences.loadHints()
        pendingBotSettings = preferences.loadBotSettings()
        review = HandReviewController(runner: reviewRunner)
        review.onChange = { [weak self] in self?.render() }
        render()
    }

    // MARK: Observation

    /// Calls `listener` at once with the current state, then after every change.
    @discardableResult
    public func addListener(_ listener: @escaping (TableRenderState) -> Void) -> SessionCancellable {
        let id = nextListenerId
        nextListenerId += 1
        listeners.append((id, listener))
        listener(state)
        return CancelHandle { [weak self] in self?.listeners.removeAll { $0.id == id } }
    }

    /// Deals the first hand (the reference deals hand 1 at startup). Does nothing afterwards.
    public func start() {
        if game.hand == 0 && game.phase == .idle { nextHand() }
    }

    // MARK: Hero actions

    /// `heroAction`: returns false when it is not the hero's turn or the amount is illegal.
    @discardableResult
    public func heroAction(_ action: PokerAction, amount: Int? = nil) -> Bool {
        let legal = legalActions(game, 0)
        guard legal.enabled else { return false }
        do {
            try act(game, 0, action, amount)
        } catch {
            return false
        }
        if action == .raise || (action == .call && legal.toCall > 0) {
            emit(.chipFlight(seat: 0))
            playSound(.chip)
        }
        if game.phase == .done { playSound(.win) }
        render()
        schedule()
        return true
    }

    @discardableResult public func fold() -> Bool { heroAction(.fold) }

    /// The Call / Check button: the engine turns a call with nothing owed into a check.
    @discardableResult public func callOrCheck() -> Bool { heroAction(.call) }

    /// The Raise button with the selected bet (or an explicit raise-to total).
    @discardableResult public func raise(_ amount: Int? = nil) -> Bool { heroAction(.raise, amount: amount ?? bet) }

    /// The current raise-to selection.
    public var currentBet: Int { bet }

    /// Slider input: snaps to multiples of 25 (round half up) within the legal
    /// range, except that the exact maximum (all-in) is kept.
    public func setBet(_ value: Int) {
        let legal = legalActions(game, 0)
        guard legal.enabled else { return }
        var b = value == legal.maxRaiseTo ? value : max(legal.minRaiseTo, Int(jsRound(Double(value) / 25)) * 25)
        b = min(legal.maxRaiseTo, b)
        bet = b
        render()
    }

    /// Accessibility increment / decrement: moves the bet by 25 per step, clamped to the legal range.
    public func nudgeBet(_ steps: Int) {
        let legal = legalActions(game, 0)
        guard legal.enabled, legal.canRaise else { return }
        bet = min(legal.maxRaiseTo, max(legal.minRaiseTo, bet + steps * 25))
        render()
    }

    /// The amount a preset would select, or nil when raising is unavailable.
    public func presetAmount(_ preset: BetPreset) -> Int? {
        let legal = legalActions(game, 0)
        guard legal.canRaise else { return nil }
        let raw: Int
        switch preset {
        case .allIn: raw = legal.maxRaiseTo
        case .min: raw = legal.minRaiseTo
        case .halfPot, .pot:
            let fraction = preset == .halfPot ? 0.5 : 1.0
            raw = game.currentBet + max(game.minRaise, Int(jsRound(Double(potSize(game)) * fraction / 25)) * 25)
        }
        return min(legal.maxRaiseTo, max(legal.minRaiseTo, raw))
    }

    /// Min / ½ Pot / Pot / All-In.
    @discardableResult
    public func preset(_ preset: BetPreset) -> Bool {
        guard let amount = presetAmount(preset) else { return false }
        bet = amount
        render()
        return true
    }

    // MARK: Hand flow

    /// Next Hand (also Rebuy and Keep Practicing). Applies a pending seat count
    /// and opponent styles. Returns false while a hand is in progress.
    @discardableResult
    public func nextHand() -> Bool {
        guard game.phase == .idle || game.phase == .done else { return false }
        // Unlike the reference, the previous hand's review job does not outlive
        // the hand: cancel it and drop any late result. Its settled input stays
        // until the new hand settles, but it is no longer reachable (the review
        // button is hidden during the new hand). An open dialog is closed first,
        // while the old view token is still current.
        if review.state().dialogOpen { review.close() }
        review.pause()
        botWait = nil
        seatHandVisibility.removeAll()
        finishing = false
        finishWaiting = nil
        cancelTimer()
        cancelFinishLoop()
        resetShowdown()
        epoch += 1
        viewToken += 1
        lastBoard = 0
        closePotDialog()
        if requestedCount != game.players.count {
            let difficulty = game.difficulty
            game = engine { try newGame(requestedCount) }
            game.difficulty = difficulty
            review.reset()
            lastHand = 0
        }
        engine { try applyBotSettings(game, pendingBotSettings) }
        engine { try startHand(game, random: random) }
        let legal = legalActions(game, 0)
        bet = legal.enabled ? min(legal.maxRaiseTo, max(legal.minRaiseTo, Self.defaultBet)) : Self.defaultBet
        render()
        playSound(.deal)
        schedule()
        return true
    }

    /// Replay Hand: restores the post-blind state of this hand and reverses its settlement once.
    @discardableResult
    public func replayHand() -> Bool {
        guard canRestartHand(game) else { return false }
        botWait = nil
        seatHandVisibility.removeAll()
        finishing = false
        finishWaiting = nil
        cancelTimer()
        cancelFinishLoop()
        resetShowdown()
        review.rollback(game, token: viewToken)
        epoch += 1
        viewToken += 1
        closePotDialog()
        emit(.cancelChipFlights)
        engine { try restartHand(game) }
        lastHand = 0
        lastBoard = 0
        bet = Self.defaultBet
        render()
        playSound(.deal)
        schedule()
        return true
    }

    /// Start New Session (after the confirmation): a new table with the
    /// requested size, the current difficulty and the saved styles.
    public func startNewSession() {
        review.reset()
        let difficulty = game.difficulty
        cancelTimer()
        cancelFinishLoop()
        game = engine { try newGame(requestedCount) }
        game.difficulty = difficulty
        lastHand = 0
        nextHand()
    }

    /// Whether Finish Hand is available (`canFastFinish`).
    public func canFinishHand() -> Bool {
        let hero = game.players[0]
        return hero.folded && !finishing && !backgrounded &&
            (game.phase != .done || (game.board.count < 5 && game.practiceBoard == nil))
    }

    /// Finish Hand (`continueDeal`): executes the pending planned decision at
    /// once, plans and executes every later bot turn immediately, deals streets
    /// without delay, and adds a practice runout after a fold-win. Each step
    /// runs on its own zero-delay tick so it can be cancelled.
    @discardableResult
    public func finishHand() -> Bool {
        guard canFinishHand() else { return false }
        cancelTimer()
        finishWaiting = botWait
        botWait = nil
        epoch += 1
        viewToken += 1
        let ticket = epoch
        finishing = true
        render()
        if game.phase == .done {
            finishComplete(ticket)
        } else {
            finishTimer = scheduler.schedule(delayMs: 0) { [weak self] in self?.finishStep(ticket) }
        }
        return true
    }

    private func finishStep(_ ticket: Int) {
        finishTimer = nil
        guard ticket == epoch else { return }
        if game.phase == .between {
            engine { try advanceStreet(game) }
        } else if let waiting = finishWaiting, isBotTurnCurrent(game, waiting.plan) {
            engine { try executeBotTurn(game, waiting.plan, expedited: true, waitedMs: waiting.waitedMs(scheduler.nowMs)) }
        } else {
            engine { try playBotTurn(game, random: random, timingRandom: random) }
        }
        if game.phase == .between { render() }
        guard ticket == epoch else { return }
        if game.phase != .done {
            finishTimer = scheduler.schedule(delayMs: 0) { [weak self] in self?.finishStep(ticket) }
            return
        }
        finishComplete(ticket)
    }

    private func finishComplete(_ ticket: Int) {
        if ticket == epoch { engine { try completeBoardForPractice(game) } }
        finishSettle(ticket)
    }

    private func finishSettle(_ ticket: Int) {
        guard ticket == epoch else { return }
        finishing = false
        finishWaiting = nil
        render()
        if game.phase == .done { playSound(.win) }
        schedule()
    }

    /// The post-settlement eye toggle: shows or hides one opponent's hole cards (display only).
    @discardableResult
    public func toggleReveal(_ seat: Int) -> Bool {
        guard game.phase == .done, seat != 0, game.players.indices.contains(seat) else { return false }
        let visible = !isSeatHandVisible(game.players[seat])
        seatHandVisibility[seat] = visible
        render()
        emit(.revealToggled(seat: seat, visible: visible))
        return true
    }

    // MARK: Settings

    /// Table size 5–9: saved now, applied by the next Next Hand or Start New Session.
    @discardableResult
    public func setSeatCount(_ count: Int) -> Bool {
        guard (MIN_PLAYERS...MAX_PLAYERS).contains(count) else { return false }
        requestedCount = count
        preferences.saveTable(TablePreferences(playerCount: requestedCount, difficulty: game.difficulty))
        render()
        return true
    }

    /// Opponent difficulty takes effect immediately; a thinking bot re-plans under it.
    public func setDifficulty(_ difficulty: Difficulty) {
        game.difficulty = difficulty
        preferences.saveTable(TablePreferences(playerCount: requestedCount, difficulty: game.difficulty))
        if game.phase == .playing && game.actor != 0 && !finishing { schedule() }
        render()
    }

    public func toggleHints() {
        hints.toggle()
        preferences.saveHints(hints)
        render()
    }

    public func toggleSound() {
        sound.toggle()
        preferences.saveSound(sound)
        render()
        if sound { playSound(.deal) }
    }

    /// The saved opponent settings that the next deal applies.
    public var savedBotSettings: BotSettings { pendingBotSettings }

    public func openOpponentSettings() {
        opponentsEditor.open(pendingBotSettings)
        render()
    }

    public func previewProfile(_ id: String) {
        opponentsEditor.previewProfile(id)
        render()
    }

    public func assignSeatStyle(_ seat: Int, _ profile: String) {
        opponentsEditor.assignSeat(seat, profile)
        render()
    }

    public func setEmotionMode(_ mode: EmotionMode) {
        opponentsEditor.setEmotionMode(mode)
        render()
    }

    public func mixLineup() {
        opponentsEditor.mixLineup()
        render()
    }

    /// Save (applies next hand): persists the sanitized draft and closes the dialog.
    @discardableResult
    public func saveOpponentSettings() -> Bool {
        guard let settings = opponentsEditor.save() else { return false }
        preferences.saveBotSettings(settings)
        pendingBotSettings = settings
        render()
        return true
    }

    /// Close without saving: the next open starts again from the saved settings.
    public func discardOpponentSettings() {
        opponentsEditor.discard()
        render()
    }

    // MARK: Pot details and review

    public func openPotDetails() {
        potDialogOpen = true
        render()
    }

    public func closePotDetails() {
        closePotDialog()
        render()
    }

    /// Expands or collapses a settled pot's distribution details (kept by pot index).
    public func togglePotDistribution(_ index: Int) {
        if potExpanded.contains(index) { potExpanded.remove(index) } else { potExpanded.insert(index) }
        render()
    }

    private func closePotDialog() {
        potDialogOpen = false
        potExpanded.removeAll()
    }

    public func openReview() { review.open() }
    public func closeReview() { review.close() }
    public func retryReview() { review.retry() }
    public func selectReviewStep(_ index: Int) { review.select(index) }
    public func previousReviewStep() { review.previous() }
    public func nextReviewStep() { review.next() }
    public func setReviewPerspective(_ perspective: HandReviewPerspective) { review.setPerspective(perspective) }
    public func setOpponentReviewFilter(_ seat: Int?) { review.setOpponentFilter(seat) }
    public func selectOpponentReviewRecord(_ index: Int) { review.selectOpponent(index) }

    // MARK: Lifecycle

    /// The app moved to the background: cancel the timer, stop a running Finish
    /// Hand loop and the review job. A thinking bot keeps its plan (no new
    /// random draws); on return it waits only for the rest of its delay, and
    /// the time spent in the background is excluded from its recorded
    /// `waitedMs`. A cancelled Finish Hand is not resumed: the player taps it
    /// again.
    public func onBackground() {
        guard !backgrounded else { return }
        backgrounded = true
        backgroundedAt = scheduler.nowMs
        cancelTimer()
        cancelFinishLoop()
        epoch += 1
        if finishing {
            finishing = false
            if let waiting = finishWaiting, isBotTurnCurrent(game, waiting.plan) { botWait = waiting }
        }
        finishWaiting = nil
        review.pause()
        render()
    }

    public func onForeground() {
        guard backgrounded else { return }
        backgrounded = false
        if let waiting = botWait, isBotTurnCurrent(game, waiting.plan) {
            let away = max(0, scheduler.nowMs - backgroundedAt)
            botWait = BotWait(
                plan: waiting.plan,
                startedAt: waiting.startedAt,
                deadline: waiting.deadline + away,
                pausedMs: waiting.pausedMs + away
            )
        } else {
            botWait = nil
        }
        review.resume()
        render()
        schedule()
    }

    // MARK: Scheduling

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    private func cancelFinishLoop() {
        finishTimer?.cancel()
        finishTimer = nil
    }

    /// The reference `schedule()`: the single pending street advance or bot action.
    private func schedule() {
        cancelTimer()
        let ticket = epoch
        if backgrounded || game.phase == .idle { return }
        if game.phase == .done || finishing {
            botWait = nil
            return
        }
        if game.phase == .between {
            botWait = nil
            let delay = game.board.count == 5 ? Self.showdownDelayMs : Self.streetDelayMs
            timer = scheduler.schedule(delayMs: delay) { [weak self] in
                guard let self, ticket == self.epoch, self.game.phase == .between, !self.finishing else { return }
                self.timer = nil
                engine { try advanceStreet(self.game) }
                self.playSound(self.game.phase == .done ? .win : .deal)
                self.render()
                self.schedule()
            }
        } else if game.actor != 0 {
            if botWait == nil || !isBotTurnCurrent(game, botWait!.plan) {
                let plan = engine { try planBotTurn(game, random: random, timingRandom: random) }
                let startedAt = scheduler.nowMs
                botWait = BotWait(plan: plan, startedAt: startedAt, deadline: startedAt + plan.delayMs)
            }
            let waiting = botWait!
            timer = scheduler.schedule(delayMs: max(0, waiting.deadline - scheduler.nowMs)) { [weak self] in
                guard let self, ticket == self.epoch, self.botWait === waiting, !self.finishing else { return }
                self.timer = nil
                guard isBotTurnCurrent(self.game, waiting.plan) else {
                    self.botWait = nil
                    self.schedule()
                    return
                }
                self.botWait = nil
                let id = self.game.actor
                let d = engine { try executeBotTurn(self.game, waiting.plan, waitedMs: waiting.waitedMs(self.scheduler.nowMs)) }
                if d.action != .fold && d.action != .check {
                    self.emit(.chipFlight(seat: id))
                    self.playSound(.chip)
                }
                if self.game.phase == .done { self.playSound(.win) }
                self.render()
                self.schedule()
            }
        } else {
            botWait = nil
        }
    }

    // MARK: Effects

    private func emit(_ effect: SessionEffect) { effectListener?(effect) }

    private func playSound(_ kind: SoundKind) {
        if sound { emit(.sound(kind)) }
    }

    // MARK: Rendering

    private func isSeatHandVisible(_ p: Player) -> Bool {
        if game.phase == .done, let override = seatHandVisibility[p.id] { return override }
        return (game.showdown || game.revealed) && !p.folded
    }

    private func resetShowdown() {
        showdownKey = nil
        showdownState = nil
    }

    private func updateShowdown() {
        let g = game
        let nextKey = "\(viewToken):\(g.hand)"
        guard g.phase == .done, g.showdown else {
            resetShowdown()
            return
        }
        if showdownKey == nextKey { return }
        showdownKey = nextKey
        let scenes = showdownScenes(g)
        let names = ActivityFormatter(g.players)
        showdownState = scenes.isEmpty ? nil : ShowdownState(
            key: nextKey,
            context: SessionCopy.sdContext(scenes.count, multiPot: g.pots.count > 1),
            scenes: scenes.map { s in
                let won = !s.awards.isEmpty
                return ShowdownSceneState(
                    scene: s,
                    nameSegments: names.format(s.name),
                    isWinner: won,
                    statusText: won ? SessionCopy.sdWon(s.amount) : SessionCopy.sdNoPot,
                    footerText: won
                        ? s.awards.map { SessionCopy.sdAwardItem($0.pot, split: $0.split, $0.amount) }.joined(separator: " · ")
                        : SessionCopy.sdBestFive,
                    a11y: SessionCopy.sdPlayerA11y(s.name, s.label)
                )
            }
        )
    }

    /// Recomputes and publishes the state. Mutates only the bet clamp, review input and showdown key.
    private func render() {
        if rendering {
            dirty = true
            return
        }
        rendering = true
        defer {
            rendering = false
            pendingAnimation = nil
        }
        repeat {
            dirty = false
            let displayBoardSize = (game.practiceBoard ?? game.board).count
            let animation = pendingAnimation ?? Animation(newHand: game.hand != lastHand, lastBoard: lastBoard,
                                                          boardChanged: displayBoardSize > lastBoard)
            pendingAnimation = animation
            let legal = legalActions(game, 0)
            if legal.enabled { bet = min(legal.maxRaiseTo, max(legal.minRaiseTo, bet)) }
            review.update(game, token: viewToken)
            updateShowdown()
            if dirty { continue }
            state = buildState(animation)
            lastHand = game.hand
            lastBoard = displayBoardSize
        } while dirty
        let published = state!
        for l in listeners { l.body(published) }
    }

    private func position(_ id: Int) -> PositionBadge {
        let code = seatPosition(game, id)
        return PositionBadge(code: code, name: SessionCopy.positionNames[code] ?? code)
    }

    private func buildState(_ anim: Animation) -> TableRenderState {
        let g = game
        let count = g.players.count
        let hero = g.players[0]
        let done = g.phase == .done
        let displayBoard = g.practiceBoard ?? g.board
        let heroBest: Set<String> = g.showdown && !hero.folded ? Set(evaluate(hero.hole + g.board).cards.map(\.key)) : []
        let details = currentPots(g)
        let legal = legalActions(g, 0)

        let board = (0..<5).map { i -> BoardSlot in
            let c: Card? = i < displayBoard.count ? displayBoard[i] : nil
            return BoardSlot(
                index: i,
                card: c.map { CardFace($0, best: heroBest.contains($0.key), animate: i >= anim.lastBoard && anim.boardChanged,
                                       delayMs: (i - anim.lastBoard) * 140) },
                placeholderGlyph: SessionCopy.boardSlotGlyphs[i],
                a11y: c?.description ?? SessionCopy.undealtCard
            )
        }

        var caption: String
        if g.practiceBoard != nil { caption = SessionCopy.captionPractice }
        else if done && g.showdown { caption = hero.folded ? SessionCopy.captionShowdownFolded : SessionCopy.captionShowdownHero }
        else if g.street == 0 { caption = SessionCopy.captionPreflop }
        else if g.street == 1 { caption = SessionCopy.captionFlop }
        else if g.street == 2 { caption = SessionCopy.captionTurn }
        else { caption = SessionCopy.captionRiver }
        if details.pots.count > 1 {
            caption = SessionCopy.captionMultiPot(done: done, main: details.pots[0].amount, sideCount: details.pots.count - 1)
        }

        let seats = g.players.dropFirst().map { seatState($0, anim) }

        let heroWinner = g.winners.first { $0.id == 0 }
        let showHeroRank = g.board.count == 5 && (g.revealed || g.showdown)
        let heroBadge: RankBadge? = !showHeroRank && heroWinner == nil ? nil : RankBadge(
            text: showHeroRank
                ? (hero.folded ? SessionCopy.heroFoldedPrefix : "") + evaluate(hero.hole + g.board).label
                : SessionCopy.winnerFallback,
            isWinner: heroWinner != nil,
            a11y: heroWinner.map { SessionCopy.heroWinnerA11y($0.amount) },
            title: heroWinner.map { SessionCopy.winnerTitle($0.label, $0.amount) }
        )
        let turnText: String?
        if done { turnText = nil }
        else if g.actor == 0 { turnText = SessionCopy.heroTurnYours }
        else if hero.folded { turnText = SessionCopy.heroTurnFolded }
        else if hero.allin { turnText = SessionCopy.heroTurnAllIn }
        else { turnText = SessionCopy.waiting }
        let heroState = HeroState(
            name: SessionCopy.heroName,
            cards: hero.hole.enumerated().map { CardFace($0.element, best: heroBest.contains($0.element.key), animate: anim.newHand,
                                                         delayMs: 420 + $0.offset * 130) },
            rankBadge: heroBadge,
            folded: hero.folded,
            isActive: g.actor == 0,
            stack: hero.stack,
            stackText: formatChips(hero.stack),
            position: position(0),
            turnText: turnText,
            lastAction: hero.lastAction != nil ? seatActionChip(g, hero, recent: true) : nil,
            lastActionA11y: SessionCopy.heroLastActionA11y
        )

        let diff = hero.stack - g.stats.buyin
        let session = SessionStatsState(
            stack: hero.stack,
            stackText: formatChips(hero.stack),
            chipsUnit: SessionCopy.chipsUnit,
            changeText: g.stats.hands > 0 ? SessionCopy.sessionChange(diff) : SessionCopy.sessionChangeInitial,
            negative: diff < 0,
            hands: g.stats.hands,
            wins: g.stats.wins,
            winRateText: g.stats.hands > 0
                ? SessionCopy.winRate(Int(jsRound(Double(g.stats.wins) / Double(g.stats.hands) * 100)))
                : SessionCopy.statEmpty
        )

        let formatter = ActivityFormatter(g.players)
        let activity = ActivityState(
            entries: g.logs.reversed().enumerated().map { i, l in
                let segments = formatter.formatLog(l)
                return ActivityEntryState(number: i + 1, text: segments.plainText, segments: segments, type: l.type,
                                          playerId: l.player, isHero: l.player == 0, street: l.street)
            },
            badge: done ? SessionCopy.activityFinished : SessionCopy.activityLive
        )

        let coach = CoachState(
            visible: hints,
            toggleOn: hints,
            toggleLabel: hints ? SessionCopy.coachOn : SessionCopy.coachOff,
            stage: coachStage(g),
            tip: coachTip(g)
        )

        let pot = done ? g.potAtShowdown : potSize(g)
        version += 1
        return TableRenderState(
            version: version,
            hand: g.hand,
            handNumber: SessionCopy.handNumber(g.hand),
            handHeading: SessionCopy.handHeading(g.hand),
            playerCount: count,
            tableTag: SessionCopy.tableTag(count),
            tableSize: SessionCopy.tableSize(count),
            hasFullPlayerNames: g.players.dropFirst().contains { ["viktor", "jungleman", "dwan"].contains($0.botProfile) },
            phase: g.phase,
            street: g.street,
            streetLabel: done ? SessionCopy.streetDone : SessionCopy.street(g.street) ?? SessionCopy.streetReady,
            dealer: g.dealer,
            replayAttempt: g.replayAttempt,
            replayBadge: g.replayAttempt > 0 ? SessionCopy.replayBadge(g.replayAttempt) : nil,
            replayNote: g.replayAttempt > 0 ? SessionCopy.replayNote : nil,
            pot: pot,
            potText: formatChips(pot),
            potPulse: anim.boardChanged,
            potButtonLabel: details.pots.count > 1 ? SessionCopy.potButtonMulti(details.pots.count - 1) : SessionCopy.potButtonSingle,
            potButtonA11y: SessionCopy.potDetailsA11y,
            board: board,
            boardCaption: caption,
            practiceRunout: g.practiceBoard != nil,
            seats: seats,
            hero: heroState,
            session: session,
            activity: activity,
            actions: actionPanel(legal, done: done),
            coach: coach,
            showdown: showdownState,
            potDetails: potDetails(details, done: done),
            opponents: opponentsSummary(g, pendingBotSettings),
            opponentsDialog: opponentsEditor.state(g, requestedCount: requestedCount),
            review: review.state(),
            settings: SettingsState(
                requestedSeatCount: requestedCount,
                seatCountOptions: (MIN_PLAYERS...MAX_PLAYERS).map { OptionItem($0, SessionCopy.playerCountOption($0)) },
                tableChangeNote: requestedCount != count ? SessionCopy.tableChangeNote(requestedCount) : nil,
                difficulty: g.difficulty,
                difficultyOptions: Difficulty.allCases.map { OptionItem($0, SessionCopy.difficultyLabel($0)) },
                hints: hints,
                sound: sound,
                soundA11y: sound ? SessionCopy.soundOffA11y : SessionCopy.soundOnA11y,
                soundTitle: sound ? SessionCopy.soundStateOn : SessionCopy.soundStateOff,
                emotionOptions: EmotionMode.allCases.map { OptionItem($0, $0.label) }
            ),
            finishing: finishing,
            backgrounded: backgrounded
        )
    }

    private func seatState(_ p: Player, _ anim: Animation) -> SeatState {
        let g = game
        let winner = g.winners.first { $0.id == p.id }
        let reveal = isSeatHandVisible(p)
        let rank = reveal && !p.folded && g.board.count == 5 ? evaluate(p.hole + g.board) : nil
        let layout = SEAT_LAYOUTS[g.players.count]![p.id - 1]
        let profile = getBotProfile(p.botProfile)
        let mood: MoodKind = g.emotionMode == .off ? .steady : p.botMood.kind
        var badge: RankBadge?
        if rank != nil || winner != nil {
            badge = RankBadge(
                text: rank?.label ?? SessionCopy.winnerFallback,
                isWinner: winner != nil,
                a11y: winner.map { SessionCopy.winnerA11y(p.name, $0.amount) },
                title: winner.map { SessionCopy.winnerTitle($0.label, $0.amount) }
            )
        }
        return SeatState(
            id: p.id,
            name: p.name,
            layoutX: layout.x,
            layoutY: layout.y,
            position: position(p.id),
            folded: p.folded,
            isActor: g.actor == p.id,
            isWinner: winner != nil,
            revealed: reveal,
            cards: reveal ? p.hole.map { c in CardFace(c, best: rank?.cards.contains { $0.key == c.key } ?? false) } : [],
            cardBacks: reveal ? 0 : p.hole.count,
            dealAnimation: !reveal && anim.newHand,
            cardBackDelaysMs: reveal ? [] : p.hole.indices.map { p.id * 65 + $0 * 140 },
            cardBackA11y: SessionCopy.cardBackA11y,
            badge: badge,
            avatar: SessionCopy.avatarLetters[p.id],
            avatarTitle: SessionCopy.avatarTitle(p.name, profile.short, mood.label),
            profileId: profile.id,
            styleShort: profile.short,
            styleTitle: SessionCopy.styleTitle(profile.name, profile.tag),
            styleA11y: SessionCopy.styleA11y(p.name, profile.name),
            mood: mood,
            moodLabel: mood.label,
            stack: p.stack,
            stackText: formatChips(p.stack),
            peek: g.phase == .done
                ? PeekToggle(pressed: reveal, title: reveal ? SessionCopy.peekHide : SessionCopy.peekShow,
                             a11y: SessionCopy.peekA11y(reveal: reveal, p.name))
                : nil,
            action: seatActionChip(g, p),
            actionA11y: SessionCopy.seatActionA11y(p.name)
        )
    }

    private func actionPanel(_ legal: LegalActions, done: Bool) -> ActionPanelState {
        let g = game
        let hero = g.players[0]
        let decisionText: String
        if legal.enabled {
            decisionText = legal.canCheck
                ? SessionCopy.decisionCanCheck
                : SessionCopy.decisionToCall(legal.callAmount) + (legal.raiseReopened ? "" : SessionCopy.decisionNotReopened)
        } else if done {
            decisionText = ""
        } else if g.phase == .between {
            decisionText = g.revealed
                ? (g.board.count == 5 ? SessionCopy.decisionShowdownSettling : SessionCopy.decisionAllInRunout)
                : SessionCopy.decisionDealingNext
        } else {
            let name = g.players.indices.contains(g.actor) ? g.players[g.actor].name : SessionCopy.opponentFallback
            decisionText = hero.folded ? SessionCopy.decisionObserve(name) : SessionCopy.decisionWait(name)
        }
        let callLabel = legal.enabled && legal.canCheck ? SessionCopy.check
            : legal.enabled && legal.callAmount < legal.toCall ? SessionCopy.callAllIn
            : SessionCopy.call
        let callAmount: Int? = legal.enabled && !legal.canCheck ? legal.callAmount : nil
        let caption = raiseCaption(LabelStep(street: g.street, history: g.history, currentBet: g.currentBet, legal: legal), bet)
        let canRaise = legal.enabled && legal.canRaise
        let canFinish = canFinishHand()
        return ActionPanelState(
            decisionStripVisible: !done,
            decisionText: decisionText,
            controlsVisible: !done && !hero.folded,
            foldLabel: SessionCopy.fold,
            foldEnabled: legal.enabled,
            callEnabled: legal.enabled,
            callLabel: callLabel,
            callAmount: callAmount,
            callAmountText: callAmount.map { formatChips($0) },
            callA11y: callAmount.map { "\(callLabel) \(formatChips($0))" } ?? callLabel,
            raiseEnabled: canRaise,
            raiseCaption: caption,
            bet: bet,
            betText: formatChips(bet),
            raiseA11y: "\(caption) \(formatChips(bet))",
            sliderLabel: SessionCopy.betSliderLabel,
            sliderA11y: SessionCopy.betSliderA11y,
            sliderMin: legal.enabled ? legal.minRaiseTo : nil,
            sliderMax: legal.enabled ? legal.maxRaiseTo : nil,
            presets: BetPreset.allCases.map { PresetState(preset: $0, label: SessionCopy.presetLabel($0), amount: presetAmount($0), enabled: canRaise) },
            nextHandVisible: done,
            nextHandLabel: hero.stack == 0 ? SessionCopy.nextHandRebuy : SessionCopy.nextHand,
            finishHandVisible: canFinish || finishing,
            finishHandEnabled: !finishing && canFinish,
            finishHandLabel: finishing ? SessionCopy.finishHandBusy : SessionCopy.finishHand,
            finishHandTitle: SessionCopy.finishHandTitle,
            replayVisible: canRestartHand(g),
            replayLabel: SessionCopy.replayHand,
            replayTitle: SessionCopy.replayHandTitle,
            reviewVisible: review.state().buttonVisible,
            reviewLabel: SessionCopy.reviewHand
        )
    }

    private func potDetails(_ details: PotSet, done: Bool) -> PotDetailsState {
        let g = game
        let hero = g.players[0]
        func eligibilityLabel(_ eligible: [Int]) -> String {
            if eligible.contains(0) { return SessionCopy.potEligHero }
            if done || hero.folded { return SessionCopy.potEligNotIn }
            if hero.allin { return SessionCopy.potEligOverAllIn }
            return SessionCopy.potEligNotYet
        }
        let pots = details.pots.map { pot -> PotCardState in
            let participants = pot.eligible.map { g.players[$0].name }.joined(separator: SessionCopy.listJoiner)
            let split = pot.awards.count > 1
            let label = eligibilityLabel(pot.eligible)
            return PotCardState(
                index: pot.index,
                label: pot.label,
                amount: pot.amount,
                amountText: formatChips(pot.amount),
                settled: done,
                eligibilityLabel: label,
                heroEligible: pot.eligible.contains(0),
                contributions: pot.contributions.map { c in
                    let p = g.players[c.id]
                    let suffix = p.folded ? SessionCopy.potContribFolded : p.allin ? SessionCopy.potContribAllIn : ""
                    return PotContributionRow(playerId: c.id, text: p.name + suffix, amount: c.amount, amountText: formatChips(c.amount))
                },
                splitTotalText: done && split ? SessionCopy.potSplitTotal(pot.amount) : nil,
                awards: done ? pot.awards.map { a in
                    let name = g.players[a.id].name
                    return PotAwardRow(playerId: a.id, name: name, winnerText: split ? name : SessionCopy.potAwardWinner(name),
                                       label: a.label, amountText: SessionCopy.potAwardAmount(a.amount), unit: SessionCopy.chips)
                } : [],
                distributionSummary: SessionCopy.potDistributionSummary,
                distributionEligibility: SessionCopy.potDistributionEligibility(label, participants),
                contributionsHeading: SessionCopy.potContribHeading,
                oddChipNote: done && split ? SessionCopy.potOddChipNote : nil,
                expanded: potExpanded.contains(pot.index),
                unit: SessionCopy.chips,
                playerCountText: SessionCopy.potLiveCount(pot.eligible.count),
                participantsText: SessionCopy.potLiveParticipants(participants),
                contributionsSummary: SessionCopy.potContribSummary
            )
        }
        let refunds = details.refunds.map { r -> RefundRowState in
            let name = g.players[r.id].name
            return RefundRowState(
                playerId: r.id,
                amount: r.amount,
                amountText: formatChips(r.amount),
                text: done ? SessionCopy.refundDone(name) : SessionCopy.refundLive(name),
                a11y: done ? SessionCopy.refundDoneA11y(name, r.amount) : nil,
                returned: done
            )
        }
        return PotDetailsState(
            open: potDialogOpen,
            settled: done,
            title: done ? SessionCopy.potTitleSettled : SessionCopy.potTitleLive,
            note: done ? nil : SessionCopy.potNoteLive,
            pots: pots,
            refunds: refunds
        )
    }

    // MARK: Diagnostics

    /// The reference `publicState()` plus `totalLogs` and `wealth`. Never exposes hidden cards or traces.
    public func publicSnapshot() -> PublicTableSnapshot {
        let g = game
        let details = currentPots(g)
        let done = g.phase == .done
        return PublicTableSnapshot(
            playerCount: g.players.count,
            emotionMode: g.emotionMode.rawValue,
            canContinue: canFinishHand(),
            replayAttempt: g.replayAttempt,
            canRestart: canRestartHand(g),
            hand: g.hand,
            dealer: g.players[g.dealer].name,
            seatOrder: "clockwise",
            street: SessionCopy.street(g.street),
            phase: g.phase.rawValue,
            actor: g.players.indices.contains(g.actor) ? g.players[g.actor].name : nil,
            pot: done ? g.potAtShowdown : potSize(g),
            pots: details.pots.map { p in
                PublicPot(label: p.label, amount: p.amount, eligible: p.eligible.map { g.players[$0].name },
                          awards: p.awards.map { PublicAward(name: g.players[$0.id].name, amount: $0.amount, label: $0.label) })
            },
            uncalled: details.refunds.map { PublicRefund(name: g.players[$0.id].name, amount: $0.amount, returned: done) },
            board: (g.practiceBoard ?? g.board).map(\.description),
            settlementBoard: g.board.map(\.description),
            practiceRunout: g.practiceBoard != nil,
            hole: g.players[0].hole.map(\.description),
            stack: g.players[0].stack,
            legal: legalActions(g, 0),
            players: g.players.map { p in
                PublicPlayer(
                    id: p.id,
                    name: p.name,
                    position: seatPosition(g, p.id),
                    stack: p.stack,
                    folded: p.folded,
                    allin: p.allin,
                    bet: p.bet,
                    action: p.action,
                    lastAction: p.lastAction,
                    botProfile: p.id != 0 ? p.botProfile : nil,
                    mood: p.id != 0 ? (g.emotionMode == .off ? MoodKind.steady : p.botMood.kind).rawValue : nil,
                    botStats: p.id != 0 ? p.botStats : nil,
                    cards: isSeatHandVisible(p) ? p.hole.map(\.description) : nil
                )
            },
            result: g.result.isEmpty ? nil : g.result,
            totalLogs: g.logs.count,
            wealth: g.players.reduce(0) { $0 + $1.stack } + (done ? 0 : potSize(g))
        )
    }

    /// Debug and UI-test hooks mirroring the reference's `window.qa` fixtures.
    /// Not for production code paths: the app should only reach them from
    /// debug or UI-test builds.
    public var testHooks: TestHooks { TestHooks(session: self) }

    public struct TestHooks {
        let session: TableSession

        public var game: Game { session.game }

        /// `fixtureGame(count, heroFirst)`: cancels all work, builds a fresh game
        /// with the saved opponent settings, then runs `setup` (usually a
        /// `startHand` plus scripted actions) and renders without scheduling
        /// bots. With `heroFirst` the hero is UTG after `startHand`. Unlike the
        /// reference fixture, the current difficulty is kept.
        @discardableResult
        public func fixture(count: Int = 6, heroFirst: Bool = false, _ setup: (Game) throws -> Void = { _ in }) rethrows -> Game {
            let s = session
            s.seatHandVisibility.removeAll()
            s.cancelTimer()
            s.cancelFinishLoop()
            s.botWait = nil
            s.finishWaiting = nil
            s.finishing = false
            s.resetShowdown()
            s.review.reset()
            s.epoch += 1
            s.viewToken += 1
            let difficulty = s.game.difficulty
            s.game = engine { try newGame(count) }
            s.game.difficulty = difficulty
            if heroFirst { s.game.dealer = count - 4 }
            engine { try applyBotSettings(s.game, s.pendingBotSettings) }
            s.requestedCount = count
            s.lastHand = 0
            s.lastBoard = 0
            try setup(s.game)
            s.render()
            return s.game
        }

        /// Mutates the live game directly (like the fixtures), then renders without scheduling.
        public func mutate(_ block: (Game) throws -> Void) rethrows {
            try block(session.game)
            session.render()
        }

        /// `qa.stop()`: freezes bots.
        public func stop() {
            session.cancelTimer()
            session.botWait = nil
        }

        /// `qa.thinking()`.
        public func thinking() -> BotWaitInfo? {
            session.botWait.map {
                BotWaitInfo(actor: session.game.actor, delayMs: $0.plan.delayMs, startedAt: $0.startedAt, deadline: $0.deadline)
            }
        }

        /// `qa.resumeBots()`: schedules again, reusing a current plan.
        @discardableResult
        public func resumeBots() -> BotWaitInfo? {
            session.schedule()
            return thinking()
        }

        /// `qa.timingRecords()`: the private bot execution records.
        public func timingRecords() -> [BotDecisionRecord] { session.game.botDecisions }

        public var hasPendingTimer: Bool { session.timer != nil || session.finishTimer != nil }
    }
}
