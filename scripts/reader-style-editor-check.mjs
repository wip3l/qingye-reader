import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { loadObsidianReader } from './lib/obsidian-reader-fixture.mjs';
import { loadReaderModules } from './lib/load-reader-modules.mjs';

const base = new URL('../entry/src/main/ets/', import.meta.url);
const read = name => fs.readFileSync(new URL(name, base), 'utf8').replace(/\r\n/g, '\n');
const source = read('pages/Settings.ets');
function method(name, moduleSource = source) {
  const start = moduleSource.indexOf(`  ${name}(`);
  assert(start >= 0, `Missing ${name}`);
  const end = moduleSource.indexOf('\n  }\n', start);
  assert(end > start);
  return moduleSource.slice(start, end + 4);
}
const fieldsSource = read('components/reader/ReaderLayoutSettings.ets');
const fieldsStart = fieldsSource.indexOf('export class ReaderTypographyField');
const fieldsEnd = fieldsSource.indexOf('\n}\n', fieldsStart) + 3;
const compile = code => stripTypeScriptTypes(code.replace(/^export /gm, ''), { mode: 'strip' });
const pendingSwitches = new Map();
let switchSerial = 0;
const context = vm.createContext({
  setTimeout: (callback, delay) => { const id = ++switchSerial; pendingSwitches.set(id, { callback, delay }); return id; },
  clearTimeout: id => pendingSwitches.delete(id)
});
vm.runInContext(compile(read('core/reader/ReaderFontWeight.ts')) + '\n' +
  compile(read('theme/AppSpacing.ets')) + '\n' +
  compile(read('core/reader/ReaderCommentBubbleSize.ts')) + '\n' +
  compile(fieldsSource.slice(fieldsStart, fieldsEnd)) + '\n' + compile(`
class ReaderSettings {}
class EditorHarness {
  readerFontSize = 20;
  readerFontWeight = 400;
  readerLetterSpacing = 0;
  readerTextAlign = 'justify';
  readerLineHeight = 12;
  readerParagraphSpacing = 0;
  readerParagraphIndent = 2;
  readerMarginLeft = 18;
  readerMarginRight = 18;
  readerMarginTop = 18;
  readerMarginBottom = 18;
  readerCommentBubbleSize = ReaderCommentBubbleSize.DEFAULT;
  readerHeaderEnabled = true;
  readerFooterEnabled = true;
  readerInfoBarConfig = 'current-chrome';
  readerExtendToStatusBar = false;
  typographySettingIndex = 0;
  fontPreviewSettings = { titleFontSize: 37, regexFontEnabled: true, fontSize: 28 };
  saves = 0;
  statusBarHeight = 32;
  navBarHeight = 24;
  novelViewportHeight = 844;
  novelSettingsCollapsed = false;
  novelViewportWidth = 390;
  novelSettingsGroup = 0;
  novelStyleContentHeight = 0;
  novelPanelHeaderHeight = 0;
  novelPanelFooterHeight = 0;
  applyTypographyValueInput(): void {}
  saveReaderLayoutSettings(): void { this.saves++; }
  syncBars(): void {}
  ${['setNovelTypography', 'currentTypographySettingValue', 'previewLayoutSettings',
    'novelPanelTop', 'novelPanelHeight', 'novelPanelWidth', 'openNovelStyleEditor'].map(name => method(name)).join('\n')}
}
globalThis.api = { EditorHarness, ReaderTypographyField };
`), context);
const { EditorHarness: Harness, ReaderTypographyField: Fields } = context.api;
const h = new Harness();
for (let field = 0; field < Fields.COUNT; field++) {
  const before = h.saves;
  h.setNovelTypography(field, -1000, false);
  assert.equal(h.currentTypographySettingValue(field), Fields.min(field));
  assert.equal(h.saves, before, 'dragging updates the preview without a disk write per frame');
  h.setNovelTypography(field, 10000);
  assert.equal(h.currentTypographySettingValue(field), Fields.max(field));
  assert.equal(h.saves, before + 1, 'the final slider value is saved');
}
h.readerFontSize = 24;
h.readerLineHeight = 20;
h.readerCommentBubbleSize = Fields.min(9);
const preview = h.previewLayoutSettings();
assert.equal(preview.fontSize, 24);
assert.equal(preview.lineHeight, 20);
assert.equal(preview.titleFontSize, 37, 'font editing and layout editing share a complete preview snapshot');
assert.equal(preview.readerInfoBarConfig, 'current-chrome');
assert.equal(h.fontPreviewSettings.fontSize, 28, 'preview composition never mutates the font editor snapshot');
for (const height of [280, 360, 600, 844, 1200]) {
  h.novelViewportHeight = height;
  const before = h.novelPanelHeight();
  assert(before >= 140);
  if (height >= 600) assert(before >= Math.min(640, height * 0.6), 'expanded panels expose more settings on taller windows');
  assert(h.novelPanelTop() + before <= height - h.navBarHeight);
  assert(Math.abs(h.novelPanelTop() - (height - h.novelPanelTop() - before)) < 0.001,
    'the full panel keeps equal top and bottom margins');
  h.novelSettingsCollapsed = true;
  assert.equal(h.novelPanelHeight(), before, 'show/hide does not redefine the reading viewport');
  h.novelSettingsCollapsed = false;
}
console.log('PASS: all ten typography fields clamp, preview live, save on commit, preserve font/chrome settings, and fit short and tall windows');

const fitted = new Harness();
fitted.novelViewportHeight = 844;
const fullHeight = fitted.novelPanelHeight();
fitted.openNovelStyleEditor(3);
assert.equal(fitted.novelSettingsGroup, 3, 'each entry opens its own panel');
fitted.novelPanelHeaderHeight = 48;
fitted.novelPanelFooterHeight = 32;
fitted.novelStyleContentHeight = 220;
assert.equal(fitted.novelPanelHeight(), 300, 'a short category shrinks the panel to its content');
assert(Math.abs(fitted.novelPanelTop() - (844 - fitted.novelPanelTop() - 300)) < 0.001, 'a fitted panel stays centered');
fitted.novelStyleContentHeight = 40;
assert.equal(fitted.novelPanelHeight(), 200, 'nearly empty content keeps a usable minimum height');
fitted.novelStyleContentHeight = 5000;
assert.equal(fitted.novelPanelHeight(), fullHeight, 'long content scrolls inside the full-height panel');
fitted.openNovelStyleEditor(2);
fitted.novelStyleContentHeight = 220;
assert.equal(fitted.novelPanelHeight(), fullHeight, 'the font panel keeps one height while switching its sections');
fitted.openNovelStyleEditor(0);
assert.equal(fitted.novelStyleContentHeight, 0, 'reopening re-measures the new category');
assert.equal(fitted.novelPanelHeight(), fullHeight);
console.log('PASS: separate category panels fit short content, cap long content and stay centered');

const previewSource = read('components/reader/ReaderSettingsPreview.ets');
const withoutImports = code => code.replace(/^import .*;\n/gm, '');
vm.runInContext(compile(withoutImports(read('utils/HexColor.ts'))) + '\n' +
  compile(withoutImports(read('core/reader/ReaderInfoBarModel.ts'))) + '\n' + compile(`
class PreviewHarness {
  statusBarHeight = 32;
  navBarHeight = 24;
  previewHeight = 844;
  settings = { readerHeaderEnabled: false, readerFooterEnabled: true,
    readerInfoBarConfig: '', extendToStatusBar: false, marginTop: 18, marginBottom: 18 };
  getUIContext() { return { fp2px: n => n * 3, px2vp: n => n / 2 }; }
  ${['info', 'headerVisible', 'headerTop', 'footerBottom', 'bodyTop', 'bodyBottom',
    'footerHeight', 'footerTop'].map(name => method(name, previewSource)).join('\n')}
}
globalThis.previewAPI = { PreviewHarness, ReaderInfoBarConfig };
`), context);
const { PreviewHarness, ReaderInfoBarConfig: Config } = context.previewAPI;
const p = new PreviewHarness();
assert(p.footerTop() > p.previewHeight * 0.8, 'footer remains at the bottom of the full reading surface');
assert(p.footerTop() + p.footerHeight() <= p.previewHeight);
assert(p.previewHeight - p.bodyBottom() < p.footerTop(), 'body pagination clears the scaled footer');
p.settings.readerHeaderEnabled = true;
const chrome = new Config();
chrome.headerOffset = 64;
chrome.footerFontSize = 40;
chrome.footerOffset = 80;
p.settings.readerInfoBarConfig = chrome.serialize();
assert(p.bodyTop() >= p.headerTop() + chrome.headerLineHeight(), 'body clears a repositioned header');
assert(p.previewHeight - p.bodyBottom() < p.footerTop(), 'large footer fonts reserve matching pagination space');
p.settings.readerFooterEnabled = false;
assert(p.bodyBottom() >= p.navBarHeight, 'footerless reading still avoids the gesture area');
console.log('PASS: header and footer placement, font scaling and body pagination reserves stay consistent');

// Compare the preview against production reader styles, including matches spanning a decorated title.
const fixture = loadObsidianReader();
const modules = await loadReaderModules();
try {
  const sandbox = fixture.sandbox;
  Object.assign(sandbox, { ReaderActionMarker: modules.ReaderActionMarker, EpubNoteLink: modules.EpubNoteLink,
    ReaderImageMarker: modules.ReaderImageMarker, ReaderInfoBarContext: modules.ReaderInfoBarContext,
    ReaderInfoBarClock: { timeText: () => '10:30', batteryPercent: () => 80 },
    CooperativeScheduler: { reportSynchronousOperation() {} } });
  const readerSource = read('pages/ReadBook.ets');
  const typographySource = read('components/reader/ReaderTypographyPreview.ets');
  const configStart = typographySource.indexOf('export class ReaderTypographyPreviewConfig');
  const configEnd = typographySource.indexOf('\n}\n', configStart) + 3;
  const constants = previewSource.slice(previewSource.indexOf('const SETTINGS_PREVIEW_TITLE'),
    previewSource.indexOf('/** 全尺寸阅读底层'));
  vm.runInContext(compile(read('core/reader/ReaderHorizontalMargin.ts')) + '\n' +
    compile(read('core/reader/ReaderV2Document.ets')
    .replace(/^import .*;\n/gm, '')) + '\n' +
    compile(read('core/reader/ReaderV2LayoutSnapshot.ets').replace(/^import .*;\n/gm, '')) + '\n' +
    compile(typographySource.slice(configStart, configEnd)) + '\n' + compile(constants) + '\n' + compile(`
class PreviewStyleHarness {
  settings = { titleStyleRaw: '', fontSize: 20, fontWeight: 500, lineHeight: 12,
    letterSpacing: 1, paragraphSpacing: 16, marginLeft: 18, marginRight: 18, paragraphIndent: 2,
    bodyFontMode: 'global', bodyFontFamily: '', titleFontMode: 'global', titleFontFamily: '',
    titleFontSize: 25, titleFontWeight: 700, textAlign: 'justify', regexFontEnabled: true,
    regexFontRulesRaw: '', commentBubbleSize: 100 };
  readerTheme = { backgroundColor: '#FFF8E8', textColor: '#332211' };
  globalFamily = ''; systemFamily = 'device'; darkMode = false; appDarkMode = true;
  previewWidth = 360; previewHeight = 844; revision = 0; previewPageIndex = 0; pageChanges = [];
  previewPager = { changeIndex: (index, animated) => this.pageChanges.push([index, animated]) };
  resolveCustomFamily(family) { return 'registered_' + family; }
  getUIContext() { return { vp2px: n => n * 2, fp2px: n => n * 2.4 }; }
  bodyTop() { return 60; } bodyBottom() { return 50; }
  ${['titleSinglePage', 'onPreviewPageChanged', 'infoContext', 'emphasisContext', 'fontFamily',
    'spanStyle', 'rangesOutsideTitle', 'effectiveHorizontalMargin', 'config'].map(name => method(name, previewSource)).join('\n')}
}
class ActualStyleHarness extends ReaderHarness {
  rules = []; readerRegexFontEnabled = true; readerRegexFontSize = 20;
  readerTitleFontSize = 25; readerTitleFontWeight = 700; readerTitleStyleRaw = '';
  paperDark = false;
  columnWidth = 360;
  getReaderPageColumnWidth() { return this.columnWidth; }
  ${method('getEffectiveReaderHorizontalMargin', readerSource)}
  getTitleReaderFontFamily() { return ''; }
  getRegexRules() { return this.rules; }
  buildTextSliceKey(text) { return text; }
  resolveStyledReaderFontFamily(mode, family) {
    return mode === 'custom' ? 'registered_' + family : mode === 'system' ? 'device' : '';
  }
  isReaderThemeDark() { return this.paperDark; }
  getBackgroundColor() { return '#FFF8E8'; }
  getTextColor() { return '#332211'; }
  toMeasurePx(n) { return n * 2; } toMeasureFontPx(n) { return n * 2.4; }
  ${['getRegexTextSlices', 'hasOverlappedRegexSlice', 'getRegexRuleBySlice', 'getRegexSliceFontSize',
    'getRegexSliceFontFamily', 'buildReaderV2RegexStyles'].map(name => method(name, readerSource)).join('\n')}
}
globalThis.styleAPI = { PreviewStyleHarness, ActualStyleHarness, ReaderRegexFontCodec,
  ReaderTitleStyleCodec, ReaderTitleStyleSettings, ReaderRegexFontRule };
`), sandbox);
  const { PreviewStyleHarness, ActualStyleHarness, ReaderRegexFontCodec: RegexCodec,
    ReaderTitleStyleCodec: TitleCodec, ReaderTitleStyleSettings: TitleSettings,
    ReaderRegexFontRule: Rule } = sandbox.styleAPI;
  const preview = new PreviewStyleHarness(), actual = new ActualStyleHarness();
  for (const width of [96, 200, 320, 360, 600]) {
    for (const fontSize of [14, 20, 50]) {
      for (const margins of [[0, 0], [18, 18], [80, 80], [80, 20]]) {
        preview.previewWidth = actual.columnWidth = width;
        preview.settings.fontSize = actual.readerFontSize = fontSize;
        preview.settings.marginLeft = actual.readerMarginLeft = margins[0];
        preview.settings.marginRight = actual.readerMarginRight = margins[1];
        const settingsBefore = JSON.stringify(preview.settings);
        const config = preview.config();
        assert.equal(config.input.marginLeftPx / 2, actual.getEffectiveReaderHorizontalMargin(true),
          `preview and reader left margins agree: width=${width}, font=${fontSize}, margins=${margins}`);
        assert.equal(config.input.marginRightPx / 2, actual.getEffectiveReaderHorizontalMargin(false),
          `preview and reader right margins agree: width=${width}, font=${fontSize}, margins=${margins}`);
        assert.equal(JSON.stringify(preview.settings), settingsBefore, 'adaptive margins never rewrite settings');
      }
    }
  }
  preview.previewWidth = 360;
  preview.settings.fontSize = 50;
  preview.settings.marginLeft = preview.settings.marginRight = 80;
  assert.equal(preview.config().input.marginLeftPx, 120, 'large fonts preserve 240 vp of text on a 360 vp page');
  preview.previewWidth = 600;
  assert.equal(preview.config().input.marginLeftPx, 160, 'widening the viewport restores the stored 80 vp margin');
  preview.settings.fontSize = 20;
  preview.settings.marginLeft = preview.settings.marginRight = 18;
  console.log('PASS: preview and reader share adaptive margins across narrow windows, large fonts, asymmetric margins and resizing');
  const title = new TitleSettings();
  title.emphasis.emphasisMode = 'custom';
  title.emphasis.customTextColorEnabled = true;
  title.emphasis.customTextColor = '#CCAA5511';
  title.singlePage = true;
  title.mode = 'position'; title.position = '3';
  preview.settings.titleStyleRaw = actual.readerTitleStyleRaw = TitleCodec.encode(title);
  const first = new Rule();
  first.id = 'first'; first.pattern = '[\\s\\S]+'; first.fontMode = 'custom'; first.fontFamily = 'sample';
  first.fontSize = 27; first.fontWeight = 650; first.emphasisMode = 'inherit';
  const second = new Rule(); second.id = 'second'; second.pattern = '风'; second.fontSize = 40;
  const invalid = new Rule(); invalid.id = 'invalid'; invalid.pattern = '[';
  const empty = new Rule(); empty.id = 'empty'; empty.pattern = '$';
  const plain = config => JSON.parse(JSON.stringify(config));
  for (const appDark of [false, true]) for (const paperDark of [false, true]) {
    fixture.store.set('appDarkMode', appDark);
    preview.appDarkMode = actual.appDarkMode = appDark;
    preview.darkMode = actual.paperDark = paperDark;
    for (const patterns of [[first, second, invalid, empty], [second, first], [invalid, empty],
      [Object.assign(new Rule(), { id: 'dialogue', pattern: '“[^”]+”', fontSize: 24, emphasisMode: 'inherit' })]]) {
      preview.settings.regexFontRulesRaw = RegexCodec.encode(patterns);
      actual.rules = RegexCodec.decode(preview.settings.regexFontRulesRaw);
      const config = preview.config(1);
      assert.deepEqual(plain(config.styles), plain(actual.buildReaderV2RegexStyles(config.document)),
        'preview and reader agree on title precedence, rule order, registered fonts, colors and bubble decoration');
      if (patterns[0] === first) {
        assert(config.styles.some(style => !style.repeatCaps && style.fontSizePx === 64.8),
          'a regex spanning the title still styles the body');
      }
    }
  }
  assert.equal(preview.config(0).pageIndex, 0);
  assert.equal(preview.config(1).pageIndex, 1);
  assert.equal(preview.config(0).input.titleSinglePage, true);
  assert.equal(preview.config(1).input.titleSinglePage, true);
  assert.deepEqual(plain(preview.config(0).document), plain(preview.config(1).document),
    'both full-size pages share the same source document and actual pagination settings');
  assert.equal(preview.infoContext(0).pageCount, 2);
  assert.equal(preview.infoContext(1).pageIndex, 1);
  preview.previewPageIndex = 1; preview.onPreviewPageChanged();
  assert.deepEqual(plain(preview.pageChanges), [[1, true]], 'the page button requests an animated native page switch');
  title.singlePage = false;
  preview.settings.titleStyleRaw = TitleCodec.encode(title);
  assert.equal(preview.config(1).pageIndex, 0, 'disabling title-only pages restores combined title and body');
  preview.onPreviewPageChanged();
  assert.equal(preview.pageChanges.length, 1, 'a removed pager is not addressed after disabling title-only pages');
  console.log('PASS: preview styles match the reader across title-spanning rules, overlap, invalid/empty matches and light/dark paper');
  console.log('PASS: title and body use separate full-size preview pages, synchronized metadata, animated navigation and combined-page fallback');
} finally {
  modules.cleanup();
}

const previewNodeSource = read('components/reader/ReaderTypographyPreview.ets')
  .replace(/^  private /gm, '  ');
vm.runInContext(compile(`class PreviewCapsHarness {
  capSegments = []; measuredHeightVp = 0; capsSignature = ''; layoutEpoch = 0; capsPublishTimer = -1;
  config = {};
  controller = { config: null, onLayoutReady: () => {}, rebuild: () => {} };
  ${['cancelCapsPublish', 'publishLayoutCaps', 'refresh', 'aboutToDisappear']
    .map(name => method(name, previewNodeSource)).join('\n')}
}
globalThis.PreviewCapsHarness = PreviewCapsHarness;`), context);
const caps = new context.PreviewCapsHarness();
caps.refresh();
const layout = { fragments: [{ regexBubbleSegments: [{ styleId: 'gilded-orbit', rect: { left: 30, top: 200 } }] }] };
const firstLayoutCallback = caps.controller.onLayoutReady;
firstLayoutCallback(layout, 844);
assert.equal(caps.capSegments.length, 0, 'decoration state is not mutated during native measurement');
assert.equal(pendingSwitches.size, 1);
firstLayoutCallback(JSON.parse(JSON.stringify(layout)), 844);
assert.equal(pendingSwitches.size, 1, 'unchanged geometry does not cause a measurement/publish loop');
let publication = [...pendingSwitches.values()][0].callback;
pendingSwitches.clear(); publication();
assert.equal(caps.capSegments[0].styleId, 'gilded-orbit', 'measured theme artwork reaches the visible preview layer');
assert.equal(caps.measuredHeightVp, 844);
firstLayoutCallback({ fragments: [] }, 844);
publication = [...pendingSwitches.values()][0].callback;
caps.refresh();
assert.equal(pendingSwitches.size, 0);
publication();
firstLayoutCallback(layout, 844);
assert.equal(caps.capSegments.length, 0, 'an old page cannot republish caps after a preview rebuild');
assert.equal(pendingSwitches.size, 0);
caps.controller.onLayoutReady(layout, 844);
assert.equal(pendingSwitches.size, 1);
caps.aboutToDisappear();
assert.equal(pendingSwitches.size, 0, 'leaving the preview cancels deferred decoration updates');
console.log('PASS: native layout publishes theme artwork after measurement, avoids render loops, and cancels stale page updates');
