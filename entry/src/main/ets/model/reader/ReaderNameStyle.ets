import { MimoRole } from '../../core/mimo/MimoPolicy';
import { ReaderNamePatterns, ReaderNameRoleInput } from '../../core/reader/ReaderNamePatterns';
import { MimoBookCast } from '../../utils/mimo/MimoStore';
import { ReaderRegexFontCodec, ReaderRegexFontRule } from './ReaderRegexFontRule';

/**
 * 正文人名上色：多角色朗读识别出的人物（本书人物档案）在正文里按人显示。
 * 能力和正则强调规则一样——本书一条“人名样式”规则管全部人物，颜色按人物分（或统一颜色）；某个人可以单独设一条完整规则。
 * 只存在这本书的人物档案里，不进“我的规则”。阅读时由 rules() 生成每人一条规则，接在用户自己的规则后面。
 */
export class ReaderNameStyle {
  static readonly MODE_ROLE: string = 'role';
  static readonly MODE_ONE: string = 'one';
  /** 打开阅读字体页的规则编辑来改人名样式：书的地址；改某个人单独的样式时再带上人物 id。 */
  static readonly PARAM_BOOK: string = 'nameStyleBook';
  static readonly PARAM_ROLE: string = 'nameStyleRole';

  /** 没设过人名样式时：只换文字颜色、稍加粗，只在正文里；字号取正文字号。 */
  static defaultRule(fontSize: number): ReaderRegexFontRule {
    const rule = new ReaderRegexFontRule();
    rule.id = 'name_style';
    rule.name = '人名';
    rule.scope = 'body';
    rule.fontMode = 'global';
    rule.fontSize = ReaderRegexFontCodec.normalizeFontSize(fontSize);
    rule.fontWeight = 600;
    rule.emphasisMode = 'custom';
    rule.customTextColorEnabled = true;
    rule.customTextColor = ReaderNamePatterns.PALETTE[4][0];
    rule.customTextColorDark = ReaderNamePatterns.PALETTE[4][1];
    rule.customHighlightColor = ReaderNamePatterns.PALETTE[4][0];
    rule.customBubbleColor = ReaderNamePatterns.PALETTE[4][0];
    return ReaderRegexFontCodec.cloneRule(rule);
  }

  static decodeOne(raw: string | undefined): ReaderRegexFontRule | null {
    if (!raw || !raw.trim()) return null;
    const rules = ReaderRegexFontCodec.decode(raw);
    return rules.length > 0 ? rules[0] : null;
  }

  static encodeOne(rule: ReaderRegexFontRule): string {
    return ReaderRegexFontCodec.encode([rule]);
  }

  static sharedRule(cast: MimoBookCast, fontSize: number): ReaderRegexFontRule {
    return ReaderNameStyle.decodeOne(cast.nameRule) ?? ReaderNameStyle.defaultRule(fontSize);
  }

  static ownRule(role: MimoRole): ReaderRegexFontRule | null {
    return ReaderNameStyle.decodeOne(role.nameRule);
  }

  static colorMode(cast: MimoBookCast): string {
    return cast.nameColorMode === ReaderNameStyle.MODE_ONE ? ReaderNameStyle.MODE_ONE : ReaderNameStyle.MODE_ROLE;
  }

  /** 参与上色的人物：除了旁白。 */
  static characters(cast: MimoBookCast): MimoRole[] {
    return cast.roles.filter((role: MimoRole): boolean => role.id !== 'narrator');
  }

  /** 与 characters 同序的色板下标，-1 为不上色。 */
  static colors(cast: MimoBookCast): number[] {
    return ReaderNamePatterns.assignColors(ReaderNameStyle.characters(cast).map((role: MimoRole): ReaderNameRoleInput => {
      const input = new ReaderNameRoleInput();
      input.id = role.id;
      input.name = role.name;
      input.aliases = role.aliases || [];
      input.lead = role.lead === true;
      input.color = typeof role.nameColor === 'number' ? role.nameColor : undefined;
      return input;
    }));
  }

  /** 每个上色的人一条规则，名字长的排前面（先认领，长名字不会被短名字截掉一半）。 */
  static rules(cast: MimoBookCast, fontSize: number): ReaderRegexFontRule[] {
    if (cast.nameStyleOn !== true) return [];
    const roles = ReaderNameStyle.characters(cast);
    const colors = ReaderNameStyle.colors(cast);
    const shared = ReaderNameStyle.sharedRule(cast, fontSize);
    const byRole = ReaderNameStyle.colorMode(cast) === ReaderNameStyle.MODE_ROLE;
    const built: ReaderRegexFontRule[] = [];
    const lengths: Map<string, number> = new Map<string, number>();
    roles.forEach((role: MimoRole, index: number) => {
      if (colors[index] < 0) return;
      const names = [role.name].concat(role.aliases || []);
      const pattern = ReaderNamePatterns.pattern(names);
      if (!pattern) return;
      const own = ReaderNameStyle.ownRule(role);
      const rule = ReaderRegexFontCodec.cloneRule(own ?? shared);
      rule.id = `name_${role.id}`;
      rule.name = `人名·${role.name}`;
      rule.pattern = pattern;
      rule.matcher = '';
      rule.enabled = true;
      rule.nestOthers = false;
      rule.paragraphIndent = -1;
      if (!own && byRole) {
        const pair = ReaderNamePatterns.PALETTE[colors[index]];
        rule.customTextColor = pair[0];
        rule.customTextColorDark = pair[1];
        rule.customHighlightColor = pair[0];
        rule.customHighlightColorDark = pair[1];
        rule.customBubbleColor = pair[0];
        rule.customBubbleColorDark = pair[1];
      }
      lengths.set(rule.id, ReaderNamePatterns.longestName(names));
      built.push(ReaderRegexFontCodec.cloneRule(rule));
    });
    return built.sort((left: ReaderRegexFontRule, right: ReaderRegexFontRule): number =>
      (lengths.get(right.id) ?? 0) - (lengths.get(left.id) ?? 0));
  }

  /** 列表里色点显示的颜色：单独设过样式的取它自己的颜色，否则取色板；不上色为空。 */
  static roleColor(cast: MimoBookCast, role: MimoRole, colorIndex: number, dark: boolean): string {
    if (colorIndex < 0) return '';
    const own = ReaderNameStyle.ownRule(role);
    if (own) {
      const text = ReaderRegexFontCodec.customTextColor(own, dark);
      const highlight = ReaderRegexFontCodec.customHighlightColor(own, dark);
      const bubble = ReaderRegexFontCodec.customBubbleColor(own, dark);
      if (own.customTextColorEnabled && text) return text;
      if (own.customHighlightEnabled && highlight) return highlight;
      if (own.customBubbleEnabled && bubble) return bubble;
    }
    if (ReaderNameStyle.colorMode(cast) === ReaderNameStyle.MODE_ONE) {
      const shared = ReaderNameStyle.sharedRule(cast, 20);
      return ReaderRegexFontCodec.customTextColor(shared, dark) || ReaderNamePatterns.PALETTE[colorIndex][dark ? 1 : 0];
    }
    return ReaderNamePatterns.PALETTE[colorIndex][dark ? 1 : 0];
  }

  /** “人名样式”一行右边的摘要。 */
  static summary(cast: MimoBookCast): string {
    const rule = ReaderNameStyle.sharedRule(cast, 20);
    if (rule.emphasisMode === 'inherit') return '跟随主题';
    if (rule.emphasisMode === 'none') return '无强调';
    const parts: string[] = [];
    if (rule.customTextColorEnabled) parts.push('文字色');
    if (rule.customHighlightEnabled) parts.push('高亮色块');
    if (rule.customBubbleEnabled) parts.push('气泡');
    const effect = parts.length > 0 ? parts.join(' + ') : '自定义';
    return `${effect} · ${ReaderNameStyle.colorMode(cast) === ReaderNameStyle.MODE_ONE ? '统一颜色' : '按人物'}`;
  }
}
