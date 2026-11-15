// Original vector companions to the Dreamina-generated obsidian/champagne artwork.
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
const root = new URL('../entry/src/main/resources/base/media/', import.meta.url);
const svg = (w,h,body) => `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${body}</svg>\n`;
const save = (name,w,h,body) => writeFileSync(new URL(name+'.svg',root),svg(w,h,body));
const star = (x,y,s,c) => `<path d="M${x} ${y-s}Q${x} ${y} ${x+s} ${y}Q${x} ${y} ${x} ${y+s}Q${x} ${y} ${x-s} ${y}Q${x} ${y} ${x} ${y-s}Z" fill="${c}"/>`;
for(const mode of ['light','dark']) {
  const gold = mode==='light'?'#A38A57':'#9E865B';
  const paperGold = mode==='light'?'#94764D':'#C3AB7E';
  const lineOpacity = mode==='light'?'0.28':'0.20';
  // Ginkgo flyleaf: asymmetrical, open edges and quiet foil veins. The text area stays empty.
  const leaf='M78 149C37 132 12 102 19 68C36 31 71 17 99 34C112 7 155 9 179 34C207 62 196 99 164 115C130 128 107 143 78 149Z';
  const corner=`<path d="${leaf}" fill="${paperGold}" opacity="0.055"/>`+
    `<g fill="none" stroke="${paperGold}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" opacity="${lineOpacity}">`+
    `<path d="${leaf}"/><path d="M78 149C105 151 128 173 145 210M78 149Q44 108 30 72M78 149Q61 92 56 41M78 149Q77 86 88 32M78 149Q103 82 123 26M78 149Q127 87 153 26M78 149Q147 99 178 48M78 149Q150 119 192 77"/>`+
    '<path d="M14 180C43 185 73 184 109 173M12 190C40 196 66 196 89 189M220 49C240 56 251 73 252 94C233 88 220 72 220 49ZM252 94L264 118"/>'+
    '</g>'+
    `<g fill="${paperGold}" opacity="${lineOpacity}"><circle cx="203" cy="140" r="2.5"/><circle cx="20" cy="222" r="2"/>${star(288,37,4,paperGold)}</g>`;
  // A distant mountain becomes the edge of a turning page; only the lower outer corner is occupied.
  const ridge='M107 400L181 367 218 380 275 326 314 347 349 312 387 343 423 321 465 344';
  const trailing=`<path d="${ridge}L465 378Q375 369 296 405Q224 433 107 400Z" fill="${paperGold}" opacity="0.045"/>`+
    `<g fill="none" stroke="${paperGold}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" opacity="${lineOpacity}">`+
    `<path d="${ridge}"/><path d="M151 400L191 381 217 394 277 343 313 361 351 330 386 356 426 337 465 357"/>`+
    '<path d="M80 421C145 400 200 432 268 421C340 409 393 368 465 384M107 438C168 422 218 449 287 437C352 424 397 396 466 403M164 457C226 444 248 464 313 450C374 436 413 423 466 423"/>'+
    '<path d="M349 281Q356 281 362 287Q364 278 372 274M402 260Q408 259 413 264Q415 257 421 254"/>'+
    '</g>'+`<g opacity="${lineOpacity}">${star(458,291,4,paperGold)}${star(306,285,3,paperGold)}</g>`;
  save(`reader_decor_obsidian_archive_${mode}`,480,480,corner);
  save(`reader_decor_obsidian_archive_trailing_${mode}`,480,480,trailing);
  save(`reader_bg_obsidian_archive_${mode}`,1080,1920,`<rect width="1080" height="1920" fill="${mode==='light'?'#F5EFE3':'#1C1C1B'}"/>`);
  // Fine architecture and paper arcs live above the player controls; no heavy central motif.
  save(`tts_panel_obsidian_archive_${mode}`,720,520,
    `<g fill="none" stroke="${gold}" opacity="0.32" stroke-width="1.5"><path d="M40 280V130A96 96 0 0 1 232 130V250M50 276V132A86 86 0 0 1 222 132V246"/><path d="M414 246Q515 140 680 190M440 264Q535 183 700 220"/><path d="M80 278Q151 247 210 279L210 301Q147 272 80 301ZM210 279Q260 250 314 271V296Q258 277 210 301"/><path d="M85 320H650"/><circle cx="556" cy="96" r="31"/><circle cx="556" cy="96" r="42"/></g>${star(352,80,7,gold)}${star(633,145,5,gold)}${star(398,200,4,gold)}`);
}
// 书架封面边框 theme_frame_obsidian_archive 已改为位图（透明 WebP），不再由本脚本生成；
// 这里若再写出同名 SVG 会和位图资源重名。
save('theme_logo_obsidian_archive',64,64,
  '<rect x="3" y="3" width="58" height="58" rx="15" fill="#191B1F"/><g fill="none" stroke="#D6B878" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 40Q22 36 32 42Q42 36 52 40V48Q41 44 32 50Q23 44 12 48Z"/><path d="M32 42V50M32 26C19 10 8 23 17 31C24 38 37 17 45 19C58 22 46 44 32 26"/></g>');
// Foil bookplate: chamfered corners and an inset rule, rather than a generic rounded pill.
save('regex_frame_gilded_orbit',96,48,
  '<path d="M10 3H82L94 15V38L86 45H14L2 33V11Z" fill="none" stroke="#C6A76A" stroke-width="1.2"/>'+
  '<path d="M8 29V13L14 8H77M19 40H82L88 35V20M82 3V15H94" fill="none" stroke="#E5CD99" stroke-width="1"/>');
// Inline cap is square so the folded ribbon remains readable at 16–24 vp.
save('regex_cap_gilded_orbit',24,24,
  '<path d="M5 3H17V21L11 17 5 21Z" fill="#C5A36A"/>'+
  '<path d="M8 5.5H14V15.5L11 13.5 8 15.5Z" fill="#292620"/>'+
  '<path d="M17 3L21 7H17Z" fill="#F1DEB4"/>'+
  star(11,9.5,2.5,'#F1DEB4'));
// 深色模式的强调底色是深褐，端饰改成亮金书签、象牙内页，边框的金线也提亮。
save('regex_frame_gilded_orbit_dark',96,48,
  '<path d="M10 3H82L94 15V38L86 45H14L2 33V11Z" fill="none" stroke="#DCC088" stroke-width="1.2"/>'+
  '<path d="M8 29V13L14 8H77M19 40H82L88 35V20M82 3V15H94" fill="none" stroke="#F4E3BF" stroke-width="1"/>');
save('regex_cap_gilded_orbit_dark',24,24,
  '<path d="M5 3H17V21L11 17 5 21Z" fill="#E0C489"/>'+
  '<path d="M8 5.5H14V15.5L11 13.5 8 15.5Z" fill="#F7E8C5"/>'+
  '<path d="M17 3L21 7H17Z" fill="#B8975A"/>'+
  star(11,9.5,2.5,'#30291E'));
// A coherent 24-vp folio family: open leaves, folded compass, quill lens, reader ex libris.
// Monochrome paths are tinted by both native and compatibility tab bars.
const nav={
  bookshelf:'<path d="M3 5.5C6 4.7 9.1 5.3 12 7.4C14.9 5.3 18 4.7 21 5.5V18C17.8 17.1 14.8 17.9 12 20C9.2 17.9 6.2 17.1 3 18ZM12 7.4V20M6 9C7.3 9 8.4 9.4 9.5 10.1M6 12.3C7.3 12.3 8.4 12.7 9.5 13.4M15 13.2L17 11.7 19 13.2V5.4"/>'+star(12,2.8,1.8,'#000000'),
  explore:'<path d="M9.8 3.4L3.2 10V19.8H13L20.6 12.2V4.2H15.5M3.2 10H9.8V3.4M7 16.5L11 9.5 18 6 14 13Z M11 9.5L14 13"/>'+star(20.5,2.5,1.6,'#000000'),
  search:'<circle cx="9.6" cy="9.6" r="6.6"/><path d="M6 9.5C7.4 8.6 8.5 8.8 9.6 9.6C10.7 8.8 11.8 8.6 13.2 9.5V12.1C11.8 11.2 10.7 11.4 9.6 12.2C8.5 11.4 7.4 11.2 6 12.1ZM9.6 9.6V12.2M14.4 14.4L17.2 17.2M17.2 15.5L21.6 19.9 20 21.5 15.6 17.1Z"/>'+star(19.8,4.1,1.8,'#000000'),
  mine:'<circle cx="12" cy="6.3" r="3.3"/><path d="M4 17.5C4 13.8 7.1 11.5 12 11.5C16.9 11.5 20 13.8 20 17.5M4 16.5L12 20.8 20 16.5M4 16.5V20M20 16.5V20M12 15.5V20.8"/>'+star(20.5,6.2,1.7,'#000000')
};
// ArkUI fillColor reliably tints filled outlines. Keep editable centre lines above,
// and checked-in stroke outlines below so normal regeneration has no extra dependency.
// To refresh outlines after editing: npm install --prefix output/obsidian-vector-tools --no-save pathkit-wasm
// Then: node scripts/generate-obsidian-theme-vectors.mjs --outline-navigation
const outlineFile = new URL('./obsidian-navigation-outlines.json', import.meta.url);
const navHash = createHash('sha256').update(JSON.stringify(nav)).digest('hex');
let outlines;
if (process.argv.includes('--outline-navigation')) {
  const require = createRequire(import.meta.url);
  const init = require('../output/obsidian-vector-tools/node_modules/pathkit-wasm/bin/pathkit.js');
  const pk = await init({ wasmBinary: readFileSync(new URL('../output/obsidian-vector-tools/node_modules/pathkit-wasm/bin/pathkit.wasm', import.meta.url)) });
  outlines = { sourceSha256: navHash, icons: {} };
  for (const [name, body] of Object.entries(nav)) {
    const shapes = body.replace(/<circle cx="([\d.]+)" cy="([\d.]+)" r="([\d.]+)"\/>/g, (_, x, y, r) =>
      `<path d="M${+x-r} ${y}a${r} ${r} 0 1 0 ${+r*2} 0a${r} ${r} 0 1 0 ${-r*2} 0Z"/>`);
    let filled = '';
    for (const match of shapes.matchAll(/<path d="([^"]+)"([^>]*)\/>/g)) {
      const p = pk.FromSVGString(match[1]);
      if (!p || !p.stroke({ width: 1.5, cap: pk.StrokeCap.ROUND, join: pk.StrokeJoin.ROUND })) {
        throw new Error(`Cannot outline ${name}`);
      }
      filled += `<path d="${p.toSVGString()}"/>`;
      if (match[2].includes('fill="#000000"')) filled += `<path d="${match[1]}"/>`;
      p.delete();
    }
    outlines.icons[name] = `<g fill="#000000">${filled}</g>`;
  }
  writeFileSync(outlineFile, JSON.stringify(outlines, null, 2)+'\n');
} else {
  outlines = JSON.parse(readFileSync(outlineFile, 'utf8'));
  if (outlines.sourceSha256 !== navHash) throw new Error('Navigation changed; regenerate with --outline-navigation.');
}
for(const [name,body] of Object.entries(outlines.icons)) save('ic_theme_obsidian_archive_'+name,24,24,body);
console.log('Generated obsidian theme vector companions.');
