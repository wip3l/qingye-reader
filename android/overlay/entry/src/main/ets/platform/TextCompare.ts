// platform/TextCompare.ts 的安卓实现。
// ArkUI-X 安卓版的 ICU 不认部分区域标记（实测 'zh-Hans-CN-u-co-pinyin' 会抛 RangeError: invalid locale），
// 依次退到去掉扩展的标记、'zh'、默认区域，都不行就按码位比较。每个标记（连同选项）只试一次。
type Comparer = (a: string, b: string) => number;

const comparers: Map<string, Comparer> = new Map<string, Comparer>();

function resolve(locale: string, options?: Intl.CollatorOptions): Comparer {
  const candidates: string[] = [locale, locale.replace(/-u-.*$/, ''), 'zh'];
  for (const candidate of candidates) {
    try {
      '甲'.localeCompare('乙', candidate, options);
      return (a: string, b: string): number => a.localeCompare(b, candidate, options);
    } catch (_) {
      // 换下一个
    }
  }
  try {
    '甲'.localeCompare('乙');
    return (a: string, b: string): number => a.localeCompare(b);
  } catch (_) {
    return (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0);
  }
}

export function compareText(a: string, b: string, locale: string, options?: Intl.CollatorOptions): number {
  const key = options ? `${locale}|${JSON.stringify(options)}` : locale;
  let comparer = comparers.get(key);
  if (!comparer) {
    comparer = resolve(locale, options);
    comparers.set(key, comparer);
  }
  return comparer(a, b);
}
