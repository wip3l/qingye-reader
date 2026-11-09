import { EpubHtmlConverter } from './EpubHtmlConverter';

/** 从书的 OPF 里读出的多看扩展。路径都相对解压目录。 */
export class EpubDuokanPackage {
  /** spine 里 properties 含 duokan-page-fullscreen 的文件：整页铺满屏幕，不留页边距、不显示页眉页脚。 */
  fullscreen: string[] = [];
  /** 多看的“~slim”图：x.jpg 旁边的 x~slim.jpg 是给瘦长屏幕用的版本。两个数组下标一一对应。 */
  slimFrom: string[] = [];
  slimTo: string[] = [];
}

/**
 * 多看阅读的私有扩展，文件排版按多看的效果还原：
 * - OPF spine 的 duokan-page-fullscreen 全屏页与“~slim”瘦长屏图（parsePackage）；
 * - 样式里的多看内置字体名 DK-SONGTI 等换成系统里对应的字体（其它阅读器认不出这些名字，会一路落到无衬线体）；
 * - 样式属性 duokan-bleed（出血：元素越过页边距铺到屏幕边）。浏览器解析样式时会丢掉不认识的属性，
 *   脚本读不到，所以在交给网页之前改写成自定义属性 --legado-bleed，由脚本按它把元素撑到页边。
 * 本模块不依赖系统 API，Node 回归脚本直接测这一份实现。
 */
export class EpubDuokanExtensions {
  static readonly FULLSCREEN_PROPERTY: string = 'duokan-page-fullscreen';
  static readonly BLEED_PROPERTY: string = '--legado-bleed';
  /** 屏幕高宽比至少这么大才换用“~slim”图。 */
  static readonly SLIM_MIN_RATIO: number = 1.7;
  // 系统字体：衬线（宋、明体）与无衬线（黑体）。系统里没有楷体、仿宋，退而用衬线体，比落到黑体更接近原意。
  private static readonly SERIF_FAMILIES: string[] = ['Noto Serif CJK SC', 'Noto Serif SC', 'Source Han Serif SC'];
  private static readonly SANS_FAMILIES: string[] = ['HarmonyOS Sans SC', 'Noto Sans CJK SC', 'Noto Sans SC'];

  /** META-INF/container.xml 里 OPF 的路径（相对解压目录）；找不到返回空串。 */
  static opfPath(containerXml: string): string {
    const match = /<rootfile\b[^>]*\bfull-path\s*=\s*(["'])([^"']+)\1/i.exec(containerXml || '');
    return match ? EpubDuokanExtensions.cleanPath(EpubHtmlConverter.resolvePath('', match[2])) : '';
  }

  static parsePackage(opf: string, opfPath: string): EpubDuokanPackage {
    const result = new EpubDuokanPackage();
    const source = opf || '';
    const slash = opfPath.lastIndexOf('/');
    const opfDir = slash >= 0 ? opfPath.substring(0, slash) : '';
    const hrefById = new Map<string, string>();
    const paths = new Set<string>();
    const itemPattern = /<(?:\w+:)?item\b[^>]*>/gi;
    let item = itemPattern.exec(source);
    while (item) {
      const id = EpubDuokanExtensions.attribute(item[0], 'id');
      const href = EpubDuokanExtensions.attribute(item[0], 'href');
      if (href) {
        const path = EpubDuokanExtensions.cleanPath(EpubHtmlConverter.resolvePath(opfDir, href));
        if (id) hrefById.set(id, path);
        if (path) paths.add(path);
      }
      item = itemPattern.exec(source);
    }
    const refPattern = /<(?:\w+:)?itemref\b[^>]*>/gi;
    let ref = refPattern.exec(source);
    while (ref) {
      const properties = EpubDuokanExtensions.attribute(ref[0], 'properties').toLowerCase().split(/\s+/);
      const path = hrefById.get(EpubDuokanExtensions.attribute(ref[0], 'idref')) || '';
      if (path && properties.includes(EpubDuokanExtensions.FULLSCREEN_PROPERTY) && !result.fullscreen.includes(path)) {
        result.fullscreen.push(path);
      }
      ref = refPattern.exec(source);
    }
    for (const path of Array.from(paths)) {
      const slim = /^(.*)~slim(\.[A-Za-z0-9]+)$/.exec(path);
      if (!slim) continue;
      const original = `${slim[1]}${slim[2]}`;
      if (!paths.has(original)) continue;
      result.slimFrom.push(original);
      result.slimTo.push(path);
    }
    return result;
  }

  /** 多看内置字体名对应的系统字体；不认识的名字返回空数组（原样保留）。 */
  static systemFamilies(name: string): string[] {
    const key = (name || '').toUpperCase();
    if (!key.startsWith('DK-')) return [];
    if (key.includes('HEI')) return EpubDuokanExtensions.SANS_FAMILIES;
    if (/SONG|KAI|FANG|MING|BIAO|SERIF/.test(key)) return EpubDuokanExtensions.SERIF_FAMILIES;
    return [];
  }

  /** 改写一段样式（样式表、<style> 内容或 style 属性值）：多看字体名与出血属性。 */
  static rewriteCss(css: string): string {
    const source = css || '';
    if (!/DK-|duokan-bleed/i.test(source)) return source;
    // 书自己用 @font-face 定义了同名字体（自带字体文件）就不换，免得把书的字体顶掉。
    const ownFaces = new Set<string>();
    const facePattern = /@font-face\s*\{[^}]*?font-family\s*:\s*(["']?)\s*([^;"'}]+?)\s*\1\s*[;}]/gi;
    let face = facePattern.exec(source);
    while (face) {
      ownFaces.add(face[2].trim().toUpperCase());
      face = facePattern.exec(source);
    }
    const familiesOf = (name: string): string[] =>
      ownFaces.has(name.toUpperCase()) ? [] : EpubDuokanExtensions.systemFamilies(name);
    let result = source.replace(/local\(\s*(["']?)\s*(DK-[A-Za-z0-9-]+)\s*\1\s*\)/gi,
      (all: string, _quote: string, name: string): string => {
        const families = familiesOf(name);
        return families.length ? families.map((family: string): string => `local("${family}")`).join(',') : all;
      });
    result = result.replace(/(^|[^\w/.-])(["']?)(DK-[A-Za-z0-9-]+)\2(?![\w-])/g,
      (all: string, lead: string, _quote: string, name: string): string => {
        const families = familiesOf(name);
        return families.length ? `${lead}${families.map((family: string): string => `"${family}"`).join(',')}` : all;
      });
    return result.replace(/(^|[;{\s])duokan-bleed(\s*:)/gi, `$1${EpubDuokanExtensions.BLEED_PROPERTY}$2`);
  }

  private static attribute(tag: string, name: string): string {
    const match = new RegExp(`\\s${name}\\s*=\\s*(["'])([^"']*)\\1`, 'i').exec(tag);
    return match ? EpubHtmlConverter.decodeEntities(match[2]).trim() : '';
  }

  private static cleanPath(path: string): string {
    return (path || '').replace(/^\/+/, '');
  }
}
