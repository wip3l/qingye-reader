import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { ThemeIds, ThemePack, ThemeVariant } from '../theme/ThemeModels';
import { StartupCoverTextStore } from '../utils/StartupCoverTextStore';

@Component
export struct ThemeStartupCover {
  @Prop themeId: string = ThemeIds.PLAIN_DEFAULT;
  @Prop darkMode: boolean = false;
  @Prop compact: boolean = false;
  @Prop animated: boolean = false;
  @Prop customImagePath: string = '';
  @Prop titleOverride: string = '';
  @Prop subtitleOverride: string = '';
  @Prop explicitText: boolean = false;
  // 方案的文案样式覆盖；空 / 0 用默认。
  @Prop titleColor: string = '';
  @Prop subtitleColor: string = '';
  @Prop titleSize: number = 0;
  @Prop subtitleSize: number = 0;
  @Prop showTextEditButton: boolean = false;
  onEditText: () => void = (): void => {};
  @StorageLink('startupCoverTextsRevision') startupCoverTextsRevision: number = 0;
  @State artScale: number = 1;
  @State contentOpacity: number = 1;
  @State viewportHeight: number = 0;
  private entranceTimer: number = -1;

  aboutToAppear(): void {
    if (!this.animated || !this.usesBusinessCover()) return;
    this.artScale = 1.04;
    this.contentOpacity = 0;
    this.entranceTimer = setTimeout(() => {
      this.entranceTimer = -1;
      animateTo({ duration: 520, curve: Curve.EaseOut }, () => {
        this.artScale = 1;
        this.contentOpacity = 1;
      });
    }, 24);
  }

  aboutToDisappear(): void {
    if (this.entranceTimer >= 0) {
      clearTimeout(this.entranceTimer);
      this.entranceTimer = -1;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (!this.usesBusinessCover()) {
        // 仅在主题设置的预览框中展示系统启动页的 App 图标。
        // 默认主题真实冷启动由 EntryAbility 直接加载首页，不绘制业务启动页。
        if (this.compact) {
          Image($r('app.media.icon'))
            .width(48)
            .height(48)
            .objectFit(ImageFit.Contain)
            .draggable(false)
        }
      } else {
        // 使用参考主题封面视觉语言重新绘制的独立启动插画，不复用书籍封面本身。
        Image(this.customImagePath || ThemeAssetRegistry.startupBackground(this.resolvedThemeId(), this.darkMode))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(this.contentOpacity * (this.isObsidianArtwork() ? 1 : (this.darkMode ? 0.62 : 1)))
          .scale({ x: this.artScale, y: this.artScale })
          .draggable(false)

        Row()
          .width('100%')
          .height('100%')
          .backgroundColor(this.isObsidianArtwork() ? '#00000000' : (this.darkMode ? '#42000000' : '#0AFFFFFF'))
          .opacity(this.contentOpacity)

        // Keep the fade attached to the current viewport bottom. A percentage
        // y-position plus a fixed height leaves a bright strip above the
        // navigation indicator on tall screens and after a fold-state change.
        Column() {
          Blank()
            .layoutWeight(1)

          Column()
            .width('100%')
            .height(this.bottomFadeHeight())
            .linearGradient({
              angle: 180,
              colors: [['#00000000', 0], [this.darkMode ? '#CC000000' : '#8F000000', 1]]
            })
            // The startup page is edge-to-edge. Expanding the fade itself is
            // required; expanding only the page does not expand child layout.
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
        .width('100%')
        .height('100%')
        .opacity(this.contentOpacity)
        .hitTestBehavior(HitTestMode.None)

        Column() {
          Blank()
          Row({ space: this.compact ? 7 : 0 }) {
            Column() {
              if (this.coverTitle()) {
                Text(this.coverTitle())
                  .fontSize(this.scaledSize(this.titleSize, 21, 11))
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.theme().typography.appFontFamily)
                  .fontColor(this.titleColor || (this.isObsidianArtwork() ? '#E4CCA0' : '#FFFFFF'))
                  .letterSpacing(this.compact ? 1.2 : 4)
                  .textAlign(TextAlign.Center)
                  .opacity(this.contentOpacity * 0.94)
              }
              if (this.coverSubtitle()) {
                Text(this.coverSubtitle())
                  .fontSize(this.scaledSize(this.subtitleSize, 12, 7))
                  .fontFamily(this.theme().typography.appFontFamily)
                  .fontColor(this.subtitleColor || (this.isObsidianArtwork() ? '#C8BAA1' : '#D9FFFFFF'))
                  .letterSpacing(this.compact ? 0.3 : 1.2)
                  .textAlign(TextAlign.Center)
                  .margin({ top: this.compact ? 2 : 8 })
                  .opacity(this.contentOpacity)
              }
            }
            .alignItems(HorizontalAlign.Center)
            .hitTestBehavior(HitTestMode.None)

            if (this.compact && this.showTextEditButton) {
              Button('编辑文案', { type: ButtonType.Normal })
                .height(24)
                .padding({ left: 7, right: 7 })
                .fontSize(10)
                .fontColor('#F2FFFFFF')
                .backgroundColor('#42000000')
                .border({ width: 0.5, color: '#55FFFFFF' })
                .onClick(() => this.onEditText())
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .padding({ bottom: this.compact ? 8 : 34 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.variant().colors.pageColor)
    // Full-screen children may expand into system safe areas; previews still
    // need clipping for their rounded-card bounds.
    .clip(this.compact)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const height = this.areaDimension(newValue.height);
      if (height > 0 && Math.abs(height - this.viewportHeight) >= 1) {
        this.viewportHeight = height;
      }
    })
  }

  bottomFadeHeight(): number {
    if (this.compact) return 58;
    if (this.viewportHeight <= 0) return 190;
    // Use the live ArkUI viewport rather than a device model or cached display
    // size. It is recalculated for outer/inner fold displays and multi-window.
    return Math.max(168, Math.min(300, this.viewportHeight * 0.26));
  }

  areaDimension(value: Length): number {
    if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  /** 预览卡按默认字号的比例缩小自定义字号。 */
  scaledSize(custom: number, normal: number, compact: number): number {
    if (custom <= 0) return this.compact ? compact : normal;
    return this.compact ? Math.max(6, Math.round(custom * compact / normal)) : custom;
  }

  isDefaultTheme(): boolean {
    return this.resolvedThemeId() === ThemeIds.PLAIN_DEFAULT;
  }

  isObsidianArtwork(): boolean {
    return !this.customImagePath && this.resolvedThemeId() === ThemeIds.OBSIDIAN_ARCHIVE;
  }

  usesBusinessCover(): boolean {
    return !!this.customImagePath || !this.isDefaultTheme();
  }

  resolvedThemeId(): string {
    return BuiltinThemeRegistry.normalizeBuiltinId(this.themeId);
  }

  theme(): ThemePack {
    return BuiltinThemeRegistry.findById(this.resolvedThemeId());
  }

  variant(): ThemeVariant {
    const theme = this.theme();
    return this.darkMode ? theme.dark : theme.light;
  }

  coverTitle(): string {
    if (this.explicitText) return this.titleOverride;
    return StartupCoverTextStore.title(this.resolvedThemeId(), '开源轻页');
  }

  coverSubtitle(): string {
    if (this.explicitText) return this.subtitleOverride;
    const id = this.resolvedThemeId();
    return StartupCoverTextStore.subtitle(id, StartupCoverTextStore.defaultSubtitle(id));
  }
}
