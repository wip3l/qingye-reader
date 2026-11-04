import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { Book } from '@legado/sourceengine';
import { LocalBookService } from '../core/book/LocalBookService';
import { QYBOOK_EXTENSION, QYBOOK_UTD, ReadingContinuation } from './ReadingContinuation';

/** 碰一碰时现取要发出去的内容；返回 null 表示当前没有可分享的东西。 */
export type KnockShareProvider = () => Promise<systemShare.SharedData | null>;

class KnockShareEntry {
  ownerId: string = '';
  provider: KnockShareProvider;

  constructor(ownerId: string, provider: KnockShareProvider) {
    this.ownerId = ownerId;
    this.provider = provider;
  }
}

/**
 * 华为分享“碰一碰”的进程级入口：系统只认一个监听，页面在 onPageShow 时 attach、onPageHide 时 detach，
 * 碰一碰时交给最后显示的页面出数据。没有页面挂着时注销监听，碰一碰就走系统默认行为。
 */
export class KnockShare {
  private static entries: KnockShareEntry[] = [];
  private static listening: boolean = false;
  private static readonly listener = (target: harmonyShare.SharableTarget): void => {
    KnockShare.handle(target);
  };

  static attach(ownerId: string, provider: KnockShareProvider): void {
    if (!ownerId) return;
    KnockShare.entries = KnockShare.entries.filter((entry: KnockShareEntry): boolean => entry.ownerId !== ownerId);
    KnockShare.entries.push(new KnockShareEntry(ownerId, provider));
    KnockShare.syncListener();
  }

  static attachBook(ownerId: string, context: common.Context, book: () => Book | null): void {
    KnockShare.attach(ownerId, (): Promise<systemShare.SharedData | null> => KnockShare.bookData(context, book()));
  }

  static attachFile(ownerId: string, path: () => string, title: string): void {
    KnockShare.attach(ownerId, (): Promise<systemShare.SharedData | null> =>
      Promise.resolve(KnockShare.fileData(path(), title)));
  }

  static detach(ownerId: string): void {
    if (!ownerId) return;
    KnockShare.entries = KnockShare.entries.filter((entry: KnockShareEntry): boolean => entry.ownerId !== ownerId);
    KnockShare.syncListener();
  }

  /**
   * 本地书发源文件，在线书发 .qybook（书籍信息和进度），接收方都能用“打开方式”交给本应用。
   * 在线书只发文字的话，电脑等设备上没有能打开纯文本卡片的应用，会提示“暂无可用打开方式”。
   */
  static async bookData(context: common.Context, book: Book | null): Promise<systemShare.SharedData | null> {
    if (!book || !book.name) return null;
    if (LocalBookService.isPhysicalLocalBook(book)) {
      const file = await KnockShare.localBookFile(context, book);
      if (file) return file;
    }
    if (LocalBookService.isLocalBook(book)) return null;
    const bookFile = await KnockShare.onlineBookFile(context, book);
    if (bookFile) return bookFile;
    const lines: string[] = [book.author ? `《${book.name}》 ${book.author}` : `《${book.name}》`];
    if (book.originName) lines.push(`来源：${book.originName}`);
    if (/^https?:\/\//i.test(book.bookUrl)) lines.push(book.bookUrl);
    const intro = (book.intro || '').replace(/\s+/g, ' ').trim();
    return new systemShare.SharedData({
      utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
      content: lines.join('\n'),
      title: book.name,
      description: intro.length > 60 ? `${intro.substring(0, 60)}…` : intro
    });
  }

  static fileData(path: string, title: string, fallbackUtd: string = 'general.file'): systemShare.SharedData | null {
    if (!KnockShare.exists(path)) return null;
    const dot = path.lastIndexOf('.');
    let utd = fallbackUtd;
    if (dot > path.lastIndexOf('/')) {
      try {
        utd = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(path.substring(dot), fallbackUtd);
      } catch (_) {
      }
    }
    return new systemShare.SharedData({ utd: utd, uri: fileUri.getUriFromPath(path), title: title });
  }

  private static async localBookFile(context: common.Context, book: Book): Promise<systemShare.SharedData | null> {
    const localPath = book.getVariable('localFilePath') || '';
    if (!KnockShare.exists(localPath)) return null;
    const format = (book.getVariable('localFormat') || 'txt').toLowerCase();
    const author = book.author ? ` - ${book.author}` : '';
    const fileName = `${LocalBookService.sanitizeFileName(book.name + author)}.${format}`;
    // 接收方看到的就是这个文件名；书库里的源文件名不可读，复制一份到缓存里再发。
    // 碰一碰回调在主线程，几百 MB 的 EPUB/PDF 必须异步复制，同步复制会卡到被系统判无响应。
    try {
      const sharePath = `${await KnockShare.freshDir(context)}/${fileName}`;
      await fileIo.copyFile(localPath, sharePath);
      return KnockShare.fileData(sharePath, book.name);
    } catch (error) {
      console.warn('[KnockShare] copy local book failed:', error);
      return KnockShare.fileData(localPath, book.name);
    }
  }

  private static async onlineBookFile(context: common.Context, book: Book): Promise<systemShare.SharedData | null> {
    const raw = ReadingContinuation.payloadFor(book);
    if (!raw) return null;
    const author = book.author ? ` - ${book.author}` : '';
    try {
      const sharePath =
        `${await KnockShare.freshDir(context)}/${LocalBookService.sanitizeFileName(book.name + author)}${QYBOOK_EXTENSION}`;
      const file = fileIo.openSync(sharePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, raw);
      } finally {
        fileIo.closeSync(file);
      }
      return new systemShare.SharedData({ utd: QYBOOK_UTD, uri: fileUri.getUriFromPath(sharePath), title: book.name });
    } catch (error) {
      console.warn('[KnockShare] write book file failed:', error);
      return null;
    }
  }

  /** 每次分享前清空，缓存里只留最近发出的一个文件。 */
  private static async freshDir(context: common.Context): Promise<string> {
    const dir = `${context.cacheDir}/knock-share`;
    if (KnockShare.exists(dir)) await fileIo.rmdir(dir);
    await fileIo.mkdir(dir);
    return dir;
  }

  private static exists(path: string): boolean {
    if (!path) return false;
    try {
      return fileIo.accessSync(path);
    } catch (_) {
      return false;
    }
  }

  private static syncListener(): void {
    const wanted = KnockShare.entries.length > 0;
    if (wanted === KnockShare.listening) return;
    if (!canIUse('SystemCapability.Collaboration.HarmonyShare')) return;
    try {
      if (wanted) harmonyShare.on('knockShare', KnockShare.listener);
      else harmonyShare.off('knockShare', KnockShare.listener);
      KnockShare.listening = wanted;
    } catch (error) {
      console.warn('[KnockShare] listener change failed:', error);
    }
  }

  private static async handle(target: harmonyShare.SharableTarget): Promise<void> {
    const entry = KnockShare.entries.length > 0 ? KnockShare.entries[KnockShare.entries.length - 1] : null;
    let data: systemShare.SharedData | null = null;
    try {
      data = entry ? await entry.provider() : null;
    } catch (error) {
      console.warn('[KnockShare] provider failed:', error);
    }
    try {
      if (data) await target.share(data);
      else await target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR);
    } catch (error) {
      console.warn('[KnockShare] share failed:', error);
    }
  }
}
