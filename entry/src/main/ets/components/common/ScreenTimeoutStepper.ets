import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { AppFontSize } from '../../theme/AppFontSize';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { ReaderSettingsStore } from '../../utils/ReaderSettingsStore';

/**
 * 亮屏时间步进器：0～60 分钟，0 表示常亮。
 * 收发的是存储值（常亮为 SCREEN_TIMEOUT_ALWAYS_ON），与步进数值的换算在 ReaderSettingsStore 里。
 * 点中间的数值可以直接输入分钟数。
 */
@Component
export struct ScreenTimeoutStepper {
  @Prop minutes: number = ReaderSettingsStore.SCREEN_TIMEOUT_ALWAYS_ON;
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#80868B';
  @Prop inputColor: string = '#FFFFFF';
  @Prop darkMode: boolean = false;
  @Prop controlId: string = '';
  onChange: (minutes: number) => void = (_minutes: number): void => {
  };

  @State private inputVisible: boolean = false;
  @State private inputDraft: string = '';

  private stepValue(): number {
    return ReaderSettingsStore.screenTimeoutStepperValue(this.minutes);
  }

  private label(): string {
    const value = this.stepValue();
    return value <= 0 ? '常亮' : `${value}分钟`;
  }

  private apply(stepValue: number): void {
    const next = ReaderSettingsStore.screenTimeoutFromStepperValue(stepValue);
    if (next !== ReaderSettingsStore.normalizeScreenTimeoutMinutes(this.minutes)) this.onChange(next);
  }

  private applyInput(): void {
    if (!this.inputVisible) return;
    const value = Number(this.inputDraft);
    if (this.inputDraft.trim() && Number.isFinite(value)) this.apply(value);
    this.inputVisible = false;
  }

  private step(delta: number): void {
    this.applyInput();
    this.apply(this.stepValue() + delta);
  }

  build() {
    Row({ space: 4 }) {
      // 直接写在 build 里：按值传参的 @Builder 只在首次建出时取 enabled，常亮（0）时建出的减号会一直不可点。
      ImmersiveBackButton({
        icon: $r('sys.symbol.minus'),
        accessibilityLabel: '缩短亮屏时间',
        iconColor: this.textColor,
        disabledIconColor: this.subTextColor,
        darkMode: this.darkMode,
        buttonEnabled: this.stepValue() > 0,
        buttonSize: 34,
        containerWidth: 34,
        containerHeight: 34,
        startInset: 0,
        compactLayout: true,
        onBack: (): void => this.step(-1)
      })
      if (this.inputVisible) {
        TextInput({ text: this.inputDraft, placeholder: `${this.stepValue()}` })
          .type(InputType.Number)
          .enterKeyType(EnterKeyType.Done)
          .defaultFocus(true)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.textColor)
          .width(64)
          .height(34)
          .padding(0)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.inputColor)
          .borderRadius(ThemeRuntime.mediumRadius())
          .onChange((value: string) => {
            this.inputDraft = value.replace(/[^0-9]/g, '').substring(0, 2);
          })
          .onSubmit(() => this.applyInput())
          .onBlur(() => this.applyInput())
      } else {
        Text(this.label())
          .id(this.controlId)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.textColor)
          .width(64)
          .height(34)
          .textAlign(TextAlign.Center)
          .accessibilityText(`亮屏时间 ${this.label()}，点按输入分钟数`)
          .onClick(() => {
            this.inputDraft = '';
            this.inputVisible = true;
          })
      }
      ImmersiveBackButton({
        icon: $r('sys.symbol.plus'),
        accessibilityLabel: '延长亮屏时间',
        iconColor: this.textColor,
        disabledIconColor: this.subTextColor,
        darkMode: this.darkMode,
        buttonEnabled: this.stepValue() < ReaderSettingsStore.SCREEN_TIMEOUT_MAX_MINUTES,
        buttonSize: 34,
        containerWidth: 34,
        containerHeight: 34,
        startInset: 0,
        compactLayout: true,
        onBack: (): void => this.step(1)
      })
    }
    .alignItems(VerticalAlign.Center)
  }
}
