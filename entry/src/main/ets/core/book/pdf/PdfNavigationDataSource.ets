import { PdfOutlineEntry, PdfPagePosition } from './PdfModels';

/** Generates page navigation lazily when a document has no embedded outline. */
export class PdfNavigationDataSource implements IDataSource {
  private entries: PdfOutlineEntry[] = [];
  private pages: number = 0;
  private listeners: DataChangeListener[] = [];
  reset(entries: PdfOutlineEntry[], pages: number): void {
    this.entries = entries; this.pages = pages;
    for (const listener of this.listeners) listener.onDataReloaded();
  }
  totalCount(): number { return this.entries.length || this.pages; }
  hasOutline(): boolean { return this.entries.length > 0; }
  /** The outline entry whose section contains `page` (the nearest preceding target), or the page row itself. */
  indexForPage(page: number): number {
    if (!this.entries.length) return PdfPagePosition.clamp(page, this.pages);
    let best = -1;
    for (let i = 0; i < this.entries.length; i++) {
      const target = this.entries[i].pageIndex;
      if (target <= page && (best < 0 || target >= this.entries[best].pageIndex)) best = i;
    }
    return Math.max(0, best);
  }
  getData(index: number): PdfOutlineEntry {
    if (this.entries.length) return this.entries[index];
    const entry = new PdfOutlineEntry();
    entry.id = `page-${index}`; entry.pageIndex = index; entry.title = PdfPagePosition.title(index);
    return entry;
  }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener); if (index >= 0) this.listeners.splice(index, 1);
  }
}
