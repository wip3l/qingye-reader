import { Context } from '@kit.AbilityKit';
import { TextTranslator } from '@legado/aiengine';

/** 阅读记录归并用的繁→简转换：字典进程内只读一次；读不出来时返回 null，按原字比较。 */
export class ReadStatsFold {
  static async load(context: Context): Promise<((text: string) => string) | null> {
    try {
      const dictionary = await TextTranslator.dictionary(context);
      return (text: string): string => dictionary.convertSameLength(text);
    } catch (e) {
      console.warn('阅读记录加载繁简字典失败:', e);
      return null;
    }
  }
}
