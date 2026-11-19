/** 把繁体折成简体的函数；简繁字典没加载时传 null，按原字比对。 */
export type AuthorFold = ((text: string) => string) | null;

/**
 * 换源候选与书架原书的作者比对。
 * 两边先规整：去掉“作者：”前缀、“著 / 编著 / 原著”后缀、括号里的说明、空白与标点，英文转小写，繁体折成简体。
 * 规整后相等，或较短的一方至少两个字且被另一方包含（“土豆豌豆”与“土豆豌豆工作室”）算同一作者。
 * 任一边规整后为空或只是“未知”之类的占位，不下结论：照样显示，排在作者一致的后面。
 */
export class ChangeSourceAuthorMatch {
  static readonly SAME: number = 0;
  static readonly UNKNOWN: number = 1;
  static readonly DIFFERENT: number = 2;

  // 只认带冒号的前缀；“作者 土豆豌豆”这种靠包含关系也能对上，免得把名叫“作者”的整个吃掉。
  private static readonly PREFIX: RegExp = /^\s*(作\s*者|著\s*者|author)\s*[:：]\s*/i;
  private static readonly BRACKETS: RegExp = /[(（【\[〔「『][^)）】\]〕」』]*[)）】\]〕」』]/g;
  private static readonly SUFFIX: RegExp = /(\/|／|\s)*(原著|编著|編著|著|作品)$/;
  private static readonly PUNCTUATION: RegExp =
    /[\s·•・.,，。、:：;；'"“”‘’`!！?？\-—–_~～*\/／\\|&＆+＋#@=<>《》]/g;
  private static readonly PLACEHOLDERS: string[] = ['未知', '佚名', '暂无', '无', '不详', 'unknown', 'null', 'undefined', 'none'];

  static normalize(author: string, fold: AuthorFold = null): string {
    let text = String(author || '');
    if (!text) return '';
    try {
      // 全角字母数字转半角。
      text = text.normalize('NFKC');
    } catch (e) {
      // normalize 不可用时按原文继续。
    }
    text = text.replace(ChangeSourceAuthorMatch.PREFIX, '').replace(ChangeSourceAuthorMatch.BRACKETS, '').trim();
    text = text.replace(ChangeSourceAuthorMatch.SUFFIX, '');
    if (fold) text = fold(text);
    text = text.replace(ChangeSourceAuthorMatch.PUNCTUATION, '').toLowerCase();
    return ChangeSourceAuthorMatch.PLACEHOLDERS.includes(text) ? '' : text;
  }

  /** 返回 SAME / UNKNOWN / DIFFERENT。 */
  static compare(bookAuthor: string, candidateAuthor: string, fold: AuthorFold = null): number {
    const left = ChangeSourceAuthorMatch.normalize(bookAuthor, fold);
    const right = ChangeSourceAuthorMatch.normalize(candidateAuthor, fold);
    if (!left || !right) return ChangeSourceAuthorMatch.UNKNOWN;
    if (left === right) return ChangeSourceAuthorMatch.SAME;
    const shorter = left.length <= right.length ? left : right;
    const longer = shorter === left ? right : left;
    return shorter.length >= 2 && longer.includes(shorter) ? ChangeSourceAuthorMatch.SAME : ChangeSourceAuthorMatch.DIFFERENT;
  }
}
