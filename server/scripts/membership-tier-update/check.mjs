// Loads the candidate membershipService.js next to the live membershipPolicy.js / membershipSales.js and runs
// membershipTierSku against a recording fake database (no network or database access).
// Usage: node check.mjs CANDIDATE_DIR [LIVE_DIR]  (LIVE_DIR defaults to CANDIDATE_DIR)
import assert from 'node:assert/strict';
import { copyFileSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const candidate = resolve(process.argv[2] || '.');
const live = resolve(process.argv[3] || candidate);
const scratch = mkdtempSync(join(tmpdir(), 'membership-tier-check-'));
try {
  writeFileSync(join(scratch, 'package.json'), '{"type":"module"}\n');
  copyFileSync(join(candidate, 'membershipService.js'), join(scratch, 'membershipService.js'));
  for (const name of ['membershipPolicy.js', 'membershipSales.js']) copyFileSync(join(live, name), join(scratch, name));
  const service = await import(pathToFileURL(join(scratch, 'membershipService.js')).href);
  // The rest of the module still loads with the live siblings.
  for (const name of ['membershipSnapshot', 'quoteMembership', 'purchaseMembership', 'claimMembershipGift']) {
    assert.equal(typeof service[name], 'function', `${name} missing`);
  }

  const calls = [];
  const fake = rows => ({ query: async (sql, params) => { calls.push({ sql, params }); return { rows }; } });
  const now = Date.parse('2028-03-10T12:00:00+08:00');
  const periodic = { periodId: 'period', sku: 'MONTHLY', expiresAt: now + 86400000 };

  // Lifetime periods answer from their own SKU without a query.
  assert.equal(await service.membershipTierSku(fake([]), { ...periodic, sku: 'LIFETIME', expiresAt: null }, now), 'LIFETIME');
  assert.equal(calls.length, 0);

  // The query picks the highest SKU among terms not yet ended, including prepaid ones that start later.
  assert.equal(await service.membershipTierSku(fake([{ sku: 'ANNUAL' }]), periodic, now), 'ANNUAL');
  const { sql, params } = calls[0];
  assert.match(sql, /term_ends_at > \$2/);
  assert.doesNotMatch(sql, /term_starts_at <= \$2/, 'still limited to the term covering now');
  assert.match(sql, /ORDER BY array_position\(ARRAY\['MONTHLY','ANNUAL','LIFETIME','SUPER_LIFETIME'\], sku\) DESC/);
  assert.deepEqual(params, ['period', new Date(now)]);

  // No order rows (old data): falls back to the period's SKU.
  assert.equal(await service.membershipTierSku(fake([]), periodic, now), 'MONTHLY');
  console.log('PASS: membershipTierSku loads with live modules and ranks unfinished terms (no network/database access)');
} finally {
  rmSync(scratch, { recursive: true, force: true });
}
