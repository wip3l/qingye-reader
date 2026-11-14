import { pasteboard } from '@kit.BasicServicesKit';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { HdsFeedback } from '../../utils/HdsFeedback';

/** 恢复码只显示这一次：注册成功、首次设置密码、重新生成后都用这块面板展示。 */
@Component
export struct RecoveryCodesPanel {
  @Prop codes: string[] = [];
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  doneLabel: string = '我已保存';
  onDone: () => void = () => {
  };

  private async copyAll(): Promise<void> {
    try {
      const text = `轻页账号恢复码（每个只能用一次）\n${this.codes.join('\n')}`;
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
      HdsFeedback.showToast('已复制恢复码，请存到安全的地方');
    } catch (e) {
      HdsFeedback.showToast('复制失败，请截图保存');
    }
  }

  build() {
    Column({ space: AppSpacing.LG }) {
      Text('请保存恢复码')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .width('100%')
      Text('忘记密码时，用户名加任意一个恢复码就能重设密码，每个恢复码只能用一次。恢复码只显示这一次，请截图或复制后存到安全的地方。')
        .fontSize(AppFontSize.BODY)
        .lineHeight(21)
        .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .width('100%')
      Grid() {
        ForEach(this.codes, (code: string) => {
          GridItem() {
            Text(code)
              .fontSize(AppFontSize.BODY_LARGE)
              .fontWeight(FontWeight.Medium)
              .letterSpacing(1)
              .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
              .textAlign(TextAlign.Center)
              .width('100%')
              .height(40)
              .borderRadius(ThemeRuntime.mediumRadius())
              .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          }
        }, (code: string) => code)
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(AppSpacing.MD)
      .rowsGap(AppSpacing.MD)
      .width('100%')
      .height(Math.ceil(this.codes.length / 2) * 40 + Math.max(0, Math.ceil(this.codes.length / 2) - 1) * AppSpacing.MD)
      .enableScrollInteraction(false)
      Row({ space: AppSpacing.LG }) {
        Button('复制全部')
          .layoutWeight(1)
          .height(40)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .onClick(() => {
            this.copyAll();
          })
        Button(this.doneLabel)
          .layoutWeight(1)
          .height(40)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.accentColor(this.appDarkMode)))
          .backgroundColor(ThemeRuntime.accentColor(this.appDarkMode))
          .onClick(() => {
            this.onDone();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
  }
}
