import { AppSpacing } from '../../theme/AppSpacing';

const READER_INFO_HINT_EFFECT: TransitionEffect = TransitionEffect.OPACITY
  .combine(TransitionEffect.translate({ y: 4 }))
  .animation({ duration: 200, curve: Curve.EaseOut });

/** 页眉页脚里的一个槽位：一段单行文字，后面可跟电池图标和电量。 */
@Component
struct ReaderInfoBarSlot {
  @Prop text: string = '';
  /** 电量百分比；小于 0 时不画电池。 */
  @Prop battery: number = -1;
  @Prop textSize: number = 12;
  @Prop textColor: string = '#80868B';
  @Prop justify: FlexAlign = FlexAlign.Start;
  // 布局参数作用在组件根节点上，由父级 Row 直接按权重和最大宽度排布。
  @Prop slotWeight: number = 0;
  @Prop slotMaxWidth: string = '100%';
  @Prop slotMarginLeft: number = 0;
  @Prop slotMarginRight: number = 0;
  @Prop slotOpacity: number = 1;
  /** 中间槽位与眼动提示互换时淡入淡出。 */
  @Prop fades: boolean = false;

  build() {
    Row({ space: AppSpacing.XS }) {
      if (this.text) {
        Text(this.text)
          .fontSize(this.textSize)
          .lineHeight(this.textSize)
          .textVerticalAlign(TextVerticalAlign.CENTER)
          .fontColor(this.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
      }
      if (this.battery >= 0) {
        Row() {
          Stack({ alignContent: Alignment.Start }) {
            Row()
              .width(`${Math.max(0, Math.min(100, this.battery))}%`)
              .height('100%')
              .backgroundColor(this.textColor)
              .borderRadius(1)
          }
          .width(this.textSize * 1.6)
          .height(this.textSize * 0.75)
          .padding(1)
          .border({ width: 1, color: this.textColor, radius: 2.5 })

          Row()
            .width(1.5)
            .height(this.textSize * 0.3)
            .backgroundColor(this.textColor)
            .borderRadius({ topRight: 1, bottomRight: 1 })
        }
        .alignItems(VerticalAlign.Center)

        Text(`${this.battery}%`)
          .fontSize(this.textSize)
          .lineHeight(this.textSize)
          .textVerticalAlign(TextVerticalAlign.CENTER)
          .fontColor(this.textColor)
          .maxLines(1)
      }
    }
    .justifyContent(this.justify)
    .alignItems(VerticalAlign.Center)
    .layoutWeight(this.slotWeight)
    .constraintSize({ maxWidth: this.slotMaxWidth })
    .margin({ left: this.slotMarginLeft, right: this.slotMarginRight })
    .opacity(this.slotOpacity)
    .transition(this.fades ? READER_INFO_HINT_EFFECT : TransitionEffect.IDENTITY)
  }
}

/**
 * 眼动翻页提示“︿ 抬眼翻页”：灰字打底，主题色按注视进度从左往右把字填满，填满即表示可以抬眼翻页，
 * 箭头随后轻轻上下动。页脚中间槽位和无页脚时的底部提示共用它。
 */
@Component
export struct ReaderEyeTurnFillHint {
  @Prop text: string = '抬眼翻页';
  /** 0–1 的注视进度。 */
  @Prop progress: number = 0;
  @Prop @Watch('onArmedChange') armed: boolean = false;
  @Prop textSize: number = 12;
  @Prop baseColor: string = '#80868B';
  @Prop baseOpacity: number = 1;
  @Prop fillColor: string = '#0A59F7';
  @State private fullWidth: number = 0;
  @State private nudgeY: number = 0;

  aboutToAppear(): void {
    if (this.armed) this.startNudge();
  }

  onArmedChange(): void {
    if (this.armed) {
      this.startNudge();
    } else {
      this.getUIContext().animateTo({ duration: 0 }, (): void => {
        this.nudgeY = 0;
      });
    }
  }

  private startNudge(): void {
    this.nudgeY = 0;
    this.getUIContext().animateTo({
      duration: 550,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, (): void => {
      this.nudgeY = -1.5;
    });
  }

  private filledWidth(): number {
    return this.fullWidth * Math.max(0, Math.min(1, this.armed ? 1 : this.progress));
  }

  @Builder
  label(color: string) {
    Row({ space: 2 }) {
      SymbolGlyph($r('sys.symbol.chevron_up'))
        .fontSize(this.textSize)
        .fontColor([color])
        .translate({ y: this.nudgeY })
      Text(this.text)
        .fontSize(this.textSize)
        .lineHeight(this.textSize)
        .textVerticalAlign(TextVerticalAlign.CENTER)
        .fontWeight(FontWeight.Medium)
        .fontColor(color)
        .maxLines(1)
    }
    .height(this.textSize)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Row() {
        this.label(this.baseColor)
      }
      .opacity(this.baseOpacity)
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        const width = Number(newArea.width);
        if (width > 0 && Math.abs(width - this.fullWidth) >= 0.5) this.fullWidth = width;
      })

      // 主题色那一层与灰字完全重合，只按进度裁出左边一段。
      Stack({ alignContent: Alignment.Start }) {
        Row() {
          this.label(this.fillColor)
        }
        .width(this.fullWidth)
      }
      .width(this.filledWidth())
      .height(this.textSize)
      .clip(true)
      .animation({ duration: 160, curve: Curve.Linear })
    }
    // 与文字槽位同高，提示出现时页脚高度不变，正文不会重新分页。
    .height(this.textSize)
  }
}

/**
 * 页眉或页脚的一行信息：左、中、右三个槽位。
 * 中间槽位有内容时左右两侧等宽，保证中间内容居中；否则左侧占满剩余宽度。
 */
@Component
export struct ReaderInfoBarRow {
  @Prop leftText: string = '';
  @Prop centerText: string = '';
  @Prop rightText: string = '';
  @Prop leftBattery: number = -1;
  @Prop centerBattery: number = -1;
  @Prop rightBattery: number = -1;
  @Prop textSize: number = 12;
  @Prop textColor: string = '#80868B';
  /** 0–1。 */
  @Prop textOpacity: number = 1;
  /** 眼动翻页的注视进度 0–1；大于 0 或 cueArmed 时中间槽位换成“抬眼翻页”填色提示。 */
  @Prop cueProgress: number = 0;
  @Prop cueArmed: boolean = false;
  @Prop cueColor: string = '#0A59F7';
  /** 提示文字：旧版“抬眼翻页”，新版识别模型“上看翻页”。 */
  @Prop cueText: string = '抬眼翻页';
  /** 没有进度时也显示提示（新版识别模型识别到人脸时常驻淡色提示）。 */
  @Prop cueVisible: boolean = false;

  private hasLeft(): boolean {
    return !!this.leftText || this.leftBattery >= 0;
  }

  private showsCue(): boolean {
    return this.cueVisible || this.cueArmed || this.cueProgress > 0;
  }

  private hasCenter(): boolean {
    return this.showsCue() || !!this.centerText || this.centerBattery >= 0;
  }

  @Builder
  centerCueView() {
    Row() {
      ReaderEyeTurnFillHint({
        text: this.cueText,
        progress: this.cueProgress,
        armed: this.cueArmed,
        textSize: this.textSize,
        baseColor: this.textColor,
        baseOpacity: this.textOpacity,
        fillColor: this.cueColor
      })
    }
    .constraintSize({ maxWidth: '50%' })
    .margin({ left: 12, right: 12 })
    .transition(READER_INFO_HINT_EFFECT)
  }

  private hasRight(): boolean {
    return !!this.rightText || this.rightBattery >= 0;
  }

  build() {
    Row() {
      if (this.hasLeft()) {
        ReaderInfoBarSlot({
          text: this.leftText,
          battery: this.leftBattery,
          textSize: this.textSize,
          textColor: this.textColor,
          justify: FlexAlign.Start,
          slotWeight: 1,
          slotOpacity: this.textOpacity
        })
      } else {
        Blank()
          .layoutWeight(1)
      }

      if (this.hasCenter()) {
        if (this.showsCue()) {
          this.centerCueView()
        } else {
          ReaderInfoBarSlot({
            text: this.centerText,
            battery: this.centerBattery,
            textSize: this.textSize,
            textColor: this.textColor,
            justify: FlexAlign.Center,
            slotMaxWidth: '50%',
            slotMarginLeft: 12,
            slotMarginRight: 12,
            slotOpacity: this.textOpacity,
            fades: true
          })
        }

        if (this.hasRight()) {
          ReaderInfoBarSlot({
            text: this.rightText,
            battery: this.rightBattery,
            textSize: this.textSize,
            textColor: this.textColor,
            justify: FlexAlign.End,
            slotWeight: 1,
            slotOpacity: this.textOpacity
          })
        } else {
          Blank()
            .layoutWeight(1)
        }
      } else if (this.hasRight()) {
        ReaderInfoBarSlot({
          text: this.rightText,
          battery: this.rightBattery,
          textSize: this.textSize,
          textColor: this.textColor,
          justify: FlexAlign.End,
          slotMaxWidth: this.hasLeft() ? '60%' : '100%',
          slotMarginLeft: 12,
          slotOpacity: this.textOpacity
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
