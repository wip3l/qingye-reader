import { MIMO_VOICES, MimoRole, MimoVoicePreset } from './MimoPolicy';
export { MimoVoicePreset } from './MimoPolicy';

export const MIMO_AGES: string[] = ['unknown', 'child', 'teen', 'adult', 'elder'];
export const MIMO_AGE_LABELS: string[] = ['未知', '儿童', '少年', '成年', '老年'];
export const MIMO_GENDERS: string[] = ['unknown', 'male', 'female'];
export const MIMO_GENDER_LABELS: string[] = ['不限', '男', '女'];

/** Only these selected presets participate in automatic assignment. */
export class MimoVoiceScheme {
  id: string = '';
  name: string = '';
  presetIds: string[] = [];
}
export class MimoVoiceLibrary {
  presets: MimoVoicePreset[] = [];
  schemes: MimoVoiceScheme[] = [];
  schemeId: string = 'general';
  assignmentEnabled: boolean = true;
  defaultPreset: MimoVoicePreset = new MimoVoicePreset();
  revision: number = 0;
}
export class MimoVoiceMatch {
  preset: MimoVoicePreset = new MimoVoicePreset();
  reason: string = '';
}
export class MimoVoiceChange {
  roleId: string = '';
  roleName: string = '';
  before: string = '';
  preset: MimoVoicePreset = new MimoVoicePreset();
  skip: boolean = false;
  reason: string = '';
}
export class MimoVoiceChoice {
  key: string = '';
  label: string = '';
  presetId: string = '';
  multi: boolean = false;
  current: boolean = false;
}

export class MimoVoicePolicy {
  /** Manual selectors show the whole library. Schemes only constrain automatic role assignment. */
  static choices(library: MimoVoiceLibrary, analysisAvailable: boolean,
    currentPreset?: MimoVoicePreset, currentKey: string = 'mimo_current'): MimoVoiceChoice[] {
    const choices: MimoVoiceChoice[] = [];
    if (analysisAvailable) {
      const multi = new MimoVoiceChoice(); multi.key = 'mimo_multi'; multi.label = 'MiMo · 自动多角色';
      multi.multi = true; choices.push(multi);
    }
    const selected = currentPreset || library.defaultPreset;
    const matches = (p: MimoVoicePreset): boolean => p.id === selected.id && p.revision === selected.revision &&
      p.voice === selected.voice && p.prompt === selected.prompt;
    if (!library.presets.some(matches)) {
      const current = new MimoVoiceChoice(); current.key = currentKey;
      current.label = 'MiMo · ' + (currentKey === 'mimo_book_current' ? '本书 · ' : '') + selected.name +
        (selected.id ? '（已保存版本）' : '');
      current.current = true; choices.push(current);
    }
    for (const preset of library.presets) {
      const choice = new MimoVoiceChoice(); choice.key = 'mimo_preset:' + preset.id;
      choice.label = 'MiMo · ' + preset.name; choice.presetId = preset.id; choice.current = matches(preset);
      choices.push(choice);
    }
    return choices;
  }
  static preset(id: string, name: string, voice: string, prompt: string = '',
    age: string = 'unknown', gender: string = 'unknown'): MimoVoicePreset {
    const p = new MimoVoicePreset();
    p.id = id; p.name = name; p.voice = voice; p.prompt = prompt; p.age = age; p.gender = gender;
    return p;
  }
  static clone(p: MimoVoicePreset): MimoVoicePreset {
    return MimoVoicePolicy.presetVersion(p.id, p.name, p.voice, p.prompt, p.age, p.gender, p.revision);
  }
  private static presetVersion(id: string, name: string, voice: string, prompt: string, age: string,
    gender: string, revision: number): MimoVoicePreset {
    const p = MimoVoicePolicy.preset(id, name, voice, prompt, age, gender); p.revision = revision; return p;
  }
  static defaults(voice: string): MimoVoiceLibrary {
    const library = new MimoVoiceLibrary();
    library.presets = [
      MimoVoicePolicy.preset('narrator', '自然旁白', '白桦'),
      MimoVoicePolicy.preset('male', '沉稳男声', '苏打', '成年男性的沉着表达，咬字清晰，句尾自然收束。', 'adult', 'male'),
      MimoVoicePolicy.preset('female', '温柔女声', '茉莉', '成年女性的温和表达，亲近自然，避免过度气声。', 'adult', 'female'),
      MimoVoicePolicy.preset('bright', '明亮女声', '冰糖', '明亮轻快，避免故作幼态和持续高声。', 'adult', 'female'),
      MimoVoicePolicy.preset('child', '儿童·清亮', '冰糖', '以儿童角色的语气演绎：清亮、天真、短句自然，避免成熟低沉的腔调，不尖叫，不模仿婴儿咿呀。', 'child'),
      MimoVoicePolicy.preset('teen', '少年·清爽', '苏打', '少年角色的清爽表达，轻盈自然，避免成熟厚重腔调。', 'teen'),
      MimoVoicePolicy.preset('elder', '长者·温和', '白桦', '长者角色的温和表达，沉着从容，吐字清晰，避免夸张颤音。', 'elder')
    ];
    const general = new MimoVoiceScheme(); general.id = 'general'; general.name = '通用配音';
    general.presetIds = ['narrator', 'male', 'female', 'child', 'teen', 'elder'];
    const classic = new MimoVoiceScheme(); classic.id = 'classic'; classic.name = '原声经典';
    classic.presetIds = ['narrator', 'male', 'female', 'bright'];
    library.schemes = [general, classic];
    library.defaultPreset = MimoVoicePolicy.preset('', '原声 · ' + voice, voice);
    return library;
  }
  static validPreset(p: MimoVoicePreset): boolean {
    return !!p && typeof p.id === 'string' && p.id.length <= 80 && typeof p.name === 'string' &&
      p.name.trim().length > 0 && p.name.length <= 30 && MIMO_VOICES.includes(p.voice) &&
      typeof p.prompt === 'string' && p.prompt.length <= 1200 && MIMO_AGES.includes(p.age) &&
      MIMO_GENDERS.includes(p.gender) && Number.isInteger(p.revision) && p.revision > 0;
  }
  static normalize(value: MimoVoiceLibrary, voice: string): MimoVoiceLibrary {
    if (!value || !Array.isArray(value.presets) || !Array.isArray(value.schemes) ||
      value.presets.length > 500 || value.schemes.length > 100) {
      throw new Error('音色库格式无效');
    }
    const result = new MimoVoiceLibrary();
    const ids: Set<string> = new Set<string>();
    for (const p of value.presets.slice(0, 500)) {
      if (!MimoVoicePolicy.validPreset(p) || !p.id || ids.has(p.id)) throw new Error('音色预设格式无效');
      ids.add(p.id); result.presets.push(MimoVoicePolicy.clone(p));
    }
    const schemeIds: Set<string> = new Set<string>();
    for (const s of value.schemes.slice(0, 100)) {
      if (!s || typeof s.id !== 'string' || !s.id || s.id.length > 80 || schemeIds.has(s.id) ||
        typeof s.name !== 'string' || !s.name.trim() || s.name.length > 30 || !Array.isArray(s.presetIds)) {
        throw new Error('音色方案格式无效');
      }
      const scheme = new MimoVoiceScheme(); scheme.id = s.id; scheme.name = s.name;
      scheme.presetIds = Array.from(new Set<string>(s.presetIds.filter((id: string): boolean => ids.has(id))));
      result.schemes.push(scheme); schemeIds.add(s.id);
    }
    result.schemeId = schemeIds.has(value.schemeId) ? value.schemeId : (result.schemes[0]?.id || '');
    result.assignmentEnabled = value.assignmentEnabled !== false;
    result.defaultPreset = MimoVoicePolicy.validPreset(value.defaultPreset) ? MimoVoicePolicy.clone(value.defaultPreset) :
      MimoVoicePolicy.preset('', '原声 · ' + voice, voice);
    result.revision = Number.isInteger(value.revision) ? Math.max(0, value.revision) : 0;
    return result;
  }
  static rolePreset(role: MimoRole): MimoVoicePreset {
    if (role.preset && MimoVoicePolicy.validPreset(role.preset)) return MimoVoicePolicy.clone(role.preset);
    return MimoVoicePolicy.preset('', '原声 · ' + role.voice, MIMO_VOICES.includes(role.voice) ? role.voice : '白桦');
  }
  static bind(role: MimoRole, preset: MimoVoicePreset): void {
    role.voice = preset.voice; role.preset = MimoVoicePolicy.clone(preset);
  }
  static match(role: MimoRole, library: MimoVoiceLibrary, schemeId: string, enabled: boolean): MimoVoiceMatch {
    const result = new MimoVoiceMatch(); result.preset = MimoVoicePolicy.clone(library.defaultPreset);
    if (!enabled || role.id === 'narrator') { result.reason = '使用默认旁白'; return result; }
    if (!role.age || role.age === 'unknown') { result.reason = '年龄证据不足，使用旁白'; return result; }
    const scheme = library.schemes.find((s: MimoVoiceScheme): boolean => s.id === schemeId);
    const candidates = library.presets.filter((p: MimoVoicePreset): boolean =>
      !!scheme?.presetIds.includes(p.id) && p.age === role.age &&
      (p.gender === 'unknown' || !role.gender || role.gender === 'unknown' || p.gender === role.gender));
    if (!candidates.length) { result.reason = '方案内没有匹配年龄的声音，使用旁白'; return result; }
    // A stable role id chooses from a small allowed pool. Never spread roles across the whole library.
    let hash = 0;
    for (let i = 0; i < role.id.length; i++) hash = (Math.imul(hash, 31) + role.id.charCodeAt(i)) | 0;
    result.preset = MimoVoicePolicy.clone(candidates[(hash >>> 0) % candidates.length]);
    result.reason = '按年龄与性别匹配，后续固定复用'; return result;
  }
  static prompt(p: MimoVoicePreset, emotion: string, mode: string, speed: number): string {
    const tone = mode === '克制' || mode === '平稳' ? '平静' : emotion;
    return '单一说话人，保持基础音色稳定。' + (p.prompt ? p.prompt.trim() + '\n' : '') +
      `本段情绪：${tone}，${mode === '生动' ? '情绪鲜明' : '自然克制'}。` +
      `最终朗读语速为通常的 ${Math.max(0.5, Math.min(2, speed)).toFixed(1)} 倍，优先于风格中的语速描述。`;
  }
  static ageLabel(age: string): string { return MIMO_AGE_LABELS[MIMO_AGES.indexOf(age)] || '未知'; }
  static genderLabel(gender: string): string { return MIMO_GENDER_LABELS[MIMO_GENDERS.indexOf(gender)] || '不限'; }
}
