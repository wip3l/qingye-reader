import { common, Context } from '@kit.AbilityKit';
import { AccountCommerceApi } from './AccountCommerceApi';
import {
  AccountCredentialResponse,
  AccountDeletionResponse,
  AccountLoginMethods,
  HuaweiBindResponse,
  PasswordLoginResponse
} from './AccountCommerceModels';
import { AccountSessionStore } from './AccountSessionStore';
import { CloudSyncSettingsStore } from './CloudSyncSettingsStore';
import { HuaweiAccountService } from './HuaweiAccountService';

/**
 * 用户名+密码账号：注册、登录、用恢复码重设密码，以及登录后的登录方式管理与注销。
 * 用户名规则与服务端一致：字母开头，3~20 位字母、数字或下划线。
 */
export class AccountCredentialService {
  static readonly USERNAME_HINT: string = '3~20 位字母、数字或下划线，以字母开头';
  static readonly PASSWORD_HINT: string = '8~64 位，至少包含字母、数字、符号中的两类';

  /** 本地先挡掉明显不合规的输入，返回空串表示通过；最终以服务端校验为准。 */
  static usernameProblem(username: string): string {
    return /^[A-Za-z][A-Za-z0-9_]{2,19}$/.test(username.trim()) ? '' : `用户名需为${AccountCredentialService.USERNAME_HINT}`;
  }

  static passwordProblem(password: string, username: string): string {
    const length = Array.from(password).length;
    if (length < 8 || length > 64) return '密码需为 8~64 位';
    let kinds = 0;
    if (/[A-Za-z]/.test(password)) kinds++;
    if (/[0-9]/.test(password)) kinds++;
    if (/[^A-Za-z0-9]/.test(password)) kinds++;
    if (kinds < 2) return '密码至少要包含字母、数字、符号中的两类';
    if (username && password.toLowerCase() === username.trim().toLowerCase()) return '密码不能与用户名相同';
    return '';
  }

  static async register(context: Context, username: string, password: string): Promise<PasswordLoginResponse> {
    const response = await AccountCommerceApi.registerWithPassword(username.trim(), password);
    await AccountCredentialService.saveLogin(context, response);
    return response;
  }

  static async login(context: Context, username: string, password: string): Promise<PasswordLoginResponse> {
    const response = await AccountCommerceApi.loginWithPassword(username.trim(), password);
    await AccountCredentialService.saveLogin(context, response);
    return response;
  }

  static async recover(context: Context, username: string, recoveryCode: string,
    newPassword: string): Promise<PasswordLoginResponse> {
    const response = await AccountCommerceApi.recoverWithCode(username.trim(), recoveryCode.trim(), newPassword);
    await AccountCredentialService.saveLogin(context, response);
    return response;
  }

  private static async saveLogin(context: Context, response: PasswordLoginResponse): Promise<void> {
    if (!response.sessionToken || !response.account?.userId) {
      throw new Error('账号服务返回的数据不完整');
    }
    await AccountSessionStore.saveLogin(context, response);
    await CloudSyncSettingsStore.load(context, AccountSessionStore.account().userId);
  }

  static async loginMethods(context: Context): Promise<AccountLoginMethods> {
    return AccountCommerceApi.fetchLoginMethods(await AccountCredentialService.token(context));
  }

  static async setPassword(context: Context, username: string, newPassword: string,
    currentPassword: string): Promise<AccountCredentialResponse> {
    return AccountCommerceApi.setPassword(username.trim(), newPassword, currentPassword,
      await AccountCredentialService.token(context));
  }

  static async regenerateRecoveryCodes(context: Context, currentPassword: string): Promise<AccountCredentialResponse> {
    return AccountCommerceApi.regenerateRecoveryCodes(currentPassword, await AccountCredentialService.token(context));
  }

  /** 给用户名账号绑定华为账号；华为账号没领过新用户赠点时，服务端会补发 300 点。 */
  static async bindHuawei(context: common.UIAbilityContext): Promise<HuaweiBindResponse> {
    const token = await AccountCredentialService.token(context);
    const authorization = await HuaweiAccountService.authorize(context);
    const response = await AccountCommerceApi.bindHuawei(authorization.authorizationCode, token);
    await AccountSessionStore.updateSnapshot(context, response.account);
    await HuaweiAccountService.seedProfile(context, authorization.nickName, authorization.avatarUri);
    return response;
  }

  /** 申请注销后服务端让所有设备的登录失效，本机随即退出。 */
  static async requestDeletion(context: Context, currentPassword: string): Promise<AccountDeletionResponse> {
    const response = await AccountCommerceApi.requestAccountDeletion(currentPassword,
      await AccountCredentialService.token(context));
    await HuaweiAccountService.clearLocalSession(context);
    return response;
  }

  private static async token(context: Context): Promise<string> {
    await AccountSessionStore.load(context);
    if (!AccountSessionStore.isLoggedIn()) throw new Error('请先登录');
    return AccountSessionStore.token();
  }
}
