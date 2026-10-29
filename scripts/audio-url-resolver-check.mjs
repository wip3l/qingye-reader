// 有声书播放与离线下载共用的地址解析回归：JSON / HTML / 字段 / 媒体扩展名 / 相对地址的取址顺序，
// 以及请求头的合并与跨站收敛。书源内核里的 URL 拼接和 Cookie 读取换成桩，只测这里自己的逻辑。

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { readEtsModule, toNodeModuleSource } from './lib/ets-module-staging.mjs';

const stagingDir = fs.mkdtempSync(path.join(os.tmpdir(), 'audio-url-resolver-'));
let assertions = 0;

function assert(condition, message) {
  assertions++;
  if (!condition) throw new Error(message);
}

function equal(actual, expected, message) {
  assert(JSON.stringify(actual) === JSON.stringify(expected),
    `${message}\n  expected: ${JSON.stringify(expected)}\n  actual:   ${JSON.stringify(actual)}`);
}

const STUB = `
export class BookSource { bookSourceUrl = ''; header = ''; }
export class BookUrlResolver {
  static resolve(value, base) {
    try { return new URL(value, base || undefined).href; } catch (_) { return value; }
  }
}
export class VerificationSupport {
  static sourceCookieHeader(source, url) { return source.cookieForTest && url.includes(source.cookieForTest.host) ? source.cookieForTest.value : ''; }
}
`;

try {
  for (const relative of ['core/rule/JavaRegexCompat.ts', 'core/book/AudioRuleSupport.ts']) {
    const target = path.join(stagingDir, relative);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, toNodeModuleSource(readEtsModule(relative), relative));
  }
  const resolverPath = path.join(stagingDir, 'core/book/AudioUrlResolver.ts');
  fs.writeFileSync(path.join(stagingDir, 'core/book/engine-stub.ts'), STUB);
  const resolverSource = readEtsModule('core/book/AudioUrlResolver.ts')
    .replace(/^import \{[^}]*\} from '@legado\/sourceengine';/m, "import { BookSource, BookUrlResolver, VerificationSupport } from './engine-stub.ts';")
    .replace("from './AudioRuleSupport'", "from './AudioRuleSupport.ts'");
  assert(resolverSource.includes("from './engine-stub.ts'"), '应替换书源内核导入');
  fs.writeFileSync(resolverPath, resolverSource);
  const { AudioUrlResolver } = await import(pathToFileURL(resolverPath).href);
  const { BookSource } = await import(pathToFileURL(path.join(stagingDir, 'core/book/engine-stub.ts')).href);
  const base = 'https://api.example.com/book/1/chapter/2';

  // 取址顺序。
  equal(AudioUrlResolver.resolveAudioUrl('https://cdn.example.com/a.mp3', base), 'https://cdn.example.com/a.mp3', '直链原样');
  equal(AudioUrlResolver.resolveAudioUrl('"https://cdn.example.com/q.mp3"', base), 'https://cdn.example.com/q.mp3', '带引号的 JSON 字符串');
  equal(AudioUrlResolver.resolveAudioUrl('{"code":0,"data":{"play_url":"https:\\/\\/cdn.example.com\\/b.m4a"}}', base),
    'https://cdn.example.com/b.m4a', '嵌套 JSON 字段并解开转义斜杠');
  equal(AudioUrlResolver.resolveAudioUrl('{"data":{"url_list":["", "https://cdn.example.com/c.mp3"]}}', base),
    'https://cdn.example.com/c.mp3', '数组里取第一个有效地址');
  equal(AudioUrlResolver.resolveAudioUrl('<div><img src="https://x.example.com/cover.jpg"><audio src="/media/d.mp3"></audio></div>', base),
    'https://api.example.com/media/d.mp3', 'HTML 里取 audio 标签并解析相对地址');
  equal(AudioUrlResolver.resolveAudioUrl('var cover="https://x.example.com/c.jpg"; var u="https://cdn.example.com/e.m3u8?t=1";', base),
    'https://cdn.example.com/e.m3u8?t=1', '脚本里优先取媒体扩展名的地址');
  equal(AudioUrlResolver.resolveAudioUrl('audio_url: "f.mp3"', base), 'https://api.example.com/book/1/chapter/f.mp3', '字段写法里的相对地址');
  equal(AudioUrlResolver.resolveAudioUrl('&quot;https://cdn.example.com/g.mp3&quot;', base), 'https://cdn.example.com/g.mp3', 'HTML 实体');
  equal(AudioUrlResolver.resolveAudioUrl('https://cdn.example.com/h.mp3,{"headers":{"Referer":"https://a.example.com"}}', base),
    'https://cdn.example.com/h.mp3', '地址后带请求头选项时只取地址');
  equal(AudioUrlResolver.resolveAudioUrl('javascript:void(0)', base), '', '拒绝 javascript 地址');
  equal(AudioUrlResolver.resolveAudioUrl('', base), '', '空内容');
  equal(AudioUrlResolver.resolveAudioUrl('请先登录', base), '', '提示文字不是地址');

  // 无效地址的说明。
  equal(AudioUrlResolver.invalidAudioAddressMessage('{"code":403,"msg":"会员专享"}'), '音频接口未返回可播放地址：会员专享',
    '接口给出的原因要带出来');
  equal(AudioUrlResolver.invalidAudioAddressMessage('<html></html>'), '正文规则没有返回有效音频地址', '没有原因时用通用说明');

  // 请求头：书源头只发到书源自己的站点，地址自带的头总是生效，Cookie 按媒体地址取。
  const source = new BookSource();
  source.bookSourceUrl = 'https://api.example.com';
  source.header = '{"Referer":"https://api.example.com/","Cookie":"sid=1","X-Token":"java.get(\'t\')"}';
  const sameSite = AudioUrlResolver.audioHeaders('https://api.example.com/a.mp3', source, '');
  equal(sameSite['Referer'], 'https://api.example.com/', '同站带上书源 Referer');
  assert(!('X-Token' in sameSite), '含 java. 的动态头不发');
  assert(typeof sameSite['User-Agent'] === 'string' && sameSite['User-Agent'].length > 0, '默认带 User-Agent');
  const crossSite = AudioUrlResolver.audioHeaders('https://cdn.other.com/a.mp3', source, '');
  assert(!Object.keys(crossSite).some((key) => key.toLowerCase() === 'cookie'), '跨站不带书源 Cookie');
  const explicit = AudioUrlResolver.audioHeaders('https://cdn.other.com/a.mp3', source,
    'https://cdn.other.com/a.mp3,{"headers":{"Referer":"https://other.com/"}}');
  equal(explicit['Referer'], 'https://other.com/', '地址自带的请求头优先');
  source.cookieForTest = { host: 'cdn.other.com', value: 'media=2' };
  equal(AudioUrlResolver.audioHeaders('https://cdn.other.com/a.mp3', source, '')['Cookie'], 'media=2',
    '媒体地址自己的 Cookie 跨站也带');
  equal(Object.keys(AudioUrlResolver.audioHeaders('https://x.com/a.mp3', null, '')), ['User-Agent'], '没有书源时只有 UA');

  console.log(`audio-url-resolver-check: ${assertions} assertions passed`);
} finally {
  fs.rmSync(stagingDir, { recursive: true, force: true });
}
