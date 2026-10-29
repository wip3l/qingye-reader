import { Book } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { ReadBookEngine } from '../core/book/ReadBookEngine';
import { AudioOfflineStore } from '../core/book/AudioOfflineStore';
import { AudioOfflinePolicy } from '../core/book/AudioOfflinePolicy';

/**
 * 边听边下：每章开始播放后，在 Wi-Fi 下悄悄下载后面几章，并删掉已经听过的自动下载章节。
 * 进程内单例——播放器在听书页关闭后仍在播，预下载也跟着播放走，而不是跟着页面走。
 * 不发通知、不申请后台任务（听书本身持有后台播放许可）；切章、停止播放时作废正在进行的这一轮。
 */
export class AudioPrefetch {
  /** 离线音频有变化（预下载完成一章、删除了听过的章节）时更新，听书页和书架据此刷新标记。 */
  static readonly REVISION_KEY: string = 'audioOfflineRevision';
  private static instance: AudioPrefetch | null = null;
  private generation: number = 0;
  private running: Promise<void> | null = null;
  private engine: ReadBookEngine | null = null;

  static get(): AudioPrefetch {
    if (!AudioPrefetch.instance) AudioPrefetch.instance = new AudioPrefetch();
    return AudioPrefetch.instance;
  }

  static notifyChanged(): void {
    AppStorage.setOrCreate(AudioPrefetch.REVISION_KEY, Date.now());
  }

  /** 第 currentIndex 章开始播放了。没开边听边下时什么也不做。 */
  schedule(book: Book, currentIndex: number): void {
    if (AudioOfflineStore.prefetchCount() <= 0 || !book.bookUrl || !book.origin || book.origin === 'local') return;
    const generation = ++this.generation;
    this.engine?.cancelPendingRequests();
    this.start(book.bookUrl, currentIndex, generation).catch((error: Error) => {
      console.warn('边听边下失败:', error);
    });
  }

  /** 停止播放、关掉边听边下时调用。 */
  cancel(): void {
    this.generation++;
    this.engine?.cancelPendingRequests();
  }

  private async start(bookUrl: string, currentIndex: number, generation: number): Promise<void> {
    const previous = this.running;
    if (previous) {
      try { await previous; } catch (_) {}
    }
    if (generation !== this.generation) return;
    const task = this.run(bookUrl, currentIndex, generation);
    this.running = task;
    try {
      await task;
    } finally {
      if (this.running === task) this.running = null;
    }
  }

  private async run(bookUrl: string, currentIndex: number, generation: number): Promise<void> {
    const cancelled = (): boolean => generation !== this.generation;
    if (await AudioOfflineStore.evictListened(bookUrl, currentIndex) > 0) AudioPrefetch.notifyChanged();
    // 只在 Wi-Fi（或有线）下预下载；移动网络上一律不自动用流量。
    const network = AudioOfflineStore.network();
    if (network !== 'wifi' && network !== 'other') return;
    const count = AudioOfflineStore.prefetchCount();
    if (count <= 0 || cancelled()) return;
    const engine = await this.engineFor(bookUrl);
    if (!engine || cancelled()) return;
    await engine.syncChapterCacheDates();
    const downloaded = new Set<number>();
    engine.chapters.forEach((chapter, index: number): void => {
      if (chapter.cacheDate > 0) downloaded.add(index);
    });
    const targets = AudioOfflinePolicy.prefetchTargets(currentIndex, count, engine.chapters.length, downloaded);
    for (const index of targets) {
      if (cancelled()) return;
      const ok = await engine.cacheChapter(index, cancelled);
      // 空间不足或达到上限：这一轮停下，不打扰用户；手动下载时才提示原因。
      if (engine.lastCacheError) {
        console.warn('边听边下暂停:', engine.lastCacheError);
        return;
      }
      if (ok) AudioPrefetch.notifyChanged();
    }
  }

  /** 每轮都从数据库重新打开，换音色、刷新目录后才不会按旧状态下载。 */
  private async engineFor(bookUrl: string): Promise<ReadBookEngine | null> {
    const book = await AppDatabase.getInstance().getBook(bookUrl);
    if (!book) return null;
    const engine = ReadBookEngine.createBackgroundWorker();
    this.engine = engine;
    await engine.openBook(book);
    engine.audioAuto = true;
    engine.audioAllowCellular = false;
    return engine;
  }
}
