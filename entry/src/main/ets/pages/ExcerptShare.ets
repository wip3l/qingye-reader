import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';
import { PageScaffold } from '../components/common/PageScaffold';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { ExcerptPosterOptions, ExcerptPosterRenderer, ExcerptPosterSession,
  ExcerptPosterSnapshot } from '../core/excerpt/ExcerptPoster';
import { ReadStatsPosterPalette, ReadStatsPosterRenderer } from '../core/stats/ReadStatsPosterRenderer';
import { ImageFileExport } from '../utils/ImageFileExport';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { syncSystemBars } from '../utils/SystemBars';
import { KnockShare } from '../utils/KnockShare';

const EXCERPT_POSTER_STORE: string = 'excerpt_poster';
const EXCERPT_POSTER_KEY: string = 'options';

/** 摘录分享图：预览 + 样式与显示内容 + 保存/分享。摘录由 ExcerptPosterSession 带进来。 */
@Entry
@Component
struct ExcerptSharePage {
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State headerCollapse: number = 0;
  @State snapshot: ExcerptPosterSnapshot = new ExcerptPosterSnapshot();
  @State options: ExcerptPosterOptions = new ExcerptPosterOptions();
  @State previewUri: string = '';
  @State previewHeight: number = 1400;
  @State rendering: boolean = true;
  @State busy: boolean = false;
  @State errorText: string = '';
  @State ready: boolean = false;
  private scroller: Scroller = new Scroller();
  private alive: boolean = false;
  private revision: number = 0;
  private debounce: number = -1;
  private renderQueue: Promise<void> = Promise.resolve();
  private settingsQueue: Promise<void> = Promise.resolve();
  private previewPath: string = '';
  private knockShareOwner: string = `excerpt-share-${Date.now()}-${Math.random()}`;

  aboutToAppear(): void {
    this.alive = true;
    this.initialize();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.revision++;
    if (this.debounce !== -1) clearTimeout(this.debounce);
    KnockShare.detach(this.knockShareOwner);
  }

  onPageShow(): void {
    KnockShare.attachFile(this.knockShareOwner, (): string => this.ready && !this.rendering ? this.previewPath : '',
      '摘录分享图');
    syncSystemBars(this.context(), this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private async initialize(): Promise<void> {
    const snapshot = ExcerptPosterSession.take();
    if (!snapshot || !snapshot.quote.trim()) {
      this.rendering = false;
      this.errorText = '请从摘录或划线重新进入';
      return;
    }
    this.snapshot = snapshot;
    let saved = false;
    try {
      const store = await preferences.getPreferences(this.context(), EXCERPT_POSTER_STORE);
      const raw = await store.get(EXCERPT_POSTER_KEY, '');
      if (typeof raw === 'string' && raw) {
        this.options = ExcerptPosterOptions.normalize(JSON.parse(raw) as ExcerptPosterOptions);
        saved = true;
      }
    } catch (_) { /* 默认选项也能出图。 */ }
    if (!this.alive) return;
    // 第一次用：没登录就不署名。
    if (!saved && !snapshot.nickname) this.options.signature = false;
    this.ready = true;
    this.scheduleRender(false);
    ReadStatsPosterRenderer.cleanExpired(this.context());
  }

  private changed(): void {
    this.options = ExcerptPosterOptions.normalize(this.options);
    this.scheduleRender(true);
    const settings = JSON.stringify(this.options);
    const context = this.context();
    this.settingsQueue = this.settingsQueue.catch(() => {}).then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, EXCERPT_POSTER_STORE);
      await store.put(EXCERPT_POSTER_KEY, settings);
      await store.flush();
    }).catch((): void => { /* 存选项失败不影响出图。 */ });
  }

  private scheduleRender(debounce: boolean): void {
    const version = ++this.revision;
    if (this.debounce !== -1) clearTimeout(this.debounce);
    // 改选项时旧预览先留着，新图出来前不能导出。
    this.previewPath = '';
    this.errorText = '';
    this.rendering = true;
    this.debounce = setTimeout((): void => {
      this.debounce = -1;
      this.renderQueue = this.renderQueue.catch(() => {}).then(async (): Promise<void> => {
        if (!this.alive || version !== this.revision) return;
        const options = ExcerptPosterOptions.normalize(this.options);
        try {
          const path = await ExcerptPosterRenderer.render(this.context(), this.snapshot, options,
            (): boolean => !this.alive || version !== this.revision);
          if (!this.alive || version !== this.revision) return;
          this.previewPath = path;
          this.previewUri = fileUri.getUriFromPath(path);
        } catch (_) {
          if (this.alive && version === this.revision) this.errorText = '分享图生成失败，请点击重试';
        } finally {
          if (this.alive && version === this.revision) this.rendering = false;
        }
      });
    }, debounce ? 300 : 0);
  }

  private async exportImage(save: boolean): Promise<void> {
    if (!this.ready || this.busy || this.rendering || !this.previewPath) return;
    this.busy = true;
    try {
      this.getUIContext().getFocusController().clearFocus();
      if (save) {
        const saved = await ImageFileExport.save(this.context(), [this.previewPath]);
        if (saved && this.alive) this.toast('已保存到图库');
      } else {
        await ImageFileExport.share(this.context(), [this.previewPath]);
      }
    } catch (_) {
      if (this.alive) this.toast(save ? '保存失败，请重试' : '分享未完成，请重试或保存图片');
    } finally {
      if (this.alive) this.busy = false;
    }
  }

  @Builder
  preview() {
    Column({ space: 12 }) {
      if (this.previewUri) {
        Image(this.previewUri)
          .width('100%')
          .objectFit(ImageFit.Contain)
          .borderRadius(12)
          .accessibilityText('摘录分享图预览')
          .onComplete((event) => {
            if (event && event.width > 0) {
              this.previewHeight = Number(event.height) / Number(event.width) * ExcerptPosterRenderer.WIDTH;
            }
          })
          .aspectRatio(ExcerptPosterRenderer.WIDTH / this.previewHeight)
        if (this.rendering) {
          Text('正在更新预览…').fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        } else if (this.errorText) {
          Button(this.errorText).fontSize(AppFontSize.CAPTION).onClick((): void => { this.scheduleRender(false); })
        }
      } else {
        Column({ space: 16 }) {
          if (this.rendering) {
            LoadingProgress().width(32).height(32).color(ThemeRuntime.accentColor(this.appDarkMode))
          }
          Text(this.rendering ? '正在生成分享图' : this.errorText)
            .fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          if (!this.rendering && this.ready) {
            Button('重试').onClick((): void => { this.scheduleRender(false); })
          }
        }
        .width('100%').height(360).justifyContent(FlexAlign.Center)
        .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode)).borderRadius(12)
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: 440 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  stylePicker() {
    Row({ space: 8 }) {
      ForEach(ExcerptPosterRenderer.STYLE_NAMES, (name: string, index: number) => {
        Column({ space: 6 }) {
          Stack() {
            Text('“')
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.swatch(index).accent)
          }
          .width('100%')
          .height(54)
          .borderRadius(8)
          .backgroundColor(this.swatch(index).background)
          .border({ width: this.options.style === index ? 2 : 0.5,
            color: this.options.style === index ? ThemeRuntime.accentColor(this.appDarkMode) :
              ThemeRuntime.hairlineColor(this.appDarkMode) })
          Text(name)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.options.style === index ? ThemeRuntime.accentColor(this.appDarkMode) :
              ThemeRuntime.primaryTextColor(this.appDarkMode))
            .maxLines(1)
        }
        .layoutWeight(1)
        .accessibilityText(`${name}${this.options.style === index ? '，已选择' : ''}`)
        .onClick((): void => {
          this.options.style = index;
          this.changed();
        })
      }, (name: string): string => name)
    }
    .width('100%')
  }

  /** 书封取色的小样没有具体封面，用纸上时光的颜色加一层封面色示意。 */
  swatch(style: number): ReadStatsPosterPalette {
    const palette = ExcerptPosterRenderer.swatch(style);
    if (style === 3) {
      const tinted = new ReadStatsPosterPalette();
      tinted.background = '#3A3157';
      tinted.accent = '#CFC4F2';
      return tinted;
    }
    return palette;
  }

  @Builder
  switchRow(title: string, description: string, isOn: boolean, onChange: (value: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        if (description) {
          Text(description).fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(ThemeRuntime.accentColor(this.appDarkMode))
        .accessibilityText(title)
        .onChange((value: boolean): void => onChange(value))
    }
    .width('100%')
  }

  @Builder
  settings() {
    Column({ space: 16 }) {
      this.stylePicker()
      Column({ space: 16 }) {
        if (this.snapshot.note.trim()) {
          this.switchRow('我的想法', '', this.options.note, (value: boolean): void => {
            this.options.note = value;
            this.changed();
          })
        }
        this.switchRow('书籍封面', this.snapshot.coverUrl ? '' : '这本书不在书架上，没有封面',
          this.options.cover, (value: boolean): void => {
            this.options.cover = value;
            this.changed();
          })
        this.switchRow('章节与日期', '', this.options.meta, (value: boolean): void => {
          this.options.meta = value;
          this.changed();
        })
        this.switchRow('署名', this.snapshot.nickname ? '' : '未登录时请在下面填写署名', this.options.signature,
          (value: boolean): void => {
            this.options.signature = value;
            this.changed();
          })
        if (this.options.signature) {
          TextInput({ text: this.options.alias, placeholder: this.snapshot.nickname || '填写署名' })
            .maxLength(24)
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
            .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
            .onChange((text: string): void => {
              this.options.alias = text;
              this.changed();
            })
        }
        this.switchRow('划线颜色做点缀', '引号和原文旁的竖线用这条划线的颜色', this.options.accent,
          (value: boolean): void => {
            this.options.accent = value;
            this.changed();
          })
      }
      .padding(16)
      .width('100%')
      .borderRadius(16)
      .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
      Text(`原文超过 ${ExcerptPosterRenderer.QUOTE_LIMIT} 字时只放前面一部分。`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
    }
    .width('100%')
    .enabled(this.ready && !this.busy)
  }

  @Builder
  actions() {
    Row({ space: 12 }) {
      Button('保存图片').layoutWeight(1).height(46)
        .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode)).fontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .border({ width: 1, color: ThemeRuntime.accentColor(this.appDarkMode) })
        .onClick((): void => { this.exportImage(true); })
      Button('分享').layoutWeight(1.2).height(46)
        .backgroundColor(ThemeRuntime.accentColor(this.appDarkMode))
        .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.accentColor(this.appDarkMode)))
        .onClick((): void => { this.exportImage(false); })
    }
    .width('100%')
    .enabled(this.ready && !this.rendering && !this.busy && !!this.previewUri && !this.errorText)
    .padding({ top: 10, bottom: this.navBarHeight + 12, left: 20, right: 20 })
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
  }

  @Builder
  content() {
    Column() {
      Scroll(this.scroller) {
        Column({ space: 20 }) {
          this.preview()
          this.settings()
        }
        .width('100%')
        .constraintSize({ maxWidth: 640 })
        .padding({ top: PageScaffold.BAR_HEIGHT + this.statusBarHeight + 20, bottom: 20, left: 20, right: 20 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .onDidScroll((_xOffset: number, yOffset: number) => {
        this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset, this.scroller.currentOffset().yOffset);
      })
      .onScrollStop(() => {
        const target = CollapsingHeader.settle(this.headerCollapse, this.scroller.currentOffset().yOffset);
        if (target !== this.headerCollapse) {
          this.getUIContext().animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
            this.headerCollapse = target;
          });
        }
      })
      this.actions()
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      PageScaffold({ title: '分享摘录', scrollable: false, edgeToEdge: true, externalCollapse: this.headerCollapse,
        content: (): void => { this.content(); } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
