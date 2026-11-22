import drawing from '@ohos.graphics.drawing';
import common2D from '@ohos.graphics.common2D';
import graphicsText from '@ohos.graphics.text';
import { ReaderV2InlineAction } from './ReaderV2Document';
import { ReaderV2LayoutSnapshot, ReaderV2Rect } from './ReaderV2LayoutSnapshot';
import { ReaderCommentEmoji, ReaderCommentEmojiPiece } from './ReaderCommentEmoji';
import { ReaderEmojiImages } from './ReaderEmojiImages';

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
  /** 热评文字里的表情图位置，相对 text 的左上角。 */
  textEmojis: ReaderV2CardEmoji[] = [];
  /** 表情图还没取到（或取不到）时画的浅色圆底。 */
  emojiPlaceholder: number = 0;
  meta: graphicsText.Paragraph | null = null;
  metaX: number = 0;
  metaY: number = 0;
  /** 本章说：标题行中间的细线、各条热评与它们共用的颜色。 */
  rule: ReaderV2Rect | null = null;
  hots: ReaderV2ChapterHotRow[] = [];
  lineColor: number = 0;
  pillFill: number = 0;
  iconColor: number = 0;
}

/** 本章说里的一条热评：左侧竖线、昵称、点赞胶囊与正文。坐标相对卡片左上角。 */
export class ReaderV2ChapterHotRow {
  bar: ReaderV2Rect = new ReaderV2Rect();
  user: graphicsText.Paragraph | null = null;
  userX: number = 0;
  userY: number = 0;
  pill: ReaderV2Rect | null = null;
  icon: ReaderV2Rect = new ReaderV2Rect();
  likes: graphicsText.Paragraph | null = null;
  likesX: number = 0;
  likesY: number = 0;
  text: graphicsText.Paragraph | null = null;
  textX: number = 0;
  textY: number = 0;
  textEmojis: ReaderV2CardEmoji[] = [];
}

/** 文字里一个表情图的位置（相对所在段落的左上角）与图片地址。 */
export class ReaderV2CardEmoji {
  url: string = '';
  rect: ReaderV2Rect = new ReaderV2Rect();

  constructor(url: string, rect: ReaderV2Rect) {
    this.url = url;
    this.rect = rect;
  }
}

/** 带表情的热评文字：排好的段落与其中各表情图的位置。 */
class ReaderV2EmojiText {
  paragraph: graphicsText.Paragraph;
  emojis: ReaderV2CardEmoji[] = [];

  constructor(paragraph: graphicsText.Paragraph) {
    this.paragraph = paragraph;
  }
}

export class ReaderV2CommentCardLayout {
  /** 表情图边长相对字号；与带字体留白的行高相当，插进去不把行撑高。 */
  static readonly EMOJI_SCALE: number = 1.15;

  static readonly STYLE_CARD: number = 1;
  static readonly STYLE_QUOTE: number = 2;
  static readonly STYLE_TAG: number = 3;
  /** 本章说：不画框，标题行细线分区，热评左侧一道竖线。 */
  static readonly STYLE_CHAPTER: number = 4;
  static readonly TAG_TEXT: string = '热评';
  static readonly CHAPTER_TAG_TEXT: string = '本章说';
  static readonly CHAPTER_FALLBACK_TEXT: string = '查看本章评论';
  static readonly CHAPTER_ALL_TEXT: string = '全部评论';
  /** 本章说最多列出的热评条数；页面放不下时由分页逐条减少。 */
  static readonly CHAPTER_MAX_HOTS: number = 2;

  /**
   * 卡片与上下正文字面之间的留白。上下取同一个值：行框里的行距、字体留白都不算在内，
   * 所以不随行距、段距的设置变得一边宽一边窄。本章说没有外框，多留一些和正文分开。
   */
  static edgeGap(snapshot: ReaderV2LayoutSnapshot, chapter: boolean = false): number {
    if (chapter) return snapshot.commentCardFontSizePx * 1.2;
    const style = snapshot.commentCardStyle;
    return snapshot.commentCardFontSizePx * (style === ReaderV2CommentCardLayout.STYLE_QUOTE ? 0.7 :
      (style === ReaderV2CommentCardLayout.STYLE_TAG ? 0.6 : 0.9));
  }

  /** 连着的两张卡片之间的间距。 */
  static stackGap(snapshot: ReaderV2LayoutSnapshot): number {
    return snapshot.commentCardFontSizePx * (snapshot.commentCardStyle === ReaderV2CommentCardLayout.STYLE_QUOTE ?
      0.35 : 0.5);
  }

  /**
   * tailAnchorX：挂件尖角要指向的段评气泡中心（相对卡片左边），-1 表示没有可指的气泡。
   */
  static build(action: ReaderV2InlineAction, snapshot: ReaderV2LayoutSnapshot, width: number,
    tailAnchorX: number, chapterHots: number = ReaderV2CommentCardLayout.CHAPTER_MAX_HOTS): ReaderV2CommentCard {
    const style = snapshot.commentCardStyle;
    // 本章说不属于某一段，三种热评样式下都画成同一种章末区块。
    if (action.chapter) return ReaderV2CommentCardLayout.buildChapter(action, snapshot, width, chapterHots);
    if (style === ReaderV2CommentCardLayout.STYLE_QUOTE) {
      return ReaderV2CommentCardLayout.buildQuote(action, snapshot, width);
    }
    return ReaderV2CommentCardLayout.buildBoxed(action, snapshot, width,
      style === ReaderV2CommentCardLayout.STYLE_TAG, tailAnchorX);
  }

  private static buildBoxed(action: ReaderV2InlineAction, snapshot: ReaderV2LayoutSnapshot, width: number,
    attached: boolean, tailAnchorX: number): ReaderV2CommentCard {
    const card = new ReaderV2CommentCard();
    card.style = attached ? ReaderV2CommentCardLayout.STYLE_TAG : ReaderV2CommentCardLayout.STYLE_CARD;
    const tagColor = snapshot.commentCardTagColor;
    const ink = snapshot.textColor;
    const f = snapshot.commentCardFontSizePx * (attached ? 0.92 : 1);
    const padX = f * (attached ? 0.55 : 0.7);
    const padY = f * (attached ? 0.32 : 0.5);
    const gap = f * 0.45;
    card.fill = ReaderV2CommentCardLayout.withAlpha(ink, 0x0C);
    card.stroke = ReaderV2CommentCardLayout.withAlpha(ink, 0x29);
    card.radius = f * (attached ? 0.45 : 0.55);

    const tagFontSize = f * 0.72;
    card.tag = ReaderV2CommentCardLayout.paragraph(ReaderV2CommentCardLayout.TAG_TEXT, tagFontSize, tagColor,
      graphicsText.FontWeight.W700, [], 1, tagFontSize * 8);
    const tagWidth = Math.ceil(card.tag.getLongestLine());
    const tagHeight = card.tag.getHeight();
    const chipPadX = f * 0.28;
    const chipPadY = f * 0.06;
    const chipWidth = tagWidth + chipPadX * 2;
    const chipHeight = tagHeight + chipPadY * 2;
    card.tagFill = ReaderV2CommentCardLayout.withAlpha(tagColor, 0x24);

    let metaWidth = 0;
    if (action.likes) {
      const metaFontSize = f * 0.74;
      card.meta = ReaderV2CommentCardLayout.paragraph(`♥ ${action.likes}`, metaFontSize,
        ReaderV2CommentCardLayout.withAlpha(ink, 0x99), graphicsText.FontWeight.W400, [], 1, metaFontSize * 12);
      metaWidth = Math.ceil(card.meta.getLongestLine());
    }

    const maxBoxWidth = attached ? width * 0.86 : width;
    const textRoom = Math.max(f * 2, maxBoxWidth - padX * 2 - chipWidth - gap - (metaWidth > 0 ? metaWidth + gap : 0));
    card.emojiPlaceholder = ReaderV2CommentCardLayout.withAlpha(ink, 0x14);
    const rich = ReaderV2CommentCardLayout.emojiParagraph(action.preview, action.emojis, f, ink,
      graphicsText.FontWeight.W400, [], snapshot.commentCardLines, textRoom);
    card.text = rich.paragraph;
    card.textEmojis = rich.emojis;
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

  /**
   * 本章说的章末区块：标题行“本章说 ——— 79条评论 ›”，下面最多 hotLimit 条热评，每条左侧一道竖线，
   * 昵称与点赞胶囊一行、正文最多两行。不画外框，和正文融在一起；整块都是点按区域。
   */
  private static buildChapter(action: ReaderV2InlineAction, snapshot: ReaderV2LayoutSnapshot, width: number,
    hotLimit: number): ReaderV2CommentCard {
    const card = new ReaderV2CommentCard();
    card.style = ReaderV2CommentCardLayout.STYLE_CHAPTER;
    card.chapter = true;
    const ink = snapshot.textColor;
    const muted = ReaderV2CommentCardLayout.withAlpha(ink, 0x99);
    const f = snapshot.commentCardFontSizePx;
    card.lineColor = ReaderV2CommentCardLayout.withAlpha(ink, 0x29);
    card.pillFill = ReaderV2CommentCardLayout.withAlpha(ink, 0x10);
    card.iconColor = muted;
    card.emojiPlaceholder = ReaderV2CommentCardLayout.withAlpha(ink, 0x14);

    // 标题行：强调色的“本章说”，右侧条数与箭头，中间一条细线。
    card.tag = ReaderV2CommentCardLayout.paragraph(ReaderV2CommentCardLayout.CHAPTER_TAG_TEXT, f * 1.04,
      snapshot.noteColor, graphicsText.FontWeight.W700, [], 1, f * 8);
    const hots = action.hots.slice(0, Math.max(0, Math.min(hotLimit, ReaderV2CommentCardLayout.CHAPTER_MAX_HOTS)));
    const countText = action.count || (action.hots.length > 0 ? ReaderV2CommentCardLayout.CHAPTER_ALL_TEXT :
      ReaderV2CommentCardLayout.CHAPTER_FALLBACK_TEXT);
    card.meta = ReaderV2CommentCardLayout.paragraph(`${countText} ›`, f * 0.93, muted, graphicsText.FontWeight.W400,
      [], 1, width * 0.6);
    const tagWidth = Math.ceil(card.tag.getLongestLine());
    const metaWidth = Math.ceil(card.meta.getLongestLine());
    const headHeight = Math.max(card.tag.getHeight(), card.meta.getHeight());
    card.tagX = 0;
    card.tagY = (headHeight - card.tag.getHeight()) / 2;
    card.metaX = Math.max(tagWidth, width - metaWidth);
    card.metaY = (headHeight - card.meta.getHeight()) / 2;
    const ruleGap = f * 0.75;
    const ruleLeft = tagWidth + ruleGap;
    const ruleRight = card.metaX - ruleGap;
    const ruleWidth = Math.max(1, f * 0.07);
    if (ruleRight - ruleLeft > f) {
      card.rule = new ReaderV2Rect(ruleLeft, headHeight / 2 - ruleWidth / 2, ruleRight, headHeight / 2 + ruleWidth / 2);
    }

    const barWidth = Math.max(2, f * 0.15);
    const contentX = barWidth + f * 0.75;
    const contentWidth = Math.max(f * 2, width - contentX);
    let y = headHeight;
    for (const hot of hots) {
      y += f * 0.7;
      const row = new ReaderV2ChapterHotRow();
      const top = y;
      let rowHeight = 0;
      let pillWidth = 0;
      if (hot.likes) {
        const likesSize = f * 0.85;
        row.likes = ReaderV2CommentCardLayout.paragraph(hot.likes, likesSize, muted, graphicsText.FontWeight.W400, [], 1,
          likesSize * 10);
        const likesWidth = Math.ceil(row.likes.getLongestLine());
        const likesHeight = row.likes.getHeight();
        const padX = f * 0.55;
        const iconSize = likesSize * 0.9;
        const iconGap = f * 0.22;
        const pillHeight = likesHeight + f * 0.16;
        pillWidth = padX * 2 + iconSize + iconGap + likesWidth;
        row.pill = new ReaderV2Rect(width - pillWidth, top, width, top + pillHeight);
        row.icon = new ReaderV2Rect(row.pill.left + padX, top + (pillHeight - iconSize) / 2,
          row.pill.left + padX + iconSize, top + (pillHeight + iconSize) / 2);
        row.likesX = row.icon.right + iconGap;
        row.likesY = top + (pillHeight - likesHeight) / 2;
        rowHeight = pillHeight;
      }
      if (hot.user) {
        const userRoom = Math.max(f * 2, contentWidth - (pillWidth > 0 ? pillWidth + f * 0.6 : 0));
        row.user = ReaderV2CommentCardLayout.paragraph(hot.user, f * 0.93, muted, graphicsText.FontWeight.W400, [], 1,
          userRoom);
        const userHeight = row.user.getHeight();
        if (userHeight > rowHeight && row.pill) {
          // 胶囊跟昵称行竖直居中。
          const shift = (userHeight - rowHeight) / 2;
          row.pill = new ReaderV2Rect(row.pill.left, row.pill.top + shift, row.pill.right, row.pill.bottom + shift);
          row.icon = new ReaderV2Rect(row.icon.left, row.icon.top + shift, row.icon.right, row.icon.bottom + shift);
          row.likesY += shift;
        }
        row.userX = contentX;
        row.userY = top + Math.max(0, (rowHeight - userHeight) / 2);
        rowHeight = Math.max(rowHeight, userHeight);
      }
      const textTop = rowHeight > 0 ? top + rowHeight + f * 0.12 : top;
      const rich = ReaderV2CommentCardLayout.emojiParagraph(hot.text, action.emojis, f, ink,
        graphicsText.FontWeight.W400, [], 2, contentWidth);
      row.text = rich.paragraph;
      row.textEmojis = rich.emojis;
      row.textX = contentX;
      row.textY = textTop;
      y = textTop + row.text.getHeight();
      row.bar = new ReaderV2Rect(0, top, barWidth, y);
      card.hots.push(row);
    }
    card.box = new ReaderV2Rect(0, 0, width, y);
    card.width = width;
    card.height = y;
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
    card.emojiPlaceholder = ReaderV2CommentCardLayout.withAlpha(ink, 0x14);
    const rich = ReaderV2CommentCardLayout.emojiParagraph(action.preview, action.emojis, f, muted,
      graphicsText.FontWeight.W400, family, snapshot.commentCardLines, textRoom);
    card.text = rich.paragraph;
    card.textEmojis = rich.emojis;
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

  /**
   * 热评文字：书源给了图片的表情代号排成与字等高的占位，没给的常见代号换成系统表情（见 ReaderCommentEmoji）。
   * 占位大小固定，图片取没取到都不改排版；排版时就开始取图。
   */
  private static emojiParagraph(text: string, emojis: Record<string, string>, fontSize: number, color: number,
    weight: graphicsText.FontWeight, families: string[], maxLines: number, width: number): ReaderV2EmojiText {
    const pieces = ReaderCommentEmoji.pieces(text, emojis);
    const plain = pieces.length === 1 && !pieces[0].url;
    if (pieces.length === 0 || plain) {
      return new ReaderV2EmojiText(ReaderV2CommentCardLayout.paragraph(plain ? pieces[0].text : text, fontSize, color,
        weight, families, maxLines, width));
    }
    const size = Math.round(fontSize * ReaderV2CommentCardLayout.EMOJI_SCALE);
    const urls: string[] = [];
    const paragraph = ReaderV2CommentCardLayout.paragraph('', fontSize, color, weight, families, maxLines, width,
      (builder: graphicsText.ParagraphBuilder): void => {
        pieces.forEach((piece: ReaderCommentEmojiPiece): void => {
          if (!piece.url) {
            builder.addText(piece.text);
            return;
          }
          builder.addPlaceholder({
            width: size,
            height: size,
            align: graphicsText.PlaceholderAlignment.CENTER_OF_ROW_BOX,
            baseline: graphicsText.TextBaseline.ALPHABETIC,
            baselineOffset: 0
          });
          urls.push(piece.url);
        });
      });
    const result = new ReaderV2EmojiText(paragraph);
    // 放不下被省略号截掉的占位不返回位置，按顺序对应前面的那些。
    const boxes = paragraph.getRectsForPlaceholders();
    for (let i = 0; i < boxes.length && i < urls.length; i++) {
      const box = boxes[i].rect;
      if (box.right - box.left < 1 || box.bottom - box.top < 1) continue;
      result.emojis.push(new ReaderV2CardEmoji(urls[i], new ReaderV2Rect(box.left, box.top, box.right, box.bottom)));
      ReaderEmojiImages.prepare(urls[i], size);
    }
    return result;
  }

  private static paragraph(text: string, fontSize: number, color: number, weight: graphicsText.FontWeight,
    families: string[], maxLines: number, width: number,
    fill: ((builder: graphicsText.ParagraphBuilder) => void) | null = null): graphicsText.Paragraph {
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
    if (fill) {
      fill(builder);
    } else {
      builder.addText(text);
    }
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
    if (card.style === ReaderV2CommentCardLayout.STYLE_CHAPTER) {
      ReaderV2CommentCardPainter.paintChapter(canvas, card);
      canvas.restore();
      return;
    }
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
    if (card.text) {
      card.text.paint(canvas, card.textX, card.textY);
      ReaderV2CommentCardPainter.paintEmojis(canvas, card.textEmojis, card.textX, card.textY, card.emojiPlaceholder);
    }
    if (card.meta) card.meta.paint(canvas, card.metaX, card.metaY);
    canvas.restore();
  }

  /** 表情图按比例放进占位里居中；还没取到或取不到时画一个浅色圆底占着。 */
  private static paintEmojis(canvas: drawing.Canvas, emojis: ReaderV2CardEmoji[], x: number, y: number,
    placeholder: number): void {
    for (const emoji of emojis) {
      const rect = emoji.rect;
      const w = rect.width();
      const h = rect.height();
      const bitmap = ReaderEmojiImages.get(emoji.url, Math.max(w, h));
      if (!bitmap) {
        const brush = new drawing.Brush();
        brush.setAntiAlias(true);
        brush.setColor(ReaderV2CommentCardLayout.color(placeholder));
        canvas.attachBrush(brush);
        canvas.drawCircle(x + rect.left + w / 2, y + rect.top + h / 2, Math.min(w, h) * 0.42);
        canvas.detachBrush();
        continue;
      }
      let bw = w;
      let bh = h;
      try {
        const size = bitmap.getImageInfoSync().size;
        if (size.width > 0 && size.height > 0) {
          const scale = Math.min(w / size.width, h / size.height);
          bw = size.width * scale;
          bh = size.height * scale;
        }
      } catch (_) {
        // 读不到尺寸就铺满占位。
      }
      const left = x + rect.left + (w - bw) / 2;
      const top = y + rect.top + (h - bh) / 2;
      canvas.drawImageRect(bitmap, { left: left, top: top, right: left + bw, bottom: top + bh },
        new drawing.SamplingOptions(drawing.FilterMode.FILTER_MODE_LINEAR));
    }
  }

  private static thumbPath: drawing.Path | null = null;

  /** 点赞图标：16×16 坐标里的竖起大拇指轮廓。 */
  private static thumb(): drawing.Path {
    if (!ReaderV2CommentCardPainter.thumbPath) {
      const path = new drawing.Path();
      path.buildFromSvgString('M5 7 L5 14 L2.5 14 L2.5 7 Z M5 7 L8 2 C9.2 2 9.8 2.8 9.6 3.9 L9.2 6 L12.8 6 ' +
        'C13.7 6 14.3 6.8 14.1 7.7 L12.9 12.8 C12.7 13.5 12.1 14 11.4 14 L5 14');
      ReaderV2CommentCardPainter.thumbPath = path;
    }
    return ReaderV2CommentCardPainter.thumbPath;
  }

  private static fillRect(canvas: drawing.Canvas, rect: ReaderV2Rect, color: number, radius: number): void {
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    brush.setColor(ReaderV2CommentCardLayout.color(color));
    canvas.attachBrush(brush);
    canvas.drawRoundRect(new drawing.RoundRect({ left: rect.left, top: rect.top, right: rect.right,
      bottom: rect.bottom }, radius, radius));
    canvas.detachBrush();
  }

  private static paintChapter(canvas: drawing.Canvas, card: ReaderV2CommentCard): void {
    if (card.tag) card.tag.paint(canvas, card.tagX, card.tagY);
    if (card.meta) card.meta.paint(canvas, card.metaX, card.metaY);
    if (card.rule) ReaderV2CommentCardPainter.fillRect(canvas, card.rule, card.lineColor, 0);
    for (const row of card.hots) {
      ReaderV2CommentCardPainter.fillRect(canvas, row.bar, card.lineColor, row.bar.width() / 2);
      if (row.user) row.user.paint(canvas, row.userX, row.userY);
      if (row.pill) {
        ReaderV2CommentCardPainter.fillRect(canvas, row.pill, card.pillFill, row.pill.height() / 2);
        const size = row.icon.width();
        canvas.save();
        canvas.translate(row.icon.left, row.icon.top);
        canvas.scale(size / 16, size / 16);
        const pen = new drawing.Pen();
        pen.setAntiAlias(true);
        pen.setStrokeWidth(1.4);
        pen.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
        pen.setColor(ReaderV2CommentCardLayout.color(card.iconColor));
        canvas.attachPen(pen);
        canvas.drawPath(ReaderV2CommentCardPainter.thumb());
        canvas.detachPen();
        canvas.restore();
      }
      if (row.likes) row.likes.paint(canvas, row.likesX, row.likesY);
      if (row.text) {
        row.text.paint(canvas, row.textX, row.textY);
        ReaderV2CommentCardPainter.paintEmojis(canvas, row.textEmojis, row.textX, row.textY, card.emojiPlaceholder);
      }
    }
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
