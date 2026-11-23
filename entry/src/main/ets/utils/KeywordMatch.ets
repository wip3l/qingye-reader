/** 文字里第一个命中的关键词（不区分大小写），拆成前、中、后三段，用于列表里高亮显示。 */
export class KeywordMatch {
  before: string = '';
  hit: string = '';
  after: string = '';

  static split(text: string, keyword: string): KeywordMatch {
    const result = new KeywordMatch();
    const normalized = (keyword || '').trim().toLowerCase();
    const index = normalized ? text.toLowerCase().indexOf(normalized) : -1;
    if (index < 0) {
      result.before = text;
      return result;
    }
    result.before = text.substring(0, index);
    result.hit = text.substring(index, index + normalized.length);
    result.after = text.substring(index + normalized.length);
    return result;
  }
}
