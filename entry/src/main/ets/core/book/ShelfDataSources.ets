import { Book, BookGroup, SearchBook } from '@legado/sourceengine';
import { ExploreSourceOption } from './ExploreCoordinator';

export class ShelfTileSortEntry {
  kind: string = 'book'; key: string = ''; book: Book | null = null; group: BookGroup | null = null;
  readTime: number = 0; addTime: number = 0; name: string = ''; pinned: boolean = false; originalOrder: number = 0;
}
export class ShelfBookDataSource implements IDataSource {
  private books: Book[] = []; private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.books.length; }
  getData(index: number): Book { return this.books[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { const i = this.listeners.indexOf(listener); if (i >= 0) this.listeners.splice(i, 1); }
  replace(books: Book[], force: boolean = false): void {
    if (!force && this.books.length === books.length && this.books.every((b, i) => b === books[i])) return;
    this.books = [...books]; for (const listener of this.listeners) listener.onDataReloaded();
  }
}
export class ShelfTileEntryDataSource implements IDataSource {
  private entries: ShelfTileSortEntry[] = []; private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.entries.length; } getData(index: number): ShelfTileSortEntry { return this.entries[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { const i = this.listeners.indexOf(listener); if (i >= 0) this.listeners.splice(i, 1); }
  replace(entries: ShelfTileSortEntry[], force: boolean = false): void {
    if (!force && this.entries.length === entries.length && this.entries.every((e, i) => e.key === entries[i].key && e.book === entries[i].book && e.group === entries[i].group)) return;
    this.entries = [...entries]; for (const listener of this.listeners) listener.onDataReloaded();
  }
}

/** 各分类各自持有数据源和滚动器，横向翻页时旧页和新页可以同时存在。 */
export class ShelfCategoryPage {
  signature: string = '';
  books: Book[] = [];
  listSource: ShelfBookDataSource = new ShelfBookDataSource();
  tileSource: ShelfBookDataSource = new ShelfBookDataSource();
  entrySource: ShelfTileEntryDataSource = new ShelfTileEntryDataSource();
  listScroller: ListScroller = new ListScroller();
  tileScroller: Scroller = new Scroller();
  listOffset: number = 0;
  tileOffset: number = 0;
}
export class ExploreSourceOptionDataSource implements IDataSource {
  private options: ExploreSourceOption[] = []; private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.options.length; } getData(index: number): ExploreSourceOption { return this.options[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { const i = this.listeners.indexOf(listener); if (i >= 0) this.listeners.splice(i, 1); }
  replace(options: ExploreSourceOption[]): void { this.options = options.slice(); for (const listener of this.listeners) listener.onDataReloaded(); }
}
/** 搜索范围面板的书源列表，存的是书源在面板书源数组里的下标。 */
export class SearchSourceIndexDataSource implements IDataSource {
  private indexes: number[] = []; private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.indexes.length; } getData(index: number): number { return this.indexes[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { const i = this.listeners.indexOf(listener); if (i >= 0) this.listeners.splice(i, 1); }
  replace(indexes: number[]): void { this.indexes = indexes.slice(); for (const listener of this.listeners) listener.onDataReloaded(); }
}
export class ExploreMetadataTask { book: SearchBook = new SearchBook(); loadVersion: number = 0; }
