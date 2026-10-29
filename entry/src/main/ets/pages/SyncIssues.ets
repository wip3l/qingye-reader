import { promptAction, router } from '@kit.ArkUI';
import { BookSource } from '@legado/sourceengine';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { CloudSyncIssue, CloudSyncIssueStore } from '../account/CloudSyncIssueStore';
import { AppDatabase } from '../model/data/AppDatabase';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ExploreResultCache } from '../utils/ExploreResultCache';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { CollapsingHeader } from '../utils/CollapsingHeader';

/** 问题记录里书源在本机的当前状态，决定能否打开或删除。 */
class IssueSourceInfo {
  url: string = '';
  locked: boolean = false;
  native: boolean = false;
}

@Entry
@Component
struct SyncIssuesPage {
  @State headerCollapse: number = 0;
  private headerScroller: Scroller = new Scroller();
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State issues: CloudSyncIssue[] = [];
  @State sources: IssueSourceInfo[] = [];
  @State loading: boolean = true;
  @State errorMessage: string = '';
  private userId: string = '';

  aboutToAppear(): void {
    this.loadIssues();
    this.syncBars();
  }

  onPageShow(): void {
    // 从书源编辑页返回时书源可能已被删除或改名，重新读取状态。
    if (!this.loading) this.loadIssues();
    this.syncBars();
  }

  async loadIssues(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    try {
      await AccountSessionStore.load(getContext(this));
      if (!AccountSessionStore.isLoggedIn()) {
        this.issues = [];
        this.errorMessage = '请先登录华为账号';
        return;
      }
      this.userId = AccountSessionStore.account().userId;
      const issues = await CloudSyncIssueStore.load(getContext(this), this.userId);
      this.sources = await this.loadSources(issues);
      this.issues = issues;
    } catch (e) {
      this.errorMessage = e instanceof Error ? e.message : String(e);
    } finally {
      this.loading = false;
    }
  }

  async loadSources(issues: CloudSyncIssue[]): Promise<IssueSourceInfo[]> {
    const result: IssueSourceInfo[] = [];
    const urls = issues.filter((issue: CloudSyncIssue) => !!issue.sourceUrl)
      .map((issue: CloudSyncIssue) => issue.sourceUrl);
    if (urls.length === 0) return result;
    const db = AppDatabase.getInstance();
    await db.initWithContext(getContext(this));
    for (const url of Array.from(new Set<string>(urls))) {
      const source: BookSource | null = await db.getBookSource(url);
      if (!source) continue;
      const info = new IssueSourceInfo();
      info.url = url;
      info.locked = source.isLocked;
      info.native = source.sourceFormat === 'native';
      result.push(info);
    }
    return result;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '同步问题', scrollable: false, externalCollapse: this.headerCollapse, edgeToEdge: true, content: () => {
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

      if (this.loading && this.issues.length === 0) {
        ListItem() {
          Column({ space: AppSpacing.LG }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.accentColor())
            Text('正在读取同步问题…')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
          }
          .width('100%')
          .padding({ top: 48 })
        }
      } else if (this.errorMessage) {
        ListItem() {
          Text(this.errorMessage)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding(AppSpacing.XXL)
            .margin({ top: AppSpacing.LG })
            .borderRadius(ThemeRuntime.cardRadius())
            .backgroundColor(this.cardColor())
        }
      } else if (this.issues.length === 0) {
        ListItem() {
          Text('暂无同步问题。同步失败、云端拒收的数据（如超出限额的书源）以及本地书籍、字体上传失败都会记录在这里。')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .lineHeight(20)
            .width('100%')
            .padding(AppSpacing.XL)
            .margin({ top: AppSpacing.LG })
            .borderRadius(ThemeRuntime.cardRadius())
            .backgroundColor(this.cardColor())
        }
      } else {
        ListItem() {
          Text(`共 ${this.issues.length} 条记录，按最近出现时间排列`)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .width('100%')
            .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: AppSpacing.LG })
        }

        ForEach(this.issues, (issue: CloudSyncIssue) => {
          ListItem() {
            this.issueCard(issue)
          }
        }, (issue: CloudSyncIssue) => `${issue.key}:${issue.lastAt}:${issue.count}:${this.sourceState(issue)}`)

        ListItem() {
          Text('同一问题再次出现时只更新时间和次数。问题处理后，记录不会自动消失，可以逐条移除或用右上角按钮全部清除。')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .lineHeight(18)
            .width('100%')
            .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: AppSpacing.XS })
        }
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
    if (this.issues.length > 0) {
      ImmersiveHeaderAction({
        icon: $r('sys.symbol.trash'),
        tint: this.accentColor(),
        accessibilityLabel: '清除全部记录',
        onTap: () => this.confirmClearAll()
      })
        .margin({ right: AppSpacing.XL })
    }
  }

  @Builder
  issueCard(issue: CloudSyncIssue) {
    Column({ space: AppSpacing.SM }) {
      Row({ space: AppSpacing.MD }) {
        Text(issue.title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(this.kindLabel(issue))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.kindColor(issue))
          .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
          .borderRadius(ThemeRuntime.mediumRadius())
          .backgroundColor(this.softColor())
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Text(issue.message)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.primaryTextColor())
        .opacity(0.85)
        .lineHeight(20)
        .width('100%')

      if (issue.bytes > 0) {
        Text(`上传大小：${this.sizeText(issue.bytes)}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
      }
      if (issue.sourceUrl) {
        Text(`书源地址：${issue.sourceUrl}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      Text(this.timeText(issue))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .lineHeight(18)
        .width('100%')

      Row({ space: AppSpacing.SM }) {
        if (issue.sourceUrl) {
          if (this.sourceState(issue) === 'missing') {
            Text('本机已没有这个书源')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
              .layoutWeight(1)
          } else {
            this.cardButton('打开书源', this.accentColor(), () => this.openSource(issue))
            this.cardButton('删除书源', ThemeRuntime.dangerColor(this.appDarkMode), () => this.confirmDeleteSource(issue))
            Blank()
          }
        } else {
          Blank()
        }
        this.cardButton('移除记录', this.subTextColor(), () => this.removeIssue(issue))
      }
      .width('100%')
      .margin({ top: AppSpacing.XS })
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.MD })
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
  }

  @Builder
  cardButton(label: string, color: string, action: () => void) {
    Text(label)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(color)
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.SM, bottom: AppSpacing.SM })
      .borderRadius(ThemeRuntime.mediumRadius())
      .backgroundColor(this.softColor())
      .onClick(() => action())
  }

  sourceState(issue: CloudSyncIssue): string {
    if (!issue.sourceUrl) return '';
    return this.sourceInfo(issue) ? 'present' : 'missing';
  }

  sourceInfo(issue: CloudSyncIssue): IssueSourceInfo | undefined {
    return this.sources.find((item: IssueSourceInfo) => item.url === issue.sourceUrl);
  }

  openSource(issue: CloudSyncIssue): void {
    const info = this.sourceInfo(issue);
    if (!info) return;
    if (info.locked) {
      HdsFeedback.showToast('请先在书源管理中解锁书源');
      return;
    }
    router.pushUrl({
      url: info.native ? 'pages/NativeSourceEdit' : 'pages/BookSourceEdit',
      params: { bookSourceUrl: info.url }
    });
  }

  async confirmDeleteSource(issue: CloudSyncIssue): Promise<void> {
    const info = this.sourceInfo(issue);
    if (!info) return;
    if (info.locked) {
      HdsFeedback.showToast('锁定的书源不能删除');
      return;
    }
    const result = await promptAction.showDialog({
      title: '删除书源',
      message: `确定从本机删除“${this.issueTarget(issue)}”吗？删除后不会再尝试上传它。`,
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '删除', color: ThemeRuntime.dangerColor(this.appDarkMode) }
      ]
    });
    if (result.index !== 1) return;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.deleteBookSource(info.url);
      await ExploreResultCache.clearSource(getContext(this), info.url);
      this.sources = this.sources.filter((item: IssueSourceInfo) => item.url !== info.url);
      HdsFeedback.showToast('书源已删除');
    } catch (e) {
      console.error('删除书源失败:', e);
      HdsFeedback.showToast('删除书源失败');
    }
  }

  async removeIssue(issue: CloudSyncIssue): Promise<void> {
    try {
      await CloudSyncIssueStore.remove(getContext(this), this.userId, issue.key);
      this.issues = this.issues.filter((item: CloudSyncIssue) => item.key !== issue.key);
    } catch (e) {
      HdsFeedback.showToast('移除记录失败');
    }
  }

  async confirmClearAll(): Promise<void> {
    const result = await promptAction.showDialog({
      title: '清除同步问题',
      message: '确定清除全部同步问题记录吗？问题本身不会因此解决，再次出现时会重新记录。',
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '清除', color: ThemeRuntime.dangerColor(this.appDarkMode) }
      ]
    });
    if (result.index !== 1) return;
    try {
      await CloudSyncIssueStore.clear(getContext(this), this.userId);
      this.issues = [];
      HdsFeedback.showToast('已清除同步问题记录');
    } catch (e) {
      HdsFeedback.showToast('清除失败');
    }
  }

  issueTarget(issue: CloudSyncIssue): string {
    const match = /“(.+)”/.exec(issue.title);
    return match ? match[1] : '这个书源';
  }

  kindLabel(issue: CloudSyncIssue): string {
    if (issue.kind === CloudSyncIssueStore.KIND_BOOK_SOURCE) return '书源';
    if (issue.kind === CloudSyncIssueStore.KIND_REJECTED) return '云端拒收';
    if (issue.kind === CloudSyncIssueStore.KIND_FILE) return '文件同步';
    return '同步失败';
  }

  kindColor(issue: CloudSyncIssue): string {
    return issue.kind === CloudSyncIssueStore.KIND_SYNC ? ThemeRuntime.dangerColor(this.appDarkMode) :
      this.accentColor();
  }

  sizeText(bytes: number): string {
    if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(2)} MiB`;
    return `${(bytes / 1024).toFixed(1)} KiB`;
  }

  timeText(issue: CloudSyncIssue): string {
    const last = `最近：${new Date(issue.lastAt).toLocaleString()}`;
    if (issue.count <= 1) return last;
    return `${last}\n首次：${new Date(issue.firstAt).toLocaleString()} · 共出现 ${issue.count} 次`;
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
