// utils/WatchRemoteBridge.ets 的安卓实现（平台层之外少数整文件替换之一，见 docs/android-build.md）。
//
// 鸿蒙实现引用 @kit.WearEngine。它是华为健康的系统共享包（HSP），ArkUI-X 在实例化模块时就去加载，
// 安卓上找不到就直接终止进程，import lazy 也拦不住。所以安卓整文件换成这个空实现：对外接口相同，什么都不做。
import { common } from '@kit.AbilityKit';

export interface WatchReaderSnapshot {
  book: string;
  chapter: string;
  /** 从 1 开始；0 表示页数还没统计出来。 */
  page: number;
  pages: number;
  /** 全书进度 0–1。 */
  progress: number;
}

export class WatchReaderHost {
  inputKind: () => number = (): number => 0;
  blockedReason: () => string = (): string => '';
  turn: (direction: number) => void = (_direction: number): void => {};
  snapshot: () => WatchReaderSnapshot = (): WatchReaderSnapshot => {
    const empty: WatchReaderSnapshot = { book: '', chapter: '', page: 0, pages: 0, progress: 0 };
    return empty;
  };
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

export class WatchRemoteBridge {
  static readonly KEY_SCOPE: string = 'readerWatchTurnScope';

  static enabled(): boolean {
    return false;
  }

  static sync(_context: common.Context): Promise<void> {
    return Promise.resolve();
  }

  static async stop(): Promise<void> {
  }

  static attach(_host: WatchReaderHost): void {
  }

  static detach(_host: WatchReaderHost): void {
  }

  static notifyChanged(): void {
  }

  static async queryStatus(_context: common.Context): Promise<WatchRemoteStatus> {
    const status: WatchRemoteStatus = {
      kind: WatchRemoteStatusKind.UNSUPPORTED, deviceName: '', text: '安卓版不支持手表翻页'
    };
    return status;
  }
}
