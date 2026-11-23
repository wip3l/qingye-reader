import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { util } from '@kit.ArkTS';
import { WebDavBrowsePrefs, WebDavConnection } from './WebDavModels';

export class WebDavSettingsStore {
  private static readonly STORE_NAME: string = 'webdav_settings';
  private static readonly KEY_CONNECTIONS: string = 'connections_v1';
  private static readonly KEY_ACTIVE_ID: string = 'active_connection_id';
  /** 远程书籍页的排序、显示其他文件等浏览偏好，按连接分别存。 */
  private static readonly KEY_BROWSE_PREFS_PREFIX: string = 'browse_prefs_';

  static async loadBrowsePrefs(context: Context, connectionId: string): Promise<WebDavBrowsePrefs> {
    const prefs = new WebDavBrowsePrefs();
    if (!connectionId) return prefs;
    try {
      const store = await preferences.getPreferences(context, WebDavSettingsStore.STORE_NAME);
      const raw = await store.get(`${WebDavSettingsStore.KEY_BROWSE_PREFS_PREFIX}${connectionId}`, '');
      if (typeof raw !== 'string' || !raw) return prefs;
      const value = JSON.parse(raw) as WebDavBrowsePrefs;
      prefs.sortMode = WebDavBrowsePrefs.normalizeSortMode(value.sortMode);
      prefs.showOthers = value.showOthers === true;
      prefs.searchDeep = value.searchDeep === true;
      prefs.booksOnly = value.booksOnly === true;
    } catch (_) {
    }
    return prefs;
  }

  static async saveBrowsePrefs(context: Context, connectionId: string, prefs: WebDavBrowsePrefs): Promise<void> {
    if (!connectionId) return;
    const store = await preferences.getPreferences(context, WebDavSettingsStore.STORE_NAME);
    await store.put(`${WebDavSettingsStore.KEY_BROWSE_PREFS_PREFIX}${connectionId}`, JSON.stringify(prefs));
    await store.flush();
  }

  static async loadConnections(context: Context): Promise<WebDavConnection[]> {
    const store = await preferences.getPreferences(context, WebDavSettingsStore.STORE_NAME);
    const raw = await store.get(WebDavSettingsStore.KEY_CONNECTIONS, '');
    if (typeof raw !== 'string' || !raw) return [];
    try {
      const values = JSON.parse(raw) as WebDavConnection[];
      if (!Array.isArray(values)) return [];
      return values.map((value: WebDavConnection): WebDavConnection =>
        WebDavSettingsStore.normalize(value)).filter((value: WebDavConnection): boolean => !!value.id);
    } catch (_) {
      return [];
    }
  }

  static async saveConnection(context: Context, source: WebDavConnection): Promise<WebDavConnection> {
    const connections = await WebDavSettingsStore.loadConnections(context);
    const value = WebDavSettingsStore.normalize(source);
    const now = Date.now();
    if (!value.id) value.id = util.generateRandomUUID();
    if (!value.createdAt) value.createdAt = now;
    value.updatedAt = now;
    const index = connections.findIndex((item: WebDavConnection): boolean => item.id === value.id);
    if (index >= 0) connections[index] = value;
    else connections.push(value);
    const store = await preferences.getPreferences(context, WebDavSettingsStore.STORE_NAME);
    await store.put(WebDavSettingsStore.KEY_CONNECTIONS, JSON.stringify(connections));
    await store.put(WebDavSettingsStore.KEY_ACTIVE_ID, value.id);
    await store.flush();
    return value;
  }

  static async deleteConnection(context: Context, connectionId: string): Promise<void> {
    const connections = (await WebDavSettingsStore.loadConnections(context))
      .filter((item: WebDavConnection): boolean => item.id !== connectionId);
    const store = await preferences.getPreferences(context, WebDavSettingsStore.STORE_NAME);
    await store.put(WebDavSettingsStore.KEY_CONNECTIONS, JSON.stringify(connections));
    await store.delete(`${WebDavSettingsStore.KEY_BROWSE_PREFS_PREFIX}${connectionId}`);
    const active = await store.get(WebDavSettingsStore.KEY_ACTIVE_ID, '');
    if (active === connectionId) {
      await store.put(WebDavSettingsStore.KEY_ACTIVE_ID, connections.length > 0 ? connections[0].id : '');
    }
    await store.flush();
  }

  static async activeConnectionId(context: Context): Promise<string> {
    const store = await preferences.getPreferences(context, WebDavSettingsStore.STORE_NAME);
    const value = await store.get(WebDavSettingsStore.KEY_ACTIVE_ID, '');
    return typeof value === 'string' ? value : '';
  }

  static async setActiveConnectionId(context: Context, connectionId: string): Promise<void> {
    const store = await preferences.getPreferences(context, WebDavSettingsStore.STORE_NAME);
    await store.put(WebDavSettingsStore.KEY_ACTIVE_ID, connectionId || '');
    await store.flush();
  }

  private static normalize(source: WebDavConnection): WebDavConnection {
    const result = new WebDavConnection();
    if (!source) return result;
    result.id = String(source.id || '').trim();
    result.name = String(source.name || '').trim() || 'WebDAV';
    result.baseUrl = WebDavSettingsStore.normalizeBaseUrl(String(source.baseUrl || ''));
    result.username = String(source.username || '').trim();
    result.libraryRoot = WebDavSettingsStore.normalizeRelativePath(String(source.libraryRoot || ''));
    const secretStorageVersion = Math.max(0, Math.floor(Number(source.secretStorageVersion) || 0));
    result.rememberPassword = secretStorageVersion < 1 ? true : source.rememberPassword !== false;
    result.secretStorageVersion = 1;
    result.enabled = source.enabled !== false;
    result.createdAt = Math.max(0, Math.floor(Number(source.createdAt) || 0));
    result.updatedAt = Math.max(0, Math.floor(Number(source.updatedAt) || 0));
    return result;
  }

  static normalizeBaseUrl(value: string): string {
    const result = (value || '').trim();
    if (!/^https:\/\//i.test(result) && !/^http:\/\//i.test(result)) return result;
    return result.endsWith('/') ? result : `${result}/`;
  }

  static normalizeRelativePath(value: string): string {
    const parts: string[] = [];
    for (const raw of (value || '').replace(/\\/g, '/').split('/')) {
      const part = raw.trim();
      if (!part || part === '.') continue;
      if (part === '..') {
        if (parts.length > 0) parts.pop();
      } else {
        parts.push(part);
      }
    }
    return parts.join('/');
  }
}
