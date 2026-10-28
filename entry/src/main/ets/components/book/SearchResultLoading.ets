import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/** Page-level progress only: individual book placeholders are final fallback covers. */
@Component
export struct SearchResultLoading {
  @Prop topPadding: number = 0;
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @State indicatorReady: boolean = false;
  private delayTimer: number = -1;

  aboutToAppear(): void {
    this.delayTimer = setTimeout((): void => {
      this.delayTimer = -1;
      this.indicatorReady = true;
    }, 180);
  }

  aboutToDisappear(): void {
    if (this.delayTimer >= 0) clearTimeout(this.delayTimer);
  }

  build() {
    Column({ space: AppSpacing.MD }) {
      if (this.indicatorReady) {
        LoadingProgress().width(28).height(28)
        Text('正在搜索')
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topPadding })
    .justifyContent(FlexAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }
}
