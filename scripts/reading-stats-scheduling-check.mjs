// Executes the production scheduler and change tracker; substitutes platform I/O and entity serialization.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const root = new URL('../entry/src/main/ets/', import.meta.url);
function load(file, globals, names) {
  const code = fs.readFileSync(new URL(file, root), 'utf8')
    .replace(/^import[\s\S]*?;\r?\n/gm, '').replace(/^export /gm, '');
  const context = vm.createContext({ console, ...globals });
  vm.runInContext(stripTypeScriptTypes(code, { mode: 'strip' }) + `\nthis.exports={${names}};`, context);
  return context.exports;
}

function harness() {
  let now = 10000000, pending = 1, user = 'alice', token = 'token-a', device = 'phone';
  let full = 0, stats = 0, flushes = 0, statsHook = async () => {}, wifi = true;
  const forceRefreshes = [], timers = [], storage = new Map();
  const settings = { enabled: true, autoSyncEnabled: true, foregroundSyncEnabled: true,
    readingDataEnabled: true, wifiOnly: false, pendingCount: 0, status: 'synced', lastSuccessAt: 0 };
  const AppStorage = { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) };
  const { CloudSyncChangeTracker: tracker } = load('account/CloudSyncChangeTracker.ts', { AppStorage }, 'CloudSyncChangeTracker');
  const db = { initWithContext: async () => {}, getReadStatsUploadBoundary: async () => 1000,
    getPendingReadStats: async () => pending ? [{}] : [] };
  const state = { cursor: 0, entities: {} };
  const { CloudSyncCoordinator: sync } = load('account/CloudSyncCoordinator.ets', {
    AppStorage, CloudSyncChangeTracker: tracker, util: { TextEncoder },
    Date: class extends Date { static now() { return now; } },
    setTimeout: (fn, ms) => { timers.push({ fn, ms }); return timers.length; },
    clearTimeout() {}, AccountApiError: class extends Error {},
    AccountSessionStore: { load: async () => {}, isLoggedIn: () => true,
      account: () => ({ userId: user }), token: () => token },
    CloudSyncSettingsStore: { STATUS_SYNCING: 'syncing', STATUS_SYNCED: 'synced', STATUS_ERROR: 'error',
      STORAGE_RUNTIME_ACTIVE: 'active', load: async () => settings,
      saveRuntimeState: async (_, owner, status, lastSuccessAt, pendingCount, errorMessage) => {
        Object.assign(settings, { status, lastSuccessAt, pendingCount, errorMessage });
      } },
    CloudSyncStateStore: { deviceId: async () => device, load: async () => state, save: async () => {} },
    AppDatabase: { getInstance: () => db }, readStatsTracker: { flushAndWait: async () => { flushes++; } },
    ReadStatsCloudSync: {
      assertSession: (id, tok) => { assert.equal(id, user); assert.equal(tok, token); },
      run: async (_, id, dev, tok, force) => {
        stats++; forceRefreshes.push(force); await statsHook(); pending = 0;
        return { uploaded: 1, downloaded: 1 };
      }
    }, CloudSyncIssueStore: { create: () => ({}) }
  }, 'CloudSyncCoordinator');
  sync.buildLocalEntities = async () => [];
  sync.buildOperations = () => [];
  sync.exchangeRequest = async () => ({});
  sync.exchangeSyncWithRetry = async () => { full++; return { changes: [], acknowledgements: [], nextCursor: 0, hasMore: false }; };
  sync.validateResponse = () => {};
  sync.applyAcknowledgements = async () => 0;
  sync.applyChanges = async () => 0;
  sync.recordIssues = async () => {};
  sync.isWifiConnected = () => wifi;
  return { sync, tracker, settings, storage, timers, forceRefreshes,
    counters: () => ({ full, stats, flushes }),
    advance: (ms = 60000) => { now += ms; }, pending: value => { pending = value; },
    session: (u, tok = u) => { user = u; token = tok; }, device: value => { device = value; },
    wifi: value => { wifi = value; }, hook: value => { statsHook = value; },
    auto: (trigger = sync.TRIGGER_CHANGE) => sync.syncAutomatically({}, trigger) };
}

test('initial automatic sync registers device; subsequent stats-only changes skip full exchange', async () => {
  const h = harness(); await h.auto();
  assert.equal(h.counters().full, 1); assert.equal(h.counters().stats, 1);
  h.advance(); h.pending(1); await h.auto();
  assert.equal(h.counters().full, 1); assert.equal(h.counters().stats, 2);
  assert.equal(h.storage.has('shelfUpdateTime'), false, 'statistics must not reload the bookshelf');
  h.advance(); await h.auto();
  assert.equal(h.counters().stats, 2, 'clean lifecycle triggers do no HTTP work');
});

test('progress and preferences still perform full sync; manual sync always refreshes devices', async () => {
  const h = harness(); await h.auto();
  h.advance(); h.tracker.markReadingProgressChanged(); await h.auto();
  assert.equal(h.counters().full, 2);
  h.advance(); h.tracker.markPreferenceChanged(); await h.auto();
  assert.equal(h.counters().full, 3);
  assert.equal(h.tracker.hasUnsyncedChanges(), false);
  await h.sync.syncNow({}); assert.equal(h.counters().full, 4);
  assert.deepEqual(h.forceRefreshes, [false, false, false, true]);
});

test('statistics success does not postpone the 30-minute full refresh', async () => {
  const h = harness(); await h.auto();
  h.advance(29 * 60000); h.pending(1); await h.auto();
  assert.equal(h.counters().full, 1);
  h.advance(60000); await h.auto(h.sync.TRIGGER_FOREGROUND);
  assert.equal(h.counters().full, 2);
});

test('account, token, device changes and prior errors force a full exchange', async () => {
  const h = harness(); await h.auto();
  for (const change of [() => h.session('bob'), () => h.session('bob', 'renewed'),
    () => h.device('tablet'), () => { h.settings.status = 'error'; }, () => { h.settings.pendingCount = 1; }]) {
    const before = h.counters().full;
    h.advance(); h.pending(1); change(); await h.auto();
    assert.equal(h.counters().full, before + 1);
  }
});

test('general changes arriving during a statistics-only run remain dirty for the next run', async () => {
  const h = harness(); await h.auto(); h.advance(); h.pending(1);
  h.hook(async () => h.tracker.markPreferenceChanged()); await h.auto();
  assert.equal(h.counters().full, 1);
  assert.equal(h.tracker.hasUnsyncedChanges(), true);
  h.hook(async () => {}); h.advance(); await h.auto();
  assert.equal(h.counters().full, 2); assert.equal(h.tracker.hasUnsyncedChanges(), false);
});

test('manual request during automatic statistics upload waits and then performs a full refresh', async () => {
  const h = harness(); await h.auto(); h.advance(); h.pending(1);
  let release, entered;
  const ready = new Promise(resolve => { entered = resolve; });
  const blocked = new Promise(resolve => { release = resolve; });
  h.hook(async () => { entered(); await blocked; });
  const automatic = h.auto(); await ready;
  const manual = h.sync.syncNow({});
  release(); await Promise.all([automatic, manual]);
  assert.equal(h.counters().full, 2);
  assert.deepEqual(h.forceRefreshes, [false, false, true]);
});

test('statistics queued while a run is active schedule a deferred check', async () => {
  const h = harness(); await h.auto(); h.advance(); h.pending(1);
  h.sync.running = Promise.resolve({});
  await h.auto(); assert.equal(h.timers.length, 1);
  assert.equal(h.counters().stats, 1);
  h.sync.running = null; await h.timers[0].fn();
  // Timer callback starts a promise without returning it; drain the platform-free microtasks.
  for (let i = 0; i < 40; i++) await Promise.resolve();
  assert.equal(h.counters().stats, 2);
});

test('automatic scope switches and Wi-Fi restriction still gate statistics requests', async () => {
  for (const disable of [h => { h.settings.enabled = false; }, h => { h.settings.autoSyncEnabled = false; },
    h => { h.settings.wifiOnly = true; h.wifi(false); }, h => { h.settings.readingDataEnabled = false; }]) {
    const h = harness(); disable(h); await h.auto();
    assert.equal(h.counters().full, 0); assert.equal(h.counters().stats, 0);
  }
  const h = harness(); h.settings.foregroundSyncEnabled = false;
  await h.auto(h.sync.TRIGGER_FOREGROUND); assert.equal(h.counters().stats, 0);
  await h.auto(h.sync.TRIGGER_BACKGROUND); assert.equal(h.counters().stats, 1);
});

test('short-interval lifecycle requests are merged by the existing throttle', async () => {
  const h = harness(); await h.auto(); h.advance(1000); h.pending(1);
  await h.auto(); await h.auto();
  assert.equal(h.timers.length, 1); assert.equal(h.counters().stats, 1);
  h.advance(15000); await h.timers[0].fn();
  for (let i = 0; i < 40; i++) await Promise.resolve();
  assert.equal(h.counters().stats, 2); assert.equal(h.counters().full, 1);
});
