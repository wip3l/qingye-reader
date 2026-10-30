import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';

/**
 * 应用内使用说明的数据。正文来自 rawfile/manual/help.json，由 scripts/build-help-data.mjs
 * 从网页版说明书 docs/manual/index.html 生成，两边内容一致；字段名与生成脚本对应，尽量短以减小体积。
 */

/** 行内文字。k：0 普通、1 加粗、2 菜单路径、3 代码、4 链接（u 为地址，# 开头是说明书内的小节）。 */
export interface HelpRun {
  t: string;
  k: number;
  u?: string;
}

export interface HelpListItem {
  r: HelpRun[];
  /** 嵌套层级，0 为最外层。 */
  lv: number;
}

export interface HelpRow {
  title: string;
  cells: HelpRun[][];
}

/** 点击区域九宫格的一格。m：0 上一页、1 菜单、2 下一页。 */
export interface HelpZoneCell {
  t: string;
  m: number;
}

/** 正文块。k：p 段落、tip 提示、note 注意、h 小标题、ul/ol 列表、rows 表格、zone 点击区域示意。 */
export interface HelpBlock {
  k: string;
  r?: HelpRun[];
  items?: HelpListItem[];
  head?: string[];
  rows?: HelpRow[];
  cells?: HelpZoneCell[];
}

/** 跳转到应用内页面：url 为页面路径；home 为首页页签序号，回首页并切过去。 */
export interface HelpAction {
  label: string;
  url?: string;
  home?: number;
}

export interface HelpSection {
  id: string;
  title: string;
  blocks: HelpBlock[];
  /** 纯文字，供搜索。 */
  text: string;
  action?: HelpAction;
}

/** 专题里来自说明书同一章的一段。 */
export interface HelpPart {
  id: string;
  title: string;
  intro: HelpBlock[];
  sections: HelpSection[];
}

export interface HelpTopic {
  id: string;
  title: string;
  icon: string;
  summary: string;
  parts: HelpPart[];
  action?: HelpAction;
}

export interface HelpQuickStep {
  title: string;
  desc: string;
  action?: HelpAction;
}

interface HelpFaqItem {
  q: string;
  blocks: HelpBlock[];
  text: string;
  action?: HelpAction;
}

interface HelpDataFile {
  version: string;
  updated: string;
  quickStart: HelpQuickStep[];
  groups: HelpTopic[][];
  topics: HelpTopic[];
  faq: HelpFaqItem[];
  featuredFaq: number[];
  legalFooter: string;
}

export class HelpData {
  version: string = '';
  updated: string = '';
  quickStart: HelpQuickStep[] = [];
  groups: HelpTopic[][] = [];
  /** 常见问题整理成的专题，每条问题是一个小节。 */
  faq: HelpTopic | null = null;
  featuredFaq: HelpSection[] = [];
  legalFooter: string = '';
  private topicMap: Map<string, HelpTopic> = new Map();
  /** 章节或小节 id → 所在专题 id。 */
  private anchorMap: Map<string, string> = new Map();

  topic(id: string): HelpTopic | undefined {
    return this.topicMap.get(id);
  }

  topicOfAnchor(anchor: string): string {
    return this.anchorMap.get(anchor) || '';
  }

  /** 首页分组里的专题按顺序排成一列，用于专题页底部的上一篇、下一篇。 */
  orderedTopics(): HelpTopic[] {
    const result: HelpTopic[] = [];
    this.groups.forEach((group: HelpTopic[]) => group.forEach((topic: HelpTopic) => result.push(topic)));
    return result;
  }

  faqCount(): number {
    return this.faq ? this.faq.parts[0].sections.length : 0;
  }

  register(topic: HelpTopic): void {
    this.topicMap.set(topic.id, topic);
    this.anchorMap.set(topic.id, topic.id);
    topic.parts.forEach((part: HelpPart) => {
      this.anchorMap.set(part.id, topic.id);
      part.sections.forEach((section: HelpSection) => this.anchorMap.set(section.id, topic.id));
    });
  }
}

export class HelpSearchResult {
  topicId: string = '';
  anchor: string = '';
  title: string = '';
  /** 所在专题或章节名。 */
  location: string = '';
  /** 摘要拆成命中前、命中词、命中后三段，便于高亮。 */
  before: string = '';
  match: string = '';
  after: string = '';
  score: number = 0;
}

export class HelpManual {
  static readonly FAQ_TOPIC_ID: string = 'faq';
  private static data: HelpData | null = null;
  private static loading: Promise<HelpData> | null = null;

  static async load(context: Context): Promise<HelpData> {
    if (HelpManual.data) return HelpManual.data;
    if (!HelpManual.loading) {
      HelpManual.loading = HelpManual.read(context).then((data: HelpData) => {
        HelpManual.data = data;
        return data;
      }).finally(() => {
        HelpManual.loading = null;
      });
    }
    return HelpManual.loading;
  }

  private static async read(context: Context): Promise<HelpData> {
    const bytes = await context.resourceManager.getRawFileContent('manual/help.json');
    const text = util.TextDecoder.create('utf-8').decodeWithStream(bytes, { stream: false });
    const file = JSON.parse(text) as HelpDataFile;
    const data = new HelpData();
    data.version = file.version;
    data.updated = file.updated;
    data.quickStart = file.quickStart;
    data.groups = file.groups;
    data.legalFooter = file.legalFooter;
    file.groups.forEach((group: HelpTopic[]) => group.forEach((topic: HelpTopic) => data.register(topic)));
    file.topics.forEach((topic: HelpTopic) => data.register(topic));

    const sections: HelpSection[] = file.faq.map((item: HelpFaqItem, index: number): HelpSection => {
      const section: HelpSection = { id: `faq-${index}`, title: item.q, blocks: item.blocks, text: item.text };
      if (item.action) section.action = item.action;
      return section;
    });
    const faq: HelpTopic = {
      id: HelpManual.FAQ_TOPIC_ID, title: '常见问题', icon: 'questionmark_circle', summary: '',
      parts: [{ id: HelpManual.FAQ_TOPIC_ID, title: '', intro: [], sections: sections }]
    };
    data.faq = faq;
    data.register(faq);
    data.featuredFaq = file.featuredFaq.filter((index: number) => index >= 0 && index < sections.length)
      .map((index: number) => sections[index]);
    return data;
  }

  /** 按关键词搜标题和正文，标题命中排在前面。 */
  static search(data: HelpData, keyword: string, limit: number = 60): HelpSearchResult[] {
    const key = keyword.trim().toLowerCase();
    if (!key) return [];
    const results: HelpSearchResult[] = [];
    const topics: HelpTopic[] = data.orderedTopics();
    if (data.faq) topics.push(data.faq);
    const legal = data.topic('legal');
    if (legal) topics.push(legal);
    topics.forEach((topic: HelpTopic) => {
      topic.parts.forEach((part: HelpPart) => {
        const location = topic.parts.length > 1 && part.title ? part.title : topic.title;
        part.sections.forEach((section: HelpSection) => {
          const result = HelpManual.match(section.title, section.text, key);
          if (!result) return;
          result.topicId = topic.id;
          result.anchor = section.id;
          result.location = location;
          results.push(result);
        });
      });
    });
    return results.sort((a: HelpSearchResult, b: HelpSearchResult) => b.score - a.score).slice(0, limit);
  }

  private static match(title: string, text: string, key: string): HelpSearchResult | null {
    const titleAt = title.toLowerCase().indexOf(key);
    const flat = text.replace(/\s+/g, ' ');
    const textAt = flat.toLowerCase().indexOf(key);
    if (titleAt < 0 && textAt < 0) return null;
    const result = new HelpSearchResult();
    result.title = title;
    result.score = titleAt >= 0 ? 2 : 1;
    if (textAt >= 0) {
      // 命中处前面留一小段上下文，过长的开头用省略号代替。
      const start = Math.max(0, textAt - 12);
      result.before = (start > 0 ? '…' : '') + flat.substring(start, textAt);
      result.match = flat.substring(textAt, textAt + key.length);
      result.after = flat.substring(textAt + key.length, textAt + key.length + 60);
    } else {
      result.after = flat.substring(0, 60);
    }
    return result;
  }

  static openTopic(topicId: string, anchor: string = ''): void {
    router.pushUrl({ url: 'pages/HelpTopic', params: { topic: topicId, anchor: anchor } }).catch((error: Error) => {
      console.error('打开说明专题失败:', error.message);
    });
  }

  /** 正文里的链接：# 开头跳到说明书的对应专题，其余交给系统浏览器。 */
  static openLink(context: Context, data: HelpData, url: string): void {
    if (url.startsWith('#')) {
      const anchor = url.substring(1);
      const topicId = data.topicOfAnchor(anchor);
      if (topicId) HelpManual.openTopic(topicId, anchor === topicId ? '' : anchor);
      return;
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      (context as common.UIAbilityContext).openLink(url).catch((error: Error) => {
        console.error('打开外部链接失败:', error.message);
      });
    }
  }

  static runAction(action: HelpAction): void {
    if (action.url) {
      router.pushUrl({ url: action.url }).catch((error: Error) => {
        console.error('从说明页跳转失败:', error.message);
      });
      return;
    }
    if (action.home !== undefined) {
      // 首页监听这对键切页签；说明页可能叠在多层之上，直接退回首页。
      AppStorage.setOrCreate('homeTabRequestIndex', action.home);
      AppStorage.setOrCreate('homeTabRequestNonce', (AppStorage.get<number>('homeTabRequestNonce') || 0) + 1);
      router.back({ url: 'pages/Index' });
    }
  }

  static icon(name: string): Resource {
    switch (name) {
      case 'square_grid_2x2':
        return $r('sys.symbol.square_grid_2x2');
      case 'bookshelf':
        return $r('sys.symbol.bookshelf');
      case 'magnifyingglass':
        return $r('sys.symbol.magnifyingglass');
      case 'arrow_left_arrow_right':
        return $r('sys.symbol.arrow_left_arrow_right');
      case 'externaldrive':
        return $r('sys.symbol.externaldrive');
      case 'square_and_pencil':
        return $r('sys.symbol.square_and_pencil');
      case 'book':
        return $r('sys.symbol.book');
      case 'textformat':
        return $r('sys.symbol.textformat');
      case 'speaker_wave_3':
        return $r('sys.symbol.speaker_wave_3');
      case 'funnel':
        return $r('sys.symbol.funnel');
      case 'download':
        return $r('sys.symbol.download');
      case 'arrow_2_circlepath':
        return $r('sys.symbol.arrow_2_circlepath');
      case 'paintpalette':
        return $r('sys.symbol.paintpalette');
      case 'person':
        return $r('sys.symbol.person');
      case 'checkmark_shield':
        return $r('sys.symbol.checkmark_shield');
      case 'list_bullet':
        return $r('sys.symbol.list_bullet');
      default:
        return $r('sys.symbol.questionmark_circle');
    }
  }
}
