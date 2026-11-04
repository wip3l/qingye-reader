import { userAuth } from '@kit.UserAuthenticationKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';

export enum BiometricAuthOutcome {
  SUCCESS,
  /** 用户点了认证框上的导航按钮（如“使用密码”）。 */
  USE_PASSWORD,
  /** 用户关掉了认证框。 */
  CANCELED,
  /** 没认出来、次数过多被锁、凭据被删、系统拒绝等，应退回应用自己的密码。 */
  FAILED
}

/** 参数错误；部分机型的统一认证控件不接受只含人脸/指纹的认证类型。 */
const PARAM_ERROR_CODE: number = 401;
const START_FAILED_CODE: number = -1;

/**
 * 系统指纹/人脸认证（统一认证控件）。只在本机做门禁，不校验认证令牌。
 * 信任等级取 ATL3，与系统锁屏解锁同级；不支持的设备上直接不可用。
 * 先只请求人脸/指纹；系统以参数错误拒绝时，带上锁屏密码再试一次（此时没有导航按钮）。
 */
export class BiometricAuth {
  private static readonly TRUST_LEVEL: userAuth.AuthTrustLevel = userAuth.AuthTrustLevel.ATL3;
  private static readonly CANDIDATES: userAuth.UserAuthType[] =
    [userAuth.UserAuthType.FACE, userAuth.UserAuthType.FINGERPRINT];

  /** 当前已录入且可用的方式；未录入、被锁或设备不支持的都不算。 */
  static availableTypes(): userAuth.UserAuthType[] {
    return BiometricAuth.CANDIDATES.filter((type: userAuth.UserAuthType): boolean => {
      try {
        userAuth.getAvailableStatus(type, BiometricAuth.TRUST_LEVEL);
        return true;
      } catch (_) {
        return false;
      }
    });
  }

  static isAvailable(): boolean {
    return BiometricAuth.availableTypes().length > 0;
  }

  static async authenticate(title: string, navigationButtonText?: string): Promise<BiometricAuthOutcome> {
    const types = BiometricAuth.availableTypes();
    if (types.length === 0) return BiometricAuthOutcome.FAILED;
    let code = await BiometricAuth.run(title, types, navigationButtonText);
    if (code === PARAM_ERROR_CODE) {
      code = await BiometricAuth.run(title, [userAuth.UserAuthType.PIN, ...types], undefined);
    }
    if (code === userAuth.UserAuthResultCode.SUCCESS) return BiometricAuthOutcome.SUCCESS;
    if (code === userAuth.UserAuthResultCode.CANCELED_FROM_WIDGET) return BiometricAuthOutcome.USE_PASSWORD;
    if (code === userAuth.UserAuthResultCode.CANCELED) return BiometricAuthOutcome.CANCELED;
    return BiometricAuthOutcome.FAILED;
  }

  /** 拉起一次认证框，返回结果码；同步抛错时返回错误码。 */
  private static run(title: string, types: userAuth.UserAuthType[], navigationButtonText?: string): Promise<number> {
    return new Promise<number>((resolve: (code: number) => void): void => {
      let instance: userAuth.UserAuthInstance | undefined = undefined;
      const finish = (code: number): void => {
        if (code !== userAuth.UserAuthResultCode.SUCCESS) {
          console.info(`系统生物认证未通过: ${code}, types=${JSON.stringify(types)}`);
        }
        try {
          instance?.off('result');
        } catch (_) {
          // 实例已释放时注销失败无影响。
        }
        resolve(code);
      };
      try {
        const challenge = cryptoFramework.createRandom().generateRandomSync(16).data;
        const widgetParam: userAuth.WidgetParam = { title: title };
        if (navigationButtonText) widgetParam.navigationButtonText = navigationButtonText;
        instance = userAuth.getUserAuthInstance({
          challenge: challenge,
          authType: types,
          authTrustLevel: BiometricAuth.TRUST_LEVEL
        }, widgetParam);
        instance.on('result', {
          onResult: (result: userAuth.UserAuthResult): void => finish(result.result)
        });
        instance.start();
      } catch (e) {
        console.warn('启动系统生物认证失败:', e);
        const code = (e as BusinessError).code;
        finish(typeof code === 'number' ? code : START_FAILED_CODE);
      }
    });
  }
}
