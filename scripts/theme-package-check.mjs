// 主题包（.qytheme）纯逻辑回归：ZIP 中央目录检查、清单与主题设置校验、付费部件替换、强调规则追加、字体重映射。
// node --experimental-strip-types scripts/theme-package-check.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import { projectRoot } from './lib/ets-module-staging.mjs';

const shareDir = path.join(projectRoot, 'entry', 'src', 'main', 'ets', 'theme', 'share');
const zip = await import(pathToFileURL(path.join(shareDir, 'ZipEntryInspector.ts')).href);
const format = await import(pathToFileURL(path.join(shareDir, 'ThemePackageFormat.ts')).href);

test('title layout JSON travels intact beyond the short-label limit', () => {
  const settings = {alignment:'right',marginTop:24,marginBottom:36,singlePage:true,mode:'regex',
    regex:'^第[零一二三四五六七八九十百千万0-9]+章[：: ]*',secondaryScale:1.5,lineGap:16,
    emphasis:{emphasisMode:'custom',customBubbleEnabled:true,bubbleStyleId:'capsule',customBubbleColor:'#80123456'}};
  const raw = JSON.stringify(settings);
  assert(raw.length > 200);
  const exported = format.pickLayout({titleStyleRaw:raw});
  assert.equal(exported.titleStyleRaw, raw);
  const target = {titleStyleRaw:''};
  format.applyLayout(target, exported);
  assert.deepEqual(JSON.parse(target.titleStyleRaw), settings);
  assert.equal('titleStyleRaw' in format.pickLayout({titleStyleRaw:'x'.repeat(8001)}), false,
    'oversized structured settings are skipped rather than truncated into invalid JSON');
});

/** 只写中央目录需要的字段，足够检查器使用；data 不压缩。 */
function makeZip(entries, { flags = 0x800, zip64 = false } = {}) {
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const entry of entries) {
    const name = Buffer.from(entry.name, 'utf8');
    const data = Buffer.from(entry.data ?? '');
    const size = entry.size ?? data.length;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(entry.flags ?? flags, 6);
    local.writeUInt32LE(size, 18);
    local.writeUInt32LE(size, 22);
    local.writeUInt16LE(name.length, 26);
    locals.push(local, name, data);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(entry.flags ?? flags, 8);
    central.writeUInt32LE(zip64 ? 0xFFFFFFFF : data.length, 20);
    central.writeUInt32LE(zip64 ? 0xFFFFFFFF : size, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt32LE(offset, 42);
    centrals.push(central, name);
    offset += 30 + name.length + data.length;
  }
  const directory = Buffer.concat(centrals);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(directory.length, 12);
  eocd.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, directory, eocd]);
}

function inspect(buffer, limits = {}) {
  const l = new zip.ZipInspectLimits();
  Object.assign(l, { maxEntries: 40, maxTotalUncompressed: 1000, maxEntryUncompressed: 500 }, limits);
  return zip.ZipEntryInspector.inspect(buffer.length,
    (offset, length) => new Uint8Array(buffer.subarray(offset, offset + length)), l);
}

test('reads entry names and sizes, finds the shared root folder', () => {
  const entries = inspect(makeZip([
    { name: 'theme/' }, { name: 'theme/manifest.json', data: '{}' }, { name: 'theme/assets/' },
    { name: 'theme/assets/中文.png', data: 'abc' }
  ]));
  assert.deepEqual(entries.map(e => [e.name, e.uncompressedSize, e.directory]), [
    ['theme/', 0, true], ['theme/manifest.json', 2, false], ['theme/assets/', 0, true],
    ['theme/assets/中文.png', 3, false]
  ]);
  assert.equal(zip.ZipEntryInspector.commonRoot(entries), 'theme/');
  assert.equal(zip.ZipEntryInspector.commonRoot(inspect(makeZip([{ name: 'manifest.json' }, { name: 'a/b' }]))), '');
});

test('rejects traversal, absolute, backslash and duplicate names', () => {
  for (const name of ['../evil.json', 'theme/../../x', '/abs/x', 'a\\b', 'C:/x', 'a//b', './a', 'a/\u0001']) {
    assert.throws(() => inspect(makeZip([{ name }])), /不安全/, name);
  }
  assert.throws(() => inspect(makeZip([{ name: 'a' }, { name: 'a' }])), /重复/);
});

test('enforces entry count, per-entry and total uncompressed limits', () => {
  assert.throws(() => inspect(makeZip(Array.from({ length: 41 }, (_, i) => ({ name: `f${i}` })))), /过多/);
  assert.throws(() => inspect(makeZip([{ name: 'big', size: 501 }])), /超出大小上限/);
  assert.throws(() => inspect(makeZip([{ name: 'a', size: 400 }, { name: 'b', size: 400 }, { name: 'c', size: 400 }])),
    /解压后超出/);
});

test('rejects encrypted, zip64 and non-zip input', () => {
  assert.throws(() => inspect(makeZip([{ name: 'a', flags: 0x801 }])), /加密/);
  assert.throws(() => inspect(makeZip([{ name: 'a' }], { zip64: true })), /超大/);
  assert.throws(() => inspect(Buffer.from('not a zip file at all, definitely not')), /不是有效/);
  assert.throws(() => inspect(Buffer.alloc(10)), /不是有效/);
});

const sha = (text) => createHash('sha256').update(text).digest('hex');

function manifest(overrides = {}) {
  const image = sha('image');
  return {
    format: 'qytheme', formatVersion: 1, packageId: 'abc', name: '夜读', author: '小明', exportedAt: 1,
    appVersion: '4.3', requires: ['custom-scheme-v1', 'reader-layout-v1'],
    assets: [{ id: image.substring(0, 24), path: `assets/${image.substring(0, 24)}.png`, kind: 'image', size: 10,
      sha256: image, name: '' }],
    ...overrides
  };
}

test('manifest validation: format, newer version, unknown features, asset rules', () => {
  const ok = format.decodeManifest(JSON.stringify(manifest()));
  assert.equal(ok.name, '夜读');
  assert.equal(ok.assets.length, 1);
  assert.throws(() => format.decodeManifest(JSON.stringify(manifest({ format: 'zip' }))), /不是轻页主题包/);
  assert.throws(() => format.decodeManifest(JSON.stringify(manifest({ formatVersion: 3 }))), /更新应用/);
  assert.throws(() => format.decodeManifest(JSON.stringify(manifest({ requires: ['custom-scheme-v1', 'tts-svg-v2'] }))),
    /不支持的功能/);
  assert.throws(() => format.decodeManifest(JSON.stringify(manifest({ requires: ['reader-layout-v1'] }))), /损坏/);
  const m = manifest();
  m.assets[0].path = 'assets/../../evil.png';
  assert.throws(() => format.decodeManifest(JSON.stringify(m)), /损坏/);
  const wrongKind = manifest();
  wrongKind.assets[0].kind = 'font';
  assert.throws(() => format.decodeManifest(JSON.stringify(wrongKind)), /损坏/);
  const tooBig = manifest();
  tooBig.assets[0].size = 21 * 1024 * 1024;
  assert.throws(() => format.decodeManifest(JSON.stringify(tooBig)), /大小上限/);
  const idMismatch = manifest();
  idMismatch.assets[0].sha256 = sha('other');
  assert.throws(() => format.decodeManifest(JSON.stringify(idMismatch)), /损坏/);
  const fontWithoutFeature = manifest();
  const font = sha('font');
  fontWithoutFeature.assets.push({ id: font.substring(0, 24), path: `assets/${font.substring(0, 24)}.ttf`, kind: 'font',
    size: 10, sha256: font });
  assert.throws(() => format.decodeManifest(JSON.stringify(fontWithoutFeature)), /损坏/);
  assert.throws(() => format.decodeManifest('[1,2]'), /损坏/);
  assert.throws(() => format.decodeManifest('{oops'), /损坏/);
});

test('author and name are cleaned for display', () => {
  assert.equal(format.sanitizeAuthor('  小\n明\u202E\u200B  '), '小 明');
  assert.equal(Array.from(format.sanitizeAuthor('作'.repeat(40))).length, 24);
  assert.equal(format.sanitizeAuthor('😀'.repeat(30)), '😀'.repeat(24));
  const m = format.decodeManifest(JSON.stringify(manifest({ author: 'a\u0000b', name: '' })));
  assert.equal(m.author, 'ab');
  assert.equal(m.name, '导入的主题');
  assert.equal(format.packageFileName('我的/主题:1'), '我的_主题_1.qytheme');
});

test('theme validation: asset references must exist, local paths are refused, layout keeps known keys', () => {
  const m = format.decodeManifest(JSON.stringify(manifest()));
  const imageRef = format.assetRef(m.assets[0].id);
  const theme = format.decodeTheme(JSON.stringify({
    settings: { customLightStartupImagePath: imageRef, customDarkStartupImagePath: 'builtin-key',
      customLightReaderBackgroundAssetId: 'paper-light' },
    layout: { fontSize: 22, paragraphIndent: 2, readerInfoBarConfig: '{"x":1}', tapZoneActions: '1,1', eyeTurnEnabled: true },
    fonts: [{ family: 'ReaderCustomFont_a_1', name: '霞鹜', assetId: '' }]
  }), m);
  const settings = JSON.parse(theme.settingsJson);
  assert.equal(settings.customLightStartupImagePath, imageRef);
  assert.equal(settings.customDarkStartupImagePath, '');
  assert.equal(settings.customLightReaderBackgroundAssetId, 'paper-light');
  assert.deepEqual(JSON.parse(theme.layoutJson), { fontSize: 22, paragraphIndent: 2, readerInfoBarConfig: '{"x":1}' });
  assert.equal(theme.fonts.length, 1);
  assert.throws(() => format.decodeTheme(JSON.stringify({ settings: {
    customLightReaderBackgroundAssetId: 'file:///data/storage/el2/base/files/reader_backgrounds/a.jpg' } }), m),
  /导出设备上的文件/);
  assert.throws(() => format.decodeTheme(JSON.stringify({ settings: {
    customLightStartupImagePath: format.assetRef('f'.repeat(24)) } }), m), /缺少图片/);
  assert.throws(() => format.decodeTheme(JSON.stringify({ settings: {}, emphasis: { rules: [] } }), m), /损坏/);
  assert.throws(() => format.decodeTheme(JSON.stringify({ settings: {}, fonts: [{ family: 'x', assetId: m.assets[0].id }] }), m),
    /缺少字体/);
});

test('encode/decode round trip keeps rules and fonts', () => {
  const m = format.decodeManifest(JSON.stringify(manifest({
    requires: ['custom-scheme-v1', 'reader-layout-v1', 'emphasis-rules-v3']
  })));
  const theme = new format.ThemePackageTheme();
  theme.settingsJson = JSON.stringify({ customBaseThemeId: 'plain-default' });
  theme.layoutJson = JSON.stringify({ fontSize: 19 });
  theme.emphasis = new format.ThemePackageEmphasis();
  theme.emphasis.enabled = true;
  theme.emphasis.rulesJson = JSON.stringify([{ id: 'r1', pattern: '“[^”]+”' }]);
  const back = format.decodeTheme(format.encodeTheme(theme), m);
  assert.equal(back.emphasis.enabled, true);
  assert.equal(JSON.parse(back.emphasis.rulesJson)[0].pattern, '“[^”]+”');
  assert.equal(JSON.parse(back.layoutJson).fontSize, 19);
});

test('sources from themes the importer cannot use are replaced and reported', () => {
  const settings = {
    customBaseThemeId: 'moon-crane',
    customLightSources: { paletteThemeId: 'moon-crane', bubbleThemeId: 'plain-default', readerThemeId: 'future-theme' },
    customDarkSources: { navigationThemeId: 'cat-pipi', layoutThemeId: 'plain-default' }
  };
  const owned = new Set(['plain-default', 'cat-pipi']);
  const known = new Set(['plain-default', 'cat-pipi', 'moon-crane']);
  const result = format.restrictSources(settings, id => owned.has(id), id => known.has(id),
    id => ({ 'moon-crane': '月鹤' })[id] || id, 'plain-default');
  assert.equal(settings.customBaseThemeId, 'plain-default');
  assert.equal(settings.customLightSources.paletteThemeId, 'plain-default');
  assert.equal(settings.customLightSources.readerThemeId, 'plain-default');
  assert.equal(settings.customDarkSources.navigationThemeId, 'cat-pipi');
  assert.deepEqual(result.replaced, ['浅色 · 完整配色（月鹤）']);
  assert.deepEqual(result.unknown, ['浅色 · 阅读背景']);
});

test('a base theme the importer does not own falls back instead of lending its assets', () => {
  const owned = new Set(['plain-default', 'cat-pipi']);
  const known = new Set(['plain-default', 'cat-pipi', 'obsidian-archive']);
  const restrict = (baseTheme) => {
    const manifest = new format.ThemePackageManifest();
    manifest.baseTheme = baseTheme;
    const result = format.restrictBaseTheme(manifest, id => owned.has(id), id => known.has(id),
      id => ({ 'obsidian-archive': '曜金藏书' })[id] || id, 'plain-default');
    return { base: manifest.baseTheme, replaced: result.replaced, unknown: result.unknown };
  };
  assert.deepEqual(restrict('obsidian-archive'),
    { base: 'plain-default', replaced: ['包里没设计的部件（基底主题：曜金藏书）'], unknown: [] });
  assert.deepEqual(restrict('cat-pipi'), { base: 'cat-pipi', replaced: [], unknown: [] });
  assert.deepEqual(restrict('future-theme'), { base: 'plain-default', replaced: [], unknown: ['包里没设计的部件（基底主题）'] });
  assert.deepEqual(restrict('pack:someone-else'), { base: 'plain-default', replaced: [], unknown: [] });
  assert.deepEqual(restrict(''), { base: 'plain-default', replaced: [], unknown: [] });
});

test('incoming emphasis rules are appended after existing ones, same patterns skipped', () => {
  const existing = JSON.stringify({ schemaVersion: 3, rules: [{ id: 'mine', pattern: '「[^」]+」', name: '我的' }] });
  const incoming = JSON.stringify([
    { id: 'mine', pattern: ' 「[^」]+」 ', name: '重复' },
    { id: 'theirs', pattern: '“[^”]+”', name: '对白', expanded: true },
    { id: 'x', pattern: '   ' }
  ]);
  const merged = format.mergeRules(existing, incoming, 42);
  const rules = JSON.parse(merged.rulesJson);
  assert.equal(merged.added, 1);
  assert.equal(merged.skipped, 2);
  assert.deepEqual(rules.map(r => [r.id, r.name]), [['mine', '我的'], ['rule_42_0', '对白']]);
  assert.equal(rules[1].expanded, false);
  assert.equal(format.mergeRules('', incoming, 1).added, 2);
});

test('font bindings move to the installed family or fall back to the global font', () => {
  const layout = { bodyFontMode: 'custom', bodyFontFamily: 'A', titleFontMode: 'custom', titleFontFamily: 'B' };
  const rules = [{ fontMode: 'custom', fontFamily: 'B' }, { fontMode: 'system', fontFamily: 'HarmonyOS Sans' }];
  const missing = format.remapFonts(layout, rules, new Map([['A', 'ReaderCustomFont_local_9']]),
    new Map([['B', '方正书宋']]));
  assert.deepEqual(layout, { bodyFontMode: 'custom', bodyFontFamily: 'ReaderCustomFont_local_9',
    titleFontMode: 'global', titleFontFamily: '' });
  assert.deepEqual(rules, [{ fontMode: 'global', fontFamily: '' }, { fontMode: 'system', fontFamily: 'HarmonyOS Sans' }]);
  assert.deepEqual(missing, ['方正书宋']);
});

test('layout apply only overwrites fields of the same type', () => {
  const target = { fontSize: 20, textAlign: 'justify', readerHeaderEnabled: false, pageTurnMode: 2 };
  format.applyLayout(target, { fontSize: 24, textAlign: 7, readerHeaderEnabled: true, pageTurnMode: 0 });
  assert.deepEqual(target, { fontSize: 24, textAlign: 'justify', readerHeaderEnabled: true, pageTurnMode: 2 });
});

test('asset sniffing recognises supported images and fonts only', () => {
  const bytes = (...values) => new Uint8Array(values);
  assert.equal(format.sniffAssetExtension(bytes(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)), 'png');
  assert.equal(format.sniffAssetExtension(bytes(0xFF, 0xD8, 0xFF, 0xE0)), 'jpg');
  assert.equal(format.sniffAssetExtension(new Uint8Array(Buffer.from('RIFF0000WEBPVP8 '))), 'webp');
  assert.equal(format.sniffAssetExtension(bytes(0x00, 0x01, 0x00, 0x00)), 'ttf');
  assert.equal(format.sniffAssetExtension(new Uint8Array(Buffer.from('OTTO'))), 'otf');
  assert.equal(format.sniffAssetExtension(new Uint8Array(Buffer.from('ttcf'))), 'ttc');
  assert.equal(format.sniffAssetExtension(new Uint8Array(Buffer.from('<svg xmlns='))), 'svg');
  assert.equal(format.sniffAssetExtension(new Uint8Array(Buffer.from('﻿<?xml version'))), 'svg');
  assert.equal(format.sniffAssetExtension(new Uint8Array(Buffer.from('plain text here'))), '');
  assert.equal(format.kindForExtension('svg'), 'vector');
});

// ---- 格式 2：手写主题包与包内部件 ----

const manifestV1 = manifest;

function manifestV2(overrides = {}) {
  return {
    format: 'qytheme', formatVersion: 2, packageId: 'night-garden', name: '夜花园', author: '小明',
    version: '1.0', description: '深蓝夜色', baseTheme: 'plain-default',
    requires: ['custom-scheme-v1', 'reader-layout-v1', 'theme-parts-v1'],
    ...overrides
  };
}

/** 模拟导入方枚举 assets/ 后补全的清单：路径、类型和内容 ID 都已就位。 */
function withAssets(manifest, files) {
  const result = format.decodeManifest(JSON.stringify(manifest));
  for (const [path, kind] of files) {
    const asset = new format.ThemePackageAsset();
    asset.path = path;
    asset.kind = kind;
    asset.sha256 = sha(path);
    asset.id = asset.sha256.substring(0, 24);
    asset.size = 10;
    result.assets.push(asset);
  }
  return result;
}

test('v2 manifest: assets optional, packageId charset, credits and description kept', () => {
  const m = format.decodeManifest(JSON.stringify(manifestV2()));
  assert.equal(m.formatVersion, 2);
  assert.equal(m.assetsDeclared, false);
  assert.equal(m.version, '1.0');
  assert.equal(m.baseTheme, 'plain-default');
  assert.throws(() => format.decodeManifest(JSON.stringify(manifestV2({ packageId: '../x' }))), /packageId/);
  assert.throws(() => format.decodeManifest(JSON.stringify(manifestV2({ packageId: 'a b' }))), /packageId/);
  const credits = format.decodeManifest(JSON.stringify(manifestV2({
    credits: { packageId: 'orig', name: '原主题', author: '原作者\n' } })));
  assert.deepEqual({ ...credits.credits }, { packageId: 'orig', name: '原主题', author: '原作者' });
  // 声明了素材时按路径登记，大小与摘要可省略，ID 由导入方生成。
  const declared = format.decodeManifest(JSON.stringify(manifestV2({ assets: [{ path: 'assets/cover_01.jpg' }] })));
  assert.equal(declared.assetsDeclared, true);
  assert.equal(declared.assets[0].kind, 'image');
  assert.equal(declared.assets[0].id, '');
  assert.throws(() => format.decodeManifest(JSON.stringify(manifestV2({ assets: [{ path: 'assets/../x.png' }] }))), /不合法/);
  assert.throws(() => format.decodeManifest(JSON.stringify(manifestV2({ assets: [{ path: 'assets/a.exe' }] }))), /不合法/);
  assert.throws(() => format.decodeManifest(JSON.stringify(manifestV2({ assets: [{ path: 'assets/a.png', kind: 'font' }] }))), /损坏/);
  assert.throws(() => format.decodeManifest(JSON.stringify(manifestV2({ assets: [{ path: 'assets/f.ttf' }] }))), /损坏/,
    'fonts need the fonts-v1 feature');
  assert.equal(format.assetPathExtension('assets/Cover_01.jpeg'), 'jpg');
  assert.equal(format.assetPathExtension('assets/sub/a.png'), '');
});

test('pack theme ids: prefix, suffix and reader background keys', () => {
  assert.equal(format.packThemeId('night-garden'), 'pack:night-garden');
  assert.equal(format.isPackThemeId('pack:night-garden'), true);
  assert.equal(format.isPackThemeId('pack:night-garden:dark'), true);
  assert.equal(format.isPackThemeId('pack:'), false);
  assert.equal(format.isPackThemeId('pack:../x'), false);
  assert.equal(format.isPackThemeId('plain-default'), false);
  assert.equal(format.packageIdOfThemeId('pack:night-garden:light'), 'night-garden');
  assert.equal(format.packageIdOfThemeId('classic-blue'), '');
  assert.equal(format.packReaderBackgroundId('night-garden', true), 'pack:night-garden:dark');
});

test('svg safety: self-contained files only', () => {
  assert.equal(format.checkSvgSource('<svg viewBox="0 0 24 24"><path d="M0 0h24v24z"/></svg>'), '');
  assert.match(format.checkSvgSource('<svg><script>alert(1)</script></svg>'), /script/);
  assert.match(format.checkSvgSource('<svg><image href="http://x/y.png"/></svg>'), /image/);
  assert.match(format.checkSvgSource('<svg style="background:url(http://x)"/>'), /url\(/);
  assert.match(format.checkSvgSource('<svg><use xlink:href="#a"/></svg>'), /use/);
  assert.match(format.checkSvgSource('just text'), /不是 SVG/);
});

const PARTS_FILES = [
  ['assets/nav_bookshelf.svg', 'vector'], ['assets/nav_explore.svg', 'vector'], ['assets/nav_search.svg', 'vector'],
  ['assets/nav_mine.svg', 'vector'], ['assets/cover_01.jpg', 'image'], ['assets/cover_02.jpg', 'image'],
  ['assets/frame.svg', 'vector'], ['assets/folder.jpg', 'image'], ['assets/startup.jpg', 'image'],
  ['assets/tts_light.svg', 'vector'], ['assets/reader_tl.svg', 'vector'], ['assets/reader_br.svg', 'vector'],
  ['assets/reader_dark.jpg', 'image'], ['assets/cap.svg', 'vector'], ['assets/logo.svg', 'vector']
];

function partsJson() {
  return {
    light: {
      colors: { pageColor: '#f5f5f5', accentColor: '#3366CC' },
      reader: { backgroundColor: '#FFF8EE', textColor: '#30261D', contentTone: 'light',
        backgroundMode: 'ornaments', leading: 'assets/reader_tl.svg', trailing: 'assets/reader_br.svg' },
      emphasis: { mode: 'bubble', color: '#80336699', textColor: '#102030' }
    },
    dark: {
      colors: { pageColor: '#101418' },
      reader: { backgroundColor: '#101418', textColor: '#D0D4D8', contentTone: 'dark',
        backgroundMode: 'image', image: 'assets/reader_dark.jpg', imageFit: 'contain' }
    },
    ttsPanel: { light: { artwork: 'assets/tts_light.svg', skyColor: '#DCEBFF', surfaceColor: '#F5F7FA', glowColor: '#26007DFF' } },
    navigation: { bookshelf: 'assets/nav_bookshelf.svg', explore: 'assets/nav_explore.svg',
      search: 'assets/nav_search.svg', mine: 'assets/nav_mine.svg' },
    book: { covers: ['assets/cover_01.jpg', 'assets/cover_02.jpg'], shelfFrame: 'assets/frame.svg', shelfFolder: 'assets/folder.jpg' },
    startup: { light: { image: 'assets/startup.jpg', title: '夜花园', subtitle: '月下翻页' } },
    bubble: { cap: 'assets/cap.svg' },
    logo: 'assets/logo.svg',
    radius: { card: 14, button: 22 },
    // 磨砂参数不再是部件；多出来的键被忽略。
    glass: { enabled: true, lightTintOpacity: 80 }
  };
}

test('v2 theme: parts resolve by path, settings optional, kinds and required fields enforced', () => {
  const manifest = withAssets(manifestV2(), PARTS_FILES);
  const theme = format.decodeTheme(JSON.stringify({ parts: partsJson() }), manifest);
  assert.equal(theme.settingsJson, '');
  const parts = theme.parts;
  assert.equal(parts.light.colors.pageColor, '#F5F5F5');
  assert.equal(parts.light.reader.backgroundMode, 'ornaments');
  assert.match(parts.light.reader.leading, /^qytheme-asset:[0-9a-f]{24}$/);
  assert.equal(parts.dark.reader.backgroundMode, 'image');
  assert.equal(parts.dark.reader.imageFit, 'contain');
  assert.equal(parts.book.covers.length, 2);
  assert.equal(parts.startupLight.title, '夜花园');
  assert.equal(parts.startupDark, null);
  assert.equal(parts.ttsPanelDark, null);
  assert.deepEqual(parts.radius, { card: 14, button: 22 });
  assert.equal(format.partsAssetRefs(parts).length, PARTS_FILES.length);
  assert.deepEqual(format.describeParts(parts), ['浅色与深色配色', '阅读背景（角饰、整图）', '朗读/有声书面板插画',
    '导航图标', '封面 2 张、书架边框、文件夹插画', '启动封面', '强调气泡端饰', '主题标识', '圆角']);

  const broken = (mutate, pattern) => {
    const json = partsJson();
    mutate(json);
    assert.throws(() => format.decodeTheme(JSON.stringify({ parts: json }), manifest), pattern);
  };
  broken(j => { delete j.navigation.mine; }, /bookshelf、explore、mine 三个图标/);
  // 底栏没有搜索页签了：不带 search 的包照样能读，导出时用发现的图标补上给旧版本应用。
  const withoutSearch = partsJson();
  delete withoutSearch.navigation.search;
  const decodedWithoutSearch = format.decodeTheme(JSON.stringify({ parts: withoutSearch }), manifest).parts;
  assert.equal(decodedWithoutSearch.navigation.search, '');
  const encodedNavigation = format.encodeParts(decodedWithoutSearch).navigation;
  assert.equal(encodedNavigation.search, decodedWithoutSearch.navigation.explore);
  // 第四个页签“听”“足迹”的图标可选：带了就读进来并算进素材，没带照样能读。
  const withExtraTabs = partsJson();
  withExtraTabs.navigation.listen = 'assets/nav_search.svg';
  withExtraTabs.navigation.footprintSelected = 'assets/nav_mine.svg';
  const decodedExtra = format.decodeTheme(JSON.stringify({ parts: withExtraTabs }), manifest).parts;
  assert.match(decodedExtra.navigation.listen, /^qytheme-asset:[0-9a-f]{24}$/);
  assert.equal(decodedExtra.navigation.footprint, '');
  assert.equal(format.encodeParts(decodedExtra).navigation.listen, decodedExtra.navigation.listen);
  assert.equal(decodedWithoutSearch.navigation.listen, '');
  broken(j => { j.light.colors.pageColor = 'red'; }, /颜色/);
  broken(j => { j.light.reader.trailing = ''; }, /leading 和 trailing/);
  broken(j => { j.ttsPanel.light.glowColor = ''; }, /artwork、skyColor/);
  broken(j => { j.radius.card = 99; }, /0 到 48/);
  broken(j => { j.book.covers = Array(9).fill('assets/cover_01.jpg'); }, /最多 8 张/);
  broken(j => { j.logo = 'assets/missing.svg'; }, /不存在/);
  broken(j => { j.bubble = { frame: 'assets/frame.svg' }; }, /需要 cap/);
  // 没有 parts 也没有 settings 不行；parts 需要清单声明 theme-parts-v1。
  assert.throws(() => format.decodeTheme(JSON.stringify({}), manifest), /主题设置已损坏/);
  const noFeature = withAssets(manifestV2({ requires: ['custom-scheme-v1', 'reader-layout-v1'] }), PARTS_FILES);
  assert.throws(() => format.decodeTheme(JSON.stringify({ parts: partsJson() }), noFeature), /清单已损坏/);
});

test('v2 theme: pack:self in settings becomes the installed pack id; export reverses it', () => {
  const manifest = withAssets(manifestV2(), PARTS_FILES);
  const settings = {
    customBaseThemeId: 'pack:self',
    customLightSources: { paletteThemeId: 'pack:self', bookThemeId: 'classic-blue' },
    customDarkSources: { readerThemeId: 'pack:self' },
    customLightReaderBackgroundAssetId: 'pack:self:light',
    customDarkReaderBackgroundAssetId: 'paper-dark'
  };
  const theme = format.decodeTheme(JSON.stringify({ parts: partsJson(), settings }), manifest);
  const decoded = JSON.parse(theme.settingsJson);
  assert.equal(decoded.customBaseThemeId, 'pack:night-garden');
  assert.equal(decoded.customLightSources.paletteThemeId, 'pack:night-garden');
  assert.equal(decoded.customLightSources.bookThemeId, 'classic-blue');
  assert.equal(decoded.customDarkSources.readerThemeId, 'pack:night-garden');
  assert.equal(decoded.customLightReaderBackgroundAssetId, 'pack:night-garden:light');
  assert.equal(decoded.customDarkReaderBackgroundAssetId, 'paper-dark');
  format.replaceOwnPackIdWithSelf(decoded, 'pack:night-garden');
  assert.equal(decoded.customBaseThemeId, 'pack:self');
  assert.equal(decoded.customLightReaderBackgroundAssetId, 'pack:self:light');
  // 方案的强调覆盖指向包内气泡时同样走 pack:self。
  const withBubble = { customDarkEmphasis: { bubbleStyle: 'pack:self' } };
  const bubbleTheme = format.decodeTheme(JSON.stringify({ parts: partsJson(), settings: withBubble }), manifest);
  const bubbleDecoded = JSON.parse(bubbleTheme.settingsJson);
  assert.equal(bubbleDecoded.customDarkEmphasis.bubbleStyle, 'pack:night-garden');
  format.replaceOwnPackIdWithSelf(bubbleDecoded, 'pack:night-garden');
  assert.equal(bubbleDecoded.customDarkEmphasis.bubbleStyle, 'pack:self');
  // 没有 parts 的包里 pack:self 不替换，交给来源限制当作未知主题处理。
  const plain = format.decodeTheme(JSON.stringify({ settings: { customBaseThemeId: 'pack:self' } }), manifest);
  assert.equal(JSON.parse(plain.settingsJson).customBaseThemeId, 'pack:self');
  const restricted = JSON.parse(plain.settingsJson);
  const result = format.restrictSources(restricted, () => true, id => id !== 'pack:self', () => '', 'plain-default');
  assert.equal(restricted.customBaseThemeId, 'plain-default');
  assert.deepEqual(result.unknown, []);
});

test('v2 theme: parts survive an encode/decode round trip and ref mapping', () => {
  const manifest = withAssets(manifestV2(), PARTS_FILES);
  const theme = format.decodeTheme(JSON.stringify({ parts: partsJson() }), manifest);
  const byPath = format.mapPartsAssetRefs(theme.parts, ref => format.findAsset(manifest, format.assetIdFromRef(ref)).path);
  assert.equal(byPath.navigation.mine, 'assets/nav_mine.svg');
  assert.equal(byPath.book.covers[1], 'assets/cover_02.jpg');
  assert.equal(theme.parts.navigation.mine.startsWith('qytheme-asset:'), true, 'mapping returns a copy');
  const exported = new format.ThemePackageTheme();
  exported.parts = byPath;
  const again = format.decodeTheme(format.encodeTheme(exported), manifest);
  assert.deepEqual(again.parts, theme.parts);
  // 格式 1 的包不认路径引用。
  const v1 = format.decodeManifest(JSON.stringify(manifestV1()));
  assert.equal(format.resolveAssetRef(v1, 'assets/x.png'), null);
});

test('scheme overrides travel in settings and are gated by scheme-overrides-v1', () => {
  assert.equal(format.ThemePackageFeatures.KNOWN.includes('scheme-overrides-v1'), true);
  const m = format.decodeManifest(JSON.stringify(manifestV1({ requires: ['custom-scheme-v1', 'scheme-overrides-v1'] })));
  const settings = { customLightPalette: { pageColor: '#F1F7F3' }, customDarkEmphasis: { mode: 'bubble', bubbleStyle: 'moon-halo' } };
  const theme = format.decodeTheme(JSON.stringify({ settings }), m);
  const decoded = JSON.parse(theme.settingsJson);
  assert.equal(decoded.customLightPalette.pageColor, '#F1F7F3');
  assert.equal(decoded.customDarkEmphasis.bubbleStyle, 'moon-halo');
});
