import { ReaderEyeCare } from '../../utils/ReaderEyeCare';

/**
 * 护眼滤层：放在阅读页根 Stack 的最后一层，盖住正文、菜单和面板，不接收触摸。
 * 用正片叠底（FAST，不开离屏画布）和下面已画好的内容相乘：白色变暖、黑色仍是黑色。
 * 节点常驻，只在开关时淡入淡出；开书时第一帧就是该有的浓度，不会从无到有再淡入。
 */
@Component
export struct ReaderEyeCareFilter {
  @StorageProp('readerEyeCareOn') eyeCareOn: boolean = false;
  @StorageProp('readerEyeCareLevel') eyeCareLevel: number = ReaderEyeCare.DEFAULT_LEVEL;
  @Prop dark: boolean = false;
  /** 盖着已带滤层的关书截图时为 true：先藏起来，截图撤掉的同一帧再露出。 */
  @Prop suppressed: boolean = false;

  build() {
    Column()
      .width('100%').height('100%')
      .opacity(this.eyeCareOn ? 1 : 0)
      .animation({ duration: 400, curve: Curve.EaseInOut })
      .backgroundColor(ReaderEyeCare.filterColor(this.eyeCareLevel, this.dark))
      .blendMode(BlendMode.MULTIPLY, BlendApplyType.FAST)
      .visibility(this.suppressed ? Visibility.Hidden : Visibility.Visible)
      .hitTestBehavior(HitTestMode.Transparent)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
      .accessibilityLevel('no')
  }
}
