import { drawing, text } from '@kit.ArkGraphics2D';
import { ReaderFontWeight } from './ReaderFontWeight';

export class ReaderFontStrokeRun {
  run: text.Run;
  pen: drawing.Pen;
  // Keep the outline paragraph alive for as long as its native runs are retained by a page.
  paragraph: text.Paragraph;

  constructor(run: text.Run, pen: drawing.Pen, paragraph: text.Paragraph) {
    this.run = run;
    this.pen = pen;
    this.paragraph = paragraph;
  }
}

/** Reuses shaped glyph IDs and positions, without changing advance widths, line breaks or hit testing. */
export class ReaderFontStroke {
  /** Transparent fill prevents drawing the original glyph a second time (including its antialiasing). */
  static outlineStyle(style: text.TextStyle): text.TextStyle {
    return { fontSize: style.fontSize, fontFamilies: style.fontFamilies, fontWeight: style.fontWeight,
      fontVariations: style.fontVariations, letterSpacing: style.letterSpacing,
      heightOnly: style.heightOnly, heightScale: style.heightScale, halfLeading: style.halfLeading,
      locale: style.locale, color: { alpha: 0, red: 0, green: 0, blue: 0 } };
  }

  static build(paragraph: text.Paragraph, weight: number,
    styleAt: (offset: number) => text.TextStyle,
    weightAt?: (offset: number) => number): ReaderFontStrokeRun[] {
    const result: ReaderFontStrokeRun[] = [];
    if (!weightAt && weight <= ReaderFontWeight.DEFAULT) return result;
    const lines = paragraph.getTextLines();
    for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      for (const run of lines[lineIndex].getGlyphRuns()) {
        if (run.getGlyphCount() === 0) continue;
        const style = styleAt(run.getStringRange().start);
        const family = style.fontFamilies && style.fontFamilies.length > 0 ? style.fontFamilies[0] : '';
        const stroke = ReaderFontWeight.strokeWidth(family, weightAt ? weightAt(run.getStringRange().start) : weight, style.fontSize ?? 0);
        if (stroke <= 0 || !style.color) continue;
        const font = run.getFont();
        if (!font) continue;
        const face = font.getTypeface();
        // Emoji and missing characters can use a different face inside the same styled span.
        if (!face || !ReaderFontWeight.matchesStaticFace(family, face.getFamilyName())) continue;
        const pen = new drawing.Pen();
        pen.setAntiAlias(true);
        pen.setColor(style.color);
        pen.setStrokeWidth(stroke);
        result.push(new ReaderFontStrokeRun(run, pen, paragraph));
      }
    }
    return result;
  }

  static paint(canvas: drawing.Canvas, runs: ReaderFontStrokeRun[], x: number, y: number): void {
    if (runs.length === 0) return;
    canvas.save();
    try {
      canvas.detachBrush();
      for (const run of runs) {
        canvas.attachPen(run.pen);
        // Native Run.paint keeps the paragraph's wrapping, justification and baseline transforms.
        // Rebuilding a TextBlob from getPositions() loses those transforms on supported devices.
        run.run.paint(canvas, x, y);
      }
    } finally {
      canvas.detachPen();
      canvas.restore();
    }
  }
}
