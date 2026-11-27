import { getManifestContentSources, PLUGIN_PERMISSION_LABELS, PluginManifest } from '@legado/pluginengine';

/** 插件卡片和安装确认里的一条“需要的权限”。kind 决定图标。 */
export class PluginPermissionRow {
  kind: string = 'other';
  title: string = '';
  detail: string = '';
}

/**
 * 插件能力在界面上怎么说。本应用只接朗读音色（tts）和工具面板（tools）；
 * 插件包里其他扩展点照样能装，但不会生效，安装确认和详情页会单独列出来。
 */
export class PluginCapabilities {
  /** 本应用会用上的能力，做成卡片上的标签。 */
  static supported(manifest: PluginManifest): string[] {
    const out: string[] = [];
    const c = manifest.contributes;
    if (c.tts && c.tts.voices.length > 0) out.push(`朗读音色 ${c.tts.voices.length}`);
    if (c.tools && c.tools.length > 0) out.push(c.tools.length > 1 ? `工具面板 ${c.tools.length}` : '工具面板');
    return out;
  }

  /** 插件声明了、但本应用没有接的能力。 */
  static unsupported(manifest: PluginManifest): string[] {
    const out: string[] = [];
    const c = manifest.contributes;
    if (c.translation) out.push('翻译');
    if (c.readerActions && c.readerActions.length > 0) out.push('阅读菜单动作');
    if (c.contentProcessor) out.push('正文处理');
    if (c.interaction) out.push('段落互动');
    if (c.formatImporters && c.formatImporters.length > 0) out.push('格式导入');
    if (c.catalogConnectors && c.catalogConnectors.length > 0) out.push('远程书库');
    if (getManifestContentSources(manifest).length > 0) out.push('在线书源');
    if (c.sourceManager) out.push('书源管理');
    if (c.ticketStyles && c.ticketStyles.length > 0) out.push('票面样式');
    return out;
  }

  /** 安装确认里“会提供”的条目：标题与说明。 */
  static provides(manifest: PluginManifest): PluginPermissionRow[] {
    const out: PluginPermissionRow[] = [];
    const c = manifest.contributes;
    if (c.tts && c.tts.voices.length > 0) {
      const row = new PluginPermissionRow();
      row.kind = 'tts';
      row.title = `朗读音色 ${c.tts.voices.length} 款`;
      row.detail = '并入 朗读 › 音色管理 的自定义音色';
      out.push(row);
    }
    for (const tool of c.tools || []) {
      const row = new PluginPermissionRow();
      row.kind = 'tool';
      row.title = `工具面板“${tool.title}”`;
      row.detail = tool.description || '从插件管理里打开';
      out.push(row);
    }
    return out;
  }

  /** 权限逐条换成用户看得懂的话；加密存储和本地数据合成一条。 */
  static permissions(manifest: PluginManifest): PluginPermissionRow[] {
    const out: PluginPermissionRow[] = [];
    const perms = manifest.permissions;
    if (perms.includes('network')) {
      const row = new PluginPermissionRow();
      row.kind = 'network';
      row.title = manifest.domains.includes('*') ? '联网，可以访问任意网站' :
        `联网，只限 ${manifest.domains.length} 个域名`;
      row.detail = manifest.domains.includes('*') ? '' : manifest.domains.join('\n');
      out.push(row);
    }
    if (perms.includes('secrets') || perms.includes('storage')) {
      const row = new PluginPermissionRow();
      row.kind = 'storage';
      row.title = perms.includes('secrets') ? '加密存储与本地数据' : '本地数据';
      row.detail = perms.includes('secrets') ?
        '登录令牌等加密保存，插件数据放在它自己的目录；卸载时一并清除' : '插件数据放在它自己的目录；卸载时一并清除';
      out.push(row);
    }
    if (perms.includes('webview.verify')) {
      const row = new PluginPermissionRow();
      row.kind = 'web';
      row.title = '网页登录';
      row.detail = '在内置浏览器里打开登录或验证页面';
      out.push(row);
    }
    for (const perm of perms) {
      if (perm === 'network' || perm === 'secrets' || perm === 'storage' || perm === 'webview.verify' ||
        perm === 'tts') {
        continue;
      }
      const row = new PluginPermissionRow();
      row.kind = 'other';
      row.title = PLUGIN_PERMISSION_LABELS.get(perm) || perm;
      out.push(row);
    }
    return out;
  }

  static runtimeLabel(runtime: string): string {
    if (runtime === 'python') return 'Python';
    if (runtime === 'html') return 'HTML';
    if (runtime === 'declarative') return '模板';
    return 'JS';
  }

  static iconPath(rootDir: string, manifest: PluginManifest): string {
    return manifest.icon && rootDir ? `${rootDir}/${manifest.icon}` : '';
  }
}
