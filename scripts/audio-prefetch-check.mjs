// 使用生产调度和网络策略，验证边听边下在移动网络上也会实际提交下载任务。
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

function fixture(network, count = 3, origin = 'https://source.example') {
  const values = new Map([['audioPrefetchCount', count], ['audioOfflineWifiOnly', true]]);
  const downloads = [];
  const workers = [];
  const book = { bookUrl: 'https://source.example/book', origin };
  const context = vm.createContext({
    console,
    AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value) },
    AppDatabase: { getInstance: () => ({ getBook: async () => book }) },
    ReadBookEngine: {
      createBackgroundWorker() {
        const worker = {
          chapters: [0, 0, 1, 0, 0].map(cacheDate => ({ cacheDate })),
          lastCacheError: '',
          async openBook() {},
          async syncChapterCacheDates() {},
          cancelPendingRequests() {},
          async cacheChapter(index, cancelled) {
            assert.equal(cancelled(), false);
            if (!context.AudioOfflineStore.networkAllows(this.audioAllowCellular)) return false;
            downloads.push(index);
            return true;
          },
        };
        workers.push(worker);
        return worker;
      },
    },
  });
  for (const [file, name] of [
    ['core/book/AudioOfflinePolicy.ts', 'AudioOfflinePolicy'],
    ['core/book/AudioOfflineStore.ts', 'AudioOfflineStore'],
    ['utils/AudioPrefetch.ets', 'AudioPrefetch'],
  ]) {
    const source = readEtsModule(file).replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '');
    vm.runInContext(stripTypeScriptTypes(source) + `\nglobalThis.${name} = ${name};`, context);
  }
  context.AudioOfflineStore.network = () => network;
  context.AudioOfflineStore.evictListened = async () => 0;
  return { context, book, downloads, workers };
}

let checks = 0;
for (const network of ['wifi', 'cellular', 'other', 'none']) {
  const f = fixture(network);
  const prefetch = f.context.AudioPrefetch.get();
  prefetch.schedule(f.book, 1);
  await prefetch.running;
  assert.deepEqual(f.downloads, network === 'none' ? [] : [3, 4],
    `${network}: 补齐后续三章，跳过已下载章节`);
  assert.equal(f.workers.length, network === 'none' ? 0 : 1);
  if (network !== 'none') {
    assert.equal(f.workers[0].audioAuto, true);
    assert.equal(f.workers[0].audioAllowCellular, true, '下载引擎也必须允许流量');
  }
  assert.equal(f.context.AudioOfflineStore.networkAllows(false), !['cellular', 'none'].includes(network),
    '手动下载未授权流量时仍遵守原有网络策略');
  checks++;
}
for (const f of [fixture('cellular', 0), fixture('cellular', 3, 'local')]) {
  const prefetch = f.context.AudioPrefetch.get();
  prefetch.schedule(f.book, 1);
  await prefetch.running;
  assert.deepEqual(f.downloads, [], '关闭边听边下或本地书籍不发起下载');
  assert.equal(f.workers.length, 0);
  checks++;
}
console.log(`audio-prefetch-check: ${checks} scenarios passed`);
