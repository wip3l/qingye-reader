import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AudioOfflineStore } from '../core/book/AudioOfflineStore';
import { HdsFeedback } from './HdsFeedback';

/** 听书页发给书架的下载请求。书架页一直在页面栈底部，后台任务、通知栏进度和取消都由它负责。 */
export class AudioOfflineDownloadRequest {
  bookUrl: string = '';
  /** 为空表示下载全部章节。 */
  chapterIndexes: number[] = [];
  allowCellular: boolean = false;
  nonce: number = 0;
}

export class AudioOfflineDownloadPrompt {
  static readonly REQUEST_KEY: string = 'audioOfflineDownloadRequest';
  static readonly ACK_KEY: string = 'audioOfflineDownloadAck';
  /** prepare 的结果：取消。 */
  static readonly CANCEL: number = -1;
  /** prepare 的结果：开始下载，离开 Wi-Fi 时暂停等待。 */
  static readonly WIFI: number = 0;
  /** prepare 的结果：开始下载，用户同意用移动网络。 */
  static readonly CELLULAR: number = 1;

  /**
   * 下载前按网络状态确认：Wi-Fi 下直接开始；移动网络下，开了"仅 Wi-Fi 下载"就提示稍后自动开始，
   * 否则弹窗确认是否用流量。
   */
  static async prepare(uiContext: UIContext, darkMode: boolean, chapterCount: number = 0): Promise<number> {
    if (AudioOfflineStore.network() !== 'cellular') return AudioOfflineDownloadPrompt.WIFI;
    if (AudioOfflineStore.wifiOnly()) {
      HdsFeedback.showToast('已开启仅 Wi-Fi 下载，连上 Wi-Fi 后自动开始');
      return AudioOfflineDownloadPrompt.WIFI;
    }
    try {
      const scope = chapterCount > 0 ? `${chapterCount} 章音频` : '全部章节音频';
      const result = await uiContext.getPromptAction().showDialog({
        title: '正在使用移动网络',
        message: `下载${scope}可能消耗较多流量，每章常有几到几十 MB。确定继续下载？`,
        buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(darkMode) },
          { text: '继续下载', color: ThemeRuntime.dangerColor(darkMode) }]
      });
      return result.index === 1 ? AudioOfflineDownloadPrompt.CELLULAR : AudioOfflineDownloadPrompt.CANCEL;
    } catch (_) {
      return AudioOfflineDownloadPrompt.CANCEL;
    }
  }

  /** 把下载请求交给书架；书架没有接收（例如从桌面快捷方式直接打开听书页）时返回 false。 */
  static async send(bookUrl: string, chapterIndexes: number[], allowCellular: boolean): Promise<boolean> {
    const request = new AudioOfflineDownloadRequest();
    request.bookUrl = bookUrl;
    request.chapterIndexes = chapterIndexes;
    request.allowCellular = allowCellular;
    request.nonce = Date.now();
    AppStorage.setOrCreate(AudioOfflineDownloadPrompt.REQUEST_KEY, JSON.stringify(request));
    for (let waited = 0; waited < 800; waited += 50) {
      if (AppStorage.get<number>(AudioOfflineDownloadPrompt.ACK_KEY) === request.nonce) return true;
      await new Promise<void>((resolve: () => void): number => setTimeout(resolve, 50));
    }
    return false;
  }

  static parse(raw: string): AudioOfflineDownloadRequest | null {
    if (!raw) return null;
    try {
      const value = JSON.parse(raw) as AudioOfflineDownloadRequest;
      if (!value || !value.bookUrl || !value.nonce) return null;
      const request = new AudioOfflineDownloadRequest();
      request.bookUrl = String(value.bookUrl);
      request.chapterIndexes = Array.isArray(value.chapterIndexes) ?
        value.chapterIndexes.filter((index: number): boolean => Number.isInteger(index) && index >= 0) : [];
      request.allowCellular = value.allowCellular === true;
      request.nonce = Number(value.nonce);
      return request;
    } catch (_) {
      return null;
    }
  }
}
