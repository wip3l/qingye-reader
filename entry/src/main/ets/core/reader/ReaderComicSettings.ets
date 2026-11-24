import { Context } from '@kit.AbilityKit';
import { ReaderPageTurnAnimation } from './ReaderPageTurnAnimation';
import preferences from '@ohos.data.preferences';

/** 漫画阅读方式。条漫为上下连续滚动；ltr/rtl 为单页左右翻页（rtl 为日漫的从右往左）。 */
export class ReaderComicMode {
  static readonly WEBTOON: string = 'webtoon';
  static readonly LTR: string = 'ltr';
  static readonly RTL: string = 'rtl';
  /** 横屏/展开阅读方式专用：跟竖屏那份一样。 */
  static readonly FOLLOW: string = 'follow';

  static normalize(value: string): string {
    return value === ReaderComicMode.LTR || value === ReaderComicMode.RTL ? value : ReaderComicMode.WEBTOON;
  }

  /** 横屏/展开那份阅读方式：三种方式之一或“同竖屏”，其他值都当“同竖屏”。 */
  static normalizeWide(value: string): string {
    return value === ReaderComicMode.WEBTOON || value === ReaderComicMode.LTR || value === ReaderComicMode.RTL ?
      value : ReaderComicMode.FOLLOW;
  }

  static isPaged(value: string): boolean {
    return value === ReaderComicMode.LTR || value === ReaderComicMode.RTL;
  }

  static label(value: string): string {
    if (value === ReaderComicMode.FOLLOW) return '同竖屏';
    if (value === ReaderComicMode.LTR) return '从左往右';
    if (value === ReaderComicMode.RTL) return '从右往左';
    return '条漫';
  }
}

export class ReaderComicBackground {
  static readonly BLACK: string = 'black';
  static readonly WHITE: string = 'white';
  static readonly THEME: string = 'theme';

  static normalize(value: string): string {
    return value === ReaderComicBackground.WHITE || value === ReaderComicBackground.THEME ? value :
      ReaderComicBackground.BLACK;
  }
}

export class ReaderComicFit {
  /** 宽度铺满，按原图比例取高度。 */
  static readonly WIDTH: string = 'width';
  /** 整张图放进一屏，必要时左右留边。 */
  static readonly SCREEN: string = 'screen';

  static normalize(value: string): string {
    return value === ReaderComicFit.SCREEN ? value : ReaderComicFit.WIDTH;
  }
}

/** 去白边：裁掉漫画图四周的纯白（或纯黑）空白，检测见 ReaderComicTrimDetect。 */
export class ReaderComicTrimMode {
  static readonly OFF: string = 'off';
  /** 四边都裁；条漫长图仍只裁左右。 */
  static readonly ALL: string = 'all';

  /** 早先的“只裁左右”（'sides'）几乎看不出效果，已并入开启。 */
  static normalize(value: string): string {
    return value === 'sides' || value === ReaderComicTrimMode.ALL ? ReaderComicTrimMode.ALL : ReaderComicTrimMode.OFF;
  }
}

/** 设置面板里并排选项块的一项。 */
export class ReaderComicOption {
  value: string = '';
  label: string = '';
  /** 非空时在文字前画一个色块（背景色选项）。 */
  swatch: string = '';

  constructor(value: string, label: string, swatch: string = '') {
    this.value = value;
    this.label = label;
    this.swatch = swatch;
  }
}

/**
 * 漫画模式的全局设置。阅读方式另有按书覆盖（书籍变量 readerComicReadingMode）。
 * 打开 orientationSplit 后，阅读区够宽（横屏或折叠屏展开，见 ReaderPageTurnAnimation.wideViewport）时
 * 改用横屏那份阅读方式与翻页动画：按书覆盖存书籍变量 readerComicWideReadingMode，没设过用 defaultWideMode。
 */
export class ReaderComicSettings {
  static readonly PAGE_GAPS: number[] = [0, 6, 16];

  defaultMode: string = ReaderComicMode.WEBTOON;
  /** 横向漫画翻页动画，独立保存，避免改变小说的动画偏好。 */
  pageTurnAnimation: number = ReaderPageTurnAnimation.SLIDE;
  /** 横竖屏分开设置阅读方式与翻页动画。 */
  orientationSplit: boolean = false;
  /** 横屏/展开时没单独设置过的漫画用的方式；FOLLOW 表示跟竖屏一样。 */
  defaultWideMode: string = ReaderComicMode.FOLLOW;
  widePageTurnAnimation: number = ReaderPageTurnAnimation.SLIDE;
  background: string = ReaderComicBackground.BLACK;
  pageGap: number = 0;
  fit: string = ReaderComicFit.WIDTH;
  trim: string = ReaderComicTrimMode.OFF;
  /** 点击屏幕两侧翻一屏；关闭后点哪里都呼出菜单。 */
  tapTurn: boolean = true;
  /** 角落里的话名、页码、时间与电量。 */
  infoBar: boolean = true;
  /** 双击放大/还原；关闭后单击不必等待双击判定。 */
  doubleTapZoom: boolean = true;
  /** 横屏或宽屏时翻页模式并排两页。 */
  dualPage: boolean = true;
  /** 端侧 AI 超分（会员功能）；会员到期后保留开关值，续费后自动恢复。 */
  superResolution: boolean = false;
  /** AI 着色与繁→简按书保存；这两项是没单独设置过的书用的默认值。 */
  colorDefault: boolean = false;
  textConvertDefault: boolean = false;

  /** 书籍变量 readerComicColorEnabled：'1' 开、'0' 关，空表示没单独设置过、跟随默认值。 */
  static bookColorEnabled(value: string, settings: ReaderComicSettings): boolean {
    return value === '1' || (value !== '0' && settings.colorDefault);
  }

  /** 书籍变量 readerComicTextConvert：'t2s' 开、'off' 关，空表示没单独设置过、跟随默认值。 */
  static bookTextConvert(value: string, settings: ReaderComicSettings): boolean {
    return value === 't2s' || (value !== 'off' && settings.textConvertDefault);
  }

  copy(): ReaderComicSettings {
    const next = new ReaderComicSettings();
    next.defaultMode = this.defaultMode;
    next.pageTurnAnimation = this.pageTurnAnimation;
    next.orientationSplit = this.orientationSplit;
    next.defaultWideMode = this.defaultWideMode;
    next.widePageTurnAnimation = this.widePageTurnAnimation;
    next.background = this.background;
    next.pageGap = this.pageGap;
    next.fit = this.fit;
    next.trim = this.trim;
    next.tapTurn = this.tapTurn;
    next.infoBar = this.infoBar;
    next.doubleTapZoom = this.doubleTapZoom;
    next.dualPage = this.dualPage;
    next.superResolution = this.superResolution;
    next.colorDefault = this.colorDefault;
    next.textConvertDefault = this.textConvertDefault;
    return next;
  }

  toJson(): string {
    const record: Record<string, Object> = {
      'defaultMode': this.defaultMode,
      'pageTurnAnimation': this.pageTurnAnimation,
      'orientationSplit': this.orientationSplit,
      'defaultWideMode': this.defaultWideMode,
      'widePageTurnAnimation': this.widePageTurnAnimation,
      'background': this.background,
      'pageGap': this.pageGap,
      'fit': this.fit,
      'trim': this.trim,
      'tapTurn': this.tapTurn,
      'infoBar': this.infoBar,
      'doubleTapZoom': this.doubleTapZoom,
      'dualPage': this.dualPage,
      'superResolution': this.superResolution,
      'colorDefault': this.colorDefault,
      'textConvertDefault': this.textConvertDefault
    };
    return JSON.stringify(record);
  }

  static parse(raw: string): ReaderComicSettings {
    const settings = new ReaderComicSettings();
    if (!raw) return settings;
    try {
      const record = JSON.parse(raw) as Record<string, Object>;
      settings.defaultMode = ReaderComicMode.normalize(String(record['defaultMode'] ?? ''));
      settings.pageTurnAnimation = ReaderPageTurnAnimation.normalize(Number(record['pageTurnAnimation'] ??
        ReaderPageTurnAnimation.SLIDE));
      settings.orientationSplit = record['orientationSplit'] === true;
      settings.defaultWideMode = ReaderComicMode.normalizeWide(String(record['defaultWideMode'] ?? ''));
      settings.widePageTurnAnimation = ReaderPageTurnAnimation.normalize(Number(record['widePageTurnAnimation'] ??
        settings.pageTurnAnimation));
      settings.background = ReaderComicBackground.normalize(String(record['background'] ?? ''));
      settings.pageGap = ReaderComicSettings.nearest(Number(record['pageGap']), ReaderComicSettings.PAGE_GAPS, 0);
      settings.fit = ReaderComicFit.normalize(String(record['fit'] ?? ''));
      settings.trim = ReaderComicTrimMode.normalize(String(record['trim'] ?? ''));
      settings.tapTurn = record['tapTurn'] !== false;
      settings.infoBar = record['infoBar'] !== false;
      settings.doubleTapZoom = record['doubleTapZoom'] !== false;
      settings.dualPage = record['dualPage'] !== false;
      settings.superResolution = record['superResolution'] === true;
      settings.colorDefault = record['colorDefault'] === true;
      settings.textConvertDefault = record['textConvertDefault'] === true;
    } catch (_) {
    }
    return settings;
  }

  private static nearest(value: number, options: number[], fallback: number): number {
    if (!Number.isFinite(value)) return fallback;
    let best = options[0];
    for (const option of options) {
      if (Math.abs(option - value) < Math.abs(best - value)) best = option;
    }
    return best;
  }
}

/** 存在 reader_settings 偏好文件里，随阅读设置一起备份恢复。 */
export class ReaderComicSettingsStore {
  private static readonly STORE_NAME: string = 'reader_settings';
  private static readonly KEY: string = 'readerComicSettings';
  // 不另做缓存：preferences 实例本身常驻内存，备份恢复写入同一实例后这里能直接读到新值。
  static async load(context: Context): Promise<ReaderComicSettings> {
    let settings = new ReaderComicSettings();
    try {
      const store = await preferences.getPreferences(context, ReaderComicSettingsStore.STORE_NAME);
      const raw = await store.get(ReaderComicSettingsStore.KEY, '');
      settings = ReaderComicSettings.parse(typeof raw === 'string' ? raw : '');
    } catch (error) {
      console.warn('读取漫画设置失败:', error);
    }
    return settings;
  }

  static async save(context: Context, settings: ReaderComicSettings): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, ReaderComicSettingsStore.STORE_NAME);
      await store.put(ReaderComicSettingsStore.KEY, settings.toJson());
      await store.flush();
    } catch (error) {
      console.warn('保存漫画设置失败:', error);
    }
  }
}
