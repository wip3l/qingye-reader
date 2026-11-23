import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** 遥控页长按打开的四个开关，只存在手表上。 */
export class WatchPrefs {
  keepScreenOn: boolean = true;
  vibrate: boolean = true;
  crownTurn: boolean = true;
  /** 下一页的大区域挪到上方，表冠方向也跟着反过来。 */
  swapZones: boolean = false;

  private static readonly STORE: string = 'watch_remote';

  static async load(context: common.Context): Promise<WatchPrefs> {
    const prefs = new WatchPrefs();
    try {
      const store = await preferences.getPreferences(context, WatchPrefs.STORE);
      prefs.keepScreenOn = (await store.get('keepScreenOn', true)) === true;
      prefs.vibrate = (await store.get('vibrate', true)) === true;
      prefs.crownTurn = (await store.get('crownTurn', true)) === true;
      prefs.swapZones = (await store.get('swapZones', false)) === true;
    } catch (error) {
      console.warn('[WatchRemote] 读取手表设置失败:', JSON.stringify(error));
    }
    return prefs;
  }

  static async save(context: common.Context, prefs: WatchPrefs): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, WatchPrefs.STORE);
      await store.put('keepScreenOn', prefs.keepScreenOn);
      await store.put('vibrate', prefs.vibrate);
      await store.put('crownTurn', prefs.crownTurn);
      await store.put('swapZones', prefs.swapZones);
      await store.flush();
    } catch (error) {
      console.warn('[WatchRemote] 保存手表设置失败:', JSON.stringify(error));
    }
  }

  copy(): WatchPrefs {
    const next = new WatchPrefs();
    next.keepScreenOn = this.keepScreenOn;
    next.vibrate = this.vibrate;
    next.crownTurn = this.crownTurn;
    next.swapZones = this.swapZones;
    return next;
  }
}
