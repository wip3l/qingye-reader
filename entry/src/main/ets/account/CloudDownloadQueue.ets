import { AccountSessionStore } from './AccountSessionStore';

/** 书籍与字体共用下载、导入队列；页面切换不会丢失队列或重复提交同一文件。 */
export class CloudDownloadQueue {
  private static tail: Promise<void> = Promise.resolve();
  private static keys: string[] = [];

  static position(raw: string, key: string): number {
    return (JSON.parse(raw || '[]') as string[]).indexOf(key);
  }

  static status(key: string, text: string): void {
    if (CloudDownloadQueue.keys[0] === key) AppStorage.setOrCreate('cloudDownloadStatus', text);
  }

  static enqueue<T>(key: string, run: () => Promise<T>): Promise<T> {
    if (CloudDownloadQueue.keys.includes(key)) return Promise.reject(new Error('已在下载队列中'));
    const userId = AccountSessionStore.account().userId;
    CloudDownloadQueue.keys.push(key);
    AppStorage.setOrCreate('cloudDownloadQueueRaw', JSON.stringify(CloudDownloadQueue.keys));
    const result = CloudDownloadQueue.tail.then(async (): Promise<T> => {
      if (!userId || AccountSessionStore.account().userId !== userId) throw new Error('账号已改变，请重新下载');
      CloudDownloadQueue.status(key, '等待下载');
      return await run();
    }).finally((): void => {
      CloudDownloadQueue.keys = CloudDownloadQueue.keys.filter((item: string): boolean => item !== key);
      AppStorage.setOrCreate('cloudDownloadStatus', CloudDownloadQueue.keys.length > 0 ? '等待下载' : '');
      AppStorage.setOrCreate('cloudDownloadQueueRaw', JSON.stringify(CloudDownloadQueue.keys));
    });
    // 单项失败仍然释放队列，让之后的任务继续执行。
    CloudDownloadQueue.tail = result.then((): void => {}, (): void => {});
    return result;
  }
}
