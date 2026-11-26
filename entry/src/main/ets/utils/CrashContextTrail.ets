import { bundleManager, common } from '@kit.AbilityKit';
import { UIContext, uiObserver } from '@kit.ArkUI';
import { hidebug } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { process } from '@kit.ArkTS';

class TrailPage {
  t: number = 0;
  name: string = '';
}

class TrailMemory {
  t: number = 0;
  /** 进程常驻内存（/proc/self/status 的 VmRSS），KB。 */
  rss: number = 0;
  /** ArkTS 堆已用，KB。 */
  js: number = 0;
}

class TrailMark {
  key: string = '';
  value: string = '';
  t: number = 0;
}

class TrailRecord {
  pid: number = 0;
  startedAt: number = 0;
  updatedAt: number = 0;
  version: string = '';
  rssLimit: number = 0;
  peakRss: number = 0;
  pages: TrailPage[] = [];
  memory: TrailMemory[] = [];
  marks: TrailMark[] = [];
}

/**
 * 运行状态记录：最近进过的页面、正在用的大内存功能（离线音色、AI 字幕等）、每 10 秒一次的内存采样。
 * 被系统结束（内存超限、卡死）的事件不带堆栈，下次启动时 CrashReportStore 按进程号取出那次运行的记录附进崩溃记录，
 * 才能看出当时在做什么、内存是怎么涨上去的。只存本机（filesDir/crash_reports/trails），最多留最近几次运行。
 */
export class CrashContextTrail {
  private static readonly DIR_NAME: string = 'crash_reports/trails';
  private static readonly SAMPLE_MS: number = 10000;
  private static readonly MAX_PAGES: number = 12;
  private static readonly MAX_SAMPLES: number = 30;
  private static readonly MAX_TRAILS: number = 5;
  private static dir: string = '';
  private static record: TrailRecord = new TrailRecord();
  private static started: boolean = false;
  private static writeTimer: number = -1;
  private static watchedContexts: UIContext[] = [];

  static start(context: common.UIAbilityContext): void {
    if (CrashContextTrail.started) return;
    CrashContextTrail.started = true;
    CrashContextTrail.dir = `${context.filesDir}/${CrashContextTrail.DIR_NAME}`;
    const record = CrashContextTrail.record;
    record.pid = process.pid;
    record.startedAt = Date.now();
    try {
      record.version = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
        .versionName || '';
    } catch (error) {
      record.version = '';
    }
    try {
      // 没有限制时系统给的是一个极大值（2^54），当作未知。
      const limit = Number(hidebug.getAppMemoryLimit().rssLimit);
      record.rssLimit = limit > 0 && limit < 1024 * 1024 * 1024 ? limit : 0;
    } catch (error) {
      record.rssLimit = 0;
    }
    try {
      if (!fileIo.accessSync(CrashContextTrail.dir)) fileIo.mkdirSync(CrashContextTrail.dir, true);
    } catch (error) {
      console.warn('创建运行状态目录失败:', error);
    }
    CrashContextTrail.prune();
    CrashContextTrail.sample();
    setInterval((): void => CrashContextTrail.sample(), CrashContextTrail.SAMPLE_MS);
  }

  /** 页面切换记录。主窗口 loadContent 成功后调用。 */
  static watchPages(uiContext: UIContext): void {
    if (CrashContextTrail.watchedContexts.indexOf(uiContext) >= 0) return;
    CrashContextTrail.watchedContexts.push(uiContext);
    try {
      uiObserver.on('routerPageUpdate', uiContext, (info: uiObserver.RouterPageInfo): void => {
        if (info.state !== uiObserver.RouterPageState.ON_PAGE_SHOW) return;
        const pages = CrashContextTrail.record.pages;
        const name = info.name || info.path || '';
        if (pages.length > 0 && pages[pages.length - 1].name === name) return;
        const page = new TrailPage();
        page.t = Date.now();
        page.name = name;
        pages.push(page);
        if (pages.length > CrashContextTrail.MAX_PAGES) pages.splice(0, pages.length - CrashContextTrail.MAX_PAGES);
        CrashContextTrail.scheduleWrite();
      });
    } catch (error) {
      console.warn('订阅页面切换失败:', error);
    }
  }

  /** 登记正在用的功能，value 为空表示结束。例如 mark('离线音色', '超文')、mark('离线音色', '')。 */
  static mark(key: string, value: string): void {
    const marks = CrashContextTrail.record.marks;
    const index = marks.findIndex((item: TrailMark): boolean => item.key === key);
    if (!value) {
      if (index < 0) return;
      marks.splice(index, 1);
    } else {
      const mark = index >= 0 ? marks[index] : new TrailMark();
      if (index >= 0 && mark.value === value) return;
      mark.key = key;
      mark.value = value;
      mark.t = Date.now();
      if (index < 0) marks.push(mark);
    }
    CrashContextTrail.scheduleWrite();
  }

  /** 进后台时立即落盘：在后台被结束时定时器可能已经不跑了。 */
  static flush(): void {
    CrashContextTrail.sample();
  }

  /**
   * 某次运行（按进程号）的可读摘要，给崩溃记录用；当前这次运行或找不到时返回空串。
   * eventTime 用来排除进程号被后来的运行复用的情况。
   */
  static describe(pid: number, eventTime: number): string {
    if (!pid || pid === process.pid || !CrashContextTrail.dir) return '';
    let record: TrailRecord;
    try {
      const path = CrashContextTrail.pathOf(pid);
      if (!fileIo.accessSync(path)) return '';
      record = JSON.parse(fileIo.readTextSync(path)) as TrailRecord;
    } catch (error) {
      return '';
    }
    if (!record || !record.startedAt || (eventTime > 0 && record.startedAt > eventTime)) return '';
    return CrashContextTrail.format(record);
  }

  static format(record: TrailRecord): string {
    const lines: string[] = [];
    lines.push(`运行开始：${CrashContextTrail.time(record.startedAt)}（版本 ${record.version || '未知'}，进程 ${record.pid}）`);
    lines.push(`最后记录：${CrashContextTrail.time(record.updatedAt)}`);
    const limit = record.rssLimit > 0 ? `，系统上限 ${CrashContextTrail.mb(record.rssLimit)}` : '';
    lines.push(`内存峰值：${CrashContextTrail.mb(record.peakRss)}${limit}`);
    if (record.memory && record.memory.length > 0) {
      lines.push('内存采样（常驻 / ArkTS 堆）：');
      for (const item of record.memory) {
        lines.push(`  ${CrashContextTrail.clock(item.t)}  ${CrashContextTrail.mb(item.rss)} / ${CrashContextTrail.mb(item.js)}`);
      }
    }
    if (record.marks && record.marks.length > 0) {
      lines.push('正在用：');
      for (const mark of record.marks) {
        lines.push(`  ${mark.key}：${mark.value}（${CrashContextTrail.clock(mark.t)} 起）`);
      }
    }
    if (record.pages && record.pages.length > 0) {
      lines.push('最近的页面：');
      for (const page of record.pages) {
        lines.push(`  ${CrashContextTrail.clock(page.t)}  ${page.name}`);
      }
    }
    return lines.join('\n');
  }

  private static sample(): void {
    const record = CrashContextTrail.record;
    const item = new TrailMemory();
    item.t = Date.now();
    item.rss = CrashContextTrail.readRssKb();
    try {
      item.js = Number(hidebug.getAppVMMemoryInfo().heapUsed);
    } catch (error) {
      item.js = 0;
    }
    record.memory.push(item);
    if (record.memory.length > CrashContextTrail.MAX_SAMPLES) {
      record.memory.splice(0, record.memory.length - CrashContextTrail.MAX_SAMPLES);
    }
    if (item.rss > record.peakRss) record.peakRss = item.rss;
    CrashContextTrail.write();
  }

  private static readRssKb(): number {
    try {
      const match = /VmRSS:\s*(\d+)/.exec(fileIo.readTextSync('/proc/self/status'));
      if (match) return Number(match[1]);
    } catch (error) {
      // 读不到就用 hidebug（API 24 起），再不行记 0。
    }
    try {
      return Number(hidebug.getRssInfo().rss);
    } catch (error) {
      return 0;
    }
  }

  private static scheduleWrite(): void {
    if (CrashContextTrail.writeTimer >= 0) return;
    CrashContextTrail.writeTimer = setTimeout((): void => {
      CrashContextTrail.writeTimer = -1;
      CrashContextTrail.write();
    }, 1000);
  }

  private static write(): void {
    if (!CrashContextTrail.dir) return;
    if (CrashContextTrail.writeTimer >= 0) {
      clearTimeout(CrashContextTrail.writeTimer);
      CrashContextTrail.writeTimer = -1;
    }
    const record = CrashContextTrail.record;
    record.updatedAt = Date.now();
    try {
      const file = fileIo.openSync(CrashContextTrail.pathOf(record.pid),
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, JSON.stringify(record));
      } finally {
        fileIo.closeSync(file);
      }
    } catch (error) {
      console.warn('写运行状态失败:', error);
    }
  }

  /** 只留最近几次运行的记录（按修改时间）。 */
  private static prune(): void {
    try {
      const names = fileIo.listFileSync(CrashContextTrail.dir)
        .filter((name: string): boolean => name.startsWith('trail-') && name.endsWith('.json'));
      if (names.length < CrashContextTrail.MAX_TRAILS) return;
      const dated = names.map((name: string): [string, number] => {
        try {
          return [name, fileIo.statSync(`${CrashContextTrail.dir}/${name}`).mtime];
        } catch (error) {
          return [name, 0];
        }
      });
      dated.sort((a: [string, number], b: [string, number]): number => b[1] - a[1]);
      for (let i = CrashContextTrail.MAX_TRAILS - 1; i < dated.length; i++) {
        fileIo.unlinkSync(`${CrashContextTrail.dir}/${dated[i][0]}`);
      }
    } catch (error) {
      console.warn('清理运行状态失败:', error);
    }
  }

  private static pathOf(pid: number): string {
    return `${CrashContextTrail.dir}/trail-${pid}.json`;
  }

  private static mb(kb: number): string {
    return kb > 0 ? `${Math.round(kb / 1024)} MB` : '未知';
  }

  private static pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private static clock(time: number): string {
    const date = new Date(time);
    return `${CrashContextTrail.pad(date.getHours())}:${CrashContextTrail.pad(date.getMinutes())}:` +
      `${CrashContextTrail.pad(date.getSeconds())}`;
  }

  private static time(time: number): string {
    if (!time) return '未知';
    const date = new Date(time);
    return `${date.getMonth() + 1}-${date.getDate()} ${CrashContextTrail.clock(time)}`;
  }
}
