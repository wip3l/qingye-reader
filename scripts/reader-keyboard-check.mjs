import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

// Native HarmonyOS key codes (not DOM KeyboardEvent keyCode values).
const KeyCode = {};
function keys(start, names) {
  names.split(' ').forEach((name, index) => { KeyCode[`KEYCODE_${name}`] = start + index; });
}
keys(2000, '0 1 2 3 4 5 6 7 8 9 STAR POUND DPAD_UP DPAD_DOWN DPAD_LEFT DPAD_RIGHT DPAD_CENTER A B C D E F G H I J K L M N O P Q R S T U V W X Y Z COMMA PERIOD ALT_LEFT ALT_RIGHT SHIFT_LEFT SHIFT_RIGHT TAB SPACE SYM EXPLORER ENVELOPE ENTER DEL GRAVE MINUS EQUALS LEFT_BRACKET RIGHT_BRACKET BACKSLASH SEMICOLON APOSTROPHE SLASH AT PLUS MENU PAGE_UP PAGE_DOWN ESCAPE FORWARD_DEL CTRL_LEFT CTRL_RIGHT CAPS_LOCK SCROLL_LOCK META_LEFT META_RIGHT FUNCTION SYSRQ BREAK MOVE_HOME MOVE_END INSERT FORWARD MEDIA_PLAY MEDIA_PAUSE MEDIA_CLOSE MEDIA_EJECT MEDIA_RECORD F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12 NUM_LOCK NUMPAD_0 NUMPAD_1 NUMPAD_2 NUMPAD_3 NUMPAD_4 NUMPAD_5 NUMPAD_6 NUMPAD_7 NUMPAD_8 NUMPAD_9 NUMPAD_DIVIDE NUMPAD_MULTIPLY NUMPAD_SUBTRACT NUMPAD_ADD NUMPAD_DOT NUMPAD_COMMA NUMPAD_ENTER NUMPAD_EQUALS');
KeyCode.KEYCODE_ESCAPE = 2070;
const compile = text => stripTypeScriptTypes(text.replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'strip' });
const stores = new Map();
let failWrite = false;
const context = vm.createContext({ console, KeyCode, KeyType: { Down: 0, Up: 1 },
  preferences: { getPreferences: async (_context, name) => {
    if (!stores.has(name)) stores.set(name, new Map());
    const disk = stores.get(name);
    return { get: async (key, fallback) => disk.has(key) ? disk.get(key) : fallback,
      put: async (key, value) => { if (failWrite) throw new Error('disk full'); disk.set(key, value); },
      flush: async () => {} };
  } }
});
vm.runInContext(compile(readEtsModule('core/reader/ReaderKeyboard.ets')) + '\n' +
  compile(readEtsModule('utils/ReaderKeyboardSettingsStore.ets')) +
  '\nglobalThis.api = { ReaderKeyboard, ReaderKeyboardSettings, ReaderKeyboardSettingsStore };', context);
const { ReaderKeyboard: Keyboard, ReaderKeyboardSettings: Settings, ReaderKeyboardSettingsStore: Store } = context.api;
assert.equal(new Settings().previous, 2068);
assert.equal(new Settings().next, 2069);
assert.equal(Keyboard.isBindable(33), false, 'DOM PageUp is not native PageUp');
for (const code of [0, 1, 2, 16, 17, 18, 2049, 2070, 2072, 2076, -1, NaN, 2068.5]) {
  assert.equal(Keyboard.isBindable(code), false, `reserved key ${code}`);
}
for (const code of [2012, 2015, 2017, 2042, 2050, 2068, 2069, 2101, 2119]) {
  assert.equal(Keyboard.isBindable(code), true);
  assert.ok(!Keyboard.label(code).startsWith('按键 '));
}
const corrupt = Keyboard.normalize({ enabled: 'false', previous: 18, next: 2068 });
assert.equal(corrupt.enabled, false);
assert.equal(corrupt.previous, 2068);
assert.equal(corrupt.next, 2069, 'collision falls back to a usable pair');

const source = readEtsModule('pages/ReadBook.ets');
const handler = source.slice(source.indexOf('  handleReaderKeyboardEvent('), source.indexOf('  presentReaderKeyboardCapture('));
vm.runInContext(compile(`class ReaderKeyboardHarness { ${handler} } globalThis.Handler = ReaderKeyboardHarness;`), context);
const page = new context.Handler();
Object.assign(page, { readerKeyboardSettings: new Settings(), readerKeyboard: new Keyboard(),
  readerPageVisible: true, readerKeyboardSettingsReady: true, chapters: [{}], overlay: false, loading: false,
  readerKeyboardHasOverlay() { return this.overlay; }, shouldBlockReaderInteraction() { return this.loading; },
  turns: [], refreshReaderScreenTimeout() {},
  turnNext() { this.turns.push(1); return Promise.resolve(); },
  turnPrev() { this.turns.push(-1); return Promise.resolve(); } });
const event = (keyCode, type = 0, modifiers = [], deviceId = 1) => ({ keyCode, type, deviceId, metaKey: 0,
  getModifierKeyState: keys => keys.some(key => modifiers.includes(key)) });
const send = (...args) => page.handleReaderKeyboardEvent(event(...args));
assert.equal(send(2069), false, 'keyboard paging is disabled by default');
send(2069, 1);
assert.deepEqual(page.turns, []);
page.readerKeyboardSettings.enabled = true;
assert.equal(send(2069), true);
send(2069); send(2069);
assert.deepEqual(page.turns, [1], 'long hold must not turn multiple pages');
assert.equal(send(2069, 1), true);
send(2068); send(2068, 1);
assert.deepEqual(page.turns, [1, -1]);
assert.equal(send(2069, 0, ['Ctrl']), false);
assert.equal(send(2069, 1, ['Ctrl']), false, 'do not swallow shortcut release');
page.overlay = true;
assert.equal(send(2069), false);
page.overlay = false;
send(2069);
assert.equal(page.turns.length, 2, 'held key across panel close must not turn');
send(2069, 1);
page.loading = true; send(2069); page.loading = false; send(2069); send(2069, 1);
assert.equal(page.turns.length, 2, 'no stale loading-time key replay');
page.readerKeyboardSettings.enabled = false;
assert.equal(send(2069), false); send(2069, 1);
page.readerKeyboardSettings.enabled = true;
page.readerKeyboardSettings.next = 2050;
assert.equal(send(2069), false); send(2069, 1);
send(2050); send(2050, 1);
assert.deepEqual(page.turns, [1, -1, 1]);
send(2050, 0, [], 2); send(2050, 0, [], 3);
assert.equal(page.turns.length, 5, 'devices have independent held state');
page.readerKeyboard.reset(); send(2050, 0, [], 2); send(2050, 1, [], 2);
assert.equal(page.turns.length, 6);

// Execute the real dialog event handling, without an ArkUI renderer.
const dialogSource = readEtsModule('components/reader/ReaderKeyboardCaptureDialog.ets');
const capture = dialogSource.slice(dialogSource.indexOf('  private handleKey('), dialogSource.indexOf('  private retry('));
vm.runInContext(compile(`class CaptureHarness { ${capture} } globalThis.Capture = CaptureHarness;`), context);
const dialog = new context.Capture();
Object.assign(dialog, { held: new Keyboard(), candidate: -1, released: false, saving: false, otherCode: 2069,
  closed: false, onClose() { this.closed = true; } });
dialog.handleKey(event(2069)); dialog.handleKey(event(2069, 1));
assert.equal(dialog.candidate, -1, 'duplicate direction is rejected');
dialog.handleKey(event(2017, 0, ['Alt'])); dialog.handleKey(event(2017, 1));
assert.equal(dialog.candidate, -1);
dialog.handleKey(event(2017)); dialog.handleKey(event(2017));
assert.equal(dialog.candidate, 2017); assert.equal(dialog.released, false);
assert.equal(dialog.handleKey(event(2017, 1)), true, 'recorded key release is consumed');
assert.equal(dialog.released, true);
assert.equal(dialog.handleKey(event(2054)), false, 'Enter can confirm after capture');
dialog.handleKey(event(2070)); assert.equal(dialog.closed, true);

const initial = await Store.load({});
assert.equal(initial.enabled, false);
const first = new Settings(); first.previous = 2014; first.next = 2015;
const second = new Settings(); second.enabled = false; second.previous = 2017; second.next = 2050;
await Promise.all([Store.save({}, first), Store.save({}, second)]);
second.next = 2069;
const loaded = await Store.load({});
assert.equal(loaded.enabled, false); assert.equal(loaded.previous, 2017); assert.equal(loaded.next, 2050);
assert.deepEqual([...stores.keys()], ['reader_keyboard'], 'not stored in theme or cloud preferences');
failWrite = true;
await assert.rejects(Store.save({}, new Settings()), /disk full/);
failWrite = false;
await Store.save({}, new Settings());
assert.equal((await Store.load({})).next, 2069, 'a failed save must not poison later writes');
const enabled = new Settings(); enabled.enabled = true;
await Store.save({}, enabled);
assert.equal((await Store.load({})).enabled, true, 'preserve the user\'s saved opt-in');
console.log('Reader keyboard checks passed: defaults, mappings, repeat filtering, overlay/shortcut guards, capture and persistence.');
