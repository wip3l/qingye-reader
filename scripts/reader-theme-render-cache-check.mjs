import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const root = new URL('../entry/src/main/ets/', import.meta.url);
const read = name => fs.readFileSync(new URL(name, root), 'utf8');
const source = read('pages/ReadBook.ets');
function method(name) {
  const start = source.search(new RegExp(`^  ${name}\\(`, 'm'));
  assert(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
let themeCalls = 0, modeCalls = 0, bubbleCalls = 0;
const runtime = { readerBackgroundColor: dark => { themeCalls++; return dark ? '#101826' : '#F7F1E3'; },
  readerTextColor: dark => dark ? '#D8D8D8' : '#333333', readerSubTextColor: () => '#777777',
  readerBackgroundAssetId: () => 'paper-art', readerContentTone: dark => dark ? 'dark' : 'light',
  readerBackgroundImageFit: () => 'cover',
  regexEmphasisModeFor: dark => { modeCalls++; return dark ? 'bubble' : 'color'; },
  regexBubbleStyleFor: dark => { bubbleCalls++; return dark ? 'ink-brush' : 'warm-scroll'; } };
const context = vm.createContext({ console, ThemeRuntime: runtime,
  ThemeAssetRegistry: { readerBackgroundImage: () => '' } });
const modules = ['utils/HexColor.ts', 'utils/ReaderThemeHelper.ets', 'utils/ReaderCustomThemeHelper.ets',
  'utils/ReaderThemeRenderCache.ets'].map(name => read(name).replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''));
const methods = ['currentReaderTheme', 'currentReaderThemeIndex', 'currentCustomThemeScheme', 'customThemeData',
  'themeRegexEmphasisMode', 'themeRegexBubbleStyleId'];
vm.runInContext(stripTypeScriptTypes(modules.join('\n') + `\nclass Reader {
  ${methods.map(method).join('\n')}
}; globalThis.Reader = Reader; globalThis.Cache = ReaderThemeRenderCache;
globalThis.Helper = ReaderThemeHelper; globalThis.Custom = ReaderCustomThemeHelper;`), context);
let parses = 0;
const parse = context.Custom.parse;
context.Custom.parse = (...args) => { parses++; return parse(...args); };
const reader = new context.Reader();
Object.assign(reader, { readerThemeRenderCache: new context.Cache(), appDarkMode: false, themeRevision: 0,
  readerLightThemeIndex: 4, readerDarkThemeIndex: 4, readerCustomThemesRaw: '',
  readerLightCustomThemeBackgroundColor: '#F5F5F5', readerLightCustomThemeTextColor: '#333333',
  readerDarkCustomThemeBackgroundColor: '#1F2329', readerDarkCustomThemeTextColor: '#D8D8D8' });
function baseline() {
  const scheme = reader.currentCustomThemeScheme();
  return context.Helper.themeAt(reader.appDarkMode, reader.currentReaderThemeIndex(), scheme.backgroundColor,
    scheme.textColor, scheme.backgroundType === 'image' ? scheme.backgroundImageUri : '', scheme.backgroundImageFit);
}
for (const dark of [false, true]) for (const index of [0, 1, 2, 3, 4, -10, 99]) {
  reader.appDarkMode = dark; reader.readerLightThemeIndex = index; reader.readerDarkThemeIndex = index;
  assert.equal(JSON.stringify(reader.currentReaderTheme()), JSON.stringify(baseline()));
}
reader.readerCustomThemesRaw = JSON.stringify({ schemes: [{ id: 'photo', name: 'paper', darkMode: false,
  backgroundColor: '#112233', textColor: '#DDEEFF', backgroundType: 'image',
  backgroundImageUri: 'file:///paper.png', backgroundImageFit: 'contain' }], lightSelectedId: 'photo' });
reader.appDarkMode = false; reader.readerLightThemeIndex = 3;
assert.equal(JSON.stringify(reader.currentReaderTheme()), JSON.stringify(baseline()));
assert.equal(reader.currentReaderTheme().backgroundImageUri, 'file:///paper.png');
reader.themeRegexEmphasisMode(); reader.themeRegexBubbleStyleId();
const before = [themeCalls, parses, modeCalls, bubbleCalls], retained = reader.currentReaderTheme();
for (let update = 0; update < 1000; update++) {
  assert.equal(reader.currentReaderTheme(), retained);
  reader.themeRegexEmphasisMode(); reader.themeRegexBubbleStyleId();
}
assert.deepEqual([themeCalls, parses, modeCalls, bubbleCalls], before,
  'repeated page/background/cache-key queries must not parse schemes or resolve theme packs');
for (const [key, value] of [['themeRevision', 1], ['appDarkMode', true], ['readerDarkThemeIndex', 3],
  ['readerCustomThemesRaw', ''], ['readerLightCustomThemeBackgroundColor', '#123456'],
  ['readerLightCustomThemeTextColor', '#789ABC'], ['readerDarkCustomThemeBackgroundColor', '#223344'],
  ['readerDarkCustomThemeTextColor', '#CCDDFF']]) {
  const previous = reader.currentReaderTheme(); reader[key] = value;
  const actual = reader.currentReaderTheme();
  assert.notEqual(actual, previous, `${key} must invalidate the retained theme`);
  assert.equal(JSON.stringify(actual), JSON.stringify(baseline()), `${key} preserves existing theme behavior`);
}
assert.equal(reader.themeRegexEmphasisMode(), 'bubble');
assert.equal(reader.themeRegexBubbleStyleId(), 'ink-brush');
const revisionReads = modeCalls; reader.themeRevision++;
reader.themeRegexEmphasisMode(); reader.themeRegexBubbleStyleId();
assert.equal(modeCalls, revisionReads + 1, 'theme edits refresh both inherited emphasis defaults');
console.log('PASS: cached page-theme and regex defaults, custom image/legacy/index parity, revision/color-mode invalidation');
