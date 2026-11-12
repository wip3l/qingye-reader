import { router } from '@kit.ArkUI';
import { BookSource } from '@legado/sourceengine';
import { AppDatabase } from '../../model/data/AppDatabase';
import { BookSourceGroupStore } from '../../utils/BookSourceGroupStore';
import { ExploreResultCache } from '../../utils/ExploreResultCache';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { SystemDialogSession } from '../../utils/SystemDialogSession';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { PopupMenuAction } from '../common/PopupMenuAction';

/**
 * 发现页书源下拉与搜索范围面板共用的书源选择约定：分组名、分组顺序、同名书源的显示名、
 * 搜索框、分组小标签和长按书源的操作菜单。两边容器不同（单选弹出层 / 多选半模态），
 * 这些细节保持一致，改一处两边一起变。
 */
export class SourcePickerKit {
  static readonly UNGROUPED: string = '未分组';
  static readonly SEARCH_PLACEHOLDER: string = '搜索规则名称、地址或分组';

  static groupLabel(group: string | undefined): string {
    const normalized = (group || '').trim();
    return normalized || SourcePickerKit.UNGROUPED;
  }

  /** 遵循分组管理顺序；新分组按名称补在末尾，“未分组”始终最后。 */
  static sortGroups(groups: string[]): string[] {
    const order = BookSourceGroupStore.currentOrder();
    return groups.slice().sort((left: string, right: string): number => {
      if (left === right) return 0;
      if (left === SourcePickerKit.UNGROUPED) return 1;
      if (right === SourcePickerKit.UNGROUPED) return -1;
      const leftIndex = order.indexOf(left);
      const rightIndex = order.indexOf(right);
      if (leftIndex >= 0 || rightIndex >= 0) {
        return (leftIndex < 0 ? order.length : leftIndex) - (rightIndex < 0 ? order.length : rightIndex);
      }
      return left.localeCompare(right);
    });
  }

  /** 同名书源在名称后补上去掉协议和末尾斜杠的地址；返回与输入同序的显示名。 */
  static displayNames(names: string[], urls: string[]): string[] {
    const counts: Map<string, number> = new Map<string, number>();
    const normalized = names.map((name: string): string => name || '未命名规则');
    for (const name of normalized) {
      counts.set(name, (counts.get(name) || 0) + 1);
    }
    return normalized.map((name: string, index: number): string => {
      if ((counts.get(name) || 0) <= 1) return name;
      const sourceKey = (urls[index] || '无地址').replace(/^https?:\/\//i, '').replace(/\/$/, '');
      return `${name} · ${sourceKey}`;
    });
  }
}

/** 书源选择里的搜索框：药丸形浅色底，放大镜、输入框和有内容时的清空按钮。 */
@Component
export struct SourcePickerSearchField {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @Prop text: string = '';
  placeholder: string = SourcePickerKit.SEARCH_PLACEHOLDER;
  onTextChange: (value: string) => void = (_value: string): void => {
  };

  build() {
    Row({ space: AppSpacing.SM }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(16)
        .fontColor([ThemeRuntime.subTextColor(this.appDarkMode)])
      TextInput({ text: this.text, placeholder: this.placeholder })
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .placeholderColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .placeholderFont({ size: AppFontSize.BODY })
        .layoutWeight(1)
        .height(36)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .enterKeyType(EnterKeyType.Search)
        .onChange((value: string): void => {
          if (value !== this.text) this.onTextChange(value);
        })
      if (this.text) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(14)
          .fontColor([ThemeRuntime.subTextColor(this.appDarkMode)])
          .width(28)
          .height(36)
          .accessibilityText('清空规则搜索')
          .onClick((): void => this.onTextChange(''))
      }
    }
    .width('100%')
    .height(40)
    .padding({ left: AppSpacing.LG, right: AppSpacing.SM })
    .borderRadius(20)
    .backgroundColor(ThemeRuntime.softFillColor(this.appDarkMode))
  }
}

/** 跨分组列表里书源名右侧的分组小标签。 */
@Component
export struct SourceGroupTag {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @Prop label: string = '';

  build() {
    Text(this.label)
      .fontSize(AppFontSize.MICRO)
      .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 68 })
      .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
      .borderRadius(ThemeRuntime.mediumRadius())
      .backgroundColor(ThemeRuntime.softFillColor(this.appDarkMode))
  }
}

export class SourceActionKind {
  static readonly LOGIN: string = 'login';
  static readonly VARIABLE: string = 'variable';
  static readonly GROUP: string = 'group';
  static readonly SETTINGS: string = 'settings';
  static readonly EDIT: string = 'edit';
  static readonly DELETE: string = 'delete';
}

class SourceActionItem {
  kind: string = '';
  label: string = '';
  icon: Resource = $r('sys.symbol.gearshape');
  danger: boolean = false;
}

/** 长按书源的操作菜单条目。 */
export class SourceActionMenuList {
  static readonly WIDTH: number = 160;

  static items(isNative: boolean): SourceActionItem[] {
    const result: SourceActionItem[] = [
      { kind: SourceActionKind.LOGIN, label: '登录', icon: $r('sys.symbol.arrow_right_up_and_square'), danger: false },
      { kind: SourceActionKind.VARIABLE, label: '源变量', icon: $r('sys.symbol.list_bullet'), danger: false },
      { kind: SourceActionKind.GROUP, label: '设置分组', icon: $r('sys.symbol.folder'), danger: false }
    ];
    if (isNative) {
      result.push({ kind: SourceActionKind.SETTINGS, label: '规则设置', icon: $r('sys.symbol.gearshape'), danger: false });
    }
    result.push({ kind: SourceActionKind.EDIT, label: '编辑', icon: $r('sys.symbol.square_and_pencil'), danger: false });
    result.push({ kind: SourceActionKind.DELETE, label: '删除', icon: $r('sys.symbol.trash'), danger: true });
    return result;
  }

  static itemColor(item: SourceActionItem, darkMode: boolean): string {
    return item.danger ? ThemeRuntime.dangerColor(darkMode) : ThemeRuntime.primaryTextColor(darkMode);
  }
}

/**
 * 长按书源的操作菜单内容，外层容器（发现页的系统弹出层、搜索范围面板的长按菜单）由调用方决定，
 * 沉浸光感材质也由外层容器提供。
 */
@Builder
export function SourceActionMenu(isNative: boolean, darkMode: boolean, onAction: (kind: string) => void) {
  Column() {
    ForEach(SourceActionMenuList.items(isNative), (item: SourceActionItem) => {
      PopupMenuAction(item.icon, item.label, SourceActionMenuList.itemColor(item, darkMode), () => onAction(item.kind))
    }, (item: SourceActionItem): string => item.kind)
  }
  .width(SourceActionMenuList.WIDTH)
  .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
}

export class SourceVariableDialogParams {
  url: string = '';
  name: string = '';
  comment: string = '';
  value: string = '';
  onClose: () => void = (): void => {
  };
  onSaved: () => void = (): void => {
  };
}

export class SourceGroupDialogParams {
  url: string = '';
  name: string = '';
  group: string = '';
  /** 全部已有分组（分组管理顺序），用作快捷选项。 */
  groups: string[] = [];
  onClose: () => void = (): void => {
  };
  onSaved: (group: string) => void = (_group: string): void => {
  };
}

export class SourceDeleteDialogParams {
  name: string = '';
  onCancel: () => void = (): void => {
  };
  onConfirm: () => void = (): void => {
  };
}

/** 源变量编辑框的内容，由调用方组件里的 @Builder 创建，放进系统对话框。 */
@Component
export struct SourceVariableEditor {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  params: SourceVariableDialogParams = new SourceVariableDialogParams();
  @State value: string = '';
  @State saving: boolean = false;

  aboutToAppear(): void {
    this.value = this.params.value;
  }

  build() {
    Column({ space: AppSpacing.LG }) {
      Text('编辑源变量')
        .fontSize(AppFontSize.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .width('100%')
        .textAlign(TextAlign.Center)

      Text(this.params.name || this.params.url)
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)

      if (this.params.comment) {
        Text(this.params.comment)
          .fontSize(AppFontSize.CAPTION)
          .lineHeight(18)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .width('100%')
          .padding(AppSpacing.MD)
          .borderRadius(ThemeRuntime.mediumRadius())
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
      }

      TextArea({ text: this.value, placeholder: this.params.comment || '请输入规则变量' })
        .width('100%')
        .height(180)
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .placeholderColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
        .borderRadius(ThemeRuntime.mediumRadius())
        .padding(AppSpacing.LG)
        .enabled(!this.saving)
        .onChange((value: string) => {
          this.value = value;
        })

      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .enabled(!this.saving)
          .onClick(() => this.params.onClose())
        Button(this.saving ? '保存中…' : '保存')
          .layoutWeight(1)
          .height(40)
          .fontColor(ThemeRuntime.onAccentColor())
          .backgroundColor(ThemeRuntime.accentColor(this.appDarkMode))
          .enabled(!this.saving)
          .onClick(() => this.save())
      }
      .width('100%')
    }
    .padding(AppSpacing.XL)
  }

  async save(): Promise<void> {
    if (!this.params.url || this.saving) return;
    this.saving = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      await db.updateBookSourceVariable(this.params.url, this.value);
      // 源变量会影响发现结果，缓存跟着清掉。
      await ExploreResultCache.clearSource(getContext(this), this.params.url);
      this.saving = false;
      this.params.onClose();
      HdsFeedback.showToast('源变量已保存');
      this.params.onSaved();
    } catch (error) {
      this.saving = false;
      console.error('保存规则变量失败:', error);
      HdsFeedback.showToast('保存源变量失败');
    }
  }
}

/** 设置书源分组框的内容：输入新分组或点选已有分组，留空为未分组。由调用方组件里的 @Builder 创建。 */
@Component
export struct SourceGroupEditor {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  params: SourceGroupDialogParams = new SourceGroupDialogParams();
  @State value: string = '';
  @State saving: boolean = false;

  aboutToAppear(): void {
    this.value = this.params.group;
  }

  build() {
    Column({ space: AppSpacing.LG }) {
      Text('设置分组')
        .fontSize(AppFontSize.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .width('100%')
        .textAlign(TextAlign.Center)

      Text(this.params.name || this.params.url)
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)

      TextInput({ placeholder: '输入新分组名称，留空为未分组', text: this.value })
        .width('100%')
        .height(44)
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .placeholderColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
        .borderRadius(ThemeRuntime.mediumRadius())
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        .enabled(!this.saving)
        .onChange((value: string) => {
          this.value = value;
        })

      Scroll() {
        Flex({ wrap: FlexWrap.Wrap }) {
          this.groupChip(SourcePickerKit.UNGROUPED, '')
          ForEach(this.params.groups, (group: string) => {
            this.groupChip(group, group)
          }, (group: string): string => group)
        }
        .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .constraintSize({ maxHeight: 200 })
      .scrollBar(BarState.Auto)

      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .enabled(!this.saving)
          .onClick(() => this.params.onClose())
        Button(this.saving ? '保存中…' : '保存')
          .layoutWeight(1)
          .height(40)
          .fontColor(ThemeRuntime.onAccentColor())
          .backgroundColor(ThemeRuntime.accentColor(this.appDarkMode))
          .enabled(!this.saving)
          .onClick(() => this.save())
      }
      .width('100%')
    }
    .padding(AppSpacing.XL)
  }

  @Builder
  groupChip(label: string, group: string) {
    Text(label)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.value.trim() === group ? ThemeRuntime.accentColor(this.appDarkMode) :
        ThemeRuntime.subTextColor(this.appDarkMode))
      .fontWeight(this.value.trim() === group ? FontWeight.Medium : FontWeight.Regular)
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
      .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
      .borderRadius(ThemeRuntime.buttonRadius())
      .margin({ right: AppSpacing.MD, bottom: AppSpacing.MD })
      .onClick(() => {
        if (!this.saving) this.value = group;
      })
  }

  async save(): Promise<void> {
    if (!this.params.url || this.saving) return;
    const group = this.value.trim();
    if (group === this.params.group) {
      this.params.onClose();
      return;
    }
    this.saving = true;
    try {
      const context = getContext(this);
      const db = AppDatabase.getInstance();
      await db.initWithContext(context);
      await db.updateBookSourceListFields(this.params.url, { bookSourceGroup: group });
      if (group) {
        // 与书源管理一致：输入的新名字记为用户创建的分组，点选已有分组只补进顺序。
        await BookSourceGroupStore.add(context, group, this.params.groups, !this.params.groups.includes(group));
      }
      this.saving = false;
      this.params.onClose();
      HdsFeedback.showToast(group ? `已加入分组：${group}` : '已移出分组');
      this.params.onSaved(group);
    } catch (error) {
      this.saving = false;
      console.error('设置规则分组失败:', error);
      HdsFeedback.showToast('设置分组失败');
    }
  }
}

/** 删除书源确认框的内容，由调用方组件里的 @Builder 创建，放进系统对话框。 */
@Component
export struct SourceDeleteConfirm {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  params: SourceDeleteDialogParams = new SourceDeleteDialogParams();

  build() {
    Column() {
      Text('删除规则')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .width('100%')
        .textAlign(TextAlign.Center)

      Text(`确定删除“${this.params.name}”吗？删除后不可恢复。`)
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: AppSpacing.LG, bottom: AppSpacing.XXL })

      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .onClick(() => this.params.onCancel())

        Button('删除')
          .layoutWeight(1)
          .height(44)
          .backgroundColor('#B71C1C')
          .fontColor('#FFFFFF')
          .onClick(() => this.params.onConfirm())
      }
      .width('100%')
    }
    .padding(AppSpacing.XXL)
  }
}

/** 调用方组件把对话框参数包成自己的 @Builder；内容组件要在组件里创建才有父节点，放到静态方法里建会闪退。 */
export type SourceVariableDialogBuilder = (params: SourceVariableDialogParams) => CustomBuilder;
export type SourceDeleteDialogBuilder = (params: SourceDeleteDialogParams) => CustomBuilder;
export type SourceGroupDialogBuilder = (params: SourceGroupDialogParams) => CustomBuilder;

/** 长按菜单各项的执行：跳页面的直接跳，源变量和删除弹系统对话框，完成后回调调用方刷新。 */
export class SourceActionRunner {
  // 系统自定义对话框（builder 形式）由系统画沉浸光感表面，和其他弹窗一致。
  private static variableSession: SystemDialogSession = new SystemDialogSession();
  private static deleteSession: SystemDialogSession = new SystemDialogSession();
  private static groupSession: SystemDialogSession = new SystemDialogSession();

  /** 离开所在页面（如切走发现页标签）时收起源变量与分组编辑框；已开始的保存仍会在后台完成。 */
  static closeVariableEditor(uiContext: UIContext): void {
    SourceActionRunner.variableSession.close(uiContext);
    SourceActionRunner.groupSession.close(uiContext);
  }

  /** 登录、书源设置、编辑是跳页面的操作。 */
  static isNavigation(kind: string): boolean {
    return kind === SourceActionKind.LOGIN || kind === SourceActionKind.SETTINGS || kind === SourceActionKind.EDIT;
  }

  static navigate(kind: string, sourceUrl: string, isNative: boolean): void {
    if (!sourceUrl) return;
    if (kind === SourceActionKind.LOGIN) {
      router.pushUrl({ url: 'pages/BookSource', params: { openLoginSourceUrl: sourceUrl } });
    } else if (kind === SourceActionKind.SETTINGS) {
      router.pushUrl({ url: 'pages/NativeSourceSettings', params: { bookSourceUrl: sourceUrl } });
    } else if (kind === SourceActionKind.EDIT) {
      router.pushUrl({
        url: isNative ? 'pages/NativeSourceEdit' : 'pages/BookSourceEdit',
        params: { bookSourceUrl: sourceUrl }
      });
    }
  }

  static async openVariableEditor(uiContext: UIContext, sourceUrl: string, buildDialog: SourceVariableDialogBuilder,
    onSaved: () => void): Promise<void> {
    if (!sourceUrl) return;
    const source = await SourceActionRunner.loadSource(uiContext, sourceUrl, '读取规则变量失败');
    if (!source) return;
    const params = new SourceVariableDialogParams();
    params.url = source.bookSourceUrl;
    params.name = source.bookSourceName || source.bookSourceUrl;
    params.value = source.variable || '';
    params.comment = (source.variableComment || '').trim();
    params.onClose = (): void => SourceActionRunner.variableSession.close(uiContext);
    params.onSaved = onSaved;
    // 保存中禁止蒙层关闭，避免丢掉输入。
    SourceActionRunner.variableSession.open(uiContext, buildDialog(params), {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(AppStorage.get<boolean>('appDarkMode') === true),
      warnTag: '显示编辑源变量弹窗失败:'
    });
  }

  static async openGroupEditor(uiContext: UIContext, sourceUrl: string, buildDialog: SourceGroupDialogBuilder,
    onSaved: (group: string) => void): Promise<void> {
    if (!sourceUrl) return;
    const source = await SourceActionRunner.loadSource(uiContext, sourceUrl, '读取规则失败');
    if (!source) return;
    if (source.isLocked) {
      HdsFeedback.showToast('锁定的规则不能修改分组');
      return;
    }
    let groups: string[] = [];
    try {
      groups = await BookSourceGroupStore.loadOrder(uiContext.getHostContext() as Context);
    } catch (error) {
      console.warn('读取规则分组失败:', error);
    }
    const params = new SourceGroupDialogParams();
    params.url = source.bookSourceUrl;
    params.name = source.bookSourceName || source.bookSourceUrl;
    params.group = (source.bookSourceGroup || '').trim();
    params.groups = params.group && !groups.includes(params.group) ? groups.concat([params.group]) : groups;
    params.onClose = (): void => SourceActionRunner.groupSession.close(uiContext);
    params.onSaved = onSaved;
    SourceActionRunner.groupSession.open(uiContext, buildDialog(params), {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(AppStorage.get<boolean>('appDarkMode') === true),
      warnTag: '显示设置分组弹窗失败:'
    });
  }

  static async confirmDelete(uiContext: UIContext, sourceUrl: string, buildDialog: SourceDeleteDialogBuilder,
    onDeleted: (url: string) => void): Promise<void> {
    if (!sourceUrl) return;
    const source = await SourceActionRunner.loadSource(uiContext, sourceUrl, '读取规则失败');
    if (!source) return;
    if (source.isLocked) {
      HdsFeedback.showToast('锁定的规则不能删除');
      return;
    }
    const params = new SourceDeleteDialogParams();
    params.name = source.bookSourceName || source.bookSourceUrl;
    params.onCancel = (): void => SourceActionRunner.deleteSession.close(uiContext);
    params.onConfirm = (): void => {
      SourceActionRunner.deleteSession.close(uiContext);
      SourceActionRunner.deleteSource(uiContext, source.bookSourceUrl, onDeleted);
    };
    SourceActionRunner.deleteSession.open(uiContext, buildDialog(params), {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(AppStorage.get<boolean>('appDarkMode') === true),
      warnTag: '显示删除规则弹窗失败:'
    });
  }

  private static async deleteSource(uiContext: UIContext, sourceUrl: string,
    onDeleted: (url: string) => void): Promise<void> {
    try {
      const context = uiContext.getHostContext() as Context;
      const db = AppDatabase.getInstance();
      await db.initWithContext(context);
      await db.deleteBookSource(sourceUrl);
      await ExploreResultCache.clearSource(context, sourceUrl);
      HdsFeedback.showToast('规则已删除');
      onDeleted(sourceUrl);
    } catch (e) {
      console.error('删除规则失败:', e);
      HdsFeedback.showToast('删除规则失败');
    }
  }

  private static async loadSource(uiContext: UIContext, sourceUrl: string, failText: string): Promise<BookSource | null> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(uiContext.getHostContext() as Context);
      const source = await db.getBookSource(sourceUrl);
      if (!source) {
        HdsFeedback.showToast('规则不存在');
        return null;
      }
      return source;
    } catch (error) {
      console.error(`${failText}:`, error);
      HdsFeedback.showToast(failText);
      return null;
    }
  }
}
