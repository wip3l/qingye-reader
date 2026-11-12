import { WebParseSettingsStore } from './WebParseSettingsStore';
import { Book } from '@legado/sourceengine';

export class SearchExplorePendingBook {
  private static readonly KEY_PENDING_ADD_TO_SHELF: string = 'searchExplorePendingAddToShelf';

  static isPendingAddToShelf(book: Book | null): boolean {
    return !!book && book.pendingAddToShelf;
  }

  static markPendingAddToShelf(book: Book): void {
    book.pendingAddToShelf = true;
    SearchExplorePendingBook.removeLegacyVariable(book);
  }

  static clearPendingAddToShelf(book: Book): void {
    book.pendingAddToShelf = false;
    book.shelfModifiedTime = Date.now();
    SearchExplorePendingBook.removeLegacyVariable(book);
  }

  static filterShelfBooks(books: Book[]): Book[] {
    return books.filter((book: Book) => !SearchExplorePendingBook.isPendingAddToShelf(book) &&
      WebParseSettingsStore.visibleBook(book.origin));
  }

  private static removeLegacyVariable(book: Book): void {
    if (!book.variable || book.variable.indexOf(SearchExplorePendingBook.KEY_PENDING_ADD_TO_SHELF) < 0) return;
    try {
      const source = JSON.parse(book.variable) as Record<string, string>;
      const cleaned: Record<string, string> = {};
      for (const key of Object.keys(source)) {
        if (key !== SearchExplorePendingBook.KEY_PENDING_ADD_TO_SHELF) cleaned[key] = source[key];
      }
      book.replaceVariable(JSON.stringify(cleaned));
    } catch (_) {
      // Invalid source variables are left untouched; the dedicated database column remains authoritative.
    }
  }
}
