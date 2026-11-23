// 新书默认分组规则检查：三种设置、书架页签取值、分组被删后的回落，以及各加入书架入口都接上了默认分组。
// 运行：node --experimental-strip-types scripts/new-book-group-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { NewBookGroup } from '../entry/src/main/ets/utils/NewBookGroup.ts';

const root = path.resolve(import.meta.dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

// 设置取值
assert.equal(NewBookGroup.normalizeMode('last'), 'last');
assert.equal(NewBookGroup.normalizeMode('shelf'), 'shelf');
assert.equal(NewBookGroup.normalizeMode('bogus'), 'none');
assert.equal(NewBookGroup.normalizeMode(undefined), 'none');
assert.equal(NewBookGroup.modeIndex('shelf'), 2);
assert.equal(NewBookGroup.modeIndex('bogus'), 0);
assert.equal(NewBookGroup.MODES.length, NewBookGroup.LABELS.length);

const groups = [3, 5, 8];
// 未分组：什么都不放
assert.equal(NewBookGroup.pick('none', 5, 8, groups), 0);
// 上次选的分组
assert.equal(NewBookGroup.pick('last', 5, 8, groups), 5);
assert.equal(NewBookGroup.pick('last', 0, 8, groups), 0, '上次选了未分组');
assert.equal(NewBookGroup.pick('last', 9, 8, groups), 0, '上次选的分组已删除');
// 书架当前所在分组：0 = 全部、-1 = 未分组页签都不放进分组
assert.equal(NewBookGroup.pick('shelf', 5, 8, groups), 8);
assert.equal(NewBookGroup.pick('shelf', 5, 0, groups), 0);
assert.equal(NewBookGroup.pick('shelf', 5, -1, groups), 0);
assert.equal(NewBookGroup.pick('shelf', 5, 4, groups), 0, '书架停在已删除的分组');

assert.equal(NewBookGroup.addedToast(''), '已加入书架');
assert.equal(NewBookGroup.addedToast('玄幻'), '已加入书架 · 玄幻');
assert.ok(NewBookGroup.UNGROUPED <= 0, '未分组取值要被书架当作未分组');

// 入口接线：新书与试读转正都套默认分组
const helper = read('entry/src/main/ets/utils/SearchBookShelfHelper.ets');
assert.equal((helper.match(/NewBookGroupStore\.apply\(/g) ?? []).length, 2, '搜索/发现加入书架两条路径');
const detail = read('entry/src/main/ets/pages/SearchBookDetail.ets');
assert.equal((detail.match(/NewBookGroupStore\.apply\(/g) ?? []).length, 4, '详情页三条加入路径 + 试读返回加入');
assert.ok(!/group = -2147483645/.test(helper + detail), '未分组统一用 NewBookGroup.UNGROUPED');
assert.ok(detail.includes('this.addToShelf(true)'), '顶栏书架钮要出“放进分组”提示条');

console.log('new book group check passed');
