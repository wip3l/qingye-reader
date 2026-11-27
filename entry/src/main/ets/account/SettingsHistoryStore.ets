import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';

/** 一项设置被替换前的内容。payloadJson 为空表示替换前本机没有这一项（例如新加的替换规则）。 */
export class SettingsHistoryEntry {
  entityType: string = '';
  entityId: string = '';
  payloadJson: string = '';
}

/** 列表用的元数据，不含内容。 */
export class SettingsHistoryItem {
  entityType: string = '';
  entityId: string = '';
  existed: boolean = true;
}

export class SettingsHistoryRecord {
  id: string = '';
  createdAt: number = 0;
  /** sync：同步来的设置替换前；restore：恢复设置历史前。 */
  reason: string = '';
  /** 带来替换内容的设备；本机恢复时为本机。 */
  sourceDeviceId: string = '';
  items: SettingsHistoryItem[] = [];
}

class SettingsHistoryIndex {
  records: SettingsHistoryRecord[] = [];
}

class SettingsHistoryPayload {
  entries: SettingsHistoryEntry[] = [];
}

/**
 * 本机的设置历史：同步或恢复要替换本机设置前，先把原来的内容存一份，最多保留 20 条、30 天。
 * 只存本机，不同步。内容按记录分文件存，索引只存元数据，列表时不读内容。
 */
export class SettingsHistoryStore {
  static readonly REASON_SYNC: string = 'sync';
  static readonly REASON_RESTORE: string = 'restore';
  private static readonly DIR: string = 'sync_settings_history';
  private static readonly INDEX_FILE: string = 'index.json';
  private static readonly MAX_RECORDS: number = 20;
  private static readonly KEEP_MS: number = 30 * 24 * 60 * 60 * 1000;
  private static queue: Promise<void> = Promise.resolve();

  static async list(context: Context): Promise<SettingsHistoryRecord[]> {
    await SettingsHistoryStore.queue.catch(() => {});
    const index = await SettingsHistoryStore.readIndex(context);
    const cutoff = Date.now() - SettingsHistoryStore.KEEP_MS;
    return index.records.filter((record: SettingsHistoryRecord) => record.createdAt >= cutoff);
  }

  static async entries(context: Context, recordId: string): Promise<SettingsHistoryEntry[]> {
    await SettingsHistoryStore.queue.catch(() => {});
    try {
      const raw = await SettingsHistoryStore.readText(SettingsHistoryStore.payloadPath(context, recordId));
      const payload = JSON.parse(raw) as SettingsHistoryPayload;
      return Array.isArray(payload?.entries) ? payload.entries : [];
    } catch (e) {
      return [];
    }
  }

  /**
   * 新建一条记录，或往同一次同步已建的记录里追加。同一项只留第一次存下的内容（替换前最早的那份）。
   * 返回记录 ID。
   */
  static async append(context: Context, recordId: string, reason: string, sourceDeviceId: string,
    entries: SettingsHistoryEntry[]): Promise<string> {
    if (entries.length === 0) return recordId;
    const id = recordId || `${Date.now()}-${util.generateRandomUUID().substring(0, 8)}`;
    const task = SettingsHistoryStore.queue.catch(() => {}).then(async () => {
      SettingsHistoryStore.ensureDir(context);
      const index = await SettingsHistoryStore.readIndex(context);
      let record = index.records.find((item: SettingsHistoryRecord) => item.id === id);
      let payload = new SettingsHistoryPayload();
      if (record) {
        try {
          payload = JSON.parse(await SettingsHistoryStore.readText(
            SettingsHistoryStore.payloadPath(context, id))) as SettingsHistoryPayload;
          if (!Array.isArray(payload.entries)) payload.entries = [];
        } catch (e) {
          payload = new SettingsHistoryPayload();
        }
      } else {
        record = new SettingsHistoryRecord();
        record.id = id;
        record.createdAt = Date.now();
        record.reason = reason;
        record.sourceDeviceId = sourceDeviceId;
        index.records.unshift(record);
      }
      for (const entry of entries) {
        if (payload.entries.some((existing: SettingsHistoryEntry) =>
          existing.entityType === entry.entityType && existing.entityId === entry.entityId)) {
          continue;
        }
        payload.entries.push(entry);
        const item = new SettingsHistoryItem();
        item.entityType = entry.entityType;
        item.entityId = entry.entityId;
        item.existed = !!entry.payloadJson;
        record.items.push(item);
      }
      await SettingsHistoryStore.writeText(SettingsHistoryStore.payloadPath(context, id), JSON.stringify(payload));
      await SettingsHistoryStore.prune(context, index);
      await SettingsHistoryStore.writeText(SettingsHistoryStore.indexPath(context), JSON.stringify(index));
    });
    SettingsHistoryStore.queue = task;
    await task;
    return id;
  }

  private static async prune(context: Context, index: SettingsHistoryIndex): Promise<void> {
    const cutoff = Date.now() - SettingsHistoryStore.KEEP_MS;
    const kept: SettingsHistoryRecord[] = [];
    for (const record of index.records) {
      if (kept.length < SettingsHistoryStore.MAX_RECORDS && record.createdAt >= cutoff) {
        kept.push(record);
        continue;
      }
      try {
        fs.unlinkSync(SettingsHistoryStore.payloadPath(context, record.id));
      } catch (e) {
        // 文件已不在。
      }
    }
    index.records = kept;
  }

  private static async readIndex(context: Context): Promise<SettingsHistoryIndex> {
    try {
      const parsed = JSON.parse(await SettingsHistoryStore.readText(
        SettingsHistoryStore.indexPath(context))) as SettingsHistoryIndex;
      const index = new SettingsHistoryIndex();
      index.records = Array.isArray(parsed?.records) ? parsed.records : [];
      return index;
    } catch (e) {
      return new SettingsHistoryIndex();
    }
  }

  private static ensureDir(context: Context): void {
    const dir = `${context.filesDir}/${SettingsHistoryStore.DIR}`;
    if (!fs.accessSync(dir)) fs.mkdirSync(dir);
  }

  private static indexPath(context: Context): string {
    return `${context.filesDir}/${SettingsHistoryStore.DIR}/${SettingsHistoryStore.INDEX_FILE}`;
  }

  private static payloadPath(context: Context, recordId: string): string {
    const safe = recordId.replace(/[^a-zA-Z0-9_-]/g, '_');
    return `${context.filesDir}/${SettingsHistoryStore.DIR}/${safe}.json`;
  }

  private static async writeText(path: string, value: string): Promise<void> {
    const bytes = new util.TextEncoder().encodeInto(value);
    const tempPath = `${path}.tmp`;
    const file = await fs.open(tempPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      await fs.write(file.fd, bytes.buffer, { offset: 0, length: bytes.byteLength });
    } finally {
      await fs.close(file);
    }
    await fs.rename(tempPath, path);
  }

  private static async readText(path: string): Promise<string> {
    return fs.readText(path);
  }
}
