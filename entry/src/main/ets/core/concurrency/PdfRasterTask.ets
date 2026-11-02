import { taskpool } from '@kit.ArkTS';
import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { PdfRasterPage, PdfRasterPolicy } from '../book/pdf/PdfRasterModels';

@Concurrent
async function renderPdfRaster(path: string, pageIndex: number, displayWidth: number, outputPath: string): Promise<string> {
  const result = new PdfRasterPage();
  result.pageIndex = pageIndex;
  const document = new pdfService.PdfDocument();
  let page: pdfService.PdfPage | null = null;
  try {
    if (document.loadDocument(path) !== pdfService.ParseResult.PARSE_SUCCESS) throw new Error('PDF 页面加载失败');
    page = document.getPage(pageIndex);
    result.pageWidth = page.getWidth(); result.pageHeight = page.getHeight();
    if (page.getRotation() !== pdfService.RotationAngle.ANGLE_0 || page.getTextContent().trim()) {
      result.reason = '本页使用原生清晰显示'; return JSON.stringify(result);
    }
    let crop = page.getBox(pdfService.BoxType.BOX_CROP);
    // A missing CropBox is reported as an empty rect on some PDF Kit versions.
    if (Math.abs(crop.right - crop.left) < 0.01 || Math.abs(crop.top - crop.bottom) < 0.01) {
      crop = page.getBox(pdfService.BoxType.BOX_MEDIA);
    }
    result.rectLeft = crop.left; result.rectTop = crop.top; result.rectRight = crop.right; result.rectBottom = crop.bottom;
    if (Math.abs(Math.min(crop.left, crop.right)) > 0.01 || Math.abs(Math.min(crop.top, crop.bottom)) > 0.01 ||
      Math.abs(Math.max(crop.left, crop.right) - result.pageWidth) > 0.01 ||
      Math.abs(Math.max(crop.top, crop.bottom) - result.pageHeight) > 0.01) {
      result.reason = '本页使用原生清晰显示'; return JSON.stringify(result);
    }
    const objects = page.getGraphicsObjects();
    let imageArea = 0;
    let intrinsicWidth = 0;
    let vectorContent = false;
    try {
      for (const object of objects) {
        if (object.type === pdfService.GraphicsObjectType.OBJECT_IMAGE) {
          const scan = object as pdfService.ImageObject;
          if (scan.width > 0 && scan.height > 0) {
            imageArea += scan.width * scan.height;
            const info = await scan.pixelMap.getImageInfo();
            intrinsicWidth = Math.max(intrinsicWidth, info.size.width * result.pageWidth / scan.width);
          }
        } else { vectorContent = true; }
      }
    } finally {
      for (const object of objects) {
        if (object.type === pdfService.GraphicsObjectType.OBJECT_IMAGE) {
          try { await (object as pdfService.ImageObject).pixelMap.release(); } catch (_) {}
        }
      }
    }
    if (vectorContent || imageArea < result.pageWidth * result.pageHeight * 0.45) {
      result.reason = '本页使用原生清晰显示';
      console.info(`[PdfSR] page classification: vector=${vectorContent} imageArea=${imageArea} page=${result.pageWidth}x${result.pageHeight}`);
      return JSON.stringify(result);
    }
    const width = PdfRasterPolicy.inputWidth(result.pageWidth, result.pageHeight, intrinsicWidth, displayWidth);
    if (width < 32) { result.reason = '本页无需增强'; return JSON.stringify(result); }
    result.eligible = true; result.imagePath = outputPath;
    if (fs.accessSync(outputPath) && fs.statSync(outputPath).size > 0) return JSON.stringify(result);
    const height = Math.max(1, Math.floor(width * result.pageHeight / result.pageWidth));
    // The matrix must use the output raster size; page points here crop small canvases to the top-left corner.
    const matrix = new pdfService.PdfMatrix();
    matrix.x = 0; matrix.y = 0; matrix.width = width; matrix.height = height; matrix.rotate = 0;
    const bitmap = page.getAreaPixelMap(matrix, width, height, false, true);
    const packer = image.createImagePacker();
    try {
      const bytes = await packer.packToData(bitmap, { format: 'image/jpeg', quality: 95 });
      const file = fs.openSync(`${outputPath}.part`, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(file.fd, bytes); } finally { fs.closeSync(file); }
      fs.renameSync(`${outputPath}.part`, outputPath);
    } finally { await packer.release(); await bitmap.release(); }
  } catch (error) {
    result.error = error instanceof Error ? error.message : 'PDF 页面增强失败';
    try { if (fs.accessSync(`${outputPath}.part`)) fs.unlinkSync(`${outputPath}.part`); } catch (_) {}
  } finally { if (page) page.release(); document.releaseDocument(); }
  return JSON.stringify(result);
}

export class PdfRasterTask {
  private static chain: Promise<void> = Promise.resolve();
  /** Only serializable metadata/file paths cross the TaskPool boundary. */
  static render(path: string, index: number, displayWidth: number, outputPath: string,
    active: () => boolean = (): boolean => true): Promise<PdfRasterPage> {
    const next = PdfRasterTask.chain.then(async (): Promise<PdfRasterPage> => {
      if (!active()) throw new Error('PDF 页面增强已取消');
      const output = await taskpool.execute(renderPdfRaster, path, index, displayWidth, outputPath);
      if (typeof output !== 'string') throw new Error('PDF 页面图像生成失败');
      const result = JSON.parse(output) as PdfRasterPage;
      if (result.error) throw new Error(result.error);
      return result;
    });
    PdfRasterTask.chain = next.then((): void => {}, (): void => {});
    return next;
  }
}
