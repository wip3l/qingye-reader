import { wearEngine } from '@kit.WearEngine';
import { bundleManager, common } from '@kit.AbilityKit';
import { BusinessError, Callback } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import deviceInfo from '@ohos.deviceInfo';
import { PhoneState, WatchRemoteProtocol } from './WatchRemoteProtocol';

export enum LinkFailure {
  /** 手表没连着手机。 */
  NO_PHONE = 0,
  /** 手机上没装开源轻页。 */
  APP_NOT_INSTALLED = 1,
  /** 手机上的开源轻页没在运行。 */
  APP_NOT_RUNNING = 2,
  /** 消息发出去了，但手机没回（多半是手机上没打开手表翻页）。 */
  NO_REPLY = 3,
  /** 穿戴服务本身不可用（没开通、没授权等）。 */
  SERVICE = 4
}

/**
 * 手表端与手机上开源轻页的 P2P 通道。手表和手机是同一个应用的两个 HAP，对端包名与签名指纹就是自己的。
 * Wear Engine 要求两端应用都在运行；手机没回话时按 LinkFailure 告诉页面原因。
 */
export class PhoneLink {
  private static readonly TAG: string = 'WatchRemote';
  private static readonly REPLY_TIMEOUT_MS: number = 2500;
  onState: (state: PhoneState) => void = (_state: PhoneState): void => {};
  onFailure: (failure: LinkFailure) => void = (_failure: LinkFailure): void => {};
  private readonly context: common.Context;
  private deviceId: string = '';
  private appParam: wearEngine.P2pAppParam | null = null;
  private receiver: Callback<wearEngine.P2pMessage> | null = null;
  private replyTimerId: number = -1;
  private released: boolean = false;

  constructor(context: common.Context) {
    this.context = context;
  }

  /** 找到手机、注册接收并打招呼；手机会回一条 state。 */
  async connect(): Promise<void> {
    this.released = false;
    try {
      const appParam = await this.ensureAppParam();
      // 手表只连一部手机，手表端也拿不到 Device.category，取第一个就是。
      // 编译时 randomId、P2pResult.code 会报“不可用于 wearable”，是 SDK 设备清单漏登记：
      // 同一清单里 sendMessage(deviceRandomId) 与 P2pResultCode 都标了 wearable，官方手表示例也这样用。
      const devices = await wearEngine.getDeviceClient(this.context).getConnectedDevices();
      const phone = devices.length > 0 ? devices[0] : undefined;
      if (!phone) {
        this.fail(LinkFailure.NO_PHONE);
        return;
      }
      if (phone.randomId !== this.deviceId || !this.receiver) {
        await this.unregister();
        const receiver: Callback<wearEngine.P2pMessage> = (message: wearEngine.P2pMessage): void => {
          this.onMessage(message);
        };
        await wearEngine.getP2pClient(this.context).registerMessageReceiver(phone.randomId, appParam, receiver);
        this.deviceId = phone.randomId;
        this.receiver = receiver;
      }
      await this.send(WatchRemoteProtocol.hello());
    } catch (error) {
      const code = Number((error as BusinessError)?.code);
      hilog.warn(0x0000, PhoneLink.TAG, 'connect failed: %{public}d', code);
      this.fail(code === 1008500002 || code === 1008500003 ? LinkFailure.NO_PHONE : LinkFailure.SERVICE);
    }
  }

  turn(direction: number): void {
    if (!this.deviceId || !this.appParam) {
      this.fail(LinkFailure.NO_PHONE);
      return;
    }
    this.send(WatchRemoteProtocol.turn(direction)).catch((): void => {});
  }

  /** 从手表拉起手机上的应用要手表系统 6.1.1（API 24）及以上。 */
  canOpenOnPhone(): boolean {
    return deviceInfo.sdkApiVersion >= 24 && this.deviceId !== '' && this.appParam !== null;
  }

  async openOnPhone(): Promise<boolean> {
    const appParam = this.appParam;
    if (!this.canOpenOnPhone() || !appParam) return false;
    try {
      const config: wearEngine.StartConfig = { entryType: wearEngine.EntryType.UI, entryName: 'EntryAbility' };
      const result = await wearEngine.getP2pClient(this.context).startRemoteApp(this.deviceId, appParam.remoteApp,
        config);
      return result.code === wearEngine.P2pResultCode.COMMUNICATION_SUCCESS ||
        result.code === wearEngine.P2pResultCode.REMOTE_APP_RUNNING;
    } catch (error) {
      hilog.warn(0x0000, PhoneLink.TAG, 'startRemoteApp failed: %{public}s', JSON.stringify(error));
      return false;
    }
  }

  async release(): Promise<void> {
    this.released = true;
    this.clearReplyTimer();
    await this.unregister();
  }

  private async ensureAppParam(): Promise<wearEngine.P2pAppParam> {
    if (this.appParam) return this.appParam;
    const info = await bundleManager.getBundleInfoForSelf(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_SIGNATURE_INFO);
    const appParam: wearEngine.P2pAppParam = {
      remoteApp: { bundleName: info.name, fingerprint: info.signatureInfo.fingerprint }
    };
    this.appParam = appParam;
    return appParam;
  }

  private async send(content: Uint8Array): Promise<void> {
    const appParam = this.appParam;
    if (!appParam || !this.deviceId) return;
    try {
      const message: wearEngine.P2pMessage = { content: content };
      const result = await wearEngine.getP2pClient(this.context).sendMessage(this.deviceId, appParam, message);
      if (result.code === wearEngine.P2pResultCode.REMOTE_APP_NOT_INSTALLED) {
        this.fail(LinkFailure.APP_NOT_INSTALLED);
      } else if (result.code === wearEngine.P2pResultCode.REMOTE_APP_NOT_RUNNING) {
        this.fail(LinkFailure.APP_NOT_RUNNING);
      } else if (result.code === wearEngine.P2pResultCode.COMMUNICATION_FAILURE) {
        this.fail(LinkFailure.NO_REPLY);
      } else {
        this.armReplyTimer();
      }
    } catch (error) {
      const code = Number((error as BusinessError)?.code);
      hilog.warn(0x0000, PhoneLink.TAG, 'sendMessage failed: %{public}d', code);
      this.fail(code === 1008500003 ? LinkFailure.NO_PHONE : LinkFailure.SERVICE);
    }
  }

  private onMessage(message: wearEngine.P2pMessage): void {
    const state = WatchRemoteProtocol.decodeState(message.content);
    if (!state || this.released) return;
    this.clearReplyTimer();
    this.onState(state);
  }

  private armReplyTimer(): void {
    this.clearReplyTimer();
    this.replyTimerId = setTimeout((): void => {
      this.replyTimerId = -1;
      this.fail(LinkFailure.NO_REPLY);
    }, PhoneLink.REPLY_TIMEOUT_MS);
  }

  private clearReplyTimer(): void {
    if (this.replyTimerId >= 0) clearTimeout(this.replyTimerId);
    this.replyTimerId = -1;
  }

  private fail(failure: LinkFailure): void {
    this.clearReplyTimer();
    if (!this.released) this.onFailure(failure);
  }

  private async unregister(): Promise<void> {
    const receiver = this.receiver;
    const appParam = this.appParam;
    const deviceId = this.deviceId;
    this.receiver = null;
    if (!receiver || !appParam || !deviceId) return;
    try {
      await wearEngine.getP2pClient(this.context).unregisterMessageReceiver(deviceId, appParam, receiver);
    } catch (error) {
      hilog.warn(0x0000, PhoneLink.TAG, 'unregister failed: %{public}s', JSON.stringify(error));
    }
  }
}
