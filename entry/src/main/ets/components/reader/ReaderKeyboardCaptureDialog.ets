import { KeyCode } from '@kit.InputKit';
import { ReaderKeyboard } from '../../core/reader/ReaderKeyboard';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

@Component
export struct ReaderKeyboardCaptureDialog {
  actionLabel: string = '';
  otherCode: number = -1;
  onSave: (code: number) => Promise<void> = (_code: number): Promise<void> => Promise.resolve();
  onClose: () => void = (): void => {};
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @State private candidate: number = -1;
  @State private released: boolean = false;
  @State private message: string = '请按下外接键盘或翻页器上的按键';
  @State private saving: boolean = false;
  private held: ReaderKeyboard = new ReaderKeyboard();

  private handleKey(event: KeyEvent): boolean {
    if (event.type === KeyType.Up) {
      this.held.release(event.keyCode, event.deviceId);
      if (event.keyCode === this.candidate && !this.released) {
        this.released = true;
        return true;
      }
      return !this.released;
    }
    if (event.type !== KeyType.Down) return false;
    const first = this.held.press(event.keyCode, event.deviceId);
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      if (first && !this.saving) this.onClose();
      return true;
    }
    // After release, Tab/Enter/Space can operate the confirmation buttons normally.
    if (this.released) return false;
    if (!first || this.saving || this.candidate >= 0) return true;
    if (event.keyCode === KeyCode.KEYCODE_TAB) return false;
    if (ReaderKeyboard.hasModifiers(event)) {
      this.message = '暂不支持组合键，请松开修饰键后重试';
      return true;
    }
    if (!ReaderKeyboard.isBindable(event.keyCode)) {
      this.message = '此按键不可映射，请使用翻页键、方向键、字母或空格等单键';
      return true;
    }
    if (event.keyCode === this.otherCode) {
      this.message = '此按键已用于另一个翻页方向，请换一个按键';
      return true;
    }
    this.candidate = event.keyCode;
    this.message = '松开按键后点击保存';
    return true;
  }

  private retry(): void {
    this.candidate = -1;
    this.released = false;
    this.message = '请按下外接键盘或翻页器上的按键';
    try {
      this.getUIContext().getFocusController().requestFocus('reader_keyboard_capture');
    } catch (error) {
      this.message = '请点击弹窗后重新按键';
    }
  }

  private async save(): Promise<void> {
    if (this.saving || !this.released || this.candidate < 0) return;
    this.saving = true;
    try {
      await this.onSave(this.candidate);
      this.onClose();
    } catch (error) {
      this.message = '保存失败，请重试';
    } finally {
      this.saving = false;
    }
  }

  build() {
    Column({ space: AppSpacing.LG }) {
      Text(`映射${this.actionLabel}按键`)
        .fontSize(AppFontSize.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
      Text(this.candidate >= 0 ? ReaderKeyboard.label(this.candidate) : '等待按键…')
        .fontSize(AppFontSize.TITLE)
        .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
      Text(this.message)
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .textAlign(TextAlign.Center)
      if (this.released) {
        Button('重新录入')
          .enabled(!this.saving)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .backgroundColor(ThemeRuntime.hairlineColor(this.appDarkMode))
          .onClick((): void => this.retry())
      }
      Row({ space: AppSpacing.LG }) {
        Button('取消')
          .layoutWeight(1)
          .enabled(!this.saving)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .backgroundColor(ThemeRuntime.hairlineColor(this.appDarkMode))
          .onClick((): void => this.onClose())
        Button(this.saving ? '保存中…' : '保存')
          .layoutWeight(1)
          .enabled(this.released && !this.saving)
          .fontColor(ThemeRuntime.onAccentColor())
          .backgroundColor(ThemeRuntime.buttonColor(this.appDarkMode))
          .onClick((): void => { this.save(); })
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxWidth: 440 })
    .padding(AppSpacing.XL)
    .id('reader_keyboard_capture')
    .focusable(true)
    .defaultFocus(true)
    .onKeyPreIme((event: KeyEvent): boolean => this.handleKey(event))
  }
}
