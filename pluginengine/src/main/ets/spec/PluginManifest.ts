export type PluginRuntimeKind = 'js' | 'python' | 'html' | 'declarative';

export type PluginPermission =
  | 'storage'
  | 'secrets'
  | 'network'
  | 'network.lan'
  | 'reader.selection'
  | 'reader.content'
  | 'bookshelf.read'
  | 'annotations.read'
  | 'annotations.write'
  | 'tts'
  | 'book.import'
  | 'webview.verify'
  | 'source.manage';

export const KNOWN_PLUGIN_PERMISSIONS: ReadonlySet<string> = new Set<string>([
  'storage',
  'secrets',
  'network',
  'network.lan',
  'reader.selection',
  'reader.content',
  'bookshelf.read',
  'annotations.read',
  'annotations.write',
  'tts',
  'book.import',
  'webview.verify',
  'source.manage'
]);

export type PluginSettingType = 'text' | 'secret' | 'boolean' | 'number' | 'select' | 'textarea';

export interface PluginSettingOption {
  label: string;
  value: string;
}

export interface PluginSettingField {
  key: string;
  label: string;
  type: PluginSettingType;
  description?: string;
  default?: string | number | boolean;
  options?: PluginSettingOption[];
  min?: number;
  max?: number;
  step?: number;
  placeholder?: string;
}

export interface PluginSettingAction {
  id: string;
  label: string;
  handler: string;
}

export interface PluginLanguagePair {
  from: string;
  to: string;
  label?: string;
}

export interface PluginTranslationContribution {
  id: string;
  name: string;
  languagePairs: PluginLanguagePair[];
  handler: string;
}

export interface PluginReaderActionContribution {
  id: string;
  title: string;
  placement: 'selection' | 'menu';
  bookTypes?: ('text' | 'epub' | 'comic' | 'pdf')[];
  handler?: string;
  panel?: string;
}

export interface PluginContentProcessorContribution {
  id: string;
  title: string;
  order?: number;
  handler: string;
}

export interface PluginInteractionContribution {
  id: string;
  title: string;
  fetchHandler: string;
  panelHandler?: string;
  panel?: string;
}

export interface PluginTtsVoiceSpec {
  id: string;
  name: string;
  lang: string;
  outputFormat?: 'pcm16le' | 'mp3' | 'wav';
  sampleRate?: number;
  concurrentRate?: string;
}

export interface PluginTtsContribution {
  id: string;
  name: string;
  voices: PluginTtsVoiceSpec[];
  outputFormat: 'pcm16le' | 'mp3' | 'wav';
  sampleRate?: number;
  concurrentRate?: string;
  handler: string;
}

export interface PluginFormatImporterContribution {
  id: string;
  name: string;
  extensions: string[];
  bookType: 'text' | 'epub' | 'comic';
  handler: string;
}

export interface PluginCatalogConnectorContribution {
  id: string;
  name: string;
  description?: string;
  browseHandler: string;
  searchHandler?: string;
  downloadHandler: string;
}

export interface PluginContentSourceHandlers {
  search: string;
  exploreMenus?: string;
  explore?: string;
  detail: string;
  toc: string;
  content: string;
  decodeImage?: string;
}

export interface PluginContentSourceContribution {
  /** 子内容源标识；单插件声明多形态 contentSources 时用于生成影子书源 URL `plugin://<pluginId>/<id>`。 */
  id?: string;
  name: string;
  group?: string;
  mediaType: 'text' | 'comic' | 'audio' | 'video';
  hasExplore?: boolean;
  handlers: PluginContentSourceHandlers;
}

export interface ParsedPluginShadowUrl {
  pluginId: string;
  sourceId: string;
}

export interface PluginShadowSourceEntry {
  sourceId: string;
  shadowUrl: string;
  contribution: PluginContentSourceContribution;
}

export interface PluginToolContribution {
  id: string;
  title: string;
  description?: string;
  panel: string;
  handler?: string;
}

export interface PluginSourceManagerContribution {
  id: string;
  title: string;
  enableExplore?: boolean;
  enableLegacyBackupImport?: boolean;
  preprocessImportHandler?: string;
  panel?: string;
}

export interface PluginTicketStyleFontSpec {
  family: string;
  src: string;
}

export interface PluginTicketStyleContribution {
  id: string;
  name: string;
  template: string;
  backTemplate?: string;
  aspectRatio?: number;
  coverWidth?: number;
  fonts?: PluginTicketStyleFontSpec[];
}

export interface ParsedPluginTicketStyleId {
  pluginId: string;
  styleId: string;
}

export interface PluginContributes {
  translation?: PluginTranslationContribution;
  readerActions?: PluginReaderActionContribution[];
  contentProcessor?: PluginContentProcessorContribution;
  interaction?: PluginInteractionContribution;
  tts?: PluginTtsContribution;
  formatImporters?: PluginFormatImporterContribution[];
  catalogConnectors?: PluginCatalogConnectorContribution[];
  contentSource?: PluginContentSourceContribution;
  contentSources?: PluginContentSourceContribution[];
  sourceManager?: PluginSourceManagerContribution;
  tools?: PluginToolContribution[];
  ticketStyles?: PluginTicketStyleContribution[];
}

export interface PluginAssetHash {
  path: string;
  sha256?: string;
  size?: number;
}

export interface PluginManifest {
  format: 'qyplugin';
  formatVersion: 1;
  id: string;
  name: string;
  version: string;
  author: string;
  description: string;
  icon: string;
  runtime: PluginRuntimeKind;
  main: string;
  minAppVersion: string;
  permissions: PluginPermission[];
  domains: string[];
  settings: PluginSettingField[];
  actions: PluginSettingAction[];
  contributes: PluginContributes;
  assets: PluginAssetHash[];
}

/** 每项权限给用户看的说明，安装预览逐条展示。 */
export const PLUGIN_PERMISSION_LABELS: ReadonlyMap<PluginPermission, string> = new Map<PluginPermission, string>([
  ['storage', '在插件私有空间保存数据'],
  ['secrets', '在系统密钥库保存账号、令牌等凭据'],
  ['network', '联网访问声明的域名'],
  ['network.lan', '访问局域网与本机地址'],
  ['reader.selection', '读取你在正文中选中的文字'],
  ['reader.content', '读取并改写正在阅读的章节正文'],
  ['bookshelf.read', '读取当前书籍的书名、作者、书籍地址与章节名'],
  ['annotations.read', '读取当前书籍的划线与笔记'],
  ['annotations.write', '在当前书籍中创建划线或笔记'],
  ['tts', '提供朗读音色，接收待朗读的正文'],
  ['book.import', '导入书籍到书架'],
  ['webview.verify', '打开网页验证窗口处理站点人机验证'],
  ['source.manage', '启用书源管理与在线阅读，读取书源与在线书籍统计']
]);

interface ContributionPermissionRule {
  label: string;
  permission: PluginPermission;
  applies: (c: PluginContributes) => boolean;
}

/** 扩展点拿到的数据或能力由这张表约束：声明了扩展点就必须声明对应权限，安装时一并展示给用户。 */
const CONTRIBUTION_PERMISSION_RULES: ContributionPermissionRule[] = [
  {
    label: 'readerActions（placement=selection）',
    permission: 'reader.selection',
    applies: (c) => (c.readerActions || []).some((a) => a.placement === 'selection')
  },
  { label: 'contentProcessor', permission: 'reader.content', applies: (c) => c.contentProcessor !== undefined },
  { label: 'interaction', permission: 'reader.content', applies: (c) => c.interaction !== undefined },
  { label: 'tts', permission: 'tts', applies: (c) => c.tts !== undefined },
  {
    label: 'formatImporters',
    permission: 'book.import',
    applies: (c) => (c.formatImporters || []).length > 0
  },
  {
    label: 'catalogConnectors',
    permission: 'book.import',
    applies: (c) => (c.catalogConnectors || []).length > 0
  },
  { label: 'sourceManager', permission: 'source.manage', applies: (c) => c.sourceManager !== undefined }
];

export function missingContributionPermissions(
  contributes: PluginContributes,
  permissions: PluginPermission[]
): string[] {
  const out: string[] = [];
  for (const rule of CONTRIBUTION_PERMISSION_RULES) {
    if (rule.applies(contributes) && !permissions.includes(rule.permission)) {
      out.push(`${rule.label} 需要 "${rule.permission}"`);
    }
  }
  return out;
}

export interface PluginReaderContextInput {
  bookUrl: string;
  bookName: string;
  author: string;
  chapterTitle: string;
  selectedText?: string;
}

/**
 * 按插件权限裁剪交给扩展点的阅读上下文：书籍身份与章节名要 bookshelf.read，选中文字要 reader.selection。
 * 没有权限的字段给空字符串，插件代码不用判断字段是否存在。
 */
export function pluginReaderContextFields(
  manifest: PluginManifest,
  input: PluginReaderContextInput
): Record<string, string> {
  const canReadBook = manifest.permissions.includes('bookshelf.read');
  const out: Record<string, string> = {
    bookUrl: canReadBook ? input.bookUrl : '',
    bookName: canReadBook ? input.bookName : '',
    author: canReadBook ? input.author : '',
    chapterTitle: canReadBook ? input.chapterTitle : ''
  };
  if (input.selectedText !== undefined) {
    out['selectedText'] = manifest.permissions.includes('reader.selection') ? input.selectedText : '';
  }
  return out;
}

export const QYPLUGIN_EXTENSION: string = '.qyplugin';
export const QYPLUGIN_UTD: string = 'io.qingye.modular.qyplugin';

const ID_RE: RegExp = /^[a-z0-9][a-z0-9._-]{2,63}$/;
const VERSION_RE: RegExp = /^\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z.-]+)?$/;
const DOMAIN_RE: RegExp = /^(?:\*|\*\.[a-z0-9-]+(?:\.[a-z0-9-]+)+|[a-z0-9-]+(?:\.[a-z0-9-]+)+|(?:localhost|\d{1,3}(?:\.\d{1,3}){3})(?::\d{1,5})?)$/i;

function isRecord(val: unknown): val is Record<string, unknown> {
  return typeof val === 'object' && val !== null && !Array.isArray(val);
}

function asTrimmedString(val: unknown, maxLen: number = 256): string {
  if (typeof val !== 'string') return '';
  const trimmed = val.trim();
  return trimmed.length > maxLen ? trimmed.slice(0, maxLen) : trimmed;
}

export function normalizeSafePluginRelPath(raw: string): string {
  const trimmed = raw.trim().replace(/\\/g, '/');
  if (!trimmed || trimmed.startsWith('/') || trimmed.includes(':') || trimmed.includes('\0')) {
    throw new Error(`非法的插件包内路径: ${raw}`);
  }
  const out: string[] = [];
  for (const part of trimmed.split('/')) {
    if (!part || part === '.') continue;
    if (part === '..') throw new Error(`插件路径禁止包含上级目录跳转: ${raw}`);
    out.push(part);
  }
  if (out.length === 0) throw new Error(`插件路径为空: ${raw}`);
  return out.join('/');
}

export function validatePluginManifest(input: unknown): PluginManifest {
  if (!isRecord(input)) {
    throw new Error('manifest.json 必须是 JSON 对象');
  }
  if (input['format'] !== 'qyplugin') {
    throw new Error('manifest.json 的 format 必须为 "qyplugin"');
  }
  const formatVersion = Number(input['formatVersion'] ?? 1);
  if (formatVersion !== 1) {
    throw new Error(`当前应用不支持 formatVersion=${formatVersion}，请升级应用`);
  }

  const id = asTrimmedString(input['id'], 64);
  if (!ID_RE.test(id)) {
    throw new Error('插件 id 必须由 3-64 位小写字母、数字、点、连字符或下划线组成');
  }
  const name = asTrimmedString(input['name'], 40);
  if (!name) {
    throw new Error('插件 name 不能为空');
  }
  const version = asTrimmedString(input['version'], 32);
  if (!VERSION_RE.test(version)) {
    throw new Error(`插件版本号格式无效: ${version}`);
  }
  const runtimeRaw = asTrimmedString(input['runtime'], 16);
  if (runtimeRaw !== 'js' && runtimeRaw !== 'python' && runtimeRaw !== 'html' && runtimeRaw !== 'declarative') {
    throw new Error(`不支持的插件 runtime: ${runtimeRaw}（仅支持 js / python / html / declarative）`);
  }
  const runtime: PluginRuntimeKind = runtimeRaw;

  const mainRaw = asTrimmedString(input['main'], 128);
  const main = mainRaw ? normalizeSafePluginRelPath(mainRaw) : '';
  if ((runtime === 'js' || runtime === 'python') && !main) {
    throw new Error(`runtime="${runtime}" 的插件必须指定入口文件 main`);
  }

  const iconRaw = asTrimmedString(input['icon'], 128);
  const icon = iconRaw ? normalizeSafePluginRelPath(iconRaw) : '';

  const permissions: PluginPermission[] = [];
  const rawPerms = Array.isArray(input['permissions']) ? input['permissions'] : [];
  for (const item of rawPerms) {
    const p = asTrimmedString(item, 32);
    if (!KNOWN_PLUGIN_PERMISSIONS.has(p)) {
      throw new Error(`未知的插件权限声明: ${p}`);
    }
    if (!permissions.includes(p as PluginPermission)) {
      permissions.push(p as PluginPermission);
    }
  }

  const domains: string[] = [];
  const rawDomains = Array.isArray(input['domains']) ? input['domains'] : [];
  for (const d of rawDomains) {
    const dom = asTrimmedString(d, 128).toLowerCase();
    if (!dom || !DOMAIN_RE.test(dom)) {
      throw new Error(`非法的域名白名单项: ${String(d)}`);
    }
    if (!domains.includes(dom)) domains.push(dom);
  }
  if (permissions.includes('network') && domains.length === 0) {
    throw new Error('声明 network 权限时必须在 domains 中明确列出允许访问的域名（或 "*"）');
  }

  const settings = parseSettings(input['settings']);
  const actions = parseActions(input['actions'], runtime);
  const contributes = parseContributes(input['contributes'], runtime);
  const missing = missingContributionPermissions(contributes, permissions);
  if (missing.length > 0) {
    throw new Error(`扩展点需要声明对应权限：${missing.join('；')}`);
  }
  const assets = parseAssets(input['assets']);

  return {
    format: 'qyplugin',
    formatVersion: 1,
    id,
    name,
    version,
    author: asTrimmedString(input['author'], 40),
    description: asTrimmedString(input['description'], 200),
    icon,
    runtime,
    main,
    minAppVersion: asTrimmedString(input['minAppVersion'], 32),
    permissions,
    domains,
    settings,
    actions,
    contributes,
    assets
  };
}

function parseSettings(raw: unknown): PluginSettingField[] {
  if (!Array.isArray(raw)) return [];
  const out: PluginSettingField[] = [];
  const seen: Set<string> = new Set();
  for (const item of raw) {
    if (!isRecord(item)) continue;
    const key = asTrimmedString(item['key'], 64);
    const label = asTrimmedString(item['label'], 48);
    const type = asTrimmedString(item['type'], 16) as PluginSettingType;
    if (!key || !label || seen.has(key)) continue;
    if (!['text', 'secret', 'boolean', 'number', 'select', 'textarea'].includes(type)) {
      throw new Error(`设置项 ${key} 的类型无效: ${type}`);
    }
    seen.add(key);
    const field: PluginSettingField = {
      key,
      label,
      type,
      description: asTrimmedString(item['description'], 160) || undefined,
      placeholder: asTrimmedString(item['placeholder'], 80) || undefined
    };
    if (typeof item['default'] === 'string' || typeof item['default'] === 'number' || typeof item['default'] === 'boolean') {
      field.default = item['default'];
    }
    if (typeof item['min'] === 'number') field.min = item['min'];
    if (typeof item['max'] === 'number') field.max = item['max'];
    if (typeof item['step'] === 'number') field.step = item['step'];
    if (type === 'select' && Array.isArray(item['options'])) {
      field.options = item['options']
        .filter(isRecord)
        .map((opt) => ({
          label: asTrimmedString(opt['label'] ?? opt['value'], 48),
          value: asTrimmedString(opt['value'], 128)
        }))
        .filter((opt) => opt.label.length > 0 && opt.value.length > 0);
    }
    out.push(field);
  }
  return out;
}

function parseActions(raw: unknown, runtime: PluginRuntimeKind): PluginSettingAction[] {
  if (!Array.isArray(raw)) return [];
  if ((runtime === 'html' || runtime === 'declarative') && raw.length > 0) {
    throw new Error(`runtime="${runtime}" 插件不支持后台脚本设置按钮 actions`);
  }
  const out: PluginSettingAction[] = [];
  for (const item of raw) {
    if (!isRecord(item)) continue;
    const id = asTrimmedString(item['id'], 48);
    const label = asTrimmedString(item['label'], 32);
    const handler = asTrimmedString(item['handler'], 64);
    if (id && label && handler) {
      out.push({ id, label, handler });
    }
  }
  return out;
}

function parseAssets(raw: unknown): PluginAssetHash[] {
  if (!Array.isArray(raw)) return [];
  const out: PluginAssetHash[] = [];
  for (const item of raw) {
    if (!isRecord(item)) continue;
    const rel = asTrimmedString(item['path'], 180);
    if (!rel) continue;
    out.push({
      path: normalizeSafePluginRelPath(rel),
      sha256: asTrimmedString(item['sha256'], 64).toLowerCase() || undefined,
      size: typeof item['size'] === 'number' ? item['size'] : undefined
    });
  }
  return out;
}

function parseContributes(raw: unknown, runtime: PluginRuntimeKind): PluginContributes {
  if (!isRecord(raw)) return {};
  const result: PluginContributes = {};

  if (runtime === 'html') {
    const forbidden = [
      'translation', 'contentProcessor', 'interaction',
      'tts', 'formatImporters', 'catalogConnectors', 'contentSource', 'contentSources'
    ];
    for (const key of forbidden) {
      if (raw[key] !== undefined) {
        throw new Error(`runtime="html" 仅允许挂载面板界面（readerActions / tools / ticketStyles），禁止声明后台管道 "${key}"`);
      }
    }
  } else if (runtime === 'declarative') {
    const forbidden = [
      'translation', 'readerActions', 'contentProcessor', 'interaction',
      'tts', 'formatImporters', 'catalogConnectors', 'contentSource', 'contentSources',
      'sourceManager', 'tools'
    ];
    for (const key of forbidden) {
      if (raw[key] !== undefined) {
        throw new Error(`runtime="declarative" 仅允许声明式扩展点（ticketStyles），禁止声明 "${key}"`);
      }
    }
  }

  if (isRecord(raw['translation'])) {
    const tr = raw['translation'];
    const pairsRaw = Array.isArray(tr['languagePairs']) ? tr['languagePairs'] : [];
    const pairs: PluginLanguagePair[] = pairsRaw.filter(isRecord).map((p) => ({
      from: asTrimmedString(p['from'], 24),
      to: asTrimmedString(p['to'], 24),
      label: asTrimmedString(p['label'], 40) || undefined
    })).filter((p) => p.from.length > 0 && p.to.length > 0);
    const handler = asTrimmedString(tr['handler'], 64);
    if (!handler || pairs.length === 0) {
      throw new Error('contributes.translation 必须提供 handler 与至少一组 languagePairs');
    }
    result.translation = {
      id: asTrimmedString(tr['id'], 48) || 'default',
      name: asTrimmedString(tr['name'], 40) || '插件翻译',
      languagePairs: pairs,
      handler
    };
  }

  if (Array.isArray(raw['readerActions'])) {
    const actions: PluginReaderActionContribution[] = [];
    for (const item of raw['readerActions']) {
      if (!isRecord(item)) continue;
      const id = asTrimmedString(item['id'], 48);
      const title = asTrimmedString(item['title'], 24);
      const placement = asTrimmedString(item['placement'], 16);
      if (!id || !title || (placement !== 'selection' && placement !== 'menu')) {
        throw new Error('contributes.readerActions 每项必须包含 id、title 与合法 placement (selection | menu)');
      }
      const handler = asTrimmedString(item['handler'], 64) || undefined;
      const panelRaw = asTrimmedString(item['panel'], 128);
      const panel = panelRaw ? normalizeSafePluginRelPath(panelRaw) : undefined;
      if (runtime === 'html' && !panel) {
        throw new Error(`runtime="html" 的 readerAction "${id}" 必须指定 panel HTML 路径`);
      }
      if (!handler && !panel) {
        throw new Error(`readerAction "${id}" 至少需要指定 handler 或 panel 之一`);
      }
      let bookTypes: ('text' | 'epub' | 'comic' | 'pdf')[] | undefined;
      if (Array.isArray(item['bookTypes'])) {
        bookTypes = item['bookTypes']
          .map((t) => asTrimmedString(t, 12))
          .filter((t): t is 'text' | 'epub' | 'comic' | 'pdf' =>
            t === 'text' || t === 'epub' || t === 'comic' || t === 'pdf');
      }
      actions.push({ id, title, placement, bookTypes, handler, panel });
    }
    if (actions.length > 0) result.readerActions = actions;
  }

  if (isRecord(raw['contentProcessor'])) {
    const cp = raw['contentProcessor'];
    const handler = asTrimmedString(cp['handler'], 64);
    if (!handler) throw new Error('contributes.contentProcessor 必须提供 handler');
    result.contentProcessor = {
      id: asTrimmedString(cp['id'], 48) || 'default',
      title: asTrimmedString(cp['title'], 40) || '正文处理',
      order: typeof cp['order'] === 'number' ? cp['order'] : 100,
      handler
    };
  }

  if (isRecord(raw['interaction'])) {
    const inter = raw['interaction'];
    const fetchHandler = asTrimmedString(inter['fetchHandler'], 64);
    if (!fetchHandler) throw new Error('contributes.interaction 必须提供 fetchHandler');
    const panelRaw = asTrimmedString(inter['panel'], 128);
    result.interaction = {
      id: asTrimmedString(inter['id'], 48) || 'default',
      title: asTrimmedString(inter['title'], 40) || '段落互动',
      fetchHandler,
      panelHandler: asTrimmedString(inter['panelHandler'], 64) || undefined,
      panel: panelRaw ? normalizeSafePluginRelPath(panelRaw) : undefined
    };
  }

  if (isRecord(raw['tts'])) {
    const tts = raw['tts'];
    const handler = asTrimmedString(tts['handler'], 64);
    const fmt = asTrimmedString(tts['outputFormat'], 16);
    if (!handler || (fmt !== 'pcm16le' && fmt !== 'mp3' && fmt !== 'wav')) {
      throw new Error('contributes.tts 必须提供 handler 与合法 outputFormat (pcm16le | mp3 | wav)');
    }
    const voicesRaw = Array.isArray(tts['voices']) ? tts['voices'] : [];
    const voices: PluginTtsVoiceSpec[] = voicesRaw.filter(isRecord).map((v) => {
      const vFmt = asTrimmedString(v['outputFormat'], 16);
      const vRate = asTrimmedString(v['concurrentRate'], 32);
      const spec: PluginTtsVoiceSpec = {
        id: asTrimmedString(v['id'], 48),
        name: asTrimmedString(v['name'], 40),
        lang: asTrimmedString(v['lang'], 24) || 'zh-CN'
      };
      if (vFmt === 'pcm16le' || vFmt === 'mp3' || vFmt === 'wav') {
        spec.outputFormat = vFmt;
      }
      if (typeof v['sampleRate'] === 'number' && v['sampleRate'] >= 8000 && v['sampleRate'] <= 96000) {
        spec.sampleRate = v['sampleRate'];
      }
      if (vRate) {
        spec.concurrentRate = vRate;
      }
      return spec;
    }).filter((v) => v.id.length > 0 && v.name.length > 0);
    if (voices.length === 0) {
      throw new Error('contributes.tts 必须声明至少一个音色 voices');
    }
    const ttsConcurrentRate = asTrimmedString(tts['concurrentRate'], 32);
    result.tts = {
      id: asTrimmedString(tts['id'], 48) || 'default',
      name: asTrimmedString(tts['name'], 40) || '插件朗读',
      voices,
      outputFormat: fmt,
      sampleRate: typeof tts['sampleRate'] === 'number' ? tts['sampleRate'] : 24000,
      concurrentRate: ttsConcurrentRate || undefined,
      handler
    };
  }

  if (Array.isArray(raw['formatImporters'])) {
    const importers: PluginFormatImporterContribution[] = [];
    for (const item of raw['formatImporters']) {
      if (!isRecord(item)) continue;
      const id = asTrimmedString(item['id'], 48);
      const name = asTrimmedString(item['name'], 40);
      const handler = asTrimmedString(item['handler'], 64);
      const bookType = asTrimmedString(item['bookType'], 12);
      const exts = (Array.isArray(item['extensions']) ? item['extensions'] : [])
        .map((e) => asTrimmedString(e, 16).toLowerCase().replace(/^\./, ''))
        .filter((e) => /^[a-z0-9]{1,12}$/.test(e));
      if (!id || !name || !handler || exts.length === 0 ||
          (bookType !== 'text' && bookType !== 'epub' && bookType !== 'comic')) {
        throw new Error('contributes.formatImporters 项缺少必要字段或合法 bookType');
      }
      importers.push({ id, name, extensions: exts, bookType, handler });
    }
    if (importers.length > 0) result.formatImporters = importers;
  }

  if (Array.isArray(raw['catalogConnectors'])) {
    const catalogs: PluginCatalogConnectorContribution[] = [];
    for (const item of raw['catalogConnectors']) {
      if (!isRecord(item)) continue;
      const id = asTrimmedString(item['id'], 48);
      const name = asTrimmedString(item['name'], 40);
      const browseHandler = asTrimmedString(item['browseHandler'], 64);
      const downloadHandler = asTrimmedString(item['downloadHandler'], 64);
      if (!id || !name || !browseHandler || !downloadHandler) {
        throw new Error('contributes.catalogConnectors 必须提供 id、name、browseHandler 与 downloadHandler');
      }
      catalogs.push({
        id,
        name,
        description: asTrimmedString(item['description'], 120) || undefined,
        browseHandler,
        searchHandler: asTrimmedString(item['searchHandler'], 64) || undefined,
        downloadHandler
      });
    }
    if (catalogs.length > 0) result.catalogConnectors = catalogs;
  }

  const parseContentSourceEntry = (
    cs: Record<string, unknown>,
    defaultIdToMediaType: boolean,
    label: string
  ): PluginContentSourceContribution => {
    const mediaType = asTrimmedString(cs['mediaType'], 12);
    const handlers = isRecord(cs['handlers']) ? cs['handlers'] : null;
    if (!handlers || (mediaType !== 'text' && mediaType !== 'comic' && mediaType !== 'audio' && mediaType !== 'video')) {
      throw new Error(`${label} 必须提供合法 mediaType 与 handlers`);
    }
    const search = asTrimmedString(handlers['search'], 64);
    const detail = asTrimmedString(handlers['detail'], 64);
    const toc = asTrimmedString(handlers['toc'], 64);
    const content = asTrimmedString(handlers['content'], 64);
    if (!search || !detail || !toc || !content) {
      throw new Error(`${label}.handlers 必须包含 search、detail、toc、content`);
    }
    const rawId = asTrimmedString(cs['id'], 32);
    const id = rawId || (defaultIdToMediaType ? mediaType : '');
    if (id && !/^[a-z0-9][a-z0-9._-]{0,31}$/i.test(id)) {
      throw new Error(`${label} 的 id "${id}" 格式无效（仅允许字母、数字、点、连字符或下划线）`);
    }
    const entry: PluginContentSourceContribution = {
      name: asTrimmedString(cs['name'], 40) || '插件源',
      group: asTrimmedString(cs['group'], 32) || '插件',
      mediaType,
      hasExplore: Boolean(cs['hasExplore'] && handlers['explore']),
      handlers: {
        search,
        exploreMenus: asTrimmedString(handlers['exploreMenus'], 64) || undefined,
        explore: asTrimmedString(handlers['explore'], 64) || undefined,
        detail,
        toc,
        content,
        decodeImage: asTrimmedString(handlers['decodeImage'], 64) || undefined
      }
    };
    if (id) {
      entry.id = id;
    }
    return entry;
  };

  const seenContentSourceIds: Set<string> = new Set();
  if (isRecord(raw['contentSource'])) {
    const parsed = parseContentSourceEntry(raw['contentSource'], false, 'contributes.contentSource');
    seenContentSourceIds.add(parsed.id || '');
    result.contentSource = parsed;
  }

  if (Array.isArray(raw['contentSources'])) {
    const list: PluginContentSourceContribution[] = [];
    for (let i = 0; i < raw['contentSources'].length; i++) {
      const item = raw['contentSources'][i];
      if (!isRecord(item)) {
        throw new Error(`contributes.contentSources[${i}] 必须是对象`);
      }
      const parsed = parseContentSourceEntry(item, true, `contributes.contentSources[${i}]`);
      const key = parsed.id || parsed.mediaType;
      if (seenContentSourceIds.has(key)) {
        throw new Error(`contributes.contentSources 中存在重复的源标识 "${key}"`);
      }
      seenContentSourceIds.add(key);
      list.push(parsed);
    }
    if (list.length > 0) {
      result.contentSources = list;
    }
  }

  if (Array.isArray(raw['tools'])) {
    const tools: PluginToolContribution[] = [];
    for (const item of raw['tools']) {
      if (!isRecord(item)) continue;
      const id = asTrimmedString(item['id'], 48);
      const title = asTrimmedString(item['title'], 32);
      const panelRaw = asTrimmedString(item['panel'], 128);
      if (!id || !title || !panelRaw) {
        throw new Error('contributes.tools 每项必须包含 id、title 与 panel');
      }
      tools.push({
        id,
        title,
        description: asTrimmedString(item['description'], 120) || undefined,
        panel: normalizeSafePluginRelPath(panelRaw),
        handler: runtime === 'html' ? undefined : (asTrimmedString(item['handler'], 64) || undefined)
      });
    }
    if (tools.length > 0) result.tools = tools;
  }

  if (isRecord(raw['sourceManager'])) {
    const sm = raw['sourceManager'];
    const id = asTrimmedString(sm['id'], 48) || 'default';
    const title = asTrimmedString(sm['title'], 40) || '书源管理与在线阅读';
    const preprocessImportHandler = asTrimmedString(sm['preprocessImportHandler'], 64) || undefined;
    if (runtime === 'html' && preprocessImportHandler) {
      throw new Error('runtime="html" 的 sourceManager 不支持声明后台 preprocessImportHandler');
    }
    const panelRaw = asTrimmedString(sm['panel'], 128);
    const panel = panelRaw ? normalizeSafePluginRelPath(panelRaw) : undefined;
    result.sourceManager = {
      id,
      title,
      enableExplore: sm['enableExplore'] === undefined ? true : Boolean(sm['enableExplore']),
      enableLegacyBackupImport: sm['enableLegacyBackupImport'] === undefined ? true : Boolean(sm['enableLegacyBackupImport']),
      preprocessImportHandler,
      panel
    };
  }

  if (Array.isArray(raw['ticketStyles'])) {
    const styles: PluginTicketStyleContribution[] = [];
    const seenIds: Set<string> = new Set();
    for (let i = 0; i < raw['ticketStyles'].length; i++) {
      const item = raw['ticketStyles'][i];
      if (!isRecord(item)) {
        throw new Error(`contributes.ticketStyles[${i}] 必须是对象`);
      }
      const id = asTrimmedString(item['id'], 32);
      const name = asTrimmedString(item['name'], 16);
      const templateRaw = asTrimmedString(item['template'], 160);
      if (!id || !/^[a-z0-9][a-z0-9._-]{0,31}$/i.test(id)) {
        throw new Error(`contributes.ticketStyles[${i}] 的 id "${id}" 格式无效（仅允许字母、数字、点、连字符或下划线）`);
      }
      if (seenIds.has(id)) {
        throw new Error(`contributes.ticketStyles 中存在重复的样式标识 "${id}"`);
      }
      if (!name) {
        throw new Error(`contributes.ticketStyles[${i}] 必须提供显示名称 name`);
      }
      if (!templateRaw) {
        throw new Error(`contributes.ticketStyles[${i}] 必须提供模板文件路径 template`);
      }
      const template = normalizeSafePluginRelPath(templateRaw);
      const backRaw = asTrimmedString(item['backTemplate'], 160);
      const backTemplate = backRaw ? normalizeSafePluginRelPath(backRaw) : undefined;
      let aspectRatio: number | undefined;
      if (typeof item['aspectRatio'] === 'number' && Number.isFinite(item['aspectRatio'])) {
        aspectRatio = Math.max(0.4, Math.min(4.0, item['aspectRatio']));
      }
      let coverWidth: number | undefined;
      if (typeof item['coverWidth'] === 'number' && Number.isFinite(item['coverWidth'])) {
        coverWidth = Math.max(32, Math.min(300, item['coverWidth']));
      }
      let fonts: PluginTicketStyleFontSpec[] | undefined;
      if (Array.isArray(item['fonts'])) {
        const parsedFonts: PluginTicketStyleFontSpec[] = [];
        for (const f of item['fonts'].slice(0, 4)) {
          if (!isRecord(f)) continue;
          const family = asTrimmedString(f['family'], 48);
          const srcRaw = asTrimmedString(f['src'], 160);
          if (!family || !srcRaw) continue;
          parsedFonts.push({ family, src: normalizeSafePluginRelPath(srcRaw) });
        }
        if (parsedFonts.length > 0) fonts = parsedFonts;
      }
      seenIds.add(id);
      styles.push({ id, name, template, backTemplate, aspectRatio, coverWidth, fonts });
    }
    if (styles.length > 0) result.ticketStyles = styles;
  }

  return result;
}

export function normalizePluginSettings(
  manifest: PluginManifest,
  saved?: Record<string, unknown> | null
): Record<string, string | number | boolean> {
  const out: Record<string, string | number | boolean> = {};
  const src = saved && isRecord(saved) ? saved : {};
  for (const field of manifest.settings) {
    if (field.type === 'secret') continue;
    const rawVal = src[field.key];
    if (field.type === 'boolean') {
      out[field.key] = typeof rawVal === 'boolean' ? rawVal : Boolean(field.default ?? false);
    } else if (field.type === 'number') {
      const n = typeof rawVal === 'number' ? rawVal : Number(field.default ?? 0);
      let clamped = Number.isFinite(n) ? n : 0;
      if (field.min !== undefined) clamped = Math.max(field.min, clamped);
      if (field.max !== undefined) clamped = Math.min(field.max, clamped);
      out[field.key] = clamped;
    } else {
      out[field.key] = typeof rawVal === 'string' ? rawVal : String(field.default ?? '');
    }
  }
  return out;
}

export function buildPluginShadowSourceUrl(pluginId: string, sourceId?: string): string {
  const cleanId = (sourceId || '').trim();
  return cleanId ? `plugin://${pluginId}/${cleanId}` : `plugin://${pluginId}`;
}

export const PLUGIN_TICKET_STYLE_PREFIX: string = 'plugin:';

export function buildPluginTicketStyleId(pluginId: string, styleId: string): string {
  return `${PLUGIN_TICKET_STYLE_PREFIX}${pluginId.trim()}:${styleId.trim()}`;
}

export function isPluginTicketStyleId(raw: string): boolean {
  return parsePluginTicketStyleId(raw) !== null;
}

export function parsePluginTicketStyleId(raw: string): ParsedPluginTicketStyleId | null {
  const value = (raw || '').trim();
  if (!value.startsWith(PLUGIN_TICKET_STYLE_PREFIX)) return null;
  const rest = value.slice(PLUGIN_TICKET_STYLE_PREFIX.length);
  const sep = rest.indexOf(':');
  if (sep <= 0 || sep >= rest.length - 1) return null;
  const pluginId = rest.slice(0, sep).trim();
  const styleId = rest.slice(sep + 1).trim();
  if (!ID_RE.test(pluginId) || !/^[a-z0-9][a-z0-9._-]{0,31}$/i.test(styleId)) return null;
  return { pluginId, styleId };
}

export function parsePluginShadowSourceUrl(url: string): ParsedPluginShadowUrl {
  const raw = (url || '').trim();
  if (!raw.startsWith('plugin://')) {
    return { pluginId: '', sourceId: '' };
  }
  const rest = raw.slice('plugin://'.length);
  const slash = rest.indexOf('/');
  if (slash < 0) {
    return { pluginId: rest, sourceId: '' };
  }
  return {
    pluginId: rest.slice(0, slash),
    sourceId: rest.slice(slash + 1)
  };
}

export function getManifestContentSources(manifest: PluginManifest): PluginContentSourceContribution[] {
  const out: PluginContentSourceContribution[] = [];
  if (manifest.contributes.contentSource) {
    out.push(manifest.contributes.contentSource);
  }
  if (manifest.contributes.contentSources && manifest.contributes.contentSources.length > 0) {
    for (const item of manifest.contributes.contentSources) {
      out.push(item);
    }
  }
  return out;
}

export function getManifestShadowSourceEntries(manifest: PluginManifest): PluginShadowSourceEntry[] {
  const out: PluginShadowSourceEntry[] = [];
  if (manifest.contributes.contentSource) {
    const cs = manifest.contributes.contentSource;
    const sourceId = (cs.id || '').trim();
    out.push({
      sourceId,
      shadowUrl: buildPluginShadowSourceUrl(manifest.id, sourceId),
      contribution: cs
    });
  }
  if (manifest.contributes.contentSources && manifest.contributes.contentSources.length > 0) {
    for (const cs of manifest.contributes.contentSources) {
      const sourceId = (cs.id || cs.mediaType).trim();
      out.push({
        sourceId,
        shadowUrl: buildPluginShadowSourceUrl(manifest.id, sourceId),
        contribution: cs
      });
    }
  }
  return out;
}

export function resolveManifestContentSource(
  manifest: PluginManifest,
  sourceId?: string
): PluginShadowSourceEntry | null {
  const entries = getManifestShadowSourceEntries(manifest);
  if (entries.length === 0) return null;
  const cleanId = (sourceId || '').trim();
  if (!cleanId) {
    return entries.find((e) => e.sourceId === '') || entries[0];
  }
  return entries.find((e) => e.sourceId === cleanId) || null;
}

export function requiresWebParseGate(manifest: PluginManifest): boolean {
  if (manifest.contributes.sourceManager !== undefined) return true;
  if (getManifestContentSources(manifest).length > 0) return true;
  if (manifest.permissions.includes('source.manage')) return true;
  if (manifest.permissions.includes('webview.verify')) return true;
  if (manifest.domains.includes('*')) return true;
  return false;
}

export interface PluginHostPort {
  host: string;
  port: string;
}

/** 拆出主机与端口；主机转小写、去掉 IPv6 方括号与末尾的点（`example.com.` 与 `example.com` 是同一主机）。 */
export function splitHostPort(hostWithOptionalPort: string): PluginHostPort {
  const trimmed = hostWithOptionalPort.trim().toLowerCase();
  let host = trimmed;
  let port = '';
  if (trimmed.startsWith('[')) {
    const close = trimmed.indexOf(']');
    host = close > 0 ? trimmed.slice(1, close) : trimmed.slice(1);
    const rest = close > 0 ? trimmed.slice(close + 1) : '';
    if (rest.startsWith(':')) port = rest.slice(1);
  } else {
    const firstColon = trimmed.indexOf(':');
    if (firstColon >= 0 && firstColon === trimmed.lastIndexOf(':')) {
      host = trimmed.slice(0, firstColon);
      port = trimmed.slice(firstColon + 1);
    }
  }
  while (host.endsWith('.')) host = host.slice(0, -1);
  return { host, port };
}

export function matchesDomainAllowlist(hostWithOptionalPort: string, allowlist: string[]): boolean {
  const target = splitHostPort(hostWithOptionalPort);
  const hostOnly = target.host;
  if (!hostOnly) return false;
  const hostWithPort = target.port ? `${hostOnly}:${target.port}` : hostOnly;
  for (const patternRaw of allowlist) {
    const pattern = patternRaw.trim().toLowerCase();
    if (pattern === '*') return true;
    if (pattern.startsWith('*.')) {
      const suffix = pattern.slice(1); // ".example.com"
      if (hostOnly.endsWith(suffix) && hostOnly.length > suffix.length) return true;
    } else if (pattern.includes(':')) {
      if (hostWithPort === pattern) return true;
    } else if (hostOnly === pattern) {
      return true;
    }
  }
  return false;
}

function parseIpv4Part(part: string): number {
  if (!part) return NaN;
  let radix = 10;
  let digits = part;
  if (/^0x/i.test(part)) {
    radix = 16;
    digits = part.slice(2);
    if (!digits) return 0;
  } else if (part.length > 1 && part.startsWith('0')) {
    radix = 8;
    digits = part.slice(1);
  }
  const valid = radix === 16 ? /^[0-9a-f]+$/i : (radix === 8 ? /^[0-7]+$/ : /^[0-9]+$/);
  if (!valid.test(digits)) return NaN;
  return parseInt(digits, radix);
}

/**
 * 按网络栈的宽松写法解析 IPv4：`127.1`、`2130706433`、`0x7f.0.0.1`、`0177.0.0.1` 都指向 127.0.0.1。
 * 不是 IPv4 字面量时返回 null。
 */
export function parseIpv4Literal(rawHost: string): number[] | null {
  let host = rawHost.trim();
  if (host.endsWith('.')) host = host.slice(0, -1);
  if (!host) return null;
  const parts = host.split('.');
  if (parts.length > 4) return null;
  const nums: number[] = [];
  for (const part of parts) {
    const n = parseIpv4Part(part);
    if (!Number.isFinite(n)) return null;
    nums.push(n);
  }
  for (let i = 0; i < nums.length - 1; i++) {
    if (nums[i] > 255) return null;
  }
  const last = nums[nums.length - 1];
  if (last >= Math.pow(256, 5 - nums.length)) return null;
  let value = last;
  for (let i = 0; i < nums.length - 1; i++) {
    value += nums[i] * Math.pow(256, 3 - i);
  }
  return [
    Math.floor(value / 16777216) % 256,
    Math.floor(value / 65536) % 256,
    Math.floor(value / 256) % 256,
    value % 256
  ];
}

/** 解析 IPv6 字面量（可带方括号、区域标识与内嵌 IPv4），返回 16 个字节；不是 IPv6 时返回 null。 */
export function parseIpv6Literal(rawHost: string): number[] | null {
  let s = rawHost.trim().toLowerCase();
  if (s.startsWith('[') && s.endsWith(']')) s = s.slice(1, -1);
  const zone = s.indexOf('%');
  if (zone >= 0) s = s.slice(0, zone);
  if (!s.includes(':')) return null;

  let embedded: number[] | null = null;
  const lastColon = s.lastIndexOf(':');
  const tail = s.slice(lastColon + 1);
  if (tail.includes('.')) {
    const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(tail);
    if (!m) return null;
    embedded = [Number(m[1]), Number(m[2]), Number(m[3]), Number(m[4])];
    if (embedded.some((b) => b > 255)) return null;
    s = `${s.slice(0, lastColon + 1)}0:0`;
  }

  const dbl = s.indexOf('::');
  if (dbl >= 0 && dbl !== s.lastIndexOf('::')) return null;
  const headPart = dbl >= 0 ? s.slice(0, dbl) : s;
  const restPart = dbl >= 0 ? s.slice(dbl + 2) : '';
  const head = headPart ? headPart.split(':') : [];
  const rest = restPart ? restPart.split(':') : [];
  if (dbl < 0 && head.length !== 8) return null;
  if (dbl >= 0 && head.length + rest.length > 7) return null;
  const groups: string[] = head.slice();
  for (let i = head.length + rest.length; i < 8; i++) groups.push('0');
  for (const g of rest) groups.push(g);

  const bytes: number[] = [];
  for (const g of groups) {
    if (!/^[0-9a-f]{1,4}$/.test(g)) return null;
    const v = parseInt(g, 16);
    bytes.push(v >> 8, v & 0xff);
  }
  if (embedded) {
    for (let i = 0; i < 4; i++) bytes[12 + i] = embedded[i];
  }
  return bytes;
}

function isPrivateIpv4Bytes(b: number[]): boolean {
  const a = b[0];
  const c = b[1];
  if (a === 0 || a === 10 || a === 127) return true;
  if (a === 100 && c >= 64 && c <= 127) return true; // 运营商级 NAT 100.64.0.0/10
  if (a === 169 && c === 254) return true;
  if (a === 172 && c >= 16 && c <= 31) return true;
  if (a === 192 && c === 0 && b[2] === 0) return true;
  if (a === 192 && c === 168) return true;
  if (a === 198 && (c === 18 || c === 19)) return true; // 基准测试网段 198.18.0.0/15
  if (a >= 224) return true; // 组播、保留与广播
  return false;
}

function isPrivateIpv6Bytes(b: number[]): boolean {
  const zeroUntil = (end: number): boolean => {
    for (let i = 0; i < end; i++) {
      if (b[i] !== 0) return false;
    }
    return true;
  };
  const v4At = (offset: number): boolean => isPrivateIpv4Bytes(b.slice(offset, offset + 4));
  if (zeroUntil(15) && (b[15] === 0 || b[15] === 1)) return true; // :: 与 ::1
  if (zeroUntil(10) && b[10] === 0xff && b[11] === 0xff) return v4At(12); // ::ffff:a.b.c.d
  if (zeroUntil(12)) return v4At(12); // ::a.b.c.d（已废弃的兼容写法）
  if (b[0] === 0x00 && b[1] === 0x64 && b[2] === 0xff && b[3] === 0x9b) {
    if (b[4] === 0 && b[5] === 1) return true; // 64:ff9b:1::/48 本地 NAT64
    let wellKnown = true;
    for (let i = 4; i < 12; i++) {
      if (b[i] !== 0) wellKnown = false;
    }
    if (wellKnown) return v4At(12); // 64:ff9b::/96 内嵌 IPv4
  }
  if (b[0] === 0x20 && b[1] === 0x02) return v4At(2); // 6to4 2002::/16
  if ((b[0] & 0xfe) === 0xfc) return true; // 唯一本地 fc00::/7
  if (b[0] === 0xfe && (b[1] & 0xc0) === 0x80) return true; // 链路本地 fe80::/10
  if (b[0] === 0xfe && (b[1] & 0xc0) === 0xc0) return true; // 站点本地 fec0::/10
  if (b[0] === 0xff) return true; // 组播
  return false;
}

/** 是否 IP 字面量（IPv4 任意写法或 IPv6）。 */
export function isIpLiteralHost(hostWithOptionalPort: string): boolean {
  const host = splitHostPort(hostWithOptionalPort).host;
  return parseIpv6Literal(host) !== null || parseIpv4Literal(host) !== null;
}

/** 判断一个解析出来的地址（不带端口）是否落在本机、局域网或保留网段。 */
export function isPrivateIpAddress(address: string): boolean {
  const v6 = parseIpv6Literal(address);
  if (v6) return isPrivateIpv6Bytes(v6);
  const v4 = parseIpv4Literal(address);
  if (v4) return isPrivateIpv4Bytes(v4);
  return false;
}

const PRIVATE_HOSTNAME_SUFFIXES: string[] = ['.localhost', '.local', '.internal', '.home.arpa'];

/**
 * 只看字面量：本机名、局域网专用后缀与私有 IP（含十进制、十六进制、八进制与 IPv4 映射的 IPv6 写法）。
 * 普通域名解析到哪里要由宿主做 DNS 检查，见 PluginHostDispatcher。
 */
export function isPrivateOrLoopbackHost(hostWithOptionalPort: string): boolean {
  const host = splitHostPort(hostWithOptionalPort).host;
  if (!host) return true;
  if (host === 'localhost') return true;
  for (const suffix of PRIVATE_HOSTNAME_SUFFIXES) {
    if (host.endsWith(suffix)) return true;
  }
  return isPrivateIpAddress(host);
}
