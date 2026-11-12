/**
 * Legado 发现分类的文本格式：条目之间用换行或 `&&` 分隔，每条 `名称::地址`；没有地址的条目
 * （`男频榜单::` 或单独一个名称）是分组标题。发现脚本返回这种文本时与写死在 exploreUrl 里的
 * 规则同义，这里按 Legado 的拆分方式还原成条目列表。
 */
export interface ExploreTextMenuItem {
  title: string;
  url: string;
}

export class ExploreTextMenu {
  /** 文本里一个 `::` 都没有时返回空数组，避免把报错信息之类的普通文本当成分类。 */
  static parse(value: string): ExploreTextMenuItem[] {
    const raw = (value || '').trim();
    if (!raw || raw.indexOf('::') < 0) return [];
    const items: ExploreTextMenuItem[] = [];
    for (const part of raw.split(/(?:&&|\r?\n|\r)+/)) {
      const line = part.trim();
      if (!line) continue;
      const index = line.indexOf('::');
      if (index < 0) {
        items.push({ title: line, url: '' });
        continue;
      }
      items.push({
        title: line.substring(0, index).trim(),
        url: line.substring(index + 2).trim()
      });
    }
    return items;
  }
}
