import { BookMarkRules } from '../../model/book/BookMark';

/** 评分星星用固定的琥珀色：主题强调色偏蓝、偏绿时，星星就不像评分了。 */
export function bookMarkStarColor(darkMode: boolean): string {
  return darkMode ? '#F5B53A' : '#F2A516';
}

/**
 * 五颗星，rating 0–10（1 = 半颗）。interactive 时点星星改分：点在星星左半边是半颗。
 * 半颗是在空心星上叠一颗只露左半边的实心星。
 */
@Component
export struct BookMarkStars {
  @Prop rating: number = 0;
  @Prop starSize: number = 20;
  @Prop darkMode: boolean = false;
  @Prop emptyColor: string = '#33000000';
  @Prop interactive: boolean = false;
  onRate: (rating: number) => void = (_rating: number): void => {
  };

  build() {
    Row({ space: Math.round(this.starSize * 0.14) }) {
      ForEach([0, 1, 2, 3, 4], (index: number) => {
        Stack({ alignContent: Alignment.Start }) {
          SymbolGlyph($r('sys.symbol.star_fill'))
            .fontSize(this.starSize)
            .fontColor([this.emptyColor])
          if (BookMarkRules.starFill(this.rating, index) > 0) {
            Stack({ alignContent: Alignment.Start }) {
              SymbolGlyph($r('sys.symbol.star_fill'))
                .fontSize(this.starSize)
                .fontColor([bookMarkStarColor(this.darkMode)])
            }
            .width(this.starSize * BookMarkRules.starFill(this.rating, index))
            .height(this.starSize)
            .clip(true)
          }
        }
        .width(this.starSize)
        .height(this.starSize)
        .hitTestBehavior(this.interactive ? HitTestMode.Default : HitTestMode.Transparent)
        .onClick((event: ClickEvent) => {
          if (!this.interactive) return;
          const half = event.x < this.starSize / 2;
          this.onRate(index * 2 + (half ? 1 : 2));
        })
      }, (index: number) => `${index}`)
    }
    // 只读时整排读成一句；可点时每颗星单独可选。
    .accessibilityGroup(!this.interactive)
    .accessibilityText(this.rating > 0 ? `评分 ${BookMarkRules.ratingText(this.rating)} 星` : '未评分')
    .accessibilityDescription(this.interactive ? '点星星打分，点左半边是半颗星' : '')
  }
}
