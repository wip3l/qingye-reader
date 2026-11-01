import { fileIo as fs } from '@kit.CoreFileKit';
import { digestHashHex } from '@legado/sourceengine';
import { ReaderComicSuperResolution } from '@legado/aiengine';
import { PdfRasterTask } from '../../concurrency/PdfRasterTask';
import { ReaderCacheCoordinator } from '../ReaderCacheCoordinator';
import { ReaderCacheBudget } from '../ReaderCacheBudget';
import { PdfRasterPage, PdfRasterPolicy } from './PdfRasterModels';

export class PdfEnhancedPage {
  raster: PdfRasterPage = new PdfRasterPage();
  enhancedUri: string = '';
  releaseFiles: () => void = (): void => {};
}

/** At most three retained pages; shared comic budget/compute queue owns derived images. */
export class PdfSuperResolutionSession {
  private pages: Map<number, PdfEnhancedPage> = new Map<number, PdfEnhancedPage>();
  private disposed: boolean = false;
  private identity: string = '';
  private chain: Promise<void> = Promise.resolve();
  private sourcePath: string;
  private cacheDir: string;

  constructor(sourcePath: string, cacheDir: string) { this.sourcePath = sourcePath; this.cacheDir = cacheDir; }

  get(index: number): PdfEnhancedPage | undefined { return this.pages.get(index); }

  retain(pages: number[]): void {
    for (const entry of this.pages) {
      const index = entry[0]; const page = entry[1];
      if (!pages.includes(index)) { page.releaseFiles(); this.pages.delete(index); }
    }
  }

  prepare(index: number, displayWidth: number, active: () => boolean): Promise<PdfEnhancedPage | undefined> {
    const next = this.chain.then((): Promise<PdfEnhancedPage | undefined> => this.load(index, displayWidth, active));
    this.chain = next.then((): void => {}, (): void => {});
    return next;
  }

  private async load(index: number, displayWidth: number, active: () => boolean): Promise<PdfEnhancedPage | undefined> {
    if (this.disposed || !active()) return undefined;
    const previous = this.pages.get(index);
    if (previous) return previous;
    if (!this.identity) {
      const stat = await fs.stat(this.sourcePath);
      this.identity = `${this.sourcePath}\n${stat.size}\n${stat.mtime}`;
    }
    if (!this.cacheDir || this.disposed || !active()) return undefined;
    const dir = `${this.cacheDir}/comic_images`;
    if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
    const key = digestHashHex('SHA256', `pdf-raster-v2\n${this.identity}\n${index}\n${Math.round(displayWidth)}`);
    const path = `${dir}/pdf_${key}.jpg`;
    const releaseSource = ReaderCacheCoordinator.retainFile(path);
    let releaseEnhanced: () => void = (): void => {};
    let transferred = false;
    try {
      const raster = await PdfRasterTask.render(this.sourcePath, index, displayWidth, path,
        (): boolean => !this.disposed && active());
      if (raster.imagePath) ReaderCacheBudget.noteComicWrite(raster.imagePath);
      if (this.disposed || !active()) return undefined;
      const result = new PdfEnhancedPage(); result.raster = raster;
      if (raster.eligible) {
        result.enhancedUri = await ReaderComicSuperResolution.enhance(raster.imagePath, displayWidth,
          (): boolean => !this.disposed && active());
        if (result.enhancedUri) releaseEnhanced = ReaderCacheCoordinator.retainFile(result.enhancedUri);
      }
      if (this.disposed || !active()) return undefined;
      result.releaseFiles = (): void => { releaseSource(); releaseEnhanced(); };
      this.pages.set(index, result); transferred = true;
      while (this.pages.size > PdfRasterPolicy.MAX_RETAINED_PAGES) {
        const oldest = this.pages.keys().next().value as number;
        this.pages.get(oldest)?.releaseFiles(); this.pages.delete(oldest);
      }
      return result;
    } finally { if (!transferred) { releaseSource(); releaseEnhanced(); } }
  }

  dispose(): void {
    this.disposed = true;
    for (const page of this.pages.values()) page.releaseFiles();
    this.pages.clear();
  }
}
