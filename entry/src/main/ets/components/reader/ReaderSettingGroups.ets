import { LengthMetrics } from '@kit.ArkUI';
import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/**
 * 阅读页设置面板的分组与紧凑控件：面板内页签条、分组卡片、分段选择、标签选择、步进器。
 * 选中项、数值都由调用方在自己的 build 里读状态后传入（@Prop），不要经按值 @Builder 转手，否则不刷新。
 */

/** 分段条：面板顶部的页签，或设置行里的三选一。dense 为行内用的矮版本。 */
@Component
export struct ReaderSettingTabStrip {
  @Prop labels: string[] = [];
  @Prop selected: number = 0;
  @Prop dense: boolean = false;
  @Prop dark: boolean = false;
  @Prop textColor: string = '#000000';
  @Prop subTextColor: string = '#666666';
  onSelect: (index: number) => void = () => {};

  build() {
    Row() {
      ForEach(this.labels, (label: string, index: number) => {
        Text(label)
          .fontSize(this.dense ? AppFontSize.BODY : AppFontSize.BODY_LARGE)
          .fontWeight(this.selected === index ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.selected === index ? this.textColor : this.subTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .height(this.dense ? 30 : 34)
          .borderRadius(this.dense ? 9 : 11)
          .backgroundColor(this.selected === index ? (this.dark ? '#38FFFFFF' : '#FFFFFFFF') : Color.Transparent)
          .accessibilityText(label)
          .accessibilitySelected(this.selected === index)
          .onClick(() => {
            if (this.selected !== index) this.onSelect(index);
          })
      }, (label: string, index: number) => `${index}_${label}`)
    }
    .width('100%')
    .padding(3)
    .borderRadius(this.dense ? 12 : 14)
    .backgroundColor(this.dark ? '#1AFFFFFF' : '#12000000')
  }
}

/** 一组相关设置：可选的小标题加一张浅底卡片。 */
@Component
export struct ReaderSettingGroup {
  @Prop title: string = '';
  @Prop dark: boolean = false;
  @Prop subTextColor: string = '#666666';
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    Column({ space: 6 }) {
      if (this.title) {
        Text(this.title)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor)
          .width('100%')
          .padding({ left: AppSpacing.XS })
      }
      Column() {
        this.content()
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 2, bottom: 2 })
      .borderRadius(18)
      .backgroundColor(this.dark ? '#12FFFFFF' : '#0A000000')
    }
    .width('100%')
  }
}

/** 标题在上、分段条在下的设置行，用于选项不超过三四个的单选。 */
@Component
export struct ReaderSettingSegmentRow {
  @Prop title: string = '';
  @Prop labels: string[] = [];
  @Prop selected: number = 0;
  @Prop dark: boolean = false;
  @Prop textColor: string = '#000000';
  @Prop subTextColor: string = '#666666';
  onSelect: (index: number) => void = () => {};

  build() {
    Column({ space: AppSpacing.SM }) {
      if (this.title) {
        Text(this.title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
          .width('100%')
      }
      ReaderSettingTabStrip({
        labels: this.labels,
        selected: this.selected,
        dense: true,
        dark: this.dark,
        textColor: this.textColor,
        subTextColor: this.subTextColor,
        onSelect: (index: number): void => this.onSelect(index)
      })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }
}

/** 标题在上、一排可换行标签在下的设置行，用于选项较多的单选。 */
@Component
export struct ReaderSettingChipRow {
  @Prop title: string = '';
  @Prop labels: string[] = [];
  @Prop selected: number = 0;
  @Prop dark: boolean = false;
  @Prop textColor: string = '#000000';
  @Prop subTextColor: string = '#666666';
  @Prop accentColor: string = '#0A59F7';
  onSelect: (index: number) => void = () => {};

  build() {
    Column({ space: AppSpacing.SM }) {
      Text(this.title)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.textColor)
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ForEach(this.labels, (label: string, index: number) => {
          Text(label)
            .fontSize(AppFontSize.BODY)
            .fontWeight(this.selected === index ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.selected === index ? ThemeRuntime.onAccentColor() : this.subTextColor)
            .height(32)
            .padding({ left: 14, right: 14 })
            .borderRadius(16)
            .backgroundColor(this.selected === index ? this.accentColor : (this.dark ? '#1AFFFFFF' : '#12000000'))
            .accessibilityText(label)
            .accessibilitySelected(this.selected === index)
            .onClick(() => {
              if (this.selected !== index) this.onSelect(index);
            })
        }, (label: string, index: number) => `${index}_${label}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }
}

/** 加减步进器，点中间的数值可以直接输入。fill 为 true 时占满宽度、加减按钮分居两端。 */
@Component
export struct ReaderSettingStepper {
  @Prop value: number = 0;
  @Prop minValue: number = 0;
  @Prop maxValue: number = 100;
  @Prop stepValue: number = 1;
  @Prop suffix: string = '';
  @Prop title: string = '';
  @Prop large: boolean = false;
  @Prop fill: boolean = false;
  @Prop dark: boolean = false;
  @Prop textColor: string = '#000000';
  @Prop subTextColor: string = '#666666';
  @Prop inputColor: string = '#FFFFFF';
  onChange: (value: number) => void = () => {};

  @State private inputVisible: boolean = false;
  @State private inputDraft: string = '';

  private apply(value: number): void {
    const next = Math.max(this.minValue, Math.min(this.maxValue, Math.round(value)));
    if (next !== this.value) this.onChange(next);
  }

  private applyInput(): void {
    if (!this.inputVisible) return;
    const value = Number(this.inputDraft);
    if (this.inputDraft.trim() && Number.isFinite(value)) this.apply(value);
    this.inputVisible = false;
  }

  build() {
    Row({ space: this.fill ? 0 : AppSpacing.XS }) {
      ImmersiveBackButton({
        icon: $r('sys.symbol.minus'),
        accessibilityLabel: `减小${this.title}`,
        iconColor: this.dark ? '#FFFFFFFF' : '#FF202124',
        disabledIconColor: this.subTextColor,
        darkMode: this.dark,
        buttonEnabled: this.value > this.minValue,
        buttonSize: this.large ? 40 : 34,
        containerWidth: this.large ? 40 : 34,
        containerHeight: this.large ? 40 : 34,
        startInset: 0,
        compactLayout: true,
        onBack: (): void => this.apply(this.value - this.stepValue)
      })
      if (this.inputVisible) {
        TextInput({ text: this.inputDraft, placeholder: `${this.value}` })
          .type(InputType.Number)
          .enterKeyType(EnterKeyType.Done)
          .defaultFocus(true)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
          .width(this.large ? 64 : 52)
          .height(36)
          .padding(0)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.inputColor)
          .borderRadius(ThemeRuntime.mediumRadius())
          .onChange((value: string) => {
            this.inputDraft = value.replace(/[^0-9]/g, '').substring(0, 3);
          })
          .onSubmit(() => this.applyInput())
          .onBlur(() => this.applyInput())
      } else {
        Text(`${Math.round(this.value)}${this.suffix}`)
          .fontSize(this.large ? 22 : AppFontSize.BODY_LARGE)
          .fontWeight(this.large ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.textColor)
          .width(this.large ? 64 : 52)
          .height(36)
          .textAlign(TextAlign.Center)
          .accessibilityText(`${this.title} ${Math.round(this.value)}${this.suffix}，点按输入数值`)
          .onClick(() => {
            this.inputDraft = '';
            this.inputVisible = true;
          })
      }
      ImmersiveBackButton({
        icon: $r('sys.symbol.plus'),
        accessibilityLabel: `增大${this.title}`,
        iconColor: this.dark ? '#FFFFFFFF' : '#FF202124',
        disabledIconColor: this.subTextColor,
        darkMode: this.dark,
        buttonEnabled: this.value < this.maxValue,
        buttonSize: this.large ? 40 : 34,
        containerWidth: this.large ? 40 : 34,
        containerHeight: this.large ? 40 : 34,
        startInset: 0,
        compactLayout: true,
        onBack: (): void => this.apply(this.value + this.stepValue)
      })
    }
    .constraintSize({ minWidth: this.fill ? '100%' : 0 })
    .justifyContent(this.fill ? FlexAlign.SpaceBetween : FlexAlign.End)
    .alignItems(VerticalAlign.Center)
  }
}

/** 带标题的步进器。cell 为 true 时标题在上（两列并排用），否则标题与说明在左、步进器在右。 */
@Component
export struct ReaderSettingStepperItem {
  @Prop title: string = '';
  @Prop description: string = '';
  @Prop cell: boolean = false;
  @Prop value: number = 0;
  @Prop minValue: number = 0;
  @Prop maxValue: number = 100;
  @Prop stepValue: number = 1;
  @Prop suffix: string = '';
  @Prop large: boolean = false;
  @Prop dark: boolean = false;
  @Prop textColor: string = '#000000';
  @Prop subTextColor: string = '#666666';
  @Prop inputColor: string = '#FFFFFF';
  onChange: (value: number) => void = () => {};

  @Builder
  stepper(fill: boolean) {
    ReaderSettingStepper({
      value: this.value,
      minValue: this.minValue,
      maxValue: this.maxValue,
      stepValue: this.stepValue,
      suffix: this.suffix,
      title: this.title,
      large: this.large,
      fill: fill,
      dark: this.dark,
      textColor: this.textColor,
      subTextColor: this.subTextColor,
      inputColor: this.inputColor,
      onChange: (value: number): void => this.onChange(value)
    })
  }

  build() {
    Column() {
      if (this.cell) {
        Text(this.title)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor)
          .width('100%')
          .margin({ bottom: AppSpacing.XS })
        this.stepper(true)
      } else {
        Row() {
          Column() {
            Text(this.title)
              .fontSize(AppFontSize.BODY_LARGE)
              .fontColor(this.textColor)
            if (this.description) {
              Text(this.description)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor)
                .margin({ top: AppSpacing.XS })
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ right: AppSpacing.MD })

          this.stepper(false)
        }
        .width('100%')
        .constraintSize({ minHeight: 56 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding({ top: this.cell ? 8 : 0, bottom: this.cell ? 8 : 0 })
  }
}
