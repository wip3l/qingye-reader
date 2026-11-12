// node scripts/explore-text-menu-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const file = `${projectRoot}/entry/src/main/ets/core/book/ExploreTextMenu.ts`;
const code = stripTypeScriptTypes(fs.readFileSync(file, 'utf8')).replace(/^export /gm, '');
const ExploreTextMenu = new Function(`${code}\nreturn ExploreTextMenu;`)();

// 发现脚本最外层 return 的“名称::地址”文本：分组标题行地址为空，空行跳过。
const hdr = ',{"headers":{"Cookie":"_csrfToken=8","Referer":"https://m.qidian.com/"}}';
const scriptOutput = [
  '男频榜单::',
  `月票榜单::https://m.qidian.com/majax/rank/yuepiaolist?_csrfToken=8&gender=male&pageNum={{page}}${hdr}`,
  `畅销榜单::https://m.qidian.com/majax/rank/hotsaleslist?_csrfToken=8&gender=male&pageNum={{page}}${hdr}`,
  '',
  '女频分类::',
  `古代情缘::https://m.qidian.com/majax/category/list?catId=80&subCatId=801&gender=female&_csrfToken=8&pageNum={{page}}${hdr}`
].join('\n');
const items = ExploreTextMenu.parse(scriptOutput);
assert.equal(items.length, 5);
assert.deepEqual(items[0], { title: '男频榜单', url: '' });
assert.equal(items[1].title, '月票榜单');
assert.equal(items[1].url,
  `https://m.qidian.com/majax/rank/yuepiaolist?_csrfToken=8&gender=male&pageNum={{page}}${hdr}`);
assert.deepEqual(items[3], { title: '女频分类', url: '' });
assert.equal(items[4].title, '古代情缘');

// Legado 也用 && 分隔条目；地址里再出现 :: 时只按第一个拆。
assert.deepEqual(ExploreTextMenu.parse('玄幻::/a?p={{page}}&&都市::https://x.com/b::c\r\n分组'), [
  { title: '玄幻', url: '/a?p={{page}}' },
  { title: '都市', url: 'https://x.com/b::c' },
  { title: '分组', url: '' }
]);

// 不含 :: 的普通文本（报错、提示）不当成分类。
assert.deepEqual(ExploreTextMenu.parse('请先登录'), []);
assert.deepEqual(ExploreTextMenu.parse(''), []);

// 接入点：JSON 解析失败时交给文本解析。
const coordinator = fs.readFileSync(`${projectRoot}/entry/src/main/ets/core/book/ExploreCoordinator.ts`, 'utf8');
const start = coordinator.indexOf('private parseExploreScriptResult(');
const body = coordinator.slice(start, coordinator.indexOf('\n  }\n', start));
assert.match(body, /catch \(_\) \{[\s\S]*return ExploreTextMenu\.parse\(raw\);/);

console.log('explore-text-menu-check passed');
