import { AppFontSize } from '../../theme/AppFontSize';
import { ThemeRuntime } from '../../theme/ThemeRuntime';

/** Shared by the reading settings and the single-page coloring preview. */
@Component
export struct ComicColorDownloadProgress {
  @Prop receivedBytes: number = 0;
  @Prop totalBytes: number = 0;
  @Prop accent: string = ThemeRuntime.accentColor(false);
  @Prop labelColor: string = ThemeRuntime.subTextColor(false);

  private percent(): number {
    return this.totalBytes > 0 ? Math.min(100, Math.max(0, this.receivedBytes / this.totalBytes * 100)) : 0;
  }

  build() {
    Column({ space: 8 }) {
      Progress({ value: this.percent(), total: 100, type: ProgressType.Linear })
        .color(this.accent)
        .width('100%')
        .accessibilityText(`模型下载进度 ${Math.floor(this.percent())}%`)
      Row() {
        Text(`${(this.receivedBytes / 1024 / 1024).toFixed(1)} / ${(this.totalBytes / 1024 / 1024).toFixed(1)} MB`)
          .layoutWeight(1)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.labelColor)
        Text(`${Math.floor(this.percent())}%`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.labelColor)
      }
      .width('100%')
    }
    .width('100%')
  }
}
