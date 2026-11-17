import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class CloudSyncIssue {
  /** 同一问题再次出现时按 key 合并，只更新时间和次数。 */
  key: string = '';
  kind: string = '';
  title: string = '';
  message: string = '';
  /** 书源问题记下书源地址，问题页据此打开或删除书源。 */
  sourceUrl: string = '';
  /** 被拒收条目上传时的大小（字节），书源过大时供用户判断。 */
  bytes: number = 0;
  firstAt: number = 0;
  lastAt: number = 0;
  count: number = 0;
}

class CloudSyncIssueList {
  issues: CloudSyncIssue[] = [];
}

/**
 * 同步问题记录：整次同步失败、服务端拒收的条目（如超出限额的书源）、本地书籍、字体和自定义主题上传失败。
 * 按账号保存在本机，同一问题只保留一条；记录只由用户在“同步问题”页手动移除或清空。
 */
export class CloudSyncIssueStore {
  static readonly KIND_SYNC: string = 'sync';
  static readonly KIND_BOOK_SOURCE: string = 'book_source';
  static readonly KIND_REJECTED: string = 'rejected';
  static readonly KIND_FILE: string = 'file';
  static readonly STORAGE_COUNT: string = 'cloudSyncIssueCount';
  static readonly STORAGE_LATEST: string = 'cloudSyncIssueLatest';
  static readonly STORAGE_REVISION: string = 'cloudSyncIssueRevision';
  private static readonly STORE_NAME: string = 'cloud_sync_issues';
  private static readonly MAX_ISSUES: number = 100;
  private static readonly MAX_TEXT: number = 300;
  private static queue: Promise<void> = Promise.resolve();
  private static publishedUserId: string = '';

  static create(kind: string, key: string, title: string, message: string): CloudSyncIssue {
    const issue = new CloudSyncIssue();
    issue.kind = kind;
    issue.key = key;
    issue.title = title;
    issue.message = message;
    return issue;
  }

  static async load(context: Context, userId: string): Promise<CloudSyncIssue[]> {
    const normalizedUserId = CloudSyncIssueStore.normalizeUserId(userId);
    let result: CloudSyncIssue[] = [];
    const task = CloudSyncIssueStore.queue.catch(() => {
    }).then(async () => {
      result = normalizedUserId ? await CloudSyncIssueStore.read(context, normalizedUserId) : [];
      CloudSyncIssueStore.publishedUserId = normalizedUserId;
      CloudSyncIssueStore.publish(result);
    });
    CloudSyncIssueStore.queue = task;
    await task;
    return result;
  }

  static async record(context: Context, userId: string, issues: CloudSyncIssue[]): Promise<void> {
    if (issues.length === 0) return;
    await CloudSyncIssueStore.mutate(context, userId, (list: CloudSyncIssue[]) => {
      const now = Date.now();
      for (const incoming of issues) {
        const issue = CloudSyncIssueStore.normalize(incoming);
        const existing = list.find((item: CloudSyncIssue) => item.key === issue.key);
        if (existing) {
          existing.title = issue.title;
          existing.message = issue.message;
          existing.sourceUrl = issue.sourceUrl;
          existing.bytes = issue.bytes;
          existing.lastAt = now;
          existing.count++;
        } else {
          issue.firstAt = now;
          issue.lastAt = now;
          issue.count = 1;
          list.push(issue);
        }
      }
      return list;
    });
  }

  static async remove(context: Context, userId: string, key: string): Promise<void> {
    await CloudSyncIssueStore.mutate(context, userId, (list: CloudSyncIssue[]) =>
      list.filter((item: CloudSyncIssue) => item.key !== key));
  }

  static async clear(context: Context, userId: string): Promise<void> {
    await CloudSyncIssueStore.mutate(context, userId, (): CloudSyncIssue[] => []);
  }

  private static async mutate(context: Context, userId: string,
    change: (list: CloudSyncIssue[]) => CloudSyncIssue[]): Promise<void> {
    const normalizedUserId = CloudSyncIssueStore.normalizeUserId(userId);
    if (!normalizedUserId) return;
    const task = CloudSyncIssueStore.queue.catch(() => {
    }).then(async () => {
      const next = change(await CloudSyncIssueStore.read(context, normalizedUserId))
        .sort((a: CloudSyncIssue, b: CloudSyncIssue) => b.lastAt - a.lastAt)
        .slice(0, CloudSyncIssueStore.MAX_ISSUES);
      const data = new CloudSyncIssueList();
      data.issues = next;
      const store = await preferences.getPreferences(context, CloudSyncIssueStore.STORE_NAME);
      await store.put(CloudSyncIssueStore.preferenceKey(normalizedUserId), JSON.stringify(data));
      await store.flush();
      if (!CloudSyncIssueStore.publishedUserId || CloudSyncIssueStore.publishedUserId === normalizedUserId) {
        CloudSyncIssueStore.publishedUserId = normalizedUserId;
        CloudSyncIssueStore.publish(next);
      }
    });
    CloudSyncIssueStore.queue = task;
    await task;
  }

  private static async read(context: Context, normalizedUserId: string): Promise<CloudSyncIssue[]> {
    const store = await preferences.getPreferences(context, CloudSyncIssueStore.STORE_NAME);
    const raw = await store.get(CloudSyncIssueStore.preferenceKey(normalizedUserId), '');
    if (typeof raw !== 'string' || !raw) return [];
    try {
      const parsed = JSON.parse(raw) as CloudSyncIssueList;
      return (parsed && Array.isArray(parsed.issues) ? parsed.issues : [])
        .filter((item: CloudSyncIssue) => !!item && typeof item.key === 'string' && !!item.key)
        .map((item: CloudSyncIssue) => CloudSyncIssueStore.normalize(item));
    } catch (e) {
      return [];
    }
  }

  private static publish(issues: CloudSyncIssue[]): void {
    AppStorage.setOrCreate(CloudSyncIssueStore.STORAGE_COUNT, issues.length);
    AppStorage.setOrCreate(CloudSyncIssueStore.STORAGE_LATEST, issues.length > 0 ? issues[0].title : '');
    AppStorage.setOrCreate(CloudSyncIssueStore.STORAGE_REVISION,
      (AppStorage.get<number>(CloudSyncIssueStore.STORAGE_REVISION) || 0) + 1);
  }

  private static normalize(source: CloudSyncIssue): CloudSyncIssue {
    const result = new CloudSyncIssue();
    result.key = String(source.key || '').slice(0, CloudSyncIssueStore.MAX_TEXT);
    result.kind = String(source.kind || CloudSyncIssueStore.KIND_SYNC);
    result.title = String(source.title || '同步问题').slice(0, CloudSyncIssueStore.MAX_TEXT);
    result.message = String(source.message || '').slice(0, CloudSyncIssueStore.MAX_TEXT);
    result.sourceUrl = String(source.sourceUrl || '').slice(0, CloudSyncIssueStore.MAX_TEXT);
    result.bytes = Math.max(0, Math.floor(Number(source.bytes) || 0));
    result.firstAt = Math.max(0, Math.floor(Number(source.firstAt) || 0));
    result.lastAt = Math.max(result.firstAt, Math.floor(Number(source.lastAt) || 0));
    result.count = Math.max(1, Math.floor(Number(source.count) || 1));
    return result;
  }

  private static preferenceKey(userId: string): string {
    return `issues:${userId}`;
  }

  private static normalizeUserId(userId: string): string {
    return (userId || '').trim().replace(/[^a-zA-Z0-9_-]/g, '_');
  }
}
