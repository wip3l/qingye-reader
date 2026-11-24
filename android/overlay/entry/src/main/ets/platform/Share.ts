// platform/Share.ts 的安卓实现：经原生桥（ShareBridge.java）用系统分享面板，图片存进相册的 Pictures/开源轻页。
import bridge from '@arkui-x.bridge';
import { common } from '@kit.AbilityKit';

/** 与 ShareBridge.NAME 一致。 */
const SHARE_BRIDGE_NAME = 'io.legado.read/share';

const MIME_BY_EXTENSION: Record<string, string> = {
  png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', webp: 'image/webp', gif: 'image/gif',
  txt: 'text/plain', json: 'application/json', zip: 'application/zip', epub: 'application/epub+zip',
  pdf: 'application/pdf'
};

export interface ShareFile {
  path: string;
  utd: string;
  title?: string;
}

let shareBridge: bridge.BridgeObject | null = null;

async function call(method: string, payload: Object): Promise<Record<string, Object>> {
  if (!shareBridge) shareBridge = bridge.createBridge(SHARE_BRIDGE_NAME);
  const raw = await shareBridge.callMethod(method, JSON.stringify(payload));
  const result = JSON.parse(String(raw)) as Record<string, Object>;
  if (result['error']) throw new Error(String(result['error']));
  return result;
}

function mimeOf(file: ShareFile): string {
  const name = file.path.substring(file.path.lastIndexOf('/') + 1);
  const extension = name.includes('.') ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : '';
  if (MIME_BY_EXTENSION[extension]) return MIME_BY_EXTENSION[extension];
  if (file.utd.includes('image')) return 'image/*';
  if (file.utd.includes('text')) return 'text/plain';
  return 'application/octet-stream';
}

export async function shareFiles(_context: common.UIAbilityContext, files: ShareFile[], _detailPreview: boolean):
  Promise<void> {
  if (files.length === 0) return;
  const mimes = Array.from(new Set(files.map((file: ShareFile): string => mimeOf(file))));
  const mime = mimes.length === 1 ? mimes[0] : (mimes.every((item: string): boolean => item.startsWith('image/')) ?
    'image/*' : '*/*');
  await call('shareFiles', { paths: files.map((file: ShareFile): string => file.path), mime: mime,
    title: files[0].title || '' });
}

export async function saveImages(_context: common.Context, paths: string[], extension: string): Promise<boolean> {
  const mime = MIME_BY_EXTENSION[extension.toLowerCase()] || 'image/png';
  const result = await call('saveImages', { paths: paths, mime: mime });
  return Number(result['saved'] || 0) > 0;
}
