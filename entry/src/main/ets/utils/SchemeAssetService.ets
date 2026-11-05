import { Context } from '@kit.AbilityKit';
import picker from '@ohos.file.picker';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { ThemePackRegistry, ThemePackRecord } from '../theme/ThemePackRegistry';
import { ThemeIds } from '../theme/ThemeModels';
import {
  isPackThemeId,
  packThemeId,
  ThemePackageAssetKinds,
  ThemePackageBook,
  ThemePackageBubble,
  ThemePackageLimits,
  ThemePackageNavigation,
  ThemePackageTtsPanel,
  ThemePackageVariantParts
} from '../theme/share/ThemePackageFormat';
import { AppThemeSettingsStore } from './AppThemeSettingsStore';
import { ReaderCustomFontData, ReaderCustomFontItem } from '../core/reader/ReaderSettingsModels';
import { ReaderFontHelper } from './ReaderFontHelper';
import { CustomThemeScheme, CustomThemeSchemeStore } from './CustomThemeSchemeStore';
import { ThemePackStore } from './ThemePackStore';

/** 字体库里的一款字体，供编辑器的界面字体下拉使用。 */
export class SchemeFontOption {
  family: string = '';
  name: string = '';
}

/** 一次上传/移除后的结果：方案现在绑定的素材包 ID（空表示没有自己的素材包了）。 */
export class SchemeAssetResult {
  packageId: string = '';
  themeId: string = '';
}

/**
 * 自定义方案在编辑器里直接上传的素材：封面、书架边框、文件夹插画、导航图标、朗读面板插画、气泡端饰与边框。
 * 素材放进方案自己的素材包（theme_packs/custom-<随机>/，与导入的主题包同一套存储和注册），方案的 packageId
 * 指向它；导出时随包打出去，删方案时随包清理。方案本身由主题包安装而来时直接写进那个包。
 */
export class SchemeAssetService {
  static readonly IMAGE: string[] = [ThemePackageAssetKinds.IMAGE];
  static readonly VECTOR: string[] = [ThemePackageAssetKinds.VECTOR];
  static readonly ARTWORK: string[] = [ThemePackageAssetKinds.IMAGE, ThemePackageAssetKinds.VECTOR];

  static async pickImages(context: Context, max: number): Promise<string[]> {
    const options = new picker.PhotoSelectOptions();
    options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = max;
    const result = await new picker.PhotoViewPicker(context).select(options);
    return result && result.photoUris ? result.photoUris.slice(0, max) : [];
  }

  static async pickSvgFiles(context: Context, max: number): Promise<string[]> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = max;
    options.fileSuffixFilters = ['SVG|.svg'];
    const result = await new picker.DocumentViewPicker(context).select(options);
    return result ? result.slice(0, max) : [];
  }

  /** 用户字体库（阅读设置的 customFontsRaw）里可绑定为界面字体的字体。 */
  static fontOptions(raw: string): SchemeFontOption[] {
    const options: SchemeFontOption[] = [];
    const text = (raw || '').trim();
    if (!text) return options;
    try {
      const parsed = JSON.parse(text) as ReaderCustomFontData | ReaderCustomFontItem[];
      const items = Array.isArray(parsed) ? parsed as ReaderCustomFontItem[] :
        ((parsed as ReaderCustomFontData).fonts || []);
      for (const item of items) {
        if (!item || !item.filePath) continue;
        const option = new SchemeFontOption();
        option.family = item.familyName || ReaderFontHelper.normalizeFontFamily(item.filePath);
        option.name = ReaderFontHelper.resolveDisplayName(item.sourceName || '', item.filePath);
        if (option.family && !options.some((existing: SchemeFontOption): boolean => existing.family === option.family)) {
          options.push(option);
        }
      }
    } catch (_) {
    }
    return options;
  }

  /** 方案的素材包（已安装时）。 */
  static packageIdOf(scheme: CustomThemeScheme): string {
    return scheme.packageId && ThemePackRegistry.getByPackageId(scheme.packageId) ? scheme.packageId : '';
  }

  static async addCovers(context: Context, schemeId: string, uris: string[], baseTheme: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const book = record.parts.book || new ThemePackageBook();
      for (const uri of uris) {
        if (book.covers.length >= ThemePackageLimits.MAX_COVERS) break;
        const path = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.IMAGE, '封面');
        if (!book.covers.includes(path)) book.covers.push(path);
      }
      record.parts.book = book;
    });
  }

  static async setShelfFrame(context: Context, schemeId: string, uri: string, baseTheme: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const book = record.parts.book || new ThemePackageBook();
      book.shelfFrame = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.VECTOR, '书架边框');
      record.parts.book = book;
    });
  }

  static async setShelfFolder(context: Context, schemeId: string, uri: string, baseTheme: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const book = record.parts.book || new ThemePackageBook();
      book.shelfFolder = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.IMAGE, '文件夹插画');
      record.parts.book = book;
    });
  }

  /**
   * 阅读背景角饰：左上或右下一张图（SVG 或位图）。只上传了一张时另一角用同一张旋转 180°，
   * 记录里也写成两张，导出后能通过格式校验。
   */
  static async setReaderOrnament(context: Context, schemeId: string, uri: string, trailing: boolean,
    darkMode: boolean, baseTheme: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const variant = SchemeAssetService.variantOf(record, darkMode);
      const path = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.ARTWORK,
        trailing ? '右下角饰' : '左上角饰');
      if (trailing) {
        variant.reader.trailing = path;
        if (!variant.reader.leading) variant.reader.leading = path;
      } else {
        // 右下角没单独传过（为空或就是旧的左上角那张）时跟着换。
        const mirrored = !variant.reader.trailing || variant.reader.trailing === variant.reader.leading;
        variant.reader.leading = path;
        if (mirrored) variant.reader.trailing = path;
      }
      variant.reader.image = '';
      variant.reader.backgroundMode = 'ornaments';
      SchemeAssetService.storeVariant(record, darkMode, variant);
    });
  }

  /** 阅读背景整图：铺满（cover）。 */
  static async setReaderImage(context: Context, schemeId: string, uri: string, darkMode: boolean,
    baseTheme: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const variant = SchemeAssetService.variantOf(record, darkMode);
      variant.reader.image = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.IMAGE, '阅读背景');
      variant.reader.imageFit = 'cover';
      variant.reader.leading = '';
      variant.reader.trailing = '';
      variant.reader.backgroundMode = 'image';
      SchemeAssetService.storeVariant(record, darkMode, variant);
    });
  }

  static async clearReader(context: Context, schemeId: string, darkMode: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      SchemeAssetService.storeVariant(record, darkMode, null);
    });
  }

  private static variantOf(record: ThemePackRecord, darkMode: boolean): ThemePackageVariantParts {
    const existing = darkMode ? record.parts.dark : record.parts.light;
    if (existing) return existing;
    return new ThemePackageVariantParts();
  }

  /** 编辑器只往变体里写阅读背景，所以清掉背景就等于清掉整个变体。 */
  private static storeVariant(record: ThemePackRecord, darkMode: boolean,
    variant: ThemePackageVariantParts | null): void {
    if (darkMode) record.parts.dark = variant;
    else record.parts.light = variant;
  }

  static readerMode(packageId: string, darkMode: boolean): string {
    const pack = ThemePackRegistry.getByPackageId(packageId);
    if (!pack) return '';
    const variant = darkMode ? pack.record.parts.dark : pack.record.parts.light;
    return variant ? variant.reader.backgroundMode : '';
  }

  static async clearBook(context: Context, schemeId: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      record.parts.book = null;
    });
  }

  /**
   * 四个导航图标：按文件名里的 bookshelf / explore / search / mine 对号入座，认不出的按选择顺序补位。
   */
  static async setNavigation(context: Context, schemeId: string, uris: string[], baseTheme: string): Promise<SchemeAssetResult> {
    if (uris.length !== 4) {
      throw new Error('导航图标需要一次选择 4 个 SVG');
    }
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const slots: string[] = ['', '', '', ''];
      const keywords: string[][] = [['bookshelf', 'shelf', 'book'], ['explore', 'discover', 'find'],
        ['search', 'find'], ['mine', 'me', 'user', 'profile']];
      const leftover: string[] = [];
      for (const uri of uris) {
        const name = SchemeAssetService.fileName(uri).toLowerCase();
        let placed = false;
        for (let slot = 0; slot < 4 && !placed; slot++) {
          if (slots[slot]) continue;
          for (const keyword of keywords[slot]) {
            if (name.includes(keyword)) {
              slots[slot] = uri;
              placed = true;
              break;
            }
          }
        }
        if (!placed) leftover.push(uri);
      }
      for (let slot = 0; slot < 4; slot++) {
        if (!slots[slot] && leftover.length > 0) slots[slot] = leftover.shift() || '';
      }
      const navigation = new ThemePackageNavigation();
      navigation.bookshelf = await ThemePackStore.importAsset(context, record.packageId, slots[0], SchemeAssetService.VECTOR, '书架图标');
      navigation.explore = await ThemePackStore.importAsset(context, record.packageId, slots[1], SchemeAssetService.VECTOR, '发现图标');
      navigation.search = await ThemePackStore.importAsset(context, record.packageId, slots[2], SchemeAssetService.VECTOR, '搜索图标');
      navigation.mine = await ThemePackStore.importAsset(context, record.packageId, slots[3], SchemeAssetService.VECTOR, '我的图标');
      record.parts.navigation = navigation;
    });
  }

  static async clearNavigation(context: Context, schemeId: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      record.parts.navigation = null;
    });
  }

  /** 朗读面板插画；天空色、面板底色和柔光色从方案当前配色推出来。 */
  static async setTtsArtwork(context: Context, schemeId: string, uri: string, darkMode: boolean,
    scheme: CustomThemeScheme, baseTheme: string): Promise<SchemeAssetResult> {
    const theme = AppThemeSettingsStore.customTheme(scheme.settings, darkMode);
    const colors = darkMode ? theme.dark.colors : theme.light.colors;
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const panel = new ThemePackageTtsPanel();
      panel.artwork = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.ARTWORK, '面板插画');
      panel.skyColor = colors.inputColor;
      panel.surfaceColor = colors.pageColor;
      panel.glowColor = `#2E${colors.accentColor.substring(1)}`;
      if (darkMode) record.parts.ttsPanelDark = panel;
      else record.parts.ttsPanelLight = panel;
    });
  }

  static async clearTts(context: Context, schemeId: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      record.parts.ttsPanelLight = null;
      record.parts.ttsPanelDark = null;
    });
  }

  static async setBubbleCap(context: Context, schemeId: string, uri: string, baseTheme: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const bubble = record.parts.bubble || new ThemePackageBubble();
      bubble.cap = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.VECTOR, '气泡端饰');
      record.parts.bubble = bubble;
    });
  }

  static async setBubbleFrame(context: Context, schemeId: string, uri: string, baseTheme: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const bubble = record.parts.bubble || new ThemePackageBubble();
      bubble.frame = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.VECTOR, '气泡边框');
      record.parts.bubble = bubble;
    });
  }

  static async clearBubble(context: Context, schemeId: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      record.parts.bubble = null;
    });
  }

  /**
   * 取（或建）方案的素材包，改 parts，清掉不再引用的文件，重新注册。
   * 改完没有任何部件时整个卸掉并解绑，方案回到纯组合状态。
   */
  private static async update(context: Context, schemeId: string, baseTheme: string,
    mutate: (record: ThemePackRecord) => Promise<void>): Promise<SchemeAssetResult> {
    const appSettings = await AppThemeSettingsStore.load(context);
    const schemes = await CustomThemeSchemeStore.load(context, appSettings);
    const scheme = CustomThemeSchemeStore.find(schemes, schemeId);
    if (!scheme) {
      throw new Error('方案不存在');
    }
    let record = scheme.packageId ? ThemePackStore.readRecord(context, scheme.packageId) : null;
    let created = false;
    if (!record) {
      record = new ThemePackRecord();
      record.packageId = `custom-${SchemeAssetService.randomHex(8)}`;
      record.name = scheme.name;
      record.author = scheme.author;
      record.installedAt = Date.now();
      // 第一次上传时所在部件的来源主题当作基底：没上传的那部分素材继续取自它。
      record.baseTheme = baseTheme && !isPackThemeId(baseTheme) ?
        BuiltinThemeRegistry.normalizeBuiltinId(baseTheme) : BuiltinThemeRegistry.DEFAULT_THEME_ID;
      ThemePackStore.prepareDir(context, record.packageId);
      created = true;
    }
    try {
      await mutate(record);
    } catch (e) {
      // 新建的包还没登记到方案上，失败就整个清掉；已有的包只清掉这次写进去的多余文件。
      if (created) ThemePackStore.uninstall(context, record.packageId);
      else ThemePackStore.pruneAssets(context, ThemePackStore.readRecord(context, record.packageId) || record);
      throw e as Error;
    }
    const result = new SchemeAssetResult();
    if (!SchemeAssetService.hasAnyPart(record)) {
      ThemePackStore.uninstall(context, record.packageId);
      if (scheme.packageId) await CustomThemeSchemeStore.setPackageId(context, appSettings, schemeId, '');
      return result;
    }
    ThemePackStore.pruneAssets(context, record);
    ThemePackStore.install(context, record);
    if (created || scheme.packageId !== record.packageId) {
      await CustomThemeSchemeStore.setPackageId(context, appSettings, schemeId, record.packageId);
    }
    result.packageId = record.packageId;
    result.themeId = packThemeId(record.packageId);
    return result;
  }

  static hasAnyPart(record: ThemePackRecord): boolean {
    const parts = record.parts;
    return !!(parts.light || parts.dark || parts.ttsPanelLight || parts.ttsPanelDark || parts.navigation ||
      parts.book || parts.startupLight || parts.startupDark || parts.bubble || parts.logo || parts.preview ||
      parts.radius || parts.appFont || parts.appFontFamily);
  }

  private static fileName(uri: string): string {
    const clean = uri.split('?')[0].split('#')[0];
    const slash = clean.lastIndexOf('/');
    let name = slash >= 0 ? clean.substring(slash + 1) : clean;
    try {
      name = decodeURIComponent(name);
    } catch (_) {
    }
    return name;
  }

  private static randomHex(bytes: number): string {
    let hex = '';
    for (let i = 0; i < bytes; i++) {
      const value = Math.floor(Math.random() * 256);
      hex += (value < 16 ? '0' : '') + value.toString(16);
    }
    return hex;
  }

  /** 编辑器判断某类素材是否已上传。 */
  static hasBook(packageId: string): boolean {
    const pack = ThemePackRegistry.getByPackageId(packageId);
    return !!pack && !!pack.record.parts.book;
  }

  static hasNavigation(packageId: string): boolean {
    const pack = ThemePackRegistry.getByPackageId(packageId);
    return !!pack && !!pack.record.parts.navigation;
  }

  static hasTts(packageId: string): boolean {
    const pack = ThemePackRegistry.getByPackageId(packageId);
    return !!pack && !!(pack.record.parts.ttsPanelLight || pack.record.parts.ttsPanelDark);
  }

  static hasBubble(packageId: string): boolean {
    const pack = ThemePackRegistry.getByPackageId(packageId);
    return !!pack && !!pack.record.parts.bubble;
  }

  static coverCount(packageId: string): number {
    const pack = ThemePackRegistry.getByPackageId(packageId);
    return pack && pack.record.parts.book ? pack.record.parts.book.covers.length : 0;
  }

  static baseThemeOf(packageId: string): string {
    const pack = ThemePackRegistry.getByPackageId(packageId);
    return pack ? (pack.baseTheme || ThemeIds.PLAIN_DEFAULT) : ThemeIds.PLAIN_DEFAULT;
  }
}
