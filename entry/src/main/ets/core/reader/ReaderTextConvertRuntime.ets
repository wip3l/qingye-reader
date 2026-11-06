import { common } from '@kit.AbilityKit';
import { ComicChineseDictionary, TextTranslator } from '@legado/aiengine';
import { CooperativeScheduler } from '@legado/sourceengine';
import { ReaderTextConvert } from './ReaderTextConvert';

/**
 * 小说繁→简的进程内入口。字典只读一次（引擎内共享，漫画文字层也用它）；小说繁→简是本地字典转换，
 * 不走 AI 授权，所以直接取字典而不是 TextTranslator.translate。
 */
export class ReaderTextConvertRuntime {
  private static dictionary: ComicChineseDictionary | null = null;
  /** 连续转换超过这么久就让出一次主线程。 */
  private static readonly SLICE_MS: number = 8;

  /** 已加载的字典；没加载时同步调用方（章节标题）先显示原文，加载后由宿主刷新。 */
  static ready(): ComicChineseDictionary | null {
    return ReaderTextConvertRuntime.dictionary;
  }

  static async load(context: common.Context): Promise<ComicChineseDictionary> {
    if (!ReaderTextConvertRuntime.dictionary) {
      ReaderTextConvertRuntime.dictionary = await TextTranslator.dictionary(context);
    }
    return ReaderTextConvertRuntime.dictionary;
  }

  static async convert(context: common.Context, text: string): Promise<string> {
    if (!text) return text;
    const dictionary = await ReaderTextConvertRuntime.load(context);
    const parts = ReaderTextConvert.chunks(text);
    let sliceStart = Date.now();
    for (let index = 0; index < parts.length; index++) {
      if (ReaderTextConvert.isMarker(parts[index])) continue;
      parts[index] = dictionary.convertSameLength(parts[index]);
      if (index < parts.length - 1 && Date.now() - sliceStart >= ReaderTextConvertRuntime.SLICE_MS) {
        await CooperativeScheduler.yieldToEventLoop();
        sliceStart = Date.now();
      }
    }
    return parts.join('');
  }

  /** 同步转换短文本（章节标题、查找摘录所在的章）；字典未就绪时原样返回。 */
  static convertNow(text: string): string {
    const dictionary = ReaderTextConvertRuntime.dictionary;
    return dictionary && text ? ReaderTextConvert.convert(dictionary, text) : text;
  }
}
