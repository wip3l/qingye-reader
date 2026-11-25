import { promptAction, router } from '@kit.ArkUI';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { CrashReportStore, CrashReportSummary } from '../utils/CrashReportStore';
import { ThemedDialog } from '../utils/ThemedDialog';

/** 本机的崩溃记录列表（闪退、卡死、被系统结束），点开看详情并分享给开发者。 */
@Entry
@Component
struct CrashReportsPage {
  @State headerCollapse: number = 0;
  private headerScroller: Scroller = new Scroller();
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State reports: CrashReportSummary[] = [];

  aboutToAppear(): void {
    this.reload();
    this.syncBars();
  }

  onPageShow(): void {
    // 详情页里删除后返回，或启动后系统才把事件送达。
    this.reload();
    this.syncBars();
  }

  reload(): void {
    this.reports = CrashReportStore.list();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '崩溃记录', scrollable: false, externalCollapse: this.headerCollapse, edgeToEdge: true,
        content: () => {
          this.pageContent()
        }, actions: () => {
          this.titleActions()
        } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    List({ scroller: this.headerScroller, space: AppSpacing.MD }) {
      ListItem() {
        Row()
          .width('100%')
          .height(PageScaffold.BAR_HEIGHT + this.statusBarHeight)
          .hitTestBehavior(HitTestMode.None)
      }

      ListItem() {
        Text('轻页闪退、卡死或在前台被系统结束后，下次启动时会在这里留下记录。记录只保存在本机，' +
          '可以点开后分享给开发者帮助排查。记录里可能有正在阅读的书名、网址等信息，分享前可以先看一看。')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .lineHeight(20)
          .width('100%')
          .padding(AppSpacing.XL)
          .margin({ top: AppSpacing.LG })
          .borderRadius(ThemeRuntime.cardRadius())
          .backgroundColor(this.cardColor())
      }

      if (this.reports.length === 0) {
        ListItem() {
          Text('暂无崩溃记录')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding({ top: 48 })
        }
      } else {
        ForEach(this.reports, (report: CrashReportSummary) => {
          ListItem() {
            this.reportCard(report)
          }
        }, (report: CrashReportSummary) => report.id)
      }

      ListItem() {
        Row()
          .width('100%')
          .height(32 + this.navBarHeight)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .onDidScroll((yOffset: number) => {
      this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
        this.headerScroller.currentOffset().yOffset);
    })
    .onScrollStop(() => {
      const target = CollapsingHeader.settle(this.headerCollapse, this.headerScroller.currentOffset().yOffset);
      if (target !== this.headerCollapse) {
        animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
          this.headerCollapse = target;
        });
      }
    })
  }

  @Builder
  titleActions() {
    if (this.reports.length > 0) {
      ImmersiveHeaderAction({
        icon: $r('sys.symbol.trash'),
        tint: this.accentColor(),
        accessibilityLabel: '清除全部崩溃记录',
        onTap: () => this.confirmClearAll()
      })
        .margin({ right: AppSpacing.XL })
    }
  }

  @Builder
  reportCard(report: CrashReportSummary) {
    Column({ space: AppSpacing.SM }) {
      Row({ space: AppSpacing.MD }) {
        Text(CrashReportStore.formatTime(report.time))
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(CrashReportStore.kindLabel(report.kind))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(report.kind === 'killed' ? this.accentColor() : ThemeRuntime.dangerColor(this.appDarkMode))
          .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
          .borderRadius(ThemeRuntime.mediumRadius())
          .backgroundColor(this.softColor())
      }
      .width('100%')
      Text(report.title)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.primaryTextColor())
        .opacity(0.85)
        .lineHeight(20)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(`版本 ${report.version || '未知'} · ${report.foreground ? '前台' : '后台'}`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    .onClick(() => {
      router.pushUrl({ url: 'pages/CrashReportDetail', params: { id: report.id } }).catch(() => {});
    })
  }

  async confirmClearAll(): Promise<void> {
    const result = await ThemedDialog.showDialog(this.getUIContext(), {
      title: '清除崩溃记录',
      message: '确定清除全部崩溃记录吗？清除后无法恢复。',
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '清除', color: ThemeRuntime.dangerColor(this.appDarkMode) }
      ]
    });
    if (result.index !== 1) return;
    CrashReportStore.clear();
    this.reload();
    HdsFeedback.showToast('已清除崩溃记录');
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
