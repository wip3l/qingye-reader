import { EpubHtmlConverter } from './EpubHtmlConverter';

/** OPF 里一页的固定版式声明。side：'left' / 'right' / 'center'，书没指定时为空串。 */
export class EpubFixedItem {
  fixed: boolean = false;
  side: string = '';
}

/**
 * 固定版式（pre-paginated）的声明：整本的默认值、每个 spine 文件自己的覆盖、翻页方向与对开方式。
 * 路径都是相对解压目录的。
 */
export class EpubFixedPackage {
  /** 至少有一个 spine 文件是固定版式。 */
  fixed: boolean = false;
  /** page-progression-direction 为 rtl：从右往左翻。 */
  rtl: boolean = false;
  /** rendition:spread 为 none：任何屏幕都不拼对开。 */
  noSpread: boolean = false;
  /** EPUB 3.0 的 rendition:viewport（整本统一的页面大小），没有为 0。 */
  width: number = 0;
  height: number = 0;
  items: Map<string, EpubFixedItem> = new Map<string, EpubFixedItem>();
  /** spine 里第一个固定版式文件：它单独成页（封面），不和后面的拼对开。 */
  firstPath: string = '';

  isFixed(path: string): boolean {
    const item = this.items.get(path);
    return !!item && item.fixed;
  }

  sideOf(path: string): string {
    const item = this.items.get(path);
    return item ? item.side : '';
  }
}

/** 一屏显示什么：left / right 是对开时左右两边的页（-1 为空），center 是单独居中的一页（-1 为没有）。 */
export class EpubFixedView {
  left: number = -1;
  right: number = -1;
  center: number = -1;

  static single(index: number): EpubFixedView {
    const view = new EpubFixedView();
    view.center = index;
    return view;
  }
}

/**
 * 固定版式 EPUB（绘本、杂志、画册）：每个 spine 文件是一页，文字和图片按书里写死的位置排，
 * 阅读时整页等比缩放进屏幕，不重新分页。本模块只做解析与排页，不依赖系统 API，Node 回归脚本直接测。
 */
export class EpubFixedLayout {
  /** 读 OPF：整本的 rendition:layout / spread / viewport、spine 的翻页方向与每页的 properties。 */
  static parsePackage(opf: string, opfPath: string): EpubFixedPackage {
    const result = new EpubFixedPackage();
    const source = opf || '';
    const opfDir = EpubFixedLayout.directoryOf(opfPath);
    const bookFixed = EpubFixedLayout.metaProperty(source, 'rendition:layout') === 'pre-paginated';
    result.noSpread = EpubFixedLayout.metaProperty(source, 'rendition:spread') === 'none';
    const viewport = EpubFixedLayout.sizeOf(EpubFixedLayout.metaProperty(source, 'rendition:viewport'));
    result.width = viewport[0];
    result.height = viewport[1];
    const spine = /<(?:\w+:)?spine\b([^>]*)>/i.exec(source);
    result.rtl = !!spine && /page-progression-direction\s*=\s*["']rtl["']/i.test(spine[1]);

    const manifest = new Map<string, string>();
    const itemPattern = /<(?:\w+:)?item\b[^>]*>/gi;
    let item = itemPattern.exec(source);
    while (item) {
      const id = EpubFixedLayout.attribute(item[0], 'id');
      const href = EpubFixedLayout.attribute(item[0], 'href');
      if (id && href) manifest.set(id, href);
      item = itemPattern.exec(source);
    }
    const refPattern = /<(?:\w+:)?itemref\b[^>]*>/gi;
    let ref = refPattern.exec(source);
    while (ref) {
      const href = manifest.get(EpubFixedLayout.attribute(ref[0], 'idref'));
      if (href) {
        const path = EpubFixedLayout.resolve(opfDir, href);
        const properties = EpubFixedLayout.attribute(ref[0], 'properties').toLowerCase().split(/\s+/);
        const entry = new EpubFixedItem();
        entry.fixed = properties.includes('rendition:layout-pre-paginated') ||
          (bookFixed && !properties.includes('rendition:layout-reflowable'));
        for (const property of properties) {
          const side = /^(?:rendition:)?page-spread-(left|right|center)$/.exec(property);
          if (side) entry.side = side[1];
        }
        if (path && !result.items.has(path)) {
          result.items.set(path, entry);
          if (entry.fixed && !result.firstPath) result.firstPath = path;
        }
        if (entry.fixed) result.fixed = true;
      }
      ref = refPattern.exec(source);
    }
    return result;
  }

  /**
   * 一页的大小（CSS 像素）：页面里 viewport 声明的 width/height；没有时取最外层 svg 的 viewBox 或宽高；
   * 都没有返回 [0, 0]，由脚本按屏幕比例排。
   */
  static pageSize(html: string): number[] {
    const source = html || '';
    const metaPattern = /<meta\b[^>]*>/gi;
    let meta = metaPattern.exec(source);
    while (meta) {
      if (EpubFixedLayout.attribute(meta[0], 'name').toLowerCase() === 'viewport') {
        const size = EpubFixedLayout.sizeOf(EpubFixedLayout.attribute(meta[0], 'content'));
        if (size[0] > 0 && size[1] > 0) return size;
      }
      meta = metaPattern.exec(source);
    }
    const body = EpubHtmlConverter.bodyOf(source);
    const svg = /^\s*(?:<div\b[^>]*>\s*)?<svg\b[^>]*>/i.exec(body);
    if (svg) {
      const box = EpubFixedLayout.attribute(svg[0], 'viewBox').trim().split(/[\s,]+/).map(Number);
      if (box.length === 4 && box[2] > 0 && box[3] > 0) return [box[2], box[3]];
      const width = parseFloat(EpubFixedLayout.attribute(svg[0], 'width'));
      const height = parseFloat(EpubFixedLayout.attribute(svg[0], 'height'));
      if (width > 0 && height > 0 && !/%/.test(svg[0])) return [width, height];
    }
    return [0, 0];
  }

  /** 单页显示：一页一屏。 */
  static singleViews(count: number): EpubFixedView[] {
    const views: EpubFixedView[] = [];
    for (let index = 0; index < count; index++) views.push(EpubFixedView.single(index));
    return views;
  }

  /**
   * 对开显示：按书里的 page-spread 拼成左右两页。sides 是各页声明的 left / right / center（没声明为空串），
   * cover 为真时第一页单独一屏（落在第二个位置上，和纸书封面一样）。
   * 从右往左翻的书（rtl）先放右页再放左页，屏幕上仍是左边 left、右边 right。
   */
  static spreadViews(sides: string[], rtl: boolean, cover: boolean): EpubFixedView[] {
    const views: EpubFixedView[] = [];
    // 一屏里先读的那一边、后读的那一边。
    const firstSide = rtl ? 'right' : 'left';
    const secondSide = rtl ? 'left' : 'right';
    let open: EpubFixedView | null = null;
    const place = (view: EpubFixedView, side: string, index: number): void => {
      if (side === 'left') view.left = index;
      else view.right = index;
    };
    const flush = (): void => {
      if (open) views.push(open);
      open = null;
    };
    for (let index = 0; index < sides.length; index++) {
      let side = sides[index];
      if (!side) side = index === 0 && cover ? secondSide : (open ? secondSide : firstSide);
      if (side === 'center') {
        flush();
        views.push(EpubFixedView.single(index));
        continue;
      }
      if (side === firstSide) {
        flush();
        open = new EpubFixedView();
        place(open, side, index);
        continue;
      }
      if (open) {
        place(open, side, index);
        flush();
      } else {
        const view = new EpubFixedView();
        place(view, side, index);
        views.push(view);
      }
    }
    flush();
    return views;
  }

  /** 第 page 页落在哪一屏；找不到返回 0。 */
  static viewOf(views: EpubFixedView[], page: number): number {
    for (let index = 0; index < views.length; index++) {
      const view = views[index];
      if (view.left === page || view.right === page || view.center === page) return index;
    }
    return 0;
  }

  /** "width=1200, height=1600" → [1200, 1600]；不是数字（如 device-width）时为 0。 */
  private static sizeOf(value: string): number[] {
    const width = /(?:^|[\s,;])width\s*=\s*([\d.]+)/i.exec(value || '');
    const height = /(?:^|[\s,;])height\s*=\s*([\d.]+)/i.exec(value || '');
    const w = width ? parseFloat(width[1]) : 0;
    const h = height ? parseFloat(height[1]) : 0;
    return [Number.isFinite(w) && w > 0 ? w : 0, Number.isFinite(h) && h > 0 ? h : 0];
  }

  private static metaProperty(opf: string, property: string): string {
    const pattern = /<(?:\w+:)?meta\b([^>]*)>([^<]*)/gi;
    let match = pattern.exec(opf);
    while (match) {
      const tag = `<meta ${match[1]}>`;
      if (EpubFixedLayout.attribute(tag, 'property') === property) return (match[2] || '').trim().toLowerCase();
      // EPUB 2 写法：<meta name="rendition:layout" content="pre-paginated"/>
      if (EpubFixedLayout.attribute(tag, 'name') === property) {
        return EpubFixedLayout.attribute(tag, 'content').trim().toLowerCase();
      }
      match = pattern.exec(opf);
    }
    return '';
  }

  private static attribute(tag: string, name: string): string {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const match = new RegExp(`\\s${escaped}\\s*=\\s*(?:"([^"]*)"|'([^']*)')`, 'i').exec(tag || '');
    return match ? EpubHtmlConverter.decodeEntities(match[1] ?? match[2] ?? '') : '';
  }

  private static directoryOf(path: string): string {
    const normalized = EpubHtmlConverter.normalizePath(path || '');
    const slash = normalized.lastIndexOf('/');
    return slash > 0 ? normalized.substring(0, slash) : '';
  }

  /** OPF 里的 href（相对 OPF 所在目录）→ 相对解压目录的路径。 */
  private static resolve(opfDir: string, href: string): string {
    let clean = EpubHtmlConverter.withoutFragment(href || '');
    try {
      clean = decodeURIComponent(clean);
    } catch (_) {
    }
    return EpubHtmlConverter.normalizePath(opfDir ? `${opfDir}/${clean}` : clean).replace(/^\/+/, '');
  }
}
