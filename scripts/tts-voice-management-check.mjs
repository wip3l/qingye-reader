// Exercise production availability, persistence, manager actions and both voice selectors.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const read = name => fs.readFileSync(new URL(`../entry/src/main/ets/${name}`, import.meta.url), 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });
function method(source, name) {
  const match = new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm').exec(source);
  assert(match, name);
  return source.slice(match.index, source.indexOf('\n  }', match.index) + 4);
}
const values = new Map();
const disk = new Map();
let nextGate;
let failWrite = false;
const context = vm.createContext({
  console, getContext: () => ({}),
  AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value) },
  HdsFeedback: { showToast() {} },
  SymbolGlyphModifier: class { constructor(icon) { this.icon = icon; } },
  $r: resource => resource,
  ThemeRuntime: { dangerColor: () => '#CC0000' },
  preferences: { getPreferences: async () => {
    const gate = nextGate;
    nextGate = undefined;
    if (gate) await gate;
    return { get: async (key, fallback) => disk.has(key) ? disk.get(key) : fallback,
      put: async (key, value) => { if (failWrite) { failWrite = false; throw new Error('disk'); } disk.set(key, value); },
      flush: async () => {} };
  } },
  TtsVoiceOption: class {
    id = 0; name = ''; online = 1; style = ''; language = 'zh-CN'; available = true; downloadable = false;
  },
  TtsVoiceInfo: class {},
  SystemTtsReader: { parseCustomVoices: raw => JSON.parse(raw || '[]'),
    serializeCustomVoices: voices => JSON.stringify(voices), listAvailableVoices: async () => [] },
  AccountCommerceApi: { fetchTtsCatalog: async () => ({ voices: [] }) }
});
vm.runInContext(['utils/TtsVoiceAvailability.ts', 'utils/TtsVoiceCatalog.ets', 'utils/TtsSettingsStore.ets']
  .map(name => compile(read(name))).join('\n'), context);
const policy = vm.runInContext('TtsVoiceAvailability', context);
const catalog = vm.runInContext('TtsVoiceCatalog', context);
const store = vm.runInContext('TtsSettingsStore', context);
const Settings = vm.runInContext('TtsSettings', context);
const defaultVoice = catalog.defaultVoice();
const systemVoice = { ...defaultVoice, id: 8, name: '系统女声', status: 'INSTALLED' };
const cloudVoice = { id: 'xiaoyan', name: '温暖女声' };
const systemKey = policy.systemKey(8, 1, 'zh_CN', 'a');
assert.equal(systemKey, policy.systemKey(8, 1, 'zh-Hans', 'b'), 'known voices retain stable keys across metadata changes');
assert.notEqual(systemKey, policy.systemKey(8, 0, 'zh-CN', ''), 'online and offline variants stay independent');
assert.equal(policy.setEnabled('', policy.DEFAULT_KEY, false), '', 'default cannot be disabled');
assert(catalog.systemEnabled(defaultVoice, `${policy.DEFAULT_KEY}\n${systemKey}`), 'imported settings cannot hide default');
const disabled = policy.setEnabled('', systemKey, false);
assert(!catalog.systemEnabled(systemVoice, disabled));
assert(!catalog.systemEnabled({ ...systemVoice, name: '新名称' }, disabled), 'rename does not reset state');
assert(catalog.systemEnabled(systemVoice, policy.setEnabled(disabled, systemKey, true)));
assert(catalog.mergeWithDefault([{ ...systemVoice, name: '默认音色' }]).some(voice => catalog.isDefault(voice)),
  'a duplicate display name must never replace the protected default');

const initial = new Settings();
initial.person = 8;
initial.speed = 1.5;
initial.disabledVoiceKeys = `${systemKey}\n${policy.DEFAULT_KEY}`;
await store.save({}, initial);
assert.equal(values.get('ttsPerson'), 0, 'disabled selection falls back to default');
assert.equal(values.get('ttsSpeed'), 1.5, 'fallback preserves speed');
store.cachedSettings = null;
assert.equal((await store.load({})).disabledVoiceKeys, systemKey, 'disabled state survives reload');
const cloudSettings = store.fromStorage();
cloudSettings.cloudVoiceId = cloudVoice.id;
cloudSettings.disabledVoiceKeys = policy.setEnabled(disabled, policy.cloudKey(cloudVoice.id), false);
await store.save({}, cloudSettings);
assert.equal(values.get('ttsCloudVoiceId'), '', 'disabled cloud voice also falls back');
const custom = store.fromStorage();
custom.person = 8;
custom.customVoiceId = '1';
await store.save({}, custom);
assert.equal(values.get('ttsCustomVoiceId'), '1', 'system disabled state does not clear a custom selection');

// The latest toggle wins even while a prior write waits for preference access.
let release;
nextGate = new Promise(resolve => { release = resolve; });
const a = store.fromStorage();
a.disabledVoiceKeys = systemKey;
const first = store.save({}, a);
await Promise.resolve(); await Promise.resolve();
const b = store.fromStorage();
b.disabledVoiceKeys = '';
const second = store.save({}, b);
release();
await Promise.all([first, second]);
assert.equal(disk.get('ttsDisabledVoiceKeys'), '');
failWrite = true;
await assert.rejects(store.save({}, a), /disk/);
await store.save({}, b);
assert.equal(disk.get('ttsDisabledVoiceKeys'), '', 'a failed write cannot poison the save queue');

const managerSource = read('pages/CustomTtsVoiceManager.ets');
vm.runInContext(compile(managerSource.slice(managerSource.indexOf('class ManagedTtsVoiceEntry'),
  managerSource.indexOf('class VoiceEditFormDraft'))), context);
const manager = vm.runInContext(compile(`class Manager { ${[
  'nativeVoices', 'nativeEnabled', 'nativeSelected', 'toggleNativeVoice', 'clearCustomVoiceSelection',
  'toggleVoiceEnabled', 'toggleVoiceState', 'deleteVoice', 'isCurrentVoice', 'selectNativeVoice',
  'nativeSwipeActions', 'voiceSwipeActions', 'customSelectionKey', 'batchVoices', 'filteredVoices',
  'isVoiceSelected', 'setSelectionKey', 'toggleVoiceSelected', 'isAllSelected', 'toggleAllVoices',
  'pruneSelectedVoices', 'batchSetEnabled', 'batchDelete', 'showBatchResult', 'confirmDeleteVoice', 'confirmBatchDelete'
].map(name => method(managerSource, name)).join('\n')} }; new Manager()`), context);
Object.assign(manager, { ttsDisabledVoiceKeys: '', ttsCloudVoiceId: '', ttsCustomVoiceId: '',
  ttsPerson: 8, ttsOnline: 1, ttsLanguage: 'zh-CN', ttsStyle: '', searchText: '',
  systemVoices: [defaultVoice, systemVoice], cloudVoices: [cloudVoice], selectedVoiceIds: [],
  downloadingVoiceKey: '', pageAlive: true, saveSettings() {} });
const dialogs = [];
manager.getUIContext = () => ({ showAlertDialog: options => dialogs.push(options) });
manager.buttonColor = () => '#007DFF';
const native = manager.nativeVoices(false);
assert.equal(manager.nativeSwipeActions(native[0]).icons.length, 0, 'default has no swipe actions');
assert.equal(manager.nativeSwipeActions(native[1]).icons.length, 1, 'system only offers disable');
assert.equal(manager.nativeSwipeActions(manager.nativeVoices(true)[0]).icons.length, 1, 'cloud only offers disable');
manager.toggleNativeVoice(native[0]);
assert.equal(manager.ttsDisabledVoiceKeys, '', 'manager default action is guarded');
manager.toggleNativeVoice(native[1]);
assert.equal(manager.ttsPerson, 0, 'disabling current system voice selects default');
assert(!manager.nativeEnabled(native[1]));
await manager.selectNativeVoice(native[1]);
assert.equal(manager.ttsPerson, 0, 'disabled rows cannot be selected');
manager.toggleNativeVoice(native[1]);
await manager.selectNativeVoice(native[1]);
assert.equal(manager.ttsPerson, 8, 're-enabled system voice can be selected again');
manager.ttsCloudVoiceId = cloudVoice.id;
manager.toggleNativeVoice(manager.nativeVoices(true)[0]);
assert.equal(manager.ttsCloudVoiceId, '');
assert.equal(manager.ttsPerson, 0);
manager.searchText = '温暖';
assert.equal(manager.nativeVoices(false).length, 0);
assert.equal(manager.nativeVoices(true).length, 1, 'search includes disabled cloud voices');
manager.voices = [{ id: 1, name: '自定义', enabled: true }, { id: 2, name: '备用', enabled: true }];
manager.ttsCustomVoiceId = '1';
manager.toggleVoiceEnabled(manager.voices[0], false);
assert.equal(manager.ttsCustomVoiceId, '');
assert.equal(manager.voices.length, 2, 'disable retains the row for re-enabling');
manager.ttsCustomVoiceId = '2';
manager.deleteVoice(manager.voices[1]);
assert.equal(manager.voices.length, 2, 'single deletion waits for confirmation');
assert.equal(manager.ttsCustomVoiceId, '2', 'pending confirmation preserves current selection');
assert(dialogs.at(-1).message.includes('备用'));
dialogs.at(-1).primaryButton.action();
assert.equal(manager.voices.length, 2, 'cancel keeps the voice');
manager.deleteVoice(manager.voices[1]);
dialogs.at(-1).secondaryButton.action();
assert.equal(manager.ttsCustomVoiceId, '');
assert.equal(manager.voices.length, 1);
assert.equal(manager.systemVoices.length, 2, 'custom deletion leaves systems intact');
assert.equal(manager.cloudVoices.length, 1, 'custom deletion leaves cloud catalog intact');
const customActions = manager.voiceSwipeActions(manager.voices[0]).icons;
assert.equal(customActions.length, 2, 'custom offers enable/disable and delete');
assert.equal(customActions[0].iconOptions.accessibilityText, '启用音色');
customActions[0].onAction();
assert.equal(manager.voices[0].enabled, true, 'clicking enable executes the actual callback');
manager.nativeSwipeActions(native[1]).icons[0].onAction();
assert(!manager.nativeEnabled(native[1]), 'clicking native disable executes the actual callback');
customActions[1].onAction();
assert.equal(manager.voices.length, 1, 'swipe delete opens confirmation without deleting');
dialogs.at(-1).secondaryButton.action();
assert.equal(manager.voices.length, 0, 'confirming swipe delete executes deletion');

// Mixed-category selection, search, action restrictions and the actual result dialog.
manager.exitSelectionMode = () => { manager.selectionMode = false; manager.selectedVoiceIds = []; };
manager.searchText = '';
manager.ttsDisabledVoiceKeys = '';
manager.voices = [{ id: 'xiaoyan', name: '自定义女声', enabled: true }, { id: 2, name: '备用', enabled: false }];
manager.selectedVoiceIds = [];
manager.toggleAllVoices();
assert.equal(manager.selectedVoiceIds.length, 5, 'select all includes every category and protected default');
assert(manager.isAllSelected());
assert(manager.selectedVoiceIds.includes('custom:xiaoyan'));
assert(manager.selectedVoiceIds.includes('cloud:xiaoyan'), 'identical IDs across categories stay independent');
manager.searchText = '备用';
manager.pruneSelectedVoices();
assert.equal(manager.selectedVoiceIds.length, 5, 'search preserves selections from other categories');
manager.toggleAllVoices();
assert.equal(manager.selectedVoiceIds.length, 4, 'filtered deselection only affects visible rows');
manager.toggleAllVoices();
assert.equal(manager.selectedVoiceIds.length, 5);
manager.ttsCloudVoiceId = cloudVoice.id;
manager.batchSetEnabled(false);
assert(manager.nativeEnabled(native[0]));
assert(!manager.nativeEnabled(native[1]));
assert(!manager.nativeEnabled(manager.nativeVoices(true, false)[0]));
assert(manager.voices.every(voice => !voice.enabled));
assert.equal(manager.ttsCloudVoiceId, '', 'mixed disable falls back from cloud to default');
assert.equal(manager.ttsPerson, 0);
assert.equal(dialogs.at(-1).title, '批量禁用结果');
assert(dialogs.at(-1).message.includes('已禁用 4 个音色'));
assert(dialogs.at(-1).message.includes('系统默认音色（默认音色始终启用）'));
manager.batchSetEnabled(true);
assert(manager.nativeEnabled(native[1]));
assert(manager.nativeEnabled(manager.nativeVoices(true, false)[0]));
assert(manager.voices.every(voice => voice.enabled));
manager.ttsCustomVoiceId = 'xiaoyan';
manager.batchDelete();
assert.equal(manager.voices.length, 2, 'batch deletion waits for confirmation');
assert.equal(manager.ttsCustomVoiceId, 'xiaoyan');
assert.equal(dialogs.at(-1).title, '批量删除音色');
assert(dialogs.at(-1).message.includes('2 个自定义音色'));
assert(dialogs.at(-1).message.includes('自定义女声'));
assert(dialogs.at(-1).message.includes('备用'));
for (const title of ['系统默认音色', '系统女声', '温暖女声']) assert(dialogs.at(-1).message.includes(title));
assert(dialogs.at(-1).message.includes('仅自定义音色可删除'));
dialogs.at(-1).primaryButton.action();
assert.equal(manager.voices.length, 2, 'cancel batch deletion preserves all voices');
assert.equal(manager.selectedVoiceIds.length, 5, 'cancel preserves checkboxes');
manager.batchDelete();
dialogs.at(-1).secondaryButton.action();
assert.equal(manager.voices.length, 0, 'mixed deletion removes only selected custom voices');
assert.equal(manager.ttsCustomVoiceId, '');
assert.equal(manager.systemVoices.length, 2);
assert.equal(manager.cloudVoices.length, 1);
assert.equal(manager.selectedVoiceIds.length, 3, 'undeletable entries remain selected');
for (const title of ['系统默认音色', '系统女声', '温暖女声']) assert(dialogs.at(-1).message.includes(title));
assert(dialogs.at(-1).message.includes('仅自定义音色可删除'));
manager.batchDelete();
assert.equal(dialogs.at(-1).title, '无法删除所选音色');
assert(dialogs.at(-1).message.includes('未删除任何音色'), 'all-blocked selection clearly reports that nothing was deleted');
assert.equal(dialogs.at(-1).secondaryButton, undefined, 'no destructive confirmation when nothing is deletable');
manager.selectedVoiceIds = [policy.DEFAULT_KEY];
manager.batchSetEnabled(false);
assert(dialogs.at(-1).message.includes('已禁用 0 个音色'));
manager.selectedVoiceIds = [systemKey];
manager.ttsPerson = 8;
manager.batchSetEnabled(false);
assert.equal(manager.ttsPerson, 0, 'batch disable falls back from current system voice');
manager.voices = [{ id: 3, name: '临时', enabled: true }];
manager.ttsCustomVoiceId = '3';
manager.selectedVoiceIds = ['custom:3'];
manager.batchSetEnabled(false);
assert.equal(manager.ttsCustomVoiceId, '', 'batch disable falls back from current custom voice');
manager.selectionMode = true;
manager.batchDelete();
dialogs.at(-1).secondaryButton.action();
assert.equal(manager.selectionMode, false, 'deleting all selected custom voices exits selection');
manager.searchText = '不存在';
assert.equal(manager.isAllSelected(), false, 'empty filtered list never counts as all selected');

manager.searchText = '';
manager.voices = [{ id: 4, name: '确认范围', enabled: true }, { id: 5, name: '后来勾选', enabled: true }];
manager.selectedVoiceIds = ['custom:4'];
manager.batchDelete();
manager.selectedVoiceIds = ['custom:5'];
dialogs.at(-1).secondaryButton.action();
assert.equal(manager.voices.length, 1);
assert.equal(manager.voices[0].id, 5, 'confirmation only deletes the captured scope');
manager.deleteVoice(manager.voices[0]);
manager.pageAlive = false;
dialogs.at(-1).secondaryButton.action();
assert.equal(manager.voices.length, 1, 'stale confirmation cannot delete after leaving the page');
manager.pageAlive = true;

// Run both actual loading paths with one disabled system and cloud voice.
context.SystemTtsReader.listAvailableVoices = async () => [systemVoice];
context.AccountCommerceApi.fetchTtsCatalog = async () => ({ voices: [cloudVoice] });
for (const [file, load, systemList, cloudList, loading, findCloud, findCustom, findSystem] of [
  ['pages/TtsSettings.ets', 'loadVoices', 'voices', 'cloudVoices', 'isLoadingVoices', 'findCurrentCloudVoice', 'findCurrentCustomVoice', 'findCurrentVoice'],
  ['pages/ReadBook.ets', 'loadTtsVoices', 'ttsVoices', 'ttsCloudVoices', 'ttsVoicesLoading', 'findCurrentCloudTtsVoice', 'findCurrentCustomTtsVoice', 'findCurrentTtsVoice']
]) {
  const Page = vm.runInContext(compile(`(class { ${method(read(file), load)} })`), context);
  const page = new Page();
  Object.assign(page, { [loading]: false, ttsCloudVoiceId: '', ttsDisabledVoiceKeys: `${systemKey}\n${policy.cloudKey(cloudVoice.id)}`,
    ttsInstalledVoiceKeys: '', applyInstalledOverrides: voices => voices,
    [findCloud]: () => undefined, [findCustom]: () => undefined, [findSystem]: () => defaultVoice,
    publishTtsFloatingVoices() {} });
  await page[load]();
  assert.equal(page[systemList].length, 1, `${file} hides disabled system`);
  assert(catalog.isDefault(page[systemList][0]));
  assert.equal(page[cloudList].length, 0, `${file} hides disabled cloud`);
  page.ttsDisabledVoiceKeys = '';
  await page[load]();
  assert.equal(page[systemList].length, 2, `${file} restores enabled system`);
  assert.equal(page[cloudList].length, 1, `${file} restores enabled cloud`);
  const change = file.includes('ReadBook') ? 'onTtsAvailabilityChanged' : 'onVoiceAvailabilityChanged';
  const ChangePage = vm.runInContext(compile(`(class { ${method(read(file), change)} })`), context);
  const immediate = new ChangePage();
  let refreshes = 0;
  Object.assign(immediate, { [systemList]: [defaultVoice, systemVoice], [cloudList]: [cloudVoice],
    ttsDisabledVoiceKeys: `${systemKey}\n${policy.cloudKey(cloudVoice.id)}`,
    currentVoiceKey: () => 'default', currentTtsVoiceKey: () => 'default',
    publishTtsFloatingVoices() {}, loadTtsVoices() { refreshes++; } });
  immediate[change]();
  assert.equal(immediate[systemList].length, 1, `${file} removes disabled system before network completes`);
  assert.equal(immediate[cloudList].length, 0, `${file} removes disabled cloud before network completes`);
  if (file.includes('ReadBook')) assert.equal(refreshes, 1);
}
console.log('TTS voice management checks passed: protection, persistence, write ordering, fallback, search, mixed batch actions, restriction dialogs, deletion and both selectors.');
