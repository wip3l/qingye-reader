import { ThemeIds } from './ThemeModels';
import { InstalledThemePack, ThemePackRegistry } from './ThemePackRegistry';
import { ThemeImageCrop } from './share/ThemePackageFormat';
import { AnimatedImagePolicy } from '../utils/AnimatedImagePolicy';

export class ThemeAssetRegistry {
  static readonly BACKGROUND_PAPER_LIGHT: string = 'paper-light';
  static readonly BACKGROUND_PAPER_DARK: string = 'paper-dark';
  static readonly BACKGROUND_FOREST_LIGHT: string = 'forest-light';
  static readonly BACKGROUND_FOREST_DARK: string = 'forest-dark';
  static readonly BACKGROUND_INK_LIGHT: string = 'ink-light';
  static readonly BACKGROUND_INK_DARK: string = 'ink-dark';
  static readonly BACKGROUND_NEON_LIGHT: string = 'neon-light';
  static readonly BACKGROUND_NEON_DARK: string = 'neon-dark';
  static readonly BACKGROUND_STRAWBERRY_LIGHT: string = 'strawberry-light';
  static readonly BACKGROUND_STRAWBERRY_DARK: string = 'strawberry-dark';
  static readonly BACKGROUND_CRIMSON_LIGHT: string = 'crimson-light';
  static readonly BACKGROUND_CRIMSON_DARK: string = 'crimson-dark';
  static readonly BACKGROUND_PLUM_TEA_LIGHT: string = 'plum-tea-light';
  static readonly BACKGROUND_PLUM_TEA_DARK: string = 'plum-tea-dark';
  static readonly BACKGROUND_ROSE_LETTER_LIGHT: string = 'rose-letter-light';
  static readonly BACKGROUND_ROSE_LETTER_DARK: string = 'rose-letter-dark';
  static readonly BACKGROUND_MOON_CRANE_LIGHT: string = 'moon-crane-light';
  static readonly BACKGROUND_MOON_CRANE_DARK: string = 'moon-crane-dark';
  static readonly BACKGROUND_SWORD_FROST_LIGHT: string = 'sword-frost-light';
  static readonly BACKGROUND_SWORD_FROST_DARK: string = 'sword-frost-dark';
  static readonly BACKGROUND_QINGLUAN_WATER_LIGHT: string = 'qingluan-water-light';
  static readonly BACKGROUND_QINGLUAN_WATER_DARK: string = 'qingluan-water-dark';
  static readonly BACKGROUND_CAT_PIPI_LIGHT: string = 'cat-pipi-light';
  static readonly BACKGROUND_CAT_PIPI_DARK: string = 'cat-pipi-dark';
  static readonly BACKGROUND_AZURE_MECHA_LIGHT: string = 'azure-mecha-light';
  static readonly BACKGROUND_AZURE_MECHA_DARK: string = 'azure-mecha-dark';
  static readonly BACKGROUND_STARWISH_MAGIC_LIGHT: string = 'starwish-magic-light';
  static readonly BACKGROUND_STARWISH_MAGIC_DARK: string = 'starwish-magic-dark';
  static readonly BACKGROUND_LETTERPRESS_PAGE_LIGHT: string = 'letterpress-page-light';
  static readonly BACKGROUND_OBSIDIAN_ARCHIVE_LIGHT: string = 'obsidian-archive-light';
  static readonly BACKGROUND_NEON_HARBOR_LIGHT: string = 'neon-harbor-light';
  static readonly BACKGROUND_LETTERPRESS_PAGE_DARK: string = 'letterpress-page-dark';
  static readonly BACKGROUND_OBSIDIAN_ARCHIVE_DARK: string = 'obsidian-archive-dark';
  static readonly BACKGROUND_NEON_HARBOR_DARK: string = 'neon-harbor-dark';
  static readonly BACKGROUND_CELESTIAL_VAULT_LIGHT: string = 'celestial-vault-light';
  static readonly BACKGROUND_CELESTIAL_VAULT_DARK: string = 'celestial-vault-dark';

  static readonly ICON_PACK_CLASSIC: string = 'classic';
  static readonly ICON_PACK_ROUNDED: string = 'rounded';
  static readonly ICON_PACK_INK: string = 'ink';
  static readonly ICON_PACK_STRAWBERRY: string = 'strawberry';
  static readonly ICON_PACK_CRIMSON: string = 'crimson';
  static readonly ICON_PACK_PLUM: string = 'plum';
  static readonly ICON_PACK_ROSE: string = 'rose';
  static readonly ICON_PACK_CRANE: string = 'crane';
  static readonly ICON_PACK_SWORD_FROST: string = 'sword-frost';
  static readonly ICON_PACK_QINGLUAN_WATER: string = 'qingluan-water';
  static readonly ICON_PACK_CAT_PIPI: string = 'cat-pipi';
  static readonly ICON_PACK_AZURE_MECHA: string = 'azure-mecha';
  static readonly ICON_PACK_STARWISH_MAGIC: string = 'starwish-magic';
  static readonly ICON_PACK_LETTERPRESS_PAGE: string = 'letterpress-page';
  static readonly ICON_PACK_OBSIDIAN_ARCHIVE: string = 'obsidian-archive';
  static readonly ICON_PACK_NEON_HARBOR: string = 'neon-harbor';
  /** 位图图标、带选中态、底栏不显示文字（同主题包的 labels: hidden）。 */
  static readonly ICON_PACK_CELESTIAL_VAULT: string = 'celestial-vault';

  static readonly TAB_BOOKSHELF: string = 'bookshelf';
  static readonly TAB_EXPLORE: string = 'explore';
  static readonly TAB_MINE: string = 'mine';
  // 首页可选的第四个页签（其他设置 › 底栏）。
  static readonly TAB_LISTEN: string = 'listen';
  static readonly TAB_FOOTPRINT: string = 'footprint';

  /** 主题包阅读背景（pack:<id>:light / :dark）对应的已安装包；不是主题包素材或缺包时返回 null。 */
  private static packReader(assetId: string): InstalledThemePack | null {
    return ThemePackRegistry.isPackId(assetId) ? ThemePackRegistry.get(assetId) : null;
  }

  private static packReaderDark(assetId: string): boolean {
    return (assetId || '').endsWith(':dark');
  }

  /** 主题包整图模式的背景图 URI；角饰模式、内置素材和缺包时为空串。 */
  static readerBackgroundImage(assetId: string): string {
    const pack = ThemeAssetRegistry.packReader(assetId);
    if (!pack) return '';
    const reader = pack.reader(ThemeAssetRegistry.packReaderDark(assetId));
    return reader.mode === 'image' ? reader.image : '';
  }

  static readerBackgroundImageFit(assetId: string): string {
    const pack = ThemeAssetRegistry.packReader(assetId);
    if (!pack) return 'cover';
    return pack.reader(ThemeAssetRegistry.packReaderDark(assetId)).imageFit || 'cover';
  }

  static readerBackground(assetId: string): ResourceStr {
    const packImage = ThemeAssetRegistry.readerBackgroundImage(assetId);
    if (packImage) return packImage;
    switch (ThemeAssetRegistry.normalizeBackgroundAssetId(assetId)) {
      case ThemeAssetRegistry.BACKGROUND_PAPER_LIGHT:
        return $r('app.media.reader_bg_paper_light');
      case ThemeAssetRegistry.BACKGROUND_PAPER_DARK:
        return $r('app.media.reader_bg_paper_dark');
      case ThemeAssetRegistry.BACKGROUND_FOREST_LIGHT:
        return $r('app.media.reader_bg_forest_light');
      case ThemeAssetRegistry.BACKGROUND_FOREST_DARK:
        return $r('app.media.reader_bg_forest_dark');
      case ThemeAssetRegistry.BACKGROUND_INK_LIGHT:
        return $r('app.media.reader_bg_ink_light');
      case ThemeAssetRegistry.BACKGROUND_INK_DARK:
        return $r('app.media.reader_bg_ink_dark');
      case ThemeAssetRegistry.BACKGROUND_NEON_LIGHT:
        return $r('app.media.reader_bg_neon_light');
      case ThemeAssetRegistry.BACKGROUND_NEON_DARK:
        return $r('app.media.reader_bg_neon_dark');
      case ThemeAssetRegistry.BACKGROUND_STRAWBERRY_LIGHT:
        return $r('app.media.reader_bg_strawberry_light');
      case ThemeAssetRegistry.BACKGROUND_STRAWBERRY_DARK:
        return $r('app.media.reader_bg_strawberry_dark');
      case ThemeAssetRegistry.BACKGROUND_CRIMSON_LIGHT:
        return $r('app.media.reader_bg_crimson_light');
      case ThemeAssetRegistry.BACKGROUND_CRIMSON_DARK:
        return $r('app.media.reader_bg_crimson_dark');
      case ThemeAssetRegistry.BACKGROUND_PLUM_TEA_LIGHT:
        return $r('app.media.reader_bg_plum_tea_light');
      case ThemeAssetRegistry.BACKGROUND_PLUM_TEA_DARK:
        return $r('app.media.reader_bg_plum_tea_dark');
      case ThemeAssetRegistry.BACKGROUND_ROSE_LETTER_LIGHT:
        return $r('app.media.reader_bg_rose_letter_light');
      case ThemeAssetRegistry.BACKGROUND_ROSE_LETTER_DARK:
        return $r('app.media.reader_bg_rose_letter_dark');
      case ThemeAssetRegistry.BACKGROUND_MOON_CRANE_LIGHT:
        return $r('app.media.reader_bg_moon_crane_light');
      case ThemeAssetRegistry.BACKGROUND_MOON_CRANE_DARK:
        return $r('app.media.reader_bg_moon_crane_dark');
      case ThemeAssetRegistry.BACKGROUND_SWORD_FROST_LIGHT:
        return $r('app.media.reader_bg_sword_frost_light');
      case ThemeAssetRegistry.BACKGROUND_SWORD_FROST_DARK:
        return $r('app.media.reader_bg_sword_frost_dark');
      case ThemeAssetRegistry.BACKGROUND_QINGLUAN_WATER_LIGHT:
        return $r('app.media.reader_bg_qingluan_water_light');
      case ThemeAssetRegistry.BACKGROUND_QINGLUAN_WATER_DARK:
        return $r('app.media.reader_bg_qingluan_water_dark');
      case ThemeAssetRegistry.BACKGROUND_CAT_PIPI_LIGHT:
        return $r('app.media.reader_bg_cat_pipi_light');
      case ThemeAssetRegistry.BACKGROUND_CAT_PIPI_DARK:
        return $r('app.media.reader_bg_cat_pipi_dark');
      case ThemeAssetRegistry.BACKGROUND_AZURE_MECHA_LIGHT:
        return $r('app.media.reader_bg_azure_mecha_light');
      case ThemeAssetRegistry.BACKGROUND_AZURE_MECHA_DARK:
        return $r('app.media.reader_bg_azure_mecha_dark');
      case ThemeAssetRegistry.BACKGROUND_STARWISH_MAGIC_LIGHT:
        return $r('app.media.reader_bg_starwish_magic_light');
      case ThemeAssetRegistry.BACKGROUND_STARWISH_MAGIC_DARK:
        return $r('app.media.reader_bg_starwish_magic_dark');
      case ThemeAssetRegistry.BACKGROUND_LETTERPRESS_PAGE_LIGHT:
        return $r('app.media.reader_bg_letterpress_page_light');
      case ThemeAssetRegistry.BACKGROUND_OBSIDIAN_ARCHIVE_LIGHT:
        return $r('app.media.reader_bg_obsidian_archive_light');
      case ThemeAssetRegistry.BACKGROUND_NEON_HARBOR_LIGHT:
        return $r('app.media.reader_bg_neon_harbor_light');
      case ThemeAssetRegistry.BACKGROUND_LETTERPRESS_PAGE_DARK:
        return $r('app.media.reader_bg_letterpress_page_dark');
      case ThemeAssetRegistry.BACKGROUND_OBSIDIAN_ARCHIVE_DARK:
        return $r('app.media.reader_bg_obsidian_archive_dark');
      case ThemeAssetRegistry.BACKGROUND_NEON_HARBOR_DARK:
        return $r('app.media.reader_bg_neon_harbor_dark');
      case ThemeAssetRegistry.BACKGROUND_CELESTIAL_VAULT_LIGHT:
        return $r('app.media.reader_bg_celestial_vault_light');
      case ThemeAssetRegistry.BACKGROUND_CELESTIAL_VAULT_DARK:
        return $r('app.media.reader_bg_celestial_vault_dark');
      default:
        return '';
    }
  }

  static readerBackgroundDecoration(assetId: string): ResourceStr {
    const pack = ThemeAssetRegistry.packReader(assetId);
    if (pack) {
      const reader = pack.reader(ThemeAssetRegistry.packReaderDark(assetId));
      return reader.mode === 'ornaments' ? reader.leading : '';
    }
    switch (ThemeAssetRegistry.normalizeBackgroundAssetId(assetId)) {
      case ThemeAssetRegistry.BACKGROUND_PAPER_LIGHT:
        return $r('app.media.reader_decor_paper_light');
      case ThemeAssetRegistry.BACKGROUND_PAPER_DARK:
        return $r('app.media.reader_decor_paper_dark');
      case ThemeAssetRegistry.BACKGROUND_FOREST_LIGHT:
        return $r('app.media.reader_decor_forest_light');
      case ThemeAssetRegistry.BACKGROUND_FOREST_DARK:
        return $r('app.media.reader_decor_forest_dark');
      case ThemeAssetRegistry.BACKGROUND_INK_LIGHT:
        return $r('app.media.reader_decor_ink_light');
      case ThemeAssetRegistry.BACKGROUND_INK_DARK:
        return $r('app.media.reader_decor_ink_dark');
      case ThemeAssetRegistry.BACKGROUND_NEON_LIGHT:
        return $r('app.media.reader_decor_neon_light');
      case ThemeAssetRegistry.BACKGROUND_NEON_DARK:
        return $r('app.media.reader_decor_neon_dark');
      case ThemeAssetRegistry.BACKGROUND_STRAWBERRY_LIGHT:
        return $r('app.media.reader_decor_strawberry_light');
      case ThemeAssetRegistry.BACKGROUND_STRAWBERRY_DARK:
        return $r('app.media.reader_decor_strawberry_dark');
      case ThemeAssetRegistry.BACKGROUND_CRIMSON_LIGHT:
        return $r('app.media.reader_decor_crimson_light');
      case ThemeAssetRegistry.BACKGROUND_CRIMSON_DARK:
        return $r('app.media.reader_decor_crimson_dark');
      case ThemeAssetRegistry.BACKGROUND_PLUM_TEA_LIGHT:
        return $r('app.media.reader_decor_plum_tea_light');
      case ThemeAssetRegistry.BACKGROUND_PLUM_TEA_DARK:
        return $r('app.media.reader_decor_plum_tea_dark');
      case ThemeAssetRegistry.BACKGROUND_ROSE_LETTER_LIGHT:
        return $r('app.media.reader_decor_rose_letter_light');
      case ThemeAssetRegistry.BACKGROUND_ROSE_LETTER_DARK:
        return $r('app.media.reader_decor_rose_letter_dark');
      case ThemeAssetRegistry.BACKGROUND_MOON_CRANE_LIGHT:
        return $r('app.media.reader_decor_moon_crane_light');
      case ThemeAssetRegistry.BACKGROUND_MOON_CRANE_DARK:
        return $r('app.media.reader_decor_moon_crane_dark');
      case ThemeAssetRegistry.BACKGROUND_SWORD_FROST_LIGHT:
        return $r('app.media.reader_decor_sword_frost_light');
      case ThemeAssetRegistry.BACKGROUND_SWORD_FROST_DARK:
        return $r('app.media.reader_decor_sword_frost_dark');
      case ThemeAssetRegistry.BACKGROUND_QINGLUAN_WATER_LIGHT:
        return $r('app.media.reader_decor_qingluan_water_light');
      case ThemeAssetRegistry.BACKGROUND_QINGLUAN_WATER_DARK:
        return $r('app.media.reader_decor_qingluan_water_dark');
      case ThemeAssetRegistry.BACKGROUND_CAT_PIPI_LIGHT:
        return $r('app.media.reader_decor_cat_pipi_light_v2');
      case ThemeAssetRegistry.BACKGROUND_CAT_PIPI_DARK:
        return $r('app.media.reader_decor_cat_pipi_dark_v2');
      case ThemeAssetRegistry.BACKGROUND_AZURE_MECHA_LIGHT:
        return $r('app.media.reader_decor_azure_mecha_light');
      case ThemeAssetRegistry.BACKGROUND_AZURE_MECHA_DARK:
        return $r('app.media.reader_decor_azure_mecha_dark');
      case ThemeAssetRegistry.BACKGROUND_STARWISH_MAGIC_LIGHT:
        return $r('app.media.reader_decor_starwish_magic_light');
      case ThemeAssetRegistry.BACKGROUND_STARWISH_MAGIC_DARK:
        return $r('app.media.reader_decor_starwish_magic_dark');
      case ThemeAssetRegistry.BACKGROUND_LETTERPRESS_PAGE_LIGHT:
        return $r('app.media.reader_decor_letterpress_page_light');
      case ThemeAssetRegistry.BACKGROUND_OBSIDIAN_ARCHIVE_LIGHT:
        return $r('app.media.reader_decor_obsidian_archive_light');
      case ThemeAssetRegistry.BACKGROUND_NEON_HARBOR_LIGHT:
        return $r('app.media.reader_decor_neon_harbor_light');
      case ThemeAssetRegistry.BACKGROUND_LETTERPRESS_PAGE_DARK:
        return $r('app.media.reader_decor_letterpress_page_dark');
      case ThemeAssetRegistry.BACKGROUND_OBSIDIAN_ARCHIVE_DARK:
        return $r('app.media.reader_decor_obsidian_archive_dark');
      case ThemeAssetRegistry.BACKGROUND_NEON_HARBOR_DARK:
        return $r('app.media.reader_decor_neon_harbor_dark');
      case ThemeAssetRegistry.BACKGROUND_CELESTIAL_VAULT_LIGHT:
        return $r('app.media.reader_decor_celestial_vault_light');
      case ThemeAssetRegistry.BACKGROUND_CELESTIAL_VAULT_DARK:
        return $r('app.media.reader_decor_celestial_vault_dark');
      default:
        return '';
    }
  }

  // Every builtin background has its own bottom-right drawing (see
  // scripts/generate-reader-trailing-ornaments.py); the mirrored fallback is
  // only for assets registered without one.
  static readerBackgroundTrailingDecoration(assetId: string): ResourceStr {
    const pack = ThemeAssetRegistry.packReader(assetId);
    if (pack) {
      const reader = pack.reader(ThemeAssetRegistry.packReaderDark(assetId));
      return reader.mode === 'ornaments' ? (reader.trailing || reader.leading) : '';
    }
    switch (ThemeAssetRegistry.normalizeBackgroundAssetId(assetId)) {
      case ThemeAssetRegistry.BACKGROUND_PAPER_LIGHT:
        return $r('app.media.reader_decor_paper_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_PAPER_DARK:
        return $r('app.media.reader_decor_paper_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_FOREST_LIGHT:
        return $r('app.media.reader_decor_forest_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_FOREST_DARK:
        return $r('app.media.reader_decor_forest_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_INK_LIGHT:
        return $r('app.media.reader_decor_ink_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_INK_DARK:
        return $r('app.media.reader_decor_ink_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_NEON_LIGHT:
        return $r('app.media.reader_decor_neon_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_NEON_DARK:
        return $r('app.media.reader_decor_neon_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_STRAWBERRY_LIGHT:
        return $r('app.media.reader_decor_strawberry_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_STRAWBERRY_DARK:
        return $r('app.media.reader_decor_strawberry_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_CRIMSON_LIGHT:
        return $r('app.media.reader_decor_crimson_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_CRIMSON_DARK:
        return $r('app.media.reader_decor_crimson_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_PLUM_TEA_LIGHT:
        return $r('app.media.reader_decor_plum_tea_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_PLUM_TEA_DARK:
        return $r('app.media.reader_decor_plum_tea_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_ROSE_LETTER_LIGHT:
        return $r('app.media.reader_decor_rose_letter_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_ROSE_LETTER_DARK:
        return $r('app.media.reader_decor_rose_letter_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_MOON_CRANE_LIGHT:
        return $r('app.media.reader_decor_moon_crane_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_MOON_CRANE_DARK:
        return $r('app.media.reader_decor_moon_crane_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_SWORD_FROST_LIGHT:
        return $r('app.media.reader_decor_sword_frost_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_SWORD_FROST_DARK:
        return $r('app.media.reader_decor_sword_frost_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_QINGLUAN_WATER_LIGHT:
        return $r('app.media.reader_decor_qingluan_water_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_QINGLUAN_WATER_DARK:
        return $r('app.media.reader_decor_qingluan_water_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_CAT_PIPI_LIGHT:
        return $r('app.media.reader_decor_cat_pipi_trailing_light_v2');
      case ThemeAssetRegistry.BACKGROUND_CAT_PIPI_DARK:
        return $r('app.media.reader_decor_cat_pipi_trailing_dark_v2');
      case ThemeAssetRegistry.BACKGROUND_AZURE_MECHA_LIGHT:
        return $r('app.media.reader_decor_azure_mecha_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_AZURE_MECHA_DARK:
        return $r('app.media.reader_decor_azure_mecha_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_STARWISH_MAGIC_LIGHT:
        return $r('app.media.reader_decor_starwish_magic_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_STARWISH_MAGIC_DARK:
        return $r('app.media.reader_decor_starwish_magic_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_LETTERPRESS_PAGE_LIGHT:
        return $r('app.media.reader_decor_letterpress_page_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_OBSIDIAN_ARCHIVE_LIGHT:
        return $r('app.media.reader_decor_obsidian_archive_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_NEON_HARBOR_LIGHT:
        return $r('app.media.reader_decor_neon_harbor_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_LETTERPRESS_PAGE_DARK:
        return $r('app.media.reader_decor_letterpress_page_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_OBSIDIAN_ARCHIVE_DARK:
        return $r('app.media.reader_decor_obsidian_archive_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_NEON_HARBOR_DARK:
        return $r('app.media.reader_decor_neon_harbor_trailing_dark');
      case ThemeAssetRegistry.BACKGROUND_CELESTIAL_VAULT_LIGHT:
        return $r('app.media.reader_decor_celestial_vault_trailing_light');
      case ThemeAssetRegistry.BACKGROUND_CELESTIAL_VAULT_DARK:
        return $r('app.media.reader_decor_celestial_vault_trailing_dark');
      default:
        return ThemeAssetRegistry.readerBackgroundDecoration(assetId);
    }
  }

  static readerBackgroundTrailingRotation(assetId: string): number {
    const trailing = ThemeAssetRegistry.readerBackgroundTrailingDecoration(assetId);
    return trailing === ThemeAssetRegistry.readerBackgroundDecoration(assetId) ? 180 : 0;
  }

  /** selected 为 true 时优先取选中态图标：主题包和星穹御藏有选中态，其余内置图标包没有。 */
  static navigationIcon(iconPackId: string, tabId: string, selected: boolean = false): ResourceStr {
    const normalizedPackId = ThemeAssetRegistry.normalizeIconPackId(iconPackId);
    const normalizedTabId = ThemeAssetRegistry.normalizeTabId(tabId);
    if (ThemePackRegistry.isPackId(normalizedPackId)) {
      const pack = ThemePackRegistry.get(normalizedPackId);
      if (pack && pack.hasAnyNavigation()) {
        let normal = pack.navBookshelf;
        let active = pack.navBookshelfSelected;
        if (normalizedTabId === ThemeAssetRegistry.TAB_EXPLORE) {
          normal = pack.navExplore;
          active = pack.navExploreSelected;
        } else if (normalizedTabId === ThemeAssetRegistry.TAB_MINE) {
          normal = pack.navMine;
          active = pack.navMineSelected;
        } else if (normalizedTabId === ThemeAssetRegistry.TAB_LISTEN) {
          normal = pack.navListen;
          active = pack.navListenSelected;
        } else if (normalizedTabId === ThemeAssetRegistry.TAB_FOOTPRINT) {
          normal = pack.navFootprint;
          active = pack.navFootprintSelected;
        }
        if (selected && active) return active;
        if (normal) return normal;
        // 只上传了几个图标的方案、没带“听”“足迹”图标的包：缺的页签用基底主题的图标（基底一定是内置主题，
        // 不会再递归回包）。
        return ThemePackRegistry.isPackId(pack.navFallbackIconPackId) ?
          ThemeAssetRegistry.classicNavigationIcon(normalizedTabId) :
          ThemeAssetRegistry.navigationIcon(pack.navFallbackIconPackId, normalizedTabId, selected);
      }
      return ThemeAssetRegistry.classicNavigationIcon(normalizedTabId);
    }
    if (normalizedPackId === ThemeAssetRegistry.ICON_PACK_ROUNDED) {
      return ThemeAssetRegistry.roundedNavigationIcon(normalizedTabId);
    }
    if (normalizedPackId === ThemeAssetRegistry.ICON_PACK_CELESTIAL_VAULT) {
      return ThemeAssetRegistry.celestialNavigationIcon(normalizedTabId, selected);
    }
    if (normalizedPackId === ThemeAssetRegistry.ICON_PACK_INK) {
      return ThemeAssetRegistry.inkNavigationIcon(normalizedTabId);
    }
    if (normalizedPackId === ThemeAssetRegistry.ICON_PACK_STRAWBERRY ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_CRIMSON ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_PLUM ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_ROSE ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_CRANE ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_SWORD_FROST ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_QINGLUAN_WATER ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_CAT_PIPI ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_AZURE_MECHA ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_STARWISH_MAGIC ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_LETTERPRESS_PAGE ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_OBSIDIAN_ARCHIVE ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_NEON_HARBOR) {
      return ThemeAssetRegistry.themedNavigationIcon(normalizedPackId, normalizedTabId);
    }
    return ThemeAssetRegistry.classicNavigationIcon(normalizedTabId);
  }

  static themeLogo(themeId: string): ResourceStr {
    if (ThemePackRegistry.isPackId(themeId)) {
      const pack = ThemePackRegistry.get(themeId);
      if (pack && pack.logo) return pack.logo;
      return $r('app.media.theme_logo_classic_blue');
    }
    switch ((themeId || '').trim().toLowerCase()) {
      case ThemeIds.CUSTOM:
        return $r('app.media.theme_logo_custom');
      case ThemeIds.PLAIN_DEFAULT:
        return $r('app.media.theme_logo_plain_default');
      case ThemeIds.WARM_PAPER:
        return $r('app.media.theme_logo_warm_paper');
      case ThemeIds.FOREST_MIST:
        return $r('app.media.theme_logo_forest_mist');
      case ThemeIds.INK_WASH:
        return $r('app.media.theme_logo_ink_wash');
      case ThemeIds.NEON_NIGHT:
        return $r('app.media.theme_logo_neon_night');
      case ThemeIds.STRAWBERRY_CREAM:
        return $r('app.media.theme_logo_strawberry_cream');
      case ThemeIds.CRIMSON_ARCHIVE:
        return $r('app.media.theme_logo_crimson_archive');
      case ThemeIds.PLUM_TEA:
        return $r('app.media.theme_logo_plum_tea');
      case ThemeIds.ROSE_LETTER:
        return $r('app.media.theme_logo_rose_letter');
      case ThemeIds.MOON_CRANE:
        return $r('app.media.theme_logo_moon_crane');
      case ThemeIds.SWORD_FROST:
        return $r('app.media.theme_logo_sword_frost');
      case ThemeIds.QINGLUAN_WATER:
        return $r('app.media.theme_logo_qingluan_water');
      case ThemeIds.CAT_PIPI:
        return $r('app.media.theme_logo_cat_pipi');
      case ThemeIds.AZURE_MECHA:
        return $r('app.media.theme_logo_azure_mecha');
      case ThemeIds.STARWISH_MAGIC:
        return $r('app.media.theme_logo_starwish_magic');
      case ThemeIds.LETTERPRESS_PAGE:
        return $r('app.media.theme_logo_letterpress_page');
      case ThemeIds.OBSIDIAN_ARCHIVE:
        return $r('app.media.theme_logo_obsidian_archive');
      case ThemeIds.NEON_HARBOR:
        return $r('app.media.theme_logo_neon_harbor');
      case ThemeIds.CELESTIAL_VAULT:
        return $r('app.media.theme_logo_celestial_vault');
      default:
        return $r('app.media.theme_logo_classic_blue');
    }
  }

  static startupBackground(themeId: string, darkMode: boolean = false): ResourceStr {
    if (ThemePackRegistry.isPackId(themeId)) {
      const pack = ThemePackRegistry.get(themeId);
      const startup = pack ? pack.startup(darkMode) : null;
      if (startup && startup.image) return startup.image;
      return $r('app.media.theme_startup_classic_blue');
    }
    switch ((themeId || '').trim().toLowerCase()) {
      case ThemeIds.WARM_PAPER: return $r('app.media.theme_startup_warm_paper');
      case ThemeIds.FOREST_MIST: return $r('app.media.theme_startup_forest_mist');
      case ThemeIds.INK_WASH: return $r('app.media.theme_startup_ink_wash');
      case ThemeIds.NEON_NIGHT: return $r('app.media.theme_startup_neon_night');
      case ThemeIds.STRAWBERRY_CREAM: return $r('app.media.theme_startup_strawberry_cream');
      case ThemeIds.CRIMSON_ARCHIVE: return $r('app.media.theme_startup_crimson_archive');
      case ThemeIds.PLUM_TEA: return $r('app.media.theme_startup_plum_tea');
      case ThemeIds.ROSE_LETTER: return $r('app.media.theme_startup_rose_letter');
      case ThemeIds.MOON_CRANE: return $r('app.media.theme_startup_moon_crane');
      case ThemeIds.SWORD_FROST: return $r('app.media.theme_startup_sword_frost');
      case ThemeIds.QINGLUAN_WATER: return $r('app.media.theme_startup_qingluan_water');
      case ThemeIds.CAT_PIPI: return $r('app.media.theme_startup_cat_pipi_v2');
      case ThemeIds.AZURE_MECHA: return $r('app.media.theme_startup_azure_mecha');
      case ThemeIds.STARWISH_MAGIC: return $r('app.media.theme_startup_starwish_magic');
      case ThemeIds.LETTERPRESS_PAGE: return $r('app.media.theme_startup_letterpress_page');
      case ThemeIds.OBSIDIAN_ARCHIVE: return $r('app.media.theme_startup_obsidian_archive');
      case ThemeIds.NEON_HARBOR: return $r('app.media.theme_startup_neon_harbor');
      case ThemeIds.CELESTIAL_VAULT: return $r('app.media.theme_startup_celestial_vault');
      default: return $r('app.media.theme_startup_classic_blue');
    }
  }

  /**
   * 首页三个页签顶部的主题背景图（宽高比 HOME_BACKDROP_ASPECT，画面集中在上部、向下淡成纯底色）；没有的主题返回 null。
   * 主题包只取对应模式那一张，深浅色不互相借用：浅色图放进深色模式会是一大块亮斑。
   */
  static homeBackdrop(themeId: string, darkMode: boolean = false): ResourceStr | null {
    if (ThemePackRegistry.isPackId(themeId)) {
      const pack = ThemePackRegistry.get(themeId);
      const image = pack ? pack.homeBackdrop(darkMode) : '';
      return image || null;
    }
    // 两套超级会员专属主题的背景带一段循环动图（*_anim.webp，首尾帧相同的 6 秒视频转成）；
    // “播放动图”关闭时退回同一画面的静图。
    const animated = AnimatedImagePolicy.enabled();
    switch ((themeId || '').trim().toLowerCase()) {
      case ThemeIds.OBSIDIAN_ARCHIVE:
        if (animated) {
          return darkMode ? $r('app.media.home_bg_obsidian_archive_dark_anim') :
            $r('app.media.home_bg_obsidian_archive_light_anim');
        }
        return darkMode ? $r('app.media.home_bg_obsidian_archive_dark') : $r('app.media.home_bg_obsidian_archive_light');
      case ThemeIds.CELESTIAL_VAULT:
        if (animated) {
          return darkMode ? $r('app.media.home_bg_celestial_vault_dark_anim') :
            $r('app.media.home_bg_celestial_vault_light_anim');
        }
        return darkMode ? $r('app.media.home_bg_celestial_vault_dark') : $r('app.media.home_bg_celestial_vault_light');
      default: return null;
    }
  }

  static readonly HOME_BACKDROP_ASPECT: number = 1080 / 1350;

  /**
   * 主题包素材的显示区域（动图取景）。src 可以是 AnimatedImagePolicy 换出来的第一帧静图，按原图查。
   * 内置主题和没有区域的素材返回 null，照常整张显示。
   */
  static imageCrop(slot: string, src: ResourceStr | null | undefined, darkMode: boolean = false): ThemeImageCrop | null {
    if (typeof src !== 'string' || !src) return null;
    return ThemePackRegistry.imageCrop(slot, src, darkMode) ||
      ThemePackRegistry.imageCrop(slot, AnimatedImagePolicy.originalOf(src), darkMode);
  }

  static themeBookCover(assetId: string): ResourceStr {
    const covers = ThemeAssetRegistry.themeBookCovers(assetId);
    return covers.length > 0 ? covers[0] : '';
  }

  static themeBookCovers(assetId: string): ResourceStr[] {
    if (ThemePackRegistry.isPackId(assetId)) {
      const pack = ThemePackRegistry.get(assetId);
      const covers: ResourceStr[] = [];
      if (pack) {
        for (const cover of pack.covers) covers.push(cover);
      }
      return covers;
    }
    switch ((assetId || '').trim().toLowerCase()) {
      case '': return [];
      case ThemeIds.WARM_PAPER: return [
        $r('app.media.theme_cover_warm_paper_01'), $r('app.media.theme_cover_warm_paper_02'),
        $r('app.media.theme_cover_warm_paper_03'), $r('app.media.theme_cover_warm_paper_04')
      ];
      case ThemeIds.FOREST_MIST: return [
        $r('app.media.theme_cover_forest_mist_01'), $r('app.media.theme_cover_forest_mist_02'),
        $r('app.media.theme_cover_forest_mist_03'), $r('app.media.theme_cover_forest_mist_04')
      ];
      case ThemeIds.INK_WASH: return [
        $r('app.media.theme_cover_ink_wash_01'), $r('app.media.theme_cover_ink_wash_02'),
        $r('app.media.theme_cover_ink_wash_03'), $r('app.media.theme_cover_ink_wash_04')
      ];
      case ThemeIds.NEON_NIGHT: return [
        $r('app.media.theme_cover_neon_night_01'), $r('app.media.theme_cover_neon_night_02'),
        $r('app.media.theme_cover_neon_night_03'), $r('app.media.theme_cover_neon_night_04')
      ];
      case ThemeIds.STRAWBERRY_CREAM: return [
        $r('app.media.theme_cover_strawberry_cream_01'), $r('app.media.theme_cover_strawberry_cream_02'),
        $r('app.media.theme_cover_strawberry_cream_03'), $r('app.media.theme_cover_strawberry_cream_04'),
        $r('app.media.theme_cover_strawberry_cream_05'), $r('app.media.theme_cover_strawberry_cream_06')
      ];
      case ThemeIds.CRIMSON_ARCHIVE: return [
        $r('app.media.theme_cover_crimson_archive_01'), $r('app.media.theme_cover_crimson_archive_02'),
        $r('app.media.theme_cover_crimson_archive_03'), $r('app.media.theme_cover_crimson_archive_04'),
        $r('app.media.theme_cover_crimson_archive_05'), $r('app.media.theme_cover_crimson_archive_06')
      ];
      case ThemeIds.PLUM_TEA: return [
        $r('app.media.theme_cover_plum_tea_01'), $r('app.media.theme_cover_plum_tea_02'),
        $r('app.media.theme_cover_plum_tea_03'), $r('app.media.theme_cover_plum_tea_04'),
        $r('app.media.theme_cover_plum_tea_05'), $r('app.media.theme_cover_plum_tea_06')
      ];
      case ThemeIds.ROSE_LETTER: return [
        $r('app.media.theme_cover_rose_letter_01'), $r('app.media.theme_cover_rose_letter_02'),
        $r('app.media.theme_cover_rose_letter_03'), $r('app.media.theme_cover_rose_letter_04'),
        $r('app.media.theme_cover_rose_letter_05'), $r('app.media.theme_cover_rose_letter_06')
      ];
      case ThemeIds.MOON_CRANE: return [
        $r('app.media.theme_cover_moon_crane_01'), $r('app.media.theme_cover_moon_crane_02'),
        $r('app.media.theme_cover_moon_crane_03'), $r('app.media.theme_cover_moon_crane_04'),
        $r('app.media.theme_cover_moon_crane_05'), $r('app.media.theme_cover_moon_crane_06')
      ];
      case ThemeIds.SWORD_FROST: return [
        $r('app.media.theme_cover_sword_frost_01'), $r('app.media.theme_cover_sword_frost_02'),
        $r('app.media.theme_cover_sword_frost_03'), $r('app.media.theme_cover_sword_frost_04'),
        $r('app.media.theme_cover_sword_frost_05'), $r('app.media.theme_cover_sword_frost_06')
      ];
      case ThemeIds.QINGLUAN_WATER: return [
        $r('app.media.theme_cover_qingluan_water_01'), $r('app.media.theme_cover_qingluan_water_02'),
        $r('app.media.theme_cover_qingluan_water_03'), $r('app.media.theme_cover_qingluan_water_04'),
        $r('app.media.theme_cover_qingluan_water_05'), $r('app.media.theme_cover_qingluan_water_06')
      ];
      case ThemeIds.CAT_PIPI: return [
        $r('app.media.theme_cover_cat_pipi_v2_01'), $r('app.media.theme_cover_cat_pipi_v2_02'),
        $r('app.media.theme_cover_cat_pipi_v2_03'), $r('app.media.theme_cover_cat_pipi_v2_04'),
        $r('app.media.theme_cover_cat_pipi_v2_05'), $r('app.media.theme_cover_cat_pipi_v2_06')
      ];
      case ThemeIds.AZURE_MECHA: return [
        $r('app.media.theme_cover_azure_mecha_01'), $r('app.media.theme_cover_azure_mecha_02'),
        $r('app.media.theme_cover_azure_mecha_03'), $r('app.media.theme_cover_azure_mecha_04'),
        $r('app.media.theme_cover_azure_mecha_05'), $r('app.media.theme_cover_azure_mecha_06')
      ];
      case ThemeIds.STARWISH_MAGIC: return [
        $r('app.media.theme_cover_starwish_magic_01'), $r('app.media.theme_cover_starwish_magic_02'),
        $r('app.media.theme_cover_starwish_magic_03'), $r('app.media.theme_cover_starwish_magic_04'),
        $r('app.media.theme_cover_starwish_magic_05'), $r('app.media.theme_cover_starwish_magic_06')
      ];
      case ThemeIds.LETTERPRESS_PAGE: return [
        $r('app.media.theme_cover_letterpress_page_01'), $r('app.media.theme_cover_letterpress_page_02'),
        $r('app.media.theme_cover_letterpress_page_03'), $r('app.media.theme_cover_letterpress_page_04'),
        $r('app.media.theme_cover_letterpress_page_05'), $r('app.media.theme_cover_letterpress_page_06')
      ];
      case ThemeIds.OBSIDIAN_ARCHIVE: return [
        $r('app.media.theme_cover_obsidian_archive_01'), $r('app.media.theme_cover_obsidian_archive_02'),
        $r('app.media.theme_cover_obsidian_archive_03'), $r('app.media.theme_cover_obsidian_archive_04'),
        $r('app.media.theme_cover_obsidian_archive_05'), $r('app.media.theme_cover_obsidian_archive_06')
      ];
      case ThemeIds.NEON_HARBOR: return [
        $r('app.media.theme_cover_neon_harbor_01'), $r('app.media.theme_cover_neon_harbor_02'),
        $r('app.media.theme_cover_neon_harbor_03'), $r('app.media.theme_cover_neon_harbor_04'),
        $r('app.media.theme_cover_neon_harbor_05'), $r('app.media.theme_cover_neon_harbor_06')
      ];
      case ThemeIds.CELESTIAL_VAULT: return [
        $r('app.media.theme_cover_celestial_vault_01'), $r('app.media.theme_cover_celestial_vault_02'),
        $r('app.media.theme_cover_celestial_vault_03'), $r('app.media.theme_cover_celestial_vault_04'),
        $r('app.media.theme_cover_celestial_vault_05'), $r('app.media.theme_cover_celestial_vault_06')
      ];
      default: return [
        $r('app.media.theme_cover_classic_blue_01'), $r('app.media.theme_cover_classic_blue_02'),
        $r('app.media.theme_cover_classic_blue_03'), $r('app.media.theme_cover_classic_blue_04')
      ];
    }
  }

  static themeShelfFrame(assetId: string): ResourceStr {
    if (ThemePackRegistry.isPackId(assetId)) {
      const pack = ThemePackRegistry.get(assetId);
      return pack ? pack.shelfFrame : '';
    }
    switch ((assetId || '').trim().toLowerCase()) {
      case '': return '';
      case ThemeIds.WARM_PAPER: return $r('app.media.theme_frame_warm_paper');
      case ThemeIds.FOREST_MIST: return $r('app.media.theme_frame_forest_mist');
      case ThemeIds.INK_WASH: return $r('app.media.theme_frame_ink_wash');
      case ThemeIds.NEON_NIGHT: return $r('app.media.theme_frame_neon_night');
      case ThemeIds.STRAWBERRY_CREAM: return $r('app.media.theme_frame_strawberry_cream');
      case ThemeIds.CRIMSON_ARCHIVE: return $r('app.media.theme_frame_crimson_archive');
      case ThemeIds.PLUM_TEA: return $r('app.media.theme_frame_plum_tea');
      case ThemeIds.ROSE_LETTER: return $r('app.media.theme_frame_rose_letter');
      case ThemeIds.MOON_CRANE: return $r('app.media.theme_frame_moon_crane');
      case ThemeIds.SWORD_FROST: return $r('app.media.theme_frame_sword_frost');
      case ThemeIds.QINGLUAN_WATER: return $r('app.media.theme_frame_qingluan_water');
      case ThemeIds.CAT_PIPI: return $r('app.media.theme_frame_cat_pipi');
      case ThemeIds.AZURE_MECHA: return $r('app.media.theme_frame_azure_mecha');
      case ThemeIds.STARWISH_MAGIC: return $r('app.media.theme_frame_starwish_magic');
      case ThemeIds.LETTERPRESS_PAGE: return $r('app.media.theme_frame_letterpress_page');
      case ThemeIds.OBSIDIAN_ARCHIVE: return $r('app.media.theme_frame_obsidian_archive');
      case ThemeIds.NEON_HARBOR: return $r('app.media.theme_frame_neon_harbor');
      case ThemeIds.CELESTIAL_VAULT: return $r('app.media.theme_frame_celestial_vault');
      default: return $r('app.media.theme_frame_classic_blue');
    }
  }

  static themeShelfFolder(assetId: string): ResourceStr {
    if (ThemePackRegistry.isPackId(assetId)) {
      const pack = ThemePackRegistry.get(assetId);
      return pack ? pack.shelfFolder : '';
    }
    switch ((assetId || '').trim().toLowerCase()) {
      case '': return '';
      case ThemeIds.WARM_PAPER: return $r('app.media.theme_folder_art_warm_paper');
      case ThemeIds.FOREST_MIST: return $r('app.media.theme_folder_art_forest_mist');
      case ThemeIds.INK_WASH: return $r('app.media.theme_folder_art_ink_wash');
      case ThemeIds.NEON_NIGHT: return $r('app.media.theme_folder_art_neon_night');
      case ThemeIds.STRAWBERRY_CREAM: return $r('app.media.theme_folder_art_strawberry_cream');
      case ThemeIds.CRIMSON_ARCHIVE: return $r('app.media.theme_folder_art_crimson_archive');
      case ThemeIds.PLUM_TEA: return $r('app.media.theme_folder_art_plum_tea');
      case ThemeIds.ROSE_LETTER: return $r('app.media.theme_folder_art_rose_letter');
      case ThemeIds.MOON_CRANE: return $r('app.media.theme_folder_art_moon_crane');
      case ThemeIds.SWORD_FROST: return $r('app.media.theme_folder_art_sword_frost');
      case ThemeIds.QINGLUAN_WATER: return $r('app.media.theme_folder_art_qingluan_water');
      case ThemeIds.CAT_PIPI: return $r('app.media.theme_folder_art_cat_pipi');
      case ThemeIds.AZURE_MECHA: return $r('app.media.theme_folder_art_azure_mecha');
      case ThemeIds.STARWISH_MAGIC: return $r('app.media.theme_folder_art_starwish_magic');
      case ThemeIds.LETTERPRESS_PAGE: return $r('app.media.theme_folder_art_letterpress_page');
      case ThemeIds.OBSIDIAN_ARCHIVE: return $r('app.media.theme_folder_art_obsidian_archive');
      case ThemeIds.NEON_HARBOR: return $r('app.media.theme_folder_art_neon_harbor');
      case ThemeIds.CELESTIAL_VAULT: return $r('app.media.theme_folder_art_celestial_vault');
      default: return $r('app.media.theme_folder_art_classic_blue');
    }
  }

  static regexBubbleFrame(styleId: string): ResourceStr {
    if (ThemePackRegistry.isPackId(styleId)) {
      const pack = ThemePackRegistry.get(styleId);
      return pack ? pack.bubbleFrame : '';
    }
    switch ((styleId || '').trim().toLowerCase()) {
      case 'classic-glass': return $r('app.media.regex_frame_classic_glass');
      case 'warm-scroll': return $r('app.media.regex_frame_warm_scroll');
      case 'forest-dew': return $r('app.media.regex_frame_forest_dew');
      case 'ink-brush': return $r('app.media.regex_frame_ink_brush');
      case 'neon-pulse': return $r('app.media.regex_frame_neon_pulse');
      case 'strawberry-ribbon': return $r('app.media.regex_frame_strawberry_ribbon');
      case 'crimson-stamp': return $r('app.media.regex_frame_crimson_stamp');
      case 'celadon-slip': return $r('app.media.regex_frame_celadon_slip');
      case 'rose-frame': return $r('app.media.regex_frame_rose_letter');
      case 'moon-halo': return $r('app.media.regex_frame_moon_halo');
      case 'sword-talisman': return $r('app.media.regex_frame_sword_talisman');
      case 'qingluan-jade': return $r('app.media.regex_frame_qingluan_jade');
      case 'pipi-soft-paw': return $r('app.media.regex_frame_pipi_soft_paw');
      case 'mecha-comm': return $r('app.media.regex_frame_mecha_comm');
      case 'starwish-ribbon': return $r('app.media.regex_frame_starwish_ribbon');
      case 'pencil-mark': return $r('app.media.regex_frame_pencil_mark');
      case 'gilded-orbit': return $r('app.media.regex_frame_gilded_orbit');
      case 'harbor-postcard': return $r('app.media.regex_frame_harbor_postcard');
      case 'celestial-orbit': return $r('app.media.regex_frame_celestial_orbit');
      default: return '';
    }
  }

  static hasRegexBubbleFrame(styleId: string): boolean {
    return !!ThemeAssetRegistry.regexBubbleFrame(styleId);
  }

  static regexBubbleCap(styleId: string): ResourceStr {
    if (ThemePackRegistry.isPackId(styleId)) {
      const pack = ThemePackRegistry.get(styleId);
      return pack ? pack.bubbleCap : '';
    }
    switch ((styleId || '').trim().toLowerCase()) {
      case 'classic-glass': return $r('app.media.regex_cap_classic_glass');
      case 'warm-scroll': return $r('app.media.regex_cap_warm_scroll');
      case 'forest-dew': return $r('app.media.regex_cap_forest_dew');
      case 'ink-brush': return $r('app.media.regex_cap_ink_brush');
      case 'neon-pulse': return $r('app.media.regex_cap_neon_pulse');
      case 'strawberry-ribbon': return $r('app.media.regex_cap_strawberry_ribbon');
      case 'crimson-stamp': return $r('app.media.regex_cap_crimson_stamp');
      case 'celadon-slip': return $r('app.media.regex_cap_celadon_slip');
      case 'rose-frame': return $r('app.media.regex_cap_rose_letter');
      case 'moon-halo': return $r('app.media.regex_cap_moon_halo');
      case 'sword-talisman': return $r('app.media.regex_cap_sword_talisman');
      case 'qingluan-jade': return $r('app.media.regex_cap_qingluan_jade');
      case 'pipi-soft-paw': return $r('app.media.regex_cap_pipi_soft_paw');
      case 'mecha-comm': return $r('app.media.regex_cap_mecha_comm');
      case 'starwish-ribbon': return $r('app.media.regex_cap_starwish_ribbon');
      case 'pencil-mark': return $r('app.media.regex_cap_pencil_mark');
      case 'gilded-orbit': return $r('app.media.regex_cap_gilded_orbit');
      case 'harbor-postcard': return $r('app.media.regex_cap_harbor_postcard');
      case 'celestial-orbit': return $r('app.media.regex_cap_celestial_orbit');
      default: return '';
    }
  }

  static hasRegexBubbleCap(styleId: string): boolean {
    return !!ThemeAssetRegistry.regexBubbleCap(styleId);
  }

  static normalizeBackgroundAssetId(assetId: string): string {
    if (ThemePackRegistry.isPackId(assetId)) {
      return ThemePackRegistry.has(assetId) ? assetId.trim() : '';
    }
    const normalized = (assetId || '').trim().toLowerCase();
    switch (normalized) {
      case ThemeAssetRegistry.BACKGROUND_PAPER_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_PAPER_DARK:
      case ThemeAssetRegistry.BACKGROUND_FOREST_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_FOREST_DARK:
      case ThemeAssetRegistry.BACKGROUND_INK_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_INK_DARK:
      case ThemeAssetRegistry.BACKGROUND_NEON_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_NEON_DARK:
      case ThemeAssetRegistry.BACKGROUND_STRAWBERRY_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_STRAWBERRY_DARK:
      case ThemeAssetRegistry.BACKGROUND_CRIMSON_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_CRIMSON_DARK:
      case ThemeAssetRegistry.BACKGROUND_PLUM_TEA_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_PLUM_TEA_DARK:
      case ThemeAssetRegistry.BACKGROUND_ROSE_LETTER_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_ROSE_LETTER_DARK:
      case ThemeAssetRegistry.BACKGROUND_MOON_CRANE_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_MOON_CRANE_DARK:
      case ThemeAssetRegistry.BACKGROUND_SWORD_FROST_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_SWORD_FROST_DARK:
      case ThemeAssetRegistry.BACKGROUND_QINGLUAN_WATER_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_QINGLUAN_WATER_DARK:
      case ThemeAssetRegistry.BACKGROUND_CAT_PIPI_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_CAT_PIPI_DARK:
      case ThemeAssetRegistry.BACKGROUND_AZURE_MECHA_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_AZURE_MECHA_DARK:
      case ThemeAssetRegistry.BACKGROUND_STARWISH_MAGIC_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_STARWISH_MAGIC_DARK:
      case ThemeAssetRegistry.BACKGROUND_LETTERPRESS_PAGE_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_LETTERPRESS_PAGE_DARK:
      case ThemeAssetRegistry.BACKGROUND_OBSIDIAN_ARCHIVE_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_NEON_HARBOR_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_OBSIDIAN_ARCHIVE_DARK:
      case ThemeAssetRegistry.BACKGROUND_NEON_HARBOR_DARK:
      case ThemeAssetRegistry.BACKGROUND_CELESTIAL_VAULT_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_CELESTIAL_VAULT_DARK:
        return normalized;
      default:
        return '';
    }
  }

  static normalizeIconPackId(iconPackId: string): string {
    if (ThemePackRegistry.isPackId(iconPackId)) {
      return ThemePackRegistry.has(iconPackId) ? iconPackId.trim() : ThemeAssetRegistry.ICON_PACK_CLASSIC;
    }
    const normalized = (iconPackId || '').trim().toLowerCase();
    if (normalized === ThemeAssetRegistry.ICON_PACK_ROUNDED ||
      normalized === ThemeAssetRegistry.ICON_PACK_INK ||
      normalized === ThemeAssetRegistry.ICON_PACK_STRAWBERRY ||
      normalized === ThemeAssetRegistry.ICON_PACK_CRIMSON ||
      normalized === ThemeAssetRegistry.ICON_PACK_PLUM ||
      normalized === ThemeAssetRegistry.ICON_PACK_ROSE ||
      normalized === ThemeAssetRegistry.ICON_PACK_CRANE ||
      normalized === ThemeAssetRegistry.ICON_PACK_SWORD_FROST ||
      normalized === ThemeAssetRegistry.ICON_PACK_QINGLUAN_WATER ||
      normalized === ThemeAssetRegistry.ICON_PACK_CAT_PIPI ||
      normalized === ThemeAssetRegistry.ICON_PACK_AZURE_MECHA ||
      normalized === ThemeAssetRegistry.ICON_PACK_STARWISH_MAGIC ||
      normalized === ThemeAssetRegistry.ICON_PACK_LETTERPRESS_PAGE ||
      normalized === ThemeAssetRegistry.ICON_PACK_OBSIDIAN_ARCHIVE ||
      normalized === ThemeAssetRegistry.ICON_PACK_NEON_HARBOR ||
      normalized === ThemeAssetRegistry.ICON_PACK_CELESTIAL_VAULT) {
      return normalized;
    }
    return ThemeAssetRegistry.ICON_PACK_CLASSIC;
  }

  /** 主题包带了选中态图标；没有时底栏不必在切换页签时重设图标。 */
  static navigationHasSelectedIcons(iconPackId: string): boolean {
    const normalizedPackId = ThemeAssetRegistry.normalizeIconPackId(iconPackId);
    if (normalizedPackId === ThemeAssetRegistry.ICON_PACK_CELESTIAL_VAULT) return true;
    if (!ThemePackRegistry.isPackId(normalizedPackId)) return false;
    const pack = ThemePackRegistry.get(normalizedPackId);
    return !!pack && pack.hasAnyNavigation() && !!(pack.navBookshelfSelected || pack.navExploreSelected ||
      pack.navMineSelected || pack.navListenSelected || pack.navFootprintSelected);
  }

  /** 主题包要求底栏只显示图标。 */
  static navigationHidesLabels(iconPackId: string): boolean {
    const normalizedPackId = ThemeAssetRegistry.normalizeIconPackId(iconPackId);
    if (normalizedPackId === ThemeAssetRegistry.ICON_PACK_CELESTIAL_VAULT) return true;
    if (!ThemePackRegistry.isPackId(normalizedPackId)) return false;
    const pack = ThemePackRegistry.get(normalizedPackId);
    return !!pack && pack.hasAnyNavigation() && pack.navHideLabels;
  }

  static normalizeTabId(tabId: string): string {
    const normalized = (tabId || '').trim().toLowerCase();
    if (normalized === ThemeAssetRegistry.TAB_EXPLORE || normalized === ThemeAssetRegistry.TAB_MINE ||
      normalized === ThemeAssetRegistry.TAB_LISTEN || normalized === ThemeAssetRegistry.TAB_FOOTPRINT) {
      return normalized;
    }
    return ThemeAssetRegistry.TAB_BOOKSHELF;
  }

  private static classicNavigationIcon(tabId: string): Resource {
    switch (tabId) {
      case ThemeAssetRegistry.TAB_EXPLORE:
        return $r('app.media.ic_tab_explore');
      case ThemeAssetRegistry.TAB_LISTEN:
        return $r('app.media.ic_tab_listen');
      case ThemeAssetRegistry.TAB_FOOTPRINT:
        return $r('app.media.ic_tab_footprint');
      case ThemeAssetRegistry.TAB_MINE:
        return $r('app.media.ic_tab_mine');
      default:
        return $r('app.media.ic_tab_bookshelf');
    }
  }

  private static roundedNavigationIcon(tabId: string): Resource {
    switch (tabId) {
      case ThemeAssetRegistry.TAB_EXPLORE:
        return $r('app.media.ic_theme_rounded_explore');
      case ThemeAssetRegistry.TAB_LISTEN:
        return $r('app.media.ic_theme_rounded_listen');
      case ThemeAssetRegistry.TAB_FOOTPRINT:
        return $r('app.media.ic_theme_rounded_footprint');
      case ThemeAssetRegistry.TAB_MINE:
        return $r('app.media.ic_theme_rounded_mine');
      default:
        return $r('app.media.ic_theme_rounded_bookshelf');
    }
  }

  private static inkNavigationIcon(tabId: string): Resource {
    switch (tabId) {
      case ThemeAssetRegistry.TAB_EXPLORE:
        return $r('app.media.ic_theme_ink_explore');
      case ThemeAssetRegistry.TAB_LISTEN:
        return $r('app.media.ic_theme_ink_listen');
      case ThemeAssetRegistry.TAB_FOOTPRINT:
        return $r('app.media.ic_theme_ink_footprint');
      case ThemeAssetRegistry.TAB_MINE:
        return $r('app.media.ic_theme_ink_mine');
      default:
        return $r('app.media.ic_theme_ink_bookshelf');
    }
  }

  private static celestialNavigationIcon(tabId: string, selected: boolean): Resource {
    switch (tabId) {
      case ThemeAssetRegistry.TAB_EXPLORE: return selected ?
        $r('app.media.ic_theme_celestial_vault_explore_selected') : $r('app.media.ic_theme_celestial_vault_explore');
      case ThemeAssetRegistry.TAB_LISTEN: return selected ?
        $r('app.media.ic_theme_celestial_vault_listen_selected') : $r('app.media.ic_theme_celestial_vault_listen');
      case ThemeAssetRegistry.TAB_FOOTPRINT: return selected ?
        $r('app.media.ic_theme_celestial_vault_footprint_selected') : $r('app.media.ic_theme_celestial_vault_footprint');
      case ThemeAssetRegistry.TAB_MINE: return selected ?
        $r('app.media.ic_theme_celestial_vault_mine_selected') : $r('app.media.ic_theme_celestial_vault_mine');
      default: return selected ?
        $r('app.media.ic_theme_celestial_vault_bookshelf_selected') : $r('app.media.ic_theme_celestial_vault_bookshelf');
    }
  }

  private static themedNavigationIcon(iconPackId: string, tabId: string): Resource {
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_STRAWBERRY) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_strawberry_explore');
        case ThemeAssetRegistry.TAB_LISTEN: return $r('app.media.ic_theme_strawberry_listen');
        case ThemeAssetRegistry.TAB_FOOTPRINT: return $r('app.media.ic_theme_strawberry_footprint');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_strawberry_mine');
        default: return $r('app.media.ic_theme_strawberry_bookshelf');
      }
    }
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_CRIMSON) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_crimson_explore');
        case ThemeAssetRegistry.TAB_LISTEN: return $r('app.media.ic_theme_crimson_listen');
        case ThemeAssetRegistry.TAB_FOOTPRINT: return $r('app.media.ic_theme_crimson_footprint');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_crimson_mine');
        default: return $r('app.media.ic_theme_crimson_bookshelf');
      }
    }
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_PLUM) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_plum_explore');
        case ThemeAssetRegistry.TAB_LISTEN: return $r('app.media.ic_theme_plum_listen');
        case ThemeAssetRegistry.TAB_FOOTPRINT: return $r('app.media.ic_theme_plum_footprint');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_plum_mine');
        default: return $r('app.media.ic_theme_plum_bookshelf');
      }
    }
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_ROSE) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_rose_explore');
        case ThemeAssetRegistry.TAB_LISTEN: return $r('app.media.ic_theme_rose_listen');
        case ThemeAssetRegistry.TAB_FOOTPRINT: return $r('app.media.ic_theme_rose_footprint');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_rose_mine');
        default: return $r('app.media.ic_theme_rose_bookshelf');
      }
    }
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_SWORD_FROST) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_sword_frost_explore');
        case ThemeAssetRegistry.TAB_LISTEN: return $r('app.media.ic_theme_sword_frost_listen');
        case ThemeAssetRegistry.TAB_FOOTPRINT: return $r('app.media.ic_theme_sword_frost_footprint');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_sword_frost_mine');
        default: return $r('app.media.ic_theme_sword_frost_bookshelf');
      }
    }
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_QINGLUAN_WATER) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_qingluan_water_explore');
        case ThemeAssetRegistry.TAB_LISTEN: return $r('app.media.ic_theme_qingluan_water_listen');
        case ThemeAssetRegistry.TAB_FOOTPRINT: return $r('app.media.ic_theme_qingluan_water_footprint');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_qingluan_water_mine');
        default: return $r('app.media.ic_theme_qingluan_water_bookshelf');
      }
    }
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_CAT_PIPI) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_cat_pipi_explore');
        case ThemeAssetRegistry.TAB_LISTEN: return $r('app.media.ic_theme_cat_pipi_listen');
        case ThemeAssetRegistry.TAB_FOOTPRINT: return $r('app.media.ic_theme_cat_pipi_footprint');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_cat_pipi_mine');
        default: return $r('app.media.ic_theme_cat_pipi_bookshelf');
      }
    }
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_AZURE_MECHA) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_azure_mecha_explore');
        case ThemeAssetRegistry.TAB_LISTEN: return $r('app.media.ic_theme_azure_mecha_listen');
        case ThemeAssetRegistry.TAB_FOOTPRINT: return $r('app.media.ic_theme_azure_mecha_footprint');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_azure_mecha_mine');
        default: return $r('app.media.ic_theme_azure_mecha_bookshelf');
      }
    }
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_STARWISH_MAGIC) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_starwish_magic_explore');
        case ThemeAssetRegistry.TAB_LISTEN: return $r('app.media.ic_theme_starwish_magic_listen');
        case ThemeAssetRegistry.TAB_FOOTPRINT: return $r('app.media.ic_theme_starwish_magic_footprint');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_starwish_magic_mine');
        default: return $r('app.media.ic_theme_starwish_magic_bookshelf');
      }
    }
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_LETTERPRESS_PAGE) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_letterpress_page_explore');
        case ThemeAssetRegistry.TAB_LISTEN: return $r('app.media.ic_theme_letterpress_page_listen');
        case ThemeAssetRegistry.TAB_FOOTPRINT: return $r('app.media.ic_theme_letterpress_page_footprint');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_letterpress_page_mine');
        default: return $r('app.media.ic_theme_letterpress_page_bookshelf');
      }
    }
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_OBSIDIAN_ARCHIVE) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_obsidian_archive_explore');
        case ThemeAssetRegistry.TAB_LISTEN: return $r('app.media.ic_theme_obsidian_archive_listen');
        case ThemeAssetRegistry.TAB_FOOTPRINT: return $r('app.media.ic_theme_obsidian_archive_footprint');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_obsidian_archive_mine');
        default: return $r('app.media.ic_theme_obsidian_archive_bookshelf');
      }
    }
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_NEON_HARBOR) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_neon_harbor_explore');
        case ThemeAssetRegistry.TAB_LISTEN: return $r('app.media.ic_theme_neon_harbor_listen');
        case ThemeAssetRegistry.TAB_FOOTPRINT: return $r('app.media.ic_theme_neon_harbor_footprint');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_neon_harbor_mine');
        default: return $r('app.media.ic_theme_neon_harbor_bookshelf');
      }
    }
    switch (tabId) {
      case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_crane_explore');
      case ThemeAssetRegistry.TAB_LISTEN: return $r('app.media.ic_theme_crane_listen');
      case ThemeAssetRegistry.TAB_FOOTPRINT: return $r('app.media.ic_theme_crane_footprint');
      case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_crane_mine');
      default: return $r('app.media.ic_theme_crane_bookshelf');
    }
  }
}
