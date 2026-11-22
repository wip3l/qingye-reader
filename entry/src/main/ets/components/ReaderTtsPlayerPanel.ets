import { BookCover } from './book/BookCover';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ReaderTtsFloatingSession } from '../utils/ReaderTtsFloatingSession';
import deviceInfo from '@ohos.deviceInfo';
import { router } from '@kit.ArkUI';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { TtsPanelThemeBackground } from './TtsPanelThemeBackground';
import { ImmersiveMaterialSurface } from './ImmersiveMaterialSurface';
import { PlaybackLoudnessGain } from '../utils/PlaybackLoudnessGain';
import { PlaybackSpeed } from '../utils/PlaybackSpeed';
import { AudioSkipRange } from '../utils/AudioSkipRange';
import { AudioBookSettingsStore } from '../utils/AudioBookSettingsStore';
import { AudioSubtitleView } from './AudioSubtitleView';

/** 顶栏圆形按钮的尺寸。 */
const PANEL_CONTROL_SIZE: number = 40;
/** 听书大封面在空间不够时最多缩到这个高度。 */
const AUDIO_COVER_MIN_HEIGHT: number = 72;
/** 听书音色下拉框的高度，与 audioVoiceSelect 一致。 */
const AUDIO_VOICE_ROW_HEIGHT: number = 44;
/** 听书“简介 | 字幕”切换条的高度。 */
const SUBTITLE_TABS_HEIGHT: number = 30;
/** 选“字幕”时字幕区至少留这么高（约 5 行），封面按剩下的空间缩小。 */
const SUBTITLE_AREA_MIN_HEIGHT: number = 140;
/** 切换“简介 | 字幕”时封面缩放的时长。 */
const SUBTITLE_SWITCH_MS: number = 300;
/** 听书进度滑条的高度：够手指拖动，不带系统默认的上下留白。 */
const AUDIO_PROGRESS_HEIGHT: number = 28;
const SECONDARY_TIMER: string = 'timer';
const SECONDARY_SPEED: string = 'speed';
const SECONDARY_CATALOG: string = 'catalog';
const SECONDARY_STOP: string = 'stop';
const SECONDARY_SKIP: string = 'skip';
// 听视频：回到播放页看画面。
const SECONDARY_WATCH: string = 'watch';
/** 跳过提示显示的时长。 */
const SKIP_NOTICE_MS: number = 3000;
/** 定时最后这么多秒按钮和状态行改用危险色，提醒快停了。 */
const TIMER_WARN_SECONDS: number = 60;
/** 定时面板“加时”一次加的分钟数。 */
const TIMER_EXTEND_MINUTES: number = 15;

/** 定时剩余时间：不足一小时 mm:ss，否则 h:mm:ss。 */
function formatTimerRemaining(seconds: number): string {
  const total = Math.max(0, Math.floor(seconds));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const secs = total % 60;
  const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
  return hours > 0 ? `${hours}:${pad(minutes)}:${pad(secs)}` : `${pad(minutes)}:${pad(secs)}`;
}

@Component
export struct ReaderTtsPlayerPanel {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('mimoEnabled') mimoEnabled: boolean = false;
  @StorageProp('mimoMulti') mimoMulti: boolean = false;
  @StorageProp('mimoCurrentRole') mimoCurrentRole: string = '';
  @StorageProp('mimoReadingStatus') mimoReadingStatus: string = '';
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @Prop sharedMotionId: string = '';
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
  @Prop @Watch('onSubtitleBookChanged') hostBookUrl: string = '';
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
  @StorageProp('globalTtsBookUrl') @Watch('onSubtitleBookChanged') globalTtsBookUrl: string = '';
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
  @StorageProp('globalTtsAudioSkipHead') globalTtsAudioSkipHead: number = 0;
  @StorageProp('globalTtsAudioSkipTail') globalTtsAudioSkipTail: number = 0;
  @StorageProp('globalTtsAudioSkipNotice') globalTtsAudioSkipNotice: string = '';
  @StorageProp('globalTtsAudioSkipUndo') globalTtsAudioSkipUndo: string = '';
  @StorageProp('globalTtsAudioSkipNoticeSerial') @Watch('onSkipNoticeChanged') globalTtsAudioSkipNoticeSerial: number = 0;
  @StorageLink('globalTtsVoiceRevision') globalTtsVoiceRevision: number = 0;
  @StorageLink('globalTtsStatusText') globalTtsStatusText: string = '';
  @StorageLink('globalTtsBusy') globalTtsBusy: boolean = false;
  /** 朗读主人支持按原文位置重新开读时为 true：显示上一句/下一句，正文可以点句跳读。 */
  @StorageProp('globalTtsSentenceControl') globalTtsSentenceControl: boolean = false;
  @StorageProp('ttsLoudnessGain') ttsLoudnessGain: number = 0;
  @StorageProp('audioLoudnessGain') audioLoudnessGain: number = 0;
  @StorageProp('ttsLoudnessGainSupported') ttsLoudnessGainSupported: boolean = true;
  @StorageProp('audioLoudnessGainSupported') audioLoudnessGainSupported: boolean = true;
  /** 0 关闭，1 定时，2 倍速与音量增益，4 跳过片头片尾。 */
  @State optionsPanel: number = 0;
  /** 拖动增益滑条时只改显示，松手才下发；-1 表示没在拖。 */
  @State gainDraft: number = -1;
  /** 拖动倍速滑条时的显示值；-1 表示没在拖。 */
  @State speedDraft: number = -1;
  @State audioVoiceMenuRevision: number = 0;
  // 听书封面区实际分到的高度和其中章节名、状态行的高度。定时/倍速/增益面板展开后封面区变矮，
  // 封面按这些量出来的值缩小；否则屏幕矮的机型上内容溢出，音色下拉会压到进度条上。
  @State audioHeroHeight: number = 0;
  @State audioHeroTitleHeight: number = 0;
  @State audioHeroStatusHeight: number = 0;
  private textScroller: Scroller = new Scroller();
  private readingTextController: TextController = new TextController();
  private readingViewportHeight: number = 0;
  private textUpdateTimer: number = -1;
  @State skipNoticeVisible: boolean = false;
  /** 听书封面下面显示字幕（true）还是简介。 */
  @State subtitleTab: boolean = false;
  private skipNoticeTimer: number = -1;

  aboutToAppear(): void {
    this.onSubtitleBookChanged();
    this.scrollToCurrentSentence(false);
  }

  aboutToDisappear(): void {
    if (this.textUpdateTimer >= 0) clearTimeout(this.textUpdateTimer);
    this.textUpdateTimer = -1;
    if (this.skipNoticeTimer >= 0) clearTimeout(this.skipNoticeTimer);
    this.skipNoticeTimer = -1;
  }

  onSkipNoticeChanged(): void {
    if (this.skipNoticeTimer >= 0) clearTimeout(this.skipNoticeTimer);
    this.skipNoticeVisible = !!this.globalTtsAudioSkipNotice;
    this.skipNoticeTimer = setTimeout(() => {
      this.skipNoticeTimer = -1;
      this.skipNoticeVisible = false;
    }, SKIP_NOTICE_MS);
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
        // 空 id 时解析为默认主题的面板插画，背景始终是清晰的插画而不是封面模糊。
        TtsPanelThemeBackground({ themeId: this.backgroundThemeId, darkMode: this.darkMode })

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
          } else if (this.optionsPanel === 4 && this.isAudio()) {
            this.skipOptions()
          }

          this.secondaryActions()
        }
        .width('100%')
        .height('100%')
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: this.topInset + 8, bottom: this.bottomInset + 12 })
      }
      .width('100%')
      .height('100%')
      .transition(this.sharedMotionId ? TransitionEffect.IDENTITY : TransitionEffect.translate({ y: 520 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 280, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
    .borderRadius(this.sharedMotionId ? 24 : 0)
    .clip(!!this.sharedMotionId)
    .geometryTransition(this.sharedMotionId)
    .transition(this.sharedMotionId ? TransitionEffect.opacity(0.99) : TransitionEffect.IDENTITY)
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
        Text(this.headerSubtitle())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
      .alignItems(HorizontalAlign.Center)
      // 在线有声书的下载放在右上角；没有时用等宽占位让标题真正居中。
      if (this.hostDownloadAvailable && this.isAudio()) {
        this.circleButton($r('sys.symbol.download'), '下载', () => this.onOpenDownload())
      } else {
        Column()
          .width(PANEL_CONTROL_SIZE)
          .height(PANEL_CONTROL_SIZE)
      }
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

      // 看字幕时章节名挪到顶栏第二行，把高度让给字幕。
      if (!this.chapterInHeader()) {
        Text(this.audioChapterTitle())
          .fontSize(AppFontSize.SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .margin({ top: AppSpacing.SM })
          .onAreaChange((_oldArea: Area, area: Area): void => {
            const height = Math.ceil(Number(area.height));
            if (this.audioHeroTitleHeight !== height) this.audioHeroTitleHeight = height;
          })
      }

      if (this.subtitleAvailable()) {
        this.subtitleTabs()
      }

      // 跳过片头片尾的提示叠在简介底部：放在简介区域里面，撤回按钮才点得到，也不挤动下面的进度条。
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.subtitleAvailable() && this.subtitleTab) {
          AudioSubtitleView({
            darkMode: this.darkMode,
            accentColor: this.accentColor,
            primaryTextColor: this.primaryTextColor,
            subTextColor: this.subTextColor
          })
        } else {
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
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
        }

        if (this.skipNoticeVisible && this.globalTtsAudioSkipNotice) {
          this.skipNotice()
        }
      }
      .layoutWeight(1)
      .width('100%')
      // 内容比分到的高度多时裁掉，不压到下面的进度条。
      .clip(true)

      if (this.statusText()) {
        Column() {
          this.statusLine()
        }
        .width('100%')
        .onAreaChange((_oldArea: Area, area: Area): void => {
          const height = Math.ceil(Number(area.height));
          if (this.audioHeroStatusHeight !== height) this.audioHeroStatusHeight = height;
        })
      }

      if (this.showAudioVoiceRow()) {
        Row() {
          this.audioVoiceSelect()
        }
        .width('100%')
      }
    }
    .layoutWeight(1)
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .onAreaChange((_oldArea: Area, area: Area): void => {
      const height = Math.floor(Number(area.height));
      if (this.audioHeroHeight !== height) this.audioHeroHeight = height;
    })
  }

  /** 听书封面下面的“简介 | 字幕”切换。选了哪个按书记住。 */
  @Builder
  subtitleTabs() {
    Row({ space: AppSpacing.XXS }) {
      this.subtitleTabItem('简介', false)
      this.subtitleTabItem('字幕', true)
    }
    .height(SUBTITLE_TABS_HEIGHT)
    .padding(3)
    .borderRadius(SUBTITLE_TABS_HEIGHT / 2)
    .backgroundColor(ThemeRuntime.softFillColor(this.darkMode))
  }

  @Builder
  subtitleTabItem(label: string, subtitle: boolean) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontWeight(this.subtitleTab === subtitle ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.subtitleTab === subtitle ? this.primaryTextColor : this.subTextColor)
      .height('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
      .borderRadius((SUBTITLE_TABS_HEIGHT - 6) / 2)
      .backgroundColor(this.subtitleTab === subtitle ? ThemeRuntime.cardColor(this.darkMode) : Color.Transparent)
      .shadow(this.subtitleTab === subtitle ?
        { radius: 4, color: this.darkMode ? '#40000000' : '#1A000000', offsetX: 0, offsetY: 1 } :
        { radius: 0, color: Color.Transparent })
      .accessibilityText(subtitle ? 'AI 字幕' : '书籍简介')
      .accessibilitySelected(this.subtitleTab === subtitle)
      .onClick(() => this.selectSubtitleTab(subtitle))
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
        // 点某一句从那句开始读；拖动翻看由外层 Scroll 处理，不会触发点按。
        .onClick((event: ClickEvent) => this.onReadingTextTap(event))
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

      // MiMo sits in the same voice list as regular voices, so switching works both ways here.
      if (this.hasTtsVoices()) {
        Row() {
          this.ttsVoiceSelect()
        }
        .width('100%')
      }
      if (this.mimoEnabled) {
        Row({ space: AppSpacing.SM }) {
          Text(this.mimoReadingStatus || this.mimoCurrentRole || (this.mimoMulti ? '自动识别人物' : '单音色朗读'))
            .fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.mimoMulti) {
            Button('这句不对？').height(30).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor)
              .backgroundColor(Color.Transparent)
              .onClick(() => router.pushUrl({ url: 'pages/MimoBookRoles' }))
            Button('本书角色').height(30).fontSize(AppFontSize.CAPTION)
              .fontColor(this.primaryTextColor).backgroundColor(ThemeRuntime.softFillColor(this.darkMode))
              .onClick(() => router.pushUrl({ url: 'pages/MimoBookRoles' }))
          }
        }.width('100%').padding({ left: AppSpacing.XS })
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
          .fontSize(large ? Math.max(16, Math.round(this.audioCoverHeight() * 0.22)) : 16)
          .fontColor(ThemeRuntime.onAccentColor())
      }
    }
    .width(large ? Math.round(this.audioCoverHeight() * 0.75) : 42)
    .height(large ? this.audioCoverHeight() : 56)
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

  /** 主控制区：上一章、[后退 15 秒 / 上一句]、大号播放键、[前进 15 秒 / 下一句]、下一章。 */
  @Builder
  mainControls() {
    Row() {
      this.chapterButton(false)
      if (this.isAudio()) {
        this.seekStepButton(-1)
      } else if (this.globalTtsSentenceControl) {
        this.sentenceStepButton(-1)
      }
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
      if (this.isAudio()) {
        this.seekStepButton(1)
      } else if (this.globalTtsSentenceControl) {
        this.sentenceStepButton(1)
      }
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
    .accessibilityText(forward ? (this.isVideo() ? '下一集' : '下一章') : (this.isVideo() ? '上一集' : '上一章'))
    .onClick(() => {
      if (!this.chapterEnabled(forward)) return;
      if (forward) {
        ReaderTtsFloatingSession.next();
      } else {
        ReaderTtsFloatingSession.previous();
      }
    })
  }

  /**
   * 前进/后退一次 15 秒。还不知道总时长（缓冲中、没点过播放）时不能用。
   * direction：-1 后退，1 前进。
   */
  @Builder
  seekStepButton(direction: number) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(direction < 0 ? $r('sys.symbol.gobackward_15') : $r('sys.symbol.goforward_15'))
        .fontSize(28)
        .fontColor([this.globalTtsAudioDurationMs > 0 ? this.primaryTextColor : this.subTextColor])
    }
    .width(48)
    .height(56)
    .opacity(this.globalTtsAudioDurationMs > 0 ? 1 : 0.4)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .accessibilityText(direction < 0 ? '后退 15 秒' : '前进 15 秒')
    .onClick(() => {
      if (this.globalTtsAudioDurationMs <= 0) return;
      ReaderTtsFloatingSession.seekAudioBy(direction * AudioSkipRange.SEEK_STEP_MS);
    })
  }

  /** 朗读的上一句/下一句：点一下按句，长按按段。direction：-1 往前，1 往后。 */
  @Builder
  sentenceStepButton(direction: number) {
    Column({ space: 1 }) {
      SymbolGlyph($r('sys.symbol.backward_fill'))
        .fontSize(22)
        .fontColor([this.primaryTextColor])
        .rotate({ angle: direction < 0 ? 0 : 180 })
      Text(direction < 0 ? '上一句' : '下一句')
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.subTextColor)
        .maxLines(1)
    }
    .width(52)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
    .accessibilityText(direction < 0 ? '上一句，长按上一段' : '下一句，长按下一段')
    .gesture(GestureGroup(GestureMode.Exclusive,
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => ReaderTtsFloatingSession.stepSentence(direction, true)),
      TapGesture()
        .onAction(() => ReaderTtsFloatingSession.stepSentence(direction, false))))
  }

  /**
   * 底部一排：定时、倍速（含音量增益）、[跳过]、目录、停止。跳过只有听书有；
   * 在线有声书的下载在顶栏右边，音色统一使用内容下方的整行下拉框。
   */
  @Builder
  secondaryActions() {
    Row() {
      this.timerItem()
      this.secondaryItem(SECONDARY_SPEED)
      if (this.isVideo()) {
        this.secondaryItem(SECONDARY_WATCH)
      } else if (this.isAudio()) {
        this.secondaryItem(SECONDARY_SKIP)
      }
      this.secondaryItem(SECONDARY_CATALOG)
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

  /**
   * 定时按钮：开着定时时文字是分秒倒计时，图标外圈细环按“剩余 / 总时长”变短。
   * 细环叠在图标的 22vp 占位外面，不改变这一格的高度，和同排其他按钮的文字保持对齐。
   */
  @Builder
  timerItem() {
    Column({ space: AppSpacing.XS }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.timerActive()) {
          Progress({ value: this.timerRemainingShown(), total: this.timerTotalSeconds(), type: ProgressType.Ring })
            .width(32)
            .height(32)
            .color(this.timerColor())
            .backgroundColor(ThemeRuntime.hairlineColor(this.darkMode))
            .style({ strokeWidth: 2 })
            .hitTestBehavior(HitTestMode.None)
        }
        SymbolGlyph($r('sys.symbol.timer'))
          .fontSize(this.timerActive() ? 17 : 22)
          .fontColor([this.timerActive() ? this.timerColor() : this.secondaryColor(SECONDARY_TIMER, true)])
      }
      .width(22)
      .height(22)
      Text(this.secondaryLabel(SECONDARY_TIMER))
        .fontSize(AppFontSize.CAPTION)
        .fontWeight(this.timerActive() ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.timerActive() ? this.timerColor() : this.secondaryColor(SECONDARY_TIMER, false))
        .fontFeature('"tnum" on')
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
    .accessibilityText(this.timerActive() ?
      `定时，剩余 ${formatTimerRemaining(this.globalTtsTimerRemainingSeconds)}` : '定时')
    .onClick(() => this.onSecondaryTap(SECONDARY_TIMER))
  }

  /** 开着定时时顶部一行显示剩余时间、几点停止，以及加时、关闭；下面的档位点哪个都从那一档重新计时。 */
  @Builder
  timerOptions() {
    Column({ space: AppSpacing.SM }) {
      if (this.timerActive()) {
        this.timerStatusRow()
      }
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
    .width('100%')
  }

  @Builder
  timerStatusRow() {
    Row({ space: AppSpacing.SM }) {
      SymbolGlyph($r('sys.symbol.timer'))
        .fontSize(18)
        .fontColor([this.timerColor()])
      Text('剩余')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor)
      Text(formatTimerRemaining(this.globalTtsTimerRemainingSeconds))
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.timerWarning() ? this.timerColor() : this.primaryTextColor)
        .fontFeature('"tnum" on')
        .maxLines(1)
      Text(`${this.timerEndClock()} 停止`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor)
        .fontFeature('"tnum" on')
        .maxLines(1)
        .layoutWeight(1)
      this.timerStatusButton(`+${TIMER_EXTEND_MINUTES}分`, `延长 ${TIMER_EXTEND_MINUTES} 分钟`, true,
        () => ReaderTtsFloatingSession.extendTimer(TIMER_EXTEND_MINUTES))
      this.timerStatusButton('关闭', '关闭定时', false, () => ReaderTtsFloatingSession.setTimer(0))
    }
    .width('100%')
    .height(44)
    .padding({ left: AppSpacing.MD, right: AppSpacing.SM })
    .borderRadius(ThemeRuntime.buttonRadius())
    .backgroundColor(ThemeRuntime.softFillColor(this.darkMode))
  }

  @Builder
  timerStatusButton(label: string, accessibility: string, accent: boolean, action: () => void) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontWeight(accent ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(accent ? this.accentColor : this.subTextColor)
      .height(30)
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
      .borderRadius(15)
      .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .accessibilityText(accessibility)
      .onClick(action)
  }

  /**
   * 倍速：滑条 0.05 一格，两侧按钮微调，下面是快捷档；再往下是音量增益，两者都是调声音，放在一个面板里。
   * 朗读换倍速要从当前句重新合成，拖动中只改显示、松手才下发；有声书边拖边变速。
   */
  @Builder
  speedOptions() {
    Column({ space: AppSpacing.SM }) {
      Row() {
        Text('倍速')
          .fontSize(AppFontSize.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor)
          .layoutWeight(1)
        Text(`${PlaybackSpeed.label(this.speedShown())}x`)
          .fontSize(AppFontSize.CAPTION)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.accentColor)
      }
      .width('100%')

      Row({ space: AppSpacing.SM }) {
        this.speedStepButton(-1)
        Slider({
          value: this.speedShown(),
          min: PlaybackSpeed.MIN,
          max: PlaybackSpeed.MAX,
          step: PlaybackSpeed.STEP
        })
          .layoutWeight(1)
          .selectedColor(this.accentColor)
          .trackColor(ThemeRuntime.inputColor(this.darkMode))
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
          .accessibilityText('倍速')
          .onChange((value: number, mode: SliderChangeMode) => {
            const speed = PlaybackSpeed.normalize(value);
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.speedDraft = -1;
              this.commitSpeed(speed);
            } else {
              this.speedDraft = speed;
              if (this.isAudio()) this.commitSpeed(speed);
            }
          })
        this.speedStepButton(1)
      }
      .width('100%')

      Row({ space: AppSpacing.SM }) {
        ForEach(PlaybackSpeed.PRESETS, (value: number) => {
          this.speedChip(value)
        }, (value: number) => value.toString())
      }
      .width('100%')

      Divider()
        .strokeWidth(0.5)
        .color(ThemeRuntime.hairlineColor(this.darkMode))
        .margin({ top: AppSpacing.XS, bottom: AppSpacing.XS })
      this.gainOptions()
    }
    .width('100%')
  }

  /** direction：-1 减一格，1 加一格。可用状态在这里现读，倍速变化后立即刷新。 */
  @Builder
  speedStepButton(direction: number) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(direction < 0 ? $r('sys.symbol.minus') : $r('sys.symbol.plus'))
        .fontSize(16)
        .fontColor([this.speedStepEnabled(direction) ? this.primaryTextColor : this.subTextColor])
    }
    .width(30)
    .height(30)
    .borderRadius(15)
    .backgroundColor(ThemeRuntime.softFillColor(this.darkMode))
    .opacity(this.speedStepEnabled(direction) ? 1 : 0.5)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
    .accessibilityText(direction < 0 ? '降低倍速' : '提高倍速')
    .onClick(() => {
      if (!this.speedStepEnabled(direction)) return;
      this.speedDraft = -1;
      this.commitSpeed(PlaybackSpeed.normalize(this.globalTtsSpeed + direction * PlaybackSpeed.STEP));
    })
  }

  @Builder
  speedChip(value: number) {
    Text(`${PlaybackSpeed.label(value)}x`)
      .fontSize(AppFontSize.CAPTION)
      .fontWeight(PlaybackSpeed.same(this.speedShown(), value) ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(PlaybackSpeed.same(this.speedShown(), value) ? ThemeRuntime.onAccentColor() : this.primaryTextColor)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(30)
      .borderRadius(ThemeRuntime.buttonRadius())
      .backgroundColor(PlaybackSpeed.same(this.speedShown(), value) ? this.accentColor :
        (ThemeRuntime.softFillColor(this.darkMode)))
      .accessibilityText(`倍速 ${PlaybackSpeed.label(value)}`)
      .onClick(() => {
        this.speedDraft = -1;
        this.commitSpeed(value);
      })
  }

  /** 音量增益：滑条到 24 dB，放在倍速面板下半部分；朗读和有声书各存一个值。 */
  @Builder
  gainOptions() {
    Column({ space: AppSpacing.SM }) {
      Row() {
        Text('音量增益')
          .fontSize(AppFontSize.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor)
          .layoutWeight(1)
        Text(this.gainSupported() ? this.gainValueText(this.gainShown()) : '不可用')
          .fontSize(AppFontSize.CAPTION)
          .fontWeight(this.gainShown() > 0 && this.gainSupported() ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(this.gainShown() > 0 && this.gainSupported() ? this.accentColor : this.subTextColor)
      }
      .width('100%')

      Row({ space: AppSpacing.SM }) {
        SymbolGlyph($r('sys.symbol.speaker_wave_2'))
          .fontSize(16)
          .fontColor([this.subTextColor])
        Slider({ value: this.gainShown(), min: 0, max: PlaybackLoudnessGain.MAX_DB, step: 1 })
          .layoutWeight(1)
          .selectedColor(this.accentColor)
          .trackColor(ThemeRuntime.inputColor(this.darkMode))
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
          .enabled(this.gainSupported())
          .accessibilityText('音量增益')
          .onChange((value: number, mode: SliderChangeMode) => {
            const gain = Math.round(value);
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.gainDraft = -1;
              PlaybackLoudnessGain.set(this.gainKind(), gain);
            } else {
              this.gainDraft = gain;
            }
          })
        SymbolGlyph($r('sys.symbol.speaker_wave_3'))
          .fontSize(18)
          .fontColor([this.subTextColor])
      }
      .width('100%')
      .opacity(this.gainSupported() ? 1 : 0.5)

      if (this.gainHint()) {
        Text(this.gainHint())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.gainSupported() ? ThemeRuntime.warningColor(this.darkMode) : this.subTextColor)
          .width('100%')
          .maxLines(2)
      }
    }
    .width('100%')
  }

  /** 跳过片头片尾：两行用 ± 调整，“设为当前”取播放位置；只对这本书生效，规则见 AudioSkipRange。 */
  @Builder
  skipOptions() {
    Column({ space: AppSpacing.SM }) {
      Row() {
        Text('跳过片头片尾')
          .fontSize(AppFontSize.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor)
          .layoutWeight(1)
        Text('仅本书')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor)
      }
      .width('100%')

      this.skipRow(true)
      this.skipRow(false)

      Text('从章节开头播放时跳过片头；剩余不到片尾时长时直接播下一章')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor)
        .width('100%')
        .maxLines(2)
    }
    .width('100%')
  }

  @Builder
  skipRow(head: boolean) {
    Row({ space: AppSpacing.SM }) {
      Text(head ? '片头' : '片尾')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor)
        .width(32)
      Row({ space: AppSpacing.XS }) {
        this.skipStepButton(head, -1)
        Text(this.skipSeconds(head) > 0 ? AudioSkipRange.label(this.skipSeconds(head)) : '不跳过')
          .fontSize(AppFontSize.BODY)
          .fontWeight(this.skipSeconds(head) > 0 ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(this.skipSeconds(head) > 0 ? this.primaryTextColor : this.subTextColor)
          .fontFeature('"tnum" on')
          .textAlign(TextAlign.Center)
          .width(64)
        this.skipStepButton(head, 1)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      Text('设为当前')
        .fontSize(AppFontSize.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.accentColor)
        .height(30)
        .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
        .borderRadius(15)
        .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
        .opacity(this.globalTtsAudioDurationMs > 0 ? 1 : 0.5)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
        .accessibilityText(head ? '把当前位置设为片头结束' : '把当前位置设为片尾开始')
        .onClick(() => this.setSkipToCurrent(head))
    }
    .width('100%')
    .height(44)
    .padding({ left: AppSpacing.MD, right: AppSpacing.SM })
    .borderRadius(ThemeRuntime.buttonRadius())
    .backgroundColor(ThemeRuntime.softFillColor(this.darkMode))
  }

  /** direction：-1 减 5 秒，1 加 5 秒。 */
  @Builder
  skipStepButton(head: boolean, direction: number) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(direction < 0 ? $r('sys.symbol.minus') : $r('sys.symbol.plus'))
        .fontSize(16)
        .fontColor([this.skipStepEnabled(head, direction) ? this.primaryTextColor : this.subTextColor])
    }
    .width(30)
    .height(30)
    .borderRadius(15)
    .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
    .opacity(this.skipStepEnabled(head, direction) ? 1 : 0.5)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
    .accessibilityText(`${head ? '片头' : '片尾'}${direction < 0 ? '减少' : '增加'} ${AudioSkipRange.STEP_SECONDS} 秒`)
    .onClick(() => {
      if (!this.skipStepEnabled(head, direction)) return;
      this.changeSkip(head, this.skipSeconds(head) + direction * AudioSkipRange.STEP_SECONDS);
    })
  }

  /** 跳过后的提示：文字加可选的撤回按钮，3 秒后消失。 */
  @Builder
  skipNotice() {
    Row({ space: AppSpacing.MD }) {
      Text(this.globalTtsAudioSkipNotice)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.darkMode ? '#18191C' : '#FFFFFF')
        .maxLines(1)
      if (this.globalTtsAudioSkipUndo) {
        Text(this.globalTtsAudioSkipUndo)
          .fontSize(AppFontSize.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.darkMode ? '#18191C' : '#FFFFFF')
          .height(26)
          .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
          .borderRadius(13)
          .backgroundColor(this.darkMode ? '#1F000000' : '#33FFFFFF')
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
          .onClick(() => {
            this.skipNoticeVisible = false;
            ReaderTtsFloatingSession.undoAudioSkip();
          })
      }
    }
    .height(36)
    .padding({ left: AppSpacing.LG, right: this.globalTtsAudioSkipUndo ? AppSpacing.SM : AppSpacing.LG })
    .borderRadius(18)
    .backgroundColor(this.darkMode ? '#E6FFFFFF' : '#D118191C')
    .margin({ bottom: AppSpacing.SM })
    .alignItems(VerticalAlign.Center)
    .transition(TransitionEffect.opacity(0).combine(TransitionEffect.translate({ y: 6 }))
      .animation({ duration: 180, curve: Curve.EaseOut }))
  }

  /** 倒计时中档位都不高亮（剩余时间已不等于档位），没开定时时“关闭”高亮。 */
  @Builder
  timerChip(minutes: number, label: string) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontWeight(this.timerChipSelected(minutes) ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.timerChipSelected(minutes) ? ThemeRuntime.onAccentColor() : this.primaryTextColor)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(30)
      .borderRadius(ThemeRuntime.buttonRadius())
      .backgroundColor(this.timerChipSelected(minutes) ? this.accentColor :
        (ThemeRuntime.softFillColor(this.darkMode)))
      .accessibilityText(minutes > 0 ? `定时 ${minutes} 分钟` : '关闭定时')
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
      .optionFont({ family: this.applicationFontFamily })
      .selectedOptionFont({ family: this.applicationFontFamily })
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
      .optionFont({ family: this.applicationFontFamily })
      .selectedOptionFont({ family: this.applicationFontFamily })
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
    // 时间放在滑条两端，整条只占一行高度，省下的空间留给封面和字幕。
    Row({ space: AppSpacing.MD }) {
      Text(this.formatAudioDuration(this.globalTtsAudioPositionMs))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor)
        .fontFeature('"tnum" on')
        .constraintSize({ minWidth: 34 })
        .textAlign(TextAlign.Start)
      // 还不知道总时长（缓冲中，或关了自动播放、还没点播放）时进度条留空、不能拖，左边照样显示已听到的位置。
      Slider({ value: this.globalTtsAudioDurationMs > 0 ? this.globalTtsAudioPositionMs : 0, min: 0,
        max: Math.max(1, this.globalTtsAudioDurationMs), step: 1000 })
        .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
        .layoutWeight(1)
        .height(AUDIO_PROGRESS_HEIGHT)
        .showTips(true)
        .enabled(this.globalTtsAudioDurationMs > 0)
        .selectedColor(this.accentColor)
        .trackColor(ThemeRuntime.inputColor(this.darkMode))
        .onChange((value: number, mode: SliderChangeMode) => {
          this.globalTtsAudioPositionMs = value;
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            ReaderTtsFloatingSession.seekAudio(value);
          }
        })
      Text(this.globalTtsAudioDurationMs > 0 ? this.formatAudioDuration(this.globalTtsAudioDurationMs) : '--:--')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor)
        .fontFeature('"tnum" on')
        .constraintSize({ minWidth: 34 })
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  close(): void {
    this.optionsPanel = 0;
    this.onClose();
  }

  /** 听视频和听书用同一套界面：大封面、进度条、前进后退 15 秒。 */
  isAudio(): boolean {
    return this.hostAudioPage || this.globalTtsMode === 'audio' || this.globalTtsMode === 'video';
  }

  isVideo(): boolean {
    return !this.hostAudioPage && this.globalTtsMode === 'video';
  }

  audioChapterTitle(): string {
    return this.hostChapterTitle || this.globalTtsChapterTitle || '正在获取章节…';
  }

  /** 听书选了“字幕”页签时，章节名放在顶栏第二行。 */
  chapterInHeader(): boolean {
    return this.subtitleAvailable() && this.subtitleTab;
  }

  /** 顶栏第二行：章节进度；看字幕时接上章节名（“8/1699 · 007 全区封锁”）。 */
  headerSubtitle(): string {
    if (!this.isAudio()) return '正在朗读';
    const progress = this.globalTtsChapterProgress || (this.isVideo() ? '正在听视频' : '正在听书');
    if (!this.chapterInHeader()) return progress;
    const title = this.hostChapterTitle || this.globalTtsChapterTitle;
    if (!title) return progress;
    return this.globalTtsChapterProgress ? `${this.globalTtsChapterProgress.replace(/章$/, '')} · ${title}` : title;
  }

  /** 字幕只给有声书：听视频时没有这个页签。 */
  subtitleAvailable(): boolean {
    return this.isAudio() && !this.isVideo() && !!this.coverBookUrl();
  }

  selectSubtitleTab(subtitle: boolean): void {
    if (this.subtitleTab === subtitle) return;
    // 封面高度由 subtitleTab 算出，放进动画里切换，封面会平滑缩小/放大。
    this.getUIContext().animateTo({ duration: SUBTITLE_SWITCH_MS, curve: Curve.Friction }, () => {
      this.subtitleTab = subtitle;
    });
    AudioBookSettingsStore.saveSubtitleTab(getContext(this), this.coverBookUrl(), subtitle)
      .catch((error: Error) => console.warn('保存字幕页签失败:', error));
  }

  onSubtitleBookChanged(): void {
    this.subtitleTab = AudioBookSettingsStore.subtitleTab(this.coverBookUrl());
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

  /**
   * 听书大封面的高度：优先用 coverHeight()，封面区放不下时扣掉章节名、状态行、音色下拉和间距后缩小。
   * 选了“字幕”时再给字幕区留出 SUBTITLE_AREA_MIN_HEIGHT，封面跟着变小。
   * 封面区是 layoutWeight 分到的高度，不随封面大小变化，所以不会来回触发布局。
   */
  audioCoverHeight(): number {
    const preferred = this.coverHeight();
    if (this.audioHeroHeight <= 0) return preferred;
    const hasStatus = !!this.statusText();
    const hasVoice = this.showAudioVoiceRow();
    const hasTabs = this.subtitleAvailable();
    const hasTitle = !this.chapterInHeader();
    // 子项间距：封面、[章节名]、[简介/字幕切换]、简介、[状态行]、[音色]；再加封面和章节名各自的上边距。
    const gaps = AppSpacing.MD * (1 + (hasTitle ? 1 : 0) + (hasTabs ? 1 : 0) + (hasStatus ? 1 : 0) +
      (hasVoice ? 1 : 0)) + AppSpacing.SM * (hasTitle ? 2 : 1);
    const fixed = (hasTitle ? this.audioHeroTitleHeight : 0) + (hasStatus ? this.audioHeroStatusHeight : 0) +
      (hasVoice ? AUDIO_VOICE_ROW_HEIGHT : 0) + (hasTabs ? SUBTITLE_TABS_HEIGHT : 0) + gaps +
      (hasTabs && this.subtitleTab ? SUBTITLE_AREA_MIN_HEIGHT : 0);
    return Math.max(AUDIO_COVER_MIN_HEIGHT, Math.min(preferred, Math.floor(this.audioHeroHeight - fixed)));
  }

  /** 朗读卡片里点到的字换算成面板文字里的位置，交给朗读主人找到那一句重新开读。 */
  onReadingTextTap(event: ClickEvent): void {
    if (this.isAudio() || !this.globalTtsSentenceControl || !this.globalTtsCurrentText) return;
    try {
      const ui = this.getUIContext();
      const position = this.readingTextController.getLayoutManager()
        .getGlyphPositionAtCoordinate(ui.vp2px(event.x), ui.vp2px(event.y));
      ReaderTtsFloatingSession.jumpToPanelText(position.position, this.globalTtsTextBefore.length);
    } catch (error) {
      console.warn('朗读面板点句跳读失败:', error);
    }
  }

  /** 书源提供了多个音色，或简介里说明了音色代码时才显示音色下拉（里面有“自定义音色代码”）。 */
  showAudioVoiceRow(): boolean {
    if (this.isVideo()) return false;
    return this.globalTtsVoiceRevision >= 0 &&
      (this.audioVoiceTitles().length > 1 || /音色/.test(this.hostIntro || this.globalTtsContent || ''));
  }

  skipSeconds(head: boolean): number {
    return AudioSkipRange.normalize(head ? this.globalTtsAudioSkipHead : this.globalTtsAudioSkipTail);
  }

  skipStepEnabled(head: boolean, direction: number): boolean {
    const value = this.skipSeconds(head);
    return direction < 0 ? value > 0 : value < AudioSkipRange.MAX_SECONDS;
  }

  changeSkip(head: boolean, seconds: number): void {
    const value = AudioSkipRange.normalize(seconds);
    ReaderTtsFloatingSession.setAudioSkip(head ? value : this.skipSeconds(true), head ? this.skipSeconds(false) : value);
  }

  /** 片头取当前位置；片尾取“总时长 − 当前位置”。还不知道总时长时不处理。 */
  setSkipToCurrent(head: boolean): void {
    const duration = this.globalTtsAudioDurationMs;
    if (duration <= 0) return;
    const position = Math.max(0, Math.min(this.globalTtsAudioPositionMs, duration));
    this.changeSkip(head, (head ? position : duration - position) / 1000);
  }

  hasTtsVoices(): boolean {
    // 先读修订号登记依赖：音色列表在面板打开后才发布时，这里会跟着重新判断。
    return this.globalTtsVoiceRevision >= 0 && ReaderTtsFloatingSession.ttsVoiceTitles().length > 0;
  }

  chapterEnabled(forward: boolean): boolean {
    return forward ? this.globalTtsCanNext : this.globalTtsCanPrevious;
  }

  speedShown(): number {
    return this.speedDraft > 0 ? this.speedDraft : PlaybackSpeed.normalize(this.globalTtsSpeed);
  }

  speedStepEnabled(direction: number): boolean {
    return direction < 0 ? this.globalTtsSpeed > PlaybackSpeed.MIN + 0.001 :
      this.globalTtsSpeed < PlaybackSpeed.MAX - 0.001;
  }

  commitSpeed(value: number): void {
    if (PlaybackSpeed.same(this.globalTtsSpeed, value)) return;
    ReaderTtsFloatingSession.setSpeed(value);
  }

  gainKind(): string {
    return this.isAudio() ? PlaybackLoudnessGain.AUDIO : PlaybackLoudnessGain.TTS;
  }

  gainStored(): number {
    return this.isAudio() ? this.audioLoudnessGain : this.ttsLoudnessGain;
  }

  gainShown(): number {
    return this.gainDraft >= 0 ? this.gainDraft : this.gainStored();
  }

  gainSupported(): boolean {
    return this.isAudio() ? this.audioLoudnessGainSupported : this.ttsLoudnessGainSupported;
  }

  gainActive(): boolean {
    return this.gainSupported() && this.gainStored() > 0;
  }

  gainValueText(gain: number): string {
    return gain > 0 ? `+${gain} dB` : '关闭';
  }

  gainHint(): string {
    if (!this.gainSupported()) {
      if (this.isAudio()) {
        return PlaybackLoudnessGain.avPlayerSupported() ? '当前音频不支持音量增益' :
          '当前系统版本不支持有声书音量增益';
      }
      return '当前朗读方式不支持音量增益，可换用其他音色后再试';
    }
    return this.gainShown() > PlaybackLoudnessGain.SAFE_DB ? '增益较高，人声可能破音，建议先调大系统音量' : '';
  }

  secondaryIcon(kind: string): Resource {
    if (kind === SECONDARY_TIMER) return $r('sys.symbol.timer');
    if (kind === SECONDARY_SPEED) return $r('sys.symbol.hourglass');
    if (kind === SECONDARY_CATALOG) return $r('sys.symbol.list_bullet');
    if (kind === SECONDARY_SKIP) return $r('sys.symbol.arrow_right_to_line');
    if (kind === SECONDARY_WATCH) return $r('sys.symbol.video');
    return $r('sys.symbol.stop_circle');
  }

  timerActive(): boolean {
    return this.globalTtsTimerMinutes > 0 && this.globalTtsTimerRemainingSeconds > 0;
  }

  timerWarning(): boolean {
    return this.timerActive() && this.globalTtsTimerRemainingSeconds <= TIMER_WARN_SECONDS;
  }

  timerColor(): ResourceColor {
    return this.timerWarning() ? ThemeRuntime.dangerColor(this.darkMode) : this.accentColor;
  }

  /** 恢复的定时可能只知道剩余秒数，总时长取两者较大值，细环不会超过一圈。 */
  timerTotalSeconds(): number {
    return Math.max(1, this.globalTtsTimerMinutes * 60, this.globalTtsTimerRemainingSeconds);
  }

  timerRemainingShown(): number {
    return Math.min(this.timerTotalSeconds(), Math.max(0, this.globalTtsTimerRemainingSeconds));
  }

  timerEndClock(): string {
    const end = new Date(Date.now() + this.globalTtsTimerRemainingSeconds * 1000);
    const hours = end.getHours();
    const minutes = end.getMinutes();
    return `${hours < 10 ? '0' : ''}${hours}:${minutes < 10 ? '0' : ''}${minutes}`;
  }

  timerChipSelected(minutes: number): boolean {
    return minutes === 0 && !this.timerActive();
  }

  secondaryLabel(kind: string): string {
    if (kind === SECONDARY_TIMER) {
      return this.timerActive() ? formatTimerRemaining(this.globalTtsTimerRemainingSeconds) : '定时';
    }
    if (kind === SECONDARY_SPEED) {
      const speed = `${PlaybackSpeed.label(this.globalTtsSpeed)}x`;
      return this.gainActive() ? `${speed}·+${this.gainStored()}` : speed;
    }
    if (kind === SECONDARY_SKIP) {
      if (this.skipSeconds(true) > 0) return `片头${AudioSkipRange.label(this.skipSeconds(true))}`;
      if (this.skipSeconds(false) > 0) return `片尾${AudioSkipRange.label(this.skipSeconds(false))}`;
      return '跳过';
    }
    if (kind === SECONDARY_CATALOG) return this.isVideo() ? '选集' : '目录';
    if (kind === SECONDARY_WATCH) return '看画面';
    return '停止';
  }

  secondaryColor(kind: string, icon: boolean): ResourceColor {
    if (kind === SECONDARY_STOP) return ThemeRuntime.dangerColor(this.darkMode);
    let active = false;
    if (kind === SECONDARY_TIMER) {
      active = this.globalTtsTimerMinutes > 0 || this.optionsPanel === 1;
    } else if (kind === SECONDARY_SPEED) {
      active = Math.abs(this.globalTtsSpeed - 1) > 0.01 || this.gainActive() || this.optionsPanel === 2;
    } else if (kind === SECONDARY_SKIP) {
      active = this.skipSeconds(true) > 0 || this.skipSeconds(false) > 0 || this.optionsPanel === 4;
    }
    if (active) return this.accentColor;
    return icon ? this.primaryTextColor : this.subTextColor;
  }

  onSecondaryTap(kind: string): void {
    if (kind === SECONDARY_TIMER) {
      this.optionsPanel = this.optionsPanel === 1 ? 0 : 1;
    } else if (kind === SECONDARY_SPEED) {
      this.speedDraft = -1;
      this.gainDraft = -1;
      this.optionsPanel = this.optionsPanel === 2 ? 0 : 2;
    } else if (kind === SECONDARY_SKIP) {
      this.optionsPanel = this.optionsPanel === 4 ? 0 : 4;
    } else if (kind === SECONDARY_CATALOG) {
      this.onOpenCatalog();
    } else if (kind === SECONDARY_WATCH) {
      this.close();
      ReaderTtsFloatingSession.watchVideo();
    } else {
      this.close();
      ReaderTtsFloatingSession.stop();
    }
  }

  coverInitial(): string {
    const name = this.hostBookName || this.globalTtsBookName;
    return name ? name.substring(0, 1) : '书';
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
