import { ReaderTitleSplit, ReaderTitleSplitSettings } from '../../core/reader/ReaderTitleSplit';
import { ReaderRegexFontCodec, ReaderRegexFontRule, ReaderTitleEmphasis } from './ReaderRegexFontRule';

/** 阅读设置里“标题装饰”“首字装饰”两个开关的取值：跟随主题，或不显示。 */
export class ReaderChapterDecoration {
  static readonly THEME: string = 'theme';
  static readonly OFF: string = 'off';

  static normalize(value: string | null | undefined): string {
    return value === ReaderChapterDecoration.OFF ? ReaderChapterDecoration.OFF : ReaderChapterDecoration.THEME;
  }
}

/** Shares emphasis semantics and theme entitlement checks with regex fonts. */
export class ReaderTitleStyleSettings extends ReaderTitleSplitSettings {
  emphasis: ReaderRegexFontRule = new ReaderRegexFontRule();
  /**
   * 2：标题强调有“跟随主题”（theme，默认）。更早的数据里 none 是旧默认值、inherit 是旧的“跟随主题”（用正文强调）：
   * 读入时 none 改成 theme（现有主题都不设标题强调，看起来不变），inherit 原样保留，现在叫“同正文强调”。
   */
  emphasisVersion: number = 2;
  /** 标题装饰（主题的标题饰图、序号行颜色）：theme 跟随主题，off 不显示。 */
  decoration: string = ReaderChapterDecoration.THEME;
  /** 首字装饰（主题的首字放大与印章）：theme 跟随主题，off 不显示。和标题装饰各管各的。 */
  dropCap: string = ReaderChapterDecoration.THEME;

  constructor() {
    super();
    this.emphasis.id = 'reader_title_emphasis';
    this.emphasis.name = '标题强调';
    this.emphasis.emphasisMode = ReaderTitleEmphasis.THEME;
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
      result.decoration = ReaderChapterDecoration.normalize(source.decoration);
      result.dropCap = ReaderChapterDecoration.normalize(source.dropCap);
      if (source.emphasis && typeof source.emphasis === 'object' && !Array.isArray(source.emphasis)) {
        result.emphasis = ReaderRegexFontCodec.cloneRule(source.emphasis);
        result.emphasis.id = 'reader_title_emphasis';
        result.emphasis.pattern = '';
        const version = typeof source.emphasisVersion === 'number' ? source.emphasisVersion : 1;
        if (version < 2 && result.emphasis.emphasisMode === 'none') result.emphasis.emphasisMode = ReaderTitleEmphasis.THEME;
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
