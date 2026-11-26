import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import connection from '@ohos.net.connection';
import { CoverFailures } from './CoverFailures';

/**
 * CoverFailures 的落盘与界面通知。记录变化时 AppStorage `coverFailureRevision` 加一，
 * 书架与封面组件据此重新取图；写盘和通知都合并延后，一屏封面同时失败只触发一次。
 */
export class CoverFailureStore {
  static readonly REVISION_KEY: string = 'coverFailureRevision';
  private static readonly STORE_NAME: string = 'cover_failures';
  // 旧键 entries 里混着超时、断连记下的地址（当时不分失败原因），换键整份丢掉，真取不到的下次显示时再记。
  private static readonly KEY_ENTRIES: string = 'entries_v2';
  private static readonly LEGACY_KEY_ENTRIES: string = 'entries';
  private static saveTimer: number = -1;
  private static notifyTimer: number = -1;

  /** 启动时读一次；读到记录后通知界面，已经显示的书架随即换成兜底封面。 */
  static async load(context: Context): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, CoverFailureStore.STORE_NAME);
      if (await store.has(CoverFailureStore.LEGACY_KEY_ENTRIES)) {
        await store.delete(CoverFailureStore.LEGACY_KEY_ENTRIES);
        await store.flush();
      }
      const raw = await store.get(CoverFailureStore.KEY_ENTRIES, '');
      if (typeof raw !== 'string' || !raw) return;
      CoverFailures.load(raw);
      CoverFailureStore.notify();
    } catch (e) {
      console.warn('读取封面失败记录失败:', e);
    }
  }

  /** 没有网络时取不到封面说明不了什么，不记。 */
  static online(): boolean {
    try {
      return connection.hasDefaultNetSync();
    } catch (_) {
      return true;
    }
  }

  static markFailed(context: Context, url: string): void {
    if (!CoverFailures.mark(url)) return;
    CoverFailureStore.scheduleSave(context);
    CoverFailureStore.notify();
  }

  static markLoaded(context: Context, url: string): void {
    if (!CoverFailures.clear(url)) return;
    CoverFailureStore.scheduleSave(context);
    CoverFailureStore.notify();
  }

  private static notify(): void {
    if (CoverFailureStore.notifyTimer >= 0) return;
    CoverFailureStore.notifyTimer = setTimeout((): void => {
      CoverFailureStore.notifyTimer = -1;
      AppStorage.setOrCreate(CoverFailureStore.REVISION_KEY,
        (AppStorage.get<number>(CoverFailureStore.REVISION_KEY) || 0) + 1);
    }, 400);
  }

  private static scheduleSave(context: Context): void {
    if (CoverFailureStore.saveTimer >= 0) return;
    CoverFailureStore.saveTimer = setTimeout((): void => {
      CoverFailureStore.saveTimer = -1;
      preferences.getPreferences(context, CoverFailureStore.STORE_NAME).then(async (store): Promise<void> => {
        await store.put(CoverFailureStore.KEY_ENTRIES, CoverFailures.serialize());
        await store.flush();
      }).catch((e: Error): void => console.warn('保存封面失败记录失败:', e));
    }, 2000);
  }
}
