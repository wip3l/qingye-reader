import { ReaderV2RegexBubbleSegment } from '../../core/reader/ReaderV2PageLayout';
import { ThemeAssetRegistry } from '../../theme/ThemeAssetRegistry';

/**
 * 正文阅读与整页预览共用同一组主题端饰，坐标直接来自 V2 分页结果。
 * 调用方必须放在铺满页面的 TopStart Stack 里。这里不建自定义组件：一页常有十来个气泡，逐个创建带 @Prop
 * 深拷贝和满版 Stack 的组件，会让翻页开始和结束的那一帧各多出几毫秒的创建、销毁开销。
 */
@Builder
export function ReaderV2RegexBubbleCapImages(segment: ReaderV2RegexBubbleSegment, uiContext: UIContext) {
  if (segment.leading && segment.leadingCapWidthPx > 0.5) {
    Image(ThemeAssetRegistry.regexBubbleCap(segment.styleId))
      .id('reader_regex_bubble_leading_cap')
      .width(uiContext.px2vp(segment.capSizePx))
      .height(uiContext.px2vp(segment.capSizePx))
      .objectFit(ImageFit.Contain)
      .position({
        x: uiContext.px2vp(segment.rect.left),
        y: uiContext.px2vp(segment.rect.top + (segment.rect.height() - segment.capSizePx) / 2)
      })
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
  }
  if (segment.trailing && segment.trailingCapWidthPx > 0.5) {
    Image(ThemeAssetRegistry.regexBubbleCap(segment.styleId))
      .id('reader_regex_bubble_trailing_cap')
      .width(uiContext.px2vp(segment.capSizePx))
      .height(uiContext.px2vp(segment.capSizePx))
      .objectFit(ImageFit.Contain)
      .rotate({ angle: 180 })
      .position({
        x: uiContext.px2vp(segment.rect.right - segment.capSizePx),
        y: uiContext.px2vp(segment.rect.top + (segment.rect.height() - segment.capSizePx) / 2)
      })
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
  }
}
