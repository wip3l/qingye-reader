/** 按书的繁→简与繁体检测。字典由 AI 引擎提供（与漫画文字层同一份 OpenCC 字典），这里只依赖它的转换方法。 */
export interface ReaderTextConverter {
  convertSameLength(text: string): string;
}

/** 一段样本的繁体特征：中文字数、转换后会变的字数、假名数（日文汉字多与繁体同形，要排除）。 */
export class ReaderTraditionalSample {
  cjk: number = 0;
  changed: number = 0;
  kana: number = 0;
}

export class ReaderTextConvert {
  /** 书籍变量：'t2s' 开、'off' 关，空表示没设置过（开书时会检测一次并询问）。 */
  static readonly VARIABLE: string = 'readerTextConvert';
  static readonly T2S: string = 't2s';
  static readonly OFF: string = 'off';
  /** 检测只看开头这么多字，够判断又不拖慢开书。 */
  static readonly SAMPLE_CHARS: number = 4000;

  // 与 ReaderContentPreprocessor 的豁免一致：标记里是应用内部的交互数据和编码过的图片路径，不是正文。
  private static readonly MARKER: RegExp =
    /(\[\[LEGADO_(?:READER_ACTION(?:_V[23])?|EPUB_IMAGE):[\s\S]*?\]\])/g;
  /** 一次转换的片段上限；长章节按换行切开分批，宿主可在批次之间让出主线程。 */
  private static readonly CHUNK_CHARS: number = 8000;

  static enabled(variable: string): boolean {
    return variable === ReaderTextConvert.T2S;
  }

  /** 没设置过才询问；用户选过“不用”（off）就不再打扰。 */
  static undecided(variable: string): boolean {
    return variable !== ReaderTextConvert.T2S && variable !== ReaderTextConvert.OFF;
  }

  /** 正文转换：标记原样保留，结果与原文等长逐位对齐。 */
  static convert(converter: ReaderTextConverter, text: string): string {
    const parts = ReaderTextConvert.chunks(text);
    for (let index = 0; index < parts.length; index++) {
      if (!ReaderTextConvert.isMarker(parts[index])) parts[index] = converter.convertSameLength(parts[index]);
    }
    return parts.join('');
  }

  /**
   * 把正文切成标记与不超过 CHUNK_CHARS 的文字片段，拼回去就是原文。文字只在换行处切开，词组不会被切断。
   * 宿主逐片转换、片间让出，超长 TXT 章节也不会一次占住主线程。
   */
  static chunks(text: string): string[] {
    const source = text || '';
    if (!source) return [];
    const pieces = source.indexOf('[[LEGADO_') >= 0 ? source.split(ReaderTextConvert.MARKER) : [source];
    const result: string[] = [];
    for (let index = 0; index < pieces.length; index++) {
      const piece = pieces[index];
      if (!piece) continue;
      if (index % 2 === 1) {
        result.push(piece);
        continue;
      }
      let start = 0;
      while (piece.length - start > ReaderTextConvert.CHUNK_CHARS) {
        const newline = piece.lastIndexOf('\n', start + ReaderTextConvert.CHUNK_CHARS);
        const end = newline > start ? newline + 1 : start + ReaderTextConvert.CHUNK_CHARS;
        result.push(piece.substring(start, end));
        start = end;
      }
      if (start < piece.length) result.push(piece.substring(start));
    }
    return result;
  }

  static isMarker(part: string): boolean {
    return part.startsWith('[[LEGADO_') && part.endsWith(']]');
  }

  static sample(converter: ReaderTextConverter, text: string): ReaderTraditionalSample {
    const result = new ReaderTraditionalSample();
    const plain = (text || '').replace(ReaderTextConvert.MARKER, '').substring(0, ReaderTextConvert.SAMPLE_CHARS);
    const converted = converter.convertSameLength(plain);
    for (let index = 0; index < plain.length; index++) {
      const code = plain.charCodeAt(index);
      if ((code >= 0x3040 && code <= 0x30FF) || (code >= 0x31F0 && code <= 0x31FF)) {
        result.kana++;
      } else if ((code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF)) {
        result.cjk++;
        if (converted.charCodeAt(index) !== code) result.changed++;
      }
    }
    return result;
  }

  /**
   * 繁体书通常有两三成的字会被转换，简体书几乎为零；门槛取 5% 且至少 30 字，避免简体书里偶尔夹的繁体字误判。
   * 假名占比明显的是日文，不提示。
   */
  static looksTraditional(sample: ReaderTraditionalSample): boolean {
    if (sample.cjk < 100 || sample.changed < 30) return false;
    if (sample.kana * 20 > sample.cjk) return false;
    return sample.changed * 20 >= sample.cjk;
  }
}
