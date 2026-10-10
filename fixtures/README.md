# Shared reference fixtures

Every file in this directory is generated from the pinned reference
(`.reference/noir-poker` at `referenceCommit`) by

```bash
node scripts/generate-reference-fixtures.mjs          # regenerate (needs a local reference checkout)
node scripts/check-fixtures.mjs                       # CI: parse, pin and checksum every file
```

The reference repository is no longer public, so these committed files are
the source of truth. `SHA256SUMS` covers every generated file; a deliberate
change updates its line in the same commit.

The one exception is `session-scenarios.json`, which is hand-authored and
recorded from the Kotlin session (see its section below) because the reference
table controller cannot run without a browser DOM; the generator neither writes
nor checks it, so it is not reference output.

Never edit the generated files by hand, and never bundle any fixture into the apps. The Kotlin
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
  | `bot-cannot-act` | `botDecision` / `chooseBotAction` (and so `planBotTurn`) without a legal actor |
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
| `name` | Reference test title (prefixed by its test file), `random hand N`, or `engine guards: …` for reference engine guards that no reference test throws (bot executor on the hero seat or with no legal actor, practice runout after a short-board showdown, a contested pot layer with only folded contributors). |
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
| `planBotTurn` | `result: {delayMs}` | `plan = planBotTurn(g, rng, timingRandom: rng)`; keep `plan` as the case's held plan. The game is unchanged. |
| `executeBotTurn` | | `executeBotTurn(g, heldPlan, expedited: false, waitedMs: 0)` with the plan from the last `planBotTurn` step. Draws nothing. |
| `expectError` | `step`, `error` | Run `step` (any op above, or `{op: "newGame", playerCount}`); it must throw `error` and leave the game, `rng` and the held plan unchanged. |
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
- A whole-array `logs` / `history` wins over `logsAdded` / `historyAdded` in the
  same delta, whatever the key order (the generator never emits both).
- Every non-`query` step carries a delta; harnesses treat a missing one as
  empty (the public snapshot must be unchanged).

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

## Review

Two files cover `src/review/*.js`: `review-decisions.json` (one case per hero
decision snapshot) and `review-hands.json` (one case per hand, plus privacy,
synthetic inputs, standalone explanations and errors). They are split because
together they exceed 7 MB. The expensive reference calls run on a worker pool
(`scripts/review-fixture-worker.mjs`); every review call is deterministic, so
the output does not depend on scheduling, and `Math.random` stays forbidden
while review code runs.

### Review copy

Review strings were produced by the reference in Chinese and translated by
`scripts/review-copy.mjs`, the authority for review copy (its header documents
the rules; the English baseline is the review copy catalog). Summary:

- The source concatenates sentence fragments; English joins the translated
  fragments with one space. Numbers are copied verbatim from the reference
  output, so they keep the reference formatters: grouped integers (`1,800`),
  integer percents (`34%`, `Math.round(x*100)+'%'`), one-decimal percents
  (`12.3%`, `-0.0%`, signed `+1.5%`, `toFixed(1)`), `toFixed(1)` ratios and
  SPR, `Math.round(x/50)` big blinds, ungrouped counts, and raw JS numbers for
  mood axes (`String(x)`).
- Counts use English singular for exactly 1, plural otherwise
  (`1 opponent`, `2 opponents`, `0 players`).
- Hand labels (`decisionContext.handLabel`) have a mid-sentence form and a
  start form. Start form (sentence start, after `": "`, and every standalone
  field value): engine hand names unchanged (`Two Pair`); templates
  capitalized (`Pocket Queens`, `A/7 suited`, `Q/7 offsuit`,
  `A hand that plays the board (hole cards add nothing)`, `A set of Nines`,
  `An overpair (Kings)` + optional `, on a paired board`,
  `Pocket Fives with an overcard on board`,
  `A board pair of Sevens, hole cards as kickers`,
  `Top pair (K) with an 8 kicker`, `Second-or-lower pair (9) with a Q kicker`).
  Mid form: the same with a lowercase first letter, and engine names as
  `high card`, `one pair`, `two pair`, `three of a kind`, `a straight`,
  `a flush`, `a full house`, `four of a kind`, `a straight flush`,
  `a royal flush`. Plural rank words: Twos … Tens, Jacks, Queens, Kings, Aces;
  `an` before 8 and A kickers.
- Board texture labels (`boardTexture.label`): tags `trips on board`,
  `paired`, `four to a flush`, `three to a flush`, `two-tone`,
  `four to a straight`, `clearly straight-connected`, joined with `", "`, or
  `rainbow and disconnected`. Preflop labels (`preflopContext.label`):
  `unopened pot`, `unraised, with limpers`, `facing an open`,
  `open with callers`, `facing a 3-bet`, `facing a 4-bet or more`. Both are
  lowercase mid-sentence and capitalized at a sentence start, after `": "`,
  and as standalone field values (`"Paired, three to a flush"`).
- The reference quirk `公共牌公共牌有对子` ("board" + "paired board") is
  rendered once: `on a board that's paired`. The preflop check fallback says
  `on a board that's rainbow and disconnected`, as in the source.
- Action labels inside review copy (`label`, `alternativeLabel`, summaries,
  `Simulation pick: …`) use the engine action copy (`Fold`, `Check`,
  `Call 125`, `All-In Call 25`, `2-bet open to 150`, `1-bet bet to 575`).
- Caveats are kept: candidate sizes are practice lines, not GTO; equities are
  estimates under assumed ranges with sampling error; completion cards are
  not guaranteed winners; outcomes never grade decisions; bot explanations
  describe the simulator, not real player psychology.

`review-hands.json` → `tables`: `streetNames` (`STREET_NAMES`),
`botReasonNames` and `botCheckNames` (code → English, `BOT_REASON_NAMES` /
`BOT_CHECK_NAMES`). `errors`: review error code → English message.

| Code | Thrown by |
| --- | --- |
| `review-not-ready` | `createReviewInput` before `done` |
| `invalid-review-trials` | `analyzeDecision` with a non-positive or non-integer `trials` |
| `invalid-simulation-trials` | `compareCandidateActions` with `trials` < 2 or non-integer |
| `simulation-runaway` | `compareCandidateActions` after more than 400 actions (never reached) |

### Snapshots

`snapshot` is a hero decision snapshot (shape above, cards as keys, copy in
English). Snapshots from seeded hands are complete. Snapshots built by the
reference unit tests are partial, exactly as the tests build them: they may
lack `dealer`, `emotionMode`, `players[].actedTo/checked/botProfile/...`, may
have 2 players, and `players[].action` may be `Bet 200`. A snapshot without an
integer `dealer`, or with any player lacking `actedTo`, runs no simulation
(`simulation: null`); native code must accept these partial snapshots.
Absent keys in any output mean `undefined` in the reference (for example
`decisionContext.facingRaise`, `preflopContext.lastRaiser`).

### `review-decisions.json`

`cases[]`, one per decision:

| Field | Meaning |
| --- | --- |
| `name` | Case name; hand decisions are `"{hand name} · decision k"`, others name the reference test. |
| `hand` | Index into `review-hands.json` → `hands`, or `null` for standalone snapshots. |
| `snapshot` | The decision snapshot `s`. |
| `startingTier` | `startingTier(s.hole)`. |
| `drawInfo` | `drawInfo(s.hole, s.board)` = `{flush, straight, flushOuts, straightOuts, outs, nextChance}`. |
| `boardTexture` | `boardTexture(s.board)` = `{paired, trips, maxSuit, connected, wet, label}`. |
| `decisionContext` | `decisionContext(s)` = `{made: {score, cards, label}, texture, draw, opponents, handClass, handLabel, inPosition, pendingOthers, effective, spr, extra, betRatio, preflopRaises, facingRaise?, pastCalls, pastCallActions, nutFlushBlocker, missedDraw, tier}` (`made.cards` as keys, `facingRaise` a history entry). |
| `preflopContext` | `preflopContext(s)` on every snapshot (the reference uses it preflop only; it is defined on any street): `{raises, limpers, callersAfterOpen, late, unopened, ace, kicker, suited, weakAce, ownOpen, lastRaiser?, openTo, ratio, openingCandidate, label}`. |
| `snapshotSeed` | `snapshotSeed(s)` (unsigned 32-bit). |
| `callPrice` | `callPrice(s)` = `{pots, contestable, cost, refundBefore, refundAfter, required, closing}`; `pots` are the projected partition pots the hero is eligible for, in the Pot shape above (`awards` empty). |
| `rangeWeight[]` | `{opponent, pair, weight}`: `rangeWeight(pair, s, s.players[opponent])` for every live opponent and eight pairs (AA, AKs, QJs, 72o resolved to unseen cards, plus four seeded random unseen pairs); reference-test cases first list the test's own pair. |
| `sampleValue[]` | `{trials, weighted, result}`: `sampleValue(s, callPrice(s), trials, weighted)` for trials 600 (the analyze default) and 25, unweighted and weighted. `result` = `{equity, margin, ev, method?, samples?}` (`{equity:0, margin:0, ev:0}` when nothing is contestable; `method` is `enumeration` on a heads-up river, else `sampling`). |
| `candidateActions[]` | `{alternatives, result}`: `candidateActions(s, alternatives)` with `[]`, with `[analyzeDecision(s).alternative, analyzeDecision(s).routes.secondary]` (`null` allowed), and for one reference-test case `[{raise 5000}]`. |
| `comparisonRoutes[]` | `{args: {code, status, alternative, withPreflopContext}, result}`: `comparisonRoutes(s, decisionContext(s), {code, status, alternative, pre})` with `pre = withPreflopContext ? preflopContext(s) : null`. The first entry uses the pre-simulation arguments of `analyzeDecision` (equal to `analyzeDecision.noSimulation.routes`); every third case adds a matrix of route codes × the first four candidate actions with `status: "sound"`. |
| `compareCandidateActions[]` | `{alternatives, trials, result}`: `compareCandidateActions(s, alternatives, {trials})`. Only for snapshots that simulate. Every other hand decision (and a few test cases) has the default (`alternatives: []`, `trials: 40`); every simulating case has `trials: 4` with the no-simulation alternative and secondary. `result` = `{rows: [{action: {action, amount}, scenarios: [{name, ev, margin, immediateFoldWin}]}], trials, policyTrials, best, stable, method, note}`; scenario names `Random range`, `Public-action-weighted range`. |
| `analyzeDecision.default` | `analyzeDecision(s)` (trials 600, rolloutTrials 40), full output: `{index, status, code, title, reason, lesson, plan, confidence, evidence, alternative, alternativeLabel, routes: {primary, secondary}, recommendation, simulation, metrics, draw, context}`. |
| `analyzeDecision.reduced` | `{options: {trials: 60}, result}` (rolloutTrials 12). |
| `analyzeDecision.noSimulation` | `analyzeDecision(s without dealer)`: the legacy-snapshot path, `simulation: null`. |
| `analyzeDecision.test` | Reference-test cases only: `{options, result}` with the trials the test uses (120, 100 or 10). |

### `review-hands.json`

`hands[]`: 44 seeded hands (5–9 seats; bots, scripted, or mixed opponents;
3-bets, 4-bets, short all-ins, multiway side pots, free checks and folds on
every street) plus the reference `settled bot traces` hand.

| Field | Meaning |
| --- | --- |
| `name`, `seed`, `playerCount` | Description only; natives need not replay the hand. |
| `input` | `createReviewInput(g)` after settlement: `{hand, hole, decisions, opponents, outcome: {profit, paid, returned, folded, wonPot, board, pots: [{label, amount, eligible: [name], awards: [{name, amount, label}]}], result}}`. `opponents` are the executed bot records (`g.botDecisions`, shape above). |
| `decisions` | Indices into `review-decisions.json` → `cases`, one per `input.decisions[i]` (same snapshot). |
| `analyzeReview` | `{options: {}, summary}`: `analyzeReview(input)` without `steps`; `steps[i]` is `cases[decisions[i]].analyzeDecision.default`. `summary` = `{priorityIndex, attention, consider, themes, title, summary}`. |
| `analyzeReviewReduced` | Same with `{trials: 60}`; steps are the `reduced` results. |
| `explainOpponent[]` | `explainOpponent(input.opponents[i])` = `{title, detail, reasons, made, warning}` for every bot record. |

`privacy[]`: `{name, options, variants: [inputA, inputB], result}`. Both
variants have identical `decisions` (the same public snapshots) but different
hidden opponent cards, future deck, bot records, winners and outcome
(variant B replays A's actions with every card the hero had not seen
permuted). `analyzeReview(variant, options)` must equal `result` (full output
including `steps`) for both variants.

`reviewInputs[]`: `{name, input, options, result}` from the reference review
tests (outcome-independence and the blind-only loss): `analyzeReview(input,
options)` must equal `result` (full output).

`explainOpponent[]`: `{name, record, result}` for the reference test's
synthetic record (a partial `view`).

`errorCases[]`: `{name, fn, decision?, options?, error}`. `createReviewInput`
on a game in `playing` phase; `analyzeDecision` / `compareCandidateActions`
with `options` on `review-decisions.json` case `decision`.

## `session-scenarios.json`

Hand-authored table-session scenarios, consumed by
`android/core/.../session/SessionScenarioFixtureTest.kt` and
`ios/Packages/PokerCore/Tests/PokerCoreTests/Session/SessionScenarioFixtureTests.swift`.
The reference `src/ui/table-controller.js` binds to the page on import, so the
values come from the UI behavior spec and the copy catalog, not from the
generator; `referenceCommit` records the reference version the spec describes.
Each scenario has `name`, `seed` (one `SeededRandom` stream for the whole
scenario), optional `storage` (initial key-value pairs) and `reviewRunner`
(`true` installs a fake runner that completes on `completeReview`), and
`steps`. A step is either a command (`do`, its arguments, and an optional
`returns` boolean) or an `expect` excerpt that is compared partially: objects
check only the listed keys, arrays check their length and every element, and
numbers compare numerically. The commands and the projected fields are
documented in `docs/SESSION.md` → "Shared session fixture".

### Provenance

This file is **not** generated from the reference, and it is not reference
output. It was written in two steps:

1. The scenarios (commands and which fields to check) were written by hand
   from the UI behavior spec and the English copy catalog.
2. The expected values were recorded from the Kotlin `TableSession` with
   `NOIR_SESSION_RECORD=/tmp/dump.json ./gradlew -p android/core test --tests
   '*SessionScenarioFixtureTest*'`, then checked by hand against the spec and
   the copy catalog before they were added. The Swift suite must pass on the
   same file unchanged, which makes the two native sessions agree with each
   other. It does not by itself prove that they agree with the reference.

Only these timing constants were cross-checked directly against the reference
source at `referenceCommit`:

| Constant | Value | Reference source |
| --- | --- | --- |
| Street advance delay | 1,000 ms | `src/ui/table-controller.js` `schedule()`: `game.board.length === 5 ? 850 : 1000` |
| Settlement delay after river betting | 850 ms | same expression |
| Bot thinking time bounds | 1,200–8,000 ms | `src/engine/bot-timing.js` `BOT_THINK_LIMITS = { minimum: 1200, maximum: 8000 }` |
| Bot deadline | `startedAt + plan.delayMs` | `src/ui/table-controller.js` `schedule()` |
| Finish Hand step | 0 ms per step | `src/ui/table-controller.js` `continueDeal()` (`setTimeout(resolve, 0)`) |

The thinking-time draws themselves come from the engine and are covered by the
generated `bot-decisions.json`. Behavior that intentionally differs from the
reference, such as cancelling the review at Next Hand and carrying the elapsed
bot wait across a background transition, is described in `docs/SESSION.md`.
The scenario "background cancels bot timers and the foreground resumes the same
plan for the rest of its delay" records the native background behavior, not the
reference's (the reference has no background handling).
