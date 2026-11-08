import { BookshelfDisplaySettingsStore } from '../../utils/BookshelfDisplaySettingsStore';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/**
 * 陪伴布局书架网格上方标题的编辑面板，书架长按标题与书架设置共用。调用方在自己的对话框 builder 里创建它，
 * 保存、取消交回调用方写设置并关闭对话框；留空保存即显示默认文案，“恢复默认”只回填输入框，仍要点保存。
 */
@Component
export struct ShelfSectionTitleEditor {
  @Prop appDarkMode: boolean = false;
  @Prop initialTitle: string = '';
  @State title: string = '';
  onSave: (title: string) => void = () => {};
  onCancel: () => void = () => {};

  aboutToAppear(): void {
    this.title = BookshelfDisplaySettingsStore.companionSectionTitleText(this.initialTitle);
  }

  save(): void {
    const title = this.title.trim();
    // 与默认文案相同就存空串，以后默认文案调整时跟着变。
    this.onSave(title === BookshelfDisplaySettingsStore.DEFAULT_COMPANION_SECTION_TITLE ? '' : title);
  }

  build() {
    Column() {
      Text('编辑书架标题')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.XL })

      // 预览与书架上的样式一致。
      Text(BookshelfDisplaySettingsStore.companionSectionTitleText(this.title))
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding(AppSpacing.LG)
        .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
        .borderRadius(ThemeRuntime.mediumRadius())

      TextInput({ placeholder: `留空则显示“${BookshelfDisplaySettingsStore.DEFAULT_COMPANION_SECTION_TITLE}”`, text: this.title })
        .width('100%')
        .height(44)
        .margin({ top: AppSpacing.LG })
        .maxLength(BookshelfDisplaySettingsStore.COMPANION_SECTION_TITLE_MAX_LENGTH)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .placeholderColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => {
          this.title = value;
        })

      Row({ space: 10 }) {
        Button('恢复默认')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .onClick(() => {
            this.title = BookshelfDisplaySettingsStore.DEFAULT_COMPANION_SECTION_TITLE;
          })
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .onClick(() => this.onCancel())
        Button('保存')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(ThemeRuntime.buttonColor(this.appDarkMode))
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => this.save())
      }
      .width('100%')
      .margin({ top: AppSpacing.XL })
    }
    .padding(AppSpacing.XXL)
  }
}
