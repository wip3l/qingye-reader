import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BookChapter, sleepMs } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { ReadBookEngine } from '../book/ReadBookEngine';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { FullTextCacheCancelCoordinator, FullTextCacheCancelSignal } from '../../utils/FullTextCacheCancelCoordinator';

const NOTIFICATION_INTERVAL_MS = 5000;
const NOTIFICATION_ID = 2601;
const CANCEL_REQUEST_CODE = 2602;
const OPEN_REQUEST_CODE = 2603;

/** 阅读页为全文缓存任务提供的环境。 */
export interface ReaderFullTextCacheHost {
  abilityContext: () => common.UIAbilityContext;
  bookUrl: () => string;
  bookName: () => string;
  /** 朗读正持有后台长时任务。 */
  ttsBackgroundRunning: () => boolean;
  /** 朗读正持有或正在申请后台长时任务。 */
  ttsBackgroundBusy: () => boolean;
  /** caching / done / total / status 有变化，页面据此刷新自己的展示状态。 */
  onStateChanged: () => void;
  onChaptersChanged: (chapters: BookChapter[]) => void;
}

/**
 * 阅读页的章节缓存后台任务：缓存全文或指定章节，逐章缓存、通知栏进度与取消、后台长时任务的申请和释放。
 * 与书架的缓存任务同一套做法：任务用自己的后台引擎，不占用阅读页正在使用的引擎，
 * 进度按本次要缓存的章节计算，对话框可以随时关闭而不影响任务。
 * 不持有任何界面状态；后台长时任务与朗读共用同一个 Ability 许可，谁后结束谁负责释放。
 */
export class ReaderFullTextCacheController {
  caching: boolean = false;
  done: number = 0;
  total: number = 0;
  status: string = '';
  /** 本任务是否在占用后台长时任务许可；朗读停止后台时会读写它来交接许可。 */
  backgroundRunning: boolean = false;
  /** 任务引擎里的最新目录（含缓存标记），对话框用它刷新"已缓存"标识；没有跑过任务时为空。 */
  chapters: BookChapter[] = [];

  private readonly host: ReaderFullTextCacheHost;
  private taskId: number = 0;
  private taskKey: string = '';
  private cancelRequested: boolean = false;
  private cancelSeenNonce: number = 0;
  private notificationLastAt: number = 0;
  private cancelAgent: WantAgent | null = null;
  private stoppingNotificationTask: Promise<void> | null = null;
  private startedAt: number = 0;
  private scopeLabel: string = '全文';
  private engine: ReadBookEngine | null = null;
  private liveSyncAt: number = 0;
  private notificationSlotReady: boolean = false;
  private notificationFailureHintShown: boolean = false;

  private listeners: Set<() => void> = new Set<() => void>();

  constructor(host: ReaderFullTextCacheHost) {
    this.host = host;
  }

  /** 订阅 caching / done / total / status 的变化，返回取消订阅的函数。对话框组件靠它刷新自己的状态。 */
  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return (): void => {
      this.listeners.delete(listener);
    };
  }

  /** 进行中优先显示状态文字，其次是进度。 */
  panelStatus(): string {
    return this.caching ? (this.status || this.progressText()) : '';
  }

  private notifyStateChanged(): void {
    this.host.onStateChanged();
    for (const listener of Array.from(this.listeners)) listener();
  }

  static countCached(chapters: BookChapter[]): number {
    let count = 0;
    for (const chapter of chapters) {
      if (chapter.cacheDate > 0) count++;
    }
    return count;
  }

  static countCachedIn(chapters: BookChapter[], indexes: number[]): number {
    let count = 0;
    for (const index of indexes) {
      const chapter = chapters[index];
      if (chapter && chapter.cacheDate > 0) count++;
    }
    return count;
  }

  progressText(): string {
    const total = Math.max(this.total, 0);
    if (total === 0) return '正在准备缓存章节';
    const done = Math.max(0, Math.min(this.done, total));
    const percent = Math.floor((done / total) * 100);
    return `已缓存 ${done}/${total} 章（${percent}%）`;
  }

  /**
   * 启动一次缓存。chapterIndexes 为空表示全书，否则只缓存这些章节；scopeLabel 用在通知标题和状态文字里
   * （"全文" 或 "章节"）。调用方负责前置校验和提示。
   */
  start(chapterIndexes: number[] = [], scopeLabel: string = '全文'): void {
    this.scopeLabel = scopeLabel || '全文';
    this.run(++this.taskId, chapterIndexes).catch(async (error: Error): Promise<void> => {
      if (this.cancelRequested) {
        if (this.stoppingNotificationTask) await this.stoppingNotificationTask;
        this.caching = false;
        this.status = '缓存已取消';
        this.notifyStateChanged();
        await this.publishNotification('缓存已停止', this.progressText(), false);
        await this.stopBackgroundRunning();
        this.releaseCancelRegistration();
        this.cancelRequested = false;
        return;
      }
      this.releaseCancelRegistration();
      console.error('章节缓存任务失败:', error);
      this.caching = false;
      this.status = '缓存失败';
      this.notifyStateChanged();
      HdsFeedback.showToast('缓存失败');
      this.publishNotification('缓存失败', this.progressText(), false).catch((e: Error) => {
        console.warn('更新全文缓存失败通知失败:', e);
      });
      this.stopBackgroundRunning().catch((e: Error) => {
        console.warn('停止全文缓存后台任务失败:', e);
      });
    });
  }

  /** 通知栏取消动作通过 AppStorage 里的 nonce 传到页面，页面转交到这里。 */
  onCancelNonceChanged(nonce: number): void {
    if (!this.caching || nonce <= 0 || nonce === this.cancelSeenNonce) return;
    const signal = FullTextCacheCancelCoordinator.parse(AppStorage.get<string>('fullTextCacheCancelSignal') || '');
    if (signal && !FullTextCacheCancelCoordinator.matches(signal, this.taskKey, this.host.bookUrl())) {
      this.cancelSeenNonce = nonce;
      return;
    }
    this.beginStopping(signal ? signal.nonce : nonce, true);
  }

  private async run(taskId: number, chapterIndexes: number[]): Promise<void> {
    const bookUrl = this.host.bookUrl();
    if (!bookUrl) return;

    this.caching = true;
    this.cancelRequested = false;
    this.cancelSeenNonce = AppStorage.get<number>('fullTextCacheCancelNonce') || 0;
    this.notificationLastAt = 0;
    this.cancelAgent = null;
    this.stoppingNotificationTask = null;
    this.startedAt = Date.now();
    this.notificationFailureHintShown = false;
    this.liveSyncAt = 0;
    this.taskKey = `reader_${taskId}_${this.startedAt}`;
    this.total = 0;
    this.done = 0;
    this.status = `${this.scopeLabel}缓存后台进行中`;
    this.notifyStateChanged();
    FullTextCacheCancelCoordinator.register(this.taskKey, bookUrl,
      (signal: FullTextCacheCancelSignal): void => {
        if (FullTextCacheCancelCoordinator.matches(signal, this.taskKey, bookUrl)) {
          this.beginStopping(signal.nonce, true);
        }
      });

    await this.startBackgroundRunning();
    await this.requestNotificationEnabled();
    await this.publishNotification('准备缓存章节', this.progressText(), true);

    // The task owns its engine. The reader's engine follows whatever book and chapter the reader is on;
    // sharing it would let a book switch or a cancelled request in the reader derail the task.
    const db = AppDatabase.getInstance();
    await db.initWithContext(this.host.abilityContext());
    const book = await db.getBook(bookUrl);
    if (!book) throw new Error('书籍不存在');
    const engine = ReadBookEngine.createBackgroundWorker();
    this.engine = engine;
    await engine.openBook(book);
    await engine.syncChapterCacheDates();
    if (taskId !== this.taskId) {
      this.releaseCancelRegistration();
      return;
    }

    // A scoped task reports progress against the chapters it was asked for, so the percentage in the
    // notification matches the request. Indexes that no longer exist after a catalogue refresh are dropped.
    const targets: number[] = [];
    if (chapterIndexes.length === 0) {
      for (let index = 0; index < engine.chapters.length; index++) targets.push(index);
    } else {
      for (const index of chapterIndexes) {
        if (index >= 0 && index < engine.chapters.length) targets.push(index);
      }
    }
    this.chapters = [...engine.chapters];
    this.total = targets.length;
    this.done = 0;
    this.notifyStateChanged();

    if (!this.shouldCancel()) await this.publishProgress(true);

    for (let position = 0; position < targets.length; position++) {
      if (taskId !== this.taskId || this.shouldCancel()) break;
      const index = targets[position];
      const chapter = engine.chapters[index];
      if (!chapter) continue;

      const ok = await this.cacheChapter(engine, index, taskId);
      if (engine.lastCacheError) throw new Error(engine.lastCacheError);
      if (taskId !== this.taskId) break;
      if (ok) {
        this.done++;
        this.chapters = [...engine.chapters];
        this.notifyStateChanged();
        await this.syncLiveEngine(bookUrl, false);
      }
      if (this.shouldCancel()) break;
      await this.publishProgress(false);
      await sleepMs(0);
    }

    if (taskId !== this.taskId) {
      this.releaseCancelRegistration();
      return;
    }

    const canceled = this.shouldCancel();
    await engine.syncChapterCacheDates();
    this.chapters = [...engine.chapters];
    await this.syncLiveEngine(bookUrl, true);
    this.caching = false;
    const failedCount = Math.max(0, this.total - this.done);
    this.status = canceled ? '缓存已取消' :
      (failedCount > 0 ? `缓存结束，${failedCount} 章未缓存` : `${this.scopeLabel}缓存完成`);
    this.notifyStateChanged();
    if (canceled && this.stoppingNotificationTask) await this.stoppingNotificationTask;
    await this.publishNotification(canceled ? '缓存已停止' : this.status, this.progressText(), false);
    HdsFeedback.showToast(canceled ? '缓存已停止' : `缓存完成 ${this.done}/${this.total}`);
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    await this.stopBackgroundRunning();
    this.releaseCancelRegistration();
    this.cancelRequested = false;
  }

  // The reader's own engine holds separate chapter objects. Refresh their cache marks from the database,
  // at most every couple of seconds while the task runs, so the reader's catalogue shows "已缓存" too.
  private async syncLiveEngine(bookUrl: string, force: boolean): Promise<void> {
    const now = Date.now();
    if (!force && now - this.liveSyncAt < 2000) return;
    this.liveSyncAt = now;
    try {
      const live = ReadBookEngine.get();
      if (live.book?.bookUrl !== bookUrl) return;
      await live.syncChapterCacheDates();
      if (live.book?.bookUrl === bookUrl) this.host.onChaptersChanged([...live.chapters]);
    } catch (error) {
      console.warn('同步阅读页目录缓存标记失败:', error);
    }
  }

  private beginStopping(nonce: number, showHint: boolean): void {
    if (!this.caching || this.cancelRequested) return;
    this.cancelRequested = true;
    this.cancelSeenNonce = nonce;
    this.status = '正在停止缓存…';
    this.notifyStateChanged();
    if (this.engine) this.engine.cancelPendingRequests();
    this.stoppingNotificationTask = this.publishNotification('正在停止缓存…', this.progressText(), true)
      .catch((error: Error) => console.warn('更新正在停止缓存通知失败:', error));
    if (showHint) HdsFeedback.showToast('正在停止缓存…');
  }

  private releaseCancelRegistration(): void {
    this.engine = null;
    FullTextCacheCancelCoordinator.unregister(this.taskKey);
    this.taskKey = '';
    this.stoppingNotificationTask = null;
  }

  private shouldCancel(): boolean {
    if (this.cancelRequested) return true;
    const nonce = AppStorage.get<number>('fullTextCacheCancelNonce') || 0;
    if (nonce > 0 && nonce !== this.cancelSeenNonce) {
      const signal = FullTextCacheCancelCoordinator.parse(AppStorage.get<string>('fullTextCacheCancelSignal') || '');
      if (signal && !FullTextCacheCancelCoordinator.matches(signal, this.taskKey, this.host.bookUrl())) {
        this.cancelSeenNonce = nonce;
        return false;
      }
      this.beginStopping(signal ? signal.nonce : nonce, false);
      return this.cancelRequested;
    }
    return false;
  }

  private async cacheChapter(engine: ReadBookEngine, chapterIndex: number, taskId: number): Promise<boolean> {
    for (let attempt = 0; attempt < 2; attempt++) {
      if (taskId !== this.taskId || this.shouldCancel()) return false;
      try {
        if (await engine.cacheChapter(chapterIndex,
          (): boolean => taskId !== this.taskId || this.shouldCancel())) {
          return true;
        }
      } catch (error) {
        if (!this.shouldCancel()) {
          console.warn(`缓存第 ${chapterIndex + 1} 章失败（第 ${attempt + 1} 次）:`, error);
        }
      }
      if (engine.lastCacheError) return false;
      if (attempt === 0) await sleepMs(300);
    }
    return false;
  }

  private async publishProgress(force: boolean): Promise<void> {
    const now = Date.now();
    if (!force && now - this.notificationLastAt < NOTIFICATION_INTERVAL_MS) return;
    this.notificationLastAt = now;
    await this.publishNotification(this.status || `${this.scopeLabel}缓存后台进行中`, this.progressText(), true);
  }

  // Same request shape as the bookshelf's cache notification, which is known to publish: an explicit slot,
  // a tap target, and no optional field left as undefined. The reader used to build a sparser request and
  // swallow the failure, so the notification silently never appeared.
  private async publishNotification(text: string, additionalText: string, ongoing: boolean): Promise<void> {
    try {
      await this.ensureNotificationSlot();
      await notificationManager.publish(await this.buildNotificationRequest(text, additionalText, ongoing, true));
    } catch (error) {
      console.warn('发布全文缓存通知失败:', error);
      try {
        // A rejected action button must not cost the user the progress display as well.
        await notificationManager.publish(await this.buildNotificationRequest(text, additionalText, ongoing, false));
      } catch (fallbackError) {
        console.warn('发布全文缓存基础通知失败:', fallbackError);
        this.showNotificationFailureHint(fallbackError as Object);
      }
    }
  }

  private async buildNotificationRequest(text: string, additionalText: string, ongoing: boolean,
    withCancelButton: boolean): Promise<notificationManager.NotificationRequest> {
    const bookName = this.host.bookName();
    const request: notificationManager.NotificationRequest = {
      id: NOTIFICATION_ID,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      isOngoing: ongoing,
      tapDismissed: false,
      isAlertOnce: true,
      deliveryTime: this.startedAt,
      showDeliveryTime: false,
      wantAgent: await this.openWantAgent(),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: bookName ? `缓存${this.scopeLabel}：${bookName}` : `缓存${this.scopeLabel}`,
          // The system panel does not show additionalText, so the progress has to ride in the main line.
          text: ongoing && additionalText && !text.includes(additionalText) ? `${text} · ${additionalText}` : text,
          additionalText: additionalText
        }
      }
    };
    request.label = 'full_text_cache';
    if (!ongoing) request.autoDeletedTime = Date.now() + 5000;
    if (ongoing && withCancelButton) {
      request.actionButtons = [{
        title: '停止缓存',
        wantAgent: await this.cancelWantAgent()
      }];
    }
    return request;
  }

  private async ensureNotificationSlot(): Promise<void> {
    if (this.notificationSlotReady) return;
    await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
    this.notificationSlotReady = true;
  }

  private showNotificationFailureHint(error: Object): void {
    if (this.notificationFailureHintShown) return;
    this.notificationFailureHintShown = true;
    const code = (error as Record<string, Object>)['code'];
    const errorCode = typeof code === 'number' ? code as number : 0;
    if (errorCode === 1600004 || errorCode === 1600020) {
      HdsFeedback.showToast('通知权限未开启，缓存仍会继续');
    } else if (errorCode === 1600005) {
      HdsFeedback.showToast('通知类别已关闭，请检查应用通知设置');
    } else {
      HdsFeedback.showToast(errorCode > 0 ? `通知发布失败(${errorCode})，缓存仍会继续` : '通知发布失败，缓存仍会继续');
    }
  }

  private async requestNotificationEnabled(): Promise<void> {
    try {
      if (await notificationManager.isNotificationEnabled()) return;
      await notificationManager.requestEnableNotification(this.host.abilityContext());
    } catch (error) {
      console.warn('请求通知权限失败:', error);
    }
  }

  private async cancelWantAgent(): Promise<WantAgent> {
    if (this.cancelAgent) return this.cancelAgent;
    this.cancelAgent = await wantAgent.getWantAgent({
      wants: [{
        bundleName: this.host.abilityContext().abilityInfo.bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          cacheAction: 'cancelFullTextCache',
          cacheTaskId: this.taskId,
          cacheTaskKey: this.taskKey,
          bookUrl: this.host.bookUrl()
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: CANCEL_REQUEST_CODE,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
    return this.cancelAgent;
  }

  private async startBackgroundRunning(): Promise<void> {
    if (this.backgroundRunning) return;
    if (this.host.ttsBackgroundRunning()) {
      this.backgroundRunning = true;
      return;
    }
    try {
      const agent = await this.openWantAgent();
      await backgroundTaskManager.startBackgroundRunning(this.host.abilityContext(), ['dataTransfer'], agent);
      this.backgroundRunning = true;
    } catch (error) {
      console.warn('启动全文缓存后台任务失败:', error);
    }
  }

  private async stopBackgroundRunning(): Promise<void> {
    if (!this.backgroundRunning) return;
    this.backgroundRunning = false;
    if (this.host.ttsBackgroundBusy()) return;
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.host.abilityContext());
    } catch (error) {
      console.warn('停止全文缓存后台任务失败:', error);
    }
  }

  private async openWantAgent(): Promise<WantAgent> {
    return await wantAgent.getWantAgent({
      wants: [{
        bundleName: this.host.abilityContext().abilityInfo.bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          bookUrl: this.host.bookUrl()
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: OPEN_REQUEST_CODE,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
  }
}
