import fs from '@ohos.file.fs';
import { appDb, ReaderImageResource } from '../../model/data/AppDatabase';
import { ReaderCacheCoordinator } from './ReaderCacheCoordinator';
import { ReaderImageReferences } from './ReaderImageReferences';
import { ReaderImageMarker } from './ReaderImageMarker';

/** Original images have durable, content-identity filenames. Derived AI files remain disposable. */
export class ReaderImageCache {
  static fileRevision: number = 0;
  static writeFailureEpoch: number = 0;
  private static recent: Map<string, number> = new Map();
  private static flushTimer: number = -1;
  private static aliases: Map<string, string> = new Map();

  static directory(): string {
    const root = AppStorage.get<string>('appFilesDir') || '';
    return root ? `${root}/reader_images` : '';
  }

  static legacyDirectory(): string {
    const root = AppStorage.get<string>('appCacheDir') || '';
    return root ? `${root}/comic_images` : '';
  }

  static managed(path: string): boolean {
    const value = ReaderCacheCoordinator.path(path);
    return [ReaderImageCache.directory(), ReaderImageCache.legacyDirectory()].some((dir: string): boolean => {
      if (!dir || !value.startsWith(`${dir}/`)) return false;
      const name = value.substring(dir.length + 1);
      return !!name && name !== '.' && name !== '..' && !/[\\/]/.test(name);
    });
  }

  static exists(path: string): boolean {
    try { const stat = fs.statSync(ReaderCacheCoordinator.path(path)); return stat.isFile() && stat.size > 0; }
    catch (_) { return false; }
  }

  static touch(path: string): void {
    path = ReaderCacheCoordinator.path(path);
    if (!ReaderImageCache.managed(path)) return;
    ReaderImageCache.recent.set(path, Date.now());
    if (ReaderImageCache.flushTimer >= 0) return;
    ReaderImageCache.flushTimer = setTimeout((): void => {
      ReaderImageCache.flushTimer = -1;
      ReaderImageCache.flush().catch((e: Error): void => console.warn('[ImageCache] access flush failed', e));
    }, 5000);
  }

  static lastUse(path: string): number { return ReaderImageCache.recent.get(path) || 0; }

  static async flush(): Promise<void> {
    const pending = Array.from(ReaderImageCache.recent.entries());
    await ReaderCacheCoordinator.run(async (): Promise<void> => {
      for (const [path, time] of pending) await appDb.touchImageResource(path, time);
    });
    for (const [path, time] of pending) {
      if (ReaderImageCache.recent.get(path) === time && Date.now() - time > 600000) ReaderImageCache.recent.delete(path);
    }
  }

  static normalize(text: string): string {
    for (const path of ReaderImageReferences.paths(text)) {
      const next = ReaderImageCache.aliases.get(path);
      if (next && ReaderImageCache.exists(next)) text = ReaderImageReferences.replace(text, path, next);
    }
    return text;
  }

  static complete(text: string, offline: boolean = false): boolean {
    if (ReaderImageMarker.hasFailure(text) || ReaderImageMarker.hasPending(text)) return false;
    for (const marker of ReaderImageReferences.markers(text)) {
      const source = ReaderImageMarker.parse(marker).source;
      const path = ReaderCacheCoordinator.path(source);
      if (path.startsWith('/') && !ReaderImageCache.exists(path)) return false;
      if (offline && !path.startsWith('/') && !/^data:image\//i.test(source)) return false;
    }
    return true;
  }

  static touchText(text: string): void {
    for (const path of ReaderImageReferences.paths(text)) ReaderImageCache.touch(path);
  }

  static retainText(text: string): () => void {
    const releases = ReaderImageReferences.paths(text).map((path: string): (() => void) => ReaderCacheCoordinator.retainFile(path));
    return (): void => { for (const release of releases) release(); };
  }

  static async registerExisting(path: string, sourceUrl: string, raw: string, imageIndex: number): Promise<void> {
    await ReaderCacheCoordinator.run(async (): Promise<void> => {
      const row = await appDb.imageResource(path) || new ReaderImageResource();
      row.path = path; row.sourceUrl = sourceUrl; row.raw = raw.length <= 65536 && !/^data:/i.test(raw) ? raw : '';  row.imageIndex = imageIndex;
      row.bytes = fs.statSync(path).size; row.usedAt = Date.now(); row.state = 'ready';
      await appDb.saveImageResource(row);
    });
  }

  static async commit(path: string, bytes: Uint8Array, sourceUrl: string, raw: string, imageIndex: number): Promise<void> {
    if (!ReaderImageCache.managed(path)) throw new Error('图片缓存目录不可用');
    const release = ReaderCacheCoordinator.retainFile(path);
    try {
      await ReaderCacheCoordinator.run(async (): Promise<void> => {
        const temp = `${path}.part`;
        const file = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try {
          let offset = 0;
          while (offset < bytes.length) {
            const written = fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset + offset, bytes.byteOffset + bytes.byteLength));
            if (written <= 0) throw new Error('图片缓存写入失败，设备空间可能不足');
            offset += written;
          }
          fs.fsyncSync(file.fd);
        } finally { fs.closeSync(file); }
        if (fs.statSync(temp).size !== bytes.length) throw new Error('图片缓存写入不完整');
        fs.renameSync(temp, path);
        const row = new ReaderImageResource();
        row.path = path; row.raw = raw; row.sourceUrl = sourceUrl; row.imageIndex = imageIndex;
        row.bytes = bytes.length; row.usedAt = Date.now();
        await appDb.saveImageResource(row);
        ReaderImageCache.touch(path);
      });
    } catch (e) {
      ReaderImageCache.writeFailureEpoch++;
      throw e;
    } finally { release(); }
  }

  /** Copy first, commit references second. Old files are swept only after all persisted users switch. */
  static async migrateLegacy(onlyPaths: string[] | null = null): Promise<boolean> {
    const dir = ReaderImageCache.directory();
    const legacy = ReaderImageCache.legacyDirectory();
    if (!dir || !legacy) return false;
    const paths = onlyPaths || await appDb.imagePaths();
    const active = new Set(await appDb.imagePaths(true, ReaderCacheCoordinator.protectedBooks()));
    let migrated = 0;
    let pending = false;
    for (const previous of paths) {
      if (!previous.startsWith(`${legacy}/`) || !ReaderImageCache.managed(previous)) continue;
      // Missing legacy originals cannot be reconstructed from their hash; chapter reload repairs them later.
      if (!ReaderImageCache.exists(previous)) continue;
      if (!onlyPaths && migrated >= 20) { pending = true; break; }
      // Pinning does not prevent copying; leave the original available to already decoded/live chapters.
      await ReaderCacheCoordinator.run(async (): Promise<void> => {
        const next = `${dir}/legacy_${previous.substring(legacy.length + 1)}`;
        if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
        const temp = `${next}.part`;
        await fs.copyFile(previous, temp);
        if (fs.statSync(previous).size !== fs.statSync(temp).size) throw new Error('旧图片迁移校验失败');
        fs.renameSync(temp, next);
        ReaderImageCache.fileRevision++;
        const row = await appDb.imageResource(previous) || new ReaderImageResource();
        row.path = next; row.bytes = fs.statSync(next).size; row.usedAt = Date.now(); row.state = 'ready';
        await appDb.saveImageResource(row);
        await appDb.replaceImageReference(previous, next);
        ReaderImageCache.aliases.set(previous, next);
        ReaderImageCache.touch(next);
        if (active.has(previous)) ReaderImageCache.touch(previous);
      });
      migrated++;
    }
    return pending;
  }
}
