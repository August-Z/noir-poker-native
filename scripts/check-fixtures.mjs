// Verifies the committed shared fixtures. The pinned reference repository is no
// longer public, so these files are the source of truth for both native domain
// layers: every file must parse, generated files must carry the pinned
// reference commit, and generated files must match fixtures/SHA256SUMS (a
// deliberate fixture change updates the sums in the same commit).
//   node scripts/check-fixtures.mjs
import { readFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REFERENCE_COMMIT = '03c78233f9454de54e378c5c81ba1dd25fa9b14e';
const dir = resolve(dirname(fileURLToPath(import.meta.url)), '../fixtures');
const sums = new Map(
  readFileSync(resolve(dir, 'SHA256SUMS'), 'utf8').trim().split('\n')
    .map((line) => line.split(/\s+/)).map(([hash, name]) => [name, hash]),
);
const failures = [];
const files = readdirSync(dir).filter((f) => f.endsWith('.json')).sort();
for (const name of files) {
  const text = readFileSync(resolve(dir, name), 'utf8');
  let data;
  try { data = JSON.parse(text); } catch (e) { failures.push(`${name}: invalid JSON (${e.message})`); continue; }
  if (data.generator === 'scripts/generate-reference-fixtures.mjs') {
    if (data.referenceCommit !== REFERENCE_COMMIT) failures.push(`${name}: referenceCommit is ${data.referenceCommit}`);
    const hash = createHash('sha256').update(text).digest('hex');
    if (sums.get(name) !== hash) failures.push(`${name}: does not match fixtures/SHA256SUMS`);
  }
}
for (const name of sums.keys()) if (!files.includes(name)) failures.push(`${name}: listed in SHA256SUMS but missing`);
if (failures.length) {
  console.error(failures.join('\n'));
  process.exit(1);
}
console.log(`Fixtures OK: ${files.length} files, ${sums.size} generated files match their checksums.`);
