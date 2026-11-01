import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class CloudSyncSettings {
  enabled: boolean = false;
  autoSyncEnabled: boolean = true;
  wifiOnly: boolean = false;
  foregroundSyncEnabled: boolean = false;
  // 保存用户偏好；实际启用还须通过终身超级会员校验。
  localBooksEnabled: boolean = true;
  customFontsEnabled: boolean = true;
  readingDataEnabled: boolean = true;
  bookSourcesEnabled: boolean = true;
  readingPreferencesEnabled: boolean = true;
  applicationPreferencesEnabled: boolean = true;
  lastSuccessAt: number = 0;
  pendingCount: number = 0;
  status: string = 'disabled';
  errorMessage: string = '';
}

export class CloudSyncSettingsStore {
  static readonly STORAGE_ENABLED: string = 'cloudSyncEnabled';
  static readonly STORAGE_AUTO_SYNC_ENABLED: string = 'cloudSyncAutoEnabled';
  static readonly STORAGE_WIFI_ONLY: string = 'cloudSyncWifiOnly';
  static readonly STORAGE_FOREGROUND_SYNC_ENABLED: string = 'cloudSyncForegroundEnabled';
  static readonly STORAGE_LOCAL_BOOKS_ENABLED: string = 'cloudSyncLocalBooksEnabled';
  static readonly STORAGE_CUSTOM_FONTS_ENABLED: string = 'cloudSyncCustomFontsEnabled';
  static readonly STORAGE_READING_DATA_ENABLED: string = 'cloudSyncReadingDataEnabled';
  static readonly STORAGE_BOOK_SOURCES_ENABLED: string = 'cloudSyncBookSourcesEnabled';
  static readonly STORAGE_READING_PREFERENCES_ENABLED: string = 'cloudSyncReadingPreferencesEnabled';
  static readonly STORAGE_APPLICATION_PREFERENCES_ENABLED: string = 'cloudSyncApplicationPreferencesEnabled';
  static readonly STORAGE_LAST_SUCCESS_AT: string = 'cloudSyncLastSuccessAt';
  static readonly STORAGE_PENDING_COUNT: string = 'cloudSyncPendingCount';
  static readonly STORAGE_STATUS: string = 'cloudSyncStatus';
  static readonly STORAGE_ERROR_MESSAGE: string = 'cloudSyncErrorMessage';
  static readonly STORAGE_REVISION: string = 'cloudSyncSettingsRevision';
  static readonly STORAGE_RUNTIME_ACTIVE: string = 'cloudSyncRuntimeActive';

  static readonly STATUS_DISABLED: string = 'disabled';
  static readonly STATUS_NOT_STARTED: string = 'not_started';
  static readonly STATUS_SYNCING: string = 'syncing';
  static readonly STATUS_SYNCED: string = 'synced';
  static readonly STATUS_OFFLINE: string = 'offline';
  static readonly STATUS_ERROR: string = 'error';
  /** 同步完成，但有条目（过大或被服务端拒收）被跳过；pendingCount 为跳过的条数。 */
  static readonly STATUS_PARTIAL: string = 'partial';

  private static readonly STORE_NAME: string = 'account_cloud_sync_settings';
  private static readonly KEY_PREFIX: string = 'settings_';
  private static currentUserId: string = '';
  private static cachedSettings: CloudSyncSettings = new CloudSyncSettings();
  private static storageQueue: Promise<void> = Promise.resolve();

  static initializeStorage(): void {
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_ENABLED, false);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_AUTO_SYNC_ENABLED, true);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_WIFI_ONLY, false);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_FOREGROUND_SYNC_ENABLED, false);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_LOCAL_BOOKS_ENABLED, true);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_CUSTOM_FONTS_ENABLED, true);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_READING_DATA_ENABLED, true);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_BOOK_SOURCES_ENABLED, true);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_READING_PREFERENCES_ENABLED, true);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_APPLICATION_PREFERENCES_ENABLED, true);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_LAST_SUCCESS_AT, 0);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_PENDING_COUNT, 0);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_STATUS, CloudSyncSettingsStore.STATUS_DISABLED);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_ERROR_MESSAGE, '');
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_REVISION, 0);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_RUNTIME_ACTIVE, false);
  }

  static async load(context: Context, userId: string): Promise<CloudSyncSettings> {
    CloudSyncSettingsStore.initializeStorage();
    const normalizedUserId = CloudSyncSettingsStore.normalizeUserId(userId);
    let loadedSettings = new CloudSyncSettings();
    const readTask = CloudSyncSettingsStore.storageQueue.catch(() => {
    }).then(async () => {
      const store = await preferences.getPreferences(context, CloudSyncSettingsStore.STORE_NAME);
      const raw = await store.get(CloudSyncSettingsStore.preferenceKey(normalizedUserId), '');
      const settings = CloudSyncSettingsStore.parse(typeof raw === 'string' ? raw : '');
      if (settings.status === CloudSyncSettingsStore.STATUS_SYNCING &&
        AppStorage.get<boolean>(CloudSyncSettingsStore.STORAGE_RUNTIME_ACTIVE) !== true) {
        // syncing 会写入偏好存储。进程被终止或同步异常退出后没有内存任务承接它，
        // 应恢复为可重试状态，避免界面永久禁用“立即同步”。
        settings.status = CloudSyncSettingsStore.STATUS_NOT_STARTED;
        settings.errorMessage = '';
        await store.put(CloudSyncSettingsStore.preferenceKey(normalizedUserId), JSON.stringify(settings));
        await store.flush();
      }
      CloudSyncSettingsStore.currentUserId = normalizedUserId;
      CloudSyncSettingsStore.cachedSettings = CloudSyncSettingsStore.clone(settings);
      CloudSyncSettingsStore.applyToStorage(settings);
      loadedSettings = CloudSyncSettingsStore.clone(settings);
    });
    CloudSyncSettingsStore.storageQueue = readTask;
    await readTask;
    return loadedSettings;
  }

  static async save(context: Context, userId: string, settings: CloudSyncSettings): Promise<void> {
    CloudSyncSettingsStore.initializeStorage();
    const normalizedUserId = CloudSyncSettingsStore.normalizeUserId(userId);
    const normalized = CloudSyncSettingsStore.normalize(settings);
    const writeTask = CloudSyncSettingsStore.storageQueue.catch(() => {
    }).then(async () => {
      const store = await preferences.getPreferences(context, CloudSyncSettingsStore.STORE_NAME);
      await store.put(CloudSyncSettingsStore.preferenceKey(normalizedUserId), JSON.stringify(normalized));
      await store.flush();
      CloudSyncSettingsStore.currentUserId = normalizedUserId;
      CloudSyncSettingsStore.cachedSettings = CloudSyncSettingsStore.clone(normalized);
      CloudSyncSettingsStore.applyToStorage(normalized);
    });
    CloudSyncSettingsStore.storageQueue = writeTask;
    await writeTask;
  }

  static async saveUserPreferences(context: Context, userId: string,
    settings: CloudSyncSettings): Promise<void> {
    CloudSyncSettingsStore.initializeStorage();
    const normalizedUserId = CloudSyncSettingsStore.normalizeUserId(userId);
    const requested = CloudSyncSettingsStore.normalize(settings);
    const writeTask = CloudSyncSettingsStore.storageQueue.catch(() => {
    }).then(async () => {
      const store = await preferences.getPreferences(context, CloudSyncSettingsStore.STORE_NAME);
      const raw = await store.get(CloudSyncSettingsStore.preferenceKey(normalizedUserId), '');
      const current = CloudSyncSettingsStore.parse(typeof raw === 'string' ? raw : '');
      current.enabled = requested.enabled;
      current.autoSyncEnabled = requested.autoSyncEnabled;
      current.wifiOnly = requested.wifiOnly;
      current.foregroundSyncEnabled = requested.foregroundSyncEnabled;
      current.localBooksEnabled = requested.localBooksEnabled;
      current.customFontsEnabled = requested.customFontsEnabled;
      current.readingDataEnabled = requested.readingDataEnabled;
      current.bookSourcesEnabled = requested.bookSourcesEnabled;
      current.readingPreferencesEnabled = requested.readingPreferencesEnabled;
      current.applicationPreferencesEnabled = requested.applicationPreferencesEnabled;
      if (!current.enabled) {
        current.status = CloudSyncSettingsStore.STATUS_DISABLED;
        current.errorMessage = '';
      } else if (current.status === CloudSyncSettingsStore.STATUS_DISABLED) {
        current.status = CloudSyncSettingsStore.STATUS_NOT_STARTED;
      }
      const normalized = CloudSyncSettingsStore.normalize(current);
      await store.put(CloudSyncSettingsStore.preferenceKey(normalizedUserId), JSON.stringify(normalized));
      await store.flush();
      CloudSyncSettingsStore.currentUserId = normalizedUserId;
      CloudSyncSettingsStore.cachedSettings = CloudSyncSettingsStore.clone(normalized);
      CloudSyncSettingsStore.applyToStorage(normalized);
    });
    CloudSyncSettingsStore.storageQueue = writeTask;
    await writeTask;
  }

  static async saveRuntimeState(context: Context, userId: string, status: string,
    lastSuccessAt: number, pendingCount: number, errorMessage: string): Promise<void> {
    CloudSyncSettingsStore.initializeStorage();
    const normalizedUserId = CloudSyncSettingsStore.normalizeUserId(userId);
    const writeTask = CloudSyncSettingsStore.storageQueue.catch(() => {
    }).then(async () => {
      const store = await preferences.getPreferences(context, CloudSyncSettingsStore.STORE_NAME);
      const raw = await store.get(CloudSyncSettingsStore.preferenceKey(normalizedUserId), '');
      const current = CloudSyncSettingsStore.parse(typeof raw === 'string' ? raw : '');
      if (current.enabled) {
        current.status = status;
        current.lastSuccessAt = lastSuccessAt;
        current.pendingCount = pendingCount;
        current.errorMessage = errorMessage;
      }
      const normalized = CloudSyncSettingsStore.normalize(current);
      await store.put(CloudSyncSettingsStore.preferenceKey(normalizedUserId), JSON.stringify(normalized));
      await store.flush();
      CloudSyncSettingsStore.currentUserId = normalizedUserId;
      CloudSyncSettingsStore.cachedSettings = CloudSyncSettingsStore.clone(normalized);
      CloudSyncSettingsStore.applyToStorage(normalized);
    });
    CloudSyncSettingsStore.storageQueue = writeTask;
    await writeTask;
  }

  static current(): CloudSyncSettings {
    return CloudSyncSettingsStore.clone(CloudSyncSettingsStore.cachedSettings);
  }

  static currentAccountId(): string {
    return CloudSyncSettingsStore.currentUserId;
  }

  static applyToStorage(settings: CloudSyncSettings): void {
    const normalized = CloudSyncSettingsStore.normalize(settings);
    CloudSyncSettingsStore.cachedSettings = CloudSyncSettingsStore.clone(normalized);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_ENABLED, normalized.enabled);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_AUTO_SYNC_ENABLED, normalized.autoSyncEnabled);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_WIFI_ONLY, normalized.wifiOnly);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_FOREGROUND_SYNC_ENABLED,
      normalized.foregroundSyncEnabled);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_LOCAL_BOOKS_ENABLED, normalized.localBooksEnabled);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_CUSTOM_FONTS_ENABLED, normalized.customFontsEnabled);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_READING_DATA_ENABLED,
      normalized.readingDataEnabled);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_BOOK_SOURCES_ENABLED,
      normalized.bookSourcesEnabled);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_READING_PREFERENCES_ENABLED,
      normalized.readingPreferencesEnabled);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_APPLICATION_PREFERENCES_ENABLED,
      normalized.applicationPreferencesEnabled);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_LAST_SUCCESS_AT, normalized.lastSuccessAt);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_PENDING_COUNT, normalized.pendingCount);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_STATUS, normalized.status);
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_ERROR_MESSAGE, normalized.errorMessage);
    const revision = (AppStorage.get<number>(CloudSyncSettingsStore.STORAGE_REVISION) || 0) + 1;
    AppStorage.setOrCreate(CloudSyncSettingsStore.STORAGE_REVISION, revision);
  }

  static statusSummary(loggedIn: boolean, enabled: boolean, status: string,
    pendingCount: number, lastSuccessAt: number): string {
    if (!loggedIn) {
      return '登录后开启';
    }
    if (!enabled) {
      return '未开启';
    }
    if (status === CloudSyncSettingsStore.STATUS_SYNCING) {
      return '正在同步';
    }
    if (status === CloudSyncSettingsStore.STATUS_OFFLINE) {
      return pendingCount > 0 ? `离线 · 待同步 ${pendingCount} 项` : '当前离线';
    }
    if (status === CloudSyncSettingsStore.STATUS_ERROR) {
      return '同步失败';
    }
    if (status === CloudSyncSettingsStore.STATUS_PARTIAL && pendingCount > 0) {
      return `已同步 · 跳过 ${pendingCount} 项`;
    }
    if (pendingCount > 0) {
      return `待同步 ${pendingCount} 项`;
    }
    if (lastSuccessAt > 0) {
      return `已同步 · ${CloudSyncSettingsStore.relativeTime(lastSuccessAt)}`;
    }
    return '等待首次同步';
  }

  private static relativeTime(timestamp: number): string {
    const elapsed = Math.max(0, Date.now() - timestamp);
    if (elapsed < 60 * 1000) {
      return '刚刚';
    }
    const minutes = Math.floor(elapsed / (60 * 1000));
    if (minutes < 60) {
      return `${minutes} 分钟前`;
    }
    const hours = Math.floor(minutes / 60);
    if (hours < 24) {
      return `${hours} 小时前`;
    }
    const days = Math.floor(hours / 24);
    if (days < 7) {
      return `${days} 天前`;
    }
    return new Date(timestamp).toLocaleDateString();
  }

  private static preferenceKey(userId: string): string {
    return `${CloudSyncSettingsStore.KEY_PREFIX}${userId || 'guest'}`;
  }

  private static normalizeUserId(userId: string): string {
    const normalized = (userId || '').trim().replace(/[^a-zA-Z0-9_-]/g, '_');
    return normalized || 'guest';
  }

  private static parse(raw: string): CloudSyncSettings {
    if (!raw) {
      return new CloudSyncSettings();
    }
    try {
      return CloudSyncSettingsStore.normalize(JSON.parse(raw) as CloudSyncSettings);
    } catch (e) {
      return new CloudSyncSettings();
    }
  }

  private static normalize(source: CloudSyncSettings | null | undefined): CloudSyncSettings {
    const result = new CloudSyncSettings();
    if (!source) {
      return result;
    }
    result.enabled = source.enabled === true;
    result.autoSyncEnabled = source.autoSyncEnabled !== false;
    result.wifiOnly = source.wifiOnly === true;
    // A missing field belongs to an old/newly-created account and must not
    // immediately fire another sync when the login flow returns to foreground.
    result.foregroundSyncEnabled = source.foregroundSyncEnabled === true;
    result.localBooksEnabled = source.localBooksEnabled !== false;
    result.customFontsEnabled = source.customFontsEnabled !== false;
    result.readingDataEnabled = source.readingDataEnabled !== false;
    result.bookSourcesEnabled = source.bookSourcesEnabled !== false;
    result.readingPreferencesEnabled = source.readingPreferencesEnabled !== false;
    result.applicationPreferencesEnabled = source.applicationPreferencesEnabled !== false;
    result.lastSuccessAt = Math.max(0, Math.floor(Number(source.lastSuccessAt) || 0));
    result.pendingCount = Math.max(0, Math.floor(Number(source.pendingCount) || 0));
    result.status = CloudSyncSettingsStore.normalizeStatus(source.status, result.enabled);
    result.errorMessage = typeof source.errorMessage === 'string' ? source.errorMessage : '';
    if (!result.enabled) {
      result.status = CloudSyncSettingsStore.STATUS_DISABLED;
      result.errorMessage = '';
    } else if (result.status === CloudSyncSettingsStore.STATUS_DISABLED) {
      result.status = CloudSyncSettingsStore.STATUS_NOT_STARTED;
    }
    return result;
  }

  private static normalizeStatus(status: string, enabled: boolean): string {
    if (!enabled) {
      return CloudSyncSettingsStore.STATUS_DISABLED;
    }
    if (status === CloudSyncSettingsStore.STATUS_NOT_STARTED ||
      status === CloudSyncSettingsStore.STATUS_SYNCING ||
      status === CloudSyncSettingsStore.STATUS_SYNCED ||
      status === CloudSyncSettingsStore.STATUS_OFFLINE ||
      status === CloudSyncSettingsStore.STATUS_ERROR ||
      status === CloudSyncSettingsStore.STATUS_PARTIAL) {
      return status;
    }
    return CloudSyncSettingsStore.STATUS_NOT_STARTED;
  }

  private static clone(source: CloudSyncSettings): CloudSyncSettings {
    const result = new CloudSyncSettings();
    result.enabled = source.enabled;
    result.autoSyncEnabled = source.autoSyncEnabled;
    result.wifiOnly = source.wifiOnly;
    result.foregroundSyncEnabled = source.foregroundSyncEnabled;
    result.localBooksEnabled = source.localBooksEnabled;
    result.customFontsEnabled = source.customFontsEnabled;
    result.readingDataEnabled = source.readingDataEnabled;
    result.bookSourcesEnabled = source.bookSourcesEnabled;
    result.readingPreferencesEnabled = source.readingPreferencesEnabled;
    result.applicationPreferencesEnabled = source.applicationPreferencesEnabled;
    result.lastSuccessAt = source.lastSuccessAt;
    result.pendingCount = source.pendingCount;
    result.status = source.status;
    result.errorMessage = source.errorMessage;
    return result;
  }
}
