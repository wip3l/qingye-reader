import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { BookReadStats, BookReadStatsCalendarCell, BookReadStatsDay, BookReadStatsMonth,
  BookReadStatsSession, BookReadStatsTimelineDay } from '../../core/stats/BookReadStats';
import { BookReadStatsSnapshot } from '../../core/stats/BookReadStatsLoader';

interface BookReadStatsMetric {
  icon: Resource;
  label: string;
  /** 交替的数字与单位。 */
  parts: string[];
  sub: string;
}

/**
 * 书籍详情页“统计”页签的内容：六格数字，下面按每日、日历、时间线三种方式看阅读记录。
 * 只负责显示，数据由宿主用 BookReadStatsLoader 读好传进来；自身不滚动，跟着详情页滚。
 */
@Component
export struct BookReadStatsPanel {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @Prop @Watch('onSnapshotChanged') snapshot: BookReadStatsSnapshot = new BookReadStatsSnapshot();
  /** 进度的单位：章、集或页。 */
  @Prop chapterUnit: string = '章';

  @State view: number = 0;
  /** 收起的月份；默认只展开最近一个月。 */
  @State collapsedMonths: string[] = [];
  @State calendarYear: number = 0;
  @State calendarMonth: number = 0;
  @State selectedDayKey: string = '';
  /** 上次按哪些月份摆的默认展开与日历月份；月份没变时重读数据不打乱用户的选择。 */
  private monthsSignature: string = '';
  private static readonly VIEWS: string[] = ['每日', '日历', '时间线'];
  private static readonly WEEKDAYS: string[] = ['一', '二', '三', '四', '五', '六', '日'];

  aboutToAppear(): void {
    this.onSnapshotChanged();
  }

  onSnapshotChanged(): void {
    const months = this.snapshot.stats.months;
    const signature = months.map((month: BookReadStatsMonth): string => month.key).join(',');
    if (signature === this.monthsSignature && this.calendarYear > 0) return;
    this.monthsSignature = signature;
    this.collapsedMonths = months.slice(1).map((month: BookReadStatsMonth): string => month.key);
    const now = new Date();
    this.calendarYear = months.length > 0 ? months[0].year : now.getFullYear();
    this.calendarMonth = months.length > 0 ? months[0].month : now.getMonth() + 1;
    this.selectedDayKey = '';
  }

  private primary(): string {
    return ThemeRuntime.primaryTextColor(this.darkMode);
  }

  private sub(): string {
    return ThemeRuntime.subTextColor(this.darkMode);
  }

  private accent(): string {
    return ThemeRuntime.accentColor(this.darkMode);
  }

  /** 强调色加透明度，alpha 为两位十六进制。 */
  private accentTint(alpha: string): string {
    return `#${alpha}${this.accent().substring(1)}`;
  }

  private hasProgress(): boolean {
    return this.snapshot.chapterIndex >= 0 && this.snapshot.chapterTotal > 0;
  }

  private progressParts(): string[] {
    if (!this.hasProgress()) return ['—', ''];
    return [`${Math.min(this.snapshot.chapterIndex + 1, this.snapshot.chapterTotal)}`,
      `/ ${this.snapshot.chapterTotal} ${this.chapterUnit}`];
  }

  private progressSub(): string {
    if (!this.hasProgress()) return '当前书源还没开始读';
    const percent = Math.min(100, (this.snapshot.chapterIndex + 1) * 100 / this.snapshot.chapterTotal);
    return `按${this.chapterUnit}数 ${percent >= 100 ? '100' : percent.toFixed(1)}%`;
  }

  private annotationSub(): string {
    const counts = this.snapshot.annotationCounts;
    if (counts[0] <= 0) return '还没有划线';
    const parts: string[] = [];
    if (counts[1] > 0) parts.push(`${counts[1]} 个想法`);
    if (counts[2] > 0) parts.push(`${counts[2]} 条摘录`);
    return parts.length > 0 ? parts.join(' · ') : '只有划线';
  }

  build() {
    Column() {
      Column({ space: AppSpacing.XL }) {
        Row({ space: AppSpacing.LG }) {
          this.metric({
            icon: $r('sys.symbol.clock'),
            label: '累计时长',
            parts: BookReadStats.durationParts(this.snapshot.stats.totalMs),
            sub: `${BookReadStats.shortDate(this.snapshot.stats.firstDayKey)} 开始阅读`
          })
          this.metric({
            icon: $r('sys.symbol.calendar'),
            label: '阅读天数',
            parts: [`${this.snapshot.stats.activeDays}`, '天'],
            sub: `上次阅读 · ${BookReadStats.shortDate(this.snapshot.stats.lastDayKey)}`
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Row({ space: AppSpacing.LG }) {
          this.metric({
            icon: $r('sys.symbol.book_pages'),
            label: '阅读进度',
            parts: this.progressParts(),
            sub: this.progressSub()
          })
          this.metric({
            icon: $r('sys.symbol.star'),
            label: '单日最久',
            parts: BookReadStats.durationParts(this.snapshot.stats.bestDayMs),
            sub: BookReadStats.shortDate(this.snapshot.stats.bestDayKey)
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Row({ space: AppSpacing.LG }) {
          this.metric({
            icon: $r('sys.symbol.doc_text'),
            label: '划线与笔记',
            parts: [`${this.snapshot.annotationCounts[0]}`, '条'],
            sub: this.annotationSub()
          })
          this.metric({
            icon: $r('sys.symbol.timer'),
            label: '日均时长',
            parts: BookReadStats.durationParts(this.snapshot.stats.totalMs /
              Math.max(1, this.snapshot.stats.activeDays)),
            sub: '按阅读的日子平均'
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
      // 六格数字聚在一块浅底里，和下面的阅读记录分成上下两段；简介、标记页签不加底。
      .width('100%')
      .padding(AppSpacing.XL)
      .margin({ top: AppSpacing.LG })
      .borderRadius(ThemeRuntime.largeRadius())
      .backgroundColor(ThemeRuntime.softFillColor(this.darkMode))

      Row({ space: AppSpacing.MD }) {
        ForEach(BookReadStatsPanel.VIEWS, (label: string, index: number) => {
          Text(label)
            .fontSize(AppFontSize.BODY)
            .fontWeight(this.view === index ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.view === index ? this.accent() : this.sub())
            .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.XS, bottom: AppSpacing.XS })
            .borderRadius(14)
            .backgroundColor(this.view === index ? ThemeRuntime.accentSurfaceColor(this.darkMode) :
              ThemeRuntime.softFillColor(this.darkMode))
            .onClick(() => {
              this.view = index;
            })
        }, (label: string): string => label)
      }
      .width('100%')
      .padding({ top: AppSpacing.LG, bottom: AppSpacing.SM })

      if (this.view === 0) {
        this.monthsPanel()
      } else if (this.view === 1) {
        this.calendarPanel()
      } else {
        this.timelinePanel()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  metric(item: BookReadStatsMetric) {
    Column({ space: AppSpacing.XXS }) {
      Row({ space: AppSpacing.XS }) {
        SymbolGlyph(item.icon)
          .fontSize(14)
          .fontColor([this.sub()])
        Text(item.label)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.sub())
      }
      .alignItems(VerticalAlign.Center)
      Text() {
        ForEach(item.parts, (part: string, index: number) => {
          Span(index % 2 === 0 ? part : ` ${part} `)
            .fontSize(index % 2 === 0 ? AppFontSize.HEADLINE : AppFontSize.CAPTION)
            .fontWeight(index % 2 === 0 ? FontWeight.Medium : FontWeight.Normal)
        }, (part: string, index: number): string => `${index}:${part}`)
      }
      .fontColor(this.primary())
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(item.sub)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.sub())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  private monthExpanded(key: string): boolean {
    return !this.collapsedMonths.includes(key);
  }

  private toggleMonth(key: string): void {
    this.collapsedMonths = this.monthExpanded(key) ? this.collapsedMonths.concat([key]) :
      this.collapsedMonths.filter((item: string): boolean => item !== key);
  }

  @Builder
  monthsPanel() {
    ForEach(this.snapshot.stats.months, (month: BookReadStatsMonth) => {
      Column() {
        Row({ space: AppSpacing.SM }) {
          Text(`${month.year} 年 ${month.month} 月 · ${BookReadStats.durationText(month.totalMs)} · ${month.days.length} 天`)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.sub())
            .layoutWeight(1)
          SymbolGlyph(this.monthExpanded(month.key) ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([this.sub()])
        }
        .width('100%')
        .height(40)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.toggleMonth(month.key);
        })

        if (this.monthExpanded(month.key)) {
          ForEach(month.days, (day: BookReadStatsDay) => {
            this.dayBar(day, month.maxMs)
          }, (day: BookReadStatsDay): string => `${day.dayKey}:${day.durationMs}`)
        }
      }
      .width('100%')
      .margin({ bottom: AppSpacing.SM })
    }, (month: BookReadStatsMonth): string => `${month.key}:${month.totalMs}`)
  }

  @Builder
  dayBar(day: BookReadStatsDay, maxMs: number) {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width(`${Math.max(2, Math.round(day.durationMs * 100 / Math.max(1, maxMs)))}%`)
        .height('100%')
        .borderRadius(8)
        .backgroundColor(this.accentTint(this.darkMode ? '59' : '40'))
      Row() {
        Text(`${day.day} 日`)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primary())
        Blank()
        Text(BookReadStats.durationText(day.durationMs))
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primary())
      }
      .width('100%')
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    }
    .width('100%')
    .height(34)
    .borderRadius(8)
    .backgroundColor(ThemeRuntime.softFillColor(this.darkMode))
    .margin({ bottom: AppSpacing.SM })
    .accessibilityGroup(true)
    .accessibilityText(`${day.dayKey}，${BookReadStats.durationText(day.durationMs)}`)
  }

  private calendarSource(): BookReadStatsMonth | null {
    const found = this.snapshot.stats.months.find((month: BookReadStatsMonth): boolean =>
      month.year === this.calendarYear && month.month === this.calendarMonth);
    return found ? found : null;
  }

  private monthIndex(year: number, month: number): number {
    return year * 12 + month - 1;
  }

  private canShiftCalendar(step: number): boolean {
    const target = this.monthIndex(this.calendarYear, this.calendarMonth) + step;
    const now = new Date();
    let first = this.monthIndex(now.getFullYear(), now.getMonth() + 1);
    if (this.snapshot.stats.months.length > 0) {
      const oldest = this.snapshot.stats.months[this.snapshot.stats.months.length - 1];
      first = Math.min(first, this.monthIndex(oldest.year, oldest.month));
    }
    return target >= first && target <= this.monthIndex(now.getFullYear(), now.getMonth() + 1);
  }

  private shiftCalendar(step: number): void {
    if (!this.canShiftCalendar(step)) return;
    const target = this.monthIndex(this.calendarYear, this.calendarMonth) + step;
    this.calendarYear = Math.floor(target / 12);
    this.calendarMonth = target % 12 + 1;
    this.selectedDayKey = '';
  }

  private calendarHint(): string {
    const source = this.calendarSource();
    if (this.selectedDayKey) {
      const day = source ? source.days.find((item: BookReadStatsDay): boolean => item.dayKey === this.selectedDayKey) : undefined;
      return `${BookReadStats.shortDate(this.selectedDayKey)} · ${day ? BookReadStats.durationText(day.durationMs) : '没有阅读'}`;
    }
    if (!source) return '这个月没有阅读记录';
    return `本月 ${BookReadStats.durationText(source.totalMs)} · ${source.days.length} 天 · 点某天看当天时长`;
  }

  private cellColor(level: number): string {
    if (level <= 0) return ThemeRuntime.softFillColor(this.darkMode);
    return this.accentTint(['33', '66', '99', 'CC'][Math.min(4, level) - 1]);
  }

  @Builder
  calendarPanel() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(16)
        .fontColor([this.canShiftCalendar(-1) ? this.primary() : ThemeRuntime.softFillColor(this.darkMode)])
        .padding(AppSpacing.MD)
        .accessibilityText('上个月')
        .onClick(() => {
          this.shiftCalendar(-1);
        })
      Text(`${this.calendarYear} 年 ${this.calendarMonth} 月`)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primary())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([this.canShiftCalendar(1) ? this.primary() : ThemeRuntime.softFillColor(this.darkMode)])
        .padding(AppSpacing.MD)
        .accessibilityText('下个月')
        .onClick(() => {
          this.shiftCalendar(1);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)

    GridRow({ columns: 7, gutter: AppSpacing.SM }) {
      ForEach(BookReadStatsPanel.WEEKDAYS, (label: string) => {
        GridCol() {
          Text(label)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.sub())
            .textAlign(TextAlign.Center)
            .width('100%')
        }
      }, (label: string): string => label)
      ForEach(BookReadStats.calendar(this.calendarYear, this.calendarMonth, this.calendarSource()),
        (cell: BookReadStatsCalendarCell, index: number) => {
          GridCol() {
            if (cell.day > 0) {
              Text(`${cell.day}`)
                .fontSize(AppFontSize.BODY)
                .fontColor(cell.level > 0 ? this.primary() : this.sub())
                .textAlign(TextAlign.Center)
                .width('100%')
                .aspectRatio(1)
                .borderRadius(10)
                .backgroundColor(this.cellColor(cell.level))
                .border({ width: 1.5,
                  color: this.selectedDayKey === cell.dayKey ? this.accent() : Color.Transparent })
                .accessibilityText(`${cell.dayKey}，${cell.durationMs > 0 ?
                  BookReadStats.durationText(cell.durationMs) : '没有阅读'}`)
                .onClick(() => {
                  this.selectedDayKey = this.selectedDayKey === cell.dayKey ? '' : cell.dayKey;
                })
            }
          }
        }, (cell: BookReadStatsCalendarCell, index: number): string =>
          `${this.calendarYear}-${this.calendarMonth}-${index}:${cell.durationMs}`)
    }
    .width('100%')
    .margin({ top: AppSpacing.SM })

    Text(this.calendarHint())
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.sub())
      .width('100%')
      .margin({ top: AppSpacing.LG })
  }

  @Builder
  timelinePanel() {
    ForEach(this.snapshot.stats.timeline, (day: BookReadStatsTimelineDay) => {
      Row({ space: AppSpacing.LG }) {
        Text(BookReadStats.monthDay(day.dayKey))
          .fontSize(AppFontSize.BODY)
          .fontColor(this.sub())
          .width(48)
        Column({ space: AppSpacing.XS }) {
          ForEach(day.sessions, (session: BookReadStatsSession) => {
            Text(BookReadStats.sessionText(session))
              .fontSize(AppFontSize.BODY)
              .fontColor(this.primary())
          }, (session: BookReadStatsSession, index: number): string =>
            `${index}:${session.startTs}:${session.durationMs}`)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: AppSpacing.LG, bottom: AppSpacing.LG })
      .border({ width: { bottom: 0.5 }, color: ThemeRuntime.hairlineColor(this.darkMode) })
    }, (day: BookReadStatsTimelineDay): string => `${day.dayKey}:${day.sessions.length}`)

    Text(this.snapshot.stats.timelineTruncated ?
      `只列出最近 ${BookReadStats.TIMELINE_DAY_LIMIT} 个阅读日；间隔 5 分钟内的记录并成一段` : '间隔 5 分钟内的记录并成一段')
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.sub())
      .width('100%')
      .margin({ top: AppSpacing.LG })
  }
}
