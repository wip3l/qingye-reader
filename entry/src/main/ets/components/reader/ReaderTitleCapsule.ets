import { HdsTabs } from '@kit.UIDesignKit';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';

/**
 * 阅读页顶栏中间的标题胶囊（PDF、文件排版）。与漫画阅读页的标题胶囊、两侧圆形按钮同一种系统材质和
 * 同一档底色，三者看起来是一块表面；不用 ReaderMaterialPanel，那是大面板用的较厚底色。
 * 内容用尾随闭包传入，点按等手势加在内容上。
 */
@Component
export struct ReaderTitleCapsule {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('immersiveThemeTint') immersiveThemeTint: boolean = false;
  @Prop capsuleWidth: number = 200;
  @Prop darkMode: boolean = false;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      if (ImmersiveMaterialRuntime.supportsHdsTabs()) {
        this.materialLayer()
      }
      Stack({ alignContent: Alignment.Start }) {
        this.content()
      }
      .width('100%')
      .height('100%')
      .borderRadius(20)
      .backgroundColor(ImmersiveMaterialRuntime.surfaceColor(this.immersiveLightLevel, this.darkMode,
        this.solidColor(), true, this.immersiveThemeTint))
    }
    .width(this.capsuleWidth)
    .height(40)
    .borderRadius(20)
    .backgroundColor(ImmersiveMaterialRuntime.supportsHdsTabs() ? Color.Transparent : this.solidColor())
    .border(ImmersiveMaterialRuntime.surfaceBorder(this.immersiveLightLevel, this.darkMode,
      ImmersiveMaterialRuntime.supportsHdsTabs() ? 0 : 0.5, this.darkMode ? '#26FFFFFF' : '#14000000'))
  }

  private solidColor(): string {
    return this.darkMode ? '#191B1F' : '#FFFFFF';
  }

  @Builder
  materialLayer() {
    HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
      TabContent() {
        Column()
      }
      .height(40)
      .tabBar(this.materialTab())
    }
    .barMode(BarMode.Fixed)
    .barHeight(40)
    .barOverlap(true)
    .barFloatingStyle({
      barWidth: {
        smallWidth: this.capsuleWidth,
        mediumWidth: this.capsuleWidth,
        largeWidth: this.capsuleWidth
      },
      systemMaterialEffect: {
        materialType: ImmersiveMaterialRuntime.materialType(),
        materialLevel: ImmersiveMaterialRuntime.materialLevel(this.immersiveLightLevel)
      },
      barSideMargin: 0,
      barBottomMargin: 0,
      gradientMask: {
        maskColor: Color.Transparent,
        maskHeight: 40
      },
      adaptToHandedness: false,
      thermoCtrl: true,
      barOpacity: 1
    })
    .scrollable(false)
    .onContentWillChange(() => false)
    .width(this.capsuleWidth)
    .height(40)
    .borderRadius(20, RenderStrategy.OFFSCREEN)
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  materialTab() {
    Stack()
      .width('100%')
      .height('100%')
  }
}
