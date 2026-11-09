/**
 * 文件排版的“字体”设置：按书存在书籍变量里，换的只是字形，字号、行距等仍按书的样式。
 *
 * 取值：空串 = 书本字体（不替换）；'1' = 跟随应用排版的阅读字体（早先的开关也存成 '1'）；
 * 'sans' / 'serif' = 系统黑体 / 系统宋体；'file:<文件名>' = 已上传的某款字体。
 * 范围：空串 = 只换正文（保留标题、代码和书里单独设了字体的文字）；'all' = 全部文字。
 */
export class EpubOriginalFont {
  static readonly NONE: string = '';
  static readonly READER: string = '1';
  static readonly SANS: string = 'sans';
  static readonly SERIF: string = 'serif';
  static readonly FILE_PREFIX: string = 'file:';
  static readonly SCOPE_BODY: string = '';
  static readonly SCOPE_ALL: string = 'all';

  /**
   * 系统宋体：网页组件按名字找不到任何中文衬线字体（实测“书宋-简”“Noto Serif CJK SC/JP”都找不到，
   * 通用名 serif 只给出西文的 Noto Serif，汉字照样落到黑体），所以直接把系统里的书宋字体文件
   * 经虚拟站点交给网页（SYSTEM_SERIF_FILES 依次找第一个在的）。都没有时才退到这组名字。
   */
  static readonly SERIF_STACK: string = 'serif';
  static readonly SANS_STACK: string = 'sans-serif';
  static readonly SYSTEM_SERIF_FILES: string[] = ['/system/fonts/ShuS-SC.ttf', '/system/fonts/FZShuS-SC.ttf'];
  /** 系统宋体在虚拟站点里的文件名，与上传字体的文件名（reader_font_* / cloud_*）不会撞。 */
  static readonly SYSTEM_SERIF_NAME: string = 'legado_system_serif.ttf';

  static normalize(value: string): string {
    const raw = (value || '').trim();
    if (raw === EpubOriginalFont.READER || raw === EpubOriginalFont.SANS || raw === EpubOriginalFont.SERIF) return raw;
    if (raw.startsWith(EpubOriginalFont.FILE_PREFIX) && raw.length > EpubOriginalFont.FILE_PREFIX.length) return raw;
    return EpubOriginalFont.NONE;
  }

  static normalizeScope(value: string): string {
    return (value || '').trim() === EpubOriginalFont.SCOPE_ALL ? EpubOriginalFont.SCOPE_ALL : EpubOriginalFont.SCOPE_BODY;
  }

  static fileChoice(fileName: string): string {
    return `${EpubOriginalFont.FILE_PREFIX}${fileName}`;
  }

  /** 'file:<文件名>' 里的文件名；不是这种取值时为空串。 */
  static fileNameOf(choice: string): string {
    return choice.startsWith(EpubOriginalFont.FILE_PREFIX) ? choice.substring(EpubOriginalFont.FILE_PREFIX.length) : '';
  }

  static fileNameOfPath(path: string): string {
    const normalized = (path || '').replace(/\\/g, '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  /**
   * 网页样式里的字体族：readerFont 是 'sans' / 'serif'（旧值 'system' 同 'sans'），或字体文件在虚拟站点里的地址
   * （由 @font-face 以 LegadoReaderFont 提供，缺字时退到系统黑体）。
   */
  static cssFamily(readerFont: string): string {
    if (readerFont === EpubOriginalFont.SERIF) return EpubOriginalFont.SERIF_STACK;
    if (readerFont === EpubOriginalFont.SANS || readerFont === 'system') return EpubOriginalFont.SANS_STACK;
    return `"LegadoReaderFont",${EpubOriginalFont.SANS_STACK}`;
  }

  static isFileFont(readerFont: string): boolean {
    return !!readerFont && readerFont !== EpubOriginalFont.SERIF && readerFont !== EpubOriginalFont.SANS &&
      readerFont !== 'system';
  }
}
