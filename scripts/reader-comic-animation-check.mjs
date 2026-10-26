// Execute the comic reader's actual state machine with platform doubles.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const compile = source => stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, ''));
const draws = [];
const sandbox = vm.createContext({ console, setTimeout, clearTimeout, setInterval, clearInterval,
  CanvasRenderingContext2D: class { clearRect() {} }, RenderingContextSettings: class {},
  ReaderPageCurlPainter: class { draw(...args) { draws.push(['simulation', ...args]); } },
  ReaderEmulationFlipPainter: class { draw(...args) { draws.push(['3d', ...args]); } },
  ReaderEmulationFlipRegion: { BOTTOM: 2 }, ReaderComicRetryRegistry: class {},
});
vm.runInContext(compile(readEtsModule('core/reader/ReaderPageTurnAnimation.ts')) +
  '\nglobalThis.Animation = ReaderPageTurnAnimation;', sandbox);
vm.runInContext(compile(readEtsModule('core/reader/ReaderComicProcessing.ts')), sandbox);
vm.runInContext(compile(readEtsModule('core/reader/ReaderComicSettings.ets')) +
  '\nglobalThis.Settings = ReaderComicSettings;', sandbox);
const src = readEtsModule('components/reader/ReaderComicPagedView.ets');
const controllerStart = src.indexOf('export class ReaderComicPagedController');
const controller = src.slice(controllerStart, src.indexOf('\n}', controllerStart) + 2);
const start = src.indexOf('export struct ReaderComicPagedView');
const logic = src.slice(start, src.indexOf('  @Builder', start))
  .replace('export struct', 'class').replace(/@(State|Prop|Watch)(\('[^']*'\))?\s*/g, '') + '\n}';
vm.runInContext(compile(controller) + '\n' + stripTypeScriptTypes(logic) +
  '\nglobalThis.View = ReaderComicPagedView;', sandbox);
const A = sandbox.Animation;
assert.deepEqual(Array.from(A.types()), [0, 1, 3, 4, 6, 7]);
assert.deepEqual(Array.from(A.labels()), ['无动画', '平移', '淡入', '叠页', '仿真', '3D仿真']);
assert.equal(sandbox.Settings.parse('{}').pageTurnAnimation, A.SLIDE);
for (const type of A.types()) {
  const settings = new sandbox.Settings();
  settings.pageTurnAnimation = type;
  assert.equal(settings.copy().pageTurnAnimation, type);
  assert.equal(sandbox.Settings.parse(settings.toJson()).pageTurnAnimation, type);
}
for (const value of [NaN, Infinity, -1, 2, 5, 100]) assert.equal(A.normalize(value), A.SLIDE);

function make(type, rtl = false, dual = false) {
  const view = new sandbox.View();
  const animators = [], snapshots = [], changes = [], crosses = [], boundaries = [];
  view.pages = ['a', 'b', 'c', 'd', 'e', 'f'];
  view.viewWidth = 400; view.viewHeight = 800; view.animationType = type;
  view.rightToLeft = rtl; view.dualPage = dual; view.spreadIndex = 1;
  view.canvasReady = true;
  view.getUIContext = () => ({ vp2px: n => n * 2,
    createAnimator: options => {
      const animator = { options, play() {}, cancel() {}, onFrame() {}, onFinish() {} };
      animators.push(animator); return animator;
    },
    getComponentSnapshot: () => ({ get: async id => {
      const bitmap = { id, released: false, release() { this.released = true; return Promise.resolve(); } };
      snapshots.push(bitmap); return bitmap;
    } }),
  });
  view.onPageChanged = index => changes.push(index);
  view.onCrossChapter = dir => crosses.push(dir);
  view.onBoundary = dir => boundaries.push(dir);
  return { view, animators, snapshots, changes, crosses, boundaries };
}
async function launched(view) {
  // Let snapshot capture/layout and async animation setup finish.
  await new Promise(resolve => setTimeout(resolve, view.usesCurl() ? 25 : 0));
}
function complete(harness) {
  const animator = harness.animators.at(-1);
  if (animator) { animator.onFrame(animator.options.end); animator.onFinish(); }
}

// Inspect the first drag frame BEFORE snapshot readiness, not just the settled animator.
for (const type of A.types()) for (const rtl of [false, true]) for (const direction of [-1, 1]) {
  const h = make(type, rtl), v = h.view;
  v.handlePanStart();
  v.handlePanUpdate({ offsetX: v.turnOffset(direction) * 0.1, offsetY: 0 });
  if (type === A.NONE || type === A.FADE || v.usesCurl()) {
    assert.equal(v.slotX(v.spreadIndex), 0, `type ${type}: first drag must not translate current page`);
    if (v.usesCurl()) {
      assert.equal(v.curlReady, false);
      assert.equal(v.slotOpacity(v.spreadIndex), 1);
      assert.equal(v.slotOpacity(v.spreadIndex + direction), 0);
    }
  } else if (type === A.STACK) {
    const stationary = direction > 0 ? v.spreadIndex : v.spreadIndex - 1;
    assert.equal(v.slotX(stationary), 0, 'stack must start as an overlay, not a two-page slide');
  } else {
    assert.equal(v.slotX(v.spreadIndex), v.dragOffset, 'slide should still follow the finger');
  }
  v.aboutToDisappear();
}

for (const type of A.types()) for (const rtl of [false, true]) for (const dual of [false, true]) {
  for (const direction of [-1, 1]) {
    const h = make(type, rtl, dual), v = h.view;
    assert.equal(v.dragDirection(v.turnOffset(direction)), direction);
    v.turn(direction); await launched(v);
    if (type === A.NONE) assert.equal(h.animators.length, 0);
    else {
      const a = h.animators.at(-1);
      a.onFrame(a.options.end / 2);
      v.drawCurl();
      if (v.usesCurl()) {
        const draw = draws.at(-1);
        assert.equal(draw[0], type === A.THREE_D ? '3d' : 'simulation');
        assert.equal(draw[7], rtl ? -direction : direction, 'physical curl direction');
        assert.equal(v.slotX(v.spreadIndex + direction), 0);
      }
      complete(h);
    }
    assert.deepEqual(h.changes, [(1 + direction) * (dual ? 2 : 1)]);
    assert.equal(v.animating, false);
    assert.equal(v.dragOffset, 0);
    assert.equal(v.curlReady, false);
    v.aboutToDisappear();
  }
}

// Fade and stack must keep the target above/below the current page as appropriate.
for (const rtl of [false, true]) {
  const fade = make(A.FADE, rtl).view;
  fade.dragOffset = fade.turnOffset(-1) / 2;
  assert.equal(fade.slotOpacity(0), 0.5);
  assert.equal(fade.slotOpacity(1), 1);
  assert.ok(fade.slotZIndex(0) > fade.slotZIndex(1));
  const stack = make(A.STACK, rtl).view;
  stack.dragOffset = stack.turnOffset(1) / 2;
  assert.equal(stack.slotX(1), 0);
  assert.ok(stack.slotZIndex(2) > stack.slotZIndex(1));
  stack.dragOffset = stack.turnOffset(-1) / 2;
  assert.equal(stack.slotX(0), 0);
  assert.ok(stack.slotZIndex(1) > stack.slotZIndex(0));
}

// Cross-chapter handoff, including no-animation's held target and rollback.
for (const type of A.types()) for (const rtl of [false, true]) {
  const h = make(type, rtl), v = h.view;
  v.spreadIndex = 5; v.nextChapterTitle = 'next'; v.nextChapterPages = ['next1', 'next2'];
  v.turn(1); await launched(v); complete(h);
  assert.deepEqual(h.crosses, [1]);
  assert.equal(v.slotOpacity(6), 1);
  assert.equal(v.animating, true);
  v.animating = false;
  v.settleBack(); await launched(v); complete(h);
  assert.equal(v.animating, false); assert.equal(v.dragOffset, 0);
  assert.deepEqual(h.changes, []);
  v.aboutToDisappear();
}

// A canceled short drag does not commit; stale completion cannot undo a new layout.
for (const type of A.types()) {
  const h = make(type), v = h.view;
  v.dragOffset = -20;
  v.handlePanEnd({ velocityX: 0 }); await launched(v); complete(h);
  assert.deepEqual(h.changes, []); assert.equal(v.dragOffset, 0);
  v.turn(1); await launched(v);
  v.pageIndex = 4; v.onLayoutChanged();
  complete(h);
  assert.equal(v.spreadIndex, 4); assert.equal(v.animating, false);
  v.aboutToDisappear();
}

// Dispose while capture is pending; no late animation or retained bitmap may survive.
for (const type of [A.SIMULATION, A.THREE_D]) {
  const slow = make(type), v = slow.view;
  const context = v.getUIContext();
  let resolveSnapshot;
  const bitmap = { released: false, release() { this.released = true; return Promise.resolve(); } };
  context.getComponentSnapshot = () => ({ get: () => new Promise(resolve => { resolveSnapshot = resolve; }) });
  v.getUIContext = () => context;
  v.handlePanStart();
  v.handlePanUpdate({ offsetX: -120, offsetY: 0 });
  await launched(v);
  assert.equal(typeof resolveSnapshot, 'function');
  assert.equal(v.slotX(v.spreadIndex), 0, 'a slow capture must not expose a slide');
  assert.equal(v.slotOpacity(v.spreadIndex), 1);
  v.handlePanCancel();
  assert.equal(v.dragOffset, 0);
  resolveSnapshot(bitmap);
  await launched(v);
  assert.equal(bitmap.released, true);
  assert.equal(slow.animators.length, 0, 'canceling a pending capture must not start a late return animation');
  assert.equal(v.curlReady, false);
  assert.deepEqual(slow.changes, []);
  v.aboutToDisappear();
}
const pending = make(A.SIMULATION);
pending.view.turn(1); pending.view.aboutToDisappear(); await launched(pending.view);
assert.equal(pending.animators.length, 0); assert.equal(pending.view.curlFront, null);
const captureFailure = make(A.THREE_D);
captureFailure.view.getUIContext = () => ({
  getComponentSnapshot: () => ({ get: async () => { throw new Error('expected snapshot failure'); } }),
  createAnimator: options => {
    const a = { options, play() {}, cancel() {} }; captureFailure.animators.push(a); return a;
  },
});
captureFailure.view.turn(1); await launched(captureFailure.view); complete(captureFailure);
assert.equal(captureFailure.animators.length, 0, 'snapshot failure must not replace curl with a slide');
assert.deepEqual(captureFailure.changes, [2]); captureFailure.view.aboutToDisappear();

// Both menu material branches obey the switch; shared catalog feeds novel and comic settings.
const reader = readEtsModule('pages/ReadBook.ets');
assert.match(reader, /if \(this.readerUseChapterQuickJump\) \{\s*this.readerMaterialChapterBar\(this.isReaderComicModeActive\(\)\)/);
assert.match(reader, /if \(this.readerUseChapterQuickJump && this.isReaderComicModeActive\(\)\) \{\s*this.readerFloatingComicPageRow/);
assert.match(reader, /return \(this.readerUseChapterQuickJump \? 120 : 56\)/);
assert.match(reader, /animationOptions: this.pageTurnAnimationOptions\(true\)/);
assert.match(reader, /ReaderPageTurnAnimation.labels\(horizontal\)/);
assert.match(reader, /animationType: this.readerComicSettings.pageTurnAnimation/);
assert.match(readEtsModule('components/reader/ReaderLayoutElementSettingsPanel.ets'),
  /if \(!this.comicMode\) \{\s*this.toggleRow\('使用快速朗读组件'/);
assert.match(readEtsModule('components/reader/ReaderComicSettingsPanels.ets'),
  /if \(this.paged\(\)\) \{\s*ReaderSettingSelectRow\(\{\s*title: '翻页动画'/);
console.log('Comic animation checks passed: settings, six effects, LTR/RTL, single/dual, cancel, cross-chapter, disposal and layout gates.');
