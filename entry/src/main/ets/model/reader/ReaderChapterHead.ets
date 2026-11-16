import { ThemePackageChapterHead } from '../../theme/share/ThemePackageFormat';
import { ReaderV2ChapterHeadStyle } from '../../core/reader/ReaderV2LayoutSnapshot';
import { ReaderV2Color } from '../../core/reader/ReaderV2Style';
import { ImageFileSize } from '../../utils/ImageFileSize';
import { ReaderChapterDecoration } from './ReaderTitleStyle';

export class ReaderChapterHead {
  /**
   * 主题的章首装饰换成排版用的样式。读者关掉章首装饰、主题没设、饰图读不出尺寸时对应的部分为空。
   */
  static style(tokens: ThemePackageChapterHead | null | undefined, decoration: string): ReaderV2ChapterHeadStyle {
    const style = new ReaderV2ChapterHeadStyle();
    if (!tokens || ReaderChapterDecoration.normalize(decoration) === ReaderChapterDecoration.OFF) return style;
    if (tokens.image) {
      const aspect = ImageFileSize.aspect(tokens.image);
      if (aspect > 0) {
        style.image = tokens.image;
        style.aspect = aspect;
        style.placement = tokens.placement === 'top' || tokens.placement === 'bottom' ? tokens.placement : 'side';
        style.scale = tokens.scale > 0 ? tokens.scale : 1;
      }
    }
    if (tokens.numberColor) style.numberColor = ReaderV2Color.parse(tokens.numberColor, 0);
    return style;
  }

  /** 设置页的说明：当前主题带了什么。 */
  static describe(tokens: ThemePackageChapterHead | null | undefined): string {
    const image = !!tokens && !!tokens.image;
    const color = !!tokens && !!tokens.numberColor;
    if (image && color) return '当前主题带了标题饰图和序号行颜色';
    if (image) return '当前主题带了标题饰图';
    if (color) return '当前主题带了序号行颜色（开了标题分段才看得出）';
    return '当前主题没有章首装饰';
  }
}
