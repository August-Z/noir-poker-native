#!/usr/bin/env node
// Checks that the iOS UI copy table (ios/NoirPoker/Design/UiCopy.swift)
// mirrors the Android one (android/app/src/main/java/com/august/noirpoker/ui/UiCopy.kt)
// key for key and string for string. Interpolations ($n, ${x}, \(x)) are
// compared as placeholders. Exits non-zero and lists every difference.
//
// Usage: node scripts/check-ui-copy.mjs

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const kotlinPath = 'android/app/src/main/java/com/august/noirpoker/ui/UiCopy.kt';
const swiftPath = 'ios/NoirPoker/Design/UiCopy.swift';

const LITERAL = /"((?:[^"\\\n]|\\.)*)"/g;

function normalize(raw, language) {
  let text = raw;
  if (language === 'kotlin') {
    text = text.replace(/\$\{[^}]*\}/g, '{}').replace(/\$[A-Za-z_][A-Za-z0-9_]*/g, '{}');
  } else {
    text = text.replace(/\\\((?:[^()]|\([^()]*\))*\)/g, '{}');
    text = text.replace(/\\u\{([0-9A-Fa-f]+)\}/g, (_, hex) => String.fromCodePoint(parseInt(hex, 16)));
  }
  return text.replace(/\\(["\\'])/g, '$1').replace(/\\n/g, '\n');
}

/** Maps each declared key to the string literals of its value, in order. */
function parse(path, language) {
  const source = readFileSync(join(root, path), 'utf8')
    .split('\n')
    .filter((line) => !/^\s*(\/\/|\/\*\*|\*)/.test(line))
    .join('\n');
  const declaration =
    language === 'kotlin'
      ? /^\s*(?:const\s+)?(?:val|fun)\s+([A-Za-z_][A-Za-z0-9_]*)/gm
      : /^\s*static\s+(?:let|func)\s+([A-Za-z_][A-Za-z0-9_]*)/gm;
  const starts = [...source.matchAll(declaration)];
  const table = new Map();
  starts.forEach((match, i) => {
    const end = i + 1 < starts.length ? starts[i + 1].index : source.length;
    const body = source.slice(match.index + match[0].length, end);
    const literals = [...body.matchAll(LITERAL)].map((m) => normalize(m[1], language));
    if (table.has(match[1])) throw new Error(`${path}: duplicate key ${match[1]}`);
    table.set(match[1], literals);
  });
  if (table.size === 0) throw new Error(`${path}: no copy keys found`);
  return table;
}

const kotlin = parse(kotlinPath, 'kotlin');
const swift = parse(swiftPath, 'swift');
const problems = [];

for (const [key, values] of kotlin) {
  if (!swift.has(key)) {
    problems.push(`missing on iOS: ${key}`);
    continue;
  }
  const other = swift.get(key);
  if (JSON.stringify(values) !== JSON.stringify(other)) {
    problems.push(`${key} differs:\n    Android: ${JSON.stringify(values)}\n    iOS:     ${JSON.stringify(other)}`);
  }
}
for (const key of swift.keys()) {
  if (!kotlin.has(key)) problems.push(`missing on Android: ${key}`);
}

if (problems.length) {
  console.error(`UI copy differs between ${kotlinPath} and ${swiftPath}:`);
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}
console.log(`UI copy matches: ${kotlin.size} keys.`);
