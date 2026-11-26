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
  tooBig.assets[0].size = 26 * 1024 * 1024;
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
  // 没写 baseRevision 是素笺之前的包（导入时按原默认主题打底）；写了就原样往返。
  assert.equal(m.baseRevision, 0);
  const revised = format.decodeManifest(JSON.stringify(manifestV2({ baseRevision: 2 })));
  assert.equal(revised.baseRevision, 2);
  assert.equal(format.decodeManifest(format.encodeManifest(revised)).baseRevision, 2);
  assert.equal(format.decodeManifest(JSON.stringify(manifestV2({ baseRevision: '2' }))).baseRevision, 0);
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
  // 素材最多 128 个；超过老版本的 64 个要声明 assets-128-v1，老版本不认得这个功能会提示先更新。
  const manyAssets = (count) => Array.from({ length: count }, (_, i) => ({ path: `assets/a${i}.png` }));
  const v2Base = manifestV2().requires;
  assert.equal(format.decodeManifest(JSON.stringify(manifestV2({ assets: manyAssets(64) }))).assets.length, 64);
  assert.throws(() => format.decodeManifest(JSON.stringify(manifestV2({ assets: manyAssets(65) }))), /assets-128-v1/);
  const v2Many = manifestV2({ requires: [...v2Base, 'assets-128-v1'], assets: manyAssets(128) });
  assert.equal(format.decodeManifest(JSON.stringify(v2Many)).assets.length, 128);
  assert.throws(() => format.decodeManifest(JSON.stringify(manifestV2({ requires: [...v2Base, 'assets-128-v1'],
    assets: manyAssets(129) }))), /数量超出上限/);
  assert.equal(format.ThemePackageLimits.MAX_ASSETS, 128);
  assert.equal(format.ThemePackageFeatures.KNOWN.includes('assets-128-v1'), true);
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
  broken(j => { j.light.reader.trailing = ''; j.light.reader.leading = ''; }, /至少要有 leading 或 trailing/);
  // 只有一张角饰要声明 reader-single-corner-v1，老版本不认得这个功能会提示先更新。
  broken(j => { j.light.reader.trailing = ''; }, /reader-single-corner-v1/);
  const singleManifest = withAssets(manifestV2({ requires: ['custom-scheme-v1', 'reader-layout-v1', 'theme-parts-v1',
    'reader-single-corner-v1'] }), PARTS_FILES);
  const onlyTrailing = partsJson();
  onlyTrailing.light.reader.leading = '';
  onlyTrailing.light.reader.trailingScale = 1.5;
  onlyTrailing.light.reader.leadingScale = 0.7;
  onlyTrailing.light.reader.trailingInset = 0;
  const decodedSingle = format.decodeTheme(JSON.stringify({ parts: onlyTrailing }), singleManifest).parts;
  assert.equal(decodedSingle.light.reader.leading, '');
  assert.match(decodedSingle.light.reader.trailing, /^qytheme-asset:[0-9a-f]{24}$/);
  assert.equal(decodedSingle.light.reader.trailingScale, 1.5);
  assert.equal(decodedSingle.light.reader.leadingScale, 0.7);
  assert.equal(format.partsUseSingleCorner(decodedSingle), true);
  assert.equal(format.partsUseSingleCorner(parts), false);
  // 两角大小缺省按 1，超出范围夹到 0.5–2。
  assert.equal(parts.light.reader.leadingScale, 1);
  assert.equal(parts.light.reader.trailingScale, 1);
  assert.equal(format.normalizeOrnamentScale(9), 2);
  assert.equal(format.normalizeOrnamentScale(0.1), 0.5);
  assert.equal(format.normalizeOrnamentScale(undefined), 1);
  // 两角边距缺省按 1，0 是贴边要保留，超出范围夹到 0–3。
  assert.equal(decodedSingle.light.reader.trailingInset, 0);
  assert.equal(decodedSingle.light.reader.leadingInset, 1);
  assert.equal(parts.light.reader.leadingInset, 1);
  assert.equal(format.normalizeOrnamentInset(0), 0);
  assert.equal(format.normalizeOrnamentInset(9), 3);
  assert.equal(format.normalizeOrnamentInset(-1), 0);
  assert.equal(format.normalizeOrnamentInset(undefined), 1);
  broken(j => { j.ttsPanel.light.glowColor = ''; }, /artwork、skyColor/);
  broken(j => { j.radius.card = 99; }, /0 到 48/);
  broken(j => { j.book.covers = Array(17).fill('assets/cover_01.jpg'); }, /最多 16 张/);
  // 超过老版本的 8 张要声明 book-covers-16-v1，老版本不认得这个功能会提示先更新。
  broken(j => { j.book.covers = Array(9).fill('assets/cover_01.jpg'); }, /book-covers-16-v1/);
  const manyCoversManifest = withAssets(manifestV2({ requires: ['custom-scheme-v1', 'theme-parts-v1', 'book-covers-16-v1'] }), PARTS_FILES);
  const manyCovers = partsJson();
  manyCovers.book.covers = Array(16).fill('assets/cover_01.jpg');
  const decodedManyCovers = format.decodeTheme(JSON.stringify({ parts: manyCovers }), manyCoversManifest).parts;
  assert.equal(decodedManyCovers.book.covers.length, 16);
  assert.equal(format.partsUseManyCovers(decodedManyCovers), true);
  assert.equal(format.partsUseManyCovers(parts), false);
  // 深色那套老版本不读：超过 8 张不用声明；只有深色那套时它会写成 covers，要声明。
  const manyDark = partsJson();
  manyDark.book.coversDark = Array(16).fill('assets/cover_02.jpg');
  const decodedManyDark = format.decodeTheme(JSON.stringify({ parts: manyDark }), manifest).parts;
  assert.equal(format.partsUseManyCovers(decodedManyDark), false);
  decodedManyDark.book.covers = [];
  assert.equal(format.partsUseManyCovers(decodedManyDark), true);
  assert.equal(format.ThemePackageLimits.MAX_COVERS, 16);
  assert.equal(format.ThemePackageFeatures.KNOWN.includes('book-covers-16-v1'), true);
  broken(j => { j.logo = 'assets/missing.svg'; }, /不存在/);
  broken(j => { j.bubble = { frame: 'assets/frame.svg' }; }, /需要 cap/);
  // 位图边框、只有边框没有端饰都要声明 bubble-frame-v1；拉伸设置原样读写，越界的夹住、不认得的丢掉。
  broken(j => { j.bubble = { cap: 'assets/cap.svg', frame: 'assets/cover_01.jpg' }; }, /需要SVG/);
  const frameManifest = withAssets(manifestV2({ requires: ['custom-scheme-v1', 'reader-layout-v1', 'theme-parts-v1',
    'bubble-frame-v1'] }), PARTS_FILES);
  const frameOnly = partsJson();
  frameOnly.bubble = { frame: 'assets/cover_01.jpg', frameSlice: { left: 0.2, right: 0.9, top: 0.1, bottom: -1 },
    frameRepeat: 'round', frameBreak: 'zigzag', frameTint: true };
  const decodedFrame = format.decodeTheme(JSON.stringify({ parts: frameOnly }), frameManifest).parts;
  assert.equal(decodedFrame.bubble.cap, '');
  assert.match(decodedFrame.bubble.frame, /^qytheme-asset:[0-9a-f]{24}$/);
  assert.deepEqual({ ...decodedFrame.bubble.frameSlice }, { left: 0.2, right: 0.49, top: 0.1, bottom: 0 });
  assert.equal(decodedFrame.bubble.frameRepeat, 'round');
  assert.equal(decodedFrame.bubble.frameBreak, '');
  assert.equal(decodedFrame.bubble.frameTint, true);
  assert.deepEqual(Object.keys(format.encodeParts(decodedFrame).bubble).sort(),
    ['frame', 'frameRepeat', 'frameSlice', 'frameTint']);
  assert.deepEqual(format.encodeParts(parts).bubble, { cap: parts.bubble.cap }, '没有边框时不写拉伸设置');
  assert.equal(format.describeParts(decodedFrame).includes('强调气泡边框'), true);
  broken(j => { j.bubble = {}; }, /需要 cap/);
  assert.throws(() => format.decodeTheme(JSON.stringify({ parts: { ...partsJson(), bubble: {} } }), frameManifest),
    /至少要有 cap 或 frame/);
  const usesFrame = bubble => format.partsUseBubbleFrameFeature({ bubble });
  assert.equal(usesFrame({ cap: 'assets/c.svg', frame: 'assets/f.svg' }), false);
  assert.equal(usesFrame({ cap: 'assets/c.svg', frame: 'assets/f.png' }), true);
  assert.equal(usesFrame({ cap: '', frame: 'assets/f.svg' }), true);
  assert.equal(usesFrame({ cap: 'assets/c.svg', frame: '' }), false);
  assert.equal(format.ThemePackageFeatures.KNOWN.includes('bubble-frame-v1'), true);
  // 端饰、书架边框用位图（深色那张也算）要声明 bitmap-cap-shelf-frame-v1，没声明时只收 SVG。
  broken(j => { j.bubble = { cap: 'assets/cover_01.jpg' }; }, /需要SVG/);
  broken(j => { j.book.shelfFrame = 'assets/cover_01.jpg'; }, /需要SVG/);
  broken(j => { j.book.shelfFrameDark = 'assets/cover_01.jpg'; }, /需要SVG/);
  const bitmapManifest = withAssets(manifestV2({ requires: ['custom-scheme-v1', 'reader-layout-v1', 'theme-parts-v1',
    'bitmap-cap-shelf-frame-v1'] }), PARTS_FILES);
  const bitmapParts = partsJson();
  bitmapParts.bubble = { cap: 'assets/cover_01.jpg' };
  bitmapParts.book.shelfFrame = 'assets/cover_02.jpg';
  const decodedBitmap = format.decodeTheme(JSON.stringify({ parts: bitmapParts }), bitmapManifest).parts;
  assert.match(decodedBitmap.bubble.cap, /^qytheme-asset:[0-9a-f]{24}$/);
  assert.match(decodedBitmap.book.shelfFrame, /^qytheme-asset:[0-9a-f]{24}$/);
  const usesBitmap = value => format.partsUseBitmapCapOrShelfFrame(value);
  assert.equal(usesBitmap(parts), false);
  assert.equal(usesBitmap({ bubble: { cap: 'assets/c.svg', frame: 'assets/f.png' } }), false);
  assert.equal(usesBitmap({ bubble: { cap: 'assets/c.png' } }), true);
  assert.equal(usesBitmap({ bubble: { cap: 'assets/c.svg' }, bubbleDark: { cap: 'assets/c.webp' } }), true);
  assert.equal(usesBitmap({ book: { shelfFrame: 'assets/f.svg' } }), false);
  assert.equal(usesBitmap({ book: { shelfFrame: 'assets/f.svg', shelfFrameDark: 'assets/f.gif' } }), true);
  assert.equal(format.ThemePackageFeatures.KNOWN.includes('bitmap-cap-shelf-frame-v1'), true);
  // 默认拉伸线：上下贴边，左右各留图高 × 0.6、最多 30%。
  assert.deepEqual({ ...format.defaultBubbleFrameSlice(3.75) }, { left: 0.16, right: 0.16, top: 0, bottom: 0 });
  assert.deepEqual({ ...format.defaultBubbleFrameSlice(1) }, { left: 0.3, right: 0.3, top: 0, bottom: 0 });
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

test('v2 theme: dark covers are optional, fall back both ways and stay readable by older apps', () => {
  const manifest = withAssets(manifestV2(), PARTS_FILES);
  const decode = json => format.decodeTheme(JSON.stringify({ parts: json }), manifest).parts;
  const byPath = parts => format.mapPartsAssetRefs(parts, ref => format.findAsset(manifest, format.assetIdFromRef(ref)).path);
  const area = image => ({ image, x: 10, y: 20, width: 300, height: 440, imageWidth: 450, imageHeight: 660 });

  // 老主题包没有深色封面：两种模式都是 covers，导出也不多出字段。
  const legacy = decode(partsJson());
  assert.deepEqual(legacy.book.coversDark, []);
  assert.deepEqual(format.bookCoversFor(legacy.book, true), legacy.book.covers);
  assert.equal('coversDark' in format.encodeParts(legacy).book, false);
  // 本机旧记录连字段都没有。
  assert.deepEqual(format.bookCoversFor({ covers: ['a'] }, true), ['a']);
  assert.deepEqual(format.partsAssetRefs({ book: { covers: ['a'], shelfFrame: '', shelfFolder: '' } }), ['a']);

  const json = partsJson();
  json.book.coversDark = ['assets/folder.jpg', 'assets/cover_02.jpg'];
  json.book.coverCrops = [area('assets/cover_02.jpg')];
  json.book.coverCropsDark = [area('assets/folder.jpg'), area('assets/startup.jpg')];
  const parts = decode(json);
  const paths = byPath(parts);
  assert.deepEqual(format.bookCoversFor(paths.book, false), ['assets/cover_01.jpg', 'assets/cover_02.jpg']);
  assert.deepEqual(format.bookCoversFor(paths.book, true), ['assets/folder.jpg', 'assets/cover_02.jpg']);
  assert.deepEqual(paths.book.coverCrops, [area('assets/cover_02.jpg')]);
  assert.deepEqual(paths.book.coverCropsDark, [area('assets/folder.jpg')], 'areas of images outside coversDark are dropped');
  assert.deepEqual(format.describeParts(parts)[4], '封面 浅色 2 张、深色 2 张、书架边框、文件夹插画');
  const exported = new format.ThemePackageTheme();
  exported.parts = paths;
  assert.deepEqual(format.decodeTheme(format.encodeTheme(exported), manifest).parts, parts);
  const encoded = format.encodeParts(paths).book;
  assert.deepEqual(encoded.covers, ['assets/cover_01.jpg', 'assets/cover_02.jpg'], 'older apps keep reading covers');
  assert.deepEqual(encoded.coversDark, ['assets/folder.jpg', 'assets/cover_02.jpg']);

  // 只有深色封面：浅色借用它；导出时写成 covers，旧版本应用也认得。
  const onlyDark = partsJson();
  onlyDark.book.coversDark = onlyDark.book.covers;
  onlyDark.book.coverCropsDark = [area('assets/cover_01.jpg')];
  onlyDark.book.covers = [];
  const dark = byPath(decode(onlyDark));
  assert.deepEqual(format.bookCoversFor(dark.book, false), ['assets/cover_01.jpg', 'assets/cover_02.jpg']);
  assert.equal(format.bookHasNoCovers(dark.book), false);
  const encodedDark = format.encodeParts(dark).book;
  assert.deepEqual(encodedDark.covers, ['assets/cover_01.jpg', 'assets/cover_02.jpg']);
  assert.equal('coversDark' in encodedDark, false);
  assert.deepEqual(encodedDark.coverCrops, [area('assets/cover_01.jpg')]);
  // 只剩深色封面的 book 不算空。
  const bare = { coversDark: ['assets/cover_01.jpg'] };
  assert.equal(decode({ book: bare, logo: 'assets/logo.svg' }).book.coversDark.length, 1);

  const bad = partsJson();
  bad.book.coversDark = Array(17).fill('assets/cover_01.jpg');
  assert.throws(() => decode(bad), /coversDark 最多 16 张/);
});

test('v2 theme: the dark folder illustration follows the same rules as dark covers', () => {
  const manifest = withAssets(manifestV2(), PARTS_FILES);
  const decode = json => format.decodeTheme(JSON.stringify({ parts: json }), manifest).parts;
  const byPath = parts => format.mapPartsAssetRefs(parts, ref => format.findAsset(manifest, format.assetIdFromRef(ref)).path);
  const area = image => ({ image, x: 10, y: 20, width: 300, height: 440, imageWidth: 450, imageHeight: 660 });

  // 老主题包：深色沿用 shelfFolder，导出不多出字段；本机旧记录没有这个字段。
  const legacy = byPath(decode(partsJson()));
  assert.equal(legacy.book.shelfFolderDark, '');
  assert.equal(format.bookFolderFor(legacy.book, true), 'assets/folder.jpg');
  assert.equal('shelfFolderDark' in format.encodeParts(legacy).book, false);
  assert.equal(format.bookFolderFor({ covers: [], shelfFolder: 'a' }, true), 'a');

  const json = partsJson();
  json.book.shelfFolderDark = 'assets/startup.jpg';
  json.book.shelfFolderCrop = area('assets/folder.jpg');
  json.book.shelfFolderCropDark = area('assets/startup.jpg');
  const parts = decode(json);
  const paths = byPath(parts);
  assert.equal(format.bookFolderFor(paths.book, false), 'assets/folder.jpg');
  assert.equal(format.bookFolderFor(paths.book, true), 'assets/startup.jpg');
  assert.deepEqual(paths.book.shelfFolderCropDark, area('assets/startup.jpg'));
  assert.equal(format.describeParts(parts)[4], '封面 2 张、书架边框、文件夹插画（浅色、深色）');
  const exported = new format.ThemePackageTheme();
  exported.parts = paths;
  assert.deepEqual(format.decodeTheme(format.encodeTheme(exported), manifest).parts, parts);
  const encoded = format.encodeParts(paths).book;
  assert.equal(encoded.shelfFolder, 'assets/folder.jpg', 'older apps keep reading shelfFolder');
  assert.equal(encoded.shelfFolderDark, 'assets/startup.jpg');
  assert.deepEqual(encoded.shelfFolderCropDark, area('assets/startup.jpg'));
  // 区域记的不是深色那张图：读包时丢掉。
  const stale = partsJson();
  stale.book.shelfFolderDark = 'assets/startup.jpg';
  stale.book.shelfFolderCropDark = area('assets/folder.jpg');
  assert.equal(decode(stale).book.shelfFolderCropDark, null);

  // 只有深色那张：浅色借用它，导出时写成 shelfFolder；只带这一张的 book 不算空。
  const onlyDark = { book: { shelfFolderDark: 'assets/folder.jpg', shelfFolderCropDark: area('assets/folder.jpg') }, logo: 'assets/logo.svg' };
  const dark = byPath(decode(onlyDark));
  assert.equal(format.bookIsEmpty(dark.book), false);
  assert.equal(format.bookFolderFor(dark.book, false), 'assets/folder.jpg');
  const encodedDark = format.encodeParts(dark).book;
  assert.equal(encodedDark.shelfFolder, 'assets/folder.jpg');
  assert.equal('shelfFolderDark' in encodedDark, false);
  assert.deepEqual(encodedDark.shelfFolderCrop, area('assets/folder.jpg'));
  assert.equal(format.partsAssetRefs(dark).includes('assets/folder.jpg'), true);
});

test('v2 theme: shelf layouts can each have their own backdrop beside the shared one', () => {
  const manifest = withAssets(manifestV2(), PARTS_FILES);
  const decode = json => format.decodeTheme(JSON.stringify({ parts: json }), manifest).parts;
  const byPath = parts => format.mapPartsAssetRefs(parts, ref => format.findAsset(manifest, format.assetIdFromRef(ref)).path);
  const area = image => ({ image, x: 0, y: 100, width: 1080, height: 1250, imageWidth: 1080, imageHeight: 1350 });

  // 老主题包：没有按布局的背景，四种布局都落到通用那张，导出不多出字段。
  const legacy = byPath(decode(partsJson()));
  assert.deepEqual(legacy.shelfBackdrops, []);
  assert.equal(format.shelfBackdropFor(legacy.shelfBackdrops, 'companion', false), '');
  assert.equal('shelfBackdrop' in format.encodeParts(legacy), false);
  assert.equal(format.shelfBackdropFor(undefined, 'tile', true), '', 'records saved before this field existed');

  const json = partsJson();
  json.homeBackdrop = { light: 'assets/startup.jpg' };
  json.shelfBackdrop = {
    compact: { dark: 'assets/folder.jpg' },
    companion: { light: 'assets/cover_01.jpg', dark: 'assets/cover_02.jpg', lightCrop: area('assets/cover_01.jpg'), darkCrop: area('assets/cover_01.jpg') },
    grid: { light: 'assets/cover_01.jpg' }
  };
  const parts = decode(json);
  const paths = byPath(parts);
  assert.deepEqual(paths.shelfBackdrops.map(item => item.layout), ['companion', 'compact'], 'fixed layout order, unknown layouts ignored');
  assert.equal(format.shelfBackdropFor(paths.shelfBackdrops, 'companion', false), 'assets/cover_01.jpg');
  assert.equal(format.shelfBackdropFor(paths.shelfBackdrops, 'companion', true), 'assets/cover_02.jpg');
  // 浅色、深色互不借用；没配的布局和模式返回空串，由调用方退回通用背景。
  assert.equal(format.shelfBackdropFor(paths.shelfBackdrops, 'compact', false), '');
  assert.equal(format.shelfBackdropFor(paths.shelfBackdrops, 'compact', true), 'assets/folder.jpg');
  assert.equal(format.shelfBackdropFor(paths.shelfBackdrops, 'tile', false), '');
  assert.equal(format.shelfBackdropFor(paths.shelfBackdrops, 'whatever', false), '');
  assert.deepEqual(paths.shelfBackdrops[0].lightCrop, area('assets/cover_01.jpg'));
  assert.equal(paths.shelfBackdrops[0].darkCrop, null, 'an area recorded for another image is dropped');
  assert.equal(format.describeParts(parts).includes('书架背景（陪伴布局、紧凑布局）'), true);
  assert.equal(format.partsAssetRefs(paths).includes('assets/cover_02.jpg'), true);

  const exported = new format.ThemePackageTheme();
  exported.parts = paths;
  assert.deepEqual(format.decodeTheme(format.encodeTheme(exported), manifest).parts, parts);
  const encoded = format.encodeParts(paths);
  assert.deepEqual(encoded.homeBackdrop, { light: 'assets/startup.jpg' }, 'older apps keep reading the shared backdrop');
  assert.deepEqual(encoded.shelfBackdrop, {
    companion: { light: 'assets/cover_01.jpg', dark: 'assets/cover_02.jpg', lightCrop: area('assets/cover_01.jpg') },
    compact: { dark: 'assets/folder.jpg' }
  });

  // 只有布局专属图、没有通用背景的包也能读：旧版本应用不认识 shelfBackdrop，整节忽略。
  const only = decode({ shelfBackdrop: { loose: { light: 'assets/folder.jpg' } } });
  assert.equal(only.homeBackdropLight, '');
  assert.equal(only.shelfBackdrops.length, 1);
  assert.throws(() => decode({ shelfBackdrop: { tile: {} }, logo: 'assets/logo.svg' }), /shelfBackdrop\.tile 至少要有 light 或 dark/);
  assert.throws(() => decode({ shelfBackdrop: { tile: { light: 'assets/frame.svg' } } }), /./, 'vector files are not accepted');
});

test('v2 theme: shelfBackdrop.all is the shelf-wide backdrop between each layout entry and the shared one', () => {
  const manifest = withAssets(manifestV2(), PARTS_FILES);
  const decode = json => format.decodeTheme(JSON.stringify({ parts: json }), manifest).parts;
  const byPath = parts => format.mapPartsAssetRefs(parts, ref => format.findAsset(manifest, format.assetIdFromRef(ref)).path);
  const json = partsJson();
  json.homeBackdrop = { light: 'assets/startup.jpg', dark: 'assets/startup.jpg' };
  json.shelfBackdrop = {
    tile: { light: 'assets/cover_02.jpg' },
    all: { light: 'assets/cover_01.jpg' }
  };
  const parts = decode(json);
  const paths = byPath(parts);
  assert.deepEqual(paths.shelfBackdrops.map(item => item.layout), ['all', 'tile'], 'the shelf-wide entry comes first');
  // 布局自己的 → all → 空串（调用方再退回 homeBackdrop）；all 不跨模式借用。
  assert.equal(format.shelfBackdropFor(paths.shelfBackdrops, 'tile', false), 'assets/cover_02.jpg');
  assert.equal(format.shelfBackdropFor(paths.shelfBackdrops, 'companion', false), 'assets/cover_01.jpg');
  assert.equal(format.shelfBackdropFor(paths.shelfBackdrops, 'tile', true), '');
  assert.equal(format.shelfBackdropFor(paths.shelfBackdrops, 'all', false), 'assets/cover_01.jpg');
  assert.equal(format.shelfBackdropFor(paths.shelfBackdrops, '', false), '', 'other tabs never get the shelf backdrop');
  assert.equal(format.describeParts(parts).includes('书架背景（书架通用、平铺布局）'), true);
  const encoded = format.encodeParts(paths);
  assert.deepEqual(Object.keys(encoded.shelfBackdrop), ['all', 'tile']);
  assert.deepEqual(encoded.shelfBackdrop.all, { light: 'assets/cover_01.jpg' });
  const exported = new format.ThemePackageTheme();
  exported.parts = paths;
  assert.deepEqual(format.decodeTheme(format.encodeTheme(exported), manifest).parts, parts);
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

test('v2 theme: dark-mode bubble art, shelf frame, nav icons and comment bubbles', () => {
  const manifest = withAssets(manifestV2(), PARTS_FILES);
  const decode = json => format.decodeTheme(JSON.stringify({ parts: json }), manifest).parts;
  const byPath = parts => format.mapPartsAssetRefs(parts, ref => format.findAsset(manifest, format.assetIdFromRef(ref)).path);

  // 老主题包没有这些字段：深色沿用浅色，导出不多出字段。
  const legacy = byPath(decode(partsJson()));
  assert.equal(legacy.bubbleDark, null);
  assert.equal(format.bubbleFor(legacy, true).cap, 'assets/cap.svg');
  assert.equal(format.bookShelfFrameFor(legacy.book, true), 'assets/frame.svg');
  const legacyEncoded = format.encodeParts(legacy);
  assert.equal('bubbleDark' in legacyEncoded, false);
  assert.equal('navigationDark' in legacyEncoded, false);
  assert.equal('shelfFrameDark' in legacyEncoded.book, false);
  assert.equal('commentBubble' in legacyEncoded.light, false);

  // 深色只换边框（不用声明 bubble-frame-v1，位图也收），端饰按项沿用浅色。
  const json = partsJson();
  json.bubbleDark = { frame: 'assets/cover_01.jpg', frameSlice: { left: 0.2, right: 0.2, top: 0, bottom: 0 }, frameTint: true };
  json.book.shelfFrameDark = 'assets/logo.svg';
  json.navigationDark = { bookshelf: 'assets/cover_02.jpg', mineSelected: 'assets/logo.svg', labels: 'hidden' };
  json.light.commentBubble = { shape: 'rounded', radius: 0.9, fill: '#FFB98546', text: '#fff6e6', ornament: 'star' };
  json.dark.commentBubble = { shape: 'hexagon', ornament: 'sparkle', ornamentColor: '#F0D18F' };
  const parts = byPath(decode(json));
  const night = format.bubbleFor(parts, true);
  assert.equal(night.cap, 'assets/cap.svg');
  assert.equal(night.frame, 'assets/cover_01.jpg');
  assert.equal(night.frameTint, true);
  // 只有一种模式有边框时另一种也用它（同封面）。
  assert.equal(format.bubbleFor(parts, false).frame, 'assets/cover_01.jpg');
  assert.equal(format.bookShelfFrameFor(parts.book, true), 'assets/logo.svg');
  assert.equal(format.bookShelfFrameFor(parts.book, false), 'assets/frame.svg');
  assert.equal(parts.navigationDark.bookshelf, 'assets/cover_02.jpg');
  assert.equal(parts.navigationDark.labels, '', 'labels only come from navigation');
  assert.deepEqual({ ...parts.light.commentBubble },
    { shape: 'rounded', radius: 0.5, fill: '#FFB98546', stroke: '', text: '#FFF6E6', ornament: 'star', ornamentColor: '',
      image: '', imageSlice: null, imageText: null, imageRepeat: '', imageBreak: '', imageTint: false, ornamentImage: '',
      ornamentCorner: '', ornamentSize: -1 });
  assert.equal(parts.dark.commentBubble.shape, '', 'unknown shapes fall back to the bubble style');
  assert.equal(parts.dark.commentBubble.ornament, 'sparkle');
  assert.equal(format.describeParts(parts).includes('段评气泡'), true);
  assert.equal(format.partsAssetRefs(parts).includes('assets/logo.svg'), true);
  assert.throws(() => decode({ ...partsJson(), light: { commentBubble: { fill: 'red' } } }), /commentBubble/);

  const encoded = format.encodeParts(parts);
  // 浅色那套借了深色的边框，写进 bubble；深色和浅色一样了，bubbleDark 不写。
  assert.equal(encoded.bubble.frame, 'assets/cover_01.jpg');
  assert.equal('bubbleDark' in encoded, false);
  assert.equal(encoded.book.shelfFrameDark, 'assets/logo.svg');
  assert.deepEqual(encoded.navigationDark, { bookshelf: 'assets/cover_02.jpg', mineSelected: 'assets/logo.svg' });
  assert.deepEqual(encoded.dark.commentBubble, { ornament: 'sparkle', ornamentColor: '#F0D18F' });
  // 浅色有自己的 SVG 边框时，深色的位图边框单独写，浅色那套不用声明 bubble-frame-v1。
  parts.bubble = { ...parts.bubble, frame: 'assets/frame.svg', frameSlice: null, frameRepeat: '', frameBreak: '', frameTint: false };
  const split = format.encodeParts(parts);
  assert.deepEqual(split.bubble, { cap: 'assets/cap.svg', frame: 'assets/frame.svg' });
  assert.deepEqual(split.bubbleDark, { frame: 'assets/cover_01.jpg', frameSlice: { left: 0.2, right: 0.2, top: 0, bottom: 0 }, frameTint: true });
  assert.equal(format.partsUseBubbleFrameFeature(parts), false);

  // 只有深色书架边框、只有深色气泡：导出写成浅色字段，老版本也认。
  const onlyDark = byPath(decode(partsJson()));
  onlyDark.book.shelfFrameDark = onlyDark.book.shelfFrame;
  onlyDark.book.shelfFrame = '';
  onlyDark.bubbleDark = onlyDark.bubble;
  onlyDark.bubble = null;
  const onlyEncoded = format.encodeParts(onlyDark);
  assert.equal(onlyEncoded.book.shelfFrame, 'assets/frame.svg');
  assert.equal('shelfFrameDark' in onlyEncoded.book, false);
  assert.deepEqual(onlyEncoded.bubble, { cap: 'assets/cap.svg' });
  assert.equal('bubbleDark' in onlyEncoded, false);

  // 没有 navigation 时深色图标整节不读。
  const noNav = partsJson();
  delete noNav.navigation;
  noNav.navigationDark = { bookshelf: 'assets/cover_02.jpg' };
  assert.equal(decode(noNav).navigationDark, null);
});

test('chapter head: decode, per-mode fallback, refs, encode, pack:self', () => {
  const manifest = withAssets(manifestV2(), PARTS_FILES);
  const decode = json => format.decodeTheme(JSON.stringify({ parts: json }), manifest).parts;
  const byPath = parts => format.mapPartsAssetRefs(parts, ref => format.findAsset(manifest, format.assetIdFromRef(ref)).path);
  const json = partsJson();
  json.light.chapterHead = { image: 'assets/logo.svg', placement: 'top', scale: 1.5, numberColor: '#8d8478' };
  json.dark.chapterHead = { numberColor: '#99FFFFFF', placement: 'bottom' };
  const parts = byPath(decode(json));
  const noCap = { dropCapLines: 0, dropCapStyle: '', dropCapImage: '', dropCapColor: '', dropCapRatio: 0.62 };
  assert.deepEqual({ ...parts.light.chapterHead },
    { image: 'assets/logo.svg', placement: 'top', scale: 1.5, numberColor: '#8D8478', ...noCap });
  // 深色没写饰图：沿用浅色那张和它的位置、大小，颜色用自己的；自己写的位置没有图可跟，不生效。
  const night = format.chapterHeadFor(parts, true);
  assert.deepEqual({ ...night }, { image: 'assets/logo.svg', placement: 'top', scale: 1.5, numberColor: '#99FFFFFF', ...noCap });
  assert.equal(format.partsAssetRefs(parts).includes('assets/logo.svg'), true);
  assert.equal(format.describeParts(parts).includes('章首装饰（标题饰图、序号行颜色）'), true);
  const encoded = format.encodeParts(parts);
  assert.deepEqual(encoded.light.chapterHead, { image: 'assets/logo.svg', placement: 'top', scale: 1.5, numberColor: '#8D8478' });
  assert.deepEqual(encoded.dark.chapterHead, { numberColor: '#99FFFFFF' });
  const exported = new format.ThemePackageTheme();
  exported.parts = parts;
  const again = byPath(format.decodeTheme(format.encodeTheme(exported), manifest).parts);
  assert.equal(again.light.chapterHead.image, 'assets/logo.svg');
  assert.equal(again.dark.chapterHead.numberColor, '#99FFFFFF');
  // 缺省值不写；不认得的位置按标题左侧；大小夹在 0.5–2。
  const plain = decode({ ...partsJson(), light: { chapterHead: { image: 'assets/logo.svg', placement: 'corner', scale: 9 } } });
  assert.equal(plain.light.chapterHead.placement, '');
  assert.equal(plain.light.chapterHead.scale, 2);
  assert.deepEqual(format.encodeParts(byPath(decode({ ...partsJson(), light: { chapterHead: { image: 'assets/logo.svg' } } }))).light.chapterHead,
    { image: 'assets/logo.svg' });
  // 旧包没有这一节：编码不多出字段，取值为 null。
  const legacy = byPath(decode(partsJson()));
  assert.equal('chapterHead' in format.encodeParts(legacy).light, false);
  assert.equal(format.chapterHeadFor(legacy, false), null);
  assert.throws(() => decode({ ...partsJson(), light: { chapterHead: { image: 'assets/missing.png' } } }), /chapterHead\.image/);
  assert.throws(() => decode({ ...partsJson(), light: { chapterHead: { numberColor: 'red' } } }), /chapterHead\.numberColor/);
  // 首字装饰：行数 2–4，只写了印章图时按 2 行；字占比夹在 0.4–0.9；深色没设时沿用浅色整套，颜色可以另写。
  const capJson = partsJson();
  capJson.light.chapterHead = { dropCapLines: 3, dropCapImage: 'assets/logo.svg', dropCapColor: '#b5402f', dropCapRatio: 0.95 };
  capJson.dark.chapterHead = { dropCapColor: '#FFE0A0' };
  const cap = byPath(decode(capJson));
  assert.equal(cap.light.chapterHead.dropCapLines, 3);
  assert.equal(cap.light.chapterHead.dropCapRatio, 0.9);
  assert.equal(format.partsAssetRefs(cap).includes('assets/logo.svg'), true);
  const capNight = format.chapterHeadFor(cap, true);
  assert.deepEqual([capNight.dropCapLines, capNight.dropCapImage, capNight.dropCapRatio, capNight.dropCapColor],
    [3, 'assets/logo.svg', 0.9, '#FFE0A0']);
  assert.equal(format.describeParts(cap).includes('章首装饰（首字装饰）'), true);
  const capEncoded = format.encodeParts(cap);
  assert.deepEqual(capEncoded.light.chapterHead,
    { dropCapLines: 3, dropCapImage: 'assets/logo.svg', dropCapRatio: 0.9, dropCapColor: '#B5402F' });
  assert.deepEqual(capEncoded.dark.chapterHead, { dropCapColor: '#FFE0A0' });
  assert.equal(decode({ ...partsJson(), light: { chapterHead: { dropCapImage: 'assets/logo.svg' } } }).light.chapterHead.dropCapLines, 2);
  assert.deepEqual(format.encodeParts(byPath(decode({ ...partsJson(), light: { chapterHead: { dropCapLines: 2, dropCapRatio: 0.62 } } }))).light.chapterHead,
    { dropCapLines: 2 });
  assert.equal(decode({ ...partsJson(), light: { chapterHead: { dropCapLines: 7 } } }).light.chapterHead, null);
  assert.throws(() => decode({ ...partsJson(), light: { chapterHead: { dropCapLines: 2, dropCapColor: 'red' } } }), /chapterHead\.dropCapColor/);
  // 首字样式：4 行、放大原样往返；不认得的样式按下沉（不写）；深色沿用浅色整套时样式也跟着。
  const raiseJson = partsJson();
  raiseJson.light.chapterHead = { dropCapLines: 4, dropCapStyle: 'raise' };
  const raise = byPath(decode(raiseJson));
  assert.deepEqual([raise.light.chapterHead.dropCapLines, raise.light.chapterHead.dropCapStyle], [4, 'raise']);
  assert.equal(format.chapterHeadFor(raise, true).dropCapStyle, 'raise');
  assert.deepEqual(format.encodeParts(raise).light.chapterHead, { dropCapLines: 4, dropCapStyle: 'raise' });
  const oddStyle = byPath(decode({ ...partsJson(), light: { chapterHead: { dropCapLines: 2, dropCapStyle: 'swirl' } } }));
  assert.deepEqual(format.encodeParts(oddStyle).light.chapterHead, { dropCapLines: 2 });
  // 方案覆盖里的 pack:self。
  const settings = { customLightEmphasis: { chapterHead: 'pack:self' }, customDarkEmphasis: { chapterHead: 'none' } };
  format.replaceSelfPackId(settings, 'pack:demo');
  assert.equal(settings.customLightEmphasis.chapterHead, 'pack:demo');
  assert.equal(settings.customDarkEmphasis.chapterHead, 'none');
  format.replaceOwnPackIdWithSelf(settings, 'pack:demo');
  assert.equal(settings.customLightEmphasis.chapterHead, 'pack:self');
});

test('title emphasis and title bubble: decode, per-mode fallback, refs, encode, pack:self', () => {
  const manifest = withAssets(manifestV2(), PARTS_FILES);
  const decode = json => format.decodeTheme(JSON.stringify({ parts: json }), manifest).parts;
  const byPath = parts => format.mapPartsAssetRefs(parts, ref => format.findAsset(manifest, format.assetIdFromRef(ref)).path);
  const json = partsJson();
  json.light.titleEmphasis = { mode: 'bubble', color: '#E9D3A8', textColor: '#5a3a1c' };
  json.dark.titleEmphasis = { mode: 'highlight', bubbleStyle: 'emphasis' };
  // 位图端饰和边框都收，不需要 bubble-frame-v1 / bitmap-cap-shelf-frame-v1。
  json.titleBubble = { cap: 'assets/cover_01.jpg', frame: 'assets/cover_02.jpg', frameSlice: { left: 0.16, right: 0.16, top: 0.1, bottom: 0.1 } };
  json.titleBubbleDark = { frame: 'assets/logo.svg' };
  const parts = byPath(decode(json));
  assert.deepEqual({ ...parts.light.titleEmphasis }, { mode: 'bubble', bubbleStyle: '', color: '#E9D3A8', textColor: '#5A3A1C' });
  assert.equal(parts.dark.titleEmphasis.bubbleStyle, 'emphasis');
  const night = format.titleBubbleFor(parts, true);
  assert.equal(night.cap, 'assets/cover_01.jpg', 'dark keeps the light cap');
  assert.equal(night.frame, 'assets/logo.svg');
  assert.equal(format.titleBubbleFor(parts, false).frame, 'assets/cover_02.jpg');
  assert.equal(format.partsAssetRefs(parts).includes('assets/cover_02.jpg'), true);
  assert.equal(format.describeParts(parts).includes('标题强调与标题气泡（含深色）'), true);
  const encoded = format.encodeParts(parts);
  assert.deepEqual(encoded.light.titleEmphasis, { mode: 'bubble', color: '#E9D3A8', textColor: '#5A3A1C' });
  assert.deepEqual(encoded.titleBubbleDark, { frame: 'assets/logo.svg' });
  const exported = new format.ThemePackageTheme();
  exported.parts = parts;
  const again = byPath(format.decodeTheme(format.encodeTheme(exported), manifest).parts);
  assert.equal(again.titleBubble.frame, 'assets/cover_02.jpg');
  assert.equal(again.dark.titleEmphasis.mode, 'highlight');
  // 旧包没有这几节：编码不多出字段。
  const legacy = format.encodeParts(byPath(decode(partsJson())));
  assert.equal('titleBubble' in legacy, false);
  assert.equal('titleEmphasis' in legacy.light, false);
  assert.throws(() => decode({ ...partsJson(), light: { titleEmphasis: { mode: 'glow' } } }), /titleEmphasis\.mode/);
  // 样式 ID 与方案覆盖里的 pack:self。
  assert.equal(format.packTitleBubbleStyleId('pack:demo'), 'pack:demo:title');
  assert.equal(format.isPackTitleBubbleStyle('pack:demo:title'), true);
  assert.equal(format.isPackTitleBubbleStyle('pack:demo'), false);
  const settings = { customLightEmphasis: { title: { mode: 'bubble', bubbleStyle: 'pack:custom-0011aabb:title' } } };
  format.replaceOwnPackIdWithSelf(settings, 'pack:custom-0011aabb');
  assert.equal(settings.customLightEmphasis.title.bubbleStyle, 'pack:self:title');
  format.replaceSelfPackId(settings, 'pack:demo-pack');
  assert.equal(settings.customLightEmphasis.title.bubbleStyle, 'pack:demo-pack:title');
});

test('comment bubble image and custom ornament: decode, per-mode fallback, refs, encode, pack:self', () => {
  const manifest = withAssets(manifestV2(), PARTS_FILES);
  const decode = json => format.decodeTheme(JSON.stringify({ parts: json }), manifest).parts;
  const byPath = parts => format.mapPartsAssetRefs(parts, ref => format.findAsset(manifest, format.assetIdFromRef(ref)).path);
  const json = partsJson();
  json.light.commentBubble = {
    shape: 'rounded', fill: '#B98546', text: '#4A3423',
    image: 'assets/cover_01.jpg', imageSlice: { left: 0.28, right: 0.7, top: 0.3, bottom: 0.3 },
    imageText: { left: 0.1, right: 0.1, top: 0.14, bottom: 0.3 }, imageRepeat: 'round', imageBreak: 'full', imageTint: true,
    ornament: 'custom', ornamentImage: 'assets/logo.svg', ornamentCorner: 'bottomRight', ornamentSize: 3
  };
  json.dark.commentBubble = { text: '#F2DEAE' };
  const parts = byPath(decode(json));
  const light = parts.light.commentBubble;
  assert.equal(light.image, 'assets/cover_01.jpg');
  assert.deepEqual({ ...light.imageSlice }, { left: 0.28, right: 0.49, top: 0, bottom: 0 }, 'only left / right stretch lines');
  assert.deepEqual({ ...light.imageText }, { left: 0.1, right: 0.1, top: 0.14, bottom: 0.3 });
  assert.equal(light.imageRepeat, 'round');
  assert.equal(light.imageBreak, 'full');
  assert.equal(light.imageTint, true);
  assert.equal(light.ornament, 'custom');
  assert.equal(light.ornamentCorner, 'bottomRight');
  assert.equal(light.ornamentSize, 1.5, 'size is clamped to 0.5–1.5');
  // 深色没给图：气泡图与角标图沿用浅色，深色自己的文字色保留。
  const night = format.commentBubbleFor(parts, true);
  assert.equal(night.image, 'assets/cover_01.jpg');
  assert.equal(night.ornamentImage, 'assets/logo.svg');
  assert.equal(night.ornament, 'custom');
  assert.equal(night.text, '#F2DEAE');
  // 'none' 不沿用另一模式的图。
  parts.dark.commentBubble = { ...parts.dark.commentBubble, image: 'none' };
  assert.equal(format.commentBubbleHasImage(format.commentBubbleFor(parts, true)), false);
  assert.equal(format.partsAssetRefs(parts).includes('assets/cover_01.jpg'), true);
  assert.equal(format.partsAssetRefs(parts).includes('none'), false);
  assert.equal(format.describeParts(parts).includes('段评气泡（含气泡图）'), true);
  const encoded = format.encodeParts(parts);
  assert.deepEqual(encoded.light.commentBubble.imageSlice, { left: 0.28, right: 0.49 });
  assert.equal(encoded.light.commentBubble.ornamentSize, 1.5);
  assert.equal(encoded.dark.commentBubble.image, 'none');
  assert.equal('imageSlice' in encoded.dark.commentBubble, false);
  // 往返。
  const exported = new format.ThemePackageTheme();
  exported.parts = parts;
  const again = byPath(format.decodeTheme(format.encodeTheme(exported), manifest).parts);
  assert.deepEqual({ ...again.light.commentBubble }, { ...parts.light.commentBubble,
    imageSlice: { ...parts.light.commentBubble.imageSlice }, imageText: { ...parts.light.commentBubble.imageText } });
  // 引用不存在的素材、字体当图片都报错；不认得的角标位置按右上。
  assert.throws(() => decode({ ...partsJson(), light: { commentBubble: { image: 'assets/missing.png' } } }), /commentBubble\.image/);
  const odd = decode({ ...partsJson(), light: { commentBubble: { ornament: 'custom', ornamentImage: 'assets/logo.svg', ornamentCorner: 'middle' } } });
  assert.equal(odd.light.commentBubble.ornamentCorner, '');
  // 默认拉伸线与文字区、上下超出比例。
  assert.deepEqual({ ...format.defaultCommentImageSlice(2) }, { left: 0.3, right: 0.3, top: 0, bottom: 0 });
  assert.deepEqual({ ...format.defaultCommentImageText(2.5) }, { left: 0.14, right: 0.14, top: 0.12, bottom: 0.2 });
  const [up, down] = format.commentImageOverhang({ left: 0, right: 0, top: 0.14, bottom: 0.3 });
  assert.equal(Math.round(up * 100), 25);
  assert.equal(Math.round(down * 100), 54);
  // 方案覆盖里的 pack:<id> 导出写成 pack:self，导入换回来。
  const settings = { customLightEmphasis: { comment: { image: 'pack:custom-0011aabb', ornamentImage: 'pack:custom-0011aabb' } },
    customDarkEmphasis: { comment: { image: 'none' } } };
  format.replaceOwnPackIdWithSelf(settings, 'pack:custom-0011aabb');
  assert.equal(settings.customLightEmphasis.comment.image, 'pack:self');
  assert.equal(settings.customLightEmphasis.comment.ornamentImage, 'pack:self');
  assert.equal(settings.customDarkEmphasis.comment.image, 'none');
  format.replaceSelfPackId(settings, 'pack:demo-pack');
  assert.equal(settings.customLightEmphasis.comment.image, 'pack:demo-pack');
  // 旧数据里的覆盖只有颜色：不算有图。
  assert.equal(format.commentBubbleIsEmpty({ image: 'none' }), false);
  assert.equal(format.commentBubbleIsEmpty({}), true);
});

test('installed pack record keeps every parts field when read back', async () => {
  // 本机记录读回时逐个字段拷贝：ThemePackageParts 加了字段而这里没跟上，装好的包重启后就丢那一部分。
  const { readFileSync } = await import('node:fs');
  const store = readFileSync(path.join(projectRoot, 'entry', 'src', 'main', 'ets', 'utils', 'ThemePackStore.ets'), 'utf8');
  const start = store.indexOf('private static normalizeParts(');
  assert(start >= 0);
  const body = store.substring(start, store.indexOf('\n  }\n', start));
  for (const key of Object.keys(new format.ThemePackageParts())) {
    assert(body.includes(`parts.${key} = `), `ThemePackStore.normalizeParts 漏了 ${key}`);
  }
});

test('v2 theme: shelf frame and folder can be turned off per mode', () => {
  const manifest = withAssets(manifestV2(), PARTS_FILES);
  const decode = json => format.decodeTheme(JSON.stringify({ parts: json }), manifest).parts;
  const byPath = parts => format.mapPartsAssetRefs(parts, ref => format.findAsset(manifest, format.assetIdFromRef(ref)).path);

  // 老主题包没有这些字段：一样都不算“不用”，导出也不多出字段。
  const legacy = byPath(decode(partsJson()));
  assert.equal(format.bookHasOffParts(legacy.book), false);
  assert.equal('noShelfFrame' in format.encodeParts(legacy).book, false);

  // 浅色不用边框，深色没单独设：两种模式都不画；文件夹只是深色不用。
  const json = { book: { covers: ['assets/cover_01.jpg'], noShelfFrame: true, shelfFolder: 'assets/folder.jpg', noShelfFolderDark: true },
    logo: 'assets/logo.svg' };
  const parts = byPath(decode(json));
  assert.equal(format.bookShelfFrameOff(parts.book, false), true);
  assert.equal(format.bookShelfFrameOff(parts.book, true), true);
  assert.equal(format.bookShelfFrameFor(parts.book, true), '');
  assert.equal(format.bookFolderOff(parts.book, false), false);
  assert.equal(format.bookFolderFor(parts.book, false), 'assets/folder.jpg');
  assert.equal(format.bookFolderOff(parts.book, true), true);
  assert.equal(format.bookFolderFor(parts.book, true), '');
  const encoded = format.encodeParts(parts).book;
  assert.equal(encoded.noShelfFrame, true);
  assert.equal('noShelfFrameDark' in encoded, false);
  assert.equal(encoded.noShelfFolderDark, true);
  assert.equal(format.describeParts(parts).includes('封面 1 张、文件夹插画、不用书架边框、不用文件夹插画'), true);

  // 浅色不用、深色有图：深色那张不并到 shelfFrame（否则浅色也会显示它）。
  const darkOnly = byPath(decode({ book: { noShelfFrame: true, shelfFrameDark: 'assets/frame.svg' }, logo: 'assets/logo.svg' }));
  assert.equal(format.bookShelfFrameFor(darkOnly.book, false), '');
  assert.equal(format.bookShelfFrameFor(darkOnly.book, true), 'assets/frame.svg');
  const darkEncoded = format.encodeParts(darkOnly).book;
  assert.equal('shelfFrame' in darkEncoded, false);
  assert.equal(darkEncoded.shelfFrameDark, 'assets/frame.svg');
  assert.equal(darkEncoded.noShelfFrame, true);

  // 同一模式有图时“不用”不起作用；只带“不用”的 book 不算空。
  const both = byPath(decode({ book: { shelfFrame: 'assets/frame.svg', noShelfFrame: true }, logo: 'assets/logo.svg' }));
  assert.equal(both.book.noShelfFrame, false);
  assert.equal(format.bookShelfFrameFor(both.book, false), 'assets/frame.svg');
  const onlyOff = decode({ book: { noShelfFolder: true }, logo: 'assets/logo.svg' });
  assert.notEqual(onlyOff.book, null);
  assert.equal(format.bookIsEmpty(onlyOff.book), false);
});
