import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import fs from '@ohos.file.fs';
import { fileUri } from '../platform/FileUri';
import { copyFile, selectImages } from '../platform/Files';
import { ReaderBackgroundDisplay } from './ReaderBackgroundDisplay';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { ThemePackageShelfBackdropDisplay } from '../theme/share/ThemePackageFormat';

/**
 * 书架自己的背景设置（书架设置 › 书架背景）。
 * - source：theme 跟随主题（首页背景的原有逻辑），custom 用这里上传的图。
 * - display：top 和主题背景一样按 4 : 5 铺在顶部往下淡出；full 铺满整屏，图片显示方式同阅读背景。
 * - 浅色、深色各一张；深色没传时用浅色那张（连取景一起）。淡化、模糊按模式分开记，图片显示方式两种模式共用。
 * 四种书架布局共用一份，只影响书架和书架分组页，不跟主题走。只存本机，不进云同步和数据备份。
 */
export class ShelfBackdropConfig {
  source: string = 'theme';
  display: string = 'full';
  fit: string = 'cover';
  gap: string = 'blur';
  lightImage: string = '';
  darkImage: string = '';
  lightPosition: number = 50;
  darkPosition: number = 50;
  // 与 ShelfBackdropStore.DEFAULT_LIGHT_WASH / DEFAULT_DARK_WASH 一致（这里还不能引用后面的类）。
  lightWash: number = 30;
  darkWash: number = 45;
  lightBlur: number = 0;
  darkBlur: number = 0;
}

/** 某个模式实际要画的样子；image 为空表示这个模式不用自定义背景。 */
export class ShelfBackdropLook {
  image: string = '';
  display: string = 'full';
  fit: string = 'cover';
  position: number = 50;
  gap: string = 'blur';
  /** 0～ShelfBackdropStore.MAX_WASH，盖在图上的页面底色不透明度（百分比）。 */
  wash: number = 0;
  /** 0～ShelfBackdropStore.MAX_BLUR，整张背景的模糊半径（vp）。 */
  blur: number = 0;
}

export class ShelfBackdropStore {
  static readonly STORE_NAME: string = 'shelf_backdrop';
  static readonly REVISION_KEY: string = 'shelfBackdropRevision';
  static readonly SOURCE_THEME: string = 'theme';
  static readonly SOURCE_CUSTOM: string = 'custom';
  static readonly DISPLAY_TOP: string = 'top';
  static readonly DISPLAY_FULL: string = 'full';
  static readonly MAX_WASH: number = 80;
  static readonly MAX_BLUR: number = 20;
  static readonly DEFAULT_LIGHT_WASH: number = 30;
  static readonly DEFAULT_DARK_WASH: number = 45;
  private static readonly CONFIG_KEY: string = 'config';
  private static readonly DIR: string = 'shelf_backdrops';
  private static config: ShelfBackdropConfig = new ShelfBackdropConfig();
  private static writes: Promise<void> = Promise.resolve();
  private static editRevision: number = 0;

  static async load(context: Context): Promise<void> {
    const revision = ShelfBackdropStore.editRevision;
    const store = await preferences.getPreferences(context, ShelfBackdropStore.STORE_NAME);
    const raw = await store.get(ShelfBackdropStore.CONFIG_KEY, '');
    // 启动途中已经改过，就不拿旧值盖回去。
    if (revision !== ShelfBackdropStore.editRevision) return;
    ShelfBackdropStore.config = ShelfBackdropStore.parse(typeof raw === 'string' ? raw : '');
    ShelfBackdropStore.bump();
  }

  /** 当前设置的副本，改完交给 preview / save。 */
  static current(): ShelfBackdropConfig {
    return ShelfBackdropStore.copy(ShelfBackdropStore.config);
  }

  /** 这个模式要不要画自定义背景（选了自定义且有图）。 */
  static customActive(dark: boolean): boolean {
    return ShelfBackdropStore.lookOf(ShelfBackdropStore.config, dark) !== null;
  }

  static look(dark: boolean): ShelfBackdropLook | null {
    return ShelfBackdropStore.lookOf(ShelfBackdropStore.config, dark);
  }

  static lookOf(config: ShelfBackdropConfig, dark: boolean): ShelfBackdropLook | null {
    if (config.source !== ShelfBackdropStore.SOURCE_CUSTOM) return null;
    const own = dark && !!config.darkImage;
    const image = own ? config.darkImage : config.lightImage;
    if (!image) return null;
    const look = new ShelfBackdropLook();
    look.image = image;
    look.display = config.display;
    look.fit = config.fit;
    look.gap = config.gap;
    look.position = own ? config.darkPosition : config.lightPosition;
    look.wash = dark ? config.darkWash : config.lightWash;
    look.blur = dark ? config.darkBlur : config.lightBlur;
    return look;
  }

  /**
   * 书架页实际要按“自定义样式”画的背景：书架设置里的自定义图优先；跟随主题时主题包设了全屏，
   * 就用主题的书架图（按布局）加主题的显示设置。其余（主题图顶部淡出、没有图）返回 null，照旧由首页背景画。
   */
  static resolve(dark: boolean, shelfLayout: string): ShelfBackdropLook | null {
    const custom = ShelfBackdropStore.look(dark);
    if (custom) return custom;
    const display = ThemeAssetRegistry.shelfBackdropDisplay(ThemeRuntime.homeBackdropThemeId(dark));
    if (!display) return null;
    const image = ThemeRuntime.homeBackdrop(dark, shelfLayout);
    return typeof image === 'string' && image ? ShelfBackdropStore.themeLook(display, image, dark) : null;
  }

  /** 主题包的全屏设置换成要画的样子。 */
  static themeLook(display: ThemePackageShelfBackdropDisplay, image: string, dark: boolean): ShelfBackdropLook {
    const look = new ShelfBackdropLook();
    look.image = image;
    look.display = ShelfBackdropStore.DISPLAY_FULL;
    look.fit = display.fit;
    look.position = display.position;
    look.gap = display.gap;
    look.wash = dark ? display.darkWash : display.lightWash;
    look.blur = display.blur;
    return look;
  }

  /** 拖动滑条、取景途中先换内存里的值让书架跟着变，不写盘；松手时再 save。 */
  static preview(config: ShelfBackdropConfig): void {
    ++ShelfBackdropStore.editRevision;
    ShelfBackdropStore.config = ShelfBackdropStore.normalize(config);
    ShelfBackdropStore.bump();
  }

  static save(context: Context, config: ShelfBackdropConfig): Promise<void> {
    ++ShelfBackdropStore.editRevision;
    const previous = ShelfBackdropStore.config;
    ShelfBackdropStore.config = ShelfBackdropStore.normalize(config);
    ShelfBackdropStore.bump();
    ShelfBackdropStore.removeUnused(context, previous, ShelfBackdropStore.config);
    const raw = JSON.stringify(ShelfBackdropStore.config);
    const write = ShelfBackdropStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, ShelfBackdropStore.STORE_NAME);
      await store.put(ShelfBackdropStore.CONFIG_KEY, raw);
      await store.flush();
    });
    ShelfBackdropStore.writes = write.catch(() => {});
    return write;
  }

  /** 从相册选一张复制进应用目录，返回 file:// 地址；用户取消时返回空串。旧图由 save 清理。 */
  static async pickImage(context: Context, dark: boolean): Promise<string> {
    const photoUris = await selectImages(context, 1);
    if (photoUris.length === 0) return '';
    const source = photoUris[0];
    const dir = `${context.filesDir}/${ShelfBackdropStore.DIR}`;
    try {
      await fs.mkdir(dir, true);
    } catch (_) {
    }
    const path = `${dir}/${dark ? 'dark' : 'light'}_${Date.now()}${ShelfBackdropStore.extension(source)}`;
    if (source.startsWith('/')) {
      fs.copyFileSync(source, path);
    } else {
      await copyFile(source, fileUri.getUriFromPath(path));
    }
    return fileUri.getUriFromPath(path);
  }

  /** 换图、清图后旧文件没人用了就删掉；只删本目录里的。 */
  private static removeUnused(context: Context, before: ShelfBackdropConfig, after: ShelfBackdropConfig): void {
    const keep: string[] = [after.lightImage, after.darkImage];
    for (const uri of [before.lightImage, before.darkImage]) {
      if (!uri || keep.indexOf(uri) >= 0) continue;
      try {
        const path = uri.startsWith('file://') ? new fileUri.FileUri(uri).path : uri;
        if (path.startsWith(`${context.filesDir}/${ShelfBackdropStore.DIR}/`) && fs.accessSync(path)) {
          fs.unlinkSync(path);
        }
      } catch (error) {
        console.warn('删除书架背景图失败:', error);
      }
    }
  }

  private static bump(): void {
    const current = AppStorage.get<number>(ShelfBackdropStore.REVISION_KEY) ?? 0;
    AppStorage.setOrCreate<number>(ShelfBackdropStore.REVISION_KEY, current + 1);
  }

  private static parse(raw: string): ShelfBackdropConfig {
    if (!raw.trim()) return new ShelfBackdropConfig();
    try {
      const parsed = JSON.parse(raw) as ShelfBackdropConfig;
      if (!parsed || typeof parsed !== 'object') return new ShelfBackdropConfig();
      return ShelfBackdropStore.normalize(parsed);
    } catch (error) {
      console.warn('读取书架背景设置失败:', error);
      return new ShelfBackdropConfig();
    }
  }

  private static normalize(value: ShelfBackdropConfig): ShelfBackdropConfig {
    const config = new ShelfBackdropConfig();
    config.source = value.source === ShelfBackdropStore.SOURCE_CUSTOM ? value.source : ShelfBackdropStore.SOURCE_THEME;
    config.display = value.display === ShelfBackdropStore.DISPLAY_TOP ? value.display : ShelfBackdropStore.DISPLAY_FULL;
    config.fit = ReaderBackgroundDisplay.normalizeFit(value.fit);
    config.gap = value.gap === ReaderBackgroundDisplay.GAP_COLOR ? value.gap : ReaderBackgroundDisplay.GAP_BLUR;
    config.lightImage = typeof value.lightImage === 'string' ? value.lightImage : '';
    config.darkImage = typeof value.darkImage === 'string' ? value.darkImage : '';
    config.lightPosition = ReaderBackgroundDisplay.normalizePosition(value.lightPosition);
    config.darkPosition = ReaderBackgroundDisplay.normalizePosition(value.darkPosition);
    config.lightWash = ShelfBackdropStore.clamp(value.lightWash, ShelfBackdropStore.MAX_WASH,
      ShelfBackdropStore.DEFAULT_LIGHT_WASH);
    config.darkWash = ShelfBackdropStore.clamp(value.darkWash, ShelfBackdropStore.MAX_WASH,
      ShelfBackdropStore.DEFAULT_DARK_WASH);
    config.lightBlur = ShelfBackdropStore.clamp(value.lightBlur, ShelfBackdropStore.MAX_BLUR, 0);
    config.darkBlur = ShelfBackdropStore.clamp(value.darkBlur, ShelfBackdropStore.MAX_BLUR, 0);
    return config;
  }

  private static copy(value: ShelfBackdropConfig): ShelfBackdropConfig {
    return ShelfBackdropStore.normalize(value);
  }

  private static clamp(value: number, max: number, fallback: number): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) return fallback;
    return Math.max(0, Math.min(max, Math.round(value)));
  }

  private static extension(value: string): string {
    const lower = (value || '').toLowerCase();
    if (lower.includes('.png')) return '.png';
    if (lower.includes('.webp')) return '.webp';
    if (lower.includes('.bmp')) return '.bmp';
    if (lower.includes('.gif')) return '.gif';
    return '.jpg';
  }
}
