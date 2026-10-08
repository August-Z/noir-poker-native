// Generates the shared native fixtures in fixtures/ from the pinned reference.
//
//   node scripts/generate-reference-fixtures.mjs           # write fixtures
//   node scripts/generate-reference-fixtures.mjs --check   # verify every fixture file
//
// Every engine call that uses the reference default randomness runs with a
// seeded Mulberry32 stream (identical to src/review/equity.js seedRandom)
// installed as Math.random. Between fixture cases Math.random throws, so no
// unseeded randomness can leak into a fixture. Engine copy is translated into
// English by scripts/reference-copy.mjs and review copy by
// scripts/review-copy.mjs; both throw on any untranslated text. The review
// fixtures run the expensive reference review calls on a worker pool
// (scripts/review-fixture-worker.mjs), so a full run takes a few minutes.
// The schema of every file is documented in fixtures/README.md.
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { writeFileSync, readFileSync, mkdirSync, existsSync } from 'node:fs';
import { translate, translateDeep } from './reference-copy.mjs';
import { translateReview, translateReviewDeep, reviewErrorCode, REVIEW_ERRORS, untranslated, usedCopy, copySources } from './review-copy.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const referenceRoot = resolve(process.env.NOIR_REFERENCE_DIR || resolve(root, '.reference/noir-poker'));
const { evaluate } = await import(pathToFileURL(resolve(referenceRoot, 'src/engine/poker.js')));
const cases = [
  { name: 'ace_low_straight', cards: [[14,0],[2,1],[3,2],[4,3],[5,0],[13,1],[12,2]] },
  { name: 'royal_flush', cards: [[10,0],[11,0],[12,0],[13,0],[14,0],[2,1],[3,2]] },
  { name: 'full_house_uses_higher_trips', cards: [[14,0],[14,1],[14,2],[13,0],[13,1],[13,2],[2,3]] },
  { name: 'four_of_a_kind_kicker', cards: [[9,0],[9,1],[9,2],[9,3],[14,0],[13,1],[12,2]] },
  { name: 'two_pair_kicker', cards: [[14,0],[14,1],[13,0],[13,1],[12,0],[11,1],[2,2]] },
  { name: 'flush_takes_best_five', cards: [[14,1],[12,1],[9,1],[7,1],[4,1],[2,1],[13,2]] },
];
const REFERENCE_COMMIT = '03c78233f9454de54e378c5c81ba1dd25fa9b14e';
const fixtures = { referenceCommit: REFERENCE_COMMIT, cases: cases.map(item => {
  const cards = item.cards.map(([rank,suit]) => ({rank,suit,symbol:['♠','♥','♣','♦'][suit],key:`${suit}-${rank}`}));
  const result = evaluate(cards);
  return {name:item.name,cards:cards.map(({rank,suit})=>({rank,suit})),score:result.score,bestCardKeys:result.cards.map(card=>card.key)};
}) };
const outputs = new Map();
outputs.set('hand-ranks.json', JSON.stringify(fixtures, null, 2) + '\n');

// ---------------------------------------------------------------------------
// Reference modules
// ---------------------------------------------------------------------------
const load = (path) => import(pathToFileURL(resolve(referenceRoot, path)));
const poker = await load('src/engine/poker.js');
const bots = await load('src/engine/bot-profiles.js');
const timing = await load('src/engine/bot-timing.js');
const labels = await load('src/engine/action-labels.js');
const { seedRandom } = await load('src/review/equity.js');

// ---------------------------------------------------------------------------
// Randomness
// ---------------------------------------------------------------------------
const nativeRandom = Math.random;
const forbiddenRandom = () => {
  throw Error('Unseeded Math.random use during fixture generation.');
};
Math.random = forbiddenRandom;

// Exact copy of src/review/equity.js seedRandom (Mulberry32).
function mulberry32(seed) {
  let value = seed >>> 0;
  return () => {
    value += 0x6d2b79f5;
    let x = value;
    x = Math.imul(x ^ (x >>> 15), x | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}
function counted(source) {
  const f = () => {
    f.draws++;
    return source();
  };
  f.draws = 0;
  return f;
}
// Installs a fresh seeded stream as Math.random and returns it.
function useSeed(seed) {
  const stream = counted(mulberry32(seed));
  Math.random = stream;
  return stream;
}
function withRandom(random, body) {
  const previous = Math.random;
  Math.random = random;
  try {
    return body();
  } finally {
    Math.random = previous;
  }
}
// Generator-only stream for scripted choices; natives never need it.
const scriptStream = (seed) => mulberry32((seed ^ 0x5bd1e995) >>> 0);
const pick = (r, list) => list[Math.floor(r() * list.length)];
const intBetween = (r, lo, hi) => lo + Math.floor(r() * (hi - lo + 1));

// ---------------------------------------------------------------------------
// Cards and plain-data helpers
// ---------------------------------------------------------------------------
const DECK = poker.deckOfCards();
const CARD_BY_KEY = new Map(DECK.map((c) => [c.key, c]));
const card = (key) => {
  const c = CARD_BY_KEY.get(key);
  if (!c) throw Error(`Unknown card key ${key}`);
  return { ...c };
};
// "As Kh" -> ['0-14', '1-13'] (suits s h c d = 0 1 2 3, ranks 2..14).
const parseKeys = (s) =>
  s.split(' ').map((v) => {
    const rank = '23456789TJQKA'.indexOf(v[0]) + 2,
      suit = 'shcd'.indexOf(v[1]);
    if (rank < 2 || suit < 0) throw Error(`Bad card ${v}`);
    return `${suit}-${rank}`;
  });
const keysOf = (cards) => cards.map((c) => c.key);
const isCard = (v) =>
  v && typeof v === 'object' && !Array.isArray(v) && 'rank' in v && 'suit' in v && 'key' in v && 'symbol' in v;
// Deep plain copy with every card object replaced by its key.
function plain(value) {
  if (value === undefined) return undefined;
  if (isCard(value)) return value.key;
  if (Array.isArray(value)) return value.map((v) => (v === undefined ? null : plain(v)));
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) if (v !== undefined) out[k] = plain(v);
    return out;
  }
  return value;
}
const jsonCopy = (v) => JSON.parse(JSON.stringify(v));
const wealth = (g) =>
  g.players.reduce((s, p) => s + p.stack, 0) + (g.phase === 'done' ? 0 : poker.potSize(g));

const ERROR_CODES = {
  '牌桌人数须为 5–9 人。': 'invalid-player-count',
  '对手设置在下一手开始时生效。': 'settings-locked',
  '当前牌局尚未结束。': 'hand-in-progress',
  '请在本手结束后重打；需要本手的原始发牌记录。': 'replay-unavailable',
  '还没有轮到你行动。': 'not-your-turn',
  '未知的牌桌行动。': 'unknown-action',
  '当前需要跟注，不能过牌。': 'cannot-check',
  '请选择合法的加注总额。': 'illegal-raise',
  '本轮行动尚未结束。': 'round-not-finished',
  '请先完成本手结算。': 'hand-not-settled',
  '摊牌结算需要完整公共牌。': 'showdown-needs-board',
  '这手牌已经结算。': 'already-settled',
  '底池没有符合条件的玩家。': 'no-eligible-player',
  '底池分配金额不一致。': 'pot-mismatch',
  '权益抽样次数必须为正整数。': 'invalid-trials',
  '机器人当前不能行动。': 'bot-cannot-act',
  '玩家行动不能使用机器人执行器。': 'hero-bot-executor',
  '机器人行动计划已过期。': 'stale-bot-plan',
};
const errorCode = (e) => {
  const code = ERROR_CODES[e?.message];
  if (!code) throw e;
  return code;
};

// ---------------------------------------------------------------------------
// Public snapshots
// ---------------------------------------------------------------------------
const moodOut = (m) => ({
  kind: m.kind,
  remaining: m.remaining,
  cooldown: m.cooldown,
  reason: m.reason,
  losses: m.losses,
  wins: m.wins,
  pressureFolds: { ...m.pressureFolds },
  lastPressureRaiser: m.lastPressureRaiser ?? null,
});
const playerOut = (p) => ({
  id: p.id,
  name: p.name,
  stack: p.stack,
  bet: p.bet,
  total: p.total,
  folded: p.folded,
  allin: p.allin,
  actedTo: p.actedTo,
  checked: p.checked,
  action: p.action,
  lastAction: p.lastAction ? { ...p.lastAction } : null,
  hole: keysOf(p.hole),
  botProfile: p.botProfile,
  botMood: moodOut(p.botMood),
  botStats: { ...p.botStats },
  botHand: { ...p.botHand },
});
const potsOut = ({ pots, refunds }) => ({ pots: plain(pots), refunds: plain(refunds) });
function snapshot(g, stream) {
  return plain({
    hand: g.hand,
    phase: g.phase,
    street: g.street,
    dealer: g.dealer,
    actor: g.actor,
    pending: [...g.pending],
    currentBet: g.currentBet,
    minRaise: g.minRaise,
    board: keysOf(g.board),
    practiceBoard: g.practiceBoard ? keysOf(g.practiceBoard) : null,
    deckSize: g.deck.length,
    revealed: !!g.revealed,
    showdown: !!g.showdown,
    replayAttempt: g.replayAttempt ?? 0,
    potAtShowdown: g.potAtShowdown ?? 0,
    potSize: poker.potSize(g),
    difficulty: g.difficulty,
    emotionMode: g.emotionMode,
    canRestartHand: poker.canRestartHand(g),
    positions: g.players.map((p) => poker.seatPosition(g, p.id)),
    players: g.players.map(playerOut),
    legal: poker.legalActions(g),
    currentPots: potsOut(poker.currentPots(g)),
    pots: g.pots,
    refunds: g.refunds,
    payouts: g.payouts,
    winners: g.winners,
    result: g.result ?? '',
    stats: { ...g.stats },
    history: g.history ?? [],
    logs: g.logs,
    decisionCount: (g.decisions ?? []).length,
    botDecisionCount: (g.botDecisions ?? []).length,
    randomDraws: stream ? stream.draws : 0,
  });
}

// Declarative game patch: card fields use keys, everything else is copied.
const GAME_CARD_FIELDS = new Set(['board', 'deck', 'practiceBoard']);
function applyPatch(g, spec) {
  for (const [k, v] of Object.entries(spec.game ?? {}))
    g[k] = GAME_CARD_FIELDS.has(k) && v !== null ? v.map(card) : jsonCopy(v);
  for (const entry of spec.players ?? []) {
    const p = g.players[entry.id];
    for (const [k, v] of Object.entries(entry))
      if (k !== 'id') p[k] = k === 'hole' ? v.map(card) : jsonCopy(v);
  }
}

// ---------------------------------------------------------------------------
// Scripted engine scenarios
// ---------------------------------------------------------------------------
class Scenario {
  constructor(name, { playerCount = 6, seed }) {
    this.stream = useSeed(seed);
    this.g = poker.newGame(playerCount);
    this.expected = wealth(this.g);
    this.full = snapshot(this.g, this.stream);
    this.data = { name, seed, playerCount, initial: this.full, steps: [] };
  }
  // Snapshot delta against the previous full snapshot (see fixtures/README.md).
  delta(next) {
    const prev = this.full,
      out = {},
      same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
    for (const k of Object.keys(next)) {
      if (k === 'players') {
        const players = [];
        next.players.forEach((p, i) => {
          const changed = {};
          for (const f of Object.keys(p)) if (!same(p[f], prev.players[i][f])) changed[f] = p[f];
          if (Object.keys(changed).length) players.push({ id: p.id, ...changed });
        });
        if (players.length) out.players = players;
      } else if (k === 'logs' || k === 'history') {
        const added = next[k].length - prev[k].length;
        const kept = k === 'logs' ? next[k].slice(added) : next[k].slice(0, prev[k].length);
        if (added >= 0 && same(kept, prev[k])) {
          if (added > 0) out[k + 'Added'] = k === 'logs' ? next[k].slice(0, added) : next[k].slice(prev[k].length);
        } else out[k] = next[k];
      } else if (!same(next[k], prev[k])) out[k] = next[k];
    }
    this.full = next;
    return out;
  }
  record(op, body) {
    const g = this.g,
      decisions = (g.decisions ?? []).length,
      botDecisions = (g.botDecisions ?? []).length,
      hand = g.hand,
      attempt = g.replayAttempt;
    const result = body();
    const step = { ...op };
    if (result !== undefined) step.result = result;
    if (g.hand === hand && g.replayAttempt === attempt) {
      if ((g.decisions ?? []).length > decisions) step.decision = g.decisions.at(-1);
      if ((g.botDecisions ?? []).length > botDecisions) step.botDecision = g.botDecisions.at(-1);
    }
    step.snapshot = this.delta(snapshot(g, this.stream));
    this.data.steps.push(plain(step));
    if (op.op === 'patch') this.expected = wealth(g);
    else if (wealth(g) !== this.expected)
      throw Error(`${this.data.name}: chip conservation failed after ${op.op}`);
    return result;
  }
  patch(spec) {
    return this.record({ op: 'patch', ...spec }, () => applyPatch(this.g, spec));
  }
  startHand({ randomConstant } = {}) {
    const g = this.g;
    if (['idle', 'done'].includes(g.phase))
      this.expected = wealth(g) + 5000 * g.players.filter((p) => p.stack === 0).length;
    const op = { op: 'startHand', ...(randomConstant === undefined ? {} : { randomConstant }) };
    return this.record(op, () => {
      if (randomConstant === undefined) poker.startHand(g);
      else withRandom(() => randomConstant, () => poker.startHand(g));
    });
  }
  act(id, action, amount) {
    return this.record({ op: 'act', id, action, ...(amount === undefined ? {} : { amount }) }, () => {
      poker.act(this.g, id, action, amount);
    });
  }
  advanceStreet() {
    return this.record({ op: 'advanceStreet' }, () => {
      poker.advanceStreet(this.g);
    });
  }
  settle(showdown = true) {
    return this.record({ op: 'settle', showdown }, () => {
      poker.settle(this.g, showdown);
    });
  }
  restartHand() {
    return this.record({ op: 'restartHand' }, () => {
      poker.restartHand(this.g);
    });
  }
  completeBoardForPractice() {
    return this.record({ op: 'completeBoardForPractice' }, () => {
      poker.completeBoardForPractice(this.g);
    });
  }
  applyBotSettings(settings) {
    return this.record({ op: 'applyBotSettings', settings }, () => {
      poker.applyBotSettings(this.g, settings);
    });
  }
  // botDecision(g) on the case stream, then act with its choice.
  botAct() {
    return this.record({ op: 'botAct' }, () => {
      const id = this.g.actor,
        d = poker.botDecision(this.g);
      poker.act(this.g, id, d.action, d.amount);
      return { id, action: d.action, ...(d.amount === undefined ? {} : { amount: d.amount }), reason: d.trace.reason };
    });
  }
  // planBotTurn(g) (decision then timing, both on the case stream), then executeBotTurn.
  botTurn() {
    return this.record({ op: 'botTurn' }, () => {
      const plan = poker.planBotTurn(this.g);
      poker.executeBotTurn(this.g, plan);
      return { delayMs: plan.delayMs };
    });
  }
  // Runs one of the ops above and requires the reference to throw without
  // changing state.
  expectError(op) {
    const g = this.g,
      before = JSON.stringify(g),
      draws = this.stream.draws;
    let code = null;
    try {
      if (op.op === 'newGame') poker.newGame(op.playerCount);
      else if (op.op === 'act') poker.act(g, op.id, op.action, op.amount);
      else if (op.op === 'advanceStreet') poker.advanceStreet(g);
      else if (op.op === 'settle') poker.settle(g, op.showdown ?? true);
      else if (op.op === 'restartHand') poker.restartHand(g);
      else if (op.op === 'startHand') poker.startHand(g);
      else if (op.op === 'completeBoardForPractice') poker.completeBoardForPractice(g);
      else if (op.op === 'applyBotSettings') poker.applyBotSettings(g, op.settings);
      else if (op.op === 'planBotTurn') poker.planBotTurn(g);
      else throw Error(`Unsupported expectError op ${op.op}`);
    } catch (e) {
      code = errorCode(e);
    }
    if (code === null) throw Error(`${this.data.name}: expected ${op.op} to throw`);
    if (JSON.stringify(g) !== before || this.stream.draws !== draws)
      throw Error(`${this.data.name}: failed ${op.op} changed state`);
    this.data.steps.push(plain({ op: 'expectError', step: op, error: code, snapshot: this.delta(snapshot(g, this.stream)) }));
  }
  query(fn, args = {}) {
    const g = this.g;
    let value;
    if (fn === 'partitionPots') value = potsOut(poker.partitionPots(g));
    else if (fn === 'contestableAfterCall') value = poker.contestableAfterCall(g, args.id, args.amount);
    else if (fn === 'legalActions') value = poker.legalActions(g, args.id);
    else if (fn === 'nextBetLevel') value = labels.nextBetLevel(g);
    else if (fn === 'raiseLabel')
      value = labels.actionLabel({ ...g, legal: poker.legalActions(g), action: 'raise', amount: args.amount });
    else if (fn === 'historyActionLabel') value = labels.historyActionLabel(g.history, args.index);
    else if (fn === 'decisionActionLabel')
      value = labels.actionLabel(g.decisions[args.index], args.action, args.amount);
    else throw Error(`Unknown query ${fn}`);
    this.data.steps.push(plain({ op: 'query', fn, args, result: value }));
    return value;
  }
  // Helpers that expand into primitive recorded steps.
  finish(action = 'call') {
    let guard = 0;
    while (this.g.phase !== 'done') {
      if (++guard > 1000) throw Error('stalled');
      if (this.g.phase === 'between') this.advanceStreet();
      else this.act(this.g.actor, action);
    }
  }
  playing(action) {
    while (this.g.phase === 'playing') this.act(this.g.actor, action);
  }
  done() {
    return translateDeep(this.data);
  }
}

const scenarios = [];
let seedCounter = 100;
const scenario = (name, options = {}) => new Scenario(name, { seed: options.seed ?? seedCounter++, ...options });
const add = (s) => scenarios.push(s.done());

// --- rules-audit.test.js ----------------------------------------------------
const rotations = [
  { d: 0, pre: [3, 4, 5, 0, 1, 2], post: [1, 2, 3, 4, 5, 0] },
  { d: 1, pre: [4, 5, 0, 1, 2, 3], post: [2, 3, 4, 5, 0, 1] },
  { d: 2, pre: [5, 0, 1, 2, 3, 4], post: [3, 4, 5, 0, 1, 2] },
  { d: 3, pre: [0, 1, 2, 3, 4, 5], post: [4, 5, 0, 1, 2, 3] },
  { d: 4, pre: [1, 2, 3, 4, 5, 0], post: [5, 0, 1, 2, 3, 4] },
  { d: 5, pre: [2, 3, 4, 5, 0, 1], post: [0, 1, 2, 3, 4, 5] },
];
for (const r of rotations) {
  const s = scenario(`rules-audit: dealer ${r.d}: blinds, dealing and all four action rounds`);
  s.patch({ game: { dealer: r.d === 0 ? 5 : r.d - 1 } });
  s.startHand({ randomConstant: 0.999999 });
  for (const id of r.pre) s.act(id, 'call');
  for (let street = 0; street < 3; street++) {
    s.advanceStreet();
    for (const id of r.post) s.act(id, 'check');
  }
  s.advanceStreet();
  add(s);
}
{
  const s = scenario('rules-audit: button advances one clockwise seat over a full orbit');
  for (let i = 0; i < 7; i++) {
    s.startHand();
    s.playing('fold');
  }
  add(s);
}
{
  const s = scenario('rules-audit: big blind retains raise option after five limps');
  s.startHand();
  for (let i = 0; i < 5; i++) s.act(s.g.actor, 'call');
  s.act(2, 'raise', 100);
  s.playing('call');
  add(s);
}
{
  const s = scenario('rules-audit: postflop skips folded small blind and all-in big blind');
  s.patch({ players: [{ id: 2, stack: 50 }] });
  s.startHand();
  for (const id of [3, 4, 5, 0]) s.act(id, 'call');
  s.act(1, 'fold');
  s.advanceStreet();
  s.playing('check');
  add(s);
}
{
  const s = scenario('rules-audit: two survivors in a six-handed deal do not move the blinds to heads-up positions');
  s.startHand();
  for (const id of [3, 4, 5]) s.act(id, 'fold');
  s.act(0, 'call');
  s.act(1, 'call');
  s.act(2, 'fold');
  s.advanceStreet();
  add(s);
}
{
  const s = scenario('rules-audit: short blinds post actual stacks and keep full big blind bring-in');
  s.patch({ players: [{ id: 1, stack: 10 }, { id: 2, stack: 20 }] });
  s.startHand();
  s.finish('call');
  add(s);
}
const postflopPatch = (stacks = [1000, 1000, 1000, 1000, 1000, 1000]) => ({
  game: { dealer: 5, phase: 'playing', street: 1, currentBet: 0, minRaise: 50, pending: [0, 1, 2, 3, 4, 5], actor: 0 },
  players: stacks.map((stack, id) => ({ id, stack })),
});
{
  const s = scenario('rules-audit: ordinary check-raise remains legal after a full opening bet');
  s.patch(postflopPatch());
  s.act(0, 'check');
  s.act(1, 'raise', 100);
  for (const id of [2, 3, 4, 5]) s.act(id, 'call');
  add(s);
}
{
  const s = scenario('rules-audit: checking then facing only a sub-minimum all-in does not reopen a raise');
  s.patch(postflopPatch([1000, 20, 1000, 1000, 1000, 1000]));
  s.act(0, 'check');
  s.act(1, 'raise', 20);
  for (const id of [2, 3, 4, 5]) s.act(id, 'call');
  s.expectError({ op: 'act', id: 0, action: 'raise', amount: 70 });
  s.act(0, 'call');
  add(s);
}
{
  const s = scenario('rules-audit: cumulative sub-minimum opening all-ins reopen the checker at one full blind');
  s.patch(postflopPatch([1000, 20, 40, 50, 1000, 1000]));
  s.act(0, 'check');
  s.act(1, 'raise', 20);
  s.act(2, 'raise', 40);
  s.act(3, 'raise', 50);
  s.act(4, 'call');
  s.act(5, 'call');
  add(s);
}
{
  const s = scenario('rules-audit: TDA raise examples distinguish increment from total');
  s.patch(postflopPatch());
  s.act(0, 'raise', 125);
  s.act(1, 'raise', 250);
  s.act(2, 'raise', 550);
  s.expectError({ op: 'act', id: 3, action: 'raise', amount: 800 });
  add(s);
}
{
  const s = scenario('rules-audit: short all-in does not remove the unacted big blind raise option');
  s.patch({ players: [{ id: 3, stack: 75 }] });
  s.startHand();
  s.act(3, 'raise', 75);
  for (const id of [4, 5, 0, 1]) s.act(id, 'call');
  add(s);
}
{
  const s = scenario('rules-audit: TDA cumulative short raises reopen A but not an intervening caller C');
  s.patch(postflopPatch([1000, 125, 1000, 200, 1000, 1000]));
  s.act(0, 'raise', 100);
  s.act(1, 'raise', 125);
  s.act(2, 'call');
  s.act(3, 'raise', 200);
  s.act(4, 'call');
  s.act(5, 'fold');
  s.act(0, 'call');
  add(s);
}
{
  const s = scenario('rules-audit: one non-all-in player cannot make a dry side pot');
  s.patch(postflopPatch([1000, 100, 100, 100, 100, 100]));
  s.act(0, 'raise', 100);
  for (const id of [1, 2, 3, 4, 5]) s.act(id, 'call');
  s.patch({ game: { deck: keysOf(DECK) } });
  s.advanceStreet();
  s.query('legalActions', { id: 0 });
  add(s);
}
{
  const s = scenario('rules-audit: blinds and unfinished ordinary raises do not create side pots');
  s.startHand();
  s.act(3, 'raise', 125);
  s.act(4, 'call');
  add(s);
}
{
  const s = scenario('rules-audit: live pots split only at all-in caps and retain uncalled excess separately');
  const totals = [100, 300, 500, 500, 0, 0];
  s.patch({
    game: { phase: 'playing' },
    players: totals.map((total, i) => ({ id: i, total, allin: i < 3, folded: i > 3 })),
  });
  s.patch({ players: [{ id: 3, total: 800 }] });
  add(s);
}

// --- multi-pot-check.test.js -------------------------------------------------
const multiHands = ['As Ah', 'Ks Kh', 'Qs Qh', 'Js Jh', 'Ts Th', '9s 9h'];
const multiFixture = (totals, folded = [], custom = multiHands) => ({
  game: { phase: 'between', street: 3, board: parseKeys('2c 3d 4h 7s 8c') },
  players: multiHands.map((_, i) => {
    const total = totals[i] || 0;
    return { id: i, total, bet: total, stack: 5000 - total, hole: parseKeys(custom[i] || multiHands[i]), folded: total === 0 || folded.includes(i) };
  }),
});
{
  const s = scenario('multi-pot: four players: one main pot and two side pots have different winners');
  s.patch(multiFixture([100, 300, 500, 500]));
  s.query('partitionPots');
  s.settle();
  add(s);
}
{
  const s = scenario('multi-pot: six players: five contested pots plus a refund');
  s.patch(multiFixture([100, 200, 300, 400, 500, 600]));
  s.settle();
  add(s);
}
{
  const s = scenario('multi-pot: folded chips remain; folded contribution cap does not create a spurious extra pot');
  s.patch(multiFixture([100, 300, 500, 500, 200], [4]));
  s.settle();
  add(s);
}
{
  const s = scenario('multi-pot: folded contributions with no all-in stay in a single pot');
  s.patch(multiFixture([25, 50, 100, 100], [0, 1]));
  s.query('partitionPots');
  s.settle();
  add(s);
}
{
  const s = scenario('multi-pot: a side pot can split independently while the main pot and first side pot have single winners');
  s.patch(multiFixture([100, 300, 500, 500], [], ['As Ah', 'Ks Kh', 'Qs Qh', 'Qc Qd']));
  s.settle();
  add(s);
}
for (const dealer of [0, 1]) {
  const s = scenario(`multi-pot: odd side-pot chip goes to the first tied winner left of the button (dealer ${dealer})`);
  s.patch(multiFixture([100, 301, 301, 101], [3], ['As Ah', 'Ks Kh', 'Kc Kd']));
  s.patch({ game: { dealer } });
  s.settle();
  add(s);
}
{
  const s = scenario('multi-pot: uncalled return is separate from pot winnings and never counts as a won hand');
  s.patch(multiFixture([800, 100, 300, 500], [], ['Js Jh', 'As Ah', 'Ks Kh', 'Qs Qh']));
  s.settle();
  add(s);
}
{
  const s = scenario('multi-pot: four actual legal all-ins form three pots before settlement');
  s.patch(multiFixture([0, 0, 0, 0]));
  s.patch({
    game: { phase: 'playing', currentBet: 0, actor: 0, pending: [0, 1, 2, 3] },
    players: [100, 300, 500, 500, 5000, 5000].map((stack, i) => ({ id: i, folded: i > 3, allin: false, total: 0, bet: 0, stack, actedTo: null })),
  });
  s.act(0, 'raise', 100);
  s.act(1, 'raise', 300);
  s.act(2, 'raise', 500);
  s.act(3, 'call');
  s.query('partitionPots');
  s.advanceStreet();
  add(s);
}
{
  const s = scenario('multi-pot: short stack is exposed only when the other deep stacks can no longer bet');
  s.patch(multiFixture([0, 0, 0]));
  s.patch({
    game: { phase: 'playing', street: 1, board: parseKeys('2c 3d 4h'), deck: parseKeys('5s 6s 7s 8s 9s Ts'), currentBet: 0, actor: 0, dealer: 5, pending: [0, 1, 2] },
    players: [100, 300, 500, 5000, 5000, 5000].map((stack, i) => ({ id: i, folded: i > 2, stack, bet: 0, total: 0, actedTo: null })),
  });
  s.act(0, 'raise', 100);
  s.act(1, 'call');
  s.act(2, 'call');
  s.advanceStreet();
  s.act(1, 'raise', 200);
  s.act(2, 'call');
  s.query('partitionPots');
  s.advanceStreet();
  s.advanceStreet();
  add(s);
}
{
  const s = scenario('multi-pot: pot odds exclude side pots beyond the short stack cap');
  s.patch(multiFixture([0, 100, 100]));
  s.query('contestableAfterCall', { id: 0, amount: 20 });
  s.query('contestableAfterCall', { id: 0, amount: 100 });
  add(s);
}
{
  const s = scenario('multi-pot: several short all-ins can cumulatively reopen raising');
  s.patch(multiFixture([100, 100, 100, 100]));
  s.patch({
    game: { phase: 'playing', currentBet: 100, minRaise: 100, actor: 1, pending: [1, 2, 3] },
    players: [{ id: 0, actedTo: 100 }, { id: 1, stack: 40 }, { id: 2, stack: 100 }],
  });
  s.act(1, 'raise', 140);
  s.act(2, 'raise', 200);
  s.act(3, 'call');
  s.query('legalActions', { id: 0 });
  add(s);
}
{
  const s = scenario('multi-pot: folded players do not turn one tied pot into multiple odd-chip awards');
  s.patch(multiFixture([5, 5, 1, 2, 3, 4], [2, 3, 4, 5], ['As Ah', 'Ac Ad']));
  s.settle();
  add(s);
}
{
  const s = scenario('multi-pot: settlement cannot award chips twice');
  s.patch(multiFixture([100, 300, 500, 500]));
  s.settle();
  s.expectError({ op: 'settle', showdown: true });
  add(s);
}

// --- retry-check.test.js -----------------------------------------------------
{
  const s = scenario('retry: restart rejects idle, active and between streets without changing state');
  s.expectError({ op: 'restartHand' });
  s.startHand();
  s.expectError({ op: 'restartHand' });
  s.playing('call');
  s.expectError({ op: 'restartHand' });
  add(s);
}
{
  // The reference searches LCG seeds for a hero QQ deal; the fixture searches
  // Mulberry32 seeds instead so natives only need the one seeded generator.
  let found = null;
  for (let seed = 1; seed < 100000 && found === null; seed++) {
    useSeed(seed);
    const g = poker.newGame();
    g.dealer = 2;
    g.players[0].stack = 14000;
    poker.startHand(g);
    if (g.players[0].hole.every((c) => c.rank === 12)) found = seed;
  }
  Math.random = forbiddenRandom;
  const s = scenario('retry: pocket queens all-in folds: same deal, button, stacks and pre-hand statistics', { seed: found });
  s.patch({ game: { dealer: 2, stats: { hands: 9, wins: 4, buyin: 10000 } }, players: [{ id: 0, stack: 14000 }] });
  s.startHand();
  s.act(0, 'raise', poker.legalActions(s.g).maxRaiseTo);
  s.playing('fold');
  s.restartHand();
  s.act(0, 'raise', 150);
  add(s);
}
for (let n = 5; n <= 9; n++)
  for (let d = 0; d < n; d++) {
    const s = scenario(`retry: ${n} players all button rotations replay correctly (button ${d})`, { playerCount: n });
    s.patch({
      game: { dealer: (d + n - 1) % n, stats: { hands: 7, wins: 3, buyin: 1000 } },
      players: Array.from({ length: n }, (_, i) => ({ id: i, stack: 1000 + i * 123 })),
    });
    s.startHand();
    s.finish('fold');
    s.restartHand();
    add(s);
  }
{
  const s = scenario('retry: full river runout stays identical after different earlier choices');
  s.startHand();
  s.finish('call');
  s.restartHand();
  s.act(s.g.actor, 'raise', 100);
  s.finish('call');
  add(s);
}
{
  const s = scenario('retry: nine unequal all-ins retract eight contested pots and one refund', { playerCount: 9 });
  s.patch({ players: Array.from({ length: 9 }, (_, i) => ({ id: i, stack: (i + 1) * 100 })) });
  s.startHand();
  while (s.g.phase === 'playing') {
    const legal = poker.legalActions(s.g);
    if (legal.canRaise) s.act(s.g.actor, 'raise', legal.maxRaiseTo);
    else s.act(s.g.actor, 'call');
  }
  s.finish('call');
  s.restartHand();
  add(s);
}
{
  const s = scenario('retry: rebuy and short blind restore once with original actual blind amounts');
  s.patch({ players: [{ id: 0, stack: 0 }, { id: 1, stack: 20 }, { id: 2, stack: 35 }] });
  s.startHand();
  s.finish('call');
  s.restartHand();
  add(s);
}
{
  const s = scenario('retry: repeated retries keep baseline immutable and count only latest final attempt');
  s.startHand();
  for (let attempt = 1; attempt <= 20; attempt++) {
    s.finish(attempt % 2 ? 'fold' : 'call');
    s.restartHand();
  }
  s.patch({ game: { difficulty: 'hard' } });
  s.finish('call');
  s.restartHand();
  s.finish('call');
  add(s);
}
{
  const s = scenario('retry: next hand replaces replay baseline and resets retry counter');
  s.startHand();
  s.finish('fold');
  s.restartHand();
  s.finish('fold');
  s.startHand();
  s.finish('call');
  s.restartHand();
  add(s);
}

// --- population-check.test.js (engine parts) ---------------------------------
{
  const s = scenario('population: six seats by default; unsupported counts rejected');
  s.expectError({ op: 'newGame', playerCount: 4 });
  s.expectError({ op: 'newGame', playerCount: 10 });
  add(s);
}
for (let n = 5; n <= 9; n++)
  for (let d = 0; d < n; d++) {
    const s = scenario(`population: ${n} players button ${d}: all four rounds and immediate river reveal`, { playerCount: n });
    s.patch({ game: { dealer: (d + n - 1) % n } });
    s.startHand();
    s.playing('call');
    for (let street = 1; street <= 3; street++) {
      s.advanceStreet();
      s.playing('check');
    }
    s.advanceStreet();
    add(s);
  }
// The reference picks fold/call/raise with Math.random; the fixture records the
// chosen actions explicitly so natives only replay them.
function randomTestAction(s, r) {
  const legal = poker.legalActions(s.g),
    x = r();
  if (x < 0.13) s.act(s.g.actor, 'fold');
  else if (x > 0.8 && legal.canRaise) s.act(s.g.actor, 'raise', legal.maxRaiseTo);
  else s.act(s.g.actor, legal.canCheck ? 'check' : 'call');
}
for (let n = 5; n <= 9; n++)
  for (const mode of ['actual bots', 'random legal actions']) {
    const s = scenario(`population: ${n} players actual bots and random legal hands (${mode})`, { playerCount: n });
    const r = scriptStream(s.data.seed);
    s.startHand();
    let guard = 0;
    while (s.g.phase !== 'done') {
      if (++guard > 1000) throw Error('stalled');
      if (s.g.phase === 'between') s.advanceStreet();
      else if (mode === 'actual bots' && s.g.actor !== 0) s.botAct();
      else randomTestAction(s, r);
    }
    add(s);
  }
for (let n = 5; n <= 9; n++)
  for (let d = 0; d < n; d++) {
    const s = scenario(`population: ${n} player royal board tie, all button positions odd chip order (button ${d})`, { playerCount: n });
    const board = parseKeys('Ts Js Qs Ks As'),
      rest = keysOf(DECK).filter((k) => !board.includes(k));
    s.patch({
      game: { dealer: d, phase: 'between', street: 3, board },
      players: Array.from({ length: n }, (_, i) => {
        const total = i < 2 ? 100 : i === 2 ? 101 : 0;
        return { id: i, hole: rest.slice(i * 2, i * 2 + 2), folded: i >= 3, total, stack: 5000 - total };
      }),
    });
    s.settle();
    add(s);
  }
for (let n = 5; n <= 9; n++)
  for (let d = 0; d < n; d++) {
    const s = scenario(`population: ${n}: independent side-pot odd chip always follows button (button ${d})`, { playerCount: n });
    const board = parseKeys('2c 3d 4h 7s 8c'),
      used = parseKeys('As Ah Ks Kh Kc Kd'),
      rest = keysOf(DECK).filter((k) => !board.includes(k) && !used.includes(k));
    s.patch({
      game: { phase: 'between', street: 3, dealer: d, board },
      players: Array.from({ length: n }, (_, i) => {
        const total = [100, 301, 301, 101][i] || 0;
        return {
          id: i,
          total,
          stack: 5000 - total,
          folded: i >= 3,
          hole: i === 0 ? parseKeys('As Ah') : i === 1 ? parseKeys('Ks Kh') : i === 2 ? parseKeys('Kc Kd') : rest.splice(0, 2),
        };
      }),
    });
    s.settle();
    add(s);
  }

// --- poker-check.test.js (engine parts) ---------------------------------------
{
  const s = scenario('poker-check: blinds and big blind option');
  s.startHand();
  for (let i = 0; i < 6; i++) s.act(s.g.actor, 'call');
  s.advanceStreet();
  add(s);
}
{
  const s = scenario('poker-check: folds award pot without board');
  s.startHand();
  for (let i = 0; i < 5; i++) s.act(s.g.actor, 'fold');
  add(s);
}
{
  const s = scenario('poker-check: side pots and uncalled return');
  const hands = ['As Ah', 'Ks Kh', 'Qs Qh'];
  s.patch({
    game: { board: parseKeys('2c 3d 7s 9h Jc') },
    players: [100, 300, 500, 0, 0, 0].map((total, i) => ({ id: i, folded: i > 2, total, stack: 5000 - total, hole: parseKeys(i < 3 ? hands[i] : '4s 5h') })),
  });
  s.settle(true);
  add(s);
}
{
  const s = scenario('poker-check: board tie splits main pot');
  s.patch({
    game: { board: parseKeys('As Ks Qs Js Ts') },
    players: Array.from({ length: 6 }, (_, i) => {
      const total = i < 2 ? 101 : 0;
      return { id: i, folded: i > 1, total, stack: 5000 - total, hole: parseKeys(i === 0 ? '2h 3h' : '4c 5c') };
    }),
  });
  s.settle(true);
  add(s);
}
{
  const s = scenario('poker-check: short all-in does not reopen completed raise');
  s.patch({
    game: { phase: 'playing', street: 1, currentBet: 100, minRaise: 100, actor: 1, pending: [1, 2] },
    players: Array.from({ length: 6 }, (_, i) => {
      const bet = i < 3 ? 100 : 0;
      return { id: i, folded: i > 2, bet, total: bet, stack: i === 1 ? 50 : 1000, actedTo: i === 0 ? 100 : null };
    }),
  });
  s.act(1, 'raise', 150);
  s.act(2, 'call');
  s.expectError({ op: 'act', id: 0, action: 'raise', amount: 250 });
  s.act(0, 'call');
  add(s);
}
{
  const s = scenario('poker-check: invalid action preserves state');
  s.startHand();
  s.expectError({ op: 'act', id: 0, action: 'call' });
  s.expectError({ op: 'act', id: 3, action: 'check' });
  s.expectError({ op: 'act', id: 3, action: 'bet', amount: 100 });
  s.expectError({ op: 'advanceStreet' });
  s.expectError({ op: 'startHand' });
  s.expectError({ op: 'completeBoardForPractice' });
  s.expectError({ op: 'applyBotSettings', settings: { emotionMode: 'off' } });
  s.act(3, 'fold');
  add(s);
}
for (let trial = 0; trial < 10; trial++) {
  const s = scenario(`poker-check: 200 randomized hands conserve chips and end (sample ${trial + 1})`);
  const r = scriptStream(s.data.seed);
  s.startHand();
  let turns = 0;
  while (s.g.phase !== 'done') {
    if (turns++ > 600) throw Error('stalled');
    if (s.g.phase === 'between') {
      s.advanceStreet();
      continue;
    }
    const id = s.g.actor,
      l = poker.legalActions(s.g),
      x = r();
    if (x < 0.16) s.act(id, 'fold');
    else if (x < 0.43 && l.canRaise) s.act(id, 'raise', r() < 0.25 ? l.maxRaiseTo : l.minRaiseTo);
    else s.act(id, 'call');
  }
  add(s);
}
for (let trial = 0; trial < 3; trial++) {
  const s = scenario(`poker-check: actual bot decisions are legal for 12 hands (sample ${trial + 1})`);
  s.startHand();
  while (s.g.phase !== 'done') {
    if (s.g.phase === 'between') s.advanceStreet();
    else s.botAct();
  }
  add(s);
}

// --- last-action.test.js -------------------------------------------------------
{
  const s = scenario('last-action: preflop all-in sizes and bet level survive every runout street and payout');
  s.startHand();
  s.act(s.g.actor, 'raise', 5000);
  s.playing('call');
  while (s.g.phase !== 'done') s.advanceStreet();
  add(s);
}
{
  const s = scenario('last-action: a later action replaces the retained action, while street resets preserve call and fold context');
  s.startHand();
  s.act(3, 'raise', 150);
  s.act(4, 'call');
  s.act(5, 'fold');
  s.playing('call');
  s.advanceStreet();
  s.act(1, 'raise', 100);
  s.act(2, 'call');
  s.act(3, 'fold');
  s.act(4, 'call');
  s.act(0, 'call');
  s.advanceStreet();
  s.act(1, 'check');
  add(s);
}
{
  const s = scenario('last-action: uncalled refunds and practice cards retain the original shove; retry and next hand restore fresh actions');
  s.startHand();
  s.act(s.g.actor, 'raise', 5000);
  s.playing('fold');
  s.completeBoardForPractice();
  s.restartHand();
  s.playing('fold');
  s.startHand();
  add(s);
}

// --- practice-runout.test.js ---------------------------------------------------
for (const street of [0, 1, 2, 3]) {
  const s = scenario(`practice-runout: fold-win on street ${street}: practice runout matches original river and leaves settlement untouched`, { playerCount: 9 });
  s.patch({ game: { dealer: 5 } });
  s.startHand();
  while (s.g.street < street) {
    s.playing('call');
    s.advanceStreet();
  }
  if (street > 0) s.act(s.g.actor, 'raise', 100);
  while (s.g.actor !== 0) s.act(s.g.actor, 'fold');
  s.act(0, 'fold');
  s.playing('fold');
  s.completeBoardForPractice();
  s.completeBoardForPractice();
  s.expectError({ op: 'advanceStreet' });
  s.restartHand();
  s.finish('call');
  s.startHand();
  add(s);
}
{
  const s = scenario('practice-runout: practice runout cannot expose a live deck; a normal showdown stays unchanged');
  s.expectError({ op: 'completeBoardForPractice' });
  s.startHand();
  s.expectError({ op: 'completeBoardForPractice' });
  s.playing('call');
  s.expectError({ op: 'completeBoardForPractice' });
  s.finish('call');
  s.completeBoardForPractice();
  add(s);
}

// --- bet-labels.test.js ----------------------------------------------------------
{
  const s = scenario('bet-labels: preflop 2/3/4-bets survive intervening calls and before-action review snapshots');
  s.patch({ game: { dealer: 5 } });
  s.startHand();
  while (s.g.actor !== 0) s.act(s.g.actor, 'fold');
  s.query('raiseLabel', { amount: 150 });
  s.act(0, 'raise', 150);
  s.act(1, 'call');
  s.query('raiseLabel', { amount: 650 });
  s.act(2, 'raise', 650);
  s.act(0, 'call');
  s.query('raiseLabel', { amount: 1800 });
  s.act(1, 'raise', 1800);
  s.act(2, 'call');
  s.act(0, 'call');
  s.query('decisionActionLabel', { index: 0 });
  s.query('decisionActionLabel', { index: 2, action: 'raise', amount: 3000 });
  s.advanceStreet();
  s.query('raiseLabel', { amount: 100 });
  s.act(1, 'check');
  s.act(2, 'raise', 100);
  s.act(0, 'call');
  s.query('raiseLabel', { amount: 300 });
  s.act(1, 'raise', 300);
  s.act(2, 'call');
  s.act(0, 'call');
  s.advanceStreet();
  s.query('raiseLabel', { amount: 100 });
  add(s);
}
{
  const s = scenario('bet-labels: short all-in has an ordinal without reopening a prior bettor; all-in calls add no level');
  s.patch({ game: { dealer: 5 }, players: [{ id: 2, stack: 175 }, { id: 3, stack: 100 }] });
  s.startHand();
  s.playing('call');
  s.advanceStreet();
  s.act(1, 'raise', 100);
  s.query('raiseLabel', { amount: 125 });
  s.act(2, 'raise', 125);
  s.act(3, 'call');
  s.query('nextBetLevel');
  s.act(4, 'call');
  s.act(5, 'call');
  s.act(0, 'call');
  s.query('historyActionLabel', { index: s.g.history.findIndex((a) => a.betLabel?.includes('短全下')) });
  add(s);
}
{
  const s = scenario('bet-labels: retry clears prior raise sequence and starts again at 2-bet');
  s.patch({ game: { dealer: 2 } });
  s.startHand();
  s.act(0, 'raise', 150);
  s.playing('fold');
  s.restartHand();
  s.query('raiseLabel', { amount: 150 });
  add(s);
}

// --- Seeded random hands -----------------------------------------------------
// Scripted legal (and a few illegal) actions chosen from a separate generator
// stream. Covers short all-ins, multiway all-ins, odd chips, rebuys, ties,
// replays (each replayed twice), practice runouts, and bot turns.
function scriptedAction(s, r, style) {
  const g = s.g,
    id = g.actor,
    legal = poker.legalActions(g);
  if (r() < 0.04) {
    // Occasional illegal attempt; must leave state untouched.
    if (!legal.canCheck) return s.expectError({ op: 'act', id, action: 'check' });
    if (legal.canRaise && legal.minRaiseTo > g.currentBet + 1)
      return s.expectError({ op: 'act', id, action: 'raise', amount: legal.minRaiseTo - 1 });
    return s.expectError({ op: 'act', id: (id + 1) % g.players.length, action: 'fold' });
  }
  const pFold = style === 'passive' ? 0.08 : style === 'tight' ? 0.6 : 0.15,
    pRaise = style === 'allin' ? 0.55 : style === 'passive' ? 0.12 : 0.3;
  const x = r();
  if (legal.toCall > 0 && x < pFold) return s.act(id, 'fold');
  if (legal.canRaise && x < pFold + pRaise) {
    const k = r();
    const amount =
      style === 'allin' || k < 0.2
        ? legal.maxRaiseTo
        : k < 0.55
          ? legal.minRaiseTo
          : intBetween(r, legal.minRaiseTo, legal.maxRaiseTo);
    return s.act(id, 'raise', amount);
  }
  if (legal.canCheck) return s.act(id, r() < 0.2 ? 'call' : 'check');
  return s.act(id, 'call');
}
function playScripted(s, r, style, useBots) {
  let guard = 0;
  while (s.g.phase !== 'done') {
    if (++guard > 2000) throw Error('stalled');
    if (s.g.phase === 'between') s.advanceStreet();
    else if (useBots && s.g.actor !== 0) s.botTurn();
    else scriptedAction(s, r, style);
  }
}
// Rearranges the undealt deck and hole cards so the board is a royal flush
// that every live player plays (a guaranteed multiway tie).
function tieBoardPatch(g) {
  const board = parseKeys('Ts Js Qs Ks As'),
    others = keysOf(DECK).filter((k) => !board.includes(k));
  const players = g.players.map((p, i) => ({ id: p.id, hole: others.slice(i * 2, i * 2 + 2) }));
  const rest = others.slice(g.players.length * 2);
  const burns = rest.splice(0, 3);
  // Pop order: burn, flop x3, burn, turn, burn, river.
  const tail = [board[4], burns[2], board[3], burns[1], board[2], board[1], board[0], burns[0]];
  return { game: { deck: [...rest.slice(0, g.deck.length - tail.length), ...tail] }, players };
}
for (let i = 0; i < 42; i++) {
  const n = 5 + (i % 5);
  const s = scenario(`random hand ${i + 1}: ${n} seats`, { playerCount: n, seed: 7000 + i });
  const r = scriptStream(s.data.seed);
  const style = i % 3 === 0 ? 'allin' : i % 3 === 1 ? 'mixed' : i % 6 === 5 ? 'tight' : 'passive';
  const useBots = i % 6 === 3;
  const players = [];
  for (let id = 0; id < n; id++) {
    const roll = r();
    let stack = 5000;
    if (i % 2 === 0) stack = roll < 0.3 ? intBetween(r, 20, 400) : intBetween(r, 401, 6000);
    if (i % 7 === 0 && id === (i % n)) stack = 0;
    if (i % 7 === 0 && roll > 0.7) stack = intBetween(r, 1, 49);
    players.push({ id, stack });
  }
  const game = { dealer: intBetween(r, 0, n - 1) };
  if (useBots) {
    game.difficulty = pick(r, ['easy', 'normal', 'hard']);
  }
  s.patch({ game, players });
  if (useBots)
    s.applyBotSettings({
      emotionMode: pick(r, ['off', 'subtle', 'lively']),
      assignments: Object.fromEntries(Array.from({ length: 8 }, (_, k) => [k + 1, pick(r, bots.BOT_PROFILES).id])),
    });
  const hands = 1 + (i % 3);
  for (let h = 0; h < hands; h++) {
    s.startHand();
    if (i % 8 === 5 && h === 0) s.patch(tieBoardPatch(s.g));
    playScripted(s, r, style, useBots);
    if (i % 4 === 1 && h === 0) {
      for (let replay = 0; replay < 2; replay++) {
        s.restartHand();
        playScripted(s, r, replay ? 'mixed' : style, useBots);
      }
    }
    if (!s.g.showdown && s.g.board.length < 5) s.completeBoardForPractice();
  }
  add(s);
}

// ---------------------------------------------------------------------------
// Fixture file writers
// ---------------------------------------------------------------------------
// Pretty top level, one compact line per array item for large lists.
function compactList(meta, key, items, more = {}) {
  const head = JSON.stringify(meta, null, 2).replace(/\n}$/, '');
  const lists = Object.entries({ ...more, [key]: items }).map(
    ([k, list]) => `  ${JSON.stringify(k)}: [\n${list.map((item) => '    ' + JSON.stringify(item)).join(',\n')}\n  ]`,
  );
  return `${head},\n${lists.join(',\n')}\n}\n`;
}
const pretty = (value) => JSON.stringify(value, null, 2) + '\n';
const header = (description) => ({ referenceCommit: REFERENCE_COMMIT, generator: 'scripts/generate-reference-fixtures.mjs', description });
Math.random = forbiddenRandom;

outputs.set(
  'engine-scenarios.json',
  compactList(
    { ...header('Scripted engine scenarios with a public snapshot after every step.'), errors: ERROR_CODES_ENGLISH() },
    'cases',
    scenarios,
  ),
);
function ERROR_CODES_ENGLISH() {
  return {
    'invalid-player-count': 'Table size must be 5–9 players.',
    'settings-locked': 'Opponent settings take effect at the start of the next hand.',
    'hand-in-progress': "The current hand isn't finished yet.",
    'replay-unavailable': 'You can replay a hand after it ends; the original deal is required.',
    'not-your-turn': "It's not your turn yet.",
    'unknown-action': 'Unknown table action.',
    'cannot-check': "You must call; checking isn't allowed.",
    'illegal-raise': 'Choose a legal raise-to amount.',
    'round-not-finished': "This betting round isn't finished.",
    'hand-not-settled': 'Settle this hand first.',
    'showdown-needs-board': 'A showdown settlement requires all five community cards.',
    'already-settled': 'This hand has already been settled.',
    'no-eligible-player': 'No eligible player for this pot.',
    'pot-mismatch': "Pot distribution doesn't add up.",
    'invalid-trials': 'Equity trial count must be a positive integer.',
    'bot-cannot-act': "The bot can't act right now.",
    'hero-bot-executor': "The hero's turn can't use the bot executor.",
    'stale-bot-plan': 'This bot action plan is stale.',
  };
}

// --- rng.json ------------------------------------------------------------------
{
  const seeds = [0, 1, 2, 42, 100, 7000, 12345, 2 ** 31 - 1, 2 ** 31, 0xdeadbeef, 2 ** 32 - 1];
  const rows = seeds.map((seed) => {
    const a = seedRandom(seed),
      b = mulberry32(seed),
      values = Array.from({ length: 20 }, () => a());
    for (const v of values) if (b() !== v) throw Error('Mulberry32 port differs from seedRandom');
    return { seed, values };
  });
  outputs.set('rng.json', pretty({ ...header('Mulberry32 (seedRandom) first 20 outputs per seed.'), cases: rows }));
}

// --- hand-eval.json ------------------------------------------------------------
{
  const r = mulberry32(31337);
  const evalCase = (name, keys) => {
    const result = poker.evaluate(keys.map(card));
    return { name, cards: keys, score: result.score, label: translate(result.label), bestCardKeys: keysOf(result.cards) };
  };
  const named = [
    ['rules-audit: aces can be low, but cannot wrap K-A-2-3-4', 'Ks Ah 2c 3d 4s'],
    ['rules-audit: board plays (2s 3s)', 'As Kd Qc Jh Ts 2s 3s'],
    ['rules-audit: board plays (9h 8h)', 'As Kd Qc Jh Ts 9h 8h'],
    ['rules-audit: kicker within best five (a)', 'As Ah Ks Qs Js 2c 3c'],
    ['rules-audit: kicker within best five (b)', 'Ad Ac Kc Qc Tc 9h 8h'],
    ['rules-audit: quads with king kicker', 'As Ah Ac Ad Ks Qh Jc'],
    ['poker-check: rank 8', 'As Ks Qs Js Ts 2h 3c'],
    ['poker-check: rank 7', 'Ac Ah As Ad Kh 2s 3s'],
    ['poker-check: rank 6', 'Ac Ah As Kd Kh Qs Qh'],
    ['poker-check: rank 5', 'As Js 9s 5s 3s Kh Qh'],
    ['poker-check: rank 4', 'As 2h 3c 4d 5s Kh Qh'],
    ['poker-check: rank 3', 'As Ah Ac 9d 8s 2h 3h'],
    ['poker-check: rank 2', 'As Ah Kc Kd Qs 2h 3h'],
    ['poker-check: rank 1', 'As Ah Kc Qd 9s 2h 3h'],
    ['poker-check: rank 0', 'As Kh Qc Jd 9s 2h 3h'],
    ['poker-check: wheel', 'As 2h 3c 4d 5s'],
    ['poker-check: six-high straight', '2s 3h 4c 5d 6s'],
    ['poker-check: best full house from two trips', 'As Ah Ac Ks Kh Kc 2s'],
    ['poker-check: kicker decides (a)', 'As Ah Kc Qd 9s'],
    ['poker-check: kicker decides (b)', 'Ad Ac Kd Jh 9h'],
    ['steel wheel straight flush', 'As 2s 3s 4s 5s Kd Kh'],
    ['six-card two trips', '9s 9h 9c 4d 4s 4h'],
    ['three pairs keep best two', 'Ks Kh 7c 7d 3s 3h Ad'],
    ['pocket pair (two cards)', 'Qs Qd'],
    ['two-card high card', 'As 7d'],
    ['three cards', 'Ks Kd 2c'],
    ['four cards', '9s 8d 7c 6h'],
    ['one card', 'Th'],
  ].map(([name, s]) => evalCase(name, parseKeys(s)));
  const randomSet = (size) => {
    const keys = keysOf(DECK);
    for (let i = keys.length - 1; i > 0; i--) {
      const j = Math.floor(r() * (i + 1));
      [keys[i], keys[j]] = [keys[j], keys[i]];
    }
    return keys.slice(0, size);
  };
  const random = [];
  for (const size of [5, 6, 7]) for (let i = 0; i < 110; i++) random.push(evalCase(`random ${size}-card ${i + 1}`, randomSet(size)));
  for (const size of [0, 1, 2, 3, 4]) for (let i = 0; i < (size === 2 ? 30 : 4); i++) random.push(evalCase(`random ${size}-card ${i + 1}`, randomSet(size)));
  // Forced pocket pairs for the two-card path.
  for (let rank = 2; rank <= 14; rank++) random.push(evalCase(`pocket pair ${rank}`, [`0-${rank}`, `${rank % 4 === 0 ? 3 : 1}-${rank}`]));
  const all = [...named, ...random];
  const compareCases = [
    { a: [1, 14], b: [1, 14, 13], result: poker.compare([1, 14], [1, 14, 13]) },
    { a: [1, 14, 13], b: [1, 14], result: poker.compare([1, 14, 13], [1, 14]) },
    { a: [], b: [], result: poker.compare([], []) },
    { a: [0, 0, 0], b: [0], result: poker.compare([0, 0, 0], [0]) },
    { a: [4, 5], b: [4, 6], result: poker.compare([4, 5], [4, 6]) },
  ];
  for (let i = 0; i < 200; i++) {
    const a = pick(r, all).score,
      b = r() < 0.15 ? [...a] : pick(r, all).score;
    compareCases.push({ a, b, result: poker.compare(a, b) });
  }
  outputs.set(
    'hand-eval.json',
    compactList(header('evaluate() and compare() cases; cards are suit-rank keys.'), 'cases', all, { compare: compareCases }),
  );
}

// --- action-labels.json --------------------------------------------------------
{
  const cases = [];
  const r = mulberry32(4242);
  const addLevel = (step) => cases.push({ fn: 'nextBetLevel', step, result: labels.nextBetLevel(step) });
  const addCaption = (step, amount) => cases.push({ fn: 'raiseCaption', step, amount, result: labels.raiseCaption(step, amount) });
  const addAction = (step, action, amount) =>
    cases.push({
      fn: 'actionLabel',
      step,
      ...(action === undefined ? {} : { action }),
      ...(amount === undefined ? {} : { amount }),
      result: labels.actionLabel(step, action, amount),
    });
  const addHistory = (history, index) => cases.push({ fn: 'historyActionLabel', history, index, result: labels.historyActionLabel(history, index) });
  // bet-labels: historical ordinals use the complete street before truncation.
  const history = [{ street: 0, action: 'raise', amount: 150 }];
  for (let i = 1; i <= 6; i++) {
    history.push({ street: 1, action: 'raise', amount: 100 * i });
    history.push({ street: 1, action: 'call', amount: 100 });
    history.push({ street: 1, action: 'fold', amount: 0 });
  }
  history.forEach((_, index) => addHistory(history, index));
  addLevel({ street: 2, history });
  addLevel({ street: 0 });
  addLevel({ street: 1, history: [] });
  // Verb boundaries.
  const legal = (o) => ({ enabled: true, toCall: 0, callAmount: 0, canCheck: true, raiseReopened: true, canRaise: true, ...o });
  addCaption({ street: 0, history: [], currentBet: 50, legal: legal({ minRaiseTo: 100, fullRaiseTo: 100, maxRaiseTo: 5000 }) }, 150);
  addCaption({ street: 0, history: [], currentBet: 50, legal: legal({ minRaiseTo: 100, fullRaiseTo: 100, maxRaiseTo: 5000 }) }, 5000);
  addCaption({ street: 0, history: [], currentBet: 50, legal: legal({ minRaiseTo: 75, fullRaiseTo: 100, maxRaiseTo: 75 }) }, 75);
  addCaption({ street: 1, history: [], currentBet: 0, legal: legal({ minRaiseTo: 50, fullRaiseTo: 50, maxRaiseTo: 900 }) }, 100);
  addCaption({ street: 1, history: [{ street: 1, action: 'raise', amount: 100 }], currentBet: 100, legal: legal({ minRaiseTo: 200, fullRaiseTo: 200, maxRaiseTo: 1500 }) }, 300);
  addCaption({ street: 1, history: [{ street: 1, action: 'raise', amount: 100 }], currentBet: 100, legal: legal({ minRaiseTo: 125, fullRaiseTo: 200, maxRaiseTo: 125 }) }, 125);
  addCaption({ street: 2, history: [], currentBet: 0 }, 50);
  addCaption({ street: 2, history: [{ street: 2, action: 'raise', amount: 80 }], currentBet: 80 }, 160);
  addCaption({ street: 2, history: [{ street: 2, action: 'raise', amount: 80 }], currentBet: 80, minRaise: 80 }, 160);
  addCaption({ street: 0, history: [], currentBet: 50, legal: { maxRaiseTo: 3000 } }, 3000);
  addAction({ street: 0, history: [], currentBet: 50, stack: 1000, legal: legal({ toCall: 50, callAmount: 50, canCheck: false }) }, 'call');
  addAction({ street: 0, history: [], currentBet: 1500, stack: 1000, legal: legal({ toCall: 1500, callAmount: 1000, canCheck: false }) }, 'call');
  addAction({ street: 1, history: [], currentBet: 0, stack: 1000, legal: legal({}) }, 'check');
  addAction({ street: 1, history: [], currentBet: 0, stack: 1000, legal: legal({}) }, 'fold');
  addAction({ street: 1, history: [], currentBet: 0, stack: 12345, legal: legal({ minRaiseTo: 50, fullRaiseTo: 50, maxRaiseTo: 12345 }) }, 'raise', 1234.5);
  // Every history entry and every hero decision from the scripted scenarios.
  const engineHistories = [],
    decisionSteps = [];
  for (let i = 0; i < 24; i++) {
    useSeed(9000 + i);
    const n = 5 + (i % 5),
      g = poker.newGame(n),
      sr = scriptStream(9000 + i);
    g.dealer = intBetween(sr, 0, n - 1);
    g.players.forEach((p) => (p.stack = sr() < 0.3 ? intBetween(sr, 30, 600) : 5000));
    poker.startHand(g);
    while (g.phase !== 'done') {
      if (g.phase === 'between') {
        poker.advanceStreet(g);
        continue;
      }
      const l = poker.legalActions(g),
        x = sr();
      if (l.toCall > 0 && x < 0.15) poker.act(g, g.actor, 'fold');
      else if (l.canRaise && x < 0.5) {
        const k = sr();
        poker.act(g, g.actor, 'raise', k < 0.25 ? l.maxRaiseTo : k < 0.6 ? l.minRaiseTo : intBetween(sr, l.minRaiseTo, l.maxRaiseTo));
      } else poker.act(g, g.actor, 'call');
    }
    engineHistories.push(jsonCopy(g.history));
    decisionSteps.push(...jsonCopy(g.decisions));
  }
  Math.random = forbiddenRandom;
  for (const h of engineHistories) {
    h.forEach((_, index) => addHistory(h, index));
    // Legacy path: the same history without betLabel.
    const legacy = h.map(({ betLabel, ...rest }) => rest);
    legacy.forEach((a, index) => a.action === 'raise' && addHistory(legacy, index));
  }
  for (const d of decisionSteps) {
    const step = { street: d.street, history: d.history, currentBet: d.currentBet, minRaise: d.minRaise, stack: d.stack, legal: d.legal, action: d.action, amount: d.amount };
    addAction(step);
    addLevel({ street: d.street, history: d.history });
    if (d.legal.canRaise) {
      addAction(step, 'raise', d.legal.minRaiseTo);
      addAction(step, 'raise', d.legal.maxRaiseTo);
      addAction(step, 'raise', intBetween(r, d.legal.minRaiseTo, d.legal.maxRaiseTo));
    }
    if (!d.legal.canCheck) addAction(step, 'call');
  }
  outputs.set(
    'action-labels.json',
    compactList(header('nextBetLevel, raiseCaption, actionLabel and historyActionLabel cases with English results.'), 'cases', translateDeep(plain(cases))),
  );
}

// --- bot-profiles.json -----------------------------------------------------------
{
  const profiles = bots.BOT_PROFILES.map((p) => ({
    id: p.id,
    name: translate(p.name),
    short: translate(p.short),
    tag: translate(p.tag),
    description: translate(p.description),
    axes: p.axes,
    sizing: p.sizing,
    evidence: translate(p.evidence),
    sources: p.sources.map((s) => ({ label: translate(s.label), url: s.url })),
  }));
  const sanitizeInputs = [
    null,
    42,
    'lively',
    [],
    {},
    { emotionMode: 'off' },
    { emotionMode: 'lively' },
    { emotionMode: 'subtle' },
    { emotionMode: 'loud' },
    { emotionMode: 'toString' },
    { emotionMode: null },
    { emotionMode: 1 },
    { assignments: null },
    { assignments: { 1: 'tan', 2: 'st', 3: 'zang', 4: 'peter', 5: 'abao', 6: 'viktor', 7: 'jungleman', 8: 'dwan' } },
    { assignments: { 0: 'tan', 9: 'dwan', 10: 'st' } },
    { assignments: { 1: 'unknown', 2: 'TAN', 3: '', 4: null, 5: 7, 6: 'toString' } },
    { emotionMode: 'off', assignments: { 2: 'peter', 8: 'viktor' } },
    { emotionMode: 'lively', assignments: { 1: 'balanced', 3: 'dwan', 5: 'jungleman' } },
    { emotionMode: 'Lively', assignments: { 4: 'abao' } },
  ];
  const sanitize = sanitizeInputs.map((input) => ({ input, output: bots.sanitizeBotSettings(input) }));
  const rankChar = (r) => '  23456789TJQKA'[r];
  const classes = [];
  for (let high = 14; high >= 2; high--)
    for (let low = high; low >= 2; low--) {
      const forms = high === low ? [['', 0, 1]] : [['s', 0, 0], ['o', 0, 1]];
      for (const [suffix, s1, s2] of forms) {
        const hole = [card(`${s1}-${high}`), card(`${s2}-${low}`)];
        classes.push({ hand: rankChar(high) + rankChar(low) + suffix, hole: keysOf(hole), percentile: bots.startingPercentile(hole) });
      }
    }
  if (classes.length !== 169) throw Error('Expected 169 starting-hand classes');
  outputs.set(
    'bot-profiles.json',
    pretty({
      ...header('Bot profile data, English display copy, settings sanitization and starting-hand percentiles.'),
      profiles,
      axes: bots.PROFILE_AXES.map(translate),
      emotionModes: Object.entries(bots.EMOTION_MODES).map(([id, label]) => ({ id, label: translate(label) })),
      moodLabels: Object.entries(bots.MOOD_LABELS).map(([kind, label]) => ({ kind, label: translate(label) })),
      defaultBotSettings: bots.defaultBotSettings(),
      freshBotMood: moodOut(bots.freshBotMood()),
      freshBotStats: bots.freshBotStats(),
      botThinkLimits: timing.BOT_THINK_LIMITS,
      sanitizeBotSettings: sanitize,
      startingPercentile: classes,
    }),
  );
}

// --- mood.json -----------------------------------------------------------------
{
  const sequences = [];
  const runSequence = (name, ops) => {
    const mood = bots.freshBotMood(),
      steps = [];
    for (const op of ops) {
      let result;
      if (op.op === 'decay') result = bots.decayBotMood(mood);
      else if (op.op === 'pressureFold') result = bots.recordPressureFold(mood, op.raiser, op.mode);
      else if (op.op === 'finish') result = bots.finishBotHand({ id: op.playerId, botMood: mood }, op.profit, op.mode);
      else if (op.op === 'clearPressure') {
        mood.pressureFolds = {};
        mood.lastPressureRaiser = null;
      } else if (op.op === 'resetPressure') mood.pressureFolds[op.raiser] = 0;
      else if (op.op === 'axes') result = bots.effectiveBotAxes(bots.getBotProfile(op.profile), mood, op.mode);
      steps.push({ ...op, result: result ?? null, mood: moodOut(mood) });
    }
    sequences.push({ name, steps });
  };
  const fold = (raiser, mode = 'subtle') => ({ op: 'pressureFold', raiser, mode });
  const finish = (playerId, profit, mode = 'subtle') => ({ op: 'finish', playerId, profit, mode });
  const decay = { op: 'decay' };
  runSequence('three pressure folds to the same raiser trigger Fighting Back', [fold(2), decay, fold(2), decay, fold(2), { op: 'axes', profile: 'balanced', mode: 'subtle' }, { op: 'axes', profile: 'tan', mode: 'lively' }, decay, decay, decay, decay]);
  runSequence('a different raiser resets the pressure count', [fold(2), fold(3), fold(2), fold(2), fold(2)]);
  runSequence('emotion off records nothing', [fold(1, 'off'), fold(1, 'off'), fold(1, 'off'), finish(1, -5000, 'off'), finish(1, -5000, 'off'), finish(1, -5000, 'off'), finish(1, -5000, 'subtle')]);
  runSequence('null raiser is ignored', [fold(null), fold(null), fold(null)]);
  runSequence('big single loss on odd seat is Chasing Losses', [finish(1, -1250), { op: 'axes', profile: 'peter', mode: 'lively' }, decay, decay, decay, decay, finish(1, -1249)]);
  runSequence('big single loss on even seat is Playing Safe', [finish(2, -1300), { op: 'axes', profile: 'st', mode: 'subtle' }, { op: 'axes', profile: 'st', mode: 'off' }]);
  runSequence('three straight 5 BB losses', [finish(3, -250), finish(3, -300), finish(3, -260), decay, finish(3, -250), decay, decay, decay, finish(3, -250)]);
  runSequence('winning streak is On a Heater', [finish(4, 250), finish(4, 499), finish(4, 500), { op: 'axes', profile: 'viktor', mode: 'lively' }, decay, decay, decay, decay, finish(4, 600)]);
  runSequence('cooldown blocks a pressure trigger and the counter keeps growing', [finish(5, -2000), fold(1), fold(1), fold(1), fold(1), decay, decay, decay, decay, fold(1)]);
  runSequence('a call resets the pressure counter; settlement clears it', [fold(2), fold(2), { op: 'resetPressure', raiser: 2 }, fold(2), { op: 'clearPressure' }, fold(2)]);
  const r = mulberry32(2024);
  for (let i = 0; i < 60; i++) {
    const ops = [],
      playerId = 1 + (i % 8);
    for (let k = 0; k < 40; k++) {
      const x = r(),
        mode = pick(r, ['off', 'subtle', 'subtle', 'lively']);
      if (x < 0.25) ops.push(decay);
      else if (x < 0.5) ops.push(fold(pick(r, [0, 1, 2, 3, playerId === 1 ? 4 : 1]), mode));
      else if (x < 0.58) ops.push({ op: 'resetPressure', raiser: pick(r, [0, 1, 2, 3]) });
      else if (x < 0.63) ops.push({ op: 'clearPressure' });
      else if (x < 0.88) ops.push(finish(playerId, pick(r, [-5000, -1250, -1249, -600, -250, -249, 0, 75, 249, 250, 499, 500, 1200, 4000]) + (r() < 0.2 ? intBetween(r, -100, 100) : 0), mode));
      else ops.push({ op: 'axes', profile: pick(r, bots.BOT_PROFILES).id, mode });
    }
    runSequence(`random sequence ${i + 1} (seat ${playerId})`, ops);
  }
  outputs.set('mood.json', compactList(header('Mood state machine sequences; mood is shown after each operation.'), 'sequences', translateDeep(sequences)));
}

// --- Declarative game state for bot decisions --------------------------------------
function gameState(g) {
  return plain({
    hand: g.hand,
    phase: g.phase,
    street: g.street,
    dealer: g.dealer,
    actor: g.actor,
    pending: [...g.pending],
    currentBet: g.currentBet,
    minRaise: g.minRaise,
    board: keysOf(g.board),
    difficulty: g.difficulty,
    emotionMode: g.emotionMode,
    replayAttempt: g.replayAttempt ?? 0,
    history: g.history ?? [],
    players: g.players.map((p) => ({
      id: p.id,
      name: p.name,
      stack: p.stack,
      bet: p.bet,
      total: p.total,
      folded: p.folded,
      allin: p.allin,
      actedTo: p.actedTo,
      checked: p.checked,
      action: p.action,
      hole: keysOf(p.hole),
      botProfile: p.botProfile,
      botMood: moodOut(p.botMood),
    })),
  });
}
const viewOut = (v) => {
  const { hole, board, history, ...rest } = v;
  return rest;
};

// --- bot-decisions.json ------------------------------------------------------------
{
  const cases = [];
  const MOOD_REASON = {
    frustrated: '单手净损失至少 25 BB',
    cautious: '连续三手各净损失至少 5 BB',
    confident: '连续两手盈利，本手净赢至少 10 BB',
    reactive: '连续三手面对同一对手加注后弃牌',
  };
  for (let i = 0; cases.length < 180; i++) {
    const seed = 20000 + i,
      r = scriptStream(seed);
    useSeed(seed);
    const n = 5 + (i % 5),
      g = poker.newGame(n);
    poker.applyBotSettings(g, {
      emotionMode: ['off', 'subtle', 'lively'][i % 3],
      assignments: Object.fromEntries(Array.from({ length: 8 }, (_, k) => [k + 1, pick(r, bots.BOT_PROFILES).id])),
    });
    g.difficulty = ['easy', 'normal', 'hard'][Math.floor(i / 3) % 3];
    g.dealer = intBetween(r, 0, n - 1);
    g.players.forEach((p) => (p.stack = r() < 0.25 ? intBetween(r, 40, 1500) : r() < 0.5 ? 5000 : intBetween(r, 2000, 9000)));
    const target = i % 4;
    poker.startHand(g);
    let guard = 0;
    while (g.phase !== 'done' && ++guard < 400) {
      if (g.phase === 'between') {
        poker.advanceStreet(g);
        continue;
      }
      const l = poker.legalActions(g);
      if (g.street >= target && g.actor !== 0 && r() < (l.toCall > 0 ? 0.75 : 0.25)) break;
      const x = r();
      if (l.toCall > 0 && x < 0.1 && g.players.filter((p) => !p.folded).length > 2) poker.act(g, g.actor, 'fold');
      else if (l.canRaise && x < (target ? 0.2 : 0.45)) {
        const k = r();
        poker.act(g, g.actor, 'raise', k < 0.15 ? l.maxRaiseTo : k < 0.6 ? l.minRaiseTo : intBetween(r, l.minRaiseTo, Math.min(l.maxRaiseTo, l.minRaiseTo + 600)));
      } else poker.act(g, g.actor, 'call');
    }
    Math.random = forbiddenRandom;
    if (g.phase !== 'playing' || g.actor === 0) continue;
    const p = g.players[g.actor];
    const kind = pick(r, ['steady', 'steady', 'frustrated', 'cautious', 'confident', 'reactive']);
    if (kind !== 'steady') {
      p.botMood.kind = kind;
      p.botMood.reason = MOOD_REASON[kind];
      p.botMood.remaining = intBetween(r, 1, 3);
      p.botMood.cooldown = p.botMood.remaining + 1;
    }
    const trials = i % 11 === 7 ? intBetween(r, 1, 12) : undefined;
    const state = gameState(g);
    const decisionSeed = 300000 + i,
      timingSeed = 400000 + i;
    const random = counted(mulberry32(decisionSeed));
    const decision = poker.botDecision(g, random, trials === undefined ? {} : { trials });
    const timingRandom = counted(mulberry32(timingSeed));
    const thinking = timing.botThinkingTime(decision, timingRandom);
    const { view, ...trace } = decision.trace;
    cases.push({
      name: `bot decision ${cases.length + 1}: street ${g.street}, ${n} seats, seat ${p.id} ${p.botProfile}, ${g.emotionMode}, ${g.difficulty}, mood ${p.botMood.kind}`,
      state,
      ...(trials === undefined ? {} : { trials }),
      decisionSeed,
      timingSeed,
      decision: { action: decision.action, ...(decision.amount === undefined ? {} : { amount: decision.amount }) },
      trace,
      view: viewOut(view),
      decisionDraws: random.draws,
      thinking,
      timingDraws: timingRandom.draws,
    });
  }
  // A few error cases.
  const errors = [];
  {
    useSeed(1);
    const g = poker.newGame();
    poker.startHand(g);
    Math.random = forbiddenRandom;
    for (const t of [0, -3]) {
      let code = null;
      try {
        poker.botDecision(g, mulberry32(1), { trials: t });
      } catch (e) {
        code = errorCode(e);
      }
      errors.push({ state: gameState(g), trials: t, error: code });
    }
    g.actor = -1;
    let code = null;
    try {
      poker.botDecision(g, mulberry32(1));
    } catch (e) {
      code = errorCode(e);
    }
    errors.push({ state: gameState(g), error: code });
  }
  outputs.set(
    'bot-decisions.json',
    compactList({ ...header('botDecision and botThinkingTime on declarative game states.'), errors: translateDeep(errors) }, 'cases', translateDeep(plain(cases))),
  );
}

// --- simulations.json ----------------------------------------------------------------
{
  const sims = [];
  for (let k = 0; k < 14; k++) {
    const seed = 50000 + k,
      r = scriptStream(seed),
      n = 5 + (k % 5),
      handsToPlay = 6 + (k % 5);
    const settings = {
      emotionMode: ['lively', 'subtle', 'off'][k % 3],
      assignments: Object.fromEntries(Array.from({ length: 8 }, (_, i) => [i + 1, pick(r, bots.BOT_PROFILES).id])),
    };
    const difficulty = ['normal', 'hard', 'easy'][Math.floor(k / 3) % 3];
    const stacks = k % 4 === 2 ? Array.from({ length: n }, () => intBetween(r, 300, 2500)) : null;
    const stream = useSeed(seed);
    const g = poker.newGame(n);
    poker.applyBotSettings(g, settings);
    g.difficulty = difficulty;
    if (stacks) g.players.forEach((p, i) => (p.stack = stacks[i]));
    const hands = [];
    let chips = g.players.reduce((s, p) => s + p.stack, 0);
    for (let h = 0; h < handsToPlay; h++) {
      chips += 5000 * g.players.filter((p) => p.stack === 0).length;
      poker.startHand(g);
      const dealt = { hand: g.hand, dealer: g.dealer, holes: g.players.map((p) => keysOf(p.hole)), stacksAtDeal: g.players.map((p) => p.stack + p.bet), drawsAfterDeal: stream.draws };
      const actions = [];
      let guard = 0;
      while (g.phase !== 'done') {
        if (++guard > 500) throw Error('simulation stalled');
        if (g.phase === 'between') {
          poker.advanceStreet(g);
          continue;
        }
        const id = g.actor;
        if (id === 0) {
          const d = poker.botDecision(g);
          poker.act(g, 0, d.action, d.amount);
          actions.push({ id, action: d.action, ...(d.amount === undefined ? {} : { amount: d.amount }), reason: d.trace.reason, draws: stream.draws });
        } else {
          const plan = poker.planBotTurn(g);
          const d = poker.executeBotTurn(g, plan);
          actions.push({ id, action: d.action, ...(d.amount === undefined ? {} : { amount: d.amount }), reason: d.trace.reason, delayMs: plan.delayMs, draws: stream.draws });
        }
        if (wealth(g) !== chips) throw Error(`simulation ${seed}: chip conservation failed`);
      }
      const total = g.players.reduce((s, p) => s + p.stack, 0);
      if (total !== chips) throw Error(`simulation ${seed}: chip conservation failed at settlement`);
      hands.push({
        ...dealt,
        board: keysOf(g.board),
        history: g.history,
        actions,
        showdown: !!g.showdown,
        pots: g.pots,
        refunds: g.refunds,
        payouts: g.payouts,
        winners: g.winners,
        result: g.result,
        stacks: g.players.map((p) => p.stack),
        totalChips: total,
        stats: { ...g.stats },
        botStats: g.players.map((p) => ({ ...p.botStats })),
        moods: g.players.map((p) => moodOut(p.botMood)),
        decisions: g.decisions.length,
        thinkingMs: g.botDecisions.map((b) => b.trace.thinking.durationMs),
        logs: g.logs,
        drawsAfterHand: stream.draws,
      });
    }
    Math.random = forbiddenRandom;
    sims.push({ name: `simulation ${k + 1}: ${n} seats, ${settings.emotionMode}, ${difficulty}`, seed, playerCount: n, settings, difficulty, ...(stacks ? { stacks } : {}), hands });
  }
  outputs.set('simulations.json', compactList(header('All-bot multi-hand simulations on one seeded stream.'), 'cases', translateDeep(plain(sims))));
}

// ---------------------------------------------------------------------------
// Review fixtures (src/review/*.js)
// ---------------------------------------------------------------------------
// Inputs are hero decision snapshots (g.decisions) and review inputs
// (createReviewInput) captured from seeded hands, plus the snapshots built by
// the reference review unit tests. Every review call is deterministic: the
// review modules draw only from seedRandom streams derived from snapshotSeed,
// so Math.random stays forbidden while they run. Review copy is translated by
// scripts/review-copy.mjs, which throws on any untranslated text. The schema is
// documented in fixtures/README.md (Review section).
{
  const A = await load('src/review/analysis.js'),
    C = await load('src/review/context.js'),
    E = await load('src/review/equity.js'),
    P = await load('src/review/preflop.js'),
    RT = await load('src/review/routes.js'),
    CF = await load('src/review/counterfactual.js'),
    O = await load('src/review/opponents.js');
  // Expensive deterministic calls run on a worker pool; results are identical
  // to calling them here (each call seeds itself from the snapshot).
  const { Worker } = await import('node:worker_threads');
  const { availableParallelism } = await import('node:os');
  const workers = Array.from({ length: Math.max(1, Math.min(8, availableParallelism())) }, () =>
    new Worker(new URL('./review-fixture-worker.mjs', import.meta.url), { workerData: { referenceRoot } }),
  );
  const waiting = new Map(),
    queue = [];
  let nextId = 0;
  const idle = [...workers];
  const pump = () => {
    while (idle.length && queue.length) {
      const w = idle.pop(),
        job = queue.shift();
      w.job = job;
      w.postMessage({ id: job.id, fn: job.fn, args: job.args });
    }
  };
  for (const w of workers)
    w.on('message', ({ id, result, error }) => {
      const job = waiting.get(id);
      waiting.delete(id);
      idle.push(w);
      pump();
      if (error) job.reject(Error(error));
      else job.resolve(result);
    });
  const remote = (fn, ...args) =>
    new Promise((resolve, reject) => {
      const job = { id: nextId++, fn, args, resolve, reject };
      waiting.set(job.id, job);
      queue.push(job);
      pump();
    });
  const REDUCED = { trials: 60 }; // analyzeDecision reduced variant (rolloutTrials 12)
  const SAMPLE_TRIALS = [600, 25];
  const COMPARE_REDUCED_TRIALS = 4;
  const ROUTE_CODES = [
    'late-open',
    'late-isolation',
    'early-suited-entry',
    'squeeze-candidate',
    'weak-threebet-defense',
    'weak-fourbet-defense',
    'weak-entry',
    'pressure-bet',
    'value-bet',
    'priced-call',
  ];
  const out = (v) => translateReviewDeep(plain(v));
  const finite = (v, path = '') => {
    if (typeof v === 'number' && !Number.isFinite(v)) throw Error(`Non-finite number in review fixture at ${path}`);
    if (Array.isArray(v)) v.forEach((x, i) => finite(x, `${path}[${i}]`));
    else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) finite(x, `${path}.${k}`);
    return v;
  };
  const same = (a, b, what) => {
    if (JSON.stringify(a) !== JSON.stringify(b)) throw Error(`Review fixture mismatch: ${what}`);
  };
  const withoutDealer = (s) => {
    const copy = jsonCopy(s);
    delete copy.dealer;
    return copy;
  };

  // rangeWeight samples: four fixed starting-hand classes plus four seeded
  // random pairs from the cards the hero cannot see, for each live opponent.
  function rangeSamples(s, r) {
    const known = new Set([...s.hole, ...s.board].map((c) => c.key)),
      available = DECK.filter((c) => !known.has(c.key));
    const pairs = [];
    for (const [hi, lo, suited] of [
      [14, 14, false],
      [14, 13, true],
      [12, 11, true],
      [7, 2, false],
    ]) {
      const a = available.find((c) => c.rank === hi);
      const b = a && available.find((c) => c !== a && c.rank === lo && (suited ? c.suit === a.suit : c.suit !== a.suit));
      if (a && b) pairs.push([a, b]);
    }
    for (let k = 0; k < 4; k++) {
      const i = Math.floor(r() * available.length);
      let j = Math.floor(r() * (available.length - 1));
      if (j >= i) j++;
      pairs.push([available[i], available[j]]);
    }
    const rows = [];
    for (const p of s.players.filter((p) => p.id !== 0 && !p.folded))
      for (const pair of pairs) rows.push({ opponent: p.id, pair: keysOf(pair), weight: E.rangeWeight(pair, s, p) });
    return rows;
  }

  const decisionCases = [];
  let compareDefaultCount = 0;
  // Builds one decision case. `extra` adds reference-test specific calls.
  const pendingWork = [];
  function decisionCase(name, s, options = {}) {
    const slot = decisionCases.length;
    decisionCases.push(null);
    const work = buildDecisionCase(slot, name, s, options).then((row) => (decisionCases[slot] = row.row) && row);
    pendingWork.push(work);
    return work;
  }
  async function buildDecisionCase(slot, name, s, { hand = null, testOptions, rangeWeights = [], fullCompare = false, extraCandidates = [] } = {}) {
    const saved = JSON.stringify(s);
    const r = scriptStream(E.snapshotSeed(s));
    const ctx = C.decisionContext(s);
    const price = E.callPrice(s);
    const sampleValue = [];
    for (const trials of SAMPLE_TRIALS)
      for (const weighted of [false, true])
        sampleValue.push({ trials, weighted, result: E.sampleValue(s, price, trials, weighted) });
    const [full, reduced, noSim] = await Promise.all([
      remote('analyzeDecision', s, undefined),
      remote('analyzeDecision', s, REDUCED),
      remote('analyzeDecision', withoutDealer(s), undefined),
    ]);
    if (noSim.simulation !== null) throw Error('noSimulation variant ran a simulation');
    const pre = s.street === 0 ? P.preflopContext(s) : null;
    const routes = [];
    const routeArgs = { code: noSim.code, status: noSim.status, alternative: noSim.alternative };
    const actual = RT.comparisonRoutes(s, ctx, { ...routeArgs, pre });
    same(actual, noSim.routes, `${name} comparisonRoutes`);
    routes.push({ args: { ...routeArgs, withPreflopContext: !!pre }, result: actual });
    if (slot % 3 === 0) {
      const preAlways = P.preflopContext(s);
      for (const code of ROUTE_CODES)
        for (const alternative of CF.candidateActions(s).slice(0, 4)) {
          const args = { code, status: 'sound', alternative };
          routes.push({ args: { ...args, withPreflopContext: true }, result: RT.comparisonRoutes(s, ctx, { ...args, pre: preAlways }) });
        }
    }
    const alternatives = [full.alternative, full.routes.secondary];
    const compare = [];
    const simulates = Number.isInteger(s.dealer) && s.players.every((p) => 'actedTo' in p);
    if (fullCompare && simulates) {
      compare.push({ alternatives: [], trials: 40, result: await remote('compareCandidateActions', s, [], undefined) });
      compareDefaultCount++;
    }
    if (simulates)
      compare.push({
      alternatives: [noSim.alternative, noSim.routes.secondary],
      trials: COMPARE_REDUCED_TRIALS,
      result: await remote('compareCandidateActions', s, [noSim.alternative, noSim.routes.secondary], { trials: COMPARE_REDUCED_TRIALS }),
    });
    const tests = testOptions ? { options: testOptions, result: await remote('analyzeDecision', s, testOptions) } : undefined;
    if (JSON.stringify(s) !== saved) throw Error(`${name}: review mutated the snapshot`);
    const row = {
      name,
      hand,
      snapshot: s,
      startingTier: C.startingTier(s.hole),
      drawInfo: C.drawInfo(s.hole, s.board),
      boardTexture: C.boardTexture(s.board),
      decisionContext: ctx,
      preflopContext: P.preflopContext(s),
      snapshotSeed: E.snapshotSeed(s),
      callPrice: price,
      rangeWeight: [...rangeWeights.map(([pair, opponent]) => ({ opponent: opponent.id, pair: keysOf(pair), weight: E.rangeWeight(pair, s, opponent) })), ...rangeSamples(s, r)],
      sampleValue,
      candidateActions: [
        { alternatives: [], result: CF.candidateActions(s) },
        { alternatives, result: CF.candidateActions(s, alternatives) },
        ...extraCandidates.map((alts) => ({ alternatives: alts, result: CF.candidateActions(s, alts) })),
      ],
      comparisonRoutes: routes,
      compareCandidateActions: compare,
      analyzeDecision: { default: full, reduced: { options: REDUCED, result: reduced }, noSimulation: noSim, ...(tests ? { test: tests } : {}) },
    };
    return { row: finite(out(row)), index: slot, full, reduced };
  }

  // --- Seeded hands ----------------------------------------------------------
  const HOLES = ['Ac 7h', 'Qs 7s', 'As Ah', 'Qs Qh', 'Kd 2c', '8s 9s', 'Ah Kh', '5c 5d', 'Jh Th', 'Ac 4c', '7s 2h', 'Kc Qd', 'Ad 9d', '3h 3s'];
  const BOARDS = ['As Ks Qs Js Ts', 'Kd Ks 4c 9h 2s', 'Ah 7h 2h 9c 3d', '6c 7d Kc 8h 2d', 'Qd Jd 4s 4h Qc', '9s 8s 2d Td 5c', 'Jc 7d 2s 2c 7h', '4h 5h 6h 7c Ks'];
  const MOOD_REASON_ZH = {
    frustrated: '单手净损失至少 25 BB',
    cautious: '连续三手各净损失至少 5 BB',
    confident: '连续两手盈利，本手净赢至少 10 BB',
    reactive: '连续三手面对同一对手加注后弃牌',
  };
  // Moves the wanted card keys into the given slots ([array, index] pairs),
  // swapping with wherever they are now, so the 52 cards stay unique.
  function placeCards(g, wanted, slots) {
    const all = [...g.players.flatMap((p) => p.hole.map((_, i) => [p.hole, i])), ...g.deck.map((_, i) => [g.deck, i])];
    wanted.forEach((key, k) => {
      const [ta, ti] = slots[k];
      const from = all.find(([a, i]) => a[i].key === key);
      if (!from) throw Error(`placeCards: ${key} not available`);
      const [fa, fi] = from;
      [ta[ti], fa[fi]] = [fa[fi], ta[ti]];
    });
  }
  const boardSlots = (g) => {
    const L = g.deck.length;
    // Pop order: burn, flop x3, burn, turn, burn, river.
    return [L - 2, L - 3, L - 4, L - 6, L - 8].map((i) => [g.deck, i]);
  };
  function heroChoice(g, r, style) {
    const l = poker.legalActions(g, 0),
      x = r();
    const raiseTo = () => {
      const k = r();
      const target =
        k < 0.3 ? l.minRaiseTo : k < 0.55 ? Math.round((g.currentBet ? g.currentBet * 3 : poker.potSize(g) * 0.66) / 25) * 25 : k < 0.75 ? l.maxRaiseTo : intBetween(r, l.minRaiseTo, l.maxRaiseTo);
      return Math.min(l.maxRaiseTo, Math.max(l.minRaiseTo, target));
    };
    const pFold = { call: 0.08, raise: 0.12, tight: 0.45, mixed: 0.22, shove: 0.2 }[style],
      pRaise = { call: 0.1, raise: 0.55, tight: 0.15, mixed: 0.3, shove: 0.5 }[style];
    if (l.canCheck && x < (style === 'tight' ? 0.12 : 0.03)) return { action: 'fold' };
    if (!l.canCheck && x < pFold) return { action: 'fold' };
    if (l.canRaise && x < pFold + pRaise) return { action: 'raise', amount: style === 'shove' && r() < 0.6 ? l.maxRaiseTo : raiseTo() };
    return { action: l.canCheck && r() < 0.85 ? 'check' : 'call' };
  }
  function opponentChoice(g, r) {
    const l = poker.legalActions(g),
      raises = g.history.filter((a) => a.street === g.street && a.action === 'raise').length,
      x = r();
    if (!l.canCheck && x < 0.2) return { action: 'fold' };
    if (l.canRaise && raises < 4 && x < 0.5) {
      const k = r();
      return { action: 'raise', amount: k < 0.2 ? l.maxRaiseTo : k < 0.6 ? l.minRaiseTo : intBetween(r, l.minRaiseTo, Math.min(l.maxRaiseTo, l.minRaiseTo + 900)) };
    }
    return { action: l.canCheck ? 'check' : 'call' };
  }
  // Plays one hand; returns the game and the executed action list.
  function playReviewHand(cfg) {
    const stream = useSeed(cfg.seed),
      r = scriptStream(cfg.seed);
    const g = poker.newGame(cfg.n);
    poker.applyBotSettings(g, cfg.settings);
    g.difficulty = cfg.difficulty;
    g.dealer = cfg.dealer;
    cfg.stacks.forEach((stack, i) => (g.players[i].stack = stack));
    poker.startHand(g);
    if (cfg.hole) placeCards(g, parseKeys(cfg.hole), g.players[0].hole.map((_, i) => [g.players[0].hole, i]));
    if (cfg.board) placeCards(g, parseKeys(cfg.board), boardSlots(g));
    if (cfg.hidden) cfg.hidden(g);
    for (const [id, kind] of cfg.moods ?? []) {
      Object.assign(g.players[id].botMood, { kind, reason: MOOD_REASON_ZH[kind], remaining: 2, cooldown: 3 });
    }
    const actions = [];
    let guard = 0;
    while (g.phase !== 'done') {
      if (++guard > 500) throw Error('review hand stalled');
      if (g.phase === 'between') {
        poker.advanceStreet(g);
        continue;
      }
      const id = g.actor;
      if (cfg.replay) {
        const a = cfg.replay[actions.length];
        if (!a || a.id !== id) throw Error('privacy replay diverged');
        poker.act(g, id, a.action, a.amount);
        actions.push(a);
        continue;
      }
      let choice;
      if (id === 0) choice = cfg.heroScript?.[g.decisions.length] ?? heroChoice(g, r, cfg.style);
      else if (cfg.opponents === 'bots' || (cfg.opponents === 'mixed' && id % 2 === 1)) {
        const plan = poker.planBotTurn(g);
        const d = poker.executeBotTurn(g, plan);
        actions.push({ id, action: d.action, ...(d.amount === undefined ? {} : { amount: d.amount }) });
        continue;
      } else choice = opponentChoice(g, r);
      poker.act(g, id, choice.action, choice.amount);
      actions.push({ id, action: choice.action, ...(choice.amount === undefined ? {} : { amount: choice.amount }) });
    }
    Math.random = forbiddenRandom;
    return { g, actions, draws: stream.draws };
  }
  function handConfig(i) {
    const seed = 61000 + i,
      r = scriptStream(seed ^ 0x2f6b),
      n = 5 + (i % 5);
    const stacks = Array.from({ length: n }, (_, id) => {
      if (i % 3 === 0 && id > 0 && r() < 0.45) return intBetween(r, 60, 1400);
      if (i % 7 === 3 && id === 0) return intBetween(r, 90, 420);
      return r() < 0.15 ? intBetween(r, 2000, 9000) : 5000;
    });
    const emotionMode = ['lively', 'subtle', 'off'][i % 3];
    return {
      seed,
      n,
      dealer: intBetween(r, 0, n - 1),
      stacks,
      settings: { emotionMode, assignments: Object.fromEntries(Array.from({ length: 8 }, (_, k) => [k + 1, pick(r, bots.BOT_PROFILES).id])) },
      difficulty: ['normal', 'hard', 'easy'][Math.floor(i / 3) % 3],
      opponents: ['bots', 'mixed', 'scripted', 'bots'][i % 4],
      style: ['call', 'raise', 'tight', 'mixed', 'shove', 'call'][Math.floor(i / 2) % 6],
      hole: i % 2 === 0 ? HOLES[(i / 2) % HOLES.length] : null,
      board: i % 5 === 1 ? BOARDS[Math.floor(i / 5) % BOARDS.length] : null,
      moods: emotionMode === 'off' ? [] : [[1 + (i % (n - 1)), ['frustrated', 'cautious', 'confident', 'reactive'][i % 4]]],
    };
  }
  const handCases = [];
  const explainCases = [];
  function reviewHand(name, cfg, played = playReviewHand(cfg)) {
    const slot = handCases.length;
    handCases.push(null);
    pendingWork.push(buildHandCase(slot, name, cfg, played).then((row) => (handCases[slot] = row)));
  }
  async function buildHandCase(slot, name, cfg, { g }) {
    const input = A.createReviewInput(g);
    const decisionRefs = [],
      work = [];
    for (const s of input.decisions) {
      decisionRefs.push(decisionCases.length);
      work.push(decisionCase(`${name} · decision ${s.index + 1}`, s, { hand: slot, fullCompare: decisionCases.length % 2 === 0 }));
    }
    const done = await Promise.all(work);
    const steps = done.map((d) => d.full),
      reducedSteps = done.map((d) => d.reduced);
    const summary = A.summarizeReview(input, steps);
    const reduced = A.summarizeReview(input, reducedSteps);
    const strip = ({ steps, ...rest }) => rest;
    const explanations = input.opponents.map((record) => O.explainOpponent(record));
    return finite(
        out({
          name,
          seed: cfg.seed,
          playerCount: cfg.n,
          input,
          decisions: decisionRefs,
          analyzeReview: { options: {}, summary: strip(summary) },
          analyzeReviewReduced: { options: REDUCED, summary: strip(reduced) },
          explainOpponent: explanations,
        }),
      );
  }
  for (let i = 0; i < 44; i++) {
    const cfg = handConfig(i);
    reviewHand(`review hand ${i + 1}: ${cfg.n} seats, ${cfg.opponents} opponents, hero ${cfg.style}`, cfg);
  }

  // --- Reference unit-test scenarios ---------------------------------------
  const cardsOf = (s) => (s ? parseKeys(s).map(card) : []);
  // review-context.test.js decision() helper.
  function contextDecision({ hole = 'Qs Qh', board = 'Js 7h 2c', street = 1, action = 'check', amount = 0, stack = 5000, currentBet = 0, pot = 300 } = {}) {
    return {
      index: 0, hand: 1, hole: cardsOf(hole), board: cardsOf(board), street, action, amount, position: 'BTN', stack, bet: 0, total: pot / 2, pot, currentBet, minRaise: 50, pending: [0],
      players: [
        { id: 0, name: '你', position: 'BTN', total: pot / 2, bet: 0, stack, folded: false, allin: false },
        { id: 1, name: 'Mia', position: 'BB', total: pot / 2, bet: currentBet, stack, folded: false, allin: false },
      ],
      history: [],
      legal: { enabled: true, canCheck: currentBet === 0, canRaise: true, toCall: currentBet, callAmount: currentBet, minRaiseTo: currentBet + 50, maxRaiseTo: stack },
    };
  }
  const ctxOpt = { trials: 120 };
  decisionCase('review-context: overpair', contextDecision(), { testOptions: ctxOpt });
  decisionCase('review-context: top pair with ace kicker', contextDecision({ hole: 'As Jh' }), { testOptions: ctxOpt });
  decisionCase('review-context: public pair is not a value check', contextDecision({ hole: 'As Kh', board: '7s 7h 2c' }), { testOptions: ctxOpt });
  decisionCase('review-context: deep pocket queens shove', contextDecision({ street: 0, board: '', action: 'raise', amount: 5000, pot: 75, currentBet: 50 }), { testOptions: ctxOpt });
  decisionCase('review-context: short aces shove', contextDecision({ hole: 'As Ah', street: 0, board: '', stack: 1000, action: 'raise', amount: 1000, currentBet: 50, pot: 75 }), { testOptions: ctxOpt });
  decisionCase('review-context: four-suit board without a flush', contextDecision({ hole: 'Kh Kc', board: 'Ks 7s 2s 4s', street: 2 }), { testOptions: ctxOpt });
  decisionCase('review-context: river heads-up enumeration on a royal board', contextDecision({ hole: '2h 3h', board: 'As Ks Qs Js Ts', street: 3 }), { testOptions: ctxOpt });
  decisionCase('review-context: sampling band with an all-win sample', contextDecision({ hole: 'As Ah', board: 'Ac Ad 2s', street: 1 }), { testOptions: { trials: 10 } });
  // review-check.test.js snapshot() helper.
  function checkSnapshot({ hole = '7s 2h', board = '2s 6h 9c Jd Qs', street = 3, action = 'call', amount = 100, position = 'BTN', totals = [100, 200, 0, 0, 0, 0], stacks = [1000, 1000, 0, 0, 0, 0], allins = [], pending = [0], currentBet = 200, canCheck = false, canRaise = true } = {}) {
    const players = totals.map((total, id) => ({
      id, name: ['你', 'Mia', 'Alex', 'River', 'Kai', 'Luna'][id], position, stack: stacks[id], total, bet: total, folded: id > 1 && total === 0, allin: allins.includes(id), action: id === 1 ? '下注 ' + currentBet : '',
    }));
    return {
      index: 0, hand: 1, street, position, hole: cardsOf(hole), board: board ? cardsOf(board) : [], stack: stacks[0], bet: totals[0], total: totals[0], pot: totals.reduce((a, b) => a + b, 0), currentBet, minRaise: 50,
      legal: { enabled: true, canCheck, canRaise, raiseReopened: canRaise, toCall: canCheck ? 0 : amount, callAmount: canCheck ? 0 : amount, minRaiseTo: currentBet + 50, maxRaiseTo: totals[0] + stacks[0] },
      pending, action, amount, players, history: [{ id: 1, street, action: 'raise', amount: currentBet }],
    };
  }
  const chkOpt = { trials: 100 };
  decisionCase('review-check: default river call', checkSnapshot(), { testOptions: chkOpt });
  decisionCase('review-check: free fold', checkSnapshot({ action: 'fold', canCheck: true, amount: 0, currentBet: 0, totals: [50, 50, 0, 0, 0, 0] }), { testOptions: chkOpt });
  decisionCase('review-check: weak early-position entry', checkSnapshot({ street: 0, board: '', position: 'UTG', totals: [0, 50, 25, 0, 0, 0], stacks: [1000, 1000, 1000, 1000, 1000, 1000], currentBet: 50, amount: 50 }), { testOptions: chkOpt });
  const strongAllIn = checkSnapshot({ hole: 'As Ah', street: 0, board: '', action: 'raise', amount: 1000, totals: [0, 50, 25, 0, 0, 0], stacks: [1000, 1000, 1000, 0, 0, 0], currentBet: 50 });
  decisionCase('review-check: strong all-in losing to a later runout', strongAllIn, { testOptions: chkOpt });
  const flopCall = checkSnapshot({ street: 1, board: '2s 6h 9c' });
  decisionCase('review-check: flop call graded without the outcome', flopCall, { testOptions: chkOpt });
  decisionCase('review-check: closed raise is never recommended', checkSnapshot({ hole: 'As Ah', street: 0, board: '', canRaise: false }), { testOptions: chkOpt });
  decisionCase('review-check: recommended raise is legal', checkSnapshot({ hole: 'As Ah', street: 0, board: '', currentBet: 50, totals: [0, 50, 25, 0, 0, 0], amount: 50 }), { testOptions: chkOpt });
  {
    const s = checkSnapshot({ totals: [50, 300, 300, 0, 0, 0], stacks: [50, 1000, 1000, 0, 0, 0], amount: 50, currentBet: 300, pending: [0] });
    s.players[2].folded = false;
    decisionCase('review-check: short-stack call price excludes unreachable side pots', s, { testOptions: chkOpt });
  }
  {
    const s = checkSnapshot({ totals: [100, 100, 300, 300, 0, 0], stacks: [200, 0, 1000, 1000, 0, 0], amount: 200, currentBet: 300, allins: [1] });
    s.players[2].folded = false;
    s.players[3].folded = false;
    decisionCase('review-check: main and side pots have distinct eligible opponents', s, { testOptions: chkOpt });
  }
  decisionCase('review-check: uncalled refunds', checkSnapshot({ totals: [25, 20, 0, 0, 0, 0], stacks: [1000, 0, 0, 0, 0, 0], allins: [1], amount: 25, currentBet: 50, canRaise: false }), { testOptions: chkOpt });
  {
    const s = checkSnapshot({ totals: [100, 200, 200, 0, 0, 0], stacks: [1000, 1000, 0, 0, 0, 0], amount: 100 });
    s.players[2].folded = true;
    decisionCase('review-check: folded contributions stay in the call price', s, { testOptions: chkOpt });
  }
  decisionCase('review-check: royal flush board ties', checkSnapshot({ hole: '2h 3h', board: 'As Ks Qs Js Ts', totals: [100, 200, 0, 0, 0, 0], amount: 100 }), { testOptions: chkOpt });
  {
    const s = checkSnapshot({ action: 'raise', amount: 125, totals: [100, 100, 0, 0, 0, 0], stacks: [25, 1000, 0, 0, 0, 0], currentBet: 100 });
    decisionCase('review-check: short all-in raise', s, { testOptions: chkOpt });
    const c = jsonCopy(s);
    c.action = 'call';
    c.legal.callAmount = 25;
    decisionCase('review-check: all-in call', c, { testOptions: chkOpt });
  }
  // Review inputs from the review-check tests (outcome never grades decisions).
  const syntheticInputs = [];
  const synth = (name, input, options) => {
    const result = A.analyzeReview(input, options);
    syntheticInputs.push(finite(out({ name, input, options, result })));
  };
  synth('review-check: strong all-in losing to a later runout', { hand: 1, decisions: [strongAllIn], outcome: { profit: -1000, folded: false, board: cardsOf('Ks Kh Kc Qd 2s') } }, chkOpt);
  synth('review-check: outcome A (Mia wins)', { hand: 1, decisions: [flopCall], outcome: { profit: -200, folded: false, board: cardsOf('2s 6h 9c As Ah'), result: 'Mia wins' } }, chkOpt);
  synth('review-check: outcome B (hero wins)', { hand: 1, decisions: [flopCall], outcome: { profit: 500, folded: false, board: cardsOf('2s 6h 9c 7h 7c'), result: 'You win' } }, chkOpt);
  synth('review-check: blind-only loss', { hand: 1, decisions: [], outcome: { profit: -25, folded: false } }, chkOpt);
  synth('review-check: blind-only loss (default options)', { hand: 1, decisions: [], outcome: { profit: -25, folded: false } }, {});
  // review-lines.test.js button flows (startHand shuffles with a seeded stream).
  const btnGame = (seed, hole = 'Ac 7h', limp = false) => {
    useSeed(seed);
    const g = poker.newGame();
    g.dealer = 5;
    poker.startHand(g);
    Math.random = forbiddenRandom;
    placeCards(g, parseKeys(hole), g.players[0].hole.map((_, i) => [g.players[0].hole, i]));
    while (g.actor !== 0) poker.act(g, g.actor, limp && g.actor === 5 ? 'call' : 'fold');
    return g;
  };
  const lineOpt = { trials: 120 };
  {
    const g = btnGame(71001);
    poker.act(g, 0, 'raise', 150);
    decisionCase('review-lines: A7 offsuit BTN open', g.decisions[0], { testOptions: lineOpt });
  }
  {
    const g = btnGame(71002, 'Ac 7h', true);
    poker.act(g, 0, 'raise', 200);
    decisionCase('review-lines: BTN isolation of a limper', g.decisions[0], { testOptions: lineOpt });
  }
  {
    const g = btnGame(71003);
    poker.act(g, 0, 'raise', 150);
    poker.act(g, 1, 'call');
    poker.act(g, 2, 'raise', 650);
    poker.act(g, 0, 'call');
    poker.act(g, 1, 'raise', 1800);
    poker.act(g, 2, 'call');
    poker.act(g, 0, 'call');
    g.decisions.forEach((s, k) => decisionCase(`review-lines: A7 open, 3-bet and 4-bet calls (decision ${k + 1})`, s, { testOptions: lineOpt }));
    poker.advanceStreet(g);
    while (g.actor !== 0) poker.act(g, g.actor, 'check');
    poker.act(g, 0, 'check');
    decisionCase('review-lines: same-street repeated calls count once', g.decisions.at(-1), { testOptions: lineOpt });
  }
  for (const [k, h] of ['Ac 7h', 'Ac 7c'].entries()) {
    const g = btnGame(71004 + k, h);
    poker.act(g, 0, 'raise', 150);
    poker.act(g, 1, 'raise', 350);
    poker.act(g, 2, 'fold');
    poker.act(g, 0, 'call');
    decisionCase(`review-lines: ${h === 'Ac 7h' ? 'offsuit' : 'suited'} weak ace 3-bet defense`, g.decisions[1], { testOptions: lineOpt });
  }
  {
    const g = btnGame(71006);
    poker.act(g, 0, 'raise', 150);
    g.players[1].stack = 850;
    poker.act(g, 1, 'raise', 875);
    poker.act(g, 2, 'fold');
    poker.act(g, 0, 'call');
    decisionCase('review-lines: calling a sole all-in closes the action', g.decisions.at(-1), { testOptions: lineOpt });
  }
  {
    const g = btnGame(71007);
    poker.act(g, 0, 'raise', 150);
    g.players[1].stack = 850;
    poker.act(g, 1, 'raise', 875);
    poker.act(g, 2, 'call');
    poker.act(g, 0, 'call');
    decisionCase('review-lines: all-in with another live opponent does not close', g.decisions.at(-1), { testOptions: lineOpt });
  }
  {
    useSeed(71008);
    const g = poker.newGame();
    g.dealer = 2;
    poker.startHand(g);
    Math.random = forbiddenRandom;
    placeCards(g, parseKeys('Qs 7s'), g.players[0].hole.map((_, i) => [g.players[0].hole, i]));
    poker.act(g, 0, 'raise', 150);
    decisionCase('review-lines: Q7 suited UTG open', g.decisions[0], { testOptions: lineOpt, fullCompare: true });
  }
  // Additional preflop lines that the reference tests do not reach:
  // late-position limp and fold (late-passive-entry) and a squeeze.
  for (const [k, action] of ['call', 'fold'].entries()) {
    const g = btnGame(71020 + k);
    poker.act(g, 0, action);
    decisionCase(`preflop line: BTN A7 offsuit ${action === 'call' ? 'limps' : 'folds'} when folded to`, g.decisions[0]);
  }
  {
    useSeed(71022);
    const g = poker.newGame();
    g.dealer = 5;
    poker.startHand(g);
    Math.random = forbiddenRandom;
    placeCards(g, parseKeys('Ac 5h'), g.players[0].hole.map((_, i) => [g.players[0].hole, i]));
    let seen = 0;
    while (g.actor !== 0) poker.act(g, g.actor, seen++ === 0 ? 'raise' : seen === 2 ? 'call' : 'fold', seen === 1 ? 150 : undefined);
    poker.act(g, 0, 'raise', 600);
    decisionCase('preflop line: BTN weak-ace squeeze over an open and a call', g.decisions[0], { fullCompare: true });
  }
  // review-lines: settled bot traces (LCG stream from the test) are separate from hero grading.
  {
    const lcg = (seed) => {
      let n = seed;
      return () => (n = (Math.imul(n, 1664525) + 1013904223) >>> 0) / 4294967296;
    };
    useSeed(71009);
    const g = poker.newGame();
    g.dealer = 2;
    poker.startHand(g);
    const rng = lcg(91);
    // Bot decisions use the test's LCG; thinking time uses the seeded stream.
    while (g.phase !== 'done') {
      if (g.phase === 'between') poker.advanceStreet(g);
      else if (g.actor === 0) poker.act(g, 0, poker.legalActions(g).canCheck ? 'check' : 'call');
      else poker.playBotTurn(g, rng);
    }
    Math.random = forbiddenRandom;
    reviewHand('review-lines: settled bot traces are separate from hero grading', { seed: 71009, n: 6 }, { g });
  }
  // counterfactual.test.js
  const cfSnap = (seed) => {
    useSeed(seed);
    const g = poker.newGame();
    g.dealer = 2;
    poker.startHand(g);
    Math.random = forbiddenRandom;
    poker.act(g, 0, 'call');
    return g.decisions[0];
  };
  {
    const s = cfSnap(72001);
    decisionCase('counterfactual: UTG limp', s, { fullCompare: true });
    const capped = jsonCopy(s);
    capped.legal.canRaise = false;
    capped.legal.callAmount = 25;
    capped.stack = 25;
    decisionCase('counterfactual: closed raising and a capped short-stack call', capped, { extraCandidates: [[{ action: 'raise', amount: 5000 }]] });
    const h = cardsOf('Qs 7s');
    const flat = jsonCopy(s);
    flat.history = [
      { id: 2, street: 0, action: 'raise', amount: 150 },
      { id: 1, street: 0, action: 'call', amount: 125 },
    ];
    const pairOf = (snap) => [[h, snap.players[1]]];
    decisionCase('counterfactual: flat caller before an unanswered 3-bet (step 1)', flat, { rangeWeights: pairOf(flat) });
    const flat2 = jsonCopy(flat);
    flat2.history.push({ id: 3, street: 0, action: 'raise', amount: 650 });
    decisionCase('counterfactual: flat caller before an unanswered 3-bet (step 2)', flat2, { rangeWeights: pairOf(flat2) });
    const flat3 = jsonCopy(flat2);
    flat3.history.push({ id: 1, street: 0, action: 'call', amount: 500 });
    decisionCase('counterfactual: flat caller who calls the 3-bet', flat3, { rangeWeights: pairOf(flat3) });
    const opener = jsonCopy(s);
    opener.history = [{ id: 1, street: 0, action: 'raise', amount: 150 }];
    decisionCase('counterfactual: opener before a 3-bet', opener, { rangeWeights: pairOf(opener) });
    const opener2 = jsonCopy(opener);
    opener2.history.push({ id: 2, street: 0, action: 'raise', amount: 650 }, { id: 1, street: 0, action: 'call', amount: 500 });
    decisionCase('counterfactual: opener who calls a 3-bet', opener2, { rangeWeights: pairOf(opener2) });
  }
  {
    useSeed(72002);
    const g = poker.newGame();
    g.dealer = 2;
    poker.startHand(g);
    while (g.street < 3) {
      if (g.phase === 'between') poker.advanceStreet(g);
      else poker.act(g, g.actor, 'call');
    }
    Math.random = forbiddenRandom;
    g.board = cardsOf('As Ks Qs Js Ts');
    placeCards(g, parseKeys('2h 3h'), g.players[0].hole.map((_, i) => [g.players[0].hole, i]));
    while (g.actor !== 0) poker.act(g, g.actor, 'check');
    poker.act(g, 0, 'check');
    decisionCase('counterfactual: river royal board splits exactly', g.decisions.at(-1), { fullCompare: true });
  }

  // --- explainOpponent on the reference-test record --------------------------
  {
    const v = {
      id: 1, hole: cardsOf('7s 2h'), board: [], street: 0, position: 'UTG', count: 6, stack: 5000, bet: 0, pot: 5000, currentBet: 5000, difficulty: 'normal', rivals: 1, equity: 0.07, contestable: 10000,
      history: [{ id: 0, street: 0, action: 'raise', amount: 5000 }], features: { draw: false, wet: false }, playsBoard: false,
      legal: { enabled: true, canCheck: false, canRaise: false, toCall: 5000, callAmount: 5000, minRaiseTo: 10000, maxRaiseTo: 5000 },
    };
    const d = bots.chooseBotAction(v, bots.BOT_PROFILES[0], bots.freshBotMood(), 'off', () => 0);
    const record = { id: 1, name: 'Mia', ...d, trace: { ...d.trace, view: v } };
    explainCases.push(finite(out({ name: 'review-lines: weak all-in call from a randomized exception', record, result: O.explainOpponent(record) })));
  }

  // --- Privacy: same public decisions, different hidden cards/deck/winners ----
  const privacyCases = [];
  for (const [k, base] of [
    { seed: 73001, n: 6, style: 'call', hole: 'Jh Th', board: null },
    { seed: 73002, n: 9, style: 'tight', hole: 'Ac 7h', board: null },
    { seed: 73003, n: 7, style: 'shove', hole: 'Qs Qh', board: null },
  ].entries()) {
    const cfg = {
      ...base,
      dealer: k,
      stacks: Array.from({ length: base.n }, (_, id) => (id === 2 ? 700 : 5000)),
      settings: { emotionMode: 'subtle', assignments: Object.fromEntries(Array.from({ length: 8 }, (_, i) => [i + 1, bots.BOT_PROFILES[(i + k) % bots.BOT_PROFILES.length].id])) },
      difficulty: 'normal',
      opponents: 'bots',
    };
    const a = playReviewHand(cfg);
    const inputA = A.createReviewInput(a.g);
    const lastBoard = new Set((inputA.decisions.at(-1)?.board ?? []).map((c) => c.key));
    const heroKeys = new Set(inputA.hole.map((c) => c.key));
    let variants = null;
    for (let attempt = 0; attempt < 20 && !variants; attempt++) {
      const shuffleR = mulberry32(74000 + k * 100 + attempt);
      const hidden = (g) => {
        // Permute every card the hero has not seen by the last decision.
        const slots = [...g.players.slice(1).flatMap((p) => p.hole.map((_, i) => [p.hole, i])), ...g.deck.map((_, i) => [g.deck, i])].filter(([arr, i]) => {
          const key = arr[i].key;
          return !heroKeys.has(key) && !lastBoard.has(key);
        });
        const keys = slots.map(([arr, i]) => arr[i]);
        for (let i = keys.length - 1; i > 0; i--) {
          const j = Math.floor(shuffleR() * (i + 1));
          [keys[i], keys[j]] = [keys[j], keys[i]];
        }
        slots.forEach(([arr, i], n) => (arr[i] = keys[n]));
      };
      const b = playReviewHand({ ...cfg, hidden, replay: a.actions });
      const inputB = A.createReviewInput(b.g);
      same(inputA.decisions, inputB.decisions, 'privacy decisions');
      if (JSON.stringify(inputA.outcome) !== JSON.stringify(inputB.outcome)) variants = [inputA, inputB];
    }
    if (!variants) throw Error('privacy case did not change the outcome');
    const results = [];
    for (const input of variants)
      results.push(A.summarizeReview(input, await Promise.all(input.decisions.map((s) => remote('analyzeDecision', s, REDUCED)))));
    same(results[0], results[1], 'privacy review output');
    privacyCases.push(finite(out({ name: `privacy ${k + 1}: ${base.n} seats, hero ${base.style}`, options: REDUCED, variants, result: results[0] })));
  }

  await Promise.all(pendingWork);
  await Promise.all(workers.map((w) => w.terminate()));
  // --- Errors -------------------------------------------------------------------
  const errors = [];
  const expectReviewError = (name, fn) => {
    let code = null;
    try {
      fn();
    } catch (e) {
      code = reviewErrorCode(e);
    }
    if (!code) throw Error(`${name}: expected a review error`);
    errors.push({ name, error: code });
  };
  {
    useSeed(75001);
    const g = poker.newGame();
    poker.startHand(g);
    Math.random = forbiddenRandom;
    expectReviewError('createReviewInput while the hand is playing', () => A.createReviewInput(g));
    errors.at(-1).fn = 'createReviewInput';
  }
  // Errors on review-decisions.json case 0 (the first decision of review hand 1).
  const raw = playReviewHand(handConfig(0)).g.decisions[0];
  same(out(raw), decisionCases[0].snapshot, 'error case snapshot');
  for (const [fn, list, call] of [
    ['analyzeDecision', [0, -5, 1.5], (trials) => A.analyzeDecision(raw, { trials })],
    ['compareCandidateActions', [1, 0, 2.5], (trials) => CF.compareCandidateActions(raw, [], { trials })],
  ])
    for (const trials of list) {
      expectReviewError(`${fn} trials ${trials}`, () => call(trials));
      Object.assign(errors.at(-1), { fn, decision: 0, options: { trials } });
    }
  const reviewErrorsEnglish = Object.fromEntries(Object.values(REVIEW_ERRORS).map(({ code, message }) => [code, message]));
  const tables = {
    streetNames: A.STREET_NAMES.map(translateReview),
    botReasonNames: Object.fromEntries(Object.entries(O.BOT_REASON_NAMES).map(([k, v]) => [k, translateReview(v)])),
    botCheckNames: Object.fromEntries(Object.entries(O.BOT_CHECK_NAMES).map(([k, v]) => [k, translateReview(v)])),
  };
  outputs.set(
    'review-decisions.json',
    compactList(
      header('Review functions on hero decision snapshots: context, equity, routes, counterfactual simulation and analyzeDecision.'),
      'cases',
      decisionCases,
    ),
  );
  outputs.set(
    'review-hands.json',
    compactList(
      { ...header('Review inputs per hand: analyzeReview summaries, explainOpponent for every bot record, privacy invariance and errors.'), errors: reviewErrorsEnglish, tables },
      'hands',
      handCases,
      { privacy: privacyCases, reviewInputs: syntheticInputs, explainOpponent: explainCases, errorCases: errors },
    ),
  );
  if (process.env.REVIEW_COPY_COVERAGE)
    for (const source of copySources()) if (!usedCopy.has(source) && !usedCopy.has(source.replace(/\\/g, ''))) console.error(`unused review copy: ${source}`);
  if (untranslated.size) throw Error(`Untranslated review copy:\n${[...untranslated].join('\n')}`);
  console.error(`review: ${decisionCases.length} decisions, ${handCases.length} hands, ${compareDefaultCount} default comparisons`);
}

Math.random = nativeRandom;

// ---------------------------------------------------------------------------
// Write or check
// ---------------------------------------------------------------------------
const fixtureDir = resolve(root, 'fixtures');
if (process.argv.includes('--check')) {
  const stale = [];
  for (const [name, text] of outputs) {
    const path = resolve(fixtureDir, name);
    if (!existsSync(path) || readFileSync(path, 'utf8') !== text) stale.push(name);
  }
  if (stale.length) throw Error(`Reference fixtures differ from the pinned source: ${stale.join(', ')}`);
  console.log(`${outputs.size} reference fixture files verified.`);
} else {
  mkdirSync(fixtureDir, { recursive: true });
  for (const [name, text] of outputs) {
    writeFileSync(resolve(fixtureDir, name), text);
    console.log(`Wrote fixtures/${name} (${(text.length / 1024).toFixed(0)} KiB)`);
  }
}
