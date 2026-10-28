import { BookSource, HttpClient } from '@legado/sourceengine';
import { appDb } from '../../model/data/AppDatabase';
import { ComicImagePipeline } from './ComicImagePipeline';
import { ReaderImageCache } from './ReaderImageCache';
import { ReaderImageScheduler } from './ReaderImageScheduler';
import { ReaderCacheCoordinator } from './ReaderCacheCoordinator';

/** Concurrent views share one recovery. A canceled view never cancels another reader's download. */
export class ReaderImageRecovery {
  private static pending: Map<string, Promise<string>> = new Map();

  static async restore(value: string, sourceHint: BookSource | null = null): Promise<string> {
    const path = ReaderCacheCoordinator.path(value);
    if (!ReaderImageCache.managed(path)) return '';
    if (ReaderImageCache.exists(path)) { ReaderImageCache.touch(path); return path; }
    const previous = ReaderImageRecovery.pending.get(path);
    if (previous) return await previous;
    const task = ReaderImageRecovery.run(path, sourceHint);
    ReaderImageRecovery.pending.set(path, task);
    try { return await task; }
    finally { if (ReaderImageRecovery.pending.get(path) === task) ReaderImageRecovery.pending.delete(path); }
  }

  private static async run(path: string, sourceHint: BookSource | null): Promise<string> {
    const release = ReaderCacheCoordinator.retainFile(path);
    try {
      const row = await appDb.imageResource(path);
      if (!row?.raw || !row.sourceUrl) return '';
      const source = sourceHint?.bookSourceUrl === row.sourceUrl ? sourceHint : await appDb.getBookSource(row.sourceUrl);
      if (!source) return '';
      const next = await ReaderImageScheduler.run(ReaderImageScheduler.foreground, (): boolean => false,
        (): Promise<string> => ComicImagePipeline.materialize(new HttpClient(10000), source, row.raw, true,
          (): boolean => false, row.imageIndex));
      if (!ReaderImageCache.exists(next)) return '';
      if (next !== path) {
        await ReaderCacheCoordinator.run(async (): Promise<void> => { await appDb.replaceImageReference(path, next); });
      }
      return next;
    } finally { release(); }
  }
}
