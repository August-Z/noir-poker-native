import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { writeFileSync, readFileSync, mkdirSync } from 'node:fs';
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
const fixtures = { referenceCommit: '03c78233f9454de54e378c5c81ba1dd25fa9b14e', cases: cases.map(item => {
  const cards = item.cards.map(([rank,suit]) => ({rank,suit,symbol:['♠','♥','♣','♦'][suit],key:`${suit}-${rank}`}));
  const result = evaluate(cards);
  return {name:item.name,cards:cards.map(({rank,suit})=>({rank,suit})),score:result.score,bestCardKeys:result.cards.map(card=>card.key)};
}) };
const text = JSON.stringify(fixtures, null, 2) + '\n';
const destination = resolve(root, 'fixtures/hand-ranks.json');
if (process.argv.includes('--check')) {
  if (readFileSync(destination, 'utf8') !== text) throw new Error('Reference fixtures differ from the pinned source.');
  console.log(`${cases.length} reference fixture cases verified.`);
} else {
  mkdirSync(dirname(destination), {recursive:true});
  writeFileSync(destination, text);
  console.log(`Wrote ${cases.length} reference fixture cases.`);
}
