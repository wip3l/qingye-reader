import { MembershipSnapshot } from './MembershipModels';

export class AvatarCrop {
  left: number = 0;
  top: number = 0;
  size: number = 0;
}

export class ThemeEntitlement {
  themeId: string = '';
  expiresAt: number = 0;
}

export class ThemeCatalogItem {
  themeId: string = '';
  displayName: string = '';
  pricePoints: number = 60;
  validDays: number = 365;
  acquisition: string = 'POINTS';
}

export class SuperThemeClaim {
  themeId: string = '';
  expiresAt: number = 0;
  duplicate: boolean = false;
}

export class SuperThemeClaimResponse {
  claim: SuperThemeClaim = new SuperThemeClaim();
  account: AccountSnapshot = new AccountSnapshot();
}

export class ThemeCatalogResponse {
  themes: ThemeCatalogItem[] = [];
}

export class AccountSnapshot {
  membership: MembershipSnapshot | null = null;
  memberThemeIds: string[] = [];
  memberVerifiedAt: number = 0;
  userId: string = '';
  displayName: string = '华为用户';
  avatarUrl: string = '';
  points: number = 0;
  paidPoints: number = 0;
  promoPoints: number = 0;
  iapDebtPoints: number = 0;
  welcomeGranted: boolean = false;
  entitlements: ThemeEntitlement[] = [];
}

export class HuaweiLoginResponse {
  sessionToken: string = '';
  account: AccountSnapshot = new AccountSnapshot();
  /** 冷静期内登录会撤销注销申请。 */
  deletionCancelled: boolean = false;
}

/** 用户名注册、密码登录、恢复码重设密码共用的响应。 */
export class PasswordLoginResponse extends HuaweiLoginResponse {
  /** 只有注册时返回，只显示这一次。 */
  recoveryCodes: string[] = [];
  /** 用恢复码重设密码后剩余的可用恢复码。 */
  remainingRecoveryCodes: number = 0;
}

export class AccountLoginMethods {
  username: string = '';
  hasPassword: boolean = false;
  huaweiBound: boolean = false;
  recoveryCodesRemaining: number = 0;
  deletionRequestedAt: number | null = null;
  /** 改过用户名、冷却期没过时为下次能改的时间（毫秒），现在就能改时为 0。 */
  usernameChangeAvailableAt: number = 0;
}

export class AccountCredentialResponse {
  recoveryCodes: string[] = [];
  loginMethods: AccountLoginMethods = new AccountLoginMethods();
}

export class HuaweiBindResponse {
  welcomeGranted: boolean = false;
  account: AccountSnapshot = new AccountSnapshot();
  loginMethods: AccountLoginMethods = new AccountLoginMethods();
}

export class AccountDeletionResponse {
  scheduledAt: number = 0;
}

export class SessionRenewResponse {
  sessionToken: string = '';
  expiresAt: number = 0;
}

export class IapCreditResponse {
  account: AccountSnapshot = new AccountSnapshot();
  purchaseOrderId: string = '';
  purchaseToken: string = '';
  productType: number = 0;
  creditedPoints: number = 0;
  debtOffsetPoints: number = 0;
}

export class RechargeProduct {
  productId: string = '';
  points: number = 0;
  expectedPriceYuan: number = 0;
  localPrice: string = '';

  constructor(productId: string, points: number, expectedPriceYuan: number) {
    this.productId = productId;
    this.points = points;
    this.expectedPriceYuan = expectedPriceYuan;
  }
}

export class TtsVoiceInfo {
  id: string = '';
  name: string = '';
  tier: string = 'STANDARD';
  description: string = '';
  supportsPitch: boolean = false;
  supportsWordTimestamps: boolean = false;
}

export class TtsPackageInfo {
  sku: string = '';
  tier: string = 'STANDARD';
  chars: number = 0;
  points: number = 0;
  validDays: number = 365;
}

export class TtsTrialInfo {
  standardChars: number = 0;
  premiumChars: number = 0;
  validDays: number = 0;
}

export class TtsCatalogResponse {
  voices: TtsVoiceInfo[] = [];
  packages: TtsPackageInfo[] = [];
  trial: TtsTrialInfo = new TtsTrialInfo();
}

export class TtsWalletSnapshot {
  standardChars: number = 0;
  premiumChars: number = 0;
  standardNextExpiry: number | null = null;
  premiumNextExpiry: number | null = null;
}

export class TtsPackageRedeemResponse {
  account: AccountSnapshot = new AccountSnapshot();
  ttsWallet: TtsWalletSnapshot = new TtsWalletSnapshot();
}

export class AccountApiError extends Error {
  statusCode: number = 0;
  errorCode: string = '';
  retryAfterSeconds: number = 0;

  constructor(message: string, statusCode: number = 0, errorCode: string = '',
    retryAfterSeconds: number = 0) {
    super(message);
    this.name = 'AccountApiError';
    this.statusCode = statusCode;
    this.errorCode = errorCode;
    this.retryAfterSeconds = Math.max(0, Math.floor(Number(retryAfterSeconds) || 0));
  }
}
