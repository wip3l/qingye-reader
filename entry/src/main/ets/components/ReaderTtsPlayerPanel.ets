import { BookCover } from './book/BookCover';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ReaderTtsFloatingSession } from '../utils/ReaderTtsFloatingSession';
import deviceInfo from '@ohos.deviceInfo';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { TtsPanelThemeBackground } from './TtsPanelThemeBackground';
import { ImmersiveMaterialSurface } from './ImmersiveMaterialSurface';

/** 顶栏圆形按钮的尺寸。 */
const PANEL_CONTROL_SIZE: number = 40;
const SECONDARY_TIMER: string = 'timer';
const SECONDARY_SPEED: string = 'speed';
const SECONDARY_CATALOG: string = 'catalog';
const SECONDARY_STOP: string = 'stop';
const SECONDARY_DOWNLOAD: string = 'download';

@Component
export struct ReaderTtsPlayerPanel {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @Prop darkMode: boolean = false;
  @Prop accentColor: ResourceColor = '#5B8F86';
  @Prop playButtonColor: ResourceColor = '#5B8F86';
  @Prop primaryTextColor: ResourceColor = '#18191C';
  @Prop subTextColor: ResourceColor = '#71747A';
  @Prop panelColor: ResourceColor = '#F7F7F7';
  // Theme whose panel artwork is drawn behind the controls; empty keeps the plain glass surface.
  @Prop backgroundThemeId: string = '';
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop viewportHeight: number = 720;
  onClose: () => void = () => {};
  onOpenCatalog: () => void = () => {};
  // 书架上的面板脱离了阅读页，朗读模式下给一个回到正文的入口；阅读页自己的面板不显示。
  @Prop showOpenReader: boolean = false;
  onOpenReader: () => void = () => {};
  onOpenVoice: () => void = () => ReaderTtsFloatingSession.openVoice();
  /** 听书页的离线下载入口（下载、边听边下设置）。 */
  onOpenDownload: () => void = () => {};
  onTogglePlayback: () => void = () => {
    ReaderTtsFloatingSession.toggle();
  };
  // 听书页自己的书籍信息与播放状态。共享会话要等第一章音频地址取到后才发布，失败时又会被清掉，
  // 这段时间面板仍显示这本书和加载/失败提示，而不是朗读模式的占位文字。
  @Prop hostAudioPage: boolean = false;
  @Prop hostBookName: string = '';
  @Prop hostBookUrl: string = '';
  @Prop hostChapterTitle: string = '';
  @Prop hostIntro: string = '';
  @Prop hostCover: ResourceStr = '';
  @Prop hostPlaying: boolean = false;
  @Prop hostStatusText: string = '';
  @Prop hostBusy: boolean = false;
  @Prop hostVoiceTitles: string[] = [];
  @Prop hostVoiceIndex: number = 0;
  /** 在线有声书显示"下载"：听书页自己，或书架胶囊打开的面板（听书页发布了离线信息时）。 */
  @Prop hostDownloadAvailable: boolean = false;
  onSelectHostVoice: (index: number) => void = () => {};

  @StorageLink('globalTtsPaused') globalTtsPaused: boolean = false;
  @StorageProp('globalTtsBookUrl') globalTtsBookUrl: string = '';
  @State readyBookCover: ResourceStr = '';
  @StorageLink('globalTtsBookName') globalTtsBookName: string = '';
  @StorageLink('globalTtsChapterTitle') globalTtsChapterTitle: string = '';
  @StorageLink('globalTtsMode') globalTtsMode: string = '';
  @StorageLink('globalTtsVoiceCode') globalTtsVoiceCode: string = '';
  @StorageLink('globalTtsCover') globalTtsCover: ResourceStr = '';
  @StorageLink('globalTtsCoverFrame') globalTtsCoverFrame: ResourceStr = '';
  @StorageLink('globalTtsContent') globalTtsContent: string = '';
  @StorageLink('globalTtsTextBefore') @Watch('onCurrentTextChanged') globalTtsTextBefore: string = '';
  @StorageLink('globalTtsCurrentText') @Watch('onCurrentTextChanged') globalTtsCurrentText: string = '';
  @StorageLink('globalTtsTextAfter') @Watch('onCurrentTextChanged') globalTtsTextAfter: string = '';
  @StorageLink('globalTtsChapterProgress') globalTtsChapterProgress: string = '';
  @StorageLink('globalTtsProgress') globalTtsProgress: number = 0;
  @StorageLink('globalTtsSpeed') globalTtsSpeed: number = 1;
  @StorageLink('globalTtsTimerMinutes') globalTtsTimerMinutes: number = 0;
  @StorageLink('globalTtsTimerRemainingSeconds') globalTtsTimerRemainingSeconds: number = 0;
  @StorageLink('globalTtsCanPrevious') globalTtsCanPrevious: boolean = false;
  @StorageLink('globalTtsCanNext') globalTtsCanNext: boolean = false;
  @StorageLink('globalTtsAudioPositionMs') globalTtsAudioPositionMs: number = 0;
  @StorageLink('globalTtsAudioDurationMs') globalTtsAudioDurationMs: number = 0;
  @StorageLink('globalTtsVoiceRevision') globalTtsVoiceRevision: number = 0;
  @StorageLink('globalTtsStatusText') globalTtsStatusText: string = '';
  @StorageLink('globalTtsBusy') globalTtsBusy: boolean = false;
  @State optionsPanel: number = 0;
  @State audioVoiceMenuRevision: number = 0;
  private textScroller: Scroller = new Scroller();
  private readingTextController: TextController = new TextController();
  private readingViewportHeight: number = 0;
  private textUpdateTimer: number = -1;

  aboutToAppear(): void {
    this.scrollToCurrentSentence(false);
  }

  aboutToDisappear(): void {
    if (this.textUpdateTimer >= 0) clearTimeout(this.textUpdateTimer);
    this.textUpdateTimer = -1;
  }

  onCurrentTextChanged(): void {
    this.scrollToCurrentSentence(true);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.darkMode ? '#52000000' : '#26000000')
        .onClick(() => this.close())

      Stack({ alignContent: Alignment.TopStart }) {
        if (this.backgroundThemeId) {
          TtsPanelThemeBackground({ themeId: this.backgroundThemeId, darkMode: this.darkMode })
        } else {
          this.ambientBackdrop()
        }

        Column({ space: AppSpacing.LG }) {
          this.header()

          if (this.isAudio()) {
            this.audioHero()
          } else {
            this.readingCard()
          }

          if (!this.isAudio() && this.statusText()) {
            this.statusLine()
          }

          if (this.isAudio()) {
            this.audioProgress()
          } else if (this.globalTtsProgress > 0) {
            Progress({ value: this.globalTtsProgress, total: 100, type: ProgressType.Linear })
              .width('100%')
              .height(3)
              .color(this.accentColor)
              .backgroundColor(ThemeRuntime.hairlineColor(this.darkMode))
          }

          this.mainControls()

          if (this.optionsPanel === 1) {
            this.timerOptions()
          } else if (this.optionsPanel === 2) {
            this.speedOptions()
          }

          this.secondaryActions()
        }
        .width('100%')
        .height('100%')
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: this.topInset + 8, bottom: this.bottomInset + 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.backgroundThemeId ? Color.Transparent : ThemeRuntime.pageColor(this.darkMode))
      .transition(TransitionEffect.translate({ y: 520 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 280, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
  }

  /** 没有主题背景图时，用封面做模糊氛围背景，渐隐到页面底色（底色层与渐变层不透明，底部无硬边）。 */
  @Builder
  ambientBackdrop() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.coverSource()) {
        Image(this.coverSource())
          .width('100%')
          .height(this.ambientHeight())
          .objectFit(ImageFit.Cover)
          .sourceSize({ width: 96, height: 128 })
          .blur(48)
          .opacity(this.darkMode ? 0.5 : 0.6)
      }
      Column()
        .width('100%')
        .height(this.ambientHeight())
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            [this.pageColorWithAlpha('40'), 0],
            [this.pageColorWithAlpha('33'), 0.3],
            [this.pageColorWithAlpha('B3'), 0.7],
            [ThemeRuntime.pageColor(this.darkMode), 1]
          ]
        })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  header() {
    Row() {
      this.circleButton($r('sys.symbol.chevron_down'), '收起播放面板', () => this.close())
      Column({ space: AppSpacing.XXS }) {
        Text(this.hostBookName || this.globalTtsBookName || (this.isAudio() ? '听书' : '快速朗读'))
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.isAudio() ? (this.globalTtsChapterProgress || '正在听书') : '正在朗读')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor)
          .maxLines(1)
      }
      .layoutWeight(1)
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
      .alignItems(HorizontalAlign.Center)
      // 与左侧按钮等宽的占位，让标题真正居中。
      Column()
        .width(PANEL_CONTROL_SIZE)
        .height(PANEL_CONTROL_SIZE)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  circleButton(icon: Resource, label: string, action: () => void) {
    ImmersiveMaterialSurface({
      surfaceWidth: PANEL_CONTROL_SIZE,
      surfaceHeight: PANEL_CONTROL_SIZE,
      darkMode: this.darkMode,
      fallbackColor: ThemeRuntime.cardColor(this.darkMode),
      glowColor: this.accentGlowColor()
    }) {
      Stack() {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([this.primaryTextColor])
      }
      .width('100%')
      .height('100%')
      .accessibilityText(label)
      .onClick(() => action())
    }
  }

  /** 听书：大封面居中，下面是章节名、进度与简介。 */
  @Builder
  audioHero() {
    Column({ space: AppSpacing.MD }) {
      Stack() {
        this.heroCover(true)
      }
      .shadow({ radius: 24, color: this.darkMode ? '#73000000' : '#40000000', offsetX: 0, offsetY: 10 })
      .margin({ top: AppSpacing.SM })

      Text(this.hostChapterTitle || this.globalTtsChapterTitle || '正在获取章节…')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .margin({ top: AppSpacing.SM })

      Scroll() {
        Text(this.globalTtsContent || this.hostIntro || '暂无书籍简介')
          .fontSize(AppFontSize.BODY)
          .lineHeight(22)
          .fontColor(this.subTextColor)
          .copyOption(CopyOptions.LocalDevice)
          .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
          .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)

      if (this.statusText()) {
        this.statusLine()
      }

      Row() {
        this.audioVoiceSelect()
      }
      .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 朗读：当前朗读文字放在玻璃卡片里，上下文浅色，当前句高亮并自动居中。 */
  @Builder
  readingCard() {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.MD }) {
        this.heroCover(false)
        Column({ space: AppSpacing.XXS }) {
          Text(this.hostChapterTitle || this.globalTtsChapterTitle || '正在朗读')
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.globalTtsChapterProgress || '')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor)
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.showOpenReader) {
          this.openReaderButton()
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll(this.textScroller) {
        Text(undefined, { controller: this.readingTextController }) {
          Span(this.globalTtsTextBefore)
            .fontColor(this.subTextColor)
          Span(this.globalTtsCurrentText)
            .fontColor(this.primaryTextColor)
            .fontWeight(FontWeight.Medium)
            .textBackgroundStyle({ color: ThemeRuntime.accentSurfaceColor(this.darkMode), radius: 4 })
          Span(this.globalTtsTextAfter || (!this.globalTtsTextBefore && !this.globalTtsCurrentText ?
            (this.globalTtsContent || '正在准备当前朗读内容…') : ''))
            .fontColor(this.subTextColor)
        }
        .fontSize(AppFontSize.BODY_LARGE)
        .lineHeight(28)
        .wordBreak(WordBreak.NORMAL)
        .width('100%')
        .constraintSize({ maxWidth: 840 })
        .onAreaChange((oldArea: Area, area: Area): void => {
          if (oldArea.width !== area.width || oldArea.height !== area.height) {
            this.scrollToCurrentSentence(false);
          }
        })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .onAreaChange((_oldArea: Area, area: Area): void => {
        const height = Number(area.height);
        if (this.readingViewportHeight === height) return;
        this.readingViewportHeight = height;
        this.scrollToCurrentSentence(false);
      })

      if (this.hasTtsVoices()) {
        Row() {
          this.ttsVoiceSelect()
        }
        .width('100%')
      }
    }
    .layoutWeight(1)
    .width('100%')
    .padding(AppSpacing.LG)
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(this.darkMode ? '#991C1C1E' : '#B3FFFFFF')
    .border({ width: 0.5, color: this.darkMode ? '#26FFFFFF' : '#E6FFFFFF' })
  }

  @Builder
  openReaderButton() {
    Row({ space: AppSpacing.XXS }) {
      SymbolGlyph($r('sys.symbol.book'))
        .fontSize(15)
        .fontColor([this.accentColor])
      Text('回到正文')
        .fontSize(AppFontSize.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.accentColor)
        .maxLines(1)
    }
    .height(32)
    .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
    .borderRadius(16)
    .backgroundColor(ThemeRuntime.accentSurfaceColor(this.darkMode))
    .alignItems(VerticalAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
    .accessibilityText('回到正文')
    .onClick(() => {
      this.optionsPanel = 0;
      this.onOpenReader();
    })
  }

  @Builder
  heroCover(large: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.coverBookUrl()) {
        BookCover({ bookUrl: this.coverBookUrl(), name: this.hostAudioPage ? this.hostBookName : this.globalTtsBookName,
          placeholderColor: this.accentColor, cornerRadius: large ? 14 : 6,
          onReadyCover: (cover: ResourceStr): void => { this.readyBookCover = cover; }
        })
      } else {
        Text(this.coverInitial())
          .fontSize(large ? Math.max(16, Math.round(this.coverHeight() * 0.22)) : 16)
          .fontColor(ThemeRuntime.onAccentColor())
      }
    }
    .width(large ? Math.round(this.coverHeight() * 0.75) : 42)
    .height(large ? this.coverHeight() : 56)
    .borderRadius(large ? 14 : 6)
    .clip(true)
    .backgroundColor(this.accentColor)
  }

  @Builder
  statusLine() {
    Row({ space: AppSpacing.SM }) {
      if (this.isBusy()) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.accentColor)
      }
      Text(this.statusText())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.isBusy() ? this.primaryTextColor : ThemeRuntime.dangerColor(this.darkMode))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.SM, bottom: AppSpacing.SM })
    .borderRadius(ThemeRuntime.mediumRadius())
    .backgroundColor(ThemeRuntime.hairlineColor(this.darkMode))
    .alignItems(VerticalAlign.Center)
    .accessibilityText(this.statusText())
  }

  /** 主控制区：上一章、大号播放键、下一章。 */
  @Builder
  mainControls() {
    Row() {
      this.chapterButton(false)
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(68).height(68).fill(this.playButtonColor)
        if (this.isBusy()) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(ThemeRuntime.onAccentColor())
        } else {
          SymbolGlyph(this.isPaused() ? $r('sys.symbol.play_fill') : $r('sys.symbol.pause_fill'))
            .id(`shared_tts_panel_playback_${this.isPaused()}`)
            .fontSize(30)
            .fontColor([ThemeRuntime.onAccentColor()])
        }
      }
      .width(68)
      .height(68)
      .borderRadius(34)
      .shadow({ radius: 16, color: this.darkMode ? '#66000000' : '#33000000', offsetX: 0, offsetY: 6 })
      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.92 })
      .accessibilityText(this.isBusy() ? '正在加载' : (this.isPaused() ? '播放' : '暂停'))
      .onClick(() => {
        if (!this.isBusy()) this.onTogglePlayback();
      })
      this.chapterButton(true)
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 上一章/下一章。可用状态在 Builder 内直接读状态变量：按值传进来的参数不会随状态刷新，
   * 面板先于章节信息打开时按钮会一直停在不可用。
   */
  @Builder
  chapterButton(forward: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(forward ? $r('sys.symbol.forward_end_fill') : $r('sys.symbol.backward_end_fill'))
        .fontSize(30)
        .fontColor([this.chapterEnabled(forward) ? this.primaryTextColor : this.subTextColor])
    }
    .width(56)
    .height(56)
    .opacity(this.chapterEnabled(forward) ? 1 : 0.4)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .accessibilityText(forward ? '下一章' : '上一章')
    .onClick(() => {
      if (!this.chapterEnabled(forward)) return;
      if (forward) {
        ReaderTtsFloatingSession.next();
      } else {
        ReaderTtsFloatingSession.previous();
      }
    })
  }

  /** 底部一排：定时、倍速、目录、停止；音色统一使用内容下方的整行下拉框。 */
  @Builder
  secondaryActions() {
    Row() {
      this.secondaryItem(SECONDARY_TIMER)
      this.secondaryItem(SECONDARY_SPEED)
      this.secondaryItem(SECONDARY_CATALOG)
      if (this.hostDownloadAvailable && this.isAudio()) {
        this.secondaryItem(SECONDARY_DOWNLOAD)
      }
      this.secondaryItem(SECONDARY_STOP)
    }
    .width('100%')
    .padding({ top: AppSpacing.XS })
  }

  /** 文字和高亮在 Builder 内按类型现读状态变量，剩余定时、倍速等变化后立即刷新。 */
  @Builder
  secondaryItem(kind: string) {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph(this.secondaryIcon(kind))
        .fontSize(22)
        .fontColor([this.secondaryColor(kind, true)])
      Text(this.secondaryLabel(kind))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.secondaryColor(kind, false))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
    .accessibilityText(this.secondaryLabel(kind))
    .onClick(() => this.onSecondaryTap(kind))
  }

  @Builder
  timerOptions() {
    Row({ space: AppSpacing.SM }) {
      this.timerChip(0, '关闭')
      this.timerChip(15, '15分')
      this.timerChip(30, '30分')
      this.timerChip(60, '60分')
      this.timerChip(90, '90分')
      this.timerChip(120, '120分')
    }
    .width('100%')
  }

  @Builder
  speedOptions() {
    Row({ space: AppSpacing.MD }) {
      this.speedChip(0.8)
      this.speedChip(1.0)
      this.speedChip(1.2)
      this.speedChip(1.5)
      this.speedChip(2.0)
    }
    .width('100%')
  }

  @Builder
  speedChip(value: number) {
    Text(`${value.toFixed(1)}x`)
      .fontSize(AppFontSize.CAPTION)
      .fontWeight(Math.abs(this.globalTtsSpeed - value) < 0.01 ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(Math.abs(this.globalTtsSpeed - value) < 0.01 ? ThemeRuntime.onAccentColor() : this.primaryTextColor)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(30)
      .borderRadius(ThemeRuntime.buttonRadius())
      .backgroundColor(Math.abs(this.globalTtsSpeed - value) < 0.01 ? this.accentColor :
        (ThemeRuntime.softFillColor(this.darkMode)))
      .onClick(() => ReaderTtsFloatingSession.setSpeed(value))
  }

  @Builder
  timerChip(minutes: number, label: string) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontWeight(this.globalTtsTimerMinutes === minutes ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.globalTtsTimerMinutes === minutes ? ThemeRuntime.onAccentColor() : this.primaryTextColor)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(30)
      .borderRadius(ThemeRuntime.buttonRadius())
      .backgroundColor(this.globalTtsTimerMinutes === minutes ? this.accentColor :
        (ThemeRuntime.softFillColor(this.darkMode)))
      .onClick(() => ReaderTtsFloatingSession.setTimer(minutes))
  }

  @Builder
  ttsVoiceSelect() {
    if (deviceInfo.sdkApiVersion >= 26) {
      // The API 26 Select paints its own component surface, so the speaker mark has to
      // sit inside that surface instead of beside it, matching the shelf sort chip.
      Stack({ alignContent: Alignment.Start }) {
        this.ttsVoiceSelectControl(34, ThemeRuntime.softFillColor(this.darkMode))
        SymbolGlyph($r('sys.symbol.speaker_wave_3'))
          .fontSize(17)
          .fontColor([this.accentColor])
          .width(22)
          .margin({ left: AppSpacing.LG })
          .hitTestBehavior(HitTestMode.None)
      }
      .layoutWeight(1)
      .width('100%')
      .height(44)
    } else {
      Row({ space: AppSpacing.MD }) {
        SymbolGlyph($r('sys.symbol.speaker_wave_3'))
          .fontSize(17)
          .fontColor([this.accentColor])
          .width(24)
        this.ttsVoiceSelectControl(0, Color.Transparent)
      }
      .layoutWeight(1)
      .width('100%')
      .height(44)
      .padding({ left: AppSpacing.LG, right: AppSpacing.MD })
      .borderRadius(ThemeRuntime.mediumRadius())
      .backgroundColor(ThemeRuntime.softFillColor(this.darkMode))
      .border({ width: ThemeRuntime.glassBorderWidth('button'),
        color: ThemeRuntime.glassBorderColor(this.darkMode, 'button') })
    }
  }

  @Builder
  ttsVoiceSelectControl(leadingInset: number, surfaceColor: ResourceColor) {
    Select(this.ttsVoiceOptions())
      .id(`shared_tts_voice_${this.globalTtsVoiceRevision}_${ReaderTtsFloatingSession.ttsVoiceIndex()}`)
      .selected(ReaderTtsFloatingSession.ttsVoiceIndex())
      .value(this.globalTtsVoiceCode)
      .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
      .fontColor(this.primaryTextColor)
      // The API 26 branch fills its Stack by width; inside the legacy Row the
      // layoutWeight owns the main axis and this width is ignored, so both
      // branches can share one definition.
      .width('100%')
      .layoutWeight(1)
      .height(44)
      .padding({ left: leadingInset, right: 0 })
      .backgroundColor(surfaceColor)
      .borderRadius(ThemeRuntime.mediumRadius())
      .border({ width: 0 })
      .optionBgColor(Color.Transparent)
      .divider(null)
      .optionFontColor(this.primaryTextColor)
      .selectedOptionFontColor(this.accentColor)
      .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.darkMode))
      // API 26 以下保留这里的半透明底色与显式磨砂；API 26+ 由后面的修饰器接管：
      // 弱/均衡使用对应底色与模糊，跟随系统/强清除底色和模糊，交给系统材质绘制。
      .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.darkMode, ''))
      .menuBackgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel, this.darkMode, this.panelColor))
      .onSelect((index: number) => ReaderTtsFloatingSession.selectTtsVoice(index))
  }

  ttsVoiceOptions(): SelectOption[] {
    return ReaderTtsFloatingSession.ttsVoiceTitles().map((title: string): SelectOption => ({ value: title }));
  }

  @Builder
  audioVoiceSelect() {
    if (deviceInfo.sdkApiVersion >= 26) {
      // The API 26 Select paints its own component surface, so the speaker mark has to
      // sit inside that surface instead of beside it, matching the shelf sort chip.
      Stack({ alignContent: Alignment.Start }) {
        this.audioVoiceSelectControl(34, ThemeRuntime.softFillColor(this.darkMode))
        SymbolGlyph($r('sys.symbol.speaker_wave_3'))
          .fontSize(17)
          .fontColor([this.accentColor])
          .width(22)
          .margin({ left: AppSpacing.LG })
          .hitTestBehavior(HitTestMode.None)
      }
      .layoutWeight(1)
      .width('100%')
      .height(44)
    } else {
      Row({ space: AppSpacing.MD }) {
        SymbolGlyph($r('sys.symbol.speaker_wave_3'))
          .fontSize(17)
          .fontColor([this.accentColor])
          .width(24)
        this.audioVoiceSelectControl(0, Color.Transparent)
      }
      .layoutWeight(1)
      .width('100%')
      .height(44)
      .padding({ left: AppSpacing.LG, right: AppSpacing.MD })
      .borderRadius(ThemeRuntime.mediumRadius())
      .backgroundColor(ThemeRuntime.softFillColor(this.darkMode))
      .border({ width: ThemeRuntime.glassBorderWidth('button'),
        color: ThemeRuntime.glassBorderColor(this.darkMode, 'button') })
    }
  }

  @Builder
  audioVoiceSelectControl(leadingInset: number, surfaceColor: ResourceColor) {
    Select(this.audioVoiceOptions())
      .id(`shared_audio_voice_${this.globalTtsVoiceRevision}_${this.audioVoiceMenuRevision}_${this.audioVoiceSelectedIndex()}`)
      .selected(this.audioVoiceSelectedIndex())
      .value(this.hostAudioPage ? (this.hostVoiceTitles[this.hostVoiceIndex] || '默认') : this.globalTtsVoiceCode)
      .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
      .fontColor(this.primaryTextColor)
      // The API 26 branch fills its Stack by width; inside the legacy Row the
      // layoutWeight owns the main axis and this width is ignored, so both
      // branches can share one definition.
      .width('100%')
      .layoutWeight(1)
      .height(44)
      .padding({ left: leadingInset, right: 0 })
      .backgroundColor(surfaceColor)
      .borderRadius(ThemeRuntime.mediumRadius())
      .border({ width: 0 })
      .optionBgColor(Color.Transparent)
      .divider(null)
      .optionFontColor(this.primaryTextColor)
      .selectedOptionFontColor(this.accentColor)
      .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.darkMode))
      // API 26 以下保留这里的半透明底色与显式磨砂；API 26+ 由后面的修饰器接管：
      // 弱/均衡使用对应底色与模糊，跟随系统/强清除底色和模糊，交给系统材质绘制。
      .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.darkMode, ''))
      .menuBackgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel, this.darkMode, this.panelColor))
      .onSelect((index: number) => this.selectAudioVoiceOption(index))
  }

  audioVoiceOptions(): SelectOption[] {
    const options = this.audioVoiceTitles().map((title: string): SelectOption => ({ value: title }));
    options.push({ value: '自定义音色代码…' });
    return options;
  }

  selectAudioVoiceOption(index: number): void {
    if (index === this.audioVoiceTitles().length) {
      // 仅重设原生控件的当前值，不通过 ForEach 销毁、重建菜单节点。
      this.audioVoiceMenuRevision++;
      this.onOpenVoice();
    } else if (this.hostAudioPage) {
      this.onSelectHostVoice(index);
    } else {
      ReaderTtsFloatingSession.selectTtsVoice(index);
    }
  }

  audioVoiceTitles(): string[] {
    return this.hostAudioPage ? this.hostVoiceTitles : ReaderTtsFloatingSession.ttsVoiceTitles();
  }

  audioVoiceSelectedIndex(): number {
    return this.hostAudioPage ? this.hostVoiceIndex : ReaderTtsFloatingSession.ttsVoiceIndex();
  }

  @Builder
  audioProgress() {
    Column({ space: AppSpacing.XXS }) {
      Slider({ value: this.globalTtsAudioPositionMs, min: 0,
        max: Math.max(1, this.globalTtsAudioDurationMs), step: 1000 })
        .width('100%')
        .showTips(true)
        .selectedColor(this.accentColor)
        .trackColor(ThemeRuntime.inputColor(this.darkMode))
        .onChange((value: number, mode: SliderChangeMode) => {
          this.globalTtsAudioPositionMs = value;
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            ReaderTtsFloatingSession.seekAudio(value);
          }
        })
      Row() {
        Text(this.formatAudioDuration(this.globalTtsAudioPositionMs)).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor)
        Blank()
        Text(this.formatAudioDuration(this.globalTtsAudioDurationMs)).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor)
      }
      .width('100%')
    }
    .width('100%')
  }

  close(): void {
    this.optionsPanel = 0;
    this.onClose();
  }

  isAudio(): boolean {
    return this.hostAudioPage || this.globalTtsMode === 'audio';
  }

  isPaused(): boolean {
    return this.hostAudioPage ? !this.hostPlaying : this.globalTtsPaused;
  }

  isBusy(): boolean {
    return this.hostAudioPage ? this.hostBusy : this.globalTtsBusy;
  }

  statusText(): string {
    return this.hostAudioPage ? this.hostStatusText : this.globalTtsStatusText;
  }

  coverSource(): ResourceStr {
    return this.coverBookUrl() ? this.readyBookCover : (this.globalTtsCover || this.hostCover);
  }

  coverBookUrl(): string {
    return this.hostAudioPage ? this.hostBookUrl : this.globalTtsBookUrl;
  }

  coverHeight(): number {
    return Math.round(Math.min(300, Math.max(150,
      (Math.max(1, this.viewportHeight) - this.topInset - this.bottomInset) * 0.36)));
  }

  hasTtsVoices(): boolean {
    // 先读修订号登记依赖：音色列表在面板打开后才发布时，这里会跟着重新判断。
    return this.globalTtsVoiceRevision >= 0 && ReaderTtsFloatingSession.ttsVoiceTitles().length > 0;
  }

  chapterEnabled(forward: boolean): boolean {
    return forward ? this.globalTtsCanNext : this.globalTtsCanPrevious;
  }

  secondaryIcon(kind: string): Resource {
    if (kind === SECONDARY_TIMER) return $r('sys.symbol.timer');
    if (kind === SECONDARY_SPEED) return $r('sys.symbol.hourglass');
    if (kind === SECONDARY_CATALOG) return $r('sys.symbol.list_bullet');
    if (kind === SECONDARY_DOWNLOAD) return $r('sys.symbol.download');
    return $r('sys.symbol.stop_circle');
  }

  secondaryLabel(kind: string): string {
    if (kind === SECONDARY_TIMER) {
      return this.globalTtsTimerMinutes > 0 ?
        `${Math.max(1, Math.ceil(this.globalTtsTimerRemainingSeconds / 60))}分` : '定时';
    }
    if (kind === SECONDARY_SPEED) return `${this.globalTtsSpeed.toFixed(1)}x`;
    if (kind === SECONDARY_CATALOG) return '目录';
    if (kind === SECONDARY_DOWNLOAD) return '下载';
    return '停止';
  }

  secondaryColor(kind: string, icon: boolean): ResourceColor {
    if (kind === SECONDARY_STOP) return ThemeRuntime.dangerColor(this.darkMode);
    let active = false;
    if (kind === SECONDARY_TIMER) {
      active = this.globalTtsTimerMinutes > 0 || this.optionsPanel === 1;
    } else if (kind === SECONDARY_SPEED) {
      active = Math.abs(this.globalTtsSpeed - 1) > 0.01 || this.optionsPanel === 2;
    }
    if (active) return this.accentColor;
    return icon ? this.primaryTextColor : this.subTextColor;
  }

  onSecondaryTap(kind: string): void {
    if (kind === SECONDARY_TIMER) {
      this.optionsPanel = this.optionsPanel === 1 ? 0 : 1;
    } else if (kind === SECONDARY_SPEED) {
      this.optionsPanel = this.optionsPanel === 2 ? 0 : 2;
    } else if (kind === SECONDARY_CATALOG) {
      this.onOpenCatalog();
    } else if (kind === SECONDARY_DOWNLOAD) {
      this.onOpenDownload();
    } else {
      this.close();
      ReaderTtsFloatingSession.stop();
    }
  }

  ambientHeight(): number {
    return Math.round(Math.max(360, (Math.max(1, this.viewportHeight)) * 0.6));
  }

  coverInitial(): string {
    const name = this.hostBookName || this.globalTtsBookName;
    return name ? name.substring(0, 1) : '书';
  }

  pageColorWithAlpha(alpha: string): string {
    return `#${alpha}${ThemeRuntime.pageColor(this.darkMode).substring(1)}`;
  }

  accentGlowColor(): string {
    return `#40${ThemeRuntime.accentColor(this.darkMode).substring(1)}`;
  }

  scrollToCurrentSentence(smooth: boolean): void {
    if (this.textUpdateTimer >= 0) clearTimeout(this.textUpdateTimer);
    this.textUpdateTimer = setTimeout(() => {
      this.textUpdateTimer = -1;
      if (this.isAudio() || !this.globalTtsCurrentText || this.readingViewportHeight <= 0) return;
      // Measure the spoken line inside the continuous paragraph, including very long paragraphs.
      try {
        const manager = this.readingTextController.getLayoutManager();
        const firstSpokenCharacter = this.globalTtsCurrentText.search(/\S/);
        const focusOffset = this.globalTtsTextBefore.length + Math.max(0, firstSpokenCharacter);
        for (let index = 0; index < manager.getLineCount(); index++) {
          const line = manager.getLineMetrics(index);
          if (focusOffset < line.startIndex || focusOffset >= line.endIndex) continue;
          const lineCenter = this.getUIContext().px2vp(line.baseline - line.ascent + line.height / 2);
          this.textScroller.scrollTo({
            xOffset: 0,
            yOffset: Math.max(0, lineCenter - this.readingViewportHeight / 2),
            animation: smooth ? { duration: 180, curve: Curve.EaseOut } : false
          });
          break;
        }
      } catch (_) {}
    }, 0);
  }

  formatAudioDuration(valueMs: number): string {
    const totalSeconds = Math.max(0, Math.floor((valueMs || 0) / 1000));
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    const mm = minutes.toString().padStart(2, '0');
    const ss = seconds.toString().padStart(2, '0');
    return hours > 0 ? `${hours}:${mm}:${ss}` : `${minutes}:${ss}`;
  }
}
