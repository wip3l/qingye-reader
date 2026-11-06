import { appDb, ReadStatsRow } from '../../model/data/AppDatabase';
import { readStatsTracker } from '../../core/stats/ReadStatsTracker';
import { ReadStatsSummary } from '../../core/stats/ReadStatsSummary';
import { AccountSessionStore } from '../../account/AccountSessionStore';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

const NOTE_WEEK_DAYS = 7;
/** 连续天数往回最多查这么多天；再长也只显示到这个数，避免每次回书架都扫全量记录。 */
const NOTE_STREAK_LOOKBACK_DAYS = 60;
const NOTE_BAR_MAX_HEIGHT = 30;

/** 陪伴布局里的“阅读小记”：今日时长、近 7 天柱条与连续阅读天数，统计口径与阅读统计页的全部设备一致。 */
@Component
export struct ShelfReadingNoteCard {
  /** 最近阅读的书或进度一变就重读统计，回书架时能带上刚读的时长。 */
  @Prop @Watch('onRefreshKeyChanged') refreshKey: string = '';
  @Prop appDarkMode: boolean = false;
  @StorageProp('accountUserId') @Watch('onRefreshKeyChanged') accountUserId: string = '';
  @State todayMs: number = 0;
  @State weekMs: number = 0;
  @State streakDays: number = 0;
  @State dayMs: number[] = [0, 0, 0, 0, 0, 0, 0];
  private loadVersion: number = 0;
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.alive = false;
  }

  onRefreshKeyChanged(): void {
    this.load();
  }

  async load(): Promise<void> {
    const version = ++this.loadVersion;
    try {
      const context = getContext(this);
      await appDb.init(context);
      await AccountSessionStore.load(context);
      await readStatsTracker.flushAndWait();
      const ownerId = AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : '';
      const now = Date.now();
      const today = new Date(now);
      const start = new Date(today.getFullYear(), today.getMonth(), today.getDate() - NOTE_STREAK_LOOKBACK_DAYS + 1);
      const rows = await appDb.getReadStatsByDayRange(ReadStatsSummary.dayKey(start.getTime()),
        ReadStatsSummary.dayKey(now), '', ownerId);
      if (!this.alive || version !== this.loadVersion) return;
      this.applyRows(rows, today);
    } catch (error) {
      console.warn('读取阅读小记失败:', error);
    }
  }

  applyRows(rows: ReadStatsRow[], today: Date): void {
    const byDay = new Map<string, number>();
    rows.forEach((row: ReadStatsRow): void => {
      if (row.durationMs > 0) byDay.set(row.dayKey, (byDay.get(row.dayKey) ?? 0) + row.durationMs);
    });
    const dayKeyAt = (offset: number): string => ReadStatsSummary.dayKey(
      new Date(today.getFullYear(), today.getMonth(), today.getDate() - offset).getTime());
    const week: number[] = [];
    for (let offset = NOTE_WEEK_DAYS - 1; offset >= 0; offset--) week.push(byDay.get(dayKeyAt(offset)) ?? 0);
    // 今天还没读不算断：从昨天往回数，读过一页就续上。
    let streak = 0;
    for (let offset = (byDay.get(dayKeyAt(0)) ?? 0) > 0 ? 0 : 1; offset < NOTE_STREAK_LOOKBACK_DAYS; offset++) {
      if ((byDay.get(dayKeyAt(offset)) ?? 0) <= 0) break;
      streak++;
    }
    this.dayMs = week;
    this.todayMs = week[week.length - 1];
    // 问候语的 {今日阅读} 用同一个数，不再另查一遍统计。
    AppStorage.setOrCreate('shelfTodayReadMs', this.todayMs);
    this.weekMs = week.reduce((sum: number, value: number): number => sum + value, 0);
    this.streakDays = streak;
  }

  todayMinutesText(): string {
    return `${Math.floor(this.todayMs / 60000)}`;
  }

  summaryText(): string {
    if (this.weekMs <= 0) return '这几天还没翻书，挑一本慢慢读吧';
    const week = `近 7 天 ${ReadStatsSummary.duration(this.weekMs)}`;
    return this.streakDays >= 2 ? `${week} · 已连续读了 ${this.streakDays} 天` : week;
  }

  barHeight(value: number): number {
    const peak = Math.max(...this.dayMs, 30 * 60000);
    return value <= 0 ? 4 : Math.max(6, Math.round(value / peak * NOTE_BAR_MAX_HEIGHT));
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  hairlineColor(): string {
    return this.appDarkMode ? '#1FFFFFFF' : '#14000000';
  }

  build() {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.SM }) {
        SymbolGlyph($r('sys.symbol.book_pages'))
          .fontSize(18)
          .fontColor([this.accentColor()])
        Text('阅读小记')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.accentColor())
        Blank()
        Text('阅读统计')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([this.subTextColor()])
      }
      .width('100%')

      Row({ space: AppSpacing.LG }) {
        Column({ space: 2 }) {
          Text('今日阅读')
            .fontSize(AppFontSize.MICRO)
            .fontColor(this.subTextColor())
          Row({ space: 4 }) {
            Text(this.todayMinutesText())
              .fontSize(AppFontSize.DISPLAY)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.accentColor())
            Text('分钟')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
          }
          .alignItems(VerticalAlign.Bottom)
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ right: AppSpacing.LG })
        .border({ width: { right: 1 }, color: this.hairlineColor() })

        Column() {
          Row({ space: 6 }) {
            ForEach(this.dayMs, (value: number, index: number) => {
              Column()
                .layoutWeight(1)
                .constraintSize({ maxWidth: 14 })
                .height(this.barHeight(value))
                .borderRadius(4)
                .backgroundColor(this.accentColor())
                .opacity(index === this.dayMs.length - 1 ? 1 : 0.28)
            }, (value: number, index: number) => `${index}_${value}`)
          }
          .width('100%')
          .height(NOTE_BAR_MAX_HEIGHT)
          .alignItems(VerticalAlign.Bottom)

          Blank()

          Text(this.summaryText())
            .width('100%')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .height(52)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
    .borderRadius(ThemeRuntime.cardRadius())
    .accessibilityGroup(true)
    .accessibilityText(`阅读小记，今日阅读 ${this.todayMinutesText()} 分钟，${this.summaryText()}`)
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/ReadingStats' }).catch((error: Error) => {
        console.warn('打开阅读统计失败:', error);
      });
    })
  }
}
