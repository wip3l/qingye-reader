import { common } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { AccountSessionStore } from './AccountSessionStore';
import { AccountCommerceApi } from './AccountCommerceApi';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { SuperExclusiveThemes, ThemeIds } from '../theme/ThemeModels';
import { AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { ThemeTrialManager } from '../utils/ThemeTrialManager';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { AppIconManager } from '../utils/AppIconManager';

export class MembershipThemeGuard {
  private static readonly STORE_NAME: string = 'membership_theme_guard';
  private static readonly KEY_GRANTED_THEME: string = 'memberGrantedThemeId';
  private static checking: boolean = false;
  private static lastRefreshAttempt: number = 0;
  static async refresh(context: common.UIAbilityContext): Promise<void> {
    if (MembershipThemeGuard.checking || ThemeTrialManager.isActive()) return;
    MembershipThemeGuard.checking = true;
    try {
      const account = AccountSessionStore.account();
      if (AccountSessionStore.isLoggedIn() && account.membership?.state &&
        Date.now() - account.memberVerifiedAt > 6 * 60 * 60 * 1000 &&
        Date.now() - MembershipThemeGuard.lastRefreshAttempt > 15 * 60 * 1000) {
        MembershipThemeGuard.lastRefreshAttempt = Date.now();
        try {
          const latest = await AccountCommerceApi.fetchAccount(AccountSessionStore.token());
          if (AccountSessionStore.account().userId === account.userId) await AccountSessionStore.updateSnapshot(context, latest);
        } catch (_) { /* Keep the bounded offline grant when the network is unavailable. */ }
      }
      const settings = await AppThemeSettingsStore.load(context);
      // A trial can start while the account request or settings load is pending.
      // Its own expiry manager restores the previous theme when the trial ends.
      if (ThemeTrialManager.isActive()) return;
      const themeId = settings.themeId;
      const store = await preferences.getPreferences(context, MembershipThemeGuard.STORE_NAME);
      const marked = await store.get(MembershipThemeGuard.KEY_GRANTED_THEME, '') as string;
      // 专属主题逐套看：直接应用的、自定义方案底子或部件用到的，任一套没有领取记录就撤下。
      const usedExclusive = themeId === ThemeIds.CUSTOM ? SuperExclusiveThemes.usedByScheme(
        settings.customBaseThemeId, settings.customLightSources, settings.customDarkSources) :
        (SuperExclusiveThemes.has(themeId) ? [themeId] : []);
      const withdrawExclusive = usedExclusive.some((id: string) => !AccountSessionStore.hasOwnedEntitlement(id));
      const iconId = AppStorage.get<string>('appIconId') || '';
      const iconTheme = SuperExclusiveThemes.IDS.find((id: string) => SuperExclusiveThemes.appIconId(id) === iconId);
      if (iconTheme && !AccountSessionStore.hasOwnedEntitlement(iconTheme)) {
        await AppIconManager.applyIcon(context, AppIconManager.optionById('default')).catch(() => {});
      }
      if (!withdrawExclusive && (!themeId || themeId === ThemeIds.CUSTOM || BuiltinThemeRegistry.isFree(themeId) ||
        AccountSessionStore.hasOwnedEntitlement(themeId) || AccountSessionStore.hasMemberThemeAccess(themeId))) {
        // Remember themes that are in use only through membership; everything else clears the mark.
        const next = AccountSessionStore.hasMemberThemeAccess(themeId) &&
          !AccountSessionStore.hasOwnedEntitlement(themeId) ? themeId : '';
        if (next !== marked) {
          await store.put(MembershipThemeGuard.KEY_GRANTED_THEME, next);
          await store.flush();
        }
        return;
      }
      // Withdraw only a theme this guard saw granted by membership. Other active themes keep the
      // long-standing ThemeAccessPolicy behavior (e.g. a separately bought theme after logout).
      if (marked !== themeId && !withdrawExclusive) return;
      const fallback = AppThemeSettingsStore.activateTheme(AppThemeSettingsStore.DEFAULT_THEME_ID, settings);
      await AppThemeSettingsStore.save(context, fallback);
      AppThemeSettingsStore.applyToStorage(fallback);
      await store.put(MembershipThemeGuard.KEY_GRANTED_THEME, '');
      await store.flush();
      ReaderFontBootstrap.applyApplicationFont(context, 'membership-expired');
    } finally { MembershipThemeGuard.checking = false; }
  }
}
