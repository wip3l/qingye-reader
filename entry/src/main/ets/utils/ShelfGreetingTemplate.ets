/** 问候语占位符可替换的实时内容；拿不到的项留空串，替换后会把空出来的标点一并收掉。 */
export class ShelfGreetingValues {
  hour: number = 0;
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

const WEEK_DAYS: string[] = ['日', '一', '二', '三', '四', '五', '六'];

/**
 * 陪伴布局左上角的问候语：内置按时段的两行文案，或用户自己写的两行。自定义文案里的
 * {问候}、{昵称}、{今日阅读}、{在读}、{日期} 在显示时换成实时内容。
 */
export class ShelfGreetingTemplate {
  static readonly TOKENS: ShelfGreetingToken[] = [
    new ShelfGreetingToken('问候', '{问候}'),
    new ShelfGreetingToken('昵称', '{昵称}'),
    new ShelfGreetingToken('今日阅读', '{今日阅读}'),
    new ShelfGreetingToken('在读', '{在读}'),
    new ShelfGreetingToken('日期', '{日期}')
  ];
  static readonly MAX_LENGTH: number = 40;

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
      .split('{日期}').join(ShelfGreetingTemplate.formatDate(values.date));
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
}
