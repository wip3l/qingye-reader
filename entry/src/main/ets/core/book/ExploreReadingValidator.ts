import { Book, BookChapter, BookSource, SearchBook, BookTypeSupport } from '@legado/sourceengine';
import { appDb } from '../../model/data/AppDatabase';
import { ExploreCoordinator, ExploreEntry } from './ExploreCoordinator';
import { WebBookService } from './WebBookService';
import { ReaderImageRequest } from './ReaderImageScheduler';
import { ReaderImageMarker } from './ReaderImageMarker';

export class ExploreReadingValidationResult {
  validationStatus: number = BookSource.VALIDATION_UNCHECKED;
  reason: string = '';
  entryTitle: string = '';
  bookName: string = '';
  chapterTitle: string = '';
  chapterCount: number = 0;
  mediaType: string = '正文';
}

export class ExploreReadingValidationProgress {
  done: number = 0;
  total: number = 0;
  sourceName: string = '';
  stage: string = '';
}

class ExploreBookCandidate {
  entry: ExploreEntry;
  book: SearchBook;

  constructor(entry: ExploreEntry, book: SearchBook) {
    this.entry = entry;
    this.book = book;
  }
}

/**
 * Runs the same public Explore -> detail -> TOC -> content pipeline used by the UI.
 * It deliberately selects only a chapter that the source marks as non-VIP/non-pay.
 */
export class ExploreReadingValidator {
  private static readonly EXPLORE_SAMPLE_LIMIT: number = 4;
  private static readonly CHAPTER_SAMPLE_LIMIT: number = 32;
  private cancelled: boolean = false;

  cancel(): void {
    this.cancelled = true;
  }

  async validateSources(sources: BookSource[],
    onProgress?: (progress: ExploreReadingValidationProgress) => void,
    onSourceComplete?: (source: BookSource, result: ExploreReadingValidationResult) => Promise<void>):
    Promise<void> {
    this.cancelled = false;
    let done = 0;
    for (const source of sources) {
      if (this.cancelled) break;
      this.publishProgress(onProgress, done, sources.length, source, '发现分类');
      const result = await this.validateSource(source, (stage: string): void => {
        this.publishProgress(onProgress, done, sources.length, source, stage);
      });
      if (this.cancelled) break;
      done++;
      if (onSourceComplete) await onSourceComplete(source, result);
      this.publishProgress(onProgress, done, sources.length, source, '完成');
    }
  }

  async validateSource(source: BookSource, onStage?: (stage: string) => void):
    Promise<ExploreReadingValidationResult> {
    const result = new ExploreReadingValidationResult();
    if (!source.enabledExplore || !(source.exploreUrl || '').trim()) {
      return this.finish(result, BookSource.VALIDATION_FAILED, '缺少发现地址或发现未启用');
    }
    try {
      const explore = new ExploreCoordinator();
      const entries = await explore.getEntries('', source.bookSourceUrl);
      if (this.cancelled) return this.temporary(result, '校验已取消');
      if (entries.length === 0) {
        return this.classifyFailure(result, explore.getNoticeMessage() || '没有解析出发现分类', '发现');
      }

      const candidates: ExploreBookCandidate[] = [];
      const candidateUrls = new Set<string>();
      let lastNotice = '';
      const entryLimit = Math.min(entries.length, 8);
      for (let index = 0; index < entryLimit; index++) {
        if (this.cancelled) return this.temporary(result, '校验已取消');
        const entry = entries[index];
        if (!entry.url || !entry.url.trim()) continue;
        if (onStage) onStage(`发现列表 ${index + 1}/${entryLimit}`);
        const books = await explore.explore(entry, 1, ExploreReadingValidator.EXPLORE_SAMPLE_LIMIT);
        lastNotice = explore.getNoticeMessage() || lastNotice;
        for (const book of books) {
          const key = (book.bookUrl || `${entry.url}\n${book.name}`).trim();
          if (!key || candidateUrls.has(key)) continue;
          candidateUrls.add(key);
          candidates.push(new ExploreBookCandidate(entry, book));
          if (candidates.length >= 4) break;
        }
        if (candidates.length >= 4) break;
        if (this.isAccessControlMessage(lastNotice)) break;
      }
      if (candidates.length === 0) {
        return this.classifyFailure(result, lastNotice || `前 ${entryLimit} 个发现分类均无结果`, '发现');
      }
      const persistedSource = await appDb.getBookSource(source.bookSourceUrl) || source;
      let bestResult: ExploreReadingValidationResult | null = null;
      for (let index = 0; index < candidates.length; index++) {
        if (this.cancelled) return this.temporary(result, '校验已取消');
        const candidateResult = await this.validateCandidate(persistedSource, candidates[index], index,
          candidates.length, onStage);
        if (candidateResult.validationStatus === BookSource.VALIDATION_PASSED) return candidateResult;
        if (!bestResult || candidateResult.chapterCount > bestResult.chapterCount) bestResult = candidateResult;
        if (this.pendingVerification()) return candidateResult;
      }
      const failedResult = bestResult || result;
      failedResult.reason = `${failedResult.reason}（已尝试 ${candidates.length} 本发现结果）`;
      return failedResult;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error || '未知异常');
      return this.classifyFailure(result, message, '链路');
    }
  }

  private async validateCandidate(source: BookSource, candidate: ExploreBookCandidate, candidateIndex: number,
    candidateCount: number, onStage?: (stage: string) => void): Promise<ExploreReadingValidationResult> {
    const result = new ExploreReadingValidationResult();
    result.entryTitle = candidate.entry.title;
    result.bookName = candidate.book.name;
    try {
      const book = this.toBook(candidate.book, source);
      if (onStage) onStage(`书籍详情 ${candidateIndex + 1}/${candidateCount}`);
      const service = new WebBookService();
      const fullBook = await service.getBookInfo(source, book);
      if (this.cancelled) return this.temporary(result, '校验已取消');
      result.bookName = fullBook.name || result.bookName;
      BookTypeSupport.applyBookType(fullBook, source);
      result.mediaType = BookTypeSupport.isAudio(fullBook) ? '音频' :
        (BookTypeSupport.isImage(fullBook) ? '漫画图片' : '正文');

      if (onStage) onStage(`书籍目录 ${candidateIndex + 1}/${candidateCount}`);
      const chapters = await service.getChapterList(source, fullBook,
        ExploreReadingValidator.CHAPTER_SAMPLE_LIMIT, false);
      if (this.cancelled) return this.temporary(result, '校验已取消');
      result.chapterCount = chapters.length;
      if (chapters.length === 0) {
        return this.classifyFailure(result, this.runtimeMessage('目录为空'), '目录');
      }
      const publicChapters = this.publicChapters(chapters, 3);
      if (publicChapters.length === 0) {
        return this.finish(result, BookSource.VALIDATION_NEEDS_VERIFICATION,
          `发现、详情和目录样本正常（${this.chapterSampleText(chapters.length)}），` +
          `但没有明确标记为免费/公开的可测试章节`);
      }
      let content = '';
      let contentIssue = '内容规则返回空结果';
      for (let chapterIndex = 0; chapterIndex < publicChapters.length; chapterIndex++) {
        const chapter = publicChapters[chapterIndex];
        result.chapterTitle = chapter.title;
        if (onStage) onStage(`${result.mediaType === '音频' ? '音频地址' :
          (result.mediaType === '漫画图片' ? '漫画正文' : '章节正文')} ${candidateIndex + 1}/${candidateCount}`);
        const position = chapters.indexOf(chapter);
        const nextChapter = position >= 0 ? chapters[position + 1] : undefined;
        content = await service.getContent(source, fullBook, chapter, null, null, ReaderImageRequest.DEFAULT,
          nextChapter?.url || '');
        if (this.cancelled) return this.temporary(result, '校验已取消');
        contentIssue = this.contentIssue(fullBook, content, chapter.url);
        if (!contentIssue) break;
        if (this.isAccessControlMessage(contentIssue) || this.pendingVerification()) break;
      }
      if (!BookTypeSupport.isAudio(fullBook) && this.imageCount(content) > 0 && this.readableLength(content) === 0) {
        result.mediaType = '漫画图片';
      }
      if (contentIssue) return this.classifyFailure(result, this.runtimeMessage(contentIssue), result.mediaType);

      const measure = result.mediaType === '漫画图片' ? `${this.imageCount(content)} 张图片` :
        (result.mediaType === '音频' ? '已解析播放地址' : `${this.readableLength(content)} 字符`);
      return this.finish(result, BookSource.VALIDATION_PASSED,
        `发现“${result.entryTitle}” → 《${result.bookName}》 → 目录${this.chapterSampleText(chapters.length)} → ` +
        `${result.mediaType}${measure ? `（${measure}）` : ''}`);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error || '未知异常');
      return this.classifyFailure(result, message, '链路');
    }
  }

  private toBook(searchBook: SearchBook, source: BookSource): Book {
    const book = new Book();
    book.bookUrl = searchBook.bookUrl;
    book.tocUrl = searchBook.tocUrl;
    book.origin = source.bookSourceUrl;
    book.originName = source.bookSourceName;
    book.name = searchBook.name;
    book.author = searchBook.author;
    book.kind = searchBook.kind;
    book.coverUrl = searchBook.coverUrl;
    book.intro = searchBook.intro;
    book.latestChapterTitle = searchBook.latestChapterTitle;
    book.wordCount = searchBook.wordCount;
    book.variable = searchBook.variable || '';
    book.type = searchBook.type;
    BookTypeSupport.applyBookType(book, source);
    return book;
  }

  private publicChapters(chapters: BookChapter[], limit: number): BookChapter[] {
    const result: BookChapter[] = [];
    for (const chapter of chapters) {
      if (!chapter.url || chapter.isVip || chapter.isPay) continue;
      result.push(chapter);
      if (result.length >= Math.max(1, limit)) break;
    }
    return result;
  }

  private contentIssue(book: Book, content: string, baseUrl: string): string {
    const value = String(content || '').trim();
    if (!value) return '内容规则返回空结果';
    const accessSample = value.substring(0, Math.min(value.length, 240));
    if (value.length <= 800 && this.isAccessControlMessage(accessSample)) {
      return accessSample.substring(0, Math.min(accessSample.length, 120));
    }
    if (BookTypeSupport.isAudio(book)) {
      return this.audioUrl(value, baseUrl) ? '' : '音频内容已返回，但没有解析出 HTTP(S) 播放地址';
    }
    if (BookTypeSupport.isImage(book) || (this.imageCount(value) > 0 && this.readableLength(value) === 0)) {
      return this.imageCount(value) > 0 ? '' : '漫画内容已返回，但没有解析出图片';
    }
    return this.readableLength(value) > 0 ? '' : '正文只包含空白或标记';
  }

  private imageCount(content: string): number {
    const marker = new RegExp(this.escapeRegex(ReaderImageMarker.PREFIX), 'g');
    const markerCount = (content.match(marker) || []).length;
    if (markerCount > 0) return markerCount;
    const tags = content.match(/<img\b[^>]*(?:src|data-src)\s*=/gi) || [];
    if (tags.length > 0) return tags.length;
    const urls = content.match(/(?:https?:\/\/|\/data\/storage\/)[^\s"'<>]+?\.(?:avif|gif|jpe?g|png|webp)(?:[?#][^\s"'<>]*)?/gi) || [];
    return urls.length;
  }

  private audioUrl(content: string, baseUrl: string): string {
    const decoded = content.replace(/\\\//g, '/').replace(/&amp;/gi, '&');
    const media = decoded.match(/https?:\/\/[^\s"'<>]+?\.(?:aac|flac|m3u8|m4a|mp3|mp4|ogg|opus|wav)(?:\?[^\s"'<>]*)?/i);
    if (media) return media[0];
    const absolute = decoded.match(/https?:\/\/[^\s"'<>]+/i);
    if (absolute) return absolute[0];
    const tagged = decoded.match(/<(?:audio|source)\b[^>]*(?:src|data-src|data-url)\s*=\s*["']([^"']+)/i);
    if (tagged && tagged[1]) {
      if (/^https?:\/\//i.test(tagged[1])) return tagged[1];
      if (/^https?:\/\//i.test(baseUrl) && tagged[1].startsWith('/')) {
        const origin = baseUrl.match(/^(https?:\/\/[^/]+)/i);
        return origin ? `${origin[1]}${tagged[1]}` : '';
      }
    }
    return /^https?:\/\/\S+$/i.test(decoded) ? decoded : '';
  }

  private readableLength(content: string): number {
    return content.replace(new RegExp(`${this.escapeRegex(ReaderImageMarker.PREFIX)}[^\\]]+\\]\\]`, 'g'), '')
      .replace(/<[^>]+>/g, '').replace(/&(?:nbsp|ensp|emsp|zwnj|zwj);/gi, '')
      .replace(/\s+/g, '').length;
  }

  private chapterSampleText(count: number): string {
    return count >= ExploreReadingValidator.CHAPTER_SAMPLE_LIMIT ? `至少 ${count} 章（抽样）` : `${count} 章`;
  }

  private classifyFailure(result: ExploreReadingValidationResult, rawReason: string, stage: string):
    ExploreReadingValidationResult {
    const reason = String(rawReason || `${stage}失败`).trim();
    if (this.isAccessControlMessage(reason) || this.pendingVerification()) {
      return this.finish(result, BookSource.VALIDATION_NEEDS_VERIFICATION, `${stage}需要登录、验证或授权：${reason}`);
    }
    if (/HTTP\s*(?:408|425|429|5\d\d)|超时|timeout|网络|socket|connection|temporar|服务器返回空|接口返回空|Internal error|2300\d+/i.test(reason)) {
      return this.finish(result, BookSource.VALIDATION_TEMPORARY_ERROR, `${stage}暂时异常：${reason}`);
    }
    if (/无结果|没有解析出发现分类|分类均无结果|当前分类暂无结果|未搜索到|暂无内容/i.test(reason)) {
      return this.finish(result, BookSource.VALIDATION_NO_RESULTS, `${stage}无结果：${reason}`);
    }
    return this.finish(result, BookSource.VALIDATION_FAILED, `${stage}失败：${reason}`);
  }

  private pendingVerification(): boolean {
    return !!(AppStorage.get<string>('pendingVerificationUrl') || '').trim();
  }

  private isAccessControlMessage(value: string): boolean {
    return /需要验证|网页验证|验证码|请先登[录陆]|需要登[录陆]|未登[录陆]|重新登[录陆]|登录信息|无权限|未授权|访问受限|访问被拒绝|拒绝访问|付费|VIP|令牌|token|设备数已达上限|访问次数已达上限/i.test(value || '');
  }

  private runtimeMessage(fallback: string): string {
    const verification = AppStorage.get<string>('pendingVerificationTitle') || '';
    if (this.pendingVerification()) return verification || '需要网页验证';
    return AppStorage.get<string>('bookSourceStageLastError') || fallback;
  }

  private temporary(result: ExploreReadingValidationResult, reason: string): ExploreReadingValidationResult {
    return this.finish(result, BookSource.VALIDATION_TEMPORARY_ERROR, reason);
  }

  private finish(result: ExploreReadingValidationResult, status: number, reason: string):
    ExploreReadingValidationResult {
    result.validationStatus = status;
    result.reason = reason;
    return result;
  }

  private publishProgress(callback: ((progress: ExploreReadingValidationProgress) => void) | undefined,
    done: number, total: number, source: BookSource, stage: string): void {
    if (!callback) return;
    const progress = new ExploreReadingValidationProgress();
    progress.done = done;
    progress.total = total;
    progress.sourceName = source.bookSourceName || source.bookSourceUrl;
    progress.stage = stage;
    callback(progress);
  }

  private escapeRegex(value: string): string {
    return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }
}
