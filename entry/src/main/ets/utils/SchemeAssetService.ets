import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import picker from '@ohos.file.picker';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { ThemePackRegistry, ThemePackRecord } from '../theme/ThemePackRegistry';
import { ThemeIds } from '../theme/ThemeModels';
import {
  isPackThemeId,
  NAVIGATION_ICON_KEYS,
  packThemeId,
  ThemePackageAssetKinds,
  ThemePackageBook,
  ThemePackageBubble,
  ThemePackageLimits,
  ThemePackageNavigation,
  ThemePackageTtsPanel,
  ThemePackageVariantParts
} from '../theme/share/ThemePackageFormat';
import { AppThemeSettings, AppThemeSettingsStore } from './AppThemeSettingsStore';
import { ReaderCustomFontData, ReaderCustomFontItem } from '../core/reader/ReaderSettingsModels';
import { ReaderFontHelper } from './ReaderFontHelper';
import { CustomThemeScheme, CustomThemeSchemeStore } from './CustomThemeSchemeStore';
import { ThemePackStore } from './ThemePackStore';
import { CustomThemeQuota } from '../account/CustomThemeQuota';
import { ReaderSettingsStore } from './ReaderSettingsStore';

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
 * 自定义方案在编辑器里直接上传的素材：封面、书架边框、文件夹插画、导航图标、朗读面板插画、气泡端饰与边框、首页背景。
 * 素材放进方案自己的素材包（theme_packs/custom-<随机>/，与导入的主题包同一套存储和注册），方案的 packageId
 * 指向它；导出时随包打出去，删方案时随包清理。方案本身由主题包安装而来时直接写进那个包。
 */
export class SchemeAssetService {
  static readonly IMAGE: string[] = [ThemePackageAssetKinds.IMAGE];
  static readonly VECTOR: string[] = [ThemePackageAssetKinds.VECTOR];
  static readonly ARTWORK: string[] = [ThemePackageAssetKinds.IMAGE, ThemePackageAssetKinds.VECTOR];
  /** 编辑器能上传的底栏页签：前三个是主题包必备，“听”“足迹”可选。 */
  static readonly NAVIGATION_TABS: string[] = ['bookshelf', 'explore', 'mine', 'listen', 'footprint'];

  static async pickImages(context: Context, max: number): Promise<string[]> {
    const options = new picker.PhotoSelectOptions();
    options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = max;
    const result = await new picker.PhotoViewPicker(context).select(options);
    return result && result.photoUris ? result.photoUris.slice(0, max) : [];
  }

  /** 导航图标与主题标识：SVG 跟主题色着色，PNG / WebP 保持原色。 */
  static async pickIconFiles(context: Context, max: number): Promise<string[]> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = max;
    options.fileSuffixFilters = ['图标|.svg,.png,.webp'];
    const result = await new picker.DocumentViewPicker(context).select(options);
    return result ? result.slice(0, max) : [];
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
   * 一次选多个导航图标：按文件名里的 bookshelf / explore / mine / listen / footprint 对号入座，认不出的按选择
   * 顺序补进还空着的页签。已有的选中态和“只显示图标”保留。
   */
  static async setNavigation(context: Context, schemeId: string, uris: string[], baseTheme: string): Promise<SchemeAssetResult> {
    if (uris.length === 0 || uris.length > SchemeAssetService.NAVIGATION_TABS.length) {
      throw new Error(`导航图标一次最多选 ${SchemeAssetService.NAVIGATION_TABS.length} 个`);
    }
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      if (!record.parts.navigation) SchemeAssetService.rememberNavigationFallback(record, baseTheme);
      const navigation = record.parts.navigation || new ThemePackageNavigation();
      const tabs: string[] = SchemeAssetService.NAVIGATION_TABS;
      const slots: string[] = tabs.map((): string => '');
      const keywords: string[][] = [['bookshelf', 'shelf', 'book'], ['explore', 'discover'],
        ['mine', 'me', 'user', 'profile'], ['listen', 'audio', 'headphone'], ['footprint', 'history', 'stats']];
      // 先认“听”“足迹”：mine 的关键词 me 会被 theme_listen 这类文件名误中。
      const matchOrder: number[] = [3, 4, 0, 1, 2];
      const leftover: string[] = [];
      for (const uri of uris) {
        const name = SchemeAssetService.fileName(uri).toLowerCase();
        let placed = false;
        for (const slot of matchOrder) {
          if (placed) break;
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
      const fields = navigation as Object as Record<string, string>;
      // 认不出名字的先补没有图标的页签，再按顺序覆盖。
      for (let slot = 0; slot < tabs.length && leftover.length > 0; slot++) {
        if (!slots[slot] && !fields[tabs[slot]]) slots[slot] = leftover.shift() || '';
      }
      for (let slot = 0; slot < tabs.length && leftover.length > 0; slot++) {
        if (!slots[slot]) slots[slot] = leftover.shift() || '';
      }
      for (let slot = 0; slot < tabs.length; slot++) {
        if (!slots[slot]) continue;
        fields[tabs[slot]] = await ThemePackStore.importAsset(context, record.packageId, slots[slot],
          SchemeAssetService.ARTWORK, SchemeAssetService.navigationLabel(tabs[slot]));
      }
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

  /** 首页背景：浅色、深色各一张，互不借用。 */
  static async setHomeBackdrop(context: Context, schemeId: string, uri: string, darkMode: boolean,
    baseTheme: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const path = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.IMAGE, '首页背景');
      if (darkMode) record.parts.homeBackdropDark = path;
      else record.parts.homeBackdropLight = path;
    });
  }

  static async clearHomeBackdrop(context: Context, schemeId: string, darkMode: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      if (darkMode) record.parts.homeBackdropDark = '';
      else record.parts.homeBackdropLight = '';
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

  // ---- 逐个管理的素材 ----

  /** 替换第 index 张封面。 */
  static async replaceCover(context: Context, schemeId: string, index: number, uri: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const book = record.parts.book;
      if (!book || index < 0 || index >= book.covers.length) throw new Error('这张封面已不存在');
      const path = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.IMAGE, '封面');
      if (book.covers.includes(path)) throw new Error('这张图已经在封面里了');
      book.covers[index] = path;
    });
  }

  /** 删掉第 index 张封面；封面、边框、文件夹都没了时整节清掉。 */
  static async removeCover(context: Context, schemeId: string, index: number): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const book = record.parts.book;
      if (!book || index < 0 || index >= book.covers.length) return;
      book.covers.splice(index, 1);
      SchemeAssetService.tidyBook(record);
    });
  }

  /** 调整轮播顺序：把 from 位置的封面挪到 to。 */
  static async moveCover(context: Context, schemeId: string, from: number, to: number): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const book = record.parts.book;
      if (!book || from === to || from < 0 || to < 0 || from >= book.covers.length || to >= book.covers.length) return;
      const moved = book.covers.splice(from, 1)[0];
      book.covers.splice(to, 0, moved);
    });
  }

  static async clearShelfFrame(context: Context, schemeId: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      if (record.parts.book) record.parts.book.shelfFrame = '';
      SchemeAssetService.tidyBook(record);
    });
  }

  static async clearShelfFolder(context: Context, schemeId: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      if (record.parts.book) record.parts.book.shelfFolder = '';
      SchemeAssetService.tidyBook(record);
    });
  }

  private static tidyBook(record: ThemePackRecord): void {
    const book = record.parts.book;
    if (book && book.covers.length === 0 && !book.shelfFrame && !book.shelfFolder) record.parts.book = null;
  }

  /**
   * 单个导航图标（key 是 bookshelf / exploreSelected 这类字段名）。三个普通图标不必一次传齐：
   * 没传的页签显示基底主题的图标，传齐三个之前分享导出时不带导航图标。
   */
  static async setNavigationIcon(context: Context, schemeId: string, key: string, uri: string,
    baseTheme: string): Promise<SchemeAssetResult> {
    if (!NAVIGATION_ICON_KEYS.includes(key)) throw new Error('未知的导航图标');
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      if (!record.parts.navigation) SchemeAssetService.rememberNavigationFallback(record, baseTheme);
      const navigation = record.parts.navigation || new ThemePackageNavigation();
      const path = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.ARTWORK,
        SchemeAssetService.navigationLabel(key));
      (navigation as Object as Record<string, string>)[key] = path;
      record.parts.navigation = navigation;
    });
  }

  /** 移除单个导航图标；普通图标一个都不剩时连选中态和“只显示图标”一起清掉。 */
  static async clearNavigationIcon(context: Context, schemeId: string, key: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const navigation = record.parts.navigation;
      if (!navigation || !NAVIGATION_ICON_KEYS.includes(key)) return;
      (navigation as Object as Record<string, string>)[key] = '';
      if (!navigation.bookshelf && !navigation.explore && !navigation.mine && !navigation.listen &&
        !navigation.footprint) {
        record.parts.navigation = null;
      }
    });
  }

  static async setNavigationLabelsHidden(context: Context, schemeId: string, hidden: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      if (!record.parts.navigation) throw new Error('请先上传导航图标');
      record.parts.navigation.labels = hidden ? 'hidden' : '';
    });
  }

  /** 第一次上传导航图标时记下当时导航来源的内置图标，没传齐的页签继续显示它们。 */
  private static rememberNavigationFallback(record: ThemePackRecord, sourceThemeId: string): void {
    record.navFallbackIconPackId = sourceThemeId && !isPackThemeId(sourceThemeId) ?
      BuiltinThemeRegistry.findById(sourceThemeId).navigation.iconPackId : '';
  }

  static navigationLabel(key: string): string {
    const tab = key.replace('Selected', '');
    let name = '书架';
    if (tab === 'explore') name = '发现';
    else if (tab === 'mine') name = '我的';
    else if (tab === 'listen') name = '听';
    else if (tab === 'footprint') name = '足迹';
    return `${name}${key.endsWith('Selected') ? '选中' : ''}图标`;
  }

  /** 移除右下角饰：恢复成左上角那张旋转 180°；移除左上角饰或整图：这个模式的背景素材全部清掉。 */
  static async clearReaderSlot(context: Context, schemeId: string, darkMode: boolean,
    slot: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const variant = darkMode ? record.parts.dark : record.parts.light;
      if (!variant) return;
      if (slot === 'trailing' && variant.reader.leading) {
        variant.reader.trailing = variant.reader.leading;
        return;
      }
      SchemeAssetService.storeVariant(record, darkMode, null);
    });
  }

  static async setReaderImageFit(context: Context, schemeId: string, darkMode: boolean,
    fit: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const variant = darkMode ? record.parts.dark : record.parts.light;
      if (!variant || variant.reader.backgroundMode !== 'image') throw new Error('请先上传整图背景');
      variant.reader.imageFit = fit === 'contain' || fit === 'fill' ? fit : 'cover';
    });
  }

  /** 朗读面板三种颜色；空串表示不改那一项。只有已经上传了这个模式的插画时才能调。 */
  static async setTtsColors(context: Context, schemeId: string, darkMode: boolean, skyColor: string,
    surfaceColor: string, glowColor: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const panel = darkMode ? record.parts.ttsPanelDark : record.parts.ttsPanelLight;
      if (!panel) throw new Error('请先上传面板插画');
      if (skyColor) panel.skyColor = skyColor;
      if (surfaceColor) panel.surfaceColor = surfaceColor;
      if (glowColor) panel.glowColor = glowColor;
    });
  }

  static async clearTtsMode(context: Context, schemeId: string, darkMode: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      if (darkMode) record.parts.ttsPanelDark = null;
      else record.parts.ttsPanelLight = null;
    });
  }

  static async clearBubbleFrame(context: Context, schemeId: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      if (record.parts.bubble) record.parts.bubble.frame = '';
    });
  }

  /** 主题标识：主题卡片角标和详情页名字旁的小图。 */
  static async setLogo(context: Context, schemeId: string, uri: string, baseTheme: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      record.parts.logo = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.ARTWORK,
        '主题标识');
    });
  }

  static async clearLogo(context: Context, schemeId: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      record.parts.logo = '';
    });
  }

  /**
   * “另一种模式也用这张”：把当前模式的阅读背景素材、朗读面板或首页背景复制到另一种模式。
   * kind：reader / ttsPanel / homeBackdrop。
   */
  static async copyToOtherMode(context: Context, schemeId: string, kind: string,
    fromDark: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const parts = record.parts;
      if (kind === 'reader') {
        const source = fromDark ? parts.dark : parts.light;
        if (!source) throw new Error('这个模式还没有阅读背景素材');
        const copy = JSON.parse(JSON.stringify(source)) as ThemePackageVariantParts;
        if (fromDark) parts.light = copy;
        else parts.dark = copy;
      } else if (kind === 'ttsPanel') {
        const source = fromDark ? parts.ttsPanelDark : parts.ttsPanelLight;
        if (!source) throw new Error('这个模式还没有面板插画');
        const copy = JSON.parse(JSON.stringify(source)) as ThemePackageTtsPanel;
        if (fromDark) parts.ttsPanelLight = copy;
        else parts.ttsPanelDark = copy;
      } else {
        const source = fromDark ? parts.homeBackdropDark : parts.homeBackdropLight;
        if (!source) throw new Error('这个模式还没有首页背景');
        if (fromDark) parts.homeBackdropLight = source;
        else parts.homeBackdropDark = source;
      }
    });
  }

  /**
   * 复制方案：设置照搬；方案有自己的素材包时复制成新包，设置里指向旧包的来源一并改过去；
   * 本机的启动封面与预览图复制一份；阅读排版档案（含绑定标记）也复制。超出额度返回 null。
   */
  static async duplicateScheme(context: Context, schemeId: string): Promise<CustomThemeScheme | null> {
    const appSettings = await AppThemeSettingsStore.load(context);
    const schemes = await CustomThemeSchemeStore.load(context, appSettings);
    const scheme = CustomThemeSchemeStore.find(schemes, schemeId);
    if (!scheme) throw new Error('方案不存在');
    if (schemes.length >= CustomThemeQuota.current()) return null;
    let settings = AppThemeSettingsStore.cloneSettings(scheme.settings);
    let packageId = '';
    const ownPackageId = SchemeAssetService.packageIdOf(scheme);
    if (ownPackageId) {
      packageId = `custom-${SchemeAssetService.randomHex(8)}`;
      if (!ThemePackStore.copyPack(context, ownPackageId, packageId)) throw new Error('复制方案素材失败');
      const pattern = new RegExp(`pack:${ownPackageId.replace(/[.\-]/g, '\\$&')}(?=[":])`, 'g');
      settings = AppThemeSettingsStore.cloneSettings(
        JSON.parse(JSON.stringify(settings).replace(pattern, `pack:${packageId}`)) as AppThemeSettings);
    }
    settings.customLightStartupImagePath = SchemeAssetService.copyLocalImage(context, settings.customLightStartupImagePath);
    settings.customDarkStartupImagePath = settings.customDarkStartupImagePath === scheme.settings.customLightStartupImagePath ?
      settings.customLightStartupImagePath : SchemeAssetService.copyLocalImage(context, settings.customDarkStartupImagePath);
    settings.customPreviewImagePath = SchemeAssetService.copyLocalImage(context, settings.customPreviewImagePath);
    const added = await CustomThemeSchemeStore.addWith(context, appSettings, `${scheme.name} 副本`, settings,
      scheme.author, packageId, scheme.description);
    if (!added) {
      if (packageId) ThemePackStore.uninstall(context, packageId);
      return null;
    }
    try {
      const fromProfile = ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, scheme.id);
      const toProfile = ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, added.id);
      await ReaderSettingsStore.writeProfile(context, toProfile, await ReaderSettingsStore.loadProfile(context, fromProfile));
    } catch (e) {
      console.warn('复制方案排版失败:', (e as Error).message);
    }
    return added;
  }

  /** 方案引用的本机图片（启动封面、预览图）复制一份，复制出的方案删改时互不影响。 */
  private static copyLocalImage(context: Context, uri: string): string {
    if (!uri || !uri.startsWith('file://')) return uri;
    try {
      const path = new fileUri.FileUri(uri).path;
      if (!path.startsWith(`${context.filesDir}/`) || !fs.accessSync(path)) return '';
      const dot = path.lastIndexOf('.');
      const target = `${dot > path.lastIndexOf('/') ? path.substring(0, dot) : path}_copy${Date.now()}` +
        `${dot > path.lastIndexOf('/') ? path.substring(dot) : ''}`;
      fs.copyFileSync(path, target);
      return fileUri.getUriFromPath(target);
    } catch (_) {
      return '';
    }
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
      parts.book || parts.startupLight || parts.startupDark || parts.bubble || parts.homeBackdropLight ||
      parts.homeBackdropDark || parts.logo || parts.preview ||
      parts.radius || parts.appFont || parts.appFontFamily);
  }

  static fileName(uri: string): string {
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

  static hasHomeBackdrop(packageId: string, darkMode: boolean): boolean {
    const pack = ThemePackRegistry.getByPackageId(packageId);
    return !!pack && !!pack.homeBackdrop(darkMode);
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
