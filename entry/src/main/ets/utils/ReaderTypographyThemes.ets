import { Context } from '@kit.AbilityKit';
import { ThemeIds } from '../theme/ThemeModels';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppThemeSettingsStore } from './AppThemeSettingsStore';
import { CustomThemeScheme, CustomThemeSchemeStore } from './CustomThemeSchemeStore';
import { ReaderSettingsStore } from './ReaderSettingsStore';

export class TypographyThemeOption {
  profileId: string = '';
  name: string = '';
}

/** 阅读设置里“排版与主题”用到的主题信息：当前排版记在哪套主题、能从哪些主题复制排版。 */
export class ReaderTypographyThemes {
  static async activeThemeName(context: Context): Promise<string> {
    const themeId = AppStorage.get<string>('appThemeId') || AppThemeSettingsStore.DEFAULT_THEME_ID;
    if (themeId !== ThemeIds.CUSTOM) return BuiltinThemeRegistry.findById(themeId).name;
    const schemes = await ReaderTypographyThemes.loadSchemes(context);
    const scheme = CustomThemeSchemeStore.find(schemes, AppStorage.get<string>('activeCustomThemeSchemeId') || '');
    return scheme ? scheme.name : '自定义主题';
  }

  /** 已经有自己排版的其他主题，内置主题在前、自定义方案在后。 */
  static async copySources(context: Context): Promise<TypographyThemeOption[]> {
    const activeId = ReaderSettingsStore.activeProfileId();
    const candidates: TypographyThemeOption[] = [];
    for (const theme of BuiltinThemeRegistry.all()) {
      candidates.push(ReaderTypographyThemes.option(ReaderSettingsStore.profileIdFor(theme.id, ''), theme.name));
    }
    for (const scheme of await ReaderTypographyThemes.loadSchemes(context)) {
      candidates.push(ReaderTypographyThemes.option(
        ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, scheme.id), scheme.name));
    }
    const sources: TypographyThemeOption[] = [];
    for (const candidate of candidates) {
      if (candidate.profileId === activeId) continue;
      if (await ReaderSettingsStore.hasThemeTypography(context, candidate.profileId)) sources.push(candidate);
    }
    return sources;
  }

  static async restoreActivePreset(context: Context): Promise<void> {
    const layout = ThemeRuntime.readerLayout();
    await ReaderSettingsStore.restoreThemePreset(context, layout.fontSize, layout.lineHeight, layout.paragraphSpacing,
      layout.marginLeft, layout.marginRight, layout.marginTop, layout.marginBottom, layout.letterSpacing);
  }

  private static async loadSchemes(context: Context): Promise<CustomThemeScheme[]> {
    return await CustomThemeSchemeStore.load(context, await AppThemeSettingsStore.load(context));
  }

  private static option(profileId: string, name: string): TypographyThemeOption {
    const option = new TypographyThemeOption();
    option.profileId = profileId;
    option.name = name;
    return option;
  }
}
