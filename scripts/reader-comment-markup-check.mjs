// Comment markup of Legado-compatible sources becomes clickable reader actions: Android data-image
// options, iOS `<div rs-native>` paragraphs with `<comment>` bubbles, and onClick SVG cards.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const service = fs.readFileSync(`${projectRoot}/entry/src/main/ets/core/book/WebBookService.ts`, 'utf8');
const markerSource = fs.readFileSync(
  `${projectRoot}/harmony-book-source-engine/sourceengine/src/main/ets/core/book/ReaderActionMarker.ts`, 'utf8');
function method(source, name) {
  const match = new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm').exec(source);
  assert(match, name);
  const end = source.indexOf('\n  }', match.index);
  assert(end > match.index);
  return source.slice(match.index, end + '\n  }'.length).replace('private ', '');
}
const compile = text => stripTypeScriptTypes(text, { mode: 'strip' });
// File-level helper class of WebBookService (the parts of a 本章说 card).
const chapterClass = /^class ReaderDataImageChapter \{[\s\S]*?\r?\n\}\r?\n/m.exec(service);
assert(chapterClass, 'ReaderDataImageChapter');
const names = ['convertReaderNativeActions', 'convertReaderNoteActions', 'convertReaderImageScriptActions',
  'readerActionMarkerFromClickableImage',
  'readerActionMarkerFromCommentAttributes', 'readerImageOptionString', 'readerDataImageLabel', 'readerDataImageText',
  'readerDataImageHot', 'readerDataImageChapter', 'readerDataImageTexts', 'readerDataImageIsCard', 'readerDataImageIsWide', 'readerActionLine',
  'decodeHtmlEntities', 'readerRemoteBubbleAction', 'readerInlineIconSize', 'inlineRemoteSvgControls',
  'fetchRemoteSvgControl', 'findReaderImageAttribute', 'readerImageOptionIndex'];
const util = {
  Base64Helper: class { decodeSync(text) { return Uint8Array.from(Buffer.from(text, 'base64')); } },
  TextDecoder: { create: () => ({ decodeWithStream: bytes => Buffer.from(bytes).toString('utf8') }) },
  TextEncoder: class { encodeInto(text) { return Uint8Array.from(Buffer.from(text, 'utf8')); } }
};
util.Base64Helper.prototype.encodeToStringSync = bytes => Buffer.from(bytes).toString('base64');
const BookUrlResolver = {
  resolve: (url, base) => { try { return new URL(url, base).href; } catch (_) { return url; } }
};
// Remote SVG controls: requests go to a fake server keyed by address.
const served = new Map();
const requested = [];
class AnalyzeUrl {
  parse(url) { this.url = url; }
  buildRequest() { return { url: this.url, method: 'GET', headers: {} }; }
}
const WebBookService = { INLINE_ICON_VP: 24, REMOTE_SVG_CONTROL_LIMIT: 8, remoteSvgControls: new Map() };
const context = vm.createContext({ util, BookUrlResolver, AnalyzeUrl, WebBookService });
vm.runInContext(compile(markerSource.replace(/^export /gm, '') + `\n${chapterClass[0]}` +
  `\nclass Converter {\n${names.map(name => method(service, name)).join('\n')}\n}\n`) +
  'globalThis.Converter = Converter; globalThis.ReaderActionMarker = ReaderActionMarker;', context);
const converter = new context.Converter();
converter.http = {
  execute: async request => {
    requested.push(request.url);
    return served.has(request.url) ? { success: true, body: served.get(request.url) } : { success: false, body: '' };
  }
};
const Marker = context.ReaderActionMarker;
const convert = (text, base = '') => converter.convertReaderNativeActions(null, text, base);
const actions = text => {
  const found = [];
  let match = Marker.findFirst(text);
  while (match) {
    found.push({ ...match.data, at: match.start });
    match = Marker.findFirst(text, match.end);
  }
  return found;
};
const svg = (...texts) => Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg">${texts.map(text =>
  `<text x="1" y="1">${text}</text>`).join('')}</svg>`).toString('base64');
const page = 'https://reviews.example/reviews?bookId=1&amp;chapterId=2&amp;paragraphId=';

// iOS markup: paragraph + bubble + hot-comment card inside rs-native, chapter card after the paragraphs.
const ios = [
  `<div rs-native>第一段<comment count="12" onClick="java.startBrowser('${page}1')"/>`,
  `<img src="data:image/svg+xml;base64,${svg('热评', '写得真好')}" onClick="java.startBrowser('${page}1')"/></div>`,
  '<div rs-native>第二段</div>',
  `<img src="data:image/svg+xml;base64,${svg('本章说', '906 条评论 〉')}" onClick="java.startBrowser('${page}0')"/>`
].join('\n');
const out = convert(ios);
const found = actions(out);
assert.deepEqual(found.map(item => item.label), ['段评 12', '热评', '章评']);
assert.deepEqual(found.map(item => item.preview), ['', '写得真好', '906条评论'],
  'hot and chapter cards carry their wording, the trailing arrow dropped');
assert.equal(found[2].count, '906条评论', 'a 本章说 card count goes to the title row');
assert.equal(found[2].hots.length, 0);
assert.equal(found[0].url, 'https://reviews.example/reviews?bookId=1&chapterId=2&paragraphId=1');
assert.equal(found[0].title, '段评', 'a <comment> bubble is a paragraph comment whatever the page path');
assert.equal(found[2].url.endsWith('paragraphId=0'), true);
const plain = Marker.strip(out);
assert.match(plain, /^第一段\n/);
assert.match(plain, /第二段/);
assert.ok(out.indexOf('第一段') < found[0].at && found[0].at < found[1].at && found[1].at < out.indexOf('第二段'),
  'bubble follows its paragraph, the hot-comment card comes after it');
assert.ok(!/<img|<comment|rs-native/.test(out), 'no raw markup is left for the image pipeline');

// A real picture with a link stays a picture; Android data-image options keep their own path.
const picture = '<img src="https://img.example/a.jpg" onClick="java.startBrowser(\'https://img.example/page\')">';
assert.equal(convert(picture), picture);
const android = `<p>段落<img src="data:image/svg+xml;base64,${svg('7')},{'click':'showCmt("1","2","3","4")','style':'TEXT'}"></p>`;
const androidActions = actions(convert(android));
assert.equal(androidActions.length, 1);
assert.equal(androidActions[0].label, '段评 7');
assert.equal(Marker.sourceScript(androidActions[0].url), 'showCmt("1","2","3","4")');

// Data-image cards with script options say what they are: 神评论 is a hot comment, 本章说 the chapter
// card; their numbers are like counts and must not become “段评 N”.
const review = 'http://reviews.example/get_para_review?book_id=1&amp;para=';
const optionCards = [
  `<div rs-native>第一段<comment count="99" onPress="java.showReadingBrowser('${review}1','墨阅段评')"/>`,
  `<img src="data:image/svg+xml;base64,${svg('神评论', '写得真好', '22')},{"style":"FULL","type":"qd",` +
    `"click":"godOpen('${review}1','墨阅·神评')"}"></div>`,
  `<img src="data:image/svg+xml;base64,${svg('本章说', '76条评论 〉', '698')},{"style":"FULL","type":"qd",` +
    `"click":"godOpen('http://reviews.example/chapter','墨阅·本章说')"}">`
].join('\n');
const optionActions = actions(convert(optionCards));
assert.deepEqual(optionActions.map(item => item.label), ['段评 99', '热评', '章评']);
assert.deepEqual(optionActions.map(item => item.title), ['段评 · 墨阅段评', '热评', '章评']);
assert.match(Marker.sourceScript(optionActions[1].url), /^godOpen\(/);
assert.equal(optionActions[1].preview, '写得真好');
assert.equal(optionActions[1].likes, '22', 'the trailing number of a hot card is its like count');
assert.equal(optionActions[2].preview, '76条评论');
assert.equal(optionActions[2].likes, '', 'a 本章说 card number is not a like count');
assert.equal(optionActions[2].count, '76条评论');
assert.equal(optionActions[2].hots.length, 0, 'a bare number on a 本章说 card is not a comment either');

// A 本章说 card that shows one comment: count, a short nickname line, then the wrapped comment lines.
const chapterCard = `<img src="data:image/svg+xml;base64,${svg('本章说', '79 条评论', '凌啸绝顶21', '正如周海说的，',
  '石膏里藏的东西才是关键…', '›')}" onClick="java.startBrowser('${page}0')"/>`;
const chapterAction = actions(convert(chapterCard))[0];
assert.equal(chapterAction.label, '章评');
assert.equal(chapterAction.count, '79条评论');
assert.deepEqual(Array.from(chapterAction.hots, hot => [hot.user, hot.text, hot.likes]),
  [['凌啸绝顶21', '正如周海说的，石膏里藏的东西才是关键…', '']], 'nickname and comment are kept apart');
assert.equal(chapterAction.preview, '正如周海说的，石膏里藏的东西才是关键…');

// A 本章说 card listing several comments, each as nickname, like pill, wrapped lines. 起点's default
// nickname “书友” + 15 digits runs past the short-nickname limit and must still be read as the nickname.
const listedCard = `<img src="data:image/svg+xml;base64,${svg('本章说', '2333 条评论 〉', '书友161015153026477', '180',
  '短小无力短小无力短小无力短小无力短小', '无力短小无力…', '19720111冬', '37', '历史的发展，就像春夏秋冬的轮回，这东',
  '西不会因为某个人')}" onClick="java.startBrowser('${page}0')"/>`;
const listedAction = actions(convert(listedCard))[0];
assert.equal(listedAction.count, '2333条评论');
assert.deepEqual(Array.from(listedAction.hots, hot => [hot.user, hot.text]), [
  ['书友161015153026477', '短小无力短小无力短小无力短小无力短小无力短小无力…'],
  ['19720111冬', '历史的发展，就像春夏秋冬的轮回，这东西不会因为某个人']
], 'a long default nickname is kept apart from its comment');

// <note> inline cards; a server that wraps each line in rs-native can split a multi-line text attribute
// across two divs. The whole tag becomes one action and nothing of it leaks into the paragraph text.
const noted = [
  '<div rs-native>正文第一段<comment count="3" onPress="java.showReadingBrowser(\'' + review + '1\')"/>' +
    '<note label="神评论" ident="/get_para_review?book_id=1&para=1" autoHeight="0" text="第一行&gt;评论</div>',
  '<div rs-native>第二行评论"></note></div>',
  '<div rs-native>正文第二段</div>'
].join('\n');
const notedOut = convert(noted, 'https://reviews.example/legado/content?url=x');
const notedActions = actions(notedOut);
assert.deepEqual(notedActions.map(item => item.label), ['段评 3', '热评']);
assert.equal(notedActions[1].url, 'https://reviews.example/get_para_review?book_id=1&para=1');
assert.equal(notedActions[1].preview, '第一行>评论 第二行评论', 'a note keeps its text, whitespace folded');
assert.equal(Marker.strip(notedOut).split('\n').filter(Boolean).join('|'), '正文第一段|正文第二段');
// Without a resolvable address the note is dropped rather than shown as markup.
assert.equal(Marker.strip(convert('<div rs-native>段落<note label="神评论" ident="/x" text="a"></note></div>'))
  .trim(), '段落');

// Cards that do not say 热评/神评 — a nickname, the comment and its like count, drawn full width — are hot
// comments, not “段评 N” bubbles; their like count must not become a bubble on a line of its own.
const svgSpans = (...texts) => Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg">${texts.map(text =>
  `<text x="1" y="1"><tspan>${text}</tspan></text>`).join('')}</svg>`).toString('base64');
const bareCards = [
  `<p>化为丈许般巨大。<img src="data:image/svg+xml;base64,${svgSpans('15')},{'click':'para("15")','style':'TEXT'}"></p>`,
  `<img src="data:image/svg+xml;base64,${svg('书友甲', '这章太燃了', '7')},{"click":"hot(\\"a\\")","style":"FULL"}">`,
  `<img src="data:image/svg+xml;base64,${svg('掌门', '韩老魔又要跑路了', '1')},{"click":"hot(\\"b\\")"}">`,
  '<p>“砰”的一声。</p>'
].join('');
const bareOut = convert(bareCards);
const bareActions = actions(bareOut);
assert.deepEqual(bareActions.map(item => item.label), ['段评 15', '热评', '热评'],
  'tspan counts are read; worded cards are hot comments even without the word 热评');
assert.deepEqual(bareActions.map(item => item.preview), ['', '书友甲 这章太燃了', '掌门 韩老魔又要跑路了']);
assert.deepEqual(bareActions.map(item => item.likes), ['', '7', '1']);
const bareLines = bareOut.split('\n').map(line => line.replace(/<\/?p>/g, '')).filter(line => line.trim());
assert.equal(Marker.strip(bareLines[0]).trim(), '化为丈许般巨大。', 'the count bubble stays at the end of its paragraph');
assert.ok(Marker.has(bareLines[0]));
assert.equal(Marker.strip(bareLines[1]).trim(), '', 'each card sits on a line of its own');
assert.equal(Marker.strip(bareLines[2]).trim(), '');
// A plain count bubble with 段评/条 wording is still a bubble.
const worded = actions(convert(`<p>段<img src="data:image/svg+xml;base64,${svg('段评', '12条')},{'click':'x()'}"></p>`));
assert.equal(worded[0].label, '段评');

// An inline (TEXT) bubble with prose right after it stays where the source put it, as Android draws it; a
// bubble at the end of its paragraph still ends the line.
const bubble = (count, style) =>
  `<img src="data:image/svg+xml;base64,${svg(count)},{'click':'para("${count}")','style':'${style}'}">`;
const leading = convert(`${bubble('5', 'text')}他抬起头。\n第二段${bubble('8', 'TEXT')}\n第三段`).split('\n');
assert.equal(Marker.strip(leading[0]), '他抬起头。', 'a leading inline bubble keeps its paragraph on the same line');
assert.ok(Marker.has(leading[0]));
assert.equal(leading.filter(line => Marker.has(line) && !Marker.strip(line).trim()).length, 0,
  'no bubble is left alone on a line');
assert.equal(Marker.strip(convert(`甲${bubble('1', 'line')}乙`)), '甲\n乙', 'a block-style bubble still breaks the line');

// Purification rules run around the markers. A rule that deletes a paragraph takes its bubble with it; a card
// that already stood alone, and bubbles of untouched paragraphs, stay.
const preprocessor = fs.readFileSync(
  `${projectRoot}/entry/src/main/ets/core/concurrency/ReaderContentPreprocessor.ets`, 'utf8').replace(/\r\n/g, '\n');
const taskStart = preprocessor.indexOf('function applyReaderRulesInTask');
const taskEnd = preprocessor.indexOf('\n}\n', taskStart);
assert.ok(taskStart >= 0 && taskEnd > taskStart);
const ruleContext = vm.createContext({
  console,
  JavaRegexCompat: { convert: (source, flags) => ({ source, flags }), convertReplacement: text => text },
  BudgetedRegexReplace: class {
    constructor(source, flags) { this.regex = new RegExp(source, `${flags}m`); }
    replace(text, replacement) { return text.replace(this.regex, replacement); }
  }
});
vm.runInContext(compile(preprocessor.slice(taskStart, taskEnd + 2)) +
  '\nglobalThis.applyRules = applyReaderRulesInTask;', ruleContext);
const m = label => Marker.create(label, 'https://a.example/x', '段评');
const hotCard = Marker.create('热评', 'https://a.example/h', '热评', '写得好');
const purified = ruleContext.applyRules(
  `第一段${m('段评 1')}\n求月票求推荐${m('段评 5')}\n${hotCard}\n第二段${m('段评 8')}`,
  JSON.stringify([{ pattern: '^.*求月票.*$', replacement: '', isRegex: true }]), '');
assert.deepEqual(actions(purified).map(item => item.label), ['段评 1', '热评', '段评 8']);
assert.equal(Marker.strip(purified).split('\n').filter(line => line.trim()).join('|'), '第一段|第二段');
const untouched = `第一段${m('段评 1')}\n${m('段评 2')}\n第二段`;
assert.equal(ruleContext.applyRules(untouched, JSON.stringify([{ pattern: '不存在', replacement: '' }]), ''),
  untouched, 'a bubble that was already alone is not dropped');

// iOS-style aggregate markup: paragraph bubbles are <comment> tags, hot comments are clickable SVG cards in a
// (doubly wrapped) rs-native div. A long comment is one <text> with a tspan per line — thousands of characters
// of markup — and must still be read as the card it is, not as “段评 <likes>” on a line of its own. A card whose
// words cannot be read at all is told from a bubble by its shape (a wide strip).
const rawSvg = body => Buffer.from(body).toString('base64');
const longLines = Array.from({ length: 14 }, (_, index) =>
  `<tspan x="12" dy="18" font-family="PingFang SC, sans-serif" font-size="14" fill="#333333">第${index}行评论内容很长很长很长</tspan>`);
const longCard = rawSvg(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 300"><text x="12" y="20">${
  longLines.join('')}</text><text x="330" y="280">5</text></svg>`);
assert.ok(longLines.join('').length > 600);
const pathCard = rawSvg('<svg xmlns="http://www.w3.org/2000/svg" width="360" height="72"><path d="M0 0h10"/>' +
  '<text x="330" y="60">3</text></svg>');
const squareBubble = rawSvg('<svg xmlns="http://www.w3.org/2000/svg" viewBox="-150 0 1224 1224"><path d="M0 0"/>' +
  '<text x="460" y="650">8</text></svg>');
const godCard = data => `<div rs-native><div rs-native><img onPress="java.showReadingBrowser('${page}9','段评')" ` +
  `src="data:image/svg+xml;base64,${data}"></div></div>`;
const aggregate = [
  `<div rs-native>他点了点头。<comment count="8" onPress="java.showReadingBrowser('${page}9','番茄段评')"></div>`,
  godCard(longCard), godCard(pathCard),
  `<div rs-native>下一段。<comment count="10" onPress="java.showReadingBrowser('${page}10','番茄段评')"></div>`
].join('\n');
const aggregateOut = convert(aggregate);
const aggregateActions = actions(aggregateOut);
assert.deepEqual(aggregateActions.map(item => item.label), ['段评 8', '热评', '热评', '段评 10'],
  'long and wordless cards are hot comments, never count bubbles');
assert.match(aggregateActions[1].preview, /^第0行评论内容/);
assert.equal(aggregateActions[1].likes, '5');
assert.equal(aggregateOut.split('\n').filter(line => /^\s*$/.test(Marker.strip(line.replace(/<[^>]+>/g, ''))) &&
  actions(line).some(item => /^段评/.test(item.label))).length, 0, 'no count bubble stands alone');
// A small square bubble with only its number stays a count bubble, on either markup.
assert.equal(actions(convert(`<p>段<img src="data:image/svg+xml;base64,${squareBubble},{'js':'x()','style':'text'}"></p>`))[0]
  .label, '段评 8');
assert.equal(actions(convert(`段<img onClick="java.startBrowser('${page}1')" src="data:image/svg+xml;base64,${squareBubble}">`))[0]
  .label, '段评 8');

// A source whose paragraph rewrite leaves the closing </p> behind, on content that has every paragraph on one
// line: a paragraph without comments ends up inside the same rs-native block as the next one. Each bubble stays
// on the paragraph it was written into, and the paragraphs stay separate lines.
const oneLine = [
  '<div rs-native>回禀道：</p><p>“先前几次。”<comment count="4" onPress="java.showReadingBrowser(\'' + page + '4\',\'段评\')"></div></p>',
  '<div rs-native>“好生固执。”<comment count="1" onPress="java.showReadingBrowser(\'' + page + '1\',\'段评\')"></div></p>',
  godCard(longCard),
  '<div rs-native>没有评论</p><p>最后一段。<comment count="8" onPress="java.showReadingBrowser(\'' + page + '8\',\'段评\')"></div></p>'
].join('');
const oneLineOut = convert(oneLine).replace(/<\/(?:p|div)>/g, '\n').replace(/<[^>]+>/g, '');
const oneLineRows = oneLineOut.split('\n').filter(line => line.trim()).map(line => {
  const found = actions(line);
  return `${Marker.strip(line).trim()}${found.length ? `[${found[0].label}]` : ''}`;
});
assert.deepEqual(oneLineRows, ['回禀道：', '“先前几次。”[段评 4]', '“好生固执。”[段评 1]', '[热评]', '没有评论',
  '最后一段。[段评 8]']);

// Server-drawn controls (a source that serves its badge and cards as remote SVGs): the badge is
// `img_base + count` with a style:"text" click option at the end of its paragraph, the cards style:"full".
// The badge becomes a 段评 action with the count from its address and needs no request; a clickable card that
// really is an SVG is fetched once and read like a data-image card; a raster card stays a picture.
const panel = 'zlOpenPanel(\\"http://zl.example/panel/review?p=';
const badge = n => ` <img src='http://zl.example/bubble.svg?s=a&amp;n=${n},{"click":"${panel}${n}\\")","style":"text"}' ` +
  `style='display:inline-block;vertical-align:middle'/>`;
const remoteHtml = [
  `<p><img src='http://zl.example/hot.svg?c=1,{"click":"${panel}0\\")","style":"full"}' style='display:block;width:100%'/></p>`,
  `<p>玄灵大陆，金乌皇朝，开元城。${badge(12)}</p>`,
  '<p>没有评论的一段。</p>',
  `<p>又一段${badge(3)}</p>`,
  `<p><img src='http://zl.example/discuss.svg?c=1,{"click":"${panel}x\\")","style":"full"}' style='display:block'/></p>`,
  `<p><img src='http://zl.example/author.png,{"click":"${panel}a\\")","style":"full"}' style='display:block'/></p>`,
  `<p style='line-height:0'><img src='http://zl.example/warm?c=1' style='display:block;width:1px;height:1px'/></p>`
].join('\n');
served.set('http://zl.example/hot.svg?c=1', `<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg" ` +
  'viewBox="0 0 360 90"><text x="1" y="1">热评</text><text x="1" y="2">书友乙</text><text x="1" y="3">这章不错</text>' +
  '<text x="1" y="4">9</text></svg>');
served.set('http://zl.example/discuss.svg?c=1', '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 60">' +
  '<text x="1" y="1">本章说</text><text x="1" y="2">40条评论 〉</text></svg>');
served.set('http://zl.example/author.png', '\u0089PNG\r\n\u001a\n...');
const inlined = await converter.inlineRemoteSvgControls(null, remoteHtml, 'http://zl.example/api/v1/chapter', () => false);
assert.deepEqual(requested.sort(), ['http://zl.example/author.png', 'http://zl.example/discuss.svg?c=1',
  'http://zl.example/hot.svg?c=1'], 'only clickable cards are fetched, badges and plain images are not');
const remoteOut = convert(inlined);
const remoteActions = actions(remoteOut);
assert.deepEqual(remoteActions.map(item => item.label), ['热评', '段评 12', '段评 3', '章评']);
assert.equal(Marker.sourceScript(remoteActions[1].url), 'zlOpenPanel("http://zl.example/panel/review?p=12")');
assert.equal(remoteActions[0].preview, '书友乙 这章不错');
assert.equal(remoteActions[3].count, '40条评论');
const remoteRows = remoteOut.replace(/<\/p>/g, '\n').split('\n').map(line => line.replace(/<p[^>]*>/g, ''))
  .filter(line => line.trim() && !/<img/.test(line)).map(line => {
    const found = actions(line);
    return `${Marker.strip(line).trim()}${found.length ? `[${found[0].label}]` : ''}`;
  });
assert.deepEqual(remoteRows, ['[热评]', '玄灵大陆，金乌皇朝，开元城。[段评 12]', '没有评论的一段。', '又一段[段评 3]', '[章评]'],
  'each badge stays at the end of its own paragraph');
assert.match(remoteOut, /author\.png/, 'a raster card is left to the image pipeline');
// A second chapter reuses what was fetched.
requested.length = 0;
await converter.inlineRemoteSvgControls(null, remoteHtml, 'http://zl.example/api/v1/chapter', () => false);
assert.deepEqual(requested, []);

// Images that are icons get a small layout size instead of the full-page fallback.
assert.deepEqual(Array.from(converter.readerInlineIconSize(
  `<img src='http://x.example/i.png,{"style":"text"}'>`)), [24, 24]);
assert.deepEqual(Array.from(converter.readerInlineIconSize(
  `<img src='http://zl.example/warm' style='display:block;width:1px;height:1px'/>`)), [1, 1]);
assert.deepEqual(Array.from(converter.readerInlineIconSize('<img src="a.png" width="20" height="18">')), [20, 18]);
assert.deepEqual(Array.from(converter.readerInlineIconSize(
  `<img src='a.png' style='display:block;max-width:100%;width:100%'/>`)), [0, 0]);
assert.deepEqual(Array.from(converter.readerInlineIconSize('<img src="a.png" width="600" height="400">')), [0, 0]);

// Markers without a hot comment stay byte-identical to the old format.
assert.equal(Marker.create('段评 3', 'https://a.example/x', '段评'),
  `${Marker.PREFIX}${encodeURIComponent(JSON.stringify({ label: '段评 3', url: 'https://a.example/x', title: '段评' }))}]]`);
const withHot = Marker.parse(Marker.create('段评 3', 'https://a.example/x', '段评', '  好\n看  ', '1.2k'));
assert.equal(withHot.preview, '好 看');
assert.equal(withHot.likes, '1.2k');

console.log('reader-comment-markup-check: iOS bubbles/hot/chapter cards, notes, option cards, plain pictures and ' +
  'Android options, remote SVG controls passed');
