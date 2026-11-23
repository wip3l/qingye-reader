// 设置搜索索引检查：登记的标题要能在页面里找到，登记过的页面里新增的设置行也要登记；顺带验几条常见叫法的排序。
// 运行：node --experimental-strip-types scripts/settings-search-index-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  SETTINGS_SEARCH_ENTRIES,
  searchSettings,
  settingsHighlightParts,
  normalizeSettingsQuery
} from '../entry/src/main/ets/utils/SettingsSearchIndex.ts';

const root = path.resolve(import.meta.dirname, '..');
const etsRoot = path.join(root, 'entry/src/main/ets');
const read = (file) => fs.readFileSync(file, 'utf8');
const failures = [];

/** 不进搜索的设置行：确认弹窗、一次性操作、只在特定状态出现的提示行。 */
const IGNORED = new Map([
  ['Settings', ['恢复主题预设', '从其他主题复制排版', '眼动校准', '每页最多', '卡片行数']],
  ['TtsSettings', ['兑换在线朗读字数']],
  ['LabSettings', ['后台脚本线程验证']],
  ['WebParseSettings', ['请确认使用须知', '使用须知']],
  ['OtherSettings', ['删除离线音频？', '删除离线内容？', '其他设置']],
  ['DataSync', ['书源']],
  ['BookshelfSettings', ['重置隐私书架']],
  ['CoverSettings', ['书籍自带封面']]
]);

// 1. 路由页面存在
for (const entry of SETTINGS_SEARCH_ENTRIES) {
  if (!entry.page.url) continue;
  const file = path.join(etsRoot, `${entry.page.url}.ets`);
  if (!fs.existsSync(file)) failures.push(`${entry.title}：路由 ${entry.page.url} 没有对应页面`);
}

// 2. 要高亮的标题在页面源码里有同样的字面量
const pageKeys = new Set(SETTINGS_SEARCH_ENTRIES.filter((e) => e.focus).map((e) => e.page.key));
const sources = new Map();
for (const key of pageKeys) sources.set(key, read(path.join(etsRoot, 'pages', `${key}.ets`)));
for (const entry of SETTINGS_SEARCH_ENTRIES) {
  if (!entry.focus) continue;
  if (!sources.get(entry.page.key).includes(`'${entry.focus}'`)) {
    failures.push(`${entry.page.key}：找不到设置行“${entry.focus}”，页面改了标题要同步 SettingsSearchIndex.ts`);
  }
}

// 3. 登记过的页面里，字面标题的设置行都要登记或列入 IGNORED
const rowTitleRe = /(?:SettingSwitchRow|SettingNavRow|SettingRow|SettingScopeRow)\(\{[^}]*?title:\s*'([^']+)'/gs;
const selectRe = /this\.selectItem\('([^']+)'/g;
for (const key of pageKeys) {
  const src = sources.get(key);
  const registered = new Set(SETTINGS_SEARCH_ENTRIES.filter((e) => e.page.key === key).map((e) => e.focus));
  // 入口行（小说、漫画、排版……）已作为“直接打开对应页面”的条目登记。
  SETTINGS_SEARCH_ENTRIES.filter((e) => !e.focus).forEach((e) => registered.add(e.title));
  const ignored = new Set(IGNORED.get(key) ?? []);
  const titles = new Set([...src.matchAll(rowTitleRe), ...src.matchAll(selectRe)].map((m) => m[1]));
  for (const title of titles) {
    if (!registered.has(title) && !ignored.has(title)) {
      failures.push(`${key}：设置行“${title}”没有登记到 SettingsSearchIndex.ts（不该被搜到就加进本脚本的 IGNORED）`);
    }
  }
}

// 4. 排版面板滑杆与 ReaderTypographyField.LABELS 一致
const layoutSrc = read(path.join(etsRoot, 'components/reader/ReaderLayoutSettings.ets'));
const labels = /static readonly LABELS: string\[\] = \[([^\]]+)\]/.exec(layoutSrc)[1]
  .split(',').map((s) => s.trim().replace(/^'|'$/g, ''));
for (const label of labels) {
  const hit = SETTINGS_SEARCH_ENTRIES.find((e) => e.title === label && e.page.params?.group === '0');
  if (!hit) failures.push(`排版滑杆“${label}”没有登记`);
}

// 5. 定位链路：设置行认领、PageScaffold 登记滚动容器
const rowSrc = read(path.join(etsRoot, 'components/common/SettingRow.ets'));
const scaffoldSrc = read(path.join(etsRoot, 'components/common/PageScaffold.ets'));
if ((rowSrc.match(/SettingsFocus\.claim\(this\.title\)/g) ?? []).length < 2) failures.push('SettingRow/SettingScopeRow 没有认领搜索定位');
if (!scaffoldSrc.includes('SettingsFocus.bindScroller(this.scroller)')) failures.push('PageScaffold 没有登记滚动容器');

// 6. 常见叫法的排序
const first = (query) => searchSettings(query)[0]?.title;
assert.equal(first('息屏'), '亮屏时间设置');
assert.equal(first('字体大小'), '字号');
assert.equal(first('字号'), '字号');
assert.equal(first('音量键'), '音量键翻页');
assert.ok(searchSettings('夜间').slice(0, 3).some((e) => e.title === '显示模式'), '“夜间”应能搜到显示模式');
assert.equal(searchSettings('漫画 超分')[0]?.page.key, 'ComicSettings');
assert.equal(first('ＡＩ超分'), 'AI超分');
assert.deepEqual(searchSettings('   '), []);
assert.deepEqual(searchSettings('完全不存在的设置名'), []);
assert.deepEqual(settingsHighlightParts('亮屏时间设置', '时间'), ['亮屏', '时间', '设置']);
assert.deepEqual(settingsHighlightParts('HTTP/1.1 兼容模式', 'http'), ['', 'HTTP', '/1.1 兼容模式']);
assert.equal(normalizeSettingsQuery(' Ｗi-Fi '), 'wi-fi');
const gated = searchSettings('精准搜索')[0];
assert.equal(gated?.requiresWebParse, true, '搜索与发现里的设置需标记在线阅读');

if (failures.length > 0) {
  console.error(failures.join('\n'));
  process.exit(1);
}
console.log(`settings search index check passed (${SETTINGS_SEARCH_ENTRIES.length} entries)`);
