// Translation table for every string the pinned reference engine produces.
//
// The reference (src/engine/*.js) builds Chinese copy. The fixture generator
// passes every engine string through `translate(text)` so the fixtures carry the
// English copy that both native domain layers must produce byte for byte. This
// file is the single authority for engine copy; native code implements the same
// templates directly from structured data.
//
// English scheme
// --------------
// Numbers: every chip amount and hand number is rendered with en-US grouping
// ("1,800", "5,000"), including action captions where the reference prints raw
// digits. Card text in street logs keeps the reference form rank + suit symbol
// ("10♥ A♠").
//
// Player names: the hero "你" is "You"; bot names are already English.
//
// Seat action text (p.action, lastAction.text, decision players[].action):
//   弃牌 -> "Fold"            过牌 -> "Check"           跟注 N -> "Call N"
//   全下 N -> "All-In N"       全下 (street reset) -> "All-In"
//   小盲 N -> "SB N"           大盲 N -> "BB N"
//   "{k}-bet {verb} N" with verbs
//     开池至 -> "open to"  加注至 -> "raise to"  下注至 -> "bet to"
//     全下至 -> "all-in to"  短全下至 -> "short all-in to"
//   e.g. "3-bet raise to 650", "2-bet short all-in to 125".
// History betLabel is the caption without the amount ("2-bet open to").
// actionLabel / historyActionLabel: same forms; 全下跟注 N -> "All-In Call N".
//
// Activity log (type in brackets):
//   [street] 第 h 手开始 · 庄家 X        -> "Hand h begins · Button: X"
//   [info]   X 补充 5,000 虚拟筹码        -> "X rebuys 5,000 virtual chips" ("You rebuy …")
//   [blind]  A 小盲 25 · B 大盲 50        -> "A: SB 25 · B: BB 50"
//   [action] X {action}                  -> "X: {Action}" (e.g. "You: Call 100")
//   [street] 翻牌/转牌/河牌 · cards       -> "Flop · …" / "Turn · …" / "River · …"
//   [info]   第 h 手 · 第 k 次重打，原结算已撤回
//                                        -> "Hand h · Replay #k · previous settlement reversed"
//   [info]   练习补牌 · 五张公共牌已展示，弃牌结算不变
//                                        -> "Practice runout · all five community cards shown; the fold-win result is unchanged"
//   [result] {pot} N → A n / B n          -> "Main Pot 1,400 → Mia 700 / Alex 700"
//   [info]   X 未被跟注的 N 筹码已退还    -> "Uncalled 300 chips returned to X"
//   [result] settlement result (below)
//   [info]   X 模拟状态：{mood} · {reason} -> "X simulated mood: {Mood} · {Reason}"
//
// Settlement result (g.result): optional prefix "Split pots · ", then winners
// joined with " / ":
//   showdown: X {hand} · 获得 N 筹码 -> "X wins N chips · {Hand}" ("You win …")
//   fold-win: X 获胜 · 获得 N 筹码   -> "X wins N chips" ("You win …")
// Award / winner labels: hand category, or 其余玩家均已弃牌 -> "All other players folded".
// Pot labels: 主池 -> "Main Pot", 边池 k -> "Side Pot k".
// Hand categories: High Card, One Pair, Two Pair, Three of a Kind, Straight,
// Flush, Full House, Four of a Kind, Straight Flush, Royal Flush, Pocket Pair.
//
// `translate(text)` throws if any CJK character survives, so fixture coverage
// of engine copy is complete by construction.

export const CJK = /[　-〿㐀-鿿豈-﫿＀-￯]/;

export const groupNumber = (n) => Math.round(n).toLocaleString('en-US');
const parseNumber = (s) => Number(String(s).replace(/[^\d]/g, ''));
const fmt = (s) => groupNumber(parseNumber(s));

export const PLAYER_NAMES = { 你: 'You' };

export const HAND_LABELS = {
  高牌: 'High Card',
  一对: 'One Pair',
  两对: 'Two Pair',
  三条: 'Three of a Kind',
  顺子: 'Straight',
  同花: 'Flush',
  葫芦: 'Full House',
  四条: 'Four of a Kind',
  同花顺: 'Straight Flush',
  皇家同花顺: 'Royal Flush',
  口袋对子: 'Pocket Pair',
};

export const RAISE_VERBS = {
  开池至: 'open to',
  加注至: 'raise to',
  下注至: 'bet to',
  全下至: 'all-in to',
  短全下至: 'short all-in to',
};

export const MOOD_LABELS = {
  平稳: 'Steady',
  急于追回: 'Chasing Losses',
  收紧避险: 'Playing Safe',
  连胜自信: 'On a Heater',
  受压反击: 'Fighting Back',
};

export const MOOD_REASONS = {
  连续三手面对同一对手加注后弃牌: "Folded to the same opponent's raise three hands in a row",
  '单手净损失至少 25 BB': 'Lost at least 25 BB net in a single hand',
  '连续三手各净损失至少 5 BB': 'Lost at least 5 BB net in each of three straight hands',
  '连续两手盈利，本手净赢至少 10 BB': 'Won two hands in a row, at least 10 BB net this hand',
};

export const EMOTION_MODE_LABELS = { 关闭: 'Off', 轻微波动: 'Subtle', 明显波动: 'Pronounced' };

export const PROFILE_AXIS_LABELS = {
  入池宽度: 'Range Width',
  进攻倾向: 'Aggression',
  诈唬倾向: 'Bluffing',
  跟到底倾向: 'Calling Down',
  强牌诱导: 'Trapping',
};

// Bot profile display copy (bot-profiles.js BOT_PROFILES). These are training
// archetypes, not measured statistics of the named players.
export const PROFILE_COPY = {
  // balanced
  均衡练习: 'Balanced Practice',
  均衡: 'Balanced',
  稳定的基准对手: 'Steady baseline opponent',
  '中等范围、常规尺度，兼顾价值下注与少量诈唬。':
    'Medium range and standard sizing, mixing value bets with occasional bluffs.',
  '基准训练策略，不对应任何真人。':
    'Baseline training strategy; it does not represent any real player.',
  // tan
  '谈老板 · Tan Xuan': 'Johnny Tan · Tan Xuan',
  谈老板: 'Johnny Tan',
  '宽范围 · 多街施压': 'Wide range · Multi-street pressure',
  '更宽地争夺底池，弱牌与强牌共用进攻路线，偏好持续施压。':
    'Contests more pots with a wider range, takes the same aggressive lines with weak and strong hands, and prefers sustained pressure.',
  'Triton 现金桌报道记录了弱牌四下注和多街诈唬；本人短牌采访也自述喜欢宽松与诈唬。短牌频率不移植到本桌。':
    'Triton cash-game coverage documents a light 4-bet and multi-street bluffs; in a short deck interview he also says he likes playing loose and bluffing. Short deck frequencies are not carried over to this table.',
  'Triton · 现金桌进攻样本': 'Triton · Cash-game aggression sample',
  'Triton · 本人采访（短牌）': 'Triton · Player interview (short deck)',
  // st
  'ST 王': 'ST Wang',
  '选择性进攻 · 价值诱导': 'Selective aggression · Value traps',
  '收紧边缘入池，强牌在安全牌面诱导，也能面对大注及时止损。':
    'Tightens up marginal entries, slow-plays strong hands on safe boards, and still cuts losses against big bets.',
  '官方报道中，大池失利后的 AQ 仍能在河牌弃牌；另一手 AA 使用河牌过牌全下的价值陷阱。':
    'In official coverage he still folded AQ on the river right after losing a big pot; in another hand he set a river check-shove value trap with AA.',
  'Triton · 大输后保持纪律': 'Triton · Discipline after a big loss',
  'Triton · 强牌诱导': 'Triton · Trapping with a strong hand',
  // zang
  '臧书奴 · Aaron Zang': 'Aaron Zang',
  臧书奴: 'Aaron Zang',
  '经验进攻 · 河牌争夺': 'Seasoned aggression · River battles',
  '中宽范围，有位置时争夺底池，河牌保留主动加注与抓诈路线。':
    'Medium-wide range; fights for pots in position and keeps both river raising and bluff-catching lines.',
  'Triton 记录了河牌把 23k 小注加到 105k 的诈唬样本。单手不能说明其长期频率。':
    'Triton recorded a river bluff that raised a 23k bet to 105k. A single hand says nothing about long-run frequencies.',
  'Triton · 河牌进攻样本': 'Triton · River aggression sample',
  // peter
  '宽范围 · 大尺度搏杀': 'Wide range · Big-bet brawler',
  '更愿意跟入，强牌榨取大尺度价值，少量小口袋对子也会强力反击。':
    'More willing to call in, extracts big-bet value with strong hands, and occasionally fights back hard with small pocket pairs.',
  'HCL 记录了暗三条的河牌满池再加注；另一场有小口袋对子大推入。后者带 Stand-Up 附加规则，不能照搬整场频率。此处指 HCL 常客。':
    'HCL footage shows a pot-sized river re-raise with a set; another session shows a big shove with a small pocket pair. The latter was played under a Stand-Up side-game rule, so its frequencies cannot be copied over. "Peter" here refers to the HCL regular.',
  'HCL · 河牌价值加注': 'HCL · River value raise',
  'PokerNews · 小对子反击（附加规则）': 'PokerNews · Small-pair counterattack (side-game rule)',
  // abao
  '阿宝 · KPC A Bao': 'A Bao · KPC',
  阿宝: 'A Bao',
  '选择性压迫 · 半诈唬': 'Selective pressure · Semi-bluffs',
  '有听牌权益时更积极，小翻牌下注之后可用大转牌下注继续施压。':
    'More aggressive with draw equity; can follow a small flop bet with a big turn bet to keep up the pressure.',
  'KPC 详细牌局报道中，AJ 同花使用约 31% 池翻牌下注、90% 池转牌半诈唬；另有 98 同花听牌推入样本。本名未可靠确认。':
    'In detailed KPC hand coverage, suited AJ bet about 31% pot on the flop and semi-bluffed 90% pot on the turn; another sample shows a shove with a 98 flush draw. The player\'s real name has not been reliably confirmed.',
  'Pokerati · AJ 半诈唬牌局': 'Pokerati · AJ semi-bluff hand',
  'Pokerati · 同花听牌反击': 'Pokerati · Flush-draw counterattack',
  // viktor
  '松凶施压 · 宽范围争夺': 'Loose-aggressive pressure · Wide-range battles',
  '更宽地争夺后位和低成本底池，听牌与价值牌共用积极进攻路线，偏好较大尺度。':
    'Contests late-position and cheap pots more widely, takes the same aggressive lines with draws and value hands, and prefers larger sizes.',
  'PokerStars 原访谈与官方回顾支持其历史松凶风格。这里归纳的是训练原型，不是实时打法或真人频率；单挑经验不直接移植成多人精确参数。':
    'An original PokerStars interview and an official retrospective support his historical loose-aggressive style. This is a training archetype, not his current play or real frequencies; heads-up experience is not translated directly into precise multiway parameters.',
  'PokerStars · Viktor 原访谈': 'PokerStars · Original Viktor interview',
  'PokerStars · 历史诈唬回顾': 'PokerStars · Historic bluffs retrospective',
  // jungleman
  '计算型进攻 · 强牌诱导': 'Calculated aggression · Trapping strong hands',
  '保留有价格的防守，兼顾主动施压与强牌诱导；大额继续仍要通过权益和筹码压力检查。':
    'Defends when the price is right and balances proactive pressure with trapping strong hands; large continues must still pass the equity and stack-pressure checks.',
  '本人原访谈强调计算、观察实际行为并调整，避免机械平衡。当前机器人用范围和价格近似这些思路，未复刻职业级读人或动态学习。':
    'His own interviews stress calculation, watching what opponents actually do, and adjusting rather than balancing mechanically. This bot approximates those ideas with ranges and prices; it does not reproduce professional-level reads or dynamic learning.',
  'Card Player · Daniel Cates 原访谈': 'Card Player · Daniel Cates interview',
  'Card Player · 对手调整访谈': 'Card Player · Interview on adjusting to opponents',
  // dwan
  '创造性施压 · 多街诈唬': 'Creative pressure · Multi-street bluffs',
  '更积极争夺有位置的底池，在有进攻叙事或听牌时混合多街施压，也能用强牌保留对手范围。':
    "Fights harder for pots in position, mixes in multi-street pressure when he has a credible story or a draw, and can keep opponents' ranges wide with strong hands.",
  '原采访、同行评价和 PokerStars 回顾支持其历史创造性与多街诈唬风格。参数仅为可调的模拟倾向，不推断真人真实 VPIP 或心理状态。':
    "Original interviews, peer assessments, and a PokerStars retrospective support his historical creative, multi-street bluffing style. The parameters are only adjustable simulation tendencies; they do not infer the real player's VPIP or state of mind.",
  'Card Player · Dwan 原采访': 'Card Player · Original Dwan interview',
};

// Fixed engine sentences (no placeholders).
export const FIXED = {
  弃牌: 'Fold',
  过牌: 'Check',
  全下: 'All-In',
  主池: 'Main Pot',
  其余玩家均已弃牌: 'All other players folded',
  '练习补牌 · 五张公共牌已展示，弃牌结算不变':
    'Practice runout · all five community cards shown; the fold-win result is unchanged',
};

const EXACT = {
  ...PLAYER_NAMES,
  ...HAND_LABELS,
  ...MOOD_LABELS,
  ...MOOD_REASONS,
  ...EMOTION_MODE_LABELS,
  ...PROFILE_AXIS_LABELS,
  ...PROFILE_COPY,
  ...FIXED,
};

const STREET_NAMES = { 翻牌: 'Flop', 转牌: 'Turn', 河牌: 'River' };
const NUM = '(\\d[\\d,.\\u00a0\\u202f]*)';
const NAME = '(\\S+)';

export const translateName = (name) => PLAYER_NAMES[name] ?? name;
const isHero = (name) => translateName(name) === 'You';
const verb = (name, third, base) => `${translateName(name)} ${isHero(name) ? base : third}`;
const handLabel = (label) => {
  if (!Object.hasOwn(HAND_LABELS, label)) throw Error(`Unknown hand label: ${label}`);
  return HAND_LABELS[label];
};

// Bet caption without amount, e.g. "3-bet 加注至" -> "3-bet raise to".
function translateCaption(text) {
  const m = /^(\d+)-bet (\S+)$/.exec(text);
  if (!m || !Object.hasOwn(RAISE_VERBS, m[2])) return null;
  return `${m[1]}-bet ${RAISE_VERBS[m[2]]}`;
}

// Seat action text (p.action, lastAction.text, actionLabel output).
function translateAction(text) {
  if (Object.hasOwn(FIXED, text) && ['弃牌', '过牌', '全下'].includes(text)) return FIXED[text];
  let m;
  if ((m = new RegExp(`^跟注 ${NUM}$`).exec(text))) return `Call ${fmt(m[1])}`;
  if ((m = new RegExp(`^全下跟注 ${NUM}$`).exec(text))) return `All-In Call ${fmt(m[1])}`;
  if ((m = new RegExp(`^全下 ${NUM}$`).exec(text))) return `All-In ${fmt(m[1])}`;
  if ((m = new RegExp(`^小盲 ${NUM}$`).exec(text))) return `SB ${fmt(m[1])}`;
  if ((m = new RegExp(`^大盲 ${NUM}$`).exec(text))) return `BB ${fmt(m[1])}`;
  if ((m = new RegExp(`^(\\d+-bet \\S+) ${NUM}$`).exec(text))) {
    const caption = translateCaption(m[1]);
    if (caption) return `${caption} ${fmt(m[2])}`;
  }
  return translateCaption(text);
}

function translateWinner(part) {
  let m;
  if ((m = new RegExp(`^${NAME} 获胜 · 获得 ${NUM} 筹码$`).exec(part)))
    return `${verb(m[1], 'wins', 'win')} ${fmt(m[2])} chips`;
  if ((m = new RegExp(`^${NAME} (\\S+) · 获得 ${NUM} 筹码$`).exec(part)))
    return `${verb(m[1], 'wins', 'win')} ${fmt(m[3])} chips · ${handLabel(m[2])}`;
  return null;
}

const PATTERNS = [
  // Hand start.
  [new RegExp(`^第 ${NUM} 手开始 · 庄家 ${NAME}$`), (m) => `Hand ${fmt(m[1])} begins · Button: ${translateName(m[2])}`],
  // Replay line.
  [
    new RegExp(`^第 ${NUM} 手 · 第 ${NUM} 次重打，原结算已撤回$`),
    (m) => `Hand ${fmt(m[1])} · Replay #${fmt(m[2])} · previous settlement reversed`,
  ],
  // Rebuy.
  [new RegExp(`^${NAME} 补充 ${NUM} 虚拟筹码$`), (m) => `${verb(m[1], 'rebuys', 'rebuy')} ${fmt(m[2])} virtual chips`],
  // Blind log.
  [
    new RegExp(`^${NAME} 小盲 ${NUM} · ${NAME} 大盲 ${NUM}$`),
    (m) => `${translateName(m[1])}: SB ${fmt(m[2])} · ${translateName(m[3])}: BB ${fmt(m[4])}`,
  ],
  // Street deal.
  [/^(翻牌|转牌|河牌) · (.+)$/, (m) => `${STREET_NAMES[m[1]]} · ${m[2]}`],
  // Side pot label.
  [new RegExp(`^边池 ${NUM}$`), (m) => `Side Pot ${fmt(m[1])}`],
  // Pot award log: "{label} N → A n / B n".
  [
    new RegExp(`^(主池|边池 \\d+) ${NUM} → (.+)$`),
    (m) =>
      `${translate(m[1])} ${fmt(m[2])} → ` +
      m[3]
        .split(' / ')
        .map((part) => {
          const a = new RegExp(`^${NAME} ${NUM}$`).exec(part);
          if (!a) throw Error(`Unparsed award: ${part}`);
          return `${translateName(a[1])} ${fmt(a[2])}`;
        })
        .join(' / '),
  ],
  // Refund log.
  [new RegExp(`^${NAME} 未被跟注的 ${NUM} 筹码已退还$`), (m) => `Uncalled ${fmt(m[2])} chips returned to ${translateName(m[1])}`],
  // Mood event log.
  [
    new RegExp(`^${NAME} 模拟状态：(\\S+) · (.+)$`),
    (m) => {
      if (!Object.hasOwn(MOOD_LABELS, m[2]) || !Object.hasOwn(MOOD_REASONS, m[3])) return null;
      return `${translateName(m[1])} simulated mood: ${MOOD_LABELS[m[2]]} · ${MOOD_REASONS[m[3]]}`;
    },
  ],
  // Settlement result.
  [
    /^(分池结算 · )?(.+ 筹码)$/,
    (m) => {
      const parts = m[2].split(' / ').map(translateWinner);
      if (parts.some((p) => p === null)) return null;
      return (m[1] ? 'Split pots · ' : '') + parts.join(' / ');
    },
  ],
  // Action log: "{name} {action}".
  [
    /^(\S+) (.+)$/,
    (m) => {
      const action = translateAction(m[2]);
      return action ? `${translateName(m[1])}: ${action}` : null;
    },
  ],
];

export function translate(text) {
  if (typeof text !== 'string') throw TypeError('translate expects a string');
  if (!CJK.test(text)) return text;
  let out = null;
  if (Object.hasOwn(EXACT, text)) out = EXACT[text];
  if (out === null) out = translateAction(text);
  if (out === null)
    for (const [pattern, build] of PATTERNS) {
      const m = pattern.exec(text);
      if (m) {
        out = build(m);
        if (out !== null) break;
      }
    }
  if (out === null || CJK.test(out)) throw Error(`Untranslated engine copy: ${JSON.stringify(text)}`);
  return out;
}

// Translate every string inside a JSON-compatible value (object keys untouched).
export function translateDeep(value) {
  if (typeof value === 'string') return translate(value);
  if (Array.isArray(value)) return value.map(translateDeep);
  if (value && typeof value === 'object')
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, translateDeep(v)]));
  return value;
}
