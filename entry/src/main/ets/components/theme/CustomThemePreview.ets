import { ThemePack, ThemeVariant } from '../../theme/ThemeModels';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { BuiltinThemeRegistry } from '../../theme/BuiltinThemeRegistry';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ReaderSettings } from '../../utils/ReaderSettingsStore';
import { ReaderThemeBackground } from '../ReaderThemeBackground';
import { ThemeStartupCover } from '../ThemeStartupCover';
import { TtsPanelThemeBackground } from '../TtsPanelThemeBackground';
import { BookCover } from '../book/BookCover';

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
  @Prop ttsThemeId: string = '';
  @Prop readerSettings: ReaderSettings = new ReaderSettings();
  @Prop useReaderProfile: boolean = false;

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
          explicitText: true
        })
      } else if (this.scene === 'reader') {
        this.readerPreview()
      } else if (this.scene === 'tts') {
        this.ttsPreview()
      } else {
        this.bookshelfPreview()
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

  @Builder
  bookshelfPreview() {
    Column({ space: AppSpacing.MD }) {
      Row() {
        Text('我的书架')
          .fontFamily(this.themePack.typography.appFontFamily)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.variant().colors.primaryTextColor)
          .layoutWeight(1)
        Text('最近阅读')
          .fontFamily(this.themePack.typography.appFontFamily)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.variant().colors.accentColor)
      }
      Row({ space: AppSpacing.XL }) {
        ForEach(['山野来信', '长夜微光', '人间草木'], (name: string) => {
          Column({ space: AppSpacing.XS }) {
            Stack() {
              if (this.themePack.book.coverAssetId) {
                Image(ThemeAssetRegistry.themeBookCover(this.themePack.book.coverAssetId))
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
            .width(this.expanded ? 86 : 58)
            .height(this.expanded ? 122 : 82)
            Text(name)
              .fontFamily(this.themePack.typography.appFontFamily)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.variant().colors.primaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
        }, (name: string) => name)
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      Row() {
        ForEach(['bookshelf', 'explore', 'search', 'mine'], (tabId: string) => {
          Image(ThemeAssetRegistry.navigationIcon(this.themePack.navigation.iconPackId, tabId))
            .width(20)
            .height(20)
            .fillColor(tabId === 'bookshelf' ? this.variant().colors.accentColor : this.variant().colors.subTextColor)
        }, (tabId: string) => tabId)
      }
      .width('100%')
      .height(36)
      .justifyContent(FlexAlign.SpaceAround)
      .borderRadius(this.themePack.radius.medium)
      .backgroundColor(this.variant().colors.cardColor)
    }
    .width('100%')
    .height('100%')
    .padding(AppSpacing.LG)
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
        Text('把时光，留给阅读')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.variant().regexEmphasis.emphasisTextColor)
          .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
          .borderRadius(this.themePack.radius.bubble)
          .backgroundColor(this.variant().regexEmphasis.emphasisColor)
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
