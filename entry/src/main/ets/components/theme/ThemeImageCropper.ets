import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ThemeRuntime } from '../../theme/ThemeRuntime';

/** 一次取景：素材槽的固定比例与输出上限。 */
export class ThemeCropRequest {
  uri: string = '';
  title: string = '';
  ratioWidth: number = 1;
  ratioHeight: number = 1;
  // 输出不超过这个宽度（按比例算高度）；原图更小时不放大。
  maxWidth: number = 1080;
  // 带透明的素材（文件夹插画、面板插画）存 PNG，照片类存 JPEG。
  png: boolean = false;
  // 连续取景多张时的第几张 / 共几张，只用于标题。
  index: number = 0;
  total: number = 1;
}

/**
 * 主题素材的取景层：双指缩放、拖动图片，框内按素材比例裁出来，存到缓存目录交给调用方。
 * 取景框里看到的就是解码后的同一张位图，裁出来的区域和看到的一致。
 */
@Component
export struct ThemeImageCropper {
  // 连续取景多张时组件不会重建，换请求时重新读图。
  @Prop @Watch('onRequestChange') request: ThemeCropRequest = new ThemeCropRequest();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  onDone: (path: string) => void = (_path: string): void => {};
  onOriginal: () => void = (): void => {};
  onCancel: () => void = (): void => {};
  @State private pixelMap: PixelMap | undefined = undefined;
  @State private imageWidth: number = 0;
  @State private imageHeight: number = 0;
  @State private areaWidth: number = 0;
  @State private areaHeight: number = 0;
  @State private zoom: number = 1;
  @State private offsetX: number = 0;
  @State private offsetY: number = 0;
  @State private working: boolean = false;
  @State private failed: boolean = false;
  private startZoom: number = 1;
  private startOffsetX: number = 0;
  private startOffsetY: number = 0;

  aboutToAppear(): void {
    this.decode();
  }

  onRequestChange(): void {
    this.releasePixelMap();
    this.working = false;
    this.failed = false;
    this.imageWidth = 0;
    this.imageHeight = 0;
    this.decode();
  }

  aboutToDisappear(): void {
    this.releasePixelMap();
  }

  build() {
    Column() {
      Row({ space: AppSpacing.MD }) {
        Button('取消', { type: ButtonType.Capsule })
          .height(36)
          .fontSize(AppFontSize.BODY)
          .fontColor('#FFFFFF')
          .backgroundColor('#2A2F35')
          .onClick(() => this.onCancel())
        Text(this.titleText())
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .maxLines(1)
        Button(this.working ? '处理中' : '使用', { type: ButtonType.Capsule })
          .height(36)
          .fontSize(AppFontSize.BODY)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeRuntime.accentColor(true))
          .enabled(!!this.pixelMap && !this.working)
          .onClick(() => this.confirm())
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: this.statusBarHeight })

      Stack() {
        if (this.pixelMap && this.areaWidth > 0) {
          Image(this.pixelMap)
            .width(this.displayWidth())
            .height(this.displayHeight())
            .position({ x: this.imageLeft(), y: this.imageTop() })
            .objectFit(ImageFit.Fill)
            .draggable(false)
          this.maskLayer()
        } else {
          Text(this.failed ? '这张图片打不开，换一张试试' : '正在读取图片…')
            .fontSize(AppFontSize.BODY)
            .fontColor('#C9CED4')
        }
      }
      .width('100%')
      .layoutWeight(1)
      .clip(true)
      .onAreaChange((_old: Area, area: Area) => {
        this.areaWidth = Number(area.width);
        this.areaHeight = Number(area.height);
        this.clampOffsets();
      })
      .gesture(
        GestureGroup(GestureMode.Parallel,
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              this.startZoom = this.zoom;
            })
            .onActionUpdate((event: GestureEvent) => {
              this.zoom = Math.max(1, Math.min(6, this.startZoom * event.scale));
              this.clampOffsets();
            }),
          PanGesture({ distance: 1 })
            .onActionStart(() => {
              this.startOffsetX = this.offsetX;
              this.startOffsetY = this.offsetY;
            })
            .onActionUpdate((event: GestureEvent) => {
              this.offsetX = this.startOffsetX + event.offsetX;
              this.offsetY = this.startOffsetY + event.offsetY;
              this.clampOffsets();
            })
        )
      )

      Column({ space: AppSpacing.MD }) {
        Text(`双指缩放、拖动图片，框内保存为 ${this.request.ratioWidth} : ${this.request.ratioHeight}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#C9CED4')
          .textAlign(TextAlign.Center)
        Button('不取景，用原图', { type: ButtonType.Capsule })
          .height(36)
          .fontSize(AppFontSize.CAPTION)
          .fontColor('#C9CED4')
          .backgroundColor('#2A2F35')
          .enabled(!this.working)
          .onClick(() => this.onOriginal())
      }
      .width('100%')
      .padding({ top: AppSpacing.MD, bottom: AppSpacing.XXL + this.navBarHeight })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#111417')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /** 取景框外压暗，框线白色。 */
  @Builder
  maskLayer() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width('100%').height(this.frameTop()).backgroundColor('#8C000000')
      Column().width('100%').height(this.frameTop())
        .position({ x: 0, y: this.frameTop() + this.frameHeight() }).backgroundColor('#8C000000')
      Column().width(this.frameLeft()).height(this.frameHeight())
        .position({ x: 0, y: this.frameTop() }).backgroundColor('#8C000000')
      Column().width(this.frameLeft()).height(this.frameHeight())
        .position({ x: this.frameLeft() + this.frameWidth(), y: this.frameTop() }).backgroundColor('#8C000000')
      Column()
        .width(this.frameWidth())
        .height(this.frameHeight())
        .position({ x: this.frameLeft(), y: this.frameTop() })
        .border({ width: 2, color: '#FFFFFF' })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  titleText(): string {
    const base = this.request.title || '取景';
    return this.request.total > 1 ? `${base}（${this.request.index + 1}/${this.request.total}）` : base;
  }

  ratio(): number {
    return Math.max(0.05, this.request.ratioWidth / Math.max(1, this.request.ratioHeight));
  }

  frameWidth(): number {
    const maxWidth = Math.max(40, this.areaWidth - AppSpacing.XXL * 2);
    const maxHeight = Math.max(40, this.areaHeight - AppSpacing.XXL * 2);
    return Math.min(maxWidth, maxHeight * this.ratio());
  }

  frameHeight(): number {
    return this.frameWidth() / this.ratio();
  }

  frameLeft(): number {
    return (this.areaWidth - this.frameWidth()) / 2;
  }

  frameTop(): number {
    return (this.areaHeight - this.frameHeight()) / 2;
  }

  /** 屏幕上 1 个位图像素对应的 vp：最小时图片正好盖满取景框。 */
  pixelScale(): number {
    if (this.imageWidth <= 0 || this.imageHeight <= 0) return 1;
    return Math.max(this.frameWidth() / this.imageWidth, this.frameHeight() / this.imageHeight) * this.zoom;
  }

  displayWidth(): number {
    return this.imageWidth * this.pixelScale();
  }

  displayHeight(): number {
    return this.imageHeight * this.pixelScale();
  }

  imageLeft(): number {
    return this.frameLeft() + this.frameWidth() / 2 + this.offsetX - this.displayWidth() / 2;
  }

  imageTop(): number {
    return this.frameTop() + this.frameHeight() / 2 + this.offsetY - this.displayHeight() / 2;
  }

  clampOffsets(): void {
    const limitX = Math.max(0, (this.displayWidth() - this.frameWidth()) / 2);
    const limitY = Math.max(0, (this.displayHeight() - this.frameHeight()) / 2);
    this.offsetX = Math.max(-limitX, Math.min(limitX, this.offsetX));
    this.offsetY = Math.max(-limitY, Math.min(limitY, this.offsetY));
  }

  async decode(): Promise<void> {
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      file = fs.openSync(this.request.uri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      // 先解码成有上限的工作图，取景和裁剪都在这张图上算。
      const longest = Math.max(info.size.width, info.size.height, 1);
      const factor = Math.min(1, 2400 / longest);
      this.pixelMap = await source.createPixelMap({
        desiredSize: {
          width: Math.max(1, Math.round(info.size.width * factor)),
          height: Math.max(1, Math.round(info.size.height * factor))
        }
      });
      const decoded = await this.pixelMap.getImageInfo();
      this.imageWidth = decoded.size.width;
      this.imageHeight = decoded.size.height;
      this.zoom = 1;
      this.offsetX = 0;
      this.offsetY = 0;
    } catch (e) {
      console.error('读取取景图片失败:', e);
      this.failed = true;
    } finally {
      if (source) {
        try {
          await source.release();
        } catch (_) {
        }
      }
      if (file) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
  }

  async confirm(): Promise<void> {
    const pixelMap = this.pixelMap;
    if (!pixelMap || this.working) return;
    this.working = true;
    let packer: image.ImagePacker | null = null;
    try {
      const scale = this.pixelScale();
      const width = Math.max(1, Math.min(this.imageWidth, Math.round(this.frameWidth() / scale)));
      const height = Math.max(1, Math.min(this.imageHeight, Math.round(this.frameHeight() / scale)));
      const x = Math.max(0, Math.min(this.imageWidth - width, Math.round((this.frameLeft() - this.imageLeft()) / scale)));
      const y = Math.max(0, Math.min(this.imageHeight - height, Math.round((this.frameTop() - this.imageTop()) / scale)));
      await pixelMap.crop({ x: x, y: y, size: { width: width, height: height } });
      const shrink = Math.min(1, this.request.maxWidth / width);
      if (shrink < 1) await pixelMap.scale(shrink, shrink);
      const outWidth = Math.round(width * shrink);
      const outHeight = Math.round(height * shrink);
      packer = image.createImagePacker();
      const data = await packer.packToData(pixelMap, {
        format: this.request.png ? 'image/png' : 'image/jpeg',
        quality: 92,
        bufferSize: Math.max(1024 * 1024, outWidth * outHeight * 4 + 64 * 1024)
      });
      const path = `${getContext(this).cacheDir}/theme_crop_${Date.now()}.${this.request.png ? 'png' : 'jpg'}`;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, data);
      } finally {
        fs.closeSync(file);
      }
      this.releasePixelMap();
      this.onDone(path);
    } catch (e) {
      console.error('取景裁剪失败:', e);
      this.working = false;
      this.failed = true;
      this.releasePixelMap();
      this.onCancel();
    } finally {
      if (packer) {
        try {
          await packer.release();
        } catch (_) {
        }
      }
    }
  }

  releasePixelMap(): void {
    const pixelMap = this.pixelMap;
    this.pixelMap = undefined;
    if (pixelMap) {
      pixelMap.release().catch(() => {});
    }
  }
}
