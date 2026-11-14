import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { fileUri } from '../platform/FileUri';
import { shareFiles } from '../platform/Share';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { CrashReportStore, CrashReportSummary } from '../utils/CrashReportStore';

/** 单条崩溃记录：完整文本（可复制）、分享为 txt、删除。 */
@Entry
@Component
struct CrashReportDetailPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @State summary: CrashReportSummary | null = null;
  @State reportText: string = '';
  private reportId: string = '';
  /** 很长的系统日志一次性塞进 Text 会卡住排版，页面里只显示开头，分享的文件是全文。 */
  private static readonly DISPLAY_LIMIT: number = 60000;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string> | undefined;
    this.reportId = params?.id || '';
    this.summary = CrashReportStore.summaryOf(this.reportId);
    const text = CrashReportStore.reportText(this.reportId);
    this.reportText = text.length > CrashReportDetailPage.DISPLAY_LIMIT ?
      `${text.substring(0, CrashReportDetailPage.DISPLAY_LIMIT)}\n\n…（内容较长，完整记录请分享后查看）` : text;
    if (AppStorage.get<string>(CrashReportStore.KEY_PENDING_NOTICE) === this.reportId) {
      CrashReportStore.clearPendingNotice();
    }
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '崩溃详情', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    Column({ space: AppSpacing.LG }) {
      if (this.summary === null) {
        Text('这条崩溃记录已不存在')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 48 })
      } else {
        Column({ space: AppSpacing.SM }) {
          Text(`${CrashReportStore.kindLabel(this.summary.kind)} · ${CrashReportStore.formatTime(this.summary.time)}`)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
            .width('100%')
          Text(this.summary.title)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .opacity(0.85)
            .lineHeight(20)
            .width('100%')
          Row({ space: AppSpacing.MD }) {
            this.actionButton('分享给开发者', this.accentColor(), () => this.share())
            this.actionButton('删除', ThemeRuntime.dangerColor(this.appDarkMode), () => this.confirmDelete())
          }
          .width('100%')
          .margin({ top: AppSpacing.SM })
        }
        .width('100%')
        .padding(AppSpacing.XL)
        .backgroundColor(this.cardColor())
        .borderRadius(ThemeRuntime.cardRadius())

        Text(this.reportText)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.primaryTextColor())
          .lineHeight(18)
          .width('100%')
          .copyOption(CopyOptions.LocalDevice)
          .padding(AppSpacing.XL)
          .backgroundColor(this.cardColor())
          .borderRadius(ThemeRuntime.cardRadius())
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.XXXL })
  }

  @Builder
  actionButton(label: string, color: string, action: () => void) {
    Text(label)
      .fontSize(AppFontSize.BODY)
      .fontColor(color)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
      .borderRadius(ThemeRuntime.mediumRadius())
      .backgroundColor(this.softColor())
      .onClick(() => action())
  }

  async share(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const path = CrashReportStore.exportText(context, this.reportId);
      const utd = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension('.txt',
        uniformTypeDescriptor.UniformDataType.PLAIN_TEXT);
      await shareFiles(context, [{ path: path, utd: utd }], true);
    } catch (error) {
      console.warn('分享崩溃记录失败:', error);
      HdsFeedback.showToast('分享失败，请稍后再试');
    }
  }

  async confirmDelete(): Promise<void> {
    const result = await promptAction.showDialog({
      title: '删除崩溃记录',
      message: '确定删除这条崩溃记录吗？',
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '删除', color: ThemeRuntime.dangerColor(this.appDarkMode) }
      ]
    });
    if (result.index !== 1) return;
    CrashReportStore.remove(this.reportId);
    router.back();
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  softColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
