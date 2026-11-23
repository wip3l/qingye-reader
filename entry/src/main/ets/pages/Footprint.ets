import { FootprintTabPage } from '../components/home/FootprintTabPage';

/** 底栏没开足迹页签时，从陪伴书架的阅读小记等入口进来的独立足迹页；内容与首页足迹页签同一个组件。 */
@Entry
@Component
struct Footprint {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  build() {
    Stack() {
      FootprintTabPage({
        statusBarHeight: this.statusBarHeight,
        navBarHeight: this.navBarHeight,
        showBack: true
      })
    }
    .width('100%')
    .height('100%')
  }
}
