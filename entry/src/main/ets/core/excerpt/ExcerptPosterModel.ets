/** 摘录分享图的数据与选项；阅读页只引用这里，不会连带加载画图代码。 */
/** 分享图上的一条摘录：进分享页时从划线和书架上的书取一次，之后不再跟着改。 */
export class ExcerptPosterSnapshot {
  quote: string = '';
  note: string = '';
  bookName: string = '';
  author: string = '';
  chapterName: string = '';
  /** 划线时间（毫秒）。 */
  time: number = 0;
  /** 书架封面（自定义封面优先）；书已不在书架时为空。 */
  coverUrl: string = '';
  /** 划线颜色 '#RRGGBB'。 */
  color: string = '#3B82F6';
  /** 登录账号的昵称，未登录为空。 */
  nickname: string = '';
}

/** 分享页的选项，存本机。 */
export class ExcerptPosterOptions {
  style: number = 0;
  note: boolean = true;
  cover: boolean = true;
  meta: boolean = true;
  signature: boolean = true;
  alias: string = '';
  accent: boolean = false;

  static normalize(input: ExcerptPosterOptions): ExcerptPosterOptions {
    const result = new ExcerptPosterOptions();
    result.style = [0, 1, 2, 3].includes(Number(input.style)) ? Number(input.style) : 0;
    result.note = input.note !== false;
    result.cover = input.cover !== false;
    result.meta = input.meta !== false;
    result.signature = input.signature !== false;
    result.alias = typeof input.alias === 'string' ? input.alias.slice(0, 24) : '';
    result.accent = input.accent === true;
    return result;
  }
}

/** 阅读页、我的摘录把要分享的摘录交给分享页；只放进程单例模块，页面文件的静态字段每次开页都是新的。 */
export class ExcerptPosterSession {
  private static pending: ExcerptPosterSnapshot | null = null;

  static put(snapshot: ExcerptPosterSnapshot): void {
    ExcerptPosterSession.pending = snapshot;
  }

  static take(): ExcerptPosterSnapshot | null {
    const snapshot = ExcerptPosterSession.pending;
    ExcerptPosterSession.pending = null;
    return snapshot;
  }
}
