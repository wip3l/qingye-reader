import { common } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { ChineseTaiwanConverter, ComicChineseDictionary, TextTranslator } from '@legado/aiengine';
import { appDb } from '../../model/data/AppDatabase';
import { ChineseScriptConverter, SearchChineseScript } from './SearchChineseScript';

/** AI 引擎里的 OpenCC 字典：繁→简用等长转换（比对不改变长度），简→繁用台湾用字。 */
class OpenCcScriptConverter implements ChineseScriptConverter {
  private readonly simplified: ComicChineseDictionary;
  private readonly traditional: ChineseTaiwanConverter;

  constructor(simplified: ComicChineseDictionary, traditional: ChineseTaiwanConverter) {
    this.simplified = simplified;
    this.traditional = traditional;
  }

  toSimplified(text: string): string {
    return this.simplified.convertSameLength(text);
  }

  toTraditional(text: string): string {
    return this.traditional.convert(text);
  }
}

/**
 * 简繁同搜的进程内入口：字典与“书源用字”只读一次，搜索层、换源和聚合分组共用同一个实例。
 * 书源用字按书源地址存在独立的偏好文件里，读入时去掉已删除的书源，超过上限从最早记下的删起。
 */
export class SearchChineseScriptRuntime {
  static readonly STORAGE_KEY: string = 'searchExploreSimpTradSearch';
  private static readonly STORE_NAME: string = 'search_source_script';
  private static readonly KEY_HINTS: string = 'sourceScripts';
  private static readonly MAX_HINTS: number = 3000;
  private static instance: SearchChineseScript | null = null;
  private static loading: Promise<SearchChineseScript> | null = null;
  private static hints: Map<string, string> = new Map();

  static enabled(): boolean {
    return AppStorage.get<boolean>(SearchChineseScriptRuntime.STORAGE_KEY) !== false;
  }

  /** 已加载且开关开着时返回实例；同步调用方（聚合分组、结果角标）用它，未就绪时按逐字处理。 */
  static ready(): SearchChineseScript | null {
    return SearchChineseScriptRuntime.enabled() ? SearchChineseScriptRuntime.instance : null;
  }

  /**
   * 开关开着时加载并返回实例；字典读不出来时返回 null，这次搜索按原词逐字进行。
   * 简→繁词组表约 5 万条，解析要占主线程一小段，所以不在搜索层打开时预载（会卡入场动画和输入），
   * 而是在第一次点搜索、界面已显示“正在准备搜索”时读一次，之后整个进程复用。
   */
  static async forSearch(context: common.Context): Promise<SearchChineseScript | null> {
    if (!SearchChineseScriptRuntime.enabled()) return null;
    try {
      return await SearchChineseScriptRuntime.load(context);
    } catch (e) {
      console.warn('[SearchScript] 简繁字典加载失败:', e);
      return null;
    }
  }

  /** 搜索结束后调用：这次有新记下的书源用字才写回。 */
  static async saveHints(context: common.Context): Promise<void> {
    const script = SearchChineseScriptRuntime.instance;
    if (!script || !script.takeChanged()) return;
    const hints = SearchChineseScriptRuntime.hints;
    while (hints.size > SearchChineseScriptRuntime.MAX_HINTS) {
      const oldest = hints.keys().next();
      if (oldest.done) break;
      hints.delete(oldest.value);
    }
    const entries: string[][] = [];
    hints.forEach((value: string, key: string) => {
      entries.push([key, value]);
    });
    try {
      const store = await preferences.getPreferences(context, SearchChineseScriptRuntime.STORE_NAME);
      await store.put(SearchChineseScriptRuntime.KEY_HINTS, JSON.stringify(entries));
      await store.flush();
    } catch (e) {
      console.warn('[SearchScript] 保存书源用字失败:', e);
    }
  }

  private static async load(context: common.Context): Promise<SearchChineseScript> {
    if (SearchChineseScriptRuntime.instance) return SearchChineseScriptRuntime.instance;
    if (!SearchChineseScriptRuntime.loading) {
      SearchChineseScriptRuntime.loading = SearchChineseScriptRuntime.read(context).finally(() => {
        SearchChineseScriptRuntime.loading = null;
      });
    }
    return await SearchChineseScriptRuntime.loading;
  }

  private static async read(context: common.Context): Promise<SearchChineseScript> {
    const simplified = await TextTranslator.dictionary(context);
    const traditional = await TextTranslator.taiwanConverter(context);
    SearchChineseScriptRuntime.hints = await SearchChineseScriptRuntime.readHints(context);
    const script = new SearchChineseScript(new OpenCcScriptConverter(simplified, traditional),
      SearchChineseScriptRuntime.hints);
    SearchChineseScriptRuntime.instance = script;
    return script;
  }

  private static async readHints(context: common.Context): Promise<Map<string, string>> {
    const hints: Map<string, string> = new Map();
    try {
      const store = await preferences.getPreferences(context, SearchChineseScriptRuntime.STORE_NAME);
      const raw = await store.get(SearchChineseScriptRuntime.KEY_HINTS, '');
      if (typeof raw !== 'string' || !raw) return hints;
      const entries = JSON.parse(raw) as string[][];
      if (!Array.isArray(entries)) return hints;
      // 只取书源地址这一列，比读完整书源轻；书源删掉后它的用字也就不要了。
      const existing = await appDb.getBookSourceAddedTimes();
      for (const entry of entries) {
        if (!Array.isArray(entry) || entry.length !== 2) continue;
        const url = String(entry[0] || '');
        const script = String(entry[1] || '');
        // 书源库还没打开时（读不到任何地址）全部保留，免得误删。
        if (existing.size > 0 && !existing.has(url)) continue;
        if (script !== SearchChineseScript.SIMPLIFIED && script !== SearchChineseScript.TRADITIONAL) continue;
        hints.set(url, script);
      }
    } catch (e) {
      console.warn('[SearchScript] 读取书源用字失败:', e);
    }
    return hints;
  }
}
