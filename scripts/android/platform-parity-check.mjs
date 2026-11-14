// 安卓平台层一致性检查（不需要 ArkUI-X SDK，可在 CI 上跑）：
// 1. entry/src/main/ets/platform/ 下每个文件在 android/overlay 下都有同名实现，导出的名字一致；
// 2. 安卓实现里用到的原生桥名都有对应的 Java 类，并在 EntryEntryAbilityActivity 里注册；
// 3. 共用代码不直接调已经收进平台层的系统能力（否则安卓上取到空值或整页加载失败）。
// 用法：node scripts/android/platform-parity-check.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const ETS = path.join(REPO, 'entry', 'src', 'main', 'ets');
const PLATFORM = path.join(ETS, 'platform');
const OVERLAY = path.join(REPO, 'android', 'overlay', 'entry', 'src', 'main', 'ets', 'platform');
const JAVA = path.join(REPO, 'android', 'project', 'app', 'src', 'main', 'java', 'io', 'legado', 'read');
/** 只在安卓实现里存在的辅助文件。 */
const OVERLAY_ONLY = new Set(['MediaBridgeClient.ts']);

const problems = [];
const read = (file) => fs.readFileSync(file, 'utf8');

function exportedNames(source) {
  const names = new Set();
  for (const match of source.matchAll(/^export\s+(?:async\s+)?(?:class|struct|function|const|let|enum|interface|namespace|type)\s+([A-Za-z_$][\w$]*)/gm)) {
    names.add(match[1]);
  }
  for (const match of source.matchAll(/^export\s*\{([^}]*)\}/gm)) {
    for (const part of match[1].split(',')) {
      const name = part.trim().split(/\s+as\s+/).pop();
      if (name) names.add(name);
    }
  }
  return names;
}

// 1. 两份实现一一对应
const platformFiles = fs.readdirSync(PLATFORM).filter((name) => /\.(ets|ts)$/.test(name));
const overlayFiles = fs.readdirSync(OVERLAY).filter((name) => /\.(ets|ts)$/.test(name));
for (const name of platformFiles) {
  if (!overlayFiles.includes(name)) {
    problems.push(`platform/${name} 没有安卓实现（android/overlay/.../platform/${name}）`);
    continue;
  }
  const harmony = exportedNames(read(path.join(PLATFORM, name)));
  const android = exportedNames(read(path.join(OVERLAY, name)));
  for (const symbol of harmony) {
    if (!android.has(symbol)) problems.push(`platform/${name} 导出了 ${symbol}，安卓实现里没有`);
  }
  // 安卓实现可以多导出替身要用的辅助类型，只检查缺的。
}
for (const name of overlayFiles) {
  if (!platformFiles.includes(name) && !OVERLAY_ONLY.has(name)) {
    problems.push(`android/overlay 里的 platform/${name} 在主代码树里没有对应文件`);
  }
}

// 2. 原生桥
const javaFiles = fs.readdirSync(JAVA).filter((name) => name.endsWith('.java'));
const javaBridges = new Map();
for (const name of javaFiles) {
  const match = read(path.join(JAVA, name)).match(/NAME\s*=\s*"(io\.legado\.read\/[\w-]+)"/);
  if (match) javaBridges.set(match[1], name.replace(/\.java$/, ''));
}
const activity = read(path.join(JAVA, 'EntryEntryAbilityActivity.java'));
for (const name of overlayFiles) {
  for (const match of read(path.join(OVERLAY, name)).matchAll(/'(io\.legado\.read\/[\w-]+)'/g)) {
    const cls = javaBridges.get(match[1]);
    if (!cls) {
      problems.push(`platform/${name} 用到桥 ${match[1]}，没有对应的 Java 类`);
    } else if (!new RegExp(`new ${cls}\\(`).test(activity)) {
      problems.push(`${cls} 没有在 EntryEntryAbilityActivity.onCreate 里注册`);
    }
  }
}

// 3. 共用代码里禁止的直接调用（platform/ 自身除外）
const FORBIDDEN = [
  [/from '@kit\.CoreSpeechKit'/, '@kit.CoreSpeechKit（用 platform/SpeechKit）'],
  [/from '@kit\.AVSessionKit'/, '@kit.AVSessionKit（用 platform/MediaSession）'],
  [/from '@kit\.BackgroundTasksKit'/, '@kit.BackgroundTasksKit（用 platform/BackgroundTasks）'],
  [/from '@kit\.UniversalKeystoreKit'/, '@kit.UniversalKeystoreKit（用 platform/KeystoreCipher）'],
  [/from '@kit\.UserAuthenticationKit'/, '@kit.UserAuthenticationKit（用 platform/BiometricAuth）'],
  [/import \{[^}]*\binputConsumer\b[^}]*\} from '@kit\.InputKit'/, 'inputConsumer（用 platform/KeyConsumer）'],
  [/new picker\.(DocumentViewPicker|PhotoViewPicker)\(/, '选择器（用 platform/Files 的 selectDocuments、selectImages、saveDocuments）'],
  [/\bfs\.copy\(/, 'fs.copy（用 platform/Files 的 copyFile）'],
  [/\.localeCompare\([^,()]+,\s*'/, '带区域的 localeCompare（用 platform/TextCompare 的 compareText）'],
  [/\.setWindowBrightness\(/, 'setWindowBrightness（用 platform/WindowBrightness）'],
  [/\bCookieStore\./, 'CookieStore 的静态方法（用 platform/Cookies 的 AppCookies）']
];
/** 只在鸿蒙上有意义的功能，允许直接用系统能力：碰一碰分享。 */
const ALLOWED = new Map([['utils/KnockShare.ets', ['@kit.ShareKit']]]);

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== 'platform' && entry.name !== 'types') walk(full, out);
    } else if (/\.(ets|ts)$/.test(entry.name) && !entry.name.endsWith('.d.ts')) {
      out.push(full);
    }
  }
  return out;
}

for (const file of walk(ETS)) {
  const rel = path.relative(ETS, file).replace(/\\/g, '/');
  const source = read(file);
  for (const [pattern, label] of FORBIDDEN) {
    if (pattern.test(source)) problems.push(`${rel} 直接用了 ${label}`);
  }
  // 系统共享包在安卓上一加载就终止进程：HdsTabs 只能 import lazy，类型用 import type，其它 HDS 符号从 platform/Hds 取。
  if (/^\s*import\s+(?!lazy\b|type\b)[^;]*from\s*'@kit\.UIDesignKit'/m.test(source)) {
    problems.push(`${rel} 静态引用了 @kit.UIDesignKit（HdsTabs 用 import lazy，其它从 platform/Hds 取）`);
  }
  if (/from '@kit\.ShareKit'/.test(source) && !(ALLOWED.get(rel) || []).includes('@kit.ShareKit')) {
    problems.push(`${rel} 直接用了 @kit.ShareKit（用 platform/Share）`);
  }
}

if (problems.length > 0) {
  console.error(`安卓平台层检查发现 ${problems.length} 处问题：\n` + problems.map((item) => `  - ${item}`).join('\n'));
  process.exit(1);
}
console.log(`安卓平台层检查通过：${platformFiles.length} 个平台文件，${javaBridges.size} 个原生桥`);
