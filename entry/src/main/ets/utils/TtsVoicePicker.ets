import { HttpTTS } from '@legado/sourceengine';
import { AccountCommerceApi } from '../account/AccountCommerceApi';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { TtsCatalogResponse, TtsVoiceInfo } from '../account/AccountCommerceModels';
import { MimoVoiceChoice } from '../core/mimo/MimoVoicePolicy';
import { HdsFeedback } from './HdsFeedback';
import { LocalTtsModel, LocalTtsModels } from './localtts/LocalTtsModels';
import { LocalTtsSelection } from './localtts/LocalTtsSelection';
import { MimoStore } from './mimo/MimoStore';
import { SystemTtsReader, TtsReadOptions } from './SystemTtsReader';
import { TtsSettings, TtsSettingsStore } from './TtsSettingsStore';
import { TtsVoiceCatalog } from './TtsVoiceCatalog';
import { TtsCustomVoices, TtsVoiceOption } from './TtsVoiceModels';

/**
 * 朗读音色的选择与读写，给不在普通阅读页里的朗读（文件排版页）用。
 * 列表顺序、取舍规则与普通阅读页的快捷音色列表相同：MiMo（开着时）、离线、云端、自定义、系统，
 * 设置存同一份 TtsSettingsStore，两边换了音色彼此都能看到。
 */
export class TtsVoicePicker {
  person: number = 0;
  online: number = 1;
  style: string = '';
  language: string = 'zh-CN';
  speed: number = 1;
  private installedVoiceKeys: string = '';
  private customVoiceId: string = '';
  private customVoices: string = '';
  private cloudVoiceId: string = '';
  private disabledVoiceKeys: string = '';
  private customOptions: HttpTTS[] = [];
  private systemVoices: TtsVoiceOption[] = [];
  private cloudVoices: TtsVoiceInfo[] = [];
  private voicesLoading: boolean = false;
  private speedSaveTimer: number = -1;
  private readonly context: Context;
  private readonly bookUrl: () => string;
  /** 音色列表或选中项变了：发布到悬浮朗读面板。 */
  onListChanged: () => void = (): void => {};
  /** 选了“MiMo 朗读设置…”，或 MiMo 还没配置好。 */
  onOpenMimoSettings: () => void = (): void => {};

  constructor(context: Context, bookUrl: () => string) {
    this.context = context;
    this.bookUrl = bookUrl;
  }

  /** 读朗读设置；loadVoices 时再异步取系统与云端音色列表，取到后通知 onListChanged。 */
  async load(loadVoices: boolean = true): Promise<void> {
    try {
      this.apply(await TtsSettingsStore.load(this.context));
    } catch (error) {
      console.warn('[TtsVoicePicker] load settings failed:', error);
    }
    if (this.online === 0 && this.person === 0 && !this.style &&
      TtsVoiceCatalog.sameLanguage(this.language || 'zh-CN', 'zh-CN')) {
      this.online = 1;
      this.save();
    }
    if (loadVoices) this.loadVoices();
  }

  private apply(settings: TtsSettings): void {
    this.person = settings.person;
    this.online = settings.online;
    this.style = settings.style;
    this.language = settings.language;
    this.speed = settings.speed;
    this.installedVoiceKeys = settings.installedVoiceKeys;
    this.customVoiceId = settings.customVoiceId;
    this.customVoices = settings.customVoices;
    this.cloudVoiceId = settings.cloudVoiceId;
    this.disabledVoiceKeys = settings.disabledVoiceKeys;
    this.customOptions = TtsCustomVoices.parse(settings.customVoices);
  }

  private current(): TtsSettings {
    const settings = new TtsSettings();
    settings.person = this.person;
    settings.online = this.online;
    settings.style = this.style;
    settings.language = this.language;
    settings.speed = this.speed;
    settings.installedVoiceKeys = this.installedVoiceKeys;
    settings.customVoiceId = this.customVoiceId;
    settings.customVoices = this.customVoices;
    settings.cloudVoiceId = this.cloudVoiceId;
    settings.disabledVoiceKeys = this.disabledVoiceKeys;
    return settings;
  }

  private save(): void {
    const settings = this.current();
    TtsSettingsStore.applyToStorage(settings);
    TtsSettingsStore.save(this.context, settings).catch((error: Error): void => {
      console.warn('[TtsVoicePicker] save settings failed:', error);
    });
  }

  private async loadVoices(): Promise<void> {
    if (this.voicesLoading) return;
    this.voicesLoading = true;
    try {
      const voices: TtsVoiceOption[] = await SystemTtsReader.listAvailableVoices();
      let catalog: TtsCatalogResponse | null = null;
      try {
        catalog = await AccountCommerceApi.fetchTtsCatalog();
      } catch (_) {
        catalog = null;
      }
      this.cloudVoices = catalog ? catalog.voices.filter((voice: TtsVoiceInfo): boolean =>
        TtsVoiceCatalog.cloudEnabled(voice, this.disabledVoiceKeys)) : [];
      if (catalog && this.cloudVoiceId && !this.currentCloudVoice()) {
        const fallback = this.cloudVoices.find((voice: TtsVoiceInfo): boolean => voice.id === 'xiaoyan') ||
          this.cloudVoices[0];
        this.cloudVoiceId = fallback ? fallback.id : '';
        this.save();
      }
      if (!catalog && this.cloudVoiceId) {
        const fallbackCloud = new TtsVoiceInfo();
        fallbackCloud.id = this.cloudVoiceId;
        fallbackCloud.name = '云端音色';
        this.cloudVoices = [fallbackCloud];
      }
      this.systemVoices = TtsVoiceCatalog.applyInstalledOverrides(TtsVoiceCatalog.mergeWithDefault(voices),
        this.installedVoiceKeys).filter((voice: TtsVoiceOption): boolean =>
          TtsVoiceCatalog.systemEnabled(voice, this.disabledVoiceKeys));
      if (!this.currentCloudVoice() && !this.currentCustomVoice() && !this.currentLocalVoice()) {
        const system = this.currentSystemVoice();
        if (!system || !system.available) {
          const first = this.systemVoices.find((voice: TtsVoiceOption): boolean => voice.available) ||
            this.systemVoices[0] || TtsVoiceCatalog.defaultVoice();
          this.useSystemVoice(first);
        }
      }
    } catch (error) {
      console.warn('[TtsVoicePicker] load voices failed:', error);
      this.systemVoices = [TtsVoiceCatalog.defaultVoice()];
      this.person = 0;
      this.online = 1;
      this.style = '';
      this.language = 'zh-CN';
      this.customVoiceId = '';
      this.cloudVoiceId = '';
      this.save();
    } finally {
      this.voicesLoading = false;
      this.onListChanged();
    }
  }

  /** 交给朗读引擎的音色与语速；mimo 时由 MiMo 负责发音。 */
  fillOptions(options: TtsReadOptions): void {
    const cloud = this.currentCloudVoice();
    options.mimo = MimoStore.load().enabled;
    // 音色列表还没取回来时先按保存的云端音色读，不要悄悄换成系统音色。
    options.cloudVoiceId = cloud?.id || (this.cloudVoices.length === 0 ? (this.cloudVoiceId || '').trim() : '');
    options.cloudVoiceName = cloud?.name || '';
    options.cloudVoiceTier = cloud?.tier || 'STANDARD';
    options.person = this.person;
    options.online = this.online;
    options.style = this.style;
    options.language = this.language;
    options.speed = this.speed;
  }

  /** 改语速（0.5–2）；连续拖动时合并成一次保存。返回是否真的变了。 */
  setSpeed(value: number): boolean {
    const next = Math.max(0.5, Math.min(2, Math.round((value || 1) * 10) / 10));
    if (Math.abs(next - this.speed) < 0.01) return false;
    this.speed = next;
    AppStorage.setOrCreate('globalTtsSpeed', next);
    if (this.speedSaveTimer >= 0) clearTimeout(this.speedSaveTimer);
    this.speedSaveTimer = setTimeout((): void => {
      this.speedSaveTimer = -1;
      this.save();
    }, 300);
    return true;
  }

  flush(): void {
    if (this.speedSaveTimer < 0) return;
    clearTimeout(this.speedSaveTimer);
    this.speedSaveTimer = -1;
    this.save();
  }

  // ---- 快捷音色列表 ----

  private mimoLabels(): string[] {
    if (!MimoStore.load().enabled) return [];
    try {
      return MimoStore.voiceChoices(this.bookUrl()).map((choice: MimoVoiceChoice): string => choice.label);
    } catch (_) {
      return [];
    }
  }

  private localVoices(): LocalTtsModel[] {
    return LocalTtsModels.selectableModels();
  }

  private customList(): HttpTTS[] {
    return this.customOptions.filter((voice: HttpTTS): boolean => voice.enabled !== false);
  }

  private systemList(): TtsVoiceOption[] {
    return this.systemVoices.filter((voice: TtsVoiceOption): boolean => voice.available);
  }

  private regularCount(): number {
    return this.localVoices().length + this.cloudVoices.length + this.customList().length + this.systemList().length;
  }

  labels(): string[] {
    const labels: string[] = this.mimoLabels();
    for (const voice of this.localVoices()) labels.push(LocalTtsModels.voiceTitle(voice));
    for (const voice of this.cloudVoices) labels.push(TtsVoiceCatalog.cloudVoiceTitle(voice));
    for (const voice of this.customList()) labels.push(TtsVoiceCatalog.customVoiceTitle(voice));
    for (const voice of this.systemList()) labels.push(TtsVoiceCatalog.voiceTitle(voice));
    if (labels.length === 0) labels.push('暂无可用音色');
    if (MimoStore.load().enabled) labels.push('MiMo 朗读设置…');
    return labels;
  }

  selectedIndex(): number {
    const mimo = this.mimoLabels();
    if (mimo.length > 0) {
      const key = MimoStore.selectedVoiceKey(this.bookUrl());
      return Math.max(0, MimoStore.voiceChoices(this.bookUrl()).findIndex((choice: MimoVoiceChoice): boolean =>
        choice.key === key));
    }
    const local = this.currentLocalVoice();
    const locals = this.localVoices();
    if (local) {
      const index = locals.findIndex((voice: LocalTtsModel): boolean => voice.id === local.id);
      if (index >= 0) return index;
    }
    let offset = locals.length;
    const cloudIndex = this.cloudVoices.findIndex((voice: TtsVoiceInfo): boolean => voice.id === this.cloudVoiceId);
    if (cloudIndex >= 0) return offset + cloudIndex;
    offset += this.cloudVoices.length;
    const customs = this.customList();
    const customIndex = customs.findIndex((voice: HttpTTS): boolean => String(voice.id) === this.customVoiceId);
    if (customIndex >= 0) return offset + customIndex;
    offset += customs.length;
    const systemIndex = this.systemList().findIndex((voice: TtsVoiceOption): boolean => this.isSystemVoice(voice));
    return systemIndex >= 0 ? offset + systemIndex : locals.length;
  }

  /** 按快捷列表的下标换音色。返回 true 表示音色变了，正在朗读的要从原处重读。 */
  select(index: number): boolean {
    if (index < 0) return false;
    const mimo = this.mimoLabels();
    if (index < mimo.length) {
      const choice = MimoStore.voiceChoices(this.bookUrl())[index];
      if (!choice) return false;
      if (!MimoStore.isConfigured()) {
        this.onOpenMimoSettings();
        return false;
      }
      try {
        if (!MimoStore.selectVoice(choice, this.bookUrl())) {
          this.onOpenMimoSettings();
          return false;
        }
      } catch (error) {
        HdsFeedback.showToast((error as Error).message);
        return false;
      }
      return true;
    }
    let regular = index - mimo.length;
    if (MimoStore.load().enabled && regular === this.regularCount()) {
      this.onOpenMimoSettings();
      return false;
    }
    const locals = this.localVoices();
    if (regular < locals.length) return this.useLocalVoice(locals[regular]);
    regular -= locals.length;
    if (regular < this.cloudVoices.length) return this.useCloudVoice(this.cloudVoices[regular]);
    regular -= this.cloudVoices.length;
    const customs = this.customList();
    if (regular < customs.length) return this.useCustomVoice(customs[regular]);
    regular -= customs.length;
    const systems = this.systemList();
    if (regular >= 0 && regular < systems.length) return this.useSystemVoice(systems[regular]);
    return false;
  }

  private leaveMimo(): void {
    if (MimoStore.load().enabled) MimoStore.setEnabled(false);
  }

  private useLocalVoice(voice: LocalTtsModel): boolean {
    if (!LocalTtsModels.memberAllowed()) {
      HdsFeedback.showToast(LocalTtsModels.MEMBER_REQUIRED);
      return false;
    }
    this.leaveMimo();
    LocalTtsSelection.select(this.context, voice.id);
    this.cloudVoiceId = '';
    this.customVoiceId = '';
    this.save();
    return true;
  }

  private useCloudVoice(voice: TtsVoiceInfo): boolean {
    if (!AccountSessionStore.isLoggedIn()) {
      HdsFeedback.showToast('请先登录华为账号后使用在线音色');
      return false;
    }
    this.leaveMimo();
    this.cloudVoiceId = voice.id;
    this.customVoiceId = '';
    LocalTtsSelection.clear(this.context);
    this.save();
    return true;
  }

  private useCustomVoice(voice: HttpTTS): boolean {
    this.leaveMimo();
    this.customVoiceId = String(voice.id);
    this.cloudVoiceId = '';
    LocalTtsSelection.clear(this.context);
    this.save();
    return true;
  }

  private useSystemVoice(voice: TtsVoiceOption): boolean {
    if (!voice.available) {
      HdsFeedback.showToast(voice.downloadable ? '请到朗读设置下载该音色' : '该系统音色当前不可用');
      return false;
    }
    this.leaveMimo();
    this.person = voice.id;
    this.online = voice.online;
    this.style = voice.style;
    this.language = voice.language;
    this.customVoiceId = '';
    this.cloudVoiceId = '';
    LocalTtsSelection.clear(this.context);
    this.save();
    return true;
  }

  private currentLocalVoice(): LocalTtsModel | undefined {
    return LocalTtsSelection.current();
  }

  private currentCloudVoice(): TtsVoiceInfo | undefined {
    const id = (this.cloudVoiceId || '').trim();
    return id ? this.cloudVoices.find((voice: TtsVoiceInfo): boolean => voice.id === id) : undefined;
  }

  private currentCustomVoice(): HttpTTS | undefined {
    const id = (this.customVoiceId || '').trim();
    return id ? this.customOptions.find((voice: HttpTTS): boolean => String(voice.id) === id) : undefined;
  }

  private currentSystemVoice(): TtsVoiceOption | undefined {
    return this.systemVoices.find((voice: TtsVoiceOption): boolean => this.isSystemVoice(voice));
  }

  private isSystemVoice(voice: TtsVoiceOption): boolean {
    if (this.customVoiceId || this.cloudVoiceId || this.currentLocalVoice()) return false;
    return voice.id === this.person && voice.online === this.online && (voice.style || '') === (this.style || '') &&
      TtsVoiceCatalog.sameLanguage(voice.language || 'zh-CN', this.language || 'zh-CN');
  }
}
