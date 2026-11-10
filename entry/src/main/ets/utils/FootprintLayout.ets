import { Context } from '@kit.AbilityKit';
import { FootprintSettingsStore } from './FootprintSettingsStore';

/** 足迹页的一块内容。 */
export class FootprintSection {
  id: string = '';
  title: string = '';
  description: string = '';
  /** 可选数量；空数组表示这一块没有数量可调。 */
  limits: number[] = [];
  unit: string = '';

  constructor(id: string, title: string, description: string, limits: number[], unit: string) {
    this.id = id;
    this.title = title;
    this.description = description;
    this.limits = limits;
    this.unit = unit;
  }
}

/**
 * 足迹页显示哪些内容、什么顺序、各显示几条。存成 JSON 放在 AppStorage 的 footprintLayout 里，
 * 由 FootprintSettingsStore 写进 Preferences；只存本机。空串就是默认（与没有这项设置之前一样）。
 */
export class FootprintLayout {
  static readonly STORAGE_KEY: string = 'footprintLayout';
  static readonly WEEK: string = 'week';
  static readonly MONTH: string = 'month';
  static readonly RANK: string = 'rank';
  static readonly EXCERPT: string = 'excerpt';
  static readonly BOOKMARK: string = 'bookmark';
  static readonly SECTIONS: FootprintSection[] = [
    new FootprintSection('week', '本周阅读', '总时长、和上周比、每日柱状图', [], ''),
    new FootprintSection('month', '本月日历', '每天读了多久', [], ''),
    new FootprintSection('rank', '读得最多', '本周阅读时长排行', [3, 5, 10], '本'),
    new FootprintSection('excerpt', '最近摘录', '横滑卡片', [5, 10, 20], '条'),
    new FootprintSection('bookmark', '最近书签', '横滑卡片', [5, 10, 20], '个')
  ];
  static readonly DEFAULT_LIMITS: Record<string, number> = { 'rank': 3, 'excerpt': 10, 'bookmark': 10 };

  order: string[] = FootprintLayout.SECTIONS.map((section: FootprintSection): string => section.id);
  hidden: string[] = [];
  limits: Record<string, number> = { 'rank': 3, 'excerpt': 10, 'bookmark': 10 };

  static parse(raw: string | undefined | null): FootprintLayout {
    const layout = new FootprintLayout();
    if (!raw) return layout;
    try {
      const value = JSON.parse(raw) as FootprintLayout;
      const known = FootprintLayout.SECTIONS.map((section: FootprintSection): string => section.id);
      const order: string[] = [];
      if (Array.isArray(value.order)) {
        for (const id of value.order) {
          if (known.includes(String(id)) && !order.includes(String(id))) order.push(String(id));
        }
      }
      // 以后新加的块排在最后，默认显示。
      for (const id of known) {
        if (!order.includes(id)) order.push(id);
      }
      layout.order = order;
      layout.hidden = Array.isArray(value.hidden) ?
        value.hidden.map((id: string): string => String(id)).filter((id: string): boolean => known.includes(id)) : [];
      for (const section of FootprintLayout.SECTIONS) {
        if (section.limits.length === 0) continue;
        const limit = value.limits ? Number(value.limits[section.id]) : NaN;
        layout.limits[section.id] = section.limits.includes(limit) ? limit :
          (FootprintLayout.DEFAULT_LIMITS[section.id] ?? section.limits[0]);
      }
    } catch (_) {
      return new FootprintLayout();
    }
    return layout;
  }

  static section(id: string): FootprintSection {
    return FootprintLayout.SECTIONS.find((section: FootprintSection): boolean => section.id === id) ||
      FootprintLayout.SECTIONS[0];
  }

  static save(context: Context, layout: FootprintLayout): void {
    FootprintSettingsStore.saveLayout(context, layout.isDefault() ? '' : JSON.stringify(layout)).catch((error: Error) => {
      console.warn('保存足迹页内容失败:', error);
    });
  }

  isVisible(id: string): boolean {
    return !this.hidden.includes(id);
  }

  visibleOrder(): string[] {
    return this.order.filter((id: string): boolean => this.isVisible(id));
  }

  limit(id: string): number {
    return this.limits[id] ?? FootprintLayout.DEFAULT_LIMITS[id] ?? 10;
  }

  isDefault(): boolean {
    const defaults = new FootprintLayout();
    return this.order.join(',') === defaults.order.join(',') && this.hidden.length === 0 &&
      FootprintLayout.SECTIONS.every((section: FootprintSection): boolean =>
        this.limit(section.id) === defaults.limit(section.id));
  }

  clone(): FootprintLayout {
    const copy = new FootprintLayout();
    copy.order = this.order.slice();
    copy.hidden = this.hidden.slice();
    const limits: Record<string, number> = {};
    for (const section of FootprintLayout.SECTIONS) {
      if (section.limits.length > 0) limits[section.id] = this.limit(section.id);
    }
    copy.limits = limits;
    return copy;
  }
}
