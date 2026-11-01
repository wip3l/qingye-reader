import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { PdfImportTask } from '../../../main/ets/core/concurrency/PdfImportTask';
import { PdfBookService } from '../../../main/ets/core/book/pdf/PdfBookService';
import { appDb } from '../../../main/ets/model/data/AppDatabase';
import { Book } from '@legado/sourceengine';
import { LocalBookService } from '../../../main/ets/core/book/LocalBookService';
import { relationalStore } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { PdfRasterTask } from '../../../main/ets/core/concurrency/PdfRasterTask';
import { AiHost, AiRuntime, ReaderComicSuperResolution } from '@legado/aiengine';
import { digestHashHex } from '@legado/sourceengine';
import { AppAiHost } from '../../../main/ets/utils/AppAiHost';
import { image } from '@kit.ImageKit';

/** Test process only: exercise native inference with generated fixtures, never account data. */
class PdfProbeAiHost implements AiHost {
  private root: string;
  constructor(root: string) { this.root = root; }
  isAllowed(feature: string): boolean { return feature === 'super-resolution'; }
  cacheDir(): string { return this.root; }
  async downloadImage(_source: string): Promise<Uint8Array> { throw new Error('PDF probe cannot access network'); }
  digestHashHex(algorithm: string, value: string): string { return digestHashHex(algorithm, value); }
  touchComicFile(_path: string): void {}
  noteComicWrite(_path?: string): void {}
  resolveImageSource(marker: string): string { return marker; }
  createColorWorker(): never { throw new Error('Colorization is outside PDF probe'); }
}

/** Native PDF probe: only writes fixtures into entry_test cache, never touches the user's books. */
export default class PdfSupportTestRunner implements TestRunner {
  onPrepare(): void {}
  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    try {
      const context = delegator.getAppContext().createModuleContext('entry_test');
      const parameters = abilityDelegatorRegistry.getArguments().parameters;
      const sr = (parameters['-s pdfSuperResolution'] || parameters['pdfSuperResolution']) === 'true';
      const root = `${context.cacheDir}/pdf-native-probe`;
      if (!fs.accessSync(root)) fs.mkdirSync(root, true);
      for (const name of ['text.pdf', 'scan.pdf', 'single.pdf', 'long.pdf']) {
        const bytes = await context.resourceManager.getRawFileContent(`pdf/${name}`);
        const path = `${root}/${name}`;
        const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try { fs.writeSync(file.fd, bytes.buffer as ArrayBuffer); } finally { fs.closeSync(file); }
        if ((parameters['-s pdfViewOnly'] || parameters['pdfViewOnly']) === 'true') continue;
        const started = Date.now();
        const result = await PdfImportTask.extract(path, root);
        const expected = name === 'long.pdf' ? 1000 : name === 'single.pdf' ? 1 : 3;
        if (result.pageCount !== expected || !result.coverPath) throw new Error(`${name}: page count or cover failed`);
        if (name === 'text.pdf' && (result.title !== 'PDF Native Probe' || result.outline.length !== 2)) {
          throw new Error('PDF metadata or outline failed');
        }
        console.info(`[PdfProbe] PASS ${name}: pages=${result.pageCount} outline=${result.outline.length} ms=${Date.now() - started}`);
      }
      await this.verifyStorage(context, `${root}/text.pdf`, 3);
      await this.verifyStorage(context, `${root}/long.pdf`, 1000);
      if (sr) {
        if (!ReaderComicSuperResolution.supported()) throw new Error('PDF SR probe requires a supported API 26 device');
        AppStorage.setOrCreate('appCacheDir', `${root}/ai-cache`);
        AiRuntime.install(new PdfProbeAiHost(`${root}/ai-cache`));
        const text = await PdfRasterTask.render(`${root}/text.pdf`, 1, 1000, `${root}/text-raster.jpg`);
        const scan = await PdfRasterTask.render(`${root}/scan.pdf`, 1, 1000, `${root}/scan-raster-v2.jpg`);
        if (text.eligible || !scan.eligible || !fs.accessSync(scan.imagePath)) {
          throw new Error(`PDF SR page classification failed: text=${JSON.stringify(text)} scan=${JSON.stringify(scan)}`);
        }
        const input = fs.openSync(scan.imagePath, fs.OpenMode.READ_ONLY);
        const decoder = image.createImageSource(input.fd);
        try {
          const bitmap = await decoder.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
          try {
            const info = await bitmap.getImageInfo();
            const bytes = new Uint8Array(info.size.width * info.size.height * 4);
            await bitmap.readPixelsToBuffer(bytes.buffer as ArrayBuffer);
            const green = (Math.floor(info.size.height * 0.25) * info.size.width + Math.floor(info.size.width * 0.75)) * 4;
            const blue = (Math.floor(info.size.height * 0.75) * info.size.width + Math.floor(info.size.width * 0.25)) * 4;
            if (bytes[green + 1] < 180 || bytes[green] > 80 || bytes[blue + 2] < 180 || bytes[blue] > 80) {
              throw new Error('PDF raster geometry cropped or moved the test quadrants');
            }
          } finally { await bitmap.release(); }
        } finally { await decoder.release(); fs.closeSync(input); }
        console.info('[PdfProbe] PASS PDF raster classification and bounded background rendering');
      }
      AppStorage.setOrCreate('pdfNativeSrProbe', sr);
      AppStorage.setOrCreate('pdfNativeProbePath', `${root}/${sr ? 'scan' : 'text'}.pdf`);
      AppStorage.setOrCreate('pdfNativeProbeResult', '');
      const preview = (parameters['-s pdfControlsPreview'] || parameters['pdfControlsPreview']) === 'true';
      AppStorage.setOrCreate('pdfNativeControlsPreview', preview);
      await delegator.startAbility({ bundleName: 'io.legado.read', abilityName: 'PdfNativeViewTestAbility' });
      for (let attempt = 0; attempt < (preview ? 1800 : sr ? 600 : 100); attempt++) {
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 200); });
        const result = AppStorage.get<string>('pdfNativeProbeResult') || '';
        if (result === 'PDF_NATIVE_VIEW_PASS') {
          AppAiHost.install();
          await delegator.finishTest(sr ? 'PDF_SUPER_RESOLUTION_AND_NATIVE_VIEW_PASS' : 'PDF_NATIVE_PROBE_AND_VIEW_PASS', 0); return;
        }
        if (result.indexOf('FAIL') >= 0) throw new Error(result);
      }
      if (preview) { AppAiHost.install(); await delegator.finishTest('PDF_CONTROLS_PREVIEW_FINISHED', 0); return; }
      throw new Error('PDF native view probe timed out');
    } catch (error) { AppAiHost.install(); await delegator.finishTest(`PDF_NATIVE_PROBE_FAIL ${String(error)}`, -1); }
  }

  private async verifyStorage(context: Context, source: string, expectedPages: number): Promise<void> {
    // Explicit database name isolates these real RDB transactions from the user's legado.db.
    await appDb.init(context, 'pdf_support_probe.db');
    const candidate = new Book();
    candidate.bookUrl = 'local://pdf_native_storage_probe'; candidate.tocUrl = candidate.bookUrl;
    candidate.origin = 'local'; candidate.type = LocalBookService.TYPE_PDF; candidate.group = 42;
    candidate.durChapterIndex = 2; candidate.putVariable('localFormat', 'pdf');
    candidate.putVariable('readStarted', '1');
    try {
      const book = await PdfBookService.import(context, candidate, source, 'pdf_native_probe', 'Fallback', '',
        async (_path: string): Promise<string> => 'a'.repeat(64));
      const chapters = await appDb.getBookChapters(book.bookUrl);
      if (chapters.length !== expectedPages || book.group !== 42 || book.durChapterIndex !== 2) throw new Error('PDF storage/progress failed');
      if (await appDb.getCachedChapterContent(book.bookUrl, 0)) throw new Error('PDF unexpectedly wrote text content');
      const oldPath = book.getVariable('localFilePath');
      const oldRoot = book.getVariable('localExtractRoot');
      const damaged = `${context.cacheDir}/pdf-native-probe/damaged.pdf`;
      const file = fs.openSync(damaged, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, '%PDF-1.4\ninvalid'); } finally { fs.closeSync(file); }
      let rejected = false;
      try {
        await PdfBookService.import(context, book, damaged, 'pdf_native_probe', '', '',
          async (_path: string): Promise<string> => 'b'.repeat(64));
      } catch (_) { rejected = true; }
      if (!rejected || !fs.accessSync(oldPath) || (await appDb.getBook(book.bookUrl))?.getVariable('localFilePath') !== oldPath) {
        throw new Error('Failed PDF reimport damaged the committed revision');
      }
      const changed = (await appDb.getBook(book.bookUrl))!;
      changed.name = 'Rollback sentinel';
      rejected = false;
      const probeStore = await relationalStore.getRdbStore(context, {
        name: 'pdf_support_probe.db', securityLevel: relationalStore.SecurityLevel.S1
      });
      try {
        await probeStore.executeSql("CREATE TRIGGER pdf_probe_reject BEFORE INSERT ON book_chapters " +
          "WHEN NEW.bookUrl='local://pdf_native_storage_probe' BEGIN SELECT RAISE(ABORT,'pdf_probe_rollback'); END");
        try { await appDb.commitBookSourceSwitch(book.bookUrl, changed, chapters, true); }
        catch (_) { rejected = true; }
      } finally { await probeStore.executeSql('DROP TRIGGER IF EXISTS pdf_probe_reject'); await probeStore.close(); }
      if (!rejected || (await appDb.getBook(book.bookUrl))?.name === 'Rollback sentinel' ||
        await appDb.getBookChapterCount(book.bookUrl) !== expectedPages) throw new Error('PDF database transaction did not roll back');
      const replacement = await PdfBookService.import(context, (await appDb.getBook(book.bookUrl))!, source,
        'pdf_native_probe', '', '', async (_path: string): Promise<string> => 'a'.repeat(64));
      if (fs.accessSync(oldRoot) || !fs.accessSync(replacement.getVariable('localFilePath'))) {
        throw new Error('PDF revision cleanup failed');
      }
      console.info('[PdfProbe] PASS real RDB import, progress, parser failure, transaction rollback and revision cleanup');
    } finally { await LocalBookService.deleteBookWithFiles(context, candidate.bookUrl); }
  }
}
