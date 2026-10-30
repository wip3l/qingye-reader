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
  /** 手势松手后到换页回调的最长间隔，覆盖 320ms 翻页动画与快速连滑。 */
  private static readonly GESTURE_SELECT_WINDOW_MS: number = 1000;
  @Prop @Watch('onPagesChanged') pageKeys: string[] = [];
  @Prop @Watch('onSelectedIndexChanged') selectedIndex: number = 0;
  @Prop swipeEnabled: boolean = true;
  @Prop swipeExcludedGestureTag: string = '';
  @BuilderParam pageContent: (key: string) => void;
  onSelect: (key: string) => void = (_key: string) => {};
  canSelect: (key: string) => boolean = (_key: string): boolean => true;
  onSettled: () => void = () => {};
  onSwipe: () => void = () => {};
  private dataSource: CategoryPageDataSource = new CategoryPageDataSource();
  private controller: SwiperController = new SwiperController();
  /** Swiper 当前所在页；属性重放时 .index() 读它，不会跳回创建时的页。 */
  private nativeIndex: number = 0;
  private mounted: boolean = false;
  /** 最近一次手势横滑的时间：只有手势引起的换页才算用户切换。 */
  private lastGestureSwipeAt: number = 0;

  aboutToAppear(): void {
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
    if (index !== this.selectedIndex && Date.now() - this.lastGestureSwipeAt > CategorySwipePager.GESTURE_SELECT_WINDOW_MS) {
      // 非手势换页（属性重放、页面转场时重新布局等）不改选择，拉回当前页。
      this.nativeIndex = this.selectedIndex;
      this.controller.changeIndex(this.selectedIndex, false);
      return;
    }
    this.nativeIndex = index;
    if (index !== this.selectedIndex) this.onSelect(this.pageKeys[index]);
  }

  onGestureSwipe(): void {
    this.lastGestureSwipeAt = Date.now();
    this.onSwipe();
  }

  onPagesChanged(): void {
    this.dataSource.replace(this.pageKeys);
  }

  judgeSwipe(current: GestureRecognizer, others: GestureRecognizer[]): GestureJudgeResult {
    // 子区域独占横滑；按本次命中的手势链判断，不依赖拖动开始后的异步状态更新。
    if (this.swipeExcludedGestureTag && current.isBuiltIn() &&
      current.getType() === GestureControl.GestureType.PAN_GESTURE &&
      others.some((recognizer: GestureRecognizer): boolean =>
        recognizer.getTag() === this.swipeExcludedGestureTag)) {
      return GestureJudgeResult.REJECT;
    }
    return GestureJudgeResult.CONTINUE;
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
      .index(this.nativeIndex)
      .disableSwipe(!this.swipeEnabled)
      .onGestureRecognizerJudgeBegin((_event: BaseGestureEvent, current: GestureRecognizer,
        others: GestureRecognizer[]): GestureJudgeResult => this.judgeSwipe(current, others))
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
      .onGestureSwipe(() => this.onGestureSwipe())
      .onAnimationStart((_index: number, targetIndex: number) => this.selectNativeIndex(targetIndex))
      .onChange((index: number) => this.selectNativeIndex(index))
      .onAnimationEnd(() => this.onSettled())
    }
    .width('100%')
    .height('100%')
  }
}
