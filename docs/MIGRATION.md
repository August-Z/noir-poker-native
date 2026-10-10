# Native migration contract

Reference repository: https://github.com/JessieZJZ/noir-poker

Reference commit: `03c78233f9454de54e378c5c81ba1dd25fa9b14e`.

The reference repository is no longer public (2026-10-10). The committed fixtures in `fixtures/` are now the source of truth; CI verifies them with `node scripts/check-fixtures.mjs`, and `generate-reference-fixtures.mjs` runs only where a local checkout of the pinned commit still exists. Where access exists, run `bash scripts/fetch-reference.sh` to obtain an ignored, read-only checkout under `.reference/noir-poker`. This does not create a GitHub fork. The reference is an input to development, not an application dependency. New product code and documentation are English; the original Chinese source stays outside the tracked product tree.

## Architecture

- `android/app`: Kotlin domain layer and Jetpack Compose UI.
- `ios/Packages/PokerCore`: native Swift domain library, independently testable with Swift Package Manager.
- `ios/NoirPoker`: SwiftUI UI and platform adapters.
- `fixtures`: shared deterministic JSON contracts for both native engines.

Implement the domain twice and use the same behavioral fixtures. No browser runtime, cross-platform UI, or JavaScript engine is part of the apps. Neither app needs a server, login, or live model API.

## Current implementation boundary

Both apps implement the playable table, the rules engine and settlement, bots and synthetic emotions, replay, decision review, and preferences, with separate Kotlin and Swift domain layers checked against the same fixtures. `docs/PARITY.md` records the status of each item below, the deliberate deviations, and the remaining gaps. Do not claim that migration is complete until every row there is verified.

## Behavior that must survive migration

1. Five to nine seats; six by default. All players start with 5,000 virtual chips, with blinds of 25/50. Broken stacks reload for the next practice hand. The button advances clockwise; SB and BB are the next two seats. Burn a card before each community street.
2. Three bot difficulty levels; every seat can have its own style. Preserve all nine IDs: balanced, tan, st, zang, peter, abao, viktor, jungleman, dwan. Retain the original calibrated parameters, research links, and actual simulated VPIP/PFR statistics. Named profiles are training archetypes, not measured real-player statistics.
3. Optional synthetic emotional states: steady, frustrated, cautious, confident, reactive. Preserve intensity, decay, cooldown, triggers, and the hand-start baseline used by replay.
4. Legal check/call/fold/raise, short all-in behavior, cumulative reopening of raises, all-in calling, side-pot eligibility, folded contributions, uncalled refunds, split pots, and odd chips awarded clockwise from the button. Preserve chip conservation and prohibit repeated settlement.
5. Keep each player's most recent action, amount, street, and bet level visible through runouts and settlement. Do not overwrite it with transient turn state or payout.
6. Show each showdown participant's own best five cards and highlight winners with the correct hand category. Show unfolded players' hole cards at showdown. After settlement, allow every opponent's hole cards to be revealed or hidden in that seat, including folded opponents. Clear visibility on next hand, replay, and reset.
7. Next Hand retains session stacks and stats. Replay Hand restores the exact original hole cards, deck order, positions, and starting stacks, reversing the prior payout and statistics exactly once. Start New Session resets the table and session stats while retaining preferences. Do not conflate these operations.
8. Finish Hand after the hero folds cancels waiting and consumes the already planned first bot decision, then uses the same legal action path to complete the hand. A practice runout after a fold-win shows remaining cards without mutating the settled board/deck/payouts or the evidence used in review.
9. Review each hero decision with information available before that action. Preserve hand/draw/board/position context, call-price calculation by eligible pot, opponent ranges, sampled equity, comparisons of legal alternatives, full-engine counterfactual simulation, uncertainty, main/alternative routes, and the separate explanation of executed bot decisions. Never use hidden opponent cards, the future deck, or final winners to judge the hero. Do not rename the heuristic model a GTO solver.
10. Retain complete chronological hand activity without fixed-height truncation. Save seat count, difficulty, opponent assignments, emotional intensity, hints, and sound. As in the original, preferences survive reopening; the live hand and session need not be persisted unless explicitly approved later.
11. Cancel stale scheduled bot and review work on the next hand, replay, reset, and lifecycle transitions. Review calculations must run away from the UI thread. Preserve the already selected bot action while displaying synthetic thinking time.

## Source map

| Original source | Native responsibilities |
| --- | --- |
| `src/engine/poker.js` | Rules, hand evaluation, dealing, betting, pots, payouts, replay, public snapshots |
| `src/engine/bot-profiles.js` | Style parameters, starting ranges, public-view decisions, emotion model |
| `src/engine/bot-timing.js` | Context-based synthetic thinking time, 1.2–8 seconds |
| `src/engine/action-labels.js` | Bet ordinals, legal raise terminology |
| `src/review/*.js` | Public-information review, equity, routes, counterfactual simulation, executed bot explanation |
| `src/ui/table-controller.js` | State-to-UI wiring, scheduling, actions, preferences, lifecycle boundaries |
| `src/ui/showdown.js`, `cards.js` | Card styling, best-five highlights, hand-category winner animation |
| `src/ui/review-controller.js`, `opponent-review.js` | Review presentation, cancellation, decision timeline |
| `src/ui/opponents-controller.js`, `preferences.js` | Settings, validation, persistence |
| `src/styles/*.css`, `index.html` | Visual reference and feature hierarchy; recreate with native views |
| `tests/unit/*.test.js`, `tests/e2e/table.spec.js` | Original acceptance behavior and boundary regression cases |

## Visual and language contract

Preserve the NOIR identity, dark navy panels, mint accents, green oval felt, card styling, seat hierarchy, betting controls, session statistics, coaching/review, and activity. Adapt spacing, safe areas, touch targets, scrolling, sheets, large text, and tablet layouts to native conventions. Do not replace the reference with a generic casino theme.

| Token | Color |
| --- | --- |
| Background | `#0B1017` |
| Panel | `#111923` |
| Border | `#25313D` |
| Muted text | `#8897A6` |
| Main text | `#EDF3F6` |
| Mint | `#6EE7C5` |
| Dark mint | `#153D36` |
| Purple | `#B4A2FF` |
| Red | `#E56F80` |
| Felt | `#14362F` |

Use English-only product copy. Prefer “Replay Hand”, “Next Hand”, “Start New Session”, “Finish Hand”, “Opponent Styles”, “Hand Review”, “Your Decisions”, “Opponent Decisions”, “Main Pot”, “Side Pot”, “All-In”, “Call”, “Check”, “Raise to”, “Fold”, and “How to Play”. Use conventional terminology: hole cards, community cards, flop, turn, river, pocket pair, set, trips, overpair, top pair, kicker, flush draw, straight draw, pot odds, equity, implied odds, check-raise, 3-bet, and 4-bet. Translate explanations accurately and naturally; do not mechanically copy Chinese syntax or silently weaken caveats.

## Verification gates

- Extend shared fixtures using the pinned original engine. Implement the same JSON expectations in Kotlin and Swift tests, especially short all-ins, reopening, multi-pot eligibility, refunds, odd chips, exact replay, stats rollback, and privacy boundaries.
- Keep the baseline original unit tests passing. Run `node scripts/generate-reference-fixtures.mjs --check` to verify the included hand-ranking fixtures.
- Compare seeded bot decisions/ranges/parameters and decision-review outputs, not just visual similarity.
- Run native device/simulator UI tests on compact and tablet sizes with six and nine seats. Test rotation, background/foreground, repeated replay, interrupted review, repeated settlement requests, and large text.
- Profile release builds before replacing languages or adding complex optimization. Measure hand evaluation, equity sampling, allocations, cancellation latency, and frame responsiveness on representative devices.
