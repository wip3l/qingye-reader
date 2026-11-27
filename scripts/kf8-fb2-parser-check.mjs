#!/usr/bin/env node
// AZW3（KF8）与 FB2 解析的回归检查：在脚本里拼出合成的 KF8 文件（PalmDB、KF8 头与 EXTH、FDST 分流、
// SKEL / FRAG / NCX 索引与 CNCX 字符串、图片资源）和 FB2 文档，校验正文拼装、kindle: 链接与图片改写、
// 目录锚点、注释链接、嵌套章节标题与 base64 图片。写文件与分章走 EPUB 同一流程，在真机上验证。
// Usage: node --experimental-strip-types scripts/kf8-fb2-parser-check.mjs

import { loadReaderModules } from './lib/load-reader-modules.mjs';

const { Kf8BookParser, Fb2BookParser, MobiBookParser, cleanup } = await loadReaderModules();

let failures = 0;
const check = (condition, message, detail = '') => {
  if (condition) {
    console.log(`  ok - ${message}`);
  } else {
    failures++;
    console.error(`  FAIL - ${message}${detail ? `\n         ${detail}` : ''}`);
  }
};
const equal = (actual, expected, message) =>
  check(JSON.stringify(actual) === JSON.stringify(expected), message,
    `expected ${JSON.stringify(expected)}\n         actual   ${JSON.stringify(actual)}`);

const decode = (bytes, encoding) => new TextDecoder(encoding === 'utf-8' ? 'utf-8' : encoding).decode(bytes);
const utf8 = (text) => new TextEncoder().encode(text);
const concat = (...arrays) => {
  const out = new Uint8Array(arrays.reduce((sum, item) => sum + item.length, 0));
  let at = 0;
  for (const item of arrays) {
    out.set(item, at);
    at += item.length;
  }
  return out;
};
const u16 = (value) => new Uint8Array([(value >> 8) & 0xFF, value & 0xFF]);
const u32 = (value) => new Uint8Array([(value >>> 24) & 0xFF, (value >>> 16) & 0xFF, (value >>> 8) & 0xFF, value & 0xFF]);
const pngHex = '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000b49444154789c636000020000050001a5f645400000000049454e44ae426082';
const png = Uint8Array.from(Buffer.from(pngHex, 'hex'));
/** 前向变长整数：大端 7 位一组，最后一个字节最高位置 1。 */
const varint = (value) => {
  const bytes = [];
  let rest = value;
  do {
    bytes.unshift(rest & 0x7F);
    rest = Math.floor(rest / 128);
  } while (rest > 0);
  bytes[bytes.length - 1] |= 0x80;
  return bytes;
};
const indxHeader = (tagTable, dataRecords, cncxRecords) => {
  const headerLength = 192;
  const tagx = concat(utf8('TAGX'), u32(12 + tagTable.length * 4), u32(1), Uint8Array.from(tagTable.flat()));
  const record = new Uint8Array(headerLength + tagx.length);
  record.set(utf8('INDX'), 0);
  record.set(u32(headerLength), 4);
  record.set(u32(dataRecords), 24);
  record.set(u32(cncxRecords), 52);
  record.set(tagx, headerLength);
  return record;
};
const indxData = (entries) => {
  const headerLength = 192;
  const bodies = entries.map((entry) =>
    Uint8Array.from([utf8(entry.label).length, ...utf8(entry.label), entry.control, ...entry.values.flatMap(varint)]));
  const positions = [];
  let at = headerLength;
  for (const body of bodies) {
    positions.push(at);
    at += body.length;
  }
  const idxt = concat(utf8('IDXT'), ...positions.map(u16));
  const record = new Uint8Array(at + idxt.length);
  record.set(utf8('INDX'), 0);
  record.set(u32(headerLength), 4);
  record.set(u32(at), 20);
  record.set(u32(entries.length), 24);
  bodies.forEach((body, index) => record.set(body, positions[index]));
  record.set(idxt, at);
  return record;
};
const cncxRecord = (strings) => {
  const parts = [];
  const offsets = [];
  let at = 0;
  for (const text of strings) {
    offsets.push(at);
    const bytes = Uint8Array.from([...varint(utf8(text).length), ...utf8(text)]);
    parts.push(bytes);
    at += bytes.length;
  }
  return { record: concat(...parts, new Uint8Array([0])), offsets };
};
const palmDb = (records) => {
  const headerLength = 78 + records.length * 8 + 2;
  const palm = new Uint8Array(headerLength);
  palm.set(utf8('Palm_Name'), 0);
  palm.set(utf8('BOOKMOBI'), 60);
  palm.set(u16(records.length), 76);
  let offset = headerLength;
  records.forEach((record, index) => {
    palm.set(u32(offset), 78 + index * 8);
    offset += record.length;
  });
  return concat(palm, ...records);
};

// ---------- KF8 ----------
const skel0 = '<html><head><title>T</title><link href="kindle:flow:0001?mime=text/css" rel="stylesheet" type="text/css"/>' +
  '</head><body aid="0"></body></html>';
const frag0 = '<h1 id="c1">第一章</h1><p>甲<a href="kindle:pos:fid:0001:off:0000000000">跳到第二章</a>' +
  '<img src="kindle:embed:0001?mime=image/png"/></p>';
const skel1 = '<html><head><title>T</title></head><body aid="1"></body></html>';
const frag1 = '<h1>第二章</h1><p>乙丙</p>';
const bytesOf = (text) => utf8(text).length;
const skel0Len = bytesOf(skel0);
const frag0Insert = bytesOf(skel0.substring(0, skel0.indexOf('</body>')));
const skel1Pos = skel0Len + bytesOf(frag0);
const skel1Len = bytesOf(skel1);
const frag1Insert = skel1Pos + bytesOf(skel1.substring(0, skel1.indexOf('</body>')));
const flow0 = utf8(skel0 + frag0 + skel1 + frag1);
const css = utf8('p{margin:0}');
const text = concat(flow0, css);

const buildKf8 = () => {
  const fragCncx = cncxRecord(["P-//*[@aid='0']", "P-//*[@aid='1']"]);
  const ncxCncx = cncxRecord(['第一章', '第二章']);
  const fdst = concat(utf8('FDST'), u32(12), u32(2), u32(0), u32(flow0.length), u32(flow0.length), u32(text.length));
  const skelIndex = [
    indxHeader([[1, 1, 0x03, 0], [6, 2, 0x0C, 0], [0, 0, 0, 1]], 1, 0),
    indxData([
      { label: 'SKEL0000000000', control: 0x05, values: [1, 0, skel0Len] },
      { label: 'SKEL0000000001', control: 0x05, values: [1, skel1Pos, skel1Len] }
    ])
  ];
  const fragIndex = [
    indxHeader([[2, 1, 0x01, 0], [3, 1, 0x02, 0], [4, 1, 0x04, 0], [6, 2, 0x08, 0], [0, 0, 0, 1]], 1, 1),
    indxData([
      { label: `${frag0Insert}`, control: 0x0F, values: [fragCncx.offsets[0], 0, 0, 0, bytesOf(frag0)] },
      { label: `${frag1Insert}`, control: 0x0F, values: [fragCncx.offsets[1], 1, 1, 0, bytesOf(frag1)] }
    ]),
    fragCncx.record
  ];
  const ncxIndex = [
    indxHeader([[1, 1, 0x01, 0], [2, 1, 0x02, 0], [3, 1, 0x04, 0], [4, 1, 0x08, 0], [6, 2, 0x10, 0], [0, 0, 0, 1]], 1, 1),
    indxData([
      { label: '0', control: 0x1F, values: [frag0Insert, 10, ncxCncx.offsets[0], 0, 0, 0] },
      { label: '1', control: 0x1F, values: [frag1Insert, 10, ncxCncx.offsets[1], 0, 1, 0] }
    ]),
    ncxCncx.record
  ];

  const entry = (type, value) => concat(u32(type), u32(value.length + 8), value);
  const exthBody = concat(entry(100, utf8('作者甲')), entry(503, utf8('测试书')), entry(201, u32(0)));
  const exth = concat(utf8('EXTH'), u32(12 + exthBody.length), u32(3), exthBody);
  const mobiLength = 264;
  const fullName = utf8('Full Name');
  const record0 = new Uint8Array(16 + mobiLength + exth.length + fullName.length + 4);
  const textRecord = 1;
  const resourceStart = textRecord + 1;
  const fdstIndex = resourceStart + 1;
  const skelStart = fdstIndex + 1;
  const fragStart = skelStart + skelIndex.length;
  const ncxStart = fragStart + fragIndex.length;
  record0.set(u16(1), 0);
  record0.set(u32(text.length), 4);
  record0.set(u16(1), 8);
  record0.set(u16(4096), 10);
  record0.set(utf8('MOBI'), 16);
  record0.set(u32(mobiLength), 20);
  record0.set(u32(2), 24);
  record0.set(u32(65001), 28);
  record0.set(u32(8), 36);
  const nameOffset = 16 + mobiLength + exth.length;
  record0.set(u32(nameOffset), 84);
  record0.set(u32(fullName.length), 88);
  record0.set(u32(resourceStart), 108);
  record0.set(u32(0x40), 128);
  record0.set(u32(fdstIndex), 192);
  record0.set(u32(2), 196);
  record0.set(u32(0), 240);
  record0.set(u32(ncxStart), 244);
  record0.set(u32(fragStart), 248);
  record0.set(u32(skelStart), 252);
  record0.set(exth, 16 + mobiLength);
  record0.set(fullName, nameOffset);
  return palmDb([record0, text, png, fdst, ...skelIndex, ...fragIndex, ...ncxIndex, utf8('EOF\0')]);
};

console.log('KF8');
const kf8 = buildKf8();
check(Kf8BookParser.isKf8(kf8), '认得出 KF8（MOBI 头版本 8）');
try {
  MobiBookParser.parse(kf8, decode, '../images');
  check(false, 'MOBI6 解析遇到 KF8 仍然给出提示');
} catch (error) {
  check(/KF8|AZW3/.test(error.message), 'MOBI6 解析遇到 KF8 仍然给出提示', error.message);
}
const book = Kf8BookParser.parse(kf8, decode, '../images');
equal([book.title, book.author], ['测试书', '作者甲'], 'EXTH 书名与作者');
equal(book.images.map((image) => [image.recIndex, image.ext]), [[1, 'png']], '图片资源按序号编号');
equal(book.coverRecIndex, 1, '封面取 EXTH 201');
equal(book.parts.length, 2, '两个骨架拼成两段');
check(book.parts[0].includes('<h1 id="c1">第一章</h1>'), '片段插回骨架的 body 里', book.parts[0]);
check(book.parts[0].includes('<img src="../images/00001.png"/>'), 'kindle:embed 换成图片文件', book.parts[0]);
check(!/kindle:/.test(book.parts.join('')), '没有残留 kindle: 地址', book.parts.join(''));
check(!/<body|<head|<link/i.test(book.parts[0]), '只留 body 内容，样式表链接去掉', book.parts[0]);
const link = /<a href="(part00002\.html#kf\d+)">跳到第二章<\/a>/.exec(book.parts[0]);
check(!!link, 'kindle:pos:fid 链接指向第二段的锚点', book.parts[0]);
const secondAnchor = /^<a id="(kf\d+)"><\/a><h1>第二章<\/h1>/.exec(book.parts[1]);
check(!!secondAnchor, '第二段开头插了锚点，落在 <h1> 前面', book.parts[1]);
check(!!link && !!secondAnchor && link[1].endsWith(`#${secondAnchor[1]}`), '链接与锚点对得上');
equal(book.toc.map((item) => [item.part, item.title]), [[0, '第一章'], [1, '第二章']], 'NCX 目录');
check(book.toc.length === 2 && book.parts[0].includes(`<a id="${book.toc[0].fragment}"></a><h1 id="c1">`),
  '目录锚点插在章节标题前', book.parts[0]);
check(book.toc.length === 2 && secondAnchor && book.toc[1].fragment === secondAnchor[1], '同一位置的锚点复用');

// 锚点落点：结束标签挪到后面、开始标签挪到前面、限制在 body 里。
const sample = utf8('<html><body><p>ab</p><div x="1">c</div></body></html>');
const range = Kf8BookParser.bodyRange(sample);
const at = (needle) => utf8('<html><body><p>ab</p><div x="1">c</div></body></html>').indexOf(utf8(needle)[0],
  new TextDecoder().decode(sample).indexOf(needle));
equal(Kf8BookParser.anchorPoint(sample, 2, range[0], range[1]), range[0], '落在 head 的挪到 body 开头');
equal(Kf8BookParser.anchorPoint(sample, at('</p>') + 2, range[0], range[1]), at('<div'), '落在结束标签里的挪到它后面');
equal(Kf8BookParser.anchorPoint(sample, at('<div') + 4, range[0], range[1]), at('<div'), '落在开始标签里的挪到它前面');
equal(Kf8BookParser.anchorPoint(sample, sample.length, range[0], range[1]), range[1], '超出 body 的挪到 </body> 前');
equal(Kf8BookParser.forwardVarint(Uint8Array.from([0x01, 0x82]), 0).value, 130, '前向变长整数');

// ---------- FB2 ----------
console.log('FB2');
const b64 = Buffer.from(pngHex, 'hex').toString('base64');
const fb2 = `<?xml version="1.0" encoding="utf-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info>
  <author><first-name>Лев</first-name><middle-name>Николаевич</middle-name><last-name>Толстой</last-name></author>
  <book-title>Война и мир</book-title>
  <coverpage><image l:href="#cover.png"/></coverpage>
</title-info></description>
<body><title><p>Война и мир</p></title>
<section id="s1"><title><p>Часть 1</p></title><p>Текст<a l:href="#n1" type="note">1</a></p>
  <section><title><p>Глава 1</p><p>Салон</p></title><p>— Eh bien, mon prince &amp; Co.</p><empty-line/>
    <poem><stanza><v>Строка</v></stanza></poem><epigraph><p>Эпиграф</p><text-author>Автор</text-author></epigraph></section>
</section>
<section><title><p>Часть 2</p></title><p><emphasis>курсив</emphasis> <strong>жирный</strong> <strikethrough>зачёркнутый</strikethrough></p>
  <image l:href="#pic.png"/><subtitle>* * *</subtitle></section>
</body>
<body name="notes"><title><p>Примечания</p></title><section id="n1"><title><p>1</p></title><p>Примечание</p></section></body>
<binary id="cover.png" content-type="image/png">${b64}</binary>
<binary id="pic.png" content-type="image/png">${b64.replace(/(.{20})/g, '$1\n')}</binary>
</FictionBook>`;
const fb = Fb2BookParser.parse(utf8(fb2), decode, '../images');
equal([fb.title, fb.author], ['Война и мир', 'Лев Николаевич Толстой'], '书名与作者（名、父称、姓）');
equal(fb.images.map((image) => [image.recIndex, image.ext, image.bytes.length]), [[1, 'png', png.length], [2, 'png', png.length]],
  'base64 图片解出来（含换行）');
equal(fb.coverRecIndex, 1, '封面取 coverpage');
equal(fb.parts.length, 3, '两个顶层 section 加注释各成一段');
check(fb.parts[0].startsWith('<h1 id="'), '正文书名页并进第一段', fb.parts[0].substring(0, 80));
check(/<h2 id="fb\d+">Часть 1<\/h2>/.test(fb.parts[0]), '顶层章节标题', fb.parts[0]);
check(/<h3 id="fb\d+">Глава 1<br\/>Салон<\/h3>/.test(fb.parts[0]), '嵌套章节标题小一级、多行标题用换行', fb.parts[0]);
check(fb.parts[0].includes('<a href="part00003.html#n1">1</a>'), '注释链接指向注释段的锚点', fb.parts[0]);
check(fb.parts[0].includes('&amp; Co.'), '实体原样保留', fb.parts[0]);
check(fb.parts[0].includes('<div><div><p>Строка</p></div></div>'), '诗节与诗行', fb.parts[0]);
check(fb.parts[0].includes('<blockquote><p>Эпиграф</p><p><em>Автор</em></p></blockquote>'), '题词与署名', fb.parts[0]);
check(fb.parts[1].includes('<em>курсив</em> <strong>жирный</strong> <s>зачёркнутый</s>'), '强调、加粗、删除线', fb.parts[1]);
check(fb.parts[1].includes('<img src="../images/00002.png"/>'), '正文图片换成文件', fb.parts[1]);
check(fb.parts[1].includes('<p><strong>* * *</strong></p>'), '小标题', fb.parts[1]);
check(fb.parts[2].includes('<div id="n1">') && fb.parts[2].includes('Примечание'), '注释段保留 id', fb.parts[2]);
equal(fb.toc.map((item) => [item.part, item.title]),
  [[0, 'Часть 1'], [0, 'Глава 1 Салон'], [1, 'Часть 2'], [2, 'Примечания']], '目录：各级章节与注释');
check(fb.toc.every((item, index) => index === 3 ? true : fb.parts[item.part].includes(`id="${item.fragment}"`)),
  '目录锚点都在对应段里');
equal(Fb2BookParser.declaredEncoding(utf8('<?xml version="1.0" encoding="windows-1251"?><FictionBook>')),
  'windows-1251', '读 XML 声明里的编码');
const cp1251 = Uint8Array.from([...utf8('<?xml version="1.0" encoding="windows-1251"?><FictionBook><body><section><title><p>'),
  0xC3, 0xEB, 0xE0, 0xE2, 0xE0, ...utf8('</p></title><p>x</p></section></body></FictionBook>')]);
equal(Fb2BookParser.parse(cp1251, decode, '../images').toc.map((item) => item.title), ['Глава'], 'windows-1251 按声明解码');
try {
  Fb2BookParser.parse(utf8('<html><body>x</body></html>'), decode, '../images');
  check(false, '不是 FB2 时给出提示');
} catch (error) {
  check(/FB2/.test(error.message), '不是 FB2 时给出提示', error.message);
}

cleanup();
if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log('\nkf8-fb2-parser-check: ok');
