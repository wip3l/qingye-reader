/** 问候语占位符可替换的实时内容；拿不到的项留空串，替换后会把空出来的标点一并收掉。 */
export class ShelfGreetingValues {
  hour: number = 0;
  minute: number = 0;
  nickname: string = '';
  todayReadMs: number = 0;
  readingBookName: string = '';
  date: Date = new Date();
}

export class ShelfGreetingToken {
  label: string;
  token: string;

  constructor(label: string, token: string) {
    this.label = label;
    this.token = token;
  }
}

/** 自定义问候语的一个时段：从 start（当天第几分钟）起生效，到下一条的 start 为止。 */
export class ShelfGreetingSlot {
  start: number;
  title: string;
  subtitle: string;

  constructor(start: number, title: string, subtitle: string) {
    this.start = start;
    this.title = title;
    this.subtitle = subtitle;
  }
}

interface ShelfGreetingSlotData {
  start?: number;
  title?: string;
  subtitle?: string;
}

const WEEK_DAYS: string[] = ['日', '一', '二', '三', '四', '五', '六'];
const SHICHEN: string[] = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];

/**
 * 陪伴布局左上角的问候语：内置按时段的两行文案，或用户自己写的若干个时段、每个时段两行。自定义文案里的
 * {问候}、{昵称}、{今日阅读}、{在读}、{日期}、{时辰} 在显示时换成实时内容。
 */
export class ShelfGreetingTemplate {
  static readonly TOKENS: ShelfGreetingToken[] = [
    new ShelfGreetingToken('问候', '{问候}'),
    new ShelfGreetingToken('昵称', '{昵称}'),
    new ShelfGreetingToken('今日阅读', '{今日阅读}'),
    new ShelfGreetingToken('在读', '{在读}'),
    new ShelfGreetingToken('日期', '{日期}'),
    new ShelfGreetingToken('时辰', '{时辰}')
  ];
  static readonly MAX_LENGTH: number = 40;
  static readonly MAX_SLOTS: number = 24;
  /** 开始时间的最小刻度（分钟）。 */
  static readonly SLOT_STEP: number = 10;

  /** 子时从 23:00 起，每个时辰两小时。 */
  static shichen(minutes: number): string {
    return `${SHICHEN[Math.floor(((minutes + 60) % 1440) / 120)]}时`;
  }

  static formatSlotStart(minutes: number): string {
    const hour = Math.floor(minutes / 60);
    const minute = minutes % 60;
    return `${hour < 10 ? '0' : ''}${hour}:${minute < 10 ? '0' : ''}${minute}`;
  }

  static normalizeSlotStart(value: number): number {
    if (!Number.isFinite(value)) return 0;
    const step = ShelfGreetingTemplate.SLOT_STEP;
    const minutes = Math.floor(Math.max(0, Math.min(1439, value)) / step) * step;
    return minutes;
  }

  /**
   * 读出时段列表，按开始时间排好，至少有一条。slotsJson 为空或损坏时退回只有两行文案的旧数据，当作全天一条。
   * 开始时间相同的只留先出现的那条。
   */
  static parseSlots(slotsJson: string, legacyTitle: string, legacySubtitle: string): ShelfGreetingSlot[] {
    const slots: ShelfGreetingSlot[] = [];
    if (slotsJson) {
      try {
        const raw = JSON.parse(slotsJson) as ShelfGreetingSlotData[];
        if (Array.isArray(raw)) {
          for (const item of raw) {
            if (!item || slots.length >= ShelfGreetingTemplate.MAX_SLOTS) continue;
            const start = ShelfGreetingTemplate.normalizeSlotStart(typeof item.start === 'number' ? item.start : 0);
            if (slots.some((slot: ShelfGreetingSlot) => slot.start === start)) continue;
            slots.push(new ShelfGreetingSlot(start,
              typeof item.title === 'string' ? item.title.slice(0, ShelfGreetingTemplate.MAX_LENGTH) : '',
              typeof item.subtitle === 'string' ? item.subtitle.slice(0, ShelfGreetingTemplate.MAX_LENGTH) : ''));
          }
        }
      } catch (e) {
        console.warn('解析问候语时段失败:', e);
      }
    }
    if (slots.length === 0) slots.push(new ShelfGreetingSlot(0, legacyTitle || '', legacySubtitle || ''));
    slots.sort((a: ShelfGreetingSlot, b: ShelfGreetingSlot) => a.start - b.start);
    return slots;
  }

  static serializeSlots(slots: ShelfGreetingSlot[]): string {
    return JSON.stringify(slots.map((slot: ShelfGreetingSlot) =>
      new ShelfGreetingSlot(slot.start, slot.title.trim(), slot.subtitle.trim())));
  }

  /** 此刻生效的是哪一条：开始时间不晚于此刻的最后一条；比最早一条还早时归前一天的最后一条。slots 已按开始时间排好。 */
  static activeSlotIndex(slots: ShelfGreetingSlot[], minutes: number): number {
    let index = slots.length - 1;
    for (let i = 0; i < slots.length; i++) {
      if (slots[i].start <= minutes) index = i;
    }
    return slots[0].start <= minutes ? index : slots.length - 1;
  }

  /** 一键填入：十二时辰。 */
  static shichenPreset(): ShelfGreetingSlot[] {
    return [
      new ShelfGreetingSlot(60, '丑时鸡鸣，万籁俱寂。', '还醒着？那就再陪你一页。'),
      new ShelfGreetingSlot(180, '寅时平旦，天将明。', '{昵称}起得真早。'),
      new ShelfGreetingSlot(300, '卯时日出，{昵称}早安。', '翻开一本，日子就慢下来了。'),
      new ShelfGreetingSlot(420, '辰时食时，先吃早饭。', '路上读几页{在读}。'),
      new ShelfGreetingSlot(540, '巳时隅中，精神正好。', '今日已读 {今日阅读}。'),
      new ShelfGreetingSlot(660, '午时日中，歇一会儿。', '歇一会儿，读上几页。'),
      new ShelfGreetingSlot(780, '未时日昳，午后犯困。', '泡杯茶，故事还在原处等你。'),
      new ShelfGreetingSlot(900, '申时晡时，{昵称}下午好。', '{在读}还等着你。'),
      new ShelfGreetingSlot(1020, '酉时日入，该收工了。', '{日期}，辛苦了。'),
      new ShelfGreetingSlot(1140, '戌时黄昏，灯下好读书。', '夜里读书，最是安静。'),
      new ShelfGreetingSlot(1260, '亥时人定，{昵称}晚安。', '今日已读 {今日阅读}，够了。'),
      new ShelfGreetingSlot(1380, '子时夜半，{昵称}该歇了。', '读完这一章，就早点休息吧。')
    ];
  }

  /** 一键填入：与内置文案相同的五个时段。 */
  static periodPreset(): ShelfGreetingSlot[] {
    const starts: number[] = [0, 300, 660, 780, 1080];
    return starts.map((start: number) =>
      new ShelfGreetingSlot(start, '{问候}，慢慢读。', ShelfGreetingTemplate.periodSubtitle(Math.floor(start / 60))));
  }

  static periodGreeting(hour: number): string {
    if (hour < 5) return '夜深了';
    if (hour < 11) return '早上好';
    if (hour < 13) return '中午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  static periodSubtitle(hour: number): string {
    if (hour < 5) return '读完这一章，就早点休息吧。';
    if (hour < 11) return '翻开一本，日子就慢下来了。';
    if (hour < 13) return '歇一会儿，读上几页。';
    if (hour < 18) return '泡杯茶，故事还在原处等你。';
    return '夜里读书，最是安静。';
  }

  /** 内置文案：首行“问候，慢慢读。”，次行按时段换一句。 */
  static defaultLines(hour: number): string[] {
    return [`${ShelfGreetingTemplate.periodGreeting(hour)}，慢慢读。`, ShelfGreetingTemplate.periodSubtitle(hour)];
  }

  /** 第一次自定义时编辑框里预填的内容：首行保留随时段变化的问候，次行是此刻的内置句子。 */
  static defaultDraft(hour: number): string[] {
    return ['{问候}，慢慢读。', ShelfGreetingTemplate.periodSubtitle(hour)];
  }

  static formatDuration(ms: number): string {
    const minutes = Math.max(0, Math.floor(ms / 60000));
    if (minutes < 60) return `${minutes} 分钟`;
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    return rest > 0 ? `${hours} 小时 ${rest} 分钟` : `${hours} 小时`;
  }

  static formatDate(date: Date): string {
    return `${date.getMonth() + 1} 月 ${date.getDate()} 日 周${WEEK_DAYS[date.getDay()]}`;
  }

  static render(template: string, values: ShelfGreetingValues): string {
    const filled = template
      .split('{问候}').join(ShelfGreetingTemplate.periodGreeting(values.hour))
      .split('{昵称}').join(values.nickname.trim())
      .split('{今日阅读}').join(ShelfGreetingTemplate.formatDuration(values.todayReadMs))
      .split('{在读}').join(values.readingBookName ? `《${values.readingBookName.trim()}》` : '')
      .split('{日期}').join(ShelfGreetingTemplate.formatDate(values.date))
      .split('{时辰}').join(ShelfGreetingTemplate.shichen(values.hour * 60 + values.minute));
    return ShelfGreetingTemplate.tidy(filled);
  }

  /** 昵称、在读这类空值替换后会留下“早上好，。”或开头的逗号，收成一个标点并去掉首尾多余的分隔。 */
  static tidy(text: string): string {
    return text
      .replace(/[ \t]+/g, ' ')
      .replace(/([，,、；;])\s*(?=[，,、；;。！？!?…]|$)/g, '')
      .replace(/^[\s，,、；;]+/, '')
      .trim();
  }

  /** 自定义模式下实际显示的两行；首行写空时退回内置首行，次行写空就不显示。 */
  static customLines(title: string, subtitle: string, values: ShelfGreetingValues): string[] {
    const first = ShelfGreetingTemplate.render(title, values);
    return [first || ShelfGreetingTemplate.defaultLines(values.hour)[0], ShelfGreetingTemplate.render(subtitle, values)];
  }

  /** 自定义模式下按 values 里的时刻挑出生效的时段，返回实际显示的两行。 */
  static slotLines(slots: ShelfGreetingSlot[], values: ShelfGreetingValues): string[] {
    const slot = slots[ShelfGreetingTemplate.activeSlotIndex(slots, values.hour * 60 + values.minute)];
    return ShelfGreetingTemplate.customLines(slot.title, slot.subtitle, values);
  }
}
