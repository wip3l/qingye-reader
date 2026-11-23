import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import fs from '@ohos.file.fs';

/** 一部作品删书时给票留下的东西。 */
export class TicketKeepsakeItem {
  workKey: string = '';
  /** 留封面时标记里的封面地址；标记后来换了封面就不再用这份副本。 */
  coverSource: string = '';
  /** filesDir 下的封面副本；没留下为空。 */
  coverPath: string = '';
  /** 删书时票上那句（摘录，没有摘录用写了想法的划线）。 */
  quote: string = '';
  /** 删书时这本书的划线条数（票背面用）。 */
  annotationCount: number = 0;
}

/**
 * 票夹的“存根”：删书会清掉封面缓存、本地书文件和没收进摘录的划线，票却按标记一直在。
 * 删书前把票要用的封面复制一份、票上那句和划线条数记下来，按作品（标记的 workKey）存在本机，
 * 只在原来的东西取不到时顶上。标记删掉后由票夹读取时清理。
 */
export class TicketKeepsake {
  private static readonly STORE_NAME: string = 'ticket_keepsake';
  private static readonly COVER_DIR: string = 'ticket_covers';

  static async get(context: Context, workKey: string): Promise<TicketKeepsakeItem | null> {
    if (!workKey) return null;
    try {
      const store = await preferences.getPreferences(context, TicketKeepsake.STORE_NAME);
      return TicketKeepsake.parse(await store.get(TicketKeepsake.keyOf(workKey), ''), workKey);
    } catch (error) {
      console.warn('读取票夹存根失败:', error);
      return null;
    }
  }

  /** workKey → 存根。 */
  static async all(context: Context): Promise<Map<string, TicketKeepsakeItem>> {
    const result = new Map<string, TicketKeepsakeItem>();
    try {
      const store = await preferences.getPreferences(context, TicketKeepsake.STORE_NAME);
      const all = await store.getAll() as Record<string, preferences.ValueType>;
      for (const key of Object.keys(all)) {
        const item = TicketKeepsake.parse(all[key], '');
        if (item) result.set(item.workKey, item);
      }
    } catch (error) {
      console.warn('读取票夹存根失败:', error);
    }
    return result;
  }

  /**
   * 记下一份存根。新的封面、句子取不到时沿用旧存根里的（同一部作品先后删过几次）。
   * coverFile 是现在能读到的封面文件，会复制到 filesDir；为空表示这次没有封面可留。
   */
  static async save(context: Context, workKey: string, coverSource: string, coverFile: string, quote: string,
    annotationCount: number): Promise<void> {
    if (!workKey) return;
    const previous = await TicketKeepsake.get(context, workKey);
    const item = new TicketKeepsakeItem();
    item.workKey = workKey;
    item.quote = quote || previous?.quote || '';
    item.annotationCount = Math.max(annotationCount, previous?.annotationCount || 0);
    const copied = coverFile ? await TicketKeepsake.copyCover(context, workKey, coverFile) : '';
    if (copied) {
      item.coverSource = coverSource;
      item.coverPath = copied;
    } else if (previous && previous.coverPath) {
      item.coverSource = previous.coverSource;
      item.coverPath = previous.coverPath;
    }
    if (!item.quote && !item.coverPath && !(item.annotationCount > 0)) return;
    try {
      const store = await preferences.getPreferences(context, TicketKeepsake.STORE_NAME);
      await store.put(TicketKeepsake.keyOf(workKey), JSON.stringify(item));
      await store.flush();
    } catch (error) {
      console.warn('保存票夹存根失败:', error);
    }
  }

  /** 去掉不在 keep 里的作品的存根和封面副本。 */
  static async prune(context: Context, items: Map<string, TicketKeepsakeItem>, keep: Set<string>): Promise<void> {
    const stale: TicketKeepsakeItem[] = [];
    items.forEach((item: TicketKeepsakeItem, workKey: string): void => {
      if (!keep.has(workKey)) stale.push(item);
    });
    if (stale.length === 0) return;
    try {
      const store = await preferences.getPreferences(context, TicketKeepsake.STORE_NAME);
      for (const item of stale) {
        await store.delete(TicketKeepsake.keyOf(item.workKey));
        TicketKeepsake.unlink(item.coverPath);
        items.delete(item.workKey);
      }
      await store.flush();
    } catch (error) {
      console.warn('清理票夹存根失败:', error);
    }
  }

  /** 存根里的封面还能用时返回它的路径：标记的封面地址没变、文件还在。 */
  static coverFor(item: TicketKeepsakeItem | null | undefined, markCoverUrl: string): string {
    if (!item || !item.coverPath || item.coverSource !== markCoverUrl) return '';
    try {
      return fs.statSync(item.coverPath).size > 0 ? item.coverPath : '';
    } catch (_) {
      return '';
    }
  }

  private static async copyCover(context: Context, workKey: string, source: string): Promise<string> {
    const dir = `${context.filesDir}/${TicketKeepsake.COVER_DIR}`;
    const ext = TicketKeepsake.extOf(source);
    const target = `${dir}/${TicketKeepsake.keyOf(workKey)}${ext}`;
    if (source === target) return target;
    const temporary = `${target}.part`;
    try {
      await fs.mkdir(dir, true).catch((): void => undefined);
      await fs.copyFile(source, temporary);
      await fs.rename(temporary, target);
      return target;
    } catch (error) {
      console.warn('复制票面封面失败:', error);
      TicketKeepsake.unlink(temporary);
      return '';
    }
  }

  private static parse(raw: preferences.ValueType, workKey: string): TicketKeepsakeItem | null {
    if (typeof raw !== 'string' || !raw) return null;
    try {
      const value = JSON.parse(raw) as TicketKeepsakeItem;
      if (!value || !value.workKey || (workKey && value.workKey !== workKey)) return null;
      const item = new TicketKeepsakeItem();
      item.workKey = String(value.workKey);
      item.coverSource = String(value.coverSource || '');
      item.coverPath = String(value.coverPath || '');
      item.quote = String(value.quote || '');
      item.annotationCount = Number(value.annotationCount) || 0;
      return item;
    } catch (_) {
      return null;
    }
  }

  private static unlink(path: string): void {
    if (!path) return;
    try {
      fs.unlinkSync(path);
    } catch (_) {
    }
  }

  private static extOf(path: string): string {
    const match = path.toLowerCase().match(/\.(jpe?g|png|webp|bmp|gif)$/);
    return match ? `.${match[1]}` : '.jpg';
  }

  /** workKey 可能很长（书名作者都在里面），存储键用两段 FNV 散列。 */
  private static keyOf(workKey: string): string {
    return `w${TicketKeepsake.fnv(workKey, 2166136261)}${TicketKeepsake.fnv(workKey, 374761393)}`;
  }

  private static fnv(value: string, seed: number): string {
    let hash = seed >>> 0;
    for (let i = 0; i < value.length; i++) {
      hash ^= value.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16).padStart(8, '0');
  }
}
