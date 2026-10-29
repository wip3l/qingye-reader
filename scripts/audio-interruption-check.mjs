// Run the production players against asynchronous platform doubles.
// No phone/WeChat focus policy is simulated here: these tests verify delivery of each platform hint.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const enumValues = names => Object.fromEntries(names.map(name => [name, name]));
const audio = {
  InterruptHint: enumValues(['INTERRUPT_HINT_PAUSE', 'INTERRUPT_HINT_STOP', 'INTERRUPT_HINT_RESUME',
    'INTERRUPT_HINT_DUCK', 'INTERRUPT_HINT_UNDUCK']),
  InterruptForceType: enumValues(['INTERRUPT_SHARE', 'INTERRUPT_FORCE']),
  AudioState: enumValues(['STATE_RUNNING', 'STATE_PAUSED', 'STATE_STOPPED', 'STATE_RELEASED']),
  AudioSamplingRate: { SAMPLE_RATE_16000: 16000 },
  AudioDataCallbackResult: { INVALID: -1, VALID: 0 },
};
const sandbox = vm.createContext({
  audio, console: { info() {}, warn() {} }, deviceInfo: { sdkApiVersion: 26 },
  TtsAudioSession: { acquire: async () => {}, release() {} },
  setTimeout: () => 1, clearTimeout() {}, setInterval: () => 1, clearInterval() {},
});
for (const name of ['RemoteAudioPlayback', 'TtsAvAudioPlayer', 'TtsPcmAudioPlayer']) {
  const source = readEtsModule(`utils/${name}.ets`).replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '');
  vm.runInContext(stripTypeScriptTypes(source) + `\nglobalThis.${name} = ${name};`, sandbox);
}
const tick = async () => { for (let i = 0; i < 25; i++) await Promise.resolve(); };
function deferred() {
  let resolve;
  const promise = new Promise(r => { resolve = r; });
  return { promise, resolve };
}
function fixture(kind) {
  const pcm = kind === 'TtsPcmAudioPlayer';
  const player = new sandbox[kind]();
  const running = pcm ? 'STATE_RUNNING' : 'playing';
  const paused = pcm ? 'STATE_PAUSED' : 'paused';
  const stopped = pcm ? 'STATE_STOPPED' : 'stopped';
  const calls = [];
  const native = {
    state: running,
    pauseGate: null, startGate: null, volumeGate: null,
    async pause() {
      calls.push('pause');
      if (this.pauseGate) await this.pauseGate.promise;
      this.state = paused;
    },
    async play() {
      calls.push('play');
      if (this.startGate) await this.startGate.promise;
      this.state = running;
    },
    async start() { await this.play(); },
    setVolume() { return this.volumeGate?.promise ?? Promise.resolve(); },
    async stop() { this.state = stopped; },
    async release() { this.state = pcm ? 'STATE_RELEASED' : 'released'; },
    off() {},
  };
  player[pcm ? 'renderer' : 'player'] = native;
  if (!pcm) player.state = 'playing';
  function hint(type, force = 'SHARE') {
    if (force === 'FORCE' && ['PAUSE', 'STOP'].includes(type)) {
      native.state = type === 'STOP' ? stopped : paused;
    }
    const event = { hintType: `INTERRUPT_HINT_${type}`, forceType: `INTERRUPT_${force}` };
    if (pcm) player.handleAudioInterrupt(native, event);
    else player.handleAudioInterrupt(native, player.playGeneration ?? player.generation, event);
  }
  return { player, native, calls, hint, running, paused };
}

let checks = 0;
for (const kind of ['RemoteAudioPlayback', 'TtsAvAudioPlayer', 'TtsPcmAudioPlayer']) {
  for (const force of ['SHARE', 'FORCE']) {
    const f = fixture(kind);
    f.hint('PAUSE', force);
    await tick();
    assert.equal(f.native.state, f.paused, `${kind}/${force}: interrupted playback pauses`);
    f.hint('RESUME');
    await tick();
    assert.equal(f.native.state, f.running, `${kind}/${force}: resumes after focus returns`);
    assert.equal(f.calls.filter(c => c === 'play').length, 1);
    f.hint('RESUME');
    await tick();
    assert.equal(f.calls.filter(c => c === 'play').length, 1, 'duplicate RESUME does not restart audio');
    checks++;
  }
  {
    const f = fixture(kind);
    f.native.pauseGate = deferred();
    f.hint('PAUSE');
    f.hint('RESUME');
    await tick();
    assert.equal(f.calls.includes('play'), false, 'resume waits for in-flight pause');
    f.native.pauseGate.resolve();
    await tick();
    assert.equal(f.native.state, f.running, `${kind}: fast end of call must not leave player paused`);
    checks++;
  }
  {
    const f = fixture(kind);
    f.hint('PAUSE', 'FORCE');
    f.hint('RESUME');
    await f.player.pause();
    await tick();
    assert.equal(f.calls.includes('play'), false, `${kind}: user pause cancels queued auto-resume`);
    checks++;
  }
  {
    const f = fixture(kind);
    await f.player.pause();
    f.hint('PAUSE', 'FORCE');
    f.hint('RESUME');
    await tick();
    assert.equal(f.calls.includes('play'), false, `${kind}: originally paused playback stays paused`);
    checks++;
  }
  {
    const f = fixture(kind);
    f.native.pauseGate = deferred();
    f.hint('PAUSE');
    f.hint('RESUME');
    await f.player.stop();
    f.native.pauseGate.resolve();
    await tick();
    assert.equal(f.calls.includes('play'), false, `${kind}: stopped session cannot be resurrected`);
    checks++;
  }
  for (const force of ['SHARE', 'FORCE']) {
    const f = fixture(kind);
    f.hint('PAUSE');
    await tick();
    f.hint('RESUME');
    f.hint('STOP', force);
    await tick();
    f.hint('RESUME');
    await tick();
    assert.equal(f.calls.includes('play'), false, `${kind}: STOP cancels auto-resume permanently`);
    checks++;
  }
  {
    const f = fixture(kind);
    f.native.startGate = deferred();
    f.hint('PAUSE', 'FORCE');
    f.hint('RESUME');
    await tick();
    assert.ok(f.calls.includes('play'));
    await f.player.pause();
    f.native.startGate.resolve();
    await tick();
    assert.equal(f.native.state, f.paused, `${kind}: pause during pending start wins`);
    checks++;
  }
  {
    const f = fixture(kind);
    f.native.startGate = deferred();
    f.hint('PAUSE', 'FORCE');
    f.hint('RESUME');
    await tick();
    f.hint('RESUME');
    await tick();
    assert.equal(f.calls.filter(c => c === 'play').length, 1,
      `${kind}: duplicate notification during pending start must not start twice`);
    f.native.startGate.resolve();
    await tick();
    assert.equal(f.native.state, f.running);
    checks++;
  }
  {
    const f = fixture(kind);
    f.hint('STOP');
    await tick();
    await f.player.resume();
    assert.equal(f.native.state, f.running, `${kind}: user can resume after advisory STOP`);
    checks++;
  }
  {
    const f = fixture(kind);
    f.native.pauseGate = deferred();
    f.hint('PAUSE');
    f.hint('RESUME');
    f.hint('PAUSE');
    f.native.pauseGate.resolve();
    await tick();
    assert.equal(f.calls.includes('play'), false, `${kind}: a new interruption invalidates old RESUME`);
    f.hint('RESUME');
    await tick();
    assert.equal(f.native.state, f.running);
    checks++;
  }
  {
    const f = fixture(kind);
    f.hint('RESUME');
    await tick();
    assert.equal(f.calls.length, 0, `${kind}: unsolicited RESUME is ignored`);
    checks++;
  }
}
{
  const f = fixture('TtsPcmAudioPlayer');
  f.player.pendingWrites = [{ data: new Uint8Array([1, 2, 3, 4]), offset: 0, generation: 0, resolve() {} }];
  f.player.pendingWriteBytes = 4;
  f.hint('PAUSE');
  const output = new ArrayBuffer(4);
  assert.equal(f.player.handleRendererWriteData(output), audio.AudioDataCallbackResult.INVALID);
  assert.equal(f.player.pendingWriteBytes, 4, 'interrupted write callback must not consume unheard text');
  f.hint('RESUME');
  await tick();
  f.player.handleRendererWriteData(output);
  assert.deepEqual([...new Uint8Array(output)], [1, 2, 3, 4], 'resume starts with queued PCM intact');
  checks++;
}
console.log(`Audio interruption: ${checks} playback, cancellation and async-race scenarios passed.`);
