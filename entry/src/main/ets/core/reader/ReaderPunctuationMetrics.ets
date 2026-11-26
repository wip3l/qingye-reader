import graphicsText from '@ohos.graphics.text';
import { ReaderGlyphSpace } from './ReaderPunctuationSqueeze';

/**
 * 量出标点字形在实际字体（含回退字体）里的空白，供标点挤压使用。每种字体、字重只量一次：用 100px 的
 * 单字段落排出来，取段落实际选用的字体和字形，按字形外框与字宽算左右空白，再换算成字号的倍数。
 */
export class ReaderPunctuationMetrics {
  private static readonly PROBE_SIZE: number = 100;
  private static readonly MAX_ENTRIES: number = 512;
  private static readonly cache: Map<string, ReaderGlyphSpace | null> = new Map();

  static spaceOf(style: graphicsText.TextStyle, char: string): ReaderGlyphSpace | null {
    const key = JSON.stringify([style.fontFamilies, style.fontWeight, style.fontVariations, char]);
    if (ReaderPunctuationMetrics.cache.has(key)) return ReaderPunctuationMetrics.cache.get(key) ?? null;
    let space: ReaderGlyphSpace | null = null;
    try {
      space = ReaderPunctuationMetrics.measure(style, char);
    } catch (error) {
      space = null;
    }
    if (ReaderPunctuationMetrics.cache.size >= ReaderPunctuationMetrics.MAX_ENTRIES) {
      ReaderPunctuationMetrics.cache.clear();
    }
    ReaderPunctuationMetrics.cache.set(key, space);
    return space;
  }

  private static measure(style: graphicsText.TextStyle, char: string): ReaderGlyphSpace | null {
    const size = ReaderPunctuationMetrics.PROBE_SIZE;
    const probe: graphicsText.TextStyle = {
      fontSize: size,
      letterSpacing: 0,
      fontFamilies: style.fontFamilies,
      fontWeight: style.fontWeight,
      fontVariations: style.fontVariations,
      locale: style.locale ?? 'zh-Hans'
    };
    const builder = new graphicsText.ParagraphBuilder({ textStyle: probe },
      graphicsText.FontCollection.getGlobalInstance());
    builder.pushStyle(probe);
    builder.addText(char);
    builder.popStyle();
    const paragraph = builder.build();
    paragraph.layoutSync(size * 4);
    const advance = paragraph.getLongestLine();
    const lines = paragraph.getTextLines();
    if (lines.length === 0 || advance <= 0) return null;
    const runs = lines[0].getGlyphRuns();
    if (runs.length === 0) return null;
    const glyphs = runs[0].getGlyphs();
    if (glyphs.length !== 1) return null;
    const bounds = runs[0].getFont().getBounds(glyphs);
    if (bounds.length === 0 || bounds[0].right <= bounds[0].left) return null;
    const left = Math.max(0, bounds[0].left);
    const right = Math.max(0, advance - bounds[0].right);
    return { left: left / size, right: right / size, advance: advance / size };
  }
}
