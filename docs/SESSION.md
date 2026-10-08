# Table session API

`TableSession` is the platform-neutral controller of the practice table. It
ports the reference `src/ui/table-controller.js`, the settings logic of
`opponents-controller.js` and `preferences.js`, the showdown data of
`showdown.js`, the persona annotation of `activity.js`, and the scheduling and
lifecycle half of `review-controller.js`. It contains no UI framework code. The
Compose `ViewModel` and the SwiftUI observable model wrap it and render its
state.

- Kotlin: `android/core`, package `com.august.noirpoker.core.session`.
- Swift: `ios/Packages/PokerCore/Sources/PokerCore/Session/`, module
  `PokerCore` (see "Swift notes" below for the few renamed types).
- Tests: `android/core/src/test/kotlin/com/august/noirpoker/core/session/` and
  `ios/Packages/PokerCore/Tests/PokerCoreTests/Session/`. Both suites replay the
  shared `fixtures/session-scenarios.json` (see "Shared session fixture").

The two controllers are written independently but expose the same concepts
under the same names: the same commands, the same render-state fields, the same
English copy (`SessionCopy` is identical string for string), the same preset
formula, the same delays (street 1,000 ms, settlement 850 ms, Finish Hand 0 ms
ticks), the same random consumption, and the same activity text.

## Threading

The session is single-threaded. Call every command on one thread (the main
thread in the apps), and deliver every `Scheduler` callback and `ReviewSink`
call on that same thread. Bot decisions are planned synchronously inside the
session, as in the reference. Only the review analysis runs elsewhere, inside
the `ReviewRunner` the UI provides.

## Construction

```kotlin
val session = TableSession(
    scheduler = mainScheduler,        // Scheduler: nowMs + schedule(delayMs, action) -> Cancellable
    storage = preferencesStorage,     // KeyValueStorage: getString / putString (may throw)
    random = SystemRandom,            // RandomSource; one stream for shuffle, bots and timing
    reviewRunner = backgroundRunner,  // ReviewRunner? (null: opening a review reports an error)
)
session.effectListener = { effect -> /* sounds, chip flights, focus */ }
val subscription = session.addListener { state -> uiState.value = state }  // called at once, then on every change
session.start()                       // deals hand 1, as the reference does at startup
```

On Android, implement `Scheduler` with a main-thread `Handler` (or a
main-dispatcher coroutine) and `SystemClock.elapsedRealtime()`, and
`KeyValueStorage` with `SharedPreferences` or DataStore. On iOS, use a
main-actor task with `ContinuousClock`, and `UserDefaults`. Tests use
`ManualScheduler` (a virtual clock: `advanceBy`, `advanceTo`, `runCurrent`,
`runUntilIdle`, `nowMs`, `pendingCount`) and `InMemoryStorage`.

## State

`session.state: TableRenderState` is an immutable snapshot rebuilt after every
change. All copy is final English: UI strings come from `SessionCopy`, and
engine strings (action captions, logs, results, hand, mood and profile labels)
come from the engine unchanged. Amounts are also given as numbers.

| Field | Contents |
| --- | --- |
| `hand`, `handNumber` (`"01"`), `handHeading`, `playerCount`, `tableTag` (`6-MAX`), `tableSize` (`6-Handed No-Limit`), `hasFullPlayerNames` | Header and table meta |
| `phase`, `street`, `streetLabel`, `dealer`, `replayAttempt`, `replayBadge`, `replayNote` | Hand progress; the replay badge and note only during a replay |
| `pot`, `potText`, `potPulse`, `potButtonLabel`, `potButtonA11y` | Pot value (`potAtShowdown` once settled) and the pot details button |
| `board` (5 `BoardSlot`), `boardCaption`, `practiceRunout` | Displayed board (practice runout included), best-five highlights, deal animation flags and delays |
| `seats: List<SeatState>` | Opponents 1..n-1: reference layout percentages, position badge and full name, actor flag, winner badge (`RankBadge`), reveal state and face-up cards, card backs with deal delays, style and mood, stack, eye toggle (`peek`, only after settlement), and the action chip |
| `hero: HeroState` | Hole cards (best-five flags), rank or winner badge (`Folded · Two Pair`, `Winner`), position, turn text (null once the hand is over), and the retained last action with its street |
| `session: SessionStatsState` | Stack, net change, hands, wins, win rate |
| `activity: ActivityState` | Log entries in chronological order, numbered from 1, with persona segments (`Alex (ST Wang)`), type, player id, hero flag; `LIVE`/`FINISHED` badge |
| `actions: ActionPanelState` | Decision strip text; Fold / Call / Raise labels, enablement and accessibility text; raise caption (`3-bet raise to`); bet, slider bounds, presets with exact amounts; Next Hand / Finish Hand / Replay Hand / Review This Hand visibility and labels |
| `coach: CoachState` | Hints visibility, toggle label, stage and tip (always computed) |
| `showdown: ShowdownState?` | Context line and one `ShowdownSceneState` per live player: ordered best five, highlight flags, explanation, motion, awards, status and footer. `key` changes once per settled hand, so animate only when it changes |
| `potDetails: PotDetailsState` | Pot dialog: open flag, title, live note, per-pot cards (awards, split total, eligibility, contributions, odd-chip note, expanded state) and refund rows |
| `opponents: OpponentsSummary` | Summary chip (`Balanced`, `3 Styled Opponents`, `Next Hand`) and the pending-change note |
| `opponentsDialog: OpponentsDialogState?` | Non-null while the Opponent Styles draft is open: profile cards, detail, comparison table, 8 roster rows |
| `review: ReviewState` | Review button and dialog state, captured input, status, progress, analysis, selected step, perspective, opponent filter and records |
| `settings: SettingsState` | Requested seat count, table-change note, difficulty, hints, sound, option labels |
| `finishing`, `backgrounded` | Finish Hand loop running; app in background |

`ActionChip` (seat and hero actions) has `label`, `amount`, `amountText`,
`meaning` (tooltip or accessibility hint, for example
`Preflop · Added 50 · 50 in this round`) and `isDeciding` (shown as
`Thinking`).

`session.publicSnapshot()` returns `PublicTableSnapshot`, the reference's
`window.noir.getState()` plus `totalLogs` and `wealth`, for UI tests. It never
includes hidden hole cards, bot plans or traces.

## Commands

| Command | Reference | Notes |
| --- | --- | --- |
| `fold()`, `callOrCheck()`, `raise(amount = currentBet)`, `heroAction(action, amount)` | `heroAction` | Returns false when it is not the hero's turn or the amount is illegal (the game is unchanged) |
| `setBet(value)` | slider input | Snaps to multiples of 25 (round half up), except that the exact all-in is kept |
| `nudgeBet(steps)` | (native) | Accessibility increment and decrement, 25 per step |
| `preset(BetPreset)`, `presetAmount(BetPreset)` | presets | Min, ½ Pot, Pot, All-In with the reference formula `currentBet + max(minRaise, round(pot × f / 25) × 25)`, clamped |
| `nextHand()` | `nextHand` | Applies a pending seat count (new game) and the saved opponent settings. Returns false (and changes nothing) while a hand is in progress, because the engine's `startHand` refuses it |
| `replayHand()` | `retryHand` | Engine `restartHand`; reverses the settlement once; keeps the hand's styles |
| `startNewSession()` | confirm reset | New game with the requested size, current difficulty and saved styles |
| `finishHand()`, `canFinishHand()` | `continueDeal` | Executes the pending planned decision at once, then plans and executes each bot turn immediately (`expedited`), advances streets without delay, and adds a practice runout after a fold-win |
| `toggleReveal(seat)` | `toggleOpponentHand` | Only after settlement; display only |
| `setSeatCount(n)` | table size | 5–9, saved now, applied by the next deal |
| `setDifficulty(d)` | difficulty | Applies now; a thinking bot is re-planned |
| `toggleHints()`, `toggleSound()` | toggles | Persisted |
| `openOpponentSettings()`, `previewProfile(id)`, `assignSeatStyle(seat, id)`, `setEmotionMode(mode)`, `mixLineup()`, `saveOpponentSettings()`, `discardOpponentSettings()` | opponents dialog | Draft editing; save persists and applies at the next deal |
| `openPotDetails()`, `closePotDetails()`, `togglePotDistribution(index)` | pot dialog | Expansion is kept by pot index while the dialog is open |
| `openReview()`, `closeReview()`, `retryReview()`, `selectReviewStep(i)`, `previousReviewStep()`, `nextReviewStep()`, `setReviewPerspective(p)`, `setOpponentReviewFilter(seat?)`, `selectOpponentReviewRecord(i)` | review dialog | Analysis starts when the dialog opens |
| `onBackground()`, `onForeground()` | (native) | See below |

## Scheduling and cancellation

There is at most one pending street or bot timer, plus the Finish Hand step.

- Street advance: 1,000 ms, or 850 ms when the river betting has closed
  (settlement next).
- Bot turn: `planBotTurn` chooses the decision and its thinking time
  (1,200–8,000 ms) at once; the timer fires at `startedAt + delayMs`. A later
  reschedule reuses a current plan and its deadline and draws no new random
  values. A stale plan (difficulty, street, actor, stack… changed) is replaced.
- Finish Hand runs one engine step per zero-delay tick.

`epoch` increments on Next Hand, Replay Hand, Start New Session, Finish Hand
and `onBackground()`. Every callback captures it and does nothing once it
changed, and the handles are cancelled as well. `viewToken` is the reference's
`epoch` for the review and showdown keys (`"{token}:{hand}"`); it does not move
on background transitions, so a finished review survives them.

`onBackground()` cancels the timer, stops a running Finish Hand loop and
cancels the review job. A thinking bot keeps its plan. `onForeground()`
restarts that plan's full delay from the time of return, without new random
draws, and restarts the review analysis if its dialog is still open.

## Effects

`effectListener` receives `SessionEffect`s:

- `Sound(SoundKind)`: only while sound is on. `CHIP` 310 Hz sine, `DEAL`
  820/570 Hz triangle, `WIN` 440/554/659 Hz sine.
- `ChipFlight(seat)`: three chips fly from the seat (0 = hero) to the pot.
  Skip it under reduced motion.
- `CancelChipFlights`: Replay Hand removes the chips in flight.
- `RevealToggled(seat, visible)`: keep focus on the eye toggle and fade the
  cards in when they are shown.

## Preferences

`PreferencesStore` uses the reference keys and validation:

| Key | Value | Default |
| --- | --- | --- |
| `noir-table-v1` | `{"playerCount":6,"difficulty":"normal"}`; integer 5–9 (`6.0` accepted), `easy`/`normal`/`hard` | 6, `normal` |
| `noir-opponents-v1` | `{"emotionMode":"subtle","assignments":{"1":"balanced",…,"8":"balanced"}}`, sanitized | `subtle`, all Balanced |
| `noir-sound` | `"true"` turns sound on | off |
| `noir-hints` | `"false"` turns hints off | on |

Corrupt JSON, unexpected types and storage failures fall back to defaults. No
cards, stacks, history or statistics are persisted.

## Review runner

```kotlin
fun interface ReviewRunner { fun start(job: ReviewJob, sink: ReviewSink): Cancellable }
interface ReviewSink { fun progress(done: Int, total: Int); fun complete(analysis: ReviewAnalysis); fun fail(error: Throwable?) }
interface ReviewAnalysis { val priorityIndex: Int }
```

`ReviewJob` carries a job id, the review key and a `HeroReviewInput` (hand,
hero decision snapshots, outcome; `HandReviewInput.heroInput` on both
platforms). Opponent execution records are never sent to
the hero analysis; they stay in `ReviewState.input.opponents` for the opponent
panel. A typical Android runner launches the analysis on `Dispatchers.Default`,
checks for cancellation between decisions, and posts each sink call back to
the main thread. The session drops progress and results from stale jobs: a new
hand settles, Replay Hand, Start New Session, a seat-count change, or the
background. The review module's summary type implements `ReviewAnalysis`.

## Test hooks

`session.testHooks` mirrors the reference's `window.qa` hooks for debug and
UI-test builds only: `fixture(count, heroFirst) { game -> … }` (cancel all
work, build a fresh game with the saved styles, run a setup, render without
scheduling), `mutate { game -> … }`, `stop()`, `thinking()`, `resumeBots()`,
`timingRecords()`. Unlike the reference fixture, `fixture` keeps the current
difficulty. The test `Harness` in `SessionSupport.kt` ports the reference QA
scenarios (`heroTurn`, `bettingTurn`, `foldFinished`, `allinRest`,
`respondToHero`, `river`, `retainedRiver`, `finish`, `foldWin`, `foldRest`,
`foldPotRefund`, `scene`).

## Copy decisions

- Hero last-action labels capitalize the stripped verb: `3-bet Raise`,
  `2-bet Open`, `1-bet Bet`, matching the e2e assertions. The copy catalog
  lists them in lowercase.
- Seat-action parsing reads the English engine text, including grouped amounts
  (`4-bet raise to 1,800`).
- Persona annotation skips the leading street name of street logs, because the
  bot "River" collides with `River · 7♠` in English.
- Coach tips use lowercase hand nouns (`You've made a flush`).

## Swift notes (`PokerCore`)

The Swift port lives in `ios/Packages/PokerCore/Sources/PokerCore/Session/`
(module `PokerCore`, no UI framework and no Foundation import) with tests in
`ios/Packages/PokerCore/Tests/PokerCoreTests/Session/`. Behavior, copy, delays,
random consumption and the state fields match the Kotlin session above. The
differences are naming and Swift idiom only.

### Renamed types

`PokerCore` is one module shared with the engine and the review port, and app
code imports it next to Combine and SwiftUI, so a few names differ from Kotlin:

| Kotlin | Swift | Why |
| --- | --- | --- |
| `Cancellable` | `SessionCancellable` (protocol), `CancelHandle` (closure-backed class) | Combine has `Cancellable` |
| `Scheduler` | `SessionScheduler` | Combine has `Scheduler` |
| `ReviewOutcome`, `ReviewPot`, `ReviewAward` | `HandReviewOutcome`, `HandReviewPot`, `HandReviewAward` | Leave the plain names to the review module |
| `ReviewAnalysis` | `HandReviewAnalysis` (protocol, `Sendable`) | Same |
| `ReviewStatus`, `ReviewPerspective`, `ReviewState` | `HandReviewStatus`, `HandReviewPerspective`, `HandReviewState` | Same |
| `MiniJson` (`Any?`) | `MiniJSON.Value` (enum); `.anyValue` feeds `sanitizeBotSettings` | Typed JSON without Foundation |
| `SessionEffect.Sound(kind)` … | `.sound(SoundKind)`, `.chipFlight(seat:)`, `.cancelChipFlights`, `.revealToggled(seat:visible:)` | Swift enum |

Everything else keeps the Kotlin name: `TableSession`, `TableRenderState` and
its parts (`CardFace`, `OptionItem`, `SeatState`, `HeroState`, `ActionPanelState`, `ActionChip`,
`PresetState`, `BetPreset`, `ShowdownState`, `HandScene`, `PotDetailsState`, …),
`ManualScheduler`, `KeyValueStorage`, `InMemoryStorage`, `PreferencesStore`,
`TablePreferences`, `ReviewRunner`, `ReviewSink`, `ReviewJob`,
`HeroReviewInput`, `HandReviewInput`, `OpponentSettingsEditor`,
`ActivityFormatter`, `seatActionChip`, `coachTip`, `showdownScenes`,
`winningScenes`, `SEAT_LAYOUTS`, `MIXED_LINEUP`, `SessionCopy`.

Kotlin constants and Swift static properties follow each language's style:
`TableSession.DEFAULT_BET` / `STREET_DELAY_MS` / `SHOWDOWN_DELAY_MS` are
`TableSession.defaultBet` / `streetDelayMs` / `showdownDelayMs` (150, 1,000 and
850), and `ManualScheduler.advanceBy` / `advanceTo` are `advance(by:)` /
`advance(to:)`.

### Construction and binding

```swift
@MainActor @Observable final class TableModel {
    private(set) var state: TableRenderState
    let session: TableSession
    private var subscription: SessionCancellable?

    init() {
        session = TableSession(scheduler: MainScheduler(),        // SessionScheduler
                               storage: UserDefaultsStorage(),     // KeyValueStorage
                               random: SystemRandom.shared,
                               reviewRunner: DetachedReviewRunner()) // ReviewRunner?
        state = session.state
        session.effectListener = { [weak self] effect in self?.play(effect) }
        subscription = session.addListener { [weak self] in self?.state = $0 }
        session.start()
    }
}
```

- `SessionScheduler`: `var nowMs: Int` (monotonic, for example
  `ContinuousClock.now` in milliseconds) and
  `schedule(delayMs:_:) -> SessionCancellable`. Back it with a `@MainActor`
  `Task` that sleeps and then runs the action; `cancel()` cancels the task.
  The session also drops stale callbacks by epoch, so a late delivery is harmless.
- `KeyValueStorage`: `getString(_:) throws -> String?` and
  `putString(_:_:) throws`, for example over `UserDefaults.standard`.
- `TableSession.state` is set in `init` and replaced after every change;
  `addListener` calls back at once and then on every change (returns a
  `SessionCancellable`). `TableRenderState.version` increases with each state.
  `TableRenderState` and `HandReviewState` are not `Equatable` because the
  analysis is an existential; every nested state struct is `Equatable` and
  `Sendable`.
- Commands are the Kotlin ones with Swift labels: `heroAction(_:amount:)`,
  `fold()`, `callOrCheck()`, `raise(_:)` (nil uses the current bet),
  `setBet(_:)`, `nudgeBet(_:)`, `preset(_:)`, `presetAmount(_:)`, `nextHand()`,
  `replayHand()`, `startNewSession()`, `finishHand()`, `canFinishHand()`,
  `toggleReveal(_:)`, `setSeatCount(_:)`, `setDifficulty(_:)`, `toggleHints()`,
  `toggleSound()`, `openOpponentSettings()`, `previewProfile(_:)`,
  `assignSeatStyle(_:_:)`, `setEmotionMode(_:)`, `mixLineup()`,
  `saveOpponentSettings()`, `discardOpponentSettings()`, `openPotDetails()`,
  `closePotDetails()`, `togglePotDistribution(_:)`, the review commands, and
  `onBackground()` / `onForeground()` (call them from `scenePhase` changes).
  Commands that can be refused return a discardable `Bool`.
- Engine errors in states where the engine cannot throw are treated as broken
  invariants (`preconditionFailure`); `heroAction` returns false for an illegal
  hero action instead.

### Review runner on iOS

```swift
final class DetachedReviewRunner: ReviewRunner {
    func start(_ job: ReviewJob, _ sink: ReviewSink) -> SessionCancellable {
        let task = Task.detached(priority: .userInitiated) {
            // analyze job.input.decisions one by one; check Task.isCancelled between them
            // await MainActor.run { sink.progress(done: i, total: n) }
            // await MainActor.run { sink.complete(summary) }   // summary: HandReviewAnalysis
        }
        return CancelHandle { task.cancel() }
    }
}
```

`ReviewJob` and `HeroReviewInput` are `Sendable` values; the sink must be called
on the main actor. Results of a cancelled or stale job are dropped by job id.

### Tests

`Harness` in `SessionSupport.swift` mirrors the Kotlin harness: a
`ManualScheduler`, a `CountingRandom(SeededRandom(seed:))` stream, and the
reference QA fixtures (`heroTurn`, `bettingTurn`, `foldFinished`, `allinRest`,
`respondToHero`, `river`, `retainedRiver`, `finish`, `foldWin`, `foldRest`,
`foldPotRefund`, `scene`). `ManualScheduler` uses `advance(by:)`,
`advance(to:)`, `runCurrent()`, `runUntilIdle(maxMs:)`, `nextDueAt` and
`pendingCount`.

## Shared session fixture

`fixtures/session-scenarios.json` keeps the two controllers identical. The
reference table controller is DOM-bound (it reads and writes the page on
import), so it cannot be driven headlessly like the engine; the file is
hand-authored from the UI behavior spec instead of generated. Each scenario has
a `seed` (one Mulberry32 stream for the shuffle, bots and thinking times), an
optional initial `storage` and `reviewRunner` flag, and a list of steps:

- commands (`{"do": "nextHand", "returns": true}`): the public session commands
  (`start`, `nextHand`, `replayHand`, `startNewSession`, `finishHand`, `fold`,
  `callOrCheck`, `raise`, `setBet`, `nudgeBet`, `preset`, `toggleReveal`,
  `setSeatCount`, `setDifficulty`, `toggleHints`, `toggleSound`, the opponent
  dialog, pot dialog and review commands, `background`, `foreground`), the
  virtual clock (`advance`, `runCurrent`, `runBots`, `runUntilIdle`), test hooks
  (`stop`, `resumeBots`, `qa` with a reference QA fixture name and its
  parameters), `completeReview` (the fake runner's sink), and `playOut`
  (run bots; on each hero turn `fold` or `callOrCheck`; until the hand ends);
- `expect` steps: a partial excerpt of one projection. Objects check only the
  keys they list, arrays check their length and each element, numbers compare
  numerically. The projection is `state` (the render state with enum ids such
  as `playing`, `half`, `two-pair`, cards as `"{suit}-{rank}"` keys) plus
  `clock`, `pending`, `nextDueAt`, `draws`, `thinking`, `effects` (since the
  previous expect: `sound:deal`, `chipFlight:0`, `cancelChipFlights`,
  `revealToggled:2:true`), `storage`, `wealth`, `epoch`, `viewToken` and
  `canFinishHand`.

The consumers are `SessionScenarioFixtureTest.kt` and
`SessionScenarioFixtureTests.swift`; their projections must stay field for
field identical. Kotlin can dump full projections for authoring new
expectations: `NOIR_SESSION_RECORD=/tmp/dump.json ./gradlew -p android/core test
--tests '*SessionScenarioFixtureTest*'`. Check every recorded value against the
spec and the copy catalog before adding it; the Swift suite must then pass
unchanged.
