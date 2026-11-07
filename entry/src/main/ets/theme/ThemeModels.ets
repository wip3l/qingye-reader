export class ThemeIds {
  static readonly CUSTOM: string = 'custom';
  static readonly PLAIN_DEFAULT: string = 'plain-default';
  static readonly CLASSIC_BLUE: string = 'classic-blue';
  static readonly WARM_PAPER: string = 'warm-paper';
  static readonly FOREST_MIST: string = 'forest-mist';
  static readonly INK_WASH: string = 'ink-wash';
  static readonly NEON_NIGHT: string = 'neon-night';
  static readonly STRAWBERRY_CREAM: string = 'strawberry-cream';
  static readonly CRIMSON_ARCHIVE: string = 'crimson-archive';
  static readonly PLUM_TEA: string = 'plum-tea';
  static readonly ROSE_LETTER: string = 'rose-letter';
  static readonly MOON_CRANE: string = 'moon-crane';
  static readonly SWORD_FROST: string = 'sword-frost';
  static readonly QINGLUAN_WATER: string = 'qingluan-water';
  static readonly CAT_PIPI: string = 'cat-pipi';
  static readonly AZURE_MECHA: string = 'azure-mecha';
  static readonly STARWISH_MAGIC: string = 'starwish-magic';
  static readonly LETTERPRESS_PAGE: string = 'letterpress-page';
  static readonly OBSIDIAN_ARCHIVE: string = 'obsidian-archive';
  static readonly NEON_HARBOR: string = 'neon-harbor';
  static readonly CELESTIAL_VAULT: string = 'celestial-vault';
}

/**
 * 终身超级会员手动领取的专属主题：不进会员主题库，不能点数兑换或试用；
 * 授权同时要求终身超级会员身份和一年内的领取记录（服务端 theme_catalog.acquisition = SUPER_CLAIM）。
 */
export class SuperExclusiveThemes {
  static readonly IDS: string[] = [ThemeIds.OBSIDIAN_ARCHIVE, ThemeIds.CELESTIAL_VAULT];

  static has(themeId: string): boolean {
    return SuperExclusiveThemes.IDS.indexOf((themeId || '').trim()) >= 0;
  }

  /** 自定义方案的底子或任一部件来源里用到的专属主题。 */
  static usedByScheme(baseThemeId: string, lightSources: ThemeComponentSourceIds,
    darkSources: ThemeComponentSourceIds): string[] {
    const sources = (JSON.stringify(lightSources) || '') + (JSON.stringify(darkSources) || '');
    return SuperExclusiveThemes.IDS.filter((id: string) => baseThemeId === id || sources.includes(`"${id}"`));
  }

  /** 主题配套的桌面图标选项 ID（AppIconManager / app.json5 的 alternateIcons）。 */
  static appIconId(themeId: string): string {
    return `theme_${themeId.replace(/-/g, '_')}`;
  }
}

export class ThemeComponentSourceIds {
  startupThemeId: string = ThemeIds.PLAIN_DEFAULT;
  paletteThemeId: string = ThemeIds.PLAIN_DEFAULT;
  readerThemeId: string = ThemeIds.PLAIN_DEFAULT;
  // Added after the other sources: empty in schemes saved before it existed, which follow readerThemeId.
  ttsPanelThemeId: string = '';
  bubbleThemeId: string = ThemeIds.PLAIN_DEFAULT;
  navigationThemeId: string = ThemeIds.PLAIN_DEFAULT;
  bookThemeId: string = ThemeIds.PLAIN_DEFAULT;
  // 同样是后加的：旧方案里为空，跟随 startupThemeId（启动封面和首页背景都是主题的整幅插画）。
  homeBackdropThemeId: string = '';
  typographyThemeId: string = ThemeIds.PLAIN_DEFAULT;
  layoutThemeId: string = ThemeIds.PLAIN_DEFAULT;
  radiusThemeId: string = ThemeIds.PLAIN_DEFAULT;
  glassThemeId: string = ThemeIds.PLAIN_DEFAULT;
}

export class ThemeRegexEmphasisModes {
  static readonly INHERIT: string = 'inherit';
  static readonly NONE: string = 'none';
  static readonly TEXT: string = 'text';
  static readonly HIGHLIGHT: string = 'highlight';
  static readonly BUBBLE: string = 'bubble';
}

export class ThemeBubbleStyles {
  static readonly INHERIT: string = 'inherit';
  static readonly QQ_SOFT: string = 'qq-soft';
  static readonly QQ_SOLID: string = 'qq-solid';
  static readonly CAPSULE: string = 'capsule';
  static readonly PAPER: string = 'paper';
  static readonly NEON: string = 'neon';
  static readonly CLASSIC_GLASS: string = 'classic-glass';
  static readonly WARM_SCROLL: string = 'warm-scroll';
  static readonly FOREST_DEW: string = 'forest-dew';
  static readonly INK_BRUSH: string = 'ink-brush';
  static readonly NEON_PULSE: string = 'neon-pulse';
  static readonly STRAWBERRY_RIBBON: string = 'strawberry-ribbon';
  static readonly CRIMSON_STAMP: string = 'crimson-stamp';
  static readonly CELADON_SLIP: string = 'celadon-slip';
  static readonly ROSE_FRAME: string = 'rose-frame';
  static readonly MOON_HALO: string = 'moon-halo';
  static readonly SWORD_TALISMAN: string = 'sword-talisman';
  static readonly QINGLUAN_JADE: string = 'qingluan-jade';
  static readonly PIPI_SOFT_PAW: string = 'pipi-soft-paw';
  static readonly MECHA_COMM: string = 'mecha-comm';
  static readonly STARWISH_RIBBON: string = 'starwish-ribbon';
  static readonly PENCIL_MARK: string = 'pencil-mark';
  static readonly GILDED_ORBIT: string = 'gilded-orbit';
  static readonly HARBOR_POSTCARD: string = 'harbor-postcard';
  static readonly CELESTIAL_ORBIT: string = 'celestial-orbit';
}

/** 自定义方案对“完整配色”来源的逐项覆盖：空串表示跟随所选主题。 */
export class ThemeColorOverrides {
  pageColor: string = '';
  cardColor: string = '';
  inputColor: string = '';
  primaryTextColor: string = '';
  subTextColor: string = '';
  dividerColor: string = '';
  dangerColor: string = '';
}

/** 自定义方案对“强调气泡”来源的覆盖：mode / bubbleStyle / 颜色为空都表示跟随所选主题。 */
export class ThemeEmphasisOverrides {
  mode: string = '';
  bubbleStyle: string = '';
  color: string = '';
  textColor: string = '';
}

/** 自定义方案对圆角的逐项覆盖：-1 表示跟随所选主题。 */
export class ThemeRadiusOverrides {
  small: number = -1;
  medium: number = -1;
  large: number = -1;
  card: number = -1;
  button: number = -1;
  bubble: number = -1;
}

/** 启动封面文案样式：空串 / 0 表示默认（白字、默认字号）。 */
export class ThemeStartupTextStyle {
  titleColor: string = '';
  subtitleColor: string = '';
  titleSize: number = 0;
  subtitleSize: number = 0;
}

export class ThemeBubbleStyleLabels {
  static label(styleId: string): string {
    const id = (styleId || '').trim();
    if (id === 'qq-soft') return '柔和';
    if (id === 'qq-solid') return '实色';
    if (id === 'capsule') return '圆角胶囊';
    if (id === 'paper') return '纸笺';
    if (id === 'neon') return '霓虹';
    if (id === 'classic-glass') return '经典玻璃';
    if (id === 'warm-scroll') return '暖纸卷轴';
    if (id === 'forest-dew') return '林间露珠';
    if (id === 'ink-brush') return '水墨笔触';
    if (id === 'neon-pulse') return '霓虹脉冲';
    if (id === 'strawberry-ribbon') return '草莓软框';
    if (id === 'crimson-stamp') return '赤墨印章';
    if (id === 'celadon-slip') return '青瓷纸笺';
    if (id === 'rose-frame') return '玫瑰信框';
    if (id === 'moon-halo') return '月光描边';
    if (id === 'sword-talisman') return '剑符';
    if (id === 'qingluan-jade') return '青鸾玉令';
    if (id === 'pipi-soft-paw') return '皮皮软爪';
    if (id === 'mecha-comm') return '通讯频道';
    if (id === 'starwish-ribbon') return '星愿丝带';
    if (id === 'pencil-mark') return '铅笔划线';
    if (id === 'gilded-orbit') return '曜金藏签';
    if (id === 'harbor-postcard') return '港湾邮笺';
    if (id === 'celestial-orbit') return '星穹御签';
    return id;
  }

  /** 通用气泡 + 内置主题专属气泡，按气泡 ID 列出；主题包的气泡由调用方按已安装包追加。 */
  static readonly BUILTIN_IDS: string[] = ['qq-soft', 'qq-solid', 'capsule', 'paper', 'neon', 'classic-glass',
    'warm-scroll', 'forest-dew', 'ink-brush', 'neon-pulse', 'strawberry-ribbon', 'crimson-stamp', 'celadon-slip',
    'rose-frame', 'moon-halo', 'sword-talisman', 'qingluan-jade', 'pipi-soft-paw', 'mecha-comm', 'starwish-ribbon',
    'pencil-mark', 'gilded-orbit', 'harbor-postcard', 'celestial-orbit'];
}

export class ThemeColorTokens {
  pageColor: string = '#F5F5F5';
  cardColor: string = '#FFFFFF';
  inputColor: string = '#F0F2F5';
  primaryTextColor: string = '#1F1F1F';
  subTextColor: string = '#888888';
  dividerColor: string = '#E0E0E0';
  accentColor: string = '#007DFF';
  buttonColor: string = '#007DFF';
  dangerColor: string = '#E53935';
}

export class ThemeReaderTokens {
  backgroundColor: string = '#F7F1E3';
  backgroundAssetId: string = '';
  backgroundImageFit: string = 'cover';
  textColor: string = '#2F261D';
  subTextColor: string = '#7A6F63';
  contentTone: string = 'light';
}

export class ThemeRegexEmphasisTokens {
  emphasisMode: string = ThemeRegexEmphasisModes.BUBBLE;
  bubbleStyle: string = ThemeBubbleStyles.QQ_SOFT;
  emphasisColor: string = '#D9ECFF';
  emphasisTextColor: string = '#1B4168';
}

export class ThemeVariant {
  colors: ThemeColorTokens = new ThemeColorTokens();
  reader: ThemeReaderTokens = new ThemeReaderTokens();
  regexEmphasis: ThemeRegexEmphasisTokens = new ThemeRegexEmphasisTokens();
}

export class ThemeTypographyTokens {
  appFontFamily: string = 'sans-serif';
}

export class ThemeReaderLayoutTokens {
  fontSize: number = 20;
  letterSpacing: number = 0;
  lineHeight: number = 12;
  paragraphSpacing: number = 0;
  marginLeft: number = 18;
  marginRight: number = 18;
  marginTop: number = 18;
  marginBottom: number = 18;
}

export class ThemeBookTokens {
  coverAssetId: string = ThemeIds.CLASSIC_BLUE;
  shelfFrameAssetId: string = ThemeIds.CLASSIC_BLUE;
  shelfFolderAssetId: string = ThemeIds.CLASSIC_BLUE;
}

export class ThemeNavigationTokens {
  iconPackId: string = 'classic';
}

export class ThemeStartupTokens {
  styleId: string = ThemeIds.CLASSIC_BLUE;
}

export class ThemeRadiusTokens {
  small: number = 6;
  medium: number = 10;
  large: number = 16;
  card: number = 10;
  button: number = 20;
  bubble: number = 6;
}

export class ThemeGlassSurfaceTokens {
  blurRadius: number = 22;
  cornerRadius: number = 16;
}

export class ThemeGlassTokens {
  enabled: boolean = true;
  panel: ThemeGlassSurfaceTokens = new ThemeGlassSurfaceTokens();
  popover: ThemeGlassSurfaceTokens = new ThemeGlassSurfaceTokens();
  button: ThemeGlassSurfaceTokens = new ThemeGlassSurfaceTokens();
  overlay: ThemeGlassSurfaceTokens = new ThemeGlassSurfaceTokens();
  menu: ThemeGlassSurfaceTokens = new ThemeGlassSurfaceTokens();
  lightTintOpacity: number = 85;
  darkTintOpacity: number = 78;
  lightBorderOpacity: number = 65;
  darkBorderOpacity: number = 22;
  borderWidth: number = 1;
  shadowEnabled: boolean = true;
  lightShadowOpacity: number = 17;
  darkShadowOpacity: number = 44;
  shadowRadius: number = 18;
  shadowOffsetX: number = 0;
  shadowOffsetY: number = 6;
  adaptiveColor: boolean = true;
  materialScale: number = 1;

  constructor() {
    this.panel.blurRadius = 22;
    this.panel.cornerRadius = 16;
    this.popover.blurRadius = 18;
    this.popover.cornerRadius = 14;
    this.button.blurRadius = 12;
    this.button.cornerRadius = 24;
    this.overlay.blurRadius = 28;
    this.overlay.cornerRadius = 20;
    this.menu.blurRadius = 10;
    this.menu.cornerRadius = 12;
  }
}

export class ThemePack {
  schemaVersion: number = 3;
  id: string = ThemeIds.CLASSIC_BLUE;
  name: string = '经典蓝';
  description: string = '';
  light: ThemeVariant = new ThemeVariant();
  dark: ThemeVariant = new ThemeVariant();
  typography: ThemeTypographyTokens = new ThemeTypographyTokens();
  readerLayout: ThemeReaderLayoutTokens = new ThemeReaderLayoutTokens();
  book: ThemeBookTokens = new ThemeBookTokens();
  navigation: ThemeNavigationTokens = new ThemeNavigationTokens();
  startup: ThemeStartupTokens = new ThemeStartupTokens();
  radius: ThemeRadiusTokens = new ThemeRadiusTokens();
  glass: ThemeGlassTokens = new ThemeGlassTokens();
}
