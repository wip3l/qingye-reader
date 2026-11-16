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
    if (tokens.dropCapLines >= 2) {
      style.capLines = tokens.dropCapLines === 3 ? 3 : 2;
      // 印章图读不出来时只放大。
      if (tokens.dropCapImage && ImageFileSize.aspect(tokens.dropCapImage) > 0) style.capImage = tokens.dropCapImage;
      if (tokens.dropCapColor) style.capColor = ReaderV2Color.parse(tokens.dropCapColor, 0);
      style.capRatio = tokens.dropCapRatio > 0 ? tokens.dropCapRatio : 0.62;
    }
    return style;
  }

  /** 设置页的说明：当前主题带了什么。 */
  static describe(tokens: ThemePackageChapterHead | null | undefined): string {
    const names: string[] = [];
    if (tokens && tokens.image) names.push('标题饰图');
    if (tokens && tokens.numberColor) names.push('序号行颜色（开了标题分段才看得出）');
    if (tokens && tokens.dropCapLines >= 2) names.push('正文首字');
    return names.length > 0 ? `当前主题带了${names.join('、')}` : '当前主题没有章首装饰';
  }
}
