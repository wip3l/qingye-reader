import { HttpTTS } from '@legado/sourceengine';
import { TtsVoiceInfo } from '../account/AccountCommerceModels';
import { TtsVoiceOption } from './SystemTtsReader';
import { TtsVoiceAvailability } from './TtsVoiceAvailability';

/**
 * 朗读音色的比对、去重与展示文案（无状态）。系统返回的音色列表里同一个音色可能以在线、离线、
 * 不同风格等多个条目出现，这里决定哪些算同一个、保留哪一个、以及界面上怎么称呼。
 */
export class TtsVoiceCatalog {
  static isDefault(voice: TtsVoiceOption): boolean {
    return TtsVoiceAvailability.systemKey(voice.id, voice.online, voice.language, voice.style) ===
      TtsVoiceAvailability.DEFAULT_KEY;
  }

  static systemEnabled(voice: TtsVoiceOption, disabledKeys: string): boolean {
    return TtsVoiceAvailability.isEnabled(disabledKeys,
      TtsVoiceAvailability.systemKey(voice.id, voice.online, voice.language, voice.style));
  }

  static cloudEnabled(voice: TtsVoiceInfo, disabledKeys: string): boolean {
    return TtsVoiceAvailability.isEnabled(disabledKeys, TtsVoiceAvailability.cloudKey(voice.id));
  }

  static defaultVoice(): TtsVoiceOption {
    const option = new TtsVoiceOption();
    option.id = 0;
    option.name = '默认音色';
    option.online = 1;
    option.status = 'default';
    option.language = 'zh-CN';
    option.available = true;
    return option;
  }

  /** 系统内置的几个固定音色编号；它们不靠 style 区分。 */
  static isKnownVoiceId(id: number): boolean {
    return id === 0 || id === 8 || id === 13 || id === 21;
  }

  static normalizeLanguage(language: string): string {
    const value = (language || 'zh-CN').trim().replace(/_/g, '-').toLowerCase();
    if (value === 'zh' || value === 'zh-cn' || value.startsWith('zh-hans')) return 'zh-CN';
    if (value === 'en' || value === 'en-us') return 'en-US';
    return value || 'zh-CN';
  }

  static sameLanguage(left: string, right: string): boolean {
    return TtsVoiceCatalog.normalizeLanguage(left) === TtsVoiceCatalog.normalizeLanguage(right);
  }

  /** 把默认音色放在最前，并把系统列表里重复的条目合并成更可用的那一个。 */
  static mergeWithDefault(voices: TtsVoiceOption[]): TtsVoiceOption[] {
    const options: TtsVoiceOption[] = [TtsVoiceCatalog.defaultVoice()];
    for (const voice of voices) {
      const existingIndex = options.findIndex((item: TtsVoiceOption) =>
        TtsVoiceCatalog.isSameVoice(item, voice) || (!TtsVoiceCatalog.isDefault(item) &&
          !TtsVoiceCatalog.isDefault(voice) && TtsVoiceCatalog.isSameDisplayVoice(item, voice)));
      if (existingIndex < 0) {
        options.push(voice);
      } else if (TtsVoiceCatalog.shouldPrefer(voice, options[existingIndex])) {
        options[existingIndex] = voice;
      }
    }
    return options;
  }

  /** installedKeysRaw 是用户已下载音色的键，每行一个；命中的音色标成已安装、可用。 */
  static applyInstalledOverrides(voices: TtsVoiceOption[], installedKeysRaw: string): TtsVoiceOption[] {
    const installedKeys = (installedKeysRaw || '').split('\n');
    const options: TtsVoiceOption[] = [];
    for (const voice of voices) {
      const key = TtsVoiceCatalog.installedKey(voice);
      options.push(!!key && installedKeys.includes(key) ? TtsVoiceCatalog.markInstalled(voice) : voice);
    }
    return options;
  }

  static installedKey(voice: TtsVoiceOption): string {
    const style = TtsVoiceCatalog.isKnownVoiceId(voice.id) ? '' : (voice.style || '');
    return `${voice.id}_${voice.online}_${TtsVoiceCatalog.normalizeLanguage(voice.language || 'zh-CN')}_${style}`;
  }

  static markInstalled(voice: TtsVoiceOption): TtsVoiceOption {
    const option = new TtsVoiceOption();
    option.id = voice.id;
    option.name = voice.name;
    option.online = voice.online;
    option.status = 'INSTALLED';
    option.systemStatus = 'INSTALLED';
    option.style = voice.style;
    option.language = voice.language;
    option.downloadLanguage = voice.downloadLanguage;
    option.gender = voice.gender;
    option.available = true;
    option.downloadable = false;
    return option;
  }

  static isSameVoice(left: TtsVoiceOption, right: TtsVoiceOption): boolean {
    if (left.id !== right.id || left.online !== right.online ||
      !TtsVoiceCatalog.sameLanguage(left.language || 'zh-CN', right.language || 'zh-CN')) {
      return false;
    }
    if (TtsVoiceCatalog.isKnownVoiceId(left.id)) return true;
    return (left.style || '') === (right.style || '');
  }

  static isSameDisplayVoice(left: TtsVoiceOption, right: TtsVoiceOption): boolean {
    if (TtsVoiceCatalog.voiceTitle(left) === TtsVoiceCatalog.voiceTitle(right)) return true;
    return (left.name || '') === (right.name || '') && left.online === right.online &&
      TtsVoiceCatalog.sameLanguage(left.language || 'zh-CN', right.language || 'zh-CN');
  }

  static shouldPrefer(candidate: TtsVoiceOption, current: TtsVoiceOption): boolean {
    if (candidate.available !== current.available) return candidate.available;
    if (TtsVoiceCatalog.isKnownVoiceId(candidate.id) !== TtsVoiceCatalog.isKnownVoiceId(current.id)) {
      return TtsVoiceCatalog.isKnownVoiceId(candidate.id);
    }
    if (candidate.downloadable !== current.downloadable) return candidate.downloadable;
    return !current.style && !!candidate.style;
  }

  static voiceKey(voice: TtsVoiceOption): string {
    return `${voice.id}_${voice.online}_${voice.language || 'zh-CN'}_${voice.style || ''}_${voice.name || ''}`;
  }

  static voiceTitle(voice: TtsVoiceOption): string {
    if (voice.status === 'default') return `${voice.name} · 系统默认`;
    const suffix = voice.online === 0 ? '在线' : '离线';
    const state = voice.available ? '' : (voice.downloadable ? ' · 需下载' : ' · 不可用');
    return `${voice.name} · ${suffix}${TtsVoiceCatalog.genderText(voice)}${state}`;
  }

  static genderText(voice: TtsVoiceOption): string {
    const value = (voice.gender || '').toLowerCase();
    if (value === 'male' || value === '男' || value === '男声') return ' · 男声';
    if (value === 'female' || value === '女' || value === '女声') return ' · 女声';
    return '';
  }

  static customVoiceKey(voice: HttpTTS): string {
    return `custom_${voice.id}_${voice.name || ''}`;
  }

  static customVoiceTitle(voice: HttpTTS): string {
    const state = voice.enabled === false ? ' · 已禁用' : '';
    return `${voice.name || '未命名音色'} · 自定义${state}`;
  }

  static cloudVoiceKey(voice: TtsVoiceInfo): string {
    return `cloud_${voice.id}`;
  }

  static cloudVoiceTitle(voice: TtsVoiceInfo): string {
    const tier = voice.tier === 'PREMIUM' ? '精品' : '标准';
    const description = (voice.description || '').trim();
    return description ? `${voice.name} · ${description} · 云端${tier}` : `${voice.name} · 云端${tier}`;
  }
}
