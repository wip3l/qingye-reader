/**
 * 书架设置 › 封面 › 深色模式调暗封面。开启后深色模式下在封面图上盖一层黑色半透明，压低亮度；
 * 只压图片，角标、标记和文字画在这一层之上。主题自带的书籍封面（带书框）是为深色模式单独设计的，不调暗。
 * 开关和程度随封面图集设置一起存在 CoverGalleryStore 里。
 */
export class CoverDimSettings {
  static readonly KEY_ENABLED: string = 'bookshelfDarkCoverDim';
  static readonly KEY_LEVEL: string = 'bookshelfDarkCoverDimLevel';
  /** 可选程度（遮罩不透明度百分比），依次为轻、中、强。 */
  static readonly LEVELS: number[] = [15, 20, 30];
  static readonly LEVEL_NAMES: string[] = ['轻', '中', '强'];
  static readonly DEFAULT_LEVEL: number = 20;

  static normalizeLevel(level: number): number {
    return CoverDimSettings.LEVELS.includes(level) ? level : CoverDimSettings.DEFAULT_LEVEL;
  }

  /** 遮罩不透明度；不需要调暗时为 0，调用方据此不建遮罩节点。 */
  static opacity(darkMode: boolean, enabled: boolean, level: number): number {
    if (!darkMode || !enabled) return 0;
    return CoverDimSettings.normalizeLevel(level) / 100;
  }
}
