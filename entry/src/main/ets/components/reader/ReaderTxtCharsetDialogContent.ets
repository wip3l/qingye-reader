import { ReaderTxtCharsetOption } from '../../core/reader/ReaderSettingsModels';
import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { DialogStyle } from '../../theme/DialogStyle';

/** 本地 TXT 可手动指定的字符编码。 */
export class ReaderTxtCharsets {
  static options(): ReaderTxtCharsetOption[] {
    return [
      new ReaderTxtCharsetOption('', '自动识别', '根据文件内容自动判断编码'),
      new ReaderTxtCharsetOption('gb18030', 'GBK / GB18030', '简体中文'),
      new ReaderTxtCharsetOption('utf-8', 'UTF-8', 'Unicode，支持带 BOM 文件'),
      new ReaderTxtCharsetOption('utf-16le', 'UTF-16 LE', 'Unicode 小端序'),
      new ReaderTxtCharsetOption('utf-16be', 'UTF-16 BE', 'Unicode 大端序'),
      new ReaderTxtCharsetOption('big5', 'Big5', '繁体中文'),
      new ReaderTxtCharsetOption('koi8-r', 'KOI8-R', '俄语'),
      new ReaderTxtCharsetOption('euc-kr', 'EUC-KR', '韩语'),
      new ReaderTxtCharsetOption('euc-jp', 'EUC-JP', '日语'),
      new ReaderTxtCharsetOption('shift_jis', 'Shift-JIS', '日语'),
      new ReaderTxtCharsetOption('windows-1250', 'Windows-1250', '中欧语言'),
      new ReaderTxtCharsetOption('ibm866', 'IBM866', '西里尔字符')
    ];
  }

  /** 编码的展示名；不在列表里的编码原样大写显示，空值表示自动识别。 */
  static label(charset: string): string {
    const normalized = (charset || '').toLowerCase().replace(/_/g, '-');
    for (const option of ReaderTxtCharsets.options()) {
      if (option.value.replace(/_/g, '-') === normalized) return option.label;
    }
    return charset ? charset.toUpperCase() : '自动识别';
  }
}

/**
 * "选择字符编码"对话框的内容（配合系统自定义对话框使用）。选中项和"正在重新解析"是组件自己的状态；
 * 真正的重新解析由页面完成，组件只负责在它进行期间锁住操作。
 * 对话框表面是系统材质，颜色跟随应用主题。
 */
@Component
export struct ReaderTxtCharsetDialogContent {
  /** 当前手动指定的编码，空串表示自动识别。 */
  selectedCharset: string = '';
  /** 文件当前实际按哪种编码解析。 */
  parsedCharset: string = '';
  listHeight: number = 440;
  /** 用选中的编码重新解析；返回后对话框解除锁定。关闭对话框由页面决定。 */
  onApply: (charset: string) => Promise<void> = (_charset: string): Promise<void> => Promise.resolve();
  onClose: () => void = (): void => {
  };
  /** 重新解析进行中时页面不能关闭对话框。 */
  onApplyingChanged: (applying: boolean) => void = (_applying: boolean): void => {
  };

  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @State private draft: string = '';
  @State private applying: boolean = false;

  aboutToAppear(): void {
    this.draft = this.selectedCharset;
  }

  private textColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  private subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  private async apply(): Promise<void> {
    if (this.applying) return;
    this.applying = true;
    this.onApplyingChanged(true);
    try {
      await this.onApply(this.draft);
    } finally {
      this.applying = false;
      this.onApplyingChanged(false);
    }
  }

  build() {
    Column({ space: AppSpacing.MD }) {
      Row() {
        Column({ space: AppSpacing.XXS }) {
          Text('选择字符编码')
            .fontSize(AppFontSize.TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textColor())
          Text(`当前解析：${ReaderTxtCharsets.label(this.parsedCharset)}`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        ImmersiveBackButton({
          icon: $r('sys.symbol.xmark'),
          iconOffsetX: 0,
          iconColor: this.textColor(),
          darkMode: this.appDarkMode,
          buttonSize: 38,
          containerWidth: 38,
          containerHeight: 38,
          startInset: 0,
          compactLayout: true,
          accessibilityLabel: '关闭字符编码选择',
          onBack: () => {
            if (!this.applying) this.onClose();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: AppSpacing.XS }) {
          ForEach(ReaderTxtCharsets.options(), (option: ReaderTxtCharsetOption) => {
            this.optionRow(option)
          }, (option: ReaderTxtCharsetOption) => option.value || 'auto')
        }
        .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height(this.listHeight)
      .scrollBar(BarState.Auto)

      Row({ space: AppSpacing.LG }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontColor(this.textColor())
          .backgroundColor(DialogStyle.fill('cancel', this.appDarkMode))
          .enabled(!this.applying)
          .onClick(() => this.onClose())
        Button(this.applying ? '正在重新解析…' : '应用')
          .layoutWeight(1)
          .height(42)
          .fontColor(DialogStyle.text('primary', this.appDarkMode))
          .backgroundColor(DialogStyle.fill('primary', this.appDarkMode))
          .enabled(!this.applying)
          .onClick(() => this.apply())
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxWidth: 440 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XL, bottom: AppSpacing.XL })
  }

  @Builder
  optionRow(option: ReaderTxtCharsetOption) {
    Row({ space: AppSpacing.LG }) {
      Column({ space: AppSpacing.XXS }) {
        Text(option.label)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor())
        Text(option.description)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.draft === option.value) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(22)
          .fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(this.draft === option.value ?
      ThemeRuntime.accentSurfaceColor(this.appDarkMode) : Color.Transparent)
    .enabled(!this.applying)
    .onClick(() => {
      this.draft = option.value;
    })
  }
}
