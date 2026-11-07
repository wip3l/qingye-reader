// Visual review board assembled from the shipped images and SVGs; not a device screenshot.
import { readFileSync, mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { loadObsidianReader } from './lib/obsidian-reader-fixture.mjs';
const require = createRequire(import.meta.url);
const sharp = require('../server/node_modules/sharp');
const root = 'entry/src/main/resources/base/media/';
const output = 'output/obsidian-archive-v2';
mkdirSync(output, { recursive: true });
const svg = (w, h, content) => Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${content}</svg>`);
const text = (x, y, value, size = 18, color = '#DED6C8', extra = '') =>
  `<text x="${x}" y="${y}" font-family="Microsoft YaHei, sans-serif" font-size="${size}" fill="${color}" ${extra}>${value}</text>`;
const panels = [
  { x: 40, bg: '#F8F3E9', fg: '#302C26', accent: '#806534', secondary: '#746B5D', bubble: '#292620', ink: '#F2DEAE', name: '象牙浅色' },
  { x: 740, bg: '#191B1F', fg: '#DED6C8', accent: '#D6B878', secondary: '#AEA492', bubble: '#463B2A', ink: '#F4E3BF', name: '曜黑深色' }
];
// Resolve the colours through theme application and the actual reader context.
const {ThemeRuntime:runtime,ReaderHarness,store}=loadObsidianReader();
runtime.applyTheme('obsidian-archive');
const reader=new ReaderHarness();
panels.forEach((panel,index)=>{
  reader.appDarkMode=index===1;store.set('appDarkMode',index===1);
  const style=reader.buildReaderV2RegexStyleTemplate({});
  const hex=n=>'#'+(n>>>0).toString(16).padStart(8,'0').slice(2);
  panel.bubble=hex(style.backgroundColor);panel.ink=hex(style.color);
});
const labels = ['流金书页', '山河长卷', '月下航帆', '银杏书签', '星海鲸游', '远山飞鸟'];
let body = '<rect width="1440" height="1060" fill="#111315"/>' +
  text(40, 64, '曜金藏书', 34, '#E8D5AD') + text(40, 100, '六幅装帧艺术 · 开卷导航 · 曜金藏签', 17, '#AEA492') +
  '<path d="M40 122H1400" stroke="#534632"/>';
for (let i = 0; i < 6; i++) body += text(40 + i * 230, 489, `0${i + 1}  ${labels[i]}`, 17);
for (const p of panels) {
  body += `<rect x="${p.x}" y="530" width="660" height="450" rx="20" fill="${p.bg}"/>` +
    text(p.x + 28, 575, p.name, 20, p.fg) +
    text(p.x + 28, 612, '开卷书架 / 折页罗盘 / 寻书镜 / 藏书印', 14, p.secondary) +
    text(p.x + 28, 787, '把一段心动，留在书页之间。', 22, p.fg) +
    text(p.x + 28, 836, '每一页，都有', 22, p.fg) +
    `<path d="M${p.x+179} 811H${p.x+359}Q${p.x+368} 811 ${p.x+368} 820V844Q${p.x+368} 846 ${p.x+366} 846H${p.x+187}Q${p.x+178} 846 ${p.x+178} 837V813Q${p.x+178} 811 ${p.x+179} 811Z" fill="${p.bubble}"/>` +
    text(p.x + 210, 836, '值得珍藏', 22, p.ink) +
    text(p.x + 382, 836, '的光。', 22, p.fg) +
    text(p.x + 28, 900, '折角藏书签 · 非对称边角 · 墨底香槟字', 14, p.secondary);
  ['书架', '发现', '搜索', '我的'].forEach((name, i) => {
    body += text(p.x + 81 + i * 148, 709, name, 14, i === 0 ? p.accent : p.secondary, 'text-anchor="middle"');
  });
  body += text(p.x + 28, 954, '实际 24 px 图标', 12, p.secondary);
}
body += text(40, 1021, '使用实际资源合成的设计预览；封面已接入主题轮播。', 14, '#8C8B85');
const layers = [{ input: svg(1440, 1060, body), left: 0, top: 0 }];
for (let i = 0; i < 6; i++) {
  layers.push({ input: await sharp(`${root}theme_cover_obsidian_archive_0${i + 1}.jpg`).resize(210, 308).toBuffer(), left: 40 + i * 230, top: 150 });
}
const names = ['bookshelf', 'explore', 'mine'];
for (const p of panels) {
  for (let i = 0; i < names.length; i++) {
    const source = readFileSync(`${root}ic_theme_obsidian_archive_${names[i]}.svg`, 'utf8').replaceAll('#000000', i === 0 ? p.accent : p.secondary);
    layers.push({ input: await sharp(Buffer.from(source)).resize(40, 40).png().toBuffer(), left: p.x + 61 + i * 148, top: 643 });
    layers.push({ input: await sharp(Buffer.from(source)).resize(24, 24).png().toBuffer(), left: p.x + 160 + i * 64, top: 936 });
  }
  const cap = await sharp(`${root}regex_cap_gilded_orbit.svg`).resize(24, 24).png().toBuffer();
  layers.push({ input: cap, left: p.x + 182, top: 817 });
  layers.push({ input: await sharp(cap).rotate(180).png().toBuffer(), left: p.x + 340, top: 817 });
}
await sharp({ create: { width: 1440, height: 1060, channels: 3, background: '#111315' } })
  .composite(layers).png().toFile(`${output}/theme-refresh-preview.png`);
console.log(`${output}/theme-refresh-preview.png`);
