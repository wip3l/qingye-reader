// 正文文字划线：设置的默认值与容错、颜色浓淡、绘制挂点与“标题不画”“仅正则字体”的取数约定。
// node --experimental-strip-types scripts/reader-text-ruling-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = new URL('../', import.meta.url);
const read = (relative) => fs.readFileSync(new URL(relative, root), 'utf8');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'text-ruling-check-'));
try {
  fs.copyFileSync(new URL('entry/src/main/ets/core/reader/ReaderTextRuling.ts', root), path.join(dir, 'ReaderTextRuling.ts'));
  const { ReaderTextRuling, ReaderTextRulingSettings } = await import(pathToFileURL(path.join(dir, 'ReaderTextRuling.ts')).href);

  // 默认：关闭；打开后是整行 + 点线 + 行间居中 + 跟随文字色 40%。
  const defaults = ReaderTextRuling.decode('');
  assert.equal(defaults.enabled, false);
  assert.equal(defaults.target, 'all');
  assert.equal(defaults.scope, 'row');
  assert.equal(defaults.style, 'dotted');
  assert.equal(defaults.position, 'gap');
  assert.equal(defaults.colorMode, 'text');
  assert.equal(defaults.opacity, 40);
  assert.equal(ReaderTextRuling.thicknessVp(defaults.thickness), 1);
  assert.equal(ReaderTextRuling.spec(defaults, 0xFF000000, 3), null, 'disabled ruling produces no spec');

  // 坏数据与越界值回到默认或夹到范围内。
  const broken = ReaderTextRuling.decode('{"enabled":true,"style":"zigzag","target":"x","opacity":3,"thickness":9,"color":7}');
  assert.equal(broken.enabled, true);
  assert.equal(broken.style, 'dotted');
  assert.equal(broken.target, 'all');
  assert.equal(broken.opacity, 10);
  assert.equal(broken.thickness, 5);
  assert.equal(broken.color, '');
  assert.equal(ReaderTextRuling.decode('not json').enabled, false);

  // 编码往返。
  const custom = new ReaderTextRulingSettings();
  custom.enabled = true;
  custom.style = 'wavy';
  custom.colorMode = 'custom';
  const withLight = ReaderTextRuling.withCustomColor(custom, false, ' #FF8800 ');
  const withBoth = ReaderTextRuling.withCustomColor(withLight, true, '#3366CC');
  assert.equal(ReaderTextRuling.customColor(withBoth, false), '#FF8800', 'light and dark custom colours are kept apart');
  assert.equal(ReaderTextRuling.customColor(withBoth, true), '#3366CC');
  const roundTrip = ReaderTextRuling.decode(ReaderTextRuling.encode(withBoth));
  assert.deepEqual({ ...roundTrip }, { ...withBoth });

  // 仅正则字体时长度固定按文字。
  const regex = ReaderTextRuling.copy(defaults);
  regex.enabled = true;
  regex.target = 'regex';
  assert.equal(ReaderTextRuling.effectiveScope(regex), 'text');
  const regexSpec = ReaderTextRuling.spec(regex, 0xFF202124, 3);
  assert.equal(regexSpec.scope, 'text');

  // 浓淡乘进 alpha，线宽按 vp 换像素。
  assert.equal(ReaderTextRuling.applyOpacity(0xFF202124, 40), 0x66202124);
  assert.equal(ReaderTextRuling.applyOpacity(0x80FFFFFF, 50), 0x40FFFFFF);
  const enabled = ReaderTextRuling.copy(defaults);
  enabled.enabled = true;
  const spec = ReaderTextRuling.spec(enabled, 0xFF202124, 3);
  assert.equal(spec.color, 0x66202124);
  assert.equal(spec.widthPx, 3);
  assert.notEqual(ReaderTextRuling.stamp(spec), ReaderTextRuling.stamp(null));
  const thicker = ReaderTextRuling.copy(enabled);
  thicker.thickness = 4;
  assert.notEqual(ReaderTextRuling.stamp(ReaderTextRuling.spec(thicker, 0xFF202124, 3)), ReaderTextRuling.stamp(spec),
    'changing a setting changes the page stamp so pages are refilled');
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}

// 绘制挂点：在字形之前、划线笔记之前画，常驻页与自绘纹理共用同一个绘制器。
const pagePainter = read('entry/src/main/ets/core/reader/ReaderV2PagePainter.ets');
const rulingAt = pagePainter.indexOf('ReaderV2RulingPainter.paint(canvas, page)');
assert(rulingAt > 0, 'page painter draws the ruling');
assert(rulingAt < pagePainter.indexOf('fragment.paragraph.paint(canvas'), 'ruling is drawn below the glyphs');
assert(rulingAt < pagePainter.indexOf('ReaderV2AnnotationPainter.paintLines'), 'annotation lines cover the ruling');
assert(rulingAt > pagePainter.indexOf('drawRegexBubble(canvas, segment)'), 'ruling stays visible above regex bubbles');

const rulingPainter = read('entry/src/main/ets/core/reader/ReaderV2RulingPainter.ets');
assert(/fragment\.title\b/.test(rulingPainter) && /fragment\.card\b/.test(rulingPainter),
  'titles and comment cards are not ruled');
assert(rulingPainter.includes('fragment.regexRanges'), 'regex-only ruling reads the ranges recorded at pagination');

const paginator = read('entry/src/main/ets/core/reader/ReaderV2Paginator.ets');
assert(/if \(!fragment\.title\) fragment\.regexRanges = /.test(paginator), 'title fragments get no regex ranges');
assert(/style\.repeatCaps \|\|/.test(paginator), 'title emphasis styles are not counted as regex font');

// 阅读页：划线参数并入页对象版本串，改设置只重画不重新分页。
const readBook = read('entry/src/main/ets/pages/ReadBook.ets');
assert(/ReaderTextRuling\.stamp\(this\.readerTextRulingSpec\(\)\)/.test(readBook), 'ruling is part of the page stamp');
assert(/page\.ruling = this\.readerTextRulingSpec\(\);/.test(readBook), 'pages receive the ruling spec');
const update = readBook.slice(readBook.indexOf('  updateReaderTextRuling('), readBook.indexOf('  readerTextRulingSpec(): '));
assert(update.includes('this.refreshReaderPageDecorations()'), 'changing the ruling repaints');
assert(!/[Pp]agination|repaginate/.test(update), 'changing the ruling does not repaginate');
assert(!readBook.slice(readBook.indexOf('buildReaderPaginationCacheKey(chapterIndex: number'),
  readBook.indexOf('readerPaginationSourceHash(source: string)')).includes('readerTextRuling'),
  'ruling settings stay out of the pagination cache key');

console.log('reader-text-ruling-check: ok');
