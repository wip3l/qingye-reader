// Exercise page subscriptions and control placement with the platform motion API doubled.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const status = { LEFT_HAND_HELD: 1, RIGHT_HAND_HELD: 2 };
const listeners = new Set();
let supported = true;
let rejected = false;
const deviceInfo = { sdkApiVersion: 20 };
const sandbox = vm.createContext({
  console: { warn() {} }, deviceInfo, canIUse: () => supported, Curve: { Friction: 0 },
  motion: {
    HoldingHandStatus: status,
    on: (_event, callback) => {
      if (rejected) throw new Error('unsupported device');
      listeners.add(callback);
    },
    off: (_event, callback) => {
      assert.equal(typeof callback, 'function', 'only remove this page callback');
      listeners.delete(callback);
    },
  },
  ReaderTtsCapsule: { WIDTH: 184 }, ReaderAutoScrollCapsule: { WIDTH: 184 },
});

function pageClass(file, names) {
  const source = readEtsModule(`pages/${file}.ets`);
  const methods = names.map(name => {
    const start = source.search(new RegExp(`^  (?:private )?${name}\\(`, 'm'));
    assert.notEqual(start, -1, name);
    return source.slice(start, source.indexOf('\n  }', start) + 4);
  });
  return vm.runInContext(stripTypeScriptTypes(`(class { ${methods.join('\n')} })`), sandbox);
}
const Detail = pageClass('SearchBookDetail', ['onSmartGripEnabledChanged', 'startHoldingHandTracking',
  'stopHoldingHandTracking', 'onHoldingHandChanged']);
const Reader = pageClass('ReadBook', ['onSmartGripEnabledChanged', 'startReaderHoldingHandTracking',
  'stopReaderHoldingHandTracking', 'onReaderHoldingHandChanged', 'readerHoldingHandControlLeft',
  'readerAutoScrollCapsuleLeft', 'ttsMiniPlayerLeft', 'readerSessionQuickActionsOnLeft', 'readerTtsQuickActionLeft']);

function fixture(Type, reader) {
  const p = new Type();
  Object.assign(p, {
    smartGripEnabled: true, holdingHandPageVisible: true, readerPageVisible: true,
    readerFormatResolved: true, readerPdfDispatched: false,
    holdingHandSubscribed: false, readerHoldingHandSubscribed: false,
    readButtonOnLeft: false, readerHoldingHandSide: 0,
    readerAutoScrollManuallyPositioned: false, readerTtsManuallyPositioned: false,
    readerAutoScrollPositionX: -1, ttsMiniPlayerPositionX: 36, pageViewWidth: 360,
    getUIContext: () => ({ animateTo: (_options, apply) => apply() }),
    readerFloatingBarEdgeInset: () => 18, clampTtsMiniPlayerPositionX: x => x,
    readerFloatingBarRight: () => 342, readerUsesSideAnchoredControls: () => false,
  });
  p.holdingHandCallback = s => p.onHoldingHandChanged(s);
  p.readerHoldingHandCallback = s => p.onReaderHoldingHandChanged(s);
  const receive = reader ? p.readerHoldingHandCallback : p.holdingHandCallback;
  const side = () => reader ? p.readerHoldingHandSide : Number(p.readButtonOnLeft);
  return { p, receive, side };
}

// Two retained routes must not remove each other's callback when one is disabled.
const detail = fixture(Detail, false);
detail.p.onSmartGripEnabledChanged();
const reader = fixture(Reader, true);
reader.p.onSmartGripEnabledChanged();
assert.equal(listeners.size, 2);
for (const [f, left] of [[detail, 1], [reader, -1]]) {
  f.receive(status.LEFT_HAND_HELD);
  assert.equal(f.side(), left);
  for (const ambiguous of [0, 3, 16]) f.receive(ambiguous);
  assert.equal(f.side(), left, 'ambiguous grip keeps last position');
  f.p.smartGripEnabled = false;
  f.p.onSmartGripEnabledChanged();
  assert.equal(f.side(), 0, 'turning off restores normal placement');
  f.receive(status.LEFT_HAND_HELD);
  assert.equal(f.side(), 0, 'late events cannot move controls after disabling');
}
assert.equal(listeners.size, 0);

// Re-enabling on a retained hidden page cannot subscribe until page-show.
for (const [Type, isReader, visible, start, stop] of [
  [Detail, false, 'holdingHandPageVisible', 'startHoldingHandTracking', 'stopHoldingHandTracking'],
  [Reader, true, 'readerPageVisible', 'startReaderHoldingHandTracking', 'stopReaderHoldingHandTracking'],
]) {
  const f = fixture(Type, isReader);
  f.p[visible] = false;
  f.p.onSmartGripEnabledChanged();
  assert.equal(listeners.size, 0);
  f.p[visible] = true;
  f.p[start](); f.p[start]();
  assert.equal(listeners.size, 1);
  f.receive(status.RIGHT_HAND_HELD);
  assert.equal(f.side(), isReader ? 1 : 0);
  f.p[stop]();
  for (const failure of ['old-api', 'no-capability', 'rejected']) {
    deviceInfo.sdkApiVersion = failure === 'old-api' ? 19 : 20;
    supported = failure !== 'no-capability'; rejected = failure === 'rejected';
    f.p[start]();
    assert.equal(listeners.size, 0, failure);
  }
  deviceInfo.sdkApiVersion = 20; supported = true; rejected = false;
}

const { p } = reader;
p.smartGripEnabled = true;
p.onSmartGripEnabledChanged();
p.onReaderHoldingHandChanged(status.LEFT_HAND_HELD);
assert.equal(p.ttsMiniPlayerLeft(), 18);
assert.equal(p.readerAutoScrollCapsuleLeft(), 18);
assert.equal(p.readerTtsQuickActionLeft(), 18);
p.readerTtsManuallyPositioned = true;
p.readerAutoScrollManuallyPositioned = true;
p.readerAutoScrollPositionX = 52;
p.onReaderHoldingHandChanged(status.RIGHT_HAND_HELD);
assert.equal(p.ttsMiniPlayerLeft(), 36, 'manual TTS position wins over grip');
assert.equal(p.readerAutoScrollCapsuleLeft(), 52, 'manual scroll position wins over grip');
p.smartGripEnabled = false;
p.onSmartGripEnabledChanged();
assert.equal(p.ttsMiniPlayerLeft(), 36);
assert.equal(p.readerAutoScrollCapsuleLeft(), 52);
assert.equal(p.readerTtsQuickActionLeft(), 294);
assert.equal(listeners.size, 0);
console.log('smart grip: subscription lifecycle, fallback and manual placement passed');
