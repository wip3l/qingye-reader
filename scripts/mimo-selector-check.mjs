import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {stripTypeScriptTypes} from 'node:module';
const read=p=>fs.readFileSync(new URL('../entry/src/main/ets/'+p,import.meta.url),'utf8');
function method(source,name){const start=new RegExp('^  (?:async )?'+name+'\\(','m').exec(source)?.index;assert.notEqual(start,undefined,name);return source.slice(start,source.indexOf('\n  }',start)+4);}
const choices=[{key:'multi',label:'MiMo · 自动多角色',multi:true},
 {key:'child',presetId:'child',label:'MiMo · 儿童·清亮',multi:false},
 {key:'custom',presetId:'custom',label:'MiMo · 我的提示词',multi:false}];
let configured=true,selected='multi',routes=0;const calls=[];
const context=vm.createContext({
 MimoStore:{voiceChoices:()=>choices,load:()=>({enabled:true,multi:selected==='multi'}),isConfigured:()=>configured,
 selectedVoiceKey:()=>selected,selectedVoiceTitle:()=>choices.find(c=>c.key===selected).label,
 selectVoice:(c,book)=>{selected=c.key;calls.push([c.key,book]);return true}},
 TtsVoiceCatalog:{cloudVoiceTitle:()=> 'cloud',customVoiceTitle:()=> 'custom',voiceTitle:()=> 'system'},
 HdsFeedback:{showToast:message=>{throw Error(message)}},console
});
const readerSource=read('pages/ReadBook.ets'),settingsSource=read('pages/TtsSettings.ets');
const reader=vm.runInContext(stripTypeScriptTypes('({'+[
 'mimoQuickVoiceLabels','regularTtsVoiceCount','applyMimoPresetChoice','ttsQuickVoiceOptions','ttsQuickVoiceLabels',
 'ttsQuickVoiceSelectedIndex','selectTtsQuickVoice'].map(n=>method(readerSource,n)).join(',')+'})'),context);
Object.assign(reader,{bookUrl:'current-book',isTtsSpeaking:false,ttsReader:{isSpeaking:()=>false},
 ttsCloudVoices:[{}],selectableCustomTtsVoices:()=>[{}],selectableSystemTtsVoices:()=>[{}],
 isCurrentCloudTtsVoice:()=>false,isCurrentCustomTtsVoice:()=>false,isCurrentTtsVoice:()=>false,
 getUIContext:()=>({getRouter:()=>({pushUrl:()=>routes++})}),publishTtsFloatingVoices(){},
 applyCloudTtsVoice:()=>calls.push(['cloud']),applyCustomTtsVoice:()=>calls.push(['custom']),applyTtsVoice:()=>calls.push(['system'])});
assert.deepEqual(Array.from(reader.ttsQuickVoiceLabels()).slice(0,3),choices.map(c=>c.label));
for(let i=0;i<choices.length;i++){reader.selectTtsQuickVoice(i);assert.equal(selected,choices[i].key);assert.equal(reader.ttsQuickVoiceSelectedIndex(),i);assert.equal(calls.at(-1)[1],'current-book');}
for(const [offset,name] of [[0,'cloud'],[1,'custom'],[2,'system']]){reader.selectTtsQuickVoice(choices.length+offset);assert.equal(calls.at(-1)[0],name,'regular-provider indexes remain aligned');}
reader.selectTtsQuickVoice(choices.length+3);assert.equal(routes,1,'trailing settings entry still opens settings');
configured=false;const before=calls.length;reader.selectTtsQuickVoice(1);assert.equal(routes,2);assert.equal(calls.length,before,'no key navigates to setup without activating a preset');
const settings=vm.runInContext(stripTypeScriptTypes('({'+method(settingsSource,'voiceSelectOptions')+'})'),context);
Object.assign(settings,{mimoChoices:choices,cloudVoices:[],enabledCustomVoices:()=>[],voices:[],
 selectMimoVoice:c=>calls.push([c.key])});
const options=settings.voiceSelectOptions();assert.deepEqual(Array.from(options).slice(0,3).map(o=>o.value),choices.map(c=>c.label));
options[2].selectVoice();assert.equal(calls.at(-1)[0],'custom');
assert.match(readerSource,/@StorageProp\('mimoVoicesRevision'\) @Watch\('onMimoVoiceStateChanged'\)/);
assert.match(settingsSource,/@StorageProp\('mimoVoicesRevision'\) @Watch\('refreshMimoChoices'\)/);
// Run the production management handlers against controlled dialogs and storage.
function privateMethod(source,name){const start=new RegExp('^  private (?:async )?'+name+'\\(','m').exec(source)?.index;assert.notEqual(start,undefined,name);return source.slice(start,source.indexOf('\n  }',start)+4);}
let answer=1,globalScheme={assignmentEnabled:false,schemeId:'old'},bookScheme={assignmentEnabled:false,schemeId:'old'};
const managerContext=vm.createContext({
 MimoStore:{library:()=>globalScheme,saveLibrary:value=>globalScheme=value,cast:()=>bookScheme,saveCast:(_book,value)=>bookScheme=value,
 load:()=>({voice:'白桦',enabled:true,multi:false,analysisAvailable:true})},
 MimoVoicePolicy:{clone:value=>JSON.parse(JSON.stringify(value))},HdsFeedback:{showToast:message=>{throw Error(message)}},
 ThemeRuntime:{subTextColor:()=>'',accentColor:()=>''}
});
const managementSource=read('pages/MimoVoices.ets');
const Manager=vm.runInContext(stripTypeScriptTypes('class Manager {'+['confirm','activate','chooseRolePreset','loadRole'].map(n=>privateMethod(managementSource,n)).join('\n')+'}; Manager'),managerContext);
const manager=new Manager();Object.assign(manager,{book:'',dark:false,refresh(){},getUIContext:()=>({getPromptAction:()=>({showDialog:async()=>({index:answer})})})});
await manager.activate({id:'new',name:'新方案'});assert.equal(globalScheme.assignmentEnabled,true,'activating a scheme also enables assignment');
manager.book='book';await manager.activate({id:'new',name:'新方案'});assert.equal(bookScheme.assignmentEnabled,true);
answer=0;await manager.activate({id:'canceled',name:'取消'});assert.equal(bookScheme.schemeId,'new');
manager.getUIContext=()=>({getPromptAction:()=>({showDialog:async()=>{throw Error('dismissed')}})});
await manager.activate({id:'dismissed',name:'返回取消'});assert.equal(bookScheme.schemeId,'new','native Back dismissal must cancel without an unhandled rejection');
manager.presets=[{id:'p',name:'声音',revision:2,prompt:'新版'}];manager.chooseRolePreset({id:'p',name:'声音',revision:1,prompt:'旧版'});
assert.equal(manager.roleHasUpdate,true);assert.equal(manager.selectedRolePreset.prompt,'旧版','version notice must not silently update a bound prompt');
manager.chooseRolePreset(manager.presets[0]);assert.equal(manager.roleHasUpdate,false);assert.equal(manager.roleVersion,2);
managerContext.MimoVoicePolicy.rolePreset=role=>role.preset;
bookScheme.roles=[{id:'child',name:'小禾',age:'child',gender:'unknown',locked:false,preset:manager.presets[0]}];
manager.roleId='child';manager.loadRole();assert.equal(manager.roleLocked,false,'opening the editor preserves an unlocked character');
bookScheme.roles[0].locked=true;manager.loadRole();assert.equal(manager.roleLocked,true);
globalScheme.defaultPreset={name:'儿童·清亮'};
const SettingsSync=vm.runInContext(stripTypeScriptTypes('class SettingsSync {'+privateMethod(read('pages/MimoSettings.ets'),'syncSettings')+'}; SettingsSync'),managerContext);
const sync=new SettingsSync();sync.voice='未保存的设置';sync.syncSettings(false);
assert.equal(sync.voice,'未保存的设置');assert.equal(sync.voiceName,'儿童·清亮','returning from voice management refreshes the displayed name without replacing the key-setup draft');
console.log('MiMo selector checks passed: presets in settings/reader lists, exact selected indexes, per-book selection, regular provider offsets, setup gate and live revision wiring.');
