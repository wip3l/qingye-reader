/**
 * 书籍标记：用户给一部作品的评分、阅读状态、标签和短评，当作阅读记录。
 * 标签存在 categories 字段里（列名沿用），和书架标签是同一套，见 BookMarkTags。
 * 按作品（媒体类型 + 规范化书名 + 作者，见 BookIdentity.markKeyOf）存，换源、移出书架、删书都不影响；
 * 没加书架的书在详情页也能标记。bookUrl/origin/coverUrl 只是最近一次标记时的地址，用来从“我的标记”回到详情页。
 */
export class BookMark {
  workKey: string = '';
  bookName: string = '';
  author: string = '';
  bookUrl: string = '';
  origin: string = '';
  originName: string = '';
  coverUrl: string = '';
  /** 书籍类型位（Book.type），回到详情页时用来区分小说、有声、视频。 */
  bookType: number = 0;
  /** 0–10，0 = 没打分，每 1 是半颗星。 */
  rating: number = 0;
  status: number = BookMarkStatus.NONE;
  categories: string[] = [];
  review: string = '';
  createTime: number = 0;
  updateTime: number = 0;
  /** 标成“读过”的时间；改成别的状态时清零。 */
  finishTime: number = 0;

  clone(): BookMark {
    const copy = new BookMark();
    copy.workKey = this.workKey;
    copy.bookName = this.bookName;
    copy.author = this.author;
    copy.bookUrl = this.bookUrl;
    copy.origin = this.origin;
    copy.originName = this.originName;
    copy.coverUrl = this.coverUrl;
    copy.bookType = this.bookType;
    copy.rating = this.rating;
    copy.status = this.status;
    copy.categories = this.categories.slice();
    copy.review = this.review;
    copy.createTime = this.createTime;
    copy.updateTime = this.updateTime;
    copy.finishTime = this.finishTime;
    return copy;
  }
}

export class BookMarkStatus {
  static readonly NONE: number = 0;
  static readonly WANT: number = 1;
  static readonly READING: number = 2;
  static readonly READ: number = 3;
  /** 读了一部分不打算读下去。值排在读过之后，旧版本按未标状态处理。 */
  static readonly DROPPED: number = 4;
  static readonly LABELS: string[] = ['', '想读', '在读', '读过', '弃读'];
  /** 可选状态，按界面上的先后排列。 */
  static readonly ALL: number[] = [BookMarkStatus.WANT, BookMarkStatus.READING, BookMarkStatus.READ,
    BookMarkStatus.DROPPED];

  static label(status: number): string {
    return BookMarkStatus.LABELS[BookMarkStatus.normalize(status)];
  }

  static normalize(value: number | string | undefined | null): number {
    const status = Math.floor(Number(value) || 0);
    return status >= BookMarkStatus.WANT && status <= BookMarkStatus.DROPPED ? status : BookMarkStatus.NONE;
  }
}

export class BookMarkRules {
  static readonly MAX_RATING: number = 10;
  static readonly MAX_CATEGORIES: number = 10;
  static readonly MAX_CATEGORY_LENGTH: number = 16;
  static readonly MAX_REVIEW_LENGTH: number = 500;

  static normalizeRating(value: number | string | undefined | null): number {
    const rating = Math.round(Number(value) || 0);
    return Math.max(0, Math.min(BookMarkRules.MAX_RATING, rating));
  }

  /** 去空白、去重、截断长度和个数；顺序保留用户添加的先后。 */
  static normalizeCategories(values: Object | undefined | null): string[] {
    const result: string[] = [];
    if (!Array.isArray(values)) return result;
    for (const raw of values as Object[]) {
      const name = BookMarkRules.normalizeCategory(String(raw === undefined || raw === null ? '' : raw));
      if (name && !result.includes(name)) result.push(name);
      if (result.length >= BookMarkRules.MAX_CATEGORIES) break;
    }
    return result;
  }

  /**
   * 标签和书架标签共用：书架按空白、逗号、顿号、斜杠、冒号等拆分 customTag，
   * 这些字符留在标签里写进书架就会被拆成几个，所以一律去掉；开头的“!”在书架里表示隐藏书源标签，也去掉。
   */
  static normalizeCategory(value: string): string {
    return (value || '').replace(/[\s\u200B-\u200D\uFEFF|/;；、，,·•●▪:：<>]+/g, '')
      .replace(/^!+/, '').substring(0, BookMarkRules.MAX_CATEGORY_LENGTH);
  }

  static normalizeReview(value: string | undefined | null): string {
    return String(value || '').trim().substring(0, BookMarkRules.MAX_REVIEW_LENGTH);
  }

  static parseCategories(raw: string): string[] {
    if (!raw) return [];
    try {
      return BookMarkRules.normalizeCategories(JSON.parse(raw) as Object);
    } catch (_) {
      return [];
    }
  }

  /** 什么都没填的标记等于没有标记，保存时直接删掉。 */
  static isEmpty(mark: BookMark): boolean {
    return mark.rating <= 0 && mark.status === BookMarkStatus.NONE && mark.categories.length === 0 &&
      !mark.review.trim();
  }

  static ratingLabel(rating: number): string {
    if (rating <= 0) return '';
    if (rating <= 2) return '很差';
    if (rating <= 4) return '较差';
    if (rating <= 6) return '还行';
    if (rating <= 8) return '推荐';
    return '力荐';
  }

  /**
   * 某个状态下打过分的书的平均星级文字，没有打分的书返回空串。
   * status 为 0 表示“全部”，不算弃读的书：弃读多半是读不下去，打的低分会把整体均分拉偏。
   */
  static averageRatingText(marks: BookMark[], status: number): string {
    let sum = 0;
    let count = 0;
    for (const mark of marks) {
      if (mark.rating <= 0) continue;
      if (status === BookMarkStatus.NONE ? mark.status === BookMarkStatus.DROPPED : mark.status !== status) continue;
      sum += mark.rating;
      count++;
    }
    return count > 0 ? (sum / count / 2).toFixed(1) : '';
  }

  /** “4.5”这样的星级文字。 */
  static ratingText(rating: number): string {
    return (BookMarkRules.normalizeRating(rating) / 2).toFixed(1);
  }

  /** 每颗星的填充比例（0、0.5、1），index 从 0 开始。 */
  static starFill(rating: number, index: number): number {
    const value = BookMarkRules.normalizeRating(rating);
    if (value >= (index + 1) * 2) return 1;
    if (value === index * 2 + 1) return 0.5;
    return 0;
  }

  /** 读书手账按评分排序时的分段名：整星一档，半星归到下一档（4.5 星在“4 星”里）。 */
  static ratingBand(rating: number): string {
    const value = BookMarkRules.normalizeRating(rating);
    if (value <= 0) return '未打分';
    if (value === 1) return '半星';
    return `${Math.floor(value / 2)} 星`;
  }

  /** 读书手账按最近标记排序时的分段名：今年只写月份，往年带年份。 */
  static monthLabel(time: number, now: number): string {
    const date = new Date(time);
    const month = `${date.getMonth() + 1}月`;
    return date.getFullYear() === new Date(now).getFullYear() ? month : `${date.getFullYear()}年${month}`;
  }

  /** 备份、同步读回来的可能是普通对象，逐个字段规整；没有作品键或书名的返回 null。 */
  static fromPlain(source: Object | null | undefined): BookMark | null {
    if (!source || typeof source !== 'object') return null;
    const value = source as Record<string, Object>;
    const mark = new BookMark();
    mark.workKey = String(value['workKey'] || '');
    mark.bookName = String(value['bookName'] || '').trim();
    if (!mark.workKey || !mark.bookName) return null;
    mark.author = String(value['author'] || '');
    mark.bookUrl = String(value['bookUrl'] || '');
    mark.origin = String(value['origin'] || '');
    mark.originName = String(value['originName'] || '');
    mark.coverUrl = String(value['coverUrl'] || '');
    mark.bookType = Math.max(0, Math.floor(Number(value['bookType']) || 0));
    mark.rating = BookMarkRules.normalizeRating(value['rating'] as number);
    mark.status = BookMarkStatus.normalize(value['status'] as number);
    mark.categories = BookMarkRules.normalizeCategories(value['categories']);
    mark.review = BookMarkRules.normalizeReview(value['review'] as string);
    mark.createTime = Math.max(0, Math.floor(Number(value['createTime']) || 0));
    mark.updateTime = Math.max(mark.createTime, Math.floor(Number(value['updateTime']) || 0));
    mark.finishTime = mark.status === BookMarkStatus.READ ?
      Math.max(0, Math.floor(Number(value['finishTime']) || 0)) : 0;
    return mark;
  }

  /** 所有标记里用过的标签，按使用次数多的在前，同样多的按名字。 */
  static collectCategories(marks: BookMark[]): string[] {
    const counts = new Map<string, number>();
    for (const mark of marks) {
      for (const name of mark.categories) {
        counts.set(name, (counts.get(name) || 0) + 1);
      }
    }
    return Array.from(counts.keys()).sort((a: string, b: string): number =>
      (counts.get(b) || 0) - (counts.get(a) || 0) || a.localeCompare(b, 'zh-Hans-CN'));
  }
}

/**
 * 标记的标签与书架标签（Book.customTag）互通的纯逻辑。customTag 里不带“!”的是用户加的标签，
 * 带“!”的是被隐藏的书源标签（如 !玄幻）。标记是记录本身，书架在三处跟着改：
 * 标记面板保存、书架“自定义标签”保存、书籍加入书架（书架那本还没有自己的标签时）。
 */
export class BookMarkTags {
  static customOf(tokens: string[]): string[] {
    return tokens.filter((token: string): boolean => !!token && !token.startsWith('!'));
  }

  /** 用标记的标签替换书架上用户加的标签，保留隐藏书源标签；用户又加回被隐藏的书源标签时取消隐藏。 */
  static composeShelfTokens(tokens: string[], tags: string[]): string[] {
    const result: string[] = tags.slice();
    for (const token of tokens) {
      if (!token.startsWith('!')) continue;
      const hidden = token.substring(1).trim();
      if (hidden && !tags.includes(hidden) && !result.includes(token)) result.push(token);
    }
    return result;
  }

  /**
   * 书架上改了标签后标记的标签。书架保存时会把和书源标签同名的标签从 customTag 里省掉，
   * 所以标记里原有、书架上仍然显示的书源同名标签要留着。原有的保持顺序，新加的排在后面。
   */
  static fromShelf(markTags: string[], customTags: string[], visibleSourceTags: string[]): string[] {
    const result = markTags.filter((tag: string): boolean =>
      customTags.includes(tag) || visibleSourceTags.includes(tag));
    for (const tag of customTags) {
      if (!result.includes(tag)) result.push(tag);
    }
    return BookMarkRules.normalizeCategories(result);
  }

  static same(a: string[], b: string[]): boolean {
    return a.length === b.length && a.every((tag: string, index: number): boolean => tag === b[index]);
  }
}
