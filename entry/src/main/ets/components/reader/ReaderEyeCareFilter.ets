import { ReaderEyeCare } from '../../utils/ReaderEyeCare';

/**
 * 护眼滤层：放在阅读页根 Stack 的最后一层，盖住正文、菜单和面板，不接收触摸。
 * 用正片叠底（FAST，不开离屏画布）和下面已画好的内容相乘：白色变暖、黑色仍是黑色。
 */
@Component
export struct ReaderEyeCareFilter {
  @StorageProp('readerEyeCareOn') eyeCareOn: boolean = false;
  @StorageProp('readerEyeCareLevel') eyeCareLevel: number = ReaderEyeCare.DEFAULT_LEVEL;
  @Prop dark: boolean = false;

  build() {
    Stack() {
      if (this.eyeCareOn) {
        Column()
          .width('100%').height('100%')
          .backgroundColor(ReaderEyeCare.filterColor(this.eyeCareLevel, this.dark))
          .blendMode(BlendMode.MULTIPLY, BlendApplyType.FAST)
          .transition(TransitionEffect.OPACITY.animation({ duration: 400, curve: Curve.EaseInOut }))
      }
    }
    .width('100%').height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
    .accessibilityLevel('no')
  }
}
