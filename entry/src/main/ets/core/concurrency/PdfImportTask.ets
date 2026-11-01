import { taskpool } from '@kit.ArkTS';
import { extractPdfBook } from '../book/pdf/PdfBookExtractor';
import { PdfImportSummary } from '../book/pdf/PdfModels';

@Concurrent
async function extractPdfInTask(path: string, assetsRoot: string): Promise<string> {
  try { return JSON.stringify(await extractPdfBook(path, assetsRoot)); }
  catch (error) {
    const result = new PdfImportSummary();
    result.error = error instanceof Error ? error.message : 'PDF 解析失败';
    return JSON.stringify(result);
  }
}

export class PdfImportTask {
  /** Never fall back to synchronous parsing on the UI thread. */
  static async extract(path: string, assetsRoot: string): Promise<PdfImportSummary> {
    if (!canIUse('SystemCapability.OfficeService.PDFService.Core')) throw new Error('此设备暂不支持 PDF 阅读');
    const output = await taskpool.execute(extractPdfInTask, path, assetsRoot);
    if (typeof output !== 'string') throw new Error('PDF 后台解析失败，请重试');
    const summary = JSON.parse(output) as PdfImportSummary;
    if (summary.error) throw new Error(summary.error);
    return summary;
  }
}
