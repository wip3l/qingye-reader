import { taskpool } from '@kit.ArkTS';
import { deviceInfo } from '@kit.BasicServicesKit';
import { pdfService } from '@kit.PDFKit';
import { PdfSearchHit, PdfSearchRect, PdfSearchSummary } from '../book/pdf/PdfModels';

/**
 * Search a separate document, never the view's native search callbacks. Do not retain full-book text.
 * PdfController.searchKey() crashed in PDFView::ExecuteCB (SIGSEGV) on API 26 devices; don't switch back without a device check.
 */
@Concurrent
async function searchPdfInTask(path: string, keyword: string): Promise<string> {
  const summary = new PdfSearchSummary();
  const document = new pdfService.PdfDocument();
  try {
    if (document.loadDocument(path) !== pdfService.ParseResult.PARSE_SUCCESS) throw new Error('无法打开 PDF 进行搜索');
    if (deviceInfo.sdkApiVersion >= 21) {
      await document.searchKey(keyword, (results: pdfService.SearchResultData[]): boolean => {
        for (const result of results) {
          if (summary.hits.length >= 5000) { summary.truncated = true; return true; }
          const hit = new PdfSearchHit(); hit.pageIndex = result.pageIndex;
          hit.rects = result.rects.map((rect: pdfService.PdfRect): PdfSearchRect =>
            PdfSearchRect.of(rect.left, rect.top, rect.right, rect.bottom));
          summary.hits.push(hit);
        }
        return false;
      }, { isMatchCase: false });
    } else {
      // API 20 has the original graphics/text-object API. Match the ordered page objects and keep character rectangles.
      const needle = keyword.toLowerCase();
      for (let index = 0; index < document.getPageCount() && !summary.truncated; index++) {
        const page = document.getPage(index);
        try {
          let text = '';
          const rects: PdfSearchRect[] = [];
          for (const object of page.getGraphicsObjects()) {
            if (object.type !== pdfService.GraphicsObjectType.OBJECT_TEXT) continue;
            const item = object as pdfService.TextObject;
            const codes = item.charUnicodes;
            const boxes = item.charRects;
            for (let i = 0; i < Math.min(codes.length, boxes.length); i++) {
              const character = String.fromCodePoint(codes[i]);
              text += character;
              for (let unit = 0; unit < character.length; unit++) {
                const rect = boxes[i]; rects.push(PdfSearchRect.of(rect.left, rect.top, rect.right, rect.bottom));
              }
            }
          }
          const haystack = text.toLowerCase();
          let start = haystack.indexOf(needle);
          while (start >= 0) {
            if (summary.hits.length >= 5000) { summary.truncated = true; break; }
            const hit = new PdfSearchHit(); hit.pageIndex = index; hit.rects = rects.slice(start, start + needle.length);
            summary.hits.push(hit);
            start = haystack.indexOf(needle, start + Math.max(1, needle.length));
          }
        } finally { page.release(); }
      }
    }
  } catch (error) { summary.error = error instanceof Error ? error.message : 'PDF 搜索失败'; }
  finally { document.releaseDocument(); }
  return JSON.stringify(summary);
}

export class PdfSearchTask {
  static async search(path: string, keyword: string): Promise<PdfSearchSummary> {
    if (!keyword.trim()) return new PdfSearchSummary();
    const output = await taskpool.execute(searchPdfInTask, path, keyword.trim());
    if (typeof output !== 'string') throw new Error('PDF 搜索失败');
    const summary = JSON.parse(output) as PdfSearchSummary;
    if (summary.error) throw new Error(summary.error);
    return summary;
  }
}
