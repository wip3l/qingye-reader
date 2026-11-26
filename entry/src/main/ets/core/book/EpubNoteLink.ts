/** EPUB 正文里一个注释链接指向的位置：相对解压目录的文件路径与锚点。 */
export class EpubNoteTarget {
  path: string = '';
  fragment: string = '';
}

/**
 * EPUB 注释链接的动作地址。正文里的注释编号以书源动作标记（ReaderActionMarker）保存，地址用这个前缀，
 * 阅读器据此把它画成注释而不是段评气泡，点击时到解压目录里读出注释正文。
 * 路径存相对解压目录的形式：解压目录换位置后标记仍然有效，也让标记短一些。
 */
export class EpubNoteLink {
  static readonly SCHEME: string = 'legado-epub-note:';
  /**
   * 指向书里其他位置的普通链接（其他章节、书里自带的目录页）：点了跳过去。与引擎里
   * ReaderActionMarker.TEXT_LINK_SCHEME 相同，去标记时链接文字留在正文里。锚点可以为空（指向文件开头）。
   */
  static readonly LINK_SCHEME: string = 'legado-epub-link:';
  /** 只有图标、没有文字的注释（常见于把注释图标放进链接的书）统一显示成这个字。 */
  static readonly ICON_LABEL: string = '注';

  static create(path: string, fragment: string): string {
    const file = (path || '').trim();
    const anchor = (fragment || '').trim();
    if (!file || !anchor) return '';
    return `${EpubNoteLink.SCHEME}${encodeURIComponent(file)}#${encodeURIComponent(anchor)}`;
  }

  /** 注释正文拆成弹窗里一段一段显示的块（文字段落或图片标记）。 */
  static blocks(content: string, maxBlocks: number = 80): string[] {
    return (content || '').split(/\n+/)
      .map((line: string): string => line.trim())
      .filter((line: string): boolean => line.length > 0)
      .slice(0, maxBlocks);
  }

  static createLink(path: string, fragment: string): string {
    const file = (path || '').trim();
    if (!file) return '';
    return `${EpubNoteLink.LINK_SCHEME}${encodeURIComponent(file)}#${encodeURIComponent((fragment || '').trim())}`;
  }

  static isLink(url: string): boolean {
    return (url || '').startsWith(EpubNoteLink.LINK_SCHEME);
  }

  /** 书内链接的目标；fragment 为空表示文件开头。 */
  static parseLink(url: string): EpubNoteTarget | null {
    const value = url || '';
    if (!value.startsWith(EpubNoteLink.LINK_SCHEME)) return null;
    const payload = value.substring(EpubNoteLink.LINK_SCHEME.length);
    const hash = payload.indexOf('#');
    const target = new EpubNoteTarget();
    try {
      target.path = decodeURIComponent(hash >= 0 ? payload.substring(0, hash) : payload);
      target.fragment = hash >= 0 ? decodeURIComponent(payload.substring(hash + 1)) : '';
    } catch (_) {
      return null;
    }
    return target.path ? target : null;
  }

  static isNote(url: string): boolean {
    return (url || '').startsWith(EpubNoteLink.SCHEME);
  }

  static parse(url: string): EpubNoteTarget | null {
    const value = url || '';
    if (!value.startsWith(EpubNoteLink.SCHEME)) return null;
    const payload = value.substring(EpubNoteLink.SCHEME.length);
    const hash = payload.indexOf('#');
    if (hash <= 0 || hash >= payload.length - 1) return null;
    const target = new EpubNoteTarget();
    try {
      target.path = decodeURIComponent(payload.substring(0, hash));
      target.fragment = decodeURIComponent(payload.substring(hash + 1));
    } catch (_) {
      return null;
    }
    return target.path && target.fragment ? target : null;
  }
}
