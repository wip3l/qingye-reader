import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import fs from '@ohos.file.fs';
import { BookChapter } from '@legado/sourceengine';
import { appDb } from '../../../main/ets/model/data/AppDatabase';
import { ReaderCacheBudget } from '../../../main/ets/core/book/ReaderCacheBudget';
import { ReaderCacheCoordinator } from '../../../main/ets/core/book/ReaderCacheCoordinator';
import { ReaderImageCache } from '../../../main/ets/core/book/ReaderImageCache';
import { ReaderImageMarker } from '../../../main/ets/core/book/ReaderImageMarker';

/** Only the entry_test database and a unique test directory are used. No production book/cache is opened. */
export default class ReaderCacheSafetyTestRunner implements TestRunner {
  onPrepare(): void {}

  private require(value: boolean, message: string): void { if (!value) throw new Error(message); }

  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const context = delegator.getAppContext().createModuleContext('entry_test');
    let message = 'PASS ReaderCacheSafety';
    let code = 0;
    const oldFiles = AppStorage.get<string>('appFilesDir');
    const oldCache = AppStorage.get<string>('appCacheDir');
    const root = `${context.cacheDir}/cache-safety-${Date.now()}`;
    let ready = false;
    try {
      await appDb.init(context, 'reader-cache-safety.db');
      this.require(appDb.cacheDatabaseName() === 'reader-cache-safety.db', 'Production database is already active; refusing test');
      ready = true;
      fs.mkdirSync(`${root}/reader_images`, true);
      fs.mkdirSync(`${root}/comic_images`, true);
      AppStorage.setOrCreate('appFilesDir', root);
      AppStorage.setOrCreate('appCacheDir', root);
      ReaderCacheBudget.setProtectedBooksProvider((): string[] => []);
      const chapter = new BookChapter(); chapter.index = 0; chapter.url = 'cache-safety-chapter'; chapter.title = 'Fixture';
      await appDb.saveCachedChapterContent('cache-safety-novel', chapter, 'original');
      const selected = await appDb.listOnlineCachedContentEntries(true);
      await appDb.pinCachedChapterContent('cache-safety-novel', 0);
      const removed = await appDb.deleteCachedContentEntries(selected, false, Date.now());
      this.require(removed.removed === 0, 'A stale plan deleted a newly pinned chapter');
      await appDb.saveCachedChapterContent('cache-safety-novel', chapter, 'updated');
      this.require(await appDb.getOnlineCachedContentBytes() === 0, 'Offline content counted against automatic text budget');
      await delegator.print('PASS cache SQL: atomic pin preservation and stale-plan rejection\n');

      const image = `${root}/reader_images/original.png`;
      await ReaderImageCache.commit(image, new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]), 'fixture', 'https://fixture.invalid/image', 0);
      this.require(fs.statSync(image).size === 8 && !fs.accessSync(`${image}.part`), 'Atomic original write failed');
      await appDb.saveCachedChapterContent('cache-safety-comic', chapter, ReaderImageMarker.create(image), true);
      this.require(await ReaderCacheBudget.comicUsageBytes(true) === 8, 'Offline image ownership accounting failed');
      this.require((await ReaderCacheBudget.clearComic()).removed === 0, 'Pinned original was deleted');
      await delegator.print('PASS cache files: atomic commit and offline reference protection\n');

      const unpinned = `${root}/comic_images/old.jpg`;
      const old = fs.openSync(unpinned, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(old.fd, 'disposable'); } finally { fs.closeSync(old); }
      fs.utimes(unpinned, Date.now() - 3600000);
      const release = ReaderCacheCoordinator.retainFile(unpinned);
      try { this.require((await ReaderCacheBudget.clearComic()).removed === 0, 'Active image lease was ignored'); }
      finally { release(); }
      this.require((await ReaderCacheBudget.clearComic()).removed === 1 && !fs.accessSync(unpinned), 'Released old image was not removed');
      await delegator.print('PASS cache leases: active image retained, released image removed\n');

      const legacy = `${root}/comic_images/legacy.jpg`;
      const file = fs.openSync(legacy, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, 'legacy'); } finally { fs.closeSync(file); }
      await appDb.saveCachedChapterContent('cache-safety-legacy', chapter, ReaderImageMarker.create(legacy), true);
      await ReaderImageCache.migrateLegacy([legacy]);
      const text = await appDb.getCachedChapterContent('cache-safety-legacy', 0);
      this.require(text.includes('reader_images') && ReaderImageCache.complete(text, true) && fs.accessSync(legacy),
        'Migration did not preserve the old file and commit a complete new reference');
      await delegator.print('PASS cache migration: copied original and switched persisted references\n');

      // Sparse logical size exercises the real 1 GiB automatic threshold without writing a gigabyte of data.
      const large = `${root}/comic_images/over-budget.jpg`;
      const sparse = fs.openSync(large, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.truncateSync(sparse.fd, ReaderCacheBudget.COMIC_LIMIT_BYTES + 1024); } finally { fs.closeSync(sparse); }
      fs.utimes(large, Date.now() - 3600000);
      ReaderCacheBudget.scheduleStartupTrim(0);
      for (let i = 0; i < 100 && fs.accessSync(large); i++) {
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 100); });
      }
      this.require(!fs.accessSync(large), 'Automatic over-budget sweep did not delete an old unprotected image');
      this.require(fs.accessSync(image), 'Automatic sweep deleted the pinned original');
      await delegator.print('PASS automatic 1 GiB threshold: old file removed, offline original preserved\n');
    } catch (e) { message = `FAIL ReaderCacheSafety: ${(e as Error).message}`; code = -1; }
    finally {
      if (ready) {
        for (const book of ['cache-safety-novel', 'cache-safety-comic', 'cache-safety-legacy']) await appDb.deleteBookCachedContent(book);
        for (const dir of [`${root}/reader_images`, `${root}/comic_images`]) {
          if (fs.accessSync(dir)) {
            for (const name of fs.listFileSync(dir)) fs.unlinkSync(`${dir}/${name}`);
            fs.rmdirSync(dir);
          }
        }
        if (fs.accessSync(root)) fs.rmdirSync(root);
      }
      if (oldFiles !== undefined) AppStorage.setOrCreate('appFilesDir', oldFiles);
      else AppStorage.delete('appFilesDir');
      if (oldCache !== undefined) AppStorage.setOrCreate('appCacheDir', oldCache);
      else AppStorage.delete('appCacheDir');
    }
    await delegator.finishTest(message, code);
  }
}
