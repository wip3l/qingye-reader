import { common } from '@kit.AbilityKit';
import { hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import deviceInfo from '@ohos.deviceInfo';
import { CrashContextTrail } from './CrashContextTrail';

/** 崩溃记录的种类：闪退（JS 异常或原生崩溃）、卡死被结束、被系统结束（内存、显存等资源管控）。 */
export type CrashReportKind = 'crash' | 'freeze' | 'killed';

export interface CrashReportSummary {
  id: string;
  kind: CrashReportKind;
  time: number;
  foreground: boolean;
  version: string;
  title: string;
  hasLog: boolean;
}

/**
 * 本地崩溃记录。订阅系统的 APP_CRASH / APP_FREEZE / APP_KILLED 事件：这些事件在出事后的下一次启动时由系统投递，
 * 每条存成 crash_reports/<id>.json，系统附带的完整日志（external_log）复制成 <id>.log，最多留 MAX_REPORTS 条。
 * 每条还附上那次运行的状态（CrashContextTrail：页面、在用功能、内存采样）；“被系统结束”本身不带堆栈，全靠它判断原因。
 * 系统的内存超限预警（RESOURCE_OVERLIMIT）单独存进 overlimit.json，按进程号附到同一次运行的记录里。
 * 不联网上传，用户在“关于 › 交流与反馈 › 崩溃记录”里查看并自行分享。
 *
 * 每条新记录挂起一次启动提示（pending_notice 文件，同步到 AppStorage 的 KEY_PENDING_NOTICE），
 * 首页可见时弹出，看过或关掉就清除。后台被系统回收、升级安装结束进程不算异常，不记录（见 ignoredKill）。
 * 不注册 errorManager：注册后 JS 未捕获异常不再让进程退出，应用会停在半坏状态；JS 异常本身会以 APP_CRASH 送达。
 */
export class CrashReportStore {
  static readonly KEY_PENDING_NOTICE: string = 'crashReportPendingNotice';
  private static readonly WATCHER_NAME: string = 'qingye_crash_watcher';
  private static readonly DIR_NAME: string = 'crash_reports';
  private static readonly NOTICE_FILE: string = 'pending_notice';
  private static readonly MAX_REPORTS: number = 20;
  private static readonly MAX_LOG_BYTES: number = 1024 * 1024;
  private static readonly MAX_LOG_FILES: number = 2;
  private static readonly CRASH_KILL_REASON: RegExp = /^(JsError|CppCrash|NativeCrash|AppCrash|AppFreeze)$/i;
  private static readonly BENIGN_KILL_REASON: RegExp = /upgrade|install|clear|force.?stop|by.?user/i;
  /** 卡死后系统结束进程时附带的 APP_KILLED（实测 reason 为 ThreadBlock6S），堆栈在同一次运行的 APP_FREEZE 里。 */
  private static readonly FREEZE_KILL_REASON: RegExp = /block|freeze|lifecycle.?timeout/i;
  /** 卡死日志要十几秒才生成，APP_FREEZE 常比 APP_KILLED 晚到；这段时间内先不为后者弹提示。 */
  private static readonly FREEZE_PAIR_WAIT_MS: number = 40000;
  private static readonly OVERLIMIT_FILE: string = 'overlimit.json';
  private static readonly MAX_OVERLIMITS: number = 10;
  private static dir: string = '';
  private static started: boolean = false;
  private static writeChain: Promise<void> = Promise.resolve();

  /** 在 UIAbility.onCreate 里尽早调用；重复调用无副作用。 */
  static start(context: common.UIAbilityContext): void {
    if (CrashReportStore.started) return;
    CrashReportStore.started = true;
    CrashReportStore.dir = `${context.filesDir}/${CrashReportStore.DIR_NAME}`;
    CrashReportStore.restorePendingNotice();
    try {
      hiAppEvent.addWatcher({
        name: CrashReportStore.WATCHER_NAME,
        appEventFilters: [{
          domain: hiAppEvent.domain.OS,
          names: [hiAppEvent.event.APP_CRASH, hiAppEvent.event.APP_FREEZE, hiAppEvent.event.APP_KILLED,
            hiAppEvent.event.RESOURCE_OVERLIMIT]
        }],
        onReceive: (_domain: string, groups: Array<hiAppEvent.AppEventGroup>): void => {
          for (const group of groups) {
            for (const info of group.appEventInfos) {
              CrashReportStore.enqueue(group.name, info);
            }
          }
        }
      });
    } catch (error) {
      console.warn('订阅崩溃事件失败:', error);
    }
  }

  static list(): CrashReportSummary[] {
    const result: CrashReportSummary[] = [];
    for (const name of CrashReportStore.listFiles()) {
      if (!name.endsWith('.json')) continue;
      const record = CrashReportStore.readRecord(name.substring(0, name.length - 5));
      if (record !== null) result.push(record.summary);
    }
    result.sort((a: CrashReportSummary, b: CrashReportSummary): number => b.time - a.time);
    return result;
  }

  static summaryOf(id: string): CrashReportSummary | null {
    const record = CrashReportStore.readRecord(id);
    return record === null ? null : record.summary;
  }

  /** 可读的完整报告：概要、事件参数、最近日志，以及系统附带的日志文件内容。 */
  static reportText(id: string): string {
    const record = CrashReportStore.readRecord(id);
    if (record === null) return '';
    const summary = record.summary;
    const lines: string[] = [
      '轻页崩溃记录',
      `类型：${CrashReportStore.kindLabel(summary.kind)}`,
      `时间：${CrashReportStore.formatTime(summary.time)}`,
      `应用版本：${summary.version || '未知'}`,
      `设备：${record.device}`,
      `系统：${record.os}`,
      `发生时在前台：${summary.foreground ? '是' : '否'}`,
      `摘要：${summary.title}`,
      '',
      '==== 事件详情 ====',
      record.detail
    ];
    if (summary.kind === 'killed' && CrashReportStore.FREEZE_KILL_REASON.test(summary.title)) {
      lines.push('', '说明：这条记录不含堆栈，无法定位卡在哪里。同一次卡死的“卡死”记录会在重新打开应用后一分钟内出现，请分享那一条。');
    }
    if (record.stack) {
      lines.push('', '==== 调用栈 ====', record.stack);
    }
    if (record.trail) {
      lines.push('', '==== 出事前的状态 ====', record.trail);
    }
    const overlimits = CrashReportStore.overlimitsOf(record.pid || 0);
    if (overlimits.length > 0) {
      lines.push('', '==== 系统资源超限预警 ====');
      for (const item of overlimits) {
        lines.push(`${CrashReportStore.formatTime(item.time)}  ${item.type}`, item.detail);
      }
    }
    if (record.hilog.length > 0) {
      lines.push('', '==== 最近日志 ====');
      for (const line of record.hilog) lines.push(line);
    }
    const log = CrashReportStore.readText(CrashReportStore.logPath(id));
    if (log) {
      lines.push('', '==== 系统日志文件 ====', log);
    }
    return lines.join('\n');
  }

  /** 把报告写成 txt 交给系统分享，返回文件路径。 */
  static exportText(context: common.Context, id: string): string {
    const text = CrashReportStore.reportText(id);
    if (!text) throw new Error('崩溃记录已不存在');
    const dir = `${context.cacheDir}/crash_share`;
    if (!fileIo.accessSync(dir)) fileIo.mkdirSync(dir, true);
    const path = `${dir}/qingye-${id}.txt`;
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, text);
    } finally {
      fileIo.closeSync(file);
    }
    return path;
  }

  static remove(id: string): void {
    CrashReportStore.unlinkQuietly(CrashReportStore.jsonPath(id));
    CrashReportStore.unlinkQuietly(CrashReportStore.logPath(id));
    if (AppStorage.get<string>(CrashReportStore.KEY_PENDING_NOTICE) === id) CrashReportStore.clearPendingNotice();
  }

  static clear(): void {
    for (const name of CrashReportStore.listFiles()) {
      if (name.endsWith('.json') || name.endsWith('.log')) {
        CrashReportStore.unlinkQuietly(`${CrashReportStore.dir}/${name}`);
      }
    }
    CrashReportStore.clearPendingNotice();
  }

  static clearPendingNotice(): void {
    AppStorage.setOrCreate(CrashReportStore.KEY_PENDING_NOTICE, '');
    CrashReportStore.unlinkQuietly(`${CrashReportStore.dir}/${CrashReportStore.NOTICE_FILE}`);
  }

  static kindLabel(kind: CrashReportKind): string {
    if (kind === 'freeze') return '卡死';
    if (kind === 'killed') return '被系统结束';
    return '闪退';
  }

  static formatTime(time: number): string {
    const date = new Date(time);
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
      `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
  }

  private static enqueue(name: string, info: hiAppEvent.AppEventInfo): void {
    CrashReportStore.writeChain = CrashReportStore.writeChain
      .then((): Promise<void> => CrashReportStore.save(name, info))
      .catch((error: Error): void => console.warn('保存崩溃记录失败:', error));
  }

  private static async save(name: string, info: hiAppEvent.AppEventInfo): Promise<void> {
    const params = (info.params || {}) as Record<string, Object>;
    if (name === hiAppEvent.event.RESOURCE_OVERLIMIT) {
      CrashReportStore.saveOverlimit(params);
      return;
    }
    const kind: CrashReportKind = name === hiAppEvent.event.APP_FREEZE ? 'freeze' :
      (name === hiAppEvent.event.APP_KILLED ? 'killed' : 'crash');
    if (kind === 'killed' && CrashReportStore.ignoredKill(params)) return;
    const time = CrashReportStore.numberOf(params['time']) || Date.now();
    const id = `${kind}-${time}`;
    CrashReportStore.ensureDir();
    if (fileIo.accessSync(CrashReportStore.jsonPath(id))) return;
    // 卡死的两条事件按同一次运行配对，只留带堆栈的“卡死”：先到的“被系统结束”等对方来了就删，后到的直接不记。
    const runId = CrashReportStore.textOf(params['app_running_unique_id']);
    const freezeKill = kind === 'killed' && CrashReportStore.FREEZE_KILL_REASON.test(CrashReportStore.textOf(params['reason']));
    if (freezeKill && CrashReportStore.sameRunIds('freeze', runId).length > 0) return;

    const foreground = params['foreground'] === true;
    const hasLog = await CrashReportStore.copyExternalLogs(id, params['external_log']);
    const summary: CrashReportSummary = {
      id: id,
      kind: kind,
      time: time,
      foreground: foreground,
      version: CrashReportStore.textOf(params['bundle_version']),
      title: CrashReportStore.titleOf(kind, params),
      hasLog: hasLog
    };
    // 堆栈单独成段按原样换行；留在 JSON 里会变成一整行 \n，没法读。
    let stack = '';
    const detailParams: Record<string, Object> = {};
    for (const key of Object.keys(params)) {
      if (key === 'hilog' || key === 'external_log') continue;
      const value = params[key];
      if (key === 'exception' && value !== null && typeof value === 'object' && !Array.isArray(value)) {
        const exception: Record<string, Object> = {};
        const source = value as Record<string, Object>;
        for (const field of Object.keys(source)) {
          if (field === 'stack' && typeof source[field] === 'string') {
            stack = source[field] as string;
          } else {
            exception[field] = source[field];
          }
        }
        detailParams[key] = exception;
      } else {
        detailParams[key] = value;
      }
    }
    const pid = CrashReportStore.pidOf(params);
    const record: StoredCrashRecord = {
      summary: summary,
      pid: pid,
      trail: CrashContextTrail.describe(pid, time),
      device: `${deviceInfo.marketName || deviceInfo.productModel || ''} (${deviceInfo.productModel || ''})`,
      os: `${deviceInfo.displayVersion || ''} · API ${deviceInfo.sdkApiVersion}`,
      detail: JSON.stringify(detailParams, null, 2),
      stack: stack,
      hilog: CrashReportStore.stringsOf(params['hilog'])
    };
    CrashReportStore.writeText(CrashReportStore.jsonPath(id), JSON.stringify(record));
    if (kind === 'freeze') {
      for (const paired of CrashReportStore.sameRunIds('killed', runId)) CrashReportStore.remove(paired);
    }
    CrashReportStore.trim();
    if (freezeKill) {
      setTimeout((): void => {
        if (fileIo.accessSync(CrashReportStore.jsonPath(id))) CrashReportStore.postNotice(id);
      }, CrashReportStore.FREEZE_PAIR_WAIT_MS);
      return;
    }
    CrashReportStore.postNotice(id);
  }

  /** 事件里的进程号：闪退/卡死在顶层 pid，被系统结束在 last_exit_detail_info.pid。 */
  private static pidOf(params: Record<string, Object>): number {
    const direct = CrashReportStore.numberOf(params['pid']);
    if (direct) return direct;
    const detail = params['last_exit_detail_info'];
    if (detail !== undefined && detail !== null && typeof detail === 'object') {
      return CrashReportStore.numberOf((detail as Record<string, Object>)['pid']);
    }
    return 0;
  }

  /** 系统的资源超限预警（内存泄漏等）：不单独成记录、不弹提示，留着给同一进程后来的崩溃记录参考。 */
  private static saveOverlimit(params: Record<string, Object>): void {
    const item = new StoredOverlimit();
    item.time = CrashReportStore.numberOf(params['time']) || Date.now();
    item.pid = CrashReportStore.pidOf(params);
    item.type = CrashReportStore.textOf(params['resource_type']) || '未知资源';
    const detail: Record<string, Object> = {};
    for (const key of Object.keys(params)) {
      if (key === 'external_log' || key === 'bundle_name' || key === 'bundle_version' || key === 'time' ||
        key === 'pid' || key === 'uid' || key === 'resource_type') continue;
      detail[key] = params[key];
    }
    item.detail = JSON.stringify(detail, null, 2);
    CrashReportStore.ensureDir();
    const list = CrashReportStore.readOverlimits();
    list.push(item);
    const kept = list.slice(Math.max(0, list.length - CrashReportStore.MAX_OVERLIMITS));
    CrashReportStore.writeText(`${CrashReportStore.dir}/${CrashReportStore.OVERLIMIT_FILE}`, JSON.stringify(kept));
  }

  private static overlimitsOf(pid: number): StoredOverlimit[] {
    if (!pid) return [];
    return CrashReportStore.readOverlimits().filter((item: StoredOverlimit): boolean => item.pid === pid);
  }

  private static readOverlimits(): StoredOverlimit[] {
    const text = CrashReportStore.readText(`${CrashReportStore.dir}/${CrashReportStore.OVERLIMIT_FILE}`);
    if (!text) return [];
    try {
      const list = JSON.parse(text) as StoredOverlimit[];
      return Array.isArray(list) ? list : [];
    } catch (error) {
      return [];
    }
  }

  private static postNotice(id: string): void {
    CrashReportStore.writeText(`${CrashReportStore.dir}/${CrashReportStore.NOTICE_FILE}`, id);
    AppStorage.setOrCreate(CrashReportStore.KEY_PENDING_NOTICE, id);
  }

  /** 同一次运行（app_running_unique_id）留下的某类记录；“被系统结束”只认卡死附带的那种。 */
  private static sameRunIds(kind: CrashReportKind, runId: string): string[] {
    const result: string[] = [];
    if (!runId) return result;
    const marker = `"app_running_unique_id": "${runId}"`;
    for (const name of CrashReportStore.listFiles()) {
      if (!name.startsWith(`${kind}-`) || !name.endsWith('.json')) continue;
      const id = name.substring(0, name.length - 5);
      const record = CrashReportStore.readRecord(id);
      if (record === null || !record.detail.includes(marker)) continue;
      if (kind === 'killed' && !CrashReportStore.FREEZE_KILL_REASON.test(record.summary.title)) continue;
      result.push(id);
    }
    return result;
  }

  /**
   * 不记的 APP_KILLED：
   * - 闪退、卡死时系统另发的一条（reason 为 JsError、CppCrash、AppFreeze 等），只有进程号没有堆栈，详情由同一次的
   *   APP_CRASH / APP_FREEZE 给出，记下来会重复，还会抢先弹出“被系统关闭”；
   * - 升级安装（reason 为 Upgrade）、清除任务、强制停止这类正常结束；
   * - 在后台被回收：用户看到的不是闪退。
   */
  private static ignoredKill(params: Record<string, Object>): boolean {
    if (params['foreground'] !== true) return true;
    const reason = CrashReportStore.textOf(params['reason']);
    return CrashReportStore.CRASH_KILL_REASON.test(reason) || CrashReportStore.BENIGN_KILL_REASON.test(reason);
  }

  private static titleOf(kind: CrashReportKind, params: Record<string, Object>): string {
    if (kind === 'killed') {
      return `系统结束了应用：${CrashReportStore.textOf(params['reason']) || '原因未知'}`;
    }
    const exception = params['exception'];
    let title = '';
    if (exception !== undefined && exception !== null && typeof exception === 'object') {
      const record = exception as Record<string, Object>;
      const name = CrashReportStore.textOf(record['name']);
      const message = CrashReportStore.textOf(record['message']).split('\n')[0].trim();
      title = name && message ? `${name}: ${message}` : (name || message);
    }
    if (!title && kind === 'crash') title = CrashReportStore.textOf(params['crash_type']);
    return (title || CrashReportStore.kindLabel(kind)).substring(0, 200);
  }

  /** 复制系统附带的日志文件（系统会滚动删除它们），每个最多 1 MB、最多两个，拼成一个 .log。 */
  private static async copyExternalLogs(id: string, value: Object | undefined): Promise<boolean> {
    const paths = CrashReportStore.stringsOf(value).slice(0, CrashReportStore.MAX_LOG_FILES);
    const parts: string[] = [];
    for (const path of paths) {
      try {
        if (!fileIo.accessSync(path)) continue;
        const size = fileIo.statSync(path).size;
        const length = Math.min(size, CrashReportStore.MAX_LOG_BYTES);
        const buffer = new ArrayBuffer(length);
        const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
        try {
          fileIo.readSync(file.fd, buffer, { offset: 0, length: length });
        } finally {
          fileIo.closeSync(file);
        }
        let text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer));
        if (size > length) text += `\n…（文件共 ${size} 字节，只保留前 ${length} 字节）`;
        parts.push(`---- ${path.substring(path.lastIndexOf('/') + 1)} ----\n${text}`);
      } catch (error) {
        console.warn('复制崩溃日志失败:', error);
      }
    }
    if (parts.length === 0) return false;
    CrashReportStore.writeText(CrashReportStore.logPath(id), parts.join('\n\n'));
    return true;
  }

  private static trim(): void {
    const all = CrashReportStore.list();
    for (let index = CrashReportStore.MAX_REPORTS; index < all.length; index++) {
      CrashReportStore.unlinkQuietly(CrashReportStore.jsonPath(all[index].id));
      CrashReportStore.unlinkQuietly(CrashReportStore.logPath(all[index].id));
    }
  }

  private static restorePendingNotice(): void {
    const id = CrashReportStore.readText(`${CrashReportStore.dir}/${CrashReportStore.NOTICE_FILE}`).trim();
    if (id && fileIo.accessSync(CrashReportStore.jsonPath(id))) {
      AppStorage.setOrCreate(CrashReportStore.KEY_PENDING_NOTICE, id);
    }
  }

  private static readRecord(id: string): StoredCrashRecord | null {
    const text = CrashReportStore.readText(CrashReportStore.jsonPath(id));
    if (!text) return null;
    try {
      const record = JSON.parse(text) as StoredCrashRecord;
      return record && record.summary ? record : null;
    } catch (error) {
      return null;
    }
  }

  private static listFiles(): string[] {
    try {
      return CrashReportStore.dir && fileIo.accessSync(CrashReportStore.dir) ?
        fileIo.listFileSync(CrashReportStore.dir) : [];
    } catch (error) {
      return [];
    }
  }

  private static ensureDir(): void {
    if (!fileIo.accessSync(CrashReportStore.dir)) fileIo.mkdirSync(CrashReportStore.dir, true);
  }

  private static jsonPath(id: string): string {
    return `${CrashReportStore.dir}/${id}.json`;
  }

  private static logPath(id: string): string {
    return `${CrashReportStore.dir}/${id}.log`;
  }

  private static readText(path: string): string {
    try {
      return fileIo.accessSync(path) ? fileIo.readTextSync(path) : '';
    } catch (error) {
      return '';
    }
  }

  private static writeText(path: string, text: string): void {
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, text);
    } finally {
      fileIo.closeSync(file);
    }
  }

  private static unlinkQuietly(path: string): void {
    try {
      if (fileIo.accessSync(path)) fileIo.unlinkSync(path);
    } catch (error) {
      console.warn('删除崩溃记录文件失败:', error);
    }
  }

  private static textOf(value: Object | undefined): string {
    if (value === undefined || value === null) return '';
    return typeof value === 'string' ? value : String(value);
  }

  private static numberOf(value: Object | undefined): number {
    const number = Number(value);
    return Number.isFinite(number) && number > 0 ? number : 0;
  }

  private static stringsOf(value: Object | undefined): string[] {
    if (!Array.isArray(value)) return [];
    return (value as Object[]).map((item: Object): string => CrashReportStore.textOf(item));
  }
}

interface StoredCrashRecord {
  summary: CrashReportSummary;
  device: string;
  os: string;
  detail: string;
  /** 旧记录没有这个字段。 */
  stack?: string;
  hilog: string[];
  /** 出事进程号与那次运行的状态摘要（CrashContextTrail）；旧记录没有。 */
  pid?: number;
  trail?: string;
}

class StoredOverlimit {
  time: number = 0;
  pid: number = 0;
  type: string = '';
  detail: string = '';
}
