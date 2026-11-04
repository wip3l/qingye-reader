// Run with: node scripts/http-tts-request-check.mjs
// Executes the production HttpTtsReader request-building methods without the device HTTP stack:
// form fields are split before {{...}} substitution, substituted values are always encoded, and
// the "timeout" URL option drives the request timeouts.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../entry/src/main/ets/utils/HttpTtsReader.ets', import.meta.url), 'utf8');
const names = [
  'buildRequest', 'readTimeoutFor', 'renderBody', 'escapeJsonString', 'parseRule', 'applyOptions',
  'parseTimeout', 'findOptionIndex', 'buildBody', 'renderUrl', 'renderParams', 'renderComponent',
  'splitOutsideTemplate', 'indexOutsideTemplate', 'encodeParams', 'encodeComponent', 'escapeComponent',
  'parseHeaders', 'recordToHeaders', 'mergeHeaders', 'hasHeader', 'findHeader', 'emptyHeaders',
  'looksLikeStructuredBody',
  'looksEncoded', 'toRequestMethod', 'normalizeCharset'
];
const methods = names.map(name => {
  const start = source.indexOf(`  private ${name}(`);
  assert.ok(start >= 0, `production method ${name}`);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
});
const classes = ['TtsRequestRule', 'TtsRequestResult'].map(name => {
  const start = source.indexOf(`class ${name} {`);
  assert.ok(start >= 0, `production class ${name}`);
  return source.slice(start, source.indexOf('\n}', start) + 2);
});
const constants = source.split('\n')
  .filter(line => line.includes('private static readonly ') && line.trimEnd().endsWith(';'));

// Stand-in for JsRuntime.evalTemplate: a textual {{var}} replace, like the production runtime.
class FakeRuntime {
  vars = {};
  setVar(name, value) { this.vars[name] = value; }
  evalTemplate(tpl) {
    return tpl.replace(/\{\{([\s\S]*?)\}\}/g, (_, expr) => {
      const key = expr.trim();
      return key in this.vars ? this.vars[key] : `<${key}>`;
    });
  }
  evaluate(js, body) { return js === 'upper' ? body.toUpperCase() : ''; }
}
const http = { RequestMethod: { GET: 'GET', POST: 'POST', PUT: 'PUT', DELETE: 'DELETE', HEAD: 'HEAD' } };
const Reader = vm.runInNewContext(stripTypeScriptTypes(`${classes.join('\n')}
class HttpTtsReader { ${constants.join('\n')}
  runtimeForVoice(voice, text, speed) {
    const runtime = new FakeRuntime();
    runtime.setVar('speakText', text);
    runtime.setVar('text', text);
    runtime.setVar('speakSpeed', String(speed));
    return runtime;
  }
  ${methods.join('\n')} }; HttpTtsReader`), { http, FakeRuntime, console });
const reader = new Reader();
const build = (url, text, extra = {}) => reader.buildRequest({ url, header: '', ...extra }, text, 10);

// 02: a paragraph containing '&' / '=' stays inside its own form field.
{
  const request = build('@https://h/tts?voice=a&text={{speakText}}&rate={{speakSpeed}}', '甲&乙=丙、a=b&c，还有 ?q=1#frag');
  assert.equal(request.method, 'POST');
  assert.equal(request.url, 'https://h/tts');
  const fields = request.body.split('&');
  assert.deepEqual(fields.map(f => f.split('=')[0]), ['voice', 'text', 'rate'], 'three fields, no stray ones');
  assert.equal(decodeURIComponent(fields[1].substring(5).replace(/\+/g, '%20')), '甲&乙=丙、a=b&c，还有 ?q=1#frag');
  assert.equal(fields[2], 'rate=10');
}
// 02: the same holds for a query string on a GET request.
{
  const request = build('https://h/tts?text={{speakText}}&k=v', 'x&y=z');
  assert.equal(request.url, 'https://h/tts?text=x%26y%3Dz&k=v');
}
// 02: the url,{options} form with a form body.
{
  const request = build('https://h/tts,{"method":"POST","body":"voice=a&text={{speakText}}","retry":2}', '一&二');
  assert.equal(request.body, 'voice=a&text=%E4%B8%80%26%E4%BA%8C');
  assert.equal(request.retry, 2);
  assert.match(request.headers['Content-Type'], /x-www-form-urlencoded/);
}
// 04: substituted text that looks percent-encoded is still encoded; literal template text is not.
{
  const request = build('@https://h/tts?pre=%E4%BD%A0&text={{speakText}}', 'a%2Fb 50%25');
  assert.equal(request.body, 'pre=%E4%BD%A0&text=a%252Fb+50%2525');
  const query = build('https://h/tts?pre=%E4%BD%A0&text={{speakText}}', 'a%2Fb');
  assert.equal(query.url, 'https://h/tts?pre=%E4%BD%A0&text=a%252Fb');
}
// Template expressions containing '&' or '=' are not field boundaries.
{
  assert.deepEqual([...reader.splitOutsideTemplate('a={{x && y}}&b={{c = 1}}', '&')], ['a={{x && y}}', 'b={{c = 1}}']);
  assert.equal(reader.indexOutsideTemplate('{{a=b}}=c', '=', 0), 7);
}
// JSON bodies and bodyJs keep the whole-string path.
{
  const json = build('https://h/tts,{"method":"POST","body":{"input":"{{speakText}}"}}', '说"你好"&再见');
  assert.equal(JSON.parse(json.body).input, '说"你好"&再见');
  assert.match(json.headers['Content-Type'], /application\/json/);
  const js = build('https://h/tts,{"method":"POST","body":"text={{speakText}}","bodyJs":"upper"}', 'ab');
  assert.equal(js.body, 'TEXT=AB');
}
// 07: timeouts default to 15 s connect / 60 s read; "timeout" raises the read timeout only.
{
  assert.equal(reader.readTimeoutFor(build('https://h/tts', 'x')), 60000);
  assert.equal(Reader.DEFAULT_CONNECT_TIMEOUT_MS, 15000);
  const custom = build('https://h/tts,{"method":"POST","body":"t={{speakText}}","timeout":120000}', 'x');
  assert.equal(custom.timeout, 120000);
  assert.equal(reader.readTimeoutFor(custom), 120000);
  assert.equal(Math.min(Reader.DEFAULT_CONNECT_TIMEOUT_MS, reader.readTimeoutFor(custom)), 15000);
  const invalid = build('https://h/tts,{"method":"POST","body":"t={{speakText}}","timeout":"abc"}', 'x');
  assert.equal(reader.readTimeoutFor(invalid), 60000);
  // Regex fallback for options that are not valid JSON.
  const loose = build("https://h/tts,{method:'POST',body:'t={{speakText}}',retry:3,timeout:9000}", 'x');
  assert.equal(loose.retry, 3);
  assert.equal(loose.timeout, 9000);
  assert.equal(loose.body, 't=x');
}
console.log('http-tts-request-check: ok');
