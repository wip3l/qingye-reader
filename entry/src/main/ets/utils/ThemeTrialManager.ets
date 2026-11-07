import { common } from '@kit.AbilityKit';
import { AppThemeSettings, AppThemeSettingsStore } from './AppThemeSettingsStore';
import { RecentReadCardUpdater } from './RecentReadCardUpdater';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { ReaderFontBootstrap } from './ReaderFontBootstrap';
import { SuperExclusiveThemes } from '../theme/ThemeModels';

export class ThemeTrialManager {
  static readonly STORAGE_TRIAL_THEME_ID: string = 'themeTrialThemeId';
  static readonly STORAGE_TRIAL_ENDS_AT: string = 'themeTrialEndsAt';
  static readonly TRIAL_DURATION_MS: number = 5 * 60 * 1000;

  private static originalSettings: AppThemeSettings | null = null;
  private static trialContext: common.UIAbilityContext | null = null;
  private static timerId: number = -1;
  private static trialSerial: number = 0;

  static isActive(themeId: string = ''): boolean {
    const activeThemeId = AppStorage.get<string>(ThemeTrialManager.STORAGE_TRIAL_THEME_ID) || '';
    const endsAt = AppStorage.get<number>(ThemeTrialManager.STORAGE_TRIAL_ENDS_AT) || 0;
    return endsAt > Date.now() && !!activeThemeId && (!themeId || activeThemeId === themeId);
  }

  static async start(context: common.UIAbilityContext, themeId: string): Promise<void> {
    if (SuperExclusiveThemes.has(themeId)) throw new Error('终身超级会员专属主题，请先领取后使用');
    if (!ThemeTrialManager.originalSettings) {
      ThemeTrialManager.originalSettings = await AppThemeSettingsStore.load(context);
    }
    ThemeTrialManager.clearTimer();
    const serial = ++ThemeTrialManager.trialSerial;
    const endsAt = Date.now() + ThemeTrialManager.TRIAL_DURATION_MS;
    const trialSettings = AppThemeSettingsStore.activateTheme(themeId, ThemeTrialManager.originalSettings);
    const theme = BuiltinThemeRegistry.findById(themeId);
    trialSettings.themeBookCoverEnabled = !!theme.book.coverAssetId;
    ThemeTrialManager.trialContext = context;
    AppStorage.setOrCreate(ThemeTrialManager.STORAGE_TRIAL_THEME_ID, themeId);
    AppStorage.setOrCreate(ThemeTrialManager.STORAGE_TRIAL_ENDS_AT, endsAt);
    AppThemeSettingsStore.applyToStorage(trialSettings);
    ThemeTrialManager.applyThemeFont(context);
    ThemeTrialManager.refreshRecentReadCard(context);
    ThemeTrialManager.timerId = setTimeout(() => {
      if (serial !== ThemeTrialManager.trialSerial) {
        return;
      }
      ThemeTrialManager.stop(context);
    }, ThemeTrialManager.TRIAL_DURATION_MS);
  }

  static stop(context: common.UIAbilityContext): void {
    ThemeTrialManager.clearTimer();
    ThemeTrialManager.trialSerial++;
    const original = ThemeTrialManager.originalSettings;
    ThemeTrialManager.originalSettings = null;
    ThemeTrialManager.trialContext = null;
    AppStorage.setOrCreate(ThemeTrialManager.STORAGE_TRIAL_THEME_ID, '');
    AppStorage.setOrCreate(ThemeTrialManager.STORAGE_TRIAL_ENDS_AT, 0);
    if (!original) {
      return;
    }
    AppThemeSettingsStore.applyToStorage(original);
    ThemeTrialManager.applyThemeFont(context);
    ThemeTrialManager.refreshRecentReadCard(context);
  }

  static stopIfExpired(): void {
    const endsAt = AppStorage.get<number>(ThemeTrialManager.STORAGE_TRIAL_ENDS_AT) || 0;
    if (endsAt > 0 && endsAt <= Date.now() && ThemeTrialManager.trialContext) {
      ThemeTrialManager.stop(ThemeTrialManager.trialContext);
    }
  }

  private static clearTimer(): void {
    if (ThemeTrialManager.timerId >= 0) {
      clearTimeout(ThemeTrialManager.timerId);
      ThemeTrialManager.timerId = -1;
    }
  }

  private static applyThemeFont(context: common.UIAbilityContext): void {
    ReaderFontBootstrap.applyApplicationFont(context, 'theme-trial');
  }

  private static refreshRecentReadCard(context: common.UIAbilityContext): void {
    RecentReadCardUpdater.reload(context).catch((e: Error) => {
      console.warn('试用主题切换后刷新最近阅读卡片失败:', e);
    });
  }
}
