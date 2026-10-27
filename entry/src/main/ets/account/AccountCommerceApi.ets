import http from '@ohos.net.http';
import { ReadStatsSyncRequest, ReadStatsSyncResponse } from '../core/stats/ReadStatsSyncModels';
import { util } from '@kit.ArkTS';
import { AccountCommerceConfig } from './AccountCommerceConfig';
import { MembershipCatalog, MembershipQuote, MembershipSnapshot, MembershipOrderList } from './MembershipModels';
import { SuperThemeClaimResponse } from './AccountCommerceModels';
import {
  AccountApiError,
  AvatarCrop,
  AccountSnapshot,
  HuaweiLoginResponse,
  IapCreditResponse,
  SessionRenewResponse,
  ThemeCatalogResponse,
  TtsCatalogResponse,
  TtsPackageRedeemResponse,
  TtsWalletSnapshot
} from './AccountCommerceModels';
import {
  CloudSyncDeviceListResponse,
  CloudSyncExchangeRequest,
  CloudSyncExchangeResponse,
  CloudSyncSummary
} from './CloudSyncModels';

class ApiErrorBody {
  code: string = '';
  message: string = '';
  retryAfter: number = 0;
}

export class MembershipPurchaseResponse {
  account: AccountSnapshot = new AccountSnapshot();
  membership: MembershipSnapshot = new MembershipSnapshot();
  orderId: string = '';
}

export class MembershipGiftResponse {
  membership: MembershipSnapshot = new MembershipSnapshot();
  ttsWallet: TtsWalletSnapshot = new TtsWalletSnapshot();
}

export class AccountCommerceApi {
  static colorModelTicket(file: string, token: string): Promise<string> {
    return AccountCommerceApi.request(`/v1/ai/color-models/${encodeURIComponent(file)}/download-ticket`, 'POST', '{}', token);
  }
  static async membershipOrders(token: string): Promise<MembershipOrderList> {
    return JSON.parse(await AccountCommerceApi.request('/v1/membership/orders', 'GET', '', token)) as MembershipOrderList;
  }
  static async cloudRequest(path: string, method: string, body: string, token: string): Promise<string> {
    return AccountCommerceApi.request(`/v1/cloud-files${path}`, method, body, token);
  }
  static async fetchMembershipCatalog(token: string = ''): Promise<MembershipCatalog> {
    if (token) {
      try {
        return JSON.parse(await AccountCommerceApi.request('/v1/membership/catalog/account', 'GET', '', token)) as MembershipCatalog;
      } catch (error) {
        // Older servers only expose the public catalog; never hide authentication or network errors.
        if ((error as AccountApiError).statusCode !== 404) throw error as Error;
      }
    }
    return JSON.parse(await AccountCommerceApi.request('/v1/membership/catalog', 'GET', '', '')) as MembershipCatalog;
  }

  static async fetchMembership(token: string): Promise<MembershipSnapshot> {
    return JSON.parse(await AccountCommerceApi.request('/v1/membership', 'GET', '', token)) as MembershipSnapshot;
  }

  static async quoteMembership(sku: string, token: string): Promise<MembershipQuote> {
    return JSON.parse(await AccountCommerceApi.request('/v1/membership/quote', 'POST',
      JSON.stringify({ sku: sku }), token)) as MembershipQuote;
  }

  static async purchaseMembership(quoteId: string, requestId: string, token: string): Promise<MembershipPurchaseResponse> {
    const raw = JSON.parse(await AccountCommerceApi.request('/v1/membership/purchase', 'POST',
      JSON.stringify({ quoteId: quoteId, requestId: requestId }), token)) as MembershipPurchaseResponse;
    raw.account = AccountCommerceApi.normalizeAccount(raw.account);
    return raw;
  }

  static async claimMembershipGift(tier: string, token: string): Promise<MembershipGiftResponse> {
    return JSON.parse(await AccountCommerceApi.request('/v1/membership/gift', 'POST',
      JSON.stringify({ tier: tier }), token)) as MembershipGiftResponse;
  }
  static async login(authorizationCode: string): Promise<HuaweiLoginResponse> {
    const value = await AccountCommerceApi.request('/v1/auth/huawei', 'POST',
      JSON.stringify({ authorizationCode: authorizationCode }), '');
    const response = JSON.parse(value) as HuaweiLoginResponse;
    response.account = AccountCommerceApi.normalizeAccount(response.account);
    return response;
  }

  static async fetchAccount(sessionToken: string): Promise<AccountSnapshot> {
    const value = await AccountCommerceApi.request('/v1/me', 'GET', '', sessionToken);
    return AccountCommerceApi.normalizeAccount(JSON.parse(value) as AccountSnapshot);
  }

  static async renewSession(sessionToken: string): Promise<SessionRenewResponse> {
    const value = await AccountCommerceApi.request('/v1/auth/renew', 'POST', '{}', sessionToken);
    const raw = JSON.parse(value) as SessionRenewResponse;
    const response = new SessionRenewResponse();
    response.sessionToken = raw.sessionToken || '';
    response.expiresAt = Math.max(0, Math.floor(Number(raw.expiresAt) || 0));
    if (!response.sessionToken || response.expiresAt <= 0) {
      throw new AccountApiError('账号续签响应格式异常', 502, 'INVALID_SESSION_RENEW_RESPONSE');
    }
    return response;
  }

  static async logout(sessionToken: string): Promise<void> {
    await AccountCommerceApi.request('/v1/auth/logout', 'POST', '{}', sessionToken);
  }

  static async updateProfile(displayName: string, avatarBase64: string, removeAvatar: boolean,
    sessionToken: string, avatarCrop: AvatarCrop | null = null): Promise<AccountSnapshot> {
    const value = await AccountCommerceApi.request('/v1/me/profile', 'POST',
      JSON.stringify({
        displayName: displayName,
        avatarBase64: avatarBase64,
        avatarCrop: avatarCrop,
        removeAvatar: removeAvatar
      }), sessionToken);
    return AccountCommerceApi.normalizeAccount(JSON.parse(value) as AccountSnapshot);
  }

  static async redeemTheme(themeId: string, requestId: string, expectedPricePoints: number,
    expectedValidDays: number,
    sessionToken: string): Promise<AccountSnapshot> {
    const value = await AccountCommerceApi.request(`/v1/themes/${encodeURIComponent(themeId)}/redeem`,
      'POST', JSON.stringify({
        requestId: requestId,
        expectedPricePoints: expectedPricePoints,
        expectedValidDays: expectedValidDays
      }), sessionToken);
    return AccountCommerceApi.normalizeAccount(JSON.parse(value) as AccountSnapshot);
  }

  static async fetchThemeCatalog(): Promise<ThemeCatalogResponse> {
    const value = await AccountCommerceApi.request('/v1/themes/catalog', 'GET', '', '');
    return JSON.parse(value) as ThemeCatalogResponse;
  }

  static async claimSuperTheme(themeId: string, requestId: string, token: string): Promise<SuperThemeClaimResponse> {
    const value = await AccountCommerceApi.request(`/v1/membership/themes/${encodeURIComponent(themeId)}/claim`,
      'POST', JSON.stringify({ requestId: requestId }), token);
    const response = JSON.parse(value) as SuperThemeClaimResponse;
    response.account = AccountCommerceApi.normalizeAccount(response.account);
    return response;
  }

  static async creditIapPurchase(purchaseData: string, sessionToken: string): Promise<IapCreditResponse> {
    const value = await AccountCommerceApi.request('/v1/iap/credit', 'POST',
      JSON.stringify({ purchaseData: purchaseData }), sessionToken);
    const response = JSON.parse(value) as IapCreditResponse;
    response.account = AccountCommerceApi.normalizeAccount(response.account);
    return response;
  }

  static async fetchTtsCatalog(): Promise<TtsCatalogResponse> {
    const value = await AccountCommerceApi.request('/v1/tts/catalog', 'GET', '', '');
    return JSON.parse(value) as TtsCatalogResponse;
  }

  static async fetchTtsWallet(sessionToken: string): Promise<TtsWalletSnapshot> {
    const value = await AccountCommerceApi.request(
      `/v1/tts/wallet?refresh=${Date.now()}`,
      'GET',
      '',
      sessionToken
    );
    return AccountCommerceApi.parseTtsWalletText(value);
  }

  static async redeemTtsPackage(sku: string, requestId: string,
    sessionToken: string): Promise<TtsPackageRedeemResponse> {
    const value = await AccountCommerceApi.request(
      `/v1/tts/packages/${encodeURIComponent(sku)}/redeem`,
      'POST',
      JSON.stringify({ requestId: requestId }),
      sessionToken
    );
    const raw = JSON.parse(value) as TtsPackageRedeemResponse;
    const response = new TtsPackageRedeemResponse();
    response.account = AccountCommerceApi.normalizeAccount(raw.account);
    response.ttsWallet = AccountCommerceApi.normalizeTtsWallet(raw.ttsWallet);
    return response;
  }

  static async exchangeSync(request: CloudSyncExchangeRequest,
    sessionToken: string): Promise<CloudSyncExchangeResponse> {
    const value = await AccountCommerceApi.request(
      '/v1/sync/exchange',
      'POST',
      JSON.stringify(request),
      sessionToken
    );
    return JSON.parse(value) as CloudSyncExchangeResponse;
  }

  static async exchangeReadStats(request: ReadStatsSyncRequest,
    sessionToken: string): Promise<ReadStatsSyncResponse> {
    const value = await AccountCommerceApi.request('/v1/sync/reading-stats', 'POST',
      JSON.stringify(request), sessionToken);
    return JSON.parse(value) as ReadStatsSyncResponse;
  }

  static async fetchSyncDevices(sessionToken: string): Promise<CloudSyncDeviceListResponse> {
    const value = await AccountCommerceApi.request('/v1/sync/devices', 'GET', '', sessionToken);
    return JSON.parse(value) as CloudSyncDeviceListResponse;
  }

  static async fetchSyncSummary(sessionToken: string): Promise<CloudSyncSummary> {
    const value = await AccountCommerceApi.request('/v1/sync/summary', 'GET', '', sessionToken);
    return JSON.parse(value) as CloudSyncSummary;
  }

  static async renameSyncDevice(deviceId: string, deviceName: string, sessionToken: string): Promise<void> {
    await AccountCommerceApi.request(
      `/v1/sync/devices/${encodeURIComponent(deviceId)}/rename`,
      'POST',
      JSON.stringify({ deviceName: deviceName }),
      sessionToken
    );
  }

  static async revokeSyncDevice(deviceId: string, sessionToken: string): Promise<void> {
    await AccountCommerceApi.request(
      `/v1/sync/devices/${encodeURIComponent(deviceId)}/revoke`,
      'POST',
      '{}',
      sessionToken
    );
  }

  private static async request(path: string, method: string, body: string, sessionToken: string): Promise<string> {
    if (!AccountCommerceConfig.isServerConfigured()) {
      throw new AccountApiError('账号服务端尚未配置', 0, 'SERVER_NOT_CONFIGURED');
    }
    const client = http.createHttp();
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'Content-Type': 'application/json;charset=UTF-8',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache'
    };
    if (sessionToken) {
      headers['Authorization'] = `Bearer ${sessionToken}`;
    }
    try {
      const response = await client.request(`${AccountCommerceConfig.API_BASE_URL}${path}`, {
        method: AccountCommerceApi.resolveMethod(method),
        header: headers,
        extraData: body || undefined,
        connectTimeout: 10000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      const statusCode = Number(response.responseCode);
      const value = AccountCommerceApi.responseText(response.result);
      if (statusCode < 200 || statusCode >= 300) {
        const error = AccountCommerceApi.parseError(value);
        throw new AccountApiError(
          error.message || `服务请求失败（${statusCode}）`,
          statusCode,
          error.code,
          error.retryAfter
        );
      }
      return value;
    } finally {
      client.destroy();
    }
  }

  private static resolveMethod(method: string): http.RequestMethod {
    if (method === 'GET') {
      return http.RequestMethod.GET;
    }
    return http.RequestMethod.POST;
  }

  private static responseText(result: string | Object | ArrayBuffer): string {
    if (typeof result === 'string') {
      return result;
    }
    if (result instanceof ArrayBuffer) {
      return util.TextDecoder.create('utf-8')
        .decodeWithStream(new Uint8Array(result), { stream: false });
    }
    if (result instanceof Uint8Array) {
      return util.TextDecoder.create('utf-8')
        .decodeWithStream(result, { stream: false });
    }
    return JSON.stringify(result);
  }

  private static parseTtsWalletText(value: string): TtsWalletSnapshot {
    const standardChars = AccountCommerceApi.jsonInteger(value, 'standardChars');
    const premiumChars = AccountCommerceApi.jsonInteger(value, 'premiumChars');
    if (standardChars === null || premiumChars === null) {
      throw new AccountApiError('在线朗读额度响应格式异常', 502, 'INVALID_TTS_WALLET_RESPONSE');
    }
    const result = new TtsWalletSnapshot();
    result.standardChars = standardChars;
    result.premiumChars = premiumChars;
    result.standardNextExpiry = AccountCommerceApi.jsonInteger(value, 'standardNextExpiry');
    result.premiumNextExpiry = AccountCommerceApi.jsonInteger(value, 'premiumNextExpiry');
    return result;
  }

  private static jsonInteger(value: string, field: string): number | null {
    const expression = new RegExp(`"${field}"\\s*:\\s*(?:\"([0-9]+)\"|([0-9]+)|null)`);
    const match = value.match(expression);
    if (!match) {
      return null;
    }
    const raw = match[1] || match[2] || '';
    if (!raw) {
      return null;
    }
    const parsed = Number(raw);
    return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : null;
  }

  private static parseError(value: string): ApiErrorBody {
    try {
      return JSON.parse(value) as ApiErrorBody;
    } catch (e) {
      const result = new ApiErrorBody();
      result.message = value;
      return result;
    }
  }

  private static normalizeAccount(account: AccountSnapshot): AccountSnapshot {
    const result = new AccountSnapshot();
    result.userId = account?.userId || '';
    result.displayName = account?.displayName || '华为用户';
    result.avatarUrl = account?.avatarUrl || '';
    result.points = Math.max(0, Math.floor(Number(account?.points) || 0));
    result.paidPoints = Math.max(0, Math.floor(Number(account?.paidPoints) || 0));
    result.promoPoints = Math.max(0, Math.floor(Number(account?.promoPoints) || 0));
    result.iapDebtPoints = Math.max(0, Math.floor(Number(account?.iapDebtPoints) || 0));
    result.welcomeGranted = account?.welcomeGranted === true;
    result.membership = account?.membership || null;
    result.memberThemeIds = account?.memberThemeIds || [];
    result.memberVerifiedAt = Date.now();
    result.entitlements = account?.entitlements || [];
    return result;
  }

  private static normalizeTtsWallet(wallet: TtsWalletSnapshot): TtsWalletSnapshot {
    const result = new TtsWalletSnapshot();
    const standardChars = wallet?.standardChars;
    const premiumChars = wallet?.premiumChars;
    const standardNextExpiry = wallet?.standardNextExpiry;
    const premiumNextExpiry = wallet?.premiumNextExpiry;
    result.standardChars = Math.max(0, Math.floor(Number(standardChars) || 0));
    result.premiumChars = Math.max(0, Math.floor(Number(premiumChars) || 0));
    result.standardNextExpiry = standardNextExpiry ? Number(standardNextExpiry) : null;
    result.premiumNextExpiry = premiumNextExpiry ? Number(premiumNextExpiry) : null;
    return result;
  }
}
