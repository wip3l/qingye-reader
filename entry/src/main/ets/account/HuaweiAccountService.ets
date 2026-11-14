import { authentication } from '@kit.AccountKit';
import { common, Context } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { AccountCommerceApi } from './AccountCommerceApi';
import {
  AccountApiError,
  AvatarCrop,
  AccountSnapshot,
  HuaweiLoginResponse,
  IapCreditResponse,
  SessionRenewResponse
} from './AccountCommerceModels';
import { AccountSessionStore } from './AccountSessionStore';
import { CloudSyncSettingsStore } from './CloudSyncSettingsStore';

const DEFAULT_DISPLAY_NAME = '华为用户';

/** 华为账号授权结果：授权码交给服务端换身份，昵称头像用来填默认资料。 */
export class HuaweiAuthorization {
  authorizationCode: string = '';
  nickName: string = '';
  avatarUri: string = '';
}

export class HuaweiAccountService {
  private static renewing: Promise<void> | null = null;
  /** 最近一次登录是否撤销了冷静期内的注销申请，页面据此提示一次。 */
  static lastLoginCancelledDeletion: boolean = false;

  static async initialize(context: Context): Promise<void> {
    await AccountSessionStore.load(context);
  }

  static async login(context: common.UIAbilityContext): Promise<AccountSnapshot> {
    const authorization = await HuaweiAccountService.authorize(context);
    const loginResponse: HuaweiLoginResponse = await AccountCommerceApi.login(authorization.authorizationCode);
    if (!loginResponse.sessionToken || !loginResponse.account?.userId) {
      throw new Error('账号服务返回的数据不完整');
    }
    HuaweiAccountService.lastLoginCancelledDeletion = loginResponse.deletionCancelled === true;
    await AccountSessionStore.saveLogin(context, loginResponse);
    await CloudSyncSettingsStore.load(context, AccountSessionStore.account().userId);
    await HuaweiAccountService.seedProfile(context, authorization.nickName, authorization.avatarUri);
    return AccountSessionStore.account();
  }

  /** 拉起华为账号授权，登录和给用户名账号绑定华为账号共用。 */
  static async authorize(context: common.UIAbilityContext): Promise<HuaweiAuthorization> {
    // LoginWithHuaweiIDRequest only returns identifiers. The nickname and avatar are only
    // available through the authorization request with the profile scope.
    const request = new authentication.HuaweiIDProvider().createAuthorizationWithHuaweiIDRequest();
    request.scopes = ['profile'];
    request.permissions = ['serviceauthcode'];
    request.forceAuthorization = true;
    request.state = util.generateRandomUUID();
    const controller = new authentication.AuthenticationController(context);
    const response =
      await controller.executeRequest(request) as authentication.AuthorizationWithHuaweiIDResponse;
    if (response.state && response.state !== request.state) {
      throw new Error('华为账号登录状态校验失败');
    }
    const authorizationCode = response.data?.authorizationCode || '';
    if (!authorizationCode) {
      throw new Error('华为账号未返回授权码');
    }
    const result = new HuaweiAuthorization();
    result.authorizationCode = authorizationCode;
    result.nickName = response.data?.nickName || '';
    result.avatarUri = response.data?.avatarUri || '';
    return result;
  }

  // Fills the server profile from the Huawei account only while it still holds the defaults,
  // so a nickname or avatar the user edited in the app is never overwritten by a later login.
  static async seedProfile(context: Context, nickName: string, avatarUri: string): Promise<void> {
    try {
      const account = AccountSessionStore.account();
      const huaweiName = nickName.trim().substring(0, 30);
      const displayName =
        account.displayName === DEFAULT_DISPLAY_NAME && huaweiName ? huaweiName : account.displayName;
      const avatarBase64 =
        account.avatarUrl ? '' : await HuaweiAccountService.downloadAvatarBase64(avatarUri);
      if (displayName === account.displayName && !avatarBase64) {
        return;
      }
      const snapshot = await AccountCommerceApi.updateProfile(
        displayName, avatarBase64, false, AccountSessionStore.token());
      await AccountSessionStore.updateSnapshot(context, snapshot);
    } catch (e) {
      // Login has already succeeded; the profile can still be edited manually.
      console.warn('同步华为账号昵称头像失败:', e);
    }
  }

  // The Huawei avatar link expires, so it is re-encoded to the same 256px JPEG the profile
  // editor uploads instead of being stored as a URL.
  private static async downloadAvatarBase64(avatarUri: string): Promise<string> {
    if (!avatarUri.startsWith('https://')) {
      return '';
    }
    const client = http.createHttp();
    let source: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      const response = await client.request(avatarUri, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 10000,
        maxLimit: 2 * 1024 * 1024
      });
      if (response.responseCode !== 200 || !(response.result instanceof ArrayBuffer) ||
        response.result.byteLength === 0) {
        return '';
      }
      source = image.createImageSource(response.result);
      pixelMap = await source.createPixelMap({
        desiredSize: {
          width: 256,
          height: 256
        }
      });
      packer = image.createImagePacker();
      const packed = await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: 82,
        bufferSize: 512 * 1024
      });
      return new util.Base64Helper().encodeToStringSync(new Uint8Array(packed));
    } finally {
      client.destroy();
      if (pixelMap) {
        try {
          await pixelMap.release();
        } catch (e) {
        }
      }
      if (source) {
        try {
          await source.release();
        } catch (e) {
        }
      }
      if (packer) {
        try {
          await packer.release();
        } catch (e) {
        }
      }
    }
  }

  static async refresh(context: Context): Promise<AccountSnapshot> {
    await AccountSessionStore.load(context);
    if (!AccountSessionStore.isLoggedIn()) {
      return AccountSessionStore.account();
    }
    const snapshot = await AccountCommerceApi.fetchAccount(AccountSessionStore.token());
    await AccountSessionStore.updateSnapshot(context, snapshot);
    return AccountSessionStore.account();
  }

  static async renewSession(context: Context): Promise<void> {
    if (HuaweiAccountService.renewing !== null) {
      return await HuaweiAccountService.renewing;
    }
    const task = HuaweiAccountService.doRenewSession(context);
    HuaweiAccountService.renewing = task;
    try {
      await task;
    } finally {
      if (HuaweiAccountService.renewing === task) {
        HuaweiAccountService.renewing = null;
      }
    }
  }

  private static async doRenewSession(context: Context): Promise<void> {
    await AccountSessionStore.load(context);
    if (!AccountSessionStore.isLoggedIn()) {
      return;
    }
    const currentToken = AccountSessionStore.token();
    try {
      const response: SessionRenewResponse = await AccountCommerceApi.renewSession(currentToken);
      await AccountSessionStore.updateSessionToken(context, currentToken, response.sessionToken);
    } catch (error) {
      if (error instanceof AccountApiError && error.statusCode === 401 &&
        error.errorCode === 'SESSION_EXPIRED' && AccountSessionStore.token() === currentToken) {
        await AccountSessionStore.clear(context);
        await CloudSyncSettingsStore.load(context, '');
      }
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  static async redeemTheme(context: Context, themeId: string, expectedPricePoints: number,
    expectedValidDays: number): Promise<AccountSnapshot> {
    await AccountSessionStore.load(context);
    if (!AccountSessionStore.isLoggedIn()) {
      throw new Error('请先登录');
    }
    const snapshot = await AccountCommerceApi.redeemTheme(
      themeId, util.generateRandomUUID(), expectedPricePoints, expectedValidDays,
      AccountSessionStore.token());
    await AccountSessionStore.updateSnapshot(context, snapshot);
    return AccountSessionStore.account();
  }

  static async updateProfile(context: Context, displayName: string, avatarBase64: string,
    removeAvatar: boolean, avatarCrop: AvatarCrop | null = null): Promise<AccountSnapshot> {
    await AccountSessionStore.load(context);
    if (!AccountSessionStore.isLoggedIn()) {
      throw new Error('请先登录');
    }
    const snapshot = await AccountCommerceApi.updateProfile(
      displayName, avatarBase64, removeAvatar, AccountSessionStore.token(), avatarCrop);
    await AccountSessionStore.updateSnapshot(context, snapshot);
    return AccountSessionStore.account();
  }

  static async creditIapPurchase(context: Context, purchaseData: string): Promise<IapCreditResponse> {
    await AccountSessionStore.load(context);
    if (!AccountSessionStore.isLoggedIn()) {
      throw new Error('请先登录');
    }
    const result = await AccountCommerceApi.creditIapPurchase(purchaseData, AccountSessionStore.token());
    await AccountSessionStore.updateSnapshot(context, result.account);
    return result;
  }

  /** 只清本机登录状态，不通知服务端（服务端已让会话失效时用，比如申请注销后）。 */
  static async clearLocalSession(context: Context): Promise<void> {
    await AccountSessionStore.clear(context);
    await CloudSyncSettingsStore.load(context, '');
  }

  static async logout(context: Context): Promise<void> {
    if (HuaweiAccountService.renewing !== null) {
      try {
        await HuaweiAccountService.renewing;
      } catch {
        // Logout must continue even when foreground renewal failed.
      }
    }
    const sessionToken = AccountSessionStore.token();
    if (sessionToken) {
      try {
        await AccountCommerceApi.logout(sessionToken);
      } catch {
        // Local logout must still succeed when the network is unavailable.
      }
    }
    await AccountSessionStore.clear(context);
    await CloudSyncSettingsStore.load(context, '');
  }
}
