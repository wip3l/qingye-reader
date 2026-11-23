import { ReaderActionMarker } from '@legado/sourceengine';

/** 浏览器看书里一个可点的书源操作（段评、章评等）。 */
export class LanReaderAction {
  /** 插入位置：去掉标记后的正文里的字符偏移。 */
  pos: number = 0;
  /** 标记原本独占一行（如章末的“本章说”），网页把它画成单独一行的按钮。 */
  block: boolean = false;
  label: string = '';
  url: string = '';
  title: string = '';
  preview: string = '';
  likes: string = '';
}

export class LanReaderContent {
  text: string = '';
  actions: LanReaderAction[] = [];
}

/**
 * 把正文里的书源操作标记拆出来：正文不再带任何标记，能在浏览器里直接打开的（http/https 地址）
 * 另外列成操作清单。靠书源脚本、原生书源请求或应用内接口取数的操作离不开应用，这里只删不列。
 */
export class LanReaderActions {
  static readonly MAX_ACTIONS: number = 400;

  static split(content: string): LanReaderContent {
    const source = content || '';
    const result = new LanReaderContent();
    if (!ReaderActionMarker.has(source)) {
      result.text = source;
      return result;
    }
    let out = '';
    let cursor = 0;
    while (cursor < source.length) {
      const bounds = ReaderActionMarker.findFirstRawRange(source, cursor);
      if (bounds.length < 2) {
        out += source.substring(cursor);
        break;
      }
      const start = bounds[0];
      const end = Math.max(start + 1, bounds[1]);
      out += source.substring(cursor, start);
      cursor = end;
      // 独占一行：标记前（已输出的本行）和标记后（去掉同行其他标记）都没有正文。
      const lineStart = out.lastIndexOf('\n') + 1;
      const nextBreak = source.indexOf('\n', end);
      const lineEnd = nextBreak >= 0 ? nextBreak : source.length;
      const rest = source.substring(end, lineEnd);
      const block = out.substring(lineStart).trim().length === 0 && ReaderActionMarker.strip(rest).trim().length === 0;
      if (block) {
        out = out.substring(0, lineStart);
        // 同一行后面没有别的标记时，连同行尾换行一起去掉，不留空行。
        if (rest.trim().length === 0) cursor = nextBreak >= 0 ? nextBreak + 1 : source.length;
      }
      const data = ReaderActionMarker.parse(source.substring(start, end));
      if (!data || !/^https?:\/\//i.test(data.url) || result.actions.length >= LanReaderActions.MAX_ACTIONS) continue;
      const action = new LanReaderAction();
      action.pos = out.length;
      action.block = block;
      action.label = data.label;
      action.url = data.url;
      action.title = data.title;
      action.preview = data.preview;
      action.likes = data.likes;
      result.actions.push(action);
    }
    result.text = out.replace(/\s+$/, '');
    for (const action of result.actions) action.pos = Math.min(action.pos, result.text.length);
    return result;
  }
}
