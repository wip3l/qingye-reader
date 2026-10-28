// Run: node scripts/bookshelf-cover-badges-check.mjs
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const compile = source => stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'strip' });
const preferencesData = new Map();
const storage = new Map();
let failFlush = false;
let changes = 0;
const context = vm.createContext({
  preferences: { getPreferences: async () => ({
    get: async (key, fallback) => preferencesData.get(key) ?? fallback,
    put: async (key, value) => preferencesData.set(key, value),
    flush: async () => { if (failFlush) throw Error('disk full'); }
  }) },
  AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
  CloudSyncChangeTracker: { markApplicationPreferenceChanged: () => { changes++; } }
});
vm.runInContext(compile(readEtsModule('utils/BookshelfCoverBadgeSettings.ts')) +
  compile(readEtsModule('utils/BookshelfDisplaySettingsStore.ets')) +
  '\nglobalThis.api = { Rules: BookshelfCoverBadgeSettings, Store: BookshelfDisplaySettingsStore, Settings: BookshelfDisplaySettings };', context);
const { Rules, Store, Settings } = context.api;
const reset = () => { Store.cachedSettings = null; preferencesData.clear(); storage.clear(); failFlush = false; };

assert.equal(Rules.normalize(''), Rules.DEFAULT);
assert.equal(Rules.normalize(undefined, false, false), 'pin|update,unread||');
assert.equal(Rules.normalize('|||', false, false), '|||'); // intentional empty ≠ legacy
assert.equal(Rules.normalize('garbage', false, true), 'pin|update,unread||source');
assert.equal(Rules.normalize('pin,pin,source|update,unread,type|source,type|invalid'), 'pin,source|update,unread|type|');
assert.equal(Rules.move(Rules.DEFAULT, 0, ['type', 'source']), 'type,source|update,unread||');
assert.equal(Rules.move(Rules.DEFAULT, 1, []), 'pin||type|source');
assert.equal(Rules.move(Rules.DEFAULT, 7, ['source']), Rules.DEFAULT);
assert.equal(Rules.unreadText(0), '');
assert.equal(Rules.unreadText(NaN), '');
assert.equal(Rules.unreadText(Infinity), '');
assert.equal(Rules.unreadText(-1), '');
assert.equal(Rules.unreadText(12), '12');
assert.equal(Rules.unreadText(99), '99');
assert.equal(Rules.unreadText(100), '99+');
for (const corner of Rules.CORNERS) {
  for (const first of Rules.ITEMS) {
    for (const second of Rules.ITEMS) {
      const moved = Rules.move(Rules.DEFAULT, corner, [first, second]);
      const flat = moved.replaceAll('|', ',').split(',').filter(Boolean);
      assert.equal(new Set(flat).size, flat.length, moved);
      assert(moved.split('|').every(part => part.split(',').filter(Boolean).length <= 2));
      assert.equal(Rules.location(moved, first), corner);
      assert.equal(Rules.location(moved, second), corner);
      assert.equal(Rules.normalize(moved), moved);
    }
  }
}

// Migrate both legacy toggles, including old cloud payloads without the new field.
for (const showType of [false, true]) for (const showSource of [false, true]) {
  reset();
  preferencesData.set('bookshelfShowTypeBadge', showType);
  preferencesData.set('bookshelfShowSource', showSource);
  const migrated = await Store.load({});
  assert.equal(Rules.location(migrated.coverBadges, 'type') >= 0, showType);
  assert.equal(Rules.location(migrated.coverBadges, 'source') >= 0, showSource);
  const oldCloudPayload = new Settings();
  delete oldCloudPayload.coverBadges;
  oldCloudPayload.showTypeBadge = showType;
  oldCloudPayload.showSource = showSource;
  await Store.save({}, oldCloudPayload);
  Store.applyToStorage(oldCloudPayload);
  assert.equal(storage.get('bookshelfCoverBadges'), migrated.coverBadges);
}

// Preserve an explicitly empty configuration across save, reload, cloud and other settings edits.
reset();
const allHidden = new Settings();
allHidden.coverBadges = '|||';
allHidden.layoutMode = 'loose';
allHidden.showIntro = false;
await Store.save({}, allHidden);
Store.applyToStorage(allHidden);
Store.cachedSettings = null;
const reloaded = await Store.load({});
assert.equal(reloaded.coverBadges, '|||');
assert.equal(reloaded.showTypeBadge, false);
assert.equal(reloaded.showSource, false);
const otherEdit = Store.fromStorage();
otherEdit.showTags = false;
await Store.save({}, otherEdit);
assert.equal(preferencesData.get('bookshelfCoverBadges'), '|||');
assert.equal(otherEdit.layoutMode, 'loose');
assert.equal(otherEdit.showIntro, false);

// Failed persistence must not publish a new cached config or enqueue a cloud change.
const lastSaved = await Store.load({});
const attempted = Store.fromStorage();
attempted.coverBadges = Rules.DEFAULT;
failFlush = true;
const previousChanges = changes;
await assert.rejects(Store.save({}, attempted), /disk full/);
assert.equal((await Store.load({})).coverBadges, lastSaved.coverBadges);
assert.equal(storage.get('bookshelfCoverBadges'), '|||');
assert.equal(changes, previousChanges);

// A retained list item must refresh when the update flag or source changes at unchanged progress.
const shelf = readEtsModule('components/home/BookshelfPage.ets');
const keyStart = shelf.indexOf('  shelfBookRenderKey(');
const keyMethod = shelf.slice(keyStart, shelf.indexOf('\n  }', keyStart) + 4);
vm.runInContext(compile(`class CoverBadgeRenderKeys { ${keyMethod} } globalThis.keys = new CoverBadgeRenderKeys();`), context);
context.keys.shelfCoverRenderVersions = new Map();
const metadata = new Map();
const sampleBook = { bookUrl: 'fixture', isPinned: false, origin: 'source-url', originName: '书源甲',
  durChapterTime: 1, durChapterIndex: 10, durChapterPos: 0, totalChapterNum: 23,
  getVariable: key => metadata.get(key) || '' };
const keyBeforeUpdate = context.keys.shelfBookRenderKey(sampleBook, 'tile');
metadata.set('shelfHasUpdate', '1');
assert.notEqual(context.keys.shelfBookRenderKey(sampleBook, 'tile'), keyBeforeUpdate);
const keyBeforeRename = context.keys.shelfBookRenderKey(sampleBook, 'tile');
sampleBook.originName = '书源乙';
assert.notEqual(context.keys.shelfBookRenderKey(sampleBook, 'tile'), keyBeforeRename);
console.log('PASS: 100 corner-move combinations; migration, empty configuration, persistence, cloud compatibility, unread boundaries and retained-item refresh');
