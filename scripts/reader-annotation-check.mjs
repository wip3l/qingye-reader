// 划线与笔记：文件排版脚本能编译，选区在两种排版的正文之间互相定位。
// node --experimental-strip-types scripts/reader-annotation-check.mjs
import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { loadReaderModules } from './lib/load-reader-modules.mjs';

const m = await loadReaderModules();
try {
  const options = new m.EpubOriginalLayoutOptions();
  options.forceDark = true;
  const injection = m.EpubOriginalScript.injection(options);
  new vm.Script(injection.script);
  assert(injection.script.includes('"dark":true'), 'dark flag reaches the script');
  assert(m.EpubOriginalScript.HOST_METHODS.includes('annotation'));

  const content = '　　第一段说了一句话。\n　　他说：“好。”\n　　她也说：“好。”\n';
  const range = m.EpubOriginalPosition.locate(content, '她也说：“好。”', '他说：“好。”', '', 0.6);
  assert(range, 'quote found');
  assert.equal(content.substring(range[0], range[1]), '她也说：“好。”');
  const ambiguous = m.EpubOriginalPosition.locate(content, '好。”', '她也说：“', '', 0);
  assert.equal(ambiguous[0], content.lastIndexOf('好。”'), 'context picks the second occurrence');
  const across = m.EpubOriginalPosition.locate(content, '一句话。他说', '', '', 0);
  assert.equal(content.substring(across[0], across[1]), '一句话。\n　　他说', 'selection across paragraphs maps back');
  assert.equal(m.EpubOriginalPosition.locate(content, '不存在', '', '', 0), null);
  const marker = m.ReaderActionMarker.create('注1', 'legado-note://1');
  const withMarker = '正文' + marker + '后面';
  assert.equal(m.EpubOriginalPosition.compactOf(withMarker), '正文注1后面', 'action markers compact to their label');
} finally {
  m.cleanup();
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'annotation-check-'));
try {
  fs.copyFileSync(new URL('../entry/src/main/ets/model/reader/BookAnnotation.ts', import.meta.url), path.join(dir, 'BookAnnotation.ts'));
  const { BookAnnotation, BookAnnotationAnchor } = await import(pathToFileURL(path.join(dir, 'BookAnnotation.ts')).href);
  const web = new BookAnnotation();
  web.quote = '一句话。\n他说';
  web.prefix = '第一段说了';
  web.suffix = '：“好。”';
  web.start = 3;
  web.end = 9;
  const paged = '　　第一段说了一句话。\n\n　　他说：“好。”\n';
  const resolved = BookAnnotationAnchor.resolve(web, paged);
  assert(resolved, 'web quote resolves in reader text without matching whitespace');
  assert.equal(paged.substring(resolved[0], resolved[1]), '一句话。\n\n　　他说');
  const trimmed = BookAnnotationAnchor.trim('　　x　', 0, 5);
  assert.deepEqual(trimmed, [2, 3], 'trim drops full-width spaces');
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}
console.log('PASS: annotation script compiles; locate and compact resolve map selections across layouts');
