import asset from '@ohos.security.asset';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import fs from '@ohos.file.fs';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { MimoRole, MIMO_VOICES } from '../../core/mimo/MimoPolicy';
import { MimoVoiceLibrary, MimoVoiceScheme, MimoVoicePreset, MimoVoicePolicy, MimoVoiceChange, MimoVoiceChoice } from '../../core/mimo/MimoVoicePolicy';

export class MimoSettings {
  enabled: boolean = false;
  multi: boolean = false;
  analysisAvailable: boolean = false;
  voice: string = '白桦';
  namespace: string = '';
}
export class MimoCorrection {
  key: string = '';
  roleId: string = 'narrator';
}
export class MimoBookCast {
  roles: MimoRole[] = [new MimoRole()];
  corrections: MimoCorrection[] = [];
  emotion: string = '自然';
  revision: number = 0;
  /** Book URL and title, so the cast list can show which books were read with MiMo. */
  book: string = '';
  bookName: string = '';
  updatedAt: number = 0;
  /** Empty means inherit the global scheme; existing character snapshots remain untouched. */
  schemeId: string = '';
  assignmentEnabled?: boolean;
}
export class MimoCastSummary {
  /** Empty for casts saved before the book was recorded; see linkLegacyCasts. */
  book: string = '';
  bookName: string = '';
  updatedAt: number = 0;
  /** Characters besides the narrator. */
  characters: number = 0;
  file: string = '';
}

/** The secret never enters AppStorage, preferences, backup files, or logs. */
export class MimoStore {
  private static readonly ALIAS: string = 'legado.mimo.api-key.v1';
  private static settings: MimoSettings = new MimoSettings();
  private static loaded: boolean = false;
  static credentialRevision: number = 0;
  /** A key is saved on this device, even while MiMo is switched off; lets the reader offer MiMo as a voice. */
  private static configured: boolean = false;
  static onCredentialsChanged: (() => void)[] = [];
  static voiceRevision: number = 0;
  private static choicesCache: MimoVoiceChoice[] | null = null;
  private static choicesAnalysis: boolean = false;
  private static choicesVoice: string = '';
  private static choicesLibrary: MimoVoiceLibrary | null = null;
  private static bookChoices: MimoVoiceChoice[] = [];
  private static bookChoicesId: string = '';
  private static bookChoicesRevision: number = -1;

  static voiceChoices(book: string = ''): MimoVoiceChoice[] {
    const analysis = MimoStore.load().analysisAvailable;
    const voice = MimoStore.load().voice;
    if (!MimoStore.choicesCache || analysis !== MimoStore.choicesAnalysis || voice !== MimoStore.choicesVoice) {
      MimoStore.choicesLibrary = MimoStore.library();
      MimoStore.choicesCache = MimoVoicePolicy.choices(MimoStore.choicesLibrary, analysis);
      MimoStore.choicesAnalysis = analysis; MimoStore.choicesVoice = voice; MimoStore.bookChoicesRevision = -1;
    }
    if (book && !MimoStore.load().multi) {
      if (MimoStore.bookChoicesId !== book || MimoStore.bookChoicesRevision !== MimoStore.voiceRevision) {
        const narrator = MimoStore.cast(book).roles.find((r: MimoRole): boolean => r.id === 'narrator');
        MimoStore.bookChoices = narrator?.manual ? MimoVoicePolicy.choices(MimoStore.choicesLibrary || MimoStore.library(),
          analysis, MimoVoicePolicy.rolePreset(narrator), 'mimo_book_current') : MimoStore.choicesCache;
        MimoStore.bookChoicesId = book; MimoStore.bookChoicesRevision = MimoStore.voiceRevision;
      }
      return MimoStore.bookChoices;
    }
    return MimoStore.choicesCache;
  }
  static selectedVoiceKey(book: string = ''): string {
    if (MimoStore.load().multi) return 'mimo_multi';
    try { return MimoStore.voiceChoices(book).find((c: MimoVoiceChoice): boolean => c.current)?.key || 'mimo_current'; }
    catch (_) { return 'mimo_current'; }
  }
  static selectedVoiceTitle(book: string = ''): string {
    try {
      return MimoStore.voiceChoices(book).find((c: MimoVoiceChoice): boolean => c.key === MimoStore.selectedVoiceKey(book))?.label ||
        'MiMo · ' + MimoStore.load().voice;
    } catch (_) { return 'MiMo · ' + MimoStore.load().voice; }
  }
  static selectVoice(choice: MimoVoiceChoice, book: string = ''): boolean {
    if (!MimoStore.isConfigured() || (choice.multi && !MimoStore.load().analysisAvailable)) return false;
    if (choice.presetId) {
      const library = MimoStore.library();
      const preset = library.presets.find((p: MimoVoicePreset): boolean => p.id === choice.presetId);
      if (!preset) throw new Error('音色预设已移除，请重新选择');
      library.defaultPreset = MimoVoicePolicy.clone(preset);
      MimoStore.saveLibrary(library);
    }
    if (!choice.multi && book) {
      const cast = MimoStore.cast(book);
      const narrator = cast.roles.find((role: MimoRole): boolean => role.id === 'narrator');
      if (narrator) {
        if (choice.key !== 'mimo_book_current') MimoVoicePolicy.bind(narrator, MimoStore.library().defaultPreset);
        narrator.manual = true;
        MimoStore.saveCast(book, cast);
      }
    }
    MimoStore.load().multi = choice.multi;
    MimoStore.setEnabled(true);
    return true;
  }

  static library(): MimoVoiceLibrary {
    const path = MimoStore.root() + '/voices.json';
    if (!fs.accessSync(path)) return MimoVoicePolicy.defaults(MimoStore.load().voice);
    try {
      return MimoVoicePolicy.normalize(JSON.parse(fs.readTextSync(path)) as MimoVoiceLibrary, MimoStore.load().voice);
    } catch (_) { throw new Error('音色库读取失败，原文件已保留，请检查存储后重试'); }
  }
  static saveLibrary(library: MimoVoiceLibrary): void {
    const valid = MimoVoicePolicy.normalize(library, MimoStore.load().voice);
    valid.revision++;
    MimoStore.write(MimoStore.root() + '/voices.json', JSON.stringify(valid));
    MimoStore.choicesCache = null;
    MimoStore.load().voice = valid.defaultPreset.voice;
    MimoStore.saveSettings();
  }
  /** Reload only non-secret voice data after a settings backup is restored. */
  static reloadVoices(): void {
    MimoStore.choicesCache = null; MimoStore.bookChoicesRevision = -1;
    MimoStore.load().voice = MimoStore.library().defaultPreset.voice;
    MimoStore.saveSettings();
  }
  static savePreset(preset: MimoVoicePreset): void {
    if (!MimoVoicePolicy.validPreset(preset) || !preset.id) throw new Error('请填写有效的预设名称与提示词');
    const library = MimoStore.library();
    if (library.presets.some((p: MimoVoicePreset): boolean => p.id !== preset.id && p.name === preset.name.trim())) {
      throw new Error('已有同名预设，请修改名称');
    }
    const index = library.presets.findIndex((p: MimoVoicePreset): boolean => p.id === preset.id);
    const saved = MimoVoicePolicy.clone(preset); saved.name = saved.name.trim();
    if (index >= 0) { saved.revision = library.presets[index].revision + 1; library.presets[index] = saved; }
    else { if (library.presets.length >= 500) throw new Error('音色库最多保存 500 个预设'); library.presets.push(saved); }
    MimoStore.saveLibrary(library);
  }
  static deletePreset(id: string): void {
    const library = MimoStore.library();
    if (library.defaultPreset.id === id || library.schemes.some((s: MimoVoiceScheme): boolean => s.presetIds.includes(id))) {
      throw new Error('预设正在被默认声音或方案使用，请先更换引用');
    }
    for (const summary of MimoStore.castSummaries()) {
      if (!summary.book) throw new Error('存在未关联书籍的人物档案，请先打开人物档案列表后重试');
      if (MimoStore.cast(summary.book).roles.some((r: MimoRole): boolean => r.preset?.id === id)) {
        throw new Error('预设正在被人物使用，请先更换人物声音');
      }
    }
    library.presets = library.presets.filter((p: MimoVoicePreset): boolean => p.id !== id);
    MimoStore.saveLibrary(library);
  }
  static schemeId(cast: MimoBookCast, library: MimoVoiceLibrary): string {
    return cast.schemeId || library.schemeId;
  }
  static assign(role: MimoRole, cast: MimoBookCast, configured?: MimoVoiceLibrary): void {
    const library = configured || MimoStore.library();
    const match = MimoVoicePolicy.match(role, library, MimoStore.schemeId(cast, library),
      cast.assignmentEnabled ?? library.assignmentEnabled);
    MimoVoicePolicy.bind(role, match.preset);
  }
  static changes(book: string): MimoVoiceChange[] {
    const cast = MimoStore.cast(book), library = MimoStore.library();
    return cast.roles.map((role: MimoRole): MimoVoiceChange => {
      const change = new MimoVoiceChange();
      change.roleId = role.id; change.roleName = role.name; change.before = MimoVoicePolicy.rolePreset(role).name;
      change.skip = role.id === 'narrator' || role.locked || role.manual === true;
      const matched = MimoVoicePolicy.match(role, library, MimoStore.schemeId(cast, library),
        cast.assignmentEnabled ?? library.assignmentEnabled);
      change.preset = change.skip ? MimoVoicePolicy.rolePreset(role) : matched.preset;
      change.reason = change.skip ? '已锁定或手动指定，保持原声' : matched.reason;
      return change;
    });
  }
  static applyChanges(book: string, changes: MimoVoiceChange[]): void {
    const cast = MimoStore.cast(book);
    for (const change of changes) {
      const role = cast.roles.find((r: MimoRole): boolean => r.id === change.roleId);
      if (role && role.id !== 'narrator' && !role.locked && !role.manual && !change.skip) MimoVoicePolicy.bind(role, change.preset);
    }
    MimoStore.saveCast(book, cast);
  }

  static load(): MimoSettings {
    if (!MimoStore.loaded) {
      const path = MimoStore.root() + '/settings.json';
      try {
        const value = JSON.parse(fs.readTextSync(path)) as MimoSettings;
        MimoStore.settings.enabled = value.enabled === true;
        MimoStore.settings.multi = value.multi === true;
        MimoStore.settings.analysisAvailable = value.analysisAvailable === true;
        MimoStore.settings.voice = MIMO_VOICES.includes(value.voice) ? value.voice : '白桦';
        MimoStore.settings.namespace = typeof value.namespace === 'string' ? value.namespace : '';
      } catch (_) {}
      MimoStore.loaded = true;
      MimoStore.configured = MimoStore.settings.enabled;
      MimoStore.publish();
      MimoStore.key().then((key: string): void => { MimoStore.setConfigured(key.length > 0); })
        .catch((): void => {});
    }
    return MimoStore.settings;
  }
  static saveSettings(): void {
    MimoStore.write(MimoStore.root() + '/settings.json', JSON.stringify(MimoStore.settings));
    MimoStore.voiceRevision++;
    MimoStore.publish();
  }
  static setEnabled(enabled: boolean): void {
    const wasEnabled = MimoStore.load().enabled;
    MimoStore.load().enabled = enabled;
    if (wasEnabled && !enabled) MimoStore.invalidateCredentials();
    MimoStore.saveSettings();
  }
  /** Records a re-test of the saved key; multi-role reading cannot stay on without working analysis. */
  static setAnalysisAvailable(available: boolean): void {
    const settings = MimoStore.load();
    settings.analysisAvailable = available;
    if (!available) settings.multi = false;
    MimoStore.saveSettings();
  }
  static isConfigured(): boolean { MimoStore.load(); return MimoStore.configured; }
  private static setConfigured(configured: boolean): void {
    if (MimoStore.configured === configured) return;
    MimoStore.configured = configured;
    MimoStore.publish();
  }
  private static publish(): void {
    AppStorage.setOrCreate('mimoConfigured', MimoStore.configured);
    AppStorage.setOrCreate('mimoAnalysisAvailable', MimoStore.settings.analysisAvailable);
    AppStorage.setOrCreate('mimoEnabled', MimoStore.settings.enabled);
    AppStorage.setOrCreate('mimoMulti', MimoStore.settings.multi);
    AppStorage.setOrCreate('mimoVoice', MimoStore.settings.voice);
    AppStorage.setOrCreate('mimoVoicesRevision', MimoStore.voiceRevision);
  }
  private static query(): asset.AssetMap {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto(MimoStore.ALIAS));
    return query;
  }
  static async key(): Promise<string> {
    const query = MimoStore.query();
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const rows = await asset.query(query);
      if (rows.length === 0) return '';
      const data = rows[0].get(asset.Tag.SECRET) as Uint8Array;
      return data ? util.TextDecoder.create('utf-8').decodeWithStream(data) : '';
    } catch (error) {
      if ((error as BusinessError).code === asset.ErrorCode.NOT_FOUND) return '';
      throw new Error('无法访问本机安全密钥，请解锁设备后重试');
    }
  }
  static async saveKey(key: string, analysis: boolean, voice: string): Promise<void> {
    const value = key.trim();
    if (!value || value.length > 4096 || /\s/.test(value)) throw new Error('请输入完整的 MiMo API Key');
    const attributes = MimoStore.query();
    attributes.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(value));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    attributes.set(asset.Tag.WRAP_TYPE, asset.WrapType.NEVER);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    try { await asset.add(attributes); } catch (_) { throw new Error('密钥安全保存失败，未启用 MiMo'); }
    const settings = MimoStore.load();
    settings.enabled = true;
    settings.multi = analysis;
    settings.analysisAvailable = analysis;
    settings.voice = MIMO_VOICES.includes(voice) ? voice : '白桦';
    const library = MimoStore.library();
    if (library.defaultPreset.voice !== settings.voice) {
      library.defaultPreset = MimoVoicePolicy.preset('', '原声 · ' + settings.voice, settings.voice);
      MimoStore.saveLibrary(library);
    }
    settings.namespace = util.generateRandomUUID();
    MimoStore.configured = true;
    MimoStore.invalidateCredentials();
    MimoStore.saveSettings();
  }
  static async deleteKey(): Promise<void> {
    try { await asset.remove(MimoStore.query()); } catch (error) {
      if ((error as BusinessError).code !== asset.ErrorCode.NOT_FOUND) throw new Error('删除安全密钥失败，请重试');
    }
    MimoStore.load().enabled = false;
    MimoStore.settings.multi = false;
    MimoStore.settings.analysisAvailable = false;
    MimoStore.configured = false;
    MimoStore.invalidateCredentials();
    MimoStore.saveSettings();
  }
  private static invalidateCredentials(): void {
    MimoStore.credentialRevision++;
    MimoStore.onCredentialsChanged.slice().forEach((stop: () => void): void => stop());
  }
  static root(): string {
    const base = AppStorage.get<string>('appFilesDir');
    if (!base) throw new Error('应用存储尚未就绪');
    const path = base + '/mimo_private';
    if (!fs.accessSync(path)) fs.mkdirSync(path, true);
    return path;
  }
  static hash(value: string): string {
    const md = cryptoFramework.createMd('SHA256');
    md.updateSync({ data: new util.TextEncoder().encodeInto(value) });
    return Array.from(md.digestSync().data).map((b: number): string => b.toString(16).padStart(2, '0')).join('');
  }
  static cast(book: string): MimoBookCast {
    try {
      const cast = JSON.parse(fs.readTextSync(MimoStore.root() + '/cast_' + MimoStore.hash(book) + '.json')) as MimoBookCast;
      if (Array.isArray(cast.roles) && cast.roles.length > 0 && Array.isArray(cast.corrections)) {
        cast.schemeId = typeof cast.schemeId === 'string' ? cast.schemeId : '';
        cast.assignmentEnabled = typeof cast.assignmentEnabled === 'boolean' ? cast.assignmentEnabled : undefined;
        return cast;
      }
    } catch (_) {}
    const cast = new MimoBookCast();
    MimoVoicePolicy.bind(cast.roles[0], MimoStore.library().defaultPreset);
    return cast;
  }
  static saveCast(book: string, cast: MimoBookCast, bookName: string = ''): void {
    cast.revision++;
    cast.book = book;
    if (bookName) cast.bookName = bookName;
    cast.updatedAt = Date.now();
    MimoStore.write(MimoStore.root() + '/cast_' + MimoStore.hash(book) + '.json', JSON.stringify(cast));
    MimoStore.voiceRevision++;
    MimoStore.publish();
  }
  static deleteCast(book: string): void {
    try { fs.unlinkSync(MimoStore.root() + '/cast_' + MimoStore.hash(book) + '.json'); } catch (_) {}
    MimoStore.voiceRevision++; MimoStore.publish();
  }
  /** Every saved cast, newest first. */
  static castSummaries(): MimoCastSummary[] {
    const root = MimoStore.root();
    const summaries: MimoCastSummary[] = [];
    for (const name of fs.listFileSync(root)) {
      if (!/^cast_[a-f0-9]{64}\.json$/.test(name)) continue;
      try {
        const cast = JSON.parse(fs.readTextSync(root + '/' + name)) as MimoBookCast;
        if (!Array.isArray(cast.roles)) continue;
        const summary = new MimoCastSummary();
        summary.book = typeof cast.book === 'string' ? cast.book : '';
        summary.bookName = typeof cast.bookName === 'string' ? cast.bookName : '';
        summary.updatedAt = typeof cast.updatedAt === 'number' ? cast.updatedAt : fs.statSync(root + '/' + name).mtime * 1000;
        summary.characters = cast.roles.filter((role: MimoRole): boolean => role.id !== 'narrator').length;
        summary.file = name;
        summaries.push(summary);
      } catch (_) {}
    }
    return summaries.sort((a: MimoCastSummary, b: MimoCastSummary): number => b.updatedAt - a.updatedAt);
  }
  /**
   * Casts saved before the book was recorded are only named by a hash of the book URL; match them
   * against known books and record the URL so they can be listed and opened.
   */
  static linkLegacyCasts(summaries: MimoCastSummary[], urls: string[], names: string[]): void {
    const pending = summaries.filter((summary: MimoCastSummary): boolean => !summary.book);
    if (pending.length === 0) return;
    for (let index = 0; index < urls.length; index++) {
      const file = 'cast_' + MimoStore.hash(urls[index]) + '.json';
      const summary = pending.find((item: MimoCastSummary): boolean => item.file === file);
      if (!summary) continue;
      try {
        const path = MimoStore.root() + '/' + file;
        const cast = JSON.parse(fs.readTextSync(path)) as MimoBookCast;
        cast.book = urls[index];
        cast.bookName = names[index] || '';
        if (typeof cast.updatedAt !== 'number') cast.updatedAt = summary.updatedAt;
        MimoStore.write(path, JSON.stringify(cast));
        summary.book = cast.book;
        summary.bookName = cast.bookName;
      } catch (_) {}
    }
  }
  static write(path: string, text: string): void {
    const temporary = path + '.tmp';
    const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, text); } finally { fs.closeSync(file); }
    fs.renameSync(temporary, path);
  }
}
