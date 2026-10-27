import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../entry/src/main/ets/', import.meta.url));
const source = fs.readFileSync(path.join(root, 'utils/ReaderFontBootstrap.ets'), 'utf8');
const values = new Map();
const applied = [];
const context = vm.createContext({
  AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value) },
  ReaderSettingsStore: { FONT_MODE_DEVICE: 'device', FONT_MODE_THEME: 'system' },
  ReaderSystemFontHelper: { FALLBACK_SYSTEM_FONT_FAMILY: 'sans-serif' },
  ThemeRuntime: { fontFamily: () => 'theme-face' },
  ReaderFontItem: class {},
  ReaderFontHelper: {
    resolveDisplayName: name => name,
    registerFont: (_ui, item) => ({ registered: true, familyName: item.familyName, filePath: item.filePath })
  },
  hilog: { warn() {}, info() {} }
});
vm.runInContext(stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, '')) + '\nglobalThis.bootstrap = ReaderFontBootstrap;', context);
const bootstrap = context.bootstrap;
const appContext = { getApplicationContext: () => ({ setFont: family => applied.push(family) }) };
const published = () => values.get('applicationFontFamily');

// First launch keeps ArkUI's native system-font following, but initializes Select bindings.
values.set('readerFontMode', 'device');
bootstrap.applyApplicationFont(appContext, 'first-launch');
assert.equal(published(), 'sans-serif');
assert.deepEqual(applied, []);

// Cold-start registration calls the lower-level font setter directly.
assert.equal(bootstrap.registerSettings(appContext, {}, {
  fontFamily: 'custom-a', fontFilePath: '/fonts/a.ttf', fontSourceName: 'A'
}, 'cold-start'), true);
assert.equal(published(), 'custom-a');
assert.equal(applied.at(-1), published());

// Changing fonts updates the observable family even with an existing page alive.
values.set('readerActiveFontFamily', 'custom-b');
bootstrap.applyApplicationFont(appContext, 'font-change');
assert.equal(published(), 'custom-b');
assert.equal(applied.at(-1), published());

// An unregistered custom font must never leak into controls; theme and device modes recover.
values.set('readerFontRegistered', false);
values.set('readerFontMode', 'system');
bootstrap.applyApplicationFont(appContext, 'theme');
assert.equal(published(), 'theme-face');
assert.equal(applied.at(-1), published());
values.set('readerActiveFontFamily', '');
values.set('readerFontMode', 'device');
bootstrap.applyApplicationFont(appContext, 'restore-system');
assert.equal(published(), 'sans-serif');
assert.equal(applied.at(-1), published());

function files(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const file = path.join(dir, entry.name);
    return entry.isDirectory() ? files(file) : [file];
  });
}
let controls = 0;
for (const file of files(root).filter(file => file.endsWith('.ets'))) {
  const text = fs.readFileSync(file, 'utf8');
  const structs = [...text.matchAll(/(?:export )?struct \w+ \{/g)];
  for (const select of text.matchAll(/\bSelect\(/g)) {
    const owner = structs.findLastIndex(match => match.index < select.index);
    assert.ok(owner >= 0, `${file}: Select owner`);
    const body = text.slice(structs[owner].index, structs[owner + 1]?.index ?? text.length);
    assert.match(body, /@StorageProp\('applicationFontFamily'\) applicationFontFamily:/,
      `${file}: Select owner must observe global font changes`);
    const end = text.indexOf('.onSelect(', select.index);
    assert.ok(end > select.index, `${file}: Select handler`);
    const chain = text.slice(select.index, end);
    assert.match(chain, /\.font\(\{[^{}]*family: this\.applicationFontFamily[^{}]*\}\)/,
      `${file}: collapsed Select text must use the global font`);
    controls++;
  }
}
assert.ok(controls >= 34, 'all existing dropdowns are covered');
console.log(`Select font checks passed: ${controls} dropdowns; cold start, font changes, theme and system fallback.`);
