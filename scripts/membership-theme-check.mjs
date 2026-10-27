import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const hour = 3600000;
function fixture() {
  const now = Date.parse('2026-10-21T12:00:00Z');
  const saved = [], applied = [], icons = [], values = new Map(), persisted = new Map();
  const state = { trial: false, fetch: async () => { throw new Error('offline'); },
    load: async () => ({ themeId: 'member-theme', customAccent: '#123456' }) };
  const sandbox = vm.createContext({
    readStatsTracker: { setOwnerId() {} },
    Date: class extends Date { static now() { return now; } },
    preferences: { getPreferences: async () => ({ get: async (key, fallback) => persisted.get(key) ?? fallback,
      put: async (key, value) => { persisted.set(key, value); },
      delete: async key => { persisted.delete(key); }, flush: async () => {} }) },
    AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value) },
    AccountCommerceApi: { fetchAccount: (...args) => state.fetch(...args) },
    ThemeTrialManager: { isActive: () => state.trial },
    AppIconManager: { optionById: id => ({ id }), applyIcon: async (_ctx, option) => { icons.push(option.id); } },
    BuiltinThemeRegistry: { isFree: id => id === 'free' }, ThemeIds: { CUSTOM: 'custom', OBSIDIAN_ARCHIVE: 'obsidian-archive' },
    AppThemeSettingsStore: { DEFAULT_THEME_ID: 'free', load: () => state.load(),
      activateTheme: (themeId, previous) => ({ ...previous, themeId }),
      save: async (_ctx, settings) => { saved.push(settings); },
      applyToStorage: settings => { applied.push(settings); } },
    ReaderFontBootstrap: { applyApplicationFont: () => {} }
  });
  for (const file of ['account/AccountCommerceModels.ets', 'account/AccountSessionStore.ets', 'account/MembershipThemeGuard.ets']) {
    const source = fs.readFileSync(new URL('../entry/src/main/ets/' + file, import.meta.url), 'utf8');
    vm.runInContext(stripTypeScriptTypes(source.replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/^export /gm, ''),
      { mode: 'strip' }), sandbox);
  }
  const { store, guard } = vm.runInContext('({store: AccountSessionStore, guard: MembershipThemeGuard})', sandbox);
  const account = (overrides = {}) => ({ userId: 'a', memberVerifiedAt: now,
    memberThemeIds: ['member-theme'], iapDebtPoints: 0, entitlements: [],
    membership: { active: true, restricted: false, serverNow: now,
      state: { sku: 'MONTHLY', expiresAt: now + hour } }, ...overrides });
  const login = value => store.saveLogin({}, { sessionToken: 'token-' + value.userId, account: value });
  return { now, state, saved, applied, icons, values, store, guard, account, login };
}

test('member themes follow server expiry, debt, explicit inclusion and bounded offline time', async () => {
  const f = fixture();
  await f.login(f.account());
  assert.equal(f.store.hasValidEntitlement('member-theme', f.now), true);
  assert.equal(f.store.hasValidEntitlement('standalone-theme', f.now), false);
  assert.equal(f.store.hasValidEntitlement('member-theme', f.now + hour), false);
  assert.equal(f.store.hasValidEntitlement('member-theme', f.now - 1), false);
  for (const override of [{ iapDebtPoints: 1 }, { membership: { active: true, restricted: true,
    serverNow: f.now, state: { expiresAt: null } } }, { membership: null }]) {
    await f.login(f.account(override));
    assert.equal(f.store.hasValidEntitlement('member-theme', f.now), false);
  }
  await f.login(f.account({ membership: { active: true, restricted: false,
    serverNow: f.now, state: { expiresAt: null } } }));
  assert.equal(f.store.hasValidEntitlement('member-theme', f.now + 71 * hour), true);
  assert.equal(f.store.hasValidEntitlement('member-theme', f.now + 73 * hour), false);
  await f.store.clear({});
  assert.equal(f.store.hasValidEntitlement('member-theme', f.now), false);
});

test('separate theme purchase survives membership expiry; free/custom themes are preserved', async () => {
  const f = fixture();
  await f.login(f.account({ membership: null,
    entitlements: [{ themeId: 'member-theme', expiresAt: f.now + hour }] }));
  await f.guard.refresh({});
  assert.equal(f.saved.length, 0);
  for (const themeId of ['free', 'custom']) {
    await f.store.clear({});
    f.state.load = async () => ({ themeId, customAccent: '#123456' });
    await f.guard.refresh({});
  }
  assert.equal(f.saved.length, 0);
});

test('expired member-only theme falls back without dropping custom settings', async () => {
  const f = fixture();
  await f.login(f.account());
  await f.guard.refresh({}); // Seen while granted by membership.
  assert.equal(f.saved.length, 0);
  await f.login(f.account({ membership: { active: false, serverNow: f.now,
    state: { expiresAt: f.now - 1 } } }));
  await f.guard.refresh({});
  assert.equal(f.saved.length, 1);
  assert.equal(f.saved[0].themeId, 'free');
  assert.equal(f.saved[0].customAccent, '#123456');
  assert.equal(f.applied.length, 1);
});

test('offline refresh preserves valid cached access, but does not extend 72-hour authorization', async () => {
  for (const hours of [7, 73]) {
    const f = fixture();
    await f.login(f.account());
    await f.guard.refresh({});
    await f.login(f.account({ memberVerifiedAt: f.now - hours * hour,
      membership: { active: true, restricted: false, serverNow: f.now - hours * hour,
        state: { expiresAt: null } } }));
    await f.guard.refresh({});
    assert.equal(f.saved.length, hours === 7 ? 0 : 1);
  }
});

test('logout withdraws a membership-granted theme but keeps legacy active themes', async () => {
  const f = fixture();
  await f.login(f.account());
  await f.guard.refresh({});
  await f.store.clear({});
  await f.guard.refresh({});
  assert.equal(f.saved.length, 1);
  assert.equal(f.saved[0].themeId, 'free');

  const g = fixture();
  await g.login(g.account({ membership: null,
    entitlements: [{ themeId: 'member-theme', expiresAt: g.now + hour }] }));
  await g.guard.refresh({});
  await g.store.clear({}); // A separately bought theme stays applied after logout, as before.
  await g.guard.refresh({});
  assert.equal(g.saved.length, 0);
  g.state.load = async () => ({ themeId: 'legacy-paid' }); // Never seen through membership.
  await g.guard.refresh({});
  assert.equal(g.saved.length, 0);
});

test('late account response cannot overwrite a newly logged-in account', async () => {
  const f = fixture();
  await f.login(f.account({ memberVerifiedAt: f.now - 7 * hour }));
  f.state.fetch = async () => { await f.login(f.account({ userId: 'b' })); return f.account(); };
  await f.guard.refresh({});
  assert.equal(f.store.account().userId, 'b');
});

test('a theme trial starting while the guard awaits settings is not canceled by fallback', async () => {
  const f = fixture();
  await f.store.clear({});
  f.state.load = async () => { f.state.trial = true; return { themeId: 'trial-theme' }; };
  await f.guard.refresh({});
  assert.equal(f.saved.length, 0);
  assert.equal(f.applied.length, 0);
});

test('exclusive theme requires both super membership and an unexpired manual grant', async () => {
  const f = fixture(), themeId = 'obsidian-archive';
  const member = { active: true, restricted: false, serverNow: f.now,
    state: { sku: 'SUPER_LIFETIME', expiresAt: null } };
  await f.login(f.account({ membership: member, memberThemeIds: [themeId] }));
  assert.equal(f.store.hasValidEntitlement(themeId), false, 'Membership library must not auto-grant');
  const entitlements = [{ themeId, expiresAt: f.now + hour }];
  await f.login(f.account({ membership: member, entitlements }));
  assert.equal(f.store.hasValidEntitlement(themeId), true);
  assert.equal(f.store.hasValidEntitlement(themeId, f.now + hour), false);
  assert.equal(f.store.hasValidEntitlement(themeId, f.now - 1), false);
  for (const sku of ['MONTHLY', 'ANNUAL', 'LIFETIME']) {
    await f.login(f.account({ membership: { ...member, state: { sku, expiresAt: null } }, entitlements }));
    assert.equal(f.store.hasValidEntitlement(themeId), false);
  }
  await f.login(f.account({ membership: member, entitlements, iapDebtPoints: 1 }));
  assert.equal(f.store.hasValidEntitlement(themeId), false);
  await f.store.clear({});
  assert.equal(f.store.hasValidEntitlement(themeId), false);
});

test('expired exclusive theme and every custom source fall back; exclusive icon is reset', async () => {
  for (const settings of [
    { themeId: 'obsidian-archive' },
    { themeId: 'custom', customBaseThemeId: 'obsidian-archive' },
    ...['startup', 'palette', 'reader', 'ttsPanel', 'bubble', 'navigation', 'book', 'layout'].flatMap(category =>
      ['customLightSources', 'customDarkSources'].map(mode =>
        ({ themeId: 'custom', [mode]: { [category + 'ThemeId']: 'obsidian-archive' } })))
  ]) {
    const f = fixture();
    f.state.load = async () => ({ ...settings, customAccent: '#123456' });
    f.values.set('appIconId', 'theme_obsidian_archive');
    await f.login(f.account({ membership: { active: true, restricted: false, serverNow: f.now,
      state: { sku: 'SUPER_LIFETIME', expiresAt: null } },
      entitlements: [{ themeId: 'obsidian-archive', expiresAt: f.now }] }));
    await f.guard.refresh({});
    assert.equal(f.saved[0].themeId, 'free');
    assert.equal(f.saved[0].customAccent, '#123456');
    assert.deepEqual(f.icons, ['default']);
  }
});

test('valid exclusive annual grant remains applied until expiry', async () => {
  const f = fixture();
  f.state.load = async () => ({ themeId: 'obsidian-archive' });
  await f.login(f.account({ membership: { active: true, restricted: false, serverNow: f.now,
    state: { sku: 'SUPER_LIFETIME', expiresAt: null } },
    entitlements: [{ themeId: 'obsidian-archive', expiresAt: f.now + hour }] }));
  await f.guard.refresh({});
  assert.equal(f.saved.length, 0);
  await f.store.clear({});
  await f.guard.refresh({});
  assert.equal(f.saved[0].themeId, 'free');
});
