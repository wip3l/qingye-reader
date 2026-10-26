import { AppSpacing } from '../../theme/AppSpacing';
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

  private hasLeft(): boolean {
    return !!this.leftText || this.leftBattery >= 0;
  }

  private hasCenter(): boolean {
    return !!this.centerText || this.centerBattery >= 0;
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
          slotWeight: 1
        })
      } else {
        Blank()
          .layoutWeight(1)
      }

      if (this.hasCenter()) {
        ReaderInfoBarSlot({
          text: this.centerText,
          battery: this.centerBattery,
          textSize: this.textSize,
          textColor: this.textColor,
          justify: FlexAlign.Center,
          slotMaxWidth: '50%',
          slotMarginLeft: 12,
          slotMarginRight: 12
        })

        if (this.hasRight()) {
          ReaderInfoBarSlot({
            text: this.rightText,
            battery: this.rightBattery,
            textSize: this.textSize,
            textColor: this.textColor,
            justify: FlexAlign.End,
            slotWeight: 1
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
          slotMarginLeft: 12
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .opacity(this.textOpacity)
  }
}
