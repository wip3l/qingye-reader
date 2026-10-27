import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { readStatsTracker } from '../core/stats/ReadStatsTracker';
import {
  AccountSnapshot,
  HuaweiLoginResponse,
  ThemeEntitlement
} from './AccountCommerceModels';

export class AccountSessionStore {
  static readonly STORAGE_LOGGED_IN: string = 'accountLoggedIn';
  static readonly STORAGE_DISPLAY_NAME: string = 'accountDisplayName';
  static readonly STORAGE_AVATAR_URL: string = 'accountAvatarUrl';
  static readonly STORAGE_POINTS: string = 'accountPoints';
  static readonly STORAGE_PAID_POINTS: string = 'accountPaidPoints';
  static readonly STORAGE_PROMO_POINTS: string = 'accountPromoPoints';
  static readonly STORAGE_ENTITLEMENTS_REVISION: string = 'accountEntitlementsRevision';

  private static readonly STORE_NAME: string = 'account_commerce_session';
  private static readonly KEY_SESSION_TOKEN: string = 'session_token';
  private static readonly KEY_ACCOUNT_SNAPSHOT: string = 'account_snapshot';
  private static sessionToken: string = '';
  private static snapshot: AccountSnapshot = new AccountSnapshot();
  private static loaded: boolean = false;

  static initializeStorage(): void {
    AppStorage.setOrCreate(AccountSessionStore.STORAGE_LOGGED_IN, false);
    AppStorage.setOrCreate(AccountSessionStore.STORAGE_DISPLAY_NAME, '');
    AppStorage.setOrCreate(AccountSessionStore.STORAGE_AVATAR_URL, '');
    AppStorage.setOrCreate(AccountSessionStore.STORAGE_POINTS, 0);
    AppStorage.setOrCreate(AccountSessionStore.STORAGE_PAID_POINTS, 0);
    AppStorage.setOrCreate(AccountSessionStore.STORAGE_PROMO_POINTS, 0);
    AppStorage.setOrCreate(AccountSessionStore.STORAGE_ENTITLEMENTS_REVISION, 0);
  }

  static async load(context: Context): Promise<void> {
    AccountSessionStore.initializeStorage();
    if (AccountSessionStore.loaded) {
      AccountSessionStore.applyToStorage();
      return;
    }
    const store = await preferences.getPreferences(context, AccountSessionStore.STORE_NAME);
    AccountSessionStore.sessionToken =
      (await store.get(AccountSessionStore.KEY_SESSION_TOKEN, '')) as string;
    const snapshotRaw = (await store.get(AccountSessionStore.KEY_ACCOUNT_SNAPSHOT, '')) as string;
    AccountSessionStore.snapshot = AccountSessionStore.parseSnapshot(snapshotRaw);
    AccountSessionStore.loaded = true;
    AccountSessionStore.applyToStorage();
  }

  static async saveLogin(context: Context, response: HuaweiLoginResponse): Promise<void> {
    AccountSessionStore.sessionToken = response.sessionToken || '';
    AccountSessionStore.snapshot = AccountSessionStore.normalizeSnapshot(response.account);
    AccountSessionStore.loaded = true;
    await AccountSessionStore.persist(context);
    AccountSessionStore.applyToStorage();
  }

  static async updateSnapshot(context: Context, snapshot: AccountSnapshot): Promise<void> {
    AccountSessionStore.snapshot = AccountSessionStore.normalizeSnapshot(snapshot);
    AccountSessionStore.loaded = true;
    await AccountSessionStore.persist(context);
    AccountSessionStore.applyToStorage();
  }

  static async updateSessionToken(context: Context, expectedToken: string, sessionToken: string): Promise<boolean> {
    if (!sessionToken) {
      throw new Error('续签接口未返回登录凭证');
    }
    if (!expectedToken || AccountSessionStore.sessionToken !== expectedToken) {
      return false;
    }
    AccountSessionStore.sessionToken = sessionToken;
    const store = await preferences.getPreferences(context, AccountSessionStore.STORE_NAME);
    await store.put(AccountSessionStore.KEY_SESSION_TOKEN, sessionToken);
    await store.flush();
    AccountSessionStore.applyToStorage();
    return true;
  }

  static async clear(context: Context): Promise<void> {
    AccountSessionStore.sessionToken = '';
    AccountSessionStore.snapshot = new AccountSnapshot();
    AccountSessionStore.loaded = true;
    const store = await preferences.getPreferences(context, AccountSessionStore.STORE_NAME);
    await store.delete(AccountSessionStore.KEY_SESSION_TOKEN);
    await store.delete(AccountSessionStore.KEY_ACCOUNT_SNAPSHOT);
    await store.flush();
    AccountSessionStore.applyToStorage();
  }

  static isLoggedIn(): boolean {
    return AccountSessionStore.sessionToken.length > 0 &&
      AccountSessionStore.snapshot.userId.length > 0;
  }

  static token(): string {
    return AccountSessionStore.sessionToken;
  }

  static account(): AccountSnapshot {
    return AccountSessionStore.normalizeSnapshot(AccountSessionStore.snapshot);
  }

  static entitlement(themeId: string): ThemeEntitlement | null {
    for (const entitlement of AccountSessionStore.snapshot.entitlements) {
      if (entitlement.themeId === themeId) {
        const result = new ThemeEntitlement();
        result.themeId = entitlement.themeId;
        result.expiresAt = entitlement.expiresAt;
        return result;
      }
    }
    return null;
  }

  static hasValidEntitlement(themeId: string, now: number = Date.now()): boolean {
    return AccountSessionStore.hasOwnedEntitlement(themeId, now) ||
      AccountSessionStore.hasMemberThemeAccess(themeId, now);
  }

  /** 当前有效会员档位；未登录、欠款暂停或按服务端时间推算已到期时为空。 */
  static activeMembershipSku(now: number = Date.now()): string {
    const account = AccountSessionStore.snapshot;
    const membership = account.membership;
    if (!AccountSessionStore.isLoggedIn() || !membership?.active || membership.restricted ||
      account.iapDebtPoints > 0 || !membership.state) {
      return '';
    }
    const elapsed = Math.max(0, now - account.memberVerifiedAt);
    const expiresAt = membership.state.expiresAt;
    return expiresAt === null || expiresAt > membership.serverNow + elapsed ?
      (membership.tierSku || membership.state.sku) : '';
  }

  /** Owned themes; the exclusive annual grant additionally requires super membership. */
  static hasOwnedEntitlement(themeId: string, now: number = Date.now()): boolean {
    const entitlement = AccountSessionStore.entitlement(themeId);
    if (themeId === 'obsidian-archive') {
      const account = AccountSessionStore.snapshot;
      const elapsed = now - account.memberVerifiedAt;
      if (AccountSessionStore.activeMembershipSku(now) !== 'SUPER_LIFETIME' || elapsed < 0 || !account.membership) return false;
      return entitlement !== null && entitlement.expiresAt > account.membership.serverNow + elapsed;
    }
    return entitlement !== null && entitlement.expiresAt > now;
  }

  static hasMemberThemeAccess(themeId: string, now: number = Date.now()): boolean {
    // This theme requires an explicit annual claim, never the general member theme library.
    if (themeId === 'obsidian-archive') return false;
    const account = AccountSessionStore.snapshot;
    const membership = account.membership;
    const elapsed = now - account.memberVerifiedAt;
    if (!AccountSessionStore.isLoggedIn() || !membership?.active || membership.restricted ||
      account.iapDebtPoints > 0 || !membership.state || elapsed < 0 || elapsed > 72 * 60 * 60 * 1000) {
      return false;
    }
    const serverNow = membership.serverNow + elapsed;
    return (membership.state.expiresAt === null || membership.state.expiresAt > serverNow) &&
      account.memberThemeIds.includes(themeId);
  }

  private static async persist(context: Context): Promise<void> {
    const store = await preferences.getPreferences(context, AccountSessionStore.STORE_NAME);
    await store.put(AccountSessionStore.KEY_SESSION_TOKEN, AccountSessionStore.sessionToken);
    await store.put(AccountSessionStore.KEY_ACCOUNT_SNAPSHOT, JSON.stringify(AccountSessionStore.snapshot));
    await store.flush();
  }

  private static applyToStorage(): void {
    readStatsTracker.setOwnerId(AccountSessionStore.isLoggedIn() ? AccountSessionStore.snapshot.userId : '');
    AccountSessionStore.initializeStorage();
    AppStorage.setOrCreate(AccountSessionStore.STORAGE_LOGGED_IN, AccountSessionStore.isLoggedIn());
    const membershipSku = AccountSessionStore.activeMembershipSku();
    AppStorage.setOrCreate('accountMembershipSku', membershipSku);
    // 0 表示永久；未开通时同样为 0，需结合档位判断。
    AppStorage.setOrCreate('accountMembershipExpiresAt',
      membershipSku ? AccountSessionStore.snapshot.membership?.state?.expiresAt ?? 0 : 0);
    AppStorage.setOrCreate(AccountSessionStore.STORAGE_DISPLAY_NAME,
      AccountSessionStore.isLoggedIn() ? AccountSessionStore.snapshot.displayName : '');
    AppStorage.setOrCreate(AccountSessionStore.STORAGE_AVATAR_URL,
      AccountSessionStore.isLoggedIn() ? AccountSessionStore.snapshot.avatarUrl : '');
    AppStorage.setOrCreate(AccountSessionStore.STORAGE_POINTS,
      AccountSessionStore.isLoggedIn() ? AccountSessionStore.snapshot.points : 0);
    AppStorage.setOrCreate(AccountSessionStore.STORAGE_PAID_POINTS,
      AccountSessionStore.isLoggedIn() ? AccountSessionStore.snapshot.paidPoints : 0);
    AppStorage.setOrCreate(AccountSessionStore.STORAGE_PROMO_POINTS,
      AccountSessionStore.isLoggedIn() ? AccountSessionStore.snapshot.promoPoints : 0);
    const revision = (AppStorage.get<number>(AccountSessionStore.STORAGE_ENTITLEMENTS_REVISION) || 0) + 1;
    AppStorage.setOrCreate(AccountSessionStore.STORAGE_ENTITLEMENTS_REVISION, revision);
  }

  private static parseSnapshot(raw: string): AccountSnapshot {
    if (!raw) {
      return new AccountSnapshot();
    }
    try {
      return AccountSessionStore.normalizeSnapshot(JSON.parse(raw) as AccountSnapshot);
    } catch (e) {
      return new AccountSnapshot();
    }
  }

  static normalizeSnapshot(source: AccountSnapshot | null | undefined): AccountSnapshot {
    const result = new AccountSnapshot();
    if (!source) {
      return result;
    }
    result.userId = source.userId || '';
    result.displayName = source.displayName || '华为用户';
    result.avatarUrl = source.avatarUrl || '';
    result.points = Math.max(0, Math.floor(Number(source.points) || 0));
    result.paidPoints = Math.max(0, Math.floor(Number(source.paidPoints) || 0));
    result.promoPoints = Math.max(0, Math.floor(Number(source.promoPoints) || 0));
    result.iapDebtPoints = Math.max(0, Math.floor(Number(source.iapDebtPoints) || 0));
    result.welcomeGranted = source.welcomeGranted === true;
    result.membership = source.membership || null;
    result.memberThemeIds = source.memberThemeIds || [];
    result.memberVerifiedAt = Number(source.memberVerifiedAt) || 0;
    result.entitlements = [];
    if (source.entitlements) {
      for (const item of source.entitlements) {
        if (!item || !item.themeId) {
          continue;
        }
        const entitlement = new ThemeEntitlement();
        entitlement.themeId = item.themeId;
        entitlement.expiresAt = Number(item.expiresAt) || 0;
        result.entitlements.push(entitlement);
      }
    }
    return result;
  }
}
