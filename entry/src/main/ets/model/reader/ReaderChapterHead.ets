import { ThemePackageChapterHead } from '../../theme/share/ThemePackageFormat';
import { ReaderV2ChapterHeadStyle } from '../../core/reader/ReaderV2LayoutSnapshot';
import { ReaderV2Color } from '../../core/reader/ReaderV2Style';
import { ReaderRasterAssets } from '../../core/reader/ReaderRasterAssets';
import { ReaderChapterDecoration, ReaderDropCapMode } from './ReaderTitleStyle';

export class ReaderChapterHead {
  /**
   * 主题的章首装饰换成排版用的样式。decoration 管标题饰图和序号行颜色，dropCap 管首字装饰（取值见
   * ReaderDropCapMode），读者各自可以关；关掉的、主题没设的、图读不出尺寸的那部分为空。
   * 读者自选下沉/放大时行数用 dropCapLines，主题没设首字也照样做（只放大字），印章图和颜色仍取自主题。
   */
  static style(tokens: ThemePackageChapterHead | null | undefined, decoration: string,
    dropCap: string, dropCapLines: number): ReaderV2ChapterHeadStyle {
    const style = new ReaderV2ChapterHeadStyle();
    const titleOn = ReaderChapterDecoration.normalize(decoration) !== ReaderChapterDecoration.OFF;
    if (tokens && titleOn && tokens.image) {
      const aspect = ReaderRasterAssets.imageAspect(tokens.image);
      if (aspect > 0) {
        style.image = tokens.image;
        style.aspect = aspect;
        style.placement = tokens.placement === 'top' || tokens.placement === 'bottom' ? tokens.placement : 'side';
        style.scale = tokens.scale > 0 ? tokens.scale : 1;
      }
    }
    if (tokens && titleOn && tokens.numberColor) style.numberColor = ReaderV2Color.parse(tokens.numberColor, 0);
    const mode = ReaderDropCapMode.normalize(dropCap);
    if (mode === ReaderDropCapMode.OFF) return style;
    if (mode === ReaderDropCapMode.THEME) {
      if (!tokens || tokens.dropCapLines < 2) return style;
      style.capLines = tokens.dropCapLines === 3 ? 3 : 2;
    } else {
      style.capLines = ReaderDropCapMode.normalizeLines(dropCapLines);
      style.capRaise = mode === ReaderDropCapMode.RAISE;
    }
    if (tokens) {
      // 印章图读不出来时只放大。
      if (tokens.dropCapImage && ReaderRasterAssets.imageAspect(tokens.dropCapImage) > 0) {
        style.capImage = tokens.dropCapImage;
      }
      if (tokens.dropCapColor) style.capColor = ReaderV2Color.parse(tokens.dropCapColor, 0);
      if (tokens.dropCapRatio > 0) style.capRatio = tokens.dropCapRatio;
    }
    return style;
  }

  /** 设置页“标题装饰”的说明：当前主题带了什么。 */
  static describeTitle(tokens: ThemePackageChapterHead | null | undefined): string {
    const names: string[] = [];
    if (tokens && tokens.image) names.push('标题饰图');
    if (tokens && tokens.numberColor) names.push('序号行颜色（开了标题分段才看得出）');
    return names.length > 0 ? `当前主题带了${names.join('、')}` : '当前主题没有标题装饰';
  }

  /** 设置页“首字装饰”的说明。 */
  static describeDropCap(tokens: ThemePackageChapterHead | null | undefined): string {
    if (!tokens || tokens.dropCapLines < 2) return '当前主题没有设首字';
    return `当前主题：下沉 ${tokens.dropCapLines} 行${tokens.dropCapImage ? '，垫印章' : ''}`;
  }
}
