import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import worker, { MessageEvents } from '@ohos.worker';
import subtitleAudio from 'libsubtitle_audio.so';
import { Book, BookChapter } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { ReadBookEngine } from '../../core/book/ReadBookEngine';
import { AudioDownloadTask, AudioOfflineStore } from '../../core/book/AudioOfflineStore';
import { SubtitleCue, SubtitleText } from '../../core/subtitle/SubtitleText';
import { RemoteAudioPlayback } from '../RemoteAudioPlayback';
import { AudioPrefetch } from '../AudioPrefetch';
import { AudioBookSettingsStore } from '../AudioBookSettingsStore';
import { SubtitleModelStore } from './SubtitleModelStore';
import { AccountSessionStore } from '../../account/AccountSessionStore';

/** 每段识别 16 秒，前后各多解 1 秒给边界的字补上下文。 */
const CHUNK_MS = 16000;
const PAD_MS = 1000;
/** 一段识别超过这么久没回音就当 Worker 卡死，重启它。 */
const CHUNK_TIMEOUT_MS = 90000;
/** 字幕不在屏幕上这么久后结束 Worker，释放模型占的几百 MB 内存。 */
const IDLE_RELEASE_MS = 60000;
/** 预识别下一章的段数（约 2 分钟）。 */
const NEXT_CHAPTER_CHUNKS = 8;
const TICK_MS = 500;
const CACHE_VERSION = 1;

class SubtitleCacheFile {
  version: number = CACHE_VERSION;
  model: string = '';
  durationMs: number = 0;
  chunkMs: number = CHUNK_MS;
  chunks: Record<string, SubtitleCue[]> = {};
}

/** 一章的识别任务：本地音频、缓存文件和已识别的段。 */
class SubtitleJob {
  key: string = '';
  bookUrl: string = '';
  chapterIndex: number = -1;
  path: string = '';
  cachePath: string = '';
  durationMs: number = 0;
  chunks: Map<number, SubtitleCue[]> = new Map();
  failures: Map<number, number> = new Map();
  /** 最多识别前几段；0 表示整章。预识别下一章时用。 */
  limit: number = 0;
  dirty: number = 0;

  chunkCount(): number {
    const count = this.durationMs > 0 ? Math.ceil(this.durationMs / CHUNK_MS) : 0;
    return this.limit > 0 ? Math.min(this.limit, count) : count;
  }

  complete(): boolean {
    const count = this.chunkCount();
    if (count <= 0) return false;
    for (let i = 0; i < count; i++) if (!this.chunks.has(i) && (this.failures.get(i) || 0) < 2) return false;
    return true;
  }
}

class SubtitleWorkerReply {
  type: string = '';
  id: number = 0;
  message: string = '';
  cues: SubtitleCue[] = [];
  durationMs: number = 0;
}

class SubtitleWorkerRequest {
  type: string = '';
  id: number = 0;
  model: string = '';
  tokens: string = '';
  punct: string = '';
  threads: number = 2;
  path: string = '';
  startMs: number = 0;
  endMs: number = 0;
  padMs: number = PAD_MS;
}

/**
 * 听书 AI 字幕：跟着听书播放器当前的章节，在本机把音频识别成字幕。进程内单例，状态发布在 AppStorage 里，
 * 播放面板的字幕页签只负责显示。
 *
 * - 只在字幕页签显示时工作：播放中从当前位置往后逐段识别，读完再补前面；暂停时只补当前位置附近两段。
 * - 本地已有音频（已下载、本地书）直接识别；在线章节先按“边听边下”下载本章（听过后会自动删掉），m3u8 也能处理。
 * - 每章的结果按“书 + 章节 + 音色 + 文件大小 + 模型版本”存进缓存目录，下次直接显示。
 */
export class AudioSubtitleService {
  static readonly PHASE_KEY: string = 'audioSubtitlePhase';
  static readonly MESSAGE_KEY: string = 'audioSubtitleMessage';
  static readonly REVISION_KEY: string = 'audioSubtitleRevision';
  /** 没有字幕需要的东西时：idle 不在听书。 */
  static readonly IDLE: string = 'idle';
  /** 不是会员（或会员已到期）：AI 字幕为会员专享。 */
  static readonly MEMBER_REQUIRED: string = 'memberRequired';
  static readonly NEEDS_MODEL: string = 'needsModel';
  static readonly MODEL: string = 'model';
  static readonly AUDIO: string = 'audio';
  static readonly NEEDS_CELLULAR: string = 'needsCellular';
  static readonly LOADING: string = 'loading';
  static readonly READY: string = 'ready';
  static readonly ERROR: string = 'error';

  private static instance: AudioSubtitleService | null = null;
  private visibleCount: number = 0;
  private tickTimer: number = -1;
  private releaseTimer: number = -1;
  private job: SubtitleJob | null = null;
  /** 当前章各段合并后的字幕。 */
  private merged: SubtitleCue[] = [];
  private nextJob: SubtitleJob | null = null;
  /** 正在准备（取音频、读缓存）的章节键，防止重复准备。 */
  private preparingKey: string = '';
  private failedKey: string = '';
  private cellularAllowed: boolean = false;
  private thread: worker.ThreadWorker | null = null;
  private threadReady: boolean = false;
  private threadLoading: Promise<void> | null = null;
  private requestId: number = 0;
  private inFlight: SubtitleJob | null = null;
  private inFlightChunk: number = -1;
  private inFlightTimer: number = -1;
  private pending: Map<number, (reply: SubtitleWorkerReply) => void> = new Map();
  private engine: ReadBookEngine | null = null;
  private audioCancelled: boolean = false;
  private loadConfirmed: boolean = false;
  private backgroundSince: number = 0;

  /** AI 字幕与 AI 超分、着色一样，任一档有效会员都能用。以账号快照按服务端时间推算为准。 */
  static memberAllowed(): boolean {
    return AccountSessionStore.activeMembershipSku() !== '';
  }

  static get(): AudioSubtitleService {
    if (!AudioSubtitleService.instance) AudioSubtitleService.instance = new AudioSubtitleService();
    return AudioSubtitleService.instance;
  }

  // ---- 给字幕视图用 ----

  /** 字幕页签出现/消失。出现时开始工作，全部消失一段时间后释放模型。 */
  setVisible(visible: boolean): void {
    this.visibleCount = Math.max(0, this.visibleCount + (visible ? 1 : -1));
    if (this.visibleCount > 0) {
      if (this.releaseTimer >= 0) clearTimeout(this.releaseTimer);
      this.releaseTimer = -1;
      if (this.tickTimer < 0) {
        this.tickTimer = setInterval((): void => this.tick(), TICK_MS);
        this.tick();
      }
      return;
    }
    if (this.tickTimer >= 0) clearInterval(this.tickTimer);
    this.tickTimer = -1;
    this.saveCache(this.job, true);
    if (this.releaseTimer < 0) {
      this.releaseTimer = setTimeout((): void => {
        this.releaseTimer = -1;
        if (this.visibleCount === 0) this.releaseWorker();
      }, IDLE_RELEASE_MS);
    }
  }

  /** 当前章节的字幕，已按时间排好。不是正在播放的章节时为空。 */
  cues(): SubtitleCue[] {
    const job = this.job;
    if (!job || job.key !== this.playingKey()) return [];
    return this.merged;
  }

  /** 播放位置所在的那段已经识别完（没有字也算）。 */
  readyAt(positionMs: number): boolean {
    const job = this.job;
    if (!job || job.key !== this.playingKey()) return false;
    const index = Math.floor(Math.max(0, positionMs) / CHUNK_MS);
    return job.chunks.has(index) || (job.failures.get(index) || 0) >= 2 ||
      (job.durationMs > 0 && positionMs >= job.durationMs);
  }

  /** 用户同意这次用移动网络取音频（只在本次运行内有效）。 */
  allowCellular(): void {
    this.cellularAllowed = true;
    this.failedKey = '';
    this.tick();
  }

  /** 失败后重试本章。 */
  retry(): void {
    this.failedKey = '';
    if (this.job) this.job.failures.clear();
    this.publish(AudioSubtitleService.LOADING, '');
    this.tick();
  }

  /** 下载模型；下完自动开始识别。只有会员能下。 */
  downloadModel(): void {
    if (!AudioSubtitleService.memberAllowed()) {
      this.publish(AudioSubtitleService.MEMBER_REQUIRED, '');
      return;
    }
    this.publish(AudioSubtitleService.MODEL, '');
    SubtitleModelStore.download().then((): void => {
      this.failedKey = '';
      this.tick();
    }).catch((): void => {
      this.tick();
    });
  }

  /** 删除模型前调用：停掉 Worker，清空当前结果的显示状态（缓存的字幕保留）。 */
  onModelRemoved(): void {
    this.releaseWorker();
    this.loadConfirmed = false;
    this.tick();
  }

  // ---- 内部 ----

  private playback(): RemoteAudioPlayback {
    return RemoteAudioPlayback.get();
  }

  private playingKey(): string {
    const playback = this.playback();
    if (!playback.bookUrl || playback.chapterIndex < 0 || !playback.mediaUrl || playback.isMovieUsage()) return '';
    return `${playback.bookUrl}#${playback.chapterIndex}`;
  }

  private publish(phase: string, message: string): void {
    if (AppStorage.get<string>(AudioSubtitleService.PHASE_KEY) !== phase) {
      AppStorage.setOrCreate(AudioSubtitleService.PHASE_KEY, phase);
    }
    if (AppStorage.get<string>(AudioSubtitleService.MESSAGE_KEY) !== message) {
      AppStorage.setOrCreate(AudioSubtitleService.MESSAGE_KEY, message);
    }
  }

  private bumpRevision(): void {
    AppStorage.setOrCreate(AudioSubtitleService.REVISION_KEY,
      (AppStorage.get<number>(AudioSubtitleService.REVISION_KEY) || 0) + 1);
  }

  /** 应用退到后台（含锁屏）时不识别：面板组件还挂着，但没人在看。 */
  private static inBackground(): boolean {
    return (AppStorage.get<number>('appLifecycleBackgroundRevision') || 0) >
      (AppStorage.get<number>('appLifecycleForegroundRevision') || 0);
  }

  private tick(): void {
    if (this.visibleCount <= 0) return;
    if (AudioSubtitleService.inBackground()) {
      // 后台听书时面板还挂着：一段时间后同样释放模型，免得几百 MB 内存让系统杀掉播放。
      if (this.backgroundSince === 0) this.backgroundSince = Date.now();
      else if (this.thread && !this.inFlight && Date.now() - this.backgroundSince > IDLE_RELEASE_MS) {
        this.saveCache(this.job, true);
        this.releaseWorker();
      }
      return;
    }
    this.backgroundSince = 0;
    const key = this.playingKey();
    if (!key) {
      this.publish(AudioSubtitleService.IDLE, '');
      return;
    }
    if (!AudioSubtitleService.memberAllowed()) {
      // 会员到期时停下识别、释放模型；已识别的缓存保留，续费后直接显示。
      if (this.job) this.switchAway();
      if (this.thread && !this.inFlight) this.releaseWorker();
      this.publish(AudioSubtitleService.MEMBER_REQUIRED, '');
      return;
    }
    if (SubtitleModelStore.isDownloading()) {
      this.publish(AudioSubtitleService.MODEL, '');
      return;
    }
    if (!SubtitleModelStore.installed()) {
      this.publish(AudioSubtitleService.NEEDS_MODEL, '');
      return;
    }
    if (this.job && this.job.key !== key) this.switchAway();
    if (!this.job || this.job.key !== key) {
      if (this.failedKey === key || this.preparingKey === key) return;
      this.prepare(key).catch((error: Error): void => {
        console.warn('[Subtitle] prepare failed:', error);
      });
      return;
    }
    if (this.failedKey === key) return;
    this.schedule();
  }

  /** 换章：存下旧章结果，作废进行中的取音频。 */
  private switchAway(): void {
    this.saveCache(this.job, true);
    this.saveCache(this.nextJob, true);
    this.job = null;
    this.merged = [];
    this.audioCancelled = true;
    this.engine?.cancelPendingRequests();
    this.bumpRevision();
  }

  private async prepare(key: string): Promise<void> {
    this.preparingKey = key;
    this.audioCancelled = false;
    const playback = this.playback();
    const bookUrl = playback.bookUrl;
    const chapterIndex = playback.chapterIndex;
    const mediaUrl = playback.mediaUrl;
    const stale = (): boolean => this.audioCancelled || this.playingKey() !== key;
    try {
      this.publish(AudioSubtitleService.LOADING, '');
      let path = AudioSubtitleService.localPath(mediaUrl);
      let identity = '';
      if (!path) {
        const book = await AppDatabase.getInstance().getBook(bookUrl);
        if (!book || stale()) return;
        const chapter = await AudioSubtitleService.chapterOf(bookUrl, chapterIndex);
        if (stale()) return;
        if (!chapter) throw new Error('找不到本章');
        const voice = book.getVariable('custom') || '';
        identity = `${chapter.url}#${chapter.title}#${voice}`;
        path = await AudioOfflineStore.localFile(bookUrl, chapterIndex, chapter.url, chapter.title, voice);
        if (!path) {
          if (stale()) return;
          if (AudioOfflineStore.network() === 'cellular' && AudioOfflineStore.wifiOnly() && !this.cellularAllowed) {
            this.publish(AudioSubtitleService.NEEDS_CELLULAR, '');
            this.failedKey = key;
            return;
          }
          if (!AudioOfflineStore.networkAllows(true)) throw new Error('没有网络，取不到本章音频');
          path = await this.fetchAudio(book, chapterIndex, chapter, voice, mediaUrl, stale);
          if (!path) {
            if (stale()) return;
            throw new Error(this.engine?.lastCacheError || '取不到本章音频，可稍后重试');
          }
        }
      }
      if (stale()) return;
      const job = new SubtitleJob();
      job.key = key;
      job.bookUrl = bookUrl;
      job.chapterIndex = chapterIndex;
      job.path = path;
      job.cachePath = AudioSubtitleService.cachePath(key, identity, path);
      job.durationMs = AudioSubtitleService.probe(path);
      if (job.durationMs <= 0 && playback.chapterIndex === chapterIndex) job.durationMs = playback.durationMs;
      AudioSubtitleService.loadCache(job);
      this.job = job;
      this.rebuild();
      this.publish(AudioSubtitleService.READY, '');
      this.schedule();
    } catch (error) {
      if (stale()) return;
      this.failedKey = key;
      this.publish(AudioSubtitleService.ERROR, (error as Error)?.message || '字幕准备失败，可点重试');
    } finally {
      if (this.preparingKey === key) this.preparingKey = '';
    }
  }

  /**
   * 按边听边下下载本章音频（听过后自动删掉），进度显示在字幕区。
   * 先直接用播放器正在播的地址和请求头下载，不再让书源重新解析一遍（那一步要几秒到十几秒，
   * 还要排书源的请求频率）；地址过期或下载失败时，才退回后台引擎重新取地址再下。
   */
  private async fetchAudio(book: Book, chapterIndex: number, chapter: BookChapter, voice: string, mediaUrl: string,
    stale: () => boolean): Promise<string> {
    this.publish(AudioSubtitleService.AUDIO, '正在连接…');
    const local = (): Promise<string> =>
      AudioOfflineStore.localFile(book.bookUrl, chapterIndex, chapter.url, chapter.title, voice);
    if (/^https?:\/\//i.test(mediaUrl)) {
      const task = new AudioDownloadTask();
      task.bookUrl = book.bookUrl;
      task.chapterIndex = chapterIndex;
      task.chapterUrl = chapter.url;
      task.chapterTitle = chapter.title;
      task.voice = voice;
      task.auto = true;
      task.url = mediaUrl;
      task.headers = this.playback().mediaHeadersSnapshot();
      task.allowCellular = true;
      task.shouldCancel = stale;
      task.onProgress = (received: number, total: number): void => this.publishAudioProgress(received, total, stale);
      try {
        await AudioOfflineStore.download(task);
        if (stale()) return '';
        AudioPrefetch.notifyChanged();
        const path = await local();
        if (path) return path;
      } catch (error) {
        const message = (error as Error)?.message || '';
        if (stale() || message === AudioOfflineStore.CANCELED) return '';
        // 空间不足、超出离线上限：换地址也没用，直接告诉用户。
        if (message === AudioOfflineStore.STORAGE_FAILURE || message === AudioOfflineStore.CAP_REACHED) throw error as Error;
        console.warn('[Subtitle] direct audio download failed, resolving again:', message);
      }
    }
    if (stale()) return '';
    this.publish(AudioSubtitleService.AUDIO, '正在重新获取音频地址…');
    const engine = ReadBookEngine.createBackgroundWorker();
    this.engine = engine;
    await engine.openBook(book);
    if (stale()) return '';
    engine.audioAuto = true;
    engine.audioAllowCellular = true;
    const timer = setInterval((): void => {
      const received = engine.audioProgress.get(chapterIndex) || 0;
      if (received > 0) this.publishAudioProgress(received, 0, stale);
    }, 500);
    try {
      const ok = await engine.cacheChapter(chapterIndex, stale);
      if (!ok || stale()) return '';
      AudioPrefetch.notifyChanged();
      return await local();
    } finally {
      clearInterval(timer);
    }
  }

  private lastAudioProgressAt: number = 0;

  private publishAudioProgress(received: number, total: number, stale: () => boolean): void {
    const now = Date.now();
    if (stale() || now - this.lastAudioProgressAt < 300) return;
    this.lastAudioProgressAt = now;
    const mb = (bytes: number): string => (bytes / 1024 / 1024).toFixed(1);
    this.publish(AudioSubtitleService.AUDIO, total > 0 ?
      `${mb(received)} / ${mb(total)} MB（${Math.min(100, Math.floor(received * 100 / total))}%）` :
      `已取 ${mb(received)} MB`);
  }

  /** 从数据库取一章的地址和标题，不用为此打开整本书。 */
  private static async chapterOf(bookUrl: string, chapterIndex: number): Promise<BookChapter | undefined> {
    const chapters = await AppDatabase.getInstance().getBookChapters(bookUrl);
    const exact = chapters.find((chapter: BookChapter): boolean => chapter.index === chapterIndex);
    return exact || chapters[chapterIndex];
  }

  /** 选下一段：播放中从当前段往后，读完再补前面；暂停时只看当前段和下一段。 */
  private schedule(): void {
    if (this.inFlight || this.threadLoading) return;
    const job = this.job;
    if (!job || job.key !== this.playingKey()) return;
    const playback = this.playback();
    if (job.durationMs <= 0 && playback.durationMs > 0) job.durationMs = playback.durationMs;
    const count = job.chunkCount();
    if (count <= 0) return;
    const playing = playback.state === 'playing';
    const current = Math.min(count - 1, Math.floor(Math.max(0, playback.positionMs) / CHUNK_MS));
    const order: number[] = [];
    const ahead = playing ? count : Math.min(count, current + 2);
    for (let i = current; i < ahead; i++) order.push(i);
    if (playing) for (let i = 0; i < current; i++) order.push(i);
    const next = order.find((i: number): boolean => !job.chunks.has(i) && (job.failures.get(i) || 0) < 2);
    if (next !== undefined) {
      this.recognize(job, next);
      return;
    }
    if (job.complete()) this.saveCache(job, true);
    if (playing && job.complete() && AudioBookSettingsStore.subtitlePrefetchNext()) this.scheduleNextChapter(job);
  }

  /** 本章识别完、正在播放：下一章已经下载在本地时，先识别它的开头。不会为此去下载下一章。 */
  private scheduleNextChapter(current: SubtitleJob): void {
    const nextIndex = current.chapterIndex + 1;
    const key = `${current.bookUrl}#${nextIndex}`;
    const job = this.nextJob;
    if (job && job.key === key) {
      if (job.complete()) {
        this.saveCache(job, true);
        return;
      }
      for (let i = 0; i < job.chunkCount(); i++) {
        if (!job.chunks.has(i) && (job.failures.get(i) || 0) < 2) {
          this.recognize(job, i);
          return;
        }
      }
      return;
    }
    if (this.preparingKey) return;
    this.preparingKey = key;
    this.prepareNextChapter(current.bookUrl, nextIndex, key).catch((error: Error): void => {
      console.warn('[Subtitle] prepare next chapter failed:', error);
    }).finally((): void => {
      if (this.preparingKey === key) this.preparingKey = '';
    });
  }

  private async prepareNextChapter(bookUrl: string, chapterIndex: number, key: string): Promise<void> {
    const book = await AppDatabase.getInstance().getBook(bookUrl);
    if (!book) return;
    const chapter = await AudioSubtitleService.chapterOf(bookUrl, chapterIndex);
    const marker = new SubtitleJob();
    marker.key = key;
    if (!chapter) {
      this.nextJob = marker;
      return;
    }
    const voice = book.getVariable('custom') || '';
    const path = await AudioOfflineStore.localFile(bookUrl, chapterIndex, chapter.url, chapter.title, voice);
    marker.bookUrl = bookUrl;
    marker.chapterIndex = chapterIndex;
    if (path) {
      marker.path = path;
      marker.cachePath = AudioSubtitleService.cachePath(key, `${chapter.url}#${chapter.title}#${voice}`, path);
      marker.durationMs = AudioSubtitleService.probe(path);
      marker.limit = NEXT_CHAPTER_CHUNKS;
      AudioSubtitleService.loadCache(marker);
    }
    // 没有本地文件时留一个空任务（段数为 0），这一章就不再反复检查。
    this.nextJob = marker;
  }

  private recognize(job: SubtitleJob, index: number): void {
    this.inFlight = job;
    this.inFlightChunk = index;
    this.ensureWorker().then((): Promise<SubtitleWorkerReply> => {
      const request = new SubtitleWorkerRequest();
      request.type = 'recognize';
      request.path = job.path;
      request.startMs = index * CHUNK_MS;
      request.endMs = Math.min((index + 1) * CHUNK_MS, job.durationMs > 0 ? job.durationMs : (index + 1) * CHUNK_MS);
      return this.send(request);
    }).then((reply: SubtitleWorkerReply): void => {
      if (reply.type === 'result') {
        job.chunks.set(index, reply.cues);
        job.dirty++;
        if (reply.durationMs > 0 && job.durationMs <= 0) job.durationMs = reply.durationMs;
        if (!this.loadConfirmed) {
          this.loadConfirmed = true;
          SubtitleModelStore.clearLoading();
        }
        if (job === this.job) {
          this.rebuild();
          if (AppStorage.get<string>(AudioSubtitleService.PHASE_KEY) !== AudioSubtitleService.READY) {
            this.publish(AudioSubtitleService.READY, '');
          }
        }
        if (job.dirty >= 4) this.saveCache(job, false);
      } else {
        job.failures.set(index, (job.failures.get(index) || 0) + 1);
        console.warn(`[Subtitle] chunk ${index} failed:`, reply.message);
        if (job === this.job && job.chunks.size === 0 && (job.failures.get(index) || 0) >= 2) {
          this.failedKey = job.key;
          this.publish(AudioSubtitleService.ERROR, AudioSubtitleService.describeFailure(reply.message));
        }
      }
    }).catch((error: Error): void => {
      console.warn('[Subtitle] recognize failed:', error);
      job.failures.set(index, (job.failures.get(index) || 0) + 1);
      if (job === this.job && (error?.message || '').startsWith('subtitle_load')) {
        this.failedKey = job.key;
        this.publish(AudioSubtitleService.ERROR, '字幕模型加载失败，可在有声书设置里删除后重新下载');
      }
    }).finally((): void => {
      if (this.inFlight === job && this.inFlightChunk === index) {
        this.inFlight = null;
        this.inFlightChunk = -1;
      }
      if (this.visibleCount > 0 && !AudioSubtitleService.inBackground()) this.schedule();
    });
  }

  private rebuild(): void {
    const job = this.job;
    if (!job) {
      this.merged = [];
    } else {
      const keys = Array.from(job.chunks.keys()).sort((a: number, b: number): number => a - b);
      this.merged = SubtitleText.merge(keys.map((key: number): SubtitleCue[] => job.chunks.get(key) || []));
    }
    this.bumpRevision();
  }

  private ensureWorker(): Promise<void> {
    if (this.thread && this.threadReady) return Promise.resolve();
    if (this.threadLoading) return this.threadLoading;
    const loading = new Promise<void>((resolve, reject): void => {
      if (SubtitleModelStore.recoverInterruptedLoad()) {
        reject(new Error('subtitle_load: interrupted'));
        return;
      }
      const thread = new worker.ThreadWorker('../../workers/AudioSubtitleWorker.ets', { name: 'AudioSubtitle' });
      this.thread = thread;
      this.threadReady = false;
      thread.onmessage = (event: MessageEvents): void => {
        const reply = event.data as SubtitleWorkerReply;
        if (reply.type === 'loaded') {
          this.threadReady = true;
          resolve();
          return;
        }
        if (reply.type === 'error') {
          // 能回消息说明进程没崩，只是这次加载失败，不算进崩溃计数。
          SubtitleModelStore.clearLoading();
          reject(new Error(reply.message || 'subtitle_load'));
          this.releaseWorker();
          return;
        }
        const callback = this.pending.get(reply.id);
        if (callback) {
          this.pending.delete(reply.id);
          callback(reply);
        }
      };
      thread.onerror = (): void => {
        console.warn('[Subtitle] worker error');
        reject(new Error('subtitle_load: worker'));
        this.releaseWorker();
      };
      SubtitleModelStore.markLoading();
      const request = new SubtitleWorkerRequest();
      request.type = 'load';
      request.model = SubtitleModelStore.path(SubtitleModelStore.ASR);
      request.tokens = SubtitleModelStore.path(SubtitleModelStore.TOKENS);
      request.punct = SubtitleModelStore.path(SubtitleModelStore.PUNCT);
      request.threads = 2;
      thread.postMessage(request);
    });
    this.threadLoading = loading;
    return loading.finally((): void => {
      if (this.threadLoading === loading) this.threadLoading = null;
    });
  }

  private send(request: SubtitleWorkerRequest): Promise<SubtitleWorkerReply> {
    const thread = this.thread;
    if (!thread) return Promise.reject(new Error('subtitle_worker_gone'));
    request.id = ++this.requestId;
    return new Promise<SubtitleWorkerReply>((resolve, reject): void => {
      if (this.inFlightTimer >= 0) clearTimeout(this.inFlightTimer);
      this.inFlightTimer = setTimeout((): void => {
        this.inFlightTimer = -1;
        if (!this.pending.has(request.id)) return;
        this.pending.delete(request.id);
        reject(new Error('subtitle_timeout'));
        this.releaseWorker();
      }, CHUNK_TIMEOUT_MS);
      this.pending.set(request.id, (reply: SubtitleWorkerReply): void => {
        if (this.inFlightTimer >= 0) clearTimeout(this.inFlightTimer);
        this.inFlightTimer = -1;
        resolve(reply);
      });
      thread.postMessage(request);
    });
  }

  private releaseWorker(): void {
    const thread = this.thread;
    this.thread = null;
    this.threadReady = false;
    // 下次重新加载模型时要重新确认一次加载成功。
    this.loadConfirmed = false;
    const pending = Array.from(this.pending.values());
    this.pending.clear();
    for (const callback of pending) {
      const reply = new SubtitleWorkerReply();
      reply.type = 'failed';
      reply.message = 'subtitle_worker_gone';
      callback(reply);
    }
    if (thread) {
      try { thread.terminate(); } catch (_) {}
    }
  }

  private saveCache(job: SubtitleJob | null, force: boolean): void {
    if (!job || !job.cachePath || job.dirty === 0 || (!force && job.dirty < 4)) return;
    const data = new SubtitleCacheFile();
    data.model = SubtitleModelStore.VERSION;
    data.durationMs = job.durationMs;
    job.chunks.forEach((cues: SubtitleCue[], index: number): void => {
      data.chunks[`${index}`] = cues;
    });
    job.dirty = 0;
    try {
      const dir = job.cachePath.substring(0, job.cachePath.lastIndexOf('/'));
      if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
      const temp = `${job.cachePath}.tmp`;
      const file = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, JSON.stringify(data));
      } finally {
        fs.closeSync(file);
      }
      fs.renameSync(temp, job.cachePath);
    } catch (error) {
      console.warn('[Subtitle] save cache failed:', error);
    }
  }

  private static loadCache(job: SubtitleJob): void {
    try {
      if (!job.cachePath || !fs.accessSync(job.cachePath)) return;
      const data = JSON.parse(fs.readTextSync(job.cachePath)) as SubtitleCacheFile;
      if (data.version !== CACHE_VERSION || data.model !== SubtitleModelStore.VERSION || data.chunkMs !== CHUNK_MS) return;
      if (job.durationMs <= 0 && data.durationMs > 0) job.durationMs = data.durationMs;
      const chunks: Record<string, SubtitleCue[]> = data.chunks ? data.chunks : {};
      for (const key of Object.keys(chunks)) {
        const index = Number.parseInt(key, 10);
        const cues = chunks[key];
        if (Number.isFinite(index) && Array.isArray(cues)) job.chunks.set(index, cues);
      }
    } catch (error) {
      console.warn('[Subtitle] read cache failed:', error);
    }
  }

  /** 缓存文件名：章节键 + 章节身份 + 文件大小 + 模型版本的哈希。 */
  private static cachePath(key: string, identity: string, path: string): string {
    const root = AppStorage.get<string>('appCacheDir') || '';
    if (!root) return '';
    let size = 0;
    try { size = fs.statSync(path).size; } catch (_) {}
    const source = `${key}#${identity}#${size}#${SubtitleModelStore.VERSION}`;
    return `${root}/audio_subtitles/${AudioSubtitleService.hash(source)}.json`;
  }

  /** 两路 FNV-1a 拼成 16 位十六进制，只用来起文件名。 */
  private static hash(text: string): string {
    let a = 0x811c9dc5;
    let b = 0x01000193 ^ text.length;
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i);
      a = Math.imul(a ^ code, 0x01000193) >>> 0;
      b = Math.imul(b ^ code, 0x5bd1e995) >>> 0;
    }
    return a.toString(16).padStart(8, '0') + b.toString(16).padStart(8, '0');
  }

  /** 播放器里的地址是本地文件时返回路径。 */
  private static localPath(mediaUrl: string): string {
    if (mediaUrl.startsWith('/')) return mediaUrl;
    if (mediaUrl.startsWith('file://')) {
      try {
        return new fileUri.FileUri(mediaUrl).path;
      } catch (_) {
        return '';
      }
    }
    return '';
  }

  private static probe(path: string): number {
    try {
      return subtitleAudio.probe(path);
    } catch (error) {
      console.warn('[Subtitle] probe failed:', error);
      return 0;
    }
  }

  private static describeFailure(message: string): string {
    if (message.includes('subtitle_codec') || message.includes('subtitle_no_audio') ||
      message.includes('subtitle_format')) {
      return '这种音频格式暂时识别不了';
    }
    if (message.includes('subtitle_open')) return '读不到本章音频文件';
    return '识别失败，可点重试';
  }
}
