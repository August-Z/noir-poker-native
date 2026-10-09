# Bot styles, calibration and caveats

This document records the computer-opponent model that both native domain
layers implement (`BotProfiles.kt` / `BotProfiles.swift`, `BotTiming.kt` /
`BotTiming.swift`, `botDecision` in `Poker.kt` / `Poker.swift`). It is the
native counterpart of the pinned reference's `docs/bots.md`. The engine is
checked against shared fixtures (`fixtures/bot-profiles.json`,
`fixtures/bot-decisions.json`, `fixtures/mood.json`), and the calibration
numbers below are reproduced exactly by tests on both platforms.

## What the styles are, and what they are not

- The eight named styles are training archetypes. They are loose summaries of
  public hands and interviews. Their numbers are this project's training
  parameters. They are **not** the real players' VPIP, PFR or long-run
  statistics, they are not replicas of those players, and they are not GTO
  solutions. The supporting links for each style live in the profile data and
  appear in Opponent Styles.
- **Thinking time is synthetic.** Each pause is drawn by a context-pacing
  model (`context-pacing-v1`, 1.2–8 s). It does not measure or imitate any
  real player's speed or psychology.
- **A long pause never implies a bluff, and a quick action never implies
  strength.** Independent timing randomness, occasional quick actions and
  deliberate pauses make the pause ranges for value bets, bluffs, traps and
  folds overlap on purpose. No hand type is always fast or always slow.
- **Equity is estimated against random hands.** Bots sample equity against
  random legal opponent holdings, not against a player-specific range. It is a
  conservative whole-pot estimate in multiway and side-pot spots. Rules,
  eligibility and pot splitting are still handled exactly by the engine.
- Simulated moods are a separate synthetic mechanism. They are never
  attributed to a named player.

## Style parameters

The first five columns are 0–100 tendency scores. The sample size behind each
style is far too small to infer a real player's long-run frequencies from
these numbers.

| Style | Range Width | Aggression | Bluffing | Calling Down | Trapping | Typical postflop bet |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Balanced Practice | 50 | 50 | 40 | 50 | 20 | 45–80% of the pot |
| Boss Tan · Tan Xuan | 85 | 90 | 82 | 70 | 25 | 65–115% of the pot |
| ST Wang | 40 | 65 | 43 | 42 | 78 | 45–90% of the pot |
| Zang Shunu · Aaron Zang | 63 | 75 | 62 | 63 | 50 | 60–100% of the pot |
| Peter · HCL | 92 | 88 | 72 | 84 | 18 | 75–125% of the pot |
| A Bao · KPC | 55 | 82 | 72 | 50 | 34 | 50–100% of the pot |
| Viktor Blom | 90 | 94 | 88 | 70 | 18 | 70–125% of the pot |
| Daniel Cates | 65 | 82 | 66 | 64 | 72 | 45–95% of the pot |
| Tom Dwan | 85 | 90 | 85 | 75 | 55 | 65–120% of the pot |

- **Range Width** ranks all 1,326 starting holdings with a starting-hand
  heuristic. The base candidate share is `0.16 + width × 0.42`, then position,
  table size and earlier raises adjust it. It is not the observed VPIP: price,
  equity and later actions still filter the candidates.
- **Aggression** raises the mix probability when a value bet or bluff is
  available, and affects open sizes.
- **Bluffing** raises pure-bluff and semi-bluff mixes in suitable spots.
  Multiway pots suppress pure bluffs. A conditional probability is not an
  overall bluff rate.
- **Calling Down** nudges marginal call thresholds and the tendency to fold
  to large bets.
- **Trapping** adds slow-play only on safe boards, with high own equity and a
  free check available. Dangerous boards favor value and protection.
- **Bet sizing** is the usual postflop band, not a hard cap on every bet.
  Raises are clamped between the engine's legal minimum and maximum.

The observed VPIP and PFR shown in Opponent Styles count completed hands only.
VPIP is the share of hands with a voluntary preflop call or raise; PFR is the
share with at least one preflop raise. Forced blinds do not count. Replay
removes the overwritten sample, and changing a seat's style or starting a new
session resets it.

## Calibration (reference `measure:bots`)

The reference measures the bots with `npm run measure:bots`
(`scripts/measure-bots.mjs`). The native port is
`BotCalibrationTest` (Android, `android/core/src/test/kotlin/com/august/noirpoker/core/`)
and `BotCalibrationTests` (iOS, `ios/Packages/PokerCore/Tests/PokerCoreTests/`).
Both run the same scenario:

- 250 hands; policy random: the reference LCG seeded with 781; deck random: a
  separate LCG seeded with 711 (`startHand` shuffles with it);
- every seat, the hero included, uses the bot policy (`botDecision` then
  `act`); seats 1 and up use the measured style, emotions off;
- every stack is reset to 5,000 chips (100 BB) before each hand;
- VPIP and PFR count the bots only (seats 1 and up). Flop players are counted
  when the hand reaches the flop, before the flop is dealt; fold-win practice
  boards are not counted.

Documented results, reproduced exactly on both platforms:

| Table | Style | VPIP | PFR | Flops / 250 hands | Average flop players | 3+ player flops / 250 hands |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 6 seats | Balanced | 54.16% | 14.48% | 217 | 3.281 | 148 |
| 9 seats | Balanced | 45.95% | 12.60% | 192 | 3.859 | 141 |
| 6 seats | ST Wang | 50.32% | 16.48% | 216 | 3.065 | 139 |
| 6 seats | Peter · HCL | 71.12% | 22.08% | 214 | 3.621 | 144 |

The tests also assert the raw counts (samples, VPIP and PFR hands, flop-player
distribution, preflop re-raised hands) from the reference script's JSON
output. A second six-seat seed pair (policy seed 9182, deck seed 123) gives
3.337 average flop players and 138 three-plus-player flops, and is asserted
too.

For context, the reference documents the values before its cheap-entry
adjustment (engine v32): 6 seats 35.76% / 18.48% (119 flops, 2.487 average,
38 three-plus), 9 seats 29.75% / 14.15% (122 flops, 2.861 average, 51
three-plus). The native apps implement only the adjusted engine.

These numbers describe this simulation only. They are not real-player
frequencies and do not guarantee how many players see any given flop; no
policy forces players into a pot.

### Running and updating

- Android: `./gradlew -p android/core test --tests '*BotCalibrationTest*'`
  (about 15 s).
- iOS: `swift test --package-path ios/Packages/PokerCore --filter BotCalibrationTests`.
  This is the slowest test class in the package (about 3 minutes in a Linux
  debug build), because each measurement plays 250 hands with equity
  sampling.
- To get the reference values, run
  `node scripts/measure-bots.mjs --players=6 --profile=balanced` inside the
  pinned reference (`.reference/noir-poker`); add `--seed=9182 --deck-seed=123`
  for the second seed pair. Never copy the reference script into the apps.

Any intentional change to the bot policy, the shuffle, equity sampling or the
statistics counters changes these numbers. Update the shared fixtures from the
reference first, then this table and both tests together.

## Entry behavior

Preflop, the policy computes separate candidates for opening, continuing and
value re-raising. Widening the continuing range does not widen the value
re-raise range (`0.035 + width × 0.085`, adjusted for raise count and late
position), so marginal hands that enter do not turn into repeated 3-bets.

- **Unraised, at most one extra big blind to complete** (`affordable-entry`):
  the range grows by `0.14 + width × 0.20`, with a limited bonus for pairs,
  suited connectors and one-gappers, suited aces and suited high cards with
  a reasonable kicker when limpers are already in. The added investment is
  capped at 8% of the bot's own stack, so a short stack calling all in never
  counts as a cheap entry.
- **A single small open** (`affordable-open`): the open and the call are at
  most 4 BB, the call is at most 8% of the bot's stack, nobody is all in, and
  the effective stack after calling is at least `max(20 BB, 15 × call)`. The
  effective stack is the smaller of the bot's remaining stack and the
  opener's, never an unrelated deep stack. The big blind keeps its price
  advantage; weak offsuit aces get less help.
- **3-bets, multiple raises, large opens, all-ins or short effective stacks**
  get no entry exception; the original range, equity and pressure filters
  apply.

Tests on both platforms check the boundaries of these branches, that premium
hands can still 3-bet, and that over all 1,326 holdings facing a small open,
ST Wang continues less often than Balanced, which continues less often than
Peter.

## Information boundary

`botDecision` builds the actor's view: own hole cards, the board, public
betting history, positions, price, legal actions, own equity estimate and the
current style and mood. `chooseBotAction` receives only that view. It cannot
read other players' hidden cards, the remaining deck, review inputs or the
final winners. Tests on both platforms rewrite every rival hole, the deck, the
winners and the result for all nine styles and assert the decision does not
change.

The plan-then-execute flow (`planBotTurn` → wait → `executeBotTurn`) draws the
policy once; the wait never re-rolls the action. The planned time, the actual
wait and the expedited flag are written only to the opponent's private
execution record, and never grade the player's decisions. Session-level
scheduling and cancellation are described in `docs/SESSION.md`.
