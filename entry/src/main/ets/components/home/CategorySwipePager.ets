/** 只保留当前页及相邻页的节点，发现分类较多时也不一次创建所有结果列表。 */
class CategoryPageDataSource implements IDataSource {
  private keys: string[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.keys.length; }
  getData(index: number): string { return this.keys[index]; }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  replace(keys: string[]): void {
    // 搜索结果数量变化不会改变页序，不要因此打断正在进行的手势。
    if (keys.length === this.keys.length && keys.every((key: string, index: number) => key === this.keys[index])) return;
    this.keys = keys.slice();
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

/** 原生横向翻页：铺满顶栏背后的区域，顶部留白由各页滚动内容承载。 */
@Component
export struct CategorySwipePager {
  @Prop @Watch('onPagesChanged') pageKeys: string[] = [];
  @Prop @Watch('onSelectedIndexChanged') selectedIndex: number = 0;
  @Prop swipeEnabled: boolean = true;
  @BuilderParam pageContent: (key: string) => void;
  onSelect: (key: string) => void = (_key: string) => {};
  canSelect: (key: string) => boolean = (_key: string): boolean => true;
  onSettled: () => void = () => {};
  onSwipe: () => void = () => {};
  private dataSource: CategoryPageDataSource = new CategoryPageDataSource();
  private controller: SwiperController = new SwiperController();
  private initialIndex: number = 0;
  private nativeIndex: number = 0;
  private mounted: boolean = false;

  aboutToAppear(): void {
    this.initialIndex = this.selectedIndex;
    this.nativeIndex = this.selectedIndex;
    this.onPagesChanged();
  }

  aboutToDisappear(): void { this.mounted = false; }

  onSelectedIndexChanged(): void {
    if (!this.mounted || this.selectedIndex === this.nativeIndex) return;
    this.nativeIndex = this.selectedIndex;
    this.controller.changeIndex(this.selectedIndex, true);
  }

  selectNativeIndex(index: number): void {
    if (index < 0 || index >= this.pageKeys.length) return;
    this.nativeIndex = index;
    if (index !== this.selectedIndex) this.onSelect(this.pageKeys[index]);
  }

  onPagesChanged(): void {
    this.dataSource.replace(this.pageKeys);
  }

  build() {
    Column() {
      Swiper(this.controller) {
        LazyForEach(this.dataSource, (key: string) => {
          Column() {
            this.pageContent(key)
          }
          .width('100%')
          .height('100%')
          .clip(true)
        }, (key: string) => key)
      }
      .width('100%')
      .layoutWeight(1)
      .index(this.initialIndex)
      .disableSwipe(!this.swipeEnabled)
      .loop(false)
      .indicator(false)
      .cachedCount(1)
      .duration(320)
      .effectMode(EdgeEffect.Spring)
      .clip(true)
      .onAppear(() => {
        this.mounted = true;
        this.onSelectedIndexChanged();
      })
      .onContentWillScroll((result: SwiperContentWillScrollResult): boolean =>
        result.comingIndex < 0 || result.comingIndex >= this.pageKeys.length ||
          this.canSelect(this.pageKeys[result.comingIndex]))
      .onGestureSwipe(() => this.onSwipe())
      .onAnimationStart((_index: number, targetIndex: number) => this.selectNativeIndex(targetIndex))
      .onChange((index: number) => this.selectNativeIndex(index))
      .onAnimationEnd(() => this.onSettled())
    }
    .width('100%')
    .height('100%')
  }
}
