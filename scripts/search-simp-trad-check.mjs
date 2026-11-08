// 简繁同搜：简→繁（台湾用字）转换、关键词变体、书源用字判断与补搜决策，以及搜索接入点。
// node --experimental-strip-types scripts/search-simp-trad-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const engine = path.join(root, 'harmony-book-ai-engine/aiengine/src/main');
const context = vm.createContext({ Map, Set, Number, Math, Error, Array, RegExp, String });
function load(file) {
  const code = fs.readFileSync(file, 'utf8').replace(/^import [^;]*;\r?\n/gm, '').replace(/^export /gm, '');
  vm.runInContext(stripTypeScriptTypes(code, { mode: 'strip' }), context);
}
load(path.join(engine, 'ets/core/reader/ComicChineseDictionary.ts'));
load(path.join(engine, 'ets/core/reader/ChineseTaiwanConverter.ts'));
load(path.join(root, 'entry/src/main/ets/core/book/SearchChineseScript.ts'));
const Dictionary = vm.runInContext('ComicChineseDictionary', context);
const Taiwan = vm.runInContext('ChineseTaiwanConverter', context);
const Script = vm.runInContext('SearchChineseScript', context);
const raw = (name) => fs.readFileSync(path.join(engine, 'resources/rawfile/opencc', name), 'utf8');

const started = Date.now();
const simplified = new Dictionary(raw('TSCharacters.txt'), raw('TSPhrases.txt'));
const taiwan = new Taiwan(raw('STCharacters.txt'), raw('STPhrases.txt'), raw('TWVariants.txt'));
console.log(`字典加载 ${Date.now() - started}ms`);
const converter = {
  toSimplified: (text) => simplified.convertSameLength(text),
  toTraditional: (text) => taiwan.convert(text),
};

// 简→繁：词组区分一简对多繁，再换台湾用字。
const s2tw = {
  '斗破苍穹': '鬥破蒼穹',
  '诡秘之主': '詭秘之主',
  '后来': '後來',
  '皇后': '皇后',
  '头发': '頭髮',
  '发现': '發現',
  '干净': '乾淨',
  '里面': '裡面',
  '着急': '著急',
  '为什么': '為什麼',
  '三体': '三體',
  'Overlord': 'Overlord',
};
for (const [source, expected] of Object.entries(s2tw)) assert.equal(taiwan.convert(source), expected, source);

// 关键词变体：简体输入、繁体输入、没有简繁差异。
const script = new Script(converter, new Map());
let variants = script.variants('斗破苍穹');
assert.equal(variants.inputScript, 's');
assert.equal(variants.simplified, '斗破苍穹');
assert.equal(variants.traditional, '鬥破蒼穹');
assert.equal(variants.other(), '鬥破蒼穹');
variants = script.variants('詭秘之主');
assert.equal(variants.inputScript, 't');
assert.equal(variants.simplified, '诡秘之主');
assert.equal(variants.traditional, '詭秘之主', '繁体输入照原样发给繁体站');
assert.equal(variants.other(), '诡秘之主');
variants = script.variants('Overlord');
assert.equal(variants.hasVariant(), false);
assert.equal(variants.other(), '');
assert.equal(script.variants('天蚕土豆 斗破').inputScript, 's', '带空格的书名作者也能转换');

// 发请求：已知用字只发一次；未知时先原词、再补搜另一种；书源名写明繁体的当繁体站。
const hints = new Map([['https://simp.example', 's'], ['https://trad.example', 't']]);
const planner = new Script(converter, hints);
const simpKeyword = planner.variants('斗破苍穹');
const tradKeyword = planner.variants('詭秘之主');
let plan = planner.plan({ bookSourceUrl: 'https://simp.example' }, tradKeyword);
assert.deepEqual([plan.first, plan.second], ['诡秘之主', ''], '简体站收到繁体输入时转成简体');
plan = planner.plan({ bookSourceUrl: 'https://trad.example' }, simpKeyword);
assert.deepEqual([plan.first, plan.second], ['鬥破蒼穹', ''], '繁体站收到台湾用字');
plan = planner.plan({ bookSourceUrl: 'https://new.example' }, simpKeyword);
assert.deepEqual([plan.first, plan.firstScript, plan.second, plan.secondScript], ['斗破苍穹', 's', '鬥破蒼穹', 't']);
plan = planner.plan({ bookSourceUrl: 'https://new.example' }, tradKeyword);
assert.deepEqual([plan.first, plan.firstScript, plan.second, plan.secondScript], ['詭秘之主', 't', '诡秘之主', 's']);
plan = planner.plan({ bookSourceUrl: 'https://new.example' }, planner.variants('Overlord'));
assert.deepEqual([plan.first, plan.second], ['Overlord', ''], '没有简繁差异时照旧只搜一次');
plan = planner.plan({ bookSourceUrl: 'https://tw.example', bookSourceName: '小說狂人(TW)' }, simpKeyword);
assert.deepEqual([plan.first, plan.second], ['鬥破蒼穹', ''], '书源名带 TW 当繁体站');
plan = planner.plan({ bookSourceUrl: 'https://g.example', bookSourceName: '某站', bookSourceGroup: '繁體' }, simpKeyword);
assert.equal(plan.first, '鬥破蒼穹', '分组写明繁體当繁体站');
assert.equal(Script.nameHint('繁花小说网', ''), '', '书名里的“繁”字不算');
assert.equal(Script.nameHint('Twilight 书屋', ''), '', '单词里含 tw 不算');

// 判断站点用字：看书名作者里简繁特有字的多少。
assert.equal(planner.classify(['鬥破蒼穹', '天蠶土豆', '詭秘之主', '愛潛水的烏賊']), 't');
assert.equal(planner.classify(['斗破苍穹', '天蚕土豆', '诡秘之主', '爱潜水的乌贼']), 's');
assert.equal(planner.classify(['三國演義', '三国演义']), '', '简繁各半判断不出');
assert.equal(planner.classify(['Overlord', '丸山']), '', '没有区别字判断不出');

// 记下用字：书名判断优先，判断不出时记“搜出相关结果的那种写法”。
planner.takeChanged();
planner.learn({ bookSourceUrl: 'https://new.example' }, [{ name: '鬥破蒼穹', author: '天蠶土豆' }], 's');
assert.equal(hints.get('https://new.example'), 't', '书名是繁体时以书名为准');
assert.equal(planner.takeChanged(), true);
assert.equal(planner.takeChanged(), false, '取过一次就清零');
planner.learn({ bookSourceUrl: 'https://plain.example' }, [{ name: 'Overlord', author: '' }], 's');
assert.equal(hints.get('https://plain.example'), 's');
planner.learn({ bookSourceUrl: 'https://none.example' }, [], '');
assert.equal(hints.has('https://none.example'), false, '没有结果也没有相关写法时不记');
planner.takeChanged();
planner.learn({ bookSourceUrl: 'https://new.example' }, [{ name: '鬥破蒼穹', author: '天蠶土豆' }], 't');
assert.equal(planner.takeChanged(), false, '用字没变不算改动');
assert.equal([...hints.keys()].at(-1), 'https://plain.example', '没变时不挪位置');
planner.learn({ bookSourceUrl: 'https://simp.example' }, [{ name: '鬥破蒼穹', author: '天蠶土豆' }], '');
assert.equal(hints.get('https://simp.example'), 't', '记错的用字会被后来的结果纠正');
assert.equal([...hints.keys()].at(-1), 'https://simp.example', '改过的挪到最后，超出上限时先删最旧的');

// 比对：折成简体且等长，简繁同名视为同一书名。
assert.equal(planner.fold('鬥破蒼穹'), '斗破苍穹');
assert.equal(planner.fold('斗破苍穹'), '斗破苍穹');
assert.equal(planner.fold('詭秘之主'), planner.fold('诡秘之主'));
assert.equal(planner.isTraditional('鬥破蒼穹'), true);
assert.equal(planner.isTraditional('斗破苍穹'), false);
assert.equal(planner.isTraditional('Overlord'), false);

// 接入点：搜索协调器按书源选关键词、补搜并折简体比对；聚合按简体分组；设置与同步带上开关。
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const coordinator = read('entry/src/main/ets/core/book/SearchCoordinator.ts');
assert.ok(coordinator.includes('await this.searchSourceForScript(sources[sourceIndex], keyword, options, onPartial)'));
assert.ok(coordinator.includes('script.plan(source, variants)'));
assert.ok(coordinator.includes("result.reason === '未搜索到结果'"), '超时与出错不补搜');
assert.ok(coordinator.includes('this.chineseScript ? this.chineseScript.fold(normalized) : normalized'));
assert.ok(coordinator.includes("options.validationOnly === true ? null : (options.chineseScript || null)"), '书源校验不走简繁同搜');
const aggregation = read('entry/src/main/ets/utils/SearchResultAggregationStore.ets');
assert.ok(aggregation.includes('script ? script.fold(normalized) : normalized'));
const page = read('entry/src/main/ets/components/home/SearchPage.ets');
assert.ok(page.includes('chineseScript: chineseScript || undefined'));
assert.ok(page.includes('SearchChineseScriptRuntime.saveHints'));
const changeSource = read('entry/src/main/ets/components/BookChangeSourceDialog.ets');
assert.ok(changeSource.includes('chineseScript: chineseScript || undefined'));
const settings = read('entry/src/main/ets/utils/SearchExploreSettingsStore.ets');
assert.ok(settings.includes("KEY_SIMP_TRAD_SEARCH: string = 'searchExploreSimpTradSearch'"));
assert.ok(read('entry/src/main/ets/account/CloudSyncCoordinator.ets').includes('remoteSearch.simpTradSearch !== false'),
  '旧版本同步数据没有这个字段时按开处理');
const runtime = read('entry/src/main/ets/core/book/SearchChineseScriptRuntime.ets');
assert.ok(runtime.includes("STORAGE_KEY: string = 'searchExploreSimpTradSearch'"), '运行时与设置用同一个键');

console.log('search-simp-trad-check: ok');
