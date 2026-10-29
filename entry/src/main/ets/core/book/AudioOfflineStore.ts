import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import statvfs from '@ohos.file.statvfs';
import { connection } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { AppDatabase, appDb, AudioOfflineFile, AudioOfflineUsage } from '../../model/data/AppDatabase';
import { AudioOfflineEntry, AudioOfflinePolicy, AudioPartialMeta, HlsPlaylist, HlsSegment } from './AudioOfflinePolicy';

/** 一次下载的参数。 */
export class AudioDownloadTask {
  bookUrl: string = '';
  chapterIndex: number = 0;
  chapterUrl: string = '';
  chapterTitle: string = '';
  voice: string = '';
  /** 边听边下发起的；手动下载为 false。 */
  auto: boolean = false;
  url: string = '';
  headers: Record<string, string> = {};
  /** 用户同意过用移动网络下载。为 false 时离开 Wi-Fi 就暂停，等网络恢复。 */
  allowCellular: boolean = false;
  shouldCancel: (() => boolean) | null = null;
  /** 已收到的字节数；total 不知道时为 0。 */
  onProgress: ((received: number, total: number) => void) | null = null;
}

/**
 * 有声书离线下载的音频文件：一章一个文件，平铺在 filesDir/audio_offline 下，记录在 audio_offline_files 表。
 * 直链支持断点续传；m3u8 逐片下载（可 AES-128 解密）后拼成一个文件。不参与缓存自动清理，
 * 只有边听边下的章节会在听过后或超出上限时自动删除。
 */
export class AudioOfflineStore {
  /** 写盘失败或空间不足。离线任务遇到它就整体中止，其余错误只算本章失败。 */
  static readonly STORAGE_FAILURE: string = '音频存储失败，请检查可用空间后重试';
  static readonly CAP_REACHED: string = '已达到离线音频上限，可在其他设置里调整';
  /** 离开 Wi-Fi（且没同意用移动网络）或断网：调用方等网络恢复后重试，半截文件会续上。 */
  static readonly NETWORK_WAIT: string = '等待 Wi-Fi';
  static readonly CANCELED: string = '已取消';

  static readonly WIFI_ONLY_KEY: string = 'audioOfflineWifiOnly';
  static readonly CAP_KEY: string = 'audioOfflineCapBytes';
  static readonly PREFETCH_KEY: string = 'audioPrefetchCount';

  /** 下载前至少留出的可用空间，免得把设备写满。 */
  private static readonly MIN_FREE_BYTES: number = 200 * 1024 * 1024;
  /** 小于这个大小的响应基本是错误页或接口报错，不当成音频。 */
  private static readonly MIN_AUDIO_BYTES: number = 4096;
  private static readonly EXTENSIONS: string = 'aac|ape|flac|m4a|mp3|mp4|ogg|opus|wav|wma';
  /** 半截文件保留多久可以续传；更久的启动清理时删掉。 */
  private static readonly PARTIAL_KEEP_MS: number = 7 * 24 * 3600 * 1000;
  private static readonly SEGMENT_CONCURRENCY: number = 3;
  private static readonly inFlight: Map<string, Promise<void>> = new Map();

  static directory(): string {
    const root = AppStorage.get<string>('appFilesDir') || '';
    return root ? `${root}/audio_offline` : '';
  }

  static wifiOnly(): boolean {
    return AppStorage.get<boolean>(AudioOfflineStore.WIFI_ONLY_KEY) === true;
  }

  static capBytes(): number {
    return Math.max(0, AppStorage.get<number>(AudioOfflineStore.CAP_KEY) || 0);
  }

  static prefetchCount(): number {
    return Math.max(0, AppStorage.get<number>(AudioOfflineStore.PREFETCH_KEY) || 0);
  }

  /** wifi / cellular / none / other（有线等）。查不到时按 other，不拦下载。 */
  static network(): string {
    try {
      if (!connection.hasDefaultNetSync()) return 'none';
      const handle = connection.getDefaultNetSync();
      const bearers = connection.getNetCapabilitiesSync(handle).bearerTypes || [];
      if (bearers.includes(connection.NetBearType.BEARER_WIFI)) return 'wifi';
      if (bearers.includes(connection.NetBearType.BEARER_CELLULAR)) return 'cellular';
      return 'other';
    } catch (_) {
      return 'other';
    }
  }

  /** 现在能不能下载：断网不行；在移动网络上只有用户同意过才行。 */
  static networkAllows(allowCellular: boolean): boolean {
    const network = AudioOfflineStore.network();
    if (network === 'none') return false;
    return network !== 'cellular' || allowCellular;
  }

  static toEntry(file: AudioOfflineFile): AudioOfflineEntry {
    const entry = new AudioOfflineEntry();
    entry.chapterIndex = file.chapterIndex;
    entry.chapterUrl = file.chapterUrl;
    entry.chapterTitle = file.chapterTitle;
    entry.voice = file.voice;
    entry.bytes = file.bytes;
    entry.createdAt = file.createdAt;
    entry.auto = file.auto;
    return entry;
  }

  /**
   * 本章已下载、能直接播的文件路径。章节（地址或标题）和音色都得对得上；
   * 记录还在但文件没了时顺手删掉记录。对不上返回空，调用方改走在线播放。
   */
  static async localFile(bookUrl: string, chapterIndex: number, chapterUrl: string, chapterTitle: string,
    voice: string): Promise<string> {
    if (!bookUrl) return '';
    const file = await appDb.getAudioOfflineFile(bookUrl, chapterIndex);
    if (!file) return '';
    if (!file.path || !fs.accessSync(file.path)) {
      await appDb.deleteAudioOfflineFiles(bookUrl, chapterIndex);
      return '';
    }
    if (file.voice !== voice) return '';
    return AudioOfflinePolicy.entryMatches(AudioOfflineStore.toEntry(file), chapterUrl, chapterTitle) ? file.path : '';
  }

  /**
   * 章节序号 → 下载时间，只含当前音色、章节对得上的。目录刷新后序号变了的记录在这里挪到新位置。
   */
  static async downloadedDates(bookUrl: string, chapterUrls: string[], chapterTitles: string[],
    voice: string): Promise<Map<number, number>> {
    const dates = new Map<number, number>();
    if (!bookUrl) return dates;
    const files = await appDb.listAudioOfflineFiles(bookUrl);
    if (files.length === 0) return dates;
    const byIndex = new Map<number, AudioOfflineFile>();
    for (const file of files) byIndex.set(file.chapterIndex, file);
    const mapping = AudioOfflinePolicy.remapEntries(files.map((file: AudioOfflineFile): AudioOfflineEntry =>
      AudioOfflineStore.toEntry(file)), chapterUrls, chapterTitles);
    const moves = new Map<number, number>();
    mapping.forEach((oldIndex: number, newIndex: number): void => {
      if (oldIndex !== newIndex) moves.set(oldIndex, newIndex);
    });
    if (moves.size > 0) {
      try {
        AppDatabase.unlinkFiles(await appDb.moveAudioOfflineFiles(bookUrl, moves));
      } catch (error) {
        console.warn('离线音频章节对位失败:', error);
        return dates;
      }
    }
    mapping.forEach((oldIndex: number, newIndex: number): void => {
      const file = byIndex.get(oldIndex);
      if (file && file.voice === voice) dates.set(newIndex, Math.max(1, file.createdAt));
    });
    return dates;
  }

  static async usage(): Promise<AudioOfflineUsage> {
    return await appDb.getAudioOfflineUsage();
  }

  /** 一本书离线音频占用的字节数（含换音色前下载、暂时对不上章节的文件）。 */
  static async bookBytes(bookUrl: string): Promise<number> {
    let total = 0;
    for (const file of await appDb.listAudioOfflineFiles(bookUrl)) total += Math.max(0, file.bytes);
    return total;
  }

  /** 删除一本书的离线音频，返回删掉的章数。 */
  static async clearBook(bookUrl: string): Promise<number> {
    if (!bookUrl) return 0;
    const paths = await appDb.deleteAudioOfflineFiles(bookUrl);
    AppDatabase.unlinkFiles(paths);
    AudioOfflineStore.dropPartials(bookUrl);
    return paths.length;
  }

  static async clearChapter(bookUrl: string, chapterIndex: number): Promise<boolean> {
    if (!bookUrl) return false;
    const paths = await appDb.deleteAudioOfflineFiles(bookUrl, chapterIndex);
    AppDatabase.unlinkFiles(paths);
    return paths.length > 0;
  }

  /** 删除全部离线音频，连同没有记录的残留文件。返回释放的字节数。 */
  static async clearAll(): Promise<number> {
    const usage = await appDb.getAudioOfflineUsage();
    AppDatabase.unlinkFiles(await appDb.deleteAudioOfflineFiles());
    const dir = AudioOfflineStore.directory();
    if (dir && fs.accessSync(dir)) {
      AppDatabase.unlinkFiles((await fs.listFile(dir)).map((name: string): string => `${dir}/${name}`));
    }
    return usage.bytes;
  }

  /**
   * 启动后清理：没有记录的成品文件（删记录时删文件失败、进程中途被杀）、超过保留期的半截文件。
   * 正在下载的半截文件保留。
   */
  static async cleanupOrphans(): Promise<void> {
    const dir = AudioOfflineStore.directory();
    if (!dir || !fs.accessSync(dir)) return;
    const referenced = new Set<string>((await appDb.listAudioOfflineFiles())
      .map((file: AudioOfflineFile): string => file.path));
    const active = new Set<string>();
    AudioOfflineStore.inFlight.forEach((_: Promise<void>, key: string): void => {
      active.add(AudioOfflineStore.partialBase(key));
    });
    const now = Date.now();
    const stale: string[] = [];
    for (const name of await fs.listFile(dir)) {
      const path = `${dir}/${name}`;
      if (referenced.has(path)) continue;
      const partial = name.endsWith('.part') || name.endsWith('.part.json');
      if (partial) {
        const base = path.replace(/\.part(?:\.json)?$/, '');
        if (active.has(base)) continue;
        try {
          if (now - fs.statSync(path).mtime * 1000 <= AudioOfflineStore.PARTIAL_KEEP_MS) continue;
        } catch (_) {}
      }
      stale.push(path);
    }
    if (stale.length > 0) {
      AppDatabase.unlinkFiles(stale);
      console.info(`[AudioOffline] removed ${stale.length} orphan files`);
    }
  }

  /** 删掉这本书听过的边听边下章节（当前章之前），返回删掉的章数。 */
  static async evictListened(bookUrl: string, currentIndex: number): Promise<number> {
    const files = await appDb.listAudioOfflineFiles(bookUrl);
    const listened = AudioOfflinePolicy.listenedAutoEntries(
      files.map((file: AudioOfflineFile): AudioOfflineEntry => AudioOfflineStore.toEntry(file)), currentIndex);
    for (const entry of listened) await AudioOfflineStore.clearChapter(bookUrl, entry.chapterIndex);
    return listened.length;
  }

  /**
   * 下载 incoming 字节前检查上限：超了先删最旧的边听边下章节；还不够就抛 CAP_REACHED。
   * 不设上限（0）时什么也不做。
   */
  static async ensureCap(incoming: number, keepBookUrl: string, keepIndex: number): Promise<void> {
    const cap = AudioOfflineStore.capBytes();
    if (cap <= 0) return;
    const usage = await appDb.getAudioOfflineUsage();
    const over = usage.bytes + Math.max(0, incoming) - cap;
    if (over <= 0) return;
    const files = (await appDb.listAudioOfflineFiles())
      .filter((file: AudioOfflineFile): boolean => !(file.bookUrl === keepBookUrl && file.chapterIndex === keepIndex));
    const entries = files.map((file: AudioOfflineFile): AudioOfflineEntry => AudioOfflineStore.toEntry(file));
    // 跨书淘汰没有"听过"的概念，按下载时间从旧到新删。
    const evicted = AudioOfflinePolicy.capEvictions(entries, -1, over);
    let freed = 0;
    for (const entry of evicted) {
      const file = files[entries.indexOf(entry)];
      if (await AudioOfflineStore.clearChapter(file.bookUrl, file.chapterIndex)) freed += Math.max(0, file.bytes);
    }
    if (freed < over) throw new Error(AudioOfflineStore.CAP_REACHED);
  }

  /**
   * 把一章音频下载到本地并登记。同一章同时只下一份，重复调用等待已有的那次。
   * 出错时抛出原因：空间不足 STORAGE_FAILURE、超上限 CAP_REACHED、网络不允许 NETWORK_WAIT、取消 CANCELED。
   */
  static async download(task: AudioDownloadTask): Promise<void> {
    const key = `${task.bookUrl}#${task.chapterIndex}`;
    const running = AudioOfflineStore.inFlight.get(key);
    if (running) {
      await running;
      return;
    }
    const job = AudioOfflineStore.downloadOnce(task, key);
    AudioOfflineStore.inFlight.set(key, job);
    try {
      await job;
    } finally {
      if (AudioOfflineStore.inFlight.get(key) === job) AudioOfflineStore.inFlight.delete(key);
    }
  }

  private static async downloadOnce(task: AudioDownloadTask, key: string): Promise<void> {
    if (!AudioOfflineStore.networkAllows(task.allowCellular)) throw new Error(AudioOfflineStore.NETWORK_WAIT);
    const dir = AudioOfflineStore.directory();
    if (!dir) throw new Error(AudioOfflineStore.STORAGE_FAILURE);
    if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
    await AudioOfflineStore.ensureFreeSpace(dir, 0);
    await AudioOfflineStore.ensureCap(0, task.bookUrl, task.chapterIndex);
    const base = AudioOfflineStore.partialBase(key);
    let extension = '';
    let bytes = 0;
    if (/\.m3u8(?:[?#]|$)/i.test(task.url)) {
      const result = await AudioOfflineStore.downloadSegmented(task, base, '');
      extension = result.extension;
      bytes = result.bytes;
    } else {
      const direct = await AudioOfflineStore.downloadDirect(task, base);
      if (direct.playlist) {
        // 地址没有 .m3u8 扩展名，但返回的是播放列表。
        const result = await AudioOfflineStore.downloadSegmented(task, base, direct.playlist);
        extension = result.extension;
        bytes = result.bytes;
      } else {
        extension = direct.extension;
        bytes = direct.bytes;
      }
    }
    const finalPath = `${base}_${Date.now()}.${extension}`;
    fs.renameSync(`${base}.part`, finalPath);
    AppDatabase.unlinkFiles([`${base}.part.json`]);
    const record = new AudioOfflineFile();
    record.bookUrl = task.bookUrl;
    record.chapterIndex = task.chapterIndex;
    record.chapterUrl = task.chapterUrl || '';
    record.chapterTitle = task.chapterTitle || '';
    record.voice = task.voice || '';
    record.auto = task.auto;
    record.path = finalPath;
    record.bytes = bytes;
    record.createdAt = Date.now();
    try {
      const replaced = await appDb.saveAudioOfflineFile(record);
      if (replaced) AppDatabase.unlinkFiles([replaced]);
    } catch (error) {
      AppDatabase.unlinkFiles([finalPath]);
      throw error as Error;
    }
  }

  /** 直链下载，可续传。返回的 playlist 非空表示响应其实是 m3u8 文本，没有写盘。 */
  private static async downloadDirect(task: AudioDownloadTask, base: string): Promise<DirectResult> {
    const partPath = `${base}.part`;
    const metaPath = `${base}.part.json`;
    let meta = AudioOfflineStore.readMeta(metaPath);
    const usable = meta !== null && meta.segmented === 0 && fs.accessSync(partPath) &&
      AudioOfflinePolicy.partialUsable(meta, task.chapterUrl, task.voice, Date.now(), AudioOfflineStore.PARTIAL_KEEP_MS);
    if (!usable || !meta) {
      meta = new AudioPartialMeta();
      meta.chapterUrl = task.chapterUrl;
      meta.voice = task.voice;
    }
    const headers: Record<string, string> = {};
    Object.keys(task.headers).forEach((name: string): void => { headers[name] = task.headers[name]; });
    if (usable && meta.bytes > 0) {
      headers['Range'] = `bytes=${meta.bytes}-`;
      if (meta.etag) headers['If-Range'] = meta.etag;
      else if (meta.lastModified) headers['If-Range'] = meta.lastModified;
    }
    const output = await fs.open(partPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    const client = http.createHttp();
    const result = new DirectResult();
    let offset = 0;
    let expectedEnd = 0;
    let contentType = '';
    let failure = '';
    let timer = -1;
    let lastMetaAt = 0;
    const current: AudioPartialMeta = meta;
    const saveMeta = (): void => {
      current.bytes = offset;
      current.updatedAt = Date.now();
      AudioOfflineStore.writeMeta(metaPath, current);
    };
    try {
      await new Promise<void>((resolve, reject): void => {
        let ended = false;
        let accepted = false;
        let decided = false;
        let sniffed = false;
        let playlistText = '';
        const fail = (message: string): void => {
          if (failure) return;
          failure = message;
          reject(new Error(message));
          try { client.destroy(); } catch (_) {}
        };
        const complete = (): void => {
          if (!ended || !accepted || failure) return;
          if (playlistText) {
            result.playlist = playlistText;
            resolve();
          } else if (offset < AudioOfflineStore.MIN_AUDIO_BYTES) fail('音频地址返回的内容过小，不是有效音频');
          else if (expectedEnd > 0 && offset !== expectedEnd) fail('音频下载不完整');
          else resolve();
        };
        client.on('headersReceive', (value: Object): void => {
          const map = (value || {}) as Record<string, Object>;
          contentType = AudioOfflineStore.header(map, 'content-type').toLowerCase();
          const range = AudioOfflineStore.header(map, 'content-range');
          const etag = AudioOfflineStore.header(map, 'etag');
          const lastModified = AudioOfflineStore.header(map, 'last-modified');
          const decision = AudioOfflinePolicy.resumeDecision(range ? 206 : 200, range, current, etag, lastModified);
          // 压缩传输时 Content-Length 是压缩后的长度，没法拿来核对。
          const length = AudioOfflineStore.header(map, 'content-encoding') ? 0 :
            Math.max(0, Number(AudioOfflineStore.header(map, 'content-length')) || 0);
          if (decision === 'append') {
            offset = current.bytes;
            expectedEnd = current.total;
          } else {
            offset = 0;
            fs.truncateSync(output.fd, 0);
            current.total = length;
            expectedEnd = length;
          }
          current.etag = etag;
          current.lastModified = lastModified;
          decided = true;
          if (/^(?:text\/html|application\/(?:json|xml))/.test(contentType)) fail('音频地址返回的不是音频');
          else if (expectedEnd > offset) {
            const incoming = expectedEnd - offset;
            AudioOfflineStore.ensureFreeSpace(AudioOfflineStore.directory(), incoming)
              .then((): Promise<void> => AudioOfflineStore.ensureCap(incoming, task.bookUrl, task.chapterIndex))
              .catch((error: Error): void => fail(error.message));
          }
        });
        client.on('dataReceive', (chunk: ArrayBuffer): void => {
          if (failure) return;
          if (task.shouldCancel?.()) { fail(AudioOfflineStore.CANCELED); return; }
          if (!sniffed) {
            sniffed = true;
            const head = AudioOfflineStore.leadingText(chunk);
            if (contentType.includes('mpegurl') || AudioOfflinePolicy.isPlaylistText(head)) {
              playlistText = ' ';
            } else if (offset === 0 && (head.startsWith('<') || head.startsWith('{'))) {
              fail('音频地址返回的不是音频');
              return;
            }
          }
          if (playlistText) {
            playlistText += AudioOfflineStore.decodeText(chunk);
            return;
          }
          if (!decided) offset = 0;
          try {
            let written = 0;
            while (written < chunk.byteLength) {
              const count = fs.writeSync(output.fd, chunk.slice(written), { offset: offset + written });
              if (count <= 0) throw new Error('write failed');
              written += count;
            }
            offset += chunk.byteLength;
          } catch (_) { fail(AudioOfflineStore.STORAGE_FAILURE); return; }
          task.onProgress?.(offset, expectedEnd);
          if (Date.now() - lastMetaAt > 2000) {
            lastMetaAt = Date.now();
            saveMeta();
          }
        });
        client.on('dataEnd', (): void => { ended = true; complete(); });
        let ticks = 0;
        timer = setInterval((): void => {
          if (task.shouldCancel?.()) fail(AudioOfflineStore.CANCELED);
          else if (++ticks % 5 === 0 && !AudioOfflineStore.networkAllows(task.allowCellular)) {
            fail(AudioOfflineStore.NETWORK_WAIT);
          }
        }, 200);
        client.requestInStream(task.url, {
          method: http.RequestMethod.GET,
          header: headers,
          connectTimeout: 20000,
          readTimeout: 60000,
          usingCache: false
        }).then((status: number): void => {
          if (status === 416) {
            // 请求的起点超出了文件长度：半截文件作废，下次从头下。
            AudioOfflineStore.dropPartial(base);
            fail('音频下载失败，请重试');
            return;
          }
          if (status < 200 || status >= 300) { fail(`音频下载失败（HTTP ${status}）`); return; }
          accepted = true;
          complete();
        }).catch((error: Error): void => {
          fail(task.shouldCancel?.() ? AudioOfflineStore.CANCELED : `音频下载失败：${error?.message || '网络错误'}`);
        });
      });
    } finally {
      if (timer >= 0) clearInterval(timer);
      try { client.off('headersReceive'); client.off('dataReceive'); client.off('dataEnd'); client.destroy(); } catch (_) {}
      try { await fs.close(output); } catch (_) {}
      if (failure && offset > 0 && !result.playlist) saveMeta();
      if (failure === '音频地址返回的不是音频' || failure.startsWith('音频地址返回的内容过小')) {
        AudioOfflineStore.dropPartial(base);
      }
    }
    if (result.playlist) {
      AudioOfflineStore.dropPartial(base);
      result.playlist = result.playlist.trim();
      return result;
    }
    result.bytes = offset;
    result.extension = AudioOfflineStore.extension(task.url, contentType);
    return result;
  }

  /**
   * m3u8：主列表选最低码率，逐片下载（同时 3 片）、按需 AES-128 解密，按顺序拼进 .part。
   * 已完成的分片数记在 .part.json，失败后下次从断点那片继续。
   */
  private static async downloadSegmented(task: AudioDownloadTask, base: string,
    initialText: string): Promise<SegmentedResult> {
    let playlistUrl = task.url;
    let text = initialText || await AudioOfflineStore.fetchText(playlistUrl, task);
    let playlist: HlsPlaylist = AudioOfflinePolicy.parsePlaylist(text, playlistUrl);
    if (playlist.variants.length > 0) {
      const variant = AudioOfflinePolicy.pickVariant(playlist.variants);
      if (!variant) throw new Error('播放列表里没有可用的音频');
      playlistUrl = variant.url;
      text = await AudioOfflineStore.fetchText(playlistUrl, task);
      playlist = AudioOfflinePolicy.parsePlaylist(text, playlistUrl);
    }
    if (playlist.unsupported) throw new Error(playlist.unsupported);
    if (playlist.segments.length === 0) throw new Error('播放列表里没有可用的音频');

    const partPath = `${base}.part`;
    const metaPath = `${base}.part.json`;
    let meta = AudioOfflineStore.readMeta(metaPath);
    const usable = meta !== null && meta.segmented === 1 && fs.accessSync(partPath) &&
      meta.segmentsDone <= playlist.segments.length &&
      AudioOfflinePolicy.partialUsable(meta, task.chapterUrl, task.voice, Date.now(), AudioOfflineStore.PARTIAL_KEEP_MS);
    if (!usable || !meta) {
      meta = new AudioPartialMeta();
      meta.chapterUrl = task.chapterUrl;
      meta.voice = task.voice;
      meta.segmented = 1;
    }
    const current: AudioPartialMeta = meta;
    const output = await fs.open(partPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    const keys = new Map<string, Uint8Array>();
    let offset = usable ? current.bytes : 0;
    try {
      fs.truncateSync(output.fd, offset);
      if (offset === 0) {
        current.segmentsDone = 0;
        if (playlist.mapUrl) {
          offset += AudioOfflineStore.writeAt(output.fd, await AudioOfflineStore.fetchBytes(playlist.mapUrl, task), offset);
        }
      }
      for (let start = current.segmentsDone; start < playlist.segments.length;
        start += AudioOfflineStore.SEGMENT_CONCURRENCY) {
        if (task.shouldCancel?.()) throw new Error(AudioOfflineStore.CANCELED);
        if (!AudioOfflineStore.networkAllows(task.allowCellular)) throw new Error(AudioOfflineStore.NETWORK_WAIT);
        const window = playlist.segments.slice(start, start + AudioOfflineStore.SEGMENT_CONCURRENCY);
        const parts = await Promise.all(window.map((segment: HlsSegment): Promise<Uint8Array> =>
          AudioOfflineStore.fetchSegment(segment, task, keys)));
        let windowBytes = 0;
        for (const part of parts) windowBytes += part.byteLength;
        await AudioOfflineStore.ensureFreeSpace(AudioOfflineStore.directory(), windowBytes);
        await AudioOfflineStore.ensureCap(offset + windowBytes, task.bookUrl, task.chapterIndex);
        for (const part of parts) offset += AudioOfflineStore.writeAt(output.fd, part, offset);
        current.segmentsDone = start + window.length;
        current.bytes = offset;
        current.updatedAt = Date.now();
        AudioOfflineStore.writeMeta(metaPath, current);
        task.onProgress?.(offset, 0);
      }
    } catch (error) {
      if (offset > 0 && current.segmentsDone > 0) AudioOfflineStore.writeMeta(metaPath, current);
      throw error as Error;
    } finally {
      try { await fs.close(output); } catch (_) {}
    }
    if (offset < AudioOfflineStore.MIN_AUDIO_BYTES) throw new Error('音频地址返回的内容过小，不是有效音频');
    const result = new SegmentedResult();
    result.bytes = offset;
    result.extension = AudioOfflinePolicy.segmentedExtension(playlist);
    return result;
  }

  private static async fetchSegment(segment: HlsSegment, task: AudioDownloadTask,
    keys: Map<string, Uint8Array>): Promise<Uint8Array> {
    let data = await AudioOfflineStore.fetchBytes(segment.url, task);
    if (segment.keyMethod === 'AES-128') {
      let key = keys.get(segment.keyUrl);
      if (!key) {
        key = await AudioOfflineStore.fetchBytes(segment.keyUrl, task);
        if (key.byteLength !== 16) throw new Error('音频密钥无效');
        keys.set(segment.keyUrl, key);
      }
      data = await AudioOfflineStore.decryptAes128(data, key, AudioOfflinePolicy.segmentIv(segment));
    }
    return data;
  }

  private static async decryptAes128(data: Uint8Array, key: Uint8Array, iv: Uint8Array): Promise<Uint8Array> {
    const generator = cryptoFramework.createSymKeyGenerator('AES128');
    const symKey = await generator.convertKey({ data: key });
    try {
      const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
      const params: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: { data: iv } };
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
      const output = await cipher.doFinal({ data: data });
      if (!output || !output.data) throw new Error('音频分片解密失败');
      return output.data;
    } finally {
      symKey.clearMem();
    }
  }

  private static async fetchText(url: string, task: AudioDownloadTask): Promise<string> {
    return AudioOfflineStore.decodeText((await AudioOfflineStore.fetchBytes(url, task)).buffer as ArrayBuffer);
  }

  /** 小文件（列表、密钥、分片）整块取回，失败重试两次，间隔逐次加长。 */
  private static async fetchBytes(url: string, task: AudioDownloadTask): Promise<Uint8Array> {
    let lastError = '';
    for (let attempt = 0; attempt < 3; attempt++) {
      if (task.shouldCancel?.()) throw new Error(AudioOfflineStore.CANCELED);
      if (!AudioOfflineStore.networkAllows(task.allowCellular)) throw new Error(AudioOfflineStore.NETWORK_WAIT);
      if (attempt > 0) await new Promise<void>((resolve: () => void): number => setTimeout(resolve, 800 * attempt));
      const client = http.createHttp();
      try {
        const response = await client.request(url, {
          method: http.RequestMethod.GET,
          header: task.headers,
          connectTimeout: 20000,
          readTimeout: 60000,
          usingCache: false,
          maxLimit: 50 * 1024 * 1024,
          expectDataType: http.HttpDataType.ARRAY_BUFFER
        });
        if (response.responseCode >= 200 && response.responseCode < 300) {
          return new Uint8Array(response.result as ArrayBuffer);
        }
        lastError = `HTTP ${response.responseCode}`;
        if (response.responseCode >= 400 && response.responseCode < 500 && response.responseCode !== 429) break;
      } catch (error) {
        lastError = (error as Error)?.message || '网络错误';
      } finally {
        client.destroy();
      }
    }
    throw new Error(`音频分片下载失败（${lastError}）`);
  }

  private static writeAt(fd: number, data: Uint8Array, offset: number): number {
    try {
      let written = 0;
      while (written < data.byteLength) {
        const count = fs.writeSync(fd, data.buffer.slice(data.byteOffset + written, data.byteOffset + data.byteLength) as ArrayBuffer,
          { offset: offset + written });
        if (count <= 0) throw new Error('write failed');
        written += count;
      }
      return written;
    } catch (_) {
      throw new Error(AudioOfflineStore.STORAGE_FAILURE);
    }
  }

  /** 同一章的半截文件名固定，续传时才找得到。 */
  private static partialBase(key: string): string {
    const index = key.lastIndexOf('#');
    return `${AudioOfflineStore.directory()}/${AudioOfflineStore.hash(key.substring(0, index))}_${key.substring(index + 1)}`;
  }

  private static dropPartial(base: string): void {
    AppDatabase.unlinkFiles([`${base}.part`, `${base}.part.json`]);
  }

  private static dropPartials(bookUrl: string): void {
    const dir = AudioOfflineStore.directory();
    if (!dir || !fs.accessSync(dir)) return;
    const prefix = `${AudioOfflineStore.hash(bookUrl)}_`;
    try {
      AppDatabase.unlinkFiles(fs.listFileSync(dir)
        .filter((name: string): boolean => name.startsWith(prefix) && /\.part(?:\.json)?$/.test(name))
        .map((name: string): string => `${dir}/${name}`));
    } catch (error) {
      console.warn('删除半截音频失败:', error);
    }
  }

  private static readMeta(path: string): AudioPartialMeta | null {
    try {
      if (!fs.accessSync(path)) return null;
      const raw = JSON.parse(fs.readTextSync(path)) as AudioPartialMeta;
      const meta = new AudioPartialMeta();
      meta.chapterUrl = String(raw.chapterUrl || '');
      meta.voice = String(raw.voice || '');
      meta.bytes = Number(raw.bytes) || 0;
      meta.total = Number(raw.total) || 0;
      meta.etag = String(raw.etag || '');
      meta.lastModified = String(raw.lastModified || '');
      meta.segmentsDone = Number(raw.segmentsDone) || 0;
      meta.segmented = Number(raw.segmented) || 0;
      meta.updatedAt = Number(raw.updatedAt) || 0;
      return meta;
    } catch (_) {
      return null;
    }
  }

  private static writeMeta(path: string, meta: AudioPartialMeta): void {
    try {
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, JSON.stringify(meta)); } finally { fs.closeSync(file); }
    } catch (error) {
      console.warn('记录续传信息失败:', error);
    }
  }

  private static async ensureFreeSpace(dir: string, incomingBytes: number): Promise<void> {
    let free = Number.MAX_SAFE_INTEGER;
    try {
      free = await statvfs.getFreeSize(dir);
    } catch (error) {
      // 查不到可用空间时照常下载，真写满了由写盘失败兜底。
      console.warn('查询可用空间失败:', error);
    }
    if (free < AudioOfflineStore.MIN_FREE_BYTES + incomingBytes) throw new Error(AudioOfflineStore.STORAGE_FAILURE);
  }

  private static header(headers: Record<string, Object>, name: string): string {
    for (const key of Object.keys(headers)) {
      if (key.toLowerCase() === name) {
        const value = headers[key];
        return Array.isArray(value) ? String((value as Object[])[0] || '') : String(value || '');
      }
    }
    return '';
  }

  private static leadingText(chunk: ArrayBuffer): string {
    const bytes = new Uint8Array(chunk, 0, Math.min(chunk.byteLength, 16));
    let text = '';
    for (const byte of bytes) text += String.fromCharCode(byte);
    return text.replace(/^﻿/, '').trimStart();
  }

  /** 播放列表是 ASCII/UTF-8 文本，按字节拼回字符串即可（非 ASCII 只出现在注释里）。 */
  private static decodeText(chunk: ArrayBuffer): string {
    const bytes = new Uint8Array(chunk);
    let text = '';
    for (let i = 0; i < bytes.length; i += 4096) {
      text += String.fromCharCode(...Array.from(bytes.subarray(i, Math.min(bytes.length, i + 4096))));
    }
    return text;
  }

  private static extension(url: string, contentType: string): string {
    const path = (url || '').split(/[?#]/)[0];
    const match = path.match(new RegExp(`\\.(${AudioOfflineStore.EXTENSIONS})$`, 'i'));
    if (match) return match[1].toLowerCase();
    if (contentType.includes('mpeg') || contentType.includes('mp3')) return 'mp3';
    if (contentType.includes('mp4') || contentType.includes('m4a')) return 'm4a';
    for (const ext of ['aac', 'flac', 'ogg', 'opus', 'wav']) {
      if (contentType.includes(ext)) return ext;
    }
    return 'audio';
  }

  /** 文件名前缀，只用来区分书。 */
  private static hash(value: string): string {
    let hash = 0x811c9dc5;
    for (let i = 0; i < value.length; i++) {
      hash ^= value.charCodeAt(i);
      hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    return hash.toString(16).padStart(8, '0');
  }
}

class DirectResult {
  bytes: number = 0;
  extension: string = '';
  /** 响应其实是播放列表时的文本。 */
  playlist: string = '';
}

class SegmentedResult {
  bytes: number = 0;
  extension: string = '';
}
