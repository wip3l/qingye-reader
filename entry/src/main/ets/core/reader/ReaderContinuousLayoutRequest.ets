import { ReaderV2LayoutSnapshot } from './ReaderV2LayoutSnapshot';

/** Only lightweight presentation fields are observed; native Paragraph objects stay outside ArkUI proxies. */
@Observed
export class ReaderContinuousLayoutState {
  ready: boolean = false;
  failed: boolean = false;
  heightVp: number = 1;
}

export class ReaderContinuousLayoutRequest {
  state: ReaderContinuousLayoutState = new ReaderContinuousLayoutState();
  queued: boolean = false;
  queueSerial: number = -1;
  key: string;
  chapter: number;
  index: number;
  chunk: string;
  source: string;
  sourceStart: number;
  snapshot: ReaderV2LayoutSnapshot;

  constructor(key: string, chapter: number, index: number, chunk: string, source: string,
    sourceStart: number, snapshot: ReaderV2LayoutSnapshot) {
    this.key = key; this.chapter = chapter; this.index = index; this.chunk = chunk;
    this.source = source; this.sourceStart = sourceStart; this.snapshot = snapshot;
  }
}
