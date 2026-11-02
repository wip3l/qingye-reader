import { ReaderV2RegexBubbleSegment } from '../../core/reader/ReaderV2PageLayout';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';

/** 正文阅读与整页预览共用同一组主题端饰，坐标直接来自 V2 分页结果。 */
@Component
export struct ReaderV2RegexBubbleCaps {
  @Prop segment: ReaderV2RegexBubbleSegment = new ReaderV2RegexBubbleSegment();

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.segment.leading && this.segment.leadingCapWidthPx > 0.5) {
        Image(ThemeAssetRegistry.regexBubbleCap(this.segment.styleId))
          .id('reader_regex_bubble_leading_cap')
          .width(this.getUIContext().px2vp(this.segment.capSizePx))
          .height(this.getUIContext().px2vp(this.segment.capSizePx))
          .objectFit(ImageFit.Contain)
          .position({
            x: this.getUIContext().px2vp(this.segment.rect.left),
            y: this.getUIContext().px2vp(this.segment.rect.top +
              (this.segment.rect.height() - this.segment.capSizePx) / 2)
          })
          .hitTestBehavior(HitTestMode.None)
      }
      if (this.segment.trailing && this.segment.trailingCapWidthPx > 0.5) {
        Image(ThemeAssetRegistry.regexBubbleCap(this.segment.styleId))
          .id('reader_regex_bubble_trailing_cap')
          .width(this.getUIContext().px2vp(this.segment.capSizePx))
          .height(this.getUIContext().px2vp(this.segment.capSizePx))
          .objectFit(ImageFit.Contain)
          .rotate({ angle: 180 })
          .position({
            x: this.getUIContext().px2vp(this.segment.rect.right - this.segment.capSizePx),
            y: this.getUIContext().px2vp(this.segment.rect.top +
              (this.segment.rect.height() - this.segment.capSizePx) / 2)
          })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
  }
}
