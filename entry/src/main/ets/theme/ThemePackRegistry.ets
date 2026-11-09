import {
  isPackThemeId,
  packageIdOfThemeId,
  packReaderBackgroundId,
  packThemeId,
  ThemePackageCredits,
  ThemePackageParts,
  ThemePackageVariantParts
} from './share/ThemePackageFormat';
import { ThemePack, ThemeVariant } from './ThemeModels';

/** 安装在本机的主题包落盘记录（theme_packs/<packageId>/pack.json）：素材引用是包目录下的相对路径。 */
export class ThemePackRecord {
  packageId: string = '';
  name: string = '';
  author: string = '';
  version: string = '';
  description: string = '';
  baseTheme: string = '';
  installedAt: number = 0;
  credits: ThemePackageCredits | null = null;
  parts: ThemePackageParts = new ThemePackageParts();
  // 只在本机：编辑器逐个上传导航图标时，没传的页签用这套内置图标（第一次上传时导航来源主题的图标）。
  navFallbackIconPackId: string = '';
}

export class InstalledThemePackReader {
  // 'ornaments'、'image'、'none'，空表示沿用基底主题。
  mode: string = '';
  leading: string = '';
  trailing: string = '';
  image: string = '';
  imageFit: string = 'cover';
}

export class InstalledThemePackTtsPanel {
  artwork: string = '';
  skyColor: string = '';
  surfaceColor: string = '';
  glowColor: string = '';
}

export class InstalledThemePackStartup {
  image: string = '';
  title: string = '';
  subtitle: string = '';
}

/** 已安装的主题包：主题令牌加各部件素材的本机 URI。素材字段为空表示包里没带，回退到基底主题。 */
export class InstalledThemePack {
  packageId: string = '';
  themeId: string = '';
  name: string = '';
  author: string = '';
  version: string = '';
  description: string = '';
  baseTheme: string = '';
  dir: string = '';
  credits: ThemePackageCredits | null = null;
  pack: ThemePack = new ThemePack();
  readerLight: InstalledThemePackReader = new InstalledThemePackReader();
  readerDark: InstalledThemePackReader = new InstalledThemePackReader();
  ttsLight: InstalledThemePackTtsPanel | null = null;
  ttsDark: InstalledThemePackTtsPanel | null = null;
  navBookshelf: string = '';
  navExplore: string = '';
  navMine: string = '';
  // 第四个页签“听”“足迹”的图标，可选：没给时用基底主题的图标。
  navListen: string = '';
  navFootprint: string = '';
  // 选中态图标，没给的页签选中时用普通图标。
  navBookshelfSelected: string = '';
  navExploreSelected: string = '';
  navMineSelected: string = '';
  navListenSelected: string = '';
  navFootprintSelected: string = '';
  navHideLabels: boolean = false;
  // 编辑器逐个上传导航图标时可能只有几张：缺的页签用基底主题的这套图标。
  navFallbackIconPackId: string = '';
  covers: string[] = [];
  shelfFrame: string = '';
  shelfFolder: string = '';
  startupLight: InstalledThemePackStartup | null = null;
  startupDark: InstalledThemePackStartup | null = null;
  bubbleFrame: string = '';
  bubbleCap: string = '';
  homeBackdropLight: string = '';
  homeBackdropDark: string = '';
  logo: string = '';
  preview: string = '';
  appFont: string = '';
  record: ThemePackRecord = new ThemePackRecord();

  /** 三个普通图标都齐：主题包格式要求的完整导航，只有这样才随分享导出。 */
  hasNavigation(): boolean {
    return !!this.navBookshelf && !!this.navExplore && !!this.navMine;
  }

  hasAnyNavigation(): boolean {
    return !!this.navBookshelf || !!this.navExplore || !!this.navMine || !!this.navListen || !!this.navFootprint;
  }

  hasBubble(): boolean {
    return !!this.bubbleCap;
  }

  reader(darkMode: boolean): InstalledThemePackReader {
    return darkMode ? this.readerDark : this.readerLight;
  }

  startup(darkMode: boolean): InstalledThemePackStartup | null {
    return (darkMode ? this.startupDark : this.startupLight) || this.startupLight || this.startupDark;
  }

  homeBackdrop(darkMode: boolean): string {
    return darkMode ? this.homeBackdropDark : this.homeBackdropLight;
  }

  ttsPanel(darkMode: boolean): InstalledThemePackTtsPanel | null {
    return (darkMode ? this.ttsDark : this.ttsLight) || this.ttsLight || this.ttsDark;
  }
}

/**
 * 进程内的已安装主题包表。冷启动时由 ThemePackStore 在读取主题设置之前填好；BuiltinThemeRegistry 和
 * ThemeAssetRegistry 遇到 pack: 开头的 ID 都到这里取。放在 theme 模块里，页面文件的静态字段不共享。
 */
export class ThemePackRegistry {
  static readonly STORAGE_REVISION: string = 'installedThemePacksRevision';
  private static readonly packs: Map<string, InstalledThemePack> = new Map<string, InstalledThemePack>();

  static isPackId(themeId: string): boolean {
    return isPackThemeId(themeId);
  }

  static themeIdFor(packageId: string): string {
    return packThemeId(packageId);
  }

  /** 认得 pack:<id> 和 pack:<id>:light 这类带后缀的素材键。 */
  static get(themeId: string): InstalledThemePack | null {
    const packageId = packageIdOfThemeId(themeId);
    return packageId ? (ThemePackRegistry.packs.get(packageId) || null) : null;
  }

  static getByPackageId(packageId: string): InstalledThemePack | null {
    return ThemePackRegistry.packs.get(packageId) || null;
  }

  static has(themeId: string): boolean {
    return ThemePackRegistry.get(themeId) !== null;
  }

  static all(): InstalledThemePack[] {
    const result: InstalledThemePack[] = [];
    ThemePackRegistry.packs.forEach((pack: InstalledThemePack) => {
      result.push(pack);
    });
    return result;
  }

  static register(pack: InstalledThemePack): void {
    ThemePackRegistry.packs.set(pack.packageId, pack);
    ThemePackRegistry.bump();
  }

  static unregister(packageId: string): void {
    if (ThemePackRegistry.packs.delete(packageId)) ThemePackRegistry.bump();
  }

  static clear(): void {
    ThemePackRegistry.packs.clear();
    ThemePackRegistry.bump();
  }

  private static bump(): void {
    AppStorage.setOrCreate(ThemePackRegistry.STORAGE_REVISION,
      (AppStorage.get<number>(ThemePackRegistry.STORAGE_REVISION) || 0) + 1);
  }

  /**
   * 由落盘记录和基底主题拼出可用的主题包。resolveUri 把包内相对路径换成本机 file:// URI。
   * 部件缺省时沿用基底主题的令牌，这样只带配色的包也能完整显示。
   */
  static build(record: ThemePackRecord, base: ThemePack, resolveUri: (relativePath: string) => string):
    InstalledThemePack {
    const parts = record.parts;
    const themeId = packThemeId(record.packageId);
    const uri = (value: string): string => value ? resolveUri(value) : '';
    const installed = new InstalledThemePack();
    installed.packageId = record.packageId;
    installed.themeId = themeId;
    installed.name = record.name;
    installed.author = record.author;
    installed.version = record.version;
    installed.description = record.description;
    installed.baseTheme = record.baseTheme;
    installed.credits = record.credits;
    installed.record = record;

    const pack = base;
    pack.id = themeId;
    pack.name = record.name;
    pack.description = record.description || (record.author ? `${record.author} 制作的主题包` : '导入的主题包');

    ThemePackRegistry.applyVariant(pack.light, parts.light, installed.readerLight, record.packageId, false, uri);
    ThemePackRegistry.applyVariant(pack.dark, parts.dark, installed.readerDark, record.packageId, true, uri);

    if (parts.ttsPanelLight) {
      installed.ttsLight = new InstalledThemePackTtsPanel();
      installed.ttsLight.artwork = uri(parts.ttsPanelLight.artwork);
      installed.ttsLight.skyColor = parts.ttsPanelLight.skyColor;
      installed.ttsLight.surfaceColor = parts.ttsPanelLight.surfaceColor;
      installed.ttsLight.glowColor = parts.ttsPanelLight.glowColor;
    }
    if (parts.ttsPanelDark) {
      installed.ttsDark = new InstalledThemePackTtsPanel();
      installed.ttsDark.artwork = uri(parts.ttsPanelDark.artwork);
      installed.ttsDark.skyColor = parts.ttsPanelDark.skyColor;
      installed.ttsDark.surfaceColor = parts.ttsPanelDark.surfaceColor;
      installed.ttsDark.glowColor = parts.ttsPanelDark.glowColor;
    }
    if (parts.navigation) {
      installed.navBookshelf = uri(parts.navigation.bookshelf);
      installed.navExplore = uri(parts.navigation.explore);
      installed.navMine = uri(parts.navigation.mine);
      installed.navBookshelfSelected = uri(parts.navigation.bookshelfSelected || '');
      installed.navExploreSelected = uri(parts.navigation.exploreSelected || '');
      installed.navMineSelected = uri(parts.navigation.mineSelected || '');
      installed.navListen = uri(parts.navigation.listen || '');
      installed.navFootprint = uri(parts.navigation.footprint || '');
      installed.navListenSelected = uri(parts.navigation.listenSelected || '');
      installed.navFootprintSelected = uri(parts.navigation.footprintSelected || '');
      installed.navHideLabels = parts.navigation.labels === 'hidden';
      installed.navFallbackIconPackId = record.navFallbackIconPackId || pack.navigation.iconPackId;
      if (installed.hasAnyNavigation()) pack.navigation.iconPackId = themeId;
    }
    if (parts.book) {
      for (const cover of parts.book.covers) {
        const resolved = uri(cover);
        if (resolved) installed.covers.push(resolved);
      }
      installed.shelfFrame = uri(parts.book.shelfFrame);
      installed.shelfFolder = uri(parts.book.shelfFolder);
      if (installed.covers.length > 0) pack.book.coverAssetId = themeId;
      if (installed.shelfFrame) pack.book.shelfFrameAssetId = themeId;
      if (installed.shelfFolder) pack.book.shelfFolderAssetId = themeId;
    }
    if (parts.startupLight) {
      installed.startupLight = new InstalledThemePackStartup();
      installed.startupLight.image = uri(parts.startupLight.image);
      installed.startupLight.title = parts.startupLight.title;
      installed.startupLight.subtitle = parts.startupLight.subtitle;
    }
    if (parts.startupDark) {
      installed.startupDark = new InstalledThemePackStartup();
      installed.startupDark.image = uri(parts.startupDark.image);
      installed.startupDark.title = parts.startupDark.title;
      installed.startupDark.subtitle = parts.startupDark.subtitle;
    }
    if (installed.startupLight || installed.startupDark) pack.startup.styleId = themeId;
    if (parts.bubble) {
      installed.bubbleFrame = uri(parts.bubble.frame);
      installed.bubbleCap = uri(parts.bubble.cap);
      if (installed.hasBubble()) {
        pack.light.regexEmphasis.bubbleStyle = themeId;
        pack.dark.regexEmphasis.bubbleStyle = themeId;
      }
    }
    // 本机旧版记录里没有这两个字段。
    installed.homeBackdropLight = uri(parts.homeBackdropLight || '');
    installed.homeBackdropDark = uri(parts.homeBackdropDark || '');
    installed.logo = uri(parts.logo);
    installed.preview = uri(parts.preview);
    installed.appFont = uri(parts.appFont);
    if (parts.appFontFamily) pack.typography.appFontFamily = parts.appFontFamily;
    if (parts.radius) {
      const radius = parts.radius;
      if (radius['small'] !== undefined) pack.radius.small = radius['small'];
      if (radius['medium'] !== undefined) pack.radius.medium = radius['medium'];
      if (radius['large'] !== undefined) pack.radius.large = radius['large'];
      if (radius['card'] !== undefined) pack.radius.card = radius['card'];
      if (radius['button'] !== undefined) pack.radius.button = radius['button'];
      if (radius['bubble'] !== undefined) pack.radius.bubble = radius['bubble'];
    }
    installed.pack = pack;
    return installed;
  }

  private static applyVariant(variant: ThemeVariant, source: ThemePackageVariantParts | null,
    reader: InstalledThemePackReader, packageId: string, darkMode: boolean,
    uri: (value: string) => string): void {
    if (!source) return;
    const colors = source.colors;
    if (colors) {
      if (colors.pageColor) variant.colors.pageColor = colors.pageColor;
      if (colors.cardColor) variant.colors.cardColor = colors.cardColor;
      if (colors.inputColor) variant.colors.inputColor = colors.inputColor;
      if (colors.primaryTextColor) variant.colors.primaryTextColor = colors.primaryTextColor;
      if (colors.subTextColor) variant.colors.subTextColor = colors.subTextColor;
      if (colors.dividerColor) variant.colors.dividerColor = colors.dividerColor;
      if (colors.accentColor) variant.colors.accentColor = colors.accentColor;
      if (colors.buttonColor) variant.colors.buttonColor = colors.buttonColor;
      if (colors.dangerColor) variant.colors.dangerColor = colors.dangerColor;
    }
    const readerParts = source.reader;
    if (readerParts) {
      if (readerParts.backgroundColor) variant.reader.backgroundColor = readerParts.backgroundColor;
      if (readerParts.textColor) variant.reader.textColor = readerParts.textColor;
      if (readerParts.subTextColor) variant.reader.subTextColor = readerParts.subTextColor;
      if (readerParts.contentTone) variant.reader.contentTone = readerParts.contentTone;
      const mode = readerParts.backgroundMode || '';
      reader.mode = mode;
      reader.leading = uri(readerParts.leading || '');
      reader.trailing = uri(readerParts.trailing || '');
      reader.image = uri(readerParts.image || '');
      reader.imageFit = readerParts.imageFit || 'cover';
      if (mode === 'none') {
        variant.reader.backgroundAssetId = '';
      } else if (mode === 'ornaments' || mode === 'image') {
        variant.reader.backgroundAssetId = packReaderBackgroundId(packageId, darkMode);
        variant.reader.backgroundImageFit = reader.imageFit;
      }
    }
    const emphasis = source.emphasis;
    if (emphasis) {
      if (emphasis.mode) variant.regexEmphasis.emphasisMode = emphasis.mode;
      if (emphasis.bubbleStyle) variant.regexEmphasis.bubbleStyle = emphasis.bubbleStyle;
      if (emphasis.color) variant.regexEmphasis.emphasisColor = emphasis.color;
      if (emphasis.textColor) variant.regexEmphasis.emphasisTextColor = emphasis.textColor;
    }
  }
}
