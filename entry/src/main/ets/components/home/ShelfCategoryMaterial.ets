import { ImmersiveMaterialSurface } from '../ImmersiveMaterialSurface';

/** 只共享底板；分类文字和按钮图标留在各自布局中，避免被压缩成一团。 */
@Component
export struct ShelfCategoryMaterial {
  @Prop expanded: boolean = true;
  @Prop viewportWidth: number = 360;
  @Prop side: number = 24;
  @Prop top: number = 56;
  @Prop buttonTop: number = 8;
  @Prop darkMode: boolean = false;
  @Prop surfaceColor: string = '#FFFFFF';
  @Prop accentColor: string = '#888888';
  /** 分类文字在底板上层，触点由书架转过来点亮底板光晕。 */
  @Prop touching: boolean = false;
  @Prop touchX: number = 0;
  @Prop touchY: number = 0;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.expanded) {
        Row() {
          ImmersiveMaterialSurface({
            surfaceWidth: Math.max(1, this.viewportWidth - this.side * 2), surfaceHeight: 44,
            darkMode: this.darkMode, fallbackColor: this.surfaceColor, glowColor: this.accentColor,
            externalTouching: this.touching, externalTouchX: this.touchX, externalTouchY: this.touchY
          }) { Row().width('100%').height('100%') }
        }
        .width(Math.max(1, this.viewportWidth - this.side * 2)).height(44)
        .borderRadius(22).clip(true)
        .geometryTransition('bookshelf_category_surface')
        .transition(TransitionEffect.opacity(0.99))
        .position({ x: this.side, y: this.top })
      } else {
        Row() {
          ImmersiveMaterialSurface({
            surfaceWidth: 40, surfaceHeight: 40, darkMode: this.darkMode,
            fallbackColor: this.surfaceColor, glowColor: this.accentColor
          }) { Row().width('100%').height('100%') }
        }
        .width(40).height(40).borderRadius(20).clip(true)
        .geometryTransition('bookshelf_category_surface')
        .transition(TransitionEffect.opacity(0.99))
        .position({ x: this.viewportWidth - this.side - 140, y: this.buttonTop })
      }
    }
    .width(this.viewportWidth)
    .height(this.top + 44)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
  }
}
