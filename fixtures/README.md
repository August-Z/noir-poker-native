# Shared reference fixtures

Every file in this directory is generated from the pinned reference
(`.reference/noir-poker` at `referenceCommit`) by

```bash
node scripts/generate-reference-fixtures.mjs          # regenerate
node scripts/generate-reference-fixtures.mjs --check  # CI: every file must match byte for byte
```

Never edit these files by hand, and never bundle them into the apps. The Kotlin
(`android/core`) and Swift (`ios/Packages/PokerCore`) domain tests both read them
and must reproduce every value exactly.

## Conventions used by every file

- Each file has `referenceCommit`, `generator`, and `description` at the top.
- **Cards** are always serialized as their key string `"{suit}-{rank}"`, for
  example `"0-14"` is A♠. Suits: `0` ♠, `1` ♥, `2` ♣, `3` ♦. Ranks `2`–`14`
  (11 J, 12 Q, 13 K, 14 A). `symbol` is derived from the suit. `deckOfCards()`
  order is suit-major: `0-2 … 0-14, 1-2 … 3-14`.
- **Numbers** are JSON numbers. Chip amounts are integers. Non-integers are
  IEEE-754 doubles printed with the shortest round-trip representation; parse
  them as `Double` and compare with exact equality.
- **Randomness**: `SeededRandom(seed)` is Mulberry32, an exact port of the
  reference `seedRandom` in `src/review/equity.js` (see `rng.json`). Unless a
  file says otherwise, one stream per case feeds every engine call that uses
  the reference default `Math.random`, in call order.
- **Copy** is English. All engine strings were produced by the reference in
  Chinese and translated by `scripts/reference-copy.mjs`, which documents the
  English templates at the top and is the authority for engine copy. Summary:
  - Seat action text: `Fold`, `Check`, `Call 1,000`, `All-In 500`, `All-In`
    (street reset of an all-in player), `SB 25`, `BB 50`,
    `"{k}-bet {verb} {amount}"` with verbs `open to`, `raise to`, `bet to`,
    `all-in to`, `short all-in to` (e.g. `3-bet raise to 650`).
  - History `betLabel` is the caption without the amount (`2-bet open to`).
  - `actionLabel` all-in call: `All-In Call 1,000`.
  - All numbers use en-US grouping (`1,800`), including action captions.
  - The hero name is `You`. Bot names: Mia, Alex, River, Kai, Luna, Theo, Jade, Leo.
  - Logs: `Hand 3 begins · Button: Mia`; `Mia: SB 25 · Alex: BB 50`;
    `Mia: Call 100`; `Flop · A♠ K♥ 10♣`, `Turn · …`, `River · …`;
    `Mia rebuys 5,000 virtual chips` / `You rebuy 5,000 virtual chips`;
    `Hand 3 · Replay #1 · previous settlement reversed`;
    `Practice runout · all five community cards shown; the fold-win result is unchanged`;
    `Main Pot 1,400 → Mia 700 / Alex 700`; `Uncalled 300 chips returned to Mia`;
    `Mia simulated mood: Chasing Losses · Lost at least 25 BB net in a single hand`.
  - Result: optional `Split pots · ` prefix, then winners joined with ` / `:
    showdown `Mia wins 1,400 chips · Full House` (`You win …`), fold-win
    `Mia wins 125 chips`.
  - Hand labels: `High Card`, `One Pair`, `Two Pair`, `Three of a Kind`,
    `Straight`, `Flush`, `Full House`, `Four of a Kind`, `Straight Flush`,
    `Royal Flush`, and `Pocket Pair` (two-card evaluation). Fold-win award label:
    `All other players folded`. Pot labels: `Main Pot`, `Side Pot 1`, ….
  - Mood labels: steady `Steady`, frustrated `Chasing Losses`, cautious
    `Playing Safe`, confident `On a Heater`, reactive `Fighting Back`.
- **Error codes**: a thrown engine error is identified by a stable code. The
  English message for each code is in `engine-scenarios.json` → `errors`:

  | Code | Thrown by |
  | --- | --- |
  | `invalid-player-count` | `newGame` |
  | `settings-locked` | `applyBotSettings` outside `idle`/`done` |
  | `hand-in-progress` | `startHand` outside `idle`/`done` |
  | `replay-unavailable` | `restartHand` |
  | `not-your-turn` | `act` when `legalActions(g, id).enabled` is false |
  | `unknown-action` | `act` with an action other than fold/call/check/raise |
  | `cannot-check` | `act` check while facing a bet |
  | `illegal-raise` | `act` raise with an illegal amount |
  | `round-not-finished` | `advanceStreet` outside `between` |
  | `hand-not-settled` | `completeBoardForPractice` before `done` |
  | `showdown-needs-board` | `completeBoardForPractice` after a short-board showdown |
  | `already-settled` | `settle` after `done` |
  | `no-eligible-player`, `pot-mismatch` | `partitionPots` / `settle` invariants |
  | `invalid-trials` | `botDecision` with a non-positive trial count |
  | `bot-cannot-act` | `botDecision` / `chooseBotAction` without a legal actor |
  | `hero-bot-executor` | `planBotTurn` for seat 0 |
  | `stale-bot-plan` | `executeBotTurn` with an invalid plan |

## Shared object shapes

- **Legal actions** (`legalActions`): `{"enabled": false}` or
  `{enabled, toCall, callAmount, canCheck, raiseReopened, canRaise, minRaiseTo, fullRaiseTo, maxRaiseTo, isShortAllin}`.
- **Pot**: `{index, label, amount, eligible: [id], contributions: [{id, amount}], awards: [{id, amount, label}]}`.
  `awards` is empty until settlement. **Refund**: `{id, amount}`.
- **Winner**: `{id, name, amount, profit, label}`.
- **Log entry**: `{text, player, type, street}`; `player` is a seat id or `null`;
  `type` is `street | blind | action | info | result`. `logs` arrays are in
  engine order, **newest first**.
- **History entry**: `{street, id, action, amount}` plus `betLabel` for raises.
  `action` is the normalized action (`call` with nothing owed is `check`).
- **Mood**: `{kind, remaining, cooldown, reason, losses, wins, pressureFolds, lastPressureRaiser}`.
  `pressureFolds` maps a raiser seat id (as a JSON string key) to a count.
  `lastPressureRaiser` is `null` when absent or null in the reference (both
  behave identically).
- **Bot stats**: `{hands, vpip, pfr, postActions, postRaises, postCalls}`.
  **Bot hand flags**: `{vpip, pfr, pressureRecorded}`.
- **Hero decision snapshot** (`g.decisions[i]`, `step.decision`): exactly the
  object the reference `act` pushes for seat 0: `{index, hand, street, position,
  hole, board, stack, bet, total, pot, currentBet, minRaise, dealer,
  emotionMode, legal, pending, action, amount, players: [{id, name, position,
  stack, bet, total, folded, allin, action, botProfile, publicAxes,
  botMoodKind, actedTo, checked}], history}`. Hero rows have
  `botProfile`/`publicAxes`/`botMoodKind` = `null`.
- **Bot decision record** (`g.botDecisions[i]`, `step.botDecision`): the record
  `executeBotTurn` stores: `{id, name, hand, sequence, action, amount?, trace}`
  where `trace` is the full `chooseBotAction` trace plus `view` (the complete
  decision view, cards as keys) and `thinking`
  (`{durationMs, model, acting, factors, expedited, waitedMs}`).
  `amount` is absent for non-raises.

## `rng.json`

`cases[]`: `{seed, values}`: the first 20 outputs of `SeededRandom(seed)`.
Seeds include 0, 1, 42, 2^31−1, 2^31, 0xDEADBEEF and 2^32−1. Seeds are
interpreted as unsigned 32-bit integers.

## `hand-ranks.json`

Legacy smoke cases: `cases[]` `{name, cards: [{rank, suit}], score, bestCardKeys}`.

## `hand-eval.json`

- `cases[]`: `{name, cards, score, label, bestCardKeys}`; `evaluate(cards)`
  must return `score` (array of ints), the English `label`, and the best five
  cards in the reference order (`bestCardKeys`; for fewer than five cards this is
  the input). Includes the evaluator tests from the reference, 330 random 5/6/7
  card sets, and 0–4 card sets (the short-hand path, including `Pocket Pair`).
- `compare[]`: `{a, b, result}` with `result = compare(a, b)` in `{-1, 0, 1}`;
  missing elements count as 0.

## `engine-scenarios.json`

`errors`: map of error code → English message. `cases[]`:

| Field | Meaning |
| --- | --- |
| `name` | Reference test title (prefixed by its test file), or `random hand N`. |
| `seed` | Seed of the case stream `rng = SeededRandom(seed)`. |
| `playerCount` | `newGame(playerCount)`. |
| `initial` | Full snapshot right after `newGame`. |
| `steps[]` | Operations, in order, each with the snapshot delta after it. |

### Replay protocol

1. `rng = SeededRandom(seed)`; `g = newGame(playerCount)`; compare the full
   snapshot of `g` with `initial`.
2. For each step, perform `op`, then build the expected full snapshot by
   applying `step.snapshot` (a delta, below) to the previous expected snapshot
   and compare it with the native full snapshot. `query` steps have no snapshot.
3. If the step has `decision` / `botDecision`, compare it with the entry the
   step appended to `g.decisions` / `g.botDecisions`.

The generator asserts chip conservation after every non-patch step:
`Σ stack + (phase == done ? 0 : potSize)` stays constant, except that
`startHand` adds 5,000 per rebuy.

### Operations (`step.op`)

| op | Fields | Native call |
| --- | --- | --- |
| `patch` | `game`, `players` | Assign fields directly on the live game (below). Not an engine call. |
| `startHand` | `randomConstant?` | `startHand(g)` shuffling with `rng`; if `randomConstant` is present, shuffle with a source that always returns that value and leave `rng` untouched. |
| `act` | `id, action, amount?` | `act(g, id, action, amount)`. |
| `advanceStreet` | | `advanceStreet(g)`. |
| `settle` | `showdown` | `settle(g, showdown)`. |
| `restartHand` | | `restartHand(g)` (Replay Hand). Draws nothing. |
| `completeBoardForPractice` | | `completeBoardForPractice(g)`. |
| `applyBotSettings` | `settings` | `applyBotSettings(g, settings)`. |
| `botAct` | `result: {id, action, amount?, reason}` | `d = botDecision(g, rng)` (default trials), then `act(g, actor, d.action, d.amount)`. |
| `botTurn` | `result: {delayMs}` | `plan = planBotTurn(g, rng, timingRandom: rng)`; `executeBotTurn(g, plan, expedited: false, waitedMs: 0)`. |
| `expectError` | `step`, `error` | Run `step` (any op above, or `{op: "newGame", playerCount}`); it must throw `error` and leave the game (and `rng`) unchanged. |
| `query` | `fn`, `args`, `result` | Pure call; compare the return value. No snapshot. |

`act` steps may use the unknown action string `"bet"` inside `expectError`
(expected `unknown-action`).

Queries:

| fn | args | Call |
| --- | --- | --- |
| `partitionPots` | | `partitionPots(g)` → `{pots, refunds}` |
| `contestableAfterCall` | `id, amount` | `contestableAfterCall(g, id, amount)` |
| `legalActions` | `id` | `legalActions(g, id)` |
| `nextBetLevel` | | `nextBetLevel({street: g.street, history: g.history})` |
| `raiseLabel` | `amount` | `actionLabel({street, history, currentBet, minRaise of g, legal: legalActions(g), action: "raise", amount})` (no `stack`) |
| `historyActionLabel` | `index` | `historyActionLabel(g.history, index)` |
| `decisionActionLabel` | `index, action?, amount?` | `actionLabel(g.decisions[index], action ?? decision.action, amount ?? decision.amount)` |

### Patch semantics

`patch.game` assigns top-level game fields: `board`, `deck` and
`practiceBoard` are card-key arrays; `stats` is `{hands, wins, buyin}`; other
fields (`dealer`, `phase`, `street`, `currentBet`, `minRaise`, `pending`,
`actor`, `difficulty`) are plain values. `patch.players[]` is `{id, …fields}`;
each listed field is assigned on that seat (`hole` as card keys; `stack`,
`bet`, `total`, `folded`, `allin`, `actedTo`). Patches reproduce how the
reference tests set up games by mutating state; they bypass validation and do
not touch the private replay baseline.

### Full snapshot

| Field | Value |
| --- | --- |
| `hand`, `phase`, `street`, `dealer`, `actor` | Game fields (`phase`: `idle`/`playing`/`between`/`done`). |
| `pending` | Pending seat ids, in engine order. |
| `currentBet`, `minRaise` | Game fields. |
| `board` | Card keys. |
| `practiceBoard` | Card keys or `null`. |
| `deckSize` | `g.deck.length`. |
| `revealed`, `showdown` | Booleans (`showdown` is `false` before the first settlement). |
| `replayAttempt`, `potAtShowdown` | Integers (`0` before `startHand`). |
| `potSize` | `potSize(g)`. |
| `difficulty`, `emotionMode` | Game fields. |
| `canRestartHand` | `canRestartHand(g)`. |
| `positions` | `seatPosition(g, id)` for every seat. |
| `players[]` | `{id, name, stack, bet, total, folded, allin, actedTo, checked, action, lastAction, hole, botProfile, botMood, botStats, botHand}`; `lastAction` is `{text, street, bet}` or `null`. |
| `legal` | `legalActions(g)` for the current actor. |
| `currentPots` | `currentPots(g)` → `{pots, refunds}`. |
| `pots`, `refunds`, `payouts`, `winners`, `result` | Settlement fields (`[]` / `""` before settlement). |
| `stats` | `{hands, wins, buyin}`. |
| `history` | History entries (oldest first). |
| `logs` | Log entries (newest first). |
| `decisionCount`, `botDecisionCount` | Lengths of `g.decisions` / `g.botDecisions`. |
| `randomDraws` | Number of values drawn from `rng` so far (use it to localize RNG drift). |

### Snapshot delta (`step.snapshot`)

Only fields that changed since the previous snapshot are present:

- Any top-level field except `players`, `logs`, `history`: present means
  replace the whole value.
- `players`: array of partial seats `{id, …changedFields}`; replace each
  listed field of that seat (whole value, e.g. the whole `botMood`).
- `logsAdded`: entries to **prepend** to `logs` (already newest first). A `logs`
  field instead means replace the whole array (new hand, replay).
- `historyAdded`: entries to **append** to `history`. A `history` field means
  replace the whole array.

## `action-labels.json`

`cases[]`, by `fn`:

- `nextBetLevel`: `{step: {street, history?}, result}`.
- `raiseCaption`: `{step: {street, history, currentBet, minRaise?, legal?}, amount, result}`.
  `legal` may be partial (only `maxRaiseTo`); missing `legal.fullRaiseTo` falls
  back to `currentBet == 0 ? 50 : currentBet + (minRaise ?? 50)`.
- `actionLabel`: `{step, action?, amount?, result}`; `action`/`amount` default to
  `step.action`/`step.amount` when absent. `step` holds `street, history,
  currentBet, minRaise?, stack?, legal, action?, amount?`. Amounts are rounded
  with JS `Math.round` before formatting (one case uses `1234.5`).
- `historyActionLabel`: `{history, index, result}`, including legacy histories
  without `betLabel`.

## `bot-profiles.json`

- `profiles[]`: `{id, name, short, tag, description, axes, sizing, evidence, sources: [{label, url}]}`
  in reference order (index 0 `balanced` is the fallback). Display fields are
  English. These are training archetypes, not measured statistics of the
  named players.
- `axes`: the five axis labels. `emotionModes[]`: `{id, label}` in UI order.
  `moodLabels[]`: `{kind, label}`.
- `defaultBotSettings`, `freshBotMood`, `freshBotStats`, `botThinkLimits`.
- `sanitizeBotSettings[]`: `{input, output}`. `input` is arbitrary JSON (null,
  numbers, strings, arrays, objects with unknown modes or profile ids,
  out-of-range seats, inherited names such as `toString`); `output` is always
  `{emotionMode, assignments: {"1".."8": profileId}}`.
- `startingPercentile[]`: all 169 classes `{hand, hole, percentile}` (`AKs`,
  `AKo`, `AA`, …); `percentile = startingPercentile(hole)`.

## `mood.json`

`sequences[]`: `{name, steps}`. Start from `freshBotMood()` and apply each step
to the same mood object; after each step compare `result` and the full `mood`.

| op | Fields | Call / effect | `result` |
| --- | --- | --- | --- |
| `decay` | | `decayBotMood(mood)` | `null` |
| `pressureFold` | `raiser` (int or null), `mode` | `recordPressureFold(mood, raiser, mode)` | `{kind, reason}` or `null` |
| `finish` | `playerId, profit, mode` | `finishBotHand({id: playerId, botMood: mood}, profit, mode)` | `{kind, reason}` or `null` |
| `resetPressure` | `raiser` | `mood.pressureFolds[raiser] = 0` (what `act` does on a non-fold facing a raise) | `null` |
| `clearPressure` | | `pressureFolds = {}`, `lastPressureRaiser = null` (settlement without a pressure fold) | `null` |
| `axes` | `profile, mode` | `effectiveBotAxes(getBotProfile(profile), mood, mode)` | five doubles |

## `bot-decisions.json`

`cases[]`: one decision each.

| Field | Meaning |
| --- | --- |
| `state` | Declarative game (below). |
| `trials` | Optional explicit `trials` option for `botDecision`. |
| `decisionSeed` | `decision = botDecision(g, SeededRandom(decisionSeed), trials)`. |
| `decision` | `{action, amount?}`. |
| `trace` | The decision trace without `view` (all `chooseBotAction` fields: `reason, profile, profileName, mode, mood, axes, baseAxes, equityModel, trials, rawEquity, noise, equity, odds, pressure, percentile, range, openingRange, raiseRange, cheapEntry, cheapRangePassed, affordableOpen, affordableRangePassed, entryContext, premium, admitted, callTolerance, checks, exceptions, sizing, value, semiBluff, pureBluff, draw, playsBoard`). |
| `view` | The decision view without `hole`, `board` and `history` (those are in `state`): `id, street, position, count, inPosition, stack, bet, pot, currentBet, difficulty, legal, rivals, opponents, equity, equityTrials, contestable, features, playsBoard`. |
| `decisionDraws` | Values drawn from the decision stream (equity sampling, then policy). |
| `timingSeed`, `thinking` | `thinking = botThinkingTime(decision, SeededRandom(timingSeed))` using the complete decision (trace with view). |
| `timingDraws` | Values drawn from the timing stream. |

`state` (the GameState shape): `{hand, phase, street, dealer, actor, pending,
currentBet, minRaise, board, difficulty, emotionMode, replayAttempt, history,
players: [{id, name, stack, bet, total, folded, allin, actedTo, checked,
action, hole, botProfile, botMood}]}`. Build it with `newGame(players.length)`
and assign every listed field. The deck and other private data are absent: a
bot decision never reads them.

`errors[]`: `{state, trials?, error}`: `botDecision` on that state must throw.

## `simulations.json`

`cases[]`: `{name, seed, playerCount, settings, difficulty, stacks?, hands}`.
Protocol (one stream for everything):

```
rng = SeededRandom(seed)
g = newGame(playerCount); applyBotSettings(g, settings); g.difficulty = difficulty
if stacks: g.players[i].stack = stacks[i]
repeat hands.length times:
  startHand(g)                                   // shuffle draws from rng
  while g.phase != done:
    if phase == between: advanceStreet(g)
    else if actor == 0: d = botDecision(g, rng); act(g, 0, d.action, d.amount)
    else: plan = planBotTurn(g, rng, timingRandom: rng); executeBotTurn(g, plan)
```

Each `hands[]` entry: `hand`, `dealer`, `holes` (per seat), `stacksAtDeal`
(stack after rebuys, before blinds), `drawsAfterDeal`, `board`, `history`,
`actions[]` (`{id, action, amount?, reason, delayMs?, draws}`, `delayMs` for
bot seats only, `draws` = cumulative draws after that action), `showdown`,
`pots`, `refunds`, `payouts`, `winners`, `result`, `stacks`, `totalChips`,
`stats`, `botStats` (per seat), `moods` (per seat), `decisions` (count of hero
decision snapshots), `thinkingMs` (per bot action), `logs` (newest first),
`drawsAfterHand`. The generator asserts chip conservation after every action
and at settlement.
