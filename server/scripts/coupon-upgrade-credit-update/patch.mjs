import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

/**
 * The live membershipPolicy.js is the product of earlier hunk patches, so it is not byte-identical to any
 * clean build. Each change anchors only on the statement it edits and is skipped when already present.
 */
const steps = [
  {
    name: 'upgrade credit keeps the coupon',
    done: source => /permanentCreditPoints: product\.months === null \? pricePoints : 0,/.test(source),
    find: /(?:( *)\/\/ A later upgrade credits what this permanent product actually cost[^\n]*\n)?( *)permanentCreditPoints: product\.months === null \? pricePoints - couponPoints : 0,/,
    replace: (match, commentIndent, indent) =>
      `${indent}// A later upgrade credits the price this permanent product sold at. A coupon spent on it is\n` +
      `${indent}// credited too: it is single-use, so clawing it back on upgrade would leave it worth nothing.\n` +
      `${indent}permanentCreditPoints: product.months === null ? pricePoints : 0,`
  },
  {
    // Quotes issued by the old rule carry the old credit; the new version makes them expire.
    name: 'policy version 3',
    done: source => /export const MEMBERSHIP_POLICY_VERSION = 3;/.test(source),
    find: /export const MEMBERSHIP_POLICY_VERSION = 2;/,
    replace: () => 'export const MEMBERSHIP_POLICY_VERSION = 3;'
  }
];

/** Applies each missing change once; throws BASELINE_MISMATCH naming the step whose anchor is absent or ambiguous. */
export function patchModule(source) {
  let result = source.replace(/\r\n/g, '\n');
  let changed = false;
  for (const step of steps) {
    if (step.done(result)) continue;
    const global = new RegExp(step.find.source, 'g');
    const count = (result.match(global) || []).length;
    assert.equal(count, 1, `BASELINE_MISMATCH: cannot place "${step.name}" (${count} anchors); no live files changed`);
    result = result.replace(step.find, step.replace);
    assert(step.done(result), `Patch step did not apply: ${step.name}`);
    changed = true;
  }
  return changed ? result : source;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [input, output] = process.argv.slice(2);
  assert(input && output && resolve(input) !== resolve(output), 'Usage: node patch.mjs INPUT_DIR OUTPUT_DIR');
  const name = 'membershipPolicy.js';
  writeFileSync(resolve(output, name), patchModule(readFileSync(resolve(input, name), 'utf8')));
  console.log('PASS: prepared coupon upgrade credit patch for', name);
}
