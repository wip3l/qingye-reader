import { HttpTTS } from '@legado/sourceengine';

// 音色选项和自定义音色的解析放在这里，不放进 SystemTtsReader：阅读页打开时要读朗读设置，
// 而朗读引擎连同云端、自定义音色与 PCM 播放很大，阅读页对它是 lazy 导入，第一次朗读才加载。
export class TtsVoiceOption {
  id: number = 0;
  name: string = '默认音色';
  online: number = 1;
  status: string = '';
  systemStatus: string = '';
  style: string = '';
  language: string = 'zh-CN';
  downloadLanguage: string = '';
  gender: string = '';
  available: boolean = true;
  downloadable: boolean = false;
}

export class TtsCustomVoiceImportResult {
  voices: HttpTTS[] = [];
  /** 导入的条目合并后的 id，按文件中首次出现的顺序。 */
  importedIds: number[] = [];
  added: number = 0;
  updated: number = 0;
}

export class TtsCustomVoices {
  /** 插件音色的地址前缀。插件音色只在运行时并进列表，不写进保存的自定义音色。 */
  static readonly PLUGIN_URL_PREFIX: string = 'plugin-tts://';
  /** 启用中的插件提供的音色；由插件桥在启动时设置，插件功能关闭时返回空列表。 */
  static extraVoicesProvider: (() => HttpTTS[]) | null = null;

  /** 读出保存的自定义音色，并在末尾接上启用中的插件音色。 */
  static parse(raw: string): HttpTTS[] {
    return TtsCustomVoices.parseWith(raw, 0, true);
  }

  static isPluginVoice(voice: HttpTTS | null | undefined): boolean {
    return !!voice && (voice.url || '').startsWith(TtsCustomVoices.PLUGIN_URL_PREFIX);
  }

  /** 去掉插件音色，只留用户自己的自定义音色；保存和导出前调用。 */
  static withoutPluginVoices(voices: HttpTTS[]): HttpTTS[] {
    return voices.filter((voice: HttpTTS): boolean => !TtsCustomVoices.isPluginVoice(voice));
  }

  private static pluginVoices(): HttpTTS[] {
    if (!TtsCustomVoices.extraVoicesProvider) return [];
    try {
      return TtsCustomVoices.extraVoicesProvider();
    } catch (_) {
      return [];
    }
  }

  /** 导入用解析：没写 id（或 id 不是数字）的条目 id 记为 NaN，由 mergeImported 分配新 id。 */
  static parseImport(raw: string): HttpTTS[] {
    return TtsCustomVoices.parseWith(raw, NaN, false);
  }

  /**
   * 把导入的音色合并进已有列表。
   * 同一个音色的判定：名称和地址都相同，或 id 相同且地址相同（视为改名，只针对导入前已有的音色）；
   * id 相同但地址不同的是两个音色，导入的那条换新 id。同一份文件重复导入，结果不变。
   * 命中已有音色时用导入内容更新，但保留已有的 id（选中状态按 id 记）以及本机的启用状态和排序。
   */
  static mergeImported(existing: HttpTTS[], incoming: HttpTTS[]): TtsCustomVoiceImportResult {
    const result = new TtsCustomVoiceImportResult();
    const merged: HttpTTS[] = existing.slice();
    const taken = new Set<number>();
    for (const item of existing) taken.add(item.id);
    for (const item of incoming) {
      if (!Number.isNaN(item.id)) taken.add(item.id);
    }
    let nextId = Date.now();
    const freshId = (): number => {
      while (taken.has(nextId)) nextId++;
      taken.add(nextId);
      return nextId;
    };
    const addedIds = new Set<number>();
    const updatedIds = new Set<number>();
    // 本次导入已经写入的条目。按 id 改名只能改导入前就有的音色：否则文件里几条 id、地址相同而名称不同时，
    // 后一条会把前一条改名吞掉，下次导入前一条又被当成新音色加回来，同一个文件越导越多。
    const claimed = new Set<HttpTTS>();
    for (const voice of incoming) {
      const name = voice.name || '';
      const url = voice.url || '';
      let index = merged.findIndex((item: HttpTTS): boolean => (item.name || '') === name && (item.url || '') === url);
      if (index < 0 && !Number.isNaN(voice.id)) {
        index = merged.findIndex((item: HttpTTS): boolean =>
          !claimed.has(item) && item.id === voice.id && (item.url || '') === url);
      }
      if (index >= 0) {
        const previous = merged[index];
        voice.id = previous.id;
        voice.enabled = previous.enabled;
        voice.customOrder = previous.customOrder;
        merged[index] = voice;
        if (!addedIds.has(voice.id)) updatedIds.add(voice.id);
      } else {
        if (Number.isNaN(voice.id) || merged.some((item: HttpTTS): boolean => item.id === voice.id)) {
          voice.id = freshId();
        }
        merged.push(voice);
        addedIds.add(voice.id);
      }
      claimed.add(voice);
      if (!result.importedIds.includes(voice.id)) result.importedIds.push(voice.id);
    }
    result.voices = merged;
    result.added = addedIds.size;
    result.updated = updatedIds.size;
    return result;
  }

  static importSummary(result: TtsCustomVoiceImportResult): string {
    if (result.updated === 0) return `已导入 ${result.added} 个自定义音色`;
    if (result.added === 0) return `已更新 ${result.updated} 个自定义音色`;
    return `已导入 ${result.added} 个、更新 ${result.updated} 个自定义音色`;
  }

  private static parseWith(raw: string, missingId: number, includePlugins: boolean): HttpTTS[] {
    const extra: HttpTTS[] = includePlugins ? TtsCustomVoices.pluginVoices() : [];
    const value = (raw || '').trim();
    if (!value) {
      return extra;
    }
    try {
      const parsed = JSON.parse(value) as Object;
      const items = Array.isArray(parsed) ? parsed as Object[] : [parsed];
      const result: HttpTTS[] = [];
      for (const item of items) {
        const voice = TtsCustomVoices.parseVoice(item as Record<string, Object>, missingId);
        // 保存的数据里不该有插件音色；万一有（旧数据或手写导入），以插件当前提供的为准。
        if (voice.name && voice.url && !TtsCustomVoices.isPluginVoice(voice)) {
          result.push(voice);
        }
      }
      return result.concat(extra);
    } catch (_) {
      return extra;
    }
  }

  private static parseVoice(item: Record<string, Object>, missingId: number): HttpTTS {
    const voice = new HttpTTS();
    voice.id = TtsCustomVoices.integer(item['id'], missingId);
    voice.name = TtsCustomVoices.text(item['name']);
    voice.url = TtsCustomVoices.text(item['url']);
    voice.contentType = TtsCustomVoices.text(item['contentType']);
    voice.concurrentRate = TtsCustomVoices.text(item['concurrentRate']);
    voice.loginUrl = TtsCustomVoices.text(item['loginUrl']);
    voice.loginUi = TtsCustomVoices.text(item['loginUi']);
    voice.loginCheckJs = TtsCustomVoices.text(item['loginCheckJs']);
    voice.header = TtsCustomVoices.text(item['header']);
    voice.jsLib = TtsCustomVoices.text(item['jsLib']);
    voice.jsEngine = TtsCustomVoices.text(item['jsEngine']) || voice.jsLib;
    const enabledCookieJar = item['enabledCookieJar'];
    voice.enabledCookieJar = enabledCookieJar === true || String(enabledCookieJar) === 'true';
    voice.customOrder = TtsCustomVoices.integer(item['customOrder'], 0);
    voice.lastUpdateTime = TtsCustomVoices.integer(item['lastUpdateTime'], 0);
    const enabled = item['enabled'];
    voice.enabled = enabled === undefined || enabled === null ? true : enabled !== false && String(enabled) !== 'false';
    voice.speedMode = TtsCustomVoices.text(item['speedMode']).trim().toLowerCase();
    return voice;
  }

  private static text(value: Object | undefined): string {
    return value === undefined || value === null ? '' : String(value);
  }

  // 空值要单独判断：Number('') 是 0 而不是 NaN，否则缺字段时永远用不上 fallback。
  private static integer(value: Object | undefined, fallback: number): number {
    if (typeof value === 'number') {
      return Number.isFinite(value) ? Math.round(value) : fallback;
    }
    const text = value === undefined || value === null ? '' : String(value).trim();
    if (!text) {
      return fallback;
    }
    const parsed = Number(text);
    return Number.isFinite(parsed) ? Math.round(parsed) : fallback;
  }
}
