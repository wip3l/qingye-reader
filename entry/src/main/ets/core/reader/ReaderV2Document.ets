import { ReaderActionData, ReaderActionMarker, ReaderActionMatch } from '@legado/sourceengine';
import { EpubNoteLink } from '../book/EpubNoteLink';
import { ReaderImageMarker } from '../book/ReaderImageMarker';
import { ReaderTitleSplit, ReaderTitleSplitSettings } from './ReaderTitleSplit';

/**
 * V2 阅读文档只保存语义和稳定偏移，不保存任何 ArkUI 组件状态。
 * 书源动作标记在这里被转换为普通可见文字和独立 Action，不再进入排版字符串。
 */
export class ReaderV2OffsetSegment {
  sourceStart: number = 0;
  sourceEnd: number = 0;
  displayStart: number = 0;
  displayEnd: number = 0;

  constructor(sourceStart: number, sourceEnd: number, displayStart: number, displayEnd: number) {
    this.sourceStart = sourceStart;
    this.sourceEnd = sourceEnd;
    this.displayStart = displayStart;
    this.displayEnd = displayEnd;
  }
}

export class ReaderV2InlineAction {
  /** Word joiner plus the gap that separates the bubble from the preceding text; it is not part of the bubble. */
  static readonly LABEL_GAP: string = '\u2060\u00A0\u00A0';
  /** Inner padding on each side of the bubble text. */
  static readonly LABEL_PAD: string = '\u00A0';
  id: string = '';
  marker: string = '';
  label: string = '';
  title: string = '';
  url: string = '';
  displayStart: number = 0;
  displayEnd: number = 0;
  sourceStart: number = 0;
  sourceEnd: number = 0;
  /** Display offset where the drawn bubble starts, after the leading gap. */
  bubbleStart: number = 0;
  /** EPUB 注释编号：显示原来的编号文字（不画气泡），点开弹出注释正文。 */
  note: boolean = false;
  /** 热评原文与点赞数；有原文时可画成热评卡。本章说入口的原文是卡面文字（如“76条评论”）。 */
  preview: string = '';
  likes: string = '';
  /** 章末的本章说/章评入口：单独成段时画成本章说卡片，不会挂在段落后面。 */
  chapter: boolean = false;

  constructor(id: string, marker: string, label: string, data: ReaderActionData,
    displayStart: number, displayEnd: number, sourceStart: number, sourceEnd: number) {
    this.id = id;
    this.marker = marker;
    this.label = label;
    this.bubbleStart = label.startsWith(ReaderV2InlineAction.LABEL_GAP) ?
      displayStart + ReaderV2InlineAction.LABEL_GAP.length : displayStart;
    this.title = data.title || '';
    this.url = data.url || '';
    this.note = EpubNoteLink.isNote(this.url);
    this.preview = this.note ? '' : (data.preview || '');
    this.likes = this.preview ? (data.likes || '') : '';
    const rawLabel = data.label || '';
    this.chapter = !this.note && (/本章说|章评|章末/.test(rawLabel) ||
      (/^(?:本章说|章评)/.test(data.title || '') && !/(?:99\+|\d+)\s*$/.test(rawLabel)));
    this.displayStart = displayStart;
    this.displayEnd = displayEnd;
    this.sourceStart = sourceStart;
    this.sourceEnd = sourceEnd;
  }
}

/** 独立成块的图片。原始宽高未知时为 0。 */
export class ReaderV2ImageRef {
  source: string = '';
  width: number = 0;
  height: number = 0;
  displayStart: number = 0;
  sourceStart: number = 0;
  sourceEnd: number = 0;
}

/** 章内小标题：正文里与 text 相同的段落按标题样式排版。 */
export class ReaderV2HeadingHint {
  level: number = 0;
  text: string = '';

  constructor(level: number, text: string) {
    this.level = level;
    this.text = text;
  }
}

export class ReaderV2Block {
  id: string = '';
  text: string = '';
  displayStart: number = 0;
  displayEnd: number = 0;
  sourceStart: number = 0;
  sourceEnd: number = 0;
  title: boolean = false;
  /** 0 is the original/first title segment, 1 is the enlarged second segment. */
  titleSegment: number = 0;
  /** 1-6 表示章内小标题，0 表示普通段落。 */
  headingLevel: number = 0;
  image: ReaderV2ImageRef | null = null;
  /**
   * 整段只有一个带热评原文的入口（书源自带的热评卡），或只有一个本章说入口：开启热评卡片时整段画成卡片，
   * 关闭时照旧显示气泡。段落文字仍是气泡标签，显示偏移与关闭时完全一致。本章说卡片另有自己的开关。
   */
  card: ReaderV2InlineAction | null = null;
  /** 段末入口带热评原文：开启热评卡片时在本段下方追加一张卡片；段评气泡没关时气泡保留。 */
  trailingCard: ReaderV2InlineAction | null = null;

  constructor(id: string, text: string, displayStart: number, displayEnd: number,
    sourceStart: number, sourceEnd: number, title: boolean) {
    this.id = id;
    this.text = text;
    this.displayStart = displayStart;
    this.displayEnd = displayEnd;
    this.sourceStart = sourceStart;
    this.sourceEnd = sourceEnd;
    this.title = title;
  }
}

export class ReaderV2RegexRange {
  start: number = 0;
  end: number = 0;
  ruleIndex: number = -1;

  constructor(start: number, end: number, ruleIndex: number) {
    this.start = start;
    this.end = end;
    this.ruleIndex = ruleIndex;
  }
}

export class ReaderV2Document {
  chapterIndex: number = 0;
  chapterTitle: string = '';
  sourceText: string = '';
  displayText: string = '';
  blocks: ReaderV2Block[] = [];
  images: ReaderV2ImageRef[] = [];
  actions: ReaderV2InlineAction[] = [];
  offsets: ReaderV2OffsetSegment[] = [];
  regexRanges: ReaderV2RegexRange[] = [];
  identity: string = '';

  sourceOffsetForDisplay(displayOffset: number): number {
    const target = Math.max(0, Math.min(this.displayText.length, displayOffset));
    for (const segment of this.offsets) {
      if (target < segment.displayStart || target > segment.displayEnd) continue;
      const displayLength = segment.displayEnd - segment.displayStart;
      const sourceLength = segment.sourceEnd - segment.sourceStart;
      if (displayLength <= 0 || sourceLength <= 0) return segment.sourceStart;
      const ratio = (target - segment.displayStart) / displayLength;
      return Math.round(segment.sourceStart + ratio * sourceLength);
    }
    return target >= this.displayText.length ? this.sourceText.length : target;
  }

  displayOffsetForSource(sourceOffset: number): number {
    const target = Math.max(0, Math.min(this.sourceText.length, sourceOffset));
    for (const segment of this.offsets) {
      if (target < segment.sourceStart || target > segment.sourceEnd) continue;
      const sourceLength = segment.sourceEnd - segment.sourceStart;
      const displayLength = segment.displayEnd - segment.displayStart;
      if (sourceLength <= 0 || displayLength <= 0) return segment.displayStart;
      const ratio = (target - segment.sourceStart) / sourceLength;
      return Math.round(segment.displayStart + ratio * displayLength);
    }
    return target >= this.sourceText.length ? this.displayText.length : target;
  }

  plainText(start: number = 0, end: number = this.displayText.length): string {
    return this.displayText.substring(Math.max(0, start), Math.max(start, Math.min(this.displayText.length, end)));
  }

  copyText(start: number, end: number): string {
    const safeStart = Math.max(0, Math.min(this.displayText.length, start));
    const safeEnd = Math.max(safeStart, Math.min(this.displayText.length, end));
    let cursor = safeStart;
    let result = '';
    for (const action of this.actions) {
      if (action.displayEnd <= safeStart || action.displayStart >= safeEnd) continue;
      const actionStart = Math.max(safeStart, action.displayStart);
      if (actionStart > cursor) result += this.displayText.substring(cursor, actionStart);
      cursor = Math.max(cursor, Math.min(safeEnd, action.displayEnd));
    }
    if (cursor < safeEnd) result += this.displayText.substring(cursor, safeEnd);
    return result.replace(/[\u200B\uFFFC]/g, '').trim();
  }
}

export class ReaderV2SpeechSegment {
  speechStart: number = 0;
  speechEnd: number = 0;
  sourceStart: number = 0;
  sourceEnd: number = 0;

  constructor(speechStart: number, speechEnd: number, sourceStart: number, sourceEnd: number) {
    this.speechStart = speechStart;
    this.speechEnd = speechEnd;
    this.sourceStart = sourceStart;
    this.sourceEnd = sourceEnd;
  }
}

/** Text sent to TTS plus an exact mapping back to the source document. */
export class ReaderV2SpeechText {
  text: string = '';
  sourceStart: number = 0;
  segments: ReaderV2SpeechSegment[] = [];

  sourceOffsetAt(speechOffset: number): number {
    const target = Math.max(0, Math.min(this.text.length, speechOffset));
    for (let index = 0; index < this.segments.length; index++) {
      const segment = this.segments[index];
      if (target < segment.speechStart || target > segment.speechEnd) continue;
      // Hidden action markers do not occupy speech text. The segment before and after a marker
      // therefore share one speech boundary. Prefer the following segment at that boundary so
      // the first sentence after a paragraph comment maps after the marker instead of jumping
      // back to the previous page.
      const next = index + 1 < this.segments.length ? this.segments[index + 1] : null;
      if (target === segment.speechEnd && next && next.speechStart === target) continue;
      return segment.sourceStart + Math.max(0, Math.min(segment.sourceEnd - segment.sourceStart,
        target - segment.speechStart));
    }
    return this.segments.length > 0 ? this.segments[this.segments.length - 1].sourceEnd : this.sourceStart;
  }

  speechOffsetAt(sourceOffset: number): number {
    const target = Math.max(this.sourceStart, sourceOffset);
    for (const segment of this.segments) {
      if (target < segment.sourceStart) return segment.speechStart;
      if (target <= segment.sourceEnd) {
        return segment.speechStart + Math.max(0, Math.min(segment.speechEnd - segment.speechStart,
          target - segment.sourceStart));
      }
    }
    return this.text.length;
  }

  static build(document: ReaderV2Document, sourceStart: number): ReaderV2SpeechText {
    const result = new ReaderV2SpeechText();
    result.sourceStart = Math.max(0, Math.min(document.sourceText.length, sourceStart));
    let sourceCursor = result.sourceStart;
    const containingMarker = ReaderActionMarker.findRawRangeContaining(document.sourceText, sourceCursor);
    if (containingMarker.length >= 2) {
      // A saved page boundary from an older layout can point into a compact action marker. Starting a speech
      // substring there bypasses the normal marker scanner and exposes dimensions/scripts as spoken正文.
      sourceCursor = containingMarker[1];
      result.sourceStart = sourceCursor;
    }
    let speechCursor = 0;
    let text = '';
    const containingImage = ReaderV2DocumentParser.imageRangeContaining(document, sourceCursor);
    if (containingImage.length >= 2) {
      sourceCursor = containingImage[1];
      result.sourceStart = sourceCursor;
    }
    let imageIndex = 0;
    while (sourceCursor < document.sourceText.length) {
      const actionBounds = ReaderActionMarker.findFirstRawRange(document.sourceText, sourceCursor);
      while (imageIndex < document.images.length && document.images[imageIndex].sourceEnd <= sourceCursor) {
        imageIndex++;
      }
      // Image markers carry a file path, never prose. They are skipped exactly like hidden action markers.
      let hiddenStart = actionBounds.length >= 2 ? actionBounds[0] : document.sourceText.length;
      let hiddenEnd = actionBounds.length >= 2 ? actionBounds[1] : document.sourceText.length;
      let hasHidden = actionBounds.length >= 2;
      if (imageIndex < document.images.length && document.images[imageIndex].sourceStart < hiddenStart) {
        hiddenStart = Math.max(sourceCursor, document.images[imageIndex].sourceStart);
        hiddenEnd = document.images[imageIndex].sourceEnd;
        hasHidden = true;
      }
      if (hiddenStart > sourceCursor) {
        const plain = document.sourceText.substring(sourceCursor, hiddenStart);
        text += plain;
        result.segments.push(new ReaderV2SpeechSegment(speechCursor, speechCursor + plain.length,
          sourceCursor, hiddenStart));
        speechCursor += plain.length;
      }
      if (!hasHidden) break;
      sourceCursor = hiddenEnd;
    }
    result.text = text;
    return result;
  }
}

/** 段评、热评、本章说各自显示与否。隐藏的入口在解析时就不进显示文字，不占宽度也不留空行。 */
export class ReaderV2CommentDisplay {
  /** 段评气泡。关闭后带热评原文的入口只剩卡片（hotCards 开着时），其余段评入口整个去掉。 */
  bubbles: boolean = true;
  /** 是否会画热评卡片。 */
  hotCards: boolean = true;
  /** 本章说入口是否显示（气泡还是卡片由排版决定）。 */
  chapter: boolean = true;
}

export class ReaderV2DocumentParser {
  private static readonly MAX_ACTIONS_PER_CHAPTER: number = 320;
  private static readonly COMMENT_KEEP: number = 0;
  /** 去掉气泡文字，入口留着给热评卡片用。 */
  private static readonly COMMENT_CARD_ONLY: number = 1;
  private static readonly COMMENT_DROP: number = 2;
  private static readonly HIDDEN_ENTRY: string = String.fromCharCode(0x200B);

  /** Occupies one display character for an image block so display/source offsets stay monotonic. */
  static readonly IMAGE_PLACEHOLDER: string = '\uFFFC';

  static parse(source: string, chapterIndex: number, chapterTitle: string,
    headings: ReaderV2HeadingHint[] = [], titleSplit: ReaderTitleSplitSettings | null = null,
    comments: ReaderV2CommentDisplay | null = null): ReaderV2Document {
    const document = new ReaderV2Document();
    // Display offsets where a hidden comment entry used to be, to drop the paragraphs it leaves empty.
    const hiddenAt: number[] = [];
    document.chapterIndex = chapterIndex;
    document.chapterTitle = (chapterTitle || '').trim();
    document.sourceText = ReaderV2DocumentParser.normalizeSource(source || '');

    let sourceCursor = 0;
    let displayCursor = 0;
    let actionIndex = 0;
    let display = '';
    // -2: not searched yet, -1: no further image marker. The marker search is repeated only after the cursor
    // has passed the previous hit, so comment-heavy chapters do not rescan the chapter for every action.
    let nextImageStart = -2;
    while (sourceCursor < document.sourceText.length) {
      // Search the original chapter with an absolute cursor. Repeatedly slicing the entire remaining chapter
      // made a comment-heavy source allocate O(actions * chapterLength) temporary strings while opening.
      const rawBounds = ReaderActionMarker.findFirstRawRange(document.sourceText, sourceCursor);
      if (nextImageStart === -2 || (nextImageStart >= 0 && nextImageStart < sourceCursor)) {
        nextImageStart = document.sourceText.indexOf(ReaderImageMarker.PREFIX, sourceCursor);
      }
      const imageSuffix = nextImageStart >= 0 ?
        document.sourceText.indexOf(ReaderImageMarker.SUFFIX, nextImageStart + ReaderImageMarker.PREFIX.length) : -1;
      if (nextImageStart >= 0 && imageSuffix >= 0 && (rawBounds.length < 2 || nextImageStart < rawBounds[0])) {
        const imageEnd = imageSuffix + ReaderImageMarker.SUFFIX.length;
        if (nextImageStart > sourceCursor) {
          const before = document.sourceText.substring(sourceCursor, nextImageStart);
          display += before;
          document.offsets.push(new ReaderV2OffsetSegment(sourceCursor, nextImageStart,
            displayCursor, displayCursor + before.length));
          displayCursor += before.length;
        }
        const info = ReaderImageMarker.parse(document.sourceText.substring(nextImageStart, imageEnd));
        const standalone = (nextImageStart === 0 || document.sourceText.charAt(nextImageStart - 1) === '\n') &&
          (imageEnd >= document.sourceText.length || document.sourceText.charAt(imageEnd) === '\n');
        if (standalone && info.source) {
          const image = new ReaderV2ImageRef();
          image.source = info.source;
          image.width = info.width;
          image.height = info.height;
          image.displayStart = displayCursor;
          image.sourceStart = nextImageStart;
          image.sourceEnd = imageEnd;
          document.images.push(image);
          display += ReaderV2DocumentParser.IMAGE_PLACEHOLDER;
          document.offsets.push(new ReaderV2OffsetSegment(nextImageStart, imageEnd, displayCursor, displayCursor + 1));
          displayCursor++;
        } else {
          // A marker inside a line of prose cannot become a block. Hide its payload with a zero-width mapping.
          document.offsets.push(new ReaderV2OffsetSegment(nextImageStart, imageEnd, displayCursor, displayCursor));
        }
        sourceCursor = imageEnd;
        continue;
      }
      if (rawBounds.length < 2) {
        const tail = document.sourceText.substring(sourceCursor);
        display += tail;
        document.offsets.push(new ReaderV2OffsetSegment(sourceCursor, document.sourceText.length,
          displayCursor, displayCursor + tail.length));
        displayCursor += tail.length;
        sourceCursor = document.sourceText.length;
        break;
      }

      const absoluteStart = rawBounds[0];
      const absoluteEnd = rawBounds[1];
      if (absoluteStart > sourceCursor) {
        const before = document.sourceText.substring(sourceCursor, absoluteStart);
        display += before;
        document.offsets.push(new ReaderV2OffsetSegment(sourceCursor, absoluteStart,
          displayCursor, displayCursor + before.length));
        displayCursor += before.length;
      }

      const actionMatch = ReaderActionMarker.findFirst(document.sourceText, sourceCursor);
      const validAction = actionMatch && actionMatch.start === absoluteStart && actionMatch.end === absoluteEnd &&
        actionIndex < ReaderV2DocumentParser.MAX_ACTIONS_PER_CHAPTER;
      if (!validAction || !actionMatch) {
        // Damaged and excessive markers are provider metadata, not正文. Drop only the marker and retain an
        // explicit zero-width mapping so progress/TTS offsets continue past it without exposing its payload.
        document.offsets.push(new ReaderV2OffsetSegment(absoluteStart, absoluteEnd,
          displayCursor, displayCursor));
        sourceCursor = absoluteEnd;
        continue;
      }
      const label = ReaderV2DocumentParser.actionLabel(actionMatch);
      const labelStart = displayCursor;
      const action = new ReaderV2InlineAction(`action_${chapterIndex}_${actionIndex++}`,
        actionMatch.marker, label, actionMatch.data, labelStart, labelStart + label.length, absoluteStart, absoluteEnd);
      const hidden = comments ? ReaderV2DocumentParser.commentHidden(action, actionMatch.data, comments) :
        ReaderV2DocumentParser.COMMENT_KEEP;
      if (hidden !== ReaderV2DocumentParser.COMMENT_KEEP) {
        hiddenAt.push(labelStart);
        if (hidden === ReaderV2DocumentParser.COMMENT_CARD_ONLY) {
          // The entry itself takes no room. A zero-width space stands in for it so a paragraph that is only a
          // source hot card still exists as a block; it is plain text, never styled or painted as a bubble.
          action.label = '';
          action.displayEnd = labelStart;
          action.bubbleStart = labelStart;
          document.actions.push(action);
          display += ReaderV2DocumentParser.HIDDEN_ENTRY;
          displayCursor += ReaderV2DocumentParser.HIDDEN_ENTRY.length;
        }
        // Like a dropped marker: progress and TTS offsets continue past it.
        document.offsets.push(new ReaderV2OffsetSegment(absoluteStart, absoluteEnd, labelStart, displayCursor));
        sourceCursor = absoluteEnd;
        continue;
      }
      display += label;
      displayCursor += label.length;
      document.offsets.push(new ReaderV2OffsetSegment(absoluteStart, absoluteEnd, labelStart, displayCursor));
      document.actions.push(action);
      sourceCursor = absoluteEnd;
    }

    document.displayText = display;
    ReaderV2DocumentParser.buildBlocks(document, headings);
    if (titleSplit) ReaderV2DocumentParser.splitTitleBlocks(document, titleSplit);
    ReaderV2DocumentParser.assignCommentCards(document);
    if (hiddenAt.length > 0) {
      // A paragraph that held nothing but hidden entries would otherwise remain as an empty line.
      document.blocks = document.blocks.filter((block: ReaderV2Block): boolean =>
        !!block.image || block.title || !!block.card || !ReaderV2DocumentParser.CARD_FILLER.test(block.text) ||
          !hiddenAt.some((offset: number): boolean => offset >= block.displayStart && offset <= block.displayEnd));
    }
    document.identity = ReaderV2DocumentParser.hashIdentity(document.sourceText, chapterIndex);
    return document;
  }

  private static splitTitleBlocks(document: ReaderV2Document, settings: ReaderTitleSplitSettings): void {
    if (settings.mode === 'off') return;
    const blocks: ReaderV2Block[] = [];
    for (const block of document.blocks) {
      const cut = block.title ? ReaderTitleSplit.offset(document.chapterTitle, settings) : -1;
      if (cut <= 0 || cut >= block.text.length) {
        blocks.push(block);
        continue;
      }
      const boundary = block.displayStart + cut;
      const sourceBoundary = document.sourceOffsetForDisplay(boundary);
      const first = new ReaderV2Block(`${block.id}_title_first`, block.text.substring(0, cut),
        block.displayStart, boundary, block.sourceStart, sourceBoundary, true);
      const second = new ReaderV2Block(`${block.id}_title_second`, block.text.substring(cut),
        boundary, block.displayEnd, sourceBoundary, block.sourceEnd, true);
      second.titleSegment = 1;
      blocks.push(first, second);
    }
    document.blocks = blocks;
  }

  private static commentHidden(action: ReaderV2InlineAction, data: ReaderActionData,
    comments: ReaderV2CommentDisplay): number {
    if (action.note) return ReaderV2DocumentParser.COMMENT_KEEP;
    if (action.chapter) {
      return comments.chapter ? ReaderV2DocumentParser.COMMENT_KEEP : ReaderV2DocumentParser.COMMENT_DROP;
    }
    // Other source actions (buttons, links) are not comments and always stay.
    const comment = !!action.preview || /(?:99\+|\d+)\s*$/.test((data.label || '').trim()) ||
      /段评|评论|神评|热评/.test(`${data.label || ''}${data.title || ''}`);
    if (!comment || comments.bubbles) return ReaderV2DocumentParser.COMMENT_KEEP;
    return !!action.preview && comments.hotCards ? ReaderV2DocumentParser.COMMENT_CARD_ONLY :
      ReaderV2DocumentParser.COMMENT_DROP;
  }

  /** Characters a card-only paragraph may contain besides its bubble: indentation and the bubble's own padding. */
  private static readonly CARD_FILLER: RegExp = /^[\s　 ⁠​]*$/;

  /**
   * Marks the paragraphs that can show a hot-comment card. Only the semantics are recorded here; whether a card is
   * drawn is a layout setting, so turning cards off needs no re-parse and leaves every offset unchanged.
   */
  private static assignCommentCards(document: ReaderV2Document): void {
    if (document.actions.length === 0) return;
    let actionIndex = 0;
    for (const block of document.blocks) {
      if (block.image || block.title) continue;
      // An entry never spans a paragraph break, and one whose bubble is hidden has zero width and may sit exactly
      // on a paragraph edge, so both bounds are inclusive.
      while (actionIndex < document.actions.length && document.actions[actionIndex].displayEnd < block.displayStart) {
        actionIndex++;
      }
      let inBlock = 0;
      let withPreview: ReaderV2InlineAction | null = null;
      let chapterEntry: ReaderV2InlineAction | null = null;
      let rest = '';
      let cursor = block.displayStart;
      for (let index = actionIndex; index < document.actions.length; index++) {
        const action = document.actions[index];
        if (action.displayStart > block.displayEnd) break;
        inBlock++;
        if (action.chapter) chapterEntry = action;
        else if (action.preview) withPreview = action;
        rest += document.displayText.substring(cursor, Math.max(cursor, action.displayStart));
        cursor = Math.max(cursor, action.displayEnd);
      }
      if (!withPreview && !chapterEntry) continue;
      rest += document.displayText.substring(cursor, Math.max(cursor, block.displayEnd));
      if (inBlock === 1 && ReaderV2DocumentParser.CARD_FILLER.test(rest)) {
        block.card = chapterEntry || withPreview;
      } else if (withPreview) {
        // A 本章说 entry inside a paragraph stays a bubble; only paragraph hot comments trail a paragraph.
        block.trailingCard = withPreview;
      }
    }
  }

  private static normalizeSource(source: string): string {
    return source.replace(/\r\n/g, '\n').replace(/\r/g, '\n').replace(/\n{3,}/g, '\n\n');
  }

  private static actionLabel(match: ReaderActionMatch): string {
    // 注释编号就是正文原来的文字，原样显示，正文与加入注释链接以前逐字一致。
    if (EpubNoteLink.isNote(match.data.url)) return match.data.label || EpubNoteLink.ICON_LABEL;
    const configured = (match.data.label || '').trim();
    const count = configured.match(/(99\+|\d+)\s*$/);
    if (count && count[1]) {
      const raw = count[1];
      const value = raw === '99+' ? 100 : Number.parseInt(raw, 10);
      const displayCount = !Number.isFinite(value) || value <= 0 ? '0' : (value > 99 ? '99+' : `${value}`);
      return ReaderV2DocumentParser.bubbleLabel(displayCount);
    }
    if (/本章说/.test(configured)) return ReaderV2DocumentParser.bubbleLabel('本章说');
    if (/段评|评论|神评论/.test(configured)) return ReaderV2DocumentParser.bubbleLabel('段评');
    return ReaderV2DocumentParser.bubbleLabel(configured || '打开');
  }

  // Non-breaking padding keeps the gap and the bubble with the sentence instead of wrapping on their own.
  private static bubbleLabel(text: string): string {
    return `${ReaderV2InlineAction.LABEL_GAP}${ReaderV2InlineAction.LABEL_PAD}${text}${ReaderV2InlineAction.LABEL_PAD}`;
  }

  /** Source range of the image marker containing `sourceOffset`, or an empty array. */
  static imageRangeContaining(document: ReaderV2Document, sourceOffset: number): number[] {
    for (const image of document.images) {
      if (image.sourceStart >= sourceOffset) break;
      if (sourceOffset < image.sourceEnd) return [image.sourceStart, image.sourceEnd];
    }
    return [];
  }

  private static decorateBlock(block: ReaderV2Block, images: Map<number, ReaderV2ImageRef>,
    headingLevels: Map<string, number>): void {
    if (block.text === ReaderV2DocumentParser.IMAGE_PLACEHOLDER) {
      block.image = images.get(block.displayStart) || null;
      return;
    }
    if (block.title || headingLevels.size === 0) return;
    block.headingLevel = headingLevels.get(block.text.replace(/^[\s\u3000]+|[\s\u3000]+$/g, '')) || 0;
  }

  private static buildBlocks(document: ReaderV2Document, headings: ReaderV2HeadingHint[]): void {
    const text = document.displayText;
    const images = new Map<number, ReaderV2ImageRef>();
    for (const image of document.images) images.set(image.displayStart, image);
    const headingLevels = new Map<string, number>();
    for (const heading of headings) {
      const key = (heading.text || '').replace(/^[\s\u3000]+|[\s\u3000]+$/g, '');
      if (key && heading.level > 0 && !headingLevels.has(key)) headingLevels.set(key, heading.level);
    }
    let cursor = 0;
    let blockIndex = 0;
    // The chapter title is normally block 0. A volume heading and its cover images (both recognised from the
    // heading hints / image placeholders) may precede it; any other block ends the search.
    let titleOpen = !!document.chapterTitle;
    const separator = /\n+/g;
    let match = separator.exec(text);
    while (match) {
      const end = match.index;
      const blockText = text.substring(cursor, end);
      // A run of source newlines is one semantic paragraph boundary. Empty Text paragraphs used to create
      // their own line box and paragraph gap, so "\n\n" became three independent vertical reservations.
      // Keeping the delimiter in displayText preserves source/TTS offsets while excluding it from geometry.
      if (blockText.length > 0) {
        const sourceStart = document.sourceOffsetForDisplay(cursor);
        const sourceEnd = document.sourceOffsetForDisplay(end);
        const title = titleOpen && blockText.startsWith(document.chapterTitle);
        const block = new ReaderV2Block(`block_${document.chapterIndex}_${blockIndex++}`, blockText,
          cursor, end, sourceStart, sourceEnd, title);
        ReaderV2DocumentParser.decorateBlock(block, images, headingLevels);
        titleOpen = titleOpen && !title && (!!block.image || block.headingLevel > 0);
        document.blocks.push(block);
      }
      cursor = match.index + match[0].length;
      match = separator.exec(text);
    }
    if (cursor < text.length) {
      const blockText = text.substring(cursor);
      const sourceStart = document.sourceOffsetForDisplay(cursor);
      const sourceEnd = document.sourceOffsetForDisplay(text.length);
      const title = titleOpen && blockText.startsWith(document.chapterTitle);
      const block = new ReaderV2Block(`block_${document.chapterIndex}_${blockIndex}`, blockText,
        cursor, text.length, sourceStart, sourceEnd, title);
      ReaderV2DocumentParser.decorateBlock(block, images, headingLevels);
      document.blocks.push(block);
    }
  }

  private static hashIdentity(text: string, chapterIndex: number): string {
    let hash = 2166136261;
    for (let index = 0; index < text.length; index++) {
      hash ^= text.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return `reader_document_v2_${chapterIndex}_${text.length}_${hash >>> 0}`;
  }
}
