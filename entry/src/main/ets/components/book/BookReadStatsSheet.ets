import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { BookReadStats, BookReadStatsCalendarCell, BookReadStatsDay, BookReadStatsMonth,
  BookReadStatsSession, BookReadStatsTimelineDay } from '../../core/stats/BookReadStats';

/**
 * 单本书阅读统计的详情面板内容，材质交给宿主 bindSheet。
 * 三个页签：按月的每日时长、月历、合并成段的时间线。
 */
@Component
export struct BookReadStatsSheet {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  stats: BookReadStats = new BookReadStats();
  bookName: string = '';

  @State tab: number = 0;
  /** 收起的月份；默认只展开最近一个月。 */
  @State collapsedMonths: string[] = [];
  @State calendarYear: number = 0;
  @State calendarMonth: number = 0;
  @State selectedDayKey: string = '';
  private static readonly TABS: string[] = ['统计', '日历', '时间线'];
  private static readonly WEEKDAYS: string[] = ['一', '二', '三', '四', '五', '六', '日'];

  aboutToAppear(): void {
    this.collapsedMonths = this.stats.months.slice(1).map((month: BookReadStatsMonth): string => month.key);
    const latest = this.stats.months.length > 0 ? this.stats.months[0] : null;
    const now = new Date();
    this.calendarYear = latest ? latest.year : now.getFullYear();
    this.calendarMonth = latest ? latest.month : now.getMonth() + 1;
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

  build() {
    Column() {
      Column({ space: AppSpacing.XXS }) {
        Text('阅读统计')
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primary())
        Text(`${this.bookName ? `${this.bookName} · ` : ''}累计 ${BookReadStats.durationText(this.stats.totalMs)} · ${this.stats.activeDays} 天`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.sub())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: AppSpacing.XXL, right: AppSpacing.XXL, top: AppSpacing.XL })

      Row({ space: AppSpacing.XXL }) {
        ForEach(BookReadStatsSheet.TABS, (label: string, index: number) => {
          Column({ space: AppSpacing.XS }) {
            Text(label)
              .fontSize(AppFontSize.BODY_LARGE)
              .fontWeight(this.tab === index ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.tab === index ? this.primary() : this.sub())
            Row()
              .width(20)
              .height(2)
              .borderRadius(1)
              .backgroundColor(this.tab === index ? this.accent() : Color.Transparent)
          }
          .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM })
          .accessibilityText(label)
          .onClick(() => {
            this.tab = index;
          })
        }, (label: string): string => label)
      }
      .width('100%')
      .padding({ left: AppSpacing.XXL, right: AppSpacing.XXL, top: AppSpacing.MD })

      Scroll() {
        Column() {
          if (this.tab === 0) {
            this.monthsPanel()
          } else if (this.tab === 1) {
            this.calendarPanel()
          } else {
            this.timelinePanel()
          }
        }
        .width('100%')
        .padding({ left: AppSpacing.XXL, right: AppSpacing.XXL, top: AppSpacing.SM,
          bottom: AppSpacing.XXXL + this.navBarHeight })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
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
    ForEach(this.stats.months, (month: BookReadStatsMonth) => {
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
    const found = this.stats.months.find((month: BookReadStatsMonth): boolean =>
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
    if (this.stats.months.length > 0) {
      const oldest = this.stats.months[this.stats.months.length - 1];
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
      ForEach(BookReadStatsSheet.WEEKDAYS, (label: string) => {
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
    ForEach(this.stats.timeline, (day: BookReadStatsTimelineDay) => {
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

    Text(this.stats.timelineTruncated ?
      `只列出最近 ${BookReadStats.TIMELINE_DAY_LIMIT} 个阅读日；间隔 5 分钟内的记录并成一段` : '间隔 5 分钟内的记录并成一段')
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.sub())
      .width('100%')
      .margin({ top: AppSpacing.LG })
  }
}
