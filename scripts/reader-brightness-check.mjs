import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const source = readEtsModule('utils/ReaderBrightnessSession.ets');
function harness(initial = -1) {
  const disk = new Map();
  const writes = [];
  const errors = [];
  let value = initial;
  let gate = null;
  let failWrite = false;
  const mainWindow = {
    getWindowProperties: () => ({ brightness: value }),
    setWindowBrightness: async next => {
      if (gate) { const wait = gate; gate = null; await wait; }
      if (failWrite) { failWrite = false; throw new Error('window unavailable'); }
      value = next;
      writes.push(next);
    }
  };
  const context = vm.createContext({
    console: { warn: (...args) => errors.push(args) },
    window: { getLastWindow: async () => mainWindow },
    preferences: { getPreferences: async () => ({
      get: async (key, fallback) => disk.get(key) ?? fallback,
      put: async (key, next) => disk.set(key, next), flush: async () => {}
    }) }
  });
  vm.runInContext(stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '')
    .replace('export class', 'class')) + '\nglobalThis.Session = ReaderBrightnessSession;', context);
  const Session = context.Session;
  return { Session, disk, writes, errors, get value() { return value; },
    async drain() { await Session.windowQueue; await Session.saveQueue; },
    holdWrite() { let release; gate = new Promise(r => { release = r; }); return release; },
    fail() { failWrite = true; }
  };
}

{
  const h = harness(0.73), s = new h.Session();
  let shown;
  await s.activate({}, v => shown = v, () => assert.fail('unexpected failure'));
  await h.drain();
  assert.equal(shown, -1);
  assert.equal(h.value, -1);
  s.set(22, false); s.set(47, false); s.set(68, true);
  await h.drain();
  assert.equal(h.value, 0.68);
  assert.equal(h.disk.get('value'), 68);
  assert(!h.writes.includes(0.22), 'superseded drag must not reach native API');
  s.deactivate(); await h.drain();
  assert.equal(h.value, -1, 'leaving the reader hands the window back to system brightness');
  assert(!h.writes.includes(0.73), 'a level read back from window properties must never be restored');
  await s.activate({}, v => shown = v, () => assert.fail()); await h.drain();
  assert.equal(shown, 68);
  s.set(-1, true); await h.drain();
  assert.equal(h.value, -1);
  assert.equal(h.disk.get('value'), -1);
  s.deactivate(); await h.drain();
}

{
  const h = harness(), old = new h.Session(), next = new h.Session();
  await old.activate({}, () => {}, () => assert.fail()); await h.drain();
  old.set(34, true); await h.drain();
  await next.activate({}, () => {}, () => assert.fail()); await h.drain();
  next.set(81, true); await h.drain();
  old.deactivate(); await h.drain();
  assert.equal(h.value, 0.81, 'old reader cannot reset replacement reader');
  assert.equal(h.disk.get('value'), 81, 'old reader cannot overwrite replacement preference');
  next.deactivate(); await h.drain();
  assert.equal(h.value, -1);
  let restored;
  await old.activate({}, v => restored = v, () => assert.fail()); await h.drain();
  assert.equal(restored, 81, 'returning reader reloads current device preference');
  old.deactivate(); await h.drain();
}

{
  const h = harness(0.6), s = new h.Session();
  await s.activate({}, () => {}, () => assert.fail()); await h.drain();
  const release = h.holdWrite();
  s.set(25, false);
  for (let i = 0; i < 8; ++i) await Promise.resolve();
  s.deactivate();
  release(); await h.drain();
  assert.equal(h.value, -1, 'in-flight native write finishes before restoration');
  assert(h.writes.includes(0.25), 'in-flight native write is not dropped');
  assert.equal(h.disk.get('value'), 25, 'leaving during drag saves latest value');
  const pending = s.activate({}, () => assert.fail('hidden reader published ready'), () => assert.fail());
  s.deactivate(); await pending; await h.drain();
  assert.equal(h.value, -1, 'late preference load cannot change a hidden window');
}

{
  const h = harness(), s = new h.Session();
  let failures = 0;
  await s.activate({}, () => {}, () => failures++); await h.drain();
  h.fail(); s.set(20, true); await h.drain();
  assert.equal(failures, 1);
  s.set(60, true); await h.drain();
  assert.equal(h.value, 0.6, 'queue recovers after rejected native call');
  s.deactivate(); await h.drain();
  assert.equal(h.value, -1);
  assert.equal(h.Session.normalize(NaN), -1);
  assert.equal(h.Session.normalize(0), 1);
  assert.equal(h.Session.normalize(120), 100);
}
{
  const h = harness(0.72), old = new h.Session(), next = new h.Session();
  await old.activate({}, () => {}, () => assert.fail()); await h.drain();
  old.set(30, false); await h.drain();
  await next.activate({}, () => {}, () => assert.fail()); await h.drain();
  next.set(85, true); await h.drain();
  old.deactivate(); await h.drain();
  assert.equal(h.disk.get('value'), 85, 'late unsaved drag from replaced page must not overwrite newer choice');
  h.fail(); next.deactivate(); await h.drain();
  const returned = new h.Session();
  await returned.activate({}, () => {}, () => assert.fail()); await h.drain();
  returned.deactivate(); await h.drain();
  assert.equal(h.value, -1, 'the next release still hands the window back to the system after a failed restore');
}
console.log('Reader brightness: persistence, ownership, drag coalescing, restoration and error recovery passed.');
