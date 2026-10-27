import { AdaptiveIconButton } from '../AdaptiveIconButton';
import { ReaderFontWeight } from '../../core/reader/ReaderFontWeight';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/** Prop updates must reach both the value label and the next click's starting weight. */
@Component
export struct ReaderFontWeightStepper {
  @Prop value: number = 400;
  @Prop scope: string = '正文';
  @Prop nested: boolean = false;
  @Prop textColor: string = '#202124';
  @Prop disabledColor: string = '#999999';
  @Prop dividerColor: string = '#22000000';
  @State private inputVisible: boolean = false;
  @State private inputDraft: string = '';
  private focusTimer: number = -1;
  onChange: (value: number) => void = (_value: number): void => {};

  private apply(value: number): void {
    const next = ReaderFontWeight.normalize(value);
    if (next === this.value) return;
    this.value = next;
    this.onChange(next);
  }

  private applyInput(): void {
    if (!this.inputVisible) return;
    this.inputVisible = false;
    if (/^\d+$/.test(this.inputDraft)) this.apply(Number(this.inputDraft));
  }

  private focusInput(): void {
    this.clearFocusTimer();
    // The conditional TextInput must be mounted before requesting focus.
    this.focusTimer = setTimeout(() => {
      this.focusTimer = -1;
      if (this.inputVisible) {
        this.getUIContext().getFocusController().requestFocus(`reader_font_weight_input_${this.scope}`);
      }
    }, 30);
  }

  private clearFocusTimer(): void {
    if (this.focusTimer >= 0) clearTimeout(this.focusTimer);
    this.focusTimer = -1;
  }

  aboutToDisappear(): void { this.clearFocusTimer(); }

  private step(delta: number): void {
    this.applyInput();
    this.apply(this.value + delta);
  }

  build() {
    Row({ space: AppSpacing.MD }) {
      Text('字体粗细')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.textColor)
        .layoutWeight(1)
      AdaptiveIconButton({ icon: $r('sys.symbol.minus'), accessibilityLabel: `减小${this.scope}字体粗细`,
        buttonEnabled: this.value > ReaderFontWeight.MIN, buttonSize: 34, iconSize: 17,
        iconColor: this.textColor, disabledIconColor: this.disabledColor,
        action: () => this.step(-ReaderFontWeight.STEP) })
      if (this.inputVisible) {
        TextInput({ text: this.inputDraft, placeholder: `${this.value}` })
          .id(`reader_font_weight_input_${this.scope}`)
          .type(InputType.Number)
          .enterKeyType(EnterKeyType.Done)
          .defaultFocus(true)
          .maxLength(3)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
          .width(52)
          .height(36)
          .padding(0)
          .textAlign(TextAlign.Center)
          .backgroundColor(Color.Transparent)
          .accessibilityText(`${this.scope}字体粗细，50 到 900`)
          .onAppear(() => this.focusInput())
          .onDisAppear(() => this.clearFocusTimer())
          .onChange((value: string) => { this.inputDraft = value; })
          .onSubmit(() => this.applyInput())
          .onBlur(() => this.applyInput())
      } else {
        Text(`${this.value}`)
          .id(`reader_font_weight_${this.scope}`)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
          .width(52)
          .height(36)
          .textAlign(TextAlign.Center)
          .accessibilityText(`${this.scope}字体粗细 ${this.value}，点击输入`)
          .onClick(() => {
            this.inputDraft = '';
            this.inputVisible = true;
          })
      }
      AdaptiveIconButton({ icon: $r('sys.symbol.plus'), accessibilityLabel: `增大${this.scope}字体粗细`,
        buttonEnabled: this.value < ReaderFontWeight.MAX, buttonSize: 34, iconSize: 17,
        iconColor: this.textColor, disabledIconColor: this.disabledColor,
        action: () => this.step(ReaderFontWeight.STEP) })
    }
    .width(this.nested ? '100%' : 'calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ top: AppSpacing.MD, bottom: AppSpacing.MD })
    .margin({ left: this.nested ? 0 : AppSpacing.XL, right: this.nested ? 0 : AppSpacing.XL })
    .border({ width: { bottom: 0.5 }, color: this.dividerColor })
  }
}
