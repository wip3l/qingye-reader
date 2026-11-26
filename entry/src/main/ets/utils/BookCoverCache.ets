import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { fileUri } from '../platform/FileUri';
import http from '@ohos.net.http';
import { HttpClient, SourceCoverLoader, SourceCoverUrl } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { CoverUrlNormalizer } from './CoverUrlNormalizer';
import { CoverFailures } from './CoverFailures';
import { CoverFailureStore } from './CoverFailureStore';
import { copyFile } from '../platform/Files';

/** 一次封面下载的结果。path 为空时 definite 表示服务器明确没有这张图（值得记为取不到），否则只是这会儿没取到。 */
interface CoverDownload {
  path: string;
  definite: boolean;
}

export class BookCoverCache {
  private static resolvedCoverUris: Map<string, string> = new Map();
  private static inFlightResolutions: Map<string, Promise<string>> = new Map();
  private static activeNetworkTasks: number = 0;
  private static writeSerial: number = 0;
  private static readonly MAX_NETWORK_TASKS: number = 4;
  private static networkWaiters: Array<() => void> = [];
  // 书源声明了 coverDecode 的封面：地址带 SourceCoverUrl 标记，下载后要用该书源的参数解密才是图片。
  private static sourceCoverHttp: HttpClient | null = null;
  private static sourceCoverFailedAt: Map<string, number> = new Map();
  private static readonly SOURCE_COVER_RETRY_MS: number = 60000;
  private static sourceCoverRevisionTimer: number = -1;

  /**
   * Cover address an Image can load. An encrypted source cover is never handed to Image directly: until its
   * decrypted copy is cached this returns '' (callers show their placeholder) and starts decrypting in the
   * background; when that finishes, AppStorage `sourceCoverRevision` is bumped so views that read it re-render.
   * Other addresses are returned unchanged.
   */
  static displayCover(context: Context, raw: string): string {
    if (!raw || !SourceCoverUrl.isEncoded(raw)) return raw;
    const cached = BookCoverCache.resolveCachedCover(context, raw);
    if (cached) return cached;
    const failedAt = BookCoverCache.sourceCoverFailedAt.get(raw) || 0;
    if (!BookCoverCache.inFlightResolutions.has(raw) && Date.now() - failedAt > BookCoverCache.SOURCE_COVER_RETRY_MS) {
      BookCoverCache.resolveCover(context, raw).then((resolved: string) => {
        if (resolved) {
          BookCoverCache.sourceCoverFailedAt.delete(raw);
          BookCoverCache.bumpSourceCoverRevision();
        } else {
          BookCoverCache.sourceCoverFailedAt.set(raw, Date.now());
        }
      }).catch(() => {
        BookCoverCache.sourceCoverFailedAt.set(raw, Date.now());
      });
    }
    return '';
  }

  /** Decrypted bytes of an encrypted source cover, or null when the source is missing or decoding fails. */
  static async loadSourceCoverBytes(raw: string): Promise<Uint8Array | null> {
    try {
      const source = await AppDatabase.getInstance().getBookSource(SourceCoverUrl.source(raw));
      if (!source) return null;
      if (!BookCoverCache.sourceCoverHttp) BookCoverCache.sourceCoverHttp = new HttpClient(15000);
      const data = await SourceCoverLoader.load(BookCoverCache.sourceCoverHttp, source, raw);
      return data.byteLength > 0 ? data : null;
    } catch (e) {
      console.warn('解密书源封面失败:', e instanceof Error ? e.message : String(e));
      return null;
    }
  }

  private static bumpSourceCoverRevision(): void {
    // 一屏封面陆续解密完成时合并成一次刷新。
    if (BookCoverCache.sourceCoverRevisionTimer !== -1) return;
    BookCoverCache.sourceCoverRevisionTimer = setTimeout(() => {
      BookCoverCache.sourceCoverRevisionTimer = -1;
      AppStorage.setOrCreate<number>('sourceCoverRevision', (AppStorage.get<number>('sourceCoverRevision') || 0) + 1);
    }, 200);
  }

  static resolveCachedCover(context: Context, raw: string): string {
    if (!raw || (!raw.startsWith('http://') && !raw.startsWith('https://'))) {
      return '';
    }
    const remembered = BookCoverCache.resolvedCoverUris.get(raw);
    if (remembered && BookCoverCache.exists(BookCoverCache.cachedCoverPath(context, raw))) return remembered;
    BookCoverCache.resolvedCoverUris.delete(raw);
    const cachedPath = BookCoverCache.cachedCoverPath(context, raw);
    if (!BookCoverCache.exists(cachedPath)) return '';
    const resolved = fileUri.getUriFromPath(cachedPath);
    BookCoverCache.resolvedCoverUris.set(raw, resolved);
    return resolved;
  }

  static async resolveCachedCoverAsync(context: Context, raw: string): Promise<string> {
    if (!raw || (!raw.startsWith('http://') && !raw.startsWith('https://'))) return '';
    const remembered = BookCoverCache.resolvedCoverUris.get(raw);
    if (remembered && await BookCoverCache.existsAsync(BookCoverCache.cachedCoverPath(context, raw))) return remembered;
    BookCoverCache.resolvedCoverUris.delete(raw);
    const cachedPath = BookCoverCache.cachedCoverPath(context, raw);
    if (!(await BookCoverCache.existsAsync(cachedPath))) return '';
    const resolved = fileUri.getUriFromPath(cachedPath);
    BookCoverCache.resolvedCoverUris.set(raw, resolved);
    return resolved;
  }

  static async resolveCover(context: Context, raw: string): Promise<string> {
    const active = BookCoverCache.inFlightResolutions.get(raw);
    if (active) return await active;
    const task = BookCoverCache.resolveCoverInternal(context, raw);
    BookCoverCache.inFlightResolutions.set(raw, task);
    try {
      return await task;
    } finally {
      if (BookCoverCache.inFlightResolutions.get(raw) === task) {
        BookCoverCache.inFlightResolutions.delete(raw);
      }
    }
  }

  private static async resolveCoverInternal(context: Context, raw: string): Promise<string> {
    if (!raw) {
      return '';
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      const cachedPath = BookCoverCache.cachedCoverPath(context, raw);
      if (await BookCoverCache.existsAsync(cachedPath)) {
        const resolved = fileUri.getUriFromPath(cachedPath);
        BookCoverCache.resolvedCoverUris.set(raw, resolved);
        return resolved;
      }
      // 下载前先看有没有网：没网时的失败不算这个地址取不到。
      const online = CoverFailureStore.online();
      const download = await BookCoverCache.downloadCover(context, raw);
      if (!download.path) {
        // 超时、断连、5xx 只说明这会儿取不到，记下来会让封面两天都换成兜底。
        if (online && download.definite) CoverFailureStore.markFailed(context, raw);
        return SourceCoverUrl.isEncoded(raw) ? '' : raw;
      }
      CoverFailureStore.markLoaded(context, raw);
      const resolved = fileUri.getUriFromPath(download.path);
      BookCoverCache.resolvedCoverUris.set(raw, resolved);
      return resolved;
    }
    const localPath = BookCoverCache.localPathFromUri(raw);
    if (localPath && await BookCoverCache.existsAsync(localPath)) {
      return raw.startsWith('file://') ? raw : fileUri.getUriFromPath(localPath);
    }
    const copiedPath = await BookCoverCache.copyCoverUriToCache(context, raw);
    if (copiedPath) {
      return fileUri.getUriFromPath(copiedPath);
    }
    if (BookCoverCache.isForeignLocalCover(raw, localPath)) CoverFailureStore.markFailed(context, raw);
    return raw;
  }

  /**
   * 本机读不到的本地封面：绝对路径上没有文件，或是别的系统的 content:// 地址（多见于从安卓备份带过来的自定义封面）。
   * 其余写法的地址（应用沙箱 URI、媒体库 URI、data: 等）这里判断不了存不存在，不下结论。
   */
  private static isForeignLocalCover(raw: string, localPath: string): boolean {
    return raw.startsWith('content://') || localPath.startsWith('/');
  }

  /** 不经下载的本地封面显示不出来时调用：确认文件确实不在，就记为取不到。 */
  static async checkLocalCover(context: Context, raw: string): Promise<void> {
    if (!raw || raw.startsWith('http://') || raw.startsWith('https://') || CoverFailures.has(raw)) return;
    const localPath = BookCoverCache.localPathFromUri(raw);
    if (!BookCoverCache.isForeignLocalCover(raw, localPath)) return;
    if (localPath && await BookCoverCache.existsAsync(localPath)) return;
    CoverFailureStore.markFailed(context, raw);
  }

  static async prepareCoverFile(context: Context, raw: string): Promise<string> {
    if (!raw) {
      return '';
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      const cachedPath = BookCoverCache.cachedCoverPath(context, raw);
      if (await BookCoverCache.existsAsync(cachedPath)) {
        return cachedPath;
      }
      return (await BookCoverCache.downloadCover(context, raw)).path;
    }
    const localPath = BookCoverCache.localPathFromUri(raw);
    if (localPath && await BookCoverCache.existsAsync(localPath)) {
      return localPath;
    }
    return await BookCoverCache.copyCoverUriToCache(context, raw);
  }

  /** 本机现成的封面文件路径（网络封面的缓存、本地封面本身或它的缓存副本），不联网；没有返回空串。 */
  static async localCoverFile(context: Context, raw: string): Promise<string> {
    if (!raw) return '';
    const cachedPath = BookCoverCache.cachedCoverPath(context, raw);
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return await BookCoverCache.existsAsync(cachedPath) ? cachedPath : '';
    }
    const localPath = BookCoverCache.localPathFromUri(raw);
    if (localPath && await BookCoverCache.existsAsync(localPath)) return localPath;
    return await BookCoverCache.existsAsync(cachedPath) ? cachedPath : '';
  }

  static deleteCachedCover(context: Context, raw: string): void {
    if (!raw) {
      return;
    }
    BookCoverCache.resolvedCoverUris.delete(raw);
    BookCoverCache.sourceCoverFailedAt.delete(raw);
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      BookCoverCache.deletePath(BookCoverCache.cachedCoverPath(context, raw));
      return;
    }
    BookCoverCache.deletePath(BookCoverCache.cachedCoverPath(context, raw));
    const localPath = BookCoverCache.localPathFromUri(raw);
    if (!localPath || !BookCoverCache.isAppOwnedPath(context, localPath)) {
      return;
    }
    BookCoverCache.deletePath(localPath);
  }

  // 调用方自行取回的封面（如需要登录凭据的书库）落到同一份缓存里。
  static async storeCover(context: Context, raw: string, data: Uint8Array): Promise<string> {
    if (!raw || data.byteLength === 0) return '';
    await BookCoverCache.ensureDirAsync(`${context.cacheDir}/book_covers`);
    const path = BookCoverCache.cachedCoverPath(context, raw);
    await BookCoverCache.writeFile(path, data);
    const resolved = fileUri.getUriFromPath(path);
    BookCoverCache.resolvedCoverUris.set(raw, resolved);
    return resolved;
  }

  private static downloaded(path: string, definite: boolean): CoverDownload {
    const result: CoverDownload = { path: path, definite: definite };
    return result;
  }

  /** 服务器明确说没有这张图：4xx（请求超时 408、限流 429 除外）。5xx 多半是一时的。 */
  private static isDefiniteMiss(code: number): boolean {
    return code >= 400 && code < 500 && code !== 408 && code !== 429;
  }

  private static async downloadCover(context: Context, url: string): Promise<CoverDownload> {
    const dir = `${context.cacheDir}/book_covers`;
    await BookCoverCache.ensureDirAsync(dir);
    const path = BookCoverCache.cachedCoverPath(context, url);
    if (await BookCoverCache.existsAsync(path)) {
      return BookCoverCache.downloaded(path, false);
    }
    await BookCoverCache.acquireNetworkSlot();
    try {
      // Another request may have completed while this one waited for a slot.
      if (await BookCoverCache.existsAsync(path)) return BookCoverCache.downloaded(path, false);
      if (SourceCoverUrl.isEncoded(url)) {
        const data = await BookCoverCache.loadSourceCoverBytes(url);
        if (!data) return BookCoverCache.downloaded('', true);
        await BookCoverCache.writeFile(path, data);
        return BookCoverCache.downloaded(path, false);
      }
      const candidates = CoverUrlNormalizer.downloadCandidates(url);
      // 每个候选地址都被服务器明确拒绝才算确定取不到；有一个是超时或断连就不下结论。
      let definite = candidates.length > 0;
      for (const requestUrl of candidates) {
        const request = http.createHttp();
        try {
          const response = await request.request(requestUrl, {
            method: http.RequestMethod.GET,
            connectTimeout: 10000,
            readTimeout: 10000,
            // 不走 HTTP/2：并发的封面会挤在同一条连接上，这条连接一卡住（真机上见过番茄封面 CDN 一卡几分钟），
            // 之后每张都复用它、全部超时。HTTP/1.1 每个请求各占一条连接，超时的那条随请求一起丢掉。
            usingProtocol: http.HttpProtocol.HTTP1_1,
            expectDataType: http.HttpDataType.ARRAY_BUFFER,
            header: {
              'User-Agent': 'Mozilla/5.0 (Linux; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
              'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
              'Referer': BookCoverCache.refererFromUrl(requestUrl),
              'Origin': BookCoverCache.originFromUrl(requestUrl)
            }
          });
          if (response.responseCode < 200 || response.responseCode >= 300 || !(response.result instanceof ArrayBuffer)) {
            if (!BookCoverCache.isDefiniteMiss(response.responseCode)) definite = false;
            continue;
          }
          if (response.result.byteLength === 0) continue;
          await BookCoverCache.writeFile(path, new Uint8Array(response.result));
          return BookCoverCache.downloaded(path, false);
        } catch (e) {
          definite = false;
          console.warn('下载书籍封面失败:', e);
        } finally {
          request.destroy();
        }
      }
      return BookCoverCache.downloaded('', definite);
    } finally {
      BookCoverCache.releaseNetworkSlot();
    }
  }

  private static async writeFile(path: string, data: Uint8Array): Promise<void> {
    if (data.byteLength === 0) throw new Error('Empty cover image');
    // 最终路径只在完整写入并关闭后出现，其他封面刷新不能读到半张图片。
    const temporary = `${path}.part-${++BookCoverCache.writeSerial}`;
    try {
      const file = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        let offset = 0;
        while (offset < data.byteLength) {
          const bytes = data.buffer.slice(data.byteOffset + offset, data.byteOffset + data.byteLength);
          const written = await fs.write(file.fd, bytes);
          if (written <= 0) throw new Error('Incomplete cover image write');
          offset += written;
        }
      } finally {
        await fs.close(file);
      }
      await fs.rename(temporary, path);
    } finally {
      // 失败只清理临时文件，不能损坏此前已完成的缓存。
      try { await fs.unlink(temporary); } catch (_) {}
    }
  }

  private static async acquireNetworkSlot(): Promise<void> {
    if (BookCoverCache.activeNetworkTasks < BookCoverCache.MAX_NETWORK_TASKS) {
      BookCoverCache.activeNetworkTasks++;
      return;
    }
    await new Promise<void>((resolve) => {
      BookCoverCache.networkWaiters.push(resolve);
    });
  }

  private static releaseNetworkSlot(): void {
    const next = BookCoverCache.networkWaiters.shift();
    if (next) {
      next();
      return;
    }
    BookCoverCache.activeNetworkTasks = Math.max(0, BookCoverCache.activeNetworkTasks - 1);
  }

  private static async copyCoverUriToCache(context: Context, raw: string): Promise<string> {
    if (!raw || raw.startsWith('http://') || raw.startsWith('https://')) {
      return '';
    }
    const dir = `${context.cacheDir}/book_covers`;
    await BookCoverCache.ensureDirAsync(dir);
    const path = BookCoverCache.cachedCoverPath(context, raw);
    if (await BookCoverCache.existsAsync(path)) {
      return path;
    }
    try {
      const source = raw.startsWith('/') ? fileUri.getUriFromPath(raw) : raw;
      await copyFile(source, fileUri.getUriFromPath(path));
      return await BookCoverCache.existsAsync(path) ? path : '';
    } catch (e) {
      console.warn('复制书籍封面到缓存失败:', e);
      BookCoverCache.deletePath(path);
      return '';
    }
  }

  private static localPathFromUri(raw: string): string {
    if (raw.startsWith('file://')) {
      return decodeURIComponent(raw.substring('file://'.length));
    }
    return raw.startsWith('/') ? raw : '';
  }

  private static exists(path: string): boolean {
    try {
      return fs.statSync(path).size > 0;
    } catch (e) {
      return false;
    }
  }

  private static async existsAsync(path: string): Promise<boolean> {
    try {
      return (await fs.stat(path)).size > 0;
    } catch (e) {
      return false;
    }
  }

  private static async ensureDirAsync(path: string): Promise<void> {
    try {
      await fs.mkdir(path, true);
    } catch (e) {
    }
  }

  private static cachedCoverPath(context: Context, url: string): string {
    return `${context.cacheDir}/book_covers/${BookCoverCache.hashText(url)}${BookCoverCache.coverExt(url)}`;
  }

  private static isAppOwnedPath(context: Context, path: string): boolean {
    return path.startsWith(`${context.filesDir}/covers/`) || path.startsWith(`${context.cacheDir}/book_covers/`);
  }

  private static deletePath(path: string): void {
    try {
      if (path && BookCoverCache.exists(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      console.warn('删除书籍封面缓存失败:', e);
    }
  }

  private static coverExt(value: string): string {
    const lower = value.toLowerCase();
    if (lower.includes('.png')) return '.png';
    if (lower.includes('.webp')) return '.webp';
    if (lower.includes('.bmp')) return '.bmp';
    if (lower.includes('.gif')) return '.gif';
    return '.jpg';
  }

  private static originFromUrl(url: string): string {
    const match = url.match(/^(https?:\/\/[^\/]+)/);
    return match ? match[1] : '';
  }

  private static refererFromUrl(url: string): string {
    const origin = BookCoverCache.originFromUrl(url);
    return origin ? `${origin}/` : '';
  }

  private static hashText(value: string): string {
    let hash = 0;
    for (let i = 0; i < value.length; i++) {
      hash = value.charCodeAt(i) + ((hash << 5) - hash);
    }
    return Math.abs(hash).toString(16);
  }
}
