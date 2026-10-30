import { LengthMetrics, router } from '@kit.ArkUI';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { HelpBlockView } from '../components/help/HelpBlockView';
import { HelpAction, HelpBlock, HelpData, HelpManual, HelpPart, HelpSection, HelpTopic } from '../utils/HelpManual';

/** 专题页里的一行，每行对应列表里的一项，方便按小节 id 定位。 */
class TopicRow {
  key: string = '';
  /** lead 导语、action 跳转按钮、part 章节名、intro 章节开头说明、section 小节、nav 上一篇下一篇。 */
  kind: string = '';
  title: string = '';
  blocks: HelpBlock[] = [];
  section: HelpSection | null = null;
}

/**
 * 使用说明的一个专题：导语、跳到对应功能的按钮，以及可展开收起的小节卡片。
 * 参数 topic 为专题 id；anchor 为章节或小节 id，只传 anchor 时按它找所在专题，打开后展开并滚到该小节。
 */
@Entry
@Component
struct HelpTopicPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State headerCollapse: number = 0;
  @State title: string = '';
  @State rows: TopicRow[] = [];
  @State expanded: string[] = [];
  @State prevTopic: HelpTopic | null = null;
  @State nextTopic: HelpTopic | null = null;
  @State loadError: string = '';
  private data: HelpData | null = null;
  private topic: HelpTopic | null = null;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.syncBars();
    const params = router.getParams() as Record<string, string> | undefined;
    const topicParam = params && typeof params['topic'] === 'string' ? params['topic'] : '';
    const anchor = params && typeof params['anchor'] === 'string' ? params['anchor'] : '';
    HelpManual.load(getContext(this)).then((data: HelpData) => {
      const topicId = topicParam || data.topicOfAnchor(anchor);
      const topic = data.topic(topicId);
      if (!topic) {
        this.loadError = '没有找到这篇说明';
        return;
      }
      this.data = data;
      this.topic = topic;
      this.title = topic.title;
      this.rows = this.buildRows(topic);
      this.findNeighbors(data, topic);
      this.openAnchor(topic, anchor === topic.id ? '' : anchor);
    }).catch((error: Error) => {
      this.loadError = `说明读取失败：${error.message}`;
    });
  }

  onPageShow(): void {
    this.syncBars();
  }

  buildRows(topic: HelpTopic): TopicRow[] {
    const rows: TopicRow[] = [];
    const add = (kind: string, key: string, title: string, blocks: HelpBlock[], section: HelpSection | null): void => {
      const row = new TopicRow();
      row.kind = kind;
      row.key = key;
      row.title = title;
      row.blocks = blocks;
      row.section = section;
      rows.push(row);
    };
    const firstIntro = topic.parts.length > 0 ? topic.parts[0].intro : [];
    const hasLead = firstIntro.length > 0 && firstIntro[0].k === 'p';
    if (hasLead) add('lead', 'lead', '', [firstIntro[0]], null);
    if (topic.action) add('action', 'action', topic.action.label, [], null);
    topic.parts.forEach((part: HelpPart, partIndex: number) => {
      if (topic.parts.length > 1) add('part', part.id, part.title, [], null);
      const intro = partIndex === 0 && hasLead ? part.intro.slice(1) : part.intro;
      if (intro.length > 0) add('intro', `${part.id}-intro`, '', intro, null);
      part.sections.forEach((section: HelpSection) => add('section', section.id, section.title, [], section));
    });
    return rows;
  }

  findNeighbors(data: HelpData, topic: HelpTopic): void {
    const ordered = data.orderedTopics();
    const index = ordered.findIndex((item: HelpTopic) => item.id === topic.id);
    if (index < 0) return;
    this.prevTopic = index > 0 ? ordered[index - 1] : null;
    this.nextTopic = index < ordered.length - 1 ? ordered[index + 1] : null;
  }

  openAnchor(topic: HelpTopic, anchor: string): void {
    const rowIndex = anchor ? this.rows.findIndex((row: TopicRow) => row.key === anchor) : -1;
    if (rowIndex >= 0 && this.rows[rowIndex].kind === 'section') {
      this.expanded = [anchor];
    } else if (topic.id !== HelpManual.FAQ_TOPIC_ID) {
      // 默认展开第一个小节，让人一进来就能看到正文样式。
      const first = this.rows.find((row: TopicRow) => row.kind === 'section');
      this.expanded = first ? [first.key] : [];
    }
    if (rowIndex < 0) return;
    // 列表首项是顶栏占位，小节从 1 开始；等列表排好版再滚，停在顶栏下方。
    setTimeout(() => {
      this.scroller.scrollToIndex(rowIndex + 1, false, ScrollAlign.START,
        { extraOffset: LengthMetrics.vp(-(PageScaffold.BAR_HEIGHT + this.statusBarHeight + AppSpacing.MD)) });
    }, 80);
  }

  build() {
    Stack() {
      PageScaffold({ title: this.title, scrollable: false, edgeToEdge: true, externalCollapse: this.headerCollapse,
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
    List({ scroller: this.scroller, space: AppSpacing.LG }) {
      ListItem() {
        Row()
          .width('100%')
          .height(PageScaffold.BAR_HEIGHT + this.statusBarHeight - AppSpacing.LG)
          .hitTestBehavior(HitTestMode.None)
      }

      ForEach(this.rows, (row: TopicRow) => {
        ListItem() {
          this.rowView(row)
        }
      }, (row: TopicRow) => row.key)

      if (this.prevTopic || this.nextTopic) {
        ListItem() {
          this.neighborNav()
        }
      }

      if (this.loadError) {
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
          .height(20 + this.navBarHeight)
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
  rowView(row: TopicRow) {
    if (row.kind === 'lead') {
      Column() {
        HelpBlockView({ blocks: row.blocks, muted: true, onLink: (url: string) => this.openLink(url) })
      }
      .width('100%')
      .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
    } else if (row.kind === 'action') {
      Row({ space: AppSpacing.SM }) {
        if (this.topic) {
          SymbolGlyph(HelpManual.icon(this.topic.icon))
            .fontSize(18)
            .fontColor([ThemeRuntime.onAccentColor(this.accentColor())])
        }
        Text(row.title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(ThemeRuntime.onAccentColor(this.accentColor()))
      }
      .width('100%')
      .height(44)
      .justifyContent(FlexAlign.Center)
      .borderRadius(22)
      .backgroundColor(this.accentColor())
      .onClick(() => {
        const action: HelpAction | undefined = this.topic ? this.topic.action : undefined;
        if (action) HelpManual.runAction(action);
      })
    } else if (row.kind === 'part') {
      Text(row.title)
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .padding({ left: AppSpacing.XS, top: AppSpacing.MD })
    } else if (row.kind === 'intro') {
      Column() {
        HelpBlockView({ blocks: row.blocks, onLink: (url: string) => this.openLink(url) })
      }
      .width('100%')
      .padding(AppSpacing.XL)
      .borderRadius(ThemeRuntime.largeRadius())
      .backgroundColor(this.cardColor())
    } else if (row.section) {
      this.sectionCard(row.section)
    }
  }

  @Builder
  sectionCard(section: HelpSection) {
    Column() {
      Row({ space: AppSpacing.MD }) {
        Text(section.title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([this.subTextColor()])
          .rotate({ angle: this.isExpanded(section.id) ? 90 : 0 })
      }
      .width('100%')
      .constraintSize({ minHeight: 52 })
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.SM })
      .onClick(() => this.toggle(section.id))

      if (this.isExpanded(section.id)) {
        Column({ space: AppSpacing.LG }) {
          HelpBlockView({ blocks: section.blocks, onLink: (url: string) => this.openLink(url) })
          if (section.action) {
            Text(`${section.action.label} ›`)
              .fontSize(AppFontSize.BODY)
              .fontColor(this.accentColor())
              .onClick(() => {
                const action: HelpAction | undefined = section.action;
                if (action) HelpManual.runAction(action);
              })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.XL })
      }
    }
    .width('100%')
    .borderRadius(ThemeRuntime.largeRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
  }

  @Builder
  neighborNav() {
    Row({ space: AppSpacing.MD }) {
      this.neighborCard('上一篇', this.prevTopic, true)
      this.neighborCard('下一篇', this.nextTopic, false)
    }
    .width('100%')
    .margin({ top: AppSpacing.MD })
  }

  @Builder
  neighborCard(label: string, topic: HelpTopic | null, isPrev: boolean) {
    Column({ space: AppSpacing.XXS }) {
      if (topic) {
        Text(label)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
        Text(isPrev ? `‹ ${topic.title}` : `${topic.title} ›`)
          .fontSize(AppFontSize.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .layoutWeight(1)
    .alignItems(isPrev ? HorizontalAlign.Start : HorizontalAlign.End)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD + 2, bottom: AppSpacing.MD + 2 })
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(topic ? this.cardColor() : Color.Transparent)
    .onClick(() => {
      // 相邻专题之间替换当前页，返回时直接回到说明首页，不越叠越深。
      if (!topic) return;
      router.replaceUrl({ url: 'pages/HelpTopic', params: { topic: topic.id } }).catch((error: Error) => {
        console.error('切换说明专题失败:', error.message);
      });
    })
  }

  isExpanded(id: string): boolean {
    return this.expanded.indexOf(id) >= 0;
  }

  toggle(id: string): void {
    animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
      this.expanded = this.isExpanded(id) ? this.expanded.filter((item: string) => item !== id)
        : this.expanded.concat([id]);
    });
  }

  openLink(url: string): void {
    if (this.data) HelpManual.openLink(getContext(this), this.data, url);
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

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
