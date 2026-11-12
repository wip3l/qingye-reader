import { ThemeImageCrop } from '../../theme/share/ThemePackageFormat';

/**
 * 按显示区域画主题素材（动图取景，见 ThemeImageCrop）：区域等比放大到盖满本组件，居中对齐，裁掉多余部分
 * （同 CSS 的 object-view-box 加 object-fit: cover）；区域比例和本组件不同时，裁掉的是区域两边多出的部分。
 * 图片文件不改，动图照常播放。
 * 尺寸由调用方给本组件设宽高。位置和大小都按本组件的百分比给，量到自身大小之前先按区域拉伸铺满。
 */
@Component
export struct ThemeCroppedImage {
  @Prop src: ResourceStr = '';
  @Prop crop: ThemeImageCrop = new ThemeImageCrop();
  @Prop syncLoad: boolean = false;
  /**
   * 大于 0 时按这个宽高比排区域、再拉伸到本组件的实际大小：本组件会被整体非等比缩放成另一种比例时用
   * （开书动画里整页缩到书架封面），排出来和书架上那枚封面一致。
   */
  @Prop boxAspect: number = 0;
  onLoaded: () => void = (): void => {};
  onFailed: () => void = (): void => {};
  @State private boxWidth: number = 0;
  @State private boxHeight: number = 0;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(this.src)
        .syncLoad(this.syncLoad)
        .objectFit(ImageFit.Fill)
        .draggable(false)
        .width(this.percent(0))
        .height(this.percent(1))
        .position({ x: this.percent(2), y: this.percent(3) })
        .onComplete(() => this.onLoaded())
        .onError(() => this.onFailed())
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onAreaChange((_old: Area, area: Area) => {
      this.boxWidth = Number(area.width);
      this.boxHeight = Number(area.height);
    })
  }

  /** 排区域时假定的组件宽高比；还没量到时用区域自己的比例，即区域拉伸铺满。 */
  private layoutAspect(): number {
    if (this.boxAspect > 0) return this.boxAspect;
    if (this.boxWidth > 0 && this.boxHeight > 0) return this.boxWidth / this.boxHeight;
    return this.crop.height > 0 ? this.crop.width / this.crop.height : 1;
  }

  /** 0 宽、1 高、2 左、3 上，都是相对本组件的百分比。 */
  private percent(index: number): string {
    const crop = this.crop;
    if (crop.width <= 0 || crop.height <= 0 || crop.imageWidth <= 0 || crop.imageHeight <= 0) {
      return index < 2 ? '100%' : '0%';
    }
    // 在宽 aspect、高 1 的假想框里排：区域等比盖满，中心对齐，再把图夹回框内不露底。
    const aspect = this.layoutAspect();
    const scale = Math.max(aspect / crop.width, 1 / crop.height);
    const drawWidth = crop.imageWidth * scale;
    const drawHeight = crop.imageHeight * scale;
    const left = Math.min(0, Math.max(aspect - drawWidth, aspect / 2 - (crop.x + crop.width / 2) * scale));
    const top = Math.min(0, Math.max(1 - drawHeight, 0.5 - (crop.y + crop.height / 2) * scale));
    const values = [drawWidth / aspect, drawHeight, left / aspect, top];
    return `${values[index] * 100}%`;
  }
}
