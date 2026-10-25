// Run with: node scripts/reader-tts-error-recovery-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const read = path => fs.readFileSync(new URL(path, import.meta.url), 'utf8');
const page = read('../entry/src/main/ets/pages/ReadBook.ets');
const panel = read('../entry/src/main/ets/components/ReaderTtsPlayerPanel.ets');
const session = read('../entry/src/main/ets/utils/ReaderTtsFloatingSession.ets');
function method(source, name) {
  const match = new RegExp(`^  (?:async )?${name}\\(`, 'm').exec(source);
  assert.ok(match, name);
  return source.slice(match.index, source.indexOf('\n  }', match.index) + 4);
}
const storage = new Map();
const toasts = [];
const context = vm.createContext({
  AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
  readStatsTracker: { setTtsActive() {} },
  HdsFeedback: { showToast: message => toasts.push(message) },
  console
});
vm.runInContext(stripTypeScriptTypes(session.replace(/^import .*;\r?\n/gm, '')
  .replace('export class', 'class')), context);
const shared = vm.runInContext('ReaderTtsFloatingSession', context);
const host = vm.runInContext(stripTypeScriptTypes(`({${[
  'finishTtsReading', 'stopTtsReading', 'toggleTtsReading', 'applyCustomTtsVoice', 'applyTtsVoice'
].map(name => method(page, name)).join(',')}})`), context);
let stops = 0;
let retries = 0;
let backgroundStops = 0;
let selected = -1;
for (const name of ['cancelManualPageTurnTtsResume', 'flushTtsReadPosition', 'clearTtsSleepTimer',
  'releaseBackgroundProgressWriterAfterTtsStop', 'updateVolumeKeySubscription',
  'invalidateTtsFocusSession', 'clearTtsHighlight', 'pauseReaderAutoScroll', 'saveTtsSettings']) {
  host[name] = () => {};
}
Object.assign(host, {
  ttsFloatingSessionOwnerId: 'reader', ttsReadToken: 7, ttsPageTurnSerial: 0,
  readerPageVisible: true, isTtsSpeaking: true, isTtsPaused: false, ttsAutoContinue: true,
  ttsReader: { stop: () => stops++, isSpeaking: () => false, isPaused: () => false },
  ttsMediaSession: () => ({ stopBackgroundRunning: () => backgroundStops++ }),
  isReaderComicModeActive: () => false,
  updateTtsFloatingSession: () => shared.update('reader', 'Book', 'Chapter', host.isTtsPaused),
  startTtsReadingFromCurrentPosition: async () => { retries++; },
});
context.TtsVoiceCatalog = { customVoiceKey: voice => `custom_${voice.id}`, voiceKey: voice => voice.id };
function attach(owner = 'reader') {
  shared.attach(owner, 'book', 'Book', 'Chapter', false,
    () => host.toggleTtsReading(), () => host.isTtsPaused, () => host.stopTtsReading());
  shared.configureTtsVoices(owner, ['Broken custom', 'Working custom', 'System'], 0, index => {
    selected = index;
    if (index === 1) host.applyCustomTtsVoice({ id: 'working' }, true);
    if (index === 2) host.applyTtsVoice({ id: 'system', available: true }, true);
  });
}
const errorCallback = page.match(/onError: \(message: string\) => \{([\s\S]*?)\n        \},\r?\n        onChunkStart:/);
assert.ok(errorCallback);
context.host = host;
const onError = vm.runInContext(stripTypeScriptTypes(
  `(function () { const token = this.ttsReadToken; return (message: string) => {${errorCallback[1]}\n}; }).call(host)`), context);
const picker = vm.runInContext(stripTypeScriptTypes(`({${method(panel, 'hasTtsVoices')}})`), context);
attach();
onError('Custom voice request failed');
picker.globalTtsVoiceRevision = storage.get('globalTtsVoiceRevision');
assert.equal(picker.hasTtsVoices(), true, 'error must not remove the voice selector');
assert.equal(shared.isActive(), true, 'floating player must remain accessible');
assert.equal(storage.get('globalTtsPaused'), true, 'player must offer play after failure');
assert.equal(host.isTtsSpeaking, false);
assert.equal(host.ttsAutoContinue, false);
assert.equal(host.ttsReadToken, 8, 'invalidate failed start and its late callbacks');
assert.equal(stops, 1);
assert.equal(backgroundStops, 1, 'failed playback must release background audio');
assert.deepEqual(toasts, ['Custom voice request failed']);
for (const index of [1, 2]) {
  shared.selectTtsVoice(index);
  assert.equal(selected, index, 'voice switch callback must survive failure');
  assert.equal(shared.ttsVoiceIndex(), index);
}
assert.equal(host.ttsPerson, 'system');
assert.equal(host.ttsCustomVoiceId, '');
await shared.toggle();
assert.equal(retries, 1, 'play must start a new request instead of resuming failed audio');
onError('Late failure');
assert.equal(stops, 1, 'stale failure must not stop a retry');
assert.equal(toasts.length, 1);
host.finishTtsReading();
assert.equal(shared.isActive(), false, 'normal completion still clears controls');
assert.equal(shared.ttsVoiceTitles().length, 0);
attach();
host.finishTtsReading(true);
shared.stop();
assert.equal(shared.isActive(), false, 'explicit stop still clears a failed session');
attach('new-reader');
host.finishTtsReading(true);
assert.equal(shared.currentOwnerId(), 'new-reader', 'old reader must not replace a newer session');
assert.equal(storage.get('globalTtsPaused'), false);
console.log('TTS error recovery checks passed: selector, voice switching, retry, stale callbacks and cleanup.');
