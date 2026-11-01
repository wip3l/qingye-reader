import taskpool from '@ohos.taskpool';
import { extractMobiBook, MobiExtractSummary } from '../book/MobiBookExtractor';

/** 后台线程里拆 MOBI；解析失败的提示（DRM、KF8 等）放进 error 字段带回，不当成线程池故障。 */
@Concurrent
function extractMobiInTask(mobiPath: string, extractRoot: string): string {
  try {
    return JSON.stringify(extractMobiBook(mobiPath, extractRoot));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const failure: Record<string, string> = {};
    failure['error'] = message || 'MOBI 解析失败';
    return JSON.stringify(failure);
  }
}

export class MobiImportTask {
  /**
   * 解析和写文件放到 TaskPool：大书在主线程上连续跑几秒，会被系统判定卡死杀掉。
   * 线程池本身出故障时退回当前线程执行。
   */
  static async extract(mobiPath: string, extractRoot: string): Promise<MobiExtractSummary> {
    let text = '';
    try {
      const value = await taskpool.execute(extractMobiInTask, mobiPath, extractRoot);
      text = typeof value === 'string' ? value : '';
    } catch (error) {
      console.warn('[MobiImportTask] TaskPool failed, extract on the current thread:', error);
    }
    if (!text) return extractMobiBook(mobiPath, extractRoot);
    const parsed = JSON.parse(text) as Record<string, Object>;
    if (typeof parsed['error'] === 'string') throw new Error(parsed['error'] as string);
    return parsed as Object as MobiExtractSummary;
  }
}
