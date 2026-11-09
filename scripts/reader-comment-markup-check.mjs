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
const names = ['convertReaderNativeActions', 'convertReaderImageScriptActions', 'readerActionMarkerFromClickableImage',
  'readerActionMarkerFromCommentAttributes', 'readerImageOptionString', 'readerDataImageLabel', 'readerDataImageText',
  'decodeHtmlEntities'];
const util = {
  Base64Helper: class { decodeSync(text) { return Uint8Array.from(Buffer.from(text, 'base64')); } },
  TextDecoder: { create: () => ({ decodeWithStream: bytes => Buffer.from(bytes).toString('utf8') }) }
};
const context = vm.createContext({ util });
vm.runInContext(compile(markerSource.replace(/^export /gm, '') +
  `\nclass Converter {\n${names.map(name => method(service, name)).join('\n')}\n}\n`) +
  'globalThis.Converter = Converter; globalThis.ReaderActionMarker = ReaderActionMarker;', context);
const converter = new context.Converter();
const Marker = context.ReaderActionMarker;
const convert = text => converter.convertReaderNativeActions(null, text, '');
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

console.log('reader-comment-markup-check: iOS bubbles/hot/chapter cards, plain pictures and Android options passed');
