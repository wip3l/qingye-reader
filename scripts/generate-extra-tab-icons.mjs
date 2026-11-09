// 首页第四个页签（听 / 足迹）的各主题底栏图标。经典主题用 ic_tab_listen / ic_tab_footprint，
// 星穹御藏是位图（scripts/generate-celestial-extra-tab-icons.py），其余图标包都在这里。
// 底栏用 fillColor 给 SVG 着色，只对填充轮廓可靠：线条先用 pathkit 描成轮廓再写出。
// 依赖：npm install --prefix output/obsidian-vector-tools --no-save pathkit-wasm
// 运行：node scripts/generate-extra-tab-icons.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const root = new URL('../entry/src/main/resources/base/media/', import.meta.url);
const require = createRequire(import.meta.url);
const init = require('../output/obsidian-vector-tools/node_modules/pathkit-wasm/bin/pathkit.js');
const pk = await init({ wasmBinary: readFileSync(new URL('../output/obsidian-vector-tools/node_modules/pathkit-wasm/bin/pathkit.wasm', import.meta.url)) });

const n = (v) => +v.toFixed(2);
/** 圆角矩形。 */
const rr = (x, y, w, h, r) => `M${n(x + r)} ${n(y)}H${n(x + w - r)}A${r} ${r} 0 0 1 ${n(x + w)} ${n(y + r)}V${n(y + h - r)}` +
  `A${r} ${r} 0 0 1 ${n(x + w - r)} ${n(y + h)}H${n(x + r)}A${r} ${r} 0 0 1 ${n(x)} ${n(y + h - r)}V${n(y + r)}A${r} ${r} 0 0 1 ${n(x + r)} ${n(y)}Z`;
/** 椭圆，deg 为长轴的旋转角度。 */
const ell = (cx, cy, rx, ry, deg = 0) => {
  const a = deg * Math.PI / 180;
  const dx = rx * Math.cos(a);
  const dy = rx * Math.sin(a);
  return `M${n(cx - dx)} ${n(cy - dy)}A${rx} ${ry} ${deg} 1 0 ${n(cx + dx)} ${n(cy + dy)}A${rx} ${ry} ${deg} 1 0 ${n(cx - dx)} ${n(cy - dy)}Z`;
};
const circle = (cx, cy, r) => ell(cx, cy, r, r);
/** 墨夜书阁的弧边四角星。 */
const qstar = (x, y, s) => `M${x} ${n(y - s)}Q${x} ${y} ${n(x + s)} ${y}Q${x} ${y} ${x} ${n(y + s)}Q${x} ${y} ${n(x - s)} ${y}Q${x} ${y} ${x} ${n(y - s)}Z`;
/** 直边四角星，k 是腰部收进的比例。 */
const spark = (x, y, s, k = 0.28) => {
  const t = s * k;
  return `M${x} ${n(y - s)}L${n(x + t)} ${n(y - t)}L${n(x + s)} ${y}L${n(x + t)} ${n(y + t)}L${x} ${n(y + s)}` +
    `L${n(x - t)} ${n(y + t)}L${n(x - s)} ${y}L${n(x - t)} ${n(y - t)}Z`;
};

const F = (d, evenodd = false) => ({ d, evenodd });
const S = (d, w, cap = 'round', join = 'round') => ({ d, stroke: { w, cap, join } });

function outline(el) {
  if (!el.stroke) return el;
  const p = pk.FromSVGString(el.d);
  const cap = { round: pk.StrokeCap.ROUND, butt: pk.StrokeCap.BUTT, square: pk.StrokeCap.SQUARE }[el.stroke.cap];
  const join = { round: pk.StrokeJoin.ROUND, miter: pk.StrokeJoin.MITER, bevel: pk.StrokeJoin.BEVEL }[el.stroke.join];
  if (!p || !p.stroke({ width: el.stroke.w, cap, join, miter_limit: 4 })) throw new Error('Cannot outline ' + el.d);
  const d = p.toSVGString();
  p.delete();
  return { d, evenodd: false };
}

function save(name, elements) {
  const body = elements.map(outline).map((el) =>
    `<path${el.evenodd ? ' fill-rule="evenodd"' : ''} d="${el.d}"/>`).join('');
  writeFileSync(new URL(`${name}.svg`, root),
    `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="#000000">${body}</g></svg>\n`);
}

const icons = {};

// 圆润：粗圆头线条，耳罩实心。
icons.rounded = {
  listen: [S('M4.75 14.5V12a7.25 7.25 0 0 1 14.5 0v2.5', 2), F(rr(3, 13, 5, 8, 1.9)), F(rr(16, 13, 5, 8, 1.9))],
  footprint: [S(rr(4, 12.5, 3.5, 7.5, 1.4), 2), S(rr(10.25, 4, 3.5, 16, 1.4), 2), S(rr(16.5, 8.5, 3.5, 11.5, 1.4), 2)]
};

// 水墨：两头收细的墨线、实心墨块，配两颗墨点。
icons.ink = {
  listen: [
    F('M3.6 14.6C3.2 8.4 7 3.4 12.1 3.3c5.2-.1 8.6 4.6 8.3 11.2l-1.9.1c.4-5.4-2.4-9.2-6.4-9.1-3.9.1-6.8 4.1-6.5 9.1Z'),
    F('M4.4 13.2c1.6-.4 3.3.2 3.6 1.6l.6 3.9c.2 1.5-.9 2.6-2.4 2.6-1.3.1-2.5-.7-2.7-2l-.5-3.6c-.2-1.2.3-2.2 1.4-2.5Z'),
    F('M19.7 13.2c-1.6-.4-3.3.2-3.6 1.6l-.6 3.9c-.2 1.5.9 2.6 2.4 2.6 1.3.1 2.5-.7 2.7-2l.5-3.6c.2-1.2-.3-2.2-1.4-2.5Z'),
    F(circle(2.2, 7.9, 0.75)), F(circle(21.4, 20.7, 0.7))
  ],
  footprint: [
    F(ell(7.4, 13.2, 2.4, 3.6, -10)), F(ell(8.2, 19.2, 1.75, 1.6, -10)),
    F(ell(16.4, 5.6, 2.4, 3.6, 10)), F(ell(15.6, 11.6, 1.75, 1.6, 10)),
    F(circle(20.9, 17.4, 0.75)), F(circle(3.2, 4.4, 0.7))
  ]
};

// 草莓：圆胖实心，顶上一片叶子。
icons.strawberry = {
  listen: [
    S('M4.5 14.5V12.5a7.5 7.5 0 0 1 15 0v2', 2.3, 'butt'),
    F(rr(2.8, 13, 5.4, 8.5, 2.4)), F(rr(15.8, 13, 5.4, 8.5, 2.4)),
    F('M12 4.6c-.4-2.3.9-3.6 3.6-3.6-.1 2.3-1.3 3.6-3.6 3.6Z')
  ],
  footprint: [
    F(ell(7.5, 16.5, 2.6, 3.7)), F(circle(5.3, 11.3, 0.95)), F(circle(7.6, 10.6, 1.05)), F(circle(9.8, 11.4, 0.9)),
    F(ell(16.5, 9, 2.6, 3.7)), F(circle(14.3, 3.8, 0.95)), F(circle(16.6, 3.1, 1.05)), F(circle(18.8, 3.9, 0.9))
  ]
};

// 绯红：锐角折线与菱形。
icons.crimson = {
  listen: [
    F('M3 14V9.8L7.2 3h9.6L21 9.8V14h-2.4v-3.5L15.4 5.4H8.6L5.4 10.5V14Z'),
    F('M2 12.5h6v9H3.5L2 20Z'), F('M22 12.5h-6v9h4.5l1.5-1.5Z')
  ],
  footprint: [
    F('M2 14h5v5H2ZM9.5 9.5h5V19h-5ZM17 6h5v13h-5ZM1 20h22v2H1Z'),
    F('M19.5 0.6 21.6 2.7 19.5 4.8 17.4 2.7Z')
  ]
};

// 梅影：方框里放图形，与“书架”“我的”同一套框。
icons.plum = {
  listen: [
    F('M3 3h18v18H3V3Zm3 3v12h12V6H6Z', true),
    S('M8.6 15v-2.4a3.4 3.4 0 0 1 6.8 0V15', 1.6, 'butt'),
    F('M7.6 13h2.6v4H7.6ZM13.8 13h2.6v4h-2.6Z')
  ],
  footprint: [
    F('M3 3h18v18H3V3Zm3 3v12h12V6H6Z', true),
    F('M7.5 13h2.4v3.5H7.5ZM10.8 8h2.4v8.5h-2.4ZM14.1 10.5h2.4v6h-2.4Z')
  ]
};

// 玫瑰：实心图形配一朵小花。
icons.rose = {
  listen: [
    S('M4.5 15.5v-2a6.5 6.5 0 0 1 13 0v2', 2, 'butt'),
    F(rr(2.5, 14, 5, 8, 1.6)), F(rr(14.5, 14, 5, 8, 1.6)),
    F('M18 4c2-3 5 0 3 2 3 1 1 4-1 3-1 3-4 1-3-1-3-1-1-4 1-4Z')
  ],
  footprint: [
    F('M2 13h4v8H2ZM8 9h4v12H8ZM14 12h4v9h-4Z'),
    F('M18 4c2-3 5 0 3 2 3 1 1 4-1 3-1 3-4 1-3-1-3-1-1-4 1-4Z')
  ]
};

// 鹤鸣：方块实心；足迹是两枚鸟爪印。
const craneTrack = (x, y, s) => S(`M${x} ${n(y + 3.6 * s)}V${y}M${x} ${y}L${n(x - 3 * s)} ${n(y - 3.4 * s)}M${x} ${y}V${n(y - 4.6 * s)}M${x} ${y}L${n(x + 3 * s)} ${n(y - 3.4 * s)}`, 2.1);
icons.crane = {
  listen: [
    S('M5 14v-2a7 7 0 0 1 14 0v2', 2.2, 'butt'),
    F('M3 13h5v8H3ZM16 13h5v8h-5Z')
  ],
  footprint: [craneTrack(6.6, 16.2, 1.25), craneTrack(17.2, 7.4, 1.25)]
};

// 剑霜：棱角头梁，足迹是三柄剑形柱。
icons.sword_frost = {
  listen: [
    F('M3 15V10.6L6.6 4h10.8L21 10.6V15h-2.2v-3.9L16.1 6.2H7.9L5.2 11.1V15Z'),
    F('M3 13h5.2v8H3ZM15.8 13H21v8h-5.2Z'),
    F('M12 .8 13.3 2.6 12 4.4 10.7 2.6Z')
  ],
  footprint: [
    F('M4 19v-7l2-3 2 3v7ZM10 19V7l2-3 2 3v12ZM16 19v-9l2-3 2 3v9ZM3 20h18v2H3Z')
  ]
};

// 青鸾：柔和线条与水纹。
icons.qingluan_water = {
  listen: [
    S('M4.6 14.5v-2a7.4 7.4 0 0 1 14.8 0v2', 1.9, 'butt'),
    F(rr(3, 13, 4.8, 8, 1.6)), F(rr(16.2, 13, 4.8, 8, 1.6)),
    S('M9.2 10.2c.93-.7 1.87-.7 2.8 0s1.87.7 2.8 0', 1.4)
  ],
  footprint: [
    F(rr(4, 12, 4, 7, 1.2)), F(rr(10, 5, 4, 14, 1.2)), F(rr(16, 8.5, 4, 10.5, 1.2)),
    S('M2.5 21.5c1.6-1.1 3.2-1.1 4.8 0s3.2 1.1 4.8 0 3.2-1.1 4.8 0 3.2 1.1 4.8 0', 1.5)
  ]
};

// 猫咪皮皮：头梁带一对猫耳；足迹是猫爪印。
icons.cat_pipi = {
  listen: [
    S('M4.6 14.5V12.6a7.4 7.4 0 0 1 14.8 0v1.9', 2.2, 'butt'),
    F('M5.2 8.6 5.5 2.6 9.6 5.6Z'), F('M18.8 8.6 18.5 2.6 14.4 5.6Z'),
    F(rr(2.8, 13, 5.2, 8.5, 2)), F(rr(16, 13, 5.2, 8.5, 2))
  ],
  footprint: [
    F('M12 11.8c-3.2 0-5.9 2.8-5.9 5.6 0 2 1.5 3.1 3.2 3.1 1.1 0 1.7-.6 2.7-.6s1.6.6 2.7.6c1.7 0 3.2-1.1 3.2-3.1 0-2.8-2.7-5.6-5.9-5.6Z'),
    F(ell(4.9, 10.6, 1.65, 2.2, 70)), F(ell(9, 6.4, 1.8, 2.4, 82)), F(ell(15, 6.4, 1.8, 2.4, 98)), F(ell(19.1, 10.6, 1.65, 2.2, 110))
  ]
};

// 苍蓝机甲：切角块面，耳机带麦克风。
icons.azure_mecha = {
  listen: [
    F('M4 13V8.6L7.8 3h8.4L20 8.6V13h-2.2V9.4L15 5.2H9L6.2 9.4V13Z'),
    F('M3 11.5h5.5v8H5l-2-2ZM21 11.5h-5.5v8H19l2-2Z'),
    F('M5 19.5h1.8v.7H12V22H5Z')
  ],
  footprint: [
    F('M3 19v-5.5L4.5 12H7.5v7ZM10 19V8.5L11.5 7h3v12ZM17 19V4.5L18.5 3h3v16ZM2 20h20v2H2Z')
  ]
};

// 星愿魔法：实心图形挖出星芒；足迹是一串由小到大的星。
icons.starwish_magic = {
  listen: [
    F(`M4.5 14.5V12.5a7.5 7.5 0 0 1 15 0v2h-2.2v-2a5.3 5.3 0 0 0-10.6 0v2Z`),
    F(rr(2.8, 13, 5.4, 8.5, 1.6)), F(rr(15.8, 13, 5.4, 8.5, 1.6)),
    F(spark(12, 1.9, 1.9, 0.3))
  ],
  footprint: [
    F(spark(5, 18.5, 2.6, 0.3)), F(spark(11.5, 12.2, 3.4, 0.3)), F(spark(18.5, 5.5, 4.4, 0.3)),
    F(circle(8.2, 15.6, 0.7)), F(circle(14.9, 8.9, 0.75))
  ]
};

// 铅字书页：方块与小横线刻痕。
icons.letterpress_page = {
  listen: [
    F('M4 13V4h16v9h-2.5V6.5h-11V13Z'),
    F('M3 12h5.5v9.5H3ZM4.5 14v1.5h2.5V14Z', true),
    F('M15.5 12H21v9.5h-5.5ZM17 14v1.5h2.5V14Z', true)
  ],
  footprint: [
    F('M3 21v-7h4v7ZM4 16v1.5h2V16Z', true),
    F('M10 21V10h4v11ZM11 12v1.5h2V12Z', true),
    F('M17 21V4h4v17ZM18 6v1.5h2V6Z', true)
  ]
};

// 霓虹港湾：简洁多边形，书架同款底线。
icons.neon_harbor = {
  listen: [
    F('M4 14V11a8 8 0 0 1 16 0v3h-2v-3a6 6 0 0 0-12 0v3Z'),
    F('M3 13H8V21H3ZM16 13H21V21H16Z')
  ],
  footprint: [F('M3 13H7V18H3ZM9 8H13V18H9ZM15 4H19V18H15ZM2 20H22V22H2Z')]
};

// 墨夜书阁：1.5 圆头细线，配弧边四角星。
const obsidianStroke = (d) => S(d, 1.5);
icons.obsidian_archive = {
  listen: [
    obsidianStroke('M4.5 14.5V12.5a7.5 7.5 0 0 1 15 0v2'),
    obsidianStroke(rr(3.6, 13.2, 3.8, 7, 1.2)), obsidianStroke(rr(16.6, 13.2, 3.8, 7, 1.2)),
    F(qstar(20.6, 3.2, 1.7))
  ],
  footprint: [
    obsidianStroke('M3.2 20.5H20.8'),
    obsidianStroke(rr(4.6, 13, 3, 5, 0.6)), obsidianStroke(rr(10.5, 8, 3, 10, 0.6)), obsidianStroke(rr(16.4, 11, 3, 7, 0.6)),
    F(qstar(18, 4.2, 1.8))
  ]
};

let count = 0;
for (const [pack, set] of Object.entries(icons)) {
  for (const [tab, elements] of Object.entries(set)) {
    save(`ic_theme_${pack}_${tab}`, elements);
    count++;
  }
}
console.log(`Generated ${count} extra tab icons.`);
