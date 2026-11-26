import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const read = path => fs.readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const clean = source => source.replace(/^import [\s\S]*?;\r?\n/gm, '').replace(/^export \{.*;\r?\n/gm, '').replaceAll('export ', '');
const context = vm.createContext({ console });
vm.runInContext(stripTypeScriptTypes(clean(read('core/mimo/MimoPolicy.ts'))), context);
vm.runInContext(stripTypeScriptTypes(clean(read('core/mimo/CastVoicePolicy.ts'))), context);
const { CastVoicePolicy: policy, MimoRole: Role, CastVoiceTag: Tag } =
  vm.runInContext('({CastVoicePolicy,MimoRole,CastVoiceTag})', context);

const ref = (kind, id) => policy.ref(kind, id, id);
const role = (id, gender, age = 'unknown') => { const r = new Role(); r.id = id; r.name = id; r.gender = gender; r.age = age; return r; };
const scheme = policy.scheme('s', '默认方案');
scheme.narrator = ref('local', 'narrator');
scheme.maleLead = ref('local', 'lead-m');
scheme.femaleLead = ref('http', 'lead-f');
scheme.malePool = [ref('local', 'm1'), ref('local', 'm2'), ref('http', 'm3')];
scheme.femalePool = [ref('local', 'f1'), ref('local', 'f2')];
const all = () => true;
const noAge = () => 'unknown';
const voice = (r, roles, usable = all, age = noAge) => policy.voiceFor(r, roles, scheme, usable, age);

// 旁白、性别不明、主角都跟方案走，不写进人物档案。
const narrator = new Role();
assert.equal(policy.key(voice(narrator, [narrator]).ref), 'local:narrator');
const unknown = role('someone', 'unknown');
assert.equal(policy.key(voice(unknown, [unknown]).ref), 'local:narrator', '性别不明默认跟旁白');
assert.equal(unknown.castVoice, undefined);
scheme.unknown = ref('http', 'neutral');
assert.equal(policy.key(voice(unknown, [unknown]).ref), 'http:neutral');
const hero = role('hero', 'male'); hero.lead = true;
const heroMatch = voice(hero, [hero]);
assert.equal(policy.key(heroMatch.ref), 'local:lead-m');
assert.equal(heroMatch.slot, '男主角');
assert.equal(heroMatch.changed, false);

// 配角轮流取：先分给还没人用的，取到后固定。
const roles = [narrator, hero];
const picked = [];
for (const id of ['a', 'b', 'c', 'd']) {
  const r = role(id, 'male'); roles.push(r);
  const match = voice(r, roles);
  assert.equal(match.changed, true);
  picked.push(policy.key(match.ref));
  assert.equal(policy.key(voice(r, roles).ref), policy.key(match.ref), '第二次取到同一个音色');
  assert.equal(voice(r, roles).changed, false);
}
assert.deepEqual(picked.slice(0, 3), ['local:m1', 'local:m2', 'http:m3']);
assert.equal(picked[3], 'local:m1', '用完一轮从头再取');

// 同样没人用时优先年龄段相符的。
const ages = key => ({ 'local:f1': 'young', 'local:f2': 'elder' })[key] || 'unknown';
const granny = role('granny', 'female', 'elder');
assert.equal(policy.key(voice(granny, [granny], all, ages).ref), 'local:f2');

// 音色离开配角组或不可用时重新取；手动指定的不动。
const a = roles.find(r => r.id === 'a');
assert.equal(policy.key(voice(a, roles, r => policy.key(r) !== 'local:m1').ref) !== 'local:m1', true);
const manual = role('manual', 'female'); manual.castVoice = ref('local', 'm2'); manual.castManual = true;
assert.equal(voice(manual, [manual]).slot, '已指定');
assert.equal(policy.key(voice(manual, [manual]).ref), 'local:m2');
assert.equal(policy.key(voice(manual, [manual], r => policy.key(r) !== 'local:m2').ref), 'local:f1', '指定的音色没了就回到自动');

// 组里没有音色时由旁白读；旁白不可用时返回空。
const lonely = role('lonely', 'female');
scheme.femalePool = [];
assert.equal(policy.key(voice(lonely, [lonely]).ref), 'local:narrator');
assert.equal(policy.key(voice(lonely, [lonely], () => false).ref), '');

// 读回损坏的数据不抛错。
const normalized = policy.normalize({ enabled: true, schemeId: 'gone', schemes: [
  { id: 'x', name: ' 方案 ', narrator: { kind: 'system', id: '1', name: 'n' }, malePool: [ref('local', 'm1'), ref('local', 'm1'), null] },
  { id: 'x', name: '重复' }, { id: '', name: '没有编号' }
], tags: [{ key: 'local:m1', gender: 'robot', age: 'young', narrator: 1 }], undecodable: ['http:1', 'http:1', 3] });
assert.equal(normalized.schemes.length, 1);
assert.equal(normalized.schemes[0].name, '方案');
assert.equal(policy.key(normalized.schemes[0].narrator), '', '不认识的音色类型丢掉');
assert.equal(normalized.schemes[0].malePool.length, 1);
assert.equal(normalized.schemeId, 'x');
assert.equal(normalized.tags[0].gender, 'unknown');
assert.equal(normalized.tags[0].narrator, false);
assert.deepEqual(Array.from(normalized.undecodable), ['http:1']);
assert.equal(policy.normalize(undefined).schemes[0].id, 'default');

// 默认方案只用标过的音色填。
const tags = new Map([['local:n', ['female', true]], ['local:m', ['male', false]], ['local:f', ['female', false]], ['local:m2', ['male', false]]]);
const tagOf = key => { if (!tags.has(key)) return undefined; const t = new Tag(); t.key = key; t.gender = tags.get(key)[0]; t.narrator = tags.get(key)[1]; return t; };
const filled = policy.scheme('d', '默认方案');
assert.equal(policy.autoFill(filled, [ref('http', 'untagged'), ref('local', 'm'), ref('local', 'n'), ref('local', 'f'), ref('local', 'm2')], tagOf), true);
assert.equal(policy.key(filled.narrator), 'local:n');
assert.equal(policy.key(filled.maleLead), 'local:m');
assert.equal(policy.key(filled.femaleLead), 'local:f');
assert.deepEqual(Array.from(filled.malePool, policy.key), ['local:m2']);
assert.ok(!policy.schemeVoices(filled).some(r => r.id === 'untagged'));

// 重采样：长度按比例变，同采样率原样返回。
const pcm = new Int16Array(2205); for (let i = 0; i < pcm.length; i++) pcm[i] = Math.round(Math.sin(i / 20) * 10000);
const up = new Int16Array(policy.resample(pcm.buffer, 22050, 24000));
assert.equal(up.length, 2400);
assert.ok(Math.abs(up[1200] - Math.round(Math.sin(1200 * 22050 / 24000 / 20) * 10000)) < 200);
assert.equal(new Int16Array(policy.resample(pcm.buffer, 24000, 24000)).length, 2205);
assert.equal(policy.ageFit('teen', 'child'), 1);
assert.equal(policy.ageFit('elder', 'adult'), -1);

// 二期：响度、调度顺序、分析接口地址。
const tone = amplitude => { const a = new Int16Array(24000); for (let i = 2400; i < 21600; i++) a[i] = Math.round(Math.sin(i / 6) * amplitude); return a.buffer; };
const quiet = policy.level(tone(1500), 24000), loud = policy.level(tone(15000), 24000);
assert.ok(Math.abs(quiet - 1500 / Math.SQRT2) < 40, 'silence around speech does not lower the measured level');
assert.equal(policy.level(new Int16Array(2400).buffer, 24000), 0);
assert.equal(policy.gain(0, 0), 1);
assert.ok(policy.gain(quiet, 1500) > 2.5 && policy.gain(quiet, 1500) <= 2.8, 'a quiet voice is raised, by at most about 9 dB');
assert.ok(policy.gain(loud, 15000) < 0.4);
assert.equal(policy.gain(policy.TARGET_LEVEL, 5000), 1);
assert.ok(policy.gain(quiet, 30000) <= 32000 / 30000 + 1e-9, 'never amplified into clipping');
assert.ok(policy.peak(policy.amplify(tone(15000), 4)) >= 32767, 'amplify clamps instead of wrapping');
assert.equal(policy.peak(policy.floatToPcm(new Float32Array([0, 0.5, -1, 2]))), 32767);
assert.deepEqual(Array.from(policy.synthesisOrder(['a', 'b', 'a', '', 'b', 'a'])), [0, 2, 5, 1, 4]);
assert.deepEqual(Array.from(policy.synthesisOrder(['', ''])), []);
const sentence = '他沿着河岸一直往前走，走过了那座早就没有人看守的旧桥，又走过了一片被大水冲得七零八落的芦苇荡，天色暗下来的时候，才终于看见了远处村口那盏昏黄的灯。';
const pieces = Array.from(policy.synthesisPieces(sentence));
assert.equal(pieces.join(''), sentence, 'nothing is lost or reordered');
assert.ok(pieces.length >= 2 && pieces.every(piece => piece.length >= 12 && piece.length <= 56), 'balanced pieces: ' + pieces.map(piece => piece.length));
assert.ok(pieces.slice(0, -1).every(piece => '，。'.includes(piece.at(-1))), 'cuts fall on punctuation');
assert.deepEqual(Array.from(policy.synthesisPieces('他说了一句不长的话，然后就走了。')), ['他说了一句不长的话，然后就走了。']);
assert.equal(Array.from(policy.synthesisPieces('没有任何标点的一长串文字'.repeat(8))).length, 1, 'no punctuation, no cut');
assert.equal(Array.from(policy.synthesisPieces('“' + '很长的一句话，'.repeat(12) + '”')).join(''), '“' + '很长的一句话，'.repeat(12) + '”');
assert.equal(policy.httpConcurrency(''), 3);
assert.equal(policy.httpConcurrency('0'), 3);
assert.equal(policy.httpConcurrency('3'), 1, 'a plain number is a minimum interval, so one at a time');
assert.equal(policy.httpConcurrency('500'), 1);
assert.equal(policy.httpConcurrency('3/1000'), 3);
assert.equal(policy.httpConcurrency('10/1000'), 3);
assert.equal(policy.httpConcurrency('1/2000'), 1);
assert.equal(policy.completionsUrl('https://api.example.com/v1/'), 'https://api.example.com/v1/chat/completions');
assert.equal(policy.completionsUrl('https://api.example.com/v1/chat/completions'), 'https://api.example.com/v1/chat/completions');
assert.equal(policy.validUrl('ftp://x/y'), false);
assert.equal(policy.validUrl('https://api.example.com/v1/chat/completions'), true);
const custom = policy.normalize({ schemes: [], analysis: { provider: 'custom', url: 'https://a.test/v1/chat/completions', model: ' m ', verified: true } });
// 只存一个接口时的旧格式读成列表里的一条，并保持它正在使用。
assert.equal(custom.analysis.activeId, policy.LEGACY_ENDPOINT_ID);
assert.equal(custom.analysis.endpoints.length, 1);
assert.equal(custom.analysis.endpoints[0].model, 'm');
assert.equal(custom.analysis.endpoints[0].verified, true);
assert.equal(policy.activeEndpoint(custom.analysis).url, 'https://a.test/v1/chat/completions');
const kept = policy.normalize({ schemes: [], analysis: { provider: 'mimo', url: 'https://a.test/v1/chat/completions', model: 'm', verified: true } });
assert.equal(kept.analysis.activeId, '');
assert.equal(kept.analysis.endpoints.length, 1, 'an endpoint that is not in use is kept');
const broken = policy.normalize({ schemes: [], analysis: { provider: 'custom', url: 'not a url', model: 'm', verified: true } });
assert.equal(broken.analysis.activeId, '');
assert.equal(broken.analysis.endpoints.length, 0);
const many = policy.normalize({ schemes: [], analysis: { activeId: 'b', endpoints: [
  { id: 'a', name: ' 甲 ', url: 'https://a.test/v1/chat/completions', model: 'm1', verified: true },
  { id: 'a', name: '重复', url: 'https://a.test/v1/chat/completions', model: 'm1' },
  { id: 'b', name: '', url: 'https://b.test/v1/chat/completions', model: 'm2' },
  { id: 'bad id', name: 'x', url: 'https://c.test/v1/chat/completions', model: 'm3' },
  { id: 'c', name: 'x', url: 'ftp://c.test/', model: 'm3' }] } });
assert.deepEqual(Array.from(many.analysis.endpoints, (item) => item.id), ['a', 'b']);
assert.equal(many.analysis.endpoints[0].name, '甲');
assert.equal(many.analysis.activeId, 'b');
assert.equal(policy.endpointTitle(many.analysis.endpoints[1]), 'm2');
assert.equal(policy.activeEndpoint(many.analysis).verified, false);
assert.equal(policy.normalize({ schemes: [], analysis: { activeId: 'gone', endpoints: [] } }).analysis.activeId, '');
assert.equal(policy.normalize(JSON.parse(JSON.stringify(many))).analysis.endpoints.length, 2, 'survives a save and reload');
assert.equal(policy.endpointHost('https://api.example.com/v1/chat/completions'), 'api.example.com');
const full = { activeId: '', endpoints: Array.from({ length: 30 }, (_, index) => ({ id: 'e' + index, name: '', url: 'https://a.test/v1/chat/completions', model: 'm' })) };
assert.equal(policy.normalize({ schemes: [], analysis: full }).analysis.endpoints.length, policy.ENDPOINT_LIMIT);
console.log('cast-voice-policy-check ok');
