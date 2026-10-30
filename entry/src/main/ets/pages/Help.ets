import { common } from '@kit.AbilityKit';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { CommunityGroup } from '../utils/CommunityGroup';
import { HelpBlockView } from '../components/help/HelpBlockView';
import {
  HelpAction, HelpData, HelpManual, HelpQuickStep, HelpSearchResult, HelpSection, HelpTopic
} from '../utils/HelpManual';

/**
 * 使用说明首页：搜索、新手上手、常见问题和按功能分组的专题入口。专题内容在 HelpTopic 页展示。
 * 调用方可传 anchor（说明书的章节或小节 id），打开后直接转到对应专题。
 */
@Entry
@Component
struct HelpPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State headerCollapse: number = 0;
  @State data: HelpData | null = null;
  @State loadError: string = '';
  @State keyword: string = '';
  @State results: HelpSearchResult[] = [];
  @State expandedFaq: string = '';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.syncBars();
    HelpManual.load(getContext(this)).then((data: HelpData) => {
      this.data = data;
    }).catch((error: Error) => {
      this.loadError = `说明读取失败：${error.message}`;
    });
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Stack() {
      PageScaffold({ title: '使用说明', scrollable: false, edgeToEdge: true, externalCollapse: this.headerCollapse,
        content: () => {
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
    List({ scroller: this.scroller }) {
      ListItem() {
        Row()
          .width('100%')
          .height(PageScaffold.BAR_HEIGHT + this.statusBarHeight)
          .hitTestBehavior(HitTestMode.None)
      }

      ListItem() {
        this.searchField()
      }

      if (this.data) {
        if (this.keyword.trim()) {
          ListItem() {
            this.searchResults()
          }
        } else {
          ListItem() {
            this.homeContent(this.data)
          }
        }
      } else if (this.loadError) {
        ListItem() {
          Text(this.loadError)
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 48 })
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
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    .onDidScroll((yOffset: number) => {
      this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
        this.scroller.currentOffset().yOffset);
    })
    .onScrollStop(() => {
      const target = CollapsingHeader.settle(this.headerCollapse, this.scroller.currentOffset().yOffset);
      if (target !== this.headerCollapse) {
        animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
          this.headerCollapse = target;
        });
      }
    })
  }

  @Builder
  searchField() {
    Row({ space: AppSpacing.MD }) {
      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([this.subTextColor()])
          .margin({ left: AppSpacing.LG })
          .hitTestBehavior(HitTestMode.None)
        TextInput({ placeholder: '搜索问题，如：换源、备份', text: this.keyword })
          .layoutWeight(1)
          .height(40)
          .fontSize(AppFontSize.BODY_LARGE)
          .backgroundColor(Color.Transparent)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .padding({ left: AppSpacing.MD, right: AppSpacing.LG })
          .enterKeyType(EnterKeyType.Search)
          .onChange((value: string) => {
            this.keyword = value;
            this.results = this.data ? HelpManual.search(this.data, value) : [];
          })
      }
      .height(40)
      .borderRadius(20)
      .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
      .layoutWeight(1)

      if (this.keyword) {
        Text('取消')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .height(40)
          .onClick(() => {
            this.keyword = '';
            this.results = [];
            this.getUIContext().getFocusController().clearFocus();
          })
      }
    }
    .width('100%')
    .padding({ top: AppSpacing.XS, bottom: AppSpacing.LG })
  }

  @Builder
  homeContent(data: HelpData) {
    Column() {
      this.sectionHeader('新手上手', '详细步骤', () => HelpManual.openTopic('start'))
      Scroll() {
        Row({ space: AppSpacing.MD }) {
          ForEach(data.quickStart, (step: HelpQuickStep, index: number) => {
            this.quickStepCard(step, index)
          })
        }
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
        .alignItems(VerticalAlign.Top)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('calc(100% + 32vp)')
      .margin({ left: -AppSpacing.XL })

      this.sectionHeader('常见问题', `全部 ${data.faqCount()}`, () => HelpManual.openTopic(HelpManual.FAQ_TOPIC_ID))
      Column() {
        ForEach(data.featuredFaq, (item: HelpSection, index: number) => {
          this.faqRow(data, item, index > 0)
        }, (item: HelpSection) => item.id)
      }
      .width('100%')
      .borderRadius(ThemeRuntime.largeRadius())
      .clip(true)
      .backgroundColor(this.cardColor())

      this.sectionHeader('按功能查看', '', undefined)
      Column({ space: AppSpacing.LG }) {
        ForEach(data.groups, (group: HelpTopic[]) => {
          Column() {
            ForEach(group, (topic: HelpTopic, index: number) => {
              this.navRow(HelpManual.icon(topic.icon), topic.title, topic.summary, index > 0, false,
                () => HelpManual.openTopic(topic.id))
            }, (topic: HelpTopic) => topic.id)
          }
          .width('100%')
          .borderRadius(ThemeRuntime.largeRadius())
          .clip(true)
          .backgroundColor(this.cardColor())
        })

        Column() {
          this.navRow($r('sys.symbol.checkmark_shield'), '使用须知', '', false, false,
            () => HelpManual.openTopic('legal'))
          this.navRow($r('sys.symbol.person_2'), '没找到答案？加入交流群', '', true, true, () => {
            CommunityGroup.open(getContext(this) as common.UIAbilityContext);
          })
        }
        .width('100%')
        .borderRadius(ThemeRuntime.largeRadius())
        .clip(true)
        .backgroundColor(this.cardColor())
      }
      .width('100%')

      Text(`适用于 ${data.version} · 说明更新于 ${data.updated}`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: AppSpacing.XXL })
    }
    .width('100%')
  }

  @Builder
  sectionHeader(title: string, more: string, onMore?: () => void) {
    Row() {
      Text(title)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      if (more) {
        Row({ space: AppSpacing.XXS }) {
          Text(more)
            .fontSize(AppFontSize.CAPTION + 1)
            .fontColor(this.subTextColor())
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([this.subTextColor()])
        }
        .height(32)
        .onClick(() => {
          if (onMore) onMore();
        })
      }
    }
    .width('100%')
    .height(40)
    .padding({ left: AppSpacing.XS })
    .margin({ top: AppSpacing.LG })
  }

  @Builder
  quickStepCard(step: HelpQuickStep, index: number) {
    Column({ space: AppSpacing.XS }) {
      Text(`${index + 1}`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.onAccentColor(this.accentColor()))
        .textAlign(TextAlign.Center)
        .width(22)
        .height(22)
        .borderRadius(11)
        .backgroundColor(this.accentColor())
      Text(step.title)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .margin({ top: AppSpacing.XS })
      Text(step.desc)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .lineHeight(18)
        .maxLines(2)
        .height(36)
      if (step.action) {
        Text(`${step.action.label} ›`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.accentColor())
          .margin({ top: AppSpacing.XS })
      }
    }
    .width(148)
    .padding(AppSpacing.LG)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(this.cardColor())
    .onClick(() => {
      const action: HelpAction | undefined = step.action;
      if (action) HelpManual.runAction(action);
      else HelpManual.openTopic('start');
    })
  }

  @Builder
  faqRow(data: HelpData, item: HelpSection, showDivider: boolean) {
    Column() {
      if (showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color(this.dividerColor())
          .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
      }
      Row() {
        Text(item.title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([this.subTextColor()])
          .rotate({ angle: this.expandedFaq === item.id ? 90 : 0 })
      }
      .width('100%')
      .constraintSize({ minHeight: 52 })
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
      .onClick(() => {
        animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
          this.expandedFaq = this.expandedFaq === item.id ? '' : item.id;
        });
      })

      if (this.expandedFaq === item.id) {
        Column({ space: AppSpacing.MD }) {
          HelpBlockView({ blocks: item.blocks, onLink: (url: string) => HelpManual.openLink(getContext(this), data, url) })
          if (item.action) {
            this.actionLink(item.action)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.LG })
      }
    }
    .width('100%')
  }

  @Builder
  actionLink(action: HelpAction) {
    Text(`${action.label} ›`)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.accentColor())
      .onClick(() => HelpManual.runAction(action))
  }

  @Builder
  navRow(icon: Resource, title: string, summary: string, showDivider: boolean, external: boolean, onClick: () => void) {
    Column() {
      if (showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color(this.dividerColor())
          .margin({ left: 60, right: AppSpacing.XL })
      }
      Row() {
        Stack() {
          SymbolGlyph(icon)
            .fontSize(18)
            .fontColor([this.accentColor()])
        }
        .width(32)
        .height(32)
        .borderRadius(10)
        .backgroundColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        Column({ space: AppSpacing.XXS }) {
          Text(title)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.primaryTextColor())
          if (summary) {
            Text(summary)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.subTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: AppSpacing.LG })
        SymbolGlyph(external ? $r('sys.symbol.arrow_right_up_and_square') : $r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([this.subTextColor()])
      }
      .width('100%')
      .height(summary ? 64 : 56)
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
    }
    .width('100%')
    .onClick(onClick)
  }

  @Builder
  searchResults() {
    Column() {
      Text(this.results.length > 0 ? `“${this.keyword.trim()}” 共 ${this.results.length} 条结果` : '没有找到相关说明，换个说法试试')
        .fontSize(AppFontSize.CAPTION + 1)
        .fontColor(this.subTextColor())
        .width('100%')
        .padding({ left: AppSpacing.XS, top: AppSpacing.XS, bottom: AppSpacing.MD })
      if (this.results.length > 0) {
        Column() {
          ForEach(this.results, (result: HelpSearchResult, index: number) => {
            this.resultRow(result, index > 0)
          }, (result: HelpSearchResult) => `${this.keyword}:${result.anchor}`)
        }
        .width('100%')
        .borderRadius(ThemeRuntime.largeRadius())
        .clip(true)
        .backgroundColor(this.cardColor())
      }
    }
    .width('100%')
  }

  @Builder
  resultRow(result: HelpSearchResult, showDivider: boolean) {
    Column() {
      if (showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color(this.dividerColor())
          .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
      }
      Column({ space: AppSpacing.XS }) {
        Text(result.title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
        Text() {
          Span(`${result.location} · `)
          Span(result.before)
          Span(result.match)
            .fontColor(this.accentColor())
            .textBackgroundStyle({ color: ThemeRuntime.accentSurfaceColor(this.appDarkMode), radius: 3 })
          Span(result.after)
        }
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    }
    .width('100%')
    .onClick(() => HelpManual.openTopic(result.topicId, result.anchor))
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
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

  dividerColor(): string {
    return ThemeRuntime.dividerColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
