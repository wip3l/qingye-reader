// Voice manager section folding: stored state, search override, drag-select skipping folded sections, section select-all.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const read = name => fs.readFileSync(new URL(`../entry/src/main/ets/${name}`, import.meta.url), 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });
function method(source, name) {
  const match = new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm').exec(source);
  assert(match, name);
  return source.slice(match.index, source.indexOf('\n  }', match.index) + 4);
}
const list = value => Array.from(value);

const disk = new Map();
const context = vm.createContext({
  console,
  preferences: { getPreferences: async () => ({
    get: async (key, fallback) => disk.has(key) ? disk.get(key) : fallback,
    put: async (key, value) => { disk.set(key, value); },
    flush: async () => {}
  }) }
});
vm.runInContext(compile(read('utils/TtsVoiceSectionFoldStore.ets')), context);
const store = vm.runInContext('TtsVoiceSectionFoldStore', context);

assert.deepEqual(list(store.parse('custom\nbogus\n local\ncustom')), ['local', 'custom'], 'known keys only, fixed order');
assert.deepEqual(list(store.parse('')), []);
assert.deepEqual(list(store.toggle(['custom'], 'system')), ['system', 'custom']);
assert.deepEqual(list(store.toggle(['system', 'custom'], 'system')), ['custom']);
assert.deepEqual(list(await store.load({})), [], 'nothing stored means everything expanded');
await store.save({}, ['cloud', 'local', 'cloud']);
assert.equal(disk.get('folded'), 'local\ncloud');
assert.deepEqual(list(await store.load({})), ['local', 'cloud']);

// Page logic: search shows everything, folded sections are skipped by drag selection, section select-all.
const source = read('pages/CustomTtsVoiceManager.ets');
context.TtsVoiceSectionFoldStore = store;
const Page = vm.runInContext(compile(`class Page { ${[
  'sectionFolded', 'batchKindSection', 'sectionSelectionKeys', 'sectionAllSelected', 'toggleSectionSelection', 'voiceAtPoint'
].map(name => method(source, name)).join('\n')} }; Page`), context);
const page = new Page();
const entries = [
  { key: 'local:a', kind: '离线音色' }, { key: 'sys:1', kind: '系统音色' },
  { key: 'cloud:x', kind: '云端音色' }, { key: 'custom:7', kind: '自定义音色' }, { key: 'custom:8', kind: '自定义音色' }
];
Object.assign(page, {
  searchText: '', foldedVoiceSections: ['custom'], selectedVoiceIds: [], isBatchOperating: false,
  batchVoices: () => entries,
  voiceSelectionAreas: new Map([['custom:7', [0, 0, 100, 50]], ['sys:1', [0, 60, 100, 110]]])
});
assert(page.sectionFolded('custom'));
assert(!page.sectionFolded('system'));
page.searchText = ' 晓 ';
assert(!page.sectionFolded('custom'), 'searching shows every section');
page.searchText = '';
assert.equal(page.voiceAtPoint(10, 10), null, 'a folded card keeps its old area but cannot be hit');
assert.equal(page.voiceAtPoint(10, 80), 'sys:1');
page.foldedVoiceSections = [];
assert.equal(page.voiceAtPoint(10, 10), 'custom:7');

assert.deepEqual(list(page.sectionSelectionKeys('custom')), ['custom:7', 'custom:8']);
page.selectedVoiceIds = ['sys:1', 'custom:8'];
page.toggleSectionSelection('custom');
assert.deepEqual(list(page.selectedVoiceIds), ['sys:1', 'custom:8', 'custom:7'], 'select-all adds only the section');
assert(page.sectionAllSelected('custom'));
page.toggleSectionSelection('custom');
assert.deepEqual(list(page.selectedVoiceIds), ['sys:1'], 'second tap clears only the section');

// Every section uses the foldable header, and the old plain title builder is gone.
for (const key of ['LOCAL', 'SYSTEM', 'CLOUD', 'CUSTOM']) {
  assert(source.includes(`this.voiceSectionHeader(TtsVoiceSectionFoldStore.${key},`), `${key} header`);
  assert(source.includes(`this.voiceSectionStack(TtsVoiceSectionFoldStore.${key},`), `${key} stack`);
}
assert(!source.includes('voiceSectionTitle('));
console.log('TTS voice section fold checks passed: stored state, search override, drag hit skipping, section select-all.');
