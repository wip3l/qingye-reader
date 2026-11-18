import { AppDatabase } from '../../model/data/AppDatabase';
import { AccountSessionStore } from '../../account/AccountSessionStore';
import { readStatsTracker } from '../../core/stats/ReadStatsTracker';
import { BookReadStats } from '../../core/stats/BookReadStats';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { BookReadStatsSheet } from './BookReadStatsSheet';

interface BookReadStatsMetric {
  icon: Resource;
  label: string;
  /** 交替的数字与单位。 */
  parts: string[];
  sub: string;
}

/**
 * 书籍详情页的“阅读统计”卡片：这本书没有阅读记录时不占位置。
 * 数据自己读（当前账号加本机游客记录、所有设备合计），宿主改 refreshToken 触发重读；
 * 点卡片打开按月、日历、时间线的详情面板。
 */
@Component
export struct BookReadStatsCard {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @Prop @Watch('onInputChanged') bookUrl: string = '';
  @Prop @Watch('onInputChanged') bookName: string = '';
  @Prop @Watch('onInputChanged') author: string = '';
  @Prop @Watch('onInputChanged') refreshToken: number = 0;
  /** 进度的单位：章、集或页。 */
  @Prop chapterUnit: string = '章';

  @State stats: BookReadStats = new BookReadStats();
  @State chapterIndex: number = -1;
  @State chapterTotal: number = 0;
  @State annotationCounts: number[] = [0, 0, 0];
  @State showSheet: boolean = false;
  private loadVersion: number = 0;

  aboutToAppear(): void {
    this.reload();
  }

  aboutToDisappear(): void {
    this.loadVersion++;
  }

  onInputChanged(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    const version = ++this.loadVersion;
    const bookUrl = this.bookUrl;
    if (!bookUrl) {
      this.stats = new BookReadStats();
      return;
    }
    try {
      const context = getContext(this);
      const db = AppDatabase.getInstance();
      await db.initWithContext(context);
      await AccountSessionStore.load(context);
      const ownerId = AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : '';
      // 刚从阅读页回来时最后一段还没入库。
      await readStatsTracker.flushAndWait();
      const records = await db.getBookReadStatsRecords(bookUrl, this.bookName.trim(), this.author.trim(), ownerId);
      const stats = BookReadStats.calculate(records);
      let chapterIndex = -1;
      let chapterTotal = 0;
      let counts = [0, 0, 0];
      if (stats.activeDays > 0) {
        const book = await db.getBook(bookUrl);
        if (book) {
          chapterIndex = book.durChapterIndex;
          chapterTotal = book.totalChapterNum > 0 ? book.totalChapterNum : await db.getBookChapterCount(bookUrl);
        }
        counts = await db.getBookAnnotationCounts(bookUrl);
      }
      if (version !== this.loadVersion) return;
      this.stats = stats;
      this.chapterIndex = chapterIndex;
      this.chapterTotal = chapterTotal;
      this.annotationCounts = counts;
    } catch (error) {
      console.warn('读取本书阅读统计失败:', error);
    }
  }

  private primary(): string {
    return ThemeRuntime.primaryTextColor(this.darkMode);
  }

  private sub(): string {
    return ThemeRuntime.subTextColor(this.darkMode);
  }

  private hasProgress(): boolean {
    return this.chapterIndex >= 0 && this.chapterTotal > 0;
  }

  private progressParts(): string[] {
    if (!this.hasProgress()) return ['—', ''];
    return [`${Math.min(this.chapterIndex + 1, this.chapterTotal)}`, `/ ${this.chapterTotal} ${this.chapterUnit}`];
  }

  private progressSub(): string {
    if (!this.hasProgress()) return '还没有进度';
    const percent = Math.min(100, (this.chapterIndex + 1) * 100 / this.chapterTotal);
    return `按${this.chapterUnit}数 ${percent >= 100 ? '100' : percent.toFixed(1)}%`;
  }

  private annotationSub(): string {
    if (this.annotationCounts[0] <= 0) return '还没有划线';
    const parts: string[] = [];
    if (this.annotationCounts[1] > 0) parts.push(`${this.annotationCounts[1]} 个想法`);
    if (this.annotationCounts[2] > 0) parts.push(`${this.annotationCounts[2]} 条摘录`);
    return parts.length > 0 ? parts.join(' · ') : '只有划线';
  }

  build() {
    Column() {
      if (this.stats.activeDays > 0) {
        Column({ space: AppSpacing.XL }) {
          Row() {
            Text('阅读统计')
              .fontSize(AppFontSize.BODY_LARGE)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.primary())
            Blank()
            Text('详情')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.sub())
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(13)
              .fontColor([this.sub()])
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Row({ space: AppSpacing.LG }) {
            this.metric({
              icon: $r('sys.symbol.clock'),
              label: '累计时长',
              parts: BookReadStats.durationParts(this.stats.totalMs),
              sub: `${BookReadStats.shortDate(this.stats.firstDayKey)} 开始阅读`
            })
            this.metric({
              icon: $r('sys.symbol.calendar'),
              label: '阅读天数',
              parts: [`${this.stats.activeDays}`, '天'],
              sub: `上次阅读 · ${BookReadStats.shortDate(this.stats.lastDayKey)}`
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
              parts: BookReadStats.durationParts(this.stats.bestDayMs),
              sub: BookReadStats.shortDate(this.stats.bestDayKey)
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          Row({ space: AppSpacing.LG }) {
            this.metric({
              icon: $r('sys.symbol.doc_text'),
              label: '划线与笔记',
              parts: [`${this.annotationCounts[0]}`, '条'],
              sub: this.annotationSub()
            })
            this.metric({
              icon: $r('sys.symbol.timer'),
              label: '日均时长',
              parts: BookReadStats.durationParts(this.stats.totalMs / Math.max(1, this.stats.activeDays)),
              sub: '按阅读的日子平均'
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .width('100%')
        .padding(AppSpacing.LG)
        .margin({ top: AppSpacing.SM, bottom: AppSpacing.SM })
        .borderRadius(ThemeRuntime.largeRadius())
        .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
        .border({ width: 0.5, color: ThemeRuntime.hairlineColor(this.darkMode) })
        .accessibilityText('阅读统计，点按查看详情')
        .onClick(() => {
          this.showSheet = true;
        })
      }
    }
    .width('100%')
    .bindSheet($$this.showSheet, this.sheetContent(), this.sheetOptions())
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

  @Builder
  sheetContent() {
    BookReadStatsSheet({ stats: this.stats, bookName: this.bookName })
  }

  private sheetOptions(): SheetOptions {
    const options: SheetOptions = {
      detents: ['70%', SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      backgroundColor: Color.Transparent,
      blurStyle: BlurStyle.NONE,
      borderWidth: 0,
      radius: { topLeft: 28, topRight: 28, bottomLeft: 28, bottomRight: 28 },
      shadow: { radius: 0, color: Color.Transparent },
      onDisappear: () => {
        this.showSheet = false;
      }
    };
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, options,
      this.darkMode, ThemeRuntime.accentColor(this.darkMode));
  }
}
