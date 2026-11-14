import { BookSource } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { SearchExploreSettings, SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { CollapsingHeader } from '../utils/CollapsingHeader';

@Entry
@Component
struct ExploreSourceSortPage {
  @State headerCollapse: number = 0;
  private headerScroller: Scroller = new Scroller();
  @StorageLink('searchExploreSourceSort') searchExploreSourceSort: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State sources: BookSource[] = [];
  @State isLoading: boolean = false;

  aboutToAppear(): void {
    this.syncBars();
    this.loadSources();
  }

  onPageShow(): void {
    this.syncBars();
    this.loadSources();
  }

  async loadSources(): Promise<void> {
    this.isLoading = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const allSources = await db.getAllBookSources();
      const enabledExploreSources = allSources.filter((source: BookSource) =>
        source.enabledExplore && !!(source.exploreUrl || '').trim());
      this.sources = this.applySavedOrder(enabledExploreSources);
      this.saveOrder(false);
    } catch (e) {
      console.error('加载发现书源排序失败:', e);
      HdsFeedback.showToast('加载书源失败');
    } finally {
      this.isLoading = false;
    }
  }

  applySavedOrder(sourceList: BookSource[]): BookSource[] {
    const order = this.sortedSourceUrls();
    if (order.length === 0) {
      return sourceList;
    }
    const result: BookSource[] = [];
    for (const url of order) {
      const source = sourceList.find((item: BookSource) => item.bookSourceUrl === url);
      if (source && !result.some((item: BookSource) => item.bookSourceUrl === source.bookSourceUrl)) {
        result.push(source);
      }
    }
    for (const source of sourceList) {
      if (!result.some((item: BookSource) => item.bookSourceUrl === source.bookSourceUrl)) {
        result.push(source);
      }
    }
    return result;
  }

  sortedSourceUrls(): string[] {
    return (this.searchExploreSourceSort || '').split('\n')
      .map((url: string) => url.trim())
      .filter((url: string) => !!url);
  }

  build() {
    Stack() {
      PageScaffold({ title: '书源排序', scrollable: false, externalCollapse: this.headerCollapse, content: () => {
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
    if (this.isLoading) {
      Column() {
        LoadingProgress()
          .width(40)
          .height(40)
        Text('加载中...')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .margin({ top: AppSpacing.MD })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.sources.length === 0) {
      Column() {
        Text('暂无启用发现的书源')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.subTextColor())
        Text('请先在书源管理中启用发现')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .margin({ top: AppSpacing.MD })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ scroller: this.headerScroller, space: AppSpacing.MD }) {
        ForEach(this.sources, (source: BookSource, index: number) => {
          ListItem() {
            Row() {
              Text('☰')
                .fontSize(AppFontSize.SUBTITLE)
                .fontColor(this.subTextColor())
                .width(24)
                .textAlign(TextAlign.Center)
                .margin({ right: AppSpacing.XS })

              Text(`${index + 1}`)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.subTextColor())
                .width(28)
                .textAlign(TextAlign.Center)

              Column() {
                Text(source.bookSourceName || '未命名书源')
                  .fontSize(AppFontSize.BODY_LARGE)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.primaryTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(source.bookSourceUrl)
                  .fontSize(AppFontSize.CAPTION)
                  .fontColor(this.subTextColor())
                  .margin({ top: AppSpacing.XS })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text('↑')
                .width(36)
                .height(32)
                .fontSize(AppFontSize.SUBTITLE)
                .fontColor(index > 0 ? this.primaryTextColor() : this.disabledTextColor())
                .textAlign(TextAlign.Center)
                .backgroundColor(index > 0 ? this.inputColor() : this.disabledButtonColor())
                .borderRadius(16)
                .onClick(() => {
                  if (index > 0) {
                    this.moveSource(index, -1);
                  }
                })

              Text('↓')
                .width(36)
                .height(32)
                .fontSize(AppFontSize.SUBTITLE)
                .margin({ left: AppSpacing.SM })
                .fontColor(index < this.sources.length - 1 ? this.primaryTextColor() : this.disabledTextColor())
                .textAlign(TextAlign.Center)
                .backgroundColor(index < this.sources.length - 1 ? this.inputColor() : this.disabledButtonColor())
                .borderRadius(16)
                .onClick(() => {
                  if (index < this.sources.length - 1) {
                    this.moveSource(index, 1);
                  }
                })
            }
            .width('100%')
            .padding(AppSpacing.LG)
            .backgroundColor(this.cardColor())
            .borderRadius(ThemeRuntime.cardRadius())
          }
        }, (source: BookSource) => source.bookSourceUrl)
          // onMove 由 List 原地抬起条目、挤压让位并在边缘自动滚动；拖动中只改顺序，松手再保存。
          .onMove((from: number, to: number) => {
            this.moveSourceTo(from, to, false);
          }, {
            onDrop: (_index: number) => this.saveOrder(false)
          })

        ListItem() {
          Row()
            .height(Math.max(20, this.navBarHeight + 12))
        }
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .layoutWeight(1)
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.XL })
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
  }

  moveSource(index: number, direction: number): void {
    const target = index + direction;
    if (index < 0 || index >= this.sources.length || target < 0 || target >= this.sources.length) {
      return;
    }
    const next = this.sources.slice();
    const current = next[index];
    next[index] = next[target];
    next[target] = current;
    this.sources = next;
    this.saveOrder(true);
  }

  moveSourceTo(from: number, to: number, save: boolean = true): boolean {
    if (from < 0 || from >= this.sources.length || to < 0 || to >= this.sources.length || from === to) {
      return false;
    }
    const next = this.sources.slice();
    const moved = next.splice(from, 1)[0];
    next.splice(to, 0, moved);
    this.sources = next;
    if (save) this.saveOrder(false);
    return true;
  }

  saveOrder(showToast: boolean): void {
    this.searchExploreSourceSort = this.sources
      .map((source: BookSource) => source.bookSourceUrl)
      .filter((url: string) => !!url)
      .join('\n');
    SearchExploreSettingsStore.load(getContext(this)).then((settings: SearchExploreSettings) => {
      settings.sourceSortRaw = this.searchExploreSourceSort;
      SearchExploreSettingsStore.applyToStorage(settings);
      return SearchExploreSettingsStore.save(getContext(this), settings);
    }).then(() => {
      if (showToast) {
        HdsFeedback.showToast('排序已保存');
      }
    }).catch((e: Error) => {
      console.warn('保存发现书源排序失败:', e);
      if (showToast) {
        HdsFeedback.showToast('保存排序失败');
      }
    });
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  disabledTextColor(): string {
    return this.appDarkMode ? '#5D626B' : '#C0C4CC';
  }

  disabledButtonColor(): string {
    return this.appDarkMode ? '#202329' : '#ECEFF3';
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

}
