import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

// Run the production orchestration with controlled network and audio completion.
// No credentials, devices or external requests are used.
const source = fs.readFileSync(new URL('../entry/src/main/ets/pages/MimoSettings.ets', import.meta.url), 'utf8');
const methods = source.slice(source.indexOf('  private async test('), source.indexOf('  private startReplacing('));
const stopAndReset = source.slice(source.indexOf('  private stopTest('), source.indexOf('  private syncSettings('));
const logs = [];
let storedAnalysis;
let savedKey;
const Page = vm.runInNewContext(stripTypeScriptTypes(`class Page { ${methods} ${stopAndReset} }; Page`), {
  ReaderTtsFloatingSession: { stop() {} },
  MimoStore: {
    key: async () => 'test-key',
    setAnalysisAvailable: value => { storedAnalysis = value; },
    saveKey: async (key, analysis) => { savedKey = { key, analysis }; },
  },
  MimoPolicy: { split: text => [{ text }] },
  HdsFeedback: { showToast() {} },
  console: { info: message => logs.push(message) },
});
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const tick = () => new Promise(resolve => setImmediate(resolve));
function setup() {
  const speech = deferred(), analysis = deferred(), drained = deferred();
  let receive, playbackStart, speechRetry, analysisRetry;
  const calls = [];
  const page = new Page();
  Object.assign(page, {
    serial: 0, busy: false, consent: true, voice: '白桦', multi: true,
    tested: false, testedKey: '', ttsCheck: 'idle', analysisCheck: 'idle',
    pendingKey: () => 'test-key', syncSettings() {}, clearPendingKey() {},
    client: {
      synthesize(key, text, voice, style, callback, retry) {
        calls.push('speech'); receive = callback; speechRetry = retry; return speech.promise;
      },
      analyze(key, units, roles, context, retry) {
        calls.push('analysis'); analysisRetry = retry; return analysis.promise;
      },
      stop() {},
    },
    player: {
      writeSegment(pcm, rate, callback) { playbackStart = callback; return Promise.resolve(); },
      write() { return Promise.resolve(); },
      drain() { calls.push('drain'); return drained.promise; },
      stop() { calls.push('stop'); },
    },
  });
  return {
    page, calls, speech, analysis, drained,
    receive: () => receive(new ArrayBuffer(4)), startPlayback: () => playbackStart(),
    retrySpeech: delay => speechRetry(delay), retryAnalysis: delay => analysisRetry(delay),
  };
}

{
  const s = setup();
  const task = s.page.test();
  assert.deepEqual(s.calls, ['speech', 'analysis'], 'both probes start before either response');
  assert.equal(s.page.tested, false);
  s.retrySpeech(2000); s.retryAnalysis(1000);
  assert.match(s.page.ttsStatus, /限流.*2 秒/);
  assert.match(s.page.analysisStatus, /限流.*1 秒/);
  await s.receive();
  assert.match(s.page.ttsStatus, /准备播放/);
  s.startPlayback();
  assert.equal(s.page.ttsStatus, '正在播放试听…');
  s.analysis.resolve(); await tick();
  assert.equal(s.page.analysisCheck, 'ok', 'analysis can finish while preview is playing');
  assert.equal(s.page.busy, true);
  await s.page.save();
  assert.equal(savedKey, undefined, 'saving is blocked until both probes and playback settle');
  s.speech.resolve(); await tick();
  assert.equal(s.page.ttsCheck, 'running', 'stream completion is distinct from audible completion');
  s.drained.resolve(); await task;
  assert.equal(s.page.ttsCheck, 'ok');
  assert.equal(s.page.tested, true);
  assert.equal(s.page.busy, false);
  await s.page.save();
  assert.deepEqual(savedKey, { key: 'test-key', analysis: true });
}
{
  const s = setup();
  const task = s.page.test();
  s.analysis.reject(new Error('analysis unavailable'));
  await s.receive(); s.startPlayback(); s.speech.resolve(); s.drained.resolve();
  await task;
  assert.equal(s.page.analysisCheck, 'fail');
  assert.equal(s.page.tested, true, 'speech success permits the single-voice fallback');
  assert.match(s.page.notice, /单音色/);
  await s.page.save();
  assert.equal(savedKey.analysis, false);
}
{
  const s = setup();
  const task = s.page.test();
  s.speech.reject(new Error('speech unavailable')); s.analysis.resolve();
  await task;
  assert.equal(s.page.ttsCheck, 'fail');
  assert.equal(s.page.analysisCheck, 'ok', 'speech failure does not overwrite the independent analysis result');
  assert.equal(s.page.tested, false, 'analysis alone cannot enable reading');
  assert.equal(s.page.busy, false);
}
{
  storedAnalysis = undefined;
  const s = setup();
  const task = s.page.test(true);
  await tick();
  s.analysis.reject(new Error('analysis unavailable'));
  s.speech.resolve(); s.drained.resolve(); await task;
  assert.equal(storedAnalysis, false, 'retesting a saved key updates its available modes');
  assert.match(s.page.notice, /已改为单音色/);
}
{
  const s = setup();
  const task = s.page.test();
  await s.receive();
  s.page.stopTest();
  // Model a subsequent test while old callbacks are still settling.
  s.page.busy = true; s.page.ttsStatus = 'new speech'; s.page.analysisStatus = 'new analysis';
  s.startPlayback(); s.retrySpeech(1000); s.retryAnalysis(1000);
  s.speech.resolve(); s.analysis.reject(new Error('late failure'));
  await task;
  assert.equal(s.page.ttsStatus, 'new speech');
  assert.equal(s.page.analysisStatus, 'new analysis');
  assert.equal(s.page.busy, true, 'old finally must not stop a new test');
  assert.ok(!s.calls.includes('drain'), 'cancelled speech must not drain the next renderer');
}
assert.ok(!logs.some(message => message.includes('test-key')), 'timing logs must not contain credentials');
assert.match(source, /checkLine\(\$\$: MimoCheckLineParams\)/);
assert.match(source, /this\.checkLine\(\{ title: '语音合成', check: this\.ttsCheck, status: this\.ttsStatus \}\)/);
assert.match(source, /this\.checkLine\(\{ title: '角色分析', check: this\.analysisCheck, status: this\.analysisStatus \}\)/);
console.log('MiMo settings checks passed: parallel probes, playback stages, retries, save gating, fallback and stale callback isolation.');
