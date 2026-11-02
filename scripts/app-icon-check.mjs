import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');
const source = (name) => stripTypeScriptTypes(
  read(`entry/src/main/ets/${name}.ets`)
    .replace(/^import\s+[\s\S]*?\s+from\s+['"][^'"]+['"];?\r?$/gm, '')
    .replace(/\bexport /g, ''), { mode: 'transform' });
let saved = 'default';
let current = 'default';
let enabled = '';
let queries = 0;
const calls = [];
let failSet = false;
let failSave = false;
let deferredQuery = null;
let deferredSet = null;
let exclusiveGranted = false;
const manifest = JSON.parse(read('AppScope/app.json5')).app.alternateIcons;
const snapshot = () => manifest.map(({ name }, index) =>
  ({ iconName: name, iconId: index + 1, enabled: name === enabled }));
const sandbox = {
  console: { warn() {} },
  $r: (name) => name,
  deviceInfo: { sdkApiVersion: 26 },
  AccountSessionStore: { hasOwnedEntitlement: id => id === 'obsidian-archive' && exclusiveGranted },
  AppIconSettings: class { iconId = 'default'; },
  AppIconSettingsStore: {
    DEFAULT_ICON_ID: 'default',
    normalizeIconId: (id) => id?.trim() || 'default',
    applyToStorage: (settings) => { current = settings.iconId; },
    save: async (_, settings) => {
      if (failSave) throw new Error('disk unavailable');
      saved = settings.iconId;
    }
  },
  bundleManager: {
    getAlternateIcons: async () => {
      queries++;
      if (deferredQuery) return deferredQuery;
      return snapshot();
    },
    setAlternateIcon: async (name) => {
      calls.push(name);
      if (failSet) throw new Error('system rejected switch');
      if (deferredSet) await deferredSet;
      assert(name === '' || manifest.some((entry) => entry.name === name), 'Unregistered icon');
      enabled = name;
    }
  }
};
vm.createContext(sandbox);
vm.runInContext(source('theme/ThemeModels') + '\n' +
  source('theme/BuiltinThemeRegistry') + '\n' + source('utils/AppIconManager') +
  '\nglobalThis.manager = AppIconManager; globalThis.themes = BuiltinThemeRegistry.all();', sandbox);
const manager = sandbox.manager;
const option = (id) => manager.optionById(id);
const files = fs.readdirSync(path.join(root, 'AppScope/resources/base/media'));
const entryFiles = fs.readdirSync(path.join(root, 'entry/src/main/resources/base/media'));
function assertResource(resource, appScopeOnly = true) {
  const stem = resource.replace(/^\$media:|^app\.media\./, '');
  const names = appScopeOnly ? files : [...files, ...entryFiles];
  const file = names.find((name) => name.slice(0, name.lastIndexOf('.')) === stem);
  assert(file, `Missing resource ${resource}`);
  if (file.endsWith('.json')) {
    const layered = JSON.parse(read(`AppScope/resources/base/media/${file}`))['layered-image'];
    assertResource(layered.background);
    assertResource(layered.foreground);
  }
}
assert.equal(new Set(manifest.map((entry) => entry.name)).size, manifest.length);
assert.equal(manager.OPTIONS.length, manifest.length + 1);
for (const entry of manifest) {
  assert.equal(option(entry.name).id, entry.name);
  assertResource(entry.icon);
}
for (const item of manager.OPTIONS) assertResource(item.preview, false);
for (const theme of sandbox.themes) {
  assert.equal(manager.optionForTheme(theme.id).title, theme.name, `Theme/icon name mismatch: ${theme.id}`);
}
// Exercise the production color selector with both variants of the exclusive theme.
vm.runInContext(source('theme/ThemeRuntime') + '\nglobalThis.runtime = ThemeRuntime;', sandbox);
const exclusive = sandbox.themes.find(theme => theme.id === 'obsidian-archive');
function luminance(hex) {
  const rgb = [1, 3, 5].map(start => parseInt(hex.slice(start, start + 2), 16) / 255)
    .map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  return rgb[0] * .2126 + rgb[1] * .7152 + rgb[2] * .0722;
}
function contrast(a, b) {
  const x = luminance(a), y = luminance(b);
  return (Math.max(x, y) + .05) / (Math.min(x, y) + .05);
}
for (const variant of [exclusive.light, exclusive.dark]) {
  for (const background of [variant.colors.pageColor, variant.colors.cardColor]) {
    for (const foreground of [variant.colors.primaryTextColor, variant.colors.subTextColor, variant.colors.accentColor]) {
      assert(contrast(background, foreground) >= 4.5, `Insufficient theme text contrast: ${background}/${foreground}`);
    }
  }
  for (const background of [variant.colors.accentColor, variant.colors.buttonColor, variant.colors.dangerColor]) {
    assert(contrast(background, sandbox.runtime.onAccentColor(background)) >= 4.5);
  }
  assert(contrast(variant.reader.backgroundColor, variant.reader.textColor) >= 7);
  assert(contrast(variant.reader.backgroundColor, variant.reader.subTextColor) >= 4.5);
}
assert.equal(sandbox.runtime.onAccentColor(), '#FFFFFF', 'Preserve existing callers without an explicit fill');
vm.runInContext(stripTypeScriptTypes(read('entry/src/main/ets/utils/HexColor.ts')
  .replace(/\bexport /g, ''), { mode: 'transform' }), sandbox);
vm.runInContext(source('model/reader/ReaderRegexFontRule') +
  '\nglobalThis.bubbleResolver = ReaderRegexBubbleStyleResolver;', sandbox);
for (const darkMode of [false, true]) {
  const bubble = sandbox.bubbleResolver.resolve(null, {
    darkMode, inheritedMode: 'bubble', inheritedBubbleStyleId: 'gilded-orbit',
    inheritedColor: '#B59B68', accentColor: '#B59B68',
    surfaceColor: darkMode ? '#191B1F' : '#F8F3E9', normalTextColor: '#302C26'
  }, false);
  assert(contrast(bubble.backgroundColor, bubble.textColor) >= 7,
    `Exclusive bookplate must retain readable text in ${darkMode ? 'dark' : 'light'} mode`);
}
assert.equal(manager.optionForTheme('custom').title, '自定义主题');

// Old devices must never call the new APIs, including the default-icon path.
sandbox.deviceInfo.sdkApiVersion = 25;
await manager.syncCurrentIcon({});
await assert.rejects(manager.applyIcon({}, option('theme_cat_pipi')), /该能力需要鸿蒙7及以上/);
await assert.rejects(manager.applyIcon({}, option('default')), /该能力需要鸿蒙7及以上/);
assert.equal(queries, 0);
assert.equal(calls.length, 0);
assert.equal(current, 'default');
sandbox.deviceInfo.sdkApiVersion = 26;

await assert.rejects(manager.applyIcon({}, option('theme_obsidian_archive')));
assert.equal(calls.length, 0, 'Unclaimed exclusive icon must never call the system setter');
exclusiveGranted = true;
await manager.applyIcon({}, option('theme_obsidian_archive'));
assert.equal(current, 'theme_obsidian_archive');
exclusiveGranted = false;
await manager.applyIcon({}, option('default'));

await manager.applyIcon({}, option('theme_cat_pipi'));
assert.equal(enabled, 'theme_cat_pipi');
assert.equal(current, enabled);
assert.equal(saved, enabled);
failSet = true;
await assert.rejects(manager.applyIcon({}, option('theme_warm_paper')));
assert.equal(current, 'theme_cat_pipi', 'Failed switches must not publish the requested icon');
failSet = false;
await manager.applyIcon({}, option('default'));
assert.equal(enabled, '');
assert.equal(current, 'default');
const callsBeforeReset = calls.length;
await manager.applyIcon({}, option('default'));
assert.equal(calls.length, callsBeforeReset, 'Resetting the default icon must be a no-op');

enabled = 'theme_rose_letter';
await manager.syncCurrentIcon({});
assert.equal(current, enabled, 'System state must replace stale saved state');
let finishQuery;
deferredQuery = new Promise((resolve) => { finishQuery = resolve; });
const staleSnapshot = snapshot();
const sync = manager.syncCurrentIcon({});
await manager.applyIcon({}, option('theme_starwish_magic'));
finishQuery(staleSnapshot);
await sync;
assert.equal(current, 'theme_starwish_magic', 'A stale query must not undo a successful switch');
deferredQuery = null;

let finishSet;
deferredSet = new Promise((resolve) => { finishSet = resolve; });
const change = manager.applyIcon({}, option('theme_crimson_archive'));
await assert.rejects(manager.applyIcon({}, option('theme_ink_wash')), /正在切换/);
await manager.syncCurrentIcon({});
finishSet();
await change;
assert.equal(current, 'theme_crimson_archive');
deferredSet = null;
failSave = true;
await manager.applyIcon({}, option('theme_forest_mist'));
assert.equal(current, 'theme_forest_mist', 'Successful system state survives disk failure');
assert.equal(enabled, current);

const page = read('entry/src/main/ets/pages/ThemeSettings.ets');
assert(page.indexOf("this.themeApplyToggleRow('icon')") > page.indexOf("this.themeApplyToggleRow('cover')"));
assert(page.includes('this.applyDialogApplyIcon = false;'), 'applying a theme keeps the desktop icon unless the user opts in');
assert(page.includes('choice.applyIcon = this.applyDialogApplyIcon;'));
assert(page.includes('if (choice.applyIcon)'));
assert(page.includes('AppIconManager.optionById(this.appIconId).preview'));
assert(page.includes('AppIconManager.optionForTheme(theme.id).preview'));
assert(!read('entry/src/main/ets/utils/AppIconManager.ets').includes('@kit.AppGalleryKit'));
console.log(`App icon checks passed: ${manifest.length} alternate icons, ${sandbox.themes.length} themes, API gating, failure/reset/reconciliation/concurrency paths.`);
