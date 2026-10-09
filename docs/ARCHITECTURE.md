# Native architecture

This document records the structural decisions shared by the Android and iOS
apps. The behavior contract is `docs/MIGRATION.md`; the feature status is
`docs/PARITY.md`.

## Layers

| Layer | Android | iOS |
| --- | --- | --- |
| Domain (pure, no UI, no platform APIs) | `android/core` — standalone Kotlin/JVM Gradle build, package `com.august.noirpoker.core` | `ios/Packages/PokerCore` — Swift package, module `PokerCore` |
| Presentation state, scheduling, persistence adapters | `android/app` — `TableViewModel`, coroutines | `ios/NoirPoker` — `@MainActor` observable table model, Swift concurrency |
| UI | Jetpack Compose | SwiftUI |

`android/core` is an included build. It compiles and tests on any JVM without
the Android SDK:

```bash
./gradlew -p android/core test
docker run --rm -v "$PWD":/src -w /src/ios/Packages/PokerCore swift:6.1-noble swift test   # optional on Linux
swift test --package-path ios/Packages/PokerCore                                          # macOS
```

The two domain layers are written independently, one per language, and must
agree on every shared fixture in `fixtures/`. Neither app embeds a browser,
JavaScript runtime, or cross-platform UI layer.

## Mirroring the reference

The domain code mirrors the module and function boundaries of the pinned
reference (`src/engine/*.js`, `src/review/*.js`) so that each native function can
be traced to its source. Names are the same camelCase identifiers where the
language allows (`startHand`, `legalActions`, `act`, `advanceStreet`, `settle`,
`restartHand`, `partitionPots`, `currentPots`, `botDecision`, `planBotTurn`,
`executeBotTurn`, `analyzeDecision`, …). Data shapes are typed classes/structs
instead of untyped objects, with the same field names.

`Game` is a mutable reference type on both platforms (`class Game`), matching
the reference's in-place mutation. Snapshots that the reference produces with
`JSON.parse(JSON.stringify(...))` (replay baseline, decision snapshots, bot
records) are explicit deep copies. Engine-private data (replay baseline, bot
plans) is kept off the public state, as in the reference's `WeakMap`s: plans are
opaque handles validated against a per-game identity, hand number, replay
attempt, street, actor, history length, difficulty, stack, and current bet.

## Determinism and randomness

All randomness flows through one injected source:

- Kotlin: `fun interface RandomSource { fun next(): Double }`
- Swift: `protocol RandomSource: AnyObject { func next() -> Double }`

Each returns a value in `[0, 1)`, like `Math.random()`. Production uses a
system generator. Tests and fixtures use `SeededRandom`, an exact port of the
reference's `seedRandom` (Mulberry32, `src/review/equity.js`), operating on
32-bit unsigned integers with wrapping arithmetic.

Every function that consumes randomness in the reference consumes it from the
native source in exactly the same order and count. The fixture generator
replaces `Math.random` with a seeded Mulberry32 stream, so engine calls that use
the reference default (`shuffle` in `startHand`, `estimateEquity`, bot choices,
thinking time) all draw from one stream in call order. Native fixture tests pass
one `SeededRandom` with the same seed to the same calls in the same order.

Numeric rules that must match JavaScript:

- `Math.round(x)` is `floor(x + 0.5)` — not banker's rounding and not
  `rounded()` for negative halves.
- `Math.floor(random() * n)` selects indices.
- Integer chip amounts are 64-bit on Kotlin (`Int` is sufficient: totals are
  below 2^31) and `Int` on Swift.
- Number formatting for copy uses en-US grouping: `5,000`.
- `snapshotSeed` hashes a JSON string. Native code builds the identical JSON
  text (same key order, same card objects, `null`, booleans, integers) and hashes
  UTF-16 code units with FNV-1a using 32-bit wrapping multiplication.

## Copy

All product copy is English. Engine-generated text (action captions, activity
log entries, settlement results, mood events) is produced by the domain layer
and is part of the fixtures, so both platforms render identical strings. The
fixture generator translates the reference's Chinese engine output with a
single translation table (`scripts/reference-copy.mjs`); that table is the
authority for engine copy. UI-only copy is catalogued in `docs/COPY.md`.

## Fixtures

`fixtures/*.json` are generated from the pinned reference by
`node scripts/generate-reference-fixtures.mjs` and verified in CI with
`--check`. Fixture files are inputs to both native test suites; they must never
be bundled into the apps. Each file carries `referenceCommit`. The exception is
`fixtures/session-scenarios.json`: the reference table controller is DOM-bound,
so the table-session scenarios are hand-authored from the UI spec (see
`docs/SESSION.md`) and are not covered by `--check`.

## Concurrency and cancellation

- The engine is synchronous and single-threaded; only the table model mutates the
  live `Game`, on the main thread.
- Bot turns are planned synchronously (the decision is selected immediately),
  then a cancellable delay shows the synthetic thinking time; the same plan is
  executed when the delay ends. An `epoch` counter is incremented on Next Hand,
  Replay Hand, Start New Session, and when the app moves to the background;
  stale work checks the epoch and the plan's validity before acting.
- Review and counterfactual calculations run off the main thread
  (`Dispatchers.Default` / detached tasks) on immutable copies of review input,
  carry a job id, check for cancellation between decisions, and never write
  results into a newer hand.

## Android UI tests

Compose instrumented tests live in `android/app/src/androidTest` and run in CI
(`connectedDebugAndroidTest` on the emulator job). `NoirAppRobot` launches
`MainActivity` with debug-only intent extras read by `LaunchOptions`: a fixed
seed for the session's random stream, a private `SharedPreferences` file
(cleared at the first launch of a test, kept on relaunch), and a time scale for
`HandlerScheduler`, which runs the session clock and every delay faster without
changing the random draws. A release build ignores the extras. Tests read the
session's render state and `publicSnapshot()` on the main thread and use
`testHooks.fixture` for the reference's `heroTurn` setup (hero first to act).

- `HandFlowTest`: a hand to settlement with chip conservation, fold then Finish
  Hand, Replay Hand (same hole cards, result reversed once), Next Hand keeps the
  stacks, Start New Session resets the stats, reveal toggles after settlement
  cleared by the next hand.
- `SettingsPersistenceTest`: nine seats apply on the next hand and survive a
  relaunch.
- `SheetsTest`: Hand Review with both tabs; Opponent Styles discard and save.
- `AdaptiveLayoutTest`: the table composed at forced window sizes with
  `DeviceConfigurationOverride` (360 × 740 at nine seats, 390 × 844 at 2×
  font scale, tablet portrait 800 × 1280 and landscape 1280 × 800).
