import { router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { PageScaffold } from '../components/common/PageScaffold';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { WebParseNoticeItem, WebParseSettingsStore } from '../utils/WebParseSettingsStore';

/**
 * 网页解析使用须知：一句引子加几条带小标题的说明。mode 为 accept 时底部有勾选和“同意并开启”，同意后才打开开关；
 * 为 view 时只读。已开启但须知待确认的用户（升级或须知改版）还可以在这里直接关闭。
 */
@Entry
@Component
struct WebParseNoticePage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('webParseEnabled') webParseEnabled: boolean = false;
  @State acceptMode: boolean = false;
  @State checked: boolean = false;
  @State saving: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string> | undefined;
    this.acceptMode = !!params && params['mode'] === 'accept';
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Stack() {
      PageScaffold({ title: this.acceptMode && !this.webParseEnabled ?
        WebParseSettingsStore.NOTICE_TITLE_BEFORE_ENABLE : WebParseSettingsStore.NOTICE_TITLE, content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    Text(WebParseSettingsStore.NOTICE_INTRO)
      .fontSize(AppFontSize.BODY)
      .lineHeight(22)
      .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })

    Column({ space: AppSpacing.XL }) {
      ForEach(WebParseSettingsStore.NOTICE_ITEMS, (item: WebParseNoticeItem) => {
        Column({ space: AppSpacing.XS }) {
          Text(item.title)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
            .width('100%')
          Text(item.body)
            .fontSize(AppFontSize.BODY)
            .lineHeight(22)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (item: WebParseNoticeItem) => item.title)
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.LG })
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))

    if (this.acceptMode) {
      Row({ space: AppSpacing.MD }) {
        Checkbox()
          .select(this.checked)
          .selectedColor(ThemeRuntime.accentColor(this.appDarkMode))
          .onChange((value: boolean) => { this.checked = value; })
          .accessibilityText(WebParseSettingsStore.NOTICE_CHECK_LABEL)
        Text(WebParseSettingsStore.NOTICE_CHECK_LABEL)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .layoutWeight(1)
          .onClick(() => { this.checked = !this.checked; })
      }
      .width('calc(100% - 32vp)')
      .margin({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XL })
      .alignItems(VerticalAlign.Center)

      Button(this.webParseEnabled ? '同意并继续使用' : '同意并开启')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.appDarkMode)))
        .backgroundColor(ThemeRuntime.buttonColor(this.appDarkMode))
        .width('calc(100% - 32vp)')
        .height(44)
        .margin({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XL })
        .opacity(this.checked && !this.saving ? 1 : 0.4)
        .onClick(() => this.accept())

      if (this.webParseEnabled) {
        Button('暂不同意，先关闭')
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .backgroundColor(Color.Transparent)
          .width('calc(100% - 32vp)')
          .height(44)
          .margin({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM })
          .onClick(() => this.decline())
      }
    }
  }

  async accept(): Promise<void> {
    if (this.saving) return;
    if (!this.checked) {
      HdsFeedback.showToast(`请先勾选“${WebParseSettingsStore.NOTICE_CHECK_LABEL}”`);
      return;
    }
    this.saving = true;
    try {
      await WebParseSettingsStore.accept(getContext(this));
      // 书架按这个时间戳重新读取，之前隐藏的在线书回到书架。
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      router.back();
    } catch (error) {
      console.warn('保存网页解析开关失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    } finally {
      this.saving = false;
    }
  }

  async decline(): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    try {
      await WebParseSettingsStore.disable(getContext(this));
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      router.back();
    } catch (error) {
      console.warn('保存网页解析开关失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    } finally {
      this.saving = false;
    }
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
  }
}
