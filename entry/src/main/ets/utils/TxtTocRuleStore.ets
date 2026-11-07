import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { CloudSyncChangeTracker } from '../account/CloudSyncChangeTracker';
import { TxtTocResolvedRule, TxtTocRule, TxtTocRules } from '../core/book/TxtTocRules';

/** 全局保存的目录规则设定：自定义规则、关掉的内置规则、新导入 TXT 的默认规则。 */
export class TxtTocRuleSettings {
  customRules: TxtTocRule[] = [];
  disabledBuiltins: string[] = [];
  /** 新导入 TXT 默认用的规则引用（见 TxtTocRules.ref），空串表示智能识别。 */
  defaultRuleRef: string = '';
}

class TxtTocRuleSettingsJson {
  customRules: TxtTocRule[] = [];
  disabledBuiltins: string[] = [];
  defaultRuleRef: string = '';
}

export class TxtTocRuleStore {
  static readonly UPDATE_TIME_KEY: string = 'txtTocRulesUpdateTime';
  /** 存储名列在数据备份的设置项里；改名要同步改 AppDataBackupService。 */
  static readonly STORE_NAME: string = 'txt_toc_rules';
  private static readonly SETTINGS_KEY: string = 'settingsV1';
  private static cached: TxtTocRuleSettings | null = null;

  static async load(context: Context, force: boolean = false): Promise<TxtTocRuleSettings> {
    if (!force && TxtTocRuleStore.cached) return TxtTocRuleStore.cloneSettings(TxtTocRuleStore.cached);
    let raw = '';
    try {
      const store = await preferences.getPreferences(context, TxtTocRuleStore.STORE_NAME);
      const value = await store.get(TxtTocRuleStore.SETTINGS_KEY, '');
      raw = typeof value === 'string' ? value : '';
    } catch (e) {
      console.warn('[TxtTocRuleStore] 读取目录规则失败:', e);
    }
    const settings = TxtTocRuleStore.decode(raw);
    TxtTocRuleStore.cached = TxtTocRuleStore.cloneSettings(settings);
    return settings;
  }

  static async save(context: Context, settings: TxtTocRuleSettings): Promise<void> {
    const normalized = TxtTocRuleStore.normalize(settings);
    TxtTocRuleStore.cached = TxtTocRuleStore.cloneSettings(normalized);
    const store = await preferences.getPreferences(context, TxtTocRuleStore.STORE_NAME);
    const json = new TxtTocRuleSettingsJson();
    json.customRules = normalized.customRules;
    json.disabledBuiltins = normalized.disabledBuiltins;
    json.defaultRuleRef = normalized.defaultRuleRef;
    await store.put(TxtTocRuleStore.SETTINGS_KEY, JSON.stringify(json));
    await store.flush();
    AppStorage.setOrCreate(TxtTocRuleStore.UPDATE_TIME_KEY, Date.now());
    CloudSyncChangeTracker.markPreferenceChanged();
  }

  /** 内置规则（带开关状态）在前，自定义规则在后。 */
  static allRules(settings: TxtTocRuleSettings): TxtTocRule[] {
    const result: TxtTocRule[] = [];
    for (const rule of TxtTocRules.builtins()) {
      rule.enabled = rule.id === TxtTocRules.AUTO_ID || !settings.disabledBuiltins.includes(rule.id);
      result.push(rule);
    }
    for (const rule of settings.customRules) result.push(TxtTocRules.clone(rule));
    return result;
  }

  /**
   * 书里规则引用对应的规则。规则被关掉仍照常使用（关掉只是不在书内列表里出现）；
   * 自定义规则被删掉或正则失效时退回智能识别。
   */
  static resolveIn(settings: TxtTocRuleSettings, ref: string): TxtTocResolvedRule {
    const resolved = new TxtTocResolvedRule();
    const id = TxtTocRules.ruleIdOf(ref);
    const rules = TxtTocRuleStore.allRules(settings);
    let rule = rules.find((item: TxtTocRule): boolean => item.id === id);
    if (rule && !rule.builtin && TxtTocRules.patternError(rule.pattern)) rule = undefined;
    resolved.rule = rule || (rules.find((item: TxtTocRule): boolean => item.id === TxtTocRules.AUTO_ID) as TxtTocRule);
    resolved.wordsPerChapter = TxtTocRules.wordsOf(ref);
    return resolved;
  }

  static async resolve(context: Context, ref: string): Promise<TxtTocResolvedRule> {
    return TxtTocRuleStore.resolveIn(await TxtTocRuleStore.load(context), ref);
  }

  private static decode(raw: string): TxtTocRuleSettings {
    const settings = new TxtTocRuleSettings();
    if (!raw) return settings;
    try {
      const parsed = JSON.parse(raw) as TxtTocRuleSettingsJson;
      settings.customRules = Array.isArray(parsed.customRules) ? parsed.customRules : [];
      settings.disabledBuiltins = Array.isArray(parsed.disabledBuiltins) ? parsed.disabledBuiltins : [];
      settings.defaultRuleRef = typeof parsed.defaultRuleRef === 'string' ? parsed.defaultRuleRef : '';
    } catch (e) {
      console.warn('[TxtTocRuleStore] 目录规则数据损坏，已忽略:', e);
    }
    return TxtTocRuleStore.normalize(settings);
  }

  private static normalize(settings: TxtTocRuleSettings): TxtTocRuleSettings {
    const result = new TxtTocRuleSettings();
    const seen: string[] = [];
    for (const source of settings.customRules || []) {
      if (!source || !source.id || seen.includes(source.id)) continue;
      seen.push(source.id);
      const rule = new TxtTocRule();
      rule.id = `${source.id}`;
      rule.name = `${source.name || ''}`.trim() || '未命名规则';
      rule.desc = '';
      rule.pattern = `${source.pattern || ''}`;
      rule.example = `${source.example || ''}`;
      rule.kind = TxtTocRules.KIND_REGEX;
      rule.builtin = false;
      rule.enabled = source.enabled !== false;
      const maxLength = Number(source.maxTitleLength);
      rule.maxTitleLength = Number.isFinite(maxLength) && maxLength > 0 ? Math.min(200, Math.round(maxLength)) :
        TxtTocRules.DEFAULT_MAX_TITLE_LENGTH;
      rule.ignoreCase = source.ignoreCase !== false;
      result.customRules.push(rule);
    }
    const builtinIds = TxtTocRules.builtins().map((rule: TxtTocRule): string => rule.id);
    result.disabledBuiltins = (settings.disabledBuiltins || []).filter((id: string): boolean =>
      id !== TxtTocRules.AUTO_ID && builtinIds.includes(id));
    result.defaultRuleRef = `${settings.defaultRuleRef || ''}`;
    return result;
  }

  private static cloneSettings(source: TxtTocRuleSettings): TxtTocRuleSettings {
    const result = new TxtTocRuleSettings();
    result.customRules = source.customRules.map((rule: TxtTocRule): TxtTocRule => TxtTocRules.clone(rule));
    result.disabledBuiltins = source.disabledBuiltins.slice();
    result.defaultRuleRef = source.defaultRuleRef;
    return result;
  }
}
