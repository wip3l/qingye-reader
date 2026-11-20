import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { ReadWorkMergeGroup, ReadWorkMerges } from '../core/stats/ReadStatsSummary';

/**
 * 阅读记录的手动合并关系，以及同名提示里点过“不是同一本”的书名。
 * 只存本机并随数据备份走，不跟账号同步；每次都读盘，恢复备份后不用另外通知。
 */
export class ReadWorkMergeStore {
  static readonly STORE_NAME: string = 'read_stats_merges';
  private static readonly KEY_GROUPS: string = 'groups';
  private static readonly KEY_IGNORED_TITLES: string = 'ignoredTitles';
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<ReadWorkMergeGroup[]> {
    try {
      await ReadWorkMergeStore.writes;
      const store = await preferences.getPreferences(context, ReadWorkMergeStore.STORE_NAME);
      const raw = await store.get(ReadWorkMergeStore.KEY_GROUPS, '[]');
      return ReadWorkMerges.parse(typeof raw === 'string' ? raw : '[]');
    } catch (error) {
      console.warn('读取阅读记录合并关系失败:', error);
      return [];
    }
  }

  static save(context: Context, groups: ReadWorkMergeGroup[]): Promise<void> {
    return ReadWorkMergeStore.put(context, ReadWorkMergeStore.KEY_GROUPS, JSON.stringify(groups));
  }

  static async loadIgnoredTitles(context: Context): Promise<string[]> {
    try {
      await ReadWorkMergeStore.writes;
      const store = await preferences.getPreferences(context, ReadWorkMergeStore.STORE_NAME);
      const raw = await store.get(ReadWorkMergeStore.KEY_IGNORED_TITLES, '[]');
      const parsed = JSON.parse(typeof raw === 'string' ? raw : '[]') as Object;
      if (!Array.isArray(parsed)) return [];
      return (parsed as Object[]).filter((item: Object): boolean => typeof item === 'string') as string[];
    } catch (error) {
      console.warn('读取阅读记录同名提示设置失败:', error);
      return [];
    }
  }

  static saveIgnoredTitles(context: Context, titles: string[]): Promise<void> {
    return ReadWorkMergeStore.put(context, ReadWorkMergeStore.KEY_IGNORED_TITLES, JSON.stringify(titles));
  }

  private static put(context: Context, key: string, value: string): Promise<void> {
    const write = ReadWorkMergeStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, ReadWorkMergeStore.STORE_NAME);
      await store.put(key, value);
      await store.flush();
    });
    ReadWorkMergeStore.writes = write.catch(() => {});
    return write;
  }
}
