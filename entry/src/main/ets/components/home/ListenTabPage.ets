import { WebParseSettingsStore } from '../../utils/WebParseSettingsStore';
import { router } from '@kit.ArkUI';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { PopupMenuAction } from '../common/PopupMenuAction';
import { Book, BookTypeSupport } from '@legado/sourceengine';
import { appDb } from '../../model/data/AppDatabase';
import { AudioOfflineStore } from '../../core/book/AudioOfflineStore';
import { ReaderTtsFloatingSession } from '../../utils/ReaderTtsFloatingSession';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { CollapsingHeader } from '../../utils/CollapsingHeader';
import { HeaderBackdrop } from '../common/HeaderBackdrop';
import { HomeThemeBackdrop } from './HomeThemeBackdrop';
import { BookCover } from '../book/BookCover';

class ListenBookItem {
  book: Book = new Book();
  offline: boolean = false;
}

class ListenEntry {
  icon: Resource = $r('sys.symbol.gearshape');
  title: string = '';
  url: string = '';
}

/** 首页第四个页签“听”：正在播放、有声书架和朗读相关设置入口。 */
@Component
export struct ListenTabPage {
  static readonly SHELF_COVER_SIZE: number = 104;
  static readonly HERO_COVER_WIDTH: number = 96;
  static readonly HERO_COVER_HEIGHT: number = 128;
  /** 和播放面板的倍速档一致，点一下换到下一档。 */
  static readonly SPEEDS: number[] = [0.8, 1.0, 1.2, 1.5, 2.0, 3.0];
  static readonly TIMER_MINUTES: number[] = [15, 30, 60, 90];
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  onHeaderCollapseChange: (progress: number) => void = () => {};
  @State headerCollapse: number = 0;
  @State headerBackdropReveal: number = 0;
  @State audioBooks: ListenBookItem[] = [];
  @State loaded: boolean = false;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('globalTtsActive') ttsActive: boolean = false;
  @StorageProp('globalTtsPaused') ttsPaused: boolean = false;
  @StorageProp('globalTtsBookName') ttsBookName: string = '';
  @StorageProp('globalTtsBookUrl') ttsBookUrl: string = '';
  @StorageProp('globalTtsChapterTitle') ttsChapterTitle: string = '';
  @StorageProp('globalTtsMode') ttsMode: string = '';
  @StorageProp('globalTtsProgress') ttsProgress: number = 0;
  @StorageProp('globalTtsCanPrevious') ttsCanPrevious: boolean = false;
  @StorageProp('globalTtsCanNext') ttsCanNext: boolean = false;
  @StorageProp('globalTtsChapterPercent') ttsChapterPercent: number = -1;
  @StorageProp('globalTtsSpeed') ttsSpeed: number = 1;
  @StorageProp('globalTtsTimerMinutes') ttsTimerMinutes: number = 0;
  @StorageProp('globalTtsTimerRemainingSeconds') ttsTimerRemainingSeconds: number = 0;
  @StorageProp('globalTtsVoiceCode') ttsVoiceCode: string = '';
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @State showTimerMenu: boolean = false;
  /** 有声书来自网页解析，开关关闭时不显示有声书相关的入口和文案。 */
  @StorageProp('webParseEnabled') webParseEnabled: boolean = false;
  @StorageProp('shelfUpdateTime') @Watch('onShelfUpdated') shelfUpdateTime: number = 0;
  private scroller: Scroller = new Scroller();
  private alive: boolean = false;
  private loadVersion: number = 0;
  private readonly entries: ListenEntry[] = [
    { icon: $r('sys.symbol.speaker_wave_2'), title: '朗读设置', url: 'pages/TtsSettings' },
    { icon: $r('sys.symbol.earphone'), title: '音色管理', url: 'pages/CustomTtsVoiceManager' },
    { icon: $r('sys.symbol.square_and_arrow_down'), title: '有声书下载', url: 'pages/AudioBookSettings' }
  ];

  visibleEntries(): ListenEntry[] {
    return this.webParseEnabled ? this.entries :
      this.entries.filter((entry: ListenEntry): boolean => entry.url !== 'pages/AudioBookSettings');
  }

  aboutToAppear(): void {
    this.alive = true;
    this.loadAudioBooks();
  }

  aboutToDisappear(): void {
    this.alive = false;
  }

  onShelfUpdated(): void {
    this.loadAudioBooks();
  }

  async loadAudioBooks(): Promise<void> {
    const version = ++this.loadVersion;
    try {
      await appDb.init(getContext(this));
      const books = (await appDb.getAllBooks())
        .filter((book: Book): boolean => BookTypeSupport.isAudio(book) && WebParseSettingsStore.visibleBook(book.origin))
        .sort((a: Book, b: Book): number => (b.durChapterTime || 0) - (a.durChapterTime || 0));
      if (!this.alive || version !== this.loadVersion) return;
      const items = books.map((book: Book): ListenBookItem => {
        const item = new ListenBookItem();
        item.book = book;
        return item;
      });
      this.audioBooks = items;
      this.loaded = true;
      // “已下载”角标要逐本查离线目录，列表先出来再补。
      const flags = await Promise.all(items.map(async (item: ListenBookItem): Promise<boolean> => {
        try {
          return await AudioOfflineStore.bookBytes(item.book.bookUrl) > 0;
        } catch (_) {
          return false;
        }
      }));
      if (!this.alive || version !== this.loadVersion) return;
      if (!flags.some((flag: boolean): boolean => flag)) return;
      this.audioBooks = items.map((item: ListenBookItem, index: number): ListenBookItem => {
        const next = new ListenBookItem();
        next.book = item.book;
        next.offline = flags[index] === true;
        return next;
      });
    } catch (error) {
      if (!this.alive || version !== this.loadVersion) return;
      this.loaded = true;
      console.warn('读取有声书失败:', error);
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HomeThemeBackdrop({ visibleHeight: this.statusBarHeight + 330, strength: 0.85 })

      Scroll(this.scroller) {
        Column({ space: AppSpacing.LG }) {
          Row()
            .width('100%')
            .height(56 + this.statusBarHeight)

          if (this.ttsActive || this.audioBooks.length > 0) {
            this.heroCard()
          } else if (this.loaded) {
            this.emptyCard()
          }

          if (this.audioBooks.length > 0) {
            Row() {
              Text('最近在听')
                .fontSize(AppFontSize.TITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .layoutWeight(1)
              Text(`${this.audioBooks.length} 本`)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor())
            }
            .width('100%')
            .padding({ left: AppSpacing.XS, right: AppSpacing.XS })

            List({ space: AppSpacing.MD }) {
              ForEach(this.audioBooks, (item: ListenBookItem) => {
                ListItem() {
                  this.audioBookCell(item)
                }
              }, (item: ListenBookItem) => `${item.book.bookUrl}|${item.offline}|${item.book.durChapterIndex}`)
            }
            .listDirection(Axis.Horizontal)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .width('100%')
            .height(ListenTabPage.SHELF_COVER_SIZE + 62)
          }

          Row({ space: AppSpacing.MD }) {
            ForEach(this.visibleEntries(), (entry: ListenEntry) => {
              this.entryTile(entry)
            }, (entry: ListenEntry) => entry.url)
          }
          .width('100%')

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
        Row() {
          Text('听')
            .fontSize(AppFontSize.DISPLAY)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
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

  /**
   * 顶部大卡：在播时是播放卡（点卡片打开首页的播放面板，按钮直接控制），没在播时接着听最近那本有声书。
   * 底图是封面放大模糊再压暗，文字一律白色。
   */
  @Builder
  heroCard() {
    Column({ space: AppSpacing.LG }) {
      Row({ space: AppSpacing.LG }) {
        Stack() {
          if (this.heroBookUrl()) {
            BookCover({
              bookUrl: this.heroBookUrl(),
              origin: this.heroOrigin(),
              coverUrl: this.heroCoverUrl(),
              customCoverUrl: this.heroCustomCoverUrl(),
              name: this.heroName(),
              placeholderColor: this.accentColor(),
              cornerRadius: 12,
              decodeWidth: 240,
              decodeHeight: 320
            })
          }
        }
        .width(ListenTabPage.HERO_COVER_WIDTH)
        .height(ListenTabPage.HERO_COVER_HEIGHT)
        .borderRadius(12)
        .clip(true)
        .shadow({ radius: 20, color: '#59000000', offsetY: 8 })

        Column({ space: AppSpacing.SM }) {
          Text(this.heroBadge())
            .fontSize(AppFontSize.MICRO)
            .fontColor('#F3ECE8')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(10)
            .backgroundColor('#2EFFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.heroName())
            .fontSize(AppFontSize.SUBTITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.heroSubtitle())
            .fontSize(AppFontSize.CAPTION)
            .fontColor('#E0D5CF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: AppSpacing.XS })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      if (this.ttsActive) {
        Column({ space: AppSpacing.XS }) {
          Progress({ value: this.heroPercent(), total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(4)
            .color('#FFFFFF')
            .backgroundColor('#40FFFFFF')
            .style({ strokeWidth: 4, strokeRadius: 2 })
          Row() {
            Text(this.heroPercentText())
              .fontSize(AppFontSize.MICRO)
              .fontColor('#E0D5CF')
              .layoutWeight(1)
            Text('点卡片打开播放面板')
              .fontSize(AppFontSize.MICRO)
              .fontColor('#B3E0D5CF')
          }
          .width('100%')
        }
        .width('100%')

        Row() {
          this.speedChip()
          Blank()
          this.controlButton($r('sys.symbol.backward_end_fill'), '上一章', this.ttsCanPrevious,
            () => ReaderTtsFloatingSession.previous())
          this.playButton()
          this.controlButton($r('sys.symbol.forward_end_fill'), '下一章', this.ttsCanNext,
            () => ReaderTtsFloatingSession.next())
          Blank()
          this.timerChip()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        Row({ space: AppSpacing.SM }) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(18)
            .fontColor(['#2A2420'])
          Text('继续收听')
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor('#2A2420')
        }
        .height(40)
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
        .borderRadius(20)
        .backgroundColor('#FFFFFF')
        .alignSelf(ItemAlign.Start)
      }
    }
    .width('100%')
    .padding(AppSpacing.XL)
    // 底图挂在 background 上，跟着内容的大小走；直接叠在 Stack 里放进 Scroll 会量不出高度。
    .background(this.heroBackdrop())
    .borderRadius(ThemeRuntime.largeRadius())
    .clip(true)
    .onClick(() => this.onHeroTap())
  }

  /** 播放卡底图：封面放大模糊，再压一层暗色。 */
  @Builder
  heroBackdrop() {
    Stack() {
      Stack() {
        if (this.heroBookUrl()) {
          BookCover({
            bookUrl: this.heroBookUrl(),
            origin: this.heroOrigin(),
            coverUrl: this.heroCoverUrl(),
            customCoverUrl: this.heroCustomCoverUrl(),
            name: this.heroName(),
            placeholderColor: this.accentColor(),
            cornerRadius: 0,
            decodeWidth: 120,
            decodeHeight: 160
          })
        }
      }
      .width('100%')
      .height('100%')
      .scale({ x: 1.4, y: 1.4 })
      .blur(60)
      .backgroundColor('#3A3533')

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#73120E0C')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  playButton() {
    Row() {
      SymbolGlyph(this.ttsPaused ? $r('sys.symbol.play_fill') : $r('sys.symbol.pause_fill'))
        .fontSize(26)
        .fontColor(['#2A2420'])
    }
    .width(60)
    .height(60)
    .borderRadius(30)
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#FFFFFF')
    .accessibilityText(this.ttsPaused ? '继续播放' : '暂停')
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
    .onClick(() => ReaderTtsFloatingSession.toggle())
  }

  @Builder
  controlButton(icon: Resource, label: string, enabled: boolean, action: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor(['#FFFFFF'])
    }
    .width(44)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .opacity(enabled ? 1 : 0.35)
    .enabled(enabled)
    .accessibilityText(label)
    .onClick(action)
  }

  /** 倍速：点一下换下一档，和播放面板同步。 */
  @Builder
  speedChip() {
    Text(this.speedLabel())
      .fontSize(AppFontSize.CAPTION)
      .fontWeight(FontWeight.Medium)
      .fontColor('#FFFFFF')
      .textAlign(TextAlign.Center)
      .width(54)
      .height(32)
      .borderRadius(16)
      .border({ width: 1, color: '#59FFFFFF' })
      .accessibilityText(`倍速 ${this.speedLabel()}，点按切换`)
      .onClick(() => ReaderTtsFloatingSession.setSpeed(this.nextSpeed()))
  }

  /** 定时关闭：点开选时长，开着时显示剩余分钟。 */
  @Builder
  timerChip() {
    Row({ space: 3 }) {
      SymbolGlyph($r('sys.symbol.timer'))
        .fontSize(14)
        .fontColor(['#FFFFFF'])
      if (this.ttsTimerMinutes > 0) {
        Text(`${this.timerRemainingMinutes()}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#FFFFFF')
      }
    }
    .width(54)
    .height(32)
    .borderRadius(16)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.ttsTimerMinutes > 0 ? '#40FFFFFF' : '#1FFFFFFF')
    .accessibilityText(this.ttsTimerMinutes > 0 ? `定时关闭，剩 ${this.timerRemainingMinutes()} 分钟` : '定时关闭')
    .bindPopup(this.showTimerMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
      this.timerMenu()
    }, Placement.TopRight, this.appDarkMode, this.accentColor(), () => {
      this.showTimerMenu = false;
    }))
    .onClick(() => {
      this.showTimerMenu = !this.showTimerMenu;
    })
  }

  @Builder
  timerMenu() {
    Column({ space: AppSpacing.XXS }) {
      ForEach(ListenTabPage.TIMER_MINUTES, (minutes: number) => {
        PopupMenuAction($r('sys.symbol.timer'), `${minutes} 分钟后停止`,
          this.ttsTimerMinutes === minutes ? this.accentColor() : this.primaryTextColor(), () => {
            this.showTimerMenu = false;
            ReaderTtsFloatingSession.setTimer(minutes);
          })
      }, (minutes: number) => `${minutes}`)
      if (this.ttsTimerMinutes > 0) {
        PopupMenuAction($r('sys.symbol.xmark'), '关闭定时', this.primaryTextColor(), () => {
          this.showTimerMenu = false;
          ReaderTtsFloatingSession.setTimer(0);
        })
      }
    }
    .width(200)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  emptyCard() {
    Column({ space: AppSpacing.SM }) {
      SymbolGlyph($r('sys.symbol.earphone'))
        .fontSize(32)
        .fontColor([this.subTextColor()])
      Text(this.webParseEnabled ? '还没有有声书' : '还没有在听的内容')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
      Text(this.webParseEnabled ? '在发现或搜索里找到有声书加入书架，或在阅读页开始朗读，这里就会出现' :
        '在阅读页开始朗读，这里就会出现')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: 28, bottom: 28 })
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(this.cardColor())
  }

  @Builder
  audioBookCell(item: ListenBookItem) {
    Column({ space: AppSpacing.XS }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        BookCover({
          bookUrl: item.book.bookUrl,
          origin: item.book.origin,
          coverUrl: item.book.coverUrl,
          customCoverUrl: item.book.customCoverUrl,
          name: item.book.name,
          author: item.book.author,
          placeholderColor: this.accentColor(),
          cornerRadius: 14,
          decodeWidth: 240,
          decodeHeight: 320
        })
        if (item.offline) {
          Row() {
            SymbolGlyph($r('sys.symbol.arrow_down'))
              .fontSize(12)
              .fontColor(['#FFFFFF'])
          }
          .width(20)
          .height(20)
          .borderRadius(10)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#80000000')
          .margin(6)
          .accessibilityText('已下载')
        }
      }
      .width(ListenTabPage.SHELF_COVER_SIZE)
      .height(ListenTabPage.SHELF_COVER_SIZE)
      .borderRadius(14)
      .clip(true)

      Text(item.book.name)
        .fontSize(AppFontSize.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Progress({ value: this.audioProgressPercent(item.book), total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(3)
        .color(this.accentColor())
        .backgroundColor(ThemeRuntime.hairlineColor(this.appDarkMode))
        .style({ strokeWidth: 3, strokeRadius: 1.5 })
      Text(this.audioProgressText(item.book))
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.subTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width(ListenTabPage.SHELF_COVER_SIZE)
    .onClick(() => this.openAudioBook(item.book))
  }

  @Builder
  entryTile(entry: ListenEntry) {
    Column({ space: AppSpacing.SM }) {
      SymbolGlyph(entry.icon)
        .fontSize(22)
        .fontColor([this.accentColor()])
      Text(entry.title)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(72)
    .justifyContent(FlexAlign.Center)
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(this.cardColor())
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => {
      router.pushUrl({ url: entry.url });
    })
  }

  /** 没在播时用最近听的有声书。 */
  heroBook(): Book | undefined {
    return !this.ttsActive && this.audioBooks.length > 0 ? this.audioBooks[0].book : undefined;
  }

  heroBookUrl(): string {
    if (this.ttsActive) return this.ttsBookUrl;
    const book = this.heroBook();
    return book ? book.bookUrl : '';
  }

  heroOrigin(): string {
    const book = this.heroBook();
    return book ? book.origin : '';
  }

  heroCoverUrl(): string {
    const book = this.heroBook();
    return book ? book.coverUrl : '';
  }

  heroCustomCoverUrl(): string {
    const book = this.heroBook();
    return book ? book.customCoverUrl : '';
  }

  heroName(): string {
    if (this.ttsActive) return this.ttsBookName || '未命名';
    const book = this.heroBook();
    return book ? book.name : '';
  }

  heroSubtitle(): string {
    if (this.ttsActive) return this.ttsChapterTitle;
    const book = this.heroBook();
    return book ? (book.durChapterTitle || book.author) : '';
  }

  heroBadge(): string {
    if (!this.ttsActive) return '上次收听';
    const state = this.ttsPaused ? '已暂停' : (this.ttsMode === 'audio' ? '收听中' : '朗读中');
    return this.ttsMode !== 'audio' && this.ttsVoiceCode ? `${state} · ${this.ttsVoiceCode}` : state;
  }

  heroPercent(): number {
    const value = this.ttsChapterPercent >= 0 ? this.ttsChapterPercent : this.ttsProgress;
    return Math.max(0, Math.min(100, value || 0));
  }

  heroPercentText(): string {
    const percent = Math.round(this.heroPercent());
    return this.ttsChapterPercent >= 0 ? `本章 ${percent}%` : `${percent}%`;
  }

  onHeroTap(): void {
    if (this.ttsActive) {
      AppStorage.setOrCreate('globalTtsPanelRequest', (AppStorage.get<number>('globalTtsPanelRequest') || 0) + 1);
      return;
    }
    const book = this.heroBook();
    if (book) this.openAudioBook(book);
  }

  speedLabel(): string {
    const speed = Math.round((this.ttsSpeed || 1) * 100) / 100;
    const oneDecimal = Math.abs(speed * 10 - Math.round(speed * 10)) < 0.001;
    return `${speed.toFixed(oneDecimal ? 1 : 2)}×`;
  }

  nextSpeed(): number {
    const speed = this.ttsSpeed || 1;
    const next = ListenTabPage.SPEEDS.find((value: number): boolean => value > speed + 0.01);
    return next ?? ListenTabPage.SPEEDS[0];
  }

  timerRemainingMinutes(): number {
    return this.ttsTimerRemainingSeconds > 0 ? Math.ceil(this.ttsTimerRemainingSeconds / 60) : this.ttsTimerMinutes;
  }

  audioProgressPercent(book: Book): number {
    if (!book.durChapterTime || book.totalChapterNum <= 0) return 0;
    return Math.max(0, Math.min(100, (book.durChapterIndex + 1) * 100 / book.totalChapterNum));
  }

  audioProgressText(book: Book): string {
    if (!book.durChapterTime) return '未开始';
    if (book.totalChapterNum > 0) return `${Math.min(book.durChapterIndex + 1, book.totalChapterNum)}/${book.totalChapterNum} 集`;
    return book.durChapterTitle || '已收听';
  }

  openAudioBook(book: Book): void {
    router.pushUrl({ url: 'pages/AudioBook', params: { bookUrl: book.bookUrl } }).catch((error: Error) => {
      console.error('打开有声书失败:', error);
    });
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
