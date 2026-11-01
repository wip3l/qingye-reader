import { ReaderTitleSplit, ReaderTitleSplitSettings } from '../../core/reader/ReaderTitleSplit';
import { ReaderRegexFontCodec, ReaderRegexFontRule } from './ReaderRegexFontRule';

/** Shares emphasis semantics and theme entitlement checks with regex fonts. */
export class ReaderTitleStyleSettings extends ReaderTitleSplitSettings {
  emphasis: ReaderRegexFontRule = new ReaderRegexFontRule();

  constructor() {
    super();
    this.emphasis.id = 'reader_title_emphasis';
    this.emphasis.name = '标题强调';
    this.emphasis.emphasisMode = 'none';
  }
}

export class ReaderTitleStyleCodec {
  static decode(raw: string): ReaderTitleStyleSettings {
    const result = new ReaderTitleStyleSettings();
    if (!raw) return result;
    try {
      const source = JSON.parse(raw) as ReaderTitleStyleSettings;
      if (!source || typeof source !== 'object' || Array.isArray(source)) return result;
      result.mode = ReaderTitleSplit.normalizeMode(source.mode);
      if (typeof source.position === 'string') result.position = source.position.substring(0, 8);
      if (typeof source.marker === 'string') result.marker = source.marker.substring(0, 64);
      if (typeof source.regex === 'string') result.regex = source.regex.substring(0, 256);
      result.secondaryScale = ReaderTitleSplit.normalizeScale(source.secondaryScale);
      result.lineGap = ReaderTitleSplit.normalizeGap(source.lineGap);
      result.alignment = ReaderTitleSplit.normalizeAlignment(source.alignment);
      result.marginTop = ReaderTitleSplit.normalizeMargin(source.marginTop);
      result.marginBottom = ReaderTitleSplit.normalizeMargin(source.marginBottom);
      result.singlePage = source.singlePage === true;
      if (source.emphasis && typeof source.emphasis === 'object' && !Array.isArray(source.emphasis)) {
        result.emphasis = ReaderRegexFontCodec.cloneRule(source.emphasis);
        result.emphasis.id = 'reader_title_emphasis';
        result.emphasis.pattern = '';
      }
    } catch (_) {
      return new ReaderTitleStyleSettings();
    }
    return result;
  }

  static encode(settings: ReaderTitleStyleSettings): string {
    return JSON.stringify(ReaderTitleStyleCodec.decode(JSON.stringify(settings)));
  }

  static normalize(raw: string): string {
    return raw ? ReaderTitleStyleCodec.encode(ReaderTitleStyleCodec.decode(raw)) : '';
  }
}
