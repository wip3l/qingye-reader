// 视频书源 content.playlist 的纯逻辑回归：识别 HLS 播放列表、按 lowLatency 去掉 LL-HLS 标签、
// 本机代理转交时改写地址（子播放列表指回代理，分片和密钥指向源站）。代理本身依赖系统网络接口，只能真机验证。

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { readEtsModule, toNodeModuleSource } from './lib/ets-module-staging.mjs';

const MODULES = ['core/book/VideoPlaylistSupport.ts', 'core/book/AudioOfflinePolicy.ts'];
const stagingDir = fs.mkdtempSync(path.join(os.tmpdir(), 'video-playlist-'));
let assertions = 0;

function assert(condition, message) {
  assertions++;
  if (!condition) throw new Error(message);
}

function equal(actual, expected, message) {
  assert(JSON.stringify(actual) === JSON.stringify(expected),
    `${message}\n  expected: ${JSON.stringify(expected)}\n  actual:   ${JSON.stringify(actual)}`);
}

try {
  for (const module of MODULES) {
    const target = path.join(stagingDir, module);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, toNodeModuleSource(readEtsModule(module), module));
  }
  const { VideoPlaylistSupport } = await import(pathToFileURL(path.join(stagingDir, MODULES[0])).href);
  const BOM = String.fromCharCode(0xFEFF);

  assert(VideoPlaylistSupport.looksLikePlaylist('#EXTM3U\n'), '正文开头');
  assert(VideoPlaylistSupport.looksLikePlaylist(`${BOM}  #EXTM3U\n`), '带 BOM 和空白');
  assert(!VideoPlaylistSupport.looksLikePlaylist('<html>'), '网页不是播放列表');

  const live = [
    '#EXTM3U',
    '#EXT-X-VERSION:9',
    '#EXT-X-TARGETDURATION:4',
    '#EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,PART-HOLD-BACK=3.0',
    '#EXT-X-PART-INF:PART-TARGET=1.0',
    '#EXT-X-MEDIA-SEQUENCE:100',
    '#EXT-X-MAP:URI="init.mp4"',
    '#EXT-X-PART:DURATION=1.0,URI="100.0.mp4",INDEPENDENT=YES',
    '#EXTINF:4.0,',
    '100.mp4',
    '#EXT-X-PART:DURATION=1.0,URI="101.0.mp4"',
    '#EXT-X-PRELOAD-HINT:TYPE=PART,URI="101.1.mp4"',
    '#EXT-X-RENDITION-REPORT:URI="../720p/index.m3u8",LAST-MSN=101',
    ''
  ].join('\r\n');
  equal(VideoPlaylistSupport.stripLowLatency(live).split('\n'), [
    '#EXTM3U', '#EXT-X-VERSION:9', '#EXT-X-TARGETDURATION:4', '#EXT-X-MEDIA-SEQUENCE:100',
    '#EXT-X-MAP:URI="init.mp4"', '#EXTINF:4.0,', '100.mp4', ''
  ], '去掉分片预告、阻塞刷新与其他码率报告，保留完整分片');
  const plain = '#EXTM3U\n#EXTINF:6,\na.ts\n#EXT-X-ENDLIST\n';
  equal(VideoPlaylistSupport.stripLowLatency(plain), plain, '普通 HLS 原样');

  const mapper = {
    playlist: (url) => `P[${url}]`,
    media: (url) => `M[${url}]`
  };
  const base = 'https://cdn.example.com/live/abc/index.m3u8?token=1';
  const master = [
    '#EXTM3U',
    '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="zh",URI="audio/zh.m3u8"',
    '#EXT-X-STREAM-INF:BANDWIDTH=1000000,AUDIO="a"',
    '720p/index.m3u8?sig=x',
    '#EXT-X-STREAM-INF:BANDWIDTH=500000',
    '//other.example.com/480p/playlist',
    '#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=90000,URI="iframe.m3u8"',
    ''
  ].join('\n');
  equal(VideoPlaylistSupport.rewrite(master, base, true, mapper).split('\n'), [
    '#EXTM3U',
    '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="zh",URI="P[https://cdn.example.com/live/abc/audio/zh.m3u8]"',
    '#EXT-X-STREAM-INF:BANDWIDTH=1000000,AUDIO="a"',
    'P[https://cdn.example.com/live/abc/720p/index.m3u8?sig=x]',
    '#EXT-X-STREAM-INF:BANDWIDTH=500000',
    'P[https://other.example.com/480p/playlist]',
    '#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=90000,URI="P[https://cdn.example.com/live/abc/iframe.m3u8]"',
    ''
  ], '多码率：子播放列表（含没有 .m3u8 后缀的）指回代理，地址按源站补全');

  const media = [
    `${BOM}#EXTM3U`,
    '#EXT-X-KEY:METHOD=AES-128,URI="/keys/k1?t=2",IV=0x01',
    '#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://drm-id"',
    '#EXT-X-MAP:URI="init.mp4"',
    '#EXTINF:4.0,',
    'seg/100.ts',
    '#EXT-X-PART:DURATION=1.0,URI="seg/101.0.mp4"',
    '#EXT-X-RENDITION-REPORT:URI="../720p/index.m3u8",LAST-MSN=101',
    '#EXTINF:4.0,',
    'https://edge.example.com/seg/101.ts',
    ''
  ].join('\r\n');
  equal(VideoPlaylistSupport.rewrite(media, base, true, mapper).split('\n'), [
    '#EXTM3U',
    '#EXT-X-KEY:METHOD=AES-128,URI="M[https://cdn.example.com/keys/k1?t=2]",IV=0x01',
    '#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://drm-id"',
    '#EXT-X-MAP:URI="M[https://cdn.example.com/live/abc/init.mp4]"',
    '#EXTINF:4.0,',
    'M[https://cdn.example.com/live/abc/seg/100.ts]',
    '#EXT-X-PART:DURATION=1.0,URI="M[https://cdn.example.com/live/abc/seg/101.0.mp4]"',
    '#EXT-X-RENDITION-REPORT:URI="P[https://cdn.example.com/live/720p/index.m3u8]",LAST-MSN=101',
    '#EXTINF:4.0,',
    'M[https://edge.example.com/seg/101.ts]',
    ''
  ], '分片、密钥、初始化段与部分分片指向源站；skd 等非 http 地址不动；去掉 BOM、换行统一');
  equal(VideoPlaylistSupport.rewrite(media, base, false, mapper).split('\n').filter((l) => l.startsWith('#EXT-X-PART') ||
    l.startsWith('#EXT-X-RENDITION-REPORT')), [], 'lowLatency 为 false 时先去掉 LL-HLS 标签再改写');

  console.log(`video-playlist-check: ${assertions} assertions passed`);
} finally {
  fs.rmSync(stagingDir, { recursive: true, force: true });
}
