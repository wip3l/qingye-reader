// Hot-comment cards: which paragraphs get one, how they paginate, and that turning them off leaves the
// layout exactly as before. Production document/pagination code runs on a small deterministic text adapter.
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

class ParagraphBuilder {
  constructor(options) { this.options = options; this.runs = []; }
  pushStyle(style) { this.current = style; }
  addText(text) { this.runs.push({ text, style: this.current || this.options.textStyle }); }
  popStyle() {}
  build() {
    const options = this.options, runs = this.runs;
    return {
      lines: [], chars: [], width: 0, text: runs.map(run => run.text).join(''),
      layout(width) { return new Promise(resolve => setTimeout(() => { this.layoutSync(width); resolve(); }, 0)); },
      layoutSync(width) {
        this.width = width;
        let offset = 0, start = 0, advance = 0, top = 0, fontSize = 0;
        const finish = () => {
          if (offset <= start) return;
          const height = fontSize * 1.2 + (options.lineSpacing || 0);
          this.lines.push({ startIndex: start, endIndex: offset, topHeight: top, height, width: advance,
            ascent: fontSize * 0.8, descent: fontSize * 0.2, baseline: top + fontSize * 0.8, x: 0 });
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
        if (options.maxLines && this.lines.length > options.maxLines) this.lines.length = options.maxLines;
      },
      getLineCount() { return this.lines.length; },
      getLineMetrics(index) { return index === undefined ? this.lines : this.lines[index]; },
      getAlphabeticBaseline() { return this.lines.length ? this.lines[0].baseline : 0; },
      getGlyphPositionAtCoordinate() { return { position: 0 }; },
      getWordBoundary() { return { start: 0, end: 0 }; },
      getLongestLine() { return Math.max(0, ...this.lines.map(line => line.width)); },
      getHeight() { return this.lines.reduce((sum, line) => sum + line.height, 0); },
      paint() {},
      getRectsForRange({ start, end }) {
        return this.lines.flatMap(line => {
          const chars = this.chars.filter(char => char.start >= Math.max(start, line.startIndex) &&
            char.end <= Math.min(end, line.endIndex));
          if (!chars.length) return [];
          return [{ rect: { left: chars[0].x, right: chars.at(-1).x + chars.at(-1).width,
            top: line.topHeight, bottom: line.topHeight + line.height - (options.lineSpacing || 0) } }];
        });
      }
    };
  }
}

const { sandbox } = loadObsidianReader();
const modules = await loadReaderModules();
try {
  Object.assign(sandbox, {
    ReaderActionMarker: modules.ReaderActionMarker, ReaderImageMarker: modules.ReaderImageMarker,
    ReaderMixedPageLayout: modules.ReaderMixedPageLayout, EpubNoteLink: modules.EpubNoteLink,
    graphicsText: {
      FontWeight: Object.fromEntries(Array.from({ length: 9 }, (_, i) => [`W${(i + 1) * 100}`, i])),
      TextAlign: { CENTER: 'center', LEFT: 'left', RIGHT: 'right', JUSTIFY: 'justify' },
      TextDirection: { LTR: 0 }, WordBreak: { BREAK_WORD: 0 }, BreakStrategy: { GREEDY: 0 },
      RectWidthStyle: { TIGHT: 0 }, RectHeightStyle: { TIGHT: 0, MAX: 1 }, EllipsisMode: { END: 2 },
      FontCollection: { getGlobalInstance: () => ({}) }, ParagraphBuilder
    }
  });
  vm.runInContext(['core/reader/ReaderV2Document.ets', 'core/reader/ReaderV2LayoutSnapshot.ets',
    'core/reader/ReaderV2CommentCard.ets', 'core/reader/ReaderV2PageLayout.ets', 'core/reader/ReaderV2Paginator.ets']
    .map(file => compile(read(file))).join('\n') + `
    globalThis.cardApi = { ReaderV2DocumentParser, ReaderV2SpeechText, ReaderV2Paginator, ReaderV2LayoutSnapshot,
      ReaderV2LayoutInput };`, sandbox);
  const { ReaderV2DocumentParser: Parser, ReaderV2SpeechText: Speech, ReaderV2Paginator: Paginator,
    ReaderV2LayoutSnapshot: Snapshot, ReaderV2LayoutInput: Input } = sandbox.cardApi;
  const Marker = modules.ReaderActionMarker;

  const bubble = (n, preview = '', likes = '') =>
    Marker.create(`段评 ${n}`, `https://c.example/p${n}`, '段评', preview, likes);
  const hotCard = text => Marker.create('热评', 'https://c.example/hot', '热评', text, '88');
  const source = [
    '标题',
    `　　第一段正文写在这里。${bubble(56, '老周活不过这一章', '312')}`,
    `　　第二段正文没有热评。${bubble(9)}`,
    hotCard('这句台词好帅'),
    '　　第三段正文。'
  ].join('\n');
  const document = Parser.parse(source, 0, '标题');
  const blocks = document.blocks;
  assert.equal(blocks.length, 5);
  assert.equal(blocks[1].trailingCard?.preview, '老周活不过这一章', 'a bubble with a hot comment gets a trailing card');
  assert.equal(blocks[1].trailingCard?.likes, '312');
  assert.equal(blocks[1].card, null);
  assert.equal(blocks[2].trailingCard, null, 'a bubble without a hot comment stays a bubble');
  assert.equal(blocks[3].card?.preview, '这句台词好帅', 'a paragraph that is only a hot card becomes the card');
  assert.equal(blocks[3].trailingCard, null);
  assert.equal(blocks[4].card, null);
  assert.ok(!Speech.build(document, 0).text.includes('老周'), 'hot comments are never spoken');
  assert.ok(!document.copyText(0, document.displayText.length).includes('台词'), 'hot comments are never copied');

  const input = new Input();
  input.viewportWidthPx = 320; input.viewportHeightPx = 2000; input.fontSizePx = 20; input.titleFontSizePx = 22;
  input.commentFontSizePx = 14; input.commentCardFontSizePx = 16; input.paragraphSpacingPx = 10;
  const off = Snapshot.create(input);
  input.commentCardStyle = 1;
  const on = Snapshot.create(input);
  assert.notEqual(on.identity, off.identity, 'card settings are part of the layout identity');
  for (const key of ['commentCardMaxPerPage', 'commentCardLines', 'commentCardStyle']) {
    const previous = input[key];
    input[key] = key === 'commentCardStyle' ? 2 : 2;
    assert.notEqual(Snapshot.create(input).identity, on.identity, key);
    input[key] = previous;
  }

  const cardsOf = page => page.fragments.filter(fragment => fragment.card);
  const offPage = Paginator.paginate(document, off).pages[0];
  assert.equal(cardsOf(offPage).length, 0, 'style off draws no card');
  const onPages = Paginator.paginate(Parser.parse(source, 0, '标题'), on);
  assert.equal(onPages.pages.length, 1);
  const onPage = onPages.pages[0];
  assert.equal(onPage.displayStart, offPage.displayStart);
  assert.equal(onPage.displayEnd, offPage.displayEnd, 'cards never change the page text range');
  const cards = cardsOf(onPage);
  assert.equal(cards.length, 2);
  assert.equal(cards[0].displayStart, blocks[1].displayEnd);
  assert.equal(cards[0].displayEnd, blocks[1].displayEnd, 'a trailing card owns no text');
  assert.equal(cards[0].fixedGapBefore, true, 'page-bottom alignment keeps a trailing card on its paragraph');
  assert.equal(cards[1].displayStart, blocks[3].displayStart);
  assert.equal(cards[1].displayEnd, blocks[3].displayEnd);
  assert.equal(cards[0].paragraph, null);
  const index = onPage.fragments.indexOf(cards[0]);
  const above = onPage.fragments[index - 1];
  assert.ok(cards[0].paragraphY >= above.paragraphY + above.paragraphHeight, 'the card sits below its paragraph');
  for (const card of cards) {
    const hit = onPage.actions.filter(area => area.rect.top >= card.paragraphY - 0.01 &&
      area.rect.bottom <= card.paragraphY + card.paragraphHeight + 0.01);
    assert.equal(hit.length, 1, 'tapping a card opens its comment');
  }
  assert.equal(onPage.actions.find(area => area.rect.top >= cards[0].paragraphY - 0.01).actionId,
    onPage.actions.find(area => area.actionId === document.actions[0].id).actionId);

  // Every style lays out; the tag style points its tail at the count bubble.
  for (const style of [2, 3]) {
    input.commentCardStyle = style;
    const page = Paginator.paginate(Parser.parse(source, 0, '标题'), Snapshot.create(input)).pages[0];
    const styled = cardsOf(page);
    assert.equal(styled.length, 2, `style ${style}`);
    assert.ok(styled.every(fragment => fragment.card.height > 0 && fragment.card.style === style));
    if (style === 3) {
      assert.ok(styled[0].card.tailX >= 0, 'attached card points at its bubble');
      assert.equal(styled[1].card.tailX, -1, 'a source card has no bubble to point at');
    }
  }
  input.commentCardStyle = 1;

  // Per-page cap only limits paragraph hot comments.
  const many = ['标题', ...[1, 2, 3].map(n => `　　第${n}段。${bubble(n, `热评${n}`)}`), hotCard('书源卡')].join('\n');
  input.commentCardMaxPerPage = 2;
  const capped = cardsOf(Paginator.paginate(Parser.parse(many, 0, '标题'), Snapshot.create(input)).pages[0]);
  assert.deepEqual(capped.map(fragment => fragment.card.text ? 1 : 0).length, 3, 'two paragraph cards plus the source card');
  input.commentCardMaxPerPage = 0;
  assert.equal(cardsOf(Paginator.paginate(Parser.parse(many, 0, '标题'), Snapshot.create(input)).pages[0]).length, 4);

  // A trailing card that does not fit moves to the top of the next page, without a gap.
  const pageDoc = Parser.parse(source, 0, '标题');
  const firstCardBlock = pageDoc.blocks[1];
  input.viewportHeightPx = 2000;
  const full = Paginator.paginate(pageDoc, Snapshot.create(input)).pages[0];
  const textBottom = full.fragments[1].paragraphY + full.fragments[1].paragraphHeight;
  input.viewportHeightPx = Math.ceil(textBottom + 2);
  const split = Paginator.paginate(Parser.parse(source, 0, '标题'), Snapshot.create(input));
  assert.ok(split.pages.length >= 2);
  assert.equal(cardsOf(split.pages[0]).length, 0);
  const moved = split.pages[1].fragments[0];
  assert.ok(moved.card, 'the card opens the next page');
  assert.equal(moved.paragraphY, split.pages[1].contentRect.top);
  assert.equal(split.pages[1].displayStart, firstCardBlock.displayEnd);
  assert.equal(split.pageForDisplayOffset(firstCardBlock.displayEnd - 1), 0);
  assert.equal(split.complete, true);

  // Asynchronous pagination produces the same pages.
  const session = Paginator.start(Parser.parse(source, 0, '标题'), Snapshot.create(input));
  while (!session.pageSet.complete) {
    if (await Paginator.appendPageAsync(session) <= 0) break;
  }
  assert.deepEqual(session.pageSet.pages.map(page => [page.displayStart, page.displayEnd, cardsOf(page).length]),
    split.pages.map(page => [page.displayStart, page.displayEnd, cardsOf(page).length]));

  // 本章说: a chapter-end entry on its own line becomes a full-width card in every style; inside a paragraph it
  // stays a bubble and never trails the paragraph.
  const chapterSource = ['标题', '　　最后一段。', '',
    Marker.create('本章说', 'https://c.example/chapter', '本章说'),
    `　　段内的入口。${Marker.create('章评', 'https://c.example/chapter2', '章评', '12条评论')}`,
    Marker.create('章评', 'https://c.example/chapter3', '章评', '76条评论', '698')].join('\n');
  const chapterDoc = Parser.parse(chapterSource, 0, '标题');
  const chapterBlocks = chapterDoc.blocks;
  assert.equal(chapterBlocks[2].card?.chapter, true, 'a native 本章说 entry becomes a card even without wording');
  assert.equal(chapterBlocks[3].card, null);
  assert.equal(chapterBlocks[3].trailingCard, null, 'a 本章说 bubble inside a paragraph stays a bubble');
  assert.equal(chapterBlocks[4].card?.preview, '76条评论');
  assert.equal(document.actions.every(action => !action.chapter), true, 'paragraph and hot comments are not chapter entries');
  input.viewportHeightPx = 2000;
  input.commentChapterCard = true;
  // The 本章说 card has its own switch and does not depend on the hot-comment style.
  for (const style of [0, 1, 2, 3]) {
    input.commentCardStyle = style;
    const page = Paginator.paginate(Parser.parse(chapterSource, 0, '标题'), Snapshot.create(input)).pages[0];
    const chapterCards = cardsOf(page);
    assert.equal(chapterCards.length, 2, `style ${style}`);
    for (const fragment of chapterCards) {
      assert.equal(fragment.card.chapter, true);
      assert.equal(fragment.card.style, 1, '本章说 is always the full-width card');
      assert.equal(fragment.card.box.width(), fragment.card.width);
      assert.equal(fragment.card.tailX, -1);
    }
    assert.equal(chapterCards[0].card.text.text, '查看本章评论');
    assert.equal(chapterCards[1].card.text.text, '76条评论');
    assert.equal(chapterCards[1].card.meta.text, '♥ 698  ›', 'a chapter hot comment shows its likes before the arrow');
    assert.equal(chapterCards[0].card.meta.text, '›');
  }
  input.commentCardStyle = 1;
  input.commentChapterCard = false;
  assert.equal(cardsOf(Paginator.paginate(Parser.parse(chapterSource, 0, '标题'), Snapshot.create(input)).pages[0])
    .length, 0, 'the bubble mode keeps the 本章说 bubble even with hot cards on');

  // 段评气泡、热评卡片、本章说分别关闭：隐藏的入口不进显示文字，也不留下空段。
  const show = (bubbles, hotCards, chapter) => ({ bubbles, hotCards, chapter });
  const mixed = [...source.split('\n'), Marker.create('本章说', 'https://c.example/chapter', '本章说'),
    `　　只有气泡的一段。${bubble(3)}`, `　　${bubble(7)}`,
    `　　书源按钮。${Marker.create('打开', 'https://c.example/button', '打开')}`].join('\n');
  const everything = Parser.parse(mixed, 0, '标题', [], null, show(true, true, true));
  assert.equal(everything.displayText, Parser.parse(mixed, 0, '标题').displayText, 'all on parses as before');
  const labels = doc => Array.from(doc.actions, action => action.label.replace(/[^0-9+一-鿿]/g, ''));
  const sourceOf = (doc, text) => doc.sourceOffsetForDisplay(doc.displayText.indexOf(text));

  const noBubbles = Parser.parse(mixed, 0, '标题', [], null, show(false, true, true));
  assert.ok(!/\d/.test(noBubbles.displayText), 'no count bubble text is left');
  assert.deepEqual(labels(noBubbles), ['', '', '本章说', '打开'], 'hot entries stay for their cards, other actions stay');
  assert.ok(noBubbles.actions.slice(0, 2).every(action => action.displayStart === action.displayEnd));
  assert.equal(noBubbles.blocks.find(block => block.text.includes('第一段')).trailingCard?.preview, '老周活不过这一章');
  assert.ok(noBubbles.blocks.some(block => block.card?.preview === '这句台词好帅'), 'a source hot card is still a card');
  assert.ok(noBubbles.blocks.every(block => block.title || block.card || /\S/.test(block.text.replace(/　/g, ''))),
    'a paragraph that only held a bubble is dropped');
  assert.equal(sourceOf(noBubbles, '只有气泡'), sourceOf(everything, '只有气泡'), 'source offsets are unchanged');
  input.commentChapterCard = true;
  const noBubblePage = Paginator.paginate(noBubbles, Snapshot.create(input)).pages[0];
  assert.equal(cardsOf(noBubblePage).length, 3, 'hot card, source card and 本章说 card');
  assert.equal(noBubblePage.fragments.reduce((sum, fragment) => sum + fragment.commentBubbleSegments.length, 0), 1,
    'only the source button keeps a bubble');
  assert.equal(new Set(noBubblePage.actions.map(area => area.actionId)).size, 4, 'three cards and the button are tappable');

  const nothing = Parser.parse(mixed, 0, '标题', [], null, show(false, false, false));
  assert.deepEqual(labels(nothing), ['打开'], 'only non-comment actions remain');
  assert.ok(nothing.blocks.every(block => !block.card && !block.trailingCard));
  assert.ok(!nothing.displayText.includes('本章说') && !/\d/.test(nothing.displayText));
  assert.equal(nothing.blocks.length, 6, 'title, four paragraphs with text and the button; emptied paragraphs are gone');

  const noChapter = Parser.parse(mixed, 0, '标题', [], null, show(true, true, false));
  assert.ok(!labels(noChapter).includes('本章说') && labels(noChapter).includes('56'));
  const noHot = Parser.parse(mixed, 0, '标题', [], null, show(false, false, true));
  assert.deepEqual(labels(noHot), ['本章说', '打开'], 'with hot cards off a hot entry counts as a bubble');

  console.log('PASS: 本章说 cards, card paragraphs, off = unchanged layout, three styles, per-page cap, card moved to the next page, ' +
    'async parity, never spoken or copied');
} finally {
  modules.cleanup();
}
