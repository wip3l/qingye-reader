import { ThemePack, ThemeVariant } from '../../theme/ThemeModels';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { HexColor } from '../../utils/HexColor';
import { BuiltinThemeRegistry } from '../../theme/BuiltinThemeRegistry';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ReaderSettings } from '../../utils/ReaderSettingsStore';
import { ReaderThemeBackground } from '../ReaderThemeBackground';
import { ThemeStartupCover } from '../ThemeStartupCover';
import { TtsPanelThemeBackground } from '../TtsPanelThemeBackground';
import { BookCover } from '../book/BookCover';
import { HomeTabBarSettingsStore } from '../../utils/HomeTabBarSettingsStore';
import {
  ReaderRegexBubbleStyleResolver,
  ReaderRegexEmphasisContext,
  ReaderResolvedRegexEmphasis
} from '../../model/reader/ReaderRegexFontRule';

/** 只读的方案预览；始终使用传入的草稿，不发布全局主题令牌。 */
@Component
export struct CustomThemePreview {
  @Prop themePack: ThemePack = new ThemePack();
  @Prop previewDark: boolean = false;
  @Prop scene: string = 'bookshelf';
  @Prop expanded: boolean = false;
  @Prop startupImagePath: string = '';
  @Prop startupTitle: string = '';
  @Prop startupSubtitle: string = '';
  @Prop startupTitleColor: string = '';
  @Prop startupSubtitleColor: string = '';
  @Prop startupTitleSize: number = 0;
  @Prop startupSubtitleSize: number = 0;
  @Prop ttsThemeId: string = '';
  @Prop homeBackdropThemeId: string = '';
  @Prop readerSettings: ReaderSettings = new ReaderSettings();
  @Prop useReaderProfile: boolean = false;
  // 书架画面按哪种书架布局画：companion / tile / loose / compact。
  @Prop shelfLayout: string = 'companion';
  // 主题卡片画面：方案名、预览图（空时用启动封面）与角标所在的主题 ID（空时不画角标）。
  @Prop schemeName: string = '';
  @Prop cardImagePath: string = '';
  @Prop logoThemeId: string = '';
  // 底栏按“其他设置 › 底栏”里选的第四个页签画，和首页一致。
  @StorageProp('homeExtraTab') homeExtraTab: string = 'none';

  build() {
    Stack() {
      if (this.scene === 'startup') {
        ThemeStartupCover({
          themeId: this.themePack.startup.styleId,
          darkMode: this.previewDark,
          compact: !this.expanded,
          animated: false,
          customImagePath: this.startupImagePath,
          titleOverride: this.startupTitle,
          subtitleOverride: this.startupSubtitle,
          explicitText: true,
          titleColor: this.startupTitleColor,
          subtitleColor: this.startupSubtitleColor,
          titleSize: this.startupTitleSize,
          subtitleSize: this.startupSubtitleSize
        })
      } else if (this.scene === 'reader') {
        this.readerPreview()
      } else if (this.scene === 'tts') {
        this.ttsPreview()
      } else if (this.scene === 'card') {
        this.cardPreview()
      } else {
        if (this.homeBackdrop()) {
          this.homeBackdropLayer()
        }
        Column({ space: AppSpacing.MD }) {
          if (this.scene === 'explore') {
            this.explorePreview()
          } else if (this.scene === 'mine') {
            this.minePreview()
          } else {
            this.bookshelfPreview()
          }
          this.navigationBar()
        }
        .width('100%')
        .height('100%')
        .padding(AppSpacing.LG)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.variant().colors.pageColor)
    .borderRadius(this.themePack.radius.card)
    .clip(true)
    .accessibilityText(`${this.previewDark ? '深色' : '浅色'}主题效果预览`)
  }

  variant(): ThemeVariant {
    return this.previewDark ? this.themePack.dark : this.themePack.light;
  }

  homeBackdrop(): ResourceStr | null {
    return this.homeBackdropThemeId ?
      ThemeAssetRegistry.homeBackdrop(this.homeBackdropThemeId, this.previewDark) : null;
  }

  /** 首页背景：贴顶铺满宽度，和首页一样向下淡成页面底色。 */
  @Builder
  homeBackdropLayer() {
    Stack({ alignContent: Alignment.Top }) {
      Image(this.homeBackdrop() as ResourceStr)
        .width('100%')
        .aspectRatio(ThemeAssetRegistry.HOME_BACKDROP_ASPECT)
        .objectFit(ImageFit.Cover)
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [[HexColor.withOpacity(this.variant().colors.pageColor, this.previewDark ? 0.4 : 0.2), 0],
            [this.variant().colors.pageColor, 1]]
        })
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  titleRow(title: string, trailing: string) {
    Row() {
      Text(title)
        .fontFamily(this.themePack.typography.appFontFamily)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.variant().colors.primaryTextColor)
        .layoutWeight(1)
      if (trailing) {
        Text(trailing)
          .fontFamily(this.themePack.typography.appFontFamily)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.variant().colors.accentColor)
      }
    }
    .width('100%')
  }

  coverResource(index: number): ResourceStr {
    const covers = ThemeAssetRegistry.themeBookCovers(this.themePack.book.coverAssetId);
    return covers.length > 0 ? covers[index % covers.length] : '';
  }

  /** 一本书的封面：主题封面（按书轮播）或普通封面，叠主题书架边框。 */
  @Builder
  coverTile(name: string, index: number, coverWidth: number) {
    Stack() {
      if (this.coverResource(index)) {
        Image(this.coverResource(index))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
      } else {
        BookCover({ name: name, useBookshelfCover: false,
          placeholderColor: this.variant().colors.accentColor,
          cornerRadius: this.themePack.radius.small })
          .width('100%')
          .height('100%')
      }
      if (this.themePack.book.shelfFrameAssetId) {
        Image(ThemeAssetRegistry.themeShelfFrame(this.themePack.book.shelfFrameAssetId))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
      }
    }
    .width(coverWidth)
    .height(coverWidth * 1.42)
    .borderRadius(this.themePack.radius.small)
    .clip(true)
  }

  @Builder
  smallText(text: string, color: string) {
    Text(text)
      .fontFamily(this.themePack.typography.appFontFamily)
      .fontSize(AppFontSize.MICRO)
      .fontColor(color)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  progressBar(percent: number) {
    Stack({ alignContent: Alignment.Start }) {
      Column()
        .width(`${percent}%`)
        .height('100%')
        .borderRadius(2)
        .backgroundColor(this.variant().colors.accentColor)
    }
    .width('100%')
    .height(4)
    .borderRadius(2)
    .backgroundColor(this.variant().colors.dividerColor)
  }

  coverScale(): number {
    return this.expanded ? 1.3 : 1;
  }

  @Builder
  bookshelfPreview() {
    Column({ space: AppSpacing.MD }) {
      if (this.shelfLayout === 'tile') {
        this.titleRow('书架', '最近阅读')
        Row({ space: AppSpacing.LG }) {
          ForEach(['山野来信', '长夜微光', '人间草木', '海上来客'], (name: string, index: number) => {
            Column({ space: AppSpacing.XS }) {
              this.coverTile(name, index, 52 * this.coverScale())
              this.smallText(name, this.variant().colors.primaryTextColor)
            }
            .layoutWeight(1)
          }, (name: string) => name)
        }
        .width('100%')
      } else if (this.shelfLayout === 'loose') {
        this.titleRow('书架', '')
        ForEach(['山野来信', '长夜微光'], (name: string, index: number) => {
          Row({ space: AppSpacing.LG }) {
            this.coverTile(name, index, 40 * this.coverScale())
            Column({ space: AppSpacing.XS }) {
              Text(name)
                .fontFamily(this.themePack.typography.appFontFamily)
                .fontSize(AppFontSize.BODY)
                .fontColor(this.variant().colors.primaryTextColor)
              this.smallText(index === 0 ? '读到第十二章 · 38%' : '读到第三章 · 9%', this.variant().colors.subTextColor)
              this.progressBar(index === 0 ? 38 : 9)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(AppSpacing.MD)
          .borderRadius(this.themePack.radius.card)
          .backgroundColor(this.variant().colors.cardColor)
        }, (name: string) => name)
      } else if (this.shelfLayout === 'compact') {
        this.titleRow('书架', '')
        Column() {
          ForEach(['山野来信', '长夜微光', '人间草木'], (name: string, index: number) => {
            Row({ space: AppSpacing.MD }) {
              this.coverTile(name, index, 22 * this.coverScale())
              Text(name)
                .fontFamily(this.themePack.typography.appFontFamily)
                .fontSize(AppFontSize.CAPTION)
                .fontColor(this.variant().colors.primaryTextColor)
                .layoutWeight(1)
              this.smallText(index === 0 ? '38%' : (index === 1 ? '9%' : '72%'), this.variant().colors.subTextColor)
            }
            .width('100%')
            .padding({ top: AppSpacing.XS, bottom: AppSpacing.XS })
            .border({ width: { bottom: index < 2 ? 1 : 0 }, color: this.variant().colors.dividerColor })
          }, (name: string) => name)
        }
        .width('100%')
        .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
        .borderRadius(this.themePack.radius.card)
        .backgroundColor(this.variant().colors.cardColor)
      } else {
        Column({ space: AppSpacing.XXS }) {
          this.titleRow('下午好', '')
          this.smallText('今天读了 24 分钟', this.variant().colors.subTextColor)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        Row({ space: AppSpacing.LG }) {
          this.coverTile('山野来信', 0, 40 * this.coverScale())
          Column({ space: AppSpacing.XS }) {
            this.smallText('继续阅读', this.variant().colors.accentColor)
            Text('山野来信')
              .fontFamily(this.themePack.typography.appFontFamily)
              .fontSize(AppFontSize.BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.variant().colors.primaryTextColor)
            this.progressBar(38)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(AppSpacing.MD)
        .borderRadius(this.themePack.radius.card)
        .backgroundColor(this.variant().colors.cardColor)
        Row({ space: AppSpacing.MD }) {
          ForEach(['长夜微光', '人间草木', '海上来客', '雪国'], (name: string, index: number) => {
            this.coverTile(name, index + 1, 32 * this.coverScale())
          }, (name: string) => name)
        }
        .width('100%')
      }
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .clip(true)
  }

  @Builder
  chip(label: string, active: boolean) {
    Text(label)
      .fontFamily(this.themePack.typography.appFontFamily)
      .fontSize(AppFontSize.MICRO)
      .fontColor(active ? this.variant().colors.accentColor : this.variant().colors.subTextColor)
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
      .borderRadius(this.themePack.radius.button)
      .backgroundColor(active ? HexColor.withOpacity(this.variant().colors.accentColor, 0.14) :
        this.variant().colors.cardColor)
  }

  @Builder
  bookRow(name: string, index: number, detail: string) {
    Row({ space: AppSpacing.MD }) {
      this.coverTile(name, index, 28 * this.coverScale())
      Column({ space: AppSpacing.XXS }) {
        Text(name)
          .fontFamily(this.themePack.typography.appFontFamily)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.variant().colors.primaryTextColor)
        this.smallText(detail, this.variant().colors.subTextColor)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  explorePreview() {
    Column({ space: AppSpacing.MD }) {
      this.titleRow('发现', '')
      Row({ space: AppSpacing.SM }) {
        this.chip('推荐', true)
        this.chip('排行', false)
        this.chip('完本', false)
      }
      Column({ space: AppSpacing.MD }) {
        this.bookRow('长夜微光', 1, '悬疑 · 连载中')
        this.bookRow('人间草木', 2, '散文 · 已完结')
      }
      .width('100%')
      .padding(AppSpacing.MD)
      .borderRadius(this.themePack.radius.card)
      .backgroundColor(this.variant().colors.cardColor)
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .clip(true)
  }

  @Builder
  mineRow(label: string, last: boolean) {
    Row() {
      Text(label)
        .fontFamily(this.themePack.typography.appFontFamily)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.variant().colors.primaryTextColor)
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(12)
        .fontColor([this.variant().colors.subTextColor])
    }
    .width('100%')
    .height(30)
    .border({ width: { bottom: last ? 0 : 1 }, color: this.variant().colors.dividerColor })
  }

  @Builder
  minePreview() {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.MD }) {
        Column()
          .width(34)
          .height(34)
          .borderRadius(17)
          .backgroundColor(HexColor.withOpacity(this.variant().colors.accentColor, 0.3))
        Column({ space: AppSpacing.XXS }) {
          Text('读书人')
            .fontFamily(this.themePack.typography.appFontFamily)
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.variant().colors.primaryTextColor)
          this.smallText('累计阅读 128 小时', this.variant().colors.subTextColor)
        }
        .alignItems(HorizontalAlign.Start)
      }
      Column() {
        this.mineRow('主题', false)
        this.mineRow('阅读设置', false)
        this.mineRow('书源管理', true)
      }
      .width('100%')
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
      .borderRadius(this.themePack.radius.card)
      .backgroundColor(this.variant().colors.cardColor)
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .clip(true)
  }

  selectedTab(): string {
    if (this.scene === 'explore' || this.scene === 'mine') return this.scene;
    return 'bookshelf';
  }

  hidesLabels(): boolean {
    return ThemeAssetRegistry.navigationHidesLabels(this.themePack.navigation.iconPackId);
  }

  tabLabel(tabId: string): string {
    if (tabId === 'explore') return '发现';
    if (tabId === 'mine') return '我的';
    if (tabId === 'listen') return '听';
    if (tabId === 'footprint') return '足迹';
    return '书架';
  }

  navigationTabs(): string[] {
    const extra = HomeTabBarSettingsStore.normalizeExtraTab(this.homeExtraTab);
    return extra === HomeTabBarSettingsStore.EXTRA_NONE ? ['bookshelf', 'explore', 'mine'] :
      ['bookshelf', 'explore', extra, 'mine'];
  }

  @Builder
  navigationBar() {
    Row() {
      ForEach(this.navigationTabs(), (tabId: string) => {
        Column({ space: 2 }) {
          Image(ThemeAssetRegistry.navigationIcon(this.themePack.navigation.iconPackId, tabId,
            tabId === this.selectedTab()))
            .width(this.hidesLabels() ? 26 : 20)
            .height(this.hidesLabels() ? 26 : 20)
            .fillColor(tabId === this.selectedTab() ? this.variant().colors.accentColor :
              this.variant().colors.subTextColor)
          if (!this.hidesLabels()) {
            Text(this.tabLabel(tabId))
              .fontFamily(this.themePack.typography.appFontFamily)
              .fontSize(9)
              .fontColor(tabId === this.selectedTab() ? this.variant().colors.accentColor :
                this.variant().colors.subTextColor)
          }
        }
        .layoutWeight(1)
      }, (tabId: string) => `${tabId}_${this.selectedTab()}`)
    }
    .width('100%')
    .height(this.hidesLabels() ? 40 : 44)
    .alignItems(VerticalAlign.Center)
    .borderRadius(this.themePack.radius.medium)
    .backgroundColor(this.variant().colors.cardColor)
  }

  /** 主题页上这套方案的卡片：预览图（没有时用启动封面）、名字与角标。 */
  @Builder
  cardPreview() {
    Column() {
      Column({ space: AppSpacing.SM }) {
        Stack({ alignContent: Alignment.TopEnd }) {
          if (this.cardImagePath) {
            Image(this.cardImagePath)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
          } else {
            ThemeStartupCover({
              themeId: this.themePack.startup.styleId,
              darkMode: this.previewDark,
              compact: true,
              animated: false,
              customImagePath: this.startupImagePath,
              titleOverride: this.startupTitle,
              subtitleOverride: this.startupSubtitle,
              explicitText: true,
              titleColor: this.startupTitleColor,
              subtitleColor: this.startupSubtitleColor,
              titleSize: this.startupTitleSize,
              subtitleSize: this.startupSubtitleSize
            })
          }
          if (this.logoThemeId) {
            Image(ThemeAssetRegistry.themeLogo(this.logoThemeId))
              .width(24)
              .height(24)
              .padding(3)
              .borderRadius(12)
              .backgroundColor(this.variant().colors.cardColor)
              .margin(AppSpacing.SM)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .borderRadius(this.themePack.radius.card)
        .clip(true)
        Text(this.schemeName || '自定义主题')
          .fontFamily(this.themePack.typography.appFontFamily)
          .fontSize(AppFontSize.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.variant().colors.primaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .height('100%')
      .aspectRatio(0.62)
      .padding(AppSpacing.SM)
      .borderRadius(this.themePack.radius.card)
      .backgroundColor(this.variant().colors.cardColor)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .padding(AppSpacing.LG)
    .alignItems(HorizontalAlign.Center)
  }

  readerFontSize(): number {
    const size = this.useReaderProfile ? this.readerSettings.fontSize : this.themePack.readerLayout.fontSize;
    return size * (this.expanded ? 1 : 0.72);
  }

  @Builder
  readerPreview() {
    Stack({ alignContent: Alignment.TopStart }) {
      ReaderThemeBackground({
        surfaceColor: this.variant().reader.backgroundColor,
        backgroundAssetId: this.variant().reader.backgroundAssetId,
        compact: !this.expanded
      })
      Column({ space: AppSpacing.MD }) {
        Row() {
          Text('山野来信')
            .layoutWeight(1)
            .fontSize(AppFontSize.MICRO)
            .fontColor(this.variant().reader.subTextColor)
          Text('第十二章')
            .fontSize(AppFontSize.MICRO)
            .fontColor(this.variant().reader.subTextColor)
        }
        .width('100%')
        Text('风从山间来')
          .fontFamily(this.themePack.typography.appFontFamily)
          .fontSize(this.readerFontSize() + 2)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.variant().reader.textColor)
          .width('100%')
        Text('　　清晨的薄雾漫过山谷，窗外的树叶还带着昨夜的雨。远处，风把林间的消息，轻轻送到了窗前。')
          .fontFamily(this.useReaderProfile && this.readerSettings.bodyFontMode !== 'device' &&
            this.readerSettings.bodyFontFamily ? this.readerSettings.bodyFontFamily : this.themePack.typography.appFontFamily)
          .fontSize(this.readerFontSize())
          .lineHeight(this.readerFontSize() + (this.useReaderProfile ?
            this.readerSettings.lineHeight : this.themePack.readerLayout.lineHeight) * 0.65)
          .letterSpacing(this.useReaderProfile ? this.readerSettings.letterSpacing :
            this.themePack.readerLayout.letterSpacing)
          .fontColor(this.variant().reader.textColor)
          .width('100%')
          .maxLines(this.expanded ? 12 : 3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        this.emphasisSample()
      }
      .width('100%')
      .padding({
        left: this.useReaderProfile ? this.readerSettings.marginLeft : this.themePack.readerLayout.marginLeft,
        right: this.useReaderProfile ? this.readerSettings.marginRight : this.themePack.readerLayout.marginRight,
        top: AppSpacing.LG,
        bottom: AppSpacing.LG
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  /** 强调示例按方案实际的强调方式、气泡样式与端饰绘制，和主题详情页的阅读页预览同一套解析。 */
  @Builder
  emphasisSample() {
    Text() {
      Span('她在扉页写下：')
        .fontColor(this.variant().reader.textColor)
      if (this.emphasisStyle().mode === 'none') {
        Span('把时光，留给阅读')
          .fontColor(this.variant().reader.textColor)
      } else if (this.emphasisStyle().bubbleDecorationEnabled && this.hasBubbleCap()) {
        ContainerSpan() {
          ImageSpan(ThemeAssetRegistry.regexBubbleCap(this.variant().regexEmphasis.bubbleStyle))
            .width(this.readerFontSize())
            .height(this.readerFontSize())
            .objectFit(ImageFit.Contain)
            .verticalAlign(ImageSpanAlignment.CENTER)
          Span('把时光，留给阅读')
            .fontColor(this.emphasisStyle().textColor)
            .textShadow(this.emphasisShadow())
          ImageSpan(ThemeAssetRegistry.regexBubbleCap(this.variant().regexEmphasis.bubbleStyle))
            .width(this.readerFontSize())
            .height(this.readerFontSize())
            .objectFit(ImageFit.Contain)
            .verticalAlign(ImageSpanAlignment.CENTER)
            .rotate({ angle: 180 })
        }
        .textBackgroundStyle(this.emphasisBackground())
      } else {
        ContainerSpan() {
          Span('把时光，留给阅读')
            .fontColor(this.emphasisStyle().textColor)
            .textShadow(this.emphasisShadow())
        }
        .textBackgroundStyle(this.emphasisBackground())
      }
    }
    .fontSize(this.readerFontSize())
    .lineHeight(this.readerFontSize() * 1.8)
    .fontFamily(this.themePack.typography.appFontFamily)
    .width('100%')
    .maxLines(2)
  }

  emphasisStyle(): ReaderResolvedRegexEmphasis {
    const variant = this.variant();
    const context = new ReaderRegexEmphasisContext();
    context.inheritedMode = variant.regexEmphasis.emphasisMode;
    context.inheritedBubbleStyleId = variant.regexEmphasis.bubbleStyle;
    context.inheritedColor = variant.regexEmphasis.emphasisColor;
    context.inheritedTextColor = variant.regexEmphasis.emphasisTextColor;
    context.accentColor = variant.colors.accentColor;
    context.surfaceColor = variant.reader.backgroundColor;
    context.normalTextColor = variant.reader.textColor;
    context.darkMode = variant.reader.contentTone === 'dark';
    // 预览画的是方案自己选的气泡，权益检查留给阅读页。
    return ReaderRegexBubbleStyleResolver.resolve(null, context, false);
  }

  hasBubbleCap(): boolean {
    return ThemeAssetRegistry.hasRegexBubbleCap(this.variant().regexEmphasis.bubbleStyle);
  }

  emphasisBackground(): TextBackgroundStyle {
    const style = this.emphasisStyle();
    if (!style.backgroundEnabled) return {};
    return {
      color: style.backgroundColor,
      radius: {
        topLeft: style.radiusTopLeft,
        topRight: style.radiusTopRight,
        bottomLeft: style.radiusBottomLeft,
        bottomRight: style.radiusBottomRight
      }
    };
  }

  emphasisShadow(): ShadowOptions | ShadowOptions[] {
    const style = this.emphasisStyle();
    if (style.textShadows.length > 0) return style.textShadows;
    return {
      radius: style.textShadowRadius,
      color: style.textShadowColor,
      offsetX: style.textShadowOffsetX,
      offsetY: style.textShadowOffsetY
    };
  }

  @Builder
  ttsPreview() {
    Stack() {
      TtsPanelThemeBackground({ themeId: this.ttsThemeId, darkMode: this.previewDark })
      Column({ space: AppSpacing.LG }) {
        Text('正在朗读 · 山野来信')
          .fontColor(this.ttsTextColor())
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
        Text('第十二章　风从山间来')
          .fontColor(this.ttsTextColor())
          .fontSize(AppFontSize.CAPTION)
        Row({ space: AppSpacing.XXXL }) {
          SymbolGlyph($r('sys.symbol.backward_end_fill'))
            .fontColor([this.ttsTextColor()])
            .fontSize(20)
          SymbolGlyph($r('sys.symbol.pause_fill'))
            .fontSize(26)
            .fontColor([ThemeRuntime.onAccentColor()])
            .padding(AppSpacing.LG)
            .borderRadius(this.themePack.radius.button)
            .backgroundColor(this.variant().colors.buttonColor)
          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontColor([this.ttsTextColor()])
            .fontSize(20)
        }
      }
      .width('calc(100% - 32vp)')
      .padding(AppSpacing.XL)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.glassTint())
      .backdropBlur(this.themePack.glass.enabled ? this.themePack.glass.panel.blurRadius : 0)
      .borderRadius(this.themePack.glass.panel.cornerRadius)
    }
    .width('100%')
    .height('100%')
  }

  ttsTextColor(): string {
    return this.previewDark ? BuiltinThemeRegistry.findById(this.ttsThemeId).dark.reader.textColor :
      BuiltinThemeRegistry.findById(this.ttsThemeId).light.reader.textColor;
  }

  glassTint(): string {
    const tint = this.previewDark ? this.themePack.glass.darkTintOpacity : this.themePack.glass.lightTintOpacity;
    const alpha = this.themePack.glass.enabled ? Math.round(tint * 2.55) : 255;
    const ttsTheme = BuiltinThemeRegistry.findById(this.ttsThemeId);
    const color = this.previewDark ? ttsTheme.dark.colors.cardColor : ttsTheme.light.colors.cardColor;
    return `#${alpha.toString(16).padStart(2, '0')}${color.substring(color.length - 6)}`;
  }
}
