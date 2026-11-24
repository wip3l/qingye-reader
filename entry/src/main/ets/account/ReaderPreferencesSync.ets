import { ReaderRegexFontCodec, ReaderRegexLegacySettings } from '../model/reader/ReaderRegexFontRule';
import { ReaderSettings } from '../utils/ReaderSettingsStore';

/**
 * 阅读偏好只同步字体规则、配色和“排版跟随主题”开关；设备排版、全局字体与交互设置始终留在本机。
 * 旧版本上传的数据没有开关字段，读取时保留本机值。
 */
export class ReaderPreferencesSyncPayload {
  syncVersion: number = 2;
  typographyFollowsTheme?: boolean;
  regexFontEnabled: boolean = false;
  regexFontPattern: string = '';
  regexFontMode: string = '';
  regexFontFamily: string = '';
  regexFontSize: number = 0;
  regexShadowColor: string = '';
  regexFontRulesRaw: string = '';
  lightThemeIndex: number = 0;
  darkThemeIndex: number = 0;
  lightCustomThemeBackgroundColor: string = '';
  lightCustomThemeTextColor: string = '';
  darkCustomThemeBackgroundColor: string = '';
  darkCustomThemeTextColor: string = '';
  customThemesRaw: string = '';
}

export class ReaderPreferencesSync {
  static toPayload(settings: ReaderSettings): ReaderPreferencesSyncPayload {
    const payload = new ReaderPreferencesSyncPayload();
    payload.regexFontEnabled = settings.regexFontEnabled;
    payload.regexFontPattern = settings.regexFontPattern;
    payload.regexFontMode = settings.regexFontMode;
    payload.regexFontFamily = settings.regexFontFamily;
    payload.regexFontSize = settings.regexFontSize;
    payload.regexShadowColor = settings.regexShadowColor;
    payload.regexFontRulesRaw = settings.regexFontRulesRaw;
    payload.lightThemeIndex = settings.lightThemeIndex;
    payload.darkThemeIndex = settings.darkThemeIndex;
    payload.lightCustomThemeBackgroundColor = settings.lightCustomThemeBackgroundColor;
    payload.lightCustomThemeTextColor = settings.lightCustomThemeTextColor;
    payload.darkCustomThemeBackgroundColor = settings.darkCustomThemeBackgroundColor;
    payload.darkCustomThemeTextColor = settings.darkCustomThemeTextColor;
    payload.customThemesRaw = settings.customThemesRaw;
    return payload;
  }

  /** 兼容旧版完整设置，只读取允许同步的字段，忽略其中的设备排版参数。 */
  static merge(local: ReaderSettings, remote: ReaderPreferencesSyncPayload): ReaderSettings {
    const merged = JSON.parse(JSON.stringify(local)) as ReaderSettings;
    // 远端一条规则都没有而本机有时，整组正则规则（含总开关）留本机：上传那台设备当时可能在用别的主题档案，
    // 空规则覆盖下来会把本机规则全清掉。代价是“删光所有规则”不会同步到别的设备。
    if (!ReaderPreferencesSync.remoteDropsLocalRules(local, remote)) {
      if (typeof remote.regexFontEnabled === 'boolean') merged.regexFontEnabled = remote.regexFontEnabled;
      if (typeof remote.regexFontPattern === 'string') merged.regexFontPattern = remote.regexFontPattern;
      if (typeof remote.regexFontMode === 'string') merged.regexFontMode = remote.regexFontMode;
      if (typeof remote.regexFontFamily === 'string') merged.regexFontFamily = remote.regexFontFamily;
      if (typeof remote.regexFontSize === 'number') merged.regexFontSize = remote.regexFontSize;
      if (typeof remote.regexShadowColor === 'string') merged.regexShadowColor = remote.regexShadowColor;
      if (typeof remote.regexFontRulesRaw === 'string') merged.regexFontRulesRaw = remote.regexFontRulesRaw;
    }
    if (typeof remote.lightThemeIndex === 'number') merged.lightThemeIndex = remote.lightThemeIndex;
    if (typeof remote.darkThemeIndex === 'number') merged.darkThemeIndex = remote.darkThemeIndex;
    if (typeof remote.lightCustomThemeBackgroundColor === 'string') merged.lightCustomThemeBackgroundColor = remote.lightCustomThemeBackgroundColor;
    if (typeof remote.lightCustomThemeTextColor === 'string') merged.lightCustomThemeTextColor = remote.lightCustomThemeTextColor;
    if (typeof remote.darkCustomThemeBackgroundColor === 'string') merged.darkCustomThemeBackgroundColor = remote.darkCustomThemeBackgroundColor;
    if (typeof remote.darkCustomThemeTextColor === 'string') merged.darkCustomThemeTextColor = remote.darkCustomThemeTextColor;
    if (typeof remote.customThemesRaw === 'string') merged.customThemesRaw = remote.customThemesRaw;
    return merged;
  }

  /** 远端解析不出任何规则（含旧版单条正则），本机却有规则。 */
  private static remoteDropsLocalRules(local: ReaderSettings, remote: ReaderPreferencesSyncPayload): boolean {
    const remoteLegacy = new ReaderRegexLegacySettings();
    remoteLegacy.pattern = typeof remote.regexFontPattern === 'string' ? remote.regexFontPattern : '';
    const remoteRaw = typeof remote.regexFontRulesRaw === 'string' ? remote.regexFontRulesRaw : '';
    if (ReaderRegexFontCodec.decode(remoteRaw, remoteLegacy).length > 0) return false;
    const localLegacy = new ReaderRegexLegacySettings();
    localLegacy.pattern = local.regexFontPattern || '';
    return ReaderRegexFontCodec.decode(local.regexFontRulesRaw || '', localLegacy).length > 0;
  }
}
