// Generates the shared native fixtures in fixtures/ from the pinned reference.
//
//   node scripts/generate-reference-fixtures.mjs           # write fixtures
//   node scripts/generate-reference-fixtures.mjs --check   # verify every fixture file
//
// Every engine call that uses the reference default randomness runs with a
// seeded Mulberry32 stream (identical to src/review/equity.js seedRandom)
// installed as Math.random. Between fixture cases Math.random throws, so no
// unseeded randomness can leak into a fixture. Engine copy is translated into
// English by scripts/reference-copy.mjs, which throws on any untranslated text.
// The schema of every file is documented in fixtures/README.md.
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { writeFileSync, readFileSync, mkdirSync, existsSync } from 'node:fs';
import { translate, translateDeep } from './reference-copy.mjs';
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
