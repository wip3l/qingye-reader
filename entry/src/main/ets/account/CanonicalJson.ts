/**
 * 按键名排序后的 JSON 文本，用来判断两份同步内容是否相同。服务端 jsonb 会重排键的顺序，
 * 直接比较 JSON.stringify 的结果会把内容相同的设置当成不同。
 */
export function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map((item: unknown) => canonicalJson(item === undefined ? null : item)).join(',')}]`;
  }
  if (value !== null && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    const parts: string[] = [];
    for (const key of Object.keys(record).sort()) {
      const item = record[key];
      if (item === undefined || typeof item === 'function') continue;
      parts.push(`${JSON.stringify(key)}:${canonicalJson(item)}`);
    }
    return `{${parts.join(',')}}`;
  }
  const text = JSON.stringify(value);
  return text === undefined ? 'null' : text;
}
