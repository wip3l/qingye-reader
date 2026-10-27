/** 系统/云端音色的本地可见性；键不依赖展示名称、下载状态或服务端排序。 */
export class TtsVoiceAvailability {
  static readonly DEFAULT_KEY: string = 'system:0_1_zh-CN_';

  static systemKey(person: number, online: number, language: string, style: string): string {
    let lang = (language || 'zh-CN').trim().replace(/_/g, '-').toLowerCase();
    if (lang === 'zh' || lang === 'zh-cn' || lang.startsWith('zh-hans')) lang = 'zh-CN';
    if (lang === 'en' || lang === 'en-us') lang = 'en-US';
    const known = person === 0 || person === 8 || person === 13 || person === 21;
    return `system:${person}_${online}_${lang}_${known ? '' : (style || '')}`;
  }

  static cloudKey(id: string): string { return `cloud:${id}`; }

  static normalize(raw: string): string {
    const keys: string[] = [];
    for (const line of (raw || '').split('\n')) {
      const key = line.trim();
      if ((key.startsWith('system:') || key.startsWith('cloud:')) &&
        key !== TtsVoiceAvailability.DEFAULT_KEY && !keys.includes(key)) keys.push(key);
    }
    return keys.join('\n');
  }

  static isEnabled(raw: string, key: string): boolean {
    return key === TtsVoiceAvailability.DEFAULT_KEY || !TtsVoiceAvailability.normalize(raw).split('\n').includes(key);
  }

  static setEnabled(raw: string, key: string, enabled: boolean): string {
    const keys = TtsVoiceAvailability.normalize(raw).split('\n').filter((item: string): boolean => !!item && item !== key);
    if (!enabled && key !== TtsVoiceAvailability.DEFAULT_KEY) keys.push(key);
    return TtsVoiceAvailability.normalize(keys.join('\n'));
  }
}
