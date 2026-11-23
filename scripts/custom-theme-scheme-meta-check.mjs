// 自定义方案的置顶、手动顺序、创建/修改时间与“导入”标记：存取、改名保存时的保留、旧数据推断与云端合并。
import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

// 沙箱里建的数组原型不同，比较前转成本域的普通值。
const plain = value => JSON.parse(JSON.stringify(value));

function fixture() {
  const clock = { now: 1800000000000 };
  const values = new Map(), stores = new Map();
  const sandbox = vm.createContext({
    Date: class extends Date { static now() { return clock.now; } },
    preferences: { getPreferences: async (_context, name) => {
      if (!stores.has(name)) stores.set(name, new Map());
      const data = stores.get(name);
      return { get: async (key, fallback) => data.get(key) ?? fallback,
        put: async (key, value) => data.set(key, value), delete: async key => data.delete(key),
        flush: async () => {} };
    } },
    AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value) },
    ThemeIds: { CUSTOM: 'custom' },
    AppThemeSettings: class {},
    AppThemeSettingsStore: { cloneSettings: value => ({ customLightReaderBackgroundAssetId: '',
      customDarkReaderBackgroundAssetId: '', ...structuredClone(value ?? {}) }), createForTheme: () => ({}) },
    CustomThemeQuota: { current: () => 100 },
    CloudSyncChangeTracker: { markPreferenceChanged: () => {} },
    CloudThemeChange: { notify: () => {} },
    ReaderSettingsStore: { profileIdFor: (themeId, schemeId) => `${themeId}__${schemeId}`, deleteProfile: async () => {} },
    ThemePackRegistry: { getByPackageId: () => null },
    ThemePackStore: {}
  });
  const source = fs.readFileSync(new URL('../entry/src/main/ets/utils/CustomThemeSchemeStore.ets', import.meta.url), 'utf8');
  vm.runInContext(stripTypeScriptTypes(source.replace(/^import\s[\s\S]*?;\r?\n/gm, '')
    .replace(/^export /gm, ''), { mode: 'strip' }), sandbox);
  const schemes = vm.runInContext('CustomThemeSchemeStore', sandbox);
  return { clock, schemes, stores };
}

test('new schemes record creation time; rename and save bump only the modified time', async () => {
  const f = fixture();
  const [first] = await f.schemes.load({}, {});
  assert.equal(first.createdAt, f.clock.now);
  f.clock.now += 1000;
  const added = await f.schemes.addWith({}, {}, '雾凇', {});
  assert.equal(added.createdAt, f.clock.now);
  assert.equal(added.updatedAt, f.clock.now);
  assert.equal(added.imported, false);
  f.clock.now += 5000;
  assert.equal(await f.schemes.rename({}, {}, added.id, '雾凇夜'), true);
  let saved = (await f.schemes.load({}, {})).find(item => item.id === added.id);
  assert.equal(saved.createdAt, added.createdAt);
  assert.equal(saved.updatedAt, f.clock.now);
  f.clock.now += 5000;
  await f.schemes.saveScheme({}, {}, { id: added.id, name: '', settings: {} });
  saved = (await f.schemes.load({}, {})).find(item => item.id === added.id);
  assert.equal(saved.updatedAt, f.clock.now);
  assert.equal(saved.name, '雾凇夜');
});

test('pinning keeps the modified time and survives later saves', async () => {
  const f = fixture();
  await f.schemes.load({}, {});
  const added = await f.schemes.addWith({}, {}, '琥珀', {});
  f.clock.now += 60000;
  assert.equal(await f.schemes.setPinned({}, {}, [added.id], true), true);
  assert.equal(await f.schemes.setPinned({}, {}, [added.id], true), false);
  let saved = (await f.schemes.load({}, {})).find(item => item.id === added.id);
  assert.equal(saved.pinned, true);
  assert.equal(saved.updatedAt, added.updatedAt);
  await f.schemes.updateInfo({}, {}, added.id, '作者', '说明');
  saved = (await f.schemes.load({}, {})).find(item => item.id === added.id);
  assert.equal(saved.pinned, true);
});

test('reorder rewrites the stored order and appends ids it was not given', async () => {
  const f = fixture();
  const [first] = await f.schemes.load({}, {});
  const a = await f.schemes.addWith({}, {}, 'A', {});
  const b = await f.schemes.addWith({}, {}, 'B', {});
  await f.schemes.reorder({}, {}, [b.id, a.id]);
  assert.deepEqual(plain((await f.schemes.load({}, {})).map(item => item.id)), [b.id, a.id, first.id]);
});

test('imports are marked, replacing an import keeps pin and creation time', async () => {
  const f = fixture();
  await f.schemes.load({}, {});
  const imported = await f.schemes.addImported({}, {}, '墨韵', {}, '砚台', '');
  assert.equal(imported.imported, true);
  await f.schemes.setPinned({}, {}, [imported.id], true);
  f.clock.now += 1000;
  const replaced = await f.schemes.addImported({}, {}, '墨韵', {}, '砚台', imported.id);
  assert.equal(replaced.id, imported.id);
  assert.equal(replaced.pinned, true);
  assert.equal(replaced.createdAt, imported.createdAt);
  assert.equal(replaced.updatedAt, f.clock.now);
});

test('old stored schemes infer creation time and import flag from their id', async () => {
  const f = fixture();
  f.stores.set('custom_theme_schemes', new Map([['schemes', JSON.stringify([
    { id: 'custom_1', name: '自定义主题 1', revision: 1, settings: {} },
    { id: 'custom_1700000000000_2', name: '自建', revision: 1, settings: {} },
    { id: 'custom_1700000001234_import', name: '导入', revision: 1, settings: {} }
  ])]]));
  const loaded = await f.schemes.load({}, {});
  assert.deepEqual(plain(loaded.map(item => [item.createdAt, item.updatedAt, item.imported, item.pinned])), [
    [0, 0, false, false], [1700000000000, 1700000000000, false, false], [1700000001234, 1700000001234, true, false]]);
});

test('cloud payloads from older clients keep the local pin and times', async () => {
  const f = fixture();
  const [first] = await f.schemes.load({}, {});
  await f.schemes.setPinned({}, {}, [first.id], true);
  await f.schemes.replaceFromSync({}, {}, [{ id: first.id, name: '云端名', revision: 3, settings: {} }]);
  let saved = (await f.schemes.load({}, {}))[0];
  assert.equal(saved.name, '云端名');
  assert.equal(saved.pinned, true);
  assert.equal(saved.createdAt, first.createdAt);
  await f.schemes.replaceFromSync({}, {}, [{ id: first.id, name: '云端名', revision: 4, settings: {},
    pinned: false, createdAt: 1600000000000, updatedAt: 1600000005000, imported: true }]);
  saved = (await f.schemes.load({}, {}))[0];
  assert.deepEqual([saved.pinned, saved.createdAt, saved.updatedAt, saved.imported],
    [false, 1600000000000, 1600000005000, true]);
});
