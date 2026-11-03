import { ReaderContinuousLayoutState } from '../../core/reader/ReaderContinuousLayoutRequest';

/** A cold chunk waits for native layout without measuring text in the List builder or refreshing sibling rows. */
@Component
export struct ReaderContinuousLayoutHost {
  @ObjectLink layoutState: ReaderContinuousLayoutState;
  @Prop pendingHeight: number = 1;
  @Prop hintColor: string = '#777777';
  @BuilderParam content: () => void;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.layoutState.ready) {
        this.content()
      } else {
        Text(this.layoutState.failed ? '正文排版失败，请刷新本章重试' : '正在排版…')
          .fontSize(14)
          .fontColor(this.hintColor)
          .padding(16)
      }
    }
    .width('100%')
    .height(this.layoutState.ready ? this.layoutState.heightVp : Math.max(1, this.pendingHeight))
  }
}
