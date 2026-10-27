import { Context } from '@kit.AbilityKit';
import { bundleManager } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { connection } from '@kit.NetworkKit';
import deviceInfo from '@ohos.deviceInfo';
import display from '@ohos.display';
import { AccountCommerceApi } from './AccountCommerceApi';
import { AccountApiError } from './AccountCommerceModels';
import { AccountSessionStore } from './AccountSessionStore';
import { ReadStatsCloudSync } from './ReadStatsCloudSync';
import { readStatsTracker } from '../core/stats/ReadStatsTracker';
import {
  CloudSyncAcknowledgement,
  CloudSyncChange,
  CloudSyncExchangeRequest,
  CloudSyncExchangeResponse,
  CloudSyncOperation
} from './CloudSyncModels';
import { CloudSyncSettings, CloudSyncSettingsStore } from './CloudSyncSettingsStore';
import { CloudSyncIssue, CloudSyncIssueStore } from './CloudSyncIssueStore';
import { CloudSyncChangeSnapshot, CloudSyncChangeTracker } from './CloudSyncChangeTracker';
import {
  CloudSyncEntityState,
  CloudSyncLocalState,
  CloudSyncStateStore
} from './CloudSyncStateStore';
import { AppDatabase } from '../model/data/AppDatabase';
import { Book, BookGroup, BookInfoRule, BookListRule, BookSource, Bookmark, ContentRule, ExploreRule, ReadConfig, SearchRule, TocRule } from '@legado/sourceengine';
import { ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderPreferencesSync, ReaderPreferencesSyncPayload } from './ReaderPreferencesSync';
import {
  ReaderReplaceRule,
  ReaderReplaceRuleStore
} from '../utils/ReaderReplaceRuleStore';
import { AppThemeSettings, AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { AppThemeModeStore } from '../utils/AppThemeModeStore';
import {
  BookshelfDisplaySettings,
  BookshelfDisplaySettingsStore
} from '../utils/BookshelfDisplaySettingsStore';
import {
  SearchExploreSettingsStore
} from '../utils/SearchExploreSettingsStore';
import {
  CustomThemeScheme,
  CustomThemeSchemeStore
} from '../utils/CustomThemeSchemeStore';
import { BookIdentity } from '../utils/BookIdentity';
import { LocalBookService } from '../core/book/LocalBookService';

class BookshelfSyncPayload {
  bookUrl: string = '';
  tocUrl: string = '';
  origin: string = '';
  originName: string = '';
  name: string = '';
  author: string = '';
  kind: string = '';
  status: string = '';
  customTag: string = '';
  coverUrl: string = '';
  customCoverUrl: string = '';
  intro: string = '';
  customIntro: string = '';
  charset: string = '';
  type: number = 0;
  groupName: string = '';
  isPinned: boolean = false;
  latestChapterTitle: string = '';
  updateTime: string = '';
  latestChapterTime: number = 0;
  totalChapterNum: number = 0;
  wordCount: string = '';
  canUpdate: boolean = true;
  order: number = 0;
  originOrder: number = 0;
  readConfig: ReadConfig | null = null;
  shelfModifiedTime: number = 0;
}

class ReadingProgressSyncPayload {
  bookUrl: string = '';
  origin: string = '';
  /** Only populated for local books; device-specific local:// URLs stay local. */
  localContentHash: string = '';
  chapterTitle: string = '';
  chapterIndex: number = 0;
  chapterPos: number = 0;
  updatedAt: number = 0;
}

class BookGroupSyncPayload {
  name: string = '';
  order: number = 0;
  show: boolean = true;
  enableRefresh: boolean = true;
}

class BookmarkSyncPayload {
  bookUrl: string = '';
  bookName: string = '';
  bookAuthor: string = '';
  chapterIndex: number = 0;
  chapterName: string = '';
  pageIndex: number = 0;
  startPos: number = 0;
  endPos: number = 0;
  content: string = '';
  createTime: number = 0;
}

class BookSourceSyncPayload {
  bookSourceUrl: string = '';
  bookSourceName: string = '';
  bookSourceType: number = 0;
  bookSourceGroup: string = '';
  bookSourceComment: string = '';
  loginUrl: string = '';
  loginUi: string = '';
  loginCheckJs: string = '';
  loginHeader: string = '';
  bookUrlPattern: string = '';
  searchUrl: string = '';
  exploreUrl: string = '';
  jsLib: string = '';
  header: string = '';
  bookListRule: BookListRule = new BookListRule();
  searchRule: SearchRule = new SearchRule();
  exploreRule: ExploreRule = new ExploreRule();
  bookInfoRule: BookInfoRule = new BookInfoRule();
  tocRule: TocRule = new TocRule();
  contentRule: ContentRule = new ContentRule();
  variableComment: string = '';
  respondTime: number = 180000;
  customOrder: number = 0;
  customButton: boolean = false;
  eventListener: boolean = false;
  isPinned: boolean = false;
  enabled: boolean = true;
  enabledExplore: boolean = true;
  isLocked: boolean = false;
  weight: number = 0;
  concurrentRate: string = '';
  enabledCookieJar: boolean = true;
}

class AppearanceModeSyncPayload {
  mode: string = 'system';
}

class SearchPreferencesSyncPayload {
  showResultCover: boolean = true;
  showResultCoverBackground: boolean = true;
  useBookshelfCoverGallery: boolean = false;
  showResultTags: boolean = true;
  aggregateSearchResults: boolean = true;
  promptAddToShelfOnBack: boolean = true;
  exactSearch: boolean = false;
  exactSearchMatchAuthor: boolean = true;
  showSearchProgress: boolean = true;
}

class CustomThemeSchemesSyncPayload {
  schemes: CustomThemeScheme[] = [];
}

class LocalSyncEntity {
  entityType: string = '';
  entityId: string = '';
  payloadJson: string = '';
  contentHash: string = '';
  localKey: string = '';
  /** 给用户看的名称（书源名、书名等），只用于同步问题记录。 */
  label: string = '';
}

export class CloudSyncRunResult {
  skipped: number = 0;
  warning: string = '';
  uploaded: number = 0;
  downloaded: number = 0;
  conflicts: number = 0;
}

export class CloudSyncCoordinator {
  static readonly TRIGGER_CHANGE: string = 'change';
  static readonly TRIGGER_FOREGROUND: string = 'foreground';
  static readonly TRIGGER_BACKGROUND: string = 'background';

  private static running: Promise<CloudSyncRunResult> | null = null;
  private static lastSyncAttemptAt: number = 0;
  private static deferredAutomaticTimer: number = -1;
  private static readonly AUTOMATIC_MIN_INTERVAL_MS: number = 15 * 1000;
  private static readonly FOREGROUND_REFRESH_INTERVAL_MS: number = 30 * 60 * 1000;
  private static readonly MAX_BATCH_OPERATIONS: number = 100;
  // A single book-source entity may be up to 512 KiB. Keep enough room for the
  // operation envelope while staying well below the server's 2 MiB request limit.
  private static readonly MAX_BATCH_BYTES: number = 768 * 1024;
  private static readonly MAX_EXCHANGE_PAGES: number = 1000;
  private static readonly MAX_RATE_LIMIT_RETRIES: number = 3;
  private static protectedLocalBooksDuringSync: number = 0;
  private static protectedLocalBookEntityIdsDuringSync: Set<string> = new Set<string>();
  // 将旧版完整阅读设置回填为仅含字体规则和主题的同步数据。
  private static readerSettingsBackfillPending: boolean = false;

  static async syncNow(context: Context, conflictPolicy: string = 'cloud'): Promise<CloudSyncRunResult> {
    if (CloudSyncCoordinator.running) {
      return await CloudSyncCoordinator.running;
    }
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_RUNTIME_ACTIVE, true);
    const task = CloudSyncCoordinator.run(context, conflictPolicy === 'local' ? 'local' : 'cloud');
    CloudSyncCoordinator.running = task;
    CloudSyncCoordinator.lastSyncAttemptAt = Date.now();
    try {
      return await task;
    } finally {
      if (CloudSyncCoordinator.running === task) {
        CloudSyncCoordinator.running = null;
      }
      AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_RUNTIME_ACTIVE, false);
    }
  }

  static isRunning(): boolean {
    return CloudSyncCoordinator.running !== null;
  }

  static async needsInitialConflictChoice(context: Context): Promise<boolean> {
    await AccountSessionStore.load(context);
    if (!AccountSessionStore.isLoggedIn()) {
      return false;
    }
    const userId = AccountSessionStore.account().userId;
    const state = await CloudSyncStateStore.load(context, userId);
    if (state.cursor > 0 || Object.keys(state.entities).length > 0) {
      return false;
    }
    const summary = await AccountCommerceApi.fetchSyncSummary(AccountSessionStore.token());
    return Math.max(0, Math.floor(Number(summary.activeEntityCount) || 0)) > 0;
  }

  static async syncAutomatically(context: Context,
    trigger: string = CloudSyncCoordinator.TRIGGER_FOREGROUND): Promise<void> {
    const localChangeTrigger = trigger === CloudSyncCoordinator.TRIGGER_CHANGE;
    const backgroundTrigger = trigger === CloudSyncCoordinator.TRIGGER_BACKGROUND;
    let hasLocalChanges = CloudSyncChangeTracker.hasUnsyncedChanges();
    if (CloudSyncCoordinator.running) {
      if (hasLocalChanges) {
        CloudSyncCoordinator.scheduleDeferredAutomaticSync(context, 2000);
      }
      return;
    }
    await AccountSessionStore.load(context);
    if (!AccountSessionStore.isLoggedIn()) {
      return;
    }
    const userId = AccountSessionStore.account().userId;
    const settings = await CloudSyncSettingsStore.load(context, userId);
    if (!settings.enabled || !settings.autoSyncEnabled ||
      (trigger === CloudSyncCoordinator.TRIGGER_FOREGROUND && !settings.foregroundSyncEnabled)) {
      return;
    }
    if (settings.readingDataEnabled) {
      const db = AppDatabase.getInstance();
      await db.initWithContext(context);
      await readStatsTracker.flushAndWait();
      const pending = await db.getPendingReadStats(userId,
        await CloudSyncStateStore.deviceId(context), await db.getReadStatsUploadBoundary());
      hasLocalChanges = hasLocalChanges || pending.length > 0;
    }
    if ((localChangeTrigger || backgroundTrigger) && !hasLocalChanges) return;
    const now = Date.now();
    if (trigger === CloudSyncCoordinator.TRIGGER_FOREGROUND && !hasLocalChanges &&
      settings.lastSuccessAt > 0 &&
      now - settings.lastSuccessAt < CloudSyncCoordinator.FOREGROUND_REFRESH_INTERVAL_MS) {
      return;
    }
    if (settings.wifiOnly && !CloudSyncCoordinator.isWifiConnected()) {
      return;
    }
    const throttleRemaining = CloudSyncCoordinator.AUTOMATIC_MIN_INTERVAL_MS -
      (now - CloudSyncCoordinator.lastSyncAttemptAt);
    if (!backgroundTrigger && throttleRemaining > 0) {
      if (localChangeTrigger) {
        CloudSyncCoordinator.scheduleDeferredAutomaticSync(context, throttleRemaining + 100);
      }
      return;
    }
    try {
      await CloudSyncCoordinator.syncNow(context);
    } catch (error) {
      console.warn('自动同步失败:', error);
    }
  }

  private static scheduleDeferredAutomaticSync(context: Context, delayMs: number): void {
    if (CloudSyncCoordinator.deferredAutomaticTimer >= 0) {
      return;
    }
    CloudSyncCoordinator.deferredAutomaticTimer = setTimeout(() => {
      CloudSyncCoordinator.deferredAutomaticTimer = -1;
      CloudSyncCoordinator.syncAutomatically(
        context, CloudSyncCoordinator.TRIGGER_CHANGE).catch((error: Error) => {
        console.warn('延迟自动同步失败:', error);
      });
    }, Math.max(500, Math.floor(delayMs)));
  }

  private static async run(context: Context, conflictPolicy: string): Promise<CloudSyncRunResult> {
    await AccountSessionStore.load(context);
    if (!AccountSessionStore.isLoggedIn()) {
      throw new Error('请先登录华为账号');
    }
    const userId = AccountSessionStore.account().userId;
    const sessionToken = AccountSessionStore.token();
    const settings = await CloudSyncSettingsStore.load(context, userId);
    if (!settings.enabled) {
      throw new Error('请先开启云同步');
    }
    await readStatsTracker.flushAndWait();
    ReadStatsCloudSync.assertSession(userId, sessionToken);
    const changeSnapshot: CloudSyncChangeSnapshot = CloudSyncChangeTracker.snapshot();

    const result = new CloudSyncRunResult();
    const issues: CloudSyncIssue[] = [];
    CloudSyncCoordinator.protectedLocalBooksDuringSync = 0;
    CloudSyncCoordinator.protectedLocalBookEntityIdsDuringSync.clear();
    CloudSyncCoordinator.readerSettingsBackfillPending = false;
    settings.status = CloudSyncSettingsStore.STATUS_SYNCING;
    settings.errorMessage = '';
    await CloudSyncSettingsStore.saveRuntimeState(context, userId, settings.status,
      settings.lastSuccessAt, settings.pendingCount, settings.errorMessage);

    // Kept outside the try so a whole-request rejection can name the items it was about.
    let localEntities: LocalSyncEntity[] = [];
    let batch: CloudSyncOperation[] = [];
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(context);
      const deviceId = await CloudSyncStateStore.deviceId(context);
      const state = await CloudSyncStateStore.load(context, userId);
      localEntities = (await CloudSyncCoordinator.buildLocalEntities(context, db, settings))
        .filter((entity: LocalSyncEntity) =>
          CloudSyncCoordinator.scopeAllows(settings, entity.entityType));
      const operations = CloudSyncCoordinator.buildOperations(localEntities, state, settings);
      settings.pendingCount = operations.length;
      await CloudSyncSettingsStore.saveRuntimeState(context, userId, settings.status,
        settings.lastSuccessAt, settings.pendingCount, settings.errorMessage);

      let remaining = operations.slice();
      let hasMore = true;
      let exchangePages = 0;
      while (remaining.length > 0 || hasMore) {
        ReadStatsCloudSync.assertSession(userId, sessionToken);
        exchangePages++;
        if (exchangePages > CloudSyncCoordinator.MAX_EXCHANGE_PAGES) {
          throw new Error('同步分页次数异常，请稍后重试');
        }
        batch = CloudSyncCoordinator.takeOperationBatch(remaining);
        const cursorBeforeExchange = state.cursor;
        const request = await CloudSyncCoordinator.exchangeRequest(
          context, deviceId, state.cursor, batch, conflictPolicy);
        const response = await CloudSyncCoordinator.exchangeSyncWithRetry(request, userId, sessionToken);
        ReadStatsCloudSync.assertSession(userId, sessionToken);
        CloudSyncCoordinator.validateResponse(response);
        const operationMap = CloudSyncCoordinator.operationEntityMap(batch, localEntities);
        for (const ack of response.acknowledgements || []) {
          if (ack.error) {
            result.skipped++;
            result.warning = ack.error.message;
            issues.push(CloudSyncCoordinator.rejectionIssue(ack, operationMap[ack.opId]));
          }
        }
        CloudSyncChangeTracker.beginRemoteApply();
        try {
          result.conflicts += await CloudSyncCoordinator.applyAcknowledgements(
            context, db, response.acknowledgements || [], operationMap, state, deviceId);
          result.downloaded += await CloudSyncCoordinator.applyChanges(
            context, db, response.changes || [], state, deviceId, settings);
        } finally {
          CloudSyncChangeTracker.endRemoteApply();
        }
        if (CloudSyncCoordinator.readerSettingsBackfillPending) {
          CloudSyncCoordinator.readerSettingsBackfillPending = false;
          // The run snapshot was captured before this revision, so markSynced
          // below cannot consume it. A following automatic/foreground sync
          // will therefore backfill the versioned reader-settings payload.
          CloudSyncChangeTracker.markPreferenceChanged();
        }
        if (CloudSyncCoordinator.protectedLocalBooksDuringSync > 0) {
          CloudSyncCoordinator.protectedLocalBooksDuringSync = 0;
          // Keep the locally re-added shelf item pending after markSynced(changeSnapshot).
          CloudSyncChangeTracker.markDataChanged();
        }
        result.uploaded += (response.acknowledgements || []).filter(
          (ack: CloudSyncAcknowledgement) => ack.accepted).length;
        const nextCursor = Math.max(state.cursor, Math.floor(Number(response.nextCursor) || 0));
        if (response.hasMore === true && batch.length === 0 && nextCursor <= cursorBeforeExchange) {
          throw new Error('服务端同步游标未推进，请稍后重试');
        }
        state.cursor = nextCursor;
        await CloudSyncStateStore.save(context, userId, state);
        hasMore = response.hasMore === true;
        if (batch.length === 0 && !hasMore) {
          break;
        }
      }

      if (settings.readingDataEnabled) {
        const stats = await ReadStatsCloudSync.run(db, userId, deviceId, sessionToken);
        result.uploaded += stats.uploaded;
        result.downloaded += stats.downloaded;
      }
      ReadStatsCloudSync.assertSession(userId, sessionToken);
      settings.status = result.skipped > 0 ? CloudSyncSettingsStore.STATUS_ERROR : CloudSyncSettingsStore.STATUS_SYNCED;
      settings.lastSuccessAt = Date.now();
      settings.pendingCount = result.skipped;
      settings.errorMessage = result.skipped > 1 ? `${result.skipped} 项未能上传，详见同步问题` : result.warning;
      await CloudSyncSettingsStore.saveRuntimeState(context, userId, settings.status,
        settings.lastSuccessAt, settings.pendingCount, settings.errorMessage);
      await CloudSyncCoordinator.recordIssues(context, userId, issues);
      CloudSyncChangeTracker.markSynced(changeSnapshot);
      if (result.downloaded > 0) {
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      }
      return result;
    } catch (error) {
      settings.status = CloudSyncSettingsStore.STATUS_ERROR;
      settings.errorMessage = error instanceof Error ? error.message : String(error);
      await CloudSyncSettingsStore.saveRuntimeState(context, userId, settings.status,
        settings.lastSuccessAt, settings.pendingCount, settings.errorMessage);
      // Items rejected on earlier pages are still worth reporting alongside the failure itself.
      const message = settings.errorMessage || '同步失败';
      issues.push(CloudSyncIssueStore.create(CloudSyncIssueStore.KIND_SYNC, `sync:${message}`, '同步失败', message));
      if (error instanceof AccountApiError && error.errorCode === 'SYNC_PAYLOAD_TOO_LARGE') {
        issues.push(...CloudSyncCoordinator.oversizedIssues(message, batch, localEntities));
      } else if (error instanceof AccountApiError && error.errorCode === 'REQUEST_TOO_LARGE') {
        // The route's body limit fires before the per-item check, and its generic message
        // speaks of files. Batches stay well under that limit unless a single item is oversized.
        issues.push(...CloudSyncCoordinator.oversizedIssues('超过了同步请求的大小上限', batch, localEntities));
      }
      await CloudSyncCoordinator.recordIssues(context, userId, issues);
      throw new Error(message);
    } finally {
      // A protected tombstone can arrive on a later exchange page. Retain the entity identities
      // until every page in this run has been applied, then avoid leaking them into the next run.
      CloudSyncCoordinator.protectedLocalBookEntityIdsDuringSync.clear();
    }
  }

  private static takeOperationBatch(remaining: CloudSyncOperation[]): CloudSyncOperation[] {
    const result: CloudSyncOperation[] = [];
    let estimatedBytes = 2048;
    const encoder = new util.TextEncoder();
    while (remaining.length > 0 && result.length < CloudSyncCoordinator.MAX_BATCH_OPERATIONS) {
      const operation = remaining[0];
      if (!operation) break;
      const operationBytes = encoder.encodeInto(JSON.stringify(operation)).byteLength + 1;
      if (result.length > 0 &&
        estimatedBytes + operationBytes > CloudSyncCoordinator.MAX_BATCH_BYTES) {
        break;
      }
      remaining.shift();
      result.push(operation);
      estimatedBytes += operationBytes;
    }
    return result;
  }

  /**
   * A sync exchange is idempotent (the server stores operation receipts), so a
   * 429 can be resumed safely after the server's minute window rolls over.
   * Previously the first large initial download stopped permanently at the
   * rate-limit boundary and surfaced as a sync failure.
   */
  private static async exchangeSyncWithRetry(
    request: CloudSyncExchangeRequest, userId: string, sessionToken: string
  ): Promise<CloudSyncExchangeResponse> {
    let retries = 0;
    while (true) {
      ReadStatsCloudSync.assertSession(userId, sessionToken);
      try {
        return await AccountCommerceApi.exchangeSync(request, sessionToken);
      } catch (error) {
        if (!(error instanceof AccountApiError) || error.statusCode !== 429 ||
          error.errorCode !== 'RATE_LIMITED' ||
          retries >= CloudSyncCoordinator.MAX_RATE_LIMIT_RETRIES) {
          throw error instanceof Error ? error : new Error(String(error));
        }
        retries++;
        const serverDelay = Math.max(1, Math.floor(Number(error.retryAfterSeconds) || 60));
        // Add a small cushion so the next request is not sent just before the
        // database minute bucket changes on a busy server.
        const delayMs = Math.min(120, serverDelay) * 1000 + 250;
        console.warn(`同步请求被限流，将在 ${Math.ceil(delayMs / 1000)} 秒后继续`);
        await new Promise<void>((resolve) => {
          setTimeout(() => resolve(), delayMs);
        });
      }
    }
  }

  private static async buildLocalEntities(context: Context, db: AppDatabase,
    settings: CloudSyncSettings): Promise<LocalSyncEntity[]> {
    const result: LocalSyncEntity[] = [];
    const groups = await db.getCustomBookGroups();
    const groupNames: Record<string, string> = {};
    for (const group of groups) {
      groupNames[String(group.groupId)] = group.groupName;
      const payload = new BookGroupSyncPayload();
      payload.name = group.groupName;
      payload.order = group.order;
      payload.show = group.show;
      payload.enableRefresh = group.enableRefresh;
      result.push(CloudSyncCoordinator.entity(
        'book_group',
        CloudSyncCoordinator.identity('group', group.groupName),
        payload,
        group.groupName,
        group.groupName
      ));
    }

    const allBooks = await db.getAllBooks();
    const onlineBooks = allBooks.filter((book: Book) =>
      !!book.origin && book.origin !== 'local' && !book.pendingAddToShelf);
    const onlineBookUrls = new Set<string>();
    for (const book of onlineBooks) {
      onlineBookUrls.add(book.bookUrl);
      const bookId = CloudSyncCoordinator.identity('book', BookIdentity.cloudIdentityValue(book));
      const shelf = new BookshelfSyncPayload();
      shelf.bookUrl = book.bookUrl;
      shelf.tocUrl = book.tocUrl;
      shelf.origin = book.origin;
      shelf.originName = book.originName;
      shelf.name = book.name;
      shelf.author = book.author;
      shelf.kind = book.kind;
      shelf.status = book.status;
      shelf.customTag = book.customTag;
      shelf.coverUrl = book.coverUrl;
      shelf.customCoverUrl = book.customCoverUrl;
      shelf.intro = book.intro;
      shelf.customIntro = book.customIntro;
      shelf.charset = book.charset;
      shelf.type = book.type;
      shelf.groupName = groupNames[String(book.group)] || '';
      shelf.isPinned = book.isPinned;
      shelf.latestChapterTitle = book.latestChapterTitle;
      shelf.updateTime = book.updateTime;
      shelf.latestChapterTime = book.latestChapterTime;
      shelf.totalChapterNum = book.totalChapterNum;
      shelf.wordCount = book.wordCount;
      shelf.canUpdate = book.canUpdate;
      shelf.order = book.order;
      shelf.originOrder = book.originOrder;
      shelf.readConfig = book.readConfig;
      shelf.shelfModifiedTime = book.shelfModifiedTime;
      result.push(CloudSyncCoordinator.entity('bookshelf_item', bookId, shelf, book.bookUrl, book.name));

      const progress = new ReadingProgressSyncPayload();
      progress.bookUrl = book.bookUrl;
      progress.origin = book.origin;
      progress.chapterTitle = book.durChapterTitle;
      progress.chapterIndex = book.durChapterIndex;
      progress.chapterPos = book.durChapterPos;
      progress.updatedAt = book.durChapterTime;
      result.push(CloudSyncCoordinator.entity('reading_progress', bookId, progress, book.bookUrl, book.name));
    }

    // Local files are deliberately never uploaded. Publish only a compact
    // progress snapshot keyed by a content fingerprint so another device that
    // has imported the same edition can apply it.
    // Cloud placeholders (super-member book sync, not downloaded yet) carry no reading position of their own.
    const localBooks = allBooks.filter((book: Book) =>
      book.origin === 'local' && !book.pendingAddToShelf && book.getVariable('cloudPlaceholder') !== '1');
    for (const book of localBooks) {
      const hadContentHash = book.getVariable(LocalBookService.LOCAL_CONTENT_HASH_KEY).trim().length > 0;
      const contentHash = await LocalBookService.ensureContentHash(book);
      if (!contentHash) continue;
      // Persist fingerprints for books imported by older app versions.
      if (!hadContentHash) {
        await db.updateBook(book, false, 'backfill_local_content_hash');
      }
      const localBookId = CloudSyncCoordinator.identity(
        'book', BookIdentity.cloudIdentityValue(book));
      const progress = new ReadingProgressSyncPayload();
      progress.origin = book.origin;
      progress.localContentHash = contentHash;
      progress.chapterTitle = book.durChapterTitle;
      progress.chapterIndex = book.durChapterIndex;
      progress.chapterPos = book.durChapterPos;
      progress.updatedAt = book.durChapterTime;
      result.push(CloudSyncCoordinator.entity(
        'reading_progress', localBookId, progress, `local:${contentHash}`, book.name));
    }

    const bookmarks = await db.getAllBookmarks();
    for (const bookmark of bookmarks) {
      if (!onlineBookUrls.has(bookmark.bookUrl)) {
        continue;
      }
      const payload = new BookmarkSyncPayload();
      payload.bookUrl = bookmark.bookUrl;
      payload.bookName = bookmark.bookName;
      payload.bookAuthor = bookmark.bookAuthor;
      payload.chapterIndex = bookmark.chapterIndex;
      payload.chapterName = bookmark.chapterName;
      payload.pageIndex = bookmark.pageIndex;
      payload.startPos = bookmark.startPos;
      payload.endPos = bookmark.endPos;
      payload.content = bookmark.content;
      payload.createTime = bookmark.createTime;
      const bookmarkKey = CloudSyncCoordinator.bookmarkKey(bookmark);
      result.push(CloudSyncCoordinator.entity(
        'bookmark',
        CloudSyncCoordinator.identity('bookmark', bookmarkKey),
        payload,
        bookmarkKey,
        `${bookmark.bookName} · ${bookmark.chapterName}`
      ));
    }

    if (settings.bookSourcesEnabled) {
      const bookSources = await db.getBookSourcesForCloudSync();
      for (const source of bookSources) {
        const payload = CloudSyncCoordinator.bookSourcePayload(source);
        result.push(CloudSyncCoordinator.entity(
          'book_source',
          CloudSyncCoordinator.identity('source', source.bookSourceUrl),
          payload,
          source.bookSourceUrl,
          source.bookSourceName
        ));
      }
    }

    const readerSettings = await ReaderSettingsStore.load(context);
    const safeReaderSettings = ReaderPreferencesSync.toPayload(readerSettings);
    result.push(CloudSyncCoordinator.entity(
      'reader_settings', 'global', safeReaderSettings, 'global'));

    const replaceRules = await ReaderReplaceRuleStore.load(context);
    for (const rule of replaceRules) {
      result.push(CloudSyncCoordinator.entity(
        'replace_rule', `rule_${Math.max(0, Math.floor(rule.id))}`, rule, String(rule.id), rule.name));
    }

    const themeSettings = await AppThemeSettingsStore.load(context);
    const safeThemeSettings = JSON.parse(JSON.stringify(themeSettings)) as AppThemeSettings;
    safeThemeSettings.themeApplyLayoutEnabled = false;
    safeThemeSettings.customLightReaderBackgroundAssetId = '';
    safeThemeSettings.customDarkReaderBackgroundAssetId = '';
    safeThemeSettings.customLightStartupImagePath = '';
    safeThemeSettings.customDarkStartupImagePath = '';
    result.push(CloudSyncCoordinator.entity(
      'theme_settings', 'global', safeThemeSettings, 'global'));

    const appearance = new AppearanceModeSyncPayload();
    appearance.mode = await AppThemeModeStore.load(context);
    result.push(CloudSyncCoordinator.entity(
      'appearance_mode', 'global', appearance, 'global'));

    const bookshelfDisplay = await BookshelfDisplaySettingsStore.load(context);
    result.push(CloudSyncCoordinator.entity(
      'bookshelf_display', 'global', bookshelfDisplay, 'global'));

    const searchSettings = await SearchExploreSettingsStore.load(context);
    const searchPreferences = new SearchPreferencesSyncPayload();
    searchPreferences.showResultCover = searchSettings.showResultCover;
    searchPreferences.showResultCoverBackground = searchSettings.showResultCoverBackground;
    searchPreferences.useBookshelfCoverGallery = searchSettings.useBookshelfCoverGallery;
    searchPreferences.showResultTags = searchSettings.showResultTags;
    searchPreferences.aggregateSearchResults = searchSettings.aggregateSearchResults;
    searchPreferences.promptAddToShelfOnBack = searchSettings.promptAddToShelfOnBack;
    searchPreferences.exactSearch = searchSettings.exactSearch;
    searchPreferences.exactSearchMatchAuthor = searchSettings.exactSearchMatchAuthor;
    searchPreferences.showSearchProgress = searchSettings.showSearchProgress;
    result.push(CloudSyncCoordinator.entity(
      'search_preferences', 'global', searchPreferences, 'global'));

    const themeSchemes = await CustomThemeSchemeStore.load(context, themeSettings);
    const schemesPayload = new CustomThemeSchemesSyncPayload();
    schemesPayload.schemes = themeSchemes.map((scheme: CustomThemeScheme) => {
      const safeScheme = JSON.parse(JSON.stringify(scheme)) as CustomThemeScheme;
      safeScheme.settings.themeApplyLayoutEnabled = false;
      safeScheme.settings.customLightReaderBackgroundAssetId = '';
      safeScheme.settings.customDarkReaderBackgroundAssetId = '';
      safeScheme.settings.customLightStartupImagePath = '';
      safeScheme.settings.customDarkStartupImagePath = '';
      return safeScheme;
    });
    result.push(CloudSyncCoordinator.entity(
      'custom_theme_schemes', 'global', schemesPayload, 'global'));
    return result;
  }

  private static buildOperations(
    entities: LocalSyncEntity[],
    state: CloudSyncLocalState,
    settings: CloudSyncSettings
  ): CloudSyncOperation[] {
    const result: CloudSyncOperation[] = [];
    const currentKeys = new Set<string>();
    for (const entity of entities) {
      const key = CloudSyncStateStore.entityKey(entity.entityType, entity.entityId);
      currentKeys.add(key);
      const previous = state.entities[key] || new CloudSyncEntityState();
      if (!previous.deleted && previous.contentHash === entity.contentHash) {
        continue;
      }
      const operation = new CloudSyncOperation();
      operation.opId = util.generateRandomUUID();
      operation.entityType = entity.entityType;
      operation.entityId = entity.entityId;
      operation.operation = 'upsert';
      operation.baseRevision = previous.revision;
      operation.payload = JSON.parse(entity.payloadJson) as Object;
      result.push(operation);
    }
    for (const key of Object.keys(state.entities)) {
      const previous = state.entities[key];
      if (!previous || previous.deleted || currentKeys.has(key)) {
        continue;
      }
      const separator = key.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      const entityType = key.substring(0, separator);
      if (!CloudSyncCoordinator.scopeAllows(settings, entityType)) {
        continue;
      }
      // A local progress entity is retained when this device has not imported
      // the corresponding file yet. Otherwise a normalisation pass would
      // delete another device's progress before the file becomes available.
      if (entityType === 'reading_progress' && previous.localKey.startsWith('local:')) {
        continue;
      }
      const operation = new CloudSyncOperation();
      operation.opId = util.generateRandomUUID();
      operation.entityType = entityType;
      operation.entityId = key.substring(separator + 1);
      operation.operation = 'delete';
      operation.baseRevision = previous.revision;
      result.push(operation);
    }
    return result;
  }

  private static async exchangeRequest(
    context: Context,
    deviceId: string,
    cursor: number,
    operations: CloudSyncOperation[],
    conflictPolicy: string
  ): Promise<CloudSyncExchangeRequest> {
    const request = new CloudSyncExchangeRequest();
    request.deviceId = deviceId;
    request.deviceName = CloudSyncCoordinator.deviceName();
    request.platform = 'HarmonyOS';
    request.appVersion = CloudSyncCoordinator.appVersion();
    request.deviceKind = CloudSyncCoordinator.deviceKind();
    request.conflictPolicy = conflictPolicy === 'local' ? 'local' : 'cloud';
    request.cursor = cursor;
    request.operations = operations;
    return request;
  }

  private static appVersion(): string {
    try {
      return bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName || '';
    } catch (e) {
      return '';
    }
  }

  private static deviceName(): string {
    try {
      return deviceInfo.marketName || deviceInfo.productModelAlias ||
        deviceInfo.productModel || deviceInfo.productSeries || deviceInfo.brand || 'HarmonyOS 设备';
    } catch (e) {
      return 'HarmonyOS 设备';
    }
  }

  private static deviceKind(): string {
    try {
      if (display.isFoldable()) {
        return 'foldable';
      }
    } catch (e) {
    }
    try {
      const type = (deviceInfo.deviceType || '').toLowerCase();
      if (type.includes('2in1') || type.includes('2-in-1') || type.includes('pc')) {
        return '2in1';
      }
      if (type.includes('tablet')) {
        return 'tablet';
      }
      if (type.includes('phone')) {
        return 'phone';
      }
    } catch (e) {
    }
    return 'unknown';
  }

  private static isWifiConnected(): boolean {
    try {
      const handle = connection.getDefaultNetSync();
      const capabilities = connection.getNetCapabilitiesSync(handle);
      return (capabilities.bearerTypes || []).includes(connection.NetBearType.BEARER_WIFI);
    } catch (e) {
      return false;
    }
  }

  private static operationEntityMap(
    operations: CloudSyncOperation[],
    entities: LocalSyncEntity[]
  ): Record<string, LocalSyncEntity> {
    const result: Record<string, LocalSyncEntity> = {};
    for (const operation of operations) {
      const entity = entities.find((item: LocalSyncEntity) =>
        item.entityType === operation.entityType && item.entityId === operation.entityId);
      if (entity) {
        result[operation.opId] = entity;
      } else {
        const deleted = new LocalSyncEntity();
        deleted.entityType = operation.entityType;
        deleted.entityId = operation.entityId;
        result[operation.opId] = deleted;
      }
    }
    return result;
  }

  private static async applyAcknowledgements(
    context: Context,
    db: AppDatabase,
    acknowledgements: CloudSyncAcknowledgement[],
    operationMap: Record<string, LocalSyncEntity>,
    state: CloudSyncLocalState,
    deviceId: string
  ): Promise<number> {
    let conflicts = 0;
    for (const ack of acknowledgements) {
      if (ack.error) continue; // A quota rejection is not a remote conflict; preserve local data.
      const local = operationMap[ack.opId];
      if (!local) {
        continue;
      }
      const key = CloudSyncStateStore.entityKey(local.entityType, local.entityId);
      const entityState = state.entities[key] || new CloudSyncEntityState();
      entityState.revision = Math.max(0, Math.floor(Number(ack.revision) || 0));
      entityState.localKey = local.localKey || entityState.localKey;
      state.entities[key] = entityState;
      if (ack.accepted) {
        entityState.deleted = !local.payloadJson;
        entityState.contentHash = local.contentHash;
      } else {
        conflicts++;
        const conflict = ack.conflict;
        if (local.entityType === 'bookshelf_item' && !!local.payloadJson && conflict?.deleted === true) {
          // A local row in the same outgoing batch is an explicit re-add. Keep it and advance to the
          // tombstone revision; the next exchange will recreate it from that revision.
          entityState.deleted = true;
          entityState.contentHash = '';
          CloudSyncCoordinator.protectedLocalBooksDuringSync++;
          CloudSyncCoordinator.protectedLocalBookEntityIdsDuringSync.add(local.entityId);
          continue;
        }
        if (local.entityType === 'reading_progress' && conflict?.payload) {
          // If a device imported the local file after the remote progress was
          // created, use the conflict payload to catch it up on this sync.
          const appliedBook = await CloudSyncCoordinator.applyReadingProgressPayload(
            db, conflict.payload);
          entityState.contentHash = CloudSyncCoordinator.digest(JSON.stringify(conflict.payload));
          entityState.deleted = false;
          entityState.localKey = appliedBook?.bookUrl || local.localKey || entityState.localKey;
          continue;
        }
        await CloudSyncCoordinator.applyEntity(
          context,
          db,
          local.entityType,
          local.entityId,
          entityState.revision,
          conflict?.deleted === true ? 'delete' : 'upsert',
          conflict?.payload || null,
          state,
          deviceId,
          0
        );
      }
    }
    return conflicts;
  }

  private static async applyChanges(
    context: Context,
    db: AppDatabase,
    changes: CloudSyncChange[],
    state: CloudSyncLocalState,
    deviceId: string,
    settings: CloudSyncSettings
  ): Promise<number> {
    const ordered = changes.slice().sort((left: CloudSyncChange, right: CloudSyncChange) => {
      const priority = CloudSyncCoordinator.entityPriority(left.entityType) -
        CloudSyncCoordinator.entityPriority(right.entityType);
      return priority !== 0 ? priority : left.sequenceId - right.sequenceId;
    });
    let applied = 0;
    for (const change of ordered) {
      if (!CloudSyncCoordinator.scopeAllows(settings, change.entityType)) {
        continue;
      }
      const key = CloudSyncStateStore.entityKey(change.entityType, change.entityId);
      const entityState = state.entities[key] || new CloudSyncEntityState();
      if (change.revision < entityState.revision) {
        continue;
      }
      if (change.deviceId === deviceId && change.revision === entityState.revision) {
        continue;
      }
      await CloudSyncCoordinator.applyEntity(
        context,
        db,
        change.entityType,
        change.entityId,
        change.revision,
        change.operation,
        change.payload,
        state,
        deviceId,
        change.createdAt
      );
      applied++;
    }
    return applied;
  }

  private static async applyEntity(
    context: Context,
    db: AppDatabase,
    entityType: string,
    entityId: string,
    revision: number,
    operation: string,
    payload: Object | null,
    state: CloudSyncLocalState,
    _deviceId: string,
    changeCreatedAt: number = 0
  ): Promise<void> {
    const key = CloudSyncStateStore.entityKey(entityType, entityId);
    const entityState = state.entities[key] || new CloudSyncEntityState();
    if (operation === 'delete') {
      await CloudSyncCoordinator.applyDelete(
        context, db, entityType, entityId, entityState, changeCreatedAt);
      entityState.revision = revision;
      entityState.deleted = true;
      entityState.contentHash = '';
      state.entities[key] = entityState;
      return;
    }
    if (!payload) {
      return;
    }
    const raw = JSON.stringify(payload);
    if (entityType === 'book_group') {
      const group = JSON.parse(raw) as BookGroupSyncPayload;
      await CloudSyncCoordinator.restoreGroup(db, group);
      entityState.localKey = group.name;
    } else if (entityType === 'bookshelf_item') {
      const shelf = JSON.parse(raw) as BookshelfSyncPayload;
      await CloudSyncCoordinator.restoreBook(db, shelf);
      entityState.localKey = shelf.bookUrl;
    } else if (entityType === 'reading_progress') {
      const progress = JSON.parse(raw) as ReadingProgressSyncPayload;
      const book = await CloudSyncCoordinator.applyReadingProgressPayload(db, progress);
      entityState.localKey = book?.bookUrl ||
        (progress.localContentHash ? `local:${progress.localContentHash}` : progress.bookUrl);
    } else if (entityType === 'bookmark') {
      const bookmarkPayload = JSON.parse(raw) as BookmarkSyncPayload;
      const bookmark = CloudSyncCoordinator.bookmarkFromPayload(bookmarkPayload);
      await db.restoreBookmark(bookmark);
      entityState.localKey = CloudSyncCoordinator.bookmarkKey(bookmark);
    } else if (entityType === 'book_source') {
      const sourcePayload = JSON.parse(raw) as BookSourceSyncPayload;
      const source = await CloudSyncCoordinator.bookSourceFromPayload(db, sourcePayload);
      if (!source) {
        return;
      }
      await db.restoreBookSource(source);
      entityState.localKey = source.bookSourceUrl;
      CloudSyncCoordinator.notifyBookSourcesChanged();
    } else if (entityType === 'reader_settings') {
      const remote = JSON.parse(raw) as ReaderPreferencesSyncPayload;
      const local = await ReaderSettingsStore.load(context);
      const merged = ReaderPreferencesSync.merge(local, remote);
      await ReaderSettingsStore.saveReaderFontRuleSettings(context, merged);
      await ReaderSettingsStore.saveThemeSettings(context, merged.lightThemeIndex, merged.darkThemeIndex,
        merged.lightCustomThemeBackgroundColor, merged.lightCustomThemeTextColor,
        merged.darkCustomThemeBackgroundColor, merged.darkCustomThemeTextColor,
        AppStorage.get<boolean>('appDarkMode') || false, merged.customThemesRaw);
      if (remote.syncVersion !== 2) {
        // 下一轮将旧版完整设置替换为精简数据；旧排版字段不会写回本机。
        CloudSyncCoordinator.readerSettingsBackfillPending = true;
      }
      entityState.localKey = 'global';
    } else if (entityType === 'replace_rule') {
      const remoteRule = JSON.parse(raw) as ReaderReplaceRule;
      const rules = await ReaderReplaceRuleStore.load(context, true);
      const next = rules.filter((rule: ReaderReplaceRule) => rule.id !== remoteRule.id);
      next.push(remoteRule);
      await ReaderReplaceRuleStore.save(context, next);
      entityState.localKey = String(remoteRule.id);
    } else if (entityType === 'theme_settings') {
      const themeSettings = JSON.parse(raw) as AppThemeSettings;
      const localThemeSettings = await AppThemeSettingsStore.load(context);
      themeSettings.themeApplyLayoutEnabled = localThemeSettings.themeApplyLayoutEnabled;
      themeSettings.customLightStartupImagePath = localThemeSettings.customLightStartupImagePath;
      themeSettings.customDarkStartupImagePath = localThemeSettings.customDarkStartupImagePath;
      await AppThemeSettingsStore.save(context, themeSettings);
      AppThemeSettingsStore.applyToStorage(themeSettings);
      entityState.localKey = 'global';
    } else if (entityType === 'appearance_mode') {
      const appearance = JSON.parse(raw) as AppearanceModeSyncPayload;
      await AppThemeModeStore.save(context, appearance.mode);
      entityState.localKey = 'global';
    } else if (entityType === 'bookshelf_display') {
      const displaySettings = JSON.parse(raw) as BookshelfDisplaySettings;
      await BookshelfDisplaySettingsStore.save(context, displaySettings);
      BookshelfDisplaySettingsStore.applyToStorage(displaySettings);
      entityState.localKey = 'global';
    } else if (entityType === 'search_preferences') {
      const remoteSearch = JSON.parse(raw) as SearchPreferencesSyncPayload;
      const searchSettings = await SearchExploreSettingsStore.load(context);
      searchSettings.showResultCover = remoteSearch.showResultCover !== false;
      searchSettings.showResultCoverBackground = remoteSearch.showResultCoverBackground !== false;
      searchSettings.useBookshelfCoverGallery = remoteSearch.useBookshelfCoverGallery === true;
      searchSettings.showResultTags = remoteSearch.showResultTags !== false;
      searchSettings.aggregateSearchResults = remoteSearch.aggregateSearchResults !== false;
      searchSettings.promptAddToShelfOnBack = remoteSearch.promptAddToShelfOnBack !== false;
      searchSettings.exactSearch = remoteSearch.exactSearch === true;
      searchSettings.exactSearchMatchAuthor = remoteSearch.exactSearchMatchAuthor !== false;
      searchSettings.showSearchProgress = remoteSearch.showSearchProgress !== false;
      await SearchExploreSettingsStore.save(context, searchSettings);
      SearchExploreSettingsStore.applyToStorage(searchSettings);
      entityState.localKey = 'global';
    } else if (entityType === 'custom_theme_schemes') {
      const schemesPayload = JSON.parse(raw) as CustomThemeSchemesSyncPayload;
      const legacySettings = await AppThemeSettingsStore.load(context);
      await CustomThemeSchemeStore.replaceFromSync(
        context, legacySettings, schemesPayload.schemes || []);
      entityState.localKey = 'global';
    }
    entityState.revision = revision;
    entityState.deleted = false;
    entityState.contentHash = CloudSyncCoordinator.digest(raw);
    state.entities[key] = entityState;
  }

  private static async applyReadingProgressPayload(
    db: AppDatabase, payload: Object
  ): Promise<Book | null> {
    const progress = JSON.parse(JSON.stringify(payload)) as ReadingProgressSyncPayload;
    const contentHash = (progress.localContentHash || '').trim();
    const book = contentHash ?
      await db.getBookByLocalContentHash(contentHash) :
      await db.getBook(progress.bookUrl);
    // A freshly imported book receives a construction timestamp even though
    // it has never been read. Do not treat that timestamp as a newer reading
    // checkpoint than a remote progress snapshot.
    if (!book || (book.hasStartedReading() && progress.updatedAt < book.durChapterTime)) {
      return book;
    }
    await db.updateBookReadingProgress(
      book.bookUrl,
      progress.chapterTitle,
      progress.chapterIndex,
      progress.chapterPos,
      progress.updatedAt,
      book.variable,
      false
    );
    return book;
  }

  private static async applyDelete(
    context: Context,
    db: AppDatabase,
    entityType: string,
    entityId: string,
    entityState: CloudSyncEntityState,
    changeCreatedAt: number = 0
  ): Promise<void> {
    if (entityType === 'bookshelf_item' && entityState.localKey) {
      // The acknowledgement pass runs before downloaded changes. When a locally re-added shelf item conflicts
      // with an older cloud tombstone, it deliberately keeps the row and advances state to the tombstone revision.
      // The same exchange response may also contain that tombstone in `changes`; do not delete the row again here.
      // Keeping entityState.deleted=true makes the next sync upload the explicit local re-add from that revision.
      if (CloudSyncCoordinator.protectedLocalBookEntityIdsDuringSync.has(entityId)) {
        console.warn(`已忽略同轮同步中的过期书架删除记录: ${entityState.localKey}`);
        return;
      }
      const localBook = await db.getBook(entityState.localKey);
      if (localBook) {
        const currentEntityId = CloudSyncCoordinator.identity(
          'book', BookIdentity.cloudIdentityValue(localBook));
        const remoteTime = changeCreatedAt > 0 && changeCreatedAt < 1000000000000 ?
          changeCreatedAt * 1000 : changeCreatedAt;
        if (currentEntityId !== entityId ||
          (remoteTime > 0 && localBook.shelfModifiedTime > remoteTime)) {
          CloudSyncCoordinator.protectedLocalBooksDuringSync++;
          console.warn(`已忽略过期书架删除记录: ${localBook.bookUrl}`);
          return;
        }
      }
      await db.deleteBook(entityState.localKey, 'cloud_remote_delete');
    } else if (entityType === 'book_group' && entityState.localKey) {
      const groups = await db.getCustomBookGroups();
      const group = groups.find((item: BookGroup) => item.groupName === entityState.localKey);
      if (group) {
        await db.deleteBookGroup(group.groupId);
      }
    } else if (entityType === 'bookmark') {
      const bookmarks = await db.getAllBookmarks();
      for (const bookmark of bookmarks) {
        if (CloudSyncCoordinator.identity('bookmark',
          CloudSyncCoordinator.bookmarkKey(bookmark)) === entityId) {
          await db.deleteBookmark(bookmark.id);
          break;
        }
      }
    } else if (entityType === 'replace_rule') {
      const ruleId = Number(entityState.localKey || entityId.replace(/^rule_/, ''));
      const rules = await ReaderReplaceRuleStore.load(context, true);
      await ReaderReplaceRuleStore.save(
        context,
        rules.filter((rule: ReaderReplaceRule) => rule.id !== ruleId)
      );
    } else if (entityType === 'book_source') {
      let bookSourceUrl = entityState.localKey;
      if (!bookSourceUrl) {
        const sources = await db.getAllBookSources();
        const matched = sources.find((source: BookSource) =>
          CloudSyncCoordinator.identity('source', source.bookSourceUrl) === entityId);
        bookSourceUrl = matched?.bookSourceUrl || '';
      }
      if (bookSourceUrl) {
        await db.deleteBookSourceForSync(bookSourceUrl);
        CloudSyncCoordinator.notifyBookSourcesChanged();
      }
    }
  }

  private static async restoreGroup(db: AppDatabase, payload: BookGroupSyncPayload): Promise<BookGroup | null> {
    if (!payload.name?.trim()) {
      return null;
    }
    const groups = await db.getCustomBookGroups();
    let group = groups.find((item: BookGroup) => item.groupName === payload.name) || null;
    if (!group) {
      group = await db.addBookGroup(payload.name);
    }
    if (!group) {
      return null;
    }
    group.order = Math.max(0, Math.floor(Number(payload.order) || 0));
    group.show = payload.show !== false;
    group.enableRefresh = payload.enableRefresh !== false;
    await db.restoreBookGroup(group);
    return group;
  }

  private static async restoreBook(db: AppDatabase, payload: BookshelfSyncPayload): Promise<void> {
    if (!payload.bookUrl || !payload.origin || payload.origin === 'local') {
      return;
    }
    const identityProbe = new Book();
    identityProbe.bookUrl = payload.bookUrl;
    identityProbe.origin = payload.origin;
    const existing = await db.getBook(payload.bookUrl) ||
      await db.getBookByIdentityKey(BookIdentity.keyOfBook(identityProbe));
    const book = existing || new Book();
    // Keep the current local URL when only a rotating aggregation host changed.
    book.bookUrl = existing?.bookUrl || payload.bookUrl;
    book.tocUrl = payload.tocUrl || '';
    book.origin = payload.origin;
    book.originName = payload.originName || '';
    book.name = payload.name || '';
    book.author = payload.author || '';
    book.kind = payload.kind || '';
    book.status = payload.status || '';
    book.customTag = payload.customTag || '';
    book.coverUrl = payload.coverUrl || '';
    book.customCoverUrl = payload.customCoverUrl || '';
    book.intro = payload.intro || '';
    book.customIntro = payload.customIntro || '';
    book.charset = payload.charset || '';
    book.type = Math.floor(Number(payload.type) || 0);
    book.isPinned = payload.isPinned === true;
    book.latestChapterTitle = payload.latestChapterTitle || '';
    book.updateTime = payload.updateTime || '';
    book.latestChapterTime = Math.max(0, Math.floor(Number(payload.latestChapterTime) || 0));
    book.totalChapterNum = Math.max(0, Math.floor(Number(payload.totalChapterNum) || 0));
    book.wordCount = payload.wordCount || '';
    book.canUpdate = payload.canUpdate !== false;
    book.order = Math.floor(Number(payload.order) || 0);
    book.originOrder = Math.floor(Number(payload.originOrder) || 0);
    book.readConfig = payload.readConfig || null;
    book.pendingAddToShelf = false;
    book.shelfModifiedTime = Math.max(
      existing?.shelfModifiedTime || 0,
      Math.max(0, Math.floor(Number(payload.shelfModifiedTime) || 0)));
    if (payload.groupName) {
      const group = await CloudSyncCoordinator.restoreGroup(db, {
        name: payload.groupName,
        order: 0,
        show: true,
        enableRefresh: true
      });
      book.group = group?.groupId || 0;
    } else {
      book.group = 0;
    }
    await db.restoreBook(book);
  }

  private static bookmarkFromPayload(payload: BookmarkSyncPayload): Bookmark {
    const bookmark = new Bookmark();
    bookmark.bookUrl = payload.bookUrl || '';
    bookmark.bookName = payload.bookName || '';
    bookmark.bookAuthor = payload.bookAuthor || '';
    bookmark.chapterIndex = Math.floor(Number(payload.chapterIndex) || 0);
    bookmark.chapterName = payload.chapterName || '';
    bookmark.pageIndex = Math.floor(Number(payload.pageIndex) || 0);
    bookmark.startPos = Math.floor(Number(payload.startPos) || 0);
    bookmark.endPos = Math.floor(Number(payload.endPos) || 0);
    bookmark.content = payload.content || '';
    bookmark.createTime = Math.max(0, Math.floor(Number(payload.createTime) || 0));
    return bookmark;
  }

  private static bookmarkKey(bookmark: Bookmark): string {
    return `${bookmark.bookUrl}\n${bookmark.chapterIndex}\n${bookmark.pageIndex}\n` +
      `${bookmark.startPos}\n${bookmark.createTime}`;
  }

  private static bookSourcePayload(source: BookSource): BookSourceSyncPayload {
    const payload = new BookSourceSyncPayload();
    payload.bookSourceUrl = source.bookSourceUrl || '';
    payload.bookSourceName = source.bookSourceName || '';
    payload.bookSourceType = Math.floor(Number(source.bookSourceType) || 0);
    payload.bookSourceGroup = source.bookSourceGroup || '';
    payload.bookSourceComment = source.bookSourceComment || '';
    payload.loginUrl = source.loginUrl || '';
    payload.loginUi = source.loginUi || '';
    payload.loginCheckJs = source.loginCheckJs || '';
    payload.loginHeader = CloudSyncCoordinator.sanitizeBookSourceHeader(source.loginHeader);
    payload.bookUrlPattern = source.bookUrlPattern || '';
    payload.searchUrl = source.searchUrl || '';
    payload.exploreUrl = source.exploreUrl || '';
    payload.jsLib = source.jsLib || '';
    payload.header = CloudSyncCoordinator.sanitizeBookSourceHeader(source.header);
    // entity() 会立即序列化 payload；这里再做一次 JSON 深拷贝只会在大量书源同步时
    // 额外制造整批规则的临时副本。
    payload.bookListRule = source.bookListRule || new BookListRule();
    payload.searchRule = source.searchRule || new SearchRule();
    payload.exploreRule = source.exploreRule || new ExploreRule();
    payload.bookInfoRule = source.bookInfoRule || new BookInfoRule();
    payload.tocRule = source.tocRule || new TocRule();
    payload.contentRule = source.contentRule || new ContentRule();
    payload.variableComment = source.variableComment || '';
    payload.respondTime = Math.max(0, Math.floor(Number(source.respondTime) || 180000));
    payload.customOrder = Math.max(0, Math.floor(Number(source.customOrder) || 0));
    payload.customButton = source.customButton === true;
    payload.eventListener = source.eventListener === true;
    payload.isPinned = source.isPinned === true;
    payload.enabled = source.enabled !== false;
    payload.enabledExplore = source.enabledExplore !== false;
    payload.isLocked = source.isLocked === true;
    payload.weight = Math.floor(Number(source.weight) || 0);
    payload.concurrentRate = source.concurrentRate || '';
    payload.enabledCookieJar = source.enabledCookieJar !== false;
    return payload;
  }

  private static async bookSourceFromPayload(db: AppDatabase,
    payload: BookSourceSyncPayload): Promise<BookSource | null> {
    const bookSourceUrl = (payload.bookSourceUrl || '').trim();
    if (!bookSourceUrl) {
      return null;
    }
    const existing = await db.getBookSource(bookSourceUrl);
    const source = new BookSource();
    source.bookSourceUrl = bookSourceUrl;
    source.bookSourceName = payload.bookSourceName || '';
    source.bookSourceType = Math.floor(Number(payload.bookSourceType) || 0);
    source.bookSourceGroup = payload.bookSourceGroup || '';
    source.bookSourceComment = payload.bookSourceComment || '';
    source.loginUrl = payload.loginUrl || '';
    source.loginUi = payload.loginUi || '';
    source.loginCheckJs = payload.loginCheckJs || '';
    source.loginHeader = CloudSyncCoordinator.mergeLocalSensitiveHeaders(
      payload.loginHeader || '', existing?.loginHeader || '');
    source.rawSourceJson = existing?.rawSourceJson || '';
    source.bookUrlPattern = payload.bookUrlPattern || '';
    source.searchUrl = payload.searchUrl || '';
    source.exploreUrl = payload.exploreUrl || '';
    source.jsLib = payload.jsLib || '';
    source.header = CloudSyncCoordinator.mergeLocalSensitiveHeaders(
      payload.header || '', existing?.header || '');
    source.bookListRule = payload.bookListRule || new BookListRule();
    source.searchRule = payload.searchRule || new SearchRule();
    source.exploreRule = payload.exploreRule || new ExploreRule();
    source.bookInfoRule = payload.bookInfoRule || new BookInfoRule();
    source.tocRule = payload.tocRule || new TocRule();
    source.contentRule = payload.contentRule || new ContentRule();
    source.variableComment = payload.variableComment || '';
    source.variable = existing?.variable || '';
    // This is local bookkeeping, not a remote content version. Refreshing it on every restore
    // makes the reader's cache identity change even when login/variable state is unchanged.
    source.lastUpdateTime = existing?.lastUpdateTime || 0;
    source.respondTime = Math.max(0, Math.floor(Number(payload.respondTime) || 180000));
    source.customOrder = Math.max(0, Math.floor(Number(payload.customOrder) || 0));
    source.customButton = payload.customButton === true;
    source.eventListener = payload.eventListener === true;
    source.isPinned = payload.isPinned === true;
    source.enabled = payload.enabled !== false;
    source.enabledExplore = payload.enabledExplore !== false;
    source.isLocked = payload.isLocked === true;
    source.validationStatus = existing?.validationStatus || BookSource.VALIDATION_UNCHECKED;
    source.weight = Math.floor(Number(payload.weight) || 0);
    source.concurrentRate = payload.concurrentRate || '';
    source.enabledCookieJar = payload.enabledCookieJar !== false;
    return source;
  }

  private static sanitizeBookSourceHeader(raw: string): string {
    const value = (raw || '').trim();
    if (!value) {
      return '';
    }
    try {
      const parsed = JSON.parse(value) as Record<string, Object>;
      if (parsed && !Array.isArray(parsed)) {
        const sanitized: Record<string, Object> = {};
        for (const key of Object.keys(parsed)) {
          if (!CloudSyncCoordinator.isSensitiveHeaderName(key)) {
            sanitized[key] = parsed[key];
          }
        }
        return JSON.stringify(sanitized);
      }
    } catch (e) {
    }
    return CloudSyncCoordinator.containsSensitiveHeader(value) ? '' : value;
  }

  private static mergeLocalSensitiveHeaders(remoteRaw: string, localRaw: string): string {
    const remote = remoteRaw || '';
    const local = localRaw || '';
    if (!local) {
      return remote;
    }
    try {
      const remoteHeaders = JSON.parse(remote || '{}') as Record<string, Object>;
      const localHeaders = JSON.parse(local) as Record<string, Object>;
      if (remoteHeaders && localHeaders &&
        !Array.isArray(remoteHeaders) && !Array.isArray(localHeaders)) {
        const merged: Record<string, Object> = {};
        for (const key of Object.keys(remoteHeaders)) {
          merged[key] = remoteHeaders[key];
        }
        for (const key of Object.keys(localHeaders)) {
          if (CloudSyncCoordinator.isSensitiveHeaderName(key)) {
            merged[key] = localHeaders[key];
          }
        }
        return JSON.stringify(merged);
      }
    } catch (e) {
    }
    return CloudSyncCoordinator.containsSensitiveHeader(local) ? local : remote;
  }

  private static containsSensitiveHeader(value: string): boolean {
    return /(^|[\s{,;"'])(cookie|authorization|proxy-authorization|x-api-key|api-key)\s*[:=]/i
      .test(value || '');
  }

  private static isSensitiveHeaderName(name: string): boolean {
    const normalized = (name || '').toLowerCase().replace(/[-_\s]/g, '');
    return normalized === 'cookie' ||
      normalized === 'authorization' ||
      normalized === 'proxyauthorization' ||
      normalized === 'xapikey' ||
      normalized === 'apikey';
  }

  private static notifyBookSourcesChanged(): void {
    const revision = AppStorage.get<number>('bookSourceOrderRevision') || 0;
    AppStorage.setOrCreate('bookSourceOrderRevision', revision + 1);
  }

  private static entity(entityType: string, entityId: string, payload: Object,
    localKey: string, label: string = ''): LocalSyncEntity {
    const result = new LocalSyncEntity();
    result.entityType = entityType;
    result.entityId = entityId;
    result.payloadJson = JSON.stringify(payload);
    result.contentHash = CloudSyncCoordinator.digest(result.payloadJson);
    result.localKey = localKey;
    result.label = label;
    return result;
  }

  private static rejectionIssue(ack: CloudSyncAcknowledgement,
    entity: LocalSyncEntity | undefined): CloudSyncIssue {
    const entityType = entity ? entity.entityType : '';
    const typeLabel = CloudSyncCoordinator.entityTypeLabel(entityType);
    const name = entity && entity.label ? entity.label.trim() : '';
    const deleting = !!entity && !entity.payloadJson;
    const title = `${typeLabel}${name ? `“${name}”` : ''}${deleting ? '删除未同步' : '未能上传'}`;
    const issue = CloudSyncIssueStore.create(
      entityType === 'book_source' ? CloudSyncIssueStore.KIND_BOOK_SOURCE : CloudSyncIssueStore.KIND_REJECTED,
      `reject:${entityType}:${entity ? entity.entityId : ack.opId}:${ack.error?.code || ''}`,
      title,
      ack.error?.message || '服务端拒收了这项数据');
    if (entity && entityType === 'book_source') issue.sourceUrl = entity.localKey;
    if (entity && entity.payloadJson) {
      issue.bytes = new util.TextEncoder().encodeInto(entity.payloadJson).byteLength;
    }
    return issue;
  }

  /**
   * The server rejects the whole request when one item exceeds its size limit, so no
   * acknowledgement names it. Measure the batch locally against the limit quoted in the message.
   */
  private static oversizedIssues(message: string, batch: CloudSyncOperation[],
    entities: LocalSyncEntity[]): CloudSyncIssue[] {
    const match = /不能超过\s*(\d+)\s*KB/i.exec(message);
    const limitBytes = match ? Number(match[1]) * 1024 : 0;
    const encoder = new util.TextEncoder();
    const sized: LocalSyncEntity[] = [];
    const sizes: number[] = [];
    for (const operation of batch) {
      if (operation.operation !== 'upsert') continue;
      const entity = entities.find((item: LocalSyncEntity) =>
        item.entityType === operation.entityType && item.entityId === operation.entityId);
      if (!entity || !entity.payloadJson) continue;
      sized.push(entity);
      sizes.push(encoder.encodeInto(entity.payloadJson).byteLength);
    }
    const result: CloudSyncIssue[] = [];
    for (let i = 0; i < sized.length; i++) {
      if (limitBytes > 0 && sizes[i] > limitBytes) {
        result.push(CloudSyncCoordinator.oversizedIssue(sized[i], sizes[i], message, false));
      }
    }
    if (result.length === 0 && sized.length > 0) {
      // Limit unknown or every item measured under it: the largest item is the cause, certainly
      // so when the batch holds only that one item.
      let largest = 0;
      for (let i = 1; i < sized.length; i++) {
        if (sizes[i] > sizes[largest]) largest = i;
      }
      result.push(CloudSyncCoordinator.oversizedIssue(sized[largest], sizes[largest], message, sized.length > 1));
    }
    return result;
  }

  private static oversizedIssue(entity: LocalSyncEntity, bytes: number, message: string,
    guessed: boolean): CloudSyncIssue {
    const name = entity.label ? `“${entity.label.trim()}”` : '';
    const issue = CloudSyncIssueStore.create(
      entity.entityType === 'book_source' ? CloudSyncIssueStore.KIND_BOOK_SOURCE : CloudSyncIssueStore.KIND_REJECTED,
      `oversize:${entity.entityType}:${entity.entityId}`,
      `${CloudSyncCoordinator.entityTypeLabel(entity.entityType)}${name}过大，导致整次同步失败`,
      guessed ? `${message}。这是本次同步中最大的一项，可能是它超出了限额。` :
        `${message}。在它被删除或变小之前，每次同步都会失败。`);
    issue.bytes = bytes;
    if (entity.entityType === 'book_source') issue.sourceUrl = entity.localKey;
    return issue;
  }

  private static entityTypeLabel(entityType: string): string {
    switch (entityType) {
      case 'book_group': return '书架分组';
      case 'bookshelf_item': return '书架书籍';
      case 'reading_progress': return '阅读进度';
      case 'bookmark': return '书签';
      case 'book_source': return '书源';
      case 'reader_settings': return '阅读设置';
      case 'replace_rule': return '替换规则';
      case 'theme_settings': return '主题设置';
      case 'appearance_mode': return '显示模式';
      case 'bookshelf_display': return '书架布局';
      case 'search_preferences': return '搜索设置';
      case 'custom_theme_schemes': return '自定义主题';
      default: return '同步数据';
    }
  }

  private static async recordIssues(context: Context, userId: string, issues: CloudSyncIssue[]): Promise<void> {
    try {
      await CloudSyncIssueStore.record(context, userId, issues);
    } catch (e) {
      console.warn('记录同步问题失败:', e);
    }
  }

  private static identity(prefix: string, value: string): string {
    return `${prefix}_${CloudSyncCoordinator.digest(value)}`;
  }

  private static digest(value: string): string {
    const md = cryptoFramework.createMd('SHA256');
    md.updateSync({ data: new util.TextEncoder().encodeInto(value) });
    const data = md.digestSync().data;
    let result = '';
    for (const byte of data) {
      result += byte.toString(16).padStart(2, '0');
    }
    return result;
  }

  private static entityPriority(entityType: string): number {
    if (entityType === 'book_group') return 0;
    if (entityType === 'book_source') return 1;
    if (entityType === 'bookshelf_item') return 2;
    if (entityType === 'reading_progress') return 3;
    if (entityType === 'bookmark') return 4;
    if (entityType === 'reader_settings') return 5;
    if (entityType === 'replace_rule') return 6;
    if (entityType === 'theme_settings') return 7;
    if (entityType === 'appearance_mode') return 8;
    if (entityType === 'bookshelf_display') return 9;
    if (entityType === 'search_preferences') return 10;
    if (entityType === 'custom_theme_schemes') return 11;
    return 20;
  }

  private static scopeAllows(settings: CloudSyncSettings, entityType: string): boolean {
    if (entityType === 'book_source') {
      return settings.bookSourcesEnabled;
    }
    if (entityType === 'book_group' ||
      entityType === 'bookshelf_item' ||
      entityType === 'reading_progress' ||
      entityType === 'bookmark') {
      return settings.readingDataEnabled;
    }
    if (entityType === 'reader_settings' ||
      entityType === 'replace_rule' ||
      entityType === 'theme_settings' ||
      entityType === 'custom_theme_schemes') {
      return settings.readingPreferencesEnabled;
    }
    if (entityType === 'appearance_mode' ||
      entityType === 'bookshelf_display' ||
      entityType === 'search_preferences') {
      return settings.applicationPreferencesEnabled;
    }
    return false;
  }

  private static validateResponse(response: CloudSyncExchangeResponse): void {
    if (!response || response.protocolVersion !== 1 ||
      !Number.isSafeInteger(Number(response.nextCursor)) ||
      Number(response.nextCursor) < 0) {
      throw new Error('同步服务返回的数据格式异常');
    }
  }
}
