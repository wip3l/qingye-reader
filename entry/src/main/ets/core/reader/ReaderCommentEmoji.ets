/** 热评文字切开后的一段：url 为空是文字，否则是一个表情图（text 是它的代号）。 */
export class ReaderCommentEmojiPiece {
  text: string = '';
  url: string = '';

  constructor(text: string, url: string) {
    this.text = text;
    this.url = url;
  }
}

/**
 * 热评、本章说文字里的表情代号。书源给了图片地址的代号画成图片；没给的常见代号（多数评论区通用的
 * [笑哭]、[赞] 一类）换成系统表情；其余照原样显示文字。
 */
export class ReaderCommentEmoji {
  /** 常见表情代号到系统表情。只收字面意思明确的，对不上的保留原文。 */
  private static readonly SYSTEM: Record<string, string> = {
    '微笑': '🙂', '笑脸': '😀', '开心': '😄', '哈哈': '😄', '大笑': '😄', '憨笑': '😄', '笑': '😄', '呲牙': '😁',
    '嘿哈': '😆', '偷笑': '🤭', '捂嘴笑': '🤭', '害羞': '😊', '可爱': '😊', '坏笑': '😏', '奸笑': '😏',
    '笑哭': '😂', '笑cry': '😂', '允悲': '😂', '捂脸': '🤦', '哭': '😭', '大哭': '😭', '泪奔': '😭',
    '流泪': '😢', '难过': '😢', '伤心': '😢', '委屈': '🥺', '可怜': '🥺', '色': '😍', '花痴': '😍',
    '爱心': '❤️', '心': '❤️', '比心': '🫶', '心碎': '💔', '亲亲': '😘', '飞吻': '😘', '抱抱': '🤗', '拥抱': '🤗',
    '赞': '👍', '点赞': '👍', '强': '👍', '弱': '👎', '踩': '👎', 'OK': '👌', 'ok': '👌', '抱拳': '🙏',
    '合十': '🙏', '祈祷': '🙏', '鼓掌': '👏', '握手': '🤝', '加油': '💪', '奋斗': '💪', '胜利': '✌️',
    '耶': '✌️', '拜拜': '👋', '再见': '👋', '思考': '🤔', '疑惑': '🤔', '疑问': '❓', '汗': '😓',
    '流汗': '😓', '擦汗': '😅', '尴尬': '😅', '无语': '😑', '白眼': '🙄', '惊讶': '😮', '吃惊': '😮',
    '震惊': '😱', '惊恐': '😱', '生气': '😠', '发怒': '😠', '怒': '😡', '抓狂': '😫', '睡': '😴',
    '睡觉': '😴', '困': '😪', '晕': '😵', '衰': '😩', '酷': '😎', '墨镜': '😎', '吐': '🤮', '呕吐': '🤮',
    '鄙视': '😒', '嘘': '🤫', '闭嘴': '🤐', '吃瓜': '🍉', '西瓜': '🍉', 'doge': '🐶', '狗头': '🐶',
    '二哈': '🐶', '猪头': '🐷', '玫瑰': '🌹', '凋谢': '🥀', '火': '🔥', '太阳': '☀️', '月亮': '🌙',
    '蛋糕': '🎂', '礼物': '🎁', '红包': '🧧', '咖啡': '☕', '啤酒': '🍺', '干杯': '🍻', '炸弹': '💣',
    '便便': '💩', '鬼脸': '😜', '调皮': '😜', '吐舌': '😛', '阴险': '😈', '恶魔': '😈', '骷髅': '💀',
    '发呆': '😳', '脸红': '😳', '捂眼': '🙈', '馋': '🤤', '流口水': '🤤', '叹气': '😮‍💨', '机智': '😏'
  };
  /** 系统表情表里代号的最长字数（含方括号）。 */
  private static readonly MAX_SYSTEM_TOKEN: number = 8;

  static systemEmoji(token: string): string {
    if (token.length < 3 || !token.startsWith('[') || !token.endsWith(']')) return '';
    return ReaderCommentEmoji.SYSTEM[token.substring(1, token.length - 1)] ?? '';
  }

  /**
   * 把文字切成文字段与表情图段。images 里的代号优先（长的先配），方括号代号再查系统表情表。
   * 没有任何表情时返回只有一段文字的列表。
   */
  static pieces(text: string, images: Record<string, string>): ReaderCommentEmojiPiece[] {
    const tokens = Object.keys(images).filter((token: string): boolean => token.length > 0)
      .sort((a: string, b: string): number => b.length - a.length);
    const result: ReaderCommentEmojiPiece[] = [];
    let buffer = '';
    let i = 0;
    while (i < text.length) {
      let matched = '';
      for (const token of tokens) {
        if (text.startsWith(token, i)) {
          matched = token;
          break;
        }
      }
      if (matched) {
        if (buffer) result.push(new ReaderCommentEmojiPiece(buffer, ''));
        buffer = '';
        result.push(new ReaderCommentEmojiPiece(matched, images[matched]));
        i += matched.length;
        continue;
      }
      if (text.charAt(i) === '[') {
        const close = text.indexOf(']', i + 1);
        if (close > i && close - i + 1 <= ReaderCommentEmoji.MAX_SYSTEM_TOKEN) {
          const emoji = ReaderCommentEmoji.systemEmoji(text.substring(i, close + 1));
          if (emoji) {
            buffer += emoji;
            i = close + 1;
            continue;
          }
        }
      }
      buffer += text.charAt(i);
      i++;
    }
    if (buffer) result.push(new ReaderCommentEmojiPiece(buffer, ''));
    return result;
  }
}
