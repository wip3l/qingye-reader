/**
 * 新书加入书架时默认放进哪个分组。纯 TS，Node 回归脚本可以直接加载。
 *
 * - none：一律未分组（旧行为）；
 * - last：上次在详情页“放进分组”里选的分组；
 * - shelf：首页书架当前停在的分组页签（“全部”“未分组”页签都算未分组）。
 *
 * 选中的分组已被删掉时回落为未分组。只管搜索、发现、详情页和试读转入书架这些在线书入口，
 * 已在书架的书不改分组。
 */
export type NewBookGroupMode = 'none' | 'last' | 'shelf';

export class NewBookGroup {
  /** 新书未分组时写入的分组值，沿用一直以来的取值；书架把所有 <= 0 的分组都当未分组。 */
  static readonly UNGROUPED: number = -2147483645;
  static readonly MODES: NewBookGroupMode[] = ['none', 'last', 'shelf'];
  static readonly LABELS: string[] = ['未分组', '上次选的分组', '书架当前所在分组'];

  static normalizeMode(value: string | undefined | null): NewBookGroupMode {
    return value === 'last' || value === 'shelf' ? value : 'none';
  }

  static modeIndex(mode: string): number {
    return Math.max(0, NewBookGroup.MODES.indexOf(NewBookGroup.normalizeMode(mode)));
  }

  /**
   * 返回应放进的自定义分组 id（> 0），不放进任何分组时返回 0。
   * shelfGroupId 是书架页签的取值：0 = 全部，-1 = 未分组，> 0 = 分组。
   */
  static pick(mode: string, lastGroupId: number, shelfGroupId: number, existingGroupIds: number[]): number {
    const normalized = NewBookGroup.normalizeMode(mode);
    const candidate = normalized === 'last' ? lastGroupId : (normalized === 'shelf' ? shelfGroupId : 0);
    if (!Number.isInteger(candidate) || candidate <= 0) return 0;
    return existingGroupIds.indexOf(candidate) >= 0 ? candidate : 0;
  }

  /** 加入书架后的提示文字。 */
  static addedToast(groupName: string): string {
    return groupName ? `已加入书架 · ${groupName}` : '已加入书架';
  }
}
