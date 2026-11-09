import { router } from '@kit.ArkUI';
import { Bookmark } from '@legado/sourceengine';
import { appDb, ReadStatsRow } from '../../model/data/AppDatabase';
import { readStatsTracker } from '../../core/stats/ReadStatsTracker';
import { ReadStatsBar, ReadStatsRank, ReadStatsSummary } from '../../core/stats/ReadStatsSummary';
import { ReadStatsPosterSession, ReadStatsPosterSnapshot } from '../../core/stats/ReadStatsPosterModel';
import { AccountSessionStore } from '../../account/AccountSessionStore';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { CollapsingHeader } from '../../utils/CollapsingHeader';
import { HeaderBackdrop } from '../common/HeaderBackdrop';
import { HomeThemeBackdrop } from './HomeThemeBackdrop';
import { BookCover } from '../book/BookCover';
import { ImmersiveMaterialSurface } from '../ImmersiveMaterialSurface';

/** 本月日历的一格；day 为 0 是月初前的空位。level 0 没读，1~3 越大读得越久，-1 是还没到的日子。 */
class FootprintDay {
  key: string = '';
  day: number = 0;
  level: number = 0;
  durationMs: number = 0;
  today: boolean = false;
}

/** 首页第四个页签“足迹”：本周阅读（全部设备）、本月日历、读得最多的书和最近书签。 */
@Component
export struct FootprintTabPage {
  static readonly HEADER_CONTROL_SIZE: number = 40;
  static readonly CHART_HEIGHT: number = 88;
  static readonly RANK_LIMIT: number = 3;
  static readonly BOOKMARK_LIMIT: number = 10;
  static readonly BOOKMARK_CARD_HEIGHT: number = 148;
  /** 日历颜色分档：20 分钟、1 小时。 */
  static readonly LEVEL_STEPS_MS: number[] = [20 * 60000, 60 * 60000];
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  onHeaderCollapseChange: (progress: number) => void = () => {};
  @State headerCollapse: number = 0;
  @State headerBackdropReveal: number = 0;
  @State summary: ReadStatsSummary = new ReadStatsSummary();
  @State lastWeekMs: number = 0;
  @State monthDays: FootprintDay[] = [];
  @State monthTitle: string = '';
  @State bookmarks: Bookmark[] = [];
  @State loading: boolean = true;
  @State todayKey: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('readStatsRecording') readStatsRecording: boolean = true;
  private scroller: Scroller = new Scroller();
  private alive: boolean = false;
  private ownerId: string = '';
  private openingShare: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.alive = false;
  }

  async load(): Promise<void> {
    const now = Date.now();
    this.todayKey = ReadStatsSummary.dayKey(now);
    try {
      const context = getContext(this);
      await appDb.init(context);
      await AccountSessionStore.load(context);
      const ownerId = AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : '';
      await readStatsTracker.flushAndWait();
      // 一次查出上周一到本月底，再分别算本周、上周和本月日历。
      const week = ReadStatsSummary.range('week', now);
      const lastWeekAnchor = ReadStatsSummary.shift('week', now, -1);
      const lastWeek = ReadStatsSummary.range('week', lastWeekAnchor);
      const month = ReadStatsSummary.range('month', now);
      const startKey = lastWeek.startKey < month.startKey ? lastWeek.startKey : month.startKey;
      const endKey = week.endKey > month.endKey ? week.endKey : month.endKey;
      const rows = await appDb.getReadStatsByDayRange(startKey, endKey, '', ownerId);
      const bookmarks = await appDb.getAllBookmarks();
      if (!this.alive) return;
      this.ownerId = ownerId;
      this.summary = ReadStatsSummary.calculate(rows, 'week', now, now);
      this.lastWeekMs = ReadStatsSummary.calculate(rows, 'week', lastWeekAnchor, now).totalMs;
      this.monthDays = this.buildMonth(rows, month.startTs, now);
      this.monthTitle = `${new Date(now).getMonth() + 1} 月足迹`;
      this.bookmarks = bookmarks.slice(0, FootprintTabPage.BOOKMARK_LIMIT);
    } catch (error) {
      console.warn('读取足迹失败:', error);
    } finally {
      if (this.alive) this.loading = false;
    }
  }

  private buildMonth(rows: ReadStatsRow[], monthStartTs: number, now: number): FootprintDay[] {
    const totals = new Map<string, number>();
    rows.forEach((row: ReadStatsRow): void => {
      if (row.durationMs > 0) totals.set(row.dayKey, (totals.get(row.dayKey) || 0) + row.durationMs);
    });
    const first = new Date(monthStartTs);
    const days: FootprintDay[] = [];
    // 周一开头，和本周柱状图一致。
    const leading = (first.getDay() + 6) % 7;
    for (let i = 0; i < leading; i++) {
      const blank = new FootprintDay();
      blank.key = `blank${i}`;
      days.push(blank);
    }
    const count = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
    const todayKey = ReadStatsSummary.dayKey(now);
    for (let day = 1; day <= count; day++) {
      const ts = new Date(first.getFullYear(), first.getMonth(), day).getTime();
      const item = new FootprintDay();
      item.key = ReadStatsSummary.dayKey(ts);
      item.day = day;
      item.today = item.key === todayKey;
      item.durationMs = totals.get(item.key) || 0;
      item.level = item.key > todayKey ? -1 : this.levelOf(item.durationMs);
      days.push(item);
    }
    return days;
  }

  private levelOf(ms: number): number {
    if (ms <= 0) return 0;
    if (ms < FootprintTabPage.LEVEL_STEPS_MS[0]) return 1;
    return ms < FootprintTabPage.LEVEL_STEPS_MS[1] ? 2 : 3;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HomeThemeBackdrop({ visibleHeight: this.statusBarHeight + 330, strength: 0.85 })

      Scroll(this.scroller) {
        Column({ space: AppSpacing.LG }) {
          Row()
            .width('100%')
            .height(56 + this.statusBarHeight)

          this.weekCard()
          this.monthCard()

          if (this.summary.items.length > 0) {
            this.sectionHeader('读得最多')
            Column() {
              ForEach(this.summary.items.slice(0, FootprintTabPage.RANK_LIMIT), (item: ReadStatsRank) => {
                this.rankRow(item)
              }, (item: ReadStatsRank) => item.bookKey)
            }
            .width('100%')
            .padding({ top: AppSpacing.XS, bottom: AppSpacing.XS })
            .borderRadius(ThemeRuntime.largeRadius())
            .clip(true)
            .backgroundColor(this.cardColor())
          }

          if (this.bookmarks.length > 0) {
            this.sectionHeader('最近书签')
            List({ space: AppSpacing.MD }) {
              ForEach(this.bookmarks, (bookmark: Bookmark) => {
                ListItem() {
                  this.bookmarkCard(bookmark)
                }
              }, (bookmark: Bookmark) => `${bookmark.id}`)
            }
            .listDirection(Axis.Horizontal)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .width('100%')
            .height(FootprintTabPage.BOOKMARK_CARD_HEIGHT)
          }

          Row()
            .width('100%')
            .height(56 + Math.max(this.navBarHeight, 8) + 20)
        }
        .width('calc(100% - 32vp)')
        .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
        .justifyContent(FlexAlign.Start)
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .backgroundColor(ThemeRuntime.homeSurfaceColor(this.appDarkMode))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onDidScroll((_xOffset: number, yOffset: number) => {
        const reveal = CollapsingHeader.backdropReveal(this.scroller.currentOffset().yOffset);
        if (reveal !== this.headerBackdropReveal) this.headerBackdropReveal = reveal;
        this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
          this.scroller.currentOffset().yOffset);
      })
      .onScrollStop(() => {
        const target = CollapsingHeader.settle(this.headerCollapse, this.scroller.currentOffset().yOffset);
        if (target !== this.headerCollapse) {
          animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
            this.headerCollapse = target;
          });
        }
      })

      HeaderBackdrop({ backdropHeight: this.statusBarHeight + 56 - this.headerCollapse,
        statusBarHeight: this.statusBarHeight,
        backdropColor: ThemeRuntime.topBarColor(this.appDarkMode),
        reveal: ThemeRuntime.homeBackdrop(this.appDarkMode) ? this.headerBackdropReveal : 1 })
        .width('100%')

      Column() {
        Row({ space: 10 }) {
          Text('足迹')
            .fontSize(AppFontSize.DISPLAY)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
          this.headerButton($r('sys.symbol.share'), '分享本周阅读海报', () => this.shareWeek())
          this.headerButton($r('sys.symbol.timer'), '完整阅读统计', () => this.openStats())
        }
        .width('100%')
        .height(56 + this.statusBarHeight)
        .alignItems(VerticalAlign.Center)
        .padding({ left: AppSpacing.XL, right: AppSpacing.LG, top: this.statusBarHeight })
        .opacity(CollapsingHeader.contentOpacity(this.headerCollapse))
        .hitTestBehavior(CollapsingHeader.acceptsTouch(this.headerCollapse) ? HitTestMode.Default : HitTestMode.None)
      }
      .width('100%')
      .height(56 + this.statusBarHeight - this.headerCollapse)
      .clip(true)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.onHeaderCollapseChange((56 + this.statusBarHeight - Number(newArea.height)) /
          CollapsingHeader.DISTANCE);
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /** 和书架、发现顶栏的圆钮同一种沉浸光感材质、同样 40 大小。 */
  @Builder
  headerButton(icon: Resource, label: string, action: () => void) {
    ImmersiveMaterialSurface({
      surfaceWidth: FootprintTabPage.HEADER_CONTROL_SIZE,
      surfaceHeight: FootprintTabPage.HEADER_CONTROL_SIZE,
      darkMode: this.appDarkMode,
      fallbackColor: this.cardColor(),
      glowColor: this.accentTint('40')
    }) {
      Stack() {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([this.primaryTextColor()])
      }
      .width('100%')
      .height('100%')
      .accessibilityText(label)
      .onClick(() => action())
    }
  }

  /** 本周：大字总时长 + 和上周比，柱状图，下面一行日均/天数/本数。 */
  @Builder
  weekCard() {
    Column({ space: AppSpacing.LG }) {
      Column({ space: AppSpacing.XS }) {
        Row({ space: AppSpacing.SM }) {
          Text('本周阅读')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
          if (!this.readStatsRecording) {
            Text('已暂停记录')
              .fontSize(AppFontSize.MICRO)
              .fontColor(ThemeRuntime.warningColor(this.appDarkMode))
              .padding({ left: 8, right: 8, top: 1, bottom: 1 })
              .borderRadius(10)
              .backgroundColor('#24E89725')
          }
        }
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Text(this.loading ? '—' : this.durationText(this.summary.totalMs))
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .margin({ right: AppSpacing.MD })
          if (!this.loading && this.compareText()) {
            Text(this.compareText())
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.accentColor())
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(10)
              .backgroundColor(this.accentTint('1F'))
          }
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row({ space: AppSpacing.SM }) {
        ForEach(this.summary.bars, (bar: ReadStatsBar) => {
          Column({ space: AppSpacing.XS }) {
            Blank()
            Column()
              .width('70%')
              .constraintSize({ maxWidth: 24 })
              .height(this.barHeight(bar))
              .borderRadius(7)
              .backgroundColor(bar.key === this.todayKey ? this.accentColor() : this.accentTint('40'))
            Text(bar.label)
              .fontSize(AppFontSize.MICRO)
              .fontColor(bar.key === this.todayKey ? this.accentColor() : this.subTextColor())
          }
          .layoutWeight(1)
          .height('100%')
          .alignItems(HorizontalAlign.Center)
          .accessibilityText(`周${bar.label} ${ReadStatsSummary.duration(bar.durationMs)}`)
        }, (bar: ReadStatsBar) => `${bar.key}|${bar.durationMs}`)
      }
      .width('100%')
      .height(FootprintTabPage.CHART_HEIGHT + 20)

      Divider()
        .strokeWidth(0.5)
        .color(ThemeRuntime.hairlineColor(this.appDarkMode))

      Row() {
        this.statCell('日均', this.loading ? '—' : this.durationText(this.summary.averageMs))
        this.statCell('读书天数', this.loading ? '—' : `${this.summary.activeDays} 天`)
        this.statCell('读过', this.loading ? '—' : `${this.summary.items.length} 本`)
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(this.cardColor())
    .onClick(() => this.openStats())
  }

  @Builder
  statCell(label: string, value: string) {
    Column({ space: AppSpacing.XXS }) {
      Text(label)
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.subTextColor())
      Text(value)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  /** 本月日历：每天一格，颜色越深读得越久，今天加圈。 */
  @Builder
  monthCard() {
    Column({ space: AppSpacing.MD }) {
      Row() {
        Text(this.monthTitle)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Row({ space: 4 }) {
          Text('少')
            .fontSize(AppFontSize.MICRO)
            .fontColor(this.subTextColor())
          ForEach([0, 1, 2, 3], (level: number) => {
            Column()
              .width(10)
              .height(10)
              .borderRadius(3)
              .backgroundColor(this.levelColor(level))
          }, (level: number) => `${level}`)
          Text('多')
            .fontSize(AppFontSize.MICRO)
            .fontColor(this.subTextColor())
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')

      Grid() {
        ForEach(this.monthDays, (item: FootprintDay) => {
          GridItem() {
            this.dayCell(item)
          }
        }, (item: FootprintDay) => `${item.key}|${item.level}|${item.today}`)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .columnsGap(5)
      .rowsGap(5)
      .width('100%')
      .layoutDirection(GridDirection.Row)
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  dayCell(item: FootprintDay) {
    Stack() {
      if (item.day > 0) {
        Text(`${item.day}`)
          .fontSize(10)
          .fontColor(item.level >= 2 ? '#FFFFFF' : this.subTextColor())
      }
    }
    .width('100%')
    .aspectRatio(1)
    .borderRadius(6)
    .backgroundColor(item.day <= 0 ? Color.Transparent :
      (item.level < 0 ? this.futureDayColor() : this.levelColor(item.level)))
    .border({ width: item.today ? 2 : 0, color: this.primaryTextColor() })
    .accessibilityText(item.day > 0 ?
      `${item.day} 日 ${item.durationMs > 0 ? ReadStatsSummary.duration(item.durationMs) : '没有阅读'}` : '')
  }

  @Builder
  sectionHeader(title: string) {
    Text(title)
      .fontSize(AppFontSize.TITLE)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.primaryTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
  }

  @Builder
  rankRow(item: ReadStatsRank) {
    Row({ space: AppSpacing.LG }) {
      Stack() {
        BookCover({
          bookUrl: item.bookUrl,
          coverUrl: item.coverUrl,
          name: item.name,
          author: item.author,
          useBookshelfCover: item.onShelf,
          placeholderColor: this.accentColor(),
          cornerRadius: 4,
          decodeWidth: 96,
          decodeHeight: 128
        })
      }
      .width(36)
      .height(48)
      .borderRadius(4)
      .clip(true)
      Column({ space: AppSpacing.SM }) {
        Row({ space: AppSpacing.SM }) {
          Text(item.name)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(ReadStatsSummary.duration(item.durationMs))
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.primaryTextColor())
        }
        .width('100%')
        Progress({ value: Math.max(0, Math.min(100, item.percent)), total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(4)
          .color(this.accentColor())
          .backgroundColor(ThemeRuntime.hairlineColor(this.appDarkMode))
          .style({ strokeWidth: 4, strokeRadius: 2 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.SM })
    .alignItems(VerticalAlign.Center)
    .accessibilityText(`${item.name}，${ReadStatsSummary.duration(item.durationMs)}，占本周 ${Math.round(item.percent)}%`)
    .onClick(() => {
      if (item.onShelf && item.bookUrl) this.openBook(item.bookUrl);
    })
  }

  /** 书签摘句卡：大引号 + 原文，下面是书名和章节。 */
  @Builder
  bookmarkCard(bookmark: Bookmark) {
    Column({ space: AppSpacing.XS }) {
      Text('“')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accentTint('80'))
        .height(26)
      Text(bookmark.content || bookmark.chapterName || '书签')
        .fontSize(AppFontSize.BODY)
        .lineHeight(20)
        .fontColor(this.primaryTextColor())
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .layoutWeight(1)
      Text(bookmark.chapterName ? `${bookmark.bookName} · ${bookmark.chapterName}` : bookmark.bookName)
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.subTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width(200)
    .height(FootprintTabPage.BOOKMARK_CARD_HEIGHT)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.LG })
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(this.cardColor())
    .onClick(() => {
      if (bookmark.bookUrl) this.openBook(bookmark.bookUrl);
    })
  }

  compareText(): string {
    const diff = this.summary.totalMs - this.lastWeekMs;
    if (this.summary.totalMs <= 0 && this.lastWeekMs <= 0) return '';
    if (Math.abs(diff) < 60000) return '和上周持平';
    return `比上周${diff > 0 ? '多' : '少'} ${ReadStatsSummary.duration(Math.abs(diff))}`;
  }

  barHeight(bar: ReadStatsBar): number {
    let max = 0;
    this.summary.bars.forEach((item: ReadStatsBar): void => { max = Math.max(max, item.durationMs); });
    if (max <= 0 || bar.durationMs <= 0) return 4;
    return Math.max(4, Math.round(FootprintTabPage.CHART_HEIGHT * bar.durationMs / max));
  }

  durationText(ms: number): string {
    if (ms <= 0) return '0分钟';
    return ReadStatsSummary.duration(ms);
  }

  openStats(): void {
    router.pushUrl({ url: 'pages/ReadingStats' });
  }

  /** 复用阅读统计的海报页，范围是本周、全部设备。 */
  async shareWeek(): Promise<void> {
    if (this.loading || this.openingShare) return;
    if (this.summary.totalMs <= 0) {
      HdsFeedback.showToast('本周还没有阅读记录');
      return;
    }
    const account = AccountSessionStore.account();
    const now = Date.now();
    const range = ReadStatsSummary.range('week', now);
    const start = new Date(range.startTs);
    const end = new Date(range.endTs);
    const period = `${start.getFullYear()}年${start.getMonth() + 1}月${start.getDate()}日 — ` +
      `${start.getFullYear() !== end.getFullYear() ? `${end.getFullYear()}年` : ''}${end.getMonth() + 1}月${end.getDate()}日`;
    this.openingShare = true;
    ReadStatsPosterSession.put(ReadStatsPosterSnapshot.capture(this.summary, this.ownerId, 'week', period, '全部设备',
      this.ownerId ? account.displayName : '', this.ownerId ? account.avatarUrl : ''));
    try {
      await router.pushUrl({ url: 'pages/ReadingStatsShare' });
    } catch (_) {
      ReadStatsPosterSession.take();
      HdsFeedback.showToast('打开分享页面失败，请重试');
    } finally {
      this.openingShare = false;
    }
  }

  /** 阅读页按书的进度打开，有声书、视频和 PDF 由阅读页自己转过去。 */
  openBook(bookUrl: string): void {
    router.pushUrl({ url: 'pages/ReadBook', params: { bookUrl: bookUrl } }).catch((error: Error) => {
      console.error('从足迹打开书籍失败:', error);
    });
  }

  levelColor(level: number): string {
    if (level <= 0) return ThemeRuntime.hairlineColor(this.appDarkMode);
    if (level === 1) return this.accentTint('40');
    return level === 2 ? this.accentTint('99') : this.accentColor();
  }

  futureDayColor(): string {
    return this.appDarkMode ? '#0DFFFFFF' : '#08000000';
  }

  /** 强调色加透明度（两位十六进制），强调色不是 #RRGGBB 时退回分隔线色。 */
  accentTint(alpha: string): string {
    const color = this.accentColor();
    return /^#[0-9A-Fa-f]{6}$/.test(color) ? `#${alpha}${color.substring(1)}` : ThemeRuntime.hairlineColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }
}
