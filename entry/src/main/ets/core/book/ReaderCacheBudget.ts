import { ReaderImageResults } from './ReaderImageResults';
import fs from '@ohos.file.fs';
import { appDb, CachedContentEntry, ReaderImageResource } from '../../model/data/AppDatabase';
import { CacheBudgetItem, ReaderCacheBudgetPolicy } from './ReaderCacheBudgetPolicy';
import { ReaderCacheCoordinator } from './ReaderCacheCoordinator';
import { ReaderImageCache } from './ReaderImageCache';

export class ReaderCacheCleanup {
  releasedBytes: number = 0;
  removed: number = 0;
  protectedCount: number = 0;
  failed: number = 0;
  remainingBytes: number = 0;
}

/** Automatic budgets exclude offline originals. All deletion is revalidated against current ownership. */
export class ReaderCacheBudget {
  static readonly TEXT_LIMIT_BYTES: number = 256 * 1024 * 1024;
  static readonly COMIC_LIMIT_BYTES: number = 1024 * 1024 * 1024;
  private static readonly RECENT_PROTECT_MS: number = 600000;
  private static chain: Promise<void> = Promise.resolve();
  private static textTimer: number = -1;
  private static comicTimer: number = -1;
  private static startupTimer: number = -1;
  private static textOver: boolean = false;
  private static comicOver: boolean = false;
  private static retryMs: number = 30000;
  private static comicIndex: Map<string, CacheBudgetItem> = new Map();
  private static comicIndexAt: number = 0;
  private static comicIndexDir: string = '';
  private static comicRevision: number = 0;

  static setProtectedBooksProvider(provider: () => string[]): void {
    ReaderCacheCoordinator.setBooksProvider(provider);
  }

  private static init(): void {
    ReaderCacheCoordinator.onRelease = (): void => {
      if (ReaderCacheBudget.textOver) ReaderCacheBudget.scheduleText(1000);
      if (ReaderCacheBudget.comicOver) ReaderCacheBudget.scheduleComic(1000);
    };
  }

  static noteTextWrite(): void { ReaderCacheBudget.init(); ReaderCacheBudget.scheduleText(15000); }

  static noteComicWrite(path?: string): void {
    ReaderCacheBudget.init();
    if (path) ReaderImageCache.touch(path);
    ReaderCacheBudget.enqueue(async (): Promise<void> => {
      if (!path || !ReaderImageCache.managed(path)) { ReaderCacheBudget.comicIndexAt = 0; return; }
      if (!ReaderCacheBudget.comicIndexAt) return;
      try {
        const stat = await fs.stat(path);
        if (!stat.isFile()) { ReaderCacheBudget.comicIndexAt = 0; return; }
        const item = new CacheBudgetItem(); item.id = path; item.bytes = stat.size;
        item.usedAt = Math.max(stat.mtime * 1000, ReaderImageCache.lastUse(path));
        ReaderCacheBudget.comicIndex.set(path, item);
      } catch (_) { ReaderCacheBudget.comicIndexAt = 0; }
    });
    ReaderCacheBudget.scheduleComic(15000);
  }

  static touchComicFile(path: string): void {
    ReaderImageCache.touch(path);
    const item = ReaderCacheBudget.comicIndex.get(ReaderCacheCoordinator.path(path));
    if (item) item.usedAt = Date.now();
  }

  static scheduleStartupTrim(delayMs: number = 20000): void {
    ReaderCacheBudget.init();
    if (ReaderCacheBudget.startupTimer >= 0) return;
    ReaderCacheBudget.startupTimer = setTimeout((): void => {
      ReaderCacheBudget.startupTimer = -1;
      ReaderCacheBudget.scheduleText(0);
      ReaderCacheBudget.scheduleComic(0);
    }, delayMs);
  }

  private static scheduleText(delay: number): void {
    if (ReaderCacheBudget.textTimer >= 0) return;
    ReaderCacheBudget.textTimer = setTimeout((): void => {
      ReaderCacheBudget.textTimer = -1;
      ReaderCacheBudget.enqueue(async (): Promise<void> => {
        try { await ReaderCacheBudget.trimText(); }
        catch (e) { console.warn('[CacheBudget] text trim failed', e); ReaderCacheBudget.scheduleText(60000); }
      });
    }, Math.max(0, delay));
  }

  private static scheduleComic(delay: number): void {
    if (ReaderCacheBudget.comicTimer >= 0) return;
    ReaderCacheBudget.comicTimer = setTimeout((): void => {
      ReaderCacheBudget.comicTimer = -1;
      ReaderCacheBudget.enqueue(async (): Promise<void> => {
        try { await ReaderCacheBudget.trimComic(); ReaderCacheBudget.retryMs = 30000; }
        catch (e) {
          console.warn('[CacheBudget] comic trim failed', e);
          ReaderCacheBudget.scheduleComic(ReaderCacheBudget.retryMs);
          ReaderCacheBudget.retryMs = Math.min(300000, ReaderCacheBudget.retryMs * 2);
        }
      });
    }, Math.max(0, delay));
  }

  private static async prepare(): Promise<void> {
    while (await appDb.backfillCachedContentBytes() > 0) await ReaderCacheBudget.yield();
    while (await appDb.backfillImageReferences() > 0) await ReaderCacheBudget.yield();
  }

  static async textUsageBytes(offline: boolean = false): Promise<number> {
    await ReaderCacheBudget.prepare();
    return await appDb.getOnlineCachedContentBytes(offline);
  }

  static async comicUsageBytes(offline: boolean = false): Promise<number> {
    return await ReaderCacheBudget.enqueueValue(async (): Promise<number> => {
      await ReaderCacheBudget.prepare();
      const pinned = new Set(await appDb.imagePaths(true));
      let total = 0;
      for (const item of await ReaderCacheBudget.listComicFiles(true)) {
        if (pinned.has(item.id) === offline) total += item.bytes;
      }
      return total;
    });
  }

  static async clearText(offline: boolean = false): Promise<ReaderCacheCleanup> {
    await ReaderCacheBudget.prepare();
    const entries = (await appDb.listOnlineCachedContentEntries(!offline)).filter((entry: CachedContentEntry): boolean => entry.pinned === offline);
    return await ReaderCacheBudget.deleteText(entries, offline, Date.now());
  }

  static async clearComic(): Promise<ReaderCacheCleanup> {
    return await ReaderCacheBudget.enqueueValue(async (): Promise<ReaderCacheCleanup> => {
      await ReaderCacheBudget.prepare();
      return await ReaderCacheBudget.deleteImages(await ReaderCacheBudget.listComicFiles(true), Number.MAX_SAFE_INTEGER);
    });
  }

  static async clearOffline(): Promise<ReaderCacheCleanup> {
    return await ReaderCacheBudget.enqueueValue(async (): Promise<ReaderCacheCleanup> => {
      await ReaderCacheBudget.prepare();
      const former = new Set(await appDb.imagePaths(true));
      const result = await ReaderCacheBudget.clearText(true);
      // Images still referenced by another chapter (including active/offline users) are retained.
      const referenced = new Set(await appDb.imagePaths());
      const candidates = (await ReaderCacheBudget.listComicFiles(true)).filter((item: CacheBudgetItem): boolean =>
        former.has(item.id) && !referenced.has(item.id));
      const images = await ReaderCacheBudget.deleteImages(candidates, Number.MAX_SAFE_INTEGER);
      result.removed += images.removed; result.releasedBytes += images.releasedBytes;
      result.failed += images.failed; result.protectedCount += images.protectedCount;
      ReaderCacheBudget.noteTextWrite(); ReaderCacheBudget.noteComicWrite();
      return result;
    });
  }

  private static async trimText(): Promise<void> {
    await ReaderCacheBudget.prepare();
    const total = await appDb.getOnlineCachedContentBytes();
    ReaderCacheBudget.textOver = total > ReaderCacheBudget.TEXT_LIMIT_BYTES;
    if (!ReaderCacheBudget.textOver) return;
    const entries = await appDb.listOnlineCachedContentEntries(true);
    const books = new Set(ReaderCacheCoordinator.protectedBooks());
    const now = Date.now();
    const items = entries.map((entry: CachedContentEntry): CacheBudgetItem => {
      const item = new CacheBudgetItem(); item.id = '' + entry.rowId; item.owner = entry.bookUrl;
      item.bytes = entry.bytes; item.usedAt = entry.usedAt; return item;
    });
    const plan = ReaderCacheBudgetPolicy.planTrim(items, total, ReaderCacheBudget.TEXT_LIMIT_BYTES,
      (item: CacheBudgetItem): boolean => books.has(item.owner) || now - item.usedAt < ReaderCacheBudget.RECENT_PROTECT_MS);
    const selected = new Set(plan.removeIds);
    const result = await ReaderCacheBudget.deleteText(entries.filter((entry: CachedContentEntry): boolean => selected.has('' + entry.rowId)), false,
      now - ReaderCacheBudget.RECENT_PROTECT_MS);
    result.remainingBytes = await appDb.getOnlineCachedContentBytes();
    ReaderCacheBudget.textOver = result.remainingBytes > ReaderCacheBudget.TEXT_LIMIT_BYTES;
    if (ReaderCacheBudget.textOver) {
      const recent = entries.filter((entry: CachedContentEntry): boolean => !books.has(entry.bookUrl) && entry.usedAt > now - 600000);
      if (recent.length) ReaderCacheBudget.scheduleText(Math.max(1000, Math.min(...recent.map((entry: CachedContentEntry): number => entry.usedAt + 600000 - now)) + 100));
      else if (result.failed || result.removed < selected.size) ReaderCacheBudget.scheduleText(60000);
    }
    console.info('[CacheBudget] text removed=' + result.removed + ' remaining=' + result.remainingBytes);
  }

  private static async deleteText(entries: CachedContentEntry[], offline: boolean, cutoff: number): Promise<ReaderCacheCleanup> {
    const result = new ReaderCacheCleanup();
    for (let offset = 0; offset < entries.length; offset += 50) {
      const batch = entries.slice(offset, offset + 50);
      try {
        const removed = await appDb.deleteCachedContentEntries(batch, offline, cutoff);
        result.removed += removed.removed; result.releasedBytes += removed.releasedBytes;
        result.protectedCount += batch.length - removed.removed;
      } catch (e) { result.failed += batch.length; console.warn('[CacheBudget] delete text failed', e); }
      await ReaderCacheBudget.yield();
    }
    return result;
  }

  private static async trimComic(): Promise<void> {
    await ReaderCacheBudget.prepare();
    if (await ReaderImageCache.migrateLegacy()) ReaderCacheBudget.scheduleComic(60000);
    const pinned = new Set(await appDb.imagePaths(true));
    const items = (await ReaderCacheBudget.listComicFiles()).filter((item: CacheBudgetItem): boolean => !pinned.has(item.id));
    const total = items.reduce((sum: number, item: CacheBudgetItem): number => sum + item.bytes, 0);
    ReaderCacheBudget.comicOver = total > ReaderCacheBudget.COMIC_LIMIT_BYTES;
    if (!ReaderCacheBudget.comicOver) return;
    const result = await ReaderCacheBudget.deleteImages(items, total - Math.floor(ReaderCacheBudget.COMIC_LIMIT_BYTES * 0.9));
    result.remainingBytes = Math.max(0, total - result.releasedBytes);
    ReaderCacheBudget.comicOver = result.remainingBytes > ReaderCacheBudget.COMIC_LIMIT_BYTES;
    if (ReaderCacheBudget.comicOver) {
      const now = Date.now();
      const due = items.map((item: CacheBudgetItem): number => Math.max(item.usedAt, ReaderImageCache.lastUse(item.id)) + 600000 - now)
        .filter((delay: number): boolean => delay > 0);
      if (due.length) ReaderCacheBudget.scheduleComic(Math.max(1000, Math.min(...due) + 100));
      else if (result.failed) ReaderCacheBudget.scheduleComic(60000);
    }
    console.info('[CacheBudget] comic removed=' + result.removed + ' remaining=' + result.remainingBytes + ' failed=' + result.failed);
  }

  private static async deleteImages(items: CacheBudgetItem[], wanted: number): Promise<ReaderCacheCleanup> {
    const result = new ReaderCacheCleanup();
    // Evict regenerable derivatives before originals; both groups use actual access time.
    const original = ReaderImageCache.directory();
    const referenced = new Set(await appDb.imagePaths());
    const ordered = [...items].sort((a: CacheBudgetItem, b: CacheBudgetItem): number =>
      Number(a.id.startsWith(original + '/') || referenced.has(a.id)) - Number(b.id.startsWith(original + '/') || referenced.has(b.id)) || a.usedAt - b.usedAt);
    for (let offset = 0; offset < ordered.length && result.releasedBytes < wanted; offset += 20) {
      await ReaderCacheCoordinator.run(async (): Promise<void> => {
        const protectedPaths = new Set(await appDb.imagePaths(true));
        for (const item of ordered.slice(offset, offset + 20)) {
          if (result.releasedBytes >= wanted) break;
          if (!ReaderImageCache.managed(item.id)) continue;
          if (protectedPaths.has(item.id) || ReaderCacheCoordinator.fileInUse(item.id) ||
            Date.now() - Math.max(item.usedAt, ReaderImageCache.lastUse(item.id)) < 600000) {
            result.protectedCount++; continue;
          }
          try {
            await appDb.markImageDeleting(item.id);
            // A view can acquire a lease while the metadata write is suspended.
            if (ReaderCacheCoordinator.fileInUse(item.id) || Date.now() - ReaderImageCache.lastUse(item.id) < 600000) {
              result.protectedCount++; continue;
            }
            const stat = fs.statSync(item.id);
            // Rewritten files never inherit an old deletion decision.
            if (!stat.isFile() || stat.size !== item.bytes || stat.mtime * 1000 > item.usedAt) {
              ReaderCacheBudget.comicIndexAt = 0; ReaderCacheBudget.scheduleComic(15000);
              result.protectedCount++; continue;
            }
            fs.unlinkSync(item.id);
            ReaderCacheBudget.comicIndex.delete(item.id);
            ReaderImageResults.invalidatePath(item.id);
            result.removed++; result.releasedBytes += stat.size;
            await appDb.markImageMissing(item.id);
          } catch (e) {
            if (!ReaderImageCache.exists(item.id)) {
              ReaderCacheBudget.comicIndex.delete(item.id);
              try { await appDb.markImageMissing(item.id); } catch (_) { result.failed++; }
            } else result.failed++;
          }
        }
      });
      await ReaderCacheBudget.yield();
    }
    return result;
  }

  private static async listComicFiles(force: boolean = false): Promise<CacheBudgetItem[]> {
    const key = ReaderImageCache.directory() + '|' + ReaderImageCache.legacyDirectory();
    const now = Date.now();
    if (!force && ReaderCacheBudget.comicIndexDir === key && ReaderCacheBudget.comicIndexAt > 0 &&
      now >= ReaderCacheBudget.comicIndexAt && now - ReaderCacheBudget.comicIndexAt < 300000 &&
      ReaderCacheBudget.comicRevision === ReaderImageCache.fileRevision) return Array.from(ReaderCacheBudget.comicIndex.values());
    ReaderCacheBudget.comicIndexAt = 0;
    const revision = ReaderImageCache.fileRevision;
    const items: CacheBudgetItem[] = [];
    const records = new Map<string, ReaderImageResource>();
    for (const record of await appDb.listImageResources()) records.set(record.path, record);
    for (const dir of [ReaderImageCache.directory(), ReaderImageCache.legacyDirectory()]) {
      if (!dir || !fs.accessSync(dir)) continue;
      for (const name of await fs.listFile(dir)) {
        const path = dir + '/' + name;
        if (!ReaderImageCache.managed(path)) continue;
        try {
          const stat = await fs.stat(path);
          if (!stat.isFile()) continue;
          if (/\.(tmp|part)$/.test(name)) {
            if (Date.now() - stat.mtime * 1000 > 3600000 && !ReaderCacheCoordinator.fileInUse(path.replace(/\.(tmp|part)$/, ''))) {
              await ReaderCacheCoordinator.run(async (): Promise<void> => {
                if (!ReaderCacheCoordinator.fileInUse(path.replace(/\.(tmp|part)$/, '')) &&
                  Date.now() - fs.statSync(path).mtime * 1000 > 3600000) fs.unlinkSync(path);
              });
            }
            continue;
          }
          const record = records.get(path);
          const item = new CacheBudgetItem(); item.id = path; item.bytes = stat.size;
          item.usedAt = Math.max(stat.mtime * 1000, record?.usedAt || 0, ReaderImageCache.lastUse(path));
          items.push(item);
          if (!record || record.state !== 'ready' || record.bytes !== stat.size) {
            await ReaderCacheCoordinator.run(async (): Promise<void> => {
              const row = await appDb.imageResource(path) || new ReaderImageResource();
              row.path = path; row.bytes = stat.size; row.usedAt = item.usedAt; row.state = 'ready';
              await appDb.saveImageResource(row);
            });
          }
        } catch (_) {}
      }
    }
    const seen = new Set(items.map((item: CacheBudgetItem): string => item.id));
    await ReaderCacheCoordinator.run(async (): Promise<void> => {
      for (const [path, record] of records) {
        if (record.state !== 'missing' && ReaderImageCache.managed(path) && !seen.has(path) &&
          !ReaderCacheCoordinator.fileInUse(path) && !ReaderImageCache.exists(path)) {
          await appDb.markImageMissing(path);
          ReaderImageResults.invalidatePath(path);
        }
      }
      await appDb.pruneImageRecords(Date.now() - 7 * 24 * 3600000);
    });
    ReaderCacheBudget.comicIndex = new Map(items.map((item: CacheBudgetItem): [string, CacheBudgetItem] => [item.id, item]));
    ReaderCacheBudget.comicIndexDir = key; ReaderCacheBudget.comicIndexAt = now;
    ReaderCacheBudget.comicRevision = revision;
    return items;
  }

  private static enqueueValue<T>(task: () => Promise<T>): Promise<T> {
    const next = ReaderCacheBudget.chain.then(task, task);
    ReaderCacheBudget.chain = next.then((): void => {}, (): void => {});
    return next;
  }

  private static enqueue(task: () => Promise<void>): void {
    ReaderCacheBudget.chain = ReaderCacheBudget.chain.then(task, task).catch((e: Error): void => console.warn('[CacheBudget]', e));
  }

  private static async yield(): Promise<void> {
    await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 0); });
  }
}
