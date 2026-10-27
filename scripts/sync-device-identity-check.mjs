// Exercise production identity persistence across fresh runtimes (including app upgrades).
import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import vm from 'node:vm';
import { randomUUID } from 'node:crypto';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../entry/src/main/ets/core/stats/ReadStatsDevice.ts', import.meta.url), 'utf8')
  .replace(/^import[^\n]+\r?\n/gm, '').replace(/^export /gm, '');
function installation() {
  const disk = new Map(); let generated = 0, failFlush = false;
  const boot = (version) => {
    const cache = new Map();
    const context = vm.createContext({ deviceInfo: {}, console,
      util: { generateRandomUUID() { generated++; return randomUUID(); } },
      preferences: { async getPreferences(_, name) {
        if (!cache.has(name)) cache.set(name, new Map(disk.get(name) || []));
        const values = cache.get(name);
        return { get: async (key, fallback) => values.get(key) ?? fallback,
          put: async (key, value) => { values.set(key, value); },
          flush: async () => { if (failFlush) throw new Error('disk unavailable'); disk.set(name, new Map(values)); } };
      } }
    });
    vm.runInContext(stripTypeScriptTypes(source) + '\nthis.device=ReadStatsDevice;', context);
    return { id: () => context.device.id({ appVersion: version }), device: context.device };
  };
  return { disk, boot, generated: () => generated, fail: value => { failFlush = value; } };
}

test('concurrent first callers share one ID and upgrades/restarts retain it', async () => {
  const app = installation(), initial = app.boot('4.4.932');
  const ids = await Promise.all(Array.from({ length: 25 }, () => initial.id()));
  assert.equal(new Set(ids).size, 1);
  assert.equal(app.generated(), 1);
  assert.equal(await app.boot('4.4.934').id(), ids[0]);
  assert.equal(await app.boot('5.0.0').id(), ids[0]);
  assert.equal(app.generated(), 1);
});

test('legacy installation ID migrates unchanged and survives loss of sync state', async () => {
  const app = installation(), legacy = randomUUID();
  app.disk.set('account_cloud_sync_state', new Map([['device_id', legacy], ['state_account', 'cursor data']]));
  assert.equal(await app.boot('4.4.934').id(), legacy);
  assert.equal(app.generated(), 0);
  assert.equal(app.disk.get('account_cloud_sync_state').get('state_account'), 'cursor data');
  app.disk.delete('account_cloud_sync_state');
  assert.equal(await app.boot('4.4.935').id(), legacy);
  assert.equal(app.generated(), 0);
});

test('a failed durable write never hands out an unpersisted ID and migration can retry', async () => {
  const app = installation(), legacy = randomUUID();
  app.disk.set('account_cloud_sync_state', new Map([['device_id', legacy]]));
  app.fail(true);
  await assert.rejects(app.boot('4.4.934').id(), /disk unavailable/);
  assert.equal(app.disk.has('account_device_identity'), false);
  app.fail(false);
  assert.equal(await app.boot('4.4.934').id(), legacy);
  assert.equal(app.generated(), 0);
});

test('different installations remain distinct; clearing all app data creates a new installation', async () => {
  const first = installation(), second = installation();
  const id = await first.boot('4.4.934').id();
  assert.notEqual(await second.boot('4.4.934').id(), id);
  first.disk.clear();
  assert.notEqual(await first.boot('4.4.934').id(), id);
  const backup = fs.readFileSync(new URL('../entry/src/main/ets/utils/AppDataBackupService.ets', import.meta.url), 'utf8');
  const stores = backup.match(/SETTINGS_STORES: string\[\] = \[([\s\S]*?)\];/)[1];
  assert.ok(!stores.includes('account_device_identity'));
  assert.ok(!stores.includes('account_cloud_sync_state'));
});

test('retry in the same process cannot mistake an unflushed cache value for durable identity', async () => {
  const app = installation(), running = app.boot('4.4.934');
  app.fail(true);
  await assert.rejects(running.id(), /disk unavailable/);
  await assert.rejects(running.id(), /disk unavailable/);
  assert.equal(app.disk.has('account_device_identity'), false);
  app.fail(false);
  const recovered = await running.id();
  assert.equal(app.disk.get('account_device_identity').get('device_id'), recovered);
  assert.equal(await app.boot('4.4.935').id(), recovered);
  assert.equal(app.generated(), 1);
});
