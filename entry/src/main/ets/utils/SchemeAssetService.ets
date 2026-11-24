import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { fileUri } from '../platform/FileUri';
import picker from '@ohos.file.picker';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { ReaderInheritedCopies, ThemePackRegistry, ThemePackRecord } from '../theme/ThemePackRegistry';
import { ThemeIds } from '../theme/ThemeModels';
import {
  bookIsEmpty,
  COMMENT_IMAGE_NONE,
  commentBubbleIsEmpty,
  CommentImageBreak,
  CommentImageRepeat,
  copyCommentImage,
  normalizeCommentBubble,
  ThemePackageCommentBubble,
  findShelfBackdrop,
  isPackThemeId,
  NAVIGATION_ICON_KEYS,
  normalizeOrnamentInset,
  normalizeOrnamentScale,
  normalizeShelfBackdropLayout,
  packThemeId,
  SHELF_BACKDROP_LAYOUTS,
  ThemeImageCrop,
  ThemePackageAssetKinds,
  ThemePackageBook,
  ThemePackageBubble,
  ThemePackageBubbleSlice,
  BubbleFrameBreak,
  BubbleFrameRepeat,
  normalizeBubbleFrameSlice,
  ThemePackageLimits,
  ThemePackageNavigation,
  ThemePackageShelfBackdrop,
  ThemePackageTtsPanel,
  ThemePackagePartReader,
  ThemePackageVariantParts,
  tidyImageCrops
} from '../theme/share/ThemePackageFormat';
import {
  chapterHeadFor,
  chapterHeadIsEmpty,
  normalizeChapterHead,
  ThemePackageChapterHead
} from '../theme/share/ThemePackageFormat';
import { AppThemeSettings, AppThemeSettingsStore } from './AppThemeSettingsStore';
import { ReaderCustomFontData, ReaderCustomFontItem } from '../core/reader/ReaderSettingsModels';
import { ReaderFontHelper } from './ReaderFontHelper';
import { CustomThemeScheme, CustomThemeSchemeStore } from './CustomThemeSchemeStore';
import { ThemePackStore } from './ThemePackStore';
import { CustomThemeQuota } from '../account/CustomThemeQuota';
import { ReaderSettingsStore } from './ReaderSettingsStore';
import { selectDocuments, selectImages } from '../platform/Files';

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
 * 某个阅读背景素材键（内置背景或主题包 pack:<id>:light/dark）这一模式的整图与角饰，编辑器用 ThemeAssetRegistry 取好后
 * 交给素材服务拷进方案自己的包。内置素材是资源，主题包素材是本机 file:// 地址；空串表示没有这一项。
 */
export class ReaderSourceItems {
  assetId: string = '';
  leading: ResourceStr = '';
  trailing: ResourceStr = '';
  image: ResourceStr = '';
  imageFit: string = 'cover';
  leadingScale: number = 1;
  trailingScale: number = 1;
  leadingInset: number = 1;
  trailingInset: number = 1;

  itemOf(slot: string): ResourceStr {
    if (slot === 'image') return this.image;
    return slot === 'trailing' ? this.trailing : this.leading;
  }

  has(slot: string): boolean {
    const item = this.itemOf(slot);
    return typeof item !== 'string' || item.length > 0;
  }
}

const READER_SLOTS: string[] = ['leading', 'trailing', 'image'];

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
    const photoUris = await selectImages(context, max);
    return photoUris.slice(0, max);
  }

  /**
   * 所有“SVG 或位图”的素材位（导航图标、主题标识、气泡端饰与边框、书架边框、阅读角饰、朗读面板插画）共用的
   * 文件选择器，后缀与包格式认得的素材一致。SVG 在导航图标上跟主题色着色，位图一律保持原色。
   */
  static async pickArtworkFiles(context: Context, max: number): Promise<string[]> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = max;
    options.fileSuffixFilters = ['图片|.svg,.png,.webp,.jpg,.jpeg,.gif,.bmp'];
    const result = await selectDocuments(context, options);
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

  /**
   * crops 与 uris 一一对应：动图取景记下的显示区域，没有时为 null。
   * dark 为 true 时加进深色模式单独的那套封面（没有这套时深色沿用浅色的）。
   */
  static async addCovers(context: Context, schemeId: string, uris: string[], baseTheme: string,
    crops: Array<ThemeImageCrop | null> = [], dark: boolean = false): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const book = record.parts.book || new ThemePackageBook();
      const covers = SchemeAssetService.coverList(book, dark);
      for (let index = 0; index < uris.length; index++) {
        if (covers.length >= ThemePackageLimits.MAX_COVERS) break;
        const path = await ThemePackStore.importAsset(context, record.packageId, uris[index], SchemeAssetService.IMAGE, '封面');
        if (!covers.includes(path)) covers.push(path);
        SchemeAssetService.setCoverCrop(book, path, index < crops.length ? crops[index] : null, dark);
      }
      record.parts.book = book;
    });
  }

  /** 浅色（也是默认）或深色那套封面的列表本身；本机旧记录里没有深色字段，补上。 */
  private static coverList(book: ThemePackageBook, dark: boolean): string[] {
    if (!dark) return book.covers;
    if (!Array.isArray(book.coversDark)) book.coversDark = [];
    return book.coversDark;
  }

  /** 把显示区域挂到 image 这张素材上；crop 为 null 时返回 null（显示整张图）。 */
  private static attachCrop(crop: ThemeImageCrop | null, image: string): ThemeImageCrop | null {
    if (!crop || !image) return null;
    const attached = new ThemeImageCrop();
    attached.image = image;
    attached.x = crop.x;
    attached.y = crop.y;
    attached.width = crop.width;
    attached.height = crop.height;
    attached.imageWidth = crop.imageWidth;
    attached.imageHeight = crop.imageHeight;
    return attached;
  }

  private static setCoverCrop(book: ThemePackageBook, image: string, crop: ThemeImageCrop | null,
    dark: boolean = false): void {
    const crops = ((dark ? book.coverCropsDark : book.coverCrops) || [])
      .filter((item: ThemeImageCrop): boolean => item.image !== image);
    const attached = SchemeAssetService.attachCrop(crop, image);
    if (attached) crops.push(attached);
    if (dark) book.coverCropsDark = crops;
    else book.coverCrops = crops;
  }

  /** dark 为 true 时设的是深色模式单独的那张（没有时深色沿用浅色的）。 */
  static async setShelfFrame(context: Context, schemeId: string, uri: string, baseTheme: string,
    dark: boolean = false): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const book = record.parts.book || new ThemePackageBook();
      const path = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.ARTWORK, '书架边框');
      if (dark) {
        book.shelfFrameDark = path;
        book.noShelfFrameDark = false;
      } else {
        book.shelfFrame = path;
        book.noShelfFrame = false;
      }
      record.parts.book = book;
    });
  }

  /** dark 为 true 时设的是深色模式单独的那张（没有时深色沿用浅色的）。 */
  static async setShelfFolder(context: Context, schemeId: string, uri: string, baseTheme: string,
    crop: ThemeImageCrop | null = null, dark: boolean = false): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const book = record.parts.book || new ThemePackageBook();
      const path = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.IMAGE, '文件夹插画');
      if (dark) {
        book.shelfFolderDark = path;
        book.shelfFolderCropDark = SchemeAssetService.attachCrop(crop, path);
        book.noShelfFolderDark = false;
      } else {
        book.shelfFolder = path;
        book.shelfFolderCrop = SchemeAssetService.attachCrop(crop, path);
        book.noShelfFolder = false;
      }
      record.parts.book = book;
    });
  }

  /**
   * 阅读背景角饰：左上、右下各一张图（SVG 或位图），可以只传其中一张，另一角就空着。
   * 两张记成同一个素材表示右下角用左上角那张旋转 180°（setReaderTrailingMirror）。
   * 已有整图时角饰叠在整图上面，模式仍记 image。
   */
  static async setReaderOrnament(context: Context, schemeId: string, uri: string, trailing: boolean,
    darkMode: boolean, baseTheme: string, seed: ReaderSourceItems | null = null): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const variant = SchemeAssetService.variantOf(record, darkMode);
      const path = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.ARTWORK,
        trailing ? '右下角饰' : '左上角饰');
      const slot = trailing ? 'trailing' : 'leading';
      if (seed) await SchemeAssetService.seedReader(context, record, variant, darkMode, seed, slot);
      SchemeAssetService.forgetInherited(record, darkMode, slot);
      const mode = variant.reader.backgroundMode;
      if (mode !== 'ornaments' && mode !== 'image') {
        variant.reader.leading = '';
        variant.reader.trailing = '';
      }
      if (trailing) {
        variant.reader.trailing = path;
      } else {
        // 右下角原本是左上角那张旋转的，换左上角时跟着换。
        const mirrored = !!variant.reader.trailing && variant.reader.trailing === variant.reader.leading;
        variant.reader.leading = path;
        if (mirrored) variant.reader.trailing = path;
      }
      if (mode !== 'image') {
        variant.reader.image = '';
        variant.reader.backgroundMode = 'ornaments';
      }
      SchemeAssetService.storeVariant(record, darkMode, variant);
    });
  }

  /** 右下角改用左上角那张旋转 180°。 */
  static async setReaderTrailingMirror(context: Context, schemeId: string, darkMode: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const variant = darkMode ? record.parts.dark : record.parts.light;
      if (!variant || !SchemeAssetService.readerAllowsOrnaments(variant) || !variant.reader.leading) {
        throw new Error('请先上传左上角饰');
      }
      variant.reader.trailing = variant.reader.leading;
      SchemeAssetService.forgetInherited(record, darkMode, 'trailing');
    });
  }

  /** 左上（trailing 为 false）或右下角饰的显示大小倍数（0.5–2）。 */
  static async setReaderOrnamentScale(context: Context, schemeId: string, darkMode: boolean, trailing: boolean,
    scale: number): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const variant = darkMode ? record.parts.dark : record.parts.light;
      if (!variant || !SchemeAssetService.readerAllowsOrnaments(variant)) throw new Error('请先上传角饰');
      if (trailing) variant.reader.trailingScale = normalizeOrnamentScale(scale);
      else variant.reader.leadingScale = normalizeOrnamentScale(scale);
    });
  }

  /** 左上（trailing 为 false）或右下角饰离屏幕边缘的边距倍数（0–3，0 是贴边）。 */
  static async setReaderOrnamentInset(context: Context, schemeId: string, darkMode: boolean, trailing: boolean,
    inset: number): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const variant = darkMode ? record.parts.dark : record.parts.light;
      if (!variant || !SchemeAssetService.readerAllowsOrnaments(variant)) throw new Error('请先上传角饰');
      if (trailing) variant.reader.trailingInset = normalizeOrnamentInset(inset);
      else variant.reader.leadingInset = normalizeOrnamentInset(inset);
    });
  }

  /** 角饰模式和整图模式都可以带角饰（整图模式下角饰叠在整图上）。 */
  private static readerAllowsOrnaments(variant: ThemePackageVariantParts): boolean {
    const mode = variant.reader.backgroundMode;
    return mode === 'ornaments' || mode === 'image';
  }

  /** 阅读背景整图：铺满（cover）。已有的角饰保留，叠在整图上面。 */
  static async setReaderImage(context: Context, schemeId: string, uri: string, darkMode: boolean,
    baseTheme: string, seed: ReaderSourceItems | null = null): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const variant = SchemeAssetService.variantOf(record, darkMode);
      const image = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.IMAGE, '阅读背景');
      if (seed) await SchemeAssetService.seedReader(context, record, variant, darkMode, seed, 'image');
      SchemeAssetService.forgetInherited(record, darkMode, 'image');
      variant.reader.image = image;
      const mode = variant.reader.backgroundMode;
      if (mode !== 'ornaments' && mode !== 'image') {
        variant.reader.leading = '';
        variant.reader.trailing = '';
      }
      variant.reader.imageFit = 'cover';
      variant.reader.backgroundMode = 'image';
      SchemeAssetService.storeVariant(record, darkMode, variant);
    });
  }

  static async clearReader(context: Context, schemeId: string, darkMode: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      SchemeAssetService.storeVariant(record, darkMode, null);
      SchemeAssetService.setInherited(record, darkMode, null);
    });
  }

  /**
   * 阅读背景的某一格选“不用”。seed 不为空表示这个模式还在跟随别的背景素材：先把那套里其余的整图、角饰拷进方案
   * 自己的包（记成拷来的），再去掉这一格；否则直接去掉方案包里的这一格。一格都不剩时变体里的阅读背景清空，
   * 编辑器把背景素材键置空，阅读页只画底色。
   */
  static async setReaderSlotOff(context: Context, schemeId: string, darkMode: boolean, slot: string,
    seed: ReaderSourceItems | null, baseTheme: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const variant = SchemeAssetService.variantOf(record, darkMode);
      if (seed) await SchemeAssetService.seedReader(context, record, variant, darkMode, seed, slot);
      else SchemeAssetService.removeReaderSlot(variant.reader, slot);
      SchemeAssetService.forgetInherited(record, darkMode, slot);
      SchemeAssetService.storeReaderVariant(record, darkMode, variant);
    });
  }

  /**
   * “不用”的那一格恢复跟随：把 follow（“取自”主题这一模式的背景素材）里的这一项拷进方案自己的包。
   * seed 不为空时这个模式当前不在用方案包（比如全都选了“不用”），先按 seed 重置方案包里的阅读背景。
   */
  static async restoreReaderSlot(context: Context, schemeId: string, darkMode: boolean, slot: string,
    follow: ReaderSourceItems, seed: ReaderSourceItems | null, baseTheme: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      if (!follow.has(slot)) throw new Error('所选主题没有这一项');
      const variant = SchemeAssetService.variantOf(record, darkMode);
      if (seed) await SchemeAssetService.seedReader(context, record, variant, darkMode, seed, '');
      const copies = SchemeAssetService.inheritedOf(record, darkMode, follow.assetId);
      await SchemeAssetService.copyReaderSlot(context, record.packageId, variant.reader, follow, slot, copies);
      SchemeAssetService.setInherited(record, darkMode, copies);
      SchemeAssetService.storeReaderVariant(record, darkMode, variant);
    });
  }

  /** 重置变体里的阅读背景，再把 seed 里除 skipSlot 以外的整图、角饰拷进来（记成拷来的）。 */
  private static async seedReader(context: Context, record: ThemePackRecord, variant: ThemePackageVariantParts,
    darkMode: boolean, seed: ReaderSourceItems, skipSlot: string): Promise<void> {
    const reader = variant.reader;
    reader.backgroundMode = '';
    reader.leading = '';
    reader.trailing = '';
    reader.image = '';
    reader.imageFit = 'cover';
    reader.leadingScale = 1;
    reader.trailingScale = 1;
    reader.leadingInset = 1;
    reader.trailingInset = 1;
    const copies = SchemeAssetService.newInherited(seed.assetId);
    // 右下角是左上角那张旋转出来的：跳过左上角时一起跳过，单拷右下会变成没旋转的左上角图。
    const mirrored = SchemeAssetService.sameItem(seed.leading, seed.trailing);
    for (const slot of READER_SLOTS) {
      if (slot === 'trailing' && skipSlot === 'leading' && mirrored) continue;
      if (slot !== skipSlot && seed.has(slot)) {
        await SchemeAssetService.copyReaderSlot(context, record.packageId, reader, seed, slot, copies);
      }
    }
    SchemeAssetService.fixReaderMode(reader);
    SchemeAssetService.setInherited(record, darkMode, copies);
  }

  private static async copyReaderSlot(context: Context, packageId: string, reader: ThemePackagePartReader,
    source: ReaderSourceItems, slot: string, copies: ReaderInheritedCopies): Promise<void> {
    let path = '';
    if (slot === 'image') {
      path = await SchemeAssetService.importResource(context, packageId, source.image, SchemeAssetService.IMAGE,
        '阅读背景');
      reader.image = path;
      reader.imageFit = source.imageFit || 'cover';
    } else if (slot === 'trailing') {
      path = await SchemeAssetService.importResource(context, packageId, source.trailing,
        SchemeAssetService.ARTWORK, '右下角饰');
      reader.trailing = path;
      reader.trailingScale = normalizeOrnamentScale(source.trailingScale);
      reader.trailingInset = normalizeOrnamentInset(source.trailingInset);
    } else {
      path = await SchemeAssetService.importResource(context, packageId, source.leading,
        SchemeAssetService.ARTWORK, '左上角饰');
      reader.leading = path;
      reader.leadingScale = normalizeOrnamentScale(source.leadingScale);
      reader.leadingInset = normalizeOrnamentInset(source.leadingInset);
    }
    copies.setPath(slot, path);
    SchemeAssetService.fixReaderMode(reader);
  }

  /** 内置资源先写成临时文件，主题包素材（file:// 地址）换成路径，再按上传同样的规则收进包里。 */
  private static async importResource(context: Context, packageId: string, item: ResourceStr, kinds: string[],
    label: string): Promise<string> {
    if (typeof item === 'string') {
      if (!item) return '';
      const path = item.startsWith('file://') ? new fileUri.FileUri(item).path : item;
      return ThemePackStore.importAsset(context, packageId, path, kinds, label);
    }
    const bytes: Uint8Array = await context.resourceManager.getMediaContent((item as Resource).id);
    const temp = `${context.tempDir}/reader_source_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
    const file = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
    } finally {
      fs.closeSync(file);
    }
    try {
      return await ThemePackStore.importAsset(context, packageId, temp, kinds, label);
    } finally {
      try {
        fs.unlinkSync(temp);
      } catch (_) {
      }
    }
  }

  private static sameItem(a: ResourceStr, b: ResourceStr): boolean {
    if (typeof a === 'string' || typeof b === 'string') return typeof a === typeof b && !!a && a === b;
    return (a as Resource).id === (b as Resource).id;
  }

  /** 去掉一格；左上角饰去掉时，用它旋转出来的右下角饰一起去掉。 */
  private static removeReaderSlot(reader: ThemePackagePartReader, slot: string): void {
    if (slot === 'image') {
      reader.image = '';
      reader.imageFit = 'cover';
    } else if (slot === 'trailing') {
      reader.trailing = '';
    } else {
      if (reader.trailing && reader.trailing === reader.leading) reader.trailing = '';
      reader.leading = '';
    }
    SchemeAssetService.fixReaderMode(reader);
  }

  private static fixReaderMode(reader: ThemePackagePartReader): void {
    if (reader.image) reader.backgroundMode = 'image';
    else if (reader.leading || reader.trailing) reader.backgroundMode = 'ornaments';
    else reader.backgroundMode = '';
  }

  /** 阅读背景一格不剩时变体只留下段评、章首装饰（都没有就整个清掉），拷来记录一并清掉。 */
  private static storeReaderVariant(record: ThemePackRecord, darkMode: boolean,
    variant: ThemePackageVariantParts): void {
    if (darkMode) record.parts.dark = variant;
    else record.parts.light = variant;
    if (variant.reader.backgroundMode) return;
    SchemeAssetService.storeVariant(record, darkMode, null);
    SchemeAssetService.setInherited(record, darkMode, null);
  }

  /** 已有记录且拷自同一套素材时沿用，否则新起一份。 */
  private static inheritedOf(record: ThemePackRecord, darkMode: boolean, sourceAssetId: string): ReaderInheritedCopies {
    const existing = ReaderInheritedCopies.normalize(darkMode ? record.readerInheritedDark : record.readerInheritedLight);
    return existing && existing.sourceAssetId === sourceAssetId ? existing :
      SchemeAssetService.newInherited(sourceAssetId);
  }

  private static newInherited(sourceAssetId: string): ReaderInheritedCopies {
    const copies = new ReaderInheritedCopies();
    copies.sourceAssetId = sourceAssetId;
    return copies;
  }

  private static setInherited(record: ThemePackRecord, darkMode: boolean, copies: ReaderInheritedCopies | null): void {
    const value = copies && (copies.leading || copies.trailing || copies.image) ? copies : null;
    if (darkMode) record.readerInheritedDark = value;
    else record.readerInheritedLight = value;
  }

  /** 这一格换成了自己传的图或去掉了：不再算拷来的。 */
  private static forgetInherited(record: ThemePackRecord, darkMode: boolean, slot: string): void {
    const existing = ReaderInheritedCopies.normalize(darkMode ? record.readerInheritedDark : record.readerInheritedLight);
    if (!existing) return;
    // 左上角饰去掉或换掉时，用它旋转出来的右下角也跟着变了。
    if (slot === 'leading' && existing.trailing && existing.trailing === existing.leading) existing.trailing = '';
    existing.setPath(slot, '');
    SchemeAssetService.setInherited(record, darkMode, existing);
  }

  private static variantOf(record: ThemePackRecord, darkMode: boolean): ThemePackageVariantParts {
    const existing = darkMode ? record.parts.dark : record.parts.light;
    if (existing) return existing;
    return new ThemePackageVariantParts();
  }

  /**
   * 编辑器往变体里写阅读背景、段评气泡素材和章首装饰：清掉背景时变体只留下段评和章首装饰两节
   * （都没有就整个清掉）。
   */
  private static storeVariant(record: ThemePackRecord, darkMode: boolean,
    variant: ThemePackageVariantParts | null): void {
    const existing = darkMode ? record.parts.dark : record.parts.light;
    let value = variant;
    if (!value && existing) {
      const keepComment = !!existing.commentBubble && !commentBubbleIsEmpty(existing.commentBubble);
      const keepHead = !chapterHeadIsEmpty(existing.chapterHead);
      if (keepComment || keepHead) {
        value = new ThemePackageVariantParts();
        if (keepComment) value.commentBubble = existing.commentBubble;
        if (keepHead) value.chapterHead = existing.chapterHead;
      }
    }
    if (darkMode) record.parts.dark = value;
    else record.parts.light = value;
  }

  // ---- 段评气泡图与角标图：写在素材包这个模式的 commentBubble 里，方案覆盖用 pack:<id> 指过来 ----

  /** 上传段评气泡图，连同拉伸页里定好的文字区、拉伸线和换行方式一起存。 */
  static async setCommentImage(context: Context, schemeId: string, uri: string, baseTheme: string,
    settings: ThemePackageCommentBubble, dark: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const comment = SchemeAssetService.commentOf(record, dark);
      comment.image = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.ARTWORK,
        '段评气泡图');
      SchemeAssetService.copyCommentImageSettings(comment, settings);
      SchemeAssetService.storeComment(record, dark, comment);
    });
  }

  /**
   * 只改气泡图的拉伸设置、平铺与染色。这个模式没有自己的图（沿用另一模式那张）时，先把那张记到这个模式，
   * 这样改动只影响这个模式。
   */
  static async setCommentImageSettings(context: Context, schemeId: string, settings: ThemePackageCommentBubble,
    dark: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const comment = SchemeAssetService.commentOf(record, dark);
      if (!comment.image || comment.image === COMMENT_IMAGE_NONE) {
        const other = SchemeAssetService.commentOf(record, !dark);
        if (!other.image || other.image === COMMENT_IMAGE_NONE) throw new Error('段评气泡图已不存在');
        copyCommentImage(comment, other);
      }
      SchemeAssetService.copyCommentImageSettings(comment, settings);
      SchemeAssetService.storeComment(record, dark, comment);
    });
  }

  /** 移除这个模式自己的气泡图（另一模式的不动）。 */
  static async clearCommentImage(context: Context, schemeId: string, dark: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const comment = SchemeAssetService.commentOf(record, dark);
      copyCommentImage(comment, new ThemePackageCommentBubble());
      SchemeAssetService.storeComment(record, dark, comment);
    });
  }

  /** “另一模式也用这张”：气泡图与拉伸设置照抄到另一种模式（同一个素材文件）。 */
  static async copyCommentImageToOtherMode(context: Context, schemeId: string,
    fromDark: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const source = SchemeAssetService.commentOf(record, fromDark);
      if (!source.image || source.image === COMMENT_IMAGE_NONE) throw new Error('这个模式还没有气泡图');
      const target = SchemeAssetService.commentOf(record, !fromDark);
      copyCommentImage(target, source);
      SchemeAssetService.storeComment(record, !fromDark, target);
    });
  }

  static async setCommentOrnament(context: Context, schemeId: string, uri: string, baseTheme: string,
    dark: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const comment = SchemeAssetService.commentOf(record, dark);
      comment.ornamentImage = await ThemePackStore.importAsset(context, record.packageId, uri,
        SchemeAssetService.ARTWORK, '段评角标图');
      comment.ornament = 'custom';
      SchemeAssetService.storeComment(record, dark, comment);
    });
  }

  static async clearCommentOrnament(context: Context, schemeId: string, dark: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const comment = SchemeAssetService.commentOf(record, dark);
      comment.ornamentImage = '';
      if (comment.ornament === 'custom') comment.ornament = '';
      SchemeAssetService.storeComment(record, dark, comment);
    });
  }

  static async copyCommentOrnamentToOtherMode(context: Context, schemeId: string,
    fromDark: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const source = SchemeAssetService.commentOf(record, fromDark);
      if (!source.ornamentImage) throw new Error('这个模式还没有角标图');
      const target = SchemeAssetService.commentOf(record, !fromDark);
      target.ornamentImage = source.ornamentImage;
      target.ornament = 'custom';
      SchemeAssetService.storeComment(record, !fromDark, target);
    });
  }

  /** 这个模式自己的段评设置（不含另一模式沿用过来的）。 */
  private static commentOf(record: ThemePackRecord, dark: boolean): ThemePackageCommentBubble {
    const variant = dark ? record.parts.dark : record.parts.light;
    return normalizeCommentBubble(variant ? variant.commentBubble : null);
  }

  /** 段评空了而变体里也没有别的东西时整个变体清掉。 */
  private static storeComment(record: ThemePackRecord, dark: boolean, comment: ThemePackageCommentBubble): void {
    const existing = dark ? record.parts.dark : record.parts.light;
    const empty = commentBubbleIsEmpty(comment);
    if (!existing) {
      if (empty) return;
      const variant = new ThemePackageVariantParts();
      variant.commentBubble = normalizeCommentBubble(comment);
      if (dark) record.parts.dark = variant;
      else record.parts.light = variant;
      return;
    }
    existing.commentBubble = empty ? null : normalizeCommentBubble(comment);
    if (empty && SchemeAssetService.variantHasNothingElse(existing)) {
      if (dark) record.parts.dark = null;
      else record.parts.light = null;
    }
  }

  private static variantHasNothingElse(variant: ThemePackageVariantParts): boolean {
    if (!chapterHeadIsEmpty(variant.chapterHead)) return false;
    const colors = variant.colors;
    if (colors.pageColor || colors.cardColor || colors.inputColor || colors.primaryTextColor || colors.subTextColor ||
      colors.dividerColor || colors.accentColor || colors.buttonColor || colors.dangerColor) return false;
    const reader = variant.reader;
    if (reader.backgroundMode || reader.backgroundColor || reader.textColor || reader.subTextColor ||
      reader.contentTone || reader.leading || reader.trailing || reader.image) return false;
    const emphasis = variant.emphasis;
    return !(emphasis.mode || emphasis.bubbleStyle || emphasis.color || emphasis.textColor);
  }

  // ---- 章首装饰：写在素材包这个模式的 chapterHead 里，方案覆盖用 pack:<id> 指过来 ----

  /** 上传标题饰图。这个模式原来沿用另一模式那张时，位置和大小接着用那张的。 */
  static async setChapterHeadImage(context: Context, schemeId: string, uri: string, baseTheme: string,
    dark: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const head = SchemeAssetService.chapterHeadOf(record, dark);
      if (!head.image) {
        const other = SchemeAssetService.chapterHeadOf(record, !dark);
        if (other.image) {
          head.placement = other.placement;
          head.scale = other.scale;
        }
      }
      head.image = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.ARTWORK,
        '标题饰图');
      SchemeAssetService.storeChapterHead(record, dark, head);
    });
  }

  /**
   * 改饰图的位置和大小。这个模式没有自己的图（沿用另一模式那张）时，先把那张记到这个模式，
   * 这样改动只影响这个模式。
   */
  static async setChapterHeadLayout(context: Context, schemeId: string, dark: boolean, placement: string,
    scale: number): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const head = SchemeAssetService.chapterHeadOf(record, dark);
      if (!head.image) {
        const other = SchemeAssetService.chapterHeadOf(record, !dark);
        if (!other.image) throw new Error('标题饰图已不存在');
        head.image = other.image;
      }
      head.placement = placement;
      head.scale = scale;
      SchemeAssetService.storeChapterHead(record, dark, head);
    });
  }

  /** 序号行颜色；空串改回和标题同色。 */
  static async setChapterHeadNumberColor(context: Context, schemeId: string, baseTheme: string, dark: boolean,
    color: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const head = SchemeAssetService.chapterHeadOf(record, dark);
      head.numberColor = color;
      SchemeAssetService.storeChapterHead(record, dark, head);
    });
  }

  /** 移除这个模式自己的标题饰图（另一模式的不动）。 */
  static async clearChapterHeadImage(context: Context, schemeId: string, dark: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const head = SchemeAssetService.chapterHeadOf(record, dark);
      head.image = '';
      head.placement = '';
      head.scale = 1;
      SchemeAssetService.storeChapterHead(record, dark, head);
    });
  }

  /**
   * 首字装饰占几行（0 不处理）、颜色和字占比。这个模式原来沿用另一模式的首字时，先把那套（印章图、字占比、
   * 颜色）记到这个模式，这样改动只影响这个模式；改成不处理时这个模式的印章图一并去掉。
   */
  static async setChapterHeadDropCap(context: Context, schemeId: string, baseTheme: string, dark: boolean,
    lines: number, color: string, ratio: number): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const head = SchemeAssetService.chapterHeadOf(record, dark);
      if (lines <= 0) {
        head.dropCapLines = 0;
        head.dropCapImage = '';
        head.dropCapColor = '';
      } else {
        if (head.dropCapLines === 0) {
          const other = SchemeAssetService.chapterHeadOf(record, !dark);
          if (other.dropCapLines > 0) head.dropCapImage = other.dropCapImage;
        }
        head.dropCapLines = lines === 3 ? 3 : 2;
        head.dropCapColor = color;
        head.dropCapRatio = ratio;
      }
      SchemeAssetService.storeChapterHead(record, dark, head);
    });
  }

  /** 上传首字印章图；还没开首字时按占 2 行打开。 */
  static async setChapterHeadDropCapImage(context: Context, schemeId: string, uri: string, baseTheme: string,
    dark: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const head = SchemeAssetService.chapterHeadOf(record, dark);
      if (head.dropCapLines === 0) {
        const other = SchemeAssetService.chapterHeadOf(record, !dark);
        head.dropCapLines = other.dropCapLines > 0 ? other.dropCapLines : 2;
        if (other.dropCapLines > 0) {
          head.dropCapRatio = other.dropCapRatio;
          if (!head.dropCapColor) head.dropCapColor = other.dropCapColor;
        }
      }
      head.dropCapImage = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.ARTWORK,
        '首字印章图');
      SchemeAssetService.storeChapterHead(record, dark, head);
    });
  }

  /** 移除这个模式的首字印章图，首字改成只放大。 */
  static async clearChapterHeadDropCapImage(context: Context, schemeId: string, dark: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const head = SchemeAssetService.chapterHeadOf(record, dark);
      if (head.dropCapLines === 0) {
        // 沿用另一模式那套时，先把行数记到这个模式，不然去掉图之后又沿用回那张。
        const other = SchemeAssetService.chapterHeadOf(record, !dark);
        head.dropCapLines = other.dropCapLines;
        head.dropCapColor = other.dropCapColor;
      }
      head.dropCapImage = '';
      SchemeAssetService.storeChapterHead(record, dark, head);
    });
  }

  /** 素材包这个模式实际用的章首装饰（饰图沿用另一模式的也算），素材是包内相对路径；没有时为 null。 */
  static chapterHead(packageId: string, dark: boolean): ThemePackageChapterHead | null {
    const pack = packageId ? ThemePackRegistry.getByPackageId(packageId) : null;
    return pack ? chapterHeadFor(pack.record.parts, dark) : null;
  }

  /** 这个模式自己有没有传标题饰图。 */
  static hasOwnChapterHeadImage(packageId: string, dark: boolean): boolean {
    const pack = packageId ? ThemePackRegistry.getByPackageId(packageId) : null;
    if (!pack) return false;
    return !!SchemeAssetService.chapterHeadOf(pack.record, dark).image;
  }

  /** 这个模式自己有没有传首字印章图。 */
  static hasOwnDropCapImage(packageId: string, dark: boolean): boolean {
    const pack = packageId ? ThemePackRegistry.getByPackageId(packageId) : null;
    if (!pack) return false;
    return !!SchemeAssetService.chapterHeadOf(pack.record, dark).dropCapImage;
  }

  /** 这个模式自己的章首装饰（不含另一模式沿用过来的）。 */
  private static chapterHeadOf(record: ThemePackRecord, dark: boolean): ThemePackageChapterHead {
    const variant = dark ? record.parts.dark : record.parts.light;
    return normalizeChapterHead(variant ? variant.chapterHead : null);
  }

  /** 章首装饰空了而变体里也没有别的东西时整个变体清掉。 */
  private static storeChapterHead(record: ThemePackRecord, dark: boolean, head: ThemePackageChapterHead): void {
    const existing = dark ? record.parts.dark : record.parts.light;
    const normalized = normalizeChapterHead(head);
    const empty = chapterHeadIsEmpty(normalized);
    if (!existing) {
      if (empty) return;
      const variant = new ThemePackageVariantParts();
      variant.chapterHead = normalized;
      if (dark) record.parts.dark = variant;
      else record.parts.light = variant;
      return;
    }
    existing.chapterHead = empty ? null : normalized;
    if (empty && SchemeAssetService.variantHasNothingElse(existing) &&
      (!existing.commentBubble || commentBubbleIsEmpty(existing.commentBubble))) {
      if (dark) record.parts.dark = null;
      else record.parts.light = null;
    }
  }

  private static copyCommentImageSettings(target: ThemePackageCommentBubble,
    settings: ThemePackageCommentBubble): void {
    target.imageSlice = settings.imageSlice ? JSON.parse(JSON.stringify(settings.imageSlice)) as ThemePackageBubbleSlice :
      null;
    target.imageText = settings.imageText ? JSON.parse(JSON.stringify(settings.imageText)) as ThemePackageBubbleSlice :
      null;
    target.imageRepeat = settings.imageRepeat === CommentImageRepeat.ROUND ? CommentImageRepeat.ROUND : '';
    target.imageBreak = settings.imageBreak === CommentImageBreak.FULL ? CommentImageBreak.FULL : '';
    target.imageTint = settings.imageTint === true;
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

  /**
   * 首页背景：浅色、深色各一张，互不借用。shelfLayout 给了书架布局（companion / tile / loose / compact）时，
   * 设的是那种布局专属的那张，只在书架页用这种布局时显示；不给就是各页签通用的那张。
   */
  static async setHomeBackdrop(context: Context, schemeId: string, uri: string, darkMode: boolean,
    baseTheme: string, crop: ThemeImageCrop | null = null, shelfLayout: string = ''): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const layout = normalizeShelfBackdropLayout(shelfLayout);
      const path = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.IMAGE,
        layout ? '书架背景' : '首页背景');
      SchemeAssetService.rememberHomeBackdropFallback(record, baseTheme, darkMode);
      if (layout) {
        const item = SchemeAssetService.shelfBackdropEntry(record, layout);
        if (darkMode) {
          item.dark = path;
          item.darkCrop = SchemeAssetService.attachCrop(crop, path);
        } else {
          item.light = path;
          item.lightCrop = SchemeAssetService.attachCrop(crop, path);
        }
      } else if (darkMode) {
        record.parts.homeBackdropDark = path;
        record.parts.homeBackdropDarkCrop = SchemeAssetService.attachCrop(crop, path);
      } else {
        record.parts.homeBackdropLight = path;
        record.parts.homeBackdropLightCrop = SchemeAssetService.attachCrop(crop, path);
      }
    });
  }

  /** 移除通用首页背景，或（给了 shelfLayout 时）某种书架布局专属的那张，后者移除后回到沿用通用背景。 */
  static async clearHomeBackdrop(context: Context, schemeId: string, darkMode: boolean,
    shelfLayout: string = ''): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const layout = normalizeShelfBackdropLayout(shelfLayout);
      if (layout) {
        // 两种模式都空了的条目由 tidyImageCrops 清掉。
        const item = findShelfBackdrop(record.parts.shelfBackdrops, layout);
        if (item && darkMode) {
          item.dark = '';
          item.darkCrop = null;
        } else if (item) {
          item.light = '';
          item.lightCrop = null;
        }
      } else if (darkMode) {
        record.parts.homeBackdropDark = '';
        record.parts.homeBackdropDarkCrop = null;
      } else {
        record.parts.homeBackdropLight = '';
        record.parts.homeBackdropLightCrop = null;
      }
    });
  }

  /** 把某种书架布局这个模式的专属背景（连同显示区域）也给其余三种布局用。 */
  static async copyShelfBackdropToOtherLayouts(context: Context, schemeId: string, shelfLayout: string,
    darkMode: boolean): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const source = findShelfBackdrop(record.parts.shelfBackdrops, normalizeShelfBackdropLayout(shelfLayout));
      const image = source ? (darkMode ? source.dark : source.light) : '';
      if (!source || !image) throw new Error('这种布局还没有单独的背景');
      const crop = darkMode ? source.darkCrop : source.lightCrop;
      for (const layout of SHELF_BACKDROP_LAYOUTS) {
        if (layout === source.layout) continue;
        const item = SchemeAssetService.shelfBackdropEntry(record, layout);
        if (darkMode) {
          item.dark = image;
          item.darkCrop = SchemeAssetService.attachCrop(crop, image);
        } else {
          item.light = image;
          item.lightCrop = SchemeAssetService.attachCrop(crop, image);
        }
      }
    });
  }

  private static shelfBackdropEntry(record: ThemePackRecord, layout: string): ThemePackageShelfBackdrop {
    if (!Array.isArray(record.parts.shelfBackdrops)) record.parts.shelfBackdrops = [];
    let item = findShelfBackdrop(record.parts.shelfBackdrops, layout);
    if (!item) {
      item = new ThemePackageShelfBackdrop();
      item.layout = layout;
      record.parts.shelfBackdrops.push(item);
    }
    return item;
  }

  /**
   * 上传背景时“首页背景”来源还是内置主题的话记下它：上传后来源改指方案自己的素材包，
   * 包里没有通用那张（只传了某种布局的）或以后把它移除时，通用背景接着用这套主题的，而不是突然没了。
   */
  private static rememberHomeBackdropFallback(record: ThemePackRecord, sourceThemeId: string, darkMode: boolean): void {
    if (!sourceThemeId || isPackThemeId(sourceThemeId)) return;
    const themeId = BuiltinThemeRegistry.normalizeBuiltinId(sourceThemeId);
    if (darkMode) record.homeBackdropFallbackDark = themeId;
    else record.homeBackdropFallbackLight = themeId;
  }

  /** dark 为 true 时写进深色模式单独的那套（parts.bubbleDark），没传的那一项深色沿用浅色的。 */
  static async setBubbleCap(context: Context, schemeId: string, uri: string, baseTheme: string,
    dark: boolean = false, title: boolean = false): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const bubble = SchemeAssetService.bubbleOf(record, dark, title) || new ThemePackageBubble();
      bubble.cap = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.ARTWORK, '气泡端饰');
      SchemeAssetService.storeBubble(record, dark, bubble, title);
    });
  }

  /** 上传边框并一起存下拉伸区域页里定好的拉伸设置。 */
  static async setBubbleFrame(context: Context, schemeId: string, uri: string, baseTheme: string,
    settings: ThemePackageBubble, dark: boolean = false, title: boolean = false): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, baseTheme, async (record: ThemePackRecord): Promise<void> => {
      const bubble = SchemeAssetService.bubbleOf(record, dark, title) || new ThemePackageBubble();
      bubble.frame = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.ARTWORK, '气泡边框');
      SchemeAssetService.copyFrameSettings(bubble, settings);
      SchemeAssetService.storeBubble(record, dark, bubble, title);
    });
  }

  /** 只改拉伸设置，边框素材不变。 */
  static async setBubbleFrameSettings(context: Context, schemeId: string,
    settings: ThemePackageBubble, dark: boolean = false, title: boolean = false): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const bubble = SchemeAssetService.bubbleOf(record, dark, title);
      if (!bubble || !bubble.frame) throw new Error('气泡边框已不存在');
      SchemeAssetService.copyFrameSettings(bubble, settings);
    });
  }

  /** title 为 true 时是标题气泡（parts.titleBubble / titleBubbleDark）。 */
  private static bubbleOf(record: ThemePackRecord, dark: boolean, title: boolean = false): ThemePackageBubble | null {
    if (title) return (dark ? record.parts.titleBubbleDark : record.parts.titleBubble) || null;
    return (dark ? record.parts.bubbleDark : record.parts.bubble) || null;
  }

  /** 端饰、边框都没有时整节记成 null。 */
  private static storeBubble(record: ThemePackRecord, dark: boolean, bubble: ThemePackageBubble | null,
    title: boolean = false): void {
    const value = bubble && (bubble.cap || bubble.frame) ? bubble : null;
    if (title) {
      if (dark) record.parts.titleBubbleDark = value;
      else record.parts.titleBubble = value;
      return;
    }
    if (dark) record.parts.bubbleDark = value;
    else record.parts.bubble = value;
  }

  /** 浅色、深色两套标题气泡一起清掉。 */
  static async clearTitleBubble(context: Context, schemeId: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      record.parts.titleBubble = null;
      record.parts.titleBubbleDark = null;
    });
  }

  static hasTitleBubble(packageId: string): boolean {
    const pack = ThemePackRegistry.getByPackageId(packageId);
    return !!pack && !!(pack.record.parts.titleBubble || pack.record.parts.titleBubbleDark);
  }

  private static copyFrameSettings(target: ThemePackageBubble, settings: ThemePackageBubble): void {
    target.frameSlice = normalizeBubbleFrameSlice(settings.frameSlice);
    target.frameRepeat = settings.frameRepeat === BubbleFrameRepeat.ROUND ? BubbleFrameRepeat.ROUND : '';
    target.frameBreak = settings.frameBreak === BubbleFrameBreak.CUT ? BubbleFrameBreak.CUT : '';
    target.frameTint = settings.frameTint === true;
  }

  /** 浅色、深色两套气泡素材一起清掉。 */
  static async clearBubble(context: Context, schemeId: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      record.parts.bubble = null;
      record.parts.bubbleDark = null;
    });
  }

  /** 移除端饰；边框还在时保留边框，否则整节清掉。dark 为 true 时只动深色那套，深色回到沿用浅色的端饰。 */
  static async clearBubbleCap(context: Context, schemeId: string, dark: boolean = false,
    title: boolean = false): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const bubble = SchemeAssetService.bubbleOf(record, dark, title);
      if (!bubble) return;
      bubble.cap = '';
      SchemeAssetService.storeBubble(record, dark, bubble, title);
    });
  }

  // ---- 逐个管理的素材 ----

  /** 替换第 index 张封面；dark 指深色那套。 */
  static async replaceCover(context: Context, schemeId: string, index: number, uri: string,
    crop: ThemeImageCrop | null = null, dark: boolean = false): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const book = record.parts.book;
      const covers = book ? SchemeAssetService.coverList(book, dark) : [];
      if (!book || index < 0 || index >= covers.length) throw new Error('这张封面已不存在');
      const path = await ThemePackStore.importAsset(context, record.packageId, uri, SchemeAssetService.IMAGE, '封面');
      if (covers.includes(path)) throw new Error('这张图已经在封面里了');
      covers[index] = path;
      SchemeAssetService.setCoverCrop(book, path, crop, dark);
    });
  }

  /** 删掉第 index 张封面；封面、边框、文件夹都没了时整节清掉。 */
  static async removeCover(context: Context, schemeId: string, index: number,
    dark: boolean = false): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const book = record.parts.book;
      const covers = book ? SchemeAssetService.coverList(book, dark) : [];
      if (!book || index < 0 || index >= covers.length) return;
      covers.splice(index, 1);
      SchemeAssetService.tidyBook(record);
    });
  }

  /** 调整轮播顺序：把 from 位置的封面挪到 to。 */
  static async moveCover(context: Context, schemeId: string, from: number, to: number,
    dark: boolean = false): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const book = record.parts.book;
      const covers = book ? SchemeAssetService.coverList(book, dark) : [];
      if (!book || from === to || from < 0 || to < 0 || from >= covers.length || to >= covers.length) return;
      const moved = covers.splice(from, 1)[0];
      covers.splice(to, 0, moved);
    });
  }

  /** 去掉深色那套封面，深色模式回到沿用浅色封面。 */
  static async clearDarkCovers(context: Context, schemeId: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const book = record.parts.book;
      if (!book) return;
      book.coversDark = [];
      book.coverCropsDark = [];
      SchemeAssetService.tidyBook(record);
    });
  }

  /** dark 为 true 时只去掉深色那张，深色回到沿用浅色的。 */
  static async clearShelfFrame(context: Context, schemeId: string, dark: boolean = false): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      if (record.parts.book && dark) record.parts.book.shelfFrameDark = '';
      else if (record.parts.book) record.parts.book.shelfFrame = '';
      SchemeAssetService.tidyBook(record);
    });
  }

  /** 移除文件夹插画；dark 为 true 时只去掉深色那张，深色回到沿用浅色的。 */
  static async clearShelfFolder(context: Context, schemeId: string, dark: boolean = false): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const book = record.parts.book;
      if (book && dark) {
        book.shelfFolderDark = '';
        book.shelfFolderCropDark = null;
      } else if (book) {
        book.shelfFolder = '';
        book.shelfFolderCrop = null;
      }
      SchemeAssetService.tidyBook(record);
    });
  }

  /**
   * 书架边框（folder 为 false）或文件夹插画选“不用”（off 为 true）或取消“不用”。选“不用”时去掉这个模式自己的图；
   * 取消后浅色回到跟随基底主题，深色回到沿用浅色。
   */
  static async setShelfPartOff(context: Context, schemeId: string, folder: boolean, dark: boolean, off: boolean,
    baseTheme: string): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, off ? baseTheme : '',
      async (record: ThemePackRecord): Promise<void> => {
        const book = record.parts.book || new ThemePackageBook();
        if (folder && dark) {
          if (off) {
            book.shelfFolderDark = '';
            book.shelfFolderCropDark = null;
          }
          book.noShelfFolderDark = off;
        } else if (folder) {
          if (off) {
            book.shelfFolder = '';
            book.shelfFolderCrop = null;
          }
          book.noShelfFolder = off;
        } else if (dark) {
          if (off) book.shelfFrameDark = '';
          book.noShelfFrameDark = off;
        } else {
          if (off) book.shelfFrame = '';
          book.noShelfFrame = off;
        }
        record.parts.book = book;
        SchemeAssetService.tidyBook(record);
      });
  }

  private static tidyBook(record: ThemePackRecord): void {
    const book = record.parts.book;
    if (book && bookIsEmpty(book)) record.parts.book = null;
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

  /** 移除边框和它的拉伸设置；端饰也没有时整节清掉。dark 为 true 时只动深色那套。 */
  static async clearBubbleFrame(context: Context, schemeId: string, dark: boolean = false,
    title: boolean = false): Promise<SchemeAssetResult> {
    return SchemeAssetService.update(context, schemeId, '', async (record: ThemePackRecord): Promise<void> => {
      const bubble = SchemeAssetService.bubbleOf(record, dark, title);
      if (!bubble) return;
      bubble.frame = '';
      bubble.frameSlice = null;
      bubble.frameRepeat = '';
      bubble.frameBreak = '';
      bubble.frameTint = false;
      SchemeAssetService.storeBubble(record, dark, bubble, title);
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
        // 段评气泡是浅深各自设置的，复制阅读背景时保留目标模式原有的那份。
        const target = fromDark ? parts.light : parts.dark;
        copy.commentBubble = target ? (target.commentBubble || null) : null;
        if (fromDark) parts.light = copy;
        else parts.dark = copy;
        // 拷来记录也带过去：那边“取自”的素材键不同，格子会显示成自传，但导出时仍能认出哪些文件拷自内置主题。
        const copies = ReaderInheritedCopies.normalize(fromDark ? record.readerInheritedDark : record.readerInheritedLight);
        SchemeAssetService.setInherited(record, !fromDark, copies);
      } else if (kind === 'ttsPanel') {
        const source = fromDark ? parts.ttsPanelDark : parts.ttsPanelLight;
        if (!source) throw new Error('这个模式还没有面板插画');
        const copy = JSON.parse(JSON.stringify(source)) as ThemePackageTtsPanel;
        if (fromDark) parts.ttsPanelLight = copy;
        else parts.ttsPanelDark = copy;
      } else {
        const source = fromDark ? parts.homeBackdropDark : parts.homeBackdropLight;
        if (!source) throw new Error('这个模式还没有首页背景');
        const crop = SchemeAssetService.attachCrop(
          (fromDark ? parts.homeBackdropDarkCrop : parts.homeBackdropLightCrop) || null, source);
        if (fromDark) {
          parts.homeBackdropLight = source;
          parts.homeBackdropLightCrop = crop;
        } else {
          parts.homeBackdropDark = source;
          parts.homeBackdropDarkCrop = crop;
        }
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
      // 换图、删封面后留下的旧区域清掉。
      tidyImageCrops(record.parts);
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
      parts.book || parts.startupLight || parts.startupDark || parts.bubble || parts.bubbleDark || parts.titleBubble ||
      parts.titleBubbleDark || parts.homeBackdropLight ||
      parts.homeBackdropDark || (parts.shelfBackdrops || []).length > 0 || parts.logo || parts.preview ||
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
    return !!pack && !!(pack.record.parts.bubble || pack.record.parts.bubbleDark);
  }

  static hasHomeBackdrop(packageId: string, darkMode: boolean): boolean {
    const pack = ThemePackRegistry.getByPackageId(packageId);
    return !!pack && !!pack.homeBackdrop(darkMode);
  }

  /** 方案自己给这种书架布局、这个模式单独传了背景。 */
  static hasShelfBackdrop(packageId: string, shelfLayout: string, darkMode: boolean): boolean {
    const pack = ThemePackRegistry.getByPackageId(packageId);
    return !!pack && !!pack.shelfBackdrop(shelfLayout, darkMode);
  }

  /** 上传背景前“首页背景”来源所选的内置主题；移除全部背景后来源退回它。没记时为空串。 */
  static homeBackdropFallbackOf(packageId: string, darkMode: boolean): string {
    const pack = ThemePackRegistry.getByPackageId(packageId);
    if (!pack) return '';
    return (darkMode ? pack.record.homeBackdropFallbackDark : pack.record.homeBackdropFallbackLight) || '';
  }

  /** 方案自己上传的封面张数；dark 数深色那套（0 表示深色沿用浅色的）。 */
  static coverCount(packageId: string, dark: boolean = false): number {
    const pack = ThemePackRegistry.getByPackageId(packageId);
    const book = pack ? pack.record.parts.book : null;
    if (!book) return 0;
    return dark ? (book.coversDark || []).length : book.covers.length;
  }

  static baseThemeOf(packageId: string): string {
    const pack = ThemePackRegistry.getByPackageId(packageId);
    return pack ? (pack.baseTheme || ThemeIds.PLAIN_DEFAULT) : ThemeIds.PLAIN_DEFAULT;
  }
}
