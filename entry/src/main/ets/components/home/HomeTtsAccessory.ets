import { BookCover } from '../book/BookCover';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ReaderTtsFloatingSession } from '../../utils/ReaderTtsFloatingSession';

/**
 * 首页底栏上方的朗读/听书伴生条，朗读与听书共用；背景与位置由首页给。
 * 封面裁成圆形，播放时慢转、暂停或加载时停在当前角度。
 * 状态全部直接读 AppStorage。
 */
@Component
export struct HomeTtsAccessory {
  @Prop accentColor: string = '#0A59F7';
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#8A8A8A';
  @Prop trackColor: string = '#1F000000';
  onOpen: () => void = (): void => {
  };

  @StorageProp('globalTtsBookUrl') bookUrl: string = '';
  @StorageProp('globalTtsBookName') bookName: string = '';
  @StorageProp('globalTtsChapterTitle') chapterTitle: string = '';
  @StorageProp('globalTtsMode') mode: string = '';
  @StorageProp('globalTtsPaused') @Watch('syncSpin') paused: boolean = false;
  @StorageProp('globalTtsBusy') @Watch('syncSpin') busy: boolean = false;
  @StorageProp('globalTtsCanPrevious') canPrevious: boolean = false;
  @StorageProp('globalTtsCanNext') canNext: boolean = false;
  @StorageProp('globalTtsProgress') bookProgress: number = 0;
  @StorageProp('globalTtsChapterPercent') chapterPercent: number = -1;
  @StorageProp('globalTtsAudioPositionMs') audioPositionMs: number = 0;
  @StorageProp('globalTtsAudioDurationMs') audioDurationMs: number = 0;
  @State coverAngle: number = 0;
  private spinning: boolean = false;
  private spinBaseAngle: number = 0;
  private spinStartedAt: number = 0;

  static readonly DISC_SIZE: number = 38;
  static readonly SPIN_DURATION: number = 9000;
  static readonly BUTTON_PREVIOUS: number = 0;
  static readonly BUTTON_TOGGLE: number = 1;
  static readonly BUTTON_NEXT: number = 2;

  aboutToAppear(): void {
    this.syncSpin();
  }

  aboutToDisappear(): void {
    this.spinning = false;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Row({ space: AppSpacing.SM }) {
        Row({ space: AppSpacing.MD }) {
          this.disc()
          Column({ space: 1 }) {
            Text(this.bookName || (this.isAudio() ? '听书' : '朗读'))
              .fontSize(AppFontSize.BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.textColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.subtitle())
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .height('100%')
        .accessibilityText(`${this.bookName}，${this.subtitle()}，打开播放面板`)
        .onClick(() => this.onOpen())

        // 三个按钮紧挨着排，并成一行时伴生条变窄，也给书名留出位置。
        Row() {
          this.iconButton(HomeTtsAccessory.BUTTON_PREVIOUS)
          this.iconButton(HomeTtsAccessory.BUTTON_TOGGLE)
          this.iconButton(HomeTtsAccessory.BUTTON_NEXT)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: AppSpacing.SM, right: AppSpacing.XS })

      if (this.hasProgress()) {
        Stack({ alignContent: Alignment.Start }) {
          Column()
            .width(`${(this.progress() * 100).toFixed(1)}%`)
            .height(2)
            .borderRadius(1)
            .backgroundColor(this.accentColor)
        }
        .width('82%')
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.trackColor)
        .margin({ bottom: 3 })
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  disc() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.bookUrl) {
        BookCover({
          bookUrl: this.bookUrl,
          name: this.bookName,
          placeholderColor: this.accentColor,
          cornerRadius: HomeTtsAccessory.DISC_SIZE / 2,
          decodeWidth: 114,
          decodeHeight: 152
        })
      } else {
        Text((this.bookName || '书').substring(0, 1))
          .fontSize(AppFontSize.BODY)
          .fontColor('#FFFFFF')
      }
      Circle()
        .width(HomeTtsAccessory.DISC_SIZE)
        .height(HomeTtsAccessory.DISC_SIZE)
        .fill(Color.Transparent)
        .stroke('#33FFFFFF')
        .strokeWidth(1)
    }
    .width(HomeTtsAccessory.DISC_SIZE)
    .height(HomeTtsAccessory.DISC_SIZE)
    .borderRadius(HomeTtsAccessory.DISC_SIZE / 2)
    .clip(true)
    .backgroundColor(this.accentColor)
    .rotate({ angle: this.coverAngle })
  }

  /**
   * 只传固定的按钮类型：@Builder 按值传入的图标和可用状态在状态变化后不会刷新，
   * 暂停/继续图标和上一章、下一章的可点状态都要在这里直接读状态。
   */
  @Builder
  iconButton(kind: number) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(this.buttonIcon(kind))
        .fontSize(20)
        .fontColor([this.textColor])
    }
    .width(36)
    .height(40)
    .opacity(this.buttonEnabled(kind) ? 1 : 0.35)
    .enabled(this.buttonEnabled(kind))
    .accessibilityText(this.buttonLabel(kind))
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.88 })
    .onClick(() => this.onButton(kind))
  }

  buttonIcon(kind: number): Resource {
    if (kind === HomeTtsAccessory.BUTTON_PREVIOUS) return $r('sys.symbol.backward_end_fill');
    if (kind === HomeTtsAccessory.BUTTON_NEXT) return $r('sys.symbol.forward_end_fill');
    return this.paused ? $r('sys.symbol.play_fill') : $r('sys.symbol.pause_fill');
  }

  buttonLabel(kind: number): string {
    if (kind === HomeTtsAccessory.BUTTON_PREVIOUS) return '上一章';
    if (kind === HomeTtsAccessory.BUTTON_NEXT) return '下一章';
    return this.paused ? '继续' : '暂停';
  }

  buttonEnabled(kind: number): boolean {
    if (kind === HomeTtsAccessory.BUTTON_PREVIOUS) return this.canPrevious;
    if (kind === HomeTtsAccessory.BUTTON_NEXT) return this.canNext;
    return true;
  }

  onButton(kind: number): void {
    if (kind === HomeTtsAccessory.BUTTON_PREVIOUS) {
      ReaderTtsFloatingSession.previous();
    } else if (kind === HomeTtsAccessory.BUTTON_NEXT) {
      ReaderTtsFloatingSession.next();
    } else {
      ReaderTtsFloatingSession.toggle();
    }
  }

  syncSpin(): void {
    if (this.paused || this.busy) {
      this.stopSpin();
    } else {
      this.startSpin();
    }
  }

  /** 无限循环动画从当前角度转一整圈，暂停时按经过的时间算出角度停住，继续时从那里接着转。 */
  startSpin(): void {
    if (this.spinning) return;
    this.spinning = true;
    this.spinBaseAngle = this.coverAngle % 360;
    this.coverAngle = this.spinBaseAngle;
    this.spinStartedAt = Date.now();
    const target = this.spinBaseAngle + 360;
    this.getUIContext().animateTo({
      duration: HomeTtsAccessory.SPIN_DURATION,
      curve: Curve.Linear,
      iterations: -1
    }, (): void => {
      this.coverAngle = target;
    });
  }

  stopSpin(): void {
    if (!this.spinning) return;
    this.spinning = false;
    const elapsed = (Date.now() - this.spinStartedAt) % HomeTtsAccessory.SPIN_DURATION;
    const angle = (this.spinBaseAngle + elapsed / HomeTtsAccessory.SPIN_DURATION * 360) % 360;
    this.getUIContext().animateTo({ duration: 0 }, (): void => {
      this.coverAngle = angle;
    });
  }

  isAudio(): boolean {
    return this.mode === 'audio';
  }

  subtitle(): string {
    if (this.busy) return '加载中…';
    const chapter = this.chapterTitle || (this.isAudio() ? '听书中' : '朗读中');
    return this.paused ? `已暂停 · ${chapter}` : chapter;
  }

  /** 有进度来源就一直显示轨道，进度为 0（章首、刚切章）时只是填充为空，不让整条线忽隐忽现。 */
  hasProgress(): boolean {
    return this.isAudio() ? this.audioDurationMs > 0 : (this.chapterPercent >= 0 || this.bookProgress > 0);
  }

  /** 听书显示本集进度，朗读显示本章进度；朗读页没给本章进度时退回整本进度。 */
  progress(): number {
    if (this.isAudio()) {
      return this.audioDurationMs > 0 ? Math.max(0, Math.min(1, this.audioPositionMs / this.audioDurationMs)) : 0;
    }
    const percent = this.chapterPercent >= 0 ? this.chapterPercent : (this.bookProgress || 0);
    return Math.max(0, Math.min(1, percent / 100));
  }
}
