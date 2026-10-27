// Exercise the window adapter with platform doubles: units, mode changes, theme, fallback and lifecycle.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';

const storage = new Map();
const deviceInfo = { deviceType: '2in1' };
const context = vm.createContext({
  console: { warn() {}, error() {} }, deviceInfo,
  AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
  ConfigurationConstant: { ColorMode: { COLOR_MODE_DARK: 0, COLOR_MODE_LIGHT: 1 } },
  window: { AvoidAreaType: { TYPE_SYSTEM: 0, TYPE_NAVIGATION_INDICATOR: 1, TYPE_SYSTEM_GESTURE: 2 } }
});
const source = readFileSync(new URL('../entry/src/main/ets/utils/SystemBars.ets', import.meta.url), 'utf8');
vm.runInContext(stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '')), context);

function makeWindow() {
  const listeners = new Map();
  return {
    listeners, decorVisible: true, draggable: false, colorMode: -1, topPx: 0,
    rect: { top: 6, right: 8, width: 120, height: 28 }, failGeometry: false, failAreas: false,
    on(type, callback) { assert(!listeners.has(type), `duplicate ${type}`); listeners.set(type, callback); },
    off(type, callback) { if (listeners.get(type) === callback) listeners.delete(type); },
    setWindowDecorVisible(value) { this.decorVisible = value; },
    setWindowTitleMoveEnabled(value) { this.draggable = value; },
    setDecorButtonStyle(style) { this.colorMode = style.colorMode; },
    getTitleButtonRect() { if (this.failGeometry) throw Error('unsupported'); return this.rect; },
    getWindowDecorHeight() { return 40; },
    getUIContext() { return { px2vp: px => px / 2 }; },
    getWindowAvoidAreaIgnoringVisibility(type) {
      if (this.failAreas) throw Error('unavailable');
      return { topRect: { height: type === 0 ? this.topPx : 0 }, bottomRect: { height: type === 1 ? 24 : 0 } };
    },
    emitRect(rect) { this.rect = rect; listeners.get('windowTitleButtonRectChange')(rect); }
  };
}
const main = makeWindow();
context.syncDesktopTitleBar(main, false);
assert.equal(main.decorVisible, false);
assert.equal(main.draggable, true);
assert.equal(main.colorMode, 1);
assert.equal(storage.get('statusBarHeight'), 40, 'native title geometry is already vp');
assert.equal(storage.get('navBarHeight'), 12, 'system avoid areas are px');
context.syncDesktopTitleBar(main, true);
assert.equal(main.colorMode, 0);
assert.equal(main.listeners.size, 2, 'theme changes must not duplicate subscriptions');
main.emitRect({ top: 8, right: 8, width: 180, height: 44 });
assert.equal(storage.get('statusBarHeight'), 52, 'resized controls remain protected');
main.emitRect({ top: 0, right: 0, width: 0, height: 0 });
assert.equal(storage.get('statusBarHeight'), 0, 'full screen releases the title inset');
main.topPx = 100;
main.emitRect({ top: 6, right: 8, width: 120, height: 28 });
assert.equal(storage.get('statusBarHeight'), 50, 'system and title insets overlap instead of adding');
main.failAreas = true;
main.emitRect({ top: 8, right: 8, width: 180, height: 60 });
assert.equal(storage.get('statusBarHeight'), 68, 'failed system queries still protect native controls');
context.releaseSystemBarListeners();
assert.equal(main.listeners.size, 0);
assert.equal(storage.get('desktopTitleBarHeight'), 0);

const unsupported = makeWindow();
unsupported.failGeometry = true;
context.syncDesktopTitleBar(unsupported, false);
assert.equal(unsupported.decorVisible, true, 'failed setup restores the native title');
assert.equal(unsupported.listeners.size, 0);
const recreated = makeWindow();
context.syncDesktopTitleBar(recreated, false);
assert.equal(recreated.listeners.size, 2, 'a recreated stage receives fresh subscriptions');
context.releaseSystemBarListeners();
deviceInfo.deviceType = 'phone';
const phone = makeWindow();
context.syncDesktopTitleBar(phone, false);
assert.equal(phone.decorVisible, true);
assert.equal(phone.listeners.size, 0);
context.syncSystemSafeAreas(phone);
assert.equal(storage.get('statusBarHeight'), 0, 'phone landscape retains a valid zero inset');
context.releaseSystemBarListeners();
console.log('Desktop title bar checks passed.');
