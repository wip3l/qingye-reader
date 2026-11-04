import fileUri from '@ohos.file.fileuri';
import { ReaderImageMarker } from '../../core/book/ReaderImageMarker';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';

/**
 * EPUB 注释正文：普通阅读页和原版排版页共用。blocks 是 EpubNoteLink.blocks 拆好的段落或图片标记。
 * 在点击处弹出时宽度受 popupWidth 限制、超高可滚动；放进半模态时铺满宽度。
 */
@Component
export struct ReaderNoteContent {
  @Prop label: string = '';
  @Prop blocks: string[] = [];
  @Prop dark: boolean = false;
  @Prop sheet: boolean = false;
  @Prop popupWidth: number = 320;

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Text(this.label ? `注释 ${this.label}` : '注释')
          .fontSize(13)
          .fontColor(ThemeRuntime.subTextColor(this.dark))
        ForEach(this.blocks, (block: string): void => {
          if (ReaderImageMarker.isMarker(block)) {
            Image(fileUri.getUriFromPath(ReaderImageMarker.parse(block).source))
              .width('100%')
              .objectFit(ImageFit.Contain)
              .borderRadius(8)
          } else {
            Text(block)
              .width('100%')
              .fontSize(16)
              .lineHeight(26)
              .fontColor(ThemeRuntime.primaryTextColor(this.dark))
              .copyOption(CopyOptions.LocalDevice)
          }
        }, (block: string, index: number): string => `${index}_${block.length}_${block.substring(0, 24)}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(this.sheet ? { left: 20, right: 20, top: 8, bottom: 24 } : 16)
    }
    .width(this.sheet ? '100%' : this.popupWidth)
    .constraintSize(this.sheet ? {} : { maxHeight: Math.floor(ImmersiveMaterialRuntime.popupMenuMaxHeight() * 0.7) })
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
  }
}
