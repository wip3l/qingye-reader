import { pdfService } from '@kit.PDFKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { PdfImportSummary, PdfOutlineEntry } from './PdfModels';

/** Called only inside the PDF import TaskPool task. Native objects never leave this thread. */
export async function extractPdfBook(path: string, assetsRoot: string): Promise<PdfImportSummary> {
  const summary = new PdfImportSummary();
  const document = new pdfService.PdfDocument();
  try {
    const result = document.loadDocument(path);
    if (result === pdfService.ParseResult.PARSE_ERROR_PASSWORD) throw new Error('此 PDF 需要打开密码，暂不支持导入');
    if (result !== pdfService.ParseResult.PARSE_SUCCESS) throw new Error('PDF 损坏或格式不受支持');
    summary.pageCount = document.getPageCount();
    if (!Number.isSafeInteger(summary.pageCount) || summary.pageCount <= 0) throw new Error('PDF 没有可阅读的页面');
    try {
      const metadata = document.getMetadata();
      summary.title = (metadata.title || '').trim();
      summary.author = (metadata.author || '').trim();
    } catch (_) { /* Missing metadata does not make the document unreadable. */ }
    try { appendPdfOutline(document.getRootBookmarks(), summary, 0); } catch (_) { /* Page navigation is always available. */ }
    let coverPage: pdfService.PdfPage | null = null;
    try {
      const page = document.getPage(0);
      coverPage = page;
      const pageWidth = page.getWidth();
      const pageHeight = page.getHeight();
      if (pageWidth > 0 && pageHeight > 0 && Number.isFinite(pageWidth + pageHeight)) {
        const ratio = 600 / Math.max(pageWidth, pageHeight);
        const matrix = new pdfService.PdfMatrix();
        matrix.x = 0; matrix.y = 0; matrix.width = pageWidth; matrix.height = pageHeight; matrix.rotate = 0;
        const bitmap = page.getAreaPixelMap(matrix, Math.max(1, Math.round(pageWidth * ratio)),
          Math.max(1, Math.round(pageHeight * ratio)), false, true);
        const packer = image.createImagePacker();
        try {
          const data = await packer.packToData(bitmap, { format: 'image/jpeg', quality: 80 });
          const coverPath = `${assetsRoot}/cover.jpg`;
          const file = fs.openSync(coverPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          try { fs.writeSync(file.fd, data); } finally { fs.closeSync(file); }
          summary.coverPath = coverPath;
        } finally { await packer.release(); await bitmap.release(); }
      }
    } catch (error) { console.warn('[PDF] cover generation skipped:', error); }
    finally { if (coverPage) coverPage.release(); }
    return summary;
  } finally { document.releaseDocument(); }
}

function appendPdfOutline(bookmarks: pdfService.Bookmark[], summary: PdfImportSummary, depth: number): void {
  if (depth > 16 || summary.outline.length >= 4096) return;
  for (let i = 0; i < bookmarks.length && summary.outline.length < 4096; i++) {
    const bookmark = bookmarks[i];
    try {
      const target = bookmark.getDestInfo();
      if (Number.isInteger(target.pageIndex) && target.pageIndex >= 0 && target.pageIndex < summary.pageCount) {
        const entry = new PdfOutlineEntry();
        entry.id = `${summary.outline.length}`;
        entry.title = (bookmark.getBookmarkInfo().title || '').trim() || `第 ${target.pageIndex + 1} 页`;
        entry.pageIndex = target.pageIndex; entry.depth = depth;
        summary.outline.push(entry);
      }
      if (bookmark.hasChild()) appendPdfOutline(bookmark.getChildren(), summary, depth + 1);
    } catch (_) { /* A malformed outline entry must not prevent opening the file. */ }
  }
}
