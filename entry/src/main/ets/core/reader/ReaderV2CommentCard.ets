import drawing from '@ohos.graphics.drawing';
import common2D from '@ohos.graphics.common2D';
import graphicsText from '@ohos.graphics.text';
import { ReaderV2InlineAction } from './ReaderV2Document';
import { ReaderV2LayoutSnapshot, ReaderV2Rect } from './ReaderV2LayoutSnapshot';

/**
 * 段落下方的热评卡。坐标都相对所在片段的 paragraphX / paragraphY，页底对齐挪动片段时卡片跟着走。
 * 卡片不占正文显示偏移，不进朗读、查找、划线与复制；点卡片等同点它对应的段评气泡。
 */
export class ReaderV2CommentCard {
  style: number = 1;
  /** 本章说卡片。 */
  chapter: boolean = false;
  /** 整块占用的宽高（含挂件尖角）。 */
  width: number = 0;
  height: number = 0;
  box: ReaderV2Rect = new ReaderV2Rect();
  radius: number = 0;
  fill: number = 0;
  stroke: number = 0;
  /** 挂件尖角中心的 x，-1 表示没有尖角。 */
  tailX: number = -1;
  tailSize: number = 0;
  tag: graphicsText.Paragraph | null = null;
  tagChip: ReaderV2Rect = new ReaderV2Rect();
  tagFill: number = 0;
  tagX: number = 0;
  tagY: number = 0;
  quote: graphicsText.Paragraph | null = null;
  quoteX: number = 0;
  quoteY: number = 0;
  text: graphicsText.Paragraph | null = null;
  textX: number = 0;
  textY: number = 0;
  meta: graphicsText.Paragraph | null = null;
  metaX: number = 0;
  metaY: number = 0;
}

export class ReaderV2CommentCardLayout {
  static readonly STYLE_CARD: number = 1;
  static readonly STYLE_QUOTE: number = 2;
  static readonly STYLE_TAG: number = 3;
  static readonly TAG_TEXT: string = '热评';
  static readonly CHAPTER_TAG_TEXT: string = '本章说';
  static readonly CHAPTER_FALLBACK_TEXT: string = '查看本章评论';

  /** 卡片与上方段落的间距。 */
  static gapBefore(snapshot: ReaderV2LayoutSnapshot): number {
    return snapshot.commentCardFontSizePx * (snapshot.commentCardStyle === ReaderV2CommentCardLayout.STYLE_QUOTE ?
      0.3 : 0.4);
  }

  /**
   * tailAnchorX：挂件尖角要指向的段评气泡中心（相对卡片左边），-1 表示没有可指的气泡。
   */
  static build(action: ReaderV2InlineAction, snapshot: ReaderV2LayoutSnapshot, width: number,
    tailAnchorX: number): ReaderV2CommentCard {
    const style = snapshot.commentCardStyle;
    // 本章说不属于某一段，三种样式下都画成整宽卡片。
    if (action.chapter) return ReaderV2CommentCardLayout.buildBoxed(action, snapshot, width, false, -1, true);
    if (style === ReaderV2CommentCardLayout.STYLE_QUOTE) {
      return ReaderV2CommentCardLayout.buildQuote(action, snapshot, width);
    }
    return ReaderV2CommentCardLayout.buildBoxed(action, snapshot, width,
      style === ReaderV2CommentCardLayout.STYLE_TAG, tailAnchorX);
  }

  private static buildBoxed(action: ReaderV2InlineAction, snapshot: ReaderV2LayoutSnapshot, width: number,
    attached: boolean, tailAnchorX: number, chapter: boolean = false): ReaderV2CommentCard {
    const card = new ReaderV2CommentCard();
    card.style = attached ? ReaderV2CommentCardLayout.STYLE_TAG : ReaderV2CommentCardLayout.STYLE_CARD;
    card.chapter = chapter;
    // 本章说用阅读主题的强调色，与段落热评的红色标签区分开。
    const tagColor = chapter ? snapshot.noteColor : snapshot.commentCardTagColor;
    const ink = snapshot.textColor;
    const f = snapshot.commentCardFontSizePx * (attached ? 0.92 : 1);
    const padX = f * (attached ? 0.55 : 0.7);
    const padY = f * (attached ? 0.32 : 0.5);
    const gap = f * 0.45;
    card.fill = ReaderV2CommentCardLayout.withAlpha(ink, 0x0C);
    card.stroke = ReaderV2CommentCardLayout.withAlpha(ink, 0x29);
    card.radius = f * (attached ? 0.45 : 0.55);

    const tagFontSize = f * 0.72;
    card.tag = ReaderV2CommentCardLayout.paragraph(chapter ? ReaderV2CommentCardLayout.CHAPTER_TAG_TEXT :
      ReaderV2CommentCardLayout.TAG_TEXT, tagFontSize, tagColor, graphicsText.FontWeight.W700, [], 1, tagFontSize * 8);
    const tagWidth = Math.ceil(card.tag.getLongestLine());
    const tagHeight = card.tag.getHeight();
    const chipPadX = f * 0.28;
    const chipPadY = f * 0.06;
    const chipWidth = tagWidth + chipPadX * 2;
    const chipHeight = tagHeight + chipPadY * 2;
    card.tagFill = ReaderV2CommentCardLayout.withAlpha(tagColor, 0x24);

    let metaWidth = 0;
    // 本章说右侧是进入箭头；卡面上的数字含义因书源而异，不当点赞数显示。
    const metaText = chapter ? '›' : (action.likes ? `♥ ${action.likes}` : '');
    if (metaText) {
      const metaFontSize = f * (chapter ? 1.1 : 0.74);
      card.meta = ReaderV2CommentCardLayout.paragraph(metaText, metaFontSize,
        ReaderV2CommentCardLayout.withAlpha(ink, 0x99), graphicsText.FontWeight.W400, [], 1, metaFontSize * 12);
      metaWidth = Math.ceil(card.meta.getLongestLine());
    }

    const maxBoxWidth = attached ? width * 0.86 : width;
    const textRoom = Math.max(f * 2, maxBoxWidth - padX * 2 - chipWidth - gap - (metaWidth > 0 ? metaWidth + gap : 0));
    card.text = ReaderV2CommentCardLayout.paragraph(
      action.preview || (chapter ? ReaderV2CommentCardLayout.CHAPTER_FALLBACK_TEXT : ''), f,
      chapter ? ReaderV2CommentCardLayout.withAlpha(ink, 0xCC) : ink, graphicsText.FontWeight.W400, [],
      chapter ? 1 : snapshot.commentCardLines, textRoom);
    // 挂件按内容收窄；卡片始终占满版心宽度。
    const textWidth = attached ? Math.min(textRoom, Math.ceil(card.text.getLongestLine()) + 1) : textRoom;
    const textHeight = card.text.getHeight();
    const firstLine = card.text.getLineMetrics(0);
    const firstLineHeight = firstLine ? firstLine.height : textHeight;
    const rowHeight = Math.max(firstLineHeight, chipHeight);
    const boxWidth = attached ? padX * 2 + chipWidth + gap + textWidth + (metaWidth > 0 ? gap + metaWidth : 0) : width;
    const boxHeight = Math.max(textHeight + Math.max(0, chipHeight - firstLineHeight), chipHeight) + padY * 2;

    const hasTail = attached && tailAnchorX >= 0;
    card.tailSize = hasTail ? f * 0.36 : 0;
    const boxLeft = attached ? Math.max(0, width - boxWidth) : 0;
    const boxTop = card.tailSize;
    card.box = new ReaderV2Rect(boxLeft, boxTop, boxLeft + boxWidth, boxTop + boxHeight);
    if (hasTail) {
      const inset = card.radius + card.tailSize;
      card.tailX = Math.max(boxLeft + inset, Math.min(boxLeft + boxWidth - inset, tailAnchorX));
    }

    const rowCenter = boxTop + padY + rowHeight / 2;
    card.tagChip = new ReaderV2Rect(boxLeft + padX, rowCenter - chipHeight / 2, boxLeft + padX + chipWidth,
      rowCenter + chipHeight / 2);
    card.tagX = card.tagChip.left + chipPadX;
    card.tagY = card.tagChip.top + chipPadY;
    card.textX = card.tagChip.right + gap;
    card.textY = rowCenter - firstLineHeight / 2;
    if (card.meta) {
      card.metaX = boxLeft + boxWidth - padX - metaWidth;
      card.metaY = rowCenter - card.meta.getHeight() / 2;
    }
    card.width = width;
    card.height = boxTop + boxHeight;
    return card;
  }

  private static buildQuote(action: ReaderV2InlineAction, snapshot: ReaderV2LayoutSnapshot,
    width: number): ReaderV2CommentCard {
    const card = new ReaderV2CommentCard();
    card.style = ReaderV2CommentCardLayout.STYLE_QUOTE;
    const ink = snapshot.textColor;
    const muted = ReaderV2CommentCardLayout.withAlpha(ink, 0xA6);
    const f = snapshot.commentCardFontSizePx;
    const family = snapshot.bodyFontFamily ? [snapshot.bodyFontFamily] : [];
    // 与正文段首缩进对齐，读起来像这一段的批注。
    const indent = Math.min(width * 0.25, snapshot.fontSizePx * 2);
    const quoteFontSize = f * 1.5;
    card.quote = ReaderV2CommentCardLayout.paragraph('“', quoteFontSize, ReaderV2CommentCardLayout.withAlpha(ink, 0x73),
      graphicsText.FontWeight.W700, family, 1, quoteFontSize * 2);
    const quoteWidth = Math.ceil(card.quote.getLongestLine());
    const gap = f * 0.25;
    const textRoom = Math.max(f * 2, width - indent - quoteWidth - gap);
    card.text = ReaderV2CommentCardLayout.paragraph(action.preview, f, muted, graphicsText.FontWeight.W400, family,
      snapshot.commentCardLines, textRoom);
    const textHeight = card.text.getHeight();
    card.quoteX = indent;
    card.quoteY = -quoteFontSize * 0.12;
    card.textX = indent + quoteWidth + gap;
    card.textY = 0;
    let height = textHeight;
    if (action.likes) {
      const metaFontSize = f * 0.72;
      card.meta = ReaderV2CommentCardLayout.paragraph(`♥ ${action.likes}`, metaFontSize,
        ReaderV2CommentCardLayout.withAlpha(ink, 0x8C), graphicsText.FontWeight.W400, [], 1, metaFontSize * 12);
      card.metaX = card.textX;
      card.metaY = textHeight + f * 0.12;
      height = card.metaY + card.meta.getHeight();
    }
    card.box = new ReaderV2Rect(indent, 0, width, height);
    card.width = width;
    card.height = height;
    return card;
  }

  private static paragraph(text: string, fontSize: number, color: number, weight: graphicsText.FontWeight,
    families: string[], maxLines: number, width: number): graphicsText.Paragraph {
    const textStyle: graphicsText.TextStyle = {
      fontSize: fontSize,
      fontWeight: weight,
      fontFamilies: families,
      color: ReaderV2CommentCardLayout.color(color),
      ellipsis: '…',
      ellipsisMode: graphicsText.EllipsisMode.END,
      locale: 'zh-Hans'
    };
    const builder = new graphicsText.ParagraphBuilder({
      textStyle: textStyle,
      align: graphicsText.TextAlign.LEFT,
      maxLines: Math.max(1, maxLines),
      wordBreak: graphicsText.WordBreak.BREAK_WORD,
      includeFontPadding: true
    }, graphicsText.FontCollection.getGlobalInstance());
    builder.pushStyle(textStyle);
    builder.addText(text);
    builder.popStyle();
    const paragraph = builder.build();
    paragraph.layoutSync(Math.max(1, width));
    return paragraph;
  }

  static withAlpha(color: number, alpha: number): number {
    return (((color >>> 0) & 0x00FFFFFF) | ((alpha & 0xFF) << 24)) >>> 0;
  }

  static color(value: number): common2D.Color {
    const color = value >>> 0;
    return {
      alpha: (color >>> 24) & 0xFF,
      red: (color >>> 16) & 0xFF,
      green: (color >>> 8) & 0xFF,
      blue: color & 0xFF
    };
  }
}

export class ReaderV2CommentCardPainter {
  static paint(canvas: drawing.Canvas, card: ReaderV2CommentCard, x: number, y: number): void {
    canvas.save();
    canvas.translate(x, y);
    if (card.style !== ReaderV2CommentCardLayout.STYLE_QUOTE) {
      ReaderV2CommentCardPainter.paintBox(canvas, card);
      if (card.tag) {
        const chip = card.tagChip;
        const radius = Math.min(chip.height() / 2, card.radius * 0.6);
        const brush = new drawing.Brush();
        brush.setAntiAlias(true);
        brush.setColor(ReaderV2CommentCardLayout.color(card.tagFill));
        canvas.attachBrush(brush);
        canvas.drawRoundRect(new drawing.RoundRect({ left: chip.left, top: chip.top, right: chip.right,
          bottom: chip.bottom }, radius, radius));
        canvas.detachBrush();
        card.tag.paint(canvas, card.tagX, card.tagY);
      }
    }
    if (card.quote) card.quote.paint(canvas, card.quoteX, card.quoteY);
    if (card.text) card.text.paint(canvas, card.textX, card.textY);
    if (card.meta) card.meta.paint(canvas, card.metaX, card.metaY);
    canvas.restore();
  }

  /** 圆角框；挂件在顶边开一个指向段评气泡的尖角，框和尖角是同一条轮廓，描边不断开。 */
  private static paintBox(canvas: drawing.Canvas, card: ReaderV2CommentCard): void {
    const box = card.box;
    const r = Math.min(card.radius, box.height() / 2, box.width() / 2);
    const path = new drawing.Path();
    const t = card.tailSize;
    path.moveTo(box.left + r, box.top);
    if (card.tailX >= 0 && t > 0) {
      path.lineTo(card.tailX - t, box.top);
      path.lineTo(card.tailX, box.top - t);
      path.lineTo(card.tailX + t, box.top);
    }
    path.lineTo(box.right - r, box.top);
    path.arcTo(box.right - 2 * r, box.top, box.right, box.top + 2 * r, -90, 90);
    path.lineTo(box.right, box.bottom - r);
    path.arcTo(box.right - 2 * r, box.bottom - 2 * r, box.right, box.bottom, 0, 90);
    path.lineTo(box.left + r, box.bottom);
    path.arcTo(box.left, box.bottom - 2 * r, box.left + 2 * r, box.bottom, 90, 90);
    path.lineTo(box.left, box.top + r);
    path.arcTo(box.left, box.top, box.left + 2 * r, box.top + 2 * r, 180, 90);
    path.close();
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    brush.setColor(ReaderV2CommentCardLayout.color(card.fill));
    canvas.attachBrush(brush);
    canvas.drawPath(path);
    canvas.detachBrush();
    const pen = new drawing.Pen();
    pen.setAntiAlias(true);
    pen.setStrokeWidth(Math.max(1, card.radius * 0.08));
    pen.setColor(ReaderV2CommentCardLayout.color(card.stroke));
    canvas.attachPen(pen);
    canvas.drawPath(path);
    canvas.detachPen();
  }
}
