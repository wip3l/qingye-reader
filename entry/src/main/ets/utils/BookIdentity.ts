import { Book, SearchBook, EncodedSourceUrl, BookTypeSupport } from '@legado/sourceengine';

export class BookIdentity {
  private static readonly UNKNOWN_AUTHORS: string[] = ['未知', '佚名', '未知作者', '匿名', '无', '暂无', 'unknown', 'none', 'null'];

  private static queryValue(url: string, names: string[]): string {
    const queryIndex = (url || '').indexOf('?');
    if (queryIndex < 0) return '';
    const hashIndex = url.indexOf('#', queryIndex + 1);
    const query = url.substring(queryIndex + 1, hashIndex >= 0 ? hashIndex : url.length);
    for (const pair of query.split('&')) {
      if (!pair) continue;
      const equalIndex = pair.indexOf('=');
      const rawName = equalIndex >= 0 ? pair.substring(0, equalIndex) : pair;
      let name = rawName;
      try {
        name = decodeURIComponent(rawName.replace(/\+/g, ' '));
      } catch (_) {
      }
      if (!names.includes(name)) continue;
      const rawValue = equalIndex >= 0 ? pair.substring(equalIndex + 1) : '';
      try {
        return decodeURIComponent(rawValue.replace(/\+/g, ' ')).trim();
      } catch (_) {
        return rawValue.trim();
      }
    }
    return '';
  }

  private static stableUrlKey(url: string): string {
    const clean = (url || '').trim();
    if (!clean) return '';
    const payload = EncodedSourceUrl.decode(clean);
    if (payload) {
      const bookId = EncodedSourceUrl.str(payload.data['book_id']) || EncodedSourceUrl.str(payload.data['bookId']);
      const source = EncodedSourceUrl.str(payload.data['source']) || EncodedSourceUrl.str(payload.data['sources']);
      const tab = EncodedSourceUrl.str(payload.data['tab']);
      if (bookId && source) return `encoded:${bookId}|${source}|${tab}`;
    }

    // Dynamic aggregation sources rotate their API host while keeping the logical detail endpoint.
    // Only canonicalise recognizable detail/book URLs; generic `id` parameters may be page-local.
    const path = clean.split(/[?#]/, 1)[0].toLowerCase();
    const looksLikeBookDetail = /\/(detail|book|bookinfo)(?:\/|$)/.test(path);
    const bookId = BookIdentity.queryValue(clean, ['bookId', 'book_id', 'bid']);
    if (looksLikeBookDetail && bookId) {
      const source = BookIdentity.queryValue(clean, ['source', 'sources']);
      const tab = BookIdentity.queryValue(clean, ['tab']);
      return `detail:${bookId}|${source}|${tab}`;
    }
    return clean;
  }

  static keyOfUrl(url: string, origin: string = ''): string {
    const stable = BookIdentity.stableUrlKey(url);
    if (!stable) return '';
    return origin ? `${origin}\n${stable}` : stable;
  }

  static hasLogicalIdentity(url: string): boolean {
    const payload = EncodedSourceUrl.decode(url);
    if (payload) {
      const bookId = EncodedSourceUrl.str(payload.data['book_id']) || EncodedSourceUrl.str(payload.data['bookId']);
      const source = EncodedSourceUrl.str(payload.data['source']) || EncodedSourceUrl.str(payload.data['sources']);
      if (bookId && source) return true;
    }
    const path = (url || '').split(/[?#]/, 1)[0].toLowerCase();
    return /\/(detail|book|bookinfo)(?:\/|$)/.test(path) &&
      !!BookIdentity.queryValue(url, ['bookId', 'book_id', 'bid']);
  }

  static keyOfBook(book: Book): string {
    return BookIdentity.keyOfUrl(book.bookUrl, book.origin);
  }

  static keyOfSearchBook(book: SearchBook): string {
    return BookIdentity.keyOfUrl(book.bookUrl, book.origin);
  }

  /**
   * Same-work identity used to keep one online copy per work on the shelf: media category plus
   * normalised title and author. Empty when the work cannot be identified reliably (missing or
   * placeholder author) and for local/WebDAV/OPDS books, whose titles come from file names.
   */
  static workKeyOf(book: Book | SearchBook | null): string {
    if (!book) return '';
    const origin = (book.origin || '').trim();
    if (!origin || origin === 'local' || origin === 'loc_book') return '';
    const name = BookIdentity.normalizeWorkName(book.name);
    const author = BookIdentity.normalizeWorkAuthor(book.author);
    if (!name || !author) return '';
    return `${BookTypeSupport.mediaCategoryOf(book)}\n${name}\n${author}`;
  }

  static normalizeWorkName(name: string): string {
    return BookIdentity.normalizeWorkText(name)
      .replace(/^[《「『"“'‘<]+/, '')
      .replace(/[》」』"”'’>]+$/, '');
  }

  static normalizeWorkAuthor(author: string): string {
    const value = BookIdentity.normalizeWorkText(author)
      .replace(/^(?:作者|著者|作)[:]/, '')
      .replace(/[\/|·\-]*(?:编著|著作|著)$/, '')
      .replace(/^[\/|·\-]+|[\/|·\-]+$/g, '');
    return BookIdentity.UNKNOWN_AUTHORS.includes(value) ? '' : value;
  }

  /** NFKC folds full-width letters, digits and punctuation into their half-width forms. */
  private static normalizeWorkText(value: string): string {
    let text = (value || '').trim();
    try {
      text = text.normalize('NFKC');
    } catch (_) {
    }
    return text.replace(/[\s\u200B-\u200D\uFEFF]+/g, '').toLowerCase();
  }

  /** Keeps legacy cloud IDs for ordinary sources and switches only host-volatile logical URLs to v2. */
  static cloudIdentityValue(book: Book): string {
    // A local source URI is device-specific (picker providers and sandbox paths
    // differ across devices). Use the imported file's content fingerprint when
    // available so progress entities can match the same local edition remotely.
    if (book.origin === 'local') {
      const contentHash = book.getVariable('localContentHash').trim();
      if (contentHash) return `local-content-v1\n${contentHash}`;
    }
    if (!BookIdentity.hasLogicalIdentity(book.bookUrl)) {
      return `${book.origin}\n${book.bookUrl}`;
    }
    return `stable-v2\n${BookIdentity.keyOfBook(book)}`;
  }
}
