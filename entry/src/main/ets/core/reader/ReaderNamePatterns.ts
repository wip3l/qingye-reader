/**
 * 正文人名上色里和界面无关的部分：色板、自动分色、把一个人的名字和别名拼成正则。方便单独测试。
 */
export class ReaderNameRoleInput {
  id: string = '';
  name: string = '';
  aliases: string[] = [];
  lead: boolean = false;
  /** 没有为自动分配，-1 不上色，>=0 色板下标。 */
  color: number | undefined = undefined;
}

export class ReaderNamePatterns {
  /** 白天、夜间一对；夜间是同色系的亮色，深色背景上也看得清。 */
  static readonly PALETTE: string[][] = [
    ['#C2410C', '#FDBA74'], ['#7C3AED', '#C4B5FD'], ['#0F766E', '#5EEAD4'], ['#B91C1C', '#FCA5A5'],
    ['#1D4ED8', '#93C5FD'], ['#A16207', '#FDE68A'], ['#BE185D', '#F9A8D4'], ['#4D7C0F', '#BEF264']
  ];
  static readonly NONE: number = -1;
  /** 一个字的名字和别名不上色：单字太容易在别的词里撞上。 */
  static readonly MIN_NAME_LENGTH: number = 2;

  /**
   * 每个人的颜色：手动选过的用选的，其余按主角在前、再按原顺序依次取色板里没被手动占用的颜色，循环使用。
   * 返回与 roles 同序的色板下标（-1 不上色）。
   */
  static assignColors(roles: ReaderNameRoleInput[]): number[] {
    const result: number[] = roles.map((role: ReaderNameRoleInput): number =>
      role.color === undefined ? -2 : Math.max(-1, Math.min(ReaderNamePatterns.PALETTE.length - 1, role.color)));
    const taken = new Set<number>();
    for (const value of result) if (value >= 0) taken.add(value);
    const free: number[] = [];
    for (let index = 0; index < ReaderNamePatterns.PALETTE.length; index++) {
      if (!taken.has(index)) free.push(index);
    }
    const pool = free.length > 0 ? free : ReaderNamePatterns.PALETTE.map((_value: string[], index: number): number => index);
    const order = roles.map((_role: ReaderNameRoleInput, index: number): number => index)
      .filter((index: number): boolean => result[index] === -2)
      .sort((left: number, right: number): number =>
        (roles[left].lead ? 0 : 1) - (roles[right].lead ? 0 : 1) || left - right);
    order.forEach((roleIndex: number, position: number) => {
      result[roleIndex] = pool[position % pool.length];
    });
    return result;
  }

  /** 名字和别名去重、去掉太短的，长的在前（“林先生”先于“林”），转义后用 | 连起来；没有可用的名字时为空。 */
  static pattern(names: string[]): string {
    const seen = new Set<string>();
    const list: string[] = [];
    for (const raw of names) {
      const name = (raw || '').trim();
      if (name.length < ReaderNamePatterns.MIN_NAME_LENGTH || seen.has(name)) continue;
      seen.add(name);
      list.push(name);
    }
    list.sort((left: string, right: string): number => right.length - left.length);
    return list.map((name: string): string => ReaderNamePatterns.escape(name)).join('|');
  }

  static longestName(names: string[]): number {
    let longest = 0;
    for (const name of names) longest = Math.max(longest, (name || '').trim().length);
    return longest;
  }

  static escape(text: string): string {
    return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }
}
