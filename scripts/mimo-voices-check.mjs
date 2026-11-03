import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { createHash } from 'node:crypto';

const read = path => fs.readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const clean = source => source.replace(/^import [\s\S]*?;\r?\n/gm, '').replace(/^export \{.*;\r?\n/gm, '').replaceAll('export ', '');
const context = vm.createContext({ console, TextEncoder, TextDecoder, setTimeout, clearTimeout });
vm.runInContext(stripTypeScriptTypes(clean(read('core/mimo/MimoPolicy.ts'))), context);
vm.runInContext(stripTypeScriptTypes(clean(read('core/mimo/MimoVoicePolicy.ts'))), context);
const { MimoVoicePolicy: policy, MimoRole: Role } = vm.runInContext('({MimoVoicePolicy,MimoRole})', context);
const library = policy.defaults('苏打');
assert.equal(library.defaultPreset.voice, '苏打', 'migration preserves the chosen original voice without adding a prompt');
assert.equal(library.defaultPreset.prompt, '');
const child = new Role(); child.id = 'little-he'; child.age = 'child'; child.gender = 'male';
assert.equal(policy.match(child, library, 'general', true).preset.id, 'child');
assert.equal(policy.match(child, library, 'classic', true).preset.voice, '苏打', 'missing child candidates use narrator, not a mature preset');
assert.match(policy.match(child, library, 'classic', true).reason, /没有匹配年龄/);
const unknown = new Role(); unknown.id = 'unknown'; unknown.gender = 'female';
assert.match(policy.match(unknown, library, 'general', true).reason, /年龄证据不足/);
assert.match(policy.match(child, library, 'general', false).reason, /默认旁白/);
for (let i = 0; i < 200; i++) {
  child.id = 'child-' + i;
  assert.equal(policy.match(child, library, 'general', true).preset.age, 'child');
}
const extra = policy.preset('extra-child', '库内未启用童声', '冰糖', '活泼', 'child');
library.presets.push(extra);
assert.equal(policy.match(child, library, 'general', true).preset.id, 'child', 'unselected presets never enter the candidate pool');
const snapshot = policy.clone(library.presets.find(p => p.id === 'child'));
library.presets.find(p => p.id === 'child').prompt = '新版提示词';
assert.notEqual(snapshot.prompt, '新版提示词', 'role presets are snapshots');
assert.throws(() => policy.normalize({presets:[{...snapshot,voice:'invented'}],schemes:[]}, '白桦'), /格式无效/);
assert.throws(() => policy.normalize({presets:[{...snapshot,prompt:'字'.repeat(1201)}],schemes:[]}, '白桦'), /格式无效/);
assert.match(policy.prompt(snapshot, '开心', '克制', 1.5), /本段情绪：平静/);
assert.match(policy.prompt(snapshot, '开心', '自然', 1.5), /1.5 倍/);
const choices = policy.choices(library, true);
assert.equal(choices.filter(c=>c.multi).length,1);
assert.ok(choices.some(c=>c.presetId==='extra-child'), 'manual selection includes presets outside the automatic scheme');
assert.ok(!policy.choices(library,false).some(c=>c.multi), 'analysis capability gates only the multi-role choice');
assert.equal(choices.filter(c=>c.current).length,1, 'exactly one single-voice option reflects the current snapshot');

// Run the actual store with a private in-memory filesystem, without looking up a credential or device.
const files = new Map();
Object.assign(context, {
  AppStorage: { get: key => key === 'appFilesDir' ? '/private' : '', setOrCreate() {} },
  asset: { Tag:{ALIAS:1,RETURN_TYPE:2}, ReturnType:{ALL:1}, query:async()=>[], ErrorCode:{NOT_FOUND:1} },
  util: { TextEncoder:class{encodeInto(text){return new TextEncoder().encode(text)}},
    TextDecoder:{create:()=>({decodeWithStream:bytes=>new TextDecoder().decode(bytes)})} },
  cryptoFramework: { createMd:()=>{let value;return {updateSync:d=>value=d.data,digestSync:()=>({data:createHash('sha256').update(value).digest()})}} },
  fs: { accessSync:path=>files.has(path), mkdirSync:path=>files.set(path,''),
    readTextSync:path=>{if(!files.has(path))throw Error('missing');return files.get(path)},
    openSync:path=>({fd:path}), writeSync:(path,text)=>files.set(path,text),closeSync(){},
    renameSync:(a,b)=>{files.set(b,files.get(a));files.delete(a)},
    listFileSync:path=>[...files.keys()].filter(p=>p.startsWith(path+'/')).map(p=>p.slice(path.length+1)),
    statSync:()=>({mtime:1}),unlinkSync:path=>files.delete(path),OpenMode:{CREATE:1,WRITE_ONLY:2,TRUNC:4} }
});
vm.runInContext(stripTypeScriptTypes(clean(read('utils/mimo/MimoStore.ets'))), context);
const store = vm.runInContext('MimoStore', context);
assert.equal(store.selectVoice(store.voiceChoices().find(c=>c.presetId==='child')),false,'missing credentials do not enable a provider');
// In-memory credential state only; no device secret or external request is used.
store.setConfigured(true);
assert.equal(store.selectVoice(store.voiceChoices().find(c=>c.presetId==='child')),true);
assert.equal(store.load().multi,false);assert.equal(store.load().enabled,true);
assert.equal(store.selectedVoiceKey(),'mimo_preset:child');
assert.equal(store.selectedVoiceTitle(),'MiMo · 儿童·清亮');
assert.equal(store.library().defaultPreset.prompt,store.library().presets.find(p=>p.id==='child').prompt);
let selectedLibrary=store.library();selectedLibrary.defaultPreset=policy.preset('','原声 · 白桦','白桦');store.saveLibrary(selectedLibrary);
const cast = store.cast('test-book');
child.id = 'he'; policy.bind(child, snapshot); cast.roles.push(child);
const manual = new Role(); manual.id='manual';manual.manual=true;manual.age='adult';cast.roles.push(manual);
const locked = new Role();locked.id='locked';locked.locked=true;locked.age='adult';cast.roles.push(locked);
store.saveCast('test-book',cast,'Test');
store.savePreset(extra);
assert.equal(store.library().presets.length,8);
assert.ok(store.voiceChoices().some(c=>c.presetId===extra.id),'saving refreshes the shared selector catalog');
store.savePreset({...extra,prompt:'第二版'});
assert.equal(store.library().presets.find(p=>p.id===extra.id).revision,2);
assert.throws(()=>store.savePreset({...extra,id:'duplicate',name:extra.name}), /同名/);
assert.equal(store.cast('test-book').roles.find(r=>r.id==='he').preset.prompt,snapshot.prompt);
assert.throws(()=>store.deletePreset('child'), /方案|人物/);
store.deletePreset(extra.id);assert.equal(store.library().presets.length,7);
assert.ok(!store.voiceChoices().some(c=>c.presetId===extra.id),'deleting removes stale selector choices');
const changes = store.changes('test-book');
assert.equal(changes.find(c=>c.roleId==='locked').skip,true);
assert.equal(changes.find(c=>c.roleId==='manual').skip,true);
const before = store.cast('test-book').roles.find(r=>r.id==='locked').voice;
store.applyChanges('test-book',changes);
assert.equal(store.cast('test-book').roles.find(r=>r.id==='locked').voice,before);
assert.equal(store.cast('test-book').roles.find(r=>r.id==='he').preset.age,'child');
store.selectVoice(store.voiceChoices().find(c=>c.presetId==='female'),'test-book');
assert.equal(store.cast('test-book').roles[0].preset.id,'female','an explicit reader selection overrides an older book narrator');
assert.equal(store.cast('test-book').roles.find(r=>r.id==='he').preset.age,'child','choosing a single voice preserves other role bindings');
const globalNext=store.library();globalNext.defaultPreset=policy.clone(globalNext.presets.find(p=>p.id==='child'));store.saveLibrary(globalNext);
assert.equal(store.selectedVoiceKey('test-book'),'mimo_preset:female','book-specific narrator has its own selected index');
assert.equal(store.selectedVoiceTitle('test-book'),'MiMo · 温柔女声');
assert.equal(store.selectedVoiceTitle(),'MiMo · 儿童·清亮');
const editedFemale=policy.clone(store.library().presets.find(p=>p.id==='female'));editedFemale.prompt='已编辑的新版本';store.savePreset(editedFemale);
assert.equal(store.selectedVoiceKey('test-book'),'mimo_book_current','old bound snapshots remain selectable');
assert.match(store.selectedVoiceTitle('test-book'),/本书.*已保存版本/);
const savedPrompt=store.cast('test-book').roles[0].preset.prompt;
store.selectVoice(store.voiceChoices('test-book').find(c=>c.key==='mimo_book_current'),'test-book');
assert.equal(store.cast('test-book').roles[0].preset.prompt,savedPrompt,'reselecting a saved book version does not replace it with the global voice');
const schemeLibrary = store.library();
schemeLibrary.schemes.push({ id: 'new-plan', name: '新建方案', presetIds: ['child'] });
store.saveLibrary(schemeLibrary);
const presetsBeforeDelete = JSON.stringify(store.library().presets);
const castBeforeDelete = JSON.stringify(store.cast('test-book').roles);
store.deleteScheme('new-plan');
assert(!store.library().schemes.some(s => s.id === 'new-plan'), 'new unused schemes can be deleted');
assert.equal(JSON.stringify(store.library().presets), presetsBeforeDelete, 'scheme deletion preserves voices');
assert.equal(JSON.stringify(store.cast('test-book').roles), castBeforeDelete, 'scheme deletion preserves assigned roles');
assert.throws(() => store.deleteScheme(store.library().schemeId), /默认方案/);
const referenced = store.cast('test-book'); referenced.schemeId = 'classic'; store.saveCast('test-book', referenced);
assert.throws(() => store.deleteScheme('classic'), /书籍使用/);
referenced.schemeId = ''; store.saveCast('test-book', referenced);
store.deleteScheme('classic'); assert(!store.library().schemes.some(s => s.id === 'classic'));
store.deleteCast('test-book');
assert.equal(store.selectedVoiceKey('test-book'),store.selectedVoiceKey(),'clearing a cast invalidates cached book-specific choices');
const libraryPath='/private/mimo_private/voices.json';files.set(libraryPath,'{broken');
assert.throws(()=>store.library(), /原文件已保留/);assert.equal(files.get(libraryPath),'{broken');
assert.throws(()=>store.reloadVoices(), /原文件已保留/);
assert.doesNotThrow(()=>store.selectedVoiceTitle(),'a corrupt library must not crash a settings title');
console.log('MiMo voice checks passed: age-aware bounded matching, missing/unknown fallback, library CRUD, immutable role versions, reference guards, locked/manual reallocation and corrupted-file preservation.');
