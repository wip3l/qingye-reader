import { Book, BookChapter } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { ReadBookEngine } from '../../core/book/ReadBookEngine';
import { ReaderChapterRange } from '../../core/reader/ReaderChapterRange';
import { ReaderFullTextCacheController } from '../../core/reader/ReaderFullTextCacheController';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { DialogStyle } from '../../theme/DialogStyle';

/**
 * 阅读页"缓存"对话框的内容（配合系统自定义对话框使用）。两种形态共用这一个组件：
 * 入口菜单（缓存全文 / 缓存指定章节 / 清除缓存）和章节选择列表。
 * 目录、状态文字、范围输入都是组件自己的状态。缓存全文和缓存指定章节都交给控制器在后台执行，
 * 组件订阅它的进度；对话框随时可以关闭，不影响后台任务。
 * 版式与书架长按书籍弹出的缓存对话框保持一致，改动时两处一起改。
 */
@Component
export struct ReaderCacheDialogContent {
  /** true：章节选择列表；false：入口菜单。 */
  chapterMode: boolean = false;
  book: Book | null = null;
  controller: ReaderFullTextCacheController | null = null;
  // 对话框表面是系统材质，深浅跟随应用主题而不是阅读主题，文字和按钮颜色也必须取应用主题的，
  // 否则"应用浅色 + 阅读深色"会出现浅字配浅底。
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  onStartFullTextCache: () => void = (): void => {
  };
  onOpenChapterMode: () => void = (): void => {
  };
  onClose: () => void = (): void => {
  };
  /** 缓存状态变化后的最新目录，页面据此刷新自己的目录和"已缓存"标识。 */
  onChaptersChanged: (chapters: BookChapter[]) => void = (_chapters: BookChapter[]): void => {
  };

  @State private chapters: BookChapter[] = [];
  @State private status: string = '';
  @State private rangeDraft: string = '';
  @State private caching: boolean = false;
  @State private cachingStatus: string = '';
  private loadSerial: number = 0;
  private unsubscribe: (() => void) | null = null;

  aboutToAppear(): void {
    this.syncTaskState();
    if (this.controller) {
      this.unsubscribe = this.controller.subscribe((): void => this.syncTaskState());
    }
    this.status = this.chapterMode ? '正在加载目录...' : '';
    this.refreshChapters();
  }

  aboutToDisappear(): void {
    this.loadSerial++;
    if (this.unsubscribe) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  }

  // Mirrors the background task: its progress line while it runs, and its chapter marks into the list.
  private textColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  private subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  private syncTaskState(): void {
    const controller = this.controller;
    const wasCaching = this.caching;
    this.caching = !!controller && controller.caching;
    this.cachingStatus = controller ? controller.panelStatus() : '';
    if (controller && controller.chapters.length > 0 && (this.caching || wasCaching)) {
      this.chapters = [...controller.chapters];
    }
    if (wasCaching && !this.caching) this.status = this.summary();
  }

  private summary(): string {
    if (this.chapters.length === 0) return '暂未获取到目录';
    const cachedCount = ReaderFullTextCacheController.countCached(this.chapters);
    return `${cachedCount}章已缓存 ${this.chapters.length - cachedCount}章待缓存`;
  }

  private panelStatus(): string {
    return this.caching ? this.cachingStatus : this.status;
  }

  private publishChapters(chapters: BookChapter[]): void {
    this.chapters = [...chapters];
    this.onChaptersChanged([...chapters]);
  }

  private async refreshChapters(): Promise<void> {
    const bookUrl = this.book?.bookUrl || '';
    if (!bookUrl) return;
    const serial = ++this.loadSerial;
    try {
      const engine = ReadBookEngine.get();
      if (engine.book?.bookUrl !== bookUrl) return;
      await engine.syncChapterCacheDates();
      if (serial !== this.loadSerial) return;
      this.publishChapters(engine.chapters);
      this.status = this.summary();
    } catch (error) {
      console.warn('读取阅读页缓存目录失败:', error);
      if (serial === this.loadSerial) this.status = '目录加载失败，请稍后重试';
    }
  }

  private cacheRange(): void {
    const indexes = ReaderChapterRange.parse(this.rangeDraft, this.chapters.length);
    if (indexes.length === 0) {
      HdsFeedback.showToast(`请输入有效章节范围（1-${this.chapters.length}）`);
      return;
    }
    this.startScopedCache(indexes);
  }

  // Selected chapters are cached by the same background task as the whole book: it keeps running with the
  // dialog closed or the app in the background, and reports to the notification panel.
  private startScopedCache(indexes: number[]): void {
    const controller = this.controller;
    if (!controller || !this.book || indexes.length === 0) return;
    if (controller.caching) {
      HdsFeedback.showToast('该书正在后台缓存，请稍候');
      return;
    }
    HdsFeedback.showToast(`已转入后台缓存 ${indexes.length} 章，可在通知栏取消`);
    controller.start(indexes, '章节');
  }

  private async clearCachedChapters(): Promise<void> {
    const bookUrl = this.book?.bookUrl || '';
    if (!bookUrl || this.caching) return;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.deleteBookCachedContent(bookUrl);
      const engine = ReadBookEngine.get();
      if (engine.book?.bookUrl === bookUrl) {
        engine.clearCurrentBookMemoryCache();
        await engine.syncChapterCacheDates();
        this.publishChapters(engine.chapters);
      } else {
        this.chapters = this.chapters.map((chapter: BookChapter) => {
          chapter.cacheDate = 0;
          return chapter;
        });
      }
      this.status = '已清除缓存章节';
      HdsFeedback.showToast('已清除缓存章节');
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (error) {
      console.error('阅读页清除缓存章节失败:', error);
      this.status = '清除缓存失败';
      HdsFeedback.showToast('清除缓存失败');
    }
  }

  build() {
    if (this.chapterMode) {
      this.chapterList()
    } else {
      this.entryMenu()
    }
  }

  @Builder
  entryMenu() {
    Column() {
      Text(`缓存《${this.book?.name || '当前书籍'}》`)
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.textColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.MD })

      if (this.panelStatus()) {
        Text(this.panelStatus())
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: AppSpacing.MD })
      }

      this.actionItem(this.caching ? '正在缓存...' : '缓存全文', () => {
        this.onStartFullTextCache();
      }, this.caching)
      this.actionItem('缓存指定章节', () => {
        this.onOpenChapterMode();
      }, this.caching)
      this.actionItem('清除已缓存章节', () => {
        this.clearCachedChapters();
      }, this.caching, ThemeRuntime.dangerColor(this.appDarkMode))

      Button('取消')
        .width('100%')
        .height(44)
        .margin({ top: AppSpacing.MD })
        .backgroundColor(DialogStyle.fill('cancel', this.appDarkMode))
        .fontColor(this.textColor())
        .onClick(() => this.onClose())
    }
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XL, bottom: AppSpacing.XL })
  }

  @Builder
  actionItem(label: string, action: () => void, disabled: boolean = false, color: string = '') {
    Button(label)
      .width('100%')
      .height(44)
      .margin({ top: AppSpacing.SM })
      .backgroundColor(DialogStyle.fill('cancel', this.appDarkMode))
      .fontColor(color || this.textColor())
      .enabled(!disabled)
      .opacity(disabled ? 0.5 : 1)
      .onClick(action)
  }

  @Builder
  chapterList() {
    Column() {
      Row() {
        Text('选择章节缓存')
          .fontSize(AppFontSize.SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor())
          .layoutWeight(1)
        ImmersiveBackButton({
          icon: $r('sys.symbol.xmark'),
          iconOffsetX: 0,
          iconColor: this.textColor(),
          darkMode: this.appDarkMode,
          buttonSize: 40,
          containerWidth: 40,
          containerHeight: 40,
          startInset: 0,
          materialScale: 0.83,
          compactLayout: true,
          accessibilityLabel: '关闭',
          onBack: () => this.onClose()
        })
      }
      .width('100%')
      .height(46)
      .alignItems(VerticalAlign.Center)

      if (this.panelStatus()) {
        Text(this.panelStatus())
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
          .margin({ bottom: AppSpacing.MD })
      }

      Row({ space: AppSpacing.MD }) {
        TextInput({ placeholder: '章节范围，如 1-10、1,3,5-8', text: this.rangeDraft })
          .type(InputType.Normal)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.textColor())
          .placeholderColor(this.subTextColor())
          .layoutWeight(1)
          .height(42)
          .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
          .backgroundColor(ThemeRuntime.softFillColor(this.appDarkMode))
          .borderRadius(ThemeRuntime.mediumRadius())
          .onChange((value: string) => {
            this.rangeDraft = value;
          })
        Button('缓存')
          .width(96)
          .height(42)
          .fontSize(AppFontSize.BODY)
          .fontColor(DialogStyle.text('primary', this.appDarkMode))
          .backgroundColor(DialogStyle.fill('primary', this.appDarkMode))
          .enabled(this.chapters.length > 0)
          .onClick(() => this.cacheRange())
      }
      .width('100%')
      .margin({ bottom: AppSpacing.MD })

      List({ space: AppSpacing.XXS }) {
        ForEach(this.chapters, (chapter: BookChapter, index: number) => {
          ListItem() {
            Row({ space: AppSpacing.MD }) {
              Text(chapter.title)
                .fontSize(AppFontSize.BODY_LARGE)
                .fontColor(chapter.cacheDate > 0 ? (this.appDarkMode ? '#DDEFE5' : '#244B35') : this.textColor())
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (chapter.cacheDate > 0) {
                Text('已缓存')
                  .fontSize(AppFontSize.CAPTION)
                  .fontColor(ThemeRuntime.successColor(this.appDarkMode))
                  .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
                  .backgroundColor(ThemeRuntime.successSurfaceColor(this.appDarkMode))
                  .borderRadius(ThemeRuntime.smallRadius())
              }
            }
            .width('100%')
            .padding({ left: AppSpacing.XXS, right: AppSpacing.XXS, top: AppSpacing.LG, bottom: AppSpacing.LG })
            .onClick(() => this.startScopedCache([index]))
          }
        }, (chapter: BookChapter, index: number) =>
          `${index}_${chapter.cacheDate > 0 ? 1 : 0}_${chapter.url || chapter.title}`)
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height(380)
    }
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XL, bottom: AppSpacing.XL })
  }
}
