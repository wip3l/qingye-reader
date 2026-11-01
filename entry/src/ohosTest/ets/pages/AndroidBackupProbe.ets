import { HttpClient, Book, BookSource, BookSourceRuntimeStore } from '@legado/sourceengine';
import { appDb } from '../../../main/ets/model/data/AppDatabase';
import { ReadBookEngine } from '../../../main/ets/core/book/ReadBookEngine';
import { BookSourceStageRuntimeHost } from '../../../main/ets/components/BookSourceStageRuntimeHost';
import { WebBookFetchRuntimeHost } from '../../../main/ets/components/WebBookFetchRuntimeHost';

class AndroidBackupProbeFixture {
  books: Book[] = [];
  sources: BookSource[] = [];
}

/** Test-only loopback fixture. Database and source runtime writes are isolated from the user's shelf. */
@Entry
@Component
struct AndroidBackupProbe {
  @State report: string = '准备备份开书验证';

  aboutToAppear(): void { this.run(); }

  private async run(): Promise<void> {
    try {
      const response = await new HttpClient(10000).execute({
        url: AppStorage.get<string>('androidBackupProbeUrl') || 'http://127.0.0.1:18395/fixture', method: 'GET',
        headers: {}
      });
      if (!response.success) throw new Error('Fixture unavailable: ' + response.error);
      const fixture = JSON.parse(response.body) as AndroidBackupProbeFixture;
      const raw = fixture.books[0];
      if (!raw || fixture.sources.length === 0) throw new Error('Fixture has no book/source');
      await appDb.init(getContext(this), 'android_backup_probe.db');
      BookSourceRuntimeStore.install(appDb);
      for (const source of fixture.sources) await appDb.restoreBookSource(source);
      const book = new Book();
      book.bookUrl = raw.bookUrl;
      book.tocUrl = raw.tocUrl;
      book.name = raw.name;
      book.author = raw.author;
      book.origin = raw.origin;
      book.originName = raw.originName;
      book.type = raw.type;
      book.totalChapterNum = raw.totalChapterNum;
      book.durChapterIndex = raw.durChapterIndex;
      book.durChapterPos = raw.durChapterPos;
      book.durChapterTitle = raw.durChapterTitle;
      book.durChapterTime = raw.durChapterTime;
      book.readConfig = raw.readConfig;
      book.lastCheckTime = 0;
      book.replaceVariable(raw.variable);
      await appDb.restoreBook(book);
      this.report = '正在解析导入书籍的目录';
      console.info('[AndroidBackupProbe] opening normalized backup book');
      const engine = ReadBookEngine.createBackgroundWorker();
      await engine.openBook(book);
      if (engine.chapters.length === 0) throw new Error('Catalog empty');
      this.report = `目录 ${engine.chapters.length} 章，正在读取第 ${book.durChapterIndex} 章`;
      const content = await engine.loadContent(book.durChapterIndex);
      if (!content) throw new Error('Content empty: ' + engine.lastCacheError);
      this.report = `PASS catalog=${engine.chapters.length}, chapter=${book.durChapterIndex}, chars=${content.length}`;
      AppStorage.setOrCreate('androidBackupProbeResult', this.report);
    } catch (error) {
      this.report = 'FAIL ' + String(error);
      AppStorage.setOrCreate('androidBackupProbeResult', this.report);
    }
    console.info('[AndroidBackupProbe] ' + this.report);
  }

  build() {
    Stack() {
      Text(this.report).fontSize(18).padding(24)
      BookSourceStageRuntimeHost()
      WebBookFetchRuntimeHost()
    }.width('100%').height('100%')
  }
}
