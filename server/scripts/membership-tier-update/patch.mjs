import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

/**
 * The live membershipService.js comes from earlier hunk patches, so each change anchors only on the code it
 * edits and is skipped when already present. The tier query is required; the doc comment is cosmetic and
 * left alone when it has been changed by hand.
 */
const steps = [
  {
    name: 'tier is the highest unfinished paid term',
    required: true,
    done: source => source.includes("ORDER BY array_position(ARRAY['MONTHLY','ANNUAL','LIFETIME','SUPER_LIFETIME'], sku) DESC, term_starts_at"),
    find: /( *)const covering = await db\.query\(`SELECT sku FROM membership_orders\n *WHERE period_id = \$1 AND term_starts_at <= \$2 AND term_ends_at > \$2\n *ORDER BY term_starts_at DESC LIMIT 1`, \[state\.periodId, new Date\(now\)\]\);\n *return covering\.rows\[0\]\?\.sku \?\? state\.sku;/,
    replace: (match, indent) =>
      `${indent}const highest = await db.query(\`SELECT sku FROM membership_orders\n` +
      `    WHERE period_id = $1 AND term_ends_at > $2\n` +
      `    ORDER BY array_position(ARRAY['MONTHLY','ANNUAL','LIFETIME','SUPER_LIFETIME'], sku) DESC, term_starts_at\n` +
      `    LIMIT 1\`, [state.periodId, new Date(now)]);\n` +
      `${indent}return highest.rows[0]?.sku ?? state.sku;`
  },
  {
    name: 'doc comment',
    required: false,
    done: source => source.includes('member who prepays a year counts as annual right away'),
    find: / \* The product that pays for `now`\. A periodic period keeps the SKU of its latest purchase, so an annual\n \* member who adds a month would otherwise look monthly; the covering order decides benefits instead\./,
    replace: () =>
      " * The highest product among the period's paid terms that have not ended. A periodic period keeps the SKU\n" +
      ' * of its latest purchase, so an annual member who adds a month would otherwise look monthly; and a monthly\n' +
      ' * member who prepays a year counts as annual right away instead of waiting for the month to run out.'
  }
];

/** Applies each missing change once; throws BASELINE_MISMATCH when the tier query is absent or ambiguous. */
export function patchModule(source) {
  let result = source.replace(/\r\n/g, '\n');
  let changed = false;
  for (const step of steps) {
    if (step.done(result)) continue;
    const count = (result.match(new RegExp(step.find.source, 'g')) || []).length;
    if (count === 0 && !step.required) continue;
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
  const name = 'membershipService.js';
  writeFileSync(resolve(output, name), patchModule(readFileSync(resolve(input, name), 'utf8')));
  console.log('PASS: prepared membership tier patch for', name);
}
