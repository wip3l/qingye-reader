import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';
const source = readEtsModule('pages/ReadBook.ets');
function method(name) {
  const start = source.search(new RegExp(`^  (?:async )?${name}\\(`, 'm'));
  assert.notEqual(start, -1, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
const copied = [], toasts = [];
let fail = false, complete;
const deviceInfo = { deviceType: '2in1' };
const context = vm.createContext({ deviceInfo, px2vp: value => value / 2, vp2px: value => value * 2,
  console: { warn() {} },
  HdsFeedback: { showToast: value => toasts.push(value) },
  pasteboard: { MIMETYPE_TEXT_PLAIN: 'text/plain', createData: (_type, value) => value,
    getSystemPasteboard: () => ({ setData: async value => {
      if (fail) throw new Error('clipboard unavailable');
      copied.push(value);
      if (complete) await complete;
    } }) } });
vm.runInContext(stripTypeScriptTypes(`class Reader {
${['isReaderDesktopSelection', 'readerDesktopSelectedText', 'copyReaderDesktopSelection',
  'readerV2DisplayOffsetForPageSelection', 'onReaderV2NativeSelectionChanged',
  'readerSelectionEndpointGeometry', 'positionReaderSelectionMenu',
  'readerContinuousV2SelectionRects', 'readerContinuousV2Locate',
  'refreshReaderSelectionHandles', 'beginReaderSelectionHandleDrag',
  'updateReaderSelectionHandleDrag'].map(method).join('\n')}
} globalThis.Reader = Reader;`), context);
const reader = new context.Reader();
let clears = 0;
Object.assign(reader, { readerDesktopSelectionPage: { selectionText: '甲乙丙丁' },
  readerSelectionStartChunk: -1, readerSelectionEndChunk: -1,
  readerDesktopSelectionStart: 1, readerDesktopSelectionEnd: 3, readerTextSelectionSerial: 1,
  scheduleReaderTextSelectionClear: () => clears++ });
assert.equal(reader.isReaderDesktopSelection(), true);
deviceInfo.deviceType = 'pc'; assert.equal(reader.isReaderDesktopSelection(), true);
deviceInfo.deviceType = 'phone'; assert.equal(reader.isReaderDesktopSelection(), false);
assert.equal(reader.readerDesktopSelectedText(), '乙丙');
await reader.copyReaderDesktopSelection();
assert.deepEqual(copied, ['乙丙']); assert.equal(clears, 1);
fail = true;
await reader.copyReaderDesktopSelection();
assert.equal(clears, 1, 'failure preserves the selection for retry');
assert.equal(toasts.at(-1), '复制失败，请重试');
fail = false;
let finish;
complete = new Promise(resolve => { finish = resolve; });
const pending = reader.copyReaderDesktopSelection();
reader.readerTextSelectionSerial++;
finish(); await pending;
assert.equal(clears, 1, 'late copy cannot clear a newer selection');
reader.readerDesktopSelectionPage = null;
await reader.copyReaderDesktopSelection();
assert.equal(copied.length, 2, 'empty selection never overwrites the clipboard');
console.log('Reader selection copy: device policy, exact range, failure, stale completion and empty selection passed.');

// Exercise the same handle methods used by paged and continuous hosts with a window offset and 2x density.
deviceInfo.deviceType = '2in1';
const fragment = (start, end, top) => ({ selectionPageStart: start, selectionPageEnd: end,
  displayStart: start, displayEnd: end, paragraphX: 10, paragraphY: top,
  clipRect: { left: 10, right: 110, top, bottom: top + 20 },
  paragraph: { getGlyphPositionAtCoordinate: x => ({ position: Math.round(x / 20) }) } });
const page = { selectionText: '甲乙丙丁戊己庚辛壬癸', selectionX: 10, selectionY: 30,
  displayStart: 0, displayEnd: 10, fragments: [fragment(0, 5, 30), fragment(5, 10, 80)] };
Object.assign(reader, { readerDesktopSelectionPage: page, readerDesktopSelectionMenuVisible: true,
  readerDesktopSelectionStart: 2, readerDesktopSelectionEnd: 3, readerV2SelectionPaintVersion: 0,
  readerV2NativeSelectionChapterIndex: 1, readerV2NativeSelectionPageIndex: 2,
  readerSelectionMenuWidth: 284, readerSelectionMenuHeight: 56, getReaderTopSafePadding: () => 20,
  getUIContext: () => ({ getComponentUtils: () => ({ getRectangleById: id => ({
    size: { width: 1000, height: 1000 }, windowOffset: id === 'reader_selection_host' ? { x: 210, y: 330 } : { x: 100, y: 100 }
  }) }) }),
  readerV2DisplayHighlightRects: (_page, start, end) => {
    const boxes = [];
    for (let index = start; index < end; index++) boxes.push({
      leftPx: 10 + index % 5 * 20, topPx: index < 5 ? 30 : 80, widthPx: 20, heightPx: 20
    });
    return boxes;
  } });
reader.refreshReaderSelectionHandles();
assert.equal(reader.readerSelectionStartX, 75);
assert.equal(reader.readerSelectionStartY, 115);
assert.equal(reader.readerSelectionEndX, 85);
assert.equal(reader.readerSelectionEndY, 125);
reader.beginReaderSelectionHandleDrag(false);
reader.updateReaderSelectionHandleDrag({ offsetX: 20, offsetY: 0 });
assert.equal(reader.readerDesktopSelectedText(), '丙丁戊', 'end handle expands the actual copy range');
reader.beginReaderSelectionHandleDrag(true);
reader.updateReaderSelectionHandleDrag({ offsetX: -20, offsetY: 0 });
assert.equal(reader.readerDesktopSelectedText(), '甲乙丙丁戊', 'start handle expands backward');
reader.beginReaderSelectionHandleDrag(false);
reader.updateReaderSelectionHandleDrag({ offsetX: -30, offsetY: 25 });
assert.equal(reader.readerDesktopSelectedText(), '甲乙丙丁戊己庚', 'drag reaches a later paragraph');
reader.beginReaderSelectionHandleDrag(true);
reader.updateReaderSelectionHandleDrag({ offsetX: 50, offsetY: 25 });
assert.equal(reader.readerDesktopSelectedText(), '辛壬癸', 'crossing the opposite endpoint keeps an ordered range');
assert.equal(reader.readerV2SelectionDisplayStart, 7);
assert.equal(reader.readerV2SelectionDisplayEnd, 10);
page.selectionText = '甲😀丁戊己庚辛壬癸';
reader.readerDesktopSelectionStart = 0; reader.readerDesktopSelectionEnd = 1;
reader.beginReaderSelectionHandleDrag(false);
reader.updateReaderSelectionHandleDrag({ offsetX: 10, offsetY: 0 });
assert.equal(reader.readerDesktopSelectionEnd, 3, 'drag never splits a surrogate pair');
console.log('Reader selection handles: geometry, both endpoints, paragraphs, crossing and UTF-16 boundaries passed.');

// Unlike paragraphs within one layout, scrolling paragraphs live in independent ListItems.
const chunks = ['甲乙丙丁戊', '己庚辛壬癸', '一二三四五'].map((selectionText, index) => ({
  identity: String(index), selectionText, selectionX: 10, selectionY: 0,
  displayStart: 0, displayEnd: 5, fragments: [fragment(0, 5, 0)]
}));
Object.assign(reader, { currentChapterIndex: 1, readerV2SelectionChapterIndex: 1,
  readerDesktopSelectionPage: chunks[0], readerDesktopSelectionStart: 2, readerDesktopSelectionEnd: 3,
  readerSelectionStartChunk: 0, readerSelectionEndChunk: 0,
  contentPages: chunks.map(page => page.selectionText), readerContinuousVisibleStart: 0, readerContinuousVisibleEnd: 2,
  readerContinuousV2Layout: index => chunks[index], readerContinuousV2ItemId: index => String(index),
  getUIContext: () => ({ getComponentUtils: () => ({ getRectangleById: id => ({
    size: { width: 1000, height: id === 'reader_keyboard_surface' ? 1000 : 100 },
    windowOffset: id === 'reader_keyboard_surface' ? { x: 100, y: 100 } : { x: 100, y: 300 + Number(id) * 100 }
  }) }) }),
  readerV2DisplayHighlightRects: (_page, start, end) => end > start ? [{
    leftPx: 10 + start * 20, topPx: 0, widthPx: (end - start) * 20, heightPx: 20
  }] : [] });
reader.refreshReaderSelectionHandles();
reader.beginReaderSelectionHandleDrag(false);
reader.updateReaderSelectionHandleDrag({ offsetX: 10, offsetY: 100 });
assert.equal(reader.readerSelectionStartChunk, 0);
assert.equal(reader.readerSelectionEndChunk, 2);
assert.equal(reader.readerDesktopSelectedText(), '丙丁戊\n己庚辛壬癸\n一二三四', 'copy includes all independently laid out chunks');
assert.equal(reader.readerContinuousV2SelectionRects(0, '', 1)[0].widthPx, 60);
assert.equal(reader.readerContinuousV2SelectionRects(1, '', 1)[0].widthPx, 100);
assert.equal(reader.readerContinuousV2SelectionRects(2, '', 1)[0].widthPx, 80);
assert.equal(reader.readerSelectionEndY, 210, 'end handle uses the last chunk origin');
reader.beginReaderSelectionHandleDrag(true);
reader.updateReaderSelectionHandleDrag({ offsetX: -10, offsetY: 50 });
assert.equal(reader.readerDesktopSelectedText(), '庚辛壬癸\n一二三四', 'start handle can move into another chunk');
reader.beginReaderSelectionHandleDrag(false);
reader.updateReaderSelectionHandleDrag({ offsetX: -20, offsetY: -100 });
assert.equal(reader.readerDesktopSelectedText(), '丙丁戊\n己', 'dragging past the opposite chunk swaps the range');
reader.beginReaderSelectionHandleDrag(false);
reader.updateReaderSelectionHandleDrag({ offsetX: -10, offsetY: 50 });
assert.equal(reader.readerSelectionEndChunk, 1, 'zero offset at next chunk uses the preceding glyph endpoint');
assert.equal(reader.readerDesktopSelectionEnd, 5);
assert.equal(reader.readerSelectionHandlesReady, true);
reader.readerSelectionStartX = 300; reader.readerSelectionEndX = 380;
reader.readerSelectionStartY = 300; reader.readerSelectionEndY = 350;
reader.positionReaderSelectionMenu(800, 600);
assert.equal(reader.readerSelectionMenuX, 198);
assert.equal(reader.readerSelectionMenuY, 204, 'menu follows selection above handles');
reader.readerSelectionStartY = 25; reader.readerSelectionEndY = 55;
reader.readerSelectionStartX = 0; reader.readerSelectionEndX = 20;
reader.positionReaderSelectionMenu(800, 600);
assert.equal(reader.readerSelectionMenuX, 8);
assert.equal(reader.readerSelectionMenuY, 95, 'top-edge selection puts menu below handles');
reader.readerSelectionStartX = 795; reader.readerSelectionEndX = 800;
reader.positionReaderSelectionMenu(800, 600);
assert.equal(reader.readerSelectionMenuX, 508, 'menu stays within the right edge');
console.log('Reader scrolling selection: independent chunks, highlights, copy, reversed endpoints and anchored menu passed.');

// Exercise actual selection entry points and cleanup, including a queued layout retry.
const timers = [];
const toggleContext = vm.createContext({ Date, Set, setTimeout: callback => timers.push(callback),
  MenuPolicy: { HIDE: 'hide' } });
vm.runInContext(stripTypeScriptTypes(`class ReaderSelectionToggle {
${['selectReaderTextAtPoint', 'beginReaderV2NativeSelection', 'onReaderLongPressSelectTextChanged',
  'scheduleReaderTextSelectionClear', 'clearReaderV2SelectionOverlay', 'retryReaderTextSelection'].map(method).join('\n')}
} globalThis.ReaderSelectionToggle = ReaderSelectionToggle;`), toggleContext);
const toggle = new toggleContext.ReaderSelectionToggle();
let pagedSelections = 0, scrollSelections = 0, continuous = false, closedMenus = 0;
Object.assign(toggle, {
  readerLongPressSelectText: false, readerPageVisible: true, readerTextSelectionSerial: 0,
  readerV2NativeSelectionHostVersion: 0, readerV2SelectionPaintVersion: 0,
  readerV2NativeSelectionFragmentIndex: -1, readerV2SelectionDisplayStart: -1,
  readerV2SelectionDisplayEnd: -1,
  isReaderNovelContinuousScrollModeActive: () => continuous,
  shouldUseReaderLayoutV2: () => true, usesReaderContinuousV2: () => continuous,
  setReaderTextSelectionActive: active => { toggle.readerTextSelectionActive = active; },
  selectReaderV2TextAtGlobalPoint: () => pagedSelections++,
  selectReaderContinuousV2TextAtPoint: () => scrollSelections++,
  readerSelectableTextControllers: new Map([['text', {
    closeSelectionMenu: () => closedMenus++,
    setTextSelection: (start, end, options) => {
      assert.equal(start, -1); assert.equal(end, -1); assert.equal(options.menuPolicy, 'hide');
    }
  }]]), readerInlineActionTextControllers: new Map()
});
for (const scrollMode of [false, true]) {
  continuous = scrollMode;
  toggle.selectReaderTextAtPoint(10, 20);
  assert.equal(toggle.suppressReaderTapClick, true, 'disabled long press must not fall through to a tap');
  assert.equal(toggle.readerTextSelectionSerial, 0);
}
assert.equal(pagedSelections + scrollSelections, 0);
assert.equal(toggle.beginReaderV2NativeSelection(null, 0, '', 0, 0, 0), 0,
  'late selection requests cannot mount a native host while disabled');
toggle.readerLongPressSelectText = true;
for (const scrollMode of [false, true]) {
  continuous = scrollMode;
  toggle.selectReaderTextAtPoint(10, 20);
}
assert.equal(pagedSelections, 1); assert.equal(scrollSelections, 1);
toggle.readerDesktopSelectionMenuVisible = true;
toggle.readerV2NativeSelectionFragmentIndex = 0;
toggle.readerV2SelectionDisplayStart = 0; toggle.readerV2SelectionDisplayEnd = 1;
let retried = false;
toggle.retryReaderTextSelection(toggle.readerTextSelectionSerial, 0, () => { retried = true; });
toggle.readerLongPressSelectText = false;
toggle.onReaderLongPressSelectTextChanged();
assert.equal(toggle.readerDesktopSelectionMenuVisible, false);
assert.equal(toggle.readerV2NativeSelectionFragmentIndex, -1);
assert.equal(toggle.readerTextSelectionActive, false);
for (const callback of timers) callback();
assert.equal(retried, false, 'disabling invalidates queued selection retries');
assert.equal(closedMenus, 1);
assert.equal(toggle.readerTextSelectionUntil, 0);
console.log('Reader long press switch: disabled, re-enabled, paged/scroll modes and pending selection cleanup passed.');
