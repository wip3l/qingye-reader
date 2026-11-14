// platform/TextCompare.ts 的安卓实现。
// ArkUI-X 安卓版的 ICU 不认部分区域标记（实测 'zh-Hans-CN-u-co-pinyin' 会抛 RangeError: invalid locale），
// 依次退到去掉扩展的标记、'zh'、默认区域，都不行就按码位比较。每个标记只试一次。
type Comparer = (a: string, b: string) => number;

const comparers: Map<string, Comparer> = new Map<string, Comparer>();

function resolve(locale: string): Comparer {
  const candidates: string[] = [locale, locale.replace(/-u-.*$/, ''), 'zh'];
  for (const candidate of candidates) {
    try {
      '甲'.localeCompare('乙', candidate);
      return (a: string, b: string): number => a.localeCompare(b, candidate);
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

export function compareText(a: string, b: string, locale: string): number {
  let comparer = comparers.get(locale);
  if (!comparer) {
    comparer = resolve(locale);
    comparers.set(locale, comparer);
  }
  return comparer(a, b);
}
