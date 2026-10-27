import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { PageScaffold } from '../components/common/PageScaffold';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { ReadStatsPosterSnapshot, ReadStatsPosterSession, ReadStatsPosterOptions, ReadStatsPosterLayout,
  ReadStatsPosterPage } from '../core/stats/ReadStatsPosterModel';
import { ReadStatsPosterRenderer, ReadStatsPosterPalette } from '../core/stats/ReadStatsPosterRenderer';
import { ImageFileExport } from '../utils/ImageFileExport';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { syncSystemBars } from '../utils/SystemBars';

const POSTER_RANK_LIMITS: number[] = [3, 5, 10, -1, 0];
const POSTER_RANK_LABELS: string[] = ['前3本', '前5本', '前10本', '全部书籍', '隐藏排行'];

interface ReadStatsPosterChoice {
  label: string;
  selected: boolean;
  onSelect: () => void;
}

@Entry
@Component
struct ReadingStatsSharePage {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State headerCollapse: number = 0;
  private headerScroller: Scroller = new Scroller();
  private previewScroller: Scroller = new Scroller();
  private settingsScroller: Scroller = new Scroller();
  @StorageProp('accountUserId') @Watch('accountChanged') accountUserId: string = '';
  @State snapshot: ReadStatsPosterSnapshot = new ReadStatsPosterSnapshot();
  @State options: ReadStatsPosterOptions = new ReadStatsPosterOptions();
  @State pageIndex: number = 0;
  @State previewUri: string = '';
  @State previewHeight: number = 1600;
  @State rendering: boolean = true;
  @State busy: boolean = false;
  @State progressText: string = '';
  @State errorText: string = '';
  @State wide: boolean = false;
  @State onlyCurrent: boolean = false;
  @State ready: boolean = false;
  private alive: boolean = false;
  private revision: number = 0;
  private debounce: number = -1;
  private renderQueue: Promise<void> = Promise.resolve();
  private settingsQueue: Promise<void> = Promise.resolve();
  private previewPath: string = '';
  private cachedPages: Map<number, string> = new Map<number, string>();

  aboutToAppear(): void { this.alive = true; this.initialize(); }
  aboutToDisappear(): void {
    this.alive = false; this.revision++;
    if (this.debounce !== -1) clearTimeout(this.debounce);
    this.cachedPages.clear();
  }
  onPageShow(): void {
    syncSystemBars(this.context(), this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
    if (this.ready) this.accountChanged();
  }

  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private owner(): string { return AccountSessionStore.isLoggedIn() ? AccountSessionStore.account().userId : ''; }
  private valid(): boolean { return this.alive && this.ready && this.owner() === this.snapshot.ownerId; }
  private toast(message: string): void { this.getUIContext().getPromptAction().showToast({ message: message }); }

  private accountChanged(): void {
    if (!this.ready || this.owner() === this.snapshot.ownerId) return;
    this.revision++; this.ready = false; this.previewUri = ''; this.previewPath = ''; this.cachedPages.clear();
    this.snapshot = new ReadStatsPosterSnapshot();
    this.options = new ReadStatsPosterOptions();
    this.rendering = false;
    this.errorText = '账号已切换，请返回阅读统计重新生成';
  }

  private async initialize(): Promise<void> {
    const snapshot = ReadStatsPosterSession.take();
    if (!snapshot || snapshot.totalMs <= 0 || snapshot.ownerId !== this.owner()) {
      this.rendering = false; this.errorText = '请从阅读统计页面重新进入'; return;
    }
    this.snapshot = snapshot;
    try {
      const store = await preferences.getPreferences(this.context(), 'reading_stats_poster');
      const raw = await store.get(`account:${snapshot.ownerId || 'guest'}`, '');
      if (!this.alive) return;
      if (this.owner() === snapshot.ownerId && typeof raw === 'string' && raw) {
        try { this.options = ReadStatsPosterOptions.normalize(JSON.parse(raw) as ReadStatsPosterOptions); } catch (_) {}
      }
    } catch (_) { /* Default settings also work without preferences. */ }
    if (!this.alive) return;
    this.ready = true;
    if (this.owner() !== snapshot.ownerId) { this.accountChanged(); return; }
    this.scheduleRender(false);
    ReadStatsPosterRenderer.cleanExpired(this.context());
  }

  private pages(): ReadStatsPosterPage[] { return ReadStatsPosterLayout.pages(this.snapshot, this.options); }
  private page(): ReadStatsPosterPage { return this.pages()[this.pageIndex] || this.pages()[0]; }

  private changed(): void {
    this.options = ReadStatsPosterOptions.normalize(this.options);
    this.pageIndex = Math.min(this.pageIndex, this.pages().length - 1);
    if (this.pages().length > 100) this.onlyCurrent = true;
    this.cachedPages.clear();
    this.scheduleRender(true);
    const owner = this.snapshot.ownerId;
    const settings = JSON.stringify(this.options);
    const context = this.context();
    this.settingsQueue = this.settingsQueue.catch(() => {}).then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, 'reading_stats_poster');
      await store.put(`account:${owner || 'guest'}`, settings);
      await store.flush();
    }).catch((): void => { /* Never block image generation on a preference write. */ });
  }

  private scheduleRender(debounce: boolean): void {
    const version = ++this.revision;
    if (this.debounce !== -1) clearTimeout(this.debounce);
    // Keep the last preview in place while editing so the inputs do not jump vertically.
    // It cannot be exported until the new image has finished successfully.
    this.previewPath = ''; this.errorText = ''; this.rendering = true;
    this.debounce = setTimeout((): void => {
      this.debounce = -1;
      this.renderQueue = this.renderQueue.catch(() => {}).then(async (): Promise<void> => {
        if (!this.valid() || version !== this.revision) return;
        const page = this.page();
        const options = ReadStatsPosterOptions.normalize(this.options);
        try {
          const path = this.cachedPages.get(page.index) || await ReadStatsPosterRenderer.render(this.context(), this.snapshot,
            options, page, (): boolean => !this.valid() || version !== this.revision);
          if (!this.valid() || version !== this.revision) return;
          this.cachedPages.set(page.index, path);
          this.previewHeight = page.height;
          this.previewPath = path; this.previewUri = fileUri.getUriFromPath(path);
        } catch (_) {
          if (this.valid() && version === this.revision) this.errorText = '海报生成失败，请点击重试';
        } finally { if (this.alive && version === this.revision) this.rendering = false; }
      });
    }, debounce ? 300 : 0);
  }

  private async exportPoster(save: boolean): Promise<void> {
    if (!this.valid() || this.busy || this.rendering || !this.previewPath) return;
    const version = this.revision;
    const options = ReadStatsPosterOptions.normalize(this.options);
    const snapshot = this.snapshot;
    const pages = this.onlyCurrent ? [this.page()] : this.pages();
    if (pages.length > 100) { this.toast('海报较多，请选择当前页后逐页分享或保存'); return; }
    this.busy = true;
    try {
      this.getUIContext().getFocusController().clearFocus();
      const paths: string[] = [];
      for (const page of pages) {
        this.progressText = `正在准备图片 ${paths.length + 1}/${pages.length}`;
        const path = this.cachedPages.get(page.index) || await ReadStatsPosterRenderer.render(this.context(), snapshot, options,
          page, (): boolean => !this.valid() || version !== this.revision);
        if (!this.valid() || version !== this.revision) return;
        this.cachedPages.set(page.index, path); paths.push(path);
      }
      this.progressText = save ? '正在打开保存窗口' : '正在打开系统分享';
      if (save) {
        const saved = await ImageFileExport.save(this.context(), paths);
        if (saved && this.valid()) this.toast(`已保存${paths.length > 1 ? `${paths.length}张` : ''}海报`);
      } else { await ImageFileExport.share(this.context(), paths); }
    } catch (_) {
      if (this.valid() && version === this.revision) this.toast(save ? '保存失败，请重试' : '分享未完成，请重试或保存图片');
    } finally { if (this.alive) { this.busy = false; this.progressText = ''; } }
  }

  private movePage(step: number): void {
    this.pageIndex = Math.max(0, Math.min(this.pages().length - 1, this.pageIndex + step));
    this.scheduleRender(false);
  }

  @Builder
  preview() {
    Column({ space: 12 }) {
      if (this.previewUri) {
        Image(this.previewUri).width('100%').aspectRatio(ReadStatsPosterLayout.WIDTH / this.previewHeight)
          .objectFit(ImageFit.Contain).borderRadius(12).accessibilityText('阅读统计分享海报预览')
        if (this.rendering) {
          Text('正在更新预览…').fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        } else if (this.errorText) {
          Button(this.errorText).fontSize(AppFontSize.CAPTION).onClick((): void => { this.scheduleRender(false); })
        }
      } else {
        Column({ space: 16 }) {
          if (this.rendering) { LoadingProgress().width(32).height(32).color(ThemeRuntime.accentColor(this.appDarkMode)) }
          Text(this.rendering ? '正在生成海报' : this.errorText)
            .fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          if (!this.rendering && this.ready) { Button('重试').onClick((): void => { this.scheduleRender(false); }) }
        }.width('100%').height(360).justifyContent(FlexAlign.Center)
          .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode)).borderRadius(12)
      }
      if (this.pages().length > 1) {
        Row({ space: 20 }) {
          Button('上一页').enabled(this.pageIndex > 0 && !this.busy).onClick((): void => { this.movePage(-1); })
          Text(`${this.pageIndex + 1} / ${this.pages().length}`).fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          Button('下一页').enabled(this.pageIndex < this.pages().length - 1 && !this.busy)
            .onClick((): void => { this.movePage(1); })
        }.width('100%').justifyContent(FlexAlign.Center)
      }
    }.width('100%').constraintSize({ maxWidth: 480 }).alignItems(HorizontalAlign.Center)
  }

  @Builder
  stylePicker() {
    Row({ space: 8 }) {
      ForEach(ReadStatsPosterLayout.STYLE_NAMES, (name: string, index: number) => {
        Button() {
          Column({ space: 8 }) {
            Column({ space: 5 }) {
              Text('阅读时光').fontSize(11).fontColor(ReadStatsPosterPalette.of(index).ink)
              Text('12h').fontSize(22).fontWeight(FontWeight.Bold).fontColor(ReadStatsPosterPalette.of(index).accent)
              Row().height(3).width('70%').backgroundColor(ReadStatsPosterPalette.of(index).line)
            }.width('100%').height(82).justifyContent(FlexAlign.Center)
              .backgroundColor(ReadStatsPosterPalette.of(index).background).borderRadius(8)
            Text(name).fontSize(11).fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode)).maxLines(1)
          }.padding(5)
        }.layoutWeight(1).type(ButtonType.Normal).borderRadius(12)
          .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
          .border({ width: this.options.style === index ? 2 : 1,
            color: this.options.style === index ? ThemeRuntime.accentColor(this.appDarkMode) : ThemeRuntime.inputColor(this.appDarkMode) })
          .accessibilityText(`${name}${this.options.style === index ? '，已选择' : ''}`)
          .onClick((): void => { this.options.style = index; this.changed(); })
      }, (name: string): string => name)
    }.width('100%')
  }

  @Builder
  infoChoice($$: ReadStatsPosterChoice) {
    Button(`${$$.selected ? '✓ ' : ''}${$$.label}`).fontSize(AppFontSize.CAPTION)
      .backgroundColor($$.selected ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : ThemeRuntime.inputColor(this.appDarkMode))
      .fontColor($$.selected ? ThemeRuntime.accentColor(this.appDarkMode) : ThemeRuntime.subTextColor(this.appDarkMode))
      .onClick($$.onSelect)
  }

  @Builder
  settings() {
    Column({ space: 16 }) {
      this.stylePicker()
      Column({ space: 16 }) {
        Row() {
          Text('书籍排行').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          Blank()
          Select(POSTER_RANK_LABELS.map((label: string): SelectOption => ({ value: label })))
            .font({ family: this.applicationFontFamily })
            .selected(POSTER_RANK_LIMITS.indexOf(this.options.rankLimit))
            .value(POSTER_RANK_LABELS[POSTER_RANK_LIMITS.indexOf(this.options.rankLimit)])
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode)).backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
            .onSelect((index: number): void => { this.options.rankLimit = POSTER_RANK_LIMITS[index]; this.changed(); })
        }.width('100%')
        if (this.pages().length > 1) {
          Row() {
            Text('导出范围').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
            Blank()
            Select([{ value: '全部海报' }, { value: '当前页' }]).selected(this.onlyCurrent ? 1 : 0)
              .font({ family: this.applicationFontFamily })
              .value(this.onlyCurrent ? '当前页' : '全部海报')
              .onSelect((index: number): void => { this.onlyCurrent = index === 1; })
          }.width('100%')
          Text(`完整排行已分页，共${this.pages().length}张；不支持多图的App可逐页分享`)
            .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.appDarkMode)).width('100%')
        }
        Row() {
          Text('底部个人信息').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.options.profile }).selectedColor(ThemeRuntime.accentColor(this.appDarkMode))
            .accessibilityText('展示底部个人信息')
            .onChange((enabled: boolean): void => { this.options.profile = enabled; this.changed(); })
        }.width('100%')
        if (this.options.profile) {
          Row({ space: 10 }) {
            this.infoChoice({ label: '头像', selected: this.options.avatar,
              onSelect: (): void => { this.options.avatar = !this.options.avatar; this.changed(); } })
            this.infoChoice({ label: '昵称', selected: this.options.nickname,
              onSelect: (): void => { this.options.nickname = !this.options.nickname; this.changed(); } })
            this.infoChoice({ label: '一句话', selected: this.options.signature,
              onSelect: (): void => { this.options.signature = !this.options.signature; this.changed(); } })
          }.width('100%')
          if (this.options.nickname) {
            TextInput({ text: this.options.alias, placeholder: this.snapshot.nickname || '填写海报署名' }).maxLength(24)
              .fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
              .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
              .onChange((text: string): void => { this.options.alias = text; this.changed(); })
          }
          if (this.options.signature) {
            TextInput({ text: this.options.quote, placeholder: '写一句话，最多40字' }).maxLength(40)
              .fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
              .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
              .onChange((text: string): void => { this.options.quote = text; this.changed(); })
          }
        }
      }.padding(16).width('100%').borderRadius(16).backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
      Text('海报使用进入预览时的统计数据，重新进入可更新。')
        .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
    }.width('100%').enabled(this.ready && !this.busy)
  }

  @Builder
  actions() {
    Column({ space: 8 }) {
      if (this.busy) {
        Text(this.progressText).fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      }
      Row({ space: 12 }) {
        Button('保存图片').layoutWeight(1).height(46)
          .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode)).fontColor(ThemeRuntime.accentColor(this.appDarkMode))
          .border({ width: 1, color: ThemeRuntime.accentColor(this.appDarkMode) })
          .onClick((): void => { this.exportPoster(true); })
        Button('生成并分享').layoutWeight(1.2).height(46)
          .backgroundColor(ThemeRuntime.accentColor(this.appDarkMode)).fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.accentColor(this.appDarkMode)))
          .onClick((): void => { this.exportPoster(false); })
      }.width('100%').enabled(this.ready && !this.rendering && !this.busy && !!this.previewUri && !this.errorText)
    }.padding({ top: 10, bottom: this.navBarHeight + 12, left: 20, right: 20 }).width('100%')
      .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
  }

  @Builder
  content() {
    Column() {
      if (this.wide) {
        Row({ space: 28 }) {
          Scroll(this.previewScroller) {
            Column() { this.preview() }
              .width('100%').padding({ top: PageScaffold.BAR_HEIGHT + this.statusBarHeight + 12, bottom: 12 })
          }.layoutWeight(1).height('100%').scrollBar(BarState.Off).align(Alignment.Top)
            .onDidScroll((_xOffset: number, yOffset: number) => {
              this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
                this.previewScroller.currentOffset().yOffset);
            })
            .onScrollStop(() => { this.settleHeader(this.previewScroller); })
          Scroll(this.settingsScroller) {
            Column() { this.settings() }
              .width('100%').padding({ top: PageScaffold.BAR_HEIGHT + this.statusBarHeight + 12, bottom: 12 })
          }.width(360).height('100%').scrollBar(BarState.Off).align(Alignment.Top)
            .onDidScroll((_xOffset: number, yOffset: number) => {
              this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
                this.settingsScroller.currentOffset().yOffset);
            })
            .onScrollStop(() => { this.settleHeader(this.settingsScroller); })
        }.layoutWeight(1).width('100%').padding({ left: 24, right: 24 }).alignItems(VerticalAlign.Top)
      } else {
        Scroll(this.headerScroller) {
          Column({ space: 20 }) { this.preview(); this.settings() }.width('100%')
            .padding({ top: PageScaffold.BAR_HEIGHT + this.statusBarHeight + 20, bottom: 20, left: 20, right: 20 })
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off).align(Alignment.Top)
          .onDidScroll((_xOffset: number, yOffset: number) => {
            this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
              this.headerScroller.currentOffset().yOffset);
          })
          .onScrollStop(() => { this.settleHeader(this.headerScroller); })
      }
      this.actions()
    }.width('100%').height('100%')
      .onAreaChange((_old: Area, area: Area): void => {
        const wide = Number(area.width) >= 840;
        if (wide !== this.wide) {
          this.headerCollapse = 0;
          this.wide = wide;
        }
      })
  }

  private settleHeader(scroller: Scroller): void {
    const target = CollapsingHeader.settle(this.headerCollapse, scroller.currentOffset().yOffset);
    if (target !== this.headerCollapse) {
      this.getUIContext().animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
        this.headerCollapse = target;
      });
    }
  }

  build() {
    Column() {
      PageScaffold({ title: '分享阅读统计', scrollable: false, edgeToEdge: true, externalCollapse: this.headerCollapse,
        content: (): void => { this.content(); } })
    }.width('100%').height('100%')
      .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
