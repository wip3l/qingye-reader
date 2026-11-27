// Plugin voices: merged into the custom voice list at runtime, never persisted, imported, or exported.
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

const pluginVoice = (id, name) => {
  const voice = new HttpTTS();
  voice.id = id;
  voice.name = name;
  voice.url = `plugin-tts://io.example.tts/${encodeURIComponent(name)}`;
  voice.speedMode = 'client';
  return voice;
};
const stored = json([{ id: 1, name: '我的音色', url: 'https://tts/a' }]);

// Without a provider the list is exactly what was stored.
voices.extraVoicesProvider = null;
assert.deepEqual(names(voices.parse(stored)), ['我的音色']);

// With a provider, plugin voices are appended after the user's own voices, also when nothing is stored.
let provided = [pluginVoice(-11, '艺柠（声桥）'), pluginVoice(-12, '星芒（声桥）')];
voices.extraVoicesProvider = () => provided;
assert.deepEqual(names(voices.parse(stored)), ['我的音色', '艺柠（声桥）', '星芒（声桥）']);
assert.deepEqual(names(voices.parse('')), ['艺柠（声桥）', '星芒（声桥）']);
assert.deepEqual(names(voices.parse('not json')), ['艺柠（声桥）', '星芒（声桥）']);

// Stale plugin entries left in stored data are dropped; the provider is the only source of plugin voices.
const staleStored = json([
  { id: 1, name: '我的音色', url: 'https://tts/a' },
  { id: -99, name: '旧插件音色', url: 'plugin-tts://io.old/x' }
]);
assert.deepEqual(names(voices.parse(staleStored)), ['我的音色', '艺柠（声桥）', '星芒（声桥）']);

// Turning the plugin off (empty provider) removes its voices without touching the user's.
provided = [];
assert.deepEqual(names(voices.parse(stored)), ['我的音色']);
provided = [pluginVoice(-11, '艺柠（声桥）')];

// A throwing provider never breaks the user's list.
voices.extraVoicesProvider = () => { throw new Error('registry not ready'); };
assert.deepEqual(names(voices.parse(stored)), ['我的音色']);
voices.extraVoicesProvider = () => provided;

// Import parsing ignores plugin voices on both sides.
assert.deepEqual(names(voices.parseImport(staleStored)), ['我的音色']);

// Saving and exporting strip plugin voices.
const list = voices.parse(stored);
assert.equal(list.length, 2);
assert(voices.isPluginVoice(list[1]));
assert(!voices.isPluginVoice(list[0]));
assert(!voices.isPluginVoice(null));
assert.deepEqual(names(voices.withoutPluginVoices(list)), ['我的音色']);

// The real save path goes through SystemTtsReader.serializeCustomVoices, which must filter.
const systemReader = read('utils/SystemTtsReader.ets');
assert.match(systemReader,
  /static serializeCustomVoices\(voices: HttpTTS\[\]\): string \{\s*return JSON\.stringify\(TtsCustomVoices\.withoutPluginVoices\(voices\)\);/,
  'serializeCustomVoices filters plugin voices');

// Voice manager: export and edit/delete/toggle are guarded for plugin voices.
const manager = read('pages/CustomTtsVoiceManager.ets');
assert.match(manager, /const voices = TtsCustomVoices\.withoutPluginVoices\(selectedVoices\);/, 'export drops plugin voices');
for (const method of ['toggleVoiceEnabled', 'toggleVoiceState', 'deleteVoice', 'openEditDialog']) {
  assert.match(manager, new RegExp(`  ${method}\\([^)]*\\): void \\{\\s*if \\(this\\.pluginVoiceBlocked\\(voice\\)\\) return;`),
    `${method} is blocked for plugin voices`);
}

// The plugin list and synthesis both respect the feature switch, and the reader loads the engine lazily.
assert.match(read('core/plugin/PluginTtsVoices.ets'), /if \(!PluginFeatureStore\.enabled\(\)\) return out;/);
assert.match(read('core/plugin/PluginTtsBridge.ets'), /if \(!PluginFeatureStore\.enabled\(\)\) \{\s*throw new Error/);
const httpReader = read('utils/HttpTtsReader.ets');
assert.match(httpReader, /await import\('\.\.\/core\/plugin\/PluginTtsBridge'\)/, 'plugin bridge is imported on demand');
assert.doesNotMatch(httpReader, /^import .*pluginengine/m, 'reader does not import the plugin engine eagerly');
assert.doesNotMatch(read('entryability/EntryAbility.ets'), /^import .*(pluginengine|core\/plugin\/)/m,
  'startup does not import plugin code eagerly');

console.log('Plugin TTS voice checks passed: runtime merge, stale entries, provider failures, save/export filtering, lazy loading.');
