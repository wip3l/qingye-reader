import { AppFontSize } from '../../theme/AppFontSize';
import { ThemeRuntime } from '../../theme/ThemeRuntime';

/** Shared content for the system-material surface and the ordinary reader panel. */
@Component
export struct ReaderQuickJumpContent {
  @Prop mode: string = 'chapter';
  @Prop chapterLabel: string = '章节';
  @Prop chapterUnit: string = '章';
  @Prop value: number = 0;
  @Prop chapterCount: number = 0;
  @Prop pageCount: number = 0;
  @Prop currentChapter: number = 0;
  @Prop valueLabel: string = '';
  @Prop busy: boolean = false;
  @Prop dark: boolean = false;
  @Prop textColor: string = '';
  @Prop subTextColor: string = '';
  @Prop accentColor: string = '';
  @Prop trackColor: string = '';
  @Prop thumbColor: string = '';
  /** 收起时只留顶部小横条和进度条；在面板上纵向滑动或点小横条切换。 */
  @Prop expanded: boolean = false;
  @Prop headerHeight: number = 44;
  onModeChange: (mode: string) => void = (_mode: string): void => {};
  onChange: (value: number, mode: SliderChangeMode) => void = (_value: number, _mode: SliderChangeMode): void => {};
  onStep: (direction: number) => void = (_direction: number): void => {};
  onExpandedChange: (expanded: boolean) => void = (_expanded: boolean): void => {};
  /** 纵向滑动起手时进度条可能已经开始拖动，交给页面撤掉预览与气泡。 */
  onSlideCancel: () => void = (): void => {};
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  /** 本次按下的方向：'' 未定，'v' 纵向展开/收起，'h' 横向交给进度条。 */
  private touchLock: string = '';
  private swipeHandled: boolean = false;
  private suppressSliderUntil: number = 0;

  handleSliderChange(value: number, mode: SliderChangeMode): void {
    // 纵向滑动期间及松手后片刻，进度条的松手/点按不能当作跳转。
    if (this.touchLock === 'v' || Date.now() < this.suppressSliderUntil) {
      if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.onSlideCancel();
      return;
    }
    this.onChange(value, mode);
  }

  /**
   * 自己按原始触点判方向，不用竖直 PanGesture：后者回报的横向位移恒为 0，
   * 横拖进度条时手指稍有上下抖动就会被当成竖滑，把拖动撤掉。
   */
  handleTouch(event: TouchEvent): void {
    const touch = event.changedTouches.length > 0 ? event.changedTouches[0] :
      (event.touches.length > 0 ? event.touches[0] : undefined);
    if (!touch) return;
    if (event.type === TouchType.Down) {
      this.touchStartX = touch.windowX;
      this.touchStartY = touch.windowY;
      this.touchLock = '';
      this.swipeHandled = false;
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.touchLock === 'v') this.suppressSliderUntil = Date.now() + 300;
      this.touchLock = '';
      return;
    }
    if (event.type !== TouchType.Move) return;
    const dx = touch.windowX - this.touchStartX;
    const dy = touch.windowY - this.touchStartY;
    if (this.touchLock === '') {
      if (Math.abs(dy) >= 8 && Math.abs(dy) > Math.abs(dx) * 1.5) {
        this.touchLock = 'v';
        this.onSlideCancel();
      } else if (Math.abs(dx) >= 8) {
        this.touchLock = 'h';
      }
    }
    if (this.touchLock === 'v' && !this.swipeHandled && Math.abs(dy) >= 16) {
      this.swipeHandled = true;
      const expand = dy < 0;
      if (expand !== this.expanded) this.onExpandedChange(expand);
    }
  }

  @Builder
  modeButton(mode: string, label: string) {
    Button(label, { type: ButtonType.Capsule, stateEffect: true })
      .fontSize(AppFontSize.BODY)
      .fontWeight(this.mode === mode ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.mode === mode ? this.textColor : this.subTextColor)
      .backgroundColor(Color.Transparent)
      .height(36)
      .layoutWeight(1)
      .padding({ left: 6, right: 6 })
      .enabled(!this.busy && this.chapterCount > 0)
      .accessibilityText(`${label}跳转${this.mode === mode ? '，已选中' : ''}`)
      .onClick(() => this.onModeChange(mode))
  }

  modeIndex(): number {
    return this.mode === 'percent' ? 1 : (this.mode === 'page' ? 2 : 0);
  }

  sliderMax(): number {
    if (this.mode === 'percent') return 100;
    // 页数还在统计时页面传来的是 0–1000 的本章阅读比例。
    if (this.mode === 'page' && this.pageCount <= 0) return 1000;
    return Math.max(1, (this.mode === 'page' ? this.pageCount : this.chapterCount) - 1);
  }

  sliderEnabled(): boolean {
    if (this.busy) return false;
    if (this.mode === 'percent') return this.chapterCount > 0;
    return (this.mode === 'page' ? this.pageCount : this.chapterCount) > 1;
  }

  /** 收起时进度条右侧的短读数；展开时上方一行已有完整文字。 */
  compactLabel(): string {
    if (this.mode === 'percent') return this.chapterCount > 0 ? `${this.value.toFixed(1)}%` : '—';
    const count = this.mode === 'page' ? this.pageCount : this.chapterCount;
    if (count <= 0) return this.mode === 'page' ? '…' : '—';
    return `${Math.round(this.value) + 1}/${count}${this.mode === 'page' ? '页' : this.chapterUnit}`;
  }

  sliderAccessibilityName(): string {
    if (this.mode === 'percent') return '全书百分比';
    return this.mode === 'page' ? `本${this.chapterUnit}页数` : this.chapterLabel;
  }

  @Builder
  stepButton(direction: number) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(direction < 0 ? $r('sys.symbol.chevron_left') : $r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.textColor])
    }
    .width(32)
    .height(40)
    .backgroundColor(Color.Transparent)
    .enabled(!this.busy && this.chapterCount > 0 &&
      (direction < 0 ? this.currentChapter > 0 : this.currentChapter < this.chapterCount - 1))
    .accessibilityText(`${direction < 0 ? '上一' : '下一'}${this.chapterUnit}`)
    .onClick(() => this.onStep(direction))
  }

  build() {
    Column() {
      Row() {
        Row()
          .width(28)
          .height(3)
          .borderRadius(1.5)
          .backgroundColor(this.subTextColor)
          .opacity(0.45)
      }
      .width(96)
      .height(14)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .accessibilityText(this.expanded ? '收起跳转方式' : '展开跳转方式')
      .onClick(() => this.onExpandedChange(!this.expanded))
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width(`${100 / 3}%`)
            .height(36)
            .borderRadius(18)
            .backgroundColor(this.thumbColor)
            .translate({ x: `${this.modeIndex() * 100}%` })
            .animation({ duration: 180, curve: Curve.EaseOut })
          Row() {
            this.modeButton('chapter', this.chapterLabel)
            this.modeButton('percent', '百分比')
            this.modeButton('page', '页数')
          }
          .width('100%')
        }
        .width('64%')
        .constraintSize({ maxWidth: 252 })
        .height(44)
        .padding(4)
        .borderRadius(22)
        .backgroundColor(ThemeRuntime.softFillColor(this.dark))
        Text(this.valueLabel)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.busy ? this.subTextColor : this.textColor)
          .layoutWeight(1)
          .textAlign(TextAlign.End)
          .maxLines(2)
      }
      .width('100%')
      .height(this.expanded ? this.headerHeight : 0)
      .padding({ left: 12, right: 16 })
      .clip(true)
      .visibility(this.expanded ? Visibility.Visible : Visibility.Hidden)
      Row() {
        this.stepButton(-1)
        Slider({
          value: this.value,
          min: 0,
          max: this.sliderMax(),
          step: this.mode === 'percent' ? 0.1 : 1,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .height(40)
          .trackThickness(4)
          .blockSize({ width: 18, height: 18 })
          .selectedColor(this.accentColor)
          .trackColor(this.trackColor)
          .blockColor(this.thumbColor)
          .blockBorderColor(this.accentColor)
          .blockBorderWidth(2)
          .showSteps(false)
          .enabled(this.sliderEnabled())
          .opacity(this.sliderEnabled() ? 1 : 0.4)
          .accessibilityText(`${this.sliderAccessibilityName()}，${this.valueLabel}`)
          .onChange((value: number, mode: SliderChangeMode) => this.handleSliderChange(value, mode))
        this.stepButton(1)
        if (!this.expanded) {
          Text(this.compactLabel())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor)
            .maxLines(1)
            .textAlign(TextAlign.End)
            .constraintSize({ minWidth: 36, maxWidth: 88 })
            .accessibilityLevel('no')
        }
      }
      .width('100%')
      .height(40)
      .padding({ left: 4, right: 12 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .onTouch((event: TouchEvent) => this.handleTouch(event))
  }
}
