// Translation table for every string the pinned reference review modules
// (src/review/*.js) produce.
//
// The reference builds Chinese review copy. The fixture generator passes every
// review string through `translateReview(text)` so the review fixtures carry the
// English copy that both native domain layers must produce byte for byte. This
// file is the authority for review copy (the English baseline is the review
// copy catalog; where this file and the catalog differ, this file wins because
// the fixtures are generated from it). Engine strings embedded in review output
// (action labels, hand names, pot labels, mood labels, player names) are
// translated by scripts/reference-copy.mjs.
//
// How strings are assembled
// -------------------------
// The reference concatenates Chinese sentence fragments without separators.
// The English port parses every review string into its source fragments, in
// order, translates each fragment, and joins the English fragments with one
// space. Optional fragments that are absent in the source are simply absent.
// Fragment boundaries follow the source exactly: a fragment that continues a
// sentence in Chinese (for example the weak-ace suffix of the late-open
// reason) is part of that sentence's template here.
//
// Numbers are copied from the reference output verbatim, so they keep the
// reference formatters: grouped integers ("1,800"), integer percents ("34%"),
// one-decimal percents ("12.3%", "-0.0%", "+1.5%"), toFixed(1) ratios ("2.5"),
// ungrouped counts and raw JS numbers for mood axes.
//
// Counts that the source writes as "N 位玩家/对手/人" use English singular for
// exactly 1 and plural otherwise ("1 player", "0 players", "2 players").
//
// Hand labels (decisionContext(s).handLabel) have two forms:
//   * mid-sentence: engine hand names per ENGINE_HAND_MID ("two pair",
//     "a straight"); review templates as listed in translateHandLabel
//     ("pocket Nines", "top pair (K) with an 8 kicker").
//   * start form, used at the start of a sentence, after ": ", and as a
//     standalone field value: the mid form with its first character
//     uppercased, except engine hand names keep their engine form ("Two Pair").
// Board texture labels and preflop situation labels follow the same rule:
// lowercase catalog phrases mid-sentence, first letter uppercased at the start
// of a sentence, after ": ", and as standalone field values.
//
// Rank words: "{rank}" is the engine rankText ("2".."10", "J", "Q", "K", "A");
// "{Ranks}" is the plural word: Twos, Threes, Fours, Fives, Sixes, Sevens,
// Eights, Nines, Tens, Jacks, Queens, Kings, Aces. The indefinite article
// before a kicker rank is "an" for 8 and A, otherwise "a".
//
// Every caveat of the source survives translation: candidate sizes are
// practice lines and not a GTO solution, equities are estimates under assumed
// ranges with sampling error, completion cards are not guaranteed winners,
// outcomes never grade decisions, and bot explanations describe the simulator,
// not real player psychology (named profiles are training archetypes).
//
// `translateReview(text)` throws if any CJK character survives, so fixture
// coverage of review copy is complete by construction.
import { CJK, translate as translateEngine, MOOD_LABELS, MOOD_REASONS, HAND_LABELS } from './reference-copy.mjs';

const hasOwn = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const cap = (s) => (s ? s[0].toUpperCase() + s.slice(1) : s);
const lowerFirst = (s) => (s ? s[0].toLowerCase() + s.slice(1) : s);
const plural = (n, one, many) => `${n} ${String(n) === '1' ? one : many}`;

// ---------------------------------------------------------------------------
// Lookups
// ---------------------------------------------------------------------------
export const STREET_NAMES = { 翻牌前: 'Preflop', 翻牌: 'Flop', 转牌: 'Turn', 河牌: 'River' };

export const RANK_PLURALS = {
  2: 'Twos', 3: 'Threes', 4: 'Fours', 5: 'Fives', 6: 'Sixes', 7: 'Sevens', 8: 'Eights',
  9: 'Nines', 10: 'Tens', J: 'Jacks', Q: 'Queens', K: 'Kings', A: 'Aces',
};
const rankPlural = (r) => {
  if (!hasOwn(RANK_PLURALS, r)) throw Error(`Unknown rank ${r}`);
  return RANK_PLURALS[r];
};
const article = (r) => (r === '8' || r === 'A' ? 'an' : 'a');

export const TEXTURE_TAGS = {
  公共牌三条: 'trips on board',
  公共牌有对子: 'paired',
  四张同花色: 'four to a flush',
  三张同花色: 'three to a flush',
  两张同花色: 'two-tone',
  四张连通: 'four to a straight',
  顺子连接明显: 'clearly straight-connected',
};
export const TEXTURE_DRY = { zh: '花色分散、连接较少', en: 'rainbow and disconnected' };

export const PREFLOP_LABELS = {
  '未加注，已有跛入': 'unraised, with limpers',
  无人主动入池: 'unopened pot',
  开池后已有平跟: 'open with callers',
  面对开池: 'facing an open',
  '面对 3-bet': 'facing a 3-bet',
  '面对 4-bet 或更多次加注': 'facing a 4-bet or more',
};

export const BOT_REASON_NAMES = {
  起手牌未进入本次防守范围: 'Hand outside this defending range',
  估计权益未达到跟注门槛: 'Estimated equity below the calling threshold',
  筹码压力触发收紧: 'Stack pressure triggered a tighter range',
  随机容错保留了边缘行动: 'Random leeway kept a marginal action',
  强起手牌分支保留继续: 'Premium-hand branch kept it in',
  低成本入池范围保留了继续: 'Low-cost entry range kept it in',
  小开池的价格与有效后手支持跟入: "Small open's price and effective stack supported calling",
  通过了价格与压力检查: 'Passed the price and pressure checks',
  主动加注范围触发进攻: 'Raising range triggered aggression',
  听牌半诈唬触发进攻: 'Draw triggered a semi-bluff',
  诈唬抽样触发主动施压: 'Bluff roll triggered pressure',
  干燥牌面强牌触发诱导过牌: 'Strong hand on a dry board triggered a trap check',
  '选择免费观察／控制底池': 'Took a free look / pot control',
};
export const BOT_CHECK_NAMES = {
  超出范围时的容错抽样: 'Leeway roll when outside range',
  权益不足时的容错抽样: 'Leeway roll when equity is short',
  高压力时的容错抽样: 'Leeway roll under high pressure',
  进攻频率抽样: 'Aggression frequency roll',
  诱导过牌抽样: 'Trap-check roll',
  小对子特殊全下抽样: 'Rare small-pair shove roll',
};

// Review error messages, by stable code.
export const REVIEW_ERRORS = {
  '牌局结束后才能复盘。': { code: 'review-not-ready', message: 'You can review a hand only after it ends.' },
  '抽样次数必须是正整数。': { code: 'invalid-review-trials', message: 'The sample count must be a positive integer.' },
  '模拟次数至少为 2。': { code: 'invalid-simulation-trials', message: 'The simulation needs at least 2 trials.' },
  '候选行动模拟未能结束。': { code: 'simulation-runaway', message: 'The candidate-action simulation did not finish.' },
};

// Fixed review sentences, titles, lessons, plans, route copy and notes.
export const REVIEW_FIXED = {
  // Statuses and confidence.
  依赖范围假设: 'Depends on range assumptions',
  规则与成本明确: 'Clear by rules and cost',
  '范围与后续策略敏感，未证明唯一最优': 'Sensitive to ranges and later strategy; no single best line shown',
  '两种范围抽样一致，但后续策略仍是模型': 'Both range samples agree, but later play is still a model',
  // Titles.
  '无需补筹码，弃牌放弃了免费机会': 'Folding when checking was free gave up a free chance',
  '后位隔离加注，要区分人数与跟注倾向':
    'Late-position isolation raise: account for the number of limpers and how often they call',
  后位主动开池有位置与弃牌权益依据: 'Late-position open is backed by position and fold equity',
  '多次再加注下，弱牌防守缺少支撑': 'Defending a weak hand against multiple re-raises lacks support',
  '可开池的牌，不等于可以宽接 3-bet': "A hand you can open isn't automatically a hand that can call a 3-bet",
  '后位可比较主动开池，而非只看起手牌档位': 'From late position, compare opening rather than going by hand tier alone',
  '挤压加注需要退出范围支持，A 阻断只是其中一项': 'A squeeze needs a range that will fold; the ace blocker is only one factor',
  '早位边缘同花牌，开池取决于后面防守范围':
    'Marginal suited hand in early position: opening depends on how players behind defend',
  早位弱牌入池缺少位置支持: 'Entering with a weak hand from early position lacks positional support',
  '面对开池，先核对价格与被压制风险': 'Facing an open, check the price and the risk of domination first',
  '深筹码强牌直接全下，可能压缩价值空间': 'Shoving a strong hand deep-stacked may cut off value',
  这次跟注的价格缺少权益支持: "This call's price isn't supported by equity",
  '跟注偏贵，后续压力还需额外考虑': 'The call is expensive, and later pressure adds to it',
  强起手牌的弃牌需要解释下注压力: 'Folding a premium hand needs the betting pressure to explain it',
  强起手牌可比较主动建立底池: 'With a premium hand, compare building the pot',
  '河牌大额下注，需要明确哪些牌会弃牌': 'A big river bet needs a clear idea of which hands will fold',
  大额投入缺少明显牌力或听牌支持: 'A big investment without clear hand strength or a draw to back it',
  这次过牌可与价值下注比较: 'Compare this check with a value bet',
  '多人湿润牌面，顶对需要谨慎实现权益': 'Top pair on a wet multiway board must realize equity carefully',
  '弃牌可能偏紧，值得重新核对范围': 'This fold may be too tight; worth rechecking ranges',
  按当前价格与风险复查这次弃牌: 'Recheck this fold against the price and risk at the time',
  '连续多轮跟注，当前价格应独立评估': 'After calling several streets, evaluate the current price on its own',
  这次跟注需要结合价格与实现条件: 'This call depends on price and your ability to realize equity',
  这次下注有价值目标可核对: 'This bet has value targets you can check',
  '带听牌主动下注，要同时考虑被跟注后权益': 'Betting with a draw: also consider your equity when called',
  主动施压的收益依赖对手退出范围: 'The payoff from applying pressure depends on what folds',
  '公共牌已成牌，底牌没有额外优势': 'The board makes the hand; your hole cards add nothing',
  '过牌保留听牌，避免提前放大底池': 'Checking keeps the draw without growing the pot early',
  这次过牌可用于控制底池: 'This check controls the pot',
  // Lessons.
  '先免费过牌，面对后续下注再评估价格。': 'Take the free check first; evaluate the price if someone bets later.',
  '开池能力与接再加注能力分开判断；A high 不是必须弃牌的理由，也不是跟到底的理由。':
    'Judge whether a hand can open separately from whether it can call a re-raise; ace-high is neither a reason to fold nor a reason to call down.',
  '已投入的开池和跟注不能成为继续接 4-bet 的依据。':
    'Chips already put in with your open and call are not a reason to call a 4-bet.',
  '区分偷盲范围与防守再加注范围，核对尺度、位置、同花潜力和对手宽度。':
    'Separate your stealing range from your range for defending against re-raises; check sizing, position, flush potential, and how wide the opponent is.',
  '把主动开池与接再加注拆成两套继续条件。':
    'Treat opening and calling a re-raise as two separate sets of conditions to continue.',
  '减少人数不是收益证明；即刻弃牌权益与被继续后的牌力要分开评估。':
    "Thinning the field doesn't prove a profit; evaluate immediate fold equity separately from hand strength once someone continues.",
  '同花、位置、踢脚与防守倾向一起判断，不能只根据“有高张／同花”入池或根据档位直接判错。':
    'Weigh suitedness, position, kicker, and defending tendencies together; don\'t enter just because a hand has "a high card / is suited," and don\'t call it a mistake based on tier alone.',
  '主动开池、平跟已有开池和防守再加注需要不同范围，不能只按起手牌档位判断。':
    "Opening, flatting an open, and defending against a re-raise need different ranges; don't judge by starting-hand tier alone.",
  '优先比较正常开池或再加注与全下，让较弱范围有机会付费。':
    'Compare a normal open or re-raise with the shove first, so weaker ranges have a chance to pay you.',
  '在这两种假设下，跟注价格高于估计权益，倾向停止投入。':
    'Under both assumptions the price is higher than the estimated equity, so lean toward not putting in more.',
  '抽到最终摊牌的权益不等于实际能实现的权益；跟注后还可能再付费。':
    "Equity measured to showdown isn't the equity you can actually realize; after calling you may have to pay again.",
  '把强牌与实际下注强度一起判断，避免机械全下或机械弃牌。':
    'Judge a strong hand together with the actual betting strength; avoid automatic shoves or automatic folds.',
  '用加注获取价值，同时保留平跟诱导等替代路线，结合对手倾向选择。':
    'Raise for value while keeping alternatives like a trapping flat; choose based on opponent tendencies.',
  '给诈唬一个明确目标范围，而不是用很大金额补偿弱牌。':
    'Give your bluff a clear target range instead of making up for a weak hand with a huge size.',
  '比较价值与保护：让较弱成牌或听牌付费，同时为面对加注保留判断。':
    'Weigh value against protection: make worse made hands and draws pay, while keeping a plan for facing a raise.',
  '干燥牌面可以考虑较小价值尺度，给较弱牌留下继续空间。':
    'On a dry board, consider a smaller value size that leaves room for worse hands to continue.',
  '保留价格判断，同时减少把顶对当成全下价值牌的倾向。':
    'Keep judging by price, and lean less toward treating top pair as an all-in value hand.',
  '区分对手真实偏强与单纯害怕输牌；范围证据不足时保留两种路线。':
    'Separate an opponent who is actually strong from simply being afraid to lose; without enough range evidence, keep both lines in mind.',
  '把退出条件建立在当前价格、牌力和位置上，已投入筹码不构成必须继续的理由。':
    'Base your exit conditions on the current price, hand strength, and position; chips already in the pot are no reason you must continue.',
  '本次无需再为后续下注预留筹码，重点比较范围假设与价格。':
    'There are no later bets to save chips for, so focus on comparing range assumptions with the price.',
  '有价格空间不等于可以自动跟到底；继续行动和权益实现仍有风险。':
    "Having room on the price doesn't mean you can call down automatically; further action and equity realization are still risky.",
  '具体列出愿意付费的较弱牌，不把牌型名称当成最优尺度的证明。':
    "List the specific worse hands that will pay; a hand's name doesn't prove the best size.",
  '先确定哪些对手范围会退出，再衡量被跟注后是否能继续。':
    'First work out which opponent ranges will fold, then judge whether you can continue when called.',
  '过牌后仍应区分免费机会与面对下注时的继续条件。':
    'After checking, still separate a free chance from your conditions for continuing against a bet.',
  // Plans (fixed sentences; templated plans are fragments below).
  '下一步若有人下注，按新的金额和参与人数重新计算，不预先承诺跟到底。':
    "If someone bets next, recalculate with the new amount and player count; don't commit in advance to calling down.",
  '跛入者跟注较多时，提高隔离尺度并收紧范围；多人跟注后减少无依据持续施压。':
    'When limpers call a lot, size up your isolation raises and tighten your range; after a multiway call, cut back on pressure with no clear reason.',
  '比较 2–3 BB 开池：较小尺度降低偷盲成本，较大尺度提高即时压力，但要看盲位的继续范围。':
    'Compare 2–3 BB opens: a smaller size makes stealing cheaper and a larger size adds immediate pressure, depending on how the blinds continue.',
  '面对小额、宽范围 3-bet 才考虑有位置防守；大尺度或 4-bet 优先收紧。翻后顶对弱踢脚以控池为主，未中牌时结合牌面与对手范围决定是否持续下注。':
    "Consider defending in position only against small, wide-range 3-bets; tighten up first against large sizes or 4-bets. Postflop, play top pair with a weak kicker mainly for pot control, and when you miss, decide whether to continuation-bet based on the board and the opponent's range.",
  '对多次加注且缺少宽范围依据的情形，优先停止新增投入；只有清晰的极宽范围证据与有利价格才重新讨论防守。':
    'Facing multiple raises without evidence of a wide range, stop adding chips first; revisit defending only with clear evidence of an extremely wide range and a good price.',
  '比较 2–3 BB 开池与当前保守路线；若遇大尺度 3-bet 或 4-bet，弱 A 优先收紧。顶对弱踢脚时避免自动把筹码打光。':
    "Compare a 2–3 BB open with your conservative line; against a large 3-bet or a 4-bet, tighten up first with a weak ace. With top pair and a weak kicker, don't automatically get all your chips in.",
  '没有对手范围与弃牌倾向证据时优先收紧；具备宽开池／可弃平跟的证据时，重打比较有位置挤压与弃牌，避免把持有 A 当成无条件进攻依据。':
    "Without evidence about opponent ranges and folding tendencies, tighten up first; with evidence of wide opens or callers who fold, replay the hand to compare an in-position squeeze with a fold, and don't treat holding an ace as an automatic reason to attack.",
  '把当前开池与弃牌放进候选行动模拟，查看对手范围改变时哪条路线占优。面对 3-bet 收紧，顶对弱踢脚控制底池；同花听牌仍按实际价格和后续付费判断。':
    "Put this open and a fold into the candidate-action simulation to see which line does better as opponent ranges change. Tighten up against a 3-bet, play top pair with a weak kicker for pot control, and judge flush draws on the actual price and what they'll have to pay later.",
  '若以后在大盲面对很小加注，应重新按价格判断，不能把“弱牌”直接等同于必须弃牌。':
    'If you later face a very small raise in the big blind, judge it again on price; "weak hand" doesn\'t automatically mean "must fold."',
  '本次跟注将结束你的下注决策，重点核对对手是否有足够诈唬，不能把未来额外收益作为理由。':
    "This call ends your betting decisions, so focus on whether the opponent has enough bluffs; future winnings can't justify it.",
  '重点辨别这是宽范围争夺还是少诈唬的强范围；证据不足时将结论保留为讨论项。':
    'Focus on whether this is a wide-range fight or a strong range with few bluffs; without enough evidence, leave the conclusion open for discussion.',
  '可以重打本手，比较主动加注和跟注两条路线。': 'Replay this hand and compare raising with calling.',
  '若没有对手弃牌倾向的依据，先比较过牌或小投入路线；这里没有计算诈唬的精确收益。':
    "Without evidence of the opponent's folding tendencies, compare a check or a smaller line first; the exact value of the bluff isn't calculated here.",
  '若下一轮再次遇到大下注，按新牌面重算；不因已经跟过一轮就继续跟注。':
    "If you face another big bet next street, recalculate on the new board; having called once isn't a reason to keep calling.",
  '重点检验对手价值牌与诈唬组合，不再依赖后续隐含收益。':
    "Focus on the opponent's value and bluff combinations; don't rely on implied odds from later streets.",
  '如果跟注，先规划后续不利牌和再加注的应对，避免把当前权益全部当成可实现收益。':
    "If you call, plan for bad cards and re-raises first, and don't treat all of your current equity as realizable.",
  '重打时可以比较另一条路线，但后面发出的好牌不能反过来证明这一步应当跟注。':
    "When replaying, you can compare another line, but good cards that come later don't prove you should have called.",
  '用不同对手范围重算这一跟注，观察结论是否稳定。':
    'Recalculate this call against different opponent ranges and see whether the conclusion holds.',
  '这是不足完整加注的全下，对已经行动的玩家不一定重新开放加注权。':
    "This is an all-in for less than a full raise, so it doesn't necessarily reopen raising for players who have already acted.",
  '若被再加注，重新比较价格与范围；若被跟注，按下一轮牌面重新制定价值或退出路线。':
    "If re-raised, compare the price and ranges again; if called, plan a new value or exit line for the next street's board.",
  '遇到下注后按实际金额重算；若公共牌单独成牌，先考虑平分权益，不虚构底牌带来的优势。':
    "If someone bets, recalculate with the actual amount; if the board alone makes the hand, think about a split first and don't invent an edge from your hole cards.",
  // Routes.
  '保留此路线，按对手范围调整': 'Keep this line; adjust to opponent ranges',
  '使用当时已知信息；范围改变时重新判断。': 'Based on what was known at the time; reassess if ranges change.',
  '候选行动未计算完整未来策略的收益。': "Candidate actions don't account for the value of a full future strategy.",
  '主动隔离，尺度随跛入人数调整': 'Isolate; scale the size to the number of limpers',
  '保留后位开池，比较 2–3 BB 尺度': 'Keep the late-position open; compare 2–3 BB sizes',
  '跛入者范围较宽，且后面未出现明显强范围。':
    'Limpers have wide ranges, and no obviously strong range has shown up behind.',
  '无人开池，盲位有可利用的弃牌率；翻后位置有利。':
    "No one has opened, the blinds fold often enough to exploit, and you'll have position postflop.",
  '争夺盲注与控制成本；被跟注后不再按随机对手牌力判断。':
    "Fights for the blinds at a controlled cost; once called, stop treating the opponent's hand as random.",
  '重打时比较另一开池尺度，记录盲位继续频率；隔离较黏的跛入者可用较大尺度。':
    'When replaying, try the other open size and note how often the blinds continue; use a larger size to isolate sticky limpers.',
  '较小尺度降低失败成本，但可能让更多牌防守；较大尺度增加压力，也可能只留下更强范围。':
    'A smaller size risks less when it fails but lets more hands defend; a larger size adds pressure but may leave only stronger ranges.',
  '保守基线收紧；比较有条件的小开池': 'Tight baseline: fold; compare a conditional small open',
  '早位、多家待行动且缺少对手过度弃牌证据时，避免边缘同花牌扩大底池。':
    'From early position with several players still to act and no evidence that opponents overfold, avoid building a pot with marginal suited hands.',
  '放弃潜在同花与偷盲收益，换取更少的无位置和踢脚风险。':
    'Gives up flush potential and steal value in exchange for less out-of-position and kicker risk.',
  '后面防守过紧、较少 3-bet，且能在被继续后及时控池或退出时。':
    'When players behind defend too tightly, rarely 3-bet, and you can control the pot or get out once someone continues.',
  '主动争夺盲注，但较强 Qx/Kx 与再加注会使同花潜力难以实现；模拟结果只是该假设下的比较。':
    'Attacks the blinds, but stronger Qx/Kx and re-raises make the flush potential hard to realize; the simulation only compares lines under that assumption.',
  '缺少开池者宽范围、平跟者可弃牌的依据时，优先收紧。':
    'Without evidence that the opener is wide and the callers will fold, tighten up first.',
  '避免弱 A 被强继续范围压制；阻断部分强 A 不等于足够弃牌率。':
    "Keeps a weak ace from being dominated by strong continuing ranges; blocking some strong aces doesn't guarantee enough folds.",
  '开池者范围宽、平跟者有封顶倾向，且对手会对再加注弃牌时，才比较挤压。':
    'Compare a squeeze only when the opener is wide, the callers look capped, and opponents will fold to a re-raise.',
  '争夺多人死钱，但失败成本更大；被跟注或 4-bet 后需停止无依据施压。':
    'Wins multiway dead money, but costs more when it fails; after a call or a 4-bet, stop applying pressure without a reason.',
  '大尺度、多人继续或少诈唬的强范围下，优先减少新增投入。':
    'Against large sizes, multiple players continuing, or strong ranges with few bluffs, put in as little new money as possible.',
  '放弃当前权益，避免弱踢脚与后续压力；已投入筹码不计作继续理由。':
    'Gives up current equity to avoid weak-kicker trouble and later pressure; chips already invested are not a reason to continue.',
  '仅在对手极宽范围有明确证据、且价格与封口条件有利时讨论；常规强范围不适用。':
    "Worth discussing only with clear evidence of an extremely wide range and a favorable price and closing action; it doesn't apply against normal strong ranges.",
  '小尺度、宽范围且有位置或大盲折扣时才考虑；不要默认成立。':
    "Consider it only against a small size and wide range, with position or a big-blind discount; don't assume it by default.",
  '保留摊牌权益，但被更强 Ax 压制及面对后续下注的风险仍在。':
    'Keeps showdown equity, but the risk of domination by stronger Ax and of facing later bets remains.',
  '有明确较好的牌会退出，且尺度带来的弃牌率能补偿被跟注后的弱权益。':
    'Clearly better hands will fold, and the folds this size generates make up for weak equity when called.',
  '听牌有被跟注后的权益，且目标范围有足够弃牌。':
    'The draw has equity when called, and the target range folds often enough.',
  '列得出会付费的较弱牌，并能承担被加注后重新判断。':
    "You can name worse hands that will pay, and you're prepared to reassess if raised.",
  '建立底池与保护权益；尺度越大，对手继续范围可能越强。':
    'Builds the pot and protects equity; the bigger the size, the stronger the continuing range may be.',
  '对手范围偏强或牌面不利时，利用位置控制投入。':
    "When the opponent's range is strong or the board is unfavorable, use position to control how much you put in.",
  '对手会主动下注或你缺少位置优势时，保留诱导／控池路线。':
    'When the opponent will bet on their own or you lack position, keep an induce / pot-control line.',
  '减少底池增长，也可能给听牌免费机会或错过价值。':
    'Keeps the pot smaller, but may give draws a free card or miss value.',
  '当前价格缺少权益支持，或权益难以实现。':
    "The current price isn't supported by equity, or the equity is hard to realize.",
  '停止本次新增投入，不根据后来好牌否定弃牌。':
    "Stops adding chips now; good cards that come later don't make the fold wrong.",
  '只有更宽范围、足够诈唬或更有利的价格假设能提供权益余量时。':
    'Only when a wider range, enough bluffs, or a better price would give an equity margin.',
  '检验范围敏感性，不代表当前跟注已经获支持。':
    "Tests range sensitivity; it doesn't mean the call is already justified.",
  '对手范围与价格有足够余量，且后续压力可控。':
    "The opponent's range and the price leave enough margin, and later pressure is manageable.",
  '保留较宽范围，避免把弱价值牌转成孤立强牌的加注。':
    'Keeps your range wide and avoids turning thin-value hands into a raise that only gets called by stronger hands.',
  '对手价值范围更窄、后面可能再加注，或无法承担后续投入时。':
    "When the opponent's value range is narrower, someone behind may re-raise, or you can't afford later bets.",
  '让出部分权益，换取更低风险；不因已跟过一轮而自动续跟。':
    "Gives up some equity for lower risk; having called one street isn't a reason to keep calling.",
  '利用最后行动观察，控制边缘成牌或保留免费听牌。':
    'Use last action to see what happens, control the pot with marginal made hands, or keep a free draw.',
  '无最后行动优势时，先观察对手下注和牌面变化。':
    "Without the last-to-act advantage, watch the opponent's bets and how the board develops first.",
  '节省投入；不是保证免费看牌，仍需为后续下注设定条件。':
    "Saves chips; it doesn't guarantee a free card, so you still need a plan for later bets.",
  '对手有足够弃牌且听牌能承担被跟注时，比较半诈唬。':
    'Compare a semi-bluff when the opponent folds enough and your draw can handle being called.',
  '有明确较弱跟注目标，或对手会放弃较好的牌时；没有依据就保留过牌。':
    'When there are clear worse hands that call, or the opponent will fold better hands; without evidence, keep checking.',
  '换取价值或弃牌权益，但暴露于跟注／加注；没有证明这条路线更赚。':
    "Gains value or fold equity but is exposed to calls and raises; it hasn't been shown to earn more.",
  // Simulation override routes.
  '本次公开风格、两种起始范围及均衡后续策略能代表练习对局时。':
    "When this hand's public styles, the two starting ranges, and the balanced follow-up strategy are representative of your practice games.",
  '抽样结果支持优先比较，但真实继续范围与更好的后续打法仍可能改变排序。':
    'The samples support comparing this first, but real continuing ranges and better follow-up play could still change the ranking.',
  '改变对手范围或后续策略时，保留原保守／价值路线作对照。':
    'When opponent ranges or the follow-up strategy change, keep the original conservative / value line as a comparison.',
  '结合下方数字与具体条件判断，不把模拟领先当成必须执行。':
    "Judge using the numbers below and the specific conditions; a simulated lead doesn't mean you must take that line.",
  // Counterfactual.
  随机范围: 'Random range',
  公开行动加权范围: 'Public-action-weighted range',
  '从当时局面抽样未知牌，按公开风格继续打完；你后续采用均衡机器人策略，每次判断抽样 8 次。数值是此模拟策略的筹码净变化估计，已投入视为沉没成本，包含分池、退还与之后下注；误差为近似抽样误差，不覆盖范围／策略模型错误。不是 GTO 或真人最优 EV。':
    "Unknown cards are sampled from the position at the time, and each hand is played out with the opponents' public styles; your later decisions use the balanced bot strategy, with 8 equity samples per decision. The figures estimate net chip change under this simulated strategy, treat chips already invested as sunk, and include split pots, refunds, and later betting. The error shown is approximate sampling error and does not cover errors in the range or strategy model. This is not GTO or a real player's optimal EV.",
  // Summary.
  '本手没有主动决策；强制盲注不能归为选择失误。':
    "You made no decisions this hand; forced blinds can't count as mistakes.",
  未发现明显决策失误: 'No obvious decision mistakes found',
  // Opponents.
  翻牌前起手牌: 'Preflop hand',
  '这次继续尤其需要警惕：机器人估计的是随机范围，未完整按你的加注线收紧范围；小样本、强牌豁免或随机容错都可能产生不合理跟注。实际记录解释了原因，没有证明打法正确。':
    "Be especially careful with this continue: the bot estimated against a random range and didn't fully narrow it for your raising line; small samples, the premium-hand exemption, or random leeway can all produce unreasonable calls. The record explains why it happened; it doesn't prove the play was right.",
  '这是模拟器当时实际使用的判断记录。权益是小样本随机范围估计，未完整建模对手继续范围、权益实现或未来策略，不是职业牌手的真实心理，也不是最优打法证明。':
    "This is the decision record the simulator actually used at the time. Equity is a small-sample estimate against a random range; it doesn't fully model the opponent's continuing range, equity realization, or future strategy. It is not a real pro's thinking and not proof of optimal play.",
  ...BOT_REASON_NAMES,
  ...BOT_CHECK_NAMES,
  ...STREET_NAMES,
};

// Reasons-list and detail sentences of explainOpponent without placeholders.
const OPPONENT_FIXED = {
  '本次通过低成本入池分支，普通权益弃牌检查没有执行；下方权益和门槛仅展示当时算出的数值，不是这一行动的触发依据。':
    "It passed the low-cost entry branch, so the normal equity fold check didn't run; the equity and threshold below are only the values computed at the time, not what triggered this action.",
  '本次没有情绪偏移，使用风格基础参数。': 'No mood shift this time; base style settings were used.',
  '它把这组牌归入强起手牌，翻前跳过了普通权益与高压力弃牌检查；这是模型近似，不意味着任何人数、价格下都应该接全下。':
    "It classed this hand as a premium starting hand and skipped the normal equity and high-pressure fold checks preflop; this is a model approximation and doesn't mean an all-in should be called at any player count or price.",
  '这是未加注底池、最多补一个 BB 的低成本入池。牌进入按位置和风格扩展的入池范围，所以不再把多人对随机牌的摊牌权益与眼前盲注赔率直接比较后机械弃牌；这不是接大额加注或全下的理由。':
    "This was a low-cost entry into an unraised pot, costing at most one more BB. The hand was in an entry range widened by position and style, so it didn't mechanically fold by comparing multiway showdown equity against random hands with the immediate blind odds; this is no reason to call a big raise or an all-in.",
  '这是面对一次小开池的条件跟入：开池不超过 4 BB，新增投入较小，开池者没有全下，跟完后的有效后手还足够深。位置、风格、起手牌适玩性与已有跟入者决定候选范围。允许跟入与允许再加注分别计算；3-bet、大额下注和短后手不使用这一豁免。':
    "This was a conditional call against a single small open: the open was no more than 4 BB, the extra cost was small, the opener wasn't all-in, and the effective stack behind after calling was still deep enough. Position, style, hand playability, and the callers already in set the candidate range. Calling and re-raising are decided separately; 3-bets, large bets, and short stacks don't get this exemption.",
  '本次没有触发弃牌分支。若未加注，是进攻抽样未命中、没有合适进攻目标，或合法加注权已关闭。通过程序检查并不等于对真实继续范围有正收益。':
    "No fold branch was triggered. If it didn't raise, the aggression roll missed, there was no suitable target, or raising was no longer allowed. Passing the program's checks doesn't mean the play is profitable against the real continuing range.",
  '它识别到自己有听牌，参与人数不超过三人，并命中半诈唬及进攻抽样。收益包含弃牌权益；成牌候选仍可能不是干净获胜 outs。':
    'It saw that it had a draw, with no more than three players in the hand, and both the semi-bluff and aggression rolls hit. The payoff includes fold equity; its completion cards may still not be clean winning outs.',
  '它识别到后位／延续进攻／较干燥牌面的施压条件，筹码压力低于 25%，且命中诈唬和进攻抽样。没有读取你的底牌，也没有证明你一定会弃牌。':
    "It saw pressure conditions (late position / continuing aggression / a fairly dry board), its stack pressure was under 25%, and both the bluff and aggression rolls hit. It didn't read your hole cards and doesn't prove you would fold.",
  '它在免费过牌、干燥牌面且估计权益超过 65% 的条件下命中诱导分支，保留让对手主动下注的机会。':
    'With a free check, a dry board, and estimated equity above 65%, it hit the trap branch, leaving room for opponents to bet.',
  '它无需补筹码，未执行主动加注，选择免费观察。过牌并不表示它一定弱，也可能是进攻抽样未命中。':
    "It had nothing to call, didn't raise, and took a free look. A check doesn't mean it was weak; the aggression roll may simply have missed.",
};

// ---------------------------------------------------------------------------
// Sub-grammars for embedded values
// ---------------------------------------------------------------------------
const R = '(?:10|[2-9JQKA])';
const ENGINE_HANDS = ['高牌', '一对', '两对', '三条', '顺子', '同花', '葫芦', '四条', '同花顺', '皇家同花顺']
  .sort((a, b) => b.length - a.length);
const HAND_SRC = [
  `口袋 ${R}，公共牌有更高点数`,
  `口袋 ${R}`,
  `${R} / ${R} (?:同花|不同花)`,
  '公共牌成牌，底牌未提高牌力',
  `暗三条 ${R}`,
  `超对 ${R}(?:，公共牌带对子)?`,
  `对子 ${R} 来自公共牌，底牌提供踢脚`,
  `(?:顶对|非顶对) ${R}，${R} 踢脚`,
  ...ENGINE_HANDS,
].join('|');
const HAND = `(${HAND_SRC})`;

// Engine hand names in mid-sentence use (start form keeps the engine name).
export const ENGINE_HAND_MID = {
  高牌: 'high card',
  一对: 'one pair',
  两对: 'two pair',
  三条: 'three of a kind',
  顺子: 'a straight',
  同花: 'a flush',
  葫芦: 'a full house',
  四条: 'four of a kind',
  同花顺: 'a straight flush',
  皇家同花顺: 'a royal flush',
};
// Hand label → { mid, start }.
export function translateHandLabel(zh) {
  let m;
  const both = (mid, start = cap(mid)) => ({ mid, start });
  if (hasOwn(ENGINE_HAND_MID, zh)) return both(ENGINE_HAND_MID[zh], HAND_LABELS[zh]);
  if ((m = new RegExp(`^口袋 (${R})，公共牌有更高点数$`).exec(zh)))
    return both(`pocket ${rankPlural(m[1])} with an overcard on board`);
  if ((m = new RegExp(`^口袋 (${R})$`).exec(zh))) return both(`pocket ${rankPlural(m[1])}`);
  if ((m = new RegExp(`^(${R}) / (${R}) (同花|不同花)$`).exec(zh)))
    return both(`${m[1]}/${m[2]} ${m[3] === '同花' ? 'suited' : 'offsuit'}`);
  if (zh === '公共牌成牌，底牌未提高牌力') return both('a hand that plays the board (hole cards add nothing)');
  if ((m = new RegExp(`^暗三条 (${R})$`).exec(zh))) return both(`a set of ${rankPlural(m[1])}`);
  if ((m = new RegExp(`^超对 (${R})(，公共牌带对子)?$`).exec(zh)))
    return both(`an overpair (${rankPlural(m[1])})${m[2] ? ', on a paired board' : ''}`);
  if ((m = new RegExp(`^对子 (${R}) 来自公共牌，底牌提供踢脚$`).exec(zh)))
    return both(`a board pair of ${rankPlural(m[1])}, hole cards as kickers`);
  if ((m = new RegExp(`^(顶对|非顶对) (${R})，(${R}) 踢脚$`).exec(zh)))
    return both(
      `${m[1] === '顶对' ? 'top pair' : 'second-or-lower pair'} (${m[2]}) with ${article(m[3])} ${m[3]} kicker`,
    );
  throw Error(`Unknown review hand label: ${JSON.stringify(zh)}`);
}

const TEX_TAG = `(?:${Object.keys(TEXTURE_TAGS).join('|')})`;
const TEX = `(${TEXTURE_DRY.zh}|${TEX_TAG}(?:、${TEX_TAG})*)`;
// Texture label → lowercase catalog phrase (mid form).
export function translateTexture(zh) {
  if (zh === TEXTURE_DRY.zh) return TEXTURE_DRY.en;
  return zh
    .split('、')
    .map((tag) => {
      if (!hasOwn(TEXTURE_TAGS, tag)) throw Error(`Unknown texture tag ${tag}`);
      return TEXTURE_TAGS[tag];
    })
    .join(', ');
}

const PRE = `(${Object.keys(PREFLOP_LABELS)
  .sort((a, b) => b.length - a.length)
  .map((s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))
  .join('|')})`;
const pre = (zh) => PREFLOP_LABELS[zh];

const POS = '([A-Z][A-Z0-9+]*)';
const N = '(-?\\d[\\d,]*)'; // grouped integer from number()/n()
const INT = '(\\d+)'; // raw integer
const DEC = '(-?\\d+\\.\\d)'; // toFixed(1)
const PCT = '(-?\\d+%)'; // percent(): Math.round(x*100)+'%'
const PCT1 = '([-+]?(?:\\d+\\.\\d|NaN)%)'; // pct(): toFixed(1)+'%', optionally signed
const RAW = '(-?[\\d.]+(?:e[-+]?\\d+)?|NaN|undefined)'; // raw JS number
const ACT = '(弃牌|过牌|(?:全下)?跟注 [\\d,]+|\\d+-bet \\S+ [\\d,]+)';
const act = (zh) => translateEngine(zh);
const STREET = `(${Object.keys(STREET_NAMES).join('|')})`;
const REASON_NAME = `(${Object.keys(BOT_REASON_NAMES).join('|')}|undefined)`;
const REASON_LIST = `((?:${Object.keys(BOT_REASON_NAMES).join('|')}|undefined)(?:、(?:${Object.keys(BOT_REASON_NAMES).join('|')}|undefined))*)`;
const reasonName = (zh) => (zh === 'undefined' ? zh : BOT_REASON_NAMES[zh]);
const reasonList = (zh) =>
  zh
    .split('、')
    .map((name) => lowerFirst(reasonName(name)))
    .join(', ');
const MOOD = `(${Object.keys(MOOD_LABELS).join('|')})`;
const MOOD_REASON = `(${[...Object.keys(MOOD_REASONS), '之前牌局的触发事件'].map((s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')})`;
const moodReason = (zh) => (zh === '之前牌局的触发事件' ? 'an event in an earlier hand' : MOOD_REASONS[zh]);

const H = (zh) => translateHandLabel(zh);
const players = (n) => plural(n, 'player', 'players');
const opponents = (n) => plural(n, 'opponent', 'opponents');
const cards = (n) => plural(n, 'direct completion card', 'direct completion cards');

// ---------------------------------------------------------------------------
// Fragments: [source regex, English builder]. A review string is parsed into
// consecutive fragments (one optional space allowed before each), and the
// English fragments are joined with one space.
// ---------------------------------------------------------------------------
const PRICED = `本次有效跟注成本 ${N}，跟注后可争夺 ${N}，盈亏平衡权益约 ${PCT}。`;
const priced = (m, i = 1) =>
  `Effective call cost ${m[i]}; after calling you can win ${m[i + 1]}; break-even equity is about ${m[i + 2]}.`;

const FRAGMENTS = [
  // §6.1 shared sentences.
  [PRICED, (m) => priced(m)],
  [
    `随机范围与行动加权范围下，底池权益分别约 ${PCT} / ${PCT}。`,
    (m) => `Pot equity is about ${m[1]} against a random range and ${m[2]} against an action-weighted range.`,
  ],
  // free-fold.
  [
    `当时你在 ${POS}，跟注成本为 0。过牌保留本手权益，不会增加投入；(?:后面还有 ${INT} 位玩家可以行动。|(本轮没有必须补齐的下注。))`,
    (m) =>
      `You were in ${m[1]} and it cost 0 to continue. Checking keeps your equity in the hand without adding chips; ` +
      (m[3] ? "there's no bet to match this round." : `${players(m[2])} behind can still act.`),
  ],
  // late-open / late-isolation.
  [
    `${HAND} 在 ${POS} (?:面对 ${INT} 位跛入者|(行动弃到你，前面没有开池))，加注至 ${N}（${DEC} BB）。`,
    (m) =>
      `${H(m[1]).start} in ${m[2]}, ${m[4] ? 'folded to you with no open in front' : `facing ${plural(m[3], 'limper', 'limpers')}`}; you raised to ${m[5]} (${m[6]} BB).`,
  ],
  [
    'A 底牌阻断部分 AA、AK、AQ 组合；后位允许比早位更宽的开池范围。',
    () => 'Your ace blocks some AA, AK, and AQ combos, and late position allows a wider opening range than early position.',
  ],
  [
    '后位能以较宽范围争夺盲注，并在翻后获得位置优势。',
    () => 'Late position can attack the blinds with a wider range and have position postflop.',
  ],
  [
    `加注可让部分弱连张和高牌退出，收益包含弃牌权益；被跟注后，留下的范围可能更强(?:，A${INT} 成顶对仍容易被更好的 A 踢脚压制)?。`,
    (m) =>
      'Raising folds out some weak connectors and high cards, and the payoff includes fold equity; once called, the remaining range may be stronger' +
      (m[1] ? `, and A${m[1]} that makes top pair is still easily dominated by a better ace kicker` : '') +
      '.',
  ],
  [
    '这里是隔离加注；已有开池再加平跟后才叫挤压加注。',
    () => "This is an isolation raise; it's only a squeeze when there's an open plus a caller.",
  ],
  ['这里是开池／偷盲，不是挤压加注。', () => 'This is an open / steal, not a squeeze.'],
  // weak 3-bet / 4-bet defense.
  [
    `${HAND} 在 ${POS}，${PRE}，最新总额 ${N}，约上一次的 ${DEC} 倍。`,
    (m) => `${H(m[1]).start} in ${m[2]}, ${pre(m[3])}; the latest bet is ${m[4]}, about ${m[5]}× the previous one.`,
  ],
  [
    '你此前的开池有合理依据，但这一跟注是新的独立决策。',
    () => 'Your earlier open was reasonable, but this call is a new, separate decision.',
  ],
  [
    '较强 Ax 压制你的踢脚，单靠持有 A 的阻断不够支持大额跟注。',
    () => "Stronger Ax dominates your kicker, and the ace blocker alone isn't enough to justify a large call.",
  ],
  [
    '弱牌被强范围压制，缺少稳健的翻后实现条件。',
    () => 'A weak hand is dominated by strong ranges and has no reliable way to realize its equity postflop.',
  ],
  [`后面仍有 ${INT} 人可再次行动。`, (m) => `${players(m[1])} behind can still act again.`],
  [
    `备选为小额有位置跟注，但需要对手 3-bet 足够宽、价格有余量(?:(，同花潜力有助于实现权益)|；不同花弱 A 需要更严格的防守条件)。低 SPR 或大尺度压力下不要仅为看翻牌继续。`,
    (m) =>
      'The alternative is a small in-position call, but it needs a wide enough 3-bet range and a margin on price' +
      (m[1] ? '; flush potential helps you realize equity' : '; an offsuit weak ace needs stricter conditions to defend') +
      ". At low SPR or under large sizing, don't continue just to see a flop.",
  ],
  // late-passive-entry.
  [`${HAND} 在 ${POS}，无人主动入池。`, (m) => `${H(m[1]).start} in ${m[2]}, with no one in the pot yet.`],
  [
    'A 阻断部分强 Ax，后位允许更宽地争夺盲注。',
    () => 'Your ace blocks some strong Ax, and late position allows attacking the blinds more widely.',
  ],
  [
    '翻后位置与对手退出空间支持比较主动开池。',
    () => 'Postflop position and room for opponents to fold support comparing an open.',
  ],
  [
    '单纯跛入让盲位低成本看牌，缺少主动弃牌权益。',
    () => 'A plain limp lets the blinds see a cheap flop and gives up fold equity.',
  ],
  [
    '弃牌避免投入，但也放弃了后位争夺盲注的机会。',
    () => 'Folding avoids putting chips in, but also gives up the chance to attack the blinds from late position.',
  ],
  [
    '这不等于被加注后还应继续；盲位很黏或有效筹码很短时需要另行调整。',
    () =>
      "This doesn't mean you should continue if raised; adjust separately when the blinds are sticky or effective stacks are short.",
  ],
  // squeeze-candidate.
  [
    `${HAND} 在 ${POS}，已有开池及 ${INT} 次平跟，你再加注至 ${N}，属于挤压加注。A 阻断部分强 A 组合，可帮助挑选诈唬候选；但不同花弱 A 被跟注后仍可能被更强 Ax 压制。是否值得挤压，关键是开池者是否足够宽、平跟者是否会退出，以及你面对 4-bet 能否及时停止。`,
    (m) =>
      `${H(m[1]).start} in ${m[2]}, after an open and ${plural(m[3], 'call', 'calls')}; re-raising to ${m[4]} is a squeeze. The ace blocks some strong ace combos, which helps when choosing bluffs, but an offsuit weak ace can still be dominated by stronger Ax once called. Whether to squeeze depends on whether the opener is wide enough, whether the callers will fold, and whether you can stop in time when facing a 4-bet.`,
  ],
  // early-suited-entry.
  [
    `${HAND} 确实是同花牌，具备同花潜力；不能按不同花弱牌处理。你在 ${POS}，后面仍有 ${INT} 人可行动。(较小踢脚使顶对容易被更强同点数高牌压制，)?同花潜力并不能消除无位置和再加注压力。常规收紧范围可选择弃牌；若后面明显过紧、很少 3-bet，则可以比较小尺度开池利用其弃牌。`,
    (m) =>
      `${H(m[1]).start} is genuinely suited and has flush potential; don't treat it like a weak offsuit hand. You're in ${m[2]} with ${players(m[3])} still to act. ` +
      (m[4]
        ? 'With a small kicker, top pair is easily dominated by the same high card with a better kicker, and flush potential'
        : 'Flush potential') +
      " doesn't remove the pressure of being out of position and facing re-raises. A standard tight range can fold here; if players behind are clearly too tight and rarely 3-bet, you can compare a small open to exploit their folds.",
  ],
  // weak-entry.
  [
    `你拿 ${HAND}，处于 ${POS}，当前需补 ${N}；仍有 ${INT} 位玩家尚可行动。`,
    (m) => `You hold ${H(m[1]).mid} in ${m[2]} and need ${m[3]} to continue; ${players(m[4])} can still act.`,
  ],
  [
    '早位缺少位置优势，(?:(同花潜力仍需承担踢脚、连接性及再加注风险。)|不同花边缘牌更难实现权益。)',
    (m) =>
      'Early position lacks a positional advantage, ' +
      (m[1]
        ? 'and flush potential still carries kicker, connectivity, and re-raise risk.'
        : 'and marginal offsuit hands have a harder time realizing equity.'),
  ],
  [
    '前面已有加注，弱牌被更好顶对或更高踢脚压制的风险增加。',
    () =>
      "There's already a raise in front, which raises the risk of a weak hand being dominated by a better top pair or a higher kicker.",
  ],
  // deep-value-shove.
  [
    `${HAND} 有价值，但这次额外投入 ${N}（约 ${N} BB），是当时底池 ${N} 的 ${DEC} 倍；有效剩余筹码约 ${N} BB。如此大的压力可能让愿意跟常规加注的较弱牌退出，不能仅凭强牌认定全下最好。`,
    (m) =>
      `${H(m[1]).start} has value, but this put in an extra ${m[2]} (about ${m[3]} BB), ${m[5]}× the pot of ${m[4]} at the time; the effective stack was about ${m[6]} BB. That much pressure can fold out worse hands that would call a normal raise, so a strong hand alone doesn't make shoving best.`,
  ],
  [
    `可以先用 ${ACT} 这条路线练习；若对手再加注，再结合其范围和有效筹码决定继续。此尺度是练习候选，不保证多赚。`,
    (m) =>
      `Practice the line ${act(m[1])} first; if an opponent re-raises, decide whether to continue based on their range and the effective stack. This size is a practice candidate and isn't guaranteed to earn more.`,
  ],
  // expensive-call.
  [`当时是 ${HAND}，面对 ${INT} 位未弃牌对手。`, (m) => `You had ${H(m[1]).mid} against ${opponents(m[2])} still in the hand.`],
  [
    `当前有 ${INT} 张直接成牌候选，下一张约 ${PCT}；成牌仍可能输给更强牌。`,
    (m) => `You have ${cards(m[1])}, about ${m[2]} to hit on the next card; completing can still lose to a stronger hand.`,
  ],
  [
    `后面尚有 ${INT} 位玩家可能行动；若跟注，先设定面对再加注或不利转牌时的退出条件。`,
    (m) => `${players(m[1])} behind may still act; if you call, set your exit conditions for a re-raise or a bad turn first.`,
  ],
  // premium-fold.
  [
    `你持有 ${HAND}，当前 ${N}、需补 ${N}，有效筹码约 ${N} BB；本手已出现 ${INT} 次翻牌前加注。`,
    (m) =>
      `You held ${H(m[1]).mid}; the bet was ${m[2]} and you needed ${m[3]} more, with about ${m[4]} BB effective; there had been ${plural(m[5], 'preflop raise', 'preflop raises')} this hand.`,
  ],
  [
    '多次再加注会收紧对手范围，不能仅用强牌标签否定弃牌。',
    () => `Multiple re-raises narrow the opponent's range, so the "premium hand" label alone doesn't make the fold wrong.`,
  ],
  [
    '常规压力下，这组牌通常值得继续比较跟注或再加注。',
    () => 'Under normal pressure, this hand is usually worth continuing; compare a call and a re-raise.',
  ],
  // premium-flat.
  [
    `${HAND} 在 ${POS} 跟注 ${N}，${INT} 位对手仍在局中，${INT} 位尚可行动。`,
    (m) =>
      `${H(m[1]).start} called ${m[3]} in ${m[2]}; ${opponents(m[4])} ${m[4] === '1' ? 'is' : 'are'} still in and ${m[5]} can still act.`,
  ],
  [
    '面对已有加注，平跟能保留较宽范围，但也可能把底池带入多人。',
    () => "Against an existing raise, flatting keeps the opponent's range wide but may also make the pot multiway.",
  ],
  ['未加注底池中，单纯跟注让其他人低成本入池。', () => 'In an unraised pot, just calling lets others in cheaply.'],
  [
    `练习候选为 ${ACT}；若有人再次加注，不自动把当前建议延伸为必须打光筹码。`,
    (m) =>
      `The practice candidate is ${act(m[1])}; if someone raises again, this suggestion doesn't automatically extend to getting all your chips in.`,
  ],
  // large-unbacked-bet.
  [
    `你当时是 ${HAND}，额外下注 ${N}，约 ${DEC} 倍底池；${INT} 位对手尚未弃牌。`,
    (m) =>
      `You had ${H(m[1]).mid} and bet an extra ${m[2]}, about ${m[3]}× the pot; ${opponents(m[4])} hadn't folded.`,
  ],
  ['此前听牌在河牌落空。', () => 'Your earlier draw missed on the river.'],
  [
    '你有该花色 A，能阻断部分坚果同花，但不代表对手一定弃牌。',
    () => "You hold the ace of that suit, which blocks some nut flushes, but that doesn't mean the opponent will fold.",
  ],
  [
    '没有识别出坚果同花 A 阻断，不能据此假设对手会频繁弃牌。',
    () => "No nut-flush ace blocker was detected, so don't assume the opponent will fold often.",
  ],
  // value-check.
  [
    `当时是 ${HAND}，公共牌${TEX}，仍有 ${INT} 位对手。`,
    (m) => `You had ${H(m[1]).mid} on a board that's ${translateTexture(m[2])}, with ${opponents(m[3])} left.`,
  ],
  ['你有最后行动的位置优势。', () => 'You have position and act last.'],
  [
    '你在其余对手之前行动，过牌可以保留诱导路线。',
    () => 'You act before the remaining opponents, and checking keeps an inducing line open.',
  ],
  [
    '超对可以向较弱一对或部分听牌取值，但不能忽视更强成牌。',
    () => "An overpair can get value from worse pairs and some draws, but don't ignore stronger made hands.",
  ],
  [
    '当前成牌具备价值潜力；过牌是否更好仍取决于对手跟注和主动下注倾向。',
    () =>
      'Your made hand has value potential; whether checking is better still depends on how often opponents call and bet on their own.',
  ],
  [
    `可用 ${ACT} 比较；若被加注，重新判断其强牌密度，不把“可下注”理解为“必须继续”。`,
    (m) =>
      `Compare with ${act(m[1])}; if raised, reassess how many strong hands the raiser has, and don't read "can bet" as "must continue."`,
  ],
  // multiway-top-pair.
  [
    `${HAND} 面对 ${INT} 位对手，公共牌${TEX}。`,
    (m) => `${H(m[1]).start} against ${opponents(m[2])} on a board that's ${translateTexture(m[3])}.`,
  ],
  [
    '多人底池中，一对的摊牌能力更容易被两对、三条或听牌追上。',
    () => "In a multiway pot, one pair's showdown value is more easily caught by two pair, trips, or draws.",
  ],
  // tight-fold.
  [`当时是 ${HAND}。`, (m) => `You had ${H(m[1]).mid}.`],
  [
    '在这两种范围假设下，权益有价格余量，但尚未证明对手真实范围也如此。',
    () =>
      "Under both range assumptions your equity beats the price with room to spare, but that hasn't been shown for the opponent's real range.",
  ],
  // priced-fold.
  [
    `你在 ${POS} 持 ${HAND}，需再补 ${N}。`,
    (m) => `You held ${H(m[2]).mid} in ${m[1]} and needed ${m[3]} more.`,
  ],
  [`公共牌${TEX}。`, (m) => `The board is ${translateTexture(m[1])}.`],
  [
    `当前直接成牌候选 ${INT} 张，下一张约 ${PCT}，并非保证获胜。`,
    (m) => `You have ${cards(m[1])}, about ${m[2]} on the next card, which doesn't guarantee a win.`,
  ],
  ['没有识别出直接的顺子或同花成牌听牌。', () => 'No direct straight or flush draw was detected.'],
  // priced-call / multi-street-call.
  [`你持 ${HAND}，${INT} 位对手仍在局中。`, (m) => `You held ${H(m[1]).mid}, with ${opponents(m[2])} still in.`],
  [
    `此前已在 ${INT} 个较早轮次跟注，过去投入不提高本次权益。`,
    (m) => `You already called on ${plural(m[1], 'earlier street', 'earlier streets')}; past investment doesn't increase your equity now.`,
  ],
  [`直接成牌候选 ${INT} 张，下一张约 ${PCT}。`, (m) => `${cap(cards(m[1]))}, about ${m[2]} on the next card.`],
  [
    `留意 ${INT} 位尚可行动的玩家，以及下一张牌是否形成更强的顺子或同花结构。`,
    (m) =>
      `Watch the ${players(m[1])} who can still act, and whether the next card brings a stronger straight or flush texture.`,
  ],
  // value-bet / draw-bet / pressure-bet.
  [
    `${HAND} 额外投入 ${N}，约底池的 ${PCT}；公共牌(?:(尚未发出)|${TEX})，${INT} 位对手尚在。`,
    (m) =>
      `${H(m[1]).start}: put in an extra ${m[2]}, about ${m[3]} of the pot; the board is ${m[4] ? 'not dealt yet' : translateTexture(m[5])}, with ${opponents(m[6])} still in.`,
  ],
  [
    `同时有 ${INT} 张直接成牌候选，下一张约 ${PCT}。`,
    (m) => `You also have ${cards(m[1])}, about ${m[2]} on the next card.`,
  ],
  [
    '可以尝试从较弱的牌取得价值；对手愿意跟哪些牌仍需判断。',
    () => 'You can try to get value from worse hands; which hands the opponent will call with still needs judging.',
  ],
  [
    '当前未识别出直接的顺子或同花听牌，不能默认被跟注后有足够改善机会。',
    () => "No direct straight or flush draw was detected, so don't assume you have enough chances to improve when called.",
  ],
  // board-check / draw-check / pot-control.
  [
    `当时是 ${HAND}，公共牌${TEX}，无需补筹码。`,
    (m) => `You had ${H(m[1]).mid} on a board that's ${translateTexture(m[2])}, with nothing to call.`,
  ],
  [
    `有 ${INT} 张直接成牌候选，下一张约 ${PCT}；过牌不额外支付这个机会。`,
    (m) =>
      `You have ${cards(m[1])}, about ${m[2]} on the next card; checking means you don't pay extra for that chance.`,
  ],
  [
    `之后还有 ${INT} 位玩家可行动，过牌并不保证免费看到下一张。`,
    (m) => `${players(m[1])} can still act after you, so checking doesn't guarantee a free card.`,
  ],
  ['你可以观察后面的牌面或进入摊牌。', () => 'You can see the next card or go to showdown.'],
  // Simulation override suffixes.
  [
    `候选行动模拟中，${ACT} 在两种范围下均有较明确的筹码收益优势，值得替代原启发式建议进行练习；这个优势依赖模拟继续策略，不是最优打法证明。`,
    (m) =>
      `In the candidate-action simulation, ${act(m[1])} showed a fairly clear chip advantage under both ranges and is worth practicing instead of the original heuristic suggestion; the edge depends on the simulated follow-up strategy and doesn't prove optimal play.`,
  ],
  [
    '重打时优先对照模拟候选与原路线；若对手的防守方式明显不同，重新分析。',
    () =>
      'When replaying, compare the simulation pick with the original line first; if opponents defend very differently, analyze again.',
  ],
  // Summary body.
  [
    `${INT} 次主动决策，共新增投入 ${N}。优先回到第 ${INT} 步（${STREET}）：([^。]+)。`,
    (m) =>
      `${plural(m[1], 'decision', 'decisions')}, ${m[2]} chips put in. Start with step ${m[3]} (${STREET_NAMES[m[4]]}): ${fixed(m[5])}.`,
  ],
  [`另有 ${INT} 个不同问题可逐步查看。`, (m) => `${plural(m[1], 'other issue', 'other issues')} to look through step by step.`],
  // explainOpponent reasons.
  [
    `起手牌强度排序约前 ${PCT1}；本次风格、位置与公开加注线允许前 ${PCT1}。(进入|未进入)该范围(，同时触发前 7% 强牌分支)?。排序是起手牌启发式，不是胜率。`,
    (m) =>
      `Starting-hand rank: about top ${m[1]}; this style, position, and the public raising line allow the top ${m[2]}. It ${m[3] === '进入' ? 'was inside' : 'was outside'} that range${m[4] ? ', and it also triggered the top-7% premium branch' : ''}. The ranking is a starting-hand heuristic, not a win rate.`,
  ],
  [
    `它面对 ${INT} 位未弃牌对手，需跟 ${N}，模型可争夺 ${N}，跟注门槛 ${PCT1}。`,
    (m) =>
      `It faced ${opponents(m[1])} still in, needed ${m[2]} to call, could win ${m[3]} in the model, and needed ${m[4]} equity to call.`,
  ],
  [
    `它曾触发 ${REASON_LIST}，但容错抽样保留了继续，随后才进入当前行动分支；不能只凭最后的价值／诈唬标签忽略这部分风险。`,
    (m) =>
      `It had triggered ${reasonList(m[1])}, but a leeway roll kept it in before it reached the current action branch; don't ignore this risk just because of the final value / bluff label.`,
  ],
  [
    `本街只有一次小开池，跟完后的有效后手约 ${N} BB，已有 ${INT} 位跟入者。(?:(对子或合适同花牌的翻后潜力)|起手牌排序与当前价格)进入了独立跟入范围；普通的全桌随机摊牌权益弃牌检查没有执行。该近似没有证明这次跟注有正收益。`,
    (m) =>
      `There was only one small open this street; the effective stack behind after calling was about ${m[1]} BB, with ${plural(m[2], 'caller', 'callers')} already in. ${m[3] ? 'The postflop potential of a pair or a suitable suited hand' : 'Its starting-hand rank and the current price'} put it into a separate calling range, so the usual fold check on random-hand showdown equity across the table didn't run. This approximation doesn't prove the call is profitable.`,
  ],
  [
    `当时只用自己的牌与公共牌，对随机对手范围抽样 ${INT} 次：原估计 ${PCT1}，判断扰动 ${PCT1}，决策使用 ${PCT1}。跟注倾向偏移 ${PCT1}，比较值 ${PCT1}，常规门槛含 2 个百分点保护为 ${PCT1}。`,
    (m) =>
      `Using only its own cards and the board, it sampled random opponent ranges ${m[1]} times: raw estimate ${m[2]}, judgment noise ${m[3]}, equity used ${m[4]}. Calling-tendency shift ${m[5]}, compared value ${m[6]}; the usual threshold, including a 2-point buffer, was ${m[7]}.`,
  ],
  [
    `当时识别到 ${INT} 张直接顺子／同花成牌候选，下一张成牌比例 ${PCT1}；不是保证赢牌的概率。`,
    (m) =>
      `It saw ${plural(m[1], 'direct straight / flush completion card', 'direct straight / flush completion cards')}, ${m[2]} to hit on the next card; that is not a probability of winning.`,
  ],
  [
    `模拟情绪：${MOOD}，来源：${MOOD_REASON}。基础／实际宽度 ${RAW} / ${RAW}，进攻 ${RAW} / ${RAW}，跟注 ${RAW} / ${RAW}；这次状态是否改变动作仍取决于上述分支。`,
    (m) =>
      `Simulated mood: ${MOOD_LABELS[m[1]]}. Trigger: ${moodReason(m[2])}. Base / actual looseness ${m[3]} / ${m[4]}, aggression ${m[5]} / ${m[6]}, calling ${m[7]} / ${m[8]}; whether this state changed the action still depends on the branches above.`,
  ],
  [
    `曾尝试加注总额 ${N}，但触及最大值的纯诈唬全下保护条件，最终没有执行该加注；实际动作仍是上方记录的(跟注|过牌)。`,
    (m) =>
      `It tried to raise to ${m[1]}, but that hit the safeguard against max-size pure-bluff shoves, so the raise wasn't made; the actual action is still the ${m[2] === '跟注' ? 'call' : 'check'} recorded above.`,
  ],
  [
    `尺度先产生总额 ${N}，再按合法区间 ${N}–${N} 调整到 ${N}。`,
    (m) => `Sizing first produced a total of ${m[1]}, then was clamped to the legal range ${m[2]}–${m[3]}, giving ${m[4]}.`,
  ],
  [
    '未加注底池按开池／跛入人数公式计算。',
    () => 'In an unraised pot, it uses the open / number-of-limpers formula.',
  ],
  [
    `尺度系数约 ${PCT1} ×（当时底池 \\+ 跟注额），再加当前下注总额。`,
    (m) => `Sizing factor about ${m[1]} × (pot at the time + call amount), plus the current total bet.`,
  ],
  // explainOpponent details.
  [
    `它本来触发了 ${REASON_LIST}，但实际随机容错抽样保留了继续。因此这次(跟注|行动)是模型刻意保留的宽松失误，不能解释为赔率已证明值得继续。`,
    (m) =>
      `It originally triggered ${reasonList(m[1])}, but a random leeway roll kept it in. So this ${m[2] === '跟注' ? 'call' : 'action'} is a deliberately loose mistake built into the model; it can't be read as the odds proving it worth continuing.`,
  ],
  [
    `这组牌进入(独立的价值再加注|开池／隔离加注)候选范围（约前 ${PCT1}），或触发强牌分支，并命中进攻抽样；它因此主动建立底池。允许平跟的边缘牌不会仅因入池范围扩大就自动再加注，标签不代表坚果牌。`,
    (m) =>
      `The hand was in the ${m[1] === '独立的价值再加注' ? 'separate value re-raise' : 'open / isolation raise'} candidate range (about the top ${m[2]}), or triggered the premium branch, and the aggression roll hit, so it built the pot. Marginal hands allowed to flat don't automatically re-raise just because the entry range widened, and the label doesn't mean the nuts.`,
  ],
  [
    `随机范围权益超过 ${PCT1}，或符合“超对且权益超过 40%”，并命中进攻抽样。这不要求一定已有成牌，A high 也可能被宽范围估计归入此分支。若对手继续范围偏强，这个估计可能过于乐观。`,
    (m) =>
      `Equity against a random range was above ${m[1]}, or it met "overpair with more than 40% equity," and the aggression roll hit. A made hand isn't required; even ace-high can land in this branch under a wide-range estimate. If the opponent's continuing range is strong, this estimate may be too optimistic.`,
  ],
  [
    `实际执行 ${REASON_NAME}，没有使用后来发出的牌来决定这一步。`,
    (m) => `Actually executed: ${lowerFirst(reasonName(m[1]))}. Cards dealt later were not used to decide this step.`,
  ],
  // Fixed opponent sentences (also usable as fragments).
  ...Object.entries(OPPONENT_FIXED).map(([zh, en]) => [escape(zh), () => en]),
  // Fixed review sentences, usable inside composed reasons and plans.
  ...Object.entries(REVIEW_FIXED)
    .filter(([zh]) => zh.endsWith('。'))
    .sort(([a], [b]) => b.length - a.length)
    .map(([zh, en]) => [escape(zh), () => en]),
].map(([source, build]) => [new RegExp(source, 'y'), build]);

function escape(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
function fixed(zh) {
  if (!hasOwn(REVIEW_FIXED, zh)) throw Error(`Unknown fixed review copy: ${JSON.stringify(zh)}`);
  return REVIEW_FIXED[zh];
}

// Whole strings with structure: evidence items, summary titles, route summaries.
const WHOLE = [
  [
    new RegExp(`^位置 ${POS} · ${INT} 位未弃牌对手(?: · (有位置|无最后行动优势))?$`),
    (m) =>
      `Position ${m[1]} · ${opponents(m[2])} in the hand${m[3] ? ' · ' + (m[3] === '有位置' ? 'In position' : 'Not last to act') : ''}`,
  ],
  [new RegExp(`^当时牌力：${HAND}$`), (m) => `Hand at the time: ${H(m[1]).start}`],
  [new RegExp(`^公共牌：${TEX}$`), (m) => `Board: ${cap(translateTexture(m[1]))}`],
  [
    new RegExp(`^翻牌前加注 ${INT} 次 · 尚可行动 ${INT} 人$`),
    (m) => `Preflop raises: ${m[1]} · Still to act: ${m[2]}`,
  ],
  [new RegExp(`^有效剩余约 ${N} · 当前 SPR ${DEC}$`), (m) => `Effective stack ≈ ${m[1]} · SPR ${m[2]}`],
  [
    new RegExp(`^直接成牌候选 ${INT} 张（已去重）· 下一张约 ${PCT}，不等于获胜率$`),
    (m) => `Direct completion cards: ${m[1]} (deduplicated) · ≈${m[2]} on the next card, not a win rate`,
  ],
  [
    new RegExp(`^入池情境：${PRE} · 跛入 ${INT} 人( · A 阻断不等于被跟注后优势)?$`),
    (m) =>
      `Preflop situation: ${cap(pre(m[1]))} · Limpers: ${m[2]}${m[3] ? " · An ace blocker isn't an edge once called" : ''}`,
  ],
  [new RegExp(`^优先核对：(.+)$`), (m) => `Check first: ${fixed(m[1])}`],
  [new RegExp(`^值得比较：(.+)$`), (m) => `Worth comparing: ${fixed(m[1])}`],
  [new RegExp(`^模拟候选：${ACT}$`), (m) => `Simulation pick: ${act(m[1])}`],
  // Standalone labels (field values): start form.
  [new RegExp(`^${HAND}$`), (m) => H(m[1]).start],
  [new RegExp(`^${TEX}$`), (m) => cap(translateTexture(m[1]))],
  [new RegExp(`^${PRE}$`), (m) => cap(pre(m[1]))],
  // Seat action text used only by the reference review unit-test snapshots.
  [/^下注 (\d[\d,]*)$/, (m) => `Bet ${m[1]}`],
];

function parseFragments(text) {
  const out = [];
  let i = 0;
  while (i < text.length) {
    if (text[i] === ' ' && out.length) i++;
    let matched = false;
    for (const [re, build] of FRAGMENTS) {
      re.lastIndex = i;
      const m = re.exec(text);
      if (m) {
        usedCopy.add(re.source);
        out.push(build(m));
        i = re.lastIndex;
        matched = true;
        break;
      }
    }
    if (!matched) return null;
  }
  return out.join(' ');
}

// Development aid: with REVIEW_COPY_COLLECT set, untranslated strings are
// collected here instead of throwing (the generator then fails at the end).
export const untranslated = new Set();
// Development aid: sources of the fragments and fixed strings that were used.
export const usedCopy = new Set();
export const copySources = () => [...FRAGMENTS.map(([re]) => re.source), ...Object.keys(REVIEW_FIXED), ...Object.keys(OPPONENT_FIXED)];

export function translateReview(text) {
  if (typeof text !== 'string') throw TypeError('translateReview expects a string');
  if (!CJK.test(text)) return text;
  let out = null;
  if (hasOwn(REVIEW_FIXED, text)) out = REVIEW_FIXED[text];
  else if (hasOwn(OPPONENT_FIXED, text)) out = OPPONENT_FIXED[text];
  if (out !== null) usedCopy.add(text);
  if (out === null)
    for (const [re, build] of WHOLE) {
      const m = re.exec(text);
      if (m) {
        out = build(m);
        break;
      }
    }
  if (out === null) out = parseFragments(text);
  if (out === null) {
    try {
      out = translateEngine(text);
    } catch {
      out = null;
    }
  }
  if (out === null || CJK.test(out)) {
    if (process.env.REVIEW_COPY_COLLECT) {
      untranslated.add(text);
      return '<untranslated>';
    }
    throw Error(`Untranslated review copy: ${JSON.stringify(text)}`);
  }
  return out;
}

// Translate every string inside a JSON-compatible value (object keys untouched).
export function translateReviewDeep(value) {
  if (typeof value === 'string') return translateReview(value);
  if (Array.isArray(value)) return value.map(translateReviewDeep);
  if (value && typeof value === 'object')
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, translateReviewDeep(v)]));
  return value;
}

export function reviewErrorCode(e) {
  const entry = REVIEW_ERRORS[e?.message];
  if (!entry) throw e;
  return entry.code;
}
