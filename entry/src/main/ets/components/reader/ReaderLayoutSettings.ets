import { ReaderCommentBubbleSize } from '../../core/reader/ReaderCommentBubbleSize';
import { ReaderFontWeight } from '../../core/reader/ReaderFontWeight';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AdaptiveSwitch } from '../AdaptiveSwitch';
import { AdaptiveColorPicker } from '../AdaptiveColorPicker';
import { ReaderInfoBarConfig, ReaderInfoItem, ReaderInfoProgressBar } from '../../core/reader/ReaderInfoBarModel';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ReaderSettingGroup, ReaderSettingStepperItem, ReaderSettingTabStrip } from './ReaderSettingGroups';

interface ReaderHeaderFooterSwitchOptions {
  title: string;
  description: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}

/** 排版参数在草稿数组里的下标。 */
export class ReaderTypographyField {
  static readonly FONT_SIZE: number = 0;
  static readonly FONT_WEIGHT: number = 1;
  static readonly LETTER_SPACING: number = 2;
  static readonly LINE_HEIGHT: number = 3;
  static readonly PARAGRAPH_SPACING: number = 4;
  static readonly MARGIN_LEFT: number = 5;
  static readonly MARGIN_RIGHT: number = 6;
  static readonly MARGIN_TOP: number = 7;
  static readonly MARGIN_BOTTOM: number = 8;
  static readonly COMMENT_BUBBLE_SIZE: number = 9;
  static readonly COUNT: number = 10;

  static readonly LABELS: string[] = ['字号', '字体粗细', '字距', '行距', '段落间距', '左边距', '右边距', '上边距', '下边距', '气泡大小'];

  static min(field: number): number {
    if (field === ReaderTypographyField.COMMENT_BUBBLE_SIZE) return ReaderCommentBubbleSize.MIN;
    if (field === ReaderTypographyField.FONT_WEIGHT) return ReaderFontWeight.MIN;
    return field === ReaderTypographyField.FONT_SIZE ? 14 : 0;
  }

  static max(field: number): number {
    if (field === ReaderTypographyField.COMMENT_BUBBLE_SIZE) return ReaderCommentBubbleSize.MAX;
    if (field === ReaderTypographyField.FONT_WEIGHT) return ReaderFontWeight.MAX;
    if (field === ReaderTypographyField.FONT_SIZE) return 50;
    if (field === ReaderTypographyField.LETTER_SPACING) return 8;
    if (field === ReaderTypographyField.LINE_HEIGHT) return 52;
    if (field === ReaderTypographyField.PARAGRAPH_SPACING) return 32;
    if (field === ReaderTypographyField.MARGIN_LEFT || field === ReaderTypographyField.MARGIN_RIGHT) return 80;
    return 120;
  }

  static step(field: number): number {
    return field === ReaderTypographyField.FONT_WEIGHT ? ReaderFontWeight.STEP : 1;
  }

  static clamp(field: number, value: number): number {
    if (field === ReaderTypographyField.FONT_WEIGHT) return ReaderFontWeight.normalize(value);
    return Math.max(ReaderTypographyField.min(field), Math.min(Math.round(value), ReaderTypographyField.max(field)));
  }
}

/**
 * 正文排版的统一调节控件：下拉选一个参数（字号、字体粗细、字距、行距、段距、四侧边距、气泡大小），用加减按钮或直接输入数值。
 * 数值草稿是组件自己的状态，连点加减只刷新这个控件；每次变化把整组草稿交给页面，
 * 页面稍后一次性提交并重排正文。
 */
@Component
export struct ReaderTypographyStepper {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  /** 打开时的初始值，顺序见 ReaderTypographyField。 */
  initialValues: number[] = [];
  @Prop dark: boolean = false;
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#80868B';
  @Prop accentColor: string = '#0A59F7';
  @Prop inputColor: string = '#FFFFFF';
  @Prop menuColor: string = '#FFFFFF';
  /** 只列出这些参数（ReaderTypographyField 下标）；空数组列出全部。文件排版只调四侧边距。 */
  fields: number[] = [];
  onChange: (values: number[]) => void = (_values: number[]): void => {
  };

  @State private field: number = 0;
  @State private values: number[] = [];
  @State private inputVisible: boolean = false;
  @State private inputDraft: string = '';

  aboutToAppear(): void {
    const values: number[] = [];
    for (let field = 0; field < ReaderTypographyField.COUNT; field++) {
      const fallback = field === ReaderTypographyField.FONT_WEIGHT ? ReaderFontWeight.DEFAULT :
        (field === ReaderTypographyField.COMMENT_BUBBLE_SIZE ? ReaderCommentBubbleSize.DEFAULT : ReaderTypographyField.min(field));
      values.push(ReaderTypographyField.clamp(field,
        field < this.initialValues.length ? this.initialValues[field] : fallback));
    }
    this.values = values;
    if (this.fields.length > 0) this.field = this.fields[0];
  }

  private visibleFields(): number[] {
    if (this.fields.length > 0) return this.fields;
    const all: number[] = [];
    for (let field = 0; field < ReaderTypographyField.COUNT; field++) all.push(field);
    return all;
  }

  private current(): number {
    return this.field < this.values.length ? this.values[this.field] : 0;
  }

  private apply(value: number): void {
    const next = [...this.values];
    next[this.field] = ReaderTypographyField.clamp(this.field, value);
    this.values = next;
    this.onChange([...next]);
  }

  private applyInput(): void {
    if (!this.inputVisible) return;
    const value = Number(this.inputDraft);
    if (this.inputDraft.trim() && Number.isFinite(value)) this.apply(value);
    this.inputVisible = false;
  }

  build() {
    Column() {
      Row({ space: AppSpacing.MD }) {
        Select(this.visibleFields().map((field: number): SelectOption => ({ value: ReaderTypographyField.LABELS[field] })))
          .id('reader_typography_selector')
          .selected(Math.max(0, this.visibleFields().indexOf(this.field)))
          .value(ReaderTypographyField.LABELS[this.field])
          .font({ size: AppFontSize.BODY_LARGE, family: this.applicationFontFamily })
          .optionFont({ family: this.applicationFontFamily })
          .selectedOptionFont({ family: this.applicationFontFamily })
          .fontColor(this.subTextColor)
          .backgroundColor(Color.Transparent)
          .arrowPosition(ArrowPosition.START)
          .padding({ left: 0, right: 0 })
          .borderRadius(16)
          .border({ width: 0 })
          .optionBgColor(Color.Transparent)
          .divider(null)
          .optionFontColor(this.textColor)
          .selectedOptionFontColor(this.accentColor)
          .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.dark))
          .menuBackgroundColor(this.menuColor)
          .menuBackgroundBlurStyle(BlurStyle.NONE)
          .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel, this.dark, this.menuColor))
          .onSelect((index: number) => {
            this.inputVisible = false;
            const visible = this.visibleFields();
            this.field = visible[Math.max(0, Math.min(index, visible.length - 1))];
          })
        Blank()
          .layoutWeight(1)
        this.stepButton($r('sys.symbol.minus'), '减小当前排版参数',
          this.current() > ReaderTypographyField.min(this.field), () => this.apply(this.current() - ReaderTypographyField.step(this.field)))
        if (this.inputVisible) {
          TextInput({ text: this.inputDraft, placeholder: `${this.current()}` })
            .type(InputType.Number)
            .enterKeyType(EnterKeyType.Done)
            .defaultFocus(true)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.textColor)
            .width(52)
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
          Text(`${Math.round(this.current())}`)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.textColor)
            .width(52)
            .height(36)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.inputDraft = '';
              this.inputVisible = true;
            })
        }
        this.stepButton($r('sys.symbol.plus'), '增大当前排版参数',
          this.current() < ReaderTypographyField.max(this.field), () => this.apply(this.current() + ReaderTypographyField.step(this.field)))
      }
      .width('100%')
      // Keep the selector on the same content baseline as the settings below.
      .padding({ left: 0, right: 0, top: AppSpacing.LG, bottom: AppSpacing.LG })
      .alignItems(VerticalAlign.Center)
      if (this.field === ReaderTypographyField.FONT_WEIGHT) {
        Text(ReaderFontWeight.HELP)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor)
          .width('100%')
          .padding({ bottom: AppSpacing.SM })
      }
    }
    .width('100%')
  }

  @Builder
  stepButton(icon: Resource, accessibilityText: string, enabled: boolean, action: () => void) {
    ImmersiveBackButton({
      icon: icon,
      accessibilityLabel: accessibilityText,
      iconColor: this.dark ? '#FFFFFFFF' : '#FF202124',
      disabledIconColor: this.subTextColor,
      darkMode: this.dark,
      buttonEnabled: enabled,
      buttonSize: 34,
      containerWidth: 34,
      containerHeight: 34,
      startInset: 0,
      compactLayout: true,
      onBack: action
    })
  }
}

/**
 * 正文排版的单个参数（字号、字距、边距等）。数值草稿是组件自己的状态，连点加减只刷新这个控件；
 * 每次变化把参数下标与新值交给页面，页面合并进整组草稿后稍后一次性提交并重排正文。
 */
@Component
export struct ReaderTypographyFieldControl {
  /** ReaderTypographyField 下标。 */
  field: number = 0;
  /** 打开时的初始值。 */
  initialValue: number = 0;
  @Prop title: string = '';
  @Prop description: string = '';
  @Prop cell: boolean = false;
  @Prop large: boolean = false;
  @Prop dark: boolean = false;
  @Prop textColor: string = '#000000';
  @Prop subTextColor: string = '#666666';
  @Prop inputColor: string = '#FFFFFF';
  onFieldChange: (field: number, value: number) => void = () => {};

  @State private value: number = 0;

  aboutToAppear(): void {
    this.value = ReaderTypographyField.clamp(this.field, this.initialValue);
  }

  build() {
    ReaderSettingStepperItem({
      title: this.title || ReaderTypographyField.LABELS[this.field],
      description: this.description,
      cell: this.cell,
      value: this.value,
      minValue: ReaderTypographyField.min(this.field),
      maxValue: ReaderTypographyField.max(this.field),
      stepValue: ReaderTypographyField.step(this.field),
      large: this.large,
      dark: this.dark,
      textColor: this.textColor,
      subTextColor: this.subTextColor,
      inputColor: this.inputColor,
      onChange: (value: number): void => {
        const next = ReaderTypographyField.clamp(this.field, value);
        if (next === this.value) return;
        this.value = next;
        this.onFieldChange(this.field, next);
      }
    })
  }
}

/**
 * 页眉页脚设置组：两个总开关、六个内容槽位和外观项，直接绑定全局设置。
 * 操作回调直接提交完整设置；页面监听只负责更新正文，避免依赖跨组件监听的通知时机保存。
 * cardStyle 为 true 时使用设置页的卡片行样式。
 */
@Component
export struct ReaderHeaderFooterSettings {
  // 阅读页传入实时安全区；独立设置页使用窗口共享的安全区。
  @Prop headerBaseInset: number = -1;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp('readerExtendToStatusBar') readerExtendToStatusBar: boolean = false;
  @Prop dark: boolean = false;
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#80868B';
  @Prop accentColor: string = '#0A59F7';
  @Prop switchColor: string = '#0A59F7';
  @Prop menuColor: string = '#FFFFFF';
  @Prop cardStyle: boolean = false;
  /** 阅读页面板用的紧凑布局：示意图上选六个位置的内容，页眉、页脚样式二选一显示。 */
  @Prop compact: boolean = false;
  @Prop dividerColor: string = '#00000000';
  /** 应用当前是否深色模式：页眉页脚颜色按浅色、深色分别编辑。dark 只管面板外观，可能取自背景深浅。 */
  @Prop modeDark: boolean = false;
  onChanged: (headerEnabled: boolean, footerEnabled: boolean, infoBarConfig: string) => void = () => {
  };
  @StorageLink('readerHeaderEnabled') readerHeaderEnabled: boolean = false;
  @StorageLink('readerFooterEnabled') readerFooterEnabled: boolean = true;
  @StorageLink('readerInfoBarConfig') readerInfoBarConfig: string = '';

  build() {
    ReaderHeaderFooterEditor({
      headerBaseInset: this.headerBaseInset >= 0 ? this.headerBaseInset :
        ReaderInfoBarConfig.headerBaseInset(this.readerExtendToStatusBar, this.statusBarHeight),
      footerBaseInset: ReaderInfoBarConfig.footerBaseInset(this.navBarHeight),
      dark: this.dark,
      textColor: this.textColor,
      subTextColor: this.subTextColor,
      accentColor: this.accentColor,
      switchColor: this.switchColor,
      menuColor: this.menuColor,
      cardStyle: this.cardStyle,
      compact: this.compact,
      dividerColor: this.dividerColor,
      modeDark: this.modeDark,
      readerHeaderEnabled: $readerHeaderEnabled,
      readerFooterEnabled: $readerFooterEnabled,
      readerInfoBarConfig: $readerInfoBarConfig,
      onChanged: (headerEnabled: boolean, footerEnabled: boolean, infoBarConfig: string): void =>
        this.onChanged(headerEnabled, footerEnabled, infoBarConfig)
    })
  }
}

/**
 * 页眉页脚设置组本体，三项设置由调用方双向绑定：上面的 ReaderHeaderFooterSettings 绑定全局设置，
 * 主题排版页绑定自己的草稿。
 */
@Component
export struct ReaderHeaderFooterEditor {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @Prop headerBaseInset: number = 0;
  @Prop footerBaseInset: number = 6;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @Prop dark: boolean = false;
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#80868B';
  @Prop accentColor: string = '#0A59F7';
  @Prop switchColor: string = '#0A59F7';
  @Prop menuColor: string = '#FFFFFF';
  @Prop cardStyle: boolean = false;
  @Prop compact: boolean = false;
  @Prop dividerColor: string = '#00000000';
  @Prop modeDark: boolean = false;
  onChanged: (headerEnabled: boolean, footerEnabled: boolean, infoBarConfig: string) => void = () => {
  };
  @Link readerHeaderEnabled: boolean;
  @Link readerFooterEnabled: boolean;
  @Link readerInfoBarConfig: string;
  /** 紧凑布局：样式区当前显示页脚（否则页眉）的样式。 */
  @State private styleFooter: boolean = true;
  /** 紧凑布局：正在选内容的位置，-1 为没有。 */
  @State private slotMenu: number = -1;
  /** 紧凑面板“位置与内缩”一行当前选中的项，页眉页脚共用。 */
  @State private geometryTarget: number = 0;

  private static readonly SLOT_HEADER_LEFT: number = 0;
  private static readonly SLOT_HEADER_CENTER: number = 1;
  private static readonly SLOT_HEADER_RIGHT: number = 2;
  private static readonly SLOT_FOOTER_LEFT: number = 3;
  private static readonly SLOT_FOOTER_CENTER: number = 4;
  private static readonly SLOT_FOOTER_RIGHT: number = 5;
  private static readonly STEPPER_HEADER_FONT_SIZE: number = 0;
  private static readonly STEPPER_HEADER_OPACITY: number = 1;
  private static readonly STEPPER_HEADER_OFFSET: number = 2;
  private static readonly STEPPER_FOOTER_OFFSET: number = 3;
  private static readonly STEPPER_FOOTER_FONT_SIZE: number = 4;
  private static readonly STEPPER_FOOTER_OPACITY: number = 5;
  private static readonly STEPPER_HEADER_INSET_LEFT: number = 6;
  private static readonly STEPPER_HEADER_INSET_RIGHT: number = 7;
  private static readonly STEPPER_FOOTER_INSET_LEFT: number = 8;
  private static readonly STEPPER_FOOTER_INSET_RIGHT: number = 9;
  private static readonly GEOMETRY_LEFT: number = 0;
  private static readonly GEOMETRY_OFFSET: number = 1;
  private static readonly GEOMETRY_RIGHT: number = 2;

  private config(): ReaderInfoBarConfig {
    return ReaderInfoBarConfig.parse(this.readerInfoBarConfig) ?? new ReaderInfoBarConfig();
  }

  private commit(config: ReaderInfoBarConfig): void {
    this.readerInfoBarConfig = config.serialize();
    this.notifyChanged();
  }

  private notifyChanged(): void {
    this.onChanged(this.readerHeaderEnabled, this.readerFooterEnabled, this.readerInfoBarConfig);
  }

  private slotIndex(slot: number): number {
    const config = this.config();
    let item = config.headerLeft;
    if (slot === ReaderHeaderFooterEditor.SLOT_HEADER_CENTER) item = config.headerCenter;
    if (slot === ReaderHeaderFooterEditor.SLOT_HEADER_RIGHT) item = config.headerRight;
    if (slot === ReaderHeaderFooterEditor.SLOT_FOOTER_LEFT) item = config.footerLeft;
    if (slot === ReaderHeaderFooterEditor.SLOT_FOOTER_CENTER) item = config.footerCenter;
    if (slot === ReaderHeaderFooterEditor.SLOT_FOOTER_RIGHT) item = config.footerRight;
    return Math.max(0, ReaderInfoItem.VALUES.indexOf(item));
  }

  private setSlot(slot: number, index: number): void {
    const item = index >= 0 && index < ReaderInfoItem.VALUES.length ? ReaderInfoItem.VALUES[index] : ReaderInfoItem.NONE;
    const config = this.config();
    if (slot === ReaderHeaderFooterEditor.SLOT_HEADER_LEFT) config.headerLeft = item;
    if (slot === ReaderHeaderFooterEditor.SLOT_HEADER_CENTER) config.headerCenter = item;
    if (slot === ReaderHeaderFooterEditor.SLOT_HEADER_RIGHT) config.headerRight = item;
    if (slot === ReaderHeaderFooterEditor.SLOT_FOOTER_LEFT) config.footerLeft = item;
    if (slot === ReaderHeaderFooterEditor.SLOT_FOOTER_CENTER) config.footerCenter = item;
    if (slot === ReaderHeaderFooterEditor.SLOT_FOOTER_RIGHT) config.footerRight = item;
    this.commit(config);
  }

  private stepperValue(field: number): number {
    const config = this.config();
    if (field === ReaderHeaderFooterEditor.STEPPER_HEADER_OFFSET) {
      return ReaderInfoBarConfig.clampOffsetToInset(config.headerOffset, this.headerBaseInset);
    }
    if (field === ReaderHeaderFooterEditor.STEPPER_FOOTER_OFFSET) {
      return ReaderInfoBarConfig.clampOffsetToInset(config.footerOffset, this.footerBaseInset);
    }
    if (this.isShrinkStepper(field)) return config.sideInset(this.isHeaderInset(field), this.isLeftInset(field));
    if (field === ReaderHeaderFooterEditor.STEPPER_HEADER_OPACITY) return config.headerOpacity;
    if (field === ReaderHeaderFooterEditor.STEPPER_FOOTER_OPACITY) return config.footerOpacity;
    return field === ReaderHeaderFooterEditor.STEPPER_HEADER_FONT_SIZE ?
      config.headerFontSize : config.footerFontSize;
  }

  private setInfoColor(header: boolean, value: string): void {
    const config = this.config();
    config.setCustomColor(header, this.modeDark, value);
    this.commit(config);
  }

  private colorDescription(header: boolean): string {
    const mode = this.modeDark ? '深色模式' : '浅色模式';
    return this.config().customColor(header, this.modeDark) ?
      `${mode}已自定义，可选“跟随主题”恢复` : `${mode}跟随主题配色`;
  }

  private isOffsetStepper(field: number): boolean {
    return field === ReaderHeaderFooterEditor.STEPPER_HEADER_OFFSET ||
      field === ReaderHeaderFooterEditor.STEPPER_FOOTER_OFFSET;
  }

  private stepperMin(field: number): number {
    if (this.isShrinkStepper(field)) return ReaderInfoBarConfig.SHRINK_MIN;
    if (this.isOffsetStepper(field)) {
      return ReaderInfoBarConfig.offsetMinForInset(field === ReaderHeaderFooterEditor.STEPPER_HEADER_OFFSET ?
        this.headerBaseInset : this.footerBaseInset);
    }
    return this.isOpacityStepper(field) ?
      ReaderInfoBarConfig.OPACITY_MIN : ReaderInfoBarConfig.FONT_SIZE_MIN;
  }

  private stepperMax(field: number): number {
    if (this.isShrinkStepper(field)) return ReaderInfoBarConfig.SHRINK_MAX;
    if (this.isOffsetStepper(field)) return ReaderInfoBarConfig.OFFSET_MAX;
    return this.isOpacityStepper(field) ?
      ReaderInfoBarConfig.OPACITY_MAX : ReaderInfoBarConfig.FONT_SIZE_MAX;
  }

  private isOpacityStepper(field: number): boolean {
    return field === ReaderHeaderFooterEditor.STEPPER_HEADER_OPACITY ||
      field === ReaderHeaderFooterEditor.STEPPER_FOOTER_OPACITY;
  }

  /** 左、右内缩共四个步进项。 */
  private isShrinkStepper(field: number): boolean {
    return field >= ReaderHeaderFooterEditor.STEPPER_HEADER_INSET_LEFT &&
      field <= ReaderHeaderFooterEditor.STEPPER_FOOTER_INSET_RIGHT;
  }

  private isHeaderInset(field: number): boolean {
    return field === ReaderHeaderFooterEditor.STEPPER_HEADER_INSET_LEFT ||
      field === ReaderHeaderFooterEditor.STEPPER_HEADER_INSET_RIGHT;
  }

  private isLeftInset(field: number): boolean {
    return field === ReaderHeaderFooterEditor.STEPPER_HEADER_INSET_LEFT ||
      field === ReaderHeaderFooterEditor.STEPPER_FOOTER_INSET_LEFT;
  }

  /** 紧凑面板里“位置与内缩”一行：选中项对应的步进项。 */
  private geometryField(header: boolean, target: number): number {
    if (target === ReaderHeaderFooterEditor.GEOMETRY_OFFSET) {
      return header ? ReaderHeaderFooterEditor.STEPPER_HEADER_OFFSET : ReaderHeaderFooterEditor.STEPPER_FOOTER_OFFSET;
    }
    if (target === ReaderHeaderFooterEditor.GEOMETRY_RIGHT) {
      return header ? ReaderHeaderFooterEditor.STEPPER_HEADER_INSET_RIGHT :
        ReaderHeaderFooterEditor.STEPPER_FOOTER_INSET_RIGHT;
    }
    return header ? ReaderHeaderFooterEditor.STEPPER_HEADER_INSET_LEFT :
      ReaderHeaderFooterEditor.STEPPER_FOOTER_INSET_LEFT;
  }

  private geometryName(target: number): string {
    if (target === ReaderHeaderFooterEditor.GEOMETRY_OFFSET) return '位置';
    return target === ReaderHeaderFooterEditor.GEOMETRY_RIGHT ? '右侧内缩' : '左侧内缩';
  }

  private geometryShortName(target: number): string {
    if (target === ReaderHeaderFooterEditor.GEOMETRY_OFFSET) return '位置';
    return target === ReaderHeaderFooterEditor.GEOMETRY_RIGHT ? '右' : '左';
  }

  private stepperText(field: number): string {
    const value = this.stepperValue(field);
    return this.isOpacityStepper(field) ? `${value}%` : `${value}`;
  }

  private stepBy(field: number, direction: number): void {
    if (!this.canStep(field, direction)) return;
    const config = this.config();
    if (field === ReaderHeaderFooterEditor.STEPPER_HEADER_OFFSET) {
      config.headerOffset = ReaderInfoBarConfig.clampOffsetToInset(
        this.stepperValue(field) + direction * ReaderInfoBarConfig.OFFSET_STEP, this.headerBaseInset);
    } else if (field === ReaderHeaderFooterEditor.STEPPER_FOOTER_OFFSET) {
      config.footerOffset = ReaderInfoBarConfig.clampOffsetToInset(
        this.stepperValue(field) + direction * ReaderInfoBarConfig.OFFSET_STEP, this.footerBaseInset);
    } else if (this.isShrinkStepper(field)) {
      config.setSideInset(this.isHeaderInset(field), this.isLeftInset(field),
        this.stepperValue(field) + direction * ReaderInfoBarConfig.SHRINK_STEP);
    } else if (field === ReaderHeaderFooterEditor.STEPPER_HEADER_OPACITY) {
      config.headerOpacity = ReaderInfoBarConfig.clampOpacity(
        config.headerOpacity + direction * ReaderInfoBarConfig.OPACITY_STEP);
    } else if (field === ReaderHeaderFooterEditor.STEPPER_FOOTER_OPACITY) {
      config.footerOpacity = ReaderInfoBarConfig.clampOpacity(
        config.footerOpacity + direction * ReaderInfoBarConfig.OPACITY_STEP);
    } else if (field === ReaderHeaderFooterEditor.STEPPER_HEADER_FONT_SIZE) {
      config.headerFontSize = ReaderInfoBarConfig.clampFontSize(config.headerFontSize + direction);
    } else if (field === ReaderHeaderFooterEditor.STEPPER_FOOTER_FONT_SIZE) {
      config.footerFontSize = ReaderInfoBarConfig.clampFontSize(config.footerFontSize + direction);
    }
    this.commit(config);
  }

  aboutToAppear(): void {
    this.styleFooter = this.readerFooterEnabled || !this.readerHeaderEnabled;
  }

  build() {
    Column({ space: this.compact ? 14 : AppSpacing.XS }) {
      if (this.compact) {
        this.compactContent()
      } else {
        this.listContent()
      }
    }
    .width('100%')
    .padding({ bottom: this.cardStyle ? 0 : 8 })
  }

  // 五个开关各包一层，列表布局与紧凑布局共用同一份回调。
  @Builder
  headerSwitch() {
    this.switchItem({ title: '显示页眉', description: '正文顶部显示书名、章节、时间等',
      checked: this.readerHeaderEnabled, onChange: (checked: boolean) => {
        this.readerHeaderEnabled = checked;
        this.notifyChanged();
      } })
  }

  @Builder
  headerDividerSwitch() {
    this.switchItem({ title: '页眉分隔线', description: '页眉下方的细线',
      checked: this.config().headerDivider, onChange: (checked: boolean) => {
        const config = this.config();
        config.headerDivider = checked;
        this.commit(config);
      }
    })
  }

  @Builder
  footerSwitch() {
    this.switchItem({ title: '显示页脚', description: '正文底部显示章节信息和进度',
      checked: this.readerFooterEnabled, onChange: (checked: boolean) => {
        this.readerFooterEnabled = checked;
        this.notifyChanged();
      } })
  }

  @Builder
  footerDividerSwitch() {
    this.switchItem({ title: '页脚分隔线', description: '页脚上方的细线',
      checked: this.config().footerDivider, onChange: (checked: boolean) => {
        const config = this.config();
        config.footerDivider = checked;
        this.commit(config);
      }
    })
  }

  @Builder
  followMarginSwitch() {
    this.switchItem({ title: '边距跟随正文', description: '页眉页脚的左右边距与正文一致',
      checked: this.config().followMargin, onChange: (checked: boolean) => {
        const config = this.config();
        config.followMargin = checked;
        this.commit(config);
      } })
  }

  @Builder
  progressBarItems() {
    this.selectItem('进度条', '显示在页眉下方或页脚上方', ReaderInfoProgressBar.LABELS,
      Math.max(0, ReaderInfoProgressBar.VALUES.indexOf(this.config().progressBar)),
      (index: number) => {
        const config = this.config();
        config.progressBar = index >= 0 && index < ReaderInfoProgressBar.VALUES.length ?
          ReaderInfoProgressBar.VALUES[index] : ReaderInfoProgressBar.NONE;
        this.commit(config);
      }, 'reader_progress_bar_select')
    if (this.config().progressBar !== ReaderInfoProgressBar.NONE) {
      this.selectItem('进度条范围', '表示本章或全书的进度', ReaderInfoProgressBar.SCOPE_LABELS,
        Math.max(0, ReaderInfoProgressBar.SCOPE_VALUES.indexOf(this.config().progressScope)),
        (index: number) => {
          const config = this.config();
          config.progressScope = index === 1 ?
            ReaderInfoProgressBar.SCOPE_BOOK : ReaderInfoProgressBar.SCOPE_CHAPTER;
          this.commit(config);
        }, 'reader_progress_scope_select')
    }
  }

  @Builder
  listContent() {
    this.headerSwitch()

    if (this.readerHeaderEnabled) {
      this.slotItem('页眉左侧', ReaderHeaderFooterEditor.SLOT_HEADER_LEFT, 'reader_header_left_select')
      this.slotItem('页眉中间', ReaderHeaderFooterEditor.SLOT_HEADER_CENTER, 'reader_header_center_select')
      this.slotItem('页眉右侧', ReaderHeaderFooterEditor.SLOT_HEADER_RIGHT, 'reader_header_right_select')
      this.colorItem('页眉颜色', true)
      this.stepperItem('页眉字号', ReaderHeaderFooterEditor.STEPPER_HEADER_FONT_SIZE)
      this.stepperItem('页眉不透明度', ReaderHeaderFooterEditor.STEPPER_HEADER_OPACITY)
      this.stepperItem('页眉位置', ReaderHeaderFooterEditor.STEPPER_HEADER_OFFSET)
      this.stepperItem('页眉左侧内缩', ReaderHeaderFooterEditor.STEPPER_HEADER_INSET_LEFT)
      this.stepperItem('页眉右侧内缩', ReaderHeaderFooterEditor.STEPPER_HEADER_INSET_RIGHT)
      this.headerDividerSwitch()
    }

    this.footerSwitch()

    if (this.readerFooterEnabled) {
      this.slotItem('页脚左侧', ReaderHeaderFooterEditor.SLOT_FOOTER_LEFT, 'reader_footer_left_select')
      this.slotItem('页脚中间', ReaderHeaderFooterEditor.SLOT_FOOTER_CENTER, 'reader_footer_center_select')
      this.slotItem('页脚右侧', ReaderHeaderFooterEditor.SLOT_FOOTER_RIGHT, 'reader_footer_right_select')
      this.colorItem('页脚颜色', false)
      this.stepperItem('页脚字号', ReaderHeaderFooterEditor.STEPPER_FOOTER_FONT_SIZE)
      this.stepperItem('页脚不透明度', ReaderHeaderFooterEditor.STEPPER_FOOTER_OPACITY)
      this.stepperItem('页脚位置', ReaderHeaderFooterEditor.STEPPER_FOOTER_OFFSET)
      this.stepperItem('页脚左侧内缩', ReaderHeaderFooterEditor.STEPPER_FOOTER_INSET_LEFT)
      this.stepperItem('页脚右侧内缩', ReaderHeaderFooterEditor.STEPPER_FOOTER_INSET_RIGHT)
      this.footerDividerSwitch()
    }

    if (this.readerHeaderEnabled || this.readerFooterEnabled) {
      this.followMarginSwitch()
      this.progressBarItems()
    }
  }

  @Builder
  compactContent() {
    ReaderSettingGroup({ title: '内容：点位置选择显示什么', dark: this.dark, subTextColor: this.subTextColor }) {
      this.headerSwitch()
      this.slotDiagram()
      this.footerSwitch()
    }

    ReaderSettingGroup({ title: '样式', dark: this.dark, subTextColor: this.subTextColor }) {
      ReaderSettingTabStrip({
        labels: ['页眉', '页脚'],
        selected: this.styleFooter ? 1 : 0,
        dense: true,
        dark: this.dark,
        textColor: this.textColor,
        subTextColor: this.subTextColor,
        onSelect: (index: number): void => {
          this.styleFooter = index === 1;
        }
      })
        .margin({ top: 10, bottom: AppSpacing.XS })
      if (this.styleFooter) {
        Column() {
          this.colorItem('页脚颜色', false)
          Row({ space: 14 }) {
            this.stepperCell('字号', ReaderHeaderFooterEditor.STEPPER_FOOTER_FONT_SIZE)
            this.stepperCell('不透明度', ReaderHeaderFooterEditor.STEPPER_FOOTER_OPACITY)
          }
          this.geometryRow(false)
          this.footerDividerSwitch()
        }
        .width('100%')
        .opacity(this.readerFooterEnabled ? 1 : 0.4)
        .enabled(this.readerFooterEnabled)
      } else {
        Column() {
          this.colorItem('页眉颜色', true)
          Row({ space: 14 }) {
            this.stepperCell('字号', ReaderHeaderFooterEditor.STEPPER_HEADER_FONT_SIZE)
            this.stepperCell('不透明度', ReaderHeaderFooterEditor.STEPPER_HEADER_OPACITY)
          }
          this.geometryRow(true)
          this.headerDividerSwitch()
        }
        .width('100%')
        .opacity(this.readerHeaderEnabled ? 1 : 0.4)
        .enabled(this.readerHeaderEnabled)
      }
    }

    if (this.readerHeaderEnabled || this.readerFooterEnabled) {
      ReaderSettingGroup({ title: '通用', dark: this.dark, subTextColor: this.subTextColor }) {
        this.followMarginSwitch()
        this.progressBarItems()
      }
    }
  }

  /** 一张小页面示意图：上排三个位置是页眉，下排三个是页脚，点一个位置选它显示的内容。 */
  @Builder
  slotDiagram() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        this.slotChip(ReaderHeaderFooterEditor.SLOT_HEADER_LEFT, '页眉左侧')
        this.slotChip(ReaderHeaderFooterEditor.SLOT_HEADER_CENTER, '页眉中间')
        this.slotChip(ReaderHeaderFooterEditor.SLOT_HEADER_RIGHT, '页眉右侧')
      }
      .width('100%')
      .opacity(this.readerHeaderEnabled ? 1 : 0.35)
      .enabled(this.readerHeaderEnabled)

      ForEach(['100%', '100%', '62%'], (lineWidth: string) => {
        Row()
          .width(lineWidth)
          .height(5)
          .borderRadius(3)
          .backgroundColor(this.dark ? '#1FFFFFFF' : '#14000000')
      }, (_lineWidth: string, index: number) => `${index}`)

      Row({ space: 6 }) {
        this.slotChip(ReaderHeaderFooterEditor.SLOT_FOOTER_LEFT, '页脚左侧')
        this.slotChip(ReaderHeaderFooterEditor.SLOT_FOOTER_CENTER, '页脚中间')
        this.slotChip(ReaderHeaderFooterEditor.SLOT_FOOTER_RIGHT, '页脚右侧')
      }
      .width('100%')
      .opacity(this.readerFooterEnabled ? 1 : 0.35)
      .enabled(this.readerFooterEnabled)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(10)
    .borderRadius(14)
    .backgroundColor(this.dark ? '#14FFFFFF' : '#B3FFFFFF')
    .margin({ top: AppSpacing.XS, bottom: AppSpacing.XS })
  }

  // 内容与弹出状态在这里直接读取，按值传入的只有固定的位置编号。
  @Builder
  slotChip(slot: number, title: string) {
    Text(this.slotIndex(slot) > 0 ? ReaderInfoItem.LABELS[this.slotIndex(slot)] : '＋')
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.slotIndex(slot) > 0 ? this.accentColor : this.subTextColor)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(30)
      .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
      .borderRadius(9)
      .border({
        width: 1,
        color: this.slotIndex(slot) > 0 ? this.accentColor : this.subTextColor,
        style: this.slotIndex(slot) > 0 ? BorderStyle.Solid : BorderStyle.Dashed
      })
      .accessibilityText(`${title}：${ReaderInfoItem.LABELS[this.slotIndex(slot)]}`)
      .onClick(() => {
        this.slotMenu = slot;
      })
      .bindPopup(this.slotMenu === slot, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
        this.slotMenuContent(slot)
      }, slot >= ReaderHeaderFooterEditor.SLOT_FOOTER_LEFT ? Placement.Top : Placement.Bottom, this.dark, this.accentColor, () => {
        if (this.slotMenu === slot) this.slotMenu = -1;
      }))
  }

  @Builder
  slotMenuContent(slot: number) {
    Scroll() {
      Column() {
        ForEach(ReaderInfoItem.LABELS, (label: string, index: number) => {
          Text(label)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.slotIndex(slot) === index ? this.accentColor : this.textColor)
            .width('100%')
            .height(42)
            .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
            .borderRadius(12)
            .backgroundColor(this.slotIndex(slot) === index ? ThemeRuntime.accentSurfaceColor(this.dark) : Color.Transparent)
            .onClick(() => {
              this.slotMenu = -1;
              this.setSlot(slot, index);
            })
        }, (_label: string, index: number) => `${index}`)
      }
      .width(208)
      .padding(6)
    }
    .constraintSize({ maxHeight: 336 })
    .scrollBar(BarState.Off)
  }

  /**
   * 位置、左侧内缩、右侧内缩合在一行：点数值标签选中一项，右边一对加减按钮调整选中项。
   * 选中项、数值与可用状态都在这里直接读取，按值传入的只有固定的页眉/页脚与方向。
   */
  @Builder
  geometryRow(header: boolean) {
    Column() {
      Text('位置与内缩')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor)
        .width('100%')
        .margin({ bottom: AppSpacing.XS })
      Row({ space: 6 }) {
        this.geometryChip(header, ReaderHeaderFooterEditor.GEOMETRY_LEFT)
        this.geometryChip(header, ReaderHeaderFooterEditor.GEOMETRY_OFFSET)
        this.geometryChip(header, ReaderHeaderFooterEditor.GEOMETRY_RIGHT)
        Row({ space: 8 }) {
          this.geometryStepButton($r('sys.symbol.minus'), header, -1)
          this.geometryStepButton($r('sys.symbol.plus'), header, 1)
        }
        .margin({ left: 6 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  geometryChip(header: boolean, target: number) {
    Text(`${this.geometryShortName(target)} ${this.stepperText(this.geometryField(header, target))}`)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.geometryTarget === target ? this.accentColor : this.textColor)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(34)
      .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
      .borderRadius(9)
      .backgroundColor(this.geometryTarget === target ? ThemeRuntime.accentSurfaceColor(this.dark) :
        (this.dark ? '#14FFFFFF' : '#0A000000'))
      .border({ width: 1, color: this.geometryTarget === target ? this.accentColor : Color.Transparent })
      .accessibilityText(`${header ? '页眉' : '页脚'}${this.geometryName(target)}：` +
        `${this.stepperText(this.geometryField(header, target))}`)
      .accessibilitySelected(this.geometryTarget === target)
      .onClick(() => {
        this.geometryTarget = target;
      })
  }

  @Builder
  geometryStepButton(icon: Resource, header: boolean, direction: number) {
    ImmersiveBackButton({
      icon: icon,
      accessibilityLabel: `${direction < 0 ? '减小' : '增大'}${this.geometryName(this.geometryTarget)}`,
      iconColor: this.dark ? '#FFFFFFFF' : '#FF202124',
      disabledIconColor: this.subTextColor,
      darkMode: this.dark,
      buttonEnabled: this.canStep(this.geometryField(header, this.geometryTarget), direction),
      buttonSize: 34,
      containerWidth: 34,
      containerHeight: 34,
      startInset: 0,
      compactLayout: true,
      onBack: (): void => this.stepBy(this.geometryField(header, this.geometryTarget), direction)
    })
  }

  // 两列并排用的步进器：标题在上。数值与可用状态同样直接从配置读取。
  @Builder
  stepperCell(title: string, field: number) {
    Column() {
      Text(title)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor)
        .width('100%')
        .margin({ bottom: AppSpacing.XS })
      Row() {
        this.stepperButton($r('sys.symbol.minus'), `减小${title}`, field, -1)
        Text(this.stepperText(field))
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
        this.stepperButton($r('sys.symbol.plus'), `增大${title}`, field, 1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .layoutWeight(1)
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  itemLabel(title: string, description: string) {
    Column() {
      Text(title)
        .fontSize(this.cardStyle ? 16 : 15)
        .fontColor(this.textColor)
      if (description) {
        Text(description)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor)
          .margin({ top: AppSpacing.XS })
      }
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  switchItem($$: ReaderHeaderFooterSwitchOptions) {
    Row() {
      this.itemLabel($$.title, $$.description)
      AdaptiveSwitch({
        isOn: $$.checked,
        selectedColor: this.switchColor,
        onChange: (value: boolean) => $$.onChange(value)
      })
    }
    .width(this.cardStyle ? 'calc(100% - 32vp)' : '100%')
    .constraintSize({ minHeight: this.cardStyle ? 64 : 56 })
    .padding({ top: this.cardStyle ? 10 : 0, bottom: this.cardStyle ? 10 : 0 })
    .margin({ left: this.cardStyle ? 16 : 0, right: this.cardStyle ? 16 : 0 })
    .border({ width: { bottom: this.cardStyle ? 0.5 : 0 }, color: this.dividerColor })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  slotItem(title: string, slot: number, controlId: string) {
    this.selectItem(title, '', ReaderInfoItem.LABELS, this.slotIndex(slot), (index: number) => {
      this.setSlot(slot, index);
    }, controlId)
  }

  @Builder
  colorItem(title: string, header: boolean) {
    Stack() {
      Row() {
        this.itemLabel(title, this.colorDescription(header))
        Row()
          .width(30)
          .height(30)
          .borderRadius(15)
          .backgroundColor(this.config().textColor(header, this.modeDark, this.subTextColor))
          .border({ width: 2, color: this.dark ? '#55FFFFFF' : '#22000000' })
          .margin({ left: 12 })
      }
      .width('100%')
      .constraintSize({ minHeight: 60 })
      .padding({ top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None)

      AdaptiveColorPicker({
        value: this.config().customColor(header, this.modeDark),
        placeholder: this.subTextColor,
        appDarkMode: this.dark,
        accentColor: this.accentColor,
        optionTitle: title,
        hideOptionTrigger: true,
        allowEmpty: true,
        emptyOptionLabel: '跟随主题',
        onColorChange: (color: string) => this.setInfoColor(header, color)
      })
        .accessibilityText(title)
    }
    .width(this.cardStyle ? 'calc(100% - 32vp)' : '100%')
    .margin({ left: this.cardStyle ? 16 : 0, right: this.cardStyle ? 16 : 0 })
    .border({ width: { bottom: this.cardStyle ? 0.5 : 0 }, color: this.dividerColor })
  }

  @Builder
  selectItem(title: string, description: string, labels: string[], selected: number,
    onSelect: (index: number) => void, controlId: string) {
    Row() {
      this.itemLabel(title, description)
      Select(labels.map((label: string): SelectOption => ({ value: label })))
        .id(controlId)
        .selected(selected)
        .value(selected >= 0 && selected < labels.length ? labels[selected] : (labels.length > 0 ? labels[0] : ''))
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
        .fontColor(this.subTextColor)
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        // Keep the hit area rectangular, but soften its corners to match the rounded settings cards.
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.textColor)
        .selectedOptionFontColor(this.accentColor)
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.dark))
        .menuBackgroundColor(this.menuColor)
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel, this.dark, this.menuColor))
        .onSelect((index: number) => onSelect(index))
    }
    .width(this.cardStyle ? 'calc(100% - 32vp)' : '100%')
    .constraintSize({ minHeight: description ? (this.cardStyle ? 64 : 56) : (this.cardStyle ? 52 : 44) })
    .padding({ top: this.cardStyle && !!description ? 10 : 0, bottom: this.cardStyle && !!description ? 10 : 0 })
    .margin({ left: this.cardStyle ? 16 : 0, right: this.cardStyle ? 16 : 0 })
    .border({ width: { bottom: this.cardStyle ? 0.5 : 0 }, color: this.dividerColor })
    .alignItems(VerticalAlign.Center)
  }

  // 数值直接从配置读取而不是经参数传入，保证点击加减后文字立即刷新。
  @Builder
  stepperItem(title: string, field: number) {
    Row({ space: AppSpacing.MD }) {
      this.itemLabel(title, '')
      this.stepperButton($r('sys.symbol.minus'), `减小${title}`, field, -1)
      Text(this.stepperText(field))
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.textColor)
        .width(52)
        .textAlign(TextAlign.Center)
      this.stepperButton($r('sys.symbol.plus'), `增大${title}`, field, 1)
    }
    .width(this.cardStyle ? 'calc(100% - 32vp)' : '100%')
    .constraintSize({ minHeight: this.cardStyle ? 52 : 44 })
    .margin({ left: this.cardStyle ? 16 : 0, right: this.cardStyle ? 16 : 0 })
    .border({ width: { bottom: this.cardStyle ? 0.5 : 0 }, color: this.dividerColor })
    .alignItems(VerticalAlign.Center)
  }

  private canStep(field: number, direction: number): boolean {
    return direction < 0 ? this.stepperValue(field) > this.stepperMin(field) :
      this.stepperValue(field) < this.stepperMax(field);
  }

  // 可用状态在这里直接从配置读取。按值传进来的布尔参数不会随配置刷新：初始值在下限的项
  // 减号一开始禁用时，数值增加后也不会恢复可用。
  @Builder
  stepperButton(icon: Resource, accessibilityText: string, field: number, direction: number) {
    ImmersiveBackButton({
      icon: icon,
      accessibilityLabel: accessibilityText,
      iconColor: this.dark ? '#FFFFFFFF' : '#FF202124',
      disabledIconColor: this.subTextColor,
      darkMode: this.dark,
      buttonEnabled: this.canStep(field, direction),
      buttonSize: 34,
      containerWidth: 34,
      containerHeight: 34,
      startInset: 0,
      compactLayout: true,
      onBack: (): void => this.stepBy(field, direction)
    })
  }
}
