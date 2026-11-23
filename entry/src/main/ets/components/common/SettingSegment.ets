import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/**
 * 设置页里两三个选项并排的单选条，放在设置行下面：
 *   SettingRow({ title: '统一封面', showDivider: false })
 *   SettingSegment({ labels: ['不使用', '主题封面', '图集'], selected: this.replaceIndex(), onSelect: … })
 * 选中项只看传入的 selected，自己不记状态：父页面没接受这次选择（保存失败等）时会留在原位。
 */
@Component
export struct SettingSegment {
  @Prop labels: string[] = [];
  @Prop selected: number = 0;
  /** 放在已经留好左右边距的容器里时传 false：占满宽度、不带外边距。 */
  @Prop inset: boolean = true;
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  onSelect: (index: number) => void = (_index: number) => {
  };

  build() {
    Row({ space: 2 }) {
      ForEach(this.labels, (label: string, index: number) => {
        Text(label)
          .fontSize(AppFontSize.BODY)
          .fontColor(index === this.selected ?
            ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.appDarkMode)) :
            ThemeRuntime.subTextColor(this.appDarkMode))
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .height(32)
          .borderRadius(8)
          .backgroundColor(index === this.selected ? ThemeRuntime.buttonColor(this.appDarkMode) : Color.Transparent)
          .accessibilityText(label)
          .accessibilitySelected(index === this.selected)
          .onClick(() => {
            if (index !== this.selected) this.onSelect(index);
          })
      }, (label: string, index: number) => `${index}_${label}_${index === this.selected ? 1 : 0}_${this.appDarkMode ? 1 : 0}_${this.themeRevision}`)
    }
    .width(this.inset ? 'calc(100% - 32vp)' : '100%')
    .padding(3)
    .margin({ left: this.inset ? AppSpacing.XL : 0, right: this.inset ? AppSpacing.XL : 0,
      bottom: this.inset ? AppSpacing.LG : 0 })
    .borderRadius(10)
    .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
  }
}
