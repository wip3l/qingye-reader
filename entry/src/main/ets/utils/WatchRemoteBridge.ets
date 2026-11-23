// 延迟加载：Wear Engine 是华为专有能力，安卓上没有，静态引用会让引用它的页面（含启动流程）加载失败。
import lazy { wearEngine } from '@kit.WearEngine';
import { bundleManager, common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError, Callback } from '@kit.BasicServicesKit';
import { ReaderInputScopes } from './ReaderInputScopes';
import { PlatformInfo } from '../platform/PlatformInfo';

/**
 * 手表翻页遥控的手机端。手表上的 wearable 模块经 Wear Engine P2P 发来短消息，这里转给当前可见的阅读页，
 * 再把书名、章节、页码回传给手表显示。
 *
 * 消息是 UTF-8 JSON，格式与 wearable 模块的 WatchRemoteProtocol 一致，改动时两边一起改：
 * - 手表 → 手机：{t:'hello'} 打开遥控页或重试时；{t:'turn', d:1|-1} 翻页。
 * - 手机 → 手表：{t:'state', st, why, book, chap, page, pages, prog, nc}。st 取 ready / noBook / busy / off，
 *   why 是不能翻页时的一句原因，nc 表示这次翻进了新章节（手表震得稍重）。
 *
 * 手表与手机是同一个应用的两个 HAP，包名和签名相同，所以对端的指纹就是自己的签名指纹。
 * 接收只在“手表翻页”打开（任一阅读类型）时注册；回传只发给本次运行里联系过手机的手表，不去唤醒没打开遥控页的手表。
 */
export interface WatchReaderSnapshot {
  book: string;
  chapter: string;
  /** 从 1 开始；0 表示页数还没统计出来。 */
  page: number;
  pages: number;
  /** 全书进度 0–1。 */
  progress: number;
}

/** 阅读页交给桥接的回调；用函数字段而不是接口方法，方便页面用箭头函数直接填。 */
export class WatchReaderHost {
  /** ReaderInputKind 的一类。 */
  inputKind: () => number = (): number => 0;
  /** 现在不接受翻页时返回原因（如“手机正在朗读”），可以翻页时返回空串。 */
  blockedReason: () => string = (): string => '';
  turn: (direction: number) => void = (_direction: number): void => {};
  snapshot: () => WatchReaderSnapshot = (): WatchReaderSnapshot => {
    const empty: WatchReaderSnapshot = { book: '', chapter: '', page: 0, pages: 0, progress: 0 };
    return empty;
  };
  /** 进书后第一次收到手表消息。 */
  onWatchContact: () => void = (): void => {};
}

export enum WatchRemoteStatusKind {
  OK = 'ok',
  NO_DEVICE = 'noDevice',
  NOT_INSTALLED = 'notInstalled',
  UNSUPPORTED = 'unsupported',
  UNAVAILABLE = 'unavailable'
}

export interface WatchRemoteStatus {
  kind: WatchRemoteStatusKind;
  deviceName: string;
  text: string;
}

interface WatchInbound {
  t?: string;
  d?: number;
}

interface WatchOutbound {
  t: string;
  st: string;
  why: string;
  book: string;
  chap: string;
  page: number;
  pages: number;
  prog: number;
  nc: boolean;
}

export class WatchRemoteBridge {
  static readonly KEY_SCOPE: string = 'readerWatchTurnScope';
  private static readonly TAG: string = '[WatchRemote]';
  private static context: common.Context | null = null;
  private static appParam: wearEngine.P2pAppParam | null = null;
  private static receivers: Map<string, Callback<wearEngine.P2pMessage>> = new Map();
  /** 本次运行里发过消息的手表，状态只推给它们。 */
  private static activeDevices: Set<string> = new Set();
  private static host: WatchReaderHost | null = null;
  private static contacted: boolean = false;
  private static lastChapter: string = '';
  private static syncSerial: number = 0;
  private static pushTimerId: number = -1;
  private static followUpTimerId: number = -1;

  /** 安卓上没有 Wear Engine。 */
  static supported(): boolean {
    return !PlatformInfo.ANDROID;
  }

  static enabled(): boolean {
    if (!WatchRemoteBridge.supported()) return false;
    return ReaderInputScopes.normalize(AppStorage.get<number>(WatchRemoteBridge.KEY_SCOPE) ?? 0) !== 0;
  }

  /** 按开关注册或撤销接收。应用回到前台、开关变化、进阅读页时调用；会重新扫一遍已连接的手表。 */
  static sync(context: common.Context): Promise<void> {
    WatchRemoteBridge.context = context;
    const serial = ++WatchRemoteBridge.syncSerial;
    if (!WatchRemoteBridge.enabled()) {
      return WatchRemoteBridge.stop();
    }
    return WatchRemoteBridge.start(context, serial).catch((error: BusinessError): void => {
      console.warn(`${WatchRemoteBridge.TAG} 注册手表消息失败: ${error?.code} ${error?.message}`);
    });
  }

  static async stop(): Promise<void> {
    const context = WatchRemoteBridge.context;
    const appParam = WatchRemoteBridge.appParam;
    const entries = Array.from(WatchRemoteBridge.receivers.entries());
    WatchRemoteBridge.receivers.clear();
    WatchRemoteBridge.activeDevices.clear();
    if (!context || !appParam) return;
    const client = wearEngine.getP2pClient(context);
    for (const entry of entries) {
      try {
        await client.unregisterMessageReceiver(entry[0], appParam, entry[1]);
      } catch (error) {
        console.warn(`${WatchRemoteBridge.TAG} 取消手表消息失败:`, JSON.stringify(error));
      }
    }
  }

  static attach(host: WatchReaderHost): void {
    if (WatchRemoteBridge.host !== host) {
      WatchRemoteBridge.contacted = false;
      WatchRemoteBridge.lastChapter = '';
    }
    WatchRemoteBridge.host = host;
    WatchRemoteBridge.notifyChanged();
  }

  static detach(host: WatchReaderHost): void {
    if (WatchRemoteBridge.host !== host) return;
    WatchRemoteBridge.host = null;
    WatchRemoteBridge.notifyChanged();
  }

  /** 阅读页状态变了（朗读开始/停止、换页等），稍后把新状态推给手表。 */
  static notifyChanged(): void {
    if (WatchRemoteBridge.activeDevices.size === 0) return;
    if (WatchRemoteBridge.pushTimerId >= 0) clearTimeout(WatchRemoteBridge.pushTimerId);
    WatchRemoteBridge.pushTimerId = setTimeout((): void => {
      WatchRemoteBridge.pushTimerId = -1;
      WatchRemoteBridge.pushState();
    }, 120);
  }

  /** 设置页的状态行。不依赖开关，打开设置页时查一次。 */
  static async queryStatus(context: common.Context): Promise<WatchRemoteStatus> {
    if (!WatchRemoteBridge.supported()) {
      return WatchRemoteBridge.status(WatchRemoteStatusKind.UNSUPPORTED, '', '安卓版不支持手表翻页');
    }
    try {
      const devices = await wearEngine.getDeviceClient(context).getConnectedDevices();
      const watches = devices.filter((device: wearEngine.Device): boolean => WatchRemoteBridge.isWatch(device));
      if (watches.length === 0) {
        return WatchRemoteBridge.status(WatchRemoteStatusKind.NO_DEVICE, '', '没有连接的手表 · 在运动健康里连接手表');
      }
      const watch = watches[0];
      const name = watch.name || watch.model || '手表';
      const p2p = await watch.isWearEngineCapabilitySupported(wearEngine.WearEngineCapability.P2P_COMMUNICATION);
      if (!p2p || watch.isSmartWatch === false) {
        return WatchRemoteBridge.status(WatchRemoteStatusKind.UNSUPPORTED, name, '这块手表不能安装第三方应用');
      }
      const installed = await wearEngine.getP2pClient(context).isRemoteAppInstalled(watch.randomId,
        context.applicationInfo.name);
      return installed ?
        WatchRemoteBridge.status(WatchRemoteStatusKind.OK, name, '已连接 · 手表上已安装') :
        WatchRemoteBridge.status(WatchRemoteStatusKind.NOT_INSTALLED, name, '手表上还没装开源轻页 · 在手表应用市场搜索安装');
    } catch (error) {
      const code = Number((error as BusinessError)?.code);
      console.warn(`${WatchRemoteBridge.TAG} 查询手表状态失败: ${code}`);
      return WatchRemoteBridge.status(WatchRemoteStatusKind.UNAVAILABLE, '', WatchRemoteBridge.errorText(code));
    }
  }

  private static status(kind: WatchRemoteStatusKind, deviceName: string, text: string): WatchRemoteStatus {
    const status: WatchRemoteStatus = { kind: kind, deviceName: deviceName, text: text };
    return status;
  }

  private static errorText(code: number): string {
    switch (code) {
      case 801:
        return '这台设备不支持连接手表';
      case 1008500002:
        return '没有连接的手表 · 在运动健康里连接手表';
      case 1008500003:
        return '手表已断开连接';
      case 1008500004:
        return '穿戴服务还没开通，暂时不能使用';
      case 1008500006:
        return '请先在运动健康里同意隐私声明';
      case 1008500008:
      case 1008500009:
        return '请先登录华为账号';
      default:
        return '暂时查不到手表状态';
    }
  }

  private static isWatch(device: wearEngine.Device): boolean {
    return device.category === wearEngine.DeviceCategory.WATCH || device.isSmartWatch === true;
  }

  private static async start(context: common.Context, serial: number): Promise<void> {
    const appParam = await WatchRemoteBridge.ensureAppParam();
    const devices = await wearEngine.getDeviceClient(context).getConnectedDevices();
    if (serial !== WatchRemoteBridge.syncSerial) return;
    const client = wearEngine.getP2pClient(context);
    const connected = new Set<string>();
    for (const device of devices) {
      if (!WatchRemoteBridge.isWatch(device)) continue;
      const deviceId = device.randomId;
      connected.add(deviceId);
      if (WatchRemoteBridge.receivers.has(deviceId)) continue;
      const callback: Callback<wearEngine.P2pMessage> = (message: wearEngine.P2pMessage): void => {
        WatchRemoteBridge.onMessage(deviceId, message);
      };
      await client.registerMessageReceiver(deviceId, appParam, callback);
      WatchRemoteBridge.receivers.set(deviceId, callback);
    }
    // 手表每次重新配对 randomId 都会变，旧的接收撤掉。
    const stale = Array.from(WatchRemoteBridge.receivers.entries())
      .filter((entry: [string, Callback<wearEngine.P2pMessage>]): boolean => !connected.has(entry[0]));
    for (const entry of stale) {
      WatchRemoteBridge.receivers.delete(entry[0]);
      WatchRemoteBridge.activeDevices.delete(entry[0]);
      client.unregisterMessageReceiver(entry[0], appParam, entry[1]).catch((): void => {});
    }
  }

  private static async ensureAppParam(): Promise<wearEngine.P2pAppParam> {
    if (WatchRemoteBridge.appParam) return WatchRemoteBridge.appParam;
    const info = await bundleManager.getBundleInfoForSelf(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_SIGNATURE_INFO);
    const appParam: wearEngine.P2pAppParam = {
      remoteApp: { bundleName: info.name, fingerprint: info.signatureInfo.fingerprint }
    };
    WatchRemoteBridge.appParam = appParam;
    return appParam;
  }

  private static onMessage(deviceId: string, message: wearEngine.P2pMessage): void {
    let inbound: WatchInbound;
    try {
      inbound = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(message.content)) as WatchInbound;
    } catch (error) {
      console.warn(`${WatchRemoteBridge.TAG} 手表消息无法解析`);
      return;
    }
    WatchRemoteBridge.activeDevices.add(deviceId);
    const host = WatchRemoteBridge.host;
    if (host && !WatchRemoteBridge.contacted) {
      WatchRemoteBridge.contacted = true;
      host.onWatchContact();
    }
    if (inbound.t === 'turn' && host) {
      const direction = Number(inbound.d) < 0 ? -1 : 1;
      if (WatchRemoteBridge.stateFor(host) === 'ready') {
        host.turn(direction);
        // 翻页是异步的：先回一次新页码，跨章加载慢的再补一次。
        WatchRemoteBridge.scheduleFollowUp(deviceId);
        return;
      }
    }
    WatchRemoteBridge.sendState(deviceId);
  }

  private static scheduleFollowUp(deviceId: string): void {
    setTimeout((): void => WatchRemoteBridge.sendState(deviceId), 200);
    if (WatchRemoteBridge.followUpTimerId >= 0) clearTimeout(WatchRemoteBridge.followUpTimerId);
    WatchRemoteBridge.followUpTimerId = setTimeout((): void => {
      WatchRemoteBridge.followUpTimerId = -1;
      WatchRemoteBridge.sendState(deviceId);
    }, 900);
  }

  private static stateFor(host: WatchReaderHost | null): string {
    if (!host) return 'noBook';
    if (!ReaderInputScopes.enabled(WatchRemoteBridge.KEY_SCOPE, host.inputKind())) return 'off';
    return host.blockedReason() ? 'busy' : 'ready';
  }

  private static outbound(): WatchOutbound {
    const host = WatchRemoteBridge.host;
    const state = WatchRemoteBridge.stateFor(host);
    const message: WatchOutbound = {
      t: 'state', st: state, why: '', book: '', chap: '', page: 0, pages: 0, prog: 0, nc: false
    };
    if (!host) return message;
    if (state === 'busy') message.why = host.blockedReason();
    if (state === 'off') message.why = '手机上没给这类书打开手表翻页';
    const snapshot = host.snapshot();
    message.book = snapshot.book;
    message.chap = snapshot.chapter;
    message.page = snapshot.page;
    message.pages = snapshot.pages;
    message.prog = Math.max(0, Math.min(1, snapshot.progress));
    message.nc = WatchRemoteBridge.lastChapter !== '' && snapshot.chapter !== WatchRemoteBridge.lastChapter;
    WatchRemoteBridge.lastChapter = snapshot.chapter;
    return message;
  }

  private static pushState(): void {
    for (const deviceId of Array.from(WatchRemoteBridge.activeDevices)) {
      WatchRemoteBridge.sendState(deviceId);
    }
  }

  private static sendState(deviceId: string): void {
    const context = WatchRemoteBridge.context;
    const appParam = WatchRemoteBridge.appParam;
    if (!context || !appParam || !WatchRemoteBridge.receivers.has(deviceId)) return;
    const content = new util.TextEncoder().encodeInto(JSON.stringify(WatchRemoteBridge.outbound()));
    const message: wearEngine.P2pMessage = { content: content };
    wearEngine.getP2pClient(context).sendMessage(deviceId, appParam, message)
      .then((result: wearEngine.P2pResult): void => {
        if (result.code === wearEngine.P2pResultCode.REMOTE_APP_NOT_RUNNING ||
          result.code === wearEngine.P2pResultCode.REMOTE_APP_NOT_INSTALLED) {
          // 手表上的遥控页关了，下次它再发消息时重新加入。
          WatchRemoteBridge.activeDevices.delete(deviceId);
        }
      })
      .catch((error: BusinessError): void => {
        console.warn(`${WatchRemoteBridge.TAG} 回传手表失败: ${error?.code}`);
      });
  }
}
