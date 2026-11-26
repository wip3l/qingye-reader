import graphicsText from '@ohos.graphics.text';
import common2D from '@ohos.graphics.common2D';
import { ReaderV2LayoutSnapshot, ReaderV2Rect } from './ReaderV2LayoutSnapshot';
import { ReaderV2PageDecoration, ReaderV2PageLayout } from './ReaderV2PageLayout';
import { ReaderFontWeight } from './ReaderFontWeight';

/**
 * 书封扉页：第一章之前的一页，画书封、书名、作者、墨线菱形、章数字数、标签、简介和“翻页开始阅读”。
 *
 * 整页只有装饰（ReaderV2PageDecoration），没有文字片段：不参与选字、划线、朗读和进度换算，页首页尾偏移都是 0。
 * 常驻页和翻页纹理都经 ReaderV2PagePainter 画，两边像素一致。书封跟书架上这本书显示的一样：同一张图铺满书形
 * （居中裁切）、叠同一个主题书框；书架画首字色块时（或图画不出来时）这里也画首字色块。
 */
export class ReaderFrontPageSpec {
  title: string = '';
  author: string = '';
  /** 例如“共 312 章 · 98.6 万字”。 */
  meta: string = '';
  tags: string[] = [];
  intro: string = '';
  /** 本机封面文件；空串画首字色块。 */
  coverPath: string = '';
  /** 本机主题书框文件；空串不叠书框。 */
  framePath: string = '';
  /** 首字色块的底色（ARGB），与书架同一套按书名取色。 */
  coverColor: number = 0xFF007DFF;
  /** 墨线与标签用的强调色（ARGB）。 */
  accentColor: number = 0xFF2E5A88;

  identity(): string {
    return `${this.layoutIdentity()}_cover_${ReaderFrontPage.coverHash(this.coverPath, this.framePath)}`;
  }

  /** 不含封面与书框路径：封面后到时只换图不重排，分页缓存键用这个。 */
  layoutIdentity(): string {
    return ReaderFrontPage.hash([this.title, this.author, this.meta, this.tags.join('|'), this.intro,
      `${this.accentColor >>> 0}`, `${this.coverColor >>> 0}`].join('\u0001'));
  }
}

export class ReaderFrontPage {
  static readonly KIND_COVER: string = 'frontCover';
  /** 书封上的首字：只在封面图画不出来时画。 */
  static readonly KIND_COVER_TEXT: string = 'frontCoverText';
  static readonly KIND_RULE: string = 'frontRule';
  static readonly KIND_CHIP: string = 'frontChip';
  /** 书封宽高比（常见竖版封面 3:4.24）。 */
  static readonly COVER_ASPECT: number = 0.708;
  private static readonly MAX_TAGS: number = 3;
  private static readonly MAX_INTRO_LINES: number = 4;

  /** 翻页模式的扉页：一整页。 */
  static page(spec: ReaderFrontPageSpec, snapshot: ReaderV2LayoutSnapshot, column: ReaderV2Rect,
    pageIndex: number, columnIndex: number): ReaderV2PageLayout {
    const page = new ReaderV2PageLayout();
    page.pageIndex = pageIndex;
    page.columnIndex = columnIndex;
    page.frontPage = true;
    page.contentRect = new ReaderV2Rect(column.left, column.top, column.right, column.bottom);
    page.decorations = ReaderFrontPage.decorations(spec, snapshot, column);
    page.contentBottomPx = column.bottom;
    return page;
  }

  /** 在 area 里排出扉页的全部装饰（滚动阅读时 area 是第一章正文上方空出的一屏）。 */
  static decorations(spec: ReaderFrontPageSpec, snapshot: ReaderV2LayoutSnapshot,
    area: ReaderV2Rect): ReaderV2PageDecoration[] {
    const result: ReaderV2PageDecoration[] = [];
    const width = area.width();
    const height = area.height();
    if (width <= 1 || height <= 1) return result;
    const font = Math.max(8, snapshot.fontSizePx);
    const ink = snapshot.textColor >>> 0;
    const sub = ReaderFrontPage.withAlpha(ink, 0.55);
    const faint = ReaderFrontPage.withAlpha(ink, 0.4);
    const accent = spec.accentColor >>> 0;
    const centerX = area.left + width / 2;

    const coverHeight = Math.max(font * 4, Math.min(height * 0.3, width * 0.46 / ReaderFrontPage.COVER_ASPECT));
    const coverWidth = coverHeight * ReaderFrontPage.COVER_ASPECT;
    const titleSize = Math.max(font * 1.25, Math.min(font * 1.75, snapshot.titleFontSizePx * 1.08));
    const title = ReaderFrontPage.text(spec.title || '未命名书籍', titleSize, ink, snapshot.titleFontFamily,
      snapshot.titleFontWeight, graphicsText.TextAlign.CENTER, width, 2, titleSize * 0.06);
    const author = spec.author ? ReaderFrontPage.text(`${spec.author} 著`, font * 0.72, sub,
      snapshot.bodyFontFamily, snapshot.fontWeight, graphicsText.TextAlign.CENTER, width, 1, font * 0.05) : null;
    const meta = spec.meta ? ReaderFrontPage.text(spec.meta, font * 0.64, sub, snapshot.bodyFontFamily,
      snapshot.fontWeight, graphicsText.TextAlign.CENTER, width, 1, 0) : null;
    const chips = ReaderFrontPage.chips(spec.tags, snapshot, font, accent, width);
    const hint = ReaderFrontPage.text('‹　翻页开始阅读', font * 0.6, faint, snapshot.bodyFontFamily,
      snapshot.fontWeight, graphicsText.TextAlign.CENTER, width, 1, font * 0.1);

    const gapCover = font * 1.5;
    const gapAuthor = font * 0.4;
    const ruleHeight = Math.max(6, font * 0.5);
    const gapRule = font * 0.95;
    const gapMeta = font * 0.75;
    const gapChips = font * 0.5;
    const gapIntro = font * 1.05;
    const hintReserve = hint.getHeight() + font * 2.4;
    let used = coverHeight + gapCover + title.getHeight();
    if (author) used += gapAuthor + author.getHeight();
    used += gapRule + ruleHeight;
    if (meta) used += gapMeta + meta.getHeight();
    if (chips.height > 0) used += (meta ? gapChips : gapMeta) + chips.height;

    // 简介按剩下的高度取行数，放不下两行就不放。
    let intro: graphicsText.Paragraph | null = null;
    const introText = ReaderFrontPage.cleanIntro(spec.intro);
    if (introText) {
      const introSize = font * 0.76;
      const probe = ReaderFrontPage.text(introText, introSize, ReaderFrontPage.withAlpha(ink, 0.82),
        snapshot.bodyFontFamily, snapshot.fontWeight, graphicsText.TextAlign.JUSTIFY, width,
        ReaderFrontPage.MAX_INTRO_LINES, 0, introSize * 0.85);
      const lineCount = Math.max(1, probe.getLineCount());
      const lineHeight = probe.getHeight() / lineCount;
      const room = height - hintReserve - used - gapIntro - font * 1.2;
      const lines = Math.min(lineCount, Math.floor(room / Math.max(1, lineHeight)));
      if (lines >= 2) {
        intro = lines === lineCount ? probe : ReaderFrontPage.text(introText, introSize,
          ReaderFrontPage.withAlpha(ink, 0.82), snapshot.bodyFontFamily, snapshot.fontWeight,
          graphicsText.TextAlign.JUSTIFY, width, lines, 0, introSize * 0.85);
        used += gapIntro + intro.getHeight();
      }
    }

    let y = area.top + Math.max(font * 1.2, (height - hintReserve - used) * 0.45);
    // 书封
    const cover = new ReaderV2PageDecoration();
    cover.kind = ReaderFrontPage.KIND_COVER;
    cover.image = spec.coverPath;
    cover.frame = spec.framePath;
    cover.color = spec.coverColor >>> 0;
    cover.shadowDark = !ReaderFrontPage.isLight(ink);
    cover.rect = new ReaderV2Rect(centerX - coverWidth / 2, y, centerX + coverWidth / 2, y + coverHeight);
    result.push(cover);
    ReaderFrontPage.coverText(result, spec, snapshot, cover.rect);
    y += coverHeight + gapCover;
    y = ReaderFrontPage.place(result, title, area.left, y);
    if (author) y = ReaderFrontPage.place(result, author, area.left, y + gapAuthor);
    y += gapRule;
    const ruleWidth = Math.min(width * 0.36, font * 6.4);
    const rule = new ReaderV2PageDecoration();
    rule.kind = ReaderFrontPage.KIND_RULE;
    rule.color = accent;
    rule.rect = new ReaderV2Rect(centerX - ruleWidth / 2, y, centerX + ruleWidth / 2, y + ruleHeight);
    result.push(rule);
    y += ruleHeight;
    if (meta) y = ReaderFrontPage.place(result, meta, area.left, y + gapMeta);
    if (chips.height > 0) {
      y += meta ? gapChips : gapMeta;
      let x = centerX - chips.width / 2;
      for (const chip of chips.items) {
        chip.rect = new ReaderV2Rect(x, y, x + chip.rect.width(), y + chips.height);
        chip.glyphX = x + (chip.rect.width() - (chip.glyph?.getLongestLine() ?? 0)) / 2;
        chip.glyphY = y + (chips.height - (chip.glyph?.getHeight() ?? 0)) / 2;
        result.push(chip);
        x += chip.rect.width() + chips.gap;
      }
      y += chips.height;
    }
    if (intro) ReaderFrontPage.place(result, intro, area.left, y + gapIntro);
    ReaderFrontPage.place(result, hint, area.left, area.bottom - font * 1.2 - hint.getHeight());
    return result;
  }

  static hash(text: string): string {
    let value = 0x811C9DC5;
    for (let index = 0; index < text.length; index++) {
      value ^= text.charCodeAt(index);
      value = Math.imul(value, 0x01000193) >>> 0;
    }
    return value.toString(36);
  }

  /** 页标识里代表书封图与书框的一段（见 ReadBook.applyReaderFrontCover）。 */
  static coverHash(coverPath: string, framePath: string): string {
    return ReaderFrontPage.hash(framePath ? `${coverPath}\u0001${framePath}` : coverPath);
  }

  /** 去掉网页标签和多余空白，段落之间不留空行。 */
  static cleanIntro(intro: string): string {
    return (intro || '').replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
      .split(/\r?\n/).map((line: string): string => line.replace(/^[\s\u3000]+|[\s\u3000]+$/g, ''))
      .filter((line: string): boolean => line.length > 0).join(' ');
  }

  static withAlpha(color: number, alpha: number): number {
    return ((Math.round(Math.max(0, Math.min(1, alpha)) * 255) << 24) | (color & 0x00FFFFFF)) >>> 0;
  }

  static isLight(color: number): boolean {
    const value = color >>> 0;
    const red = (value >>> 16) & 0xFF;
    const green = (value >>> 8) & 0xFF;
    const blue = value & 0xFF;
    return red * 0.299 + green * 0.587 + blue * 0.114 > 140;
  }

  /** 书封首字：和书架的首字色块一样，白色书名第一个字居中，只在封面图画不出来时显示。 */
  private static coverText(result: ReaderV2PageDecoration[], spec: ReaderFrontPageSpec,
    snapshot: ReaderV2LayoutSnapshot, rect: ReaderV2Rect): void {
    const width = rect.width();
    const height = rect.height();
    // 书架首字 28vp 配一百来 vp 宽的封面，按同样的比例放大。
    const size = Math.max(8, width * 0.27);
    const glyph = ReaderFrontPage.text(ReaderFrontPage.initial(spec.title), size, 0xFFFFFFFF,
      snapshot.bodyFontFamily, 400, graphicsText.TextAlign.CENTER, width, 1, 0);
    const decoration = new ReaderV2PageDecoration();
    decoration.kind = ReaderFrontPage.KIND_COVER_TEXT;
    decoration.rect = rect;
    decoration.glyph = glyph;
    decoration.glyphX = rect.left;
    decoration.glyphY = rect.top + (height - glyph.getHeight()) / 2;
    result.push(decoration);
  }

  /** 书架首字色块上的字：书名第一个字，没有书名时为“书”。 */
  static initial(title: string): string {
    return title ? Array.from(title)[0] : '书';
  }

  private static chips(tags: string[], snapshot: ReaderV2LayoutSnapshot, font: number, accent: number,
    maxWidth: number): ReaderFrontChipRow {
    const row = new ReaderFrontChipRow();
    row.gap = font * 0.32;
    const size = font * 0.58;
    const padX = size * 0.75;
    for (const tag of tags.slice(0, ReaderFrontPage.MAX_TAGS)) {
      const glyph = ReaderFrontPage.text(tag, size, accent, snapshot.bodyFontFamily, snapshot.fontWeight,
        graphicsText.TextAlign.LEFT, size * 12, 1, 0);
      const chipWidth = glyph.getLongestLine() + padX * 2;
      const nextWidth = row.width + (row.items.length > 0 ? row.gap : 0) + chipWidth;
      if (nextWidth > maxWidth) break;
      const chip = new ReaderV2PageDecoration();
      chip.kind = ReaderFrontPage.KIND_CHIP;
      chip.color = ReaderFrontPage.withAlpha(accent, 0.1);
      chip.glyph = glyph;
      chip.rect = new ReaderV2Rect(0, 0, chipWidth, 0);
      row.items.push(chip);
      row.width = nextWidth;
      row.height = Math.max(row.height, glyph.getHeight() + size * 0.5);
    }
    return row;
  }

  private static place(result: ReaderV2PageDecoration[], paragraph: graphicsText.Paragraph, left: number,
    top: number): number {
    const decoration = new ReaderV2PageDecoration();
    decoration.glyph = paragraph;
    decoration.glyphX = left;
    decoration.glyphY = top;
    // rect 只供百叶窗等按装饰范围切条的地方使用，文字本身按 glyphX / glyphY 画。
    decoration.rect = new ReaderV2Rect(left, top, left + paragraph.getMaxWidth(), top + paragraph.getHeight());
    result.push(decoration);
    return top + paragraph.getHeight();
  }

  static text(text: string, size: number, color: number, family: string, weight: number,
    align: graphicsText.TextAlign, width: number, maxLines: number, letterSpacing: number,
    lineGap: number = 0): graphicsText.Paragraph {
    const resolved = ReaderFontWeight.layoutWeight(family, weight);
    const style: graphicsText.TextStyle = {
      fontSize: size,
      letterSpacing: letterSpacing,
      fontFamilies: family ? [family] : [],
      fontWeight: ReaderFrontPage.FONT_WEIGHTS[Math.max(0, Math.min(8, Math.round(resolved / 100) - 1))],
      fontVariations: [{ axis: 'wght', value: resolved }],
      color: ReaderFrontPage.color(color),
      halfLeading: true,
      heightOnly: lineGap > 0,
      heightScale: lineGap > 0 ? (size + lineGap) / size : 1,
      ellipsis: '…',
      ellipsisMode: graphicsText.EllipsisMode.END,
      locale: 'zh-Hans'
    };
    const paragraphStyle: graphicsText.ParagraphStyle = {
      textStyle: style,
      align: align,
      textDirection: graphicsText.TextDirection.LTR,
      wordBreak: graphicsText.WordBreak.BREAK_WORD,
      includeFontPadding: true
    };
    if (maxLines > 0) paragraphStyle.maxLines = maxLines;
    const builder = new graphicsText.ParagraphBuilder(paragraphStyle, graphicsText.FontCollection.getGlobalInstance());
    builder.pushStyle(style);
    builder.addText(text);
    builder.popStyle();
    const paragraph = builder.build();
    paragraph.layoutSync(Math.max(1, width));
    return paragraph;
  }

  static readonly FONT_WEIGHTS: graphicsText.FontWeight[] = [
    graphicsText.FontWeight.W100, graphicsText.FontWeight.W200, graphicsText.FontWeight.W300,
    graphicsText.FontWeight.W400, graphicsText.FontWeight.W500, graphicsText.FontWeight.W600,
    graphicsText.FontWeight.W700, graphicsText.FontWeight.W800, graphicsText.FontWeight.W900];

  static color(value: number): common2D.Color {
    const color = value >>> 0;
    return { alpha: (color >>> 24) & 0xFF, red: (color >>> 16) & 0xFF, green: (color >>> 8) & 0xFF, blue: color & 0xFF };
  }
}

class ReaderFrontChipRow {
  items: ReaderV2PageDecoration[] = [];
  width: number = 0;
  height: number = 0;
  gap: number = 0;
}
