import { PluginManifest } from '../spec/PluginManifest';
import { formatSignerFingerprint } from './PluginSignature';

/**
 * 安装与升级的信任规则。
 *
 * - 签名者在首次安装时绑定到插件 id；已签名的插件只接受同一签名者的升级。
 *   换签名者或去掉签名一律拒绝：同 id 的包会继承原插件的 KV、data/ 与密钥库凭据，
 *   放行就等于把这些数据交给了别人。确实要更换，先卸载原插件（会清空这些数据）。
 * - 不允许降级；同版本可以重装。
 * - 未签名的包可以安装（开发调试与自用插件），但预览会明确提示无法确认作者。
 * - 官方命名空间：OFFICIAL_SIGNER_FINGERPRINTS 非空时，id 以 OFFICIAL_PLUGIN_ID_PREFIXES 开头的插件
 *   必须由其中之一签名，首次安装也不例外。
 */

export const OFFICIAL_PLUGIN_ID_PREFIXES: string[] = ['io.qingye.'];

/**
 * 官方签名公钥指纹（小写十六进制 SHA-256）。用 `qyplugin keygen` 生成密钥后，
 * 把输出的指纹填到这里即可启用官方命名空间保护；留空时不启用。
 */
export const OFFICIAL_SIGNER_FINGERPRINTS: ReadonlySet<string> = new Set<string>([]);

export interface PluginInstallBaseline {
  version: string;
  /** 已绑定的签名者指纹；未签名为空串。 */
  signer: string;
  permissions: string[];
  domains: string[];
}

export interface PluginTrustDecision {
  /** 需要用户在安装预览里看到的提示。 */
  notes: string[];
  addedPermissions: string[];
  addedDomains: string[];
}

interface ParsedVersion {
  nums: number[];
  pre: string[];
}

function parseVersion(v: string): ParsedVersion {
  const m = /^(\d+)\.(\d+)(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?$/.exec(v.trim());
  if (!m) return { nums: [0, 0, 0], pre: [] };
  return {
    nums: [Number(m[1]), Number(m[2]), Number(m[3] ?? 0)],
    pre: m[4] ? m[4].split('.') : []
  };
}

/** 语义化版本比较：返回负数表示 a 低于 b。预发布版本低于同号正式版。 */
export function comparePluginVersions(a: string, b: string): number {
  const pa = parseVersion(a);
  const pb = parseVersion(b);
  for (let i = 0; i < 3; i++) {
    if (pa.nums[i] !== pb.nums[i]) return pa.nums[i] - pb.nums[i];
  }
  if (pa.pre.length === 0 || pb.pre.length === 0) {
    return (pa.pre.length === 0 ? 1 : 0) - (pb.pre.length === 0 ? 1 : 0);
  }
  const len = Math.max(pa.pre.length, pb.pre.length);
  for (let i = 0; i < len; i++) {
    const x = pa.pre[i];
    const y = pb.pre[i];
    if (x === undefined) return -1;
    if (y === undefined) return 1;
    const xn = /^\d+$/.test(x);
    const yn = /^\d+$/.test(y);
    if (xn && yn) {
      if (Number(x) !== Number(y)) return Number(x) - Number(y);
    } else if (xn !== yn) {
      return xn ? -1 : 1;
    } else if (x !== y) {
      return x < y ? -1 : 1;
    }
  }
  return 0;
}

export function isOfficialPluginId(pluginId: string): boolean {
  return OFFICIAL_PLUGIN_ID_PREFIXES.some((prefix) => pluginId.startsWith(prefix));
}

/** 按上面的规则决定能否安装；不能安装时抛出给用户看的原因。 */
export function evaluateInstallTrust(
  manifest: PluginManifest,
  signer: string,
  baseline: PluginInstallBaseline | undefined,
  officialSigners: ReadonlySet<string> = OFFICIAL_SIGNER_FINGERPRINTS
): PluginTrustDecision {
  const notes: string[] = [];

  if (officialSigners.size > 0 && isOfficialPluginId(manifest.id) && !officialSigners.has(signer)) {
    throw new Error(`"${manifest.id}" 属于官方插件命名空间，只接受官方签名的安装包`);
  }

  if (!baseline) {
    if (!signer) notes.push('安装包未签名，无法确认作者身份；请只安装来自可信来源的插件');
    return { notes, addedPermissions: [], addedDomains: [] };
  }

  if (baseline.signer) {
    if (!signer) {
      throw new Error('已安装版本带有签名，这个升级包却没有签名，可能是他人仿冒的同名插件；如确认要更换，请先卸载原插件（会清除其数据）');
    }
    if (signer !== baseline.signer) {
      throw new Error(
        `升级包的签名者（${formatSignerFingerprint(signer)}）与已安装版本（${formatSignerFingerprint(baseline.signer)}）不同，` +
        '可能是他人仿冒的同名插件；如确认要更换，请先卸载原插件（会清除其数据）'
      );
    }
  } else if (signer) {
    notes.push('原版本未签名，升级后将绑定这个签名者，之后只接受同一签名的升级');
  } else {
    notes.push('新旧版本都未签名，无法确认升级包来自原作者；升级后它会继承原插件的数据与凭据');
  }

  if (comparePluginVersions(manifest.version, baseline.version) < 0) {
    throw new Error(`不能降级：已安装 ${baseline.version}，安装包是 ${manifest.version}；如需回退请先卸载`);
  }

  const addedPermissions = manifest.permissions.filter((p) => !baseline.permissions.includes(p));
  const addedDomains = manifest.domains.filter((d) => !baseline.domains.includes(d));
  return { notes, addedPermissions, addedDomains };
}
