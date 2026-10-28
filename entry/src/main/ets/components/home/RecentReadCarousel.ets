import { Book } from '@legado/sourceengine';
import { BookshelfSortHelper } from '../../utils/BookshelfSortHelper';
import { RecentReadCarouselGeometry } from '../../utils/RecentReadCarouselGeometry';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppSpacing } from '../../theme/AppSpacing';

/** 方案 A：固定尺寸的整卡横向平移，仅手动切换，左右露出相邻卡片。 */
@Component
export struct RecentReadCarousel {
  @Prop @Watch('onBooksChanged') books: Book[] = [];
  @Prop cardHeight: number = 150;
  @Prop accentColor: string = '';
  @Prop secondaryColor: string = '';
  @BuilderParam cardContent: (book: Book) => void;
  renderKey: (book: Book) => string = (book: Book): string => book.bookUrl;
  onOpen: (book: Book, event: GestureEvent) => void = (_book: Book, _event: GestureEvent): void => {};
  onLongPress: (book: Book, event: GestureEvent) => void = (_book: Book, _event: GestureEvent): void => {};
  @State currentIndex: number = 0;
  @State positionValue: number = 0;
  @State settledPosition: number = 0;
  @State viewportWidth: number = 360;
  private candidateSignature: string = '';
  private dragging: boolean = false;
  private settling: boolean = false;
  private animationGeneration: number = 0;
  private dragStartIndex: number = 0;

  aboutToAppear(): void { this.onBooksChanged(); }

  aboutToDisappear(): void { this.resetMotion(); }

  onBooksChanged(): void {
    const signature = this.books.map((book: Book): string =>
      `${book.bookUrl}:${BookshelfSortHelper.getBookReadTime(book)}`).join('|');
    if (signature === this.candidateSignature) return;
    this.candidateSignature = signature;
    this.currentIndex = 0;
    this.resetMotion();
  }

  resetMotion(): void {
    this.animationGeneration++;
    this.dragging = false;
    this.settling = false;
    this.positionValue = this.currentIndex;
    this.settledPosition = this.currentIndex;
  }

  itemWidth(): number {
    return this.books.length <= 1 ? this.viewportWidth :
      Math.min(this.viewportWidth, Math.max(200, this.viewportWidth * 0.74));
  }

  itemStride(): number {
    return this.itemWidth() + AppSpacing.XL;
  }

  itemTranslation(slot: number): number {
    return (slot - this.positionValue) * this.itemStride();
  }

  slotBook(slot: number): Book {
    return this.books[RecentReadCarouselGeometry.wrap(slot, this.books.length)];
  }

  startDrag(): void {
    if (this.settling) return;
    this.dragging = true;
    this.dragStartIndex = this.settledPosition;
  }

  updateDrag(event: GestureEvent): void {
    if (!this.dragging) return;
    const delta = Math.max(-1, Math.min(1, -event.offsetX / Math.max(1, this.itemStride())));
    const next = this.dragStartIndex + delta;
    this.positionValue = this.books.length === 2 ? Math.max(0, Math.min(1, next)) : next;
  }

  finishDrag(event?: GestureEvent): void {
    if (!this.dragging) return;
    this.dragging = false;
    const target = event ? RecentReadCarouselGeometry.target(this.dragStartIndex,
      event.offsetX, event.velocityX, this.books.length) : this.dragStartIndex;
    const generation = ++this.animationGeneration;
    this.settling = true;
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut, onFinish: (): void => {
      if (generation !== this.animationGeneration) return;
      this.settling = false;
      // 保持未取模坐标；只替换视口外的槽位，不让循环卡片横穿中央。
      this.settledPosition = target;
    } }, (): void => {
      this.currentIndex = RecentReadCarouselGeometry.wrap(target, this.books.length);
      this.positionValue = target;
    });
  }

  handleBookGesture(event: GestureEvent, longPress: boolean): void {
    if (this.dragging || this.settling) return;
    const book = this.books[this.currentIndex];
    if (!book) return;
    const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    // 侧面露出的卡片仅作位置提示，点击和长按只作用于中央当前书。
    if (finger && this.books.length > 1 &&
      Math.abs(finger.localX - this.viewportWidth / 2) > this.itemWidth() / 2) return;
    if (longPress) this.onLongPress(book, event);
    else this.onOpen(book, event);
  }

  @Builder
  deck() {
    Stack() {
      ForEach(RecentReadCarouselGeometry.slots(this.settledPosition, this.books.length), (slot: number) => {
        Column() {
          this.cardContent(this.slotBook(slot))
        }
        .width(this.itemWidth())
        .height(this.cardHeight)
        .borderRadius(ThemeRuntime.cardRadius())
        .clip(true)
        .translate({ x: this.itemTranslation(slot) })
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no-hide-descendants')
      }, (slot: number) => `${this.renderKey(this.slotBook(slot))}_slot_${slot}`)
    }
    .width('100%')
    .height(this.cardHeight + 20)
    .clip(true)
    .id('recentReadCarouselDeck')
    .accessibilityText(this.books.length > 0 ?
      `继续阅读 ${this.books[this.currentIndex]?.name || ''}，第${this.currentIndex + 1}本，共${this.books.length}本` : '')
  }

  build() {
    Column() {
      if (this.books.length > 1) {
        Column() {
          this.deck()
        }
        .width('100%')
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            PanGesture({ direction: PanDirection.Horizontal, distance: 12 })
              .onActionStart(() => this.startDrag())
              .onActionUpdate((event: GestureEvent) => this.updateDrag(event))
              .onActionEnd((event: GestureEvent) => this.finishDrag(event))
              .onActionCancel(() => this.finishDrag()),
            LongPressGesture({ repeat: false }).onAction((event: GestureEvent) => this.handleBookGesture(event, true)),
            TapGesture().onAction((event: GestureEvent) => this.handleBookGesture(event, false))
          )
        )
        Row({ space: 5 }) {
          ForEach(this.books, (_book: Book, itemIndex: number) => {
            Row()
              .width(itemIndex === this.currentIndex ? 15 : 5)
              .height(5)
              .borderRadius(3)
              .backgroundColor(itemIndex === this.currentIndex ? this.accentColor : this.secondaryColor)
              .opacity(itemIndex === this.currentIndex ? 1 : 0.4)
          }, (book: Book, itemIndex: number) => `${book.bookUrl}_dot_${itemIndex}`)
        }
        .height(18)
        .justifyContent(FlexAlign.Center)
        .accessibilityLevel('no-hide-descendants')
      } else if (this.books.length === 1) {
        Column() {
          this.deck()
        }
        .width('100%')
        .gesture(GestureGroup(GestureMode.Exclusive,
          LongPressGesture({ repeat: false }).onAction((event: GestureEvent) => this.handleBookGesture(event, true)),
          TapGesture().onAction((event: GestureEvent) => this.handleBookGesture(event, false))))
      }
    }
    .width('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const next = Number(newArea.width);
      if (next > 0 && next !== this.viewportWidth) this.viewportWidth = next;
    })
    .onVisibleAreaChange([0], (visible: boolean) => {
      if (!visible) this.resetMotion();
    })
  }
}
