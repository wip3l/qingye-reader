import { firstGestureFinger } from '../utils/GestureFingers';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ImmersiveBackButton } from './ImmersiveBackButton';
import { HexColor } from '../utils/HexColor';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';

class HsvColor {
  hue: number = 0;
  saturation: number = 0;
  value: number = 0;
}

class ThemePaletteColor {
  label: string = '';
  color: string = '';
}

@Component
export struct ColorCodePicker {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('themeRevision') themeRevision: number = 0;
  @Prop value: string = '#007DFF';
  @Prop placeholder: string = '#007DFF';
  @Prop appDarkMode: boolean = false;
  @Prop accentColor: string = '#007DFF';
  @Prop allowEmpty: boolean = false;
  @Prop allowAlpha: boolean = false;
  @State colorOpacity: number = 100;
  @Prop emptyOptionLabel: string = '跟随强调色';
  @Prop optionTitle: string = '';
  @Prop hideOptionTrigger: boolean = false;
  @Prop colorMode: string = '';
  /** 颜色行底部画一条和相邻设置行一样的分隔线。 */
  @Prop rowDivider: boolean = false;
  @State pickerVisible: boolean = false;
  @State draftColor: string = '#007DFF';
  @State hue: number = 210;
  @State saturation: number = 100;
  @State colorBrightness: number = 100;
  @State originalColor: string = '#007DFF';
  @State pickerAreaWidth: number = 260;
  @State pickerAreaHeight: number = 240;
  @State hueAreaHeight: number = 240;
  @State showPresetColors: boolean = false;
  onColorChange: (color: string) => void = (_color: string): void => {};
  onColorModeChange: (mode: string) => void = (_mode: string): void => {};

  private presetColors: string[] = [
    '#007DFF', '#4E9BFF', '#00A870', '#2E7D68', '#FF7A1A', '#E53935',
    '#D81B60', '#7A5AF8', '#8E24AA', '#00ACC1', '#607D8B', '#FFE58A'
  ];

  private normalizeColor(color: string, fallback: string): string {
    return this.allowAlpha ? HexColor.normalizeAlpha(color, fallback) : HexColor.normalize(color, fallback, '#007DFF');
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(value, max));
  }

  private hexToHsv(color: string): HsvColor {
    const normalized = HexColor.rgb(this.normalizeColor(color, '#007DFF'));
    const red = parseInt(normalized.substring(1, 3), 16) / 255;
    const green = parseInt(normalized.substring(3, 5), 16) / 255;
    const blue = parseInt(normalized.substring(5, 7), 16) / 255;
    const max = Math.max(red, green, blue);
    const min = Math.min(red, green, blue);
    const delta = max - min;
    let hue = 0;
    if (delta !== 0) {
      if (max === red) {
        hue = 60 * (((green - blue) / delta) % 6);
      } else if (max === green) {
        hue = 60 * (((blue - red) / delta) + 2);
      } else {
        hue = 60 * (((red - green) / delta) + 4);
      }
    }
    if (hue < 0) {
      hue += 360;
    }
    const result = new HsvColor();
    result.hue = hue;
    result.saturation = max === 0 ? 0 : delta / max;
    result.value = max;
    return result;
  }

  private componentToHex(value: number): string {
    return Math.round(this.clamp(value, 0, 255)).toString(16).padStart(2, '0').toUpperCase();
  }

  private hsvToHex(hue: number, saturation: number, value: number): string {
    const normalizedHue = ((hue % 360) + 360) % 360;
    const normalizedSaturation = this.clamp(saturation, 0, 100) / 100;
    const normalizedValue = this.clamp(value, 0, 100) / 100;
    const chroma = normalizedValue * normalizedSaturation;
    const hueSection = normalizedHue / 60;
    const secondary = chroma * (1 - Math.abs((hueSection % 2) - 1));
    const match = normalizedValue - chroma;
    let red = 0;
    let green = 0;
    let blue = 0;
    if (hueSection < 1) {
      red = chroma;
      green = secondary;
    } else if (hueSection < 2) {
      red = secondary;
      green = chroma;
    } else if (hueSection < 3) {
      green = chroma;
      blue = secondary;
    } else if (hueSection < 4) {
      green = secondary;
      blue = chroma;
    } else if (hueSection < 5) {
      red = secondary;
      blue = chroma;
    } else {
      red = chroma;
      blue = secondary;
    }
    return `#${this.componentToHex((red + match) * 255)}${this.componentToHex((green + match) * 255)}${this.componentToHex((blue + match) * 255)}`;
  }

  private hueColor(): string {
    return this.hsvToHex(this.hue, 100, 100);
  }

  private updateDraftFromHsv(): void {
    const rgb = this.hsvToHex(this.hue, this.saturation, this.colorBrightness);
    this.draftColor = this.allowAlpha ? HexColor.withOpacity(rgb, this.colorOpacity / 100) : rgb;
  }

  private updateHsvFromColor(color: string): void {
    this.colorOpacity = HexColor.alpha(color) / 255 * 100;
    const hsv = this.hexToHsv(color);
    this.hue = Math.round(hsv.hue);
    this.saturation = Math.round(hsv.saturation * 100);
    this.colorBrightness = Math.round(hsv.value * 100);
  }

  private openPicker(): void {
    this.draftColor = this.normalizeColor(this.value, this.placeholder);
    this.originalColor = this.draftColor;
    this.updateHsvFromColor(this.draftColor);
    this.showPresetColors = false;
    this.pickerVisible = true;
  }

  private commitDraftColor(): void {
    if (this.colorMode !== '') {
      this.onColorModeChange('custom');
    }
    this.onColorChange(this.draftColor);
    this.pickerVisible = false;
  }

  private parseAreaDimension(value: Length): number {
    const text = String(value).trim();
    const match = text.match(/\d+(\.\d+)?/);
    if (!match) {
      return 0;
    }
    const parsed = Number(match[0]);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private updatePickerAreaSize(area: Area): void {
    const width = this.parseAreaDimension(area.width);
    const height = this.parseAreaDimension(area.height);
    if (width > 0) {
      this.pickerAreaWidth = width;
    }
    if (height > 0) {
      this.pickerAreaHeight = height;
    }
  }

  private updateHueAreaSize(area: Area): void {
    const height = this.parseAreaDimension(area.height);
    if (height > 0) {
      this.hueAreaHeight = height;
    }
  }

  private updateSaturationAndBrightness(x: number, y: number): void {
    this.saturation = this.clamp(x / Math.max(this.pickerAreaWidth, 1) * 100, 0, 100);
    this.colorBrightness = this.clamp((1 - y / Math.max(this.pickerAreaHeight, 1)) * 100, 0, 100);
    this.updateDraftFromHsv();
  }

  private handlePickerAreaTouch(event: TouchEvent): void {
    if (event.type !== TouchType.Down && event.type !== TouchType.Move) {
      return;
    }
    const point = event.changedTouches.length > 0 ? event.changedTouches[0] :
      (event.touches.length > 0 ? event.touches[0] : null);
    if (point) {
      this.updateSaturationAndBrightness(point.x, point.y);
    }
  }

  private updateHue(y: number): void {
    const ratio = this.clamp(y / Math.max(this.hueAreaHeight, 1), 0, 1);
    this.hue = (360 - ratio * 360) % 360;
    this.updateDraftFromHsv();
  }

  private handleHueTouch(event: TouchEvent): void {
    if (event.type !== TouchType.Down && event.type !== TouchType.Move) {
      return;
    }
    const point = event.changedTouches.length > 0 ? event.changedTouches[0] :
      (event.touches.length > 0 ? event.touches[0] : null);
    if (point) {
      this.updateHue(point.y);
    }
  }

  private handlePickerAreaGesture(event: GestureEvent): void {
    const finger = firstGestureFinger(event);
    if (finger) this.updateSaturationAndBrightness(finger.localX, finger.localY);
  }

  private handleHueGesture(event: GestureEvent): void {
    const finger = firstGestureFinger(event);
    if (finger) this.updateHue(finger.localY);
  }

  private pickerIndicatorX(): number {
    return this.clamp(this.saturation / 100 * this.pickerAreaWidth - 10, -2, this.pickerAreaWidth - 18);
  }

  private pickerIndicatorY(): number {
    return this.clamp((1 - this.colorBrightness / 100) * this.pickerAreaHeight - 10, -2,
      this.pickerAreaHeight - 18);
  }

  private hueIndicatorY(): number {
    const ratio = this.hue === 0 ? 0 : (360 - this.hue) / 360;
    return this.clamp(ratio * this.hueAreaHeight - 3, -1, this.hueAreaHeight - 5);
  }

  // 颜色都取当前主题；读 themeRevision 让切换主题后跟着重绘。
  private pageColor(): string {
    return this.themeRevision >= 0 ? ThemeRuntime.cardColor(this.appDarkMode) : '';
  }

  private inputColor(): string {
    return this.themeRevision >= 0 ? ThemeRuntime.inputColor(this.appDarkMode) : '';
  }

  private primaryTextColor(): string {
    return this.themeRevision >= 0 ? ThemeRuntime.primaryTextColor(this.appDarkMode) : '';
  }

  private subTextColor(): string {
    return this.themeRevision >= 0 ? ThemeRuntime.subTextColor(this.appDarkMode) : '';
  }

  private swatchBorderColor(): string {
    return this.appDarkMode ? '#55FFFFFF' : '#24000000';
  }

  /** 取色面板顶部“主题配色”一排：当前主题的几种颜色，点一下直接取用。 */
  private themePaletteColors(): ThemePaletteColor[] {
    if (this.themeRevision < 0) {
      return [];
    }
    const dark = this.appDarkMode;
    const entries: string[][] = [
      ['强调', ThemeRuntime.accentColor(dark)],
      ['按钮', ThemeRuntime.buttonColor(dark)],
      ['正文', ThemeRuntime.primaryTextColor(dark)],
      ['次要', ThemeRuntime.subTextColor(dark)],
      ['页面', ThemeRuntime.pageColor(dark)],
      ['卡片', ThemeRuntime.cardColor(dark)],
      ['危险', ThemeRuntime.dangerColor(dark)]
    ];
    return entries.map((entry: string[]): ThemePaletteColor => {
      const item = new ThemePaletteColor();
      item.label = entry[0];
      item.color = HexColor.rgb(entry[1]);
      return item;
    });
  }

  private applyPaletteColor(color: string): void {
    this.draftColor = this.allowAlpha ? HexColor.withOpacity(color, this.colorOpacity / 100) : color;
    this.updateHsvFromColor(this.draftColor);
  }

  private isDraftRgb(color: string): boolean {
    return HexColor.rgb(this.draftColor).toUpperCase() === color.toUpperCase();
  }

  private triggerFollowsDefault(): boolean {
    return this.allowEmpty && this.value.trim() === '';
  }

  private triggerLabel(): string {
    return this.triggerFollowsDefault() ? this.emptyOptionLabel :
      this.normalizeColor(this.value, this.placeholder).toUpperCase();
  }

  private colorModeIndex(): number {
    if (this.colorMode === 'accent') {
      return 1;
    }
    if (this.colorMode === 'custom') {
      return 2;
    }
    return 0;
  }

  private colorModeLabel(): string {
    if (this.colorMode === 'accent') {
      return '跟随强调色';
    }
    if (this.colorMode === 'custom') {
      return '自定义';
    }
    return '关闭';
  }

  build() {
    Column() {
      if (this.colorMode !== '') {
        Row({ space: AppSpacing.MD }) {
          Text('自定义高亮色')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
          Select([
            { value: '关闭' },
            { value: '跟随强调色' },
            { value: '自定义' }
          ])
            .selected(this.colorModeIndex())
            .value(this.colorModeLabel())
            .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
            .optionFont({ family: this.applicationFontFamily })
            .selectedOptionFont({ family: this.applicationFontFamily })
            .fontColor(this.subTextColor())
            .backgroundColor(Color.Transparent)
            .arrowPosition(ArrowPosition.END)
            .padding({ left: 0, right: 0 })
            .borderRadius(16)
            .border({ width: 0 })
            .constraintSize({ minWidth: 112, maxWidth: 140 })
            .optionBgColor(Color.Transparent)
            .divider(null)
            .optionFontColor(this.primaryTextColor())
            .selectedOptionFontColor(this.accentColor)
            .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
            .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
            .menuBackgroundBlurStyle(BlurStyle.NONE)
            .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
            .onSelect((index: number) => {
              if (index === 2) {
                this.openPicker();
              } else {
                this.onColorModeChange(index === 1 ? 'accent' : 'off');
              }
            })
          if (this.colorMode === 'custom') {
            Row()
              .width(28)
              .height(28)
              .borderRadius(14)
              .backgroundColor(this.normalizeColor(this.value, this.placeholder))
              .border({ width: 2, color: this.swatchBorderColor() })
              .onClick(() => {
                this.openPicker();
              })
          }
        }
        .width('100%')
        .height(56)
        .alignItems(VerticalAlign.Center)
      } else if (this.optionTitle !== '') {
        if (this.hideOptionTrigger) {
          Button('')
            .width('100%')
            .height(60)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .opacity(0.01)
            .onClick(() => {
              this.openPicker();
            })
        } else {
          // 和相邻设置行同样的透明底与左右对齐；右侧色值胶囊用主题浅填充，“跟随”状态染强调色。
          Row({ space: AppSpacing.SM }) {
            Text(this.optionTitle)
              .fontSize(AppFontSize.BODY_LARGE)
              .fontColor(this.primaryTextColor())
              .layoutWeight(1)
            Row({ space: 6 }) {
              Text(this.triggerLabel())
                .fontSize(AppFontSize.CAPTION)
                .fontFamily('monospace')
                .fontColor(this.triggerFollowsDefault() ? this.accentColor : this.subTextColor())
                .maxLines(1)
              Row()
                .width(20)
                .height(20)
                .borderRadius(10)
                .backgroundColor(this.normalizeColor(this.value, this.placeholder))
                .border({ width: 1.5, color: this.swatchBorderColor() })
            }
            .height(30)
            .padding({ left: 10, right: 5 })
            .borderRadius(15)
            .backgroundColor(this.triggerFollowsDefault() ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) :
              ThemeRuntime.softFillColor(this.appDarkMode))
            .alignItems(VerticalAlign.Center)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([this.subTextColor()])
          }
          .width('100%')
          .constraintSize({ minHeight: 60 })
          .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM })
          .border({ width: { bottom: this.rowDivider ? 0.5 : 0 }, color: ThemeRuntime.hairlineColor(this.appDarkMode) })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.openPicker();
          })
        }
      } else {
        TextInput({ text: this.value, placeholder: this.placeholder })
          .height(42)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(this.inputColor())
          .borderRadius(ThemeRuntime.mediumRadius())
          .onClick(() => {
            this.openPicker();
          })
          .onChange((text: string) => {
            if (this.allowEmpty && text.trim() === '') {
              this.onColorChange('');
              return;
            }
            if (this.allowAlpha ? !!HexColor.parseAlpha(text) : !!HexColor.parse(text)) {
              this.onColorChange(this.normalizeColor(text, this.value));
            }
          })
      }
    }
      .width('100%')
      .bindSheet($$this.pickerVisible, this.colorPickerSheet(), {
        height: this.allowAlpha ? 760 : 670,
        dragBar: true,
        showClose: false,
        backgroundColor: this.pageColor(),
        onDisappear: () => {
          this.pickerVisible = false;
        }
      })
  }

  @Builder
  colorPickerSheet() {
    Column({ space: AppSpacing.XL }) {
      Row({ space: AppSpacing.LG }) {
        Text(this.optionTitle || '选择颜色')
          .fontSize(AppFontSize.HEADLINE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.allowEmpty) {
          Button(this.emptyOptionLabel)
            .height(40)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.accentColor)
            .backgroundColor(Color.Transparent)
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
            .flexShrink(0)
            .onClick(() => {
              this.onColorChange('');
              this.pickerVisible = false;
            })
        }
        ImmersiveBackButton({
          icon: $r('sys.symbol.xmark'),
          iconOffsetX: 0,
          iconColor: this.primaryTextColor(),
          darkMode: this.appDarkMode,
          buttonSize: 40,
          containerWidth: 40,
          containerHeight: 40,
          startInset: 0,
          compactLayout: true,
          accessibilityLabel: '关闭颜色选择',
          onBack: () => {
            this.pickerVisible = false;
          }
        })
          .flexShrink(0)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column({ space: AppSpacing.SM }) {
        Text('主题配色')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
        Row() {
          ForEach(this.themePaletteColors(), (item: ThemePaletteColor) => {
            Column({ space: 4 }) {
              Row()
                .width(28)
                .height(28)
                .borderRadius(14)
                .backgroundColor(item.color)
                .border({ width: 1.5, color: this.swatchBorderColor() })
                .outline({ width: this.isDraftRgb(item.color) ? 2 : 0, color: this.accentColor, radius: 16,
                  style: OutlineStyle.SOLID })
              Text(item.label)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor())
            }
            .padding(3)
            .onClick(() => {
              this.applyPaletteColor(item.color);
            })
            .accessibilityText(`主题${item.label}色`)
          }, (item: ThemePaletteColor) => `${item.label}${item.color}`)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row({ space: AppSpacing.LG }) {
        Stack({ alignContent: Alignment.TopStart }) {
          Row()
            .width('100%')
            .height('100%')
            .backgroundColor(this.hueColor())
          Row()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 90,
              colors: [['#FFFFFFFF', 0.0], ['#00FFFFFF', 1.0]]
            })
          Row()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 180,
              colors: [['#00000000', 0.0], ['#FF000000', 1.0]]
            })
          Row()
            .width(20)
            .height(20)
            .borderRadius(10)
            .border({ width: 3, color: '#FFFFFF' })
            .shadow({ radius: 3, color: '#99000000', offsetX: 0, offsetY: 1 })
            .position({ x: this.pickerIndicatorX(), y: this.pickerIndicatorY() })
            .hitTestBehavior(HitTestMode.None)
        }
        .height(240)
        .layoutWeight(1)
        .borderRadius(14)
        .clip(true)
        .border({ width: 1, color: this.swatchBorderColor() })
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          this.updatePickerAreaSize(newValue);
        })
        .onTouch((event: TouchEvent) => {
          this.handlePickerAreaTouch(event);
        })
        .priorityGesture(
          PanGesture({ direction: PanDirection.All, distance: 1 })
            .onActionStart((event: GestureEvent) => {
              this.handlePickerAreaGesture(event);
            })
            .onActionUpdate((event: GestureEvent) => {
              this.handlePickerAreaGesture(event);
            }),
          GestureMask.IgnoreInternal
        )
        .monopolizeEvents(true)

        Stack({ alignContent: Alignment.TopStart }) {
          Row()
            .width(38)
            .height('100%')
            .linearGradient({
              angle: 180,
              colors: [
                ['#FF0000', 0.0], ['#FF00FF', 0.17], ['#0000FF', 0.33], ['#00FFFF', 0.5],
                ['#00FF00', 0.67], ['#FFFF00', 0.83], ['#FF0000', 1.0]
              ]
            })
          Row()
            .width(44)
            .height(6)
            .borderRadius(3)
            .border({ width: 2, color: this.appDarkMode ? '#F2F3F5' : '#555555' })
            .backgroundColor(Color.Transparent)
            .position({ x: -3, y: this.hueIndicatorY() })
            .hitTestBehavior(HitTestMode.None)
        }
        .width(38)
        .height(240)
        .borderRadius(10)
        .clip(false)
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          this.updateHueAreaSize(newValue);
        })
        .onTouch((event: TouchEvent) => {
          this.handleHueTouch(event);
        })
        .priorityGesture(
          PanGesture({ direction: PanDirection.Vertical, distance: 1 })
            .onActionStart((event: GestureEvent) => {
              this.handleHueGesture(event);
            })
            .onActionUpdate((event: GestureEvent) => {
              this.handleHueGesture(event);
            }),
          GestureMask.IgnoreInternal
        )
        .monopolizeEvents(true)
      }
      .width('100%')

      Row({ space: AppSpacing.MD }) {
        Row()
          .width(48)
          .height(36)
          .borderRadius(10)
          .backgroundColor(this.originalColor)
          .border({ width: 1, color: this.swatchBorderColor() })
        Text('→')
          .fontSize(AppFontSize.TITLE)
          .fontColor(this.subTextColor())
        Row()
          .width(48)
          .height(36)
          .borderRadius(10)
          .backgroundColor(this.draftColor)
          .border({ width: 1, color: this.swatchBorderColor() })
        TextInput({ text: this.draftColor, placeholder: this.allowAlpha ? '#AARRGGBB' : '#RRGGBB' })
          .height(40)
          .fontSize(AppFontSize.SUBTITLE)
          .fontFamily('monospace')
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(this.inputColor())
          .borderRadius(12)
          .layoutWeight(1)
          .onChange((text: string) => {
            if (this.allowAlpha ? !!HexColor.parseAlpha(text) : !!HexColor.parse(text)) {
              this.draftColor = this.normalizeColor(text, this.draftColor);
              this.updateHsvFromColor(this.draftColor);
            }
          })
      }
      .width('100%')

      if (this.allowAlpha) {
        Column({ space: AppSpacing.XS }) {
          Row() {
            Text('透明度')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.primaryTextColor())
              .layoutWeight(1)
            Text(`${Math.round(100 - this.colorOpacity)}%`)
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
          }
          Slider({ value: 100 - this.colorOpacity, min: 0, max: 100, step: 1 })
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
            .width('100%')
            .selectedColor(this.accentColor)
            .onChange((value: number) => {
              this.colorOpacity = 100 - value;
              this.draftColor = HexColor.withOpacity(this.draftColor, this.colorOpacity / 100);
            })
          Text('0% 不透明 · 100% 完全透明 · 色值格式 #AARRGGBB')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
        }
        .width('100%')
      }

      if (this.showPresetColors) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.presetColors, (color: string) => {
            Button('')
              .width(30)
              .height(30)
              .borderRadius(15)
              .padding(0)
              .backgroundColor(color)
              .border({ width: this.draftColor === color ? 3 : 1,
                color: this.draftColor === color ? this.primaryTextColor() : this.swatchBorderColor() })
              .margin({ right: AppSpacing.MD, bottom: AppSpacing.SM })
              .onClick(() => {
                this.draftColor = this.allowAlpha ? HexColor.withOpacity(color, this.colorOpacity / 100) : color;
                this.updateHsvFromColor(this.draftColor);
              })
          })
        }
        .width('100%')
      }

      Row({ space: AppSpacing.LG }) {
        Button('预置颜色')
          .height(42)
          .fontColor(this.primaryTextColor())
          .backgroundColor(ThemeRuntime.softFillColor(this.appDarkMode))
          .layoutWeight(1)
          .onClick(() => {
            this.showPresetColors = !this.showPresetColors;
          })
        Button('确认')
          .height(42)
          .fontColor(ThemeRuntime.onAccentColor(HexColor.rgb(this.accentColor)))
          .backgroundColor(this.accentColor)
          .layoutWeight(1)
          .onClick(() => {
            this.commitDraftColor();
          })
      }
      .width('100%')
      .margin({ top: AppSpacing.XS })
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppSpacing.XXL, right: AppSpacing.XXL, top: AppSpacing.LG, bottom: AppSpacing.XXL })
    .backgroundColor(this.pageColor())
  }
}
