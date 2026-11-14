import { router } from '@kit.ArkUI';
import { Book } from '@legado/sourceengine';
import { appDb } from '../../model/data/AppDatabase';
import { BookMark, BookMarkRules, BookMarkStatus, BookMarkTags } from '../../model/book/BookMark';
import { BookIdentity } from '../../utils/BookIdentity';
import { BookDisplayHelper } from '../../utils/BookDisplayHelper';
import { Context } from '@kit.AbilityKit';

/**
 * 书籍标记的读写入口。页面都走这里，保存后递增 AppStorage 的 bookMarkRevision，
 * 详情页、我的标记页、足迹页据此重读。
 *
 * 标记的标签（字段名沿用 categories）和书架标签是同一套：标记是记录本身，书架上同一部作品的书
 * 在标记面板保存、书架“自定义标签”保存、加入书架时跟着同步，规则见 BookMarkTags。
 * 只在书架上加了标签、没有标记的书不会出现在我的标记里。
 */
export class BookMarkService {
  static readonly REVISION_KEY: string = 'bookMarkRevision';

  static notifyChanged(): void {
    AppStorage.setOrCreate<number>(BookMarkService.REVISION_KEY,
      (AppStorage.get<number>(BookMarkService.REVISION_KEY) || 0) + 1);
  }

  static keyOf(book: Book | null): string {
    return BookIdentity.markKeyOf(book);
  }

  static async markOf(book: Book | null): Promise<BookMark | null> {
    const key = BookMarkService.keyOf(book);
    return key ? await appDb.getBookMark(key) : null;
  }

  /** 给这本书准备草稿（还没保存）。还没有标记时，标签先取书架上这本书已有的标签。 */
  static async prepareDraft(book: Book, existing: BookMark | null): Promise<BookMark> {
    const mark = existing ? existing.clone() : new BookMark();
    mark.workKey = BookMarkService.keyOf(book);
    BookMarkService.applyBookInfo(mark, book);
    if (!existing && mark.workKey) {
      const shelf = await BookMarkService.shelfBooksOf(mark.workKey);
      if (shelf.length > 0) {
        mark.categories = BookMarkRules.normalizeCategories(BookMarkService.shelfCustomTags(shelf[0]));
      }
    }
    return mark;
  }

  /**
   * 保存草稿：内容全空就删掉。标成“读过”时补上读完时间，改成别的状态清掉。
   * 标签同步到书架上同一部作品的书（清空标签也同步）。返回保存后的标记；删掉时返回 null。
   */
  static async save(draft: BookMark): Promise<BookMark | null> {
    if (!draft.workKey) return null;
    const mark = draft.clone();
    mark.rating = BookMarkRules.normalizeRating(mark.rating);
    mark.status = BookMarkStatus.normalize(mark.status);
    mark.categories = BookMarkRules.normalizeCategories(mark.categories);
    mark.review = BookMarkRules.normalizeReview(mark.review);
    if (BookMarkRules.isEmpty(mark)) {
      await appDb.deleteBookMark(mark.workKey);
      await BookMarkService.pushTagsToShelf(mark.workKey, []);
      BookMarkService.notifyChanged();
      return null;
    }
    const now = Date.now();
    if (mark.createTime <= 0) mark.createTime = now;
    mark.updateTime = now;
    if (mark.status === BookMarkStatus.READ) {
      if (mark.finishTime <= 0) mark.finishTime = now;
    } else {
      mark.finishTime = 0;
    }
    await appDb.saveBookMark(mark);
    await BookMarkService.pushTagsToShelf(mark.workKey, mark.categories);
    BookMarkService.notifyChanged();
    return mark;
  }

  /** 详情页直接点星：只改评分，其余保持。 */
  static async rate(book: Book, existing: BookMark | null, rating: number): Promise<BookMark | null> {
    const draft = await BookMarkService.prepareDraft(book, existing);
    draft.rating = rating;
    return await BookMarkService.save(draft);
  }

  /** 删除标记。书架上的标签留着：书架那边也在用它们。 */
  static async remove(workKey: string): Promise<void> {
    if (!workKey) return;
    await appDb.deleteBookMark(workKey);
    BookMarkService.notifyChanged();
  }

  /** 标签面板里可点选的标签：所有标记用过的在前，再补上书架上用户加过的。 */
  static async knownTags(): Promise<string[]> {
    const result = BookMarkRules.collectCategories(await appDb.getAllBookMarks());
    for (const book of await BookMarkService.shelfBooks()) {
      for (const tag of BookMarkRules.normalizeCategories(BookMarkService.shelfCustomTags(book))) {
        if (!result.includes(tag)) result.push(tag);
      }
    }
    return result;
  }

  /**
   * 加入书架前调用（直接改 book，随后的写库一并保存）：书架这本还没有自己的标签、标记里有标签时，
   * 把标记的标签带过去。
   */
  static async carryTagsToShelfBook(book: Book): Promise<void> {
    try {
      if (BookMarkService.shelfCustomTags(book).length > 0) return;
      const key = BookMarkService.keyOf(book);
      const mark = key ? await appDb.getBookMark(key) : null;
      if (!mark || mark.categories.length === 0) return;
      book.customTag = BookMarkService.composeCustomTag(book, mark.categories);
    } catch (error) {
      console.warn('加入书架时同步标记标签失败:', error);
    }
  }

  /**
   * 补齐书架标签：书架上同一部作品的书还没有自己的标签、标记里有标签时，把标记的标签写过去。
   * 打通之前保存的标记、加入书架时没走到 carryTagsToShelfBook 的书、被旧的书籍快照写回空标签的书都靠这里补上。
   * 书架上已经有标签的书不动（书架上改过的以书架为准，见 syncTagsFromShelf）。只传 mark 时只补这一部作品。
   */
  static async fillMissingShelfTags(only: BookMark | null = null): Promise<number> {
    try {
      const marks = only ? [only] : await appDb.getAllBookMarks();
      const tagged = new Map<string, BookMark>();
      for (const mark of marks) {
        if (mark.workKey && mark.categories.length > 0) tagged.set(mark.workKey, mark);
      }
      if (tagged.size === 0) return 0;
      let changed = 0;
      for (const book of await BookMarkService.shelfBooks()) {
        const mark = tagged.get(BookIdentity.markKeyOf(book));
        if (!mark || BookMarkService.shelfCustomTags(book).length > 0) continue;
        book.customTag = BookMarkService.composeCustomTag(book, mark.categories);
        await appDb.updateBook(book, true, 'book_mark_tags_fill');
        changed++;
      }
      if (changed > 0) AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      return changed;
    } catch (error) {
      console.warn('补齐书架标签失败:', error);
      return 0;
    }
  }

  private static startupFillDone: boolean = false;

  /** 每次启动补一遍（每个进程只跑一次）。 */
  static fillMissingShelfTagsOnce(context: Context): void {
    if (BookMarkService.startupFillDone) return;
    BookMarkService.startupFillDone = true;
    appDb.init(context).then((): Promise<number> => BookMarkService.fillMissingShelfTags())
      .then((count: number): void => {
        if (count > 0) console.info(`书架标签已按标记补齐 ${count} 本`);
      }).catch((error: Error): void => console.warn('启动时补齐书架标签失败:', error));
  }

  /** 书架“自定义标签”保存后调用：这部作品有标记时，把标记的标签改成书架上的。没有标记不新建。 */
  static async syncTagsFromShelf(book: Book): Promise<void> {
    try {
      const key = BookMarkService.keyOf(book);
      const mark = key ? await appDb.getBookMark(key) : null;
      if (!mark) return;
      const custom = BookMarkService.shelfCustomTags(book);
      const visibleSource = BookDisplayHelper.getBookTags(book)
        .filter((tag: string): boolean => !custom.includes(tag));
      const tags = BookMarkTags.fromShelf(mark.categories, custom, visibleSource);
      if (BookMarkTags.same(tags, mark.categories)) return;
      mark.categories = tags;
      // 只改标签不算重新标记，保持修改时间与排序。
      if (BookMarkRules.isEmpty(mark)) {
        await appDb.deleteBookMark(mark.workKey);
      } else {
        await appDb.saveBookMark(mark);
      }
      BookMarkService.notifyChanged();
    } catch (error) {
      console.warn('书架标签同步到标记失败:', error);
    }
  }

  /** 重命名标签（标记和书架一起改）；新名字已存在时两个标签合并。返回改动的标记数。 */
  static async renameCategory(oldName: string, newName: string): Promise<number> {
    const target = BookMarkRules.normalizeCategory(newName);
    if (!oldName || !target || target === oldName) return 0;
    const rename = (tags: string[]): string[] => {
      const next: string[] = [];
      for (const name of tags) {
        const value = name === oldName ? target : name;
        if (!next.includes(value)) next.push(value);
      }
      return next;
    };
    let changed = 0;
    for (const mark of await appDb.getAllBookMarks()) {
      if (!mark.categories.includes(oldName)) continue;
      mark.categories = rename(mark.categories);
      // 改标签不算重新标记，保持原来的修改时间与排序。
      await appDb.saveBookMark(mark);
      changed++;
    }
    await BookMarkService.rewriteShelfTags(oldName, rename);
    if (changed > 0) BookMarkService.notifyChanged();
    return changed;
  }

  /** 从所有标记和书架上去掉这个标签；去掉后整条变空的标记一并删除。返回改动的标记数。 */
  static async deleteCategory(name: string): Promise<number> {
    if (!name) return 0;
    const without = (tags: string[]): string[] => tags.filter((item: string): boolean => item !== name);
    let changed = 0;
    for (const mark of await appDb.getAllBookMarks()) {
      if (!mark.categories.includes(name)) continue;
      mark.categories = without(mark.categories);
      if (BookMarkRules.isEmpty(mark)) {
        await appDb.deleteBookMark(mark.workKey);
      } else {
        await appDb.saveBookMark(mark);
      }
      changed++;
    }
    await BookMarkService.rewriteShelfTags(name, without);
    if (changed > 0) BookMarkService.notifyChanged();
    return changed;
  }

  /**
   * 从我的标记、足迹打开详情页。书架上有同一部作品时用书架那条（本地书的地址只在本机有效），
   * 否则用标记时记下的地址。
   */
  static async openDetail(mark: BookMark): Promise<void> {
    let shelfBook: Book | null = null;
    try {
      const books = await BookMarkService.shelfBooksOf(mark.workKey);
      shelfBook = books.length > 0 ? books[0] : null;
    } catch (error) {
      console.warn('查找书架上的标记书籍失败:', error);
    }
    const params: Record<string, string> = {};
    if (shelfBook) {
      params['bookUrl'] = shelfBook.bookUrl;
      params['tocUrl'] = shelfBook.tocUrl;
      params['origin'] = shelfBook.origin;
      params['originName'] = shelfBook.originName;
      params['name'] = shelfBook.name;
      params['author'] = shelfBook.author;
      params['kind'] = shelfBook.kind;
      params['status'] = shelfBook.status;
      params['coverUrl'] = shelfBook.customCoverUrl || shelfBook.coverUrl;
      params['intro'] = shelfBook.customIntro || shelfBook.intro;
      params['latestChapterTitle'] = shelfBook.latestChapterTitle;
      params['updateTime'] = shelfBook.updateTime;
      params['wordCount'] = shelfBook.wordCount;
      params['type'] = `${shelfBook.type}`;
      params['variable'] = shelfBook.variable;
    } else {
      params['bookUrl'] = mark.bookUrl;
      params['origin'] = mark.origin;
      params['originName'] = mark.originName;
      params['name'] = mark.bookName;
      params['author'] = mark.author;
      params['coverUrl'] = mark.coverUrl;
      params['type'] = `${mark.bookType}`;
    }
    params['promptAddToShelfOnBack'] = 'false';
    router.pushUrl({ url: 'pages/SearchBookDetail', params: params });
  }

  /** 书架上用户加的标签（customTag 里不带“!”的）。 */
  static shelfCustomTags(book: Book): string[] {
    return BookMarkTags.customOf(BookDisplayHelper.splitTags('', book.customTag));
  }

  private static composeCustomTag(book: Book, tags: string[]): string {
    return BookDisplayHelper.joinTags(
      BookMarkTags.composeShelfTokens(BookDisplayHelper.splitTags('', book.customTag), tags));
  }

  private static async shelfBooks(): Promise<Book[]> {
    const books = await appDb.getAllBooks();
    return books.filter((book: Book): boolean => !book.pendingAddToShelf);
  }

  private static async shelfBooksOf(workKey: string): Promise<Book[]> {
    if (!workKey) return [];
    return (await BookMarkService.shelfBooks())
      .filter((book: Book): boolean => BookIdentity.markKeyOf(book) === workKey);
  }

  /** 把标签写到书架上同一部作品的书；已经一样的不写。 */
  private static async pushTagsToShelf(workKey: string, tags: string[]): Promise<void> {
    try {
      let changed = false;
      for (const book of await BookMarkService.shelfBooksOf(workKey)) {
        const current = BookMarkRules.normalizeCategories(BookMarkService.shelfCustomTags(book));
        if (BookMarkTags.same(current, tags)) continue;
        book.customTag = BookMarkService.composeCustomTag(book, tags);
        await appDb.updateBook(book, true, 'book_mark_tags');
        changed = true;
      }
      if (changed) AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (error) {
      console.warn('标记标签同步到书架失败:', error);
    }
  }

  private static async rewriteShelfTags(name: string, transform: (tags: string[]) => string[]): Promise<void> {
    try {
      let changed = false;
      for (const book of await BookMarkService.shelfBooks()) {
        const custom = BookMarkService.shelfCustomTags(book);
        if (!custom.includes(name)) continue;
        book.customTag = BookMarkService.composeCustomTag(book, transform(custom));
        await appDb.updateBook(book, true, 'book_mark_tags');
        changed = true;
      }
      if (changed) AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (error) {
      console.warn('书架标签改名/删除失败:', error);
    }
  }

  /** 每次保存都记下当前这本书的地址和封面，书源换了也能回到最近用的那一个。 */
  private static applyBookInfo(mark: BookMark, book: Book): void {
    mark.bookName = book.name || mark.bookName;
    mark.author = book.author || mark.author;
    if (book.bookUrl) {
      mark.bookUrl = book.bookUrl;
      mark.origin = book.origin || '';
      mark.originName = book.originName || '';
      mark.bookType = book.type || 0;
    }
    // 只记书源封面：自定义封面可能是本机文件或多图轮换，换设备后对不上。
    if (book.coverUrl) mark.coverUrl = book.coverUrl;
  }
}
