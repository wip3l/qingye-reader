import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../entry/src/main/ets/pages/CustomFontManager.ets', import.meta.url), 'utf8');
const queueSource = fs.readFileSync(new URL('../entry/src/main/ets/account/CloudDownloadQueue.ets', import.meta.url), 'utf8');
const methods = ['remoteFonts', 'refreshFontLists', 'downloadCloudFont', 'cloudFontStatus', 'cloudFontSize',
  'onCloudDownloadQueueChanged'].map(name => {
  const match = source.match(new RegExp(`^  (?:async )?${name}\\([\\s\\S]*?^  }`, 'm'));
  assert.ok(match, name);
  return match[0];
}).join(',\n');
const font = { id: 'cloud-a', name: '中文字体.ttf', bytes: 2097152 };

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

function fixture() {
  let page;
  const state = { downloads: 0, refreshes: 0, fail: '', gate: null, records: [], notices: [], order: [],
    progress: null, onWait: null, registered: [], registrationSucceeds: true, failedIds: new Set() };
  const sandbox = vm.createContext({
    Error, getContext: () => ({}),
    AccountSessionStore: { account: () => ({ userId: 'user' }) },
    AppStorage: { setOrCreate: (key, value) => { page[key] = value; } },
    HdsFeedback: { showToast: message => state.notices.push(message) },
    CloudAutoSync: {
      parseRemoteFonts: raw => { try { return JSON.parse(raw) || []; } catch { return []; } },
      async reconcile() {
        state.refreshes++;
        if (state.gate) await state.gate.promise;
        if (state.fail) throw new Error(state.fail);
        page.cloudRemoteFontsRaw = JSON.stringify([font]);
      },
      async ensureFontDownloaded(_context, selected, progress, onWait) {
        state.downloads++;
        state.order.push(selected.id);
        state.progress = progress;
        state.onWait = onWait;
        if (state.gate) await state.gate.promise;
        if (state.failedIds.has(selected.id)) throw new Error('连接失败');
        if (state.fail) throw new Error(state.fail);
        const filePath = `/files/${selected.id}.ttf`;
        state.records.push({ filePath, familyName: 'cloud-family', sourceName: selected.name });
        page.cloudRemoteFontsRaw = JSON.stringify(JSON.parse(page.cloudRemoteFontsRaw).filter(item => item.id !== selected.id));
        return filePath;
      }
    }
  });
  vm.runInContext(stripTypeScriptTypes(queueSource.replace(/^import .*;\r?\n/gm, '').replace('export class', 'class'), { mode: 'strip' }), sandbox);
  vm.runInContext(stripTypeScriptTypes(`globalThis.page = {${methods}}`, { mode: 'strip' }), sandbox);
  page = sandbox.page;
  Object.assign(page, {
    refreshingCloudFonts: false, cloudDownloadQueueRaw: '[]', cloudFontError: '', cloudDownloadStatus: '',
    fontComponentActive: true,
    cloudRemoteFontsRaw: JSON.stringify([font]), customFonts: [],
    readerFontFilePath: '/files/current.ttf', readerFontFamily: 'current-family', readerFontMode: 'custom',
    reloadCustomFonts: async () => {},
    loadCustomFonts: () => { page.customFonts = [...state.records]; },
    registerCustomFont: item => { state.registered.push(item); return state.registrationSucceeds ? item.familyName : ''; }
  });
  return { page, state };
}

test('downloads queue distinct fonts, deduplicate taps, report progress and preserve selection', async () => {
  const { page, state } = fixture();
  state.gate = deferred();
  const downloading = page.downloadCloudFont(font);
  await Promise.resolve();
  await page.downloadCloudFont(font);
  const second = { ...font, id: 'cloud-b' };
  page.cloudRemoteFontsRaw = JSON.stringify([font, second]);
  const queued = page.downloadCloudFont(second);
  await page.downloadCloudFont(second);
  assert.match(page.cloudFontStatus(second), /排队中.*1/);
  assert.equal(state.downloads, 1);
  state.progress(1, 2);
  assert.equal(page.cloudFontStatus(font), '下载中 50%');
  state.onWait(3);
  assert.equal(page.cloudFontStatus(font), '3 秒后继续下载');
  state.gate.resolve();
  await Promise.all([downloading, queued]);
  assert.deepEqual(state.order, ['cloud-a', 'cloud-b']);
  assert.equal(page.remoteFonts().length, 0);
  assert.equal(page.customFonts[0].sourceName, font.name);
  assert.equal(state.registered.length, 2);
  assert.equal(page.readerFontFilePath, '/files/current.ttf');
  assert.equal(page.readerFontFamily, 'current-family');
  assert.equal(page.readerFontMode, 'custom');
  assert.equal(page.cloudDownloadQueueRaw, '[]');
  assert.equal(page.cloudDownloadStatus, '');
});

test('failed download keeps the cloud row, releases the busy state and can be retried', async () => {
  const { page, state } = fixture();
  state.fail = '网络连接失败';
  await page.downloadCloudFont(font);
  assert.equal(page.remoteFonts().length, 1);
  assert.equal(page.customFonts.length, 0);
  assert.equal(page.cloudDownloadQueueRaw, '[]');
  assert.equal(page.cloudFontError, state.fail);
  state.fail = '';
  await page.downloadCloudFont(font);
  assert.equal(page.remoteFonts().length, 0);
  assert.equal(page.customFonts.length, 1);
  assert.equal(page.cloudFontError, '');
});

test('failed font registration does not claim the font is ready to use or change selection', async () => {
  const { page, state } = fixture();
  state.registrationSucceeds = false;
  await page.downloadCloudFont(font);
  assert.match(state.notices.at(-1), /注册失败/);
  assert.equal(page.readerFontFilePath, '/files/current.ttf');
});

test('failed font does not block later queued fonts and remains available for retry', async () => {
  const { page, state } = fixture();
  const second = { ...font, id: 'cloud-b' };
  page.cloudRemoteFontsRaw = JSON.stringify([font, second]);
  state.failedIds.add(font.id);
  await Promise.all([page.downloadCloudFont(font), page.downloadCloudFont(second)]);
  assert.deepEqual(state.order, [font.id, second.id]);
  assert.equal(page.remoteFonts().length, 1);
  assert.equal(page.remoteFonts()[0].id, font.id);
  assert.equal(page.customFonts.length, 1);
  assert.equal(page.cloudDownloadQueueRaw, '[]');
});

test('leaving the font page keeps downloads running without registering against a destroyed UI', async () => {
  const { page, state } = fixture();
  state.gate = deferred();
  const running = page.downloadCloudFont(font);
  page.fontComponentActive = false;
  state.gate.resolve();
  await running;
  assert.equal(state.records.length, 1);
  assert.equal(state.registered.length, 0);
  page.fontComponentActive = true;
  page.onCloudDownloadQueueChanged();
  assert.equal(page.customFonts.length, 1);
});

test('duplicate lifecycle refreshes are coalesced and failed refresh preserves known cloud fonts', async () => {
  const { page, state } = fixture();
  state.gate = deferred();
  const refreshing = page.refreshFontLists();
  await page.refreshFontLists();
  state.fail = '服务器暂不可用';
  state.gate.resolve();
  await refreshing;
  assert.equal(state.refreshes, 1);
  assert.equal(page.refreshingCloudFonts, false);
  assert.equal(page.remoteFonts().length, 1);
  assert.equal(page.cloudFontError, state.fail);
  state.gate = null;
  state.fail = '';
  await page.refreshFontLists();
  assert.equal(page.cloudFontError, '');
  assert.equal(page.cloudFontSize(font.bytes), '2.0 MB');
});
