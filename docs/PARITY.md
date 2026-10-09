# Feature parity: native ports vs. the pinned reference

Snapshot: branch `claude/native-rules-engine-crk8fn`, HEAD `91611f4` (2026-10-09). This checklist follows the contract in `docs/MIGRATION.md` and updates the audit taken at `bc9314e`, after work packages WP-A to WP-G were merged. Domain tests (Kotlin `android/core`; Swift `PokerCore`, 267 tests in the `swift:6.1` Linux image) and `node scripts/generate-reference-fixtures.mjs --check` pass locally. Android app JVM tests, Android instrumented tests and iOS UI tests cannot run in this environment. CI was last green on every job at `f7e9199` (run 37896081642); the commits after it have not been through CI yet.

Legend:
- ✅ implemented and covered by a test that would fail if it broke
- ☑️ implemented, but no meaningful test
- 🟡 partial, or deviates from the reference (see notes)
- ❌ missing

"(UI test new; first CI run pending)" marks rows whose only proof is an Android instrumented test or an iOS UI test added after the last green CI run.

Paths: `A/` = `android/`, `I/` = `ios/`. `A/core` tests live under `A/core/src/test/kotlin/com/august/noirpoker/core/`; app sources under `A/app/src/main/java/com/august/noirpoker/`; instrumented tests under `A/app/src/androidTest/java/com/august/noirpoker/`. Swift package tests live under `I/Packages/PokerCore/Tests/PokerCoreTests/`. "F-engine" is `fixtures/engine-scenarios.json` (264 cases, full state snapshot on every step), consumed by `EngineFixturesTest` (Android) and `EngineScenarioFixtureTests` (iOS). "F-session" is `fixtures/session-scenarios.json`, consumed by `SessionScenarioFixtureTest` / `SessionScenarioFixtureTests`. "F-dialog" is `fixtures/review-dialog.json`, consumed by `ReviewDialogTest` / `ReviewPresentationTests`.

## 1. Table setup

| Behavior | Android | iOS | Evidence / notes |
|---|---|---|---|
| 5–9 seats, default 6, others rejected | ✅ | ✅ | `Poker.kt:12-17`, `Poker.swift:4-9`; F-engine "population" cases, `RulesTest`, `RulesTests.testNewGameValidatesTableSize` |
| 5,000 stacks, 25/50 blinds, short blinds post all-in | ✅ | ✅ | F-engine "short blinds post actual stacks…"; `RulesTests.testRebuyAndShortBlinds` |
| Busted stacks rebuy for the next hand; hero rebuy adds to buy-in | ✅ | ✅ | F-engine "retry: rebuy and short blind…"; `TableSessionFlowTest:382` / `TableSessionFlowTests:362` |
| Button moves clockwise; SB/BB are the next two seats | ✅ | ✅ | F-engine button-rotation cases for every seat count; `RulesTests.testPositionsForFiveToNineSeatsFollowTheButton` |
| Burn one card before each street | ✅ | ✅ | `Poker.kt:414-417`, `Poker.swift:390-393`; F-engine compares `deckSize` on every step |

## 2. Bots, difficulty and styles

| Behavior | Android | iOS | Evidence / notes |
|---|---|---|---|
| Nine profile IDs, order, calibrated parameters | ✅ | ✅ | `fixtures/bot-profiles.json` checked field by field (`UnitFixturesTest`, `ProfileFixtureTests`) |
| Research links stored and openable | ☑️ | ☑️ | Data is fixture-checked. The link UI (`A/app/.../ui/table/OpponentsSheet.kt:159,212`, `I/NoirPoker/Sheets/OpponentsSheet.swift:233`) has no test |
| "Training archetypes, not real stats" caveat | ☑️ | ☑️ | `UiCopy.kt:101`, `I/NoirPoker/Design/UiCopy.swift:100`. The two tables are diffed by `scripts/check-ui-copy.mjs` (passes locally; not run in CI). No test asserts the caveat is shown. `docs/BOTS.md` documents it |
| Per-seat styles: draft, save, apply next hand, frozen on replay, discard on close | ✅ | ✅ | `TableSessionFlowTest:406,446` / `TableSessionFlowTests:386,427`; F-session styles scenario; UI `SheetsTest:199`, `PreferencesAndLayoutTests:40` |
| Three difficulty levels; apply immediately; a thinking bot re-plans | ✅ | ✅ | `fixtures/bot-decisions.json` (180 cases); `SessionSchedulingTest:61` / `SessionSchedulingTests:54` |
| Bot decisions see only public information | ✅ | ✅ | Holes, deck, winners and result tampered for all 9 profiles: `BotsTest` (Android), `BotTests.swift:686` (`BotBehaviorTests`) |
| Seat style label and wide-name layout | ☑️ | ☑️ | `Arena.kt:560`, `SeatView.swift:179-187`. `styleShort` is checked by F-session; no test checks the rendered label or the long-name layout |
| Observed VPIP/PFR per bot in Opponent Styles | ✅ | ✅ | `SessionPresentationTest:420` / `SessionPresentationTests:434`: round half up (1/3, 2/3, 12.5%, 37.5%), "—" at zero hands and off-table, reset only after a restyle is dealt |
| Documented simulated VPIP/PFR calibration (6-max 54.16%/14.48%, 9-max 45.95%/12.60%) and a measurement harness | ✅ | ✅ | `docs/BOTS.md`; ports of `measure:bots` in `BotCalibrationTest:96,108,123,140` / `BotCalibrationTests:76,87,98,114` (flop distributions, ST/Peter entry rates, second seed pair) |
| Comparison table and stat definitions | ☑️ | ☑️ | `OpponentsSheet.kt:354-379`, `OpponentsSheet.swift:115-160`. The domain rows are counted in `TableSessionFlowTests:400`; the rendered table has no test |
| Reference behavioral bot tests (timing monotonicity, entry boundaries, style differences) | ✅ | ✅ | Android `BotsTest`, `BotTimingTest`; iOS `BotBehaviorTests` (`BotTests.swift:381-700`) mirrors them, plus `BotCalibrationTest:165` 1,326-hole ordering |

## 3. Synthetic emotions

| Behavior | Android | iOS | Evidence / notes |
|---|---|---|---|
| Five moods, three intensities (Off / Subtle / Pronounced) with axis offsets | ✅ | ✅ | `fixtures/mood.json` (70 sequences); `BotsTest` and `BotTests` emotion-axis tests |
| Triggers, decay, cooldown, loss priority | ✅ | ✅ | `mood.json`; `BotsTest` / `MoodTests` (`BotTests.swift:75-168`) |
| Hand-start baseline restored by Replay | ✅ | ✅ | `ReplayTest` "replay restores bot profiles, moods…"; `ReplayTests.testReplayRestoresFrozenProfilesMoodsAndStatisticsExactlyOnce` |
| Off clears moods next hand; restyle resets mood and stats | ✅ | ✅ | `TableSessionFlowTest:464` / `TableSessionFlowTests:447` |
| Mood avatar ring and emotion-mode control | ☑️ | ☑️ | `Arena.kt:576-588`, `SeatView.swift:236`, `OpponentsSheet.kt:331-349`, `OpponentsSheet.swift:91`. No UI test |

## 4. Betting, pots and settlement

| Behavior | Android | iOS | Evidence / notes |
|---|---|---|---|
| Legal check/call/fold/raise; "raise to"; minimum raise; call→check | ✅ | ✅ | F-engine "TDA raise examples…", "poker-check: invalid action preserves state"; `RulesTests.testInvalidActionsThrowTypedErrorsAndPreserveState` |
| Short all-in does not reopen; cumulative short raises reopen; BB keeps its option | ✅ | ✅ | F-engine rules-audit cases; `RulesTests.testShortAllInDoesNotReopenCompletedRaise`, `testSeveralShortAllInsCanCumulativelyReopenRaising` |
| All-in call for less, with the "All-In Call" label | ✅ | ✅ | F-engine bet-labels; `PracticeAndLastActionTests.testAllInCallLabelAndCaptionFallbacks` |
| Side-pot eligibility; folded contributions stay in the pot | ✅ | ✅ | F-engine multi-pot ×14; `PotsTest` (16) / `PotTests` (15) |
| Uncalled refunds, not counted as wins | ✅ | ✅ | F-engine "uncalled return is separate…"; `PotTests.testUncalledReturnIsNotAWin` |
| Split pots and odd chips clockwise from the button | ✅ | ✅ | 70 F-engine odd-chip and royal-tie cases at every seat count and button |
| Chip conservation | ✅ | ✅ | `POT_MISMATCH` guard; `ConservationTest`, randomized-hand tests, `SessionSchedulingTest:363` / `SessionSchedulingTests:379`, `simulations.json` `totalChips`; UI double-tap tests check the table total |
| Repeated settlement rejected | ✅ | ✅ | `Poker.kt:471`, `Poker.swift:440`; "settlement cannot award chips twice" on both platforms |

## 5. Last action visibility

| Behavior | Android | iOS | Evidence / notes |
|---|---|---|---|
| `lastAction` {text, street, bet} kept through runouts and settlement | ✅ | ✅ | F-engine "last-action" ×3; `PracticeAndLastActionTests` |
| Seats and hero show it after settlement | ✅ | ✅ | `TableSessionFlowTest:284,341,359` / `TableSessionFlowTests:266,323,340` |

## 6. Showdown and reveal

| Behavior | Android | iOS | Evidence / notes |
|---|---|---|---|
| One scene per unfolded player; own best five in order; winner category | ✅ | ✅ | `SessionPresentationTest:272,296` / `SessionPresentationTests:259,282` (5–9 seats); every hand category in `ShowdownExplanationTest:37` / `SessionPresentationTests:337` |
| Unfolded hole cards shown at showdown and on all-in runouts | ✅ | ✅ | F-session "street advance… then showdown and reveal toggles"; UI `PreferencesAndLayoutTests:150` shows the stage |
| Reveal/hide toggle on every opponent after settlement, including folded ones | ✅ | ✅ | Logic: `TableSessionFlowTest:243` / `TableSessionFlowTests:223`. Android `PeekButton` (`Arena.kt:605`) is a toggleable switch with a 48 dp target: `AdaptiveLayoutTest:274,281`. iOS seat-list toggle asserted at 44 pt: `PreferencesAndLayoutTests:115-140` (UI test new; first CI run pending) |
| Visibility cleared on Next Hand, Replay and Start New Session | ✅ | ✅ | `TableSession.kt:267,298,1149`, `TableSession.swift:244,276`; loop over all three in `TableSessionFlowTest:243` / `TableSessionFlowTests:223` |
| Hand-category winner animations | ✅ | ✅ | Android `ui/table/ShowdownMotion.kt`, JVM `A/app/src/test/.../ui/table/ShowdownMotionTest.kt:29-103` (runs in the CI `android` job). iOS keyframes ported exactly into `PokerCore/Session/ShowdownMotion.swift`, checked by `ShowdownMotionTests:18-120`. Tests cover the motion model, not rendered frames. Kickers are opaque under reduced motion on both |
| Showdown grid columns | ✅ | ☑️ | Reference rule on both (2 columns above 1150 and at 601–900, else 1; 1 column at large text). Android `Showdown.kt:108`, tested by `ShowdownMotionTest:113` and `AdaptiveLayoutTest:287,292`. iOS `ShowdownView.swift:12-20` (also 1 column when the stage is under 620 pt) has no test of the rule |

## 7. Next Hand / Replay Hand / Start New Session

| Behavior | Android | iOS | Evidence / notes |
|---|---|---|---|
| Next Hand keeps stacks and stats, moves the button | ✅ | ✅ | `TableSessionFlowTest:111` / `TableSessionFlowTests:89`; UI `HandFlowTest:115`, `LaunchTests:84` |
| Replay restores exact cards, deck, button and stacks; reverses payout and stats once | ✅ | ✅ | 42 F-engine retry cases (including `randomDraws`); `ReplayTest` / `ReplayTests`; `TableSessionFlowTest:181` / `TableSessionFlowTests:162` |
| Start New Session resets the table and stats, and keeps preferences | ✅ | ✅ | `TableSessionFlowTest:111` / `TableSessionFlowTests:89`: tips off, sound on and saved styles survive, styles are dealt, storage unchanged, stats reset |

## 8. Finish Hand and practice runout

| Behavior | Android | iOS | Evidence / notes |
|---|---|---|---|
| Finish Hand cancels the wait and executes the already-planned bot decision through the legal path | ✅ | ✅ | F-session "Finish Hand…"; `SessionSchedulingTest:110` / `SessionSchedulingTests:103` assert no new random draws and the planned action and amount |
| Practice runout after a fold-win does not change board, deck, payouts or review evidence | ✅ | ✅ | F-engine practice-runout ×5; `ReplayTest` "a practice runout matches the real river…"; `SessionSchedulingTest:168` / `SessionSchedulingTests:160` |
| After a pre-river fold-win, Finish Hand is offered next to Next Hand, Replay and Review | ✅ | ✅ | Independent blocks in `ActionPanel.kt:114,129` and `ActionPanelView.swift:50-62`. `HandFlowTest:188`, `LaunchTests:181` (UI test new; first CI run pending) |

## 9. Decision review

| Behavior | Android | iOS | Evidence / notes |
|---|---|---|---|
| Grading uses only pre-action public information (enforced by type) | ✅ | ✅ | No hidden fields in `ReviewDecision`/`DecisionSnapshot`; privacy variants in `review-hands.json`; `ReviewTests.testReviewTypesHaveNoFieldForHiddenCards…` |
| Context, call price by eligible pot, ranges, sampled/enumerated equity, uncertainty | ✅ | ✅ | `review-decisions.json` (164 cases) checked field by field; `ReviewCheckTest` / `ReviewTests` |
| Legal alternatives, routes, full-engine counterfactual simulation | ✅ | ✅ | Fixture `compareCandidateActions`, `analyzeDecision`; `CounterfactualTest` / `testSimulationIsDeterministicPublicOnly…` |
| Outcome independence | ✅ | ✅ | "decision verdicts do not change with the showdown winner or the future board" plus the twin |
| Separate explanation of executed bot decisions | ✅ | ✅ | Fixture `explainOpponent`; `OpponentExplanationTest` / `testReferenceExplainOpponentRecord` |
| "Not a GTO solution" caveat | ✅ | ✅ | Same method text on both (`ReviewDialog.kt:142`, `ReviewPresentation.swift:26`), locked by F-dialog |
| Dialog presenter (timeline, verdicts, simulation table, metrics, opponent panel) | ✅ | ✅ | `ReviewDialogTest:70-264` / `ReviewPresentationTests:43-269` |
| Dialog copy matches across platforms | ✅ | ✅ | F-dialog holds the copy table, templated copy and both panels in idle, running, error, done, simulation-unavailable and empty states (`ReviewDialogTest:221`, `ReviewPresentationTests:227`). Title is "Hand #12 · Review" on both. Recorded from Kotlin (`NOIR_REVIEW_DIALOG_RECORD`) |
| Review UI tabs "Your Decisions" / "Opponent Decisions" | ✅ | ✅ | Android `SheetsTest:46` waits for DONE. iOS `LaunchTests:148` now waits for DONE and checks verdict chips and the simulation (UI test new; first CI run pending) |
| Review sheet at compact/tablet sizes, 9 seats and large text | 🟡 | 🟡 | Android stacks the simulation table at font scale ≥ 1.3 and wraps tab labels and step meta (`ReviewSheet.kt:703-719`); iOS gates the timeline scroll on Reduce Motion. No layout test opens the review at tablet size, with 9 seats or with large text on either platform |

## 10. Activity and preferences

| Behavior | Android | iOS | Evidence / notes |
|---|---|---|---|
| Complete chronological activity, numbered, no fixed-height truncation | ✅ | ✅ | `SessionPresentationTest:180` / `SessionPresentationTests:166` (6 and 9 seats). Android `LaunchTest:40` counts the rendered rows (UI test new; first CI run pending); iOS has no row-count UI test |
| Seat count and difficulty persisted (`noir-table-v1`) | ✅ | ✅ | `PreferencesTest` / `PreferencesSessionTests`; relaunch tests. iOS UI terminates and relaunches; the Android UI test (`SettingsPersistenceTest:38`) relaunches in the same process only |
| Opponent styles and emotion intensity persisted (`noir-opponents-v1`) | ✅ | ✅ | `PreferencesTest` "opponent settings round-trip…" plus the twin; `TableSessionFlowTest:482` / `TableSessionFlowTests:463` |
| Hints and sound persisted | ✅ | ✅ | "sound is on only for true and hints are off only for false" plus the twin |
| Storage failure falls back to defaults | ✅ | ✅ | "failing storage never throws…" plus the twin |
| Live hand and session not persisted | ✅ | ✅ | By design; only the four keys are written. iOS UI tests use their own `UserDefaults` suite (`I/NoirPoker/Platform/LaunchOptions.swift`) |

## 11. Cancellation, threading and thinking time

| Behavior | Android | iOS | Evidence / notes |
|---|---|---|---|
| Synthetic thinking time 1.2–8 s; selected action preserved | ✅ | ✅ | `bot-decisions.json` checks thinking and timing draws for 180 cases; `BotTimingTest` / `BotPlanTests` |
| Bot work cancelled on Next Hand, Replay and Start New Session | ✅ | ✅ | Epoch and timer cancel; `SessionSchedulingTest:236,250` / `SessionSchedulingTests:229,242` |
| Review work cancelled on Replay, Start New Session and seat change | ✅ | ✅ | `ReviewLifecycleTest:60,152` / `ReviewLifecycleTests:60,148` |
| Review work cancelled on Next Hand | ✅ | ✅ | `TableSession.kt:257`, `TableSession.swift:234`; `ReviewLifecycleTest:102` / `ReviewLifecycleTests:99`. A deviation from the reference (see below) |
| Bot and review work cancelled on background, resumed on foreground | ✅ | ✅ | Session: `SessionSchedulingTest:266,307,331`, `ReviewLifecycleTest:169` and the twins. Android wiring: `SessionLifecycleBinding` (`platform/TableViewModel.kt:66`), JVM `SessionLifecycleBindingTest:47-99`, plus `LifecycleTest:152,180`. iOS wiring: `NoirPokerApp.swift:23-47`, `LifecycleTests:69,108` (UI test new; first CI run pending). Semantics documented in `docs/SESSION.md` |
| Review runs off the UI thread | ✅ | ✅ | Android `ExecutorReviewRunner`: `SessionReviewTest:88-203`. iOS `DetachedReviewRunner` moved to `PokerCore/Session/DetachedReviewRunner.swift`: `DetachedReviewRunnerTests:70-178` |
| Cancellation checkpoints and stale-result dropping | ✅ | ✅ | `SessionReviewTest:110-141`; `ReviewAdapterTests.testCancellationStopsBeforeTheNextDecision`; `ReviewLifecycleTest:76` / `ReviewLifecycleTests:75`; `DetachedReviewRunnerTests:100,135` |

## Visual and language contract

| Item | Android | iOS | Evidence / notes |
|---|---|---|---|
| Palette: the 10 MIGRATION tokens | ☑️ | ☑️ | Exact values in `NoirTheme.kt` and `Theme.swift`. No token test. The lightened footer color still differs: `#8193A1` (`NoirTheme.kt:59`) vs `#8a9dad` (`Theme.swift:58`) |
| Felt, rail and watermark | ☑️ | ☑️ | Felt gradient now matches (reference stops, radius 0.62; `ArenaView.swift:103-108`); iOS watermark uses Manrope. No test |
| Typeface (Manrope, as in the reference) | ☑️ | ☑️ | Both bundle Manrope (OFL; iOS via `UIAppFonts` in `I/Config/NoirPoker-Info.plist`, `Typography.swift`). No test |
| Seat hierarchy at 6 and 9 seats, no overlap | ✅ | ✅ | Android `AdaptiveLayoutTest.assertSeats`. iOS `assertSeatGeometry` (plates inside the arena, centers ≥ 24 pt apart) in `PreferencesAndLayoutTests:87,98,261,274` (UI test new; first CI run pending) |
| Betting controls (presets, snap to 25, exact all-in) | ✅ | ✅ | `SessionPresentationTest:21,53` / `SessionPresentationTests:9,38`; F-session "decision strip, raise captions and presets…" |
| Session statistics | ✅ | ✅ | `HandFlowTest:136`, `LaunchTests:100` |
| Coaching hints | ✅ | ✅ | Domain `coach.visible` is tested (`TableSessionFlowTest:111`, `SessionPresentationTest:455` and twins). iOS now hides the coach footer while tips are off, as Android does; no UI test checks either view |
| How to Play sheet | ✅ | ✅ | Opening is tested on both (`LaunchTest:28`, `LaunchTests:9`). iOS copy moved to `UiCopy.swift` |
| Touch targets 48 dp / 44 pt | ✅ | ☑️ | Android asserts ≥ 48 dp for Fold/Call/Raise and every eye toggle (`AdaptiveLayoutTest:202,274`) (UI test new; first CI run pending). iOS uses `minimumHitTarget()`; only the seat-list eye toggle is asserted (`PreferencesAndLayoutTests:139`) |
| Large accessibility text | ✅ | ✅ | Android caps the arena at 1.3× and adds `SeatList` (`Arena.kt:773`): `AdaptiveLayoutTest:222,255`. iOS adds `SeatListView` (`SeatView.swift:268`) at accessibility sizes: `PreferencesAndLayoutTests:66,115` (UI test new; first CI run pending) |
| Reduced motion | ☑️ | ☑️ | Android re-reads the setting on start and observes it (`MainActivity.kt`); the review timeline scroll is gated. iOS gates the arena height, button press, action panel and review scroll. A full-motion layout pass exists (`AdaptiveLayoutTest:313`), but no test asserts the reduced-motion gating |
| Screen-reader labels | ☑️ | ☑️ | Broad semantics on both; shared accessibility strings for review timeline and simulation cells (F-dialog). No accessibility audit (`AccessibilityChecks` / `performAccessibilityAudit()`) |
| English-only copy, no CJK in shipped code | ✅ | ✅ | No CJK in `android/`, `ios/`, `fixtures/*.json` or `docs/` |
| Contract terms ("Hand Activity", "Opponent Styles", "Hand Review", …) | ☑️ | ☑️ | "Hand Activity", "play it safe", "tendency scores" and the rules replay paragraph now follow the contract (`UiCopy.kt`, `UiCopy.swift`). Only the review dialog title is fixture-locked; other UI terms are not asserted |
| UI copy consistent across platforms | ☑️ | ☑️ | Engine, session and review copy are fixture-locked. UI copy: `UiCopy.swift` mirrors `UiCopy.kt` key for key; `node scripts/check-ui-copy.mjs` reports 83 matching keys locally but is not run in CI. Settings title, Table Tips label, Opponent Styles row and identifiers (`continue-deal`, `confirm-reset`) now match |
| No WebView, JS runtime or cross-platform UI | ✅ | ✅ | Dependencies are Compose / SwiftUI only |
| No reference or fixture assets bundled | ✅ | ✅ | Fixtures reach tests only through test configuration |

## Verification gates

| Gate | Android | iOS | Evidence / notes |
|---|---|---|---|
| Shared fixtures: short all-ins, reopening, multi-pot, refunds, odd chips, exact replay, stats rollback | ✅ | ✅ | F-engine, same JSON on both platforms |
| Privacy boundaries | ✅ | ✅ | 3 privacy cases; both assert that variants share public decisions and differ in outcome (`ReviewFixturesTest`, iOS twin) and that the graded hero panel is identical across variants (`ReviewDialogTest:264`, `ReviewPresentationTests:269`) |
| Engine error codes | 🟡 | 🟡 | All 18 messages are compared; only 11 codes are exercised by `expectError` |
| Seeded bot decisions, ranges, parameters | ✅ | ✅ | `bot-decisions.json`, `bot-profiles.json`, `mood.json`, `simulations.json`; calibration tests |
| Decision-review outputs | ✅ | ✅ | `review-decisions.json`, `review-hands.json`, F-dialog. Both skip total-dependent outputs for 2 fractional-chip cases |
| Session behavior fixture derived from the reference | 🟡 | 🟡 | Provenance now documented in `fixtures/README.md`: hand-authored, recorded from Kotlin (`NOIR_SESSION_RECORD`), timing constants cross-checked against the reference source. It proves cross-platform agreement, not reference equality |
| Original unit tests and `generate-reference-fixtures.mjs --check` | ✅ | ✅ | `reference` CI job; `--check` passes locally (11 fixture files) |
| UI: compact phone, 6 seats | ✅ | ✅ | Android emulator is `pixel_6` (412 dp). The iOS phone model is still the first available iPhone (`native.yml`), not pinned to a compact one |
| UI: compact phone, 9 seats | ✅ | ✅ | Android `AdaptiveLayoutTest:230` (forced 360×740). iOS `PreferencesAndLayoutTests:98` with geometry (UI test new; first CI run pending) |
| UI: tablet, 6 and 9 seats | 🟡 | ✅ | Android forces tablet sizes on the phone emulator (`AdaptiveLayoutTest:236,246,265`); no tablet AVD. iOS iPad landscape and portrait at 6 and 9 seats (`TabletLayoutTests`, `PreferencesAndLayoutTests:227-274`) (UI test new; first CI run pending) |
| Rotation | ✅ | ✅ | Android `LifecycleTest:99,123` (recreate and rotate while a bot thinks, sheet open). iOS `LifecycleTests:148` (iPhone rotation with an open sheet); iPad supports all four orientations (`I/project.yml:37-39`) (UI test new; first CI run pending) |
| Background/foreground (app level) | ✅ | ✅ | Android `SessionLifecycleBindingTest` (JVM) and `LifecycleTest:152,180`. iOS `LifecycleTests:69,108` with a `qa-lifecycle` probe (UI test new; first CI run pending) |
| Repeated replay (UI) | ✅ | ✅ | `HandFlowTest:276`, `LaunchTests:265` (UI test new; first CI run pending) |
| Interrupted review (UI) | ✅ | ✅ | `SheetsTest:104,142,181`, `LaunchTests:291,320` (UI test new; first CI run pending) |
| Repeated settlement requests (UI) | ✅ | ✅ | Double taps on Finish Hand, Next Hand and Replay Hand: `HandFlowTest:227,242`, `LaunchTests:213,231` (UI test new; first CI run pending) |
| Large text | 🟡 | 🟡 | Phone at 6 and 9 seats on both. No tablet or sheet (review, opponents, settings) coverage |
| Release-build profiling | ❌ | ❌ | No benchmark module, `XCTMetric` tests or release builds in CI. MIGRATION makes this a precondition for language changes or complex optimization, so it is not blocking yet |
| CI green | 🟡 | 🟡 | All jobs green at `f7e9199` (run 37896081642). The WP-A to WP-G merges at `91611f4` have not run in CI yet |

## Deviations

These differ from the reference on purpose and are documented where noted.

- **Grouped numbers.** Every chip amount and hand number is rendered with en-US grouping (`1,800`), including action captions where the reference prints raw digits (`scripts/reference-copy.mjs`, `fixtures/README.md`, `docs/ARCHITECTURE.md`).
- **Next Hand cancels the previous hand's review.** The reference lets the analysis run on and drops its result only when the next hand settles. The native session cancels it at Next Hand (project rule; `docs/SESSION.md`).
- **Background keeps the bot's elapsed wait.** The reference has no background handling. A thinking bot keeps its plan and acts after the rest of its delay on return; `waitedMs` counts foreground time only. A pending street advance restarts its full 1,000/850 ms delay (`docs/SESSION.md`; recorded in F-session).
- **Backgrounding cancels Finish Hand.** The fast-forward is not resumed; the button is offered again on return (`docs/SESSION.md`).
- **iOS `.inactive` does not pause the table.** Only `.background` pauses (`NoirPokerApp.swift:41-47`, `LifecycleTests`).
- **Narrow phones.** A seat plate is shifted sideways only as far as needed to stay inside the arena, where the reference's 13–14 % / 86–87 % positions would clip it (`2fc1415`).
- **Large text.** Both apps cap the felt's text size and add a full-size seat list below it; the showdown stage uses one column at accessibility sizes (and, on iOS, when the stage is narrower than 620 pt).
- **Footer color.** `#697d8c` is lightened for contrast, to slightly different values on each platform (see the palette row).

## Remaining gaps

Rows not yet ✅ on both platforms:

1. Research links: no UI test (both).
2. "Training archetypes" caveat: not asserted on screen (both).
3. Seat style label and wide-name layout: no UI test (both).
4. Comparison table and stat definitions: no UI test (both).
5. Mood avatar ring and emotion-mode control: no UI test (both).
6. iOS showdown column rule: no test.
7. Review sheet at tablet size, with 9 seats and with large text: no layout test (both).
8. Palette tokens: no test, and the footer color differs between platforms.
9. Felt, rail and watermark: no test (both).
10. Typeface: no test (both).
11. iOS touch targets: only the eye toggle is asserted.
12. Reduced motion: gating not asserted (both).
13. Screen-reader labels: no accessibility audit (both).
14. Contract terms: only the review title is locked (both).
15. UI copy parity: `scripts/check-ui-copy.mjs` is not run in CI.
16. Engine error codes: 5 codes (`showdown-needs-board`, `stale-bot-plan`, `hero-bot-executor`, `no-eligible-player`, `bot-cannot-act`) have no `expectError` fixture step.
17. `session-scenarios.json` is not reference-derived (documented).
18. Android tablet: no tablet AVD; sizes are forced on a phone emulator.
19. Large text: no tablet or sheet coverage (both).
20. Release-build profiling: no Microbenchmark/Macrobenchmark or `XCTMetric` baselines in `docs/`.
21. CI has not run on `91611f4`; every "(UI test new; first CI run pending)" row needs that run.
22. iOS has no rendered activity row-count test (Android has `LaunchTest:40`).

Open WP-H items (`.gitignore` secrets are done in `91611f4`):

- Pin the iOS phone simulator to a compact model (iPhone SE or 16e) and add a large iPhone.
- Add an Android `pixel_tablet` AVD run of `AdaptiveLayoutTest` without forced sizes; optionally a second API level.
- Add `assembleRelease` (R8) and an iOS Release build to CI.
- Add the missing error-code fixture steps and regenerate with `--check`.
- Harden Android `applyDelta` in `EngineFixturesTest` (whole-array `logs`/`history` replacement, optional `snapshot`).
- Profiling baselines: hand evaluation, `analyzeDecision`, `botDecision`, startup, frame timing and cancellation latency, recorded in `docs/`.

Other open items: product sign-off on the "Zang Shunu" and "Boss Tan" romanizations (left unchanged in the fixtures).
