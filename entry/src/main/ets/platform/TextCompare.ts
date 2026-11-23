// 按语言规则比较文本（排序用）。安卓构建会用 android/overlay 里的同名文件替换本文件。
// 安卓上 ArkUI-X 的 ICU 不认部分区域标记（如 'zh-Hans-CN-u-co-pinyin'），直接 localeCompare 会抛 RangeError。
export function compareText(a: string, b: string, locale: string, options?: Intl.CollatorOptions): number {
  return options ? a.localeCompare(b, locale, options) : a.localeCompare(b, locale);
}
