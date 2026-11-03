import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { Book, SearchBook, BookTypeSupport } from '@legado/sourceengine';

export class ChangeSourceCacheSnapshot {
  key: string = '';
  updatedAt: number = 0;
  searched: boolean = false;
  results: SearchBook[] = [];
}

class ChangeSourceCacheEntry extends ChangeSourceCacheSnapshot {
  aliases: string[] = [];
}

/** Local history independent of source metadata, source variables and sync identity. */
export class ChangeSourceResultCache {
  private static readonly STORE_NAME: string = 'change_source_result_cache';
  private static entries: ChangeSourceCacheEntry[] = [];
  private static ready: Promise<void> | null = null;
  private static loaded: boolean = false;
  private static writeQueue: Promise<void> = Promise.resolve();
  private static timer: number = -1;

  private static async initialize(context: Context): Promise<void> {
    if (!ChangeSourceResultCache.ready) ChangeSourceResultCache.ready = ChangeSourceResultCache.read(context);
    await ChangeSourceResultCache.ready;
  }

  private static async read(context: Context): Promise<void> {
    const store = await preferences.getPreferences(context, ChangeSourceResultCache.STORE_NAME);
    const raw = await store.get('history_v3', '');
    try {
      const parsed = JSON.parse(typeof raw === 'string' && raw ? raw : '[]') as ChangeSourceCacheEntry[];
      if (Array.isArray(parsed)) {
        ChangeSourceResultCache.entries = parsed.filter((entry: ChangeSourceCacheEntry): boolean => !!entry &&
          typeof entry.key === 'string' && Array.isArray(entry.aliases) && Array.isArray(entry.results)).slice(0, 30);
      }
    } catch (_) { /* Malformed history must not prevent a new search. */ }
    ChangeSourceResultCache.loaded = true;
  }

  static async load(context: Context, book: Book): Promise<ChangeSourceCacheSnapshot> {
    try { await ChangeSourceResultCache.initialize(context); } catch (error) {
      ChangeSourceResultCache.ready = Promise.resolve();
      ChangeSourceResultCache.loaded = true;
      console.warn('读取换源缓存失败:', error);
    }
    const alias = ChangeSourceResultCache.bookAlias(book);
    const key = BookTypeSupport.mediaCategoryOf(book) + '\n' + ChangeSourceResultCache.normalize(book.name) + '\n' + ChangeSourceResultCache.normalize(book.author);
    let entry = ChangeSourceResultCache.entries.find((item: ChangeSourceCacheEntry): boolean => item.aliases.includes(alias));
    if (!entry) entry = ChangeSourceResultCache.entries.find((item: ChangeSourceCacheEntry): boolean => item.key === key);
    if (!entry) {
      entry = new ChangeSourceCacheEntry();
      entry.key = key;
      // Migrate v2, including expired candidates. Refreshing v3 is explicit.
      try {
        const store = await preferences.getPreferences(context, ChangeSourceResultCache.STORE_NAME);
        const legacyKey = ChangeSourceResultCache.hashKey(ChangeSourceResultCache.normalize(book.name) + '\n' + ChangeSourceResultCache.normalize(book.author));
        const raw = await store.get('entry_v2_' + legacyKey, '');
        const legacy = JSON.parse(typeof raw === 'string' && raw ? raw : '{}') as ChangeSourceCacheSnapshot;
        if (Array.isArray(legacy.results)) {
          entry.results = legacy.results;
          entry.updatedAt = legacy.updatedAt || 0;
          entry.searched = true;
        }
      } catch (_) { /* No usable legacy entry. */ }
      const existing = ChangeSourceResultCache.entries.find((item: ChangeSourceCacheEntry): boolean => item.key === key || item.aliases.includes(alias));
      if (existing) entry = existing;
      else ChangeSourceResultCache.entries.unshift(entry);
    }
    ChangeSourceResultCache.bind(entry, book);
    ChangeSourceResultCache.mergeEntries(entry, [ChangeSourceResultCache.fromBook(book)]);
    ChangeSourceResultCache.touch(entry);
    ChangeSourceResultCache.schedule(context);
    const snapshot = new ChangeSourceCacheSnapshot();
    snapshot.key = entry.key;
    snapshot.updatedAt = entry.updatedAt;
    snapshot.searched = entry.searched;
    snapshot.results = entry.results.map((item: SearchBook): SearchBook => ChangeSourceResultCache.cloneSearchBook(item));
    return snapshot;
  }

  static merge(context: Context, key: string, results: SearchBook[], searched: boolean = true): void {
    const entry = ChangeSourceResultCache.entries.find((item: ChangeSourceCacheEntry): boolean => item.key === key);
    if (!entry) return;
    ChangeSourceResultCache.mergeEntries(entry, results);
    entry.searched = entry.searched || searched;
    if (searched) entry.updatedAt = Date.now();
    ChangeSourceResultCache.touch(entry);
    ChangeSourceResultCache.schedule(context);
  }

  static rememberSwitch(context: Context, key: string, book: Book): void {
    const entry = ChangeSourceResultCache.entries.find((item: ChangeSourceCacheEntry): boolean => item.key === key);
    if (!entry) return;
    ChangeSourceResultCache.bind(entry, book);
    ChangeSourceResultCache.merge(context, key, [ChangeSourceResultCache.fromBook(book)], false);
  }

  private static bind(entry: ChangeSourceCacheEntry, book: Book): void {
    const alias = ChangeSourceResultCache.bookAlias(book);
    entry.aliases = [alias].concat(entry.aliases.filter((value: string): boolean => value !== alias)).slice(0, 100);
  }

  private static bookAlias(book: Book): string {
    return BookTypeSupport.mediaCategoryOf(book) + '\n' + book.origin + '\n' + book.bookUrl;
  }

  private static mergeEntries(entry: ChangeSourceCacheEntry, results: SearchBook[]): void {
    const seen = new Set<string>();
    const merged: SearchBook[] = [];
    for (const item of results.concat(entry.results)) {
      const key = item.origin + '\n' + item.bookUrl;
      if (!item.bookUrl || !item.origin || seen.has(key)) continue;
      seen.add(key);
      merged.push(ChangeSourceResultCache.cloneSearchBook(item));
    }
    entry.results = merged.slice(0, 50);
  }

  private static touch(entry: ChangeSourceCacheEntry): void {
    ChangeSourceResultCache.entries = [entry].concat(ChangeSourceResultCache.entries.filter((item: ChangeSourceCacheEntry): boolean => item !== entry)).slice(0, 30);
  }

  private static schedule(context: Context): void {
    if (ChangeSourceResultCache.timer >= 0) return;
    ChangeSourceResultCache.timer = setTimeout((): void => { ChangeSourceResultCache.flush(context); }, 500);
  }

  static flush(context: Context): Promise<void> {
    // Closing while the initial disk read is pending must not overwrite history with an empty snapshot.
    if (!ChangeSourceResultCache.loaded) return Promise.resolve();
    if (ChangeSourceResultCache.timer >= 0) clearTimeout(ChangeSourceResultCache.timer);
    ChangeSourceResultCache.timer = -1;
    const raw = JSON.stringify(ChangeSourceResultCache.entries);
    // Serialized snapshots prevent a slow old write from overwriting newer candidates/aliases.
    ChangeSourceResultCache.writeQueue = ChangeSourceResultCache.writeQueue.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, ChangeSourceResultCache.STORE_NAME);
      await store.put('history_v3', raw);
      await store.flush();
    }).catch((error: Error): void => { console.warn('保存换源缓存失败:', error); });
    return ChangeSourceResultCache.writeQueue;
  }

  static fromBook(book: Book): SearchBook {
    const item = new SearchBook();
    item.bookUrl = book.bookUrl;
    item.origin = book.origin;
    item.originName = book.originName;
    item.type = book.type;
    item.name = book.name;
    item.author = book.author;
    item.tocUrl = book.tocUrl;
    item.variable = book.variable;
    item.latestChapterTitle = book.latestChapterTitle;
    item.updateTime = book.updateTime;
    return item;
  }

  private static normalize(value: string): string {
    return (value || '').trim().replace(/\s+/g, '').toLowerCase();
  }

  private static hashKey(value: string): string {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index++) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16).padStart(8, '0');
  }

  private static cloneSearchBook(source: SearchBook): SearchBook {
    const target = new SearchBook();
    target.bookUrl = source.bookUrl || '';
    target.origin = source.origin || '';
    target.originName = source.originName || '';
    target.type = source.type || 0;
    target.name = source.name || '';
    target.author = source.author || '';
    target.kind = '';
    target.status = source.status || '';
    target.coverUrl = '';
    target.intro = '';
    target.latestChapterTitle = source.latestChapterTitle || '';
    target.wordCount = '';
    target.updateTime = source.updateTime || '';
    target.tocUrl = source.tocUrl || '';
    target.variable = source.variable || '';
    target.bookSourceComment = '';
    target.customOrder = source.customOrder || 0;
    target.weight = source.weight || 0;
    return target;
  }
}
