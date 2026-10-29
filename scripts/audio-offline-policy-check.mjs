// 有声书离线下载的纯逻辑回归：m3u8 解析与码率选择、AES IV、续传判断、
// 目录刷新后的章节对位、边听边下的目标与淘汰。下载本身依赖系统网络接口，只能真机验证。

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { readEtsModule, toNodeModuleSource } from './lib/ets-module-staging.mjs';

const MODULE = 'core/book/AudioOfflinePolicy.ts';
const stagingDir = fs.mkdtempSync(path.join(os.tmpdir(), 'audio-offline-policy-'));
let assertions = 0;

function assert(condition, message) {
  assertions++;
  if (!condition) throw new Error(message);
}

function equal(actual, expected, message) {
  assert(JSON.stringify(actual) === JSON.stringify(expected),
    `${message}\n  expected: ${JSON.stringify(expected)}\n  actual:   ${JSON.stringify(actual)}`);
}

function entry(fields) {
  return { chapterIndex: 0, chapterUrl: '', voice: '', bytes: 0, createdAt: 0, auto: false, ...fields };
}

try {
  const target = path.join(stagingDir, MODULE);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, toNodeModuleSource(readEtsModule(MODULE), MODULE));
  const { AudioOfflinePolicy, AudioPartialMeta, HlsSegment } = await import(pathToFileURL(target).href);

  // 相对地址解析。
  const base = 'https://cdn.example.com/audio/book/index.m3u8?sign=1';
  equal(AudioOfflinePolicy.resolveUrl('seg1.ts', base), 'https://cdn.example.com/audio/book/seg1.ts', '同目录相对地址');
  equal(AudioOfflinePolicy.resolveUrl('../k/key.bin?x=1', base), 'https://cdn.example.com/audio/k/key.bin?x=1', '上级目录');
  equal(AudioOfflinePolicy.resolveUrl('/root.ts', base), 'https://cdn.example.com/root.ts', '根路径');
  equal(AudioOfflinePolicy.resolveUrl('//other.example.com/a.ts', base), 'https://other.example.com/a.ts', '省略协议');
  equal(AudioOfflinePolicy.resolveUrl('http://x.example.com/a.ts', base), 'http://x.example.com/a.ts', '绝对地址原样');

  // 主列表：选码率最低的一档。
  const master = AudioOfflinePolicy.parsePlaylist([
    '#EXTM3U',
    '#EXT-X-STREAM-INF:BANDWIDTH=256000,CODECS="mp4a.40.2"',
    'high/index.m3u8',
    '#EXT-X-STREAM-INF:BANDWIDTH=64000',
    'low/index.m3u8'
  ].join('\n'), base);
  equal(master.variants.length, 2, '主列表解析出两档');
  equal(AudioOfflinePolicy.pickVariant(master.variants).url, 'https://cdn.example.com/audio/book/low/index.m3u8', '选最低码率');
  equal(master.unsupported, '', '主列表不算直播流');

  // 媒体列表：AES-128、媒体序号、结尾标记。
  const media = AudioOfflinePolicy.parsePlaylist([
    '﻿#EXTM3U',
    '#EXT-X-MEDIA-SEQUENCE:7',
    '#EXT-X-KEY:METHOD=AES-128,URI="key.bin"',
    '#EXTINF:10,',
    'a.ts',
    '#EXT-X-KEY:METHOD=AES-128,URI="key2.bin",IV=0x000102030405060708090A0B0C0D0E0F',
    '#EXTINF:10,',
    'b.ts',
    '#EXT-X-ENDLIST'
  ].join('\r\n'), base);
  equal(media.segments.map((s) => s.sequence), [7, 8], '媒体序号从 EXT-X-MEDIA-SEQUENCE 开始');
  equal(media.segments[0].keyUrl, 'https://cdn.example.com/audio/book/key.bin', '密钥地址相对列表解析');
  equal(media.unsupported, '', 'AES-128 可以下载');
  equal(AudioOfflinePolicy.segmentedExtension(media), 'ts', 'TS 分片拼成 ts');
  equal(Array.from(AudioOfflinePolicy.segmentIv(media.segments[0])).slice(-2), [0, 7], '没写 IV 时按序号推算');
  equal(Array.from(AudioOfflinePolicy.segmentIv(media.segments[1])).slice(0, 3), [0, 1, 2], '显式 IV 优先');
  const bigSequence = Object.assign(new HlsSegment(), { sequence: 258 });
  equal(Array.from(AudioOfflinePolicy.segmentIv(bigSequence)).slice(-2), [1, 2], '序号大于 255 时按大端写');

  const fmp4 = AudioOfflinePolicy.parsePlaylist('#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:5,\n1.m4s\n#EXT-X-ENDLIST', base);
  equal(fmp4.mapUrl, 'https://cdn.example.com/audio/book/init.mp4', '解析初始化段');
  equal(AudioOfflinePolicy.segmentedExtension(fmp4), 'm4a', 'fMP4 拼成 m4a');

  const sampleAes = AudioOfflinePolicy.parsePlaylist('#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI="k"\n#EXTINF:5,\n1.ts\n#EXT-X-ENDLIST', base);
  equal(sampleAes.unsupported, AudioOfflinePolicy.PROTECTED, 'SAMPLE-AES 不支持');
  const drm = AudioOfflinePolicy.parsePlaylist('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="k",KEYFORMAT="com.apple.streamingkeydelivery"\n#EXTINF:5,\n1.ts\n#EXT-X-ENDLIST', base);
  equal(drm.unsupported, AudioOfflinePolicy.PROTECTED, '非 identity 的 KEYFORMAT 视为 DRM');
  const live = AudioOfflinePolicy.parsePlaylist('#EXTM3U\n#EXTINF:5,\n1.ts', base);
  equal(live.unsupported, AudioOfflinePolicy.NOT_SEGMENTED_LIVE, '没有 ENDLIST 的是直播流');
  assert(AudioOfflinePolicy.isPlaylistText('  #EXTM3U\n'), '识别列表文本');
  assert(!AudioOfflinePolicy.isPlaylistText('ID3...'), '音频不是列表');

  // 续传判断。
  const meta = Object.assign(new AudioPartialMeta(), { bytes: 1000, total: 5000, etag: '"v1"' });
  equal(AudioOfflinePolicy.resumeDecision(206, 'bytes 1000-4999/5000', meta, '"v1"', ''), 'append', 'ETag 一致接着写');
  equal(AudioOfflinePolicy.resumeDecision(206, 'bytes 1000-4999/5000', meta, '"v2"', ''), 'restart', 'ETag 变了从头写');
  equal(AudioOfflinePolicy.resumeDecision(206, 'bytes 0-4999/5000', meta, '"v1"', ''), 'restart', '起点不对从头写');
  equal(AudioOfflinePolicy.resumeDecision(200, '', meta, '"v1"', ''), 'restart', '服务器不支持 Range 从头写');
  const noValidator = Object.assign(new AudioPartialMeta(), { bytes: 1000, total: 5000 });
  equal(AudioOfflinePolicy.resumeDecision(206, 'bytes 1000-4999/5000', noValidator, '', ''), 'append', '没有校验头时比总长');
  equal(AudioOfflinePolicy.resumeDecision(206, 'bytes 1000-5999/6000', noValidator, '', ''), 'restart', '总长变了从头写');
  equal(AudioOfflinePolicy.resumeDecision(206, 'bytes 1000-4999/*', Object.assign(new AudioPartialMeta(), { bytes: 1000 }), '', ''),
    'restart', '总长未知不冒险拼接');
  const partial = Object.assign(new AudioPartialMeta(), { bytes: 10, chapterUrl: 'c1', voice: 'v', updatedAt: 1000 });
  assert(AudioOfflinePolicy.partialUsable(partial, 'c1', 'v', 2000, 5000), '同章同音色可续传');
  assert(!AudioOfflinePolicy.partialUsable(partial, 'c1', 'w', 2000, 5000), '换音色不续传');
  assert(!AudioOfflinePolicy.partialUsable(partial, 'c2', 'v', 2000, 5000), '换章节不续传');
  assert(!AudioOfflinePolicy.partialUsable(partial, 'c1', 'v', 9000, 5000), '过期不续传');

  // 目录刷新后的对位。
  const sorted = (map) => [...map.entries()].sort((a, b) => a[0] - b[0]);
  const remap = AudioOfflinePolicy.remapEntries([
    entry({ chapterIndex: 0, chapterUrl: 'u0', chapterTitle: '第1集' }),
    entry({ chapterIndex: 1, chapterUrl: 'u1', chapterTitle: '第2集' }),
    entry({ chapterIndex: 2, chapterUrl: 'gone', chapterTitle: '已删除' }),
    entry({ chapterIndex: 3 })
  ], ['new', 'u0', 'u1', 'u3'], ['序', '第1集', '第2集', '第3集']);
  equal(sorted(remap), [[1, 0], [2, 1], [3, 3]], '插入新章后按地址后移，删掉的章节不再对应，旧记录按序号认');
  const tokenChanged = AudioOfflinePolicy.remapEntries([entry({ chapterIndex: 0, chapterUrl: 'u?t=1', chapterTitle: '第1集' })],
    ['u?t=2'], ['第1集']);
  equal(sorted(tokenChanged), [[0, 0]], '地址令牌变了但标题一致仍算同一章');
  const moved = AudioOfflinePolicy.remapEntries([entry({ chapterIndex: 0, chapterUrl: 'u?t=1', chapterTitle: '第1集' })],
    ['x', 'u?t=2'], ['序', '第1集']);
  equal(sorted(moved), [[1, 0]], '地址变了时按唯一标题找到新位置');
  equal(sorted(AudioOfflinePolicy.remapEntries([entry({ chapterIndex: 0, chapterUrl: 'dup', chapterTitle: '重复' })],
    ['x', 'dup', 'dup'], ['y', '重复', '重复'])), [], '地址和标题都重复且原位置变了就当没下载');
  assert(!AudioOfflinePolicy.entryMatches(entry({ chapterUrl: 'a', chapterTitle: 'A' }), 'b', 'B'), '地址和标题都不同不是同一章');

  // 边听边下。
  equal(AudioOfflinePolicy.prefetchTargets(4, 3, 7, new Set([5])), [6], '跳过已下载，不越过最后一章');
  const autos = [
    entry({ chapterIndex: 1, auto: true, bytes: 100, createdAt: 30 }),
    entry({ chapterIndex: 2, auto: false, bytes: 100, createdAt: 10 }),
    entry({ chapterIndex: 5, auto: true, bytes: 100, createdAt: 5 }),
    entry({ chapterIndex: 6, auto: true, bytes: 100, createdAt: 20 }),
    entry({ chapterIndex: 4, auto: true, bytes: 100, createdAt: 1 })
  ];
  equal(AudioOfflinePolicy.listenedAutoEntries(autos, 4).map((e) => e.chapterIndex), [1], '只删听过的自动下载');
  equal(AudioOfflinePolicy.capEvictions(autos, 4, 150).map((e) => e.chapterIndex), [1, 5],
    '先删听过的，再按时间删预下载，不动正在播的和手动下载的');
  equal(AudioOfflinePolicy.capEvictions(autos, 4, 0), [], '不超限不删');

  console.log(`audio-offline-policy-check: ${assertions} assertions passed`);
} finally {
  fs.rmSync(stagingDir, { recursive: true, force: true });
}
