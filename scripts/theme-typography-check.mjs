import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { pathToFileURL } from 'node:url';
import { projectRoot } from './lib/ets-module-staging.mjs';

// 排版跟随主题：每套主题的阅读档案各记一份排版，切换即取回；关闭跟随时所有主题共用当前排版。

const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${file}`, 'utf8');
const compile = text => stripTypeScriptTypes(text.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });
const APP_THEME_INDEX = 4;
const format = await import(pathToFileURL(
  `${projectRoot}/entry/src/main/ets/theme/share/ThemePackageFormat.ts`).href);

function harness() {
  const values = new Map([['appThemeId', 'classic-blue']]);
  const disk = new Map();
  let syncMarks = 0;
  const store = {
    get: async (key, fallback) => disk.has(key) ? disk.get(key) : fallback,
    put: async (key, value) => { disk.set(key, value); },
    delete: async key => { disk.delete(key); },
    flush: async () => {}
  };
  const context = vm.createContext({
    console,
    AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value) },
    preferences: { getPreferences: async () => store },
    CloudSyncChangeTracker: { markPreferenceChanged() { syncMarks++; } },
    isPackThemeId: format.isPackThemeId,
    ReaderThemeHelper: {
      LIGHT_CUSTOM_BACKGROUND_COLOR: '#FFFFFF', LIGHT_CUSTOM_TEXT_COLOR: '#333333',
      DARK_CUSTOM_BACKGROUND_COLOR: '#121212', DARK_CUSTOM_TEXT_COLOR: '#CCCCCC',
      APP_THEME_INDEX, normalizeIndex: value => value || 0
    },
  });
  vm.runInContext(compile(read('utils/HexColor.ts')) + '\n' +
    compile(read('core/reader/ReaderCommentBubbleSize.ts')) + '\n' +
    compile(read('core/reader/ReaderFontWeight.ts')) + '\n' +
    compile(read('core/reader/ReaderParagraphIndent.ts')) + '\n' +
    compile(read('core/reader/ReaderInfoBarModel.ts')) + '\n' +
    compile(read('core/reader/ReaderQuickJumpModel.ts')) + '\n' +
    compile(read('core/reader/ReaderNightImage.ts')) + '\n' +
    compile(read('core/reader/ReaderTitleSplit.ts')) + '\n' +
    compile(read('model/reader/ReaderRegexFontRule.ets')) + '\n' +
    compile(read('model/reader/ReaderTitleStyle.ets')) + '\n' +
    compile(read('utils/ReaderSettingsStore.ets')) + '\n' +
    compile(read('utils/ThemeTypographyDraft.ets')) +
    '\nglobalThis.api = { ReaderSettingsStore, ReaderSettings, ReaderInfoBarConfig, ThemeTypographyDraft };', context);
  const { ReaderSettingsStore: settings, ReaderSettings, ReaderInfoBarConfig: Config, ThemeTypographyDraft } =
    context.api;
  settings.applyToStorage(new ReaderSettings());
  return { settings, ReaderSettings, Config, ThemeTypographyDraft, values, disk,
    get syncMarks() { return syncMarks; } };
}

function typography(h) {
  const source = new h.ReaderSettings();
  source.fontSize = 26;
  source.fontWeight = 550;
  source.letterSpacing = 2;
  source.textAlign = 'start';
  source.lineHeight = 20;
  source.paragraphSpacing = 9;
  source.paragraphIndent = 1;
  source.marginLeft = 30;
  source.marginRight = 31;
  source.marginTop = 40;
  source.marginBottom = 41;
  source.extendToStatusBar = true;
  source.readerHeaderEnabled = true;
  source.readerFooterEnabled = false;
  const config = new h.Config();
  config.headerOffset = 12;
  source.readerInfoBarConfig = config.serialize();
  source.bodyFontMode = 'custom';
  source.bodyFontFamily = 'theme-body';
  source.titleFontMode = 'system';
  source.titleFontSize = 30;
  source.titleFontWeight = 650;
  source.titleStyleRaw = JSON.stringify({ mode: 'marker', marker: '：', secondaryScale: 1.5, lineGap: 16,
    alignment: 'right', marginTop: 24, marginBottom: 36, singlePage: true,
    emphasis: { emphasisMode: 'custom', customTextColorEnabled: true, customTextColor: '#80123456' } });
  source.regexFontEnabled = true;
  source.regexFontRulesRaw = '{"schemaVersion":3,"rules":[]}';
  // 不属于排版的字段不能被带进档案。
  source.pageTurnMode = 2;
  source.fontFamily = 'should-not-copy';
  source.volumeTurnPage = true;
  return source;
}

function assertTypography(actual) {
  assert.equal(actual.fontSize, 26);
  assert.equal(actual.fontWeight, 550);
  assert.equal(actual.letterSpacing, 2);
  assert.equal(actual.textAlign, 'start');
  assert.equal(actual.lineHeight, 20);
  assert.equal(actual.paragraphSpacing, 9);
  assert.equal(actual.paragraphIndent, 1);
  assert.equal(actual.marginLeft, 30);
  assert.equal(actual.marginRight, 31);
  assert.equal(actual.marginTop, 40);
  assert.equal(actual.marginBottom, 41);
  assert.equal(actual.extendToStatusBar, true);
  assert.equal(actual.readerHeaderEnabled, true);
  assert.equal(actual.readerFooterEnabled, false);
  assert.equal(JSON.parse(actual.readerInfoBarConfig).headerOffset, 12);
  assert.equal(actual.bodyFontMode, 'custom');
  assert.equal(actual.bodyFontFamily, 'theme-body');
  assert.equal(actual.titleFontMode, 'system');
  assert.equal(actual.titleFontSize, 30);
  assert.equal(actual.titleFontWeight, 650);
  const title = JSON.parse(actual.titleStyleRaw);
  assert.equal(title.mode, 'marker');
  assert.equal(title.secondaryScale, 1.5);
  assert.equal(title.lineGap, 16);
  assert.equal(title.alignment, 'right');
  assert.equal(title.marginTop, 24);
  assert.equal(title.marginBottom, 36);
  assert.equal(title.singlePage, true);
  assert.equal(title.emphasis.customTextColor, '#80123456');
  assert.equal(actual.regexFontEnabled, true);
}

const SCHEME_PROFILE = 'custom__custom_1';

const tests = {
  async 'reader layout edits are visible to the active custom scheme without a separate theme save'() {
    const h = harness();
    h.values.set('appThemeId', 'custom');
    h.values.set('activeCustomThemeSchemeId', 'custom_1');
    await h.settings.reload({});
    // 阅读页连续调整后立即打开主题页，此时不要求主题排版页曾经保存过。
    const pending = h.settings.saveLayoutSettings({}, 30, 16, 8, 24, 25);
    assert.equal(await h.settings.hasThemeTypography({}, SCHEME_PROFILE), true);
    const profile = await h.settings.loadProfile({}, SCHEME_PROFILE);
    assert.equal(profile.fontSize, 30);
    assert.equal(profile.lineHeight, 16);
    assert.equal(profile.paragraphSpacing, 8);
    assert.equal(profile.marginLeft, 24);
    assert.equal(profile.marginRight, 25);
    await pending;
    assert.equal((await h.settings.reload({})).fontSize, 30);
  },

  async 'existing unmarked custom profiles keep their saved typography across scheme switches'() {
    const h = harness();
    const saved = typography(h);
    saved.fontSize = 30;
    h.disk.set(`readerThemeProfileV1_${SCHEME_PROFILE}`, JSON.stringify(saved));
    assert.equal(h.disk.has(`readerThemeTypographyBoundV1_${SCHEME_PROFILE}`), false);
    assert.equal(await h.settings.hasThemeTypography({}, SCHEME_PROFILE), true);
    assert.equal((await h.settings.loadProfile({}, SCHEME_PROFILE)).fontSize, 30);
    assert.equal((await h.settings.load({})).fontSize, 20, 'inactive profile does not change live settings');

    h.values.set('appThemeId', 'custom');
    h.values.set('activeCustomThemeSchemeId', 'custom_1');
    const active = await h.settings.switchThemeProfile({}, 'classic-blue', SCHEME_PROFILE);
    assert.equal(active.fontSize, 30);
    h.values.set('activeCustomThemeSchemeId', 'custom_2');
    const secondId = 'custom__custom_2';
    await h.settings.switchThemeProfile({}, SCHEME_PROFILE, secondId);
    await h.settings.saveLayoutSettings({}, 22, 10, 0);
    assert.equal((await h.settings.loadProfile({}, SCHEME_PROFILE)).fontSize, 30);
    assert.equal((await h.settings.loadProfile({}, secondId)).fontSize, 22);
  },

  async 'only themes with a readable profile or the active theme count as having typography'() {
    const h = harness();
    assert.equal(await h.settings.hasThemeTypography({}, SCHEME_PROFILE), false);
    h.disk.set(`readerThemeProfileV1_${SCHEME_PROFILE}`, '{broken');
    assert.equal(await h.settings.hasThemeTypography({}, SCHEME_PROFILE), false);
    assert.equal(await h.settings.hasThemeTypography({}, 'classic-blue'), true, 'the active theme always has one');
    assert.equal(await h.settings.hasThemeTypography({}, 'warm-paper'), false, 'unused builtin theme');
    h.disk.set('readerThemeProfileV1_warm-paper', JSON.stringify(new h.ReaderSettings()));
    assert.equal(await h.settings.hasThemeTypography({}, 'warm-paper'), true, 'used builtin theme');
  },

  async 'saving an inactive scheme writes only its profile'() {
    const h = harness();
    await h.settings.saveLayoutSettings({}, 20, 12, 0);
    const existing = new h.ReaderSettings();
    existing.pageTurnMode = 0;
    existing.lightThemeIndex = 2;
    h.disk.set(`readerThemeProfileV1_${SCHEME_PROFILE}`, JSON.stringify(existing));
    assert.equal(await h.settings.hasThemeTypography({}, SCHEME_PROFILE), true,
      'an existing custom scheme profile already owns its typography');

    await h.settings.saveTypographyToProfile({}, SCHEME_PROFILE, typography(h));

    const saved = JSON.parse(h.disk.get(`readerThemeProfileV1_${SCHEME_PROFILE}`));
    assertTypography(saved);
    assert.equal(saved.pageTurnMode, 0, 'unrelated settings in the scheme profile stay');
    assert.equal(saved.lightThemeIndex, 2);
    assert.equal(saved.volumeTurnPage, false);
    assert.notEqual(saved.fontFamily, 'should-not-copy');
    assert.equal(await h.settings.hasThemeTypography({}, SCHEME_PROFILE), true);
    // 正在使用的主题完全不受影响。
    assert.equal(h.values.get('readerFontSize'), 20);
    assert.equal(h.values.get('readerHeaderEnabled'), false);
    assert.equal((await h.settings.load({})).fontSize, 20);
    assert.equal(h.syncMarks, 0, 'typography stays device-local like other layout edits');
  },

  async 'a scheme without a profile copies current settings and follows the theme background'() {
    const h = harness();
    await h.settings.savePageTurnMode({}, 0);
    await h.settings.saveTypographyToProfile({}, 'custom__fresh', typography(h));
    const saved = JSON.parse(h.disk.get('readerThemeProfileV1_custom__fresh'));
    assertTypography(saved);
    assert.equal(saved.pageTurnMode, 0);
    assert.equal(saved.themeIndex, APP_THEME_INDEX);
    assert.equal(saved.lightThemeIndex, APP_THEME_INDEX);
    assert.equal(saved.darkThemeIndex, APP_THEME_INDEX);
  },

  async 'switching to a bound scheme applies its typography but keeps the global font'() {
    const h = harness();
    await h.settings.saveFontSettings({}, 'global-face', '/fonts/a.ttf', 'A', 'custom', '', '');
    await h.settings.saveTypographyToProfile({}, SCHEME_PROFILE, typography(h));
    h.values.set('appThemeId', 'custom');
    h.values.set('activeCustomThemeSchemeId', 'custom_1');
    const next = await h.settings.switchThemeProfile({}, 'classic-blue', SCHEME_PROFILE);
    assertTypography(next);
    assert.equal(next.fontFamily, 'global-face');
    assert.equal(h.values.get('readerFontSize'), 26);
    assert.equal(h.values.get('readerHeaderEnabled'), true);
    assert.equal(h.values.get('readerBodyFontFamily'), 'theme-body');
    assert.equal(h.values.get('readerExtendToStatusBar'), true);
    h.values.set('appThemeId', 'classic-blue');
    const back = await h.settings.switchThemeProfile({}, SCHEME_PROFILE, 'classic-blue');
    assert.equal(back.fontSize, 20);
    assert.equal(back.readerHeaderEnabled, false);
  },

  async 'saving the active scheme updates the live settings immediately'() {
    const h = harness();
    h.values.set('appThemeId', 'custom');
    h.values.set('activeCustomThemeSchemeId', 'custom_1');
    await h.settings.reload({});
    await h.settings.saveReadingInteractionSettings({}, true, 5, false);
    await h.settings.saveTypographyToProfile({}, SCHEME_PROFILE, typography(h));
    assert.equal(h.values.get('readerFontSize'), 26);
    assert.equal(h.values.get('readerFontWeight'), 550);
    assert.equal(h.values.get('readerHeaderEnabled'), true);
    assert.equal(h.values.get('readerFooterEnabled'), false);
    assert.equal(h.values.get('readerTitleFontSize'), 30);
    assert.equal(h.values.get('readerExtendToStatusBar'), true);
    const reloaded = await h.settings.reload({});
    assertTypography(reloaded);
    assert.equal(reloaded.volumeTurnPage, true, 'other interaction settings are kept');
    assert.equal(reloaded.screenTimeoutMinutes, 5);
    assert.equal(await h.settings.hasThemeTypography({}, SCHEME_PROFILE), true);
  },

  async 'deleting a scheme profile forgets its typography'() {
    const h = harness();
    await h.settings.saveTypographyToProfile({}, SCHEME_PROFILE, typography(h));
    await h.settings.deleteProfile({}, SCHEME_PROFILE);
    assert.equal(h.disk.has(`readerThemeProfileV1_${SCHEME_PROFILE}`), false);
    assert.equal(await h.settings.hasThemeTypography({}, SCHEME_PROFILE), false);
  },

  async 'builtin themes keep their own typography when switching back and forth'() {
    const h = harness();
    await h.settings.load({});
    await h.settings.saveLayoutSettings({}, 28, 18, 6);
    await h.settings.saveReaderChromeSettings({}, true, true, '');
    h.values.set('appThemeId', 'warm-paper');
    const fresh = await h.settings.switchThemeProfile({}, 'classic-blue', 'warm-paper');
    assert.equal(fresh.fontSize, 28, 'a theme used for the first time starts from the current typography');
    await h.settings.saveLayoutSettings({}, 18, 10, 0);
    await h.settings.saveReaderChromeSettings({}, false, true, '');
    h.values.set('appThemeId', 'classic-blue');
    const back = await h.settings.switchThemeProfile({}, 'warm-paper', 'classic-blue');
    assert.equal(back.fontSize, 28);
    assert.equal(back.lineHeight, 18);
    assert.equal(back.readerHeaderEnabled, true);
    h.values.set('appThemeId', 'warm-paper');
    const again = await h.settings.switchThemeProfile({}, 'classic-blue', 'warm-paper');
    assert.equal(again.fontSize, 18);
    assert.equal(again.readerHeaderEnabled, false);
  },

  async 'with typography not following the theme every theme shares the current typography'() {
    const h = harness();
    await h.settings.load({});
    const saved = typography(h);
    saved.fontSize = 30;
    saved.pageTurnMode = 0;
    h.disk.set('readerThemeProfileV1_warm-paper', JSON.stringify(saved));
    assert.equal(await h.settings.typographyFollowsTheme({}), true, 'follows by default');
    await h.settings.setTypographyFollowsTheme({}, false);
    assert.equal(h.values.get('readerTypographyFollowsTheme'), false);
    await h.settings.saveLayoutSettings({}, 24, 14, 2);
    h.values.set('appThemeId', 'warm-paper');
    const next = await h.settings.switchThemeProfile({}, 'classic-blue', 'warm-paper');
    assert.equal(next.fontSize, 24, 'current typography carried over');
    assert.equal(next.readerHeaderEnabled, false);
    assert.equal(next.pageTurnMode, 0, 'non-typography settings still come from the theme');

    await h.settings.setTypographyFollowsTheme({}, true);
    h.values.set('appThemeId', 'classic-blue');
    await h.settings.switchThemeProfile({}, 'warm-paper', 'classic-blue');
    h.values.set('appThemeId', 'warm-paper');
    assert.equal((await h.settings.switchThemeProfile({}, 'classic-blue', 'warm-paper')).fontSize, 24,
      'the shared typography was saved into the theme while it was in use');
  },

  async 'restoring the theme preset resets every typography field but keeps emphasis rules'() {
    const h = harness();
    await h.settings.load({});
    await h.settings.saveTypographyToProfile({}, 'classic-blue', typography(h));
    await h.settings.restoreThemePreset({}, 21, 14, 2, 22, 23, 24, 25, 1);
    const restored = await h.settings.reload({});
    const defaults = new h.ReaderSettings();
    assert.equal(restored.fontSize, 21);
    assert.equal(restored.lineHeight, 14);
    assert.equal(restored.paragraphSpacing, 2);
    assert.equal(restored.marginLeft, 22);
    assert.equal(restored.marginRight, 23);
    assert.equal(restored.marginTop, 24);
    assert.equal(restored.marginBottom, 25);
    assert.equal(restored.letterSpacing, 1);
    assert.equal(restored.fontWeight, defaults.fontWeight);
    assert.equal(restored.textAlign, defaults.textAlign);
    assert.equal(restored.paragraphIndent, defaults.paragraphIndent);
    assert.equal(restored.extendToStatusBar, false);
    assert.equal(restored.readerHeaderEnabled, defaults.readerHeaderEnabled);
    assert.equal(restored.readerFooterEnabled, defaults.readerFooterEnabled);
    assert.equal(restored.bodyFontMode, 'global');
    assert.equal(restored.titleFontSize, defaults.titleFontSize);
    assert.equal(restored.regexFontEnabled, true, 'emphasis rules are kept');
  },

  async 'copying typography from another theme applies it to the current theme'() {
    const h = harness();
    await h.settings.load({});
    h.disk.set('readerThemeProfileV1_warm-paper', JSON.stringify(typography(h)));
    await h.settings.copyTypographyFromProfile({}, 'warm-paper');
    assertTypography(await h.settings.reload({}));
    assert.equal(h.values.get('readerFontSize'), 26);
    assert.equal(JSON.parse(h.disk.get('readerThemeProfileV1_warm-paper')).fontSize, 26, 'source unchanged');
  },

  async 'every field the layout page saves travels in a theme package'() {
    // 主题排版页保存的字段（copyTypography 写的那些）里，除强调规则另走 emphasis 外都必须在 LAYOUT_KEYS 里，
    // 否则导出到别的设备后会丢。
    const source = read('utils/ReaderSettingsStore.ets').replace(/\r\n/g, '\n');
    const start = source.indexOf('  static copyTypography(');
    const body = source.slice(start, source.indexOf('\n  }\n', start));
    const copied = [...body.matchAll(/target\.(\w+) =/g)].map(match => match[1]);
    assert(copied.length >= 20, 'copyTypography fields found');
    const missing = copied.filter(key => !format.LAYOUT_KEYS.includes(key));
    assert.deepEqual(missing, [], `fields lost on export: ${missing.join(', ')}`);
    assert(body.includes('updateFontRules(target, source)'), 'regex rules are copied separately');

    const h = harness();
    const exported = format.pickLayout(JSON.parse(JSON.stringify(typography(h))));
    const target = JSON.parse(JSON.stringify(new h.ReaderSettings()));
    format.applyLayout(target, JSON.parse(JSON.stringify(exported)));
    assertTypography({ ...target, regexFontEnabled: true });
    assert.equal(target.pageTurnMode, new h.ReaderSettings().pageTurnMode, 'page turning does not travel');
    assert.equal(target.volumeTurnPage, false);
  },

  async 'font page draft only takes the fields it manages'() {
    const h = harness();
    const draft = typography(h);
    h.ThemeTypographyDraft.begin(draft);
    const revision = h.ThemeTypographyDraft.revision();
    const fontPage = new h.ReaderSettings();
    fontPage.fontSize = 18;
    fontPage.bodyFontMode = 'global';
    fontPage.titleFontSize = 24;
    fontPage.fontWeight = 350;
    fontPage.titleFontWeight = 750;
    fontPage.titleStyleRaw = JSON.stringify({ mode: 'position', position: '8', secondaryScale: 1.8 });
    fontPage.regexFontEnabled = false;
    fontPage.marginLeft = 0;
    h.ThemeTypographyDraft.applyFontStyle(fontPage);
    const current = h.ThemeTypographyDraft.current();
    assert.notEqual(h.ThemeTypographyDraft.revision(), revision);
    assert.equal(current.fontSize, 18);
    assert.equal(current.bodyFontMode, 'global');
    assert.equal(current.bodyFontFamily, '');
    assert.equal(current.titleFontSize, 24);
    assert.equal(current.fontWeight, 350);
    assert.equal(current.titleFontWeight, 750);
    assert.equal(JSON.parse(current.titleStyleRaw).position, '8');
    assert.equal(current.regexFontEnabled, false);
    assert.equal(current.marginLeft, 30, 'layout fields are not touched by the font page');
    h.ThemeTypographyDraft.end();
    assert.equal(h.ThemeTypographyDraft.current(), null);
  }
};

let failed = 0;
for (const [name, test] of Object.entries(tests)) {
  try {
    await test();
    console.log(`PASS: ${name}`);
  } catch (e) {
    failed++;
    console.error(`FAIL: ${name}`);
    console.error(e);
  }
}
if (failed > 0) process.exit(1);
