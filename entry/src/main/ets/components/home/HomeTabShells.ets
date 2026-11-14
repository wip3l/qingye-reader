import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { HomeThemeBackdrop } from './HomeThemeBackdrop';

/** 首页页签的占位外壳：冷启动时先显示的书架骨架，以及尚未激活页签的空白页。 */
@Component
export struct FastBookshelfShell {
  @Prop statusBarHeight: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('bookshelfLayoutMode') bookshelfLayoutMode: string = 'companion';

  build() {
    Column() {
      // 骨架要和随后出现的书架用同一张背景：布局是持久化的，冷启动时已经在 AppStorage 里。
      HomeThemeBackdrop({ shelfLayout: this.bookshelfLayoutMode })
        .position({ x: 0, y: 0 })
      Row() {
        Text('书架')
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
      .alignItems(VerticalAlign.Center)

      Column({ space: AppSpacing.MD }) {
        this.placeholderCard(0.92)
        this.placeholderCard(0.78)
        this.placeholderCard(0.86)
      }
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  placeholderCard(widthRatio: number) {
    Row() {
      Column()
        .width(56)
        .height(72)
        .borderRadius(6)
        .backgroundColor(this.appDarkMode ? '#24272D' : '#E6E9EE')

      Column({ space: AppSpacing.MD }) {
        Column()
          .width(`${Math.floor(widthRatio * 100)}%`)
          .height(16)
          .borderRadius(8)
          .backgroundColor(this.appDarkMode ? '#24272D' : '#E2E5EA')
        Column()
          .width('48%')
          .height(12)
          .borderRadius(6)
          .backgroundColor(this.appDarkMode ? '#202329' : '#ECEEF2')
        Column()
          .width('34%')
          .height(12)
          .borderRadius(6)
          .backgroundColor(this.appDarkMode ? '#202329' : '#ECEEF2')
      }
      .layoutWeight(1)
      .margin({ left: AppSpacing.LG })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(AppSpacing.LG)
    .borderRadius(ThemeRuntime.mediumRadius())
    .backgroundColor(this.appDarkMode ? '#191B1F' : '#FFFFFF')
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }
}

@Component
export struct BlankTabPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;

  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
