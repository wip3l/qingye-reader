/** Source offsets stay in UTF-16 units, matching substring, selection and persisted reading progress. */
export interface ReaderPaginationBoundary {
  sourceStart: number;
  sourceEnd: number;
}

export interface ReaderPaginationIndexState {
  source: string;
  pages: string[];
  starts: number[];
  ends: number[];
  cursor?: number;
  complete?: boolean;
}

export class ReaderPaginationIndex {
  /** Only the previous tail can change when a new measured page is appended. */
  static append(state: ReaderPaginationIndexState, boundaries: ReaderPaginationBoundary[], complete: boolean): void {
    if (state.pages.length > boundaries.length) {
      state.pages = [];
      state.starts = [];
      state.ends = [];
    }
    const first = Math.max(0, state.pages.length - 1);
    for (let index = first; index < boundaries.length; index++) {
      const page = boundaries[index];
      const start = index === 0 ? 0 : Math.max(state.starts[index - 1], page.sourceStart);
      const nextStart = index + 1 < boundaries.length ? boundaries[index + 1].sourceStart :
        (complete ? state.source.length : page.sourceEnd);
      const end = Math.max(start, Math.min(state.source.length, nextStart > start ? nextStart : page.sourceEnd));
      page.sourceStart = start;
      page.sourceEnd = end;
      state.starts[index] = start;
      state.ends[index] = end;
      state.pages[index] = state.source.substring(start, end);
    }
    if (state.pages.length === 0 && state.source && complete) {
      state.pages.push(state.source);
      state.starts.push(0);
      state.ends.push(state.source.length);
    }
    state.cursor = state.ends.length > 0 ? state.ends[state.ends.length - 1] : 0;
    state.complete = complete;
  }
}
