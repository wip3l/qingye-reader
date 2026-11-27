import { router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { PageScaffold } from '../components/common/PageScaffold';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PluginFeatureStore } from '../utils/PluginFeatureStore';
import { WebParseNoticeItem } from '../utils/WebParseSettingsStore';

/**
 * 插件使用须知，版式与网页解析须知一致。mode 为 accept 时底部有勾选、“同意并开启”和“暂不同意，先关闭”，
 * 同意后才打开“实验室 › 插件”总开关；为 view 时只读。
 */
@Entry
@Component
struct PluginNoticePage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('pluginFeatureEnabled') pluginFeatureEnabled: boolean = false;
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
      PageScaffold({ title: this.acceptMode && !this.pluginFeatureEnabled ?
        PluginFeatureStore.NOTICE_TITLE_BEFORE_ENABLE : PluginFeatureStore.NOTICE_TITLE, content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    Text(PluginFeatureStore.NOTICE_INTRO)
      .fontSize(AppFontSize.BODY)
      .lineHeight(22)
      .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })

    Column({ space: AppSpacing.XL }) {
      ForEach(PluginFeatureStore.NOTICE_ITEMS, (item: WebParseNoticeItem) => {
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

    if (this.acceptMode && !this.pluginFeatureEnabled) {
      Row({ space: AppSpacing.MD }) {
        Checkbox()
          .select(this.checked)
          .selectedColor(ThemeRuntime.accentColor(this.appDarkMode))
          .onChange((value: boolean) => { this.checked = value; })
          .accessibilityText(PluginFeatureStore.NOTICE_CHECK_LABEL)
        Text(PluginFeatureStore.NOTICE_CHECK_LABEL)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .layoutWeight(1)
          .onClick(() => { this.checked = !this.checked; })
      }
      .width('calc(100% - 32vp)')
      .margin({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XL })
      .alignItems(VerticalAlign.Center)

      Button('同意并开启')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.appDarkMode)))
        .backgroundColor(ThemeRuntime.buttonColor(this.appDarkMode))
        .width('calc(100% - 32vp)')
        .height(44)
        .margin({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XL })
        .opacity(this.checked && !this.saving ? 1 : 0.4)
        .onClick(() => this.accept())

      Button('暂不同意，先关闭')
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .backgroundColor(Color.Transparent)
        .width('calc(100% - 32vp)')
        .height(44)
        .margin({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.XXL })
        .onClick(() => router.back())
    }
  }

  async accept(): Promise<void> {
    if (this.saving) return;
    if (!this.checked) {
      HdsFeedback.showToast(`请先勾选“${PluginFeatureStore.NOTICE_CHECK_LABEL}”`);
      return;
    }
    this.saving = true;
    try {
      await PluginFeatureStore.accept(getContext(this));
      router.back();
    } catch (error) {
      console.warn('保存插件开关失败:', error);
      HdsFeedback.showToast('保存失败，请重试');
    } finally {
      this.saving = false;
    }
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
  }
}
