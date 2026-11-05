import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import preferences from '@ohos.data.preferences';

/** 关书时那一页的图连同它成立的条件；打开时条件变了就不用图。 */
export class ReaderOpenSnapshotMeta {
  bookUrl: string = '';
  chapterIndex: number = -1;
  /** 阅读页自己定义的渲染身份（排版键、页码、主题等），正文就绪时再比对一次，不同就撤图。 */
  identity: string = '';
  widthPx: number = 0;
  heightPx: number = 0;
  dark: boolean = false;
  themeRevision: number = 0;
  savedAt: number = 0;
  file: string = '';
}

export class ReaderOpenSnapshot {
  meta: ReaderOpenSnapshotMeta;
  pixelMap: image.PixelMap;

  constructor(meta: ReaderOpenSnapshotMeta, pixelMap: image.PixelMap) {
    this.meta = meta;
    this.pixelMap = pixelMap;
  }
}

/**
 * 关书时把当前页的图存下来，下次从书架点开这本书时先把图盖在正文位置、立刻开始翻开动画，正文在图底下排好后再换掉。
 * 图按书各存一张 JPEG（filesDir/reader_open_snapshots），条件记在 preferences；最近两张解码后的位图留在内存里，
 * 同一进程再开不必解码。位图归这里所有，页面只引用不释放。
 */
export class ReaderOpenSnapshotStore {
  private static readonly STORE_NAME: string = 'reader_open_snapshots';
  private static readonly DIR_NAME: string = 'reader_open_snapshots';
  private static readonly MAX_DECODED: number = 2;
  private static readonly MAX_FILES: number = 24;
  private static metas: Map<string, ReaderOpenSnapshotMeta> = new Map<string, ReaderOpenSnapshotMeta>();
  private static decoded: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private static loading: Promise<void> | null = null;
  private static loaded: boolean = false;

  /** 启动或书架挂载时读一次索引，点开书时才能同步判断有没有图。 */
  static prepare(context: Context): Promise<void> {
    if (ReaderOpenSnapshotStore.loaded) return Promise.resolve();
    if (ReaderOpenSnapshotStore.loading) return ReaderOpenSnapshotStore.loading;
    ReaderOpenSnapshotStore.loading = ReaderOpenSnapshotStore.loadIndex(context).catch((error: Error): void => {
      console.warn('[OpenSnapshot] index load failed:', error);
    }).finally((): void => {
      ReaderOpenSnapshotStore.loaded = true;
      ReaderOpenSnapshotStore.loading = null;
    });
    return ReaderOpenSnapshotStore.loading;
  }

  private static async loadIndex(context: Context): Promise<void> {
    const store = await preferences.getPreferences(context, ReaderOpenSnapshotStore.STORE_NAME);
    const all = await store.getAll() as Record<string, preferences.ValueType>;
    const keys = Object.keys(all);
    for (const key of keys) {
      const raw = all[key];
      if (typeof raw !== 'string' || !raw) continue;
      try {
        const parsed = JSON.parse(raw) as ReaderOpenSnapshotMeta;
        const meta = new ReaderOpenSnapshotMeta();
        meta.bookUrl = `${parsed.bookUrl || ''}`;
        meta.chapterIndex = Number(parsed.chapterIndex);
        meta.identity = `${parsed.identity || ''}`;
        meta.widthPx = Number(parsed.widthPx) || 0;
        meta.heightPx = Number(parsed.heightPx) || 0;
        meta.dark = parsed.dark === true;
        meta.themeRevision = Number(parsed.themeRevision) || 0;
        meta.savedAt = Number(parsed.savedAt) || 0;
        meta.file = `${parsed.file || ''}`;
        if (meta.bookUrl && meta.file) ReaderOpenSnapshotStore.metas.set(meta.bookUrl, meta);
      } catch (_) {
        // 坏条目跳过。
      }
    }
  }

  /** 这本书有没有在当前条件下成立的图：章节、窗口尺寸、深浅、主题修订号都要对上。 */
  static usable(bookUrl: string, chapterIndex: number, widthPx: number, heightPx: number, dark: boolean,
    themeRevision: number): ReaderOpenSnapshotMeta | null {
    const meta = ReaderOpenSnapshotStore.metas.get(bookUrl);
    if (!meta) return null;
    if (meta.chapterIndex !== chapterIndex || meta.dark !== dark || meta.themeRevision !== themeRevision) return null;
    if (Math.abs(meta.widthPx - widthPx) > 2 || Math.abs(meta.heightPx - heightPx) > 2) return null;
    return meta;
  }

  /**
   * 取这本书的图：内存里有就立刻给，否则从文件解码，最多等 waitMs（超时返回 null，解码完的图留在内存里下次用）。
   * 条件不符返回 null。
   */
  static open(context: Context, bookUrl: string, chapterIndex: number, widthPx: number, heightPx: number,
    dark: boolean, themeRevision: number, waitMs: number): Promise<ReaderOpenSnapshot | null> {
    const meta = ReaderOpenSnapshotStore.usable(bookUrl, chapterIndex, widthPx, heightPx, dark, themeRevision);
    if (!meta) return Promise.resolve(null);
    const cached = ReaderOpenSnapshotStore.decoded.get(bookUrl);
    if (cached) {
      ReaderOpenSnapshotStore.touch(bookUrl, cached);
      return Promise.resolve(new ReaderOpenSnapshot(meta, cached));
    }
    return new Promise<ReaderOpenSnapshot | null>((resolve: (value: ReaderOpenSnapshot | null) => void): void => {
      let settled = false;
      const timer = setTimeout((): void => {
        if (settled) return;
        settled = true;
        resolve(null);
      }, waitMs);
      ReaderOpenSnapshotStore.decode(context, meta).then((pixelMap: image.PixelMap | null): void => {
        if (pixelMap) ReaderOpenSnapshotStore.retain(bookUrl, pixelMap);
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve(pixelMap ? new ReaderOpenSnapshot(meta, pixelMap) : null);
      });
    });
  }

  private static async decode(context: Context, meta: ReaderOpenSnapshotMeta): Promise<image.PixelMap | null> {
    const path = `${ReaderOpenSnapshotStore.dir(context)}/${meta.file}`;
    try {
      if (!fs.accessSync(path)) {
        ReaderOpenSnapshotStore.metas.delete(meta.bookUrl);
        return null;
      }
      const source = image.createImageSource(path);
      try {
        return await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      } finally {
        source.release().catch((): void => {});
      }
    } catch (error) {
      console.warn('[OpenSnapshot] decode failed:', error);
      return null;
    }
  }

  /**
   * 关书时登记：位图先留在内存（同一进程再开直接用），再异步压成 JPEG 写盘并记下条件。
   * pixelMap 的所有权交给这里。
   */
  static save(context: Context, meta: ReaderOpenSnapshotMeta, pixelMap: image.PixelMap): void {
    ReaderOpenSnapshotStore.persist(context, meta, pixelMap).catch((error: Error): void => {
      console.warn('[OpenSnapshot] save failed:', error);
    });
  }

  private static async persist(context: Context, meta: ReaderOpenSnapshotMeta,
    pixelMap: image.PixelMap): Promise<void> {
    const info = await pixelMap.getImageInfo();
    meta.widthPx = info.size.width;
    meta.heightPx = info.size.height;
    meta.savedAt = Date.now();
    meta.file = `${ReaderOpenSnapshotStore.fileKey(meta.bookUrl)}.jpg`;
    ReaderOpenSnapshotStore.retain(meta.bookUrl, pixelMap);
    ReaderOpenSnapshotStore.metas.set(meta.bookUrl, meta);
    const packer = image.createImagePacker();
    let data: ArrayBuffer;
    try {
      data = await packer.packToData(pixelMap, { format: 'image/jpeg', quality: 85 });
    } finally {
      packer.release().catch((): void => {});
    }
    const dir = ReaderOpenSnapshotStore.dir(context);
    if (!fs.accessSync(dir)) fs.mkdirSync(dir);
    const path = `${dir}/${meta.file}`;
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      await fs.write(file.fd, data);
    } finally {
      fs.closeSync(file);
    }
    const store = await preferences.getPreferences(context, ReaderOpenSnapshotStore.STORE_NAME);
    await store.put(ReaderOpenSnapshotStore.fileKey(meta.bookUrl), JSON.stringify(meta));
    await ReaderOpenSnapshotStore.trimFiles(context, store);
    await store.flush();
  }

  /** 文件数超过上限时删最久没更新的。 */
  private static async trimFiles(context: Context, store: preferences.Preferences): Promise<void> {
    if (ReaderOpenSnapshotStore.metas.size <= ReaderOpenSnapshotStore.MAX_FILES) return;
    const entries = Array.from(ReaderOpenSnapshotStore.metas.values())
      .sort((a: ReaderOpenSnapshotMeta, b: ReaderOpenSnapshotMeta): number => a.savedAt - b.savedAt);
    const excess = entries.length - ReaderOpenSnapshotStore.MAX_FILES;
    for (let i = 0; i < excess; i++) {
      const meta = entries[i];
      ReaderOpenSnapshotStore.metas.delete(meta.bookUrl);
      try {
        const path = `${ReaderOpenSnapshotStore.dir(context)}/${meta.file}`;
        if (fs.accessSync(path)) fs.unlinkSync(path);
      } catch (_) {
        // 删不掉就留着，下次再试。
      }
      await store.delete(ReaderOpenSnapshotStore.fileKey(meta.bookUrl));
    }
  }

  /** 这本书的正文来源变了或被删除：图不再成立。 */
  static forget(context: Context, bookUrl: string): void {
    const meta = ReaderOpenSnapshotStore.metas.get(bookUrl);
    ReaderOpenSnapshotStore.metas.delete(bookUrl);
    const pixelMap = ReaderOpenSnapshotStore.decoded.get(bookUrl);
    if (pixelMap) {
      ReaderOpenSnapshotStore.decoded.delete(bookUrl);
      pixelMap.release().catch((): void => {});
    }
    if (!meta) return;
    preferences.getPreferences(context, ReaderOpenSnapshotStore.STORE_NAME).then(async (store): Promise<void> => {
      await store.delete(ReaderOpenSnapshotStore.fileKey(bookUrl));
      await store.flush();
    }).catch((): void => {});
    try {
      const path = `${ReaderOpenSnapshotStore.dir(context)}/${meta.file}`;
      if (fs.accessSync(path)) fs.unlinkSync(path);
    } catch (_) {
      // 忽略。
    }
  }

  private static retain(bookUrl: string, pixelMap: image.PixelMap): void {
    const previous = ReaderOpenSnapshotStore.decoded.get(bookUrl);
    if (previous && previous !== pixelMap) previous.release().catch((): void => {});
    ReaderOpenSnapshotStore.touch(bookUrl, pixelMap);
    while (ReaderOpenSnapshotStore.decoded.size > ReaderOpenSnapshotStore.MAX_DECODED) {
      const oldest = ReaderOpenSnapshotStore.decoded.keys().next().value as string | undefined;
      if (oldest === undefined) break;
      const dropped = ReaderOpenSnapshotStore.decoded.get(oldest);
      ReaderOpenSnapshotStore.decoded.delete(oldest);
      if (dropped) dropped.release().catch((): void => {});
    }
  }

  private static touch(bookUrl: string, pixelMap: image.PixelMap): void {
    ReaderOpenSnapshotStore.decoded.delete(bookUrl);
    ReaderOpenSnapshotStore.decoded.set(bookUrl, pixelMap);
  }

  private static dir(context: Context): string {
    return `${context.filesDir}/${ReaderOpenSnapshotStore.DIR_NAME}`;
  }

  private static fileKey(bookUrl: string): string {
    let hash = 2166136261;
    for (let i = 0; i < bookUrl.length; i++) {
      hash ^= bookUrl.charCodeAt(i);
      hash = Math.imul(hash, 16777619) >>> 0;
    }
    return `s${hash.toString(16)}_${bookUrl.length}`;
  }
}
