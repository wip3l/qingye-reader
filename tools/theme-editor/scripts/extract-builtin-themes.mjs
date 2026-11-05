// 从应用源码抽出内置主题的令牌（配色、阅读色、强调、圆角）和气泡样式名，供编辑器做基底主题的回退预览。
// 只取令牌，不取素材：内置主题的图片是应用内的付费内容，编辑器不带。
// node scripts/extract-builtin-themes.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..', '..', '..');
const themeDir = path.join(repo, 'entry', 'src', 'main', 'ets', 'theme');
const readSource = (name) => fs.readFileSync(path.join(themeDir, name), 'utf8').replace(/\r\n/g, '\n');
const registry = readSource('BuiltinThemeRegistry.ets');
const models = readSource('ThemeModels.ets');

function constants(className) {
  const start = models.indexOf(`export class ${className} {`);
  if (start < 0) throw new Error(`ThemeModels.ets 里找不到 ${className}`);
  const end = models.indexOf('\n}', start);
  const map = {};
  for (const m of models.substring(start, end).matchAll(/static readonly (\w+): string = '([^']*)'/g)) map[m[1]] = m[2];
  return map;
}

const themeIds = constants('ThemeIds');
const bubbleIds = constants('ThemeBubbleStyles');
const labelStart = models.indexOf('export class ThemeBubbleStyleLabels');
const labelBody = models.substring(labelStart, models.indexOf('\n}', labelStart));
const bubbleLabels = {};
for (const m of labelBody.matchAll(/id === '([^']+)'\) return '([^']+)'/g)) bubbleLabels[m[1]] = m[2];

const resolve = (token, map, label) => {
  const m = /^\w+\.(\w+)$/.exec(token.trim());
  if (m && m[1] in map) return map[m[1]];
  const literal = /^'([^']*)'$/.exec(token.trim());
  if (literal) return literal[1];
  throw new Error(`无法解析${label}：${token}`);
};
const args = (text) => text.split(',').map((s) => s.trim()).filter(Boolean);
const strings = (text) => args(text).map((s) => s.replace(/^'|'$/g, ''));

const themes = [];
const order = [...registry.matchAll(/themes\.push\(BuiltinThemeRegistry\.(\w+)\(\)\)/g)].map((m) => m[1]);
for (const method of order) {
  const start = registry.indexOf(`private static ${method}(): ThemePack {`);
  if (start < 0) throw new Error(`找不到 ${method}()`);
  const end = registry.indexOf('\n  }\n', start);
  const body = registry.substring(start, end);
  const head = /BuiltinThemeRegistry\.theme\(\s*([\w.]+),\s*'([^']*)',\s*'([^']*)',\s*'([^']*)',\s*'([^']*)'/s.exec(body);
  if (!head) throw new Error(`${method}() 的 theme(...) 无法解析`);
  const variants = [...body.matchAll(/BuiltinThemeRegistry\.variant\(\s*BuiltinThemeRegistry\.colors\(([^)]*)\),\s*BuiltinThemeRegistry\.reader\(([^)]*)\),\s*BuiltinThemeRegistry\.regex\(([^)]*)\)/gs)];
  if (variants.length !== 2) throw new Error(`${method}() 的浅深变体数量不是 2`);
  const variant = (m) => {
    const c = strings(m[1]);
    const r = strings(m[2]);
    const e = args(m[3]);
    const keys = ['pageColor', 'cardColor', 'inputColor', 'primaryTextColor', 'subTextColor', 'dividerColor', 'accentColor', 'buttonColor', 'dangerColor'];
    return {
      colors: Object.fromEntries(keys.map((k, i) => [k, c[i]])),
      reader: { backgroundColor: r[0], hasArtwork: !!r[1], textColor: r[2], subTextColor: r[3], contentTone: r[4] },
      emphasis: { mode: 'bubble', bubbleStyle: resolve(e[0], bubbleIds, '气泡样式'), color: e[1].replace(/'/g, ''), textColor: e[2].replace(/'/g, '') }
    };
  };
  const radius = /BuiltinThemeRegistry\.radius\(([^)]*)\)/.exec(body);
  const r = radius ? args(radius[1]).map(Number) : [6, 12, 20, 12, 24, 8];
  themes.push({
    id: resolve(head[1], themeIds, '主题 ID'),
    name: head[2],
    fontFamily: head[4],
    iconPack: head[5],
    light: variant(variants[0]),
    dark: variant(variants[1]),
    radius: { small: r[0], medium: r[1], large: r[2], card: r[3], button: r[4], bubble: r[5] }
  });
}
if (!themes.length || themes[0].id !== 'plain-default') throw new Error('第一个内置主题应是 plain-default');

const bubbles = Object.values(bubbleIds).filter((id) => id !== 'inherit').map((id) => ({ id, label: bubbleLabels[id] || id }));
const out = path.join(here, '..', 'src', 'core', 'builtinThemes.json');
const json = JSON.stringify({ themes, bubbles }, null, 2) + '\n';
if (!fs.existsSync(out) || fs.readFileSync(out, 'utf8') !== json) fs.writeFileSync(out, json);
console.log(`内置主题 ${themes.length} 套，气泡样式 ${bubbles.length} 种 → ${path.relative(process.cwd(), out)}`);
