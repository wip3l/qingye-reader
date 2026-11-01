import { ReadStatsEntry } from '../../model/data/AppDatabase';

export class AndroidReadRecord extends ReadStatsEntry {
  name: string = '';
  author: string = '';
}

/** Android exports the same reading time as daily rows, sessions and lifetime totals. */
export class AndroidReadRecordImport {
  private details: Map<string, AndroidReadRecord> = new Map<string, AndroidReadRecord>();
  private sessions: Map<string, AndroidReadRecord> = new Map<string, AndroidReadRecord>();
  private totals: Map<string, AndroidReadRecord> = new Map<string, AndroidReadRecord>();
  private sessionIds: Set<string> = new Set<string>();

  private static text(raw: Record<string, Object>, key: string): string {
    return typeof raw[key] === 'string' ? (raw[key] as string).trim() : '';
  }

  private static integer(raw: Record<string, Object>, key: string): number {
    const value = raw[key];
    if (typeof value !== 'number' && typeof value !== 'string') return 0;
    const parsed = Number(value);
    return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : 0;
  }

  private static day(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-` +
      String(date.getDate()).padStart(2, '0');
  }

  private static validDay(day: string): boolean {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return false;
    const date = new Date(`${day}T12:00:00`);
    return Number.isFinite(date.getTime()) && AndroidReadRecordImport.day(date.getTime()) === day;
  }

  private static identity(record: AndroidReadRecord): string {
    return JSON.stringify([record.name, record.author, record.deviceId]);
  }

  private static row(raw: Record<string, Object>): AndroidReadRecord | null {
    const record = new AndroidReadRecord();
    record.name = AndroidReadRecordImport.text(raw, 'bookName');
    record.author = AndroidReadRecordImport.text(raw, 'bookAuthor');
    if (!record.name || record.name.length > 1024 || record.author.length > 1024) return null;
    const device = AndroidReadRecordImport.text(raw, 'deviceId');
    record.deviceId = device ? `android:${device.substring(0, 256)}` : 'legacy-import';
    record.deviceName = 'Android 阅读导入';
    return record;
  }

  addDetail(raw: Record<string, Object>): void {
    const record = AndroidReadRecordImport.row(raw);
    if (!record) return;
    record.durationMs = AndroidReadRecordImport.integer(raw, 'readTime');
    record.dayKey = AndroidReadRecordImport.text(raw, 'date');
    record.startedAt = AndroidReadRecordImport.integer(raw, 'firstReadTime');
    record.lastReadAt = AndroidReadRecordImport.integer(raw, 'lastReadTime');
    if (!record.durationMs || !AndroidReadRecordImport.validDay(record.dayKey)) return;
    // Keep the exported calendar day even when its timestamps use another timezone.
    const key = AndroidReadRecordImport.identity(record) + record.dayKey;
    const existing = this.details.get(key);
    if (!existing || existing.durationMs < record.durationMs) this.details.set(key, record);
  }

  addSession(raw: Record<string, Object>): void {
    const template = AndroidReadRecordImport.row(raw);
    if (!template) return;
    const start = AndroidReadRecordImport.integer(raw, 'startTime');
    const end = AndroidReadRecordImport.integer(raw, 'endTime');
    if (!start || end <= start || !Number.isFinite(new Date(end).getTime())) return;
    const identity = AndroidReadRecordImport.identity(template);
    const sessionKey = JSON.stringify([identity, start, end]);
    if (this.sessionIds.has(sessionKey)) return;
    this.sessionIds.add(sessionKey);
    // A corrupt session must not generate an unbounded number of calendar rows.
    if (end - start > 7 * 86400000) return;
    let cursor = start;
    while (cursor < end) {
      const date = new Date(cursor);
      const nextDay = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1).getTime();
      const segmentEnd = Math.min(end, nextDay);
      const day = AndroidReadRecordImport.day(cursor);
      const key = identity + day;
      let record = this.sessions.get(key);
      if (!record) {
        record = AndroidReadRecordImport.row(raw) as AndroidReadRecord;
        record.dayKey = day;
        record.startedAt = cursor;
        this.sessions.set(key, record);
      }
      record.durationMs += segmentEnd - cursor;
      record.lastReadAt = Math.max(record.lastReadAt, segmentEnd);
      cursor = segmentEnd;
    }
  }

  addTotal(raw: Record<string, Object>): void {
    const record = AndroidReadRecordImport.row(raw);
    if (!record) return;
    record.durationMs = AndroidReadRecordImport.integer(raw, 'readTime');
    record.lastReadAt = AndroidReadRecordImport.integer(raw, 'lastRead');
    if (!record.durationMs || !record.lastReadAt || !Number.isFinite(new Date(record.lastReadAt).getTime())) return;
    record.dayKey = AndroidReadRecordImport.day(record.lastReadAt);
    // Old backups have no per-day information: retain the total on the last known day.
    record.startedAt = Math.max(0, record.lastReadAt - record.durationMs);
    const key = AndroidReadRecordImport.identity(record);
    const existing = this.totals.get(key);
    if (!existing || existing.durationMs < record.durationMs) this.totals.set(key, record);
  }

  records(): AndroidReadRecord[] {
    const records: AndroidReadRecord[] = [];
    const detailed: Set<string> = new Set<string>();
    this.details.forEach((record: AndroidReadRecord): void => {
      detailed.add(AndroidReadRecordImport.identity(record));
      records.push(record);
    });
    const covered: Set<string> = new Set<string>();
    this.sessions.forEach((record: AndroidReadRecord): void => {
      const identity = AndroidReadRecordImport.identity(record);
      if (!detailed.has(identity)) { records.push(record); covered.add(identity); }
    });
    this.totals.forEach((record: AndroidReadRecord, identity: string): void => {
      if (!detailed.has(identity) && !covered.has(identity)) records.push(record);
    });
    for (const record of records) {
      record.recordId = 'android-read:' + AndroidReadRecordImport.identity(record) + ':' + record.dayKey;
    }
    return records;
  }
}
