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

export class TtsCustomVoices {
  static parse(raw: string): HttpTTS[] {
    const value = (raw || '').trim();
    if (!value) {
      return [];
    }
    try {
      const parsed = JSON.parse(value) as Object;
      const items = Array.isArray(parsed) ? parsed as Object[] : [parsed];
      const result: HttpTTS[] = [];
      for (const item of items) {
        const voice = TtsCustomVoices.parseVoice(item as Record<string, Object>);
        if (voice.name && voice.url) {
          result.push(voice);
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  private static parseVoice(item: Record<string, Object>): HttpTTS {
    const voice = new HttpTTS();
    voice.id = TtsCustomVoices.integer(item['id'], Date.now());
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
    return voice;
  }

  private static text(value: Object | undefined): string {
    return value === undefined || value === null ? '' : String(value);
  }

  private static integer(value: Object | undefined, fallback: number): number {
    if (typeof value === 'number') {
      return Math.round(value);
    }
    const parsed = Number(value === undefined || value === null ? '' : String(value));
    return Number.isNaN(parsed) ? fallback : Math.round(parsed);
  }
}
