/**
 * 正文文字划线（排版设置 › 文字 › 文字划线）：像信纸一样在正文行下画装饰线。
 * 线不参与排版，改任何一项都只重画，不重新分页；章节标题、插图、段评卡片不画。
 * 设置与其他排版参数一样只留本机、所有阅读主题共用，不进云同步。
 */
export class ReaderTextRulingSettings {
  enabled: boolean = false;
  /** all 全部正文；regex 只在正则字体规则命中的文字下画（“启用正则字体”关闭时不画）。 */
  target: string = 'all';
  /** row 贯穿版心（段末短行也画满）；text 只画到每行最后一个字。target 为 regex 时总按文字。 */
  scope: string = 'row';
  /** solid / dashed / dotted / wavy / double */
  style: string = 'dotted';
  /** near 贴近文字；gap 画在两行之间。 */
  position: string = 'gap';
  /** text 跟随正文文字色；accent 主题强调色；custom 自定义（浅色、深色模式各存一份，空=跟随文字色）。 */
  colorMode: string = 'text';
  color: string = '';
  colorDark: string = '';
  /** 浓淡，10–100（%）。 */
  opacity: number = 40;
  /** 粗细档位 1–5，每档 0.5vp。 */
  thickness: number = 2;
}

/** 交给绘制器的一份已解析参数：颜色已带浓淡，线宽已换成像素。 */
export class ReaderTextRulingSpec {
  target: string = 'all';
  scope: string = 'row';
  style: string = 'dotted';
  position: string = 'gap';
  /** ARGB。 */
  color: number = 0;
  widthPx: number = 1;
}

export class ReaderTextRuling {
  static readonly TARGETS: string[] = ['all', 'regex'];
  static readonly TARGET_LABELS: string[] = ['全部正文', '仅正则字体'];
  static readonly SCOPES: string[] = ['row', 'text'];
  static readonly SCOPE_LABELS: string[] = ['整行', '仅文字'];
  static readonly STYLES: string[] = ['solid', 'dashed', 'dotted', 'wavy', 'double'];
  static readonly STYLE_LABELS: string[] = ['实线', '虚线', '点线', '波浪', '双线'];
  static readonly POSITIONS: string[] = ['near', 'gap'];
  static readonly POSITION_LABELS: string[] = ['贴近文字', '行间居中'];
  static readonly COLOR_MODES: string[] = ['text', 'accent', 'custom'];
  static readonly COLOR_MODE_LABELS: string[] = ['跟随文字', '强调色', '自定义'];
  static readonly MIN_OPACITY: number = 10;
  static readonly MAX_OPACITY: number = 100;
  static readonly MIN_THICKNESS: number = 1;
  static readonly MAX_THICKNESS: number = 5;

  static decode(raw: string): ReaderTextRulingSettings {
    const text = (raw || '').trim();
    if (!text) return new ReaderTextRulingSettings();
    try {
      return ReaderTextRuling.normalize(JSON.parse(text) as ReaderTextRulingSettings);
    } catch (_) {
      return new ReaderTextRulingSettings();
    }
  }

  static encode(settings: ReaderTextRulingSettings): string {
    return JSON.stringify(ReaderTextRuling.normalize(settings));
  }

  static normalize(source: ReaderTextRulingSettings | null | undefined): ReaderTextRulingSettings {
    const result = new ReaderTextRulingSettings();
    if (!source) return result;
    result.enabled = source.enabled === true;
    result.target = ReaderTextRuling.pick(source.target, ReaderTextRuling.TARGETS, result.target);
    result.scope = ReaderTextRuling.pick(source.scope, ReaderTextRuling.SCOPES, result.scope);
    result.style = ReaderTextRuling.pick(source.style, ReaderTextRuling.STYLES, result.style);
    result.position = ReaderTextRuling.pick(source.position, ReaderTextRuling.POSITIONS, result.position);
    result.colorMode = ReaderTextRuling.pick(source.colorMode, ReaderTextRuling.COLOR_MODES, result.colorMode);
    result.color = typeof source.color === 'string' ? source.color.trim() : '';
    result.colorDark = typeof source.colorDark === 'string' ? source.colorDark.trim() : '';
    result.opacity = ReaderTextRuling.clampStep(source.opacity, ReaderTextRuling.MIN_OPACITY,
      ReaderTextRuling.MAX_OPACITY, result.opacity);
    result.thickness = ReaderTextRuling.clampStep(source.thickness, ReaderTextRuling.MIN_THICKNESS,
      ReaderTextRuling.MAX_THICKNESS, result.thickness);
    return result;
  }

  static copy(settings: ReaderTextRulingSettings): ReaderTextRulingSettings {
    return ReaderTextRuling.normalize(settings);
  }

  /** 选“仅正则字体”时长度固定按文字。 */
  static effectiveScope(settings: ReaderTextRulingSettings): string {
    return settings.target === 'regex' ? 'text' : settings.scope;
  }

  static customColor(settings: ReaderTextRulingSettings, dark: boolean): string {
    return dark ? settings.colorDark : settings.color;
  }

  static withCustomColor(settings: ReaderTextRulingSettings, dark: boolean, color: string): ReaderTextRulingSettings {
    const next = ReaderTextRuling.copy(settings);
    if (dark) next.colorDark = (color || '').trim();
    else next.color = (color || '').trim();
    return next;
  }

  static thicknessVp(level: number): number {
    return ReaderTextRuling.clampStep(level, ReaderTextRuling.MIN_THICKNESS, ReaderTextRuling.MAX_THICKNESS, 2) * 0.5;
  }

  /** 不透明度乘进 ARGB 的 alpha。 */
  static applyOpacity(argb: number, opacity: number): number {
    const value = argb >>> 0;
    const alpha = (value >>> 24) & 0xFF;
    const percent = ReaderTextRuling.clampStep(opacity, ReaderTextRuling.MIN_OPACITY, ReaderTextRuling.MAX_OPACITY, 40);
    const next = Math.round(alpha * percent / 100);
    return ((next << 24) | (value & 0x00FFFFFF)) >>> 0;
  }

  /**
   * 关闭时返回 null。baseColor 是调用方按 colorMode 取好的颜色（自定义色为空时传正文文字色），
   * vpToPx 是 1vp 对应的像素。
   */
  static spec(settings: ReaderTextRulingSettings, baseColor: number, vpToPx: number): ReaderTextRulingSpec | null {
    if (!settings.enabled) return null;
    const spec = new ReaderTextRulingSpec();
    spec.target = settings.target;
    spec.scope = ReaderTextRuling.effectiveScope(settings);
    spec.style = settings.style;
    spec.position = settings.position;
    spec.color = ReaderTextRuling.applyOpacity(baseColor, settings.opacity);
    spec.widthPx = Math.max(0.5, ReaderTextRuling.thicknessVp(settings.thickness) * Math.max(0.5, vpToPx));
    return spec;
  }

  /** 页对象上记的版本串：设置或解析出的颜色变了就要重新填页。 */
  static stamp(spec: ReaderTextRulingSpec | null): string {
    if (!spec) return 'off';
    return `${spec.target}_${spec.scope}_${spec.style}_${spec.position}_${spec.color}_${Math.round(spec.widthPx * 100)}`;
  }

  private static pick(value: string | undefined, allowed: string[], fallback: string): string {
    return typeof value === 'string' && allowed.indexOf(value) >= 0 ? value : fallback;
  }

  private static clampStep(value: number | undefined, min: number, max: number, fallback: number): number {
    const number = typeof value === 'number' && Number.isFinite(value) ? Math.round(value) : fallback;
    return Math.max(min, Math.min(max, number));
  }
}
