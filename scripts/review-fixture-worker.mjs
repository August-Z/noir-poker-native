// Worker thread for scripts/generate-reference-fixtures.mjs: runs the expensive
// reference review calls (analyzeDecision, compareCandidateActions) in
// parallel. Every call is deterministic (seeded from the snapshot), so results
// do not depend on scheduling. Math.random is forbidden here as well.
import { parentPort, workerData } from 'node:worker_threads';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

Math.random = () => {
  throw Error('Unseeded Math.random use during review fixture generation.');
};
const load = (path) => import(pathToFileURL(resolve(workerData.referenceRoot, path)));
const analysis = await load('src/review/analysis.js');
const counterfactual = await load('src/review/counterfactual.js');
const calls = {
  analyzeDecision: (s, options) => analysis.analyzeDecision(s, options),
  compareCandidateActions: (s, alternatives, options) => counterfactual.compareCandidateActions(s, alternatives, options),
};
parentPort.on('message', ({ id, fn, args }) => {
  try {
    parentPort.postMessage({ id, result: calls[fn](...args) });
  } catch (e) {
    parentPort.postMessage({ id, error: String(e?.stack ?? e) });
  }
});
