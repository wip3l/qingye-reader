import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ImmersiveBackButton } from '../ImmersiveBackButton';

/** 面板里的一个分类；key 与发现页频道一致，为 `分类名\n地址`。 */
export interface ExploreCategoryItem {
  key: string;
  title: string;
  groupTitle: string;
}

interface ExploreCategorySection {
  key: string;
  title: string;
  items: ExploreCategoryItem[];
}

/**
 * 发现页“全部分类”面板，作为半模态（bindSheet）的内容使用，交互与详情页目录一致。
 * 按书源自带的分组分节列出全部分类，顶部是该书源最近点过的分类；分类多时可搜索。
 * 只负责展示和挑选，切换模式、加载内容和记录“最近”都交给发现页。
 */
@Component
export struct ExploreCategorySheet {
  /** 分类较多时才显示搜索框，少量分类一眼就能看完。 */
  static readonly SEARCH_THRESHOLD: number = 20;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  items: ExploreCategoryItem[] = [];
  recentKeys: string[] = [];
  selectedKey: string = '';
  onSelect: (key: string) => void = (_key: string): void => {
  };
  onClose: () => void = (): void => {
  };
  @State keyword: string = '';
  private scroller: Scroller = new Scroller();

  build() {
    Column() {
      Row({ space: AppSpacing.LG }) {
        Column({ space: AppSpacing.XS }) {
          Text('全部分类')
            .fontSize(AppFontSize.TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text(`共 ${this.items.length} 个`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        ImmersiveBackButton({
          icon: $r('sys.symbol.xmark'),
          iconOffsetX: 0,
          iconColor: this.primaryTextColor(),
          darkMode: this.appDarkMode,
          buttonSize: 40,
          containerWidth: 40,
          containerHeight: 40,
          startInset: 0,
          materialScale: 0.83,
          compactLayout: true,
          accessibilityLabel: '关闭全部分类',
          onBack: () => this.onClose()
        })
      }
      .width('100%')
      // 半模态已在拖动条下方留出位置，这里只留很小的上边距。
      .padding({ left: AppSpacing.XXL, right: AppSpacing.XL, top: AppSpacing.XS, bottom: AppSpacing.MD })
      .alignItems(VerticalAlign.Center)

      if (this.items.length >= ExploreCategorySheet.SEARCH_THRESHOLD) {
        this.searchField()
      }

      Scroll(this.scroller) {
        Column() {
          if (this.recentVisible()) {
            this.section('最近', this.recentItems())
          }
          ForEach(this.sections(), (section: ExploreCategorySection) => {
            this.section(section.title, section.items)
          }, (section: ExploreCategorySection): string => `${this.keyword}\u0001${section.key}`)

          if (this.keyword && this.sections().length === 0) {
            Text('没有匹配的分类')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: AppSpacing.XXL })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: AppSpacing.XXL, right: AppSpacing.XL, bottom: AppSpacing.XXL + this.navBarHeight })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      // 上滑先把面板拉到全屏再滚动分类，下滑先滚回顶部再收起面板。
      .nestedScroll({
        scrollForward: NestedScrollMode.PARENT_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  searchField() {
    Row({ space: AppSpacing.MD }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(18)
        .fontColor([this.subTextColor()])
      TextInput({ text: this.keyword, placeholder: '搜索分类名称' })
        .fontSize(AppFontSize.BODY)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .layoutWeight(1)
        .height(38)
        .padding({ left: 0, right: 0 })
        .backgroundColor(Color.Transparent)
        .enterKeyType(EnterKeyType.Search)
        .onChange((value: string): void => {
          this.keyword = value;
          this.scroller.scrollEdge(Edge.Top);
        })
      if (this.keyword) {
        Text('×')
          .fontSize(AppFontSize.TITLE)
          .fontColor(this.subTextColor())
          .width(32)
          .height(38)
          .textAlign(TextAlign.Center)
          .accessibilityText('清空分类搜索')
          .onClick((): void => {
            this.keyword = '';
          })
      }
    }
    .width(`calc(100% - ${AppSpacing.XXL + AppSpacing.XL}vp)`)
    .height(40)
    .margin({ left: AppSpacing.XXL, right: AppSpacing.XL, bottom: AppSpacing.SM })
    .padding({ left: AppSpacing.LG, right: AppSpacing.MD })
    .borderRadius(20)
    .backgroundColor(ThemeRuntime.hairlineColor(this.appDarkMode))
  }

  @Builder
  section(title: string, items: ExploreCategoryItem[]) {
    Column() {
      if (title) {
        Text(title)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .margin({ top: AppSpacing.MD, bottom: AppSpacing.SM })
      }
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(items, (item: ExploreCategoryItem) => {
          this.chip(item)
        }, (item: ExploreCategoryItem): string => `${title}\u0001${item.key}`)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  chip(item: ExploreCategoryItem) {
    Text(item.title)
      .fontSize(AppFontSize.BODY)
      .fontWeight(item.key === this.selectedKey ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(item.key === this.selectedKey ? this.accentColor() : this.primaryTextColor())
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 240 })
      .height(34)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(17)
      .backgroundColor(item.key === this.selectedKey ? this.selectedChipColor() :
        ThemeRuntime.softFillColor(this.appDarkMode))
      .margin({ right: AppSpacing.SM, bottom: AppSpacing.SM })
      .accessibilityText(item.title)
      .accessibilitySelected(item.key === this.selectedKey)
      .onClick(() => this.onSelect(item.key))
  }

  recentVisible(): boolean {
    return !this.keyword && this.recentItems().length > 0;
  }

  recentItems(): ExploreCategoryItem[] {
    const result: ExploreCategoryItem[] = [];
    for (const key of this.recentKeys) {
      const item = this.items.find((candidate: ExploreCategoryItem): boolean => candidate.key === key);
      if (item) result.push(item);
    }
    return result;
  }

  /** 按分组分节；搜索时只留匹配的分类，空节不显示。只有一节且没有“最近”时不显示节标题。 */
  sections(): ExploreCategorySection[] {
    const keyword = this.keyword.trim().toLowerCase();
    const result: ExploreCategorySection[] = [];
    for (const item of this.items) {
      if (keyword && !item.title.toLowerCase().includes(keyword)) continue;
      const groupTitle = item.groupTitle.trim();
      let section = result.find((candidate: ExploreCategorySection): boolean => candidate.title === groupTitle);
      if (!section) {
        section = { key: groupTitle, title: groupTitle, items: [] };
        result.push(section);
      }
      section.items.push(item);
    }
    const showTitles = result.length > 1 || this.recentVisible();
    const ungroupedTitle = result.some((section: ExploreCategorySection): boolean => section.key === '其他') ?
      '其他（未分组）' : '其他';
    return result.map((section: ExploreCategorySection): ExploreCategorySection => {
      const title = !showTitles ? '' : (section.title || (result.length > 1 ? ungroupedTitle : '全部'));
      const titled: ExploreCategorySection = { key: section.key, title: title, items: section.items };
      return titled;
    });
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

  selectedChipColor(): string {
    const color = this.accentColor();
    return /^#[0-9A-Fa-f]{6}$/.test(color) ? `#26${color.substring(1)}` : color;
  }
}
