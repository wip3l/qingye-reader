import fs from '@ohos.file.fs';
import { HttpTTS } from '@legado/sourceengine';
import { MimoRole } from '../../core/mimo/MimoPolicy';
import {
  CastLibrary, CastScheme, CastVoiceMatch, CastVoicePolicy, CastVoiceRef, CastVoiceTag
} from '../../core/mimo/CastVoicePolicy';
import { LocalTtsModel, LocalTtsModels } from '../localtts/LocalTtsModels';
import { TtsCustomVoices } from '../TtsVoiceModels';
import { MimoBookCast, MimoStore } from './MimoStore';

/** One offline or custom voice as the multi-voice pages list it. */
export class CastVoiceItem {
  ref: CastVoiceRef = new CastVoiceRef();
  key: string = '';
  title: string = '';
  /** 离线 / 自定义 */
  source: string = '';
  tag: CastVoiceTag = new CastVoiceTag();
  /** The tag comes from the built-in catalogue rather than the user. */
  builtInTag: boolean = false;
  /** Cannot take part in multi-voice reading; `reason` says why. */
  unsupported: boolean = false;
  reason: string = '';
}

/**
 * 多角色朗读（离线音色与自定义音色）的开关、音色方案和音色标签。
 * 人物识别、人物档案、纠错沿用 MiMo 多角色的那一套（MimoStore / MimoReadingSession），这里只管“谁用哪个声音”。
 */
export class CastVoiceStore {
  private static cache: CastLibrary | null = null;
  private static itemsCache: CastVoiceItem[] | null = null;
  private static itemsStamp: string = '';
  private static itemsCustomRaw: string = '';

  private static path(): string { return MimoStore.root() + '/cast_voices.json'; }

  static library(): CastLibrary {
    if (!CastVoiceStore.cache) {
      let value: CastLibrary | undefined = undefined;
      try {
        if (fs.accessSync(CastVoiceStore.path())) value = JSON.parse(fs.readTextSync(CastVoiceStore.path())) as CastLibrary;
      } catch (_) {}
      CastVoiceStore.cache = CastVoicePolicy.normalize(value);
      CastVoiceStore.publish();
    }
    return CastVoiceStore.cache;
  }
  static save(library: CastLibrary): void {
    const valid = CastVoicePolicy.normalize(library);
    valid.revision = library.revision + 1;
    MimoStore.write(CastVoiceStore.path(), JSON.stringify(valid));
    CastVoiceStore.cache = valid;
    CastVoiceStore.itemsCache = null;
    CastVoiceStore.publish();
  }
  private static publish(): void {
    const library = CastVoiceStore.cache;
    if (!library) return;
    AppStorage.setOrCreate('castVoiceEnabled', library.enabled);
    AppStorage.setOrCreate('castVoiceRevision', library.revision);
  }

  /** Never throws: the reader asks this on every start, also before app storage is ready. */
  static enabled(): boolean {
    try { return CastVoiceStore.library().enabled; } catch (_) { return false; }
  }
  static setEnabled(enabled: boolean): void {
    const library = CastVoiceStore.library();
    if (library.enabled === enabled) return;
    library.enabled = enabled;
    CastVoiceStore.save(library);
    // 两种多角色不同时开：这一种用离线/自定义音色发声，MiMo 朗读用 MiMo 的音色。
    if (enabled && MimoStore.load().enabled) MimoStore.setEnabled(false);
  }
  /** 朗读面板和设置页里显示的当前音色名。 */
  static title(): string {
    try { return '多角色 · ' + CastVoiceStore.scheme().name; } catch (_) { return '多角色'; }
  }

  static scheme(cast?: MimoBookCast): CastScheme {
    const library = CastVoiceStore.library();
    const wanted = cast?.castSchemeId || library.schemeId;
    return library.schemes.find((item: CastScheme): boolean => item.id === wanted) ||
      library.schemes.find((item: CastScheme): boolean => item.id === library.schemeId) || library.schemes[0];
  }
  static saveScheme(scheme: CastScheme): void {
    const library = CastVoiceStore.library();
    const name = scheme.name.trim();
    if (!name || name.length > 30) throw new Error('请填写 30 字以内的方案名称');
    if (library.schemes.some((item: CastScheme): boolean => item.id !== scheme.id && item.name === name)) {
      throw new Error('已有同名方案，请修改名称');
    }
    const saved = CastVoicePolicy.cloneScheme(scheme); saved.name = name;
    const index = library.schemes.findIndex((item: CastScheme): boolean => item.id === scheme.id);
    if (index >= 0) library.schemes[index] = saved;
    else {
      if (library.schemes.length >= 50) throw new Error('最多保存 50 个方案');
      library.schemes.push(saved);
    }
    CastVoiceStore.save(library);
  }
  static deleteScheme(id: string): void {
    const library = CastVoiceStore.library();
    if (library.schemes.length <= 1) throw new Error('至少保留一个方案');
    if (library.schemeId === id) throw new Error('这个方案正在使用，请先切换到其他方案');
    library.schemes = library.schemes.filter((item: CastScheme): boolean => item.id !== id);
    CastVoiceStore.save(library);
  }
  static useScheme(id: string): void {
    const library = CastVoiceStore.library();
    if (!library.schemes.some((item: CastScheme): boolean => item.id === id)) return;
    library.schemeId = id;
    CastVoiceStore.save(library);
  }

  /** Built-in offline voices say “男声 · …” / “女声 · …” in their description; that is their default tag. */
  private static builtInTag(model: LocalTtsModel, key: string): CastVoiceTag | undefined {
    const text = model.description || '';
    const gender = text.includes('男声') ? 'male' : (text.includes('女声') ? 'female' : '');
    if (!gender) return undefined;
    const tag = new CastVoiceTag(); tag.key = key; tag.gender = gender; tag.age = 'young';
    tag.narrator = true;
    return tag;
  }

  /** Installed, enabled offline voices followed by enabled custom voices. */
  static voices(): CastVoiceItem[] {
    const library = CastVoiceStore.library();
    const customRaw = AppStorage.get<string>('ttsCustomVoices') || '';
    const stamp = library.revision + '|' + (AppStorage.get<string>(LocalTtsModels.STORAGE_INSTALLED) || '') + '|' +
      (AppStorage.get<string>('ttsDisabledVoiceKeys') || '');
    if (CastVoiceStore.itemsCache && CastVoiceStore.itemsStamp === stamp && CastVoiceStore.itemsCustomRaw === customRaw) {
      return CastVoiceStore.itemsCache;
    }
    const items: CastVoiceItem[] = [];
    const add = (ref: CastVoiceRef, source: string, builtIn?: CastVoiceTag): CastVoiceItem => {
      const item = new CastVoiceItem();
      item.ref = ref; item.key = CastVoicePolicy.key(ref); item.title = ref.name; item.source = source;
      const saved = library.tags.find((tag: CastVoiceTag): boolean => tag.key === item.key);
      if (saved) item.tag = saved;
      else if (builtIn) { item.tag = builtIn; item.builtInTag = true; }
      else item.tag.key = item.key;
      items.push(item);
      return item;
    };
    for (const model of LocalTtsModels.selectableModels()) {
      const ref = CastVoicePolicy.ref('local', model.id, model.name);
      add(ref, '离线', CastVoiceStore.builtInTag(model, CastVoicePolicy.key(ref)));
    }
    let custom: HttpTTS[] = [];
    try { custom = TtsCustomVoices.parse(customRaw); } catch (_) {}
    for (const voice of custom) {
      if (voice.enabled === false) continue;
      const item = add(CastVoicePolicy.ref('http', String(voice.id), voice.name || '未命名音色'), '自定义');
      if (library.unsupported.includes(item.key)) {
        item.unsupported = true; item.reason = '返回 MP3，暂不支持';
      }
    }
    CastVoiceStore.itemsCache = items;
    CastVoiceStore.itemsStamp = stamp;
    CastVoiceStore.itemsCustomRaw = customRaw;
    return items;
  }
  static item(ref: CastVoiceRef | undefined): CastVoiceItem | undefined {
    const key = CastVoicePolicy.key(ref);
    return key ? CastVoiceStore.voices().find((item: CastVoiceItem): boolean => item.key === key) : undefined;
  }
  static usable(ref: CastVoiceRef | undefined): boolean {
    const item = CastVoiceStore.item(ref);
    return !!item && !item.unsupported;
  }
  static tagAge(key: string): string {
    return CastVoiceStore.voices().find((item: CastVoiceItem): boolean => item.key === key)?.tag.age || 'unknown';
  }
  static localModel(ref: CastVoiceRef): LocalTtsModel | undefined {
    return ref.kind === 'local' ? LocalTtsModels.selectableModels().find((model: LocalTtsModel): boolean => model.id === ref.id) : undefined;
  }
  static customVoice(ref: CastVoiceRef): HttpTTS | undefined {
    if (ref.kind !== 'http') return undefined;
    try {
      return TtsCustomVoices.parse(AppStorage.get<string>('ttsCustomVoices') || '')
        .find((voice: HttpTTS): boolean => String(voice.id) === ref.id && voice.enabled !== false);
    } catch (_) { return undefined; }
  }

  static setTag(key: string, gender: string, age: string, narrator: boolean): void {
    const library = CastVoiceStore.library();
    library.tags = library.tags.filter((tag: CastVoiceTag): boolean => tag.key !== key);
    const tag = new CastVoiceTag(); tag.key = key; tag.gender = gender; tag.age = age; tag.narrator = narrator;
    // 清空的标签也要存一条：内置音色自带标签，不存就又回到自带的那份。
    library.tags.push(tag);
    CastVoiceStore.save(library);
  }
  static clearTag(key: string): void {
    const library = CastVoiceStore.library();
    library.tags = library.tags.filter((tag: CastVoiceTag): boolean => tag.key !== key);
    CastVoiceStore.save(library);
  }
  static untaggedCount(): number {
    return CastVoiceStore.voices().filter((item: CastVoiceItem): boolean => !CastVoicePolicy.tagged(item.tag)).length;
  }
  static markUnsupported(key: string): void {
    const library = CastVoiceStore.library();
    if (!key || library.unsupported.includes(key)) return;
    library.unsupported.push(key);
    CastVoiceStore.save(library);
  }
  static clearUnsupported(key: string): void {
    const library = CastVoiceStore.library();
    if (!library.unsupported.includes(key)) return;
    library.unsupported = library.unsupported.filter((item: string): boolean => item !== key);
    CastVoiceStore.save(library);
  }

  /** Fills an untouched default scheme from tagged voices, so switching the feature on works at once. */
  static prepareDefaultScheme(): void {
    const library = CastVoiceStore.library();
    const scheme = CastVoiceStore.scheme();
    if (CastVoicePolicy.schemeVoices(scheme).length > 0) return;
    // 多人音色包排在前面：包里的音色共用一个模型，换人说话不用重新加载；单个的离线模型之间来回切换很慢。
    const packed = (item: CastVoiceItem): number => CastVoiceStore.localModel(item.ref)?.pack ? 0 : 1;
    const items = CastVoiceStore.voices().filter((item: CastVoiceItem): boolean => !item.unsupported)
      .sort((a: CastVoiceItem, b: CastVoiceItem): number => packed(a) - packed(b));
    const changed = CastVoicePolicy.autoFill(scheme, items.map((item: CastVoiceItem): CastVoiceRef => item.ref),
      (key: string): CastVoiceTag | undefined => items.find((item: CastVoiceItem): boolean => item.key === key)?.tag);
    if (changed) CastVoiceStore.save(library);
  }

  /** The voice a character speaks with under the book's scheme; see CastVoicePolicy.voiceFor. */
  static voiceFor(role: MimoRole, cast: MimoBookCast): CastVoiceMatch {
    return CastVoicePolicy.voiceFor(role, cast.roles, CastVoiceStore.scheme(cast),
      (ref: CastVoiceRef): boolean => CastVoiceStore.usable(ref), (key: string): string => CastVoiceStore.tagAge(key));
  }
  /** Why reading cannot start, or '' when the scheme has a usable narrator voice. */
  static blocker(cast?: MimoBookCast): string {
    const scheme = CastVoiceStore.scheme(cast);
    if (!CastVoicePolicy.key(scheme.narrator)) return `音色方案“${scheme.name}”还没有选旁白音色`;
    if (!CastVoiceStore.usable(scheme.narrator)) return `音色方案“${scheme.name}”的旁白音色“${scheme.narrator.name}”已不可用，请重新选择`;
    return '';
  }
}
