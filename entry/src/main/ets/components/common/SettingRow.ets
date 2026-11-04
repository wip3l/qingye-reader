import { MembershipBadge } from './MembershipBadge';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { AdaptiveSwitch } from '../AdaptiveSwitch';

/**
 * 设置页卡片里的一行：左侧标题和说明，右侧控件用尾随闭包传入。
 *   SettingRow({ title: '搜索并发数', description: '…' }) { this.stepper() }
 * 只是开关或跳转时直接用下面的 SettingSwitchRow、SettingNavRow。
 */
@Component
export struct SettingRow {
  @Prop title: string = '';
  @Prop minimumMembership: string = '';
  @Prop description: string = '';
  /** 行底部的细分隔线；卡片最后一行可以关掉。 */
  @Prop showDivider: boolean = true;
  /** 不传时用主题的主文字色；危险操作可以传危险色。 */
  @Prop titleColor?: ResourceColor;
  /** 行首图标，用在作为入口的行上；普通设置项不传。 */
  @Prop icon?: Resource;
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  onTap: () => void = () => {
  };
  @BuilderParam trailing: () => void = this.emptySlot;

  @Builder
  emptySlot() {
  }

  build() {
    Row() {
      if (this.icon !== undefined) {
        Stack() {
          SymbolGlyph(this.icon)
            .fontSize(18)
            .fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
        }
        .width(32)
        .height(32)
        .borderRadius(9)
        .backgroundColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .margin({ right: AppSpacing.LG })
      }
      Column() {
        Row({ space: AppSpacing.XS }) {
          Text(this.title)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.titleColor !== undefined ? this.titleColor :
              ThemeRuntime.primaryTextColor(this.appDarkMode))
            .flexShrink(1)
          if (this.minimumMembership) {
            MembershipBadge({ sku: this.minimumMembership })
          }
        }
        if (this.description) {
          Text(this.description)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            .margin({ top: AppSpacing.XS })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      this.trailing()
    }
    .width('calc(100% - 32vp)')
    .constraintSize({ minHeight: 64 })
    .padding({ top: AppSpacing.MD, bottom: AppSpacing.MD })
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
    .border({ width: { bottom: this.showDivider ? 0.5 : 0 }, color: ThemeRuntime.hairlineColor(this.appDarkMode) })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.onTap())
  }
}

/** 带开关的设置行。 */
@Component
export struct SettingSwitchRow {
  @Prop title: string = '';
  @Prop minimumMembership: string = '';
  @Prop description: string = '';
  @Prop isOn: boolean = false;
  @Prop switchEnabled: boolean = true;
  @Prop showDivider: boolean = true;
  onChange: (isOn: boolean) => void = (_isOn: boolean) => {
  };

  build() {
    SettingRow({ title: this.title, minimumMembership: this.minimumMembership, description: this.description, showDivider: this.showDivider }) {
      AdaptiveSwitch({
        isOn: this.isOn,
        switchEnabled: this.switchEnabled,
        accessibilityLabel: this.title,
        onChange: (isOn: boolean) => this.onChange(isOn)
      })
        .opacity(this.switchEnabled ? 1 : 0.45)
    }
  }
}

/** 点击后跳转或弹出操作的设置行，右侧显示可选的当前值和箭头。 */
@Component
export struct SettingNavRow {
  @Prop title: string = '';
  @Prop minimumMembership: string = '';
  @Prop description: string = '';
  /** 显示在箭头左侧的当前值，可不传。 */
  @Prop value: string = '';
  @Prop showDivider: boolean = true;
  @Prop titleColor?: ResourceColor;
  @Prop icon?: Resource;
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  onTap: () => void = () => {
  };

  build() {
    SettingRow({ title: this.title, minimumMembership: this.minimumMembership, description: this.description, showDivider: this.showDivider,
      titleColor: this.titleColor, icon: this.icon, onTap: () => this.onTap() }) {
      Row({ space: AppSpacing.XS }) {
        if (this.value) {
          Text(this.value)
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([ThemeRuntime.subTextColor(this.appDarkMode)])
      }
      .margin({ left: AppSpacing.MD })
    }
  }
}
