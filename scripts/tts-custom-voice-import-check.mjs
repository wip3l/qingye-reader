// Custom voice import: id-less entries, duplicate detection, kept ids/local state, and both import entry points.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const read = name => fs.readFileSync(new URL(`../entry/src/main/ets/${name}`, import.meta.url), 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });

class HttpTTS {
  id = 0; name = ''; url = ''; contentType = ''; concurrentRate = ''; loginUrl = ''; loginUi = '';
  loginCheckJs = ''; header = ''; jsLib = ''; jsEngine = ''; enabledCookieJar = false; customOrder = 0;
  lastUpdateTime = 0; enabled = true; speedMode = '';
}
const context = vm.createContext({ HttpTTS });
vm.runInContext(compile(read('utils/TtsVoiceModels.ets')), context);
const voices = vm.runInContext('TtsCustomVoices', context);
const json = value => JSON.stringify(value);
const names = list => Array.from(list, voice => voice.name);

// Stored data keeps a stable id even when one is missing; import marks it for a fresh id.
assert.equal(voices.parse(json([{ name: 'a', url: 'u' }]))[0].id, 0, 'stored voices without id stay stable');
assert.equal(voices.parse(json([{ id: '12', name: 'a', url: 'u' }]))[0].id, 12, 'string ids are read');
assert(Number.isNaN(voices.parseImport(json([{ name: 'a', url: 'u' }]))[0].id), 'missing id is marked on import');
assert(Number.isNaN(voices.parseImport(json([{ id: 'x', name: 'a', url: 'u' }]))[0].id), 'non-numeric id is marked');
assert.equal(voices.parse(json([{ name: 'a', url: 'u', customOrder: '' }]))[0].customOrder, 0, 'blank numbers use fallback');

// Several id-less entries sharing one url but with different names all survive and get distinct ids.
let result = voices.mergeImported([], voices.parseImport(json([
  { name: '女声', url: 'https://tts/a' }, { name: '男声', url: 'https://tts/a' }, { name: '童声', url: 'https://tts/b' }
])));
assert.deepEqual(names(result.voices), ['女声', '男声', '童声']);
assert.equal(new Set(result.voices.map(voice => voice.id)).size, 3, 'fresh ids are unique');
assert(result.voices.every(voice => Number.isFinite(voice.id) && voice.id > 0));
assert.equal(result.added, 3);
assert.equal(result.updated, 0);
assert.equal(voices.importSummary(result), '已导入 3 个自定义音色');

// Name + url match keeps the existing id and local state while taking the imported content.
const existing = voices.parse(json([
  { id: 7, name: '女声', url: 'https://tts/a', header: 'old', enabled: false, customOrder: 3 },
  { id: 8, name: '男声', url: 'https://tts/b' }
]));
result = voices.mergeImported(existing, voices.parseImport(json([
  { id: 99, name: '女声', url: 'https://tts/a', header: 'new', enabled: true, customOrder: 0 }
])));
assert.equal(result.voices.length, 2);
assert.equal(result.voices[0].id, 7, 'existing id survives so the current selection still resolves');
assert.equal(result.voices[0].header, 'new', 'imported content replaces the old one');
assert.equal(result.voices[0].enabled, false, 'a voice the user disabled stays disabled');
assert.equal(result.voices[0].customOrder, 3);
assert.deepEqual([...result.importedIds], [7]);
assert.equal(voices.importSummary(result), '已更新 1 个自定义音色');

// Same id and url with a new name is the same voice (rename); same id with another url is a new voice.
result = voices.mergeImported(existing, voices.parseImport(json([
  { id: 8, name: '男声二', url: 'https://tts/b' }, { id: 8, name: '另一个', url: 'https://tts/c' }
])));
assert.deepEqual(names(result.voices), ['女声', '男声二', '另一个']);
assert.equal(result.voices[1].id, 8);
assert.notEqual(result.voices[2].id, 8, 'id clash with a different url gets a fresh id');
assert.equal(result.added, 1);
assert.equal(result.updated, 1);
assert.equal(voices.importSummary(result), '已导入 1 个、更新 1 个自定义音色');

// Duplicates inside one file collapse into one entry and count once.
result = voices.mergeImported([], voices.parseImport(json([
  { name: '女声', url: 'https://tts/a', header: '1' }, { name: '女声', url: 'https://tts/a', header: '2' }
])));
assert.equal(result.voices.length, 1);
assert.equal(result.voices[0].header, '2', 'later duplicate wins');
assert.equal(result.added, 1);
assert.equal(result.updated, 0);

// Entries in one file that share an id and url but differ by name are separate voices, and re-importing
// the same file changes nothing (it used to rename-swallow one entry, then add it back on the next import).
const sharedIdFile = json([
  { id: 1, name: 'b', url: 'https://tts/x' }, { id: 1, name: 'c', url: 'https://tts/x' }, { name: 'c', url: 'https://tts/x' }
]);
let stored = voices.mergeImported([], voices.parseImport(sharedIdFile)).voices;
assert.deepEqual(names(stored), ['b', 'c']);
const firstImport = JSON.stringify(stored);
for (let i = 0; i < 3; i++) {
  stored = voices.mergeImported(voices.parse(JSON.stringify(stored)), voices.parseImport(sharedIdFile)).voices;
  assert.equal(JSON.stringify(stored), firstImport, 'repeated import of the same file is a no-op');
}
stored = voices.mergeImported(voices.parse(json([{ id: 1, name: 'c', url: 'https://tts/y' }])), voices.parseImport(json([
  { name: 'c', url: 'https://tts/y' }, { id: 3, name: 'b', url: 'https://tts/y' }, { id: 1, name: 'b', url: 'https://tts/y' },
  { id: 1, name: 'c', url: 'https://tts/y' }, { id: 1, name: 'a', url: 'https://tts/y' }
]))).voices;
const settled = JSON.stringify(stored);
assert.deepEqual(names(stored).sort(), ['a', 'b', 'c'], 'no entry is renamed away by a later one in the same file');
stored = voices.mergeImported(voices.parse(settled), voices.parseImport(json([
  { name: 'c', url: 'https://tts/y' }, { id: 3, name: 'b', url: 'https://tts/y' }, { id: 1, name: 'b', url: 'https://tts/y' },
  { id: 1, name: 'c', url: 'https://tts/y' }, { id: 1, name: 'a', url: 'https://tts/y' }
]))).voices;
assert.equal(JSON.stringify(stored), settled);

// A fresh id never collides with an explicit id that appears later in the same file.
vm.runInContext('globalThis.__now = Date.now; Date.now = () => 500;', context);
try {
  result = voices.mergeImported([], voices.parseImport(json([
    { name: 'a', url: 'https://tts/a' }, { id: 500, name: 'b', url: 'https://tts/a' }
  ])));
} finally {
  vm.runInContext('Date.now = globalThis.__now;', context);
}
assert.deepEqual(names(result.voices), ['a', 'b']);
assert.notEqual(result.voices[0].id, 500);
assert.equal(result.voices[1].id, 500);

// Both import entry points share this merge instead of keeping their own copies.
for (const file of ['pages/CustomTtsVoiceManager.ets', 'pages/TtsSettings.ets']) {
  const source = read(file);
  assert(source.includes('TtsCustomVoices.parseImport(content)'), `${file} parses with import id handling`);
  assert(source.includes('TtsCustomVoices.mergeImported('), `${file} uses the shared merge`);
  assert(!/ensureUnique\w*VoiceId/.test(source), `${file} has no private dedupe copy`);
}
console.log('TTS custom voice import checks passed: id-less entries, duplicates, kept ids and local state, shared entry points.');
