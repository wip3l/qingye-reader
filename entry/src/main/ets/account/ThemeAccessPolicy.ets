import { AccountSessionStore } from './AccountSessionStore';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { SuperExclusiveThemes, ThemeIds } from '../theme/ThemeModels';
import { ThemePackRegistry } from '../theme/ThemePackRegistry';

export class ThemeAccessPolicy {
  static hasThemeAccess(themeId: string): boolean {
    const normalized = (themeId || '').trim();
    if (!normalized || normalized === ThemeIds.CUSTOM) {
      return true;
    }
    if (BuiltinThemeRegistry.isFree(normalized)) {
      return true;
    }
    // 已安装的主题包随方案走，不另设权益；缺包时按默认主题显示。
    if (ThemePackRegistry.isPackId(normalized)) {
      return ThemePackRegistry.has(normalized);
    }
    if (SuperExclusiveThemes.has(normalized)) return AccountSessionStore.hasOwnedEntitlement(normalized);
    const activeThemeId = AppStorage.get<string>('appThemeId') || '';
    // The currently applied theme must retain its complete runtime appearance,
    // including during a timed trial. Theme selection and component-source
    // screens perform their own entitlement checks, so this does not grant
    // ownership of the trial theme.
    return activeThemeId === normalized || AccountSessionStore.hasValidEntitlement(normalized);
  }

  static requiredThemeForBubbleStyle(styleId: string): string {
    const normalized = (styleId || '').trim();
    if (ThemePackRegistry.isPackId(normalized)) return '';
    if (normalized === 'classic-glass') return ThemeIds.CLASSIC_BLUE;
    if (normalized === 'warm-scroll') return ThemeIds.WARM_PAPER;
    if (normalized === 'forest-dew') return ThemeIds.FOREST_MIST;
    if (normalized === 'ink-brush') return ThemeIds.INK_WASH;
    if (normalized === 'neon-pulse') return ThemeIds.NEON_NIGHT;
    if (normalized === 'strawberry-ribbon') return ThemeIds.STRAWBERRY_CREAM;
    if (normalized === 'crimson-stamp') return ThemeIds.CRIMSON_ARCHIVE;
    if (normalized === 'celadon-slip') return ThemeIds.PLUM_TEA;
    if (normalized === 'rose-frame') return ThemeIds.ROSE_LETTER;
    if (normalized === 'moon-halo') return ThemeIds.MOON_CRANE;
    if (normalized === 'sword-talisman') return ThemeIds.SWORD_FROST;
    if (normalized === 'qingluan-jade') return ThemeIds.QINGLUAN_WATER;
    if (normalized === 'pipi-soft-paw') return ThemeIds.CAT_PIPI;
    if (normalized === 'mecha-comm') return ThemeIds.AZURE_MECHA;
    if (normalized === 'starwish-ribbon') return ThemeIds.STARWISH_MAGIC;
    if (normalized === 'pencil-mark') return ThemeIds.LETTERPRESS_PAGE;
    if (normalized === 'gilded-orbit') return ThemeIds.OBSIDIAN_ARCHIVE;
    if (normalized === 'harbor-postcard') return ThemeIds.NEON_HARBOR;
    if (normalized === 'celestial-orbit') return ThemeIds.CELESTIAL_VAULT;
    return '';
  }

  static canUseBubbleStyle(styleId: string): boolean {
    const normalized = (styleId || '').trim();
    if (ThemePackRegistry.isPackId(normalized)) {
      const pack = ThemePackRegistry.get(normalized);
      return !!pack && pack.hasBubble();
    }
    const requiredThemeId = ThemeAccessPolicy.requiredThemeForBubbleStyle(styleId);
    return !requiredThemeId || ThemeAccessPolicy.hasThemeAccess(requiredThemeId);
  }

  static accessibleBubbleStyle(styleId: string, inheritedStyleId: string = 'qq-soft'): string {
    const normalized = (styleId || '').trim() || 'qq-soft';
    if (ThemeAccessPolicy.canUseBubbleStyle(normalized)) {
      return normalized;
    }
    const inherited = (inheritedStyleId || '').trim() || 'qq-soft';
    if (ThemeAccessPolicy.canUseBubbleStyle(inherited)) {
      return inherited;
    }
    return 'qq-soft';
  }

  static requiredThemeNameForBubbleStyle(styleId: string): string {
    const themeId = ThemeAccessPolicy.requiredThemeForBubbleStyle(styleId);
    return themeId ? BuiltinThemeRegistry.findById(themeId).name : '';
  }
}
