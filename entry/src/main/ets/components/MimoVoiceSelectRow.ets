import { SettingRow } from './common/SettingRow';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';

/** Same select-menu appearance as the existing MiMo and reader settings. */
@Component
export struct MimoVoiceSelectRow {
  @Prop title: string = '';
  @Prop description: string = '';
  @Prop choices: string[] = [];
  @Prop selection: string = '';
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('immersiveLightLevel') light: string = 'adaptive';
  onSelect: (index: number) => void = (_index: number): void => {};
  build() {
    SettingRow({ title: this.title, description: this.description, showDivider: false }) {
      Select(this.choices.map((text: string): SelectOption => ({ value: text })))
        .selected(this.choices.indexOf(this.selection)).value(this.selection)
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily }).optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily }).fontColor(ThemeRuntime.subTextColor(this.dark))
        .backgroundColor(Color.Transparent).arrowPosition(ArrowPosition.END).padding({ left: 0, right: 0 })
        .borderRadius(16).border({ width: 0 }).divider(null).optionBgColor(Color.Transparent)
        .optionFontColor(ThemeRuntime.primaryTextColor(this.dark))
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.dark))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.dark))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.dark)).menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.light))
        .accessibilityText(this.title + '，' + this.selection).onSelect((index: number) => this.onSelect(index))
    }
  }
}
