import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { loadObsidianReader } from './lib/obsidian-reader-fixture.mjs';
import { loadReaderModules } from './lib/load-reader-modules.mjs';
import { projectRoot } from './lib/ets-module-staging.mjs';

const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${file}`, 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import\s+[\s\S]*?\s+from\s+['"][^'"]+['"];?\r?$/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });
const source = read('pages/ReadBook.ets');
const near = (actual, expected, message) => assert(Math.abs(actual - expected) < 0.000001,
  `${message || 'pixel geometry'}: expected ${expected}, got ${actual}`);
function method(name) {
  const start = source.indexOf(`  ${name}(`);
  assert(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}

// Small deterministic native-text adapter: production parsing, styling, pagination and source mapping run unchanged.
let asyncLayouts = 0;
let holdLayout = false;
let rejectLayout = false;
const heldLayouts = [];
class ParagraphBuilder {
  constructor(options) { this.options = options; this.runs = []; }
  pushStyle(style) { this.current = style; }
  addText(text) { this.runs.push({ text, style: this.current }); }
  popStyle() {}
  build() {
    const options = this.options, runs = this.runs;
    const paragraph = { lines: [], chars: [], width: 0, alignment: options.align, text: runs.map(run => run.text).join(''),
      layout(width) {
        asyncLayouts++;
        return new Promise((resolve, reject) => {
          const finish = () => {
            if (rejectLayout) { rejectLayout = false; reject(new Error('native layout failed')); return; }
            this.layoutSync(width); resolve();
          };
          if (holdLayout) heldLayouts.push(finish); else setTimeout(finish, 0);
        });
      },
      layoutSync(width) {
        this.width = width;
        let offset = 0, start = 0, advance = 0, top = 0, fontSize = 0;
        const finish = () => {
          if (offset <= start) return;
          const height = fontSize * 1.2 + (options.lineSpacing || 0);
          this.lines.push({ startIndex: start, endIndex: offset, topHeight: top, height,
            ascent: fontSize * 0.8, descent: fontSize * 0.2, baseline: top + fontSize * 0.8,
            width: advance, x: options.align === 'center' ? (width - advance) / 2 :
              (options.align === 'right' ? width - advance : 0) });
          top += height; start = offset; advance = 0; fontSize = 0;
        };
        for (const run of runs) for (const char of run.text) {
          const size = run.style.fontSize || 20;
          const charWidth = size * (/[^\x00-\x7f]/.test(char) ? 1 : 0.5) + (run.style.letterSpacing || 0);
          if (advance > 0 && advance + charWidth > width) finish();
          this.chars.push({ start: offset, end: offset + char.length, x: advance, width: charWidth });
          offset += char.length; advance += charWidth; fontSize = Math.max(fontSize, size);
        }
        finish();
      },
      getLineCount() { return this.lines.length; },
      getLineMetrics(index) { return index === undefined ? this.lines : this.lines[index]; },
      getRectsForPlaceholders() { return []; },
      paint() {},
      getHeight() { return this.lines.reduce((sum, line) => sum + line.height, 0); },
      getRectsForRange({ start, end }) {
        return this.lines.flatMap(line => {
          const chars = this.chars.filter(char => char.start >= Math.max(start, line.startIndex) &&
            char.end <= Math.min(end, line.endIndex));
          if (!chars.length) return [];
          return [{ rect: { left: line.x + chars[0].x, right: line.x + chars.at(-1).x + chars.at(-1).width,
            top: line.topHeight, bottom: line.topHeight + line.height - (options.lineSpacing || 0) } }];
        });
      }
    };
    return paragraph;
  }
}

const fixture = loadObsidianReader();
const { sandbox, ReaderHarness } = fixture;
const modules = await loadReaderModules();
try {
  Object.assign(sandbox, {
    ReaderActionMarker: modules.ReaderActionMarker, ReaderImageMarker: modules.ReaderImageMarker,
    ReaderMixedPageLayout: modules.ReaderMixedPageLayout,
    CooperativeScheduler: { reportSynchronousOperation() {} },
    graphicsText: {
      FontWeight: Object.fromEntries(Array.from({ length: 9 }, (_, i) => [`W${(i + 1) * 100}`, i])),
      TextAlign: { CENTER: 'center', LEFT: 'left', RIGHT: 'right', JUSTIFY: 'justify' },
      TextDirection: { LTR: 0 }, WordBreak: { BREAK_WORD: 0 }, BreakStrategy: { GREEDY: 0 },
      RectWidthStyle: { TIGHT: 0 }, RectHeightStyle: { TIGHT: 0 },
      FontCollection: { getGlobalInstance: () => ({}) }, ParagraphBuilder
    }
  });
  vm.runInContext(['core/reader/ReaderV2Document.ets','core/reader/ReaderV2LayoutSnapshot.ets',
    'core/reader/ReaderV2PageLayout.ets','core/reader/ReaderV2ChapterHead.ets','core/reader/ReaderV2Paginator.ets']
    .map(file => compile(read(file))).join('\n') + '\n' + compile(`
    class TitleReader extends ReaderHarness {
      readerTitleFontSize = 22;
      readerTitleFontWeight = 600;
      readerRegexFontEnabled = false;
      readerTitleStyleRaw = '';
      getTitleReaderFontFamily() { return ''; }
      getRegexTextSlices() { return this.testSlices || []; }
      ${method('buildReaderV2RegexStyles')}
    }
    globalThis.titleApi = { ReaderV2ChapterHeadStyle, ReaderTitleSplit, ReaderTitleStyleCodec, ReaderTitleStyleSettings,
      ReaderV2DocumentParser, ReaderV2SpeechText, ReaderV2Paginator, ReaderV2LayoutSnapshot,
      ReaderV2LayoutInput, ReaderV2PageLayout, ReaderV2PageFragment, TitleReader };
  `), sandbox);
  const { ReaderTitleSplit: Split, ReaderTitleStyleCodec: Codec, ReaderTitleStyleSettings: Settings,
    ReaderV2DocumentParser: Parser, ReaderV2SpeechText: Speech, ReaderV2Paginator: Paginator,
    ReaderV2LayoutInput: Input, ReaderV2LayoutSnapshot: Snapshot, TitleReader,
    ReaderV2PageLayout: Page, ReaderV2PageFragment: Fragment } = sandbox.titleApi;
  const defaults = Codec.decode('');
  assert.equal(defaults.mode, 'off');
  assert.equal(defaults.emphasis.emphasisMode, 'theme', 'title emphasis follows the theme by default');
  // 旧数据：none 是旧默认值，读入时迁成 theme；inherit（旧“跟随主题”= 同正文强调）原样；新数据里的 none 是明确选的。
  assert.equal(Codec.decode('{"emphasis":{"emphasisMode":"none"}}').emphasis.emphasisMode, 'theme');
  assert.equal(Codec.decode('{"emphasis":{"emphasisMode":"inherit"}}').emphasis.emphasisMode, 'inherit');
  assert.equal(Codec.decode('{"emphasisVersion":2,"emphasis":{"emphasisMode":"none"}}').emphasis.emphasisMode, 'none');
  const explicitNone = new Settings(); explicitNone.emphasis.emphasisMode = 'none';
  assert.equal(Codec.decode(Codec.encode(explicitNone)).emphasis.emphasisMode, 'none', 'an explicit none survives a round trip');
  assert.equal(defaults.alignment, 'center');
  assert.equal(defaults.marginTop, 0);
  assert.equal(defaults.marginBottom, 0);
  assert.equal(defaults.singlePage, false);
  assert.equal(Codec.decode('{"singlePage":"true"}').singlePage, false);
  assert.equal(Codec.decode('{"singlePage":true}').singlePage, true);
  const oldSettings = Codec.decode('{"mode":"marker","secondaryScale":1.5,"lineGap":16}');
  assert.equal(oldSettings.alignment, 'center');
  assert.equal(oldSettings.marginTop, 0);
  assert.equal(oldSettings.lineGap, 16);
  for (const alignment of ['left','center','right']) {
    assert.equal(Codec.decode(JSON.stringify({ alignment })).alignment, alignment);
  }
  assert.equal(Codec.decode('{"alignment":"invalid","marginTop":-5,"marginBottom":999}').alignment, 'center');
  assert.equal(Codec.decode('{"marginTop":-5,"marginBottom":999}').marginTop, 0);
  assert.equal(Codec.decode('{"marginTop":-5,"marginBottom":999}').marginBottom, 300);
  assert.equal(Codec.decode('{"marginTop":300,"marginBottom":250}').marginTop, 300, 'title margins reach 300 vp');
  assert.equal(Codec.decode('{"marginTop":12.7,"marginBottom":"bad"}').marginTop, 13);
  assert.equal(Codec.decode('{"marginTop":12.7,"marginBottom":"bad"}').marginBottom, 0);
  for (const raw of ['{', 'null', '[]', '42', '{"mode":"invalid","emphasis":null}']) {
    assert.equal(Codec.decode(raw).mode, 'off');
    assert.equal(Codec.decode(raw).emphasis.emphasisMode, 'theme');
  }
  const title = '第七十四章：卖鸭蛋，卖粽子喽';
  const settings = new Settings();
  assert.deepEqual([...Split.parts(title, settings)], [title]);
  for (const mode of ['position','marker','regex']) {
    settings.mode = mode;
    assert.deepEqual([...Split.parts(title, settings)], ['第七十四章：','卖鸭蛋，卖粽子喽']);
  }
  settings.mode = 'position'; settings.position = '2';
  assert.deepEqual([...Split.parts('甲😀乙丙', settings)], ['甲😀','乙丙']);
  for (const position of ['0','-1','1.5','','161','99']) {
    settings.position = position;
    assert.deepEqual([...Split.parts(title, settings)], [title]);
  }
  settings.mode = 'marker'; settings.marker = '：';
  assert.deepEqual([...Split.parts('甲：乙：丙', settings)], ['甲：','乙：丙']);
  for (const text of ['无标记标题','甲：','：   ','']) assert.deepEqual([...Split.parts(text, settings)], [text]);
  settings.mode = 'regex';
  for (const regex of ['[','^','不存在','(a+)+$','']) {
    settings.regex = regex;
    assert.deepEqual([...Split.parts(title, settings)], [title]);
  }
  settings.mode = 'marker'; settings.secondaryScale = 1.5; settings.lineGap = 16;
  settings.emphasis.emphasisMode = 'custom';
  settings.emphasis.customTextColorEnabled = true; settings.emphasis.customTextColor = '#00123456';
  assert.equal(Codec.decode(Codec.encode(settings)).emphasis.customTextColor, '#00123456');
  assert.equal(Codec.decode('{"secondaryScale":99,"lineGap":-10}').secondaryScale, 3);
  assert.equal(Codec.decode('{"secondaryScale":99,"lineGap":-10}').lineGap, 0);
  console.log('PASS: defaults, corrupt settings, all split modes, Unicode, invalid/missing/empty matches and ARGB round trip');

  const fontPage = read('pages/ReaderFontSettings.ets');
  const fontMethod = name => {
    const start = fontPage.indexOf(`  ${name}(`);
    assert(start >= 0, name);
    return fontPage.slice(start, fontPage.indexOf('\n  }', start) + 4);
  };
  const editingIndex = fontPage.match(/const EDITING_REGEX_RULE_INDEX: number = (-?\d+);/);
  assert(editingIndex, 'rule editor draft index is defined');
  vm.runInContext(compile(`const EDITING_REGEX_RULE_INDEX = ${Number(editingIndex[1])};
  class TitleControls {
    titleStyle = new ReaderTitleStyleSettings(); regexRules = []; saves = 0; regexHighlightRefreshKey = 0;
    editingRegexRule = new ReaderRegexFontRule();
    saveSettings() { this.saves++; this.savedTitle = ReaderTitleStyleCodec.encode(this.titleStyle); }
    bumpRegexHighlightRefresh() { this.regexHighlightRefreshKey++; }
    ${['updateTitleSplit','updateRegexRule','regexRuleAt','adjustTitleSplit',
      'adjustTitleMargin','titleAlignmentIndex','titlePreviewAlignment'].map(fontMethod).join('\n')}
  } globalThis.TitleControls = TitleControls;`), sandbox);
  const controls = new sandbox.TitleControls();
  controls.updateTitleSplit('mode', 'marker');
  controls.updateTitleSplit('marker', '：');
  controls.updateTitleSplit('secondaryScale', '1.5');
  controls.updateTitleSplit('lineGap', '16');
  const before = controls.titleStyle;
  controls.updateRegexRule(-1, rule => { rule.emphasisMode = 'custom'; rule.customTextColorEnabled = true;
    rule.customTextColor = '#FF123456'; });
  assert.notEqual(before, controls.titleStyle, 'replace the state object so ArkUI observes nested emphasis changes');
  assert.equal(controls.regexRules.length, 0, 'title settings never create a body regex rule');
  assert.equal(controls.regexRuleAt(-1).customTextColor, '#FF123456');
  assert.equal(JSON.parse(controls.savedTitle).secondaryScale, 1.5);
  assert.equal(JSON.parse(controls.savedTitle).lineGap, 16);
  assert.equal(controls.saves, 5);
  controls.updateTitleSplit('alignment', 'right');
  controls.updateTitleSplit('marginTop', '23');
  controls.updateTitleSplit('marginBottom', '37');
  controls.adjustTitleMargin(true, 1);
  controls.adjustTitleMargin(false, -1);
  assert.equal(controls.titleAlignmentIndex(), 2);
  assert.equal(JSON.parse(controls.savedTitle).alignment, 'right');
  assert.equal(JSON.parse(controls.savedTitle).marginTop, 24);
  assert.equal(JSON.parse(controls.savedTitle).marginBottom, 36);
  assert.equal(controls.saves, 10);
  controls.updateTitleSplit('marginTop', '299');
  controls.adjustTitleMargin(true, 1);
  assert.equal(JSON.parse(controls.savedTitle).marginTop, 300, 'the plus button reaches the 300 vp maximum');
  controls.adjustTitleMargin(true, 1);
  assert.equal(JSON.parse(controls.savedTitle).marginTop, 300);
  controls.updateTitleSplit('marginTop', '24');
  controls.saves = 10;
  controls.updateTitleSplit('singlePage', 'true');
  assert.equal(JSON.parse(controls.savedTitle).singlePage, true);
  controls.updateTitleSplit('singlePage', 'false');
  assert.equal(JSON.parse(controls.savedTitle).singlePage, false);
  console.log('PASS: actual settings handlers refresh immutable state and save title emphasis independently of regex rules');

  const themePage = read('pages/ThemeTypographySettings.ets');
  const themeMethod = name => {
    const start = themePage.indexOf(`  ${name}(`);
    assert(start >= 0, name);
    return themePage.slice(start, themePage.indexOf('\n  }', start) + 4);
  };
  const fitStart = themePage.indexOf('class TypographyPreviewFit');
  const samplesStart = themePage.indexOf('const PREVIEW_CHAPTER_TITLE:');
  vm.runInContext(compile(themePage.slice(fitStart,themePage.indexOf('const TOOLBAR_CONTROL_HEIGHT',fitStart))) + '\n' +
    compile(themePage.slice(samplesStart,themePage.indexOf('/**',samplesStart))) + '\n' +
    compile(`class ThemeTitlePreviewChecks {
      draft = { titleStyleRaw:'',titleFontSize:22,titleFontWeight:600,fontSize:20,fontWeight:400,paragraphSpacing:0 };
      bodyLimit() { return 180; } bodyTop() { return 0; } contentWidth() { return 320; }
      titleLineBox() { return 22; } bodyLineBox() { return 20; }
      titleFontFamily() { return ''; } bodyFontFamily() { return ''; }
      paragraphText(index) { return PREVIEW_PARAGRAPHS[index]; } measureLines() { return 1; }
      ${['titleLayout','titlePreviewAlignment','computeFit','computeTitleFit'].map(themeMethod).join('\n')}
    } globalThis.ThemeTitlePreviewChecks = ThemeTitlePreviewChecks;`), sandbox);
  const themePreview = new sandbox.ThemeTitlePreviewChecks();
  const plainFit = themePreview.computeFit(false);
  assert.equal(themePreview.titlePreviewAlignment(), 'center');
  themePreview.draft.titleStyleRaw = JSON.stringify({alignment:'right',marginTop:40,marginBottom:60});
  assert.equal(themePreview.titlePreviewAlignment(), 'right');
  assert.equal(themePreview.computeFit(false).paragraphCount, plainFit.paragraphCount - 5,
    'theme preview fitting reserves the configured outer title margins before placing prose');
  themePreview.draft.titleStyleRaw = JSON.stringify({marginTop:120,marginBottom:120});
  assert.equal(themePreview.computeFit(false).titleLines, 0);
  assert.equal(themePreview.computeFit(false).paragraphCount, 0);
  themePreview.draft.titleStyleRaw = JSON.stringify({singlePage:true});
  assert.equal(themePreview.computeFit(false).titleLines, 0, 'the body page of a single-page title has no title');
  assert.equal(themePreview.computeFit(false).paragraphCount, 9, 'the body page starts prose at the page top');
  assert.equal(themePreview.computeTitleFit(false).titleLines, 1);
  assert.equal(themePreview.computeTitleFit(false).paragraphCount, 0, 'theme title page never shows body prose');
  themePreview.draft.titleStyleRaw = JSON.stringify({singlePage:true,marginTop:400});
  assert.equal(themePreview.computeTitleFit(true).titleTop, 158, 'an oversized top margin still keeps the title on the page');
  themePreview.bodyLimit = full => full ? 720 : 180;
  themePreview.draft.titleStyleRaw = JSON.stringify({singlePage:true,marginTop:200});
  assert.equal(themePreview.computeTitleFit(true).titleTop, 200);
  assert.equal(themePreview.computeTitleFit(false).titleTop, 50, 'the window scales the title offset to its own height');
  console.log('PASS: theme preview alignment and visible-body fitting account for both title margins');

  const chapter = `${title}\n第一段正文。\n第二段正文。`;
  const document = Parser.parse(chapter, 0, title, [], settings);
  assert.equal(document.sourceText, chapter);
  assert.equal(document.displayText, chapter);
  assert.equal(document.blocks.length, 4);
  assert.equal(document.blocks[1].titleSegment, 1);
  assert.equal(document.blocks[0].text + document.blocks[1].text, title);
  assert.equal(document.copyText(0, title.length), title);
  assert.equal(Speech.build(document, 0).text, chapter);
  for (let index = 0; index <= chapter.length; index++) {
    assert.equal(document.sourceOffsetForDisplay(index), index);
    assert.equal(document.displayOffsetForSource(index), index);
  }
  console.log('PASS: split document, copying, TTS and every source/display offset retain the original text');

  const reader = new TitleReader();
  reader.readerTitleStyleRaw = Codec.encode(settings);
  const styles = reader.buildReaderV2RegexStyles(document);
  assert.equal(styles.length, 2, 'title emphasis works when regex fonts are disabled');
  assert.equal(styles[0].fontSizePx, 22);
  assert.equal(styles[1].fontSizePx, 33);
  assert.equal(styles[1].color, 0x00123456);
  reader.readerRegexFontEnabled = true;
  reader.testSlices = [{ start: 0, end: chapter.length, text: chapter, ruleIndex: 0, highlighted: true, key: 'all' }];
  const mixedStyles = reader.buildReaderV2RegexStyles(document);
  assert.equal(mixedStyles.length, 3);
  assert.equal(mixedStyles[2].start, title.length, 'body regex survives a match crossing the title');
  assert.deepEqual(Array.from(reader.readerV2RangesOutsideTitle(0, 20, [{start:5,end:10}]), row=>Array.from(row)),
    [[0,5],[10,20]], 'both sides of a title remain available to regex styles');
  reader.readerRegexFontEnabled = false;
  settings.emphasis.emphasisMode = 'none'; reader.readerTitleStyleRaw = Codec.encode(settings);
  assert.equal(reader.buildReaderV2RegexStyles(document).length, 0);
  // 跟随主题：主题没设标题强调时标题保持原样；设了就按主题的标题强调画。
  settings.emphasis.emphasisMode = 'theme'; reader.readerTitleStyleRaw = Codec.encode(settings);
  sandbox.AppStorage.setOrCreate('themeLightTitleEmphasis', '');
  assert.equal(reader.buildReaderV2RegexStyles(document).length, 0, 'a theme without title emphasis leaves titles plain');
  sandbox.AppStorage.setOrCreate('themeLightTitleEmphasis', JSON.stringify({ mode: 'highlight', bubbleStyle: '',
    color: '#FF2B6A60', textColor: '#FFFFFFFF' }));
  const themedTitles = reader.buildReaderV2RegexStyles(document);
  assert.equal(themedTitles.length, 2, 'both title segments use the theme title emphasis');
  assert.equal(themedTitles[0].backgroundEnabled, true);
  sandbox.AppStorage.setOrCreate('themeLightTitleEmphasis', JSON.stringify({ mode: 'none' }));
  assert.equal(reader.buildReaderV2RegexStyles(document).length, 0, 'a theme can say titles get no emphasis');
  sandbox.AppStorage.setOrCreate('themeLightTitleEmphasis', '');
  console.log('PASS: independent title emphasis, secondary size, transparent colors, and title/regex precedence');

  const input = new Input(); input.viewportWidthPx = 320; input.viewportHeightPx = 900;
  input.fontSizePx = 20; input.titleFontSizePx = 22; input.titleSecondaryScale = 1.5; input.titleLineGapPx = 16;
  const snapshot = Snapshot.create(input);
  assert.equal(Paginator.baseTextStyle(document.blocks[1], snapshot).fontSize, 33);
  for (const key of ['titleSecondaryScale','titleLineGapPx']) {
    input[key]++;
    assert.notEqual(Snapshot.create(input).identity, snapshot.identity);
    input[key]--;
  }
  const continuous = Paginator.layoutContinuous(document, snapshot, []);
  const first = continuous.fragments[0], second = continuous.fragments[1];
  assert.equal(second.paragraphY - (first.paragraphY + first.paragraphHeight), 16);
  const pages = Paginator.paginate(document, snapshot, []);
  assert.equal(pages.complete, true);
  assert.equal(pages.pages[0].fragments[1].paragraphY, second.paragraphY);
  const page = new Page(); page.fragments = [new Fragment(),new Fragment(),new Fragment()];
  page.fragments[1].titleContinuation = true;
  Paginator.alignPageBottom(page, [0,0,0], 6, snapshot);
  assert.equal(page.fragments[1].paragraphY, 0, 'page-bottom distribution must not expand the title gap');
  // 行间摊完后余下的零头全部分给能加距离的块间隙（这里只有一处）。
  assert.equal(page.fragments[2].paragraphY, 6);

  // 章首饰图：左侧时标题每行让出饰图的宽度、饰图上下居中于标题组；上方、下方时算进标题的上、下边距。
  const HeadStyle = sandbox.titleApi.ReaderV2ChapterHeadStyle;
  const withHead = (placement, scale) => {
    input.chapterHead = Object.assign(new HeadStyle(), { image: 'file://head.png', aspect: 0.5, placement, scale,
      numberColor: 0xFF8D8478 });
    const headSnapshot = Snapshot.create(input);
    input.chapterHead = new HeadStyle();
    return [headSnapshot, Paginator.layoutContinuous(document, headSnapshot, [])];
  };
  assert.equal(continuous.decorations.length, 0, 'no ornament without a theme image');
  const [sideSnapshot, side] = withHead('side', 1);
  assert.notEqual(sideSnapshot.identity, snapshot.identity, 'the ornament is part of the layout identity');
  const nominal = 22 * 1.25 + 16 + 22 * 1.5 * 1.25;
  const sideWidth = nominal * 0.5;
  assert.equal(side.decorations.length, 1);
  const sideRect = side.decorations[0].rect;
  assert(Math.abs(sideRect.right - sideRect.left - sideWidth) < 0.01 && Math.abs(sideRect.bottom - sideRect.top - nominal) < 0.01);
  assert.equal(sideRect.left, sideSnapshot.columnRects[0].left, 'the side ornament hugs the column edge');
  const reserve = sideWidth + 22 * 0.35;
  assert(Math.abs(side.fragments[0].paragraphX - first.paragraphX - reserve) < 0.01, 'title lines start after the ornament');
  assert(Math.abs(side.fragments[1].leadReservePx - reserve) < 0.01);
  assert.equal(side.fragments[2].paragraphX, continuous.fragments[2].paragraphX, 'body text keeps the full width');
  const groupCentre = (side.fragments[0].paragraphY + side.fragments[1].paragraphY + side.fragments[1].paragraphHeight) / 2;
  assert(Math.abs((sideRect.top + sideRect.bottom) / 2 - groupCentre) < 0.01, 'vertically centred on the title group');
  assert.equal(Paginator.baseTextStyle(document.blocks[0], sideSnapshot).color.red, 0x8D, 'number line takes the theme colour');
  assert.equal(Paginator.baseTextStyle(document.blocks[1], sideSnapshot).color.red,
    Paginator.baseTextStyle(document.blocks[1], snapshot).color.red, 'the main title line keeps the text colour');
  const [, top] = withHead('top', 2);
  const topHeight = 22 * 0.9 * 2, topGap = 22 * 0.3;
  assert(Math.abs(top.fragments[0].paragraphY - first.paragraphY - topHeight - topGap) < 0.01, 'room above the title');
  assert(Math.abs(top.decorations[0].rect.bottom - (top.fragments[0].paragraphY - topGap)) < 0.01);
  assert.equal(top.fragments[0].paragraphX, first.paragraphX, 'no side reserve for a top ornament');
  const [, bottom] = withHead('bottom', 1);
  const bottomTitleEnd = bottom.fragments[1].paragraphY + bottom.fragments[1].paragraphHeight;
  assert(Math.abs(bottom.decorations[0].rect.top - bottomTitleEnd - topGap) < 0.01);
  assert(bottom.fragments[2].paragraphY - bottomTitleEnd >=
    continuous.fragments[2].paragraphY - (second.paragraphY + second.paragraphHeight) + 22 * 0.9 + topGap - 0.01,
    'body starts below a bottom ornament');
  console.log('PASS: chapter-head ornament reserves its space beside, above or below the title and tints the number line');

  // 首字装饰：首字单独画，首段拆成绕着它的前几行和回到整行的其余部分；两截之间没有段间距，也不多出换行。
  // 假排版引擎：汉字宽 = 字号，行高 = 字号 × 1.2 + 行距，基线在行顶下 0.8 个字号。
  {
  const capInput = new Input(); capInput.viewportWidthPx = 320; capInput.viewportHeightPx = 900;
  capInput.fontSizePx = 20; capInput.titleFontSizePx = 22; capInput.lineSpacingPx = 10; capInput.paragraphSpacingPx = 30;
  const capSnapshot = (lines, image = '') => {
    capInput.chapterHead = Object.assign(new HeadStyle(), { capLines: lines, capImage: image, capColor: 0xFFB5402F });
    const result = Snapshot.create(capInput);
    capInput.chapterHead = new HeadStyle();
    return result;
  };
  const capBody = '\u3000\u3000' + '傍晚的风从垭口灌进来晒谷场上的竹匾被掀得直响'.repeat(3);
  const capDocument = () => Parser.parse(`第一章\n${capBody}\n第二段文字。`, 0, '第一章', [], new Settings());
  const plainLayout = Paginator.layoutContinuous(capDocument(), Snapshot.create(capInput), []);
  assert.equal(plainLayout.fragments.length, 3);
  assert.equal(plainLayout.decorations.length, 0);
  const capLayout = Paginator.layoutContinuous(capDocument(), capSnapshot(2), []);
  assert.equal(capLayout.fragments.length, 4, 'title, wrapped lines, full-width rest, next paragraph');
  const [, lead, rest, nextParagraph] = capLayout.fragments;
  const pitch = 20 * 1.2 + 10, capBox = pitch + 20 * 1.2 - 20 * 0.05 * 2, capReserve = capBox + 20 * 0.3;
  assert.equal(lead.localStart, 3, 'the wrapped slice starts after the indent and the cap');
  assert(Math.abs(lead.leadReservePx - capReserve) < 0.01 && Math.abs(lead.paragraphX - plainLayout.fragments[1].paragraphX - capReserve) < 0.01);
  assert.equal(lead.paragraph.getLineCount(), 2, 'exactly the configured number of lines wrap around the cap');
  assert.equal(lead.paragraph.getLineMetrics(0).endIndex, Math.floor((320 - capReserve) / 20));
  assert.equal(rest.localStart, lead.localEnd, 'the rest continues where the wrapped lines end');
  assert.equal(rest.localEnd, capBody.length);
  assert.equal(rest.paragraphX, plainLayout.fragments[1].paragraphX, 'the rest uses the full width');
  assert(Math.abs(rest.paragraphY - (lead.paragraphY + 2 * pitch)) < 0.01, 'line pitch is kept across the two slices');
  assert.equal(rest.blockContinuation, true);
  assert.equal(lead.selectionBreakAfter, false, 'no line break inside the paragraph for the selection layer');
  assert.equal(capLayout.selectionText.split('\n').length, 3);
  assert(nextParagraph.paragraphY - (rest.paragraphY + rest.paragraphHeight) >= 30 - 0.01, 'paragraph spacing resumes after it');
  assert.equal(capLayout.decorations.length, 1);
  const capRect = capLayout.decorations[0].rect;
  assert(Math.abs(capRect.right - capRect.left - capBox) < 0.01 && Math.abs(capRect.bottom - capRect.top - capBox) < 0.01);
  assert(Math.abs(capRect.top - (lead.paragraphY + 20 * 0.05)) < 0.01, 'the box starts just inside the first line\'s text band');
  assert(Math.abs(capRect.bottom - (lead.paragraphY + pitch + 20 * 1.2 - 20 * 0.05)) < 0.01, 'and ends just inside the last wrapped line\'s');
  assert.equal(capLayout.decorations[0].glyph.text, '傍');
  assert.equal(capLayout.decorations[0].image, '');
  assert.equal(Paginator.layoutContinuous(capDocument(), capSnapshot(3, 'file://seal.png'), []).fragments[1].paragraph.getLineCount(), 3);
  assert.equal(Paginator.layoutContinuous(capDocument(), capSnapshot(3, 'file://seal.png'), []).decorations[0].image, 'file://seal.png');
  // 首段比首字矮：下一段从首字底边之后开始。
  const shortLayout = Paginator.layoutContinuous(Parser.parse('第一章\n\u3000\u3000风起了。\n第二段文字。', 0, '第一章', [], new Settings()),
    capSnapshot(3), []);
  assert.equal(shortLayout.fragments.length, 3, 'a short paragraph has no full-width rest');
  assert(shortLayout.fragments[2].paragraphY >= shortLayout.decorations[0].rect.bottom - 0.01);
  // 开头是引号、标题后先是图片、没有标题的文档：不做首字。
  for (const source of ['第一章\n\u3000\u3000“来了。”他说完就走了，风从垭口灌进来。', '\u3000\u3000傍晚的风从垭口灌进来。\n第二段。']) {
    const skipped = Paginator.layoutContinuous(Parser.parse(source, 0, '第一章', [], new Settings()), capSnapshot(2), []);
    assert.equal(skipped.decorations.length, 0, source);
    assert.equal(skipped.fragments.every(fragment => fragment.leadReservePx === 0), true);
  }
  // 页底放不下首字连同绕排的几行时，整体挪到下一页。
  capInput.viewportHeightPx = 22 * 1.2 + 30 + pitch + 8;
  const capPages = Paginator.paginate(capDocument(), capSnapshot(2), []);
  capInput.viewportHeightPx = 900;
  assert.equal(capPages.pages[0].fragments.length, 1, 'only the title stays on the first page');
  assert.equal(capPages.pages[0].decorations.length, 0);
  assert.equal(capPages.pages[1].fragments[0].dropCapBoxPx > 0, true);
  assert.equal(capPages.pages[1].decorations.length, 1);
  console.log('PASS: drop cap splits the first paragraph around the cap, keeps it together and skips unsuitable openings');

  // 首字放大：方框和下沉一样高，但底边对齐第一行文字、向上抬出；只有第一行绕排，段前多留 (行数 − 1) 行。
  const raiseSnapshot = (lines) => {
    capInput.chapterHead = Object.assign(new HeadStyle(), { capLines: lines, capRaise: true });
    const result = Snapshot.create(capInput);
    capInput.chapterHead = new HeadStyle();
    return result;
  };
  assert.notEqual(raiseSnapshot(2).identity, capSnapshot(2).identity, 'the style is part of the layout identity');
  for (const lines of [2, 3, 4]) {
    const raised = Paginator.layoutContinuous(capDocument(), raiseSnapshot(lines), []);
    const [, raisedLead, raisedRest] = raised.fragments;
    const rise = (lines - 1) * pitch, box = (lines - 1) * pitch + 20 * 1.2 - 20 * 0.05 * 2;
    assert.equal(raisedLead.paragraph.getLineCount(), 1, 'only the first line wraps around a raised cap');
    assert(Math.abs(raisedLead.paragraphY - capLayout.fragments[1].paragraphY - rise) < 0.01, 'room above for the raised part');
    assert(Math.abs(raisedRest.paragraphY - (raisedLead.paragraphY + pitch)) < 0.01, 'the second line follows at the normal pitch');
    assert.equal(raisedRest.paragraphX, plainLayout.fragments[1].paragraphX, 'from the second line on the full width is used');
    const rect = raised.decorations[0].rect;
    assert(Math.abs(rect.bottom - rect.top - box) < 0.01);
    assert(Math.abs(rect.bottom - (raisedLead.paragraphY + 20 * 1.2 - 20 * 0.05)) < 0.01, 'the box ends with the text of the first line');
    assert(rect.top >= capLayout.fragments[0].paragraphY + capLayout.fragments[0].paragraphHeight - 0.01, 'and stays below the title');
    assert(raisedLead.dropCapSpanPx > 0 && raisedLead.dropCapSpanPx < pitch, 'the selection layer indents only the first line');
  }
  // 下沉 4 行：绕排 4 行。
  assert.equal(Paginator.layoutContinuous(capDocument(), capSnapshot(4), []).fragments[1].paragraph.getLineCount(), 4);
  // 首字放大落在页首（标题在上一页）时，抬出的部分也留在版心里。
  capInput.viewportHeightPx = 22 * 1.2 + 30 + pitch + 8;
  const raisedPages = Paginator.paginate(capDocument(), raiseSnapshot(3), []);
  capInput.viewportHeightPx = 900;
  const raisedPage = raisedPages.pages.find(page => page.decorations.length > 0);
  assert(raisedPage && raisedPage.decorations[0].rect.top >= raisedPage.fragments[0].paragraphY - 2 * pitch - 0.01);
  assert(raisedPage.decorations[0].rect.top >= 0, 'the raised cap is not drawn above the page');
  console.log('PASS: raised drop cap sits on the first line, rises above it and wraps only that line');
  }

  for (const alignment of ['left','center','right']) {
    input.titleAlignment = alignment;
    input.titleMarginTopPx = 24; input.titleMarginBottomPx = 36;
    const alignedSnapshot = Snapshot.create(input);
    assert.notEqual(alignedSnapshot.identity, snapshot.identity);
    const layout = Paginator.layoutContinuous(document, alignedSnapshot);
    const [head, tail, body] = layout.fragments;
    near(head.paragraphY - first.paragraphY, 24);
    near(tail.paragraphY - head.paragraphY - head.paragraphHeight, 16,
      'split segments share one outer margin and retain their own line gap');
    near(body.paragraphY - tail.paragraphY - tail.paragraphHeight, 36);
    assert.equal(head.paragraph.alignment, alignment);
    assert.equal(tail.paragraph.alignment, alignment);
    assert.equal(body.paragraph.alignment, 'justify', 'title alignment does not override body alignment');
    const boxes = head.paragraph.getRectsForRange({start:0,end:head.localEnd});
    if (alignment === 'left') assert.equal(boxes[0].rect.left, 0);
    if (alignment === 'right') assert.equal(boxes[0].rect.right, input.viewportWidthPx);
    const paged = Paginator.paginate(document, alignedSnapshot);
    assert.equal(paged.pages[0].fragments[0].paragraphY, head.paragraphY);
    assert.equal(paged.pages[0].fragments[2].paragraphY, body.paragraphY);
  }
  const styledSnapshot = Snapshot.create(input);
  const titleOnly = Paginator.layoutContinuous(Parser.parse(title,0,title,[],settings), styledSnapshot);
  const titleTail = titleOnly.fragments.at(-1);
  assert.equal(titleOnly.contentBottomPx, titleTail.paragraphY + titleTail.paragraphHeight + 36,
    'a chapter containing only a title retains the trailing margin in scrolling height');
  const titleImageDocument = Parser.parse(`${title}\n图\n正文`,0,title,[],settings);
  titleImageDocument.blocks[2].image = {source:'fixture-image',width:80,height:40};
  const titleImage = Paginator.layoutContinuous(titleImageDocument, styledSnapshot);
  const imageGap = titleImage.fragments[2].paragraphY - titleImage.fragments[1].paragraphY -
    titleImage.fragments[1].paragraphHeight;
  near(imageGap, 46, 'an illustration after the title also respects the title bottom margin');
  const locked = new Page(); locked.fragments = [new Fragment(),new Fragment(),new Fragment(),new Fragment()];
  locked.fragments[1].titleContinuation = true;
  locked.fragments[2].fixedGapBefore = true;
  Paginator.alignPageBottom(locked,[0,0,0,0],6,styledSnapshot);
  assert.equal(locked.fragments[1].paragraphY, 0);
  assert.equal(locked.fragments[2].paragraphY, 0);
  assert.equal(locked.fragments[3].paragraphY, 6);
  const short = new Input(); short.viewportWidthPx = 320; short.viewportHeightPx = 70;
  short.fontSizePx = 20; short.titleFontSizePx = 22; short.titleSecondaryScale = 1.5;
  short.titleMarginTopPx = 120; short.titleMarginBottomPx = 120;
  const shortPages = Paginator.paginate(document, Snapshot.create(short));
  assert(shortPages.complete && shortPages.pages.length > 1);
  assert(shortPages.pages.every(item => item.fragments.length > 0), 'large margins never create empty pages');
  const nextTitle = shortPages.pages.find(item => item.fragments[0].titleContinuation);
  assert(nextTitle && nextTitle.fragments[0].paragraphY < 5, 'continuing title pages do not repeat top margins');
  const nextBody = shortPages.pages.find(item => !item.fragments[0].title);
  assert(nextBody && nextBody.fragments[0].paragraphY < 5, 'body on a new page does not repeat title bottom margins');
  for (const key of ['titleMarginTopPx','titleMarginBottomPx']) {
    input[key]++;
    assert.notEqual(Snapshot.create(input).identity, styledSnapshot.identity);
    input[key]--;
  }
  console.log('PASS: left/center/right alignment, outer group margins, image gaps, title-only scroll height and short-page boundaries');

  settings.emphasis.emphasisMode = 'custom'; settings.emphasis.customTextColorEnabled = false;
  settings.emphasis.customBubbleEnabled = true; settings.emphasis.bubbleStyleId = 'crimson-stamp';
  settings.emphasis.customBubbleColor = '#891E25'; reader.readerTitleStyleRaw = Codec.encode(settings);
  assert.equal(reader.buildReaderV2RegexStyles(document)[0].decorationEnabled, false,
    'title styles enforce the same theme access policy as regex fonts');
  fixture.ThemeRuntime.applyTheme('crimson-archive');
  const decorated = reader.buildReaderV2RegexStyles(document);
  const decoratedLayout = Paginator.layoutContinuous(document, snapshot, decorated);
  const bubbles = decoratedLayout.fragments.flatMap(fragment => fragment.regexBubbleSegments);
  assert(bubbles.length >= 2, JSON.stringify(decorated));
  assert(bubbles.every(bubble => bubble.leading && bubble.trailing), 'every wrapped title line is enclosed');
  assert(bubbles.every(bubble => bubble.rect.left >= 0 && bubble.rect.right <= input.viewportWidthPx));
  assert(bubbles.every(bubble => bubble.leadingCapWidthPx > 0 && bubble.trailingCapWidthPx > 0),
    'the title reserves horizontal room for both caps instead of painting them over the glyphs');
  console.log('PASS: paged/continuous geometry, exact title gap, cache invalidation and complete per-line title bubbles');

  // 主题包边框：文字带高度是字号的 1.36 倍；标题每行都画两端，正文整段首尾留位，平切时换行处不画端头。
  const Style = decorated[0].constructor;
  const frameFields = { decorationSizePx: 0, frameAsset: 'file://frame.png', frameAspect: 4, frameSliceLeft: 0.2,
    frameSliceRight: 0.25, frameSliceTop: 0.1, frameSliceBottom: 0.1 };
  const framedTitles = decorated.map(item => Object.assign(new Style(item.start, item.end), item, frameFields));
  const titleFrames = Paginator.layoutContinuous(document, snapshot, framedTitles).fragments
    .flatMap(fragment => fragment.regexBubbleSegments);
  assert(titleFrames.length >= 2);
  for (const frame of titleFrames) {
    assert(Math.abs(frame.frameRect.bottom - frame.frameRect.top - frame.fontSizePx * 1.36) < 0.01);
    assert(frame.frameLeadEnd && frame.frameTrailEnd && frame.leadingCapWidthPx === 0);
    assert(frame.frameRect.left >= 0 && frame.frameRect.right <= input.viewportWidthPx);
    assert.equal(frame.frameAsset, 'file://frame.png');
  }
  const longDoc = Parser.parse(`${title}
${'雨停的时候他把伞靠在门边问柜台后的老人这本账簿是谁送来的'.repeat(3)}`,
    0, title, [], settings);
  const body = longDoc.blocks.find(block => !block.title && block.text.length > 60);
  assert(body, 'fixture has a long body paragraph');
  const run = Object.assign(new Style(body.displayStart + 4, body.displayStart + 58), decorated[0], frameFields,
    { start: body.displayStart + 4, end: body.displayStart + 58, repeatCaps: false, frameCut: true });
  const bodyFrames = Paginator.layoutContinuous(longDoc, snapshot, [run]).fragments
    .flatMap(fragment => fragment.regexBubbleSegments);
  assert(bodyFrames.length >= 2, 'the framed run wraps');
  assert(bodyFrames[0].leading && bodyFrames[0].frameLeadEnd && !bodyFrames[0].frameTrailEnd);
  assert(bodyFrames.at(-1).trailing && bodyFrames.at(-1).frameTrailEnd && !bodyFrames.at(-1).frameLeadEnd);
  const lead = run.fontSizePx * 1.36 / 0.8 * 0.2 * 4;
  const plain = Paginator.layoutContinuous(longDoc, snapshot, [Object.assign(new Style(run.start, run.end), run,
    { frameAsset: '' })]);
  assert.equal(plain.fragments.flatMap(fragment => fragment.regexBubbleSegments).length, 0,
    'without a frame or cap the run stays a native text background');
  assert(lead > 10 && bodyFrames[0].frameRect.right - bodyFrames[0].frameRect.left > lead);
  console.log('PASS: theme frames align to a fixed text band, enclose title lines and cut flat at body line breaks');

  const singleInput = new Input();
  singleInput.viewportWidthPx = 320; singleInput.viewportHeightPx = 900;
  singleInput.titleFontSizePx = 22; singleInput.titleSecondaryScale = 1.5; singleInput.titleLineGapPx = 16;
  singleInput.titleMarginTopPx = 24; singleInput.titleMarginBottomPx = 36;
  singleInput.fontSizePx = 20; singleInput.titleSinglePage = true;
  const singleSnapshot = Snapshot.create(singleInput);
  const isolated = Paginator.paginate(document, singleSnapshot);
  assert(isolated.complete);
  assert.equal(isolated.pages.length, 2);
  assert.equal(isolated.pages[0].fragments.length, 2, 'both split title segments share the same title page');
  assert(isolated.pages[0].fragments.every(fragment => fragment.title));
  assert(isolated.pages[1].fragments.every(fragment => !fragment.title));
  assert.equal(isolated.pages[0].sourceStart, 0);
  assert.equal(isolated.pages[0].sourceEnd, title.length);
  assert.equal(isolated.pages[1].sourceStart, title.length + 1);
  assert.equal(isolated.pages[0].fragments[0].selectionRuns[0].fontSizePx, 22,
    'a fitting title retains its configured font size');
  const incremental = Paginator.start(document, singleSnapshot);
  assert.equal(Paginator.appendPages(incremental,1), 1);
  assert.equal(incremental.pageSet.complete, false);
  assert.equal(Paginator.appendPages(incremental,1), 1);
  assert.equal(incremental.pageSet.complete, true);
  assert.equal(incremental.pageSet.pages.length, 2);
  const oneTitle = Parser.parse(title,0,title,[],settings);
  assert.equal(Paginator.paginate(oneTitle,singleSnapshot).pages.length, 1, 'no empty body page for title-only chapters');
  const missingTitle = Parser.parse('正文没有标题。',0,'不匹配的标题',[],settings);
  assert.equal(Paginator.paginate(missingTitle,singleSnapshot).pages.length, 1, 'missing titles do not create empty pages');
  const volume = Parser.parse(`卷一\n${chapter}`,0,title,[{level:1,text:'卷一'}],settings);
  const volumePages = Paginator.paginate(volume,singleSnapshot);
  assert.equal(volumePages.pages.length, 3);
  assert.equal(volumePages.pages[0].fragments[0].title, false);
  assert(volumePages.pages[1].fragments.every(fragment => fragment.title));
  assert.equal(volumePages.pages[1].fragments[0].blockIndex, 1,
    'isolated page fragments retain their original document block indexes');
  const scrollSingle = Paginator.layoutContinuous(document,singleSnapshot);
  assert.equal(scrollSingle.fragments[2].paragraphY, 900, 'scrolling body starts after one full title screen');
  assert.equal(Paginator.layoutContinuous(oneTitle,singleSnapshot).contentBottomPx, 900);
  const scrollVolume = Paginator.layoutContinuous(volume,singleSnapshot);
  assert.equal(scrollVolume.fragments[1].paragraphY, 925);
  assert.equal(scrollVolume.fragments[3].paragraphY, 1800);
  const imagePages = Paginator.paginate(titleImageDocument,singleSnapshot);
  assert(imagePages.pages[0].fragments.every(fragment => fragment.title));
  assert(imagePages.pages[1].fragments[0].imageSource);
  const offInput = new Input(); offInput.viewportWidthPx = 320; offInput.viewportHeightPx = 900;
  assert.notEqual(Snapshot.create(offInput).identity, singleSnapshot.identity);
  singleInput.titleSinglePage = false;
  assert.notEqual(Snapshot.create(singleInput).identity, singleSnapshot.identity);
  assert.equal(Paginator.paginate(document,Snapshot.create(singleInput)).pages.length, 1);
  console.log('PASS: dedicated split-title pages, incremental pagination, volume/image boundaries, scrolling screens and disabling');

  const longTitle = '第九百九十九章：' + '这是一段很长的章节标题'.repeat(12);
  const longDocument = Parser.parse(`${longTitle}\n普通正文。`,0,longTitle,[],settings);
  const longInput = new Input(); longInput.viewportWidthPx = 160; longInput.viewportHeightPx = 200;
  longInput.fontSizePx = 20; longInput.titleFontSizePx = 80; longInput.titleSecondaryScale = 2;
  longInput.titleMarginTopPx = 120; longInput.titleMarginBottomPx = 120; longInput.titleSinglePage = true;
  reader.readerTitleFontSize = 80;
  const longStyles = reader.buildReaderV2RegexStyles(longDocument);
  const originalStyles = JSON.stringify(longStyles);
  const longPages = Paginator.paginate(longDocument,Snapshot.create(longInput),longStyles);
  assert.equal(longPages.pages.length, 2, 'even a very long decorated title fits one isolated page');
  assert(longPages.pages[0].fragments.every(fragment => fragment.title && fragment.clipRect.bottom <= 200.01));
  assert(longPages.pages[0].fragments[0].selectionRuns[0].fontSizePx < 80);
  assert.equal(longPages.pages[1].fragments[0].selectionRuns[0].fontSizePx, 20, 'title fitting never shrinks prose');
  assert.equal(longPages.pages[0].sourceEnd, longTitle.length);
  assert.equal(JSON.stringify(longStyles),originalStyles, 'fitting leaves chapter style objects unchanged');
  assert.equal(longDocument.copyText(0,longTitle.length),longTitle);
  console.log('PASS: oversized decorated titles scale into a single page without clipping, changing text or shrinking body fonts');

  // Exercise the settings page's real model and the preview's real measure/draw node with non-default typography.
  sandbox.FrameNode = class {
    getRenderNode() { return null; }
    setMeasuredSize(size) { this.measuredSize = size; }
    setLayoutPosition() {}
  };
  // 设置页预览这里只看标题排版，主题不带章首装饰。
  sandbox.ReaderChapterHead = { style: () => new sandbox.titleApi.ReaderV2ChapterHeadStyle() };
  if (sandbox.ThemeRuntime && !sandbox.ThemeRuntime.chapterHeadTokens) sandbox.ThemeRuntime.chapterHeadTokens = () => null;
  const renderSource = read('core/reader/ReaderV2RenderNode.ets');
  const previewSource = read('components/reader/ReaderTypographyPreview.ets');
  vm.runInContext(compile(read('core/reader/ReaderParagraphIndent.ts')) + '\n' +
    compile(renderSource.slice(0, renderSource.indexOf('export class ReaderV2PageNodeController'))) + '\n' +
    compile(previewSource.slice(0, previewSource.indexOf('class ReaderTypographyPreviewController'))) + '\n' +
    compile(`class FontPreviewHarness extends ReaderHarness {
      titleStyle = new ReaderTitleStyleSettings();
      titlePreviewText = '第七十四章：卖鸭蛋，卖粽子喽';
      readerFontSize = 30; readerTitleFontSize = 22;
      readerFontWeight = 550; readerTitleFontWeight = 600;
      readerRegexFontEnabled = false; regexRules = []; titleReadingPreviewHeight = 640;
      previewLayoutSettings = { lineHeight: 24, paragraphSpacing: 17, paragraphIndent: 3,
        letterSpacing: 2, textAlign: 'end', marginLeft: 23, marginRight: 31, marginTop: 19, marginBottom: 27 };
      getUIContext() { return { vp2px: n => n * 3, fp2px: n => n * 3.6,
        px2vp: n => n / 3, px2fp: n => n / 3.6 }; }
      bodyPreviewFontFamily() { return ''; } titlePreviewFontFamily() { return ''; }
      previewFontFamily() { return ''; }
      regexEmphasisContext() { return this.readerRegexEmphasisContext(); }
      ${['typographyPreviewConfig','typographyPreviewContext','typographyPreviewEmphasis','typographyPreviewRegexStyles',
        'titleEmphasisPlan'].map(fontMethod).join('\n')}
    }
    globalThis.previewApi = { FontPreviewHarness, ReaderTypographyPreviewNode, ReaderTypographyPreviewConfig,
      ReaderV2PageFrameNode };
  `), sandbox);
  const previewHost = new sandbox.previewApi.FontPreviewHarness();
  previewHost.titleStyle.alignment = 'left';
  previewHost.titleStyle.marginTop = 11; previewHost.titleStyle.marginBottom = 29;
  const previewConfig = previewHost.typographyPreviewConfig(true);
  near(previewConfig.input.fontSizePx, 108, 'preview respects font scale separately from vp');
  near(previewConfig.input.titleFontSizePx, 79.2, 'title retains its own configured size');
  assert.equal(previewConfig.input.lineSpacingPx, 72);
  assert.equal(previewConfig.input.titleLineGapPx, 72, 'unsplit wrapped title follows reader line spacing');
  assert.equal(previewConfig.input.paragraphSpacingPx, 51);
  assert.equal(previewConfig.input.letterSpacingPx, 7.2);
  assert.equal(previewConfig.input.textAlign, 'end');
  assert.equal(previewConfig.document.blocks[1].text.startsWith('　　　清晨'), true);
  const PreviewNode = sandbox.previewApi.ReaderTypographyPreviewNode;
  const previewNode = new PreviewNode(previewHost.getUIContext(), previewConfig);
  const bounds = { maxSize: { width: 1320, height: 100000 }, minSize: { height: 0 } };
  const frozenConfig = JSON.stringify(previewConfig.input);
  previewNode.onMeasure(bounds);
  assert.equal(JSON.stringify(previewConfig.input), frozenConfig, 'measuring never changes settings or draft data');
  const actualInput = Object.assign(new Input(), previewConfig.input,
    { viewportWidthPx: 1320, viewportHeightPx: 1920 });
  const actualPage = Paginator.layoutContinuous(previewConfig.document, Snapshot.create(actualInput), previewConfig.styles);
  const geometry = page => page.fragments.map(fragment => ({
    title: fragment.title, x: fragment.paragraphX, y: fragment.paragraphY,
    height: fragment.paragraphHeight, clip: { ...fragment.clipRect },
    runs: fragment.selectionRuns.map(run => ({ text: run.text, fontSize: run.fontSizePx,
      spacing: run.letterSpacingPx, weight: run.fontWeight }))
  }));
  assert.deepEqual(geometry(previewNode.page), geometry(actualPage), 'same-width preview matches real reader geometry');
  assert.equal(previewNode.measuredSize.height, actualPage.contentBottomPx + 81);
  assert.equal(previewNode.page.fragments[1].paragraph.alignment, 'right');
  assert(previewNode.page.fragments[1].paragraph.getLineMetrics().length > 1);
  const firstBody = previewNode.page.fragments[1];
  near(firstBody.paragraph.getLineMetrics()[1].topHeight, 108 * 1.2 + 72,
    'preview uses native reader line spacing rather than compact sample lines');
  assert.equal(Object.getPrototypeOf(PreviewNode.prototype), sandbox.previewApi.ReaderV2PageFrameNode.prototype,
    'preview inherits the actual glyph, outline and decoration painter');

  previewHost.titleStyle.mode = 'marker'; previewHost.titleStyle.marker = '：';
  previewHost.titleStyle.lineGap = 9; previewHost.titleStyle.secondaryScale = 1.6;
  previewHost.titleStyle.singlePage = true;
  previewHost.previewLayoutSettings.paragraphIndent = 0;
  previewHost.previewLayoutSettings.letterSpacing = -1;
  const singlePreview = previewHost.typographyPreviewConfig(true);
  assert.equal(singlePreview.input.titleLineGapPx, 27);
  assert.equal(singlePreview.document.blocks[2].text.startsWith('清晨'), true, 'zero indent is preserved');
  const singleNode = new PreviewNode(previewHost.getUIContext(), singlePreview);
  singleNode.onMeasure(bounds);
  const prose = singleNode.page.fragments.find(fragment => !fragment.title);
  assert(prose.paragraphY >= 1920 - 81, 'single-page title reserves a real screen before prose');
  near(singleNode.page.fragments[1].selectionRuns[0].fontSizePx, 79.2 * 1.6);
  const cardConfig = previewHost.typographyPreviewConfig(false);
  assert.equal(cardConfig.input.titleSinglePage, false, 'compact card never creates a screen-sized blank page');
  assert(cardConfig.document.blocks.every(block => block.title));
  previewHost.titleStyle.emphasis.emphasisMode = 'custom';
  const decoratedPreview = previewHost.typographyPreviewConfig(true);
  assert.equal(decoratedPreview.styles.length, 2);
  assert(decoratedPreview.styles.every(style => style.repeatCaps && style.fontWeight === 600));
  previewHost.readerRegexFontEnabled = true;
  previewHost.regexRules = [{ pattern: '[', fontSize: 40 }, { pattern: '^', fontSize: 40 },
    { pattern: '清晨', fontSize: 40, fontMode: 'global', fontFamily: '', fontWeight: 400, emphasisMode: 'none' }];
  const regexPreview = previewHost.typographyPreviewConfig(true);
  assert.equal(regexPreview.styles.length, 3, 'invalid and empty matches are skipped while body regex styles survive');
  assert.equal(regexPreview.styles[2].fontSizePx, 144);
  console.log('PASS: settings preview matches reader geometry, scaled fonts, spacing, alignment, indents, title pages and emphasis');

  sandbox.FrameNode = class {
    setMeasuredSize(size) { this.measuredSize = size; }
    setLayoutPosition() {}
  };
  sandbox.text = { ...sandbox.graphicsText, TextDecorationType: { NONE: 0 },
    PlaceholderAlignment: { CENTER_OF_ROW_BOX: 0 }, TextBaseline: { ALPHABETIC: 0 } };
  sandbox.ReaderFontStroke = { paint() {} };
  const weighted = read('components/reader/ReaderWeightedText.ets');
  vm.runInContext(compile(read('core/reader/ReaderFontTextStyle.ets')) + '\n' +
    compile(weighted.slice(0, weighted.indexOf('class ReaderWeightedTextController'))) +
    '\nglobalThis.weightedApi = { ReaderWeightedTextSpan, ReaderWeightedTextNode };', sandbox);
  const context = { fp2px: value => value, vp2px: value => value };
  const span = sandbox.weightedApi.ReaderWeightedTextSpan.create(context, title, 30, '', '#202124');
  span.capStyleId = 'crimson-stamp'; span.capSizePx = 22; span.repeatCaps = true;
  const node = new sandbox.weightedApi.ReaderWeightedTextNode(context, [span], 400, 1000, 'center', 16);
  node.onMeasure({ maxSize: { width: 180, height: 2000 }, minSize: { height: 0 } });
  node.capImage = () => ({});
  const caps = [];
  node.onDraw({ canvas: { save() {}, restore() {}, rotate() {}, drawImageRect(_bitmap, rect) { caps.push(rect); } } });
  assert(caps.length > 2 && caps.length % 2 === 0);
  assert(caps.every(rect => rect.left >= 0 && rect.right <= 180));
  assert.equal(node.paragraph.text, title, 'repeated preview caps never add hidden selection characters');
  console.log('PASS: native settings preview repeats complete caps within narrow bounds without inserting placeholders');

  // The asynchronous path must keep exactly the same page geometry and source offsets as the native sync path.
  // This adapter tests transactions and cancellation, not device performance.
  sandbox.ReaderFontStroke = { paint() {} };
  const shape = set => JSON.parse(JSON.stringify(set.pages.map(page => ({
    from: page.sourceStart, to: page.sourceEnd, selection: page.selectionText,
    fragments: page.fragments.map(fragment => ({ start: fragment.displayStart, end: fragment.displayEnd,
      x: fragment.paragraphX, y: fragment.paragraphY, height: fragment.paragraphHeight,
      text: fragment.paragraph?.text, clip: fragment.clipRect }))
  }))));
  for (const columns of [1, 2]) for (const titleSinglePage of [false, true]) {
    const asyncInput = new Input();
    Object.assign(asyncInput, { viewportWidthPx: 360, viewportHeightPx: 240, fontSizePx: 20,
      titleFontSizePx: titleSinglePage ? 240 : 26, titleSinglePage, columnCount: columns, columnGapPx: 12,
      marginLeftPx: 8, marginRightPx: 8, marginTopPx: 8, marginBottomPx: 8 });
    const asyncDocument = Parser.parse(`${title}\n${'甲乙😀丙丁，ABC。'.repeat(70)}\n` +
      Array.from({ length: 12 }, (_, i) => `${i} 清晨${'文字'.repeat(i + 1)}`).join('\n'), 0, title);
    const expected = Paginator.paginate(asyncDocument, Snapshot.create(asyncInput));
    const session = Paginator.start(asyncDocument, Snapshot.create(asyncInput));
    let turns = 0;
    while (!session.pageSet.complete) {
      assert(++turns < 200, 'async pagination makes progress');
      const before = session.pageSet.pages.length;
      const added = await Paginator.appendPageAsync(session);
      assert.equal(added, session.pageSet.pages.length - before);
      assert(added <= 1, 'each transaction publishes at most one complete page');
    }
    assert.deepEqual(shape(session.pageSet), shape(expected), `async parity columns=${columns} title=${titleSinglePage}`);
    const continuousExpected = Paginator.layoutContinuous(asyncDocument, Snapshot.create(asyncInput));
    const continuousActual = await Paginator.layoutContinuousAsync(asyncDocument, Snapshot.create(asyncInput));
    assert.deepEqual(shape({ pages: [continuousActual] }), shape({ pages: [continuousExpected] }),
      `continuous async geometry/selection parity columns=${columns} title=${titleSinglePage}`);
    assert.equal(continuousActual.contentBottomPx, continuousExpected.contentBottomPx);
  }
  assert(asyncLayouts > 0, 'native asynchronous layout was exercised');
  const cancellationInput = new Input();
  Object.assign(cancellationInput, { viewportWidthPx: 240, viewportHeightPx: 240, fontSizePx: 20 });
  const cancellationDoc = Parser.parse('正文😀，'.repeat(120), 0, '');
  const cancelled = Paginator.start(cancellationDoc, Snapshot.create(cancellationInput));
  holdLayout = true;
  let valid = true;
  const cancelledWork = Paginator.appendPageAsync(cancelled, () => valid);
  const joinedWork = Paginator.appendPageAsync(cancelled, () => valid);
  assert.equal(heldLayouts.length, 1, 'concurrent callers share native layout');
  assert.equal(cancelled.pageSet.pages.length, 0, 'an unfinished page is private');
  valid = false;
  heldLayouts.shift()();
  assert.deepEqual(await Promise.all([cancelledWork, joinedWork]), [0, 0]);
  assert.equal(cancelled.blockIndex, 0); assert.equal(cancelled.lineIndex, 0);
  assert.equal(cancelled.pageSet.pages.length, 0);
  assert.equal(cancelled.paragraphCache, null); assert.equal(cancelled.inFlight, null);
  holdLayout = false; valid = true;
  rejectLayout = true;
  await assert.rejects(Paginator.appendPageAsync(cancelled), /native layout failed/);
  assert.equal(cancelled.blockIndex, 0); assert.equal(cancelled.lineIndex, 0);
  assert.equal(cancelled.paragraphCache, null); assert.equal(cancelled.inFlight, null);
  assert.equal(await Paginator.appendPageAsync(cancelled), 1, 'a failed or cancelled page can be retried');
  // The host's yield point runs before every synchronous page-breaking attempt and honours cancellation there.
  const yielded = Paginator.start(cancellationDoc, Snapshot.create(cancellationInput));
  let yields = 0;
  const layoutsBefore = asyncLayouts;
  assert.equal(await Paginator.appendPageAsync(yielded, () => true, async () => { yields++; }), 1);
  assert.equal(yields, asyncLayouts - layoutsBefore + 1, 'one yield per attempt: each native layout plus the final page');
  const yieldCancelled = Paginator.start(cancellationDoc, Snapshot.create(cancellationInput));
  let yieldValid = true;
  assert.equal(await Paginator.appendPageAsync(yieldCancelled, () => yieldValid, async () => { yieldValid = false; }), 0);
  assert.equal(yieldCancelled.pageSet.pages.length, 0, 'cancellation at the yield point publishes nothing');
  assert.equal(yieldCancelled.blockIndex, 0); assert.equal(yieldCancelled.lineIndex, 0);
  assert.equal(yieldCancelled.paragraphCache, null); assert.equal(yieldCancelled.inFlight, null);
  holdLayout = true;
  const staleContinuous = Paginator.layoutContinuousAsync(cancellationDoc, Snapshot.create(cancellationInput), [], () => valid);
  valid = false; heldLayouts.shift()();
  assert.equal(await staleContinuous, null, 'cancelled continuous layout does not publish a partial chunk');
  holdLayout = false;
  console.log('PASS: async/sync pagination parity, oversized titles, UTF-16 offsets, atomic pages, deduplication, cancellation and failure recovery');
} finally {
  modules.cleanup();
}
