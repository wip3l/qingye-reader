import { SubtitleCue, SubtitleText } from '../core/subtitle/SubtitleText';
import { AudioSubtitleService } from '../utils/subtitle/AudioSubtitleService';
import { SubtitleModelStore } from '../utils/subtitle/SubtitleModelStore';
import { RemoteAudioPlayback } from '../utils/RemoteAudioPlayback';
import { ReaderTtsFloatingSession } from '../utils/ReaderTtsFloatingSession';
import { AudioOfflineStore } from '../core/book/AudioOfflineStore';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { LengthMetrics } from '@kit.ArkUI';

/** 播放位置刷新间隔：字幕切行比面板进度条（每秒一次）更跟手。 */
const POSITION_POLL_MS = 250;
/** 用户手动滑过字幕后，这么久不再自动跟随当前行。 */
const MANUAL_SCROLL_HOLD_MS = 3000;
/** 上下边缘渐隐的长度，半截的行淡出而不是被硬切。 */
const FADE_EDGE_VP = 24;

class SubtitleLineSource implements IDataSource {
  private cues: SubtitleCue[] = [];
  private listeners: DataChangeListener[] = [];

  replace(cues: SubtitleCue[]): void {
    this.cues = cues;
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }

  totalCount(): number {
    return this.cues.length;
  }

  getData(index: number): SubtitleCue {
    return this.cues[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }
}

/**
 * 听书面板“字幕”页签：像歌词一样居中滚动，当前句加粗，点一句跳到那里。
 * 识别由 AudioSubtitleService 在后台做，这里只显示状态和结果；组件在屏幕上时服务才工作。
 */
@Component
export struct AudioSubtitleView {
  @Prop darkMode: boolean = false;
  @Prop accentColor: ResourceColor = '#2E5A88';
  @Prop primaryTextColor: ResourceColor = '#1E2227';
  @Prop subTextColor: ResourceColor = '#6A6E75';
  @StorageProp('audioSubtitlePhase') phase: string = AudioSubtitleService.IDLE;
  @StorageProp('audioSubtitleMessage') message: string = '';
  @StorageProp('audioSubtitleRevision') @Watch('onCuesChanged') revision: number = 0;
  @StorageProp('subtitleModelReceived') modelReceived: number = 0;
  @StorageProp('subtitleModelError') modelError: string = '';
  @State lineCount: number = 0;
  @State currentIndex: number = -1;
  @State positionMs: number = 0;
  @State currentReady: boolean = false;
  private cues: SubtitleCue[] = [];
  private source: SubtitleLineSource = new SubtitleLineSource();
  private scroller: ListScroller = new ListScroller();
  private pollTimer: number = -1;
  /** 手指按在字幕上，或松手后 MANUAL_SCROLL_HOLD_MS 内：不自动跟随。程序滚动不算。 */
  private touching: boolean = false;
  private manualUntil: number = 0;
  private followPending: boolean = false;
  /** 字幕区高度，用来在上下留出半屏，让第一句和最后一句也能停在正中。 */
  @State viewHeight: number = 0;

  aboutToAppear(): void {
    SubtitleModelStore.refresh();
    AudioSubtitleService.get().setVisible(true);
    this.onCuesChanged();
    this.pollTimer = setInterval((): void => this.poll(), POSITION_POLL_MS);
  }

  aboutToDisappear(): void {
    if (this.pollTimer >= 0) clearInterval(this.pollTimer);
    this.pollTimer = -1;
    AudioSubtitleService.get().setVisible(false);
  }

  onCuesChanged(): void {
    this.cues = AudioSubtitleService.get().cues();
    this.source.replace(this.cues);
    this.lineCount = this.cues.length;
    this.currentIndex = -1;
    this.poll();
  }

  poll(): void {
    const service = AudioSubtitleService.get();
    const position = RemoteAudioPlayback.get().positionMs;
    this.positionMs = position;
    this.currentReady = service.readyAt(position);
    const index = SubtitleText.indexAt(this.cues, position);
    if (index === this.currentIndex) {
      // 手动滑走后停够了时间，回到当前句。
      if (this.followPending) this.followCurrent(true);
      return;
    }
    this.currentIndex = index;
    this.followCurrent(true);
  }

  /** 把当前句滚到正中。用户正在拖或刚拖完时不动。 */
  followCurrent(animated: boolean): void {
    if (this.currentIndex < 0) return;
    if (this.touching || Date.now() < this.manualUntil) {
      this.followPending = true;
      return;
    }
    this.followPending = false;
    try {
      this.scroller.scrollToIndex(this.currentIndex, animated, ScrollAlign.CENTER);
    } catch (_) {}
  }

  build() {
    Column() {
      if (this.phase === AudioSubtitleService.READY) {
        this.lines()
      } else {
        this.statusBox()
      }
    }
    .width('100%')
    .height('100%')
    .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
      const height = Number(size.height) || 0;
      if (Math.abs(height - this.viewHeight) < 1) return;
      this.viewHeight = height;
      // 封面缩放会改变字幕区高度，等新的上下留白生效后重新居中。
      setTimeout((): void => this.followCurrent(false), 0);
    })
  }

  @Builder
  lines() {
    Stack({ alignContent: Alignment.Bottom }) {
      List({ scroller: this.scroller }) {
        LazyForEach(this.source, (cue: SubtitleCue, index: number) => {
          ListItem() {
            Text(cue.text)
              .fontSize(index === this.currentIndex ? AppFontSize.BODY_LARGE : AppFontSize.BODY)
              .fontWeight(index === this.currentIndex ? FontWeight.Bold : FontWeight.Regular)
              .fontColor(index === this.currentIndex ? this.primaryTextColor : this.subTextColor)
              .lineHeight(index === this.currentIndex ? 24 : 22)
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM, left: AppSpacing.XS, right: AppSpacing.XS })
              .borderRadius(8)
              .accessibilityText(`跳到这一句：${cue.text}`)
              .onClick(() => this.jumpTo(cue))
          }
        }, (cue: SubtitleCue, index: number): string => `${index}_${cue.startMs}_${cue.text}`)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      // 上下留出半屏，第一句和最后一句也能停在中间。
      .contentStartOffset(Math.max(0, this.viewHeight / 2 - 20))
      .contentEndOffset(Math.max(0, this.viewHeight / 2 - 20))
      .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(FADE_EDGE_VP) })
      // 只把手指拖动当成手动滚动；自动居中本身也会触发滚动回调，不能拿 onScrollStart 判断。
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.touching = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.touching = false;
          this.manualUntil = Date.now() + MANUAL_SCROLL_HOLD_MS;
        }
      })

      // 播放位置所在的那段还没识别出来时，底部提示正在识别；整章目前一句都没有时说明没听到人声。
      if (!this.currentReady) {
        this.hint('正在识别这一段…')
      } else if (this.lineCount === 0) {
        this.hint('这一段没有识别到说话声')
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  hint(text: string) {
    Row({ space: AppSpacing.SM }) {
      if (text.startsWith('正在')) {
        LoadingProgress().width(16).height(16).color(this.subTextColor as ResourceColor)
      }
      Text(text).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor)
    }
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
    .borderRadius(14)
    .backgroundColor(ThemeRuntime.softFillColor(this.darkMode))
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  statusBox() {
    // 字幕区最少约 140vp，每种状态的内容都控制在这个高度以内。
    Column({ space: AppSpacing.SM }) {
      if (this.phase === AudioSubtitleService.NEEDS_MODEL) {
        this.statusTitle('开启 AI 字幕')
        this.statusText(`本机识别，不上传音频 · 约 ${SubtitleModelStore.totalLabel()}`)
        if (this.modelError) this.statusText(this.modelError, true)
        this.primaryButton(AudioOfflineStore.network() === 'cellular' ? '用流量下载模型' : '下载模型',
          () => this.downloadModel())
      } else if (this.phase === AudioSubtitleService.MODEL) {
        this.statusTitle('正在下载识别模型')
        Progress({ value: this.modelReceived, total: SubtitleModelStore.totalBytes(), type: ProgressType.Linear })
          .width('80%')
          .color(this.accentColor)
          .backgroundColor(ThemeRuntime.hairlineColor(this.darkMode))
        this.statusText(`${this.megabytes(this.modelReceived)} / ${SubtitleModelStore.totalLabel()} · 离开也会继续`)
        this.secondaryButton('取消', () => SubtitleModelStore.cancel())
      } else if (this.phase === AudioSubtitleService.AUDIO) {
        this.statusTitle('正在取本章音频')
        if (this.message) this.statusText(this.message)
        this.statusText('先存到本地再识别，听过后自动删除')
      } else if (this.phase === AudioSubtitleService.NEEDS_CELLULAR) {
        this.statusTitle('正在使用移动网络')
        this.statusText('已开启“手动下载仅用 Wi-Fi”，取本章音频要用流量')
        this.primaryButton('用流量取本章音频', () => AudioSubtitleService.get().allowCellular())
      } else if (this.phase === AudioSubtitleService.ERROR) {
        this.statusTitle('这一章暂时没法生成字幕')
        this.statusText(this.message || '可以稍后重试')
        this.secondaryButton('重试', () => AudioSubtitleService.get().retry())
      } else if (this.phase === AudioSubtitleService.LOADING) {
        LoadingProgress().width(28).height(28).color(this.subTextColor as ResourceColor)
        this.statusText('正在准备字幕…')
      } else {
        this.statusText('开始播放后显示字幕')
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
  }

  @Builder
  statusTitle(text: string) {
    Text(text)
      .fontSize(AppFontSize.BODY_LARGE)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.primaryTextColor)
      .textAlign(TextAlign.Center)
  }

  @Builder
  statusText(text: string, warn: boolean = false) {
    Text(text)
      .fontSize(AppFontSize.CAPTION)
      .lineHeight(19)
      .fontColor(warn ? ThemeRuntime.dangerColor(this.darkMode) : this.subTextColor)
      .textAlign(TextAlign.Center)
  }

  @Builder
  primaryButton(label: string, action: () => void) {
    Button(label)
      .height(32)
      .fontSize(AppFontSize.BODY)
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
      .backgroundColor(this.accentColor)
      .fontColor(ThemeRuntime.onAccentColor())
      .onClick(action)
  }

  @Builder
  secondaryButton(label: string, action: () => void) {
    Button(label)
      .height(32)
      .fontSize(AppFontSize.BODY)
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
      .backgroundColor(ThemeRuntime.softFillColor(this.darkMode))
      .fontColor(this.primaryTextColor)
      .onClick(action)
  }

  megabytes(bytes: number): string {
    return `${Math.round(Math.max(0, bytes) / 1024 / 1024)} MB`;
  }

  jumpTo(cue: SubtitleCue): void {
    this.manualUntil = 0;
    this.touching = false;
    ReaderTtsFloatingSession.seekAudio(cue.startMs);
  }

  /** 移动网络下先确认，Wi-Fi 下直接开始。 */
  async downloadModel(): Promise<void> {
    if (AudioOfflineStore.network() === 'cellular') {
      try {
        const result = await this.getUIContext().getPromptAction().showDialog({
          title: '正在使用移动网络',
          message: `字幕模型约 ${SubtitleModelStore.totalLabel()}，会消耗较多流量。确定现在下载？`,
          buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.darkMode) },
            { text: '用流量下载', color: ThemeRuntime.dangerColor(this.darkMode) }]
        });
        if (result.index !== 1) return;
      } catch (_) {
        return;
      }
    }
    AudioSubtitleService.get().downloadModel();
  }
}
