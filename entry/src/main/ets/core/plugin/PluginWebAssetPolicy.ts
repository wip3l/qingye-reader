import { normalizeSafePluginRelPath } from '@legado/pluginengine';

export const PLUGIN_VIRTUAL_ORIGIN: string = 'https://plugin.qingye.local';

export interface ResolvedPluginWebAsset {
  pluginId: string;
  relPath: string;
  mimeType: string;
}

const MIME_BY_EXT: ReadonlyMap<string, string> = new Map<string, string>([
  ['html', 'text/html; charset=utf-8'],
  ['htm', 'text/html; charset=utf-8'],
  ['css', 'text/css; charset=utf-8'],
  ['js', 'application/javascript; charset=utf-8'],
  ['mjs', 'application/javascript; charset=utf-8'],
  ['json', 'application/json; charset=utf-8'],
  ['svg', 'image/svg+xml'],
  ['png', 'image/png'],
  ['jpg', 'image/jpeg'],
  ['jpeg', 'image/jpeg'],
  ['webp', 'image/webp'],
  ['gif', 'image/gif'],
  ['woff2', 'font/woff2'],
  ['woff', 'font/woff'],
  ['ttf', 'font/ttf'],
  ['txt', 'text/plain; charset=utf-8']
]);

export class PluginWebAssetPolicy {
  static buildPanelUrl(pluginId: string, panelRelPath: string): string {
    const cleanRel = normalizeSafePluginRelPath(panelRelPath);
    return `${PLUGIN_VIRTUAL_ORIGIN}/${encodeURIComponent(pluginId)}/${cleanRel}`;
  }

  static allowsNavigation(url: string, expectedPluginId: string): boolean {
    if (!url) return false;
    if (url === 'about:blank' || url === 'about:srcdoc') return true;
    const resolved = PluginWebAssetPolicy.resolveVirtualAsset(url, expectedPluginId);
    return resolved !== null;
  }

  static allowsInlineDataUrl(url: string): boolean {
    const trimmed = url.trim().toLowerCase();
    return (
      trimmed.startsWith('data:image/png;') ||
      trimmed.startsWith('data:image/jpeg;') ||
      trimmed.startsWith('data:image/webp;') ||
      trimmed.startsWith('data:image/gif;') ||
      trimmed.startsWith('data:image/svg+xml;')
    );
  }

  static resolveVirtualAsset(url: string, expectedPluginId: string): ResolvedPluginWebAsset | null {
    if (!url || !expectedPluginId) return null;
    const prefix = `${PLUGIN_VIRTUAL_ORIGIN}/`;
    if (!url.startsWith(prefix)) return null;

    let rest = url.slice(prefix.length);
    const hashIdx = rest.indexOf('#');
    if (hashIdx >= 0) rest = rest.slice(0, hashIdx);
    const queryIdx = rest.indexOf('?');
    if (queryIdx >= 0) rest = rest.slice(0, queryIdx);

    const slashIdx = rest.indexOf('/');
    if (slashIdx <= 0) return null;

    let decodedId = '';
    let decodedRel = '';
    try {
      decodedId = decodeURIComponent(rest.slice(0, slashIdx));
      decodedRel = decodeURIComponent(rest.slice(slashIdx + 1));
    } catch (_) {
      return null;
    }
    if (decodedId !== expectedPluginId) return null;

    let cleanRel = '';
    try {
      cleanRel = normalizeSafePluginRelPath(decodedRel);
    } catch (_) {
      return null;
    }

    // Only allow static assets (or explicitly declared root HTML panels), never data/ or main scripts!
    if (cleanRel.startsWith('data/') || cleanRel === 'manifest.json') {
      return null;
    }
    const dotIdx = cleanRel.lastIndexOf('.');
    const ext = dotIdx >= 0 ? cleanRel.slice(dotIdx + 1).toLowerCase() : '';
    const mimeType = MIME_BY_EXT.get(ext);
    if (!mimeType) return null;
    if (!cleanRel.startsWith('assets/') && ext !== 'html' && ext !== 'htm') {
      return null;
    }

    return {
      pluginId: decodedId,
      relPath: cleanRel,
      mimeType
    };
  }
}
