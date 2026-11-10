import { ReaderActionMarker } from '@legado/sourceengine';
import { ReaderSettings } from '../../utils/ReaderSettingsStore';
import { ReaderThemeItem } from '../../utils/ReaderThemeHelper';
import { ReaderThemeBackground } from '../ReaderThemeBackground';
import { ImmersiveMaterialSurface } from '../ImmersiveMaterialSurface';
import { ReaderTypographyPreview, ReaderTypographyPreviewConfig } from './ReaderTypographyPreview';
import { ReaderV2DocumentParser } from '../../core/reader/ReaderV2Document';
import { ReaderV2Color, ReaderV2SpanStyleRange } from '../../core/reader/ReaderV2Style';
import { ReaderCommentBubbleStyles } from '../../core/reader/ReaderCommentBubble';
import { ReaderInfoBarRow } from './ReaderInfoBar';
import { ReaderInfoBarConfig, ReaderInfoBarContext, ReaderInfoBarText, ReaderInfoProgressBar } from '../../core/reader/ReaderInfoBarModel';
import { ReaderInfoBarClock } from '../../core/reader/ReaderInfoBarClock';
import { ReaderHorizontalMargin } from '../../core/reader/ReaderHorizontalMargin';
import { ReaderTitleStyleCodec } from '../../model/reader/ReaderTitleStyle';
import { ReaderRegexBubbleStyleResolver, ReaderRegexEmphasisContext, ReaderRegexFontCodec,
  ReaderRegexFontRule, ReaderRegexLegacySettings } from '../../model/reader/ReaderRegexFontRule';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';

const SETTINGS_PREVIEW_TITLE: string = '第一章 风起';
const SETTINGS_PREVIEW_PARAGRAPHS: string[] = [
  '窗外的风掠过树梢，纸页在指尖轻轻翻动。夜色渐深，故事也在这一刻慢慢展开。',
  '他停在灯下，听见远处传来的脚步声，像是某个被遗忘的约定终于抵达。',
  '巷口的灯还亮着。风吹起门前的帘子，带来一点潮湿的木香，也带来了山那边的消息。',
  '“你终于来了。”老人放下手里的茶杯，抬头望向门外。那一瞬间，远山与长夜都安静下来。',
  '少年没有回答，只将那封折了许多次的信轻轻放在桌上。灯影落在纸面上，像一条缓缓流动的河。',
  '他记得离开时也是这样的夜晚，雨刚停，石板路上倒映着星光。如今再回到这里，一切似乎都没有改变。',
  '屋外的风又起了。故事还长，而这不过是第一章。'
];

/** 全尺寸阅读底层；悬浮设置的显隐和滚动都不改变正文视口。 */
@Component
export struct ReaderSettingsPreview {
  @Prop settings: ReaderSettings = new ReaderSettings();
  @Prop readerTheme: ReaderThemeItem = new ReaderThemeItem();
  @Prop bodyFamily: string = '';
  @Prop globalFamily: string = '';
  @Prop systemFamily: string = '';
  resolveCustomFamily: (family: string) => string = (family: string): string => family;
  @Prop darkMode: boolean = false;
  @Prop revision: number = 0;
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State previewWidth: number = 0;
  @State previewHeight: number = 0;
  @Prop @Watch('onPreviewPageChanged') previewPageIndex: number = 0;
  @Prop allowPageSwipe: boolean = true;
  onPageSelected: (index: number) => void = (_index: number): void => {};
  private previewPager: SwiperController = new SwiperController();

  titleSinglePage(): boolean {
    return ReaderTitleStyleCodec.decode(this.settings.titleStyleRaw).singlePage;
  }

  onPreviewPageChanged(): void {
    if (this.titleSinglePage()) this.previewPager.changeIndex(this.previewPageIndex, true);
  }

  info(): ReaderInfoBarConfig {
    return ReaderInfoBarConfig.parse(this.settings.readerInfoBarConfig) ?? new ReaderInfoBarConfig();
  }

  headerVisible(): boolean {
    return this.settings.readerHeaderEnabled && this.info().headerVisible();
  }

  headerTop(): number {
    return this.info().edgeInset(true,
      ReaderInfoBarConfig.headerBaseInset(this.settings.extendToStatusBar, this.statusBarHeight));
  }

  footerBottom(): number {
    return this.info().edgeInset(false, ReaderInfoBarConfig.footerBaseInset(this.navBarHeight));
  }

  bodyTop(): number {
    const status = this.settings.extendToStatusBar ? 0 : this.statusBarHeight;
    return Math.max(0, this.settings.marginTop) + (this.headerVisible() ?
      this.headerTop() + this.info().headerLineHeight() + this.info().headerExtraHeight() +
        Math.min(4, this.settings.marginTop) : status);
  }

  bodyBottom(): number {
    const footer = this.settings.readerFooterEnabled ? this.footerHeight() +
      this.footerBottom() + Math.min(4, this.settings.marginBottom) : this.navBarHeight;
    return Math.max(0, this.settings.marginBottom) + footer;
  }

  footerHeight(): number {
    return this.getUIContext().px2vp(this.getUIContext().fp2px(this.info().footerFontSize)) +
      this.info().footerExtraHeight() + 3;
  }

  footerTop(): number {
    return Math.max(0, this.previewHeight - this.footerBottom() - this.footerHeight());
  }

  infoContext(pageIndex: number = 0): ReaderInfoBarContext {
    const context = new ReaderInfoBarContext();
    context.bookName = '风起时';
    context.author = '佚名';
    context.chapterTitle = SETTINGS_PREVIEW_TITLE;
    context.chapterIndex = 0;
    context.chapterCount = 36;
    context.pageIndex = pageIndex;
    context.pageCount = this.titleSinglePage() ? 2 : 12;
    context.timeText = ReaderInfoBarClock.timeText();
    context.batteryPercent = ReaderInfoBarClock.batteryPercent();
    return context;
  }

  emphasisContext(): ReaderRegexEmphasisContext {
    const context = new ReaderRegexEmphasisContext();
    context.inheritedMode = ThemeRuntime.regexEmphasisMode();
    context.inheritedBubbleStyleId = ThemeRuntime.regexBubbleStyle();
    // 主题强调色随应用主题选择；纸张明暗仅决定气泡的对比色，与实际阅读一致。
    context.inheritedColor = ThemeRuntime.regexEmphasisColor(this.appDarkMode);
    context.inheritedTextColor = ThemeRuntime.regexEmphasisTextColor(this.appDarkMode);
    context.accentColor = ThemeRuntime.accentColor(this.appDarkMode);
    context.surfaceColor = this.readerTheme.backgroundColor;
    context.normalTextColor = this.readerTheme.textColor;
    context.darkMode = this.darkMode;
    return context;
  }

  fontFamily(mode: string, family: string): string {
    if (mode === 'system') return this.systemFamily;
    if (mode === 'custom' && family) return this.resolveCustomFamily(family);
    return this.globalFamily;
  }

  spanStyle(rule: ReaderRegexFontRule | null, fontSize: number, family: string,
    fontWeight: number): ReaderV2SpanStyleRange {
    const resolved = ReaderRegexBubbleStyleResolver.resolve(rule, this.emphasisContext());
    const ui = this.getUIContext();
    const style = new ReaderV2SpanStyleRange();
    style.fontSizePx = ui.fp2px(fontSize);
    style.fontWeight = fontWeight;
    style.fontFamily = family;
    style.colorEnabled = true;
    style.color = ReaderV2Color.parse(resolved.textColor,
      ReaderV2Color.parse(this.readerTheme.textColor, 0xFF202124));
    style.backgroundEnabled = resolved.backgroundEnabled;
    style.backgroundColor = ReaderV2Color.parse(resolved.backgroundColor, 0);
    style.radiusTopLeftPx = ui.vp2px(resolved.radiusTopLeft);
    style.radiusTopRightPx = ui.vp2px(resolved.radiusTopRight);
    style.radiusBottomLeftPx = ui.vp2px(resolved.radiusBottomLeft);
    style.radiusBottomRightPx = ui.vp2px(resolved.radiusBottomRight);
    style.shadowEnabled = resolved.textShadowRadius > 0;
    style.shadowColor = ReaderV2Color.parse(resolved.textShadowColor, 0);
    style.shadowRadiusPx = ui.vp2px(Math.max(0, resolved.textShadowRadius));
    style.shadowOffsetXPx = ui.vp2px(Math.max(0, resolved.textShadowOffsetX));
    style.shadowOffsetYPx = ui.vp2px(Math.max(0, resolved.textShadowOffsetY));
    style.decorationEnabled = resolved.bubbleDecorationEnabled &&
      ThemeAssetRegistry.hasRegexBubbleCap(resolved.bubbleStyleId);
    style.decorationStyleId = style.decorationEnabled ? resolved.bubbleStyleId : '';
    style.decorationSizePx = style.decorationEnabled ? ui.vp2px(Math.max(15, Math.min(22, fontSize * 0.72))) : 0;
    return style;
  }

  rangesOutsideTitle(start: number, end: number, titles: ReaderV2SpanStyleRange[]): number[][] {
    let ranges: number[][] = [[start, end]];
    for (const title of titles) {
      const next: number[][] = [];
      for (const range of ranges) {
        if (range[1] <= title.start || range[0] >= title.end) next.push(range);
        else {
          if (range[0] < title.start) next.push([range[0], title.start]);
          if (range[1] > title.end) next.push([title.end, range[1]]);
        }
      }
      ranges = next;
    }
    return ranges;
  }

  effectiveHorizontalMargin(left: boolean): number {
    return ReaderHorizontalMargin.effective(this.settings.marginLeft, this.settings.marginRight,
      this.previewWidth, this.settings.fontSize, left);
  }

  config(pageIndex: number = 0): ReaderTypographyPreviewConfig {
    const config = new ReaderTypographyPreviewConfig();
    const ui = this.getUIContext();
    const input = config.input;
    const title = ReaderTitleStyleCodec.decode(this.settings.titleStyleRaw);
    input.fontSizePx = ui.fp2px(this.settings.fontSize);
    input.fontWeight = this.settings.fontWeight;
    input.lineSpacingPx = ui.vp2px(this.settings.lineHeight);
    input.letterSpacingPx = ui.fp2px(this.settings.letterSpacing);
    input.paragraphSpacingPx = ui.vp2px(this.settings.paragraphSpacing);
    input.marginLeftPx = ui.vp2px(this.effectiveHorizontalMargin(true));
    input.marginRightPx = ui.vp2px(this.effectiveHorizontalMargin(false));
    input.marginTopPx = ui.vp2px(this.bodyTop());
    input.marginBottomPx = ui.vp2px(this.bodyBottom());
    input.textAlign = this.settings.textAlign;
    input.bodyFontFamily = this.fontFamily(this.settings.bodyFontMode, this.settings.bodyFontFamily);
    input.titleFontFamily = this.fontFamily(this.settings.titleFontMode, this.settings.titleFontFamily);
    input.titleFontSizePx = ui.fp2px(this.settings.titleFontSize);
    input.titleFontWeight = this.settings.titleFontWeight;
    input.titleSecondaryScale = title.secondaryScale;
    input.titleLineGapPx = ui.vp2px(title.mode === 'off' ? this.settings.lineHeight : title.lineGap);
    input.titleAlignment = title.alignment;
    input.titleMarginTopPx = ui.vp2px(title.marginTop);
    input.titleMarginBottomPx = ui.vp2px(title.marginBottom);
    input.titleSinglePage = title.singlePage;
    input.textColor = ReaderV2Color.parse(this.readerTheme.textColor, 0xFF202124);
    input.regexEnabled = this.settings.regexFontEnabled;
    input.styleIdentity = `settings_preview_${this.revision}`;
    const bubbleContext = this.emphasisContext();
    bubbleContext.inheritedMode = 'bubble';
    const bubble = ReaderRegexBubbleStyleResolver.resolve(null, bubbleContext);
    input.commentBubble = ReaderCommentBubbleStyles.resolve(bubble.bubbleStyleId, this.darkMode, this.readerTheme.textColor);
    input.commentBubbleSize = this.settings.commentBubbleSize;
    input.commentFontSizePx = ui.fp2px(Math.max(10, this.settings.fontSize - 5));
    config.fontSizeVp = this.settings.fontSize;
    config.viewportHeightVp = Math.max(1, this.previewHeight);
    config.paginated = true;
    config.pageIndex = title.singlePage ? pageIndex : 0;
    const indent = '　'.repeat(this.settings.paragraphIndent);
    const body = SETTINGS_PREVIEW_PARAGRAPHS.map((paragraph: string, index: number): string =>
      indent + paragraph + ReaderActionMarker.create(index % 2 === 0 ? '12' : '3',
        'preview:paragraph', '段评示例')).join('\n');
    config.document = ReaderV2DocumentParser.parse(SETTINGS_PREVIEW_TITLE + '\n' + body,
      0, SETTINGS_PREVIEW_TITLE, [], title);
    if (title.emphasis.emphasisMode !== 'none') {
      for (const block of config.document.blocks) {
        if (!block.title) continue;
        const fontSize = this.settings.titleFontSize * (block.titleSegment > 0 ? title.secondaryScale : 1);
        const style = this.spanStyle(title.emphasis, fontSize, input.titleFontFamily, this.settings.titleFontWeight);
        style.start = block.displayStart;
        style.end = block.displayEnd;
        style.repeatCaps = true;
        config.styles.push(style);
      }
    }
    const legacy = new ReaderRegexLegacySettings();
    legacy.pattern = this.settings.regexFontPattern;
    legacy.fontMode = this.settings.regexFontMode;
    legacy.fontFamily = this.settings.regexFontFamily;
    legacy.fontSize = this.settings.regexFontSize;
    legacy.shadowColor = this.settings.regexShadowColor;
    const rules = this.settings.regexFontEnabled ? ReaderRegexFontCodec.decode(this.settings.regexFontRulesRaw, legacy) : [];
    const content = config.document.displayText;
    const titleStyles = config.styles.slice();
    const matched: ReaderV2SpanStyleRange[] = [];
    for (const rule of rules) {
      if (!rule.pattern.trim()) continue;
      let expression: RegExp;
      try { expression = new RegExp(rule.pattern, 'g'); } catch (_) { continue; }
      let match = expression.exec(content);
      while (match) {
        const start = match.index;
        const end = start + match[0].length;
        if (end > start && !matched.some((existing: ReaderV2SpanStyleRange): boolean =>
          start < existing.end && end > existing.start)) {
          matched.push(new ReaderV2SpanStyleRange(start, end));
          // 先按规则顺序确定命中，再只裁去标题占用的部分，保留跨标题命中的正文样式。
          for (const bounds of this.rangesOutsideTitle(start, end, titleStyles)) {
            const style = this.spanStyle(rule, rule.fontSize,
              this.fontFamily(rule.fontMode, rule.fontFamily), rule.fontWeight);
            style.start = bounds[0];
            style.end = bounds[1];
            config.styles.push(style);
          }
        }
        if (end <= start) expression.lastIndex = Math.max(expression.lastIndex + 1, start + 1);
        match = expression.exec(content);
      }
    }
    config.styles = titleStyles.concat(config.styles.slice(titleStyles.length)
      .sort((left: ReaderV2SpanStyleRange, right: ReaderV2SpanStyleRange): number => left.start - right.start));
    return config;
  }

  @Builder
  infoLine(header: boolean, pageIndex: number) {
    ReaderInfoBarRow({
      leftText: ReaderInfoBarText.leading(header ? this.info().headerLeft : this.info().footerLeft, this.infoContext(pageIndex)),
      centerText: ReaderInfoBarText.leading(header ? this.info().headerCenter : this.info().footerCenter, this.infoContext(pageIndex)),
      rightText: ReaderInfoBarText.leading(header ? this.info().headerRight : this.info().footerRight, this.infoContext(pageIndex)),
      leftBattery: ReaderInfoBarText.battery(header ? this.info().headerLeft : this.info().footerLeft, this.infoContext(pageIndex)),
      centerBattery: ReaderInfoBarText.battery(header ? this.info().headerCenter : this.info().footerCenter, this.infoContext(pageIndex)),
      rightBattery: ReaderInfoBarText.battery(header ? this.info().headerRight : this.info().footerRight, this.infoContext(pageIndex)),
      textSize: header ? this.info().headerFontSize : this.info().footerFontSize,
      textColor: this.info().textColor(header, this.appDarkMode, this.readerTheme.subTextColor),
      textOpacity: (header ? this.info().headerOpacity : this.info().footerOpacity) / 100
    })
  }

  @Builder
  infoRule(header: boolean) {
    if (this.info().progressBar === (header ? ReaderInfoProgressBar.HEADER : ReaderInfoProgressBar.FOOTER)) {
      Stack({ alignContent: Alignment.Start }) {
        Row().width('100%').height(2).backgroundColor(this.readerTheme.subTextColor).opacity(0.15)
        Row().width('8.3%').height(2).backgroundColor(ThemeRuntime.accentColor(this.darkMode))
      }
      .width('100%')
      .height(2)
    } else if (header ? this.info().headerDivider : this.info().footerDivider) {
      Row().width('100%').height(0.5).backgroundColor(this.readerTheme.subTextColor).opacity(0.3)
    }
  }

  @Builder
  previewPage(pageIndex: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      ReaderThemeBackground({ surfaceColor: this.readerTheme.backgroundColor,
        backgroundAssetId: this.readerTheme.backgroundAssetId, customImage: this.readerTheme.backgroundImageUri,
        customImageFit: this.readerTheme.backgroundImageFit === 'contain' ? ImageFit.Contain :
          (this.readerTheme.backgroundImageFit === 'fill' ? ImageFit.Fill : ImageFit.Cover) })
      if (this.previewHeight > 0) {
        ReaderTypographyPreview({ config: this.config(pageIndex) })
          .width('100%')
          .height('100%')
          .clip(true)
      }
      if (this.headerVisible()) {
        Column({ space: 3 }) {
          this.infoLine(true, pageIndex)
          this.infoRule(true)
        }
        .width('100%')
        .padding({ left: this.info().sidePadding(true, true, this.effectiveHorizontalMargin(true), this.effectiveHorizontalMargin(false), this.previewWidth),
          right: this.info().sidePadding(true, false, this.effectiveHorizontalMargin(true), this.effectiveHorizontalMargin(false), this.previewWidth) })
        .position({ x: 0, y: this.headerTop() })
      }
      if (this.settings.readerFooterEnabled) {
        Column({ space: 3 }) {
          this.infoRule(false)
          this.infoLine(false, pageIndex)
        }
        .width('100%')
        .padding({ left: this.info().sidePadding(false, true, this.effectiveHorizontalMargin(true), this.effectiveHorizontalMargin(false), this.previewWidth),
          right: this.info().sidePadding(false, false, this.effectiveHorizontalMargin(true), this.effectiveHorizontalMargin(false), this.previewWidth) })
        .position({ x: 0, y: this.footerTop() })
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.titleSinglePage()) {
        Swiper(this.previewPager) {
          this.previewPage(0)
          this.previewPage(1)
        }
        .id('settings_preview_pages')
        .width('100%')
        .height('100%')
        .index(this.previewPageIndex)
        .loop(false)
        .indicator(false)
        .disableSwipe(!this.allowPageSwipe)
        .duration(180)
        .onChange((index: number) => { this.onPageSelected(index); })
      } else {
        this.previewPage(0)
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onAreaChange((_previous: Area, current: Area) => {
      const nextWidth = Number(current.width);
      const nextHeight = Number(current.height);
      if (nextWidth > 0 && Math.abs(nextWidth - this.previewWidth) >= 1) this.previewWidth = nextWidth;
      if (nextHeight > 0 && Math.abs(nextHeight - this.previewHeight) >= 1) this.previewHeight = nextHeight;
    })
  }
}

/** 换页控件由悬浮面板承载，避免遮住阅读页的页眉页脚。 */
@Component
export struct ReaderSettingsPreviewNavigation {
  @Prop selectedIndex: number = 0;
  @Prop darkMode: boolean = false;
  @Prop navigationWidth: number = 180;
  onSelect: (index: number) => void = (_index: number): void => {};

  @Builder
  navigationContent() {
    Stack({ alignContent: Alignment.Start }) {
      Stack() {
        ImmersiveMaterialSurface({ surfaceWidth: (this.navigationWidth - 8) / 2, surfaceHeight: 32,
          darkMode: this.darkMode, fallbackColor: ThemeRuntime.accentSurfaceColor(this.darkMode) }) { Stack() }
      }
      .width((this.navigationWidth - 8) / 2)
      .height(32)
      .translate({ x: this.selectedIndex * (this.navigationWidth - 8) / 2 })
      .animation({ duration: 180, curve: Curve.EaseOut })
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
      Row() {
        ForEach(['标题页', '正文页'], (label: string, index: number) => {
          Button(label, { type: ButtonType.Capsule, stateEffect: true })
            .id(`settings_preview_page_${index}`)
            .height(32)
            .layoutWeight(1)
            .fontSize(13)
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .backgroundColor(Color.Transparent)
            .accessibilitySelected(this.selectedIndex === index)
            .onClick(() => { this.onSelect(index); })
        }, (label: string) => label)
      }.width('100%')
    }.width(this.navigationWidth - 8).height(32)
  }

  build() {
    ImmersiveMaterialSurface({ surfaceWidth: this.navigationWidth, surfaceHeight: 40,
      darkMode: this.darkMode, fallbackColor: ThemeRuntime.cardColor(this.darkMode) }) {
      this.navigationContent()
    }
  }
}
