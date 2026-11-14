import pasteboard from '@ohos.pasteboard';
import { ScriptProbeResult, ScriptThreadProbe } from '@legado/sourceengine';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';

/** 原生书源脚本阶段 0：后台脚本线程的真机验证页。 */
@Entry
@Component
struct ScriptThreadProbePage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @State results: ScriptProbeResult[] = [];
  @State running: boolean = false;
  @State httpUrl: string = ScriptThreadProbe.DEFAULT_HTTP_URL;
  @State notice: string = '';

  aboutToAppear(): void {
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '后台脚本线程验证', content: () => {
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
      Column({ space: AppSpacing.MD }) {
        Text('QuickJS 在后台线程运行，脚本里同步调用宿主（网络、选择器等由主线程代办）。逐项检查耗时、取消、超时、内存和并发；最后几项验证主线程上的书源 JS 函数库。')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
        Text('真实请求地址').fontSize(AppFontSize.BODY).fontColor(this.primaryTextColor())
        TextInput({ text: this.httpUrl, placeholder: ScriptThreadProbe.DEFAULT_HTTP_URL })
          .fontSize(AppFontSize.BODY)
          .enabled(!this.running)
          .onChange((value: string): void => {
            this.httpUrl = value;
          })
      }
      .alignItems(HorizontalAlign.Start)
      .padding(AppSpacing.LG)
      .width('calc(100% - 24vp)')
      .borderRadius(16)
      .backgroundColor(this.cardColor())

      Button(this.running ? `运行中（已完成 ${this.results.length} 项）` : '开始验证')
        .type(ButtonType.Capsule)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(ThemeRuntime.onAccentColor())
        .backgroundColor(ThemeRuntime.accentColor(this.appDarkMode))
        .width('calc(100% - 24vp)')
        .height(46)
        .enabled(!this.running)
        .onClick((): void => this.start())

      if (this.results.length > 0) {
        Column({ space: AppSpacing.MD }) {
          Text(this.summary())
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
          ForEach(this.results, (item: ScriptProbeResult) => {
            Column({ space: 4 }) {
              Text(`${item.passed ? '✓' : '✗'} ${item.name}`)
                .fontSize(AppFontSize.BODY)
                .fontWeight(FontWeight.Medium)
                .fontColor(item.passed ? this.primaryTextColor() : ThemeRuntime.dangerColor(this.appDarkMode))
              Text(item.detail)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor())
                .copyOption(CopyOptions.LocalDevice)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }, (item: ScriptProbeResult, index: number) => `${index}-${item.name}`)
        }
        .alignItems(HorizontalAlign.Start)
        .padding(AppSpacing.LG)
        .width('calc(100% - 24vp)')
        .borderRadius(16)
        .backgroundColor(this.cardColor())

        if (!this.running) {
          Button('复制结果')
            .type(ButtonType.Capsule)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.cardColor())
            .width('calc(100% - 24vp)')
            .height(46)
            .onClick((): void => {
              this.copyReport();
            })
        }
      }
      if (this.notice) {
        Text(this.notice).fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor())
      }
    }
    .width('100%')
    .padding({ top: AppSpacing.LG, bottom: AppSpacing.LG })
  }

  private start(): void {
    this.running = true;
    this.results = [];
    this.notice = '';
    const url = (this.httpUrl || '').trim() || ScriptThreadProbe.DEFAULT_HTTP_URL;
    ScriptThreadProbe.run((result: ScriptProbeResult): void => {
      this.results = this.results.concat([result]);
    }, url).then((): void => {
      this.running = false;
    }).catch((error: Error): void => {
      this.running = false;
      this.notice = `验证中断：${error.message || error}`;
    });
  }

  private async copyReport(): Promise<void> {
    try {
      const board = pasteboard.getSystemPasteboard();
      await board.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, ScriptThreadProbe.report(this.results)));
      this.notice = '已复制';
    } catch (error) {
      this.notice = `复制失败：${(error as Error).message || error}`;
    }
  }

  private summary(): string {
    const passed = this.results.filter((item: ScriptProbeResult): boolean => item.passed).length;
    return `${passed}/${this.results.length} 通过`;
  }

  private syncBars(): void { syncSystemBars(getContext(this), this.appDarkMode, this.pageColor()); }
  private pageColor(): string { return ThemeRuntime.pageColor(this.appDarkMode); }
  private cardColor(): string { return ThemeRuntime.cardColor(this.appDarkMode); }
  private primaryTextColor(): string { return ThemeRuntime.primaryTextColor(this.appDarkMode); }
  private subTextColor(): string { return ThemeRuntime.subTextColor(this.appDarkMode); }
}
