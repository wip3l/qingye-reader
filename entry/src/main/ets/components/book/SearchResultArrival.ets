/** Animate only a newly arrived card. The owner retains the ledger when a lazy child is rebuilt. */
@Component
export struct SearchResultArrival {
  @BuilderParam content: () => void;
  claimArrival: () => number = (): number => -1;
  @State private arrivalOffset: number = 0;
  @State private arrivalOpacity: number = 1;

  playArrival(): void {
    const delay = this.claimArrival();
    if (delay < 0) return;
    this.arrivalOffset = 18;
    this.arrivalOpacity = 0;
    this.getUIContext().animateTo({ duration: 260, delay, curve: Curve.EaseOut }, (): void => {
      this.arrivalOffset = 0;
      this.arrivalOpacity = 1;
    });
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .translate({ x: this.arrivalOffset, y: this.arrivalOffset * 5 / 18 })
    .opacity(this.arrivalOpacity)
    .onAppear((): void => this.playArrival())
  }
}
