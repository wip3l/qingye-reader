import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const route = `app.post('/v1/sync/reading-stats', {
    preHandler: authenticate, bodyLimit: 1024 * 1024
}, async (request) => {
    const userId = requiredUserId(request);
    await enforceAccountRateLimit(userId, 'reading-stats-exchange', config.http.syncRateLimitPerMinute);
    return inTransaction(client => exchangeReadingStats(client, userId, request.body));
});
`;
const importLine = "import { exchangeReadingStats } from './readingStats.js';\n";
const anchor = "app.post('/v1/auth/logout', { preHandler: authenticate }, async (request, reply) => {";
export function patchIndex(source) {
  const text = source.replace(/\r\n/g, '\n');
  if (text.includes('./readingStats.js') || text.includes('/v1/sync/reading-stats')) {
    assert.equal(text.split(importLine).length, 2, 'BASELINE_MISMATCH: reading stats import');
    assert.equal(text.split(route).length, 2, 'BASELINE_MISMATCH: reading stats route');
    assert.equal(text.split('/v1/sync/reading-stats').length, 2, 'Duplicate reading stats route');
    return source;
  }
  for (const dependency of ['authenticate', 'requiredUserId', 'enforceAccountRateLimit', 'inTransaction', 'config.http.syncRateLimitPerMinute']) {
    assert(text.includes(dependency), `BASELINE_MISMATCH: missing ${dependency}`);
  }
  const imports = text.match(/^import .+ from '\.\/sync\.js';\n/gm);
  assert.equal(imports?.length, 1, 'BASELINE_MISMATCH: sync import');
  assert.equal(text.split(anchor).length, 2, 'BASELINE_MISMATCH: logout route');
  return text.replace(imports[0], imports[0] + importLine).replace(anchor, route + anchor);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [input, output] = process.argv.slice(2);
  assert(input && output && resolve(input) !== resolve(output), 'Usage: node patch.mjs INPUT OUTPUT');
  writeFileSync(output, patchIndex(readFileSync(input, 'utf8')));
  console.log('PASS: compatible index.js; candidate prepared');
}
