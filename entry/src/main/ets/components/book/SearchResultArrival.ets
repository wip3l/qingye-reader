import { curves } from '@kit.ArkUI';

/** Animate only a newly arrived card. The owner retains the ledger when a lazy child is rebuilt. */
@Component
export struct SearchResultArrival {
  @BuilderParam content: () => void;
  claimArrival: () => number = (): number => -1;
  private arrivalEffect: TransitionEffect = TransitionEffect.IDENTITY;

  aboutToAppear(): void {
    const delay = this.claimArrival();
    this.arrivalEffect = TransitionEffect.IDENTITY;
    if (delay < 0) return;
    // 在首次 build 前配置原生入场效果，避免 onAppear 再把已经显示的内容置透明。
    // 透明度先到位，位移以临界阻尼收稳；不横移、缩放文字或产生回弹。
    const appear = TransitionEffect.opacity(0)
      .animation({ duration: 180, delay, curve: Curve.EaseOut })
      .combine(TransitionEffect.translate({ y: 8 })
        .animation({ delay, curve: curves.springMotion(0.32, 1) }));
    this.arrivalEffect = TransitionEffect.asymmetric(appear, TransitionEffect.IDENTITY);
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .transition(this.arrivalEffect)
  }
}
