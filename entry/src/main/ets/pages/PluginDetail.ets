import { promptAction, router } from '@kit.ArkUI';
import fs from '@ohos.file.fs';
import {
  formatSignerFingerprint,
  InstalledPluginRecord,
  PluginEngineHost,
  PluginRegistry,
  PluginSettingAction,
  PluginSettingField,
  PluginSettingOption,
  PluginToolContribution
} from '@legado/pluginengine';
import { PageScaffold } from '../components/common/PageScaffold';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';
import { PluginSandboxWebView } from '../components/plugin/PluginSandboxWebView';
import { AppPluginHost } from '../core/plugin/AppPluginHost';
import { PluginCapabilities, PluginPermissionRow } from '../core/plugin/PluginCapabilities';
import { fileUri } from '../platform/FileUri';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ThemedDialog } from '../utils/ThemedDialog';
import { syncSystemBars } from '../utils/SystemBars';

/**
 * 插件管理 › 插件详情：启用开关与简介、工具面板、插件声明的操作按钮、设置项（改完即存）、
 * 权限与签名、卸载。设置项按清单生成：选择项弹菜单，开关直接切，文字类点开就地编辑。
 */
@Entry
@Component
struct PluginDetailPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('pluginRegistryRevision') @Watch('loadData') pluginRegistryRevision: number = 1;

  @State pluginId: string = '';
  @State record: InstalledPluginRecord | null = null;
  @State loaded: boolean = false;
  @State formValues: Record<string, string | number | boolean> = {};
  @State secretSaved: Record<string, boolean> = {};
  @State editingKey: string = '';
  @State editingDraft: string = '';
  @State runningActionId: string = '';

  @State showToolPanelSheet: boolean = false;
  @State activePanelTitle: string = '';
  @State activePanelPath: string = '';
  @State activePanelInitJson: string = '{}';

  aboutToAppear(): void {
    AppPluginHost.install(getContext(this));
    this.syncBars();
    const params = router.getParams() as Record<string, Object> | undefined;
    this.pluginId = String(params?.['pluginId'] || '');
    this.loadData();
  }

  onPageShow(): void {
    this.syncBars();
  }

  onPageHide(): void {
    this.commitEditing();
  }

  private syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
  }

  private async loadData(): Promise<void> {
    try {
      await PluginRegistry.getInstance().ensureInitialized();
    } catch (_) {
    }
    const rec = PluginRegistry.getInstance().getPlugin(this.pluginId) || null;
    this.record = rec;
    this.loaded = true;
    if (!rec) return;
    this.formValues = PluginRegistry.getInstance().getSettings(this.pluginId);
    const saved: Record<string, boolean> = {};
    for (const f of rec.manifest.settings) {
      if (f.type === 'secret') {
        try {
          saved[f.key] = (await PluginEngineHost.port().getSecret(this.pluginId, f.key)).length > 0;
        } catch (_) {
          saved[f.key] = false;
        }
      }
    }
    this.secretSaved = saved;
  }

  // ---- 设置项 ----

  private valueText(field: PluginSettingField): string {
    if (field.type === 'secret') return this.secretSaved[field.key] ? '已保存' : '未填写';
    const value = this.formValues[field.key];
    if (field.type === 'select') {
      const opt = (field.options || []).find((o: PluginSettingOption): boolean => o.value === String(value));
      return opt ? opt.label : String(value ?? '');
    }
    const text = value === undefined || value === null ? '' : String(value);
    if (!text) return field.placeholder ? '未填写' : '';
    return text.length > 14 ? `${text.substring(0, 14)}…` : text;
  }

  private async saveValue(key: string, value: string | number | boolean): Promise<void> {
    const next: Record<string, string | number | boolean> = {};
    for (const k of Object.keys(this.formValues)) next[k] = this.formValues[k];
    next[key] = value;
    this.formValues = next;
    try {
      await PluginRegistry.getInstance().updateSettingValue(this.pluginId, key, value);
    } catch (e) {
      HdsFeedback.showToast(e instanceof Error ? e.message : '保存失败');
    }
  }

  private async pickSelect(field: PluginSettingField): Promise<void> {
    const options = field.options || [];
    if (options.length === 0) return;
    try {
      const buttons: promptAction.Button[] = options.map((o: PluginSettingOption): promptAction.Button => {
        const button: promptAction.Button = { text: o.label, color: ThemeRuntime.primaryTextColor(this.appDarkMode) };
        return button;
      });
      const res = await ThemedDialog.showDialog(this.getUIContext(), { title: field.label, buttons: buttons },
        this.appDarkMode);
      const opt = options[res.index];
      if (opt) await this.saveValue(field.key, opt.value);
    } catch (_) {
    }
  }

  private startEditing(field: PluginSettingField): void {
    this.commitEditing();
    if (this.editingKey === field.key) {
      this.editingKey = '';
      return;
    }
    this.editingKey = field.key;
    this.editingDraft = field.type === 'secret' ? '' : String(this.formValues[field.key] ?? '');
  }

  /** 文字类设置收起时保存；密钥留空表示保持原值。 */
  private commitEditing(): void {
    const key = this.editingKey;
    if (!key || !this.record) return;
    const field = this.record.manifest.settings.find((f: PluginSettingField): boolean => f.key === key);
    this.editingKey = '';
    if (!field) return;
    const draft = this.editingDraft;
    if (field.type === 'secret') {
      if (!draft) return;
      PluginEngineHost.port().setSecret(this.pluginId, key, draft).then(() => {
        const next: Record<string, boolean> = {};
        for (const k of Object.keys(this.secretSaved)) next[k] = this.secretSaved[k];
        next[key] = true;
        this.secretSaved = next;
      }).catch(() => HdsFeedback.showToast('保存失败'));
      return;
    }
    const value: string | number = field.type === 'number' ? (Number(draft) || 0) : draft;
    if (String(this.formValues[key] ?? '') === String(value)) return;
    this.saveValue(key, value);
  }

  // ---- 动作、面板、卸载 ----

  private async runAction(action: PluginSettingAction): Promise<void> {
    if (!this.record || this.runningActionId) return;
    if (!this.record.enabled) {
      HdsFeedback.showToast('先启用这个插件');
      return;
    }
    this.commitEditing();
    this.runningActionId = action.id;
    try {
      // 网页登录要等用户在浏览器里操作，放宽到 5 分钟。
      const wallTimeoutMs = this.record.manifest.permissions.includes('webview.verify') ? 300000 : undefined;
      const res = await PluginRegistry.getInstance().invokePlugin<Object | null>(
        this.pluginId, action.handler, { actionId: action.id }, { wallTimeoutMs });
      HdsFeedback.showToast(typeof res.data === 'string' && res.data.trim() ? res.data.trim() : `已执行：${action.label}`);
      this.loadData();
    } catch (e) {
      HdsFeedback.showToast(e instanceof Error ? e.message : '操作失败');
    } finally {
      this.runningActionId = '';
    }
  }

  private openTool(tool: PluginToolContribution): void {
    if (!this.record?.enabled) {
      HdsFeedback.showToast('先启用这个插件');
      return;
    }
    this.activePanelTitle = tool.title;
    this.activePanelPath = tool.panel;
    this.activePanelInitJson = JSON.stringify({ toolId: tool.id });
    this.showToolPanelSheet = true;
  }

  private setEnabled(isOn: boolean): void {
    if (!this.record || this.record.enabled === isOn) return;
    PluginRegistry.getInstance().setPluginEnabled(this.pluginId, isOn).then(() => this.loadData())
      .catch((e: Object) => {
        HdsFeedback.showToast(e instanceof Error ? e.message : '切换状态失败');
        this.loadData();
      });
  }

  private async confirmUninstall(): Promise<void> {
    const rec = this.record;
    if (!rec) return;
    try {
      const res = await ThemedDialog.showDialog(this.getUIContext(), {
        title: `卸载“${rec.manifest.name}”？`,
        message: '插件文件、设置和保存的令牌会一并删除，无法恢复。用到它音色的地方会换回默认音色。',
        buttons: [
          { text: '取消', color: ThemeRuntime.subTextColor(this.appDarkMode) },
          { text: '卸载', color: ThemeRuntime.dangerColor(this.appDarkMode) }
        ]
      }, this.appDarkMode);
      if (res.index !== 1) return;
      await PluginRegistry.getInstance().uninstallPlugin(rec.manifest.id);
      HdsFeedback.showToast(`已卸载 ${rec.manifest.name}`);
      router.back();
    } catch (e) {
      HdsFeedback.showToast(e instanceof Error ? e.message : '卸载失败');
    }
  }

  // ---- 界面 ----

  private iconExists(path: string): boolean {
    try {
      return !!path && fs.accessSync(path);
    } catch (_) {
      return false;
    }
  }

  @Builder
  pluginIcon(path: string, size: number) {
    if (this.iconExists(path)) {
      Image(fileUri.getUriFromPath(path))
        .width(size)
        .height(size)
        .objectFit(ImageFit.Cover)
        .borderRadius(size * 0.28)
    } else {
      Stack() {
        SymbolGlyph($r('sys.symbol.puzzle'))
          .fontSize(size * 0.5)
          .fontColor([Color.White])
      }
      .width(size)
      .height(size)
      .borderRadius(size * 0.28)
      .linearGradient({
        angle: 150,
        colors: [[ThemeRuntime.accentColor(this.appDarkMode), 0], [ThemeRuntime.buttonColor(this.appDarkMode), 1]]
      })
    }
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XL, bottom: AppSpacing.SM })
  }

  @Builder
  heroCard(rec: InstalledPluginRecord) {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.MD }) {
        this.pluginIcon(PluginCapabilities.iconPath(rec.installDir, rec.manifest), 56)
        Column({ space: 2 }) {
          Text(rec.manifest.name)
            .fontSize(AppFontSize.TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${rec.manifest.author || rec.manifest.id} · v${rec.manifest.version} · ${PluginCapabilities.runtimeLabel(rec.manifest.runtime)}`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        AdaptiveSwitch({
          isOn: rec.enabled,
          onChange: (isOn: boolean) => this.setEnabled(isOn)
        })
      }
      .width('100%')
      if (rec.manifest.description) {
        Text(rec.manifest.description)
          .fontSize(AppFontSize.BODY)
          .lineHeight(21)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .width('100%')
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM })
    .padding(AppSpacing.LG)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
  }

  @Builder
  toolRow(tool: PluginToolContribution) {
    Row({ space: AppSpacing.MD }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.square_grid_2x2')).fontSize(16).fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
      }
      .width(30)
      .height(30)
      .borderRadius(9)
      .backgroundColor(`#1A${ThemeRuntime.accentColor(this.appDarkMode).substring(1)}`)
      Column({ space: 2 }) {
        Text(tool.title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        if (tool.description) {
          Text(tool.description)
            .fontSize(AppFontSize.CAPTION)
            .lineHeight(18)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([ThemeRuntime.subTextColor(this.appDarkMode)])
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: 12, bottom: 12 })
    .onClick(() => this.openTool(tool))
  }

  @Builder
  actionButton(action: PluginSettingAction, wide: boolean) {
    Button({ type: ButtonType.Normal }) {
      Text(this.runningActionId === action.id ? `${action.label}…` : action.label)
        .fontSize(AppFontSize.BODY)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor(wide ? ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.appDarkMode)) :
          ThemeRuntime.accentColor(this.appDarkMode))
        .padding({ left: 8, right: 8 })
    }
    .width(wide ? '100%' : '48.5%')
    .height(44)
    .borderRadius(14)
    .margin({ bottom: 8 })
    .backgroundColor(wide ? ThemeRuntime.buttonColor(this.appDarkMode) :
      `#1A${ThemeRuntime.accentColor(this.appDarkMode).substring(1)}`)
    .opacity(this.runningActionId && this.runningActionId !== action.id ? 0.5 : 1)
    .onClick(() => this.runAction(action))
  }

  @Builder
  fieldRow(field: PluginSettingField, last: boolean) {
    Column() {
      Row({ space: AppSpacing.MD }) {
        Column({ space: 2 }) {
          Text(field.label)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          if (field.description) {
            Text(field.description)
              .fontSize(AppFontSize.CAPTION)
              .lineHeight(18)
              .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (field.type === 'boolean') {
          AdaptiveSwitch({
            isOn: this.formValues[field.key] === true,
            onChange: (v: boolean) => {
              if (v !== (this.formValues[field.key] === true)) this.saveValue(field.key, v);
            }
          })
        } else {
          Text(this.valueText(field))
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            .maxLines(1)
            .constraintSize({ maxWidth: 120 })
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          SymbolGlyph(field.type === 'select' || this.editingKey === field.key ?
            $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([ThemeRuntime.subTextColor(this.appDarkMode)])
        }
      }
      .width('100%')
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: 12, bottom: 12 })
      .onClick(() => {
        if (field.type === 'select') this.pickSelect(field);
        else if (field.type !== 'boolean') this.startEditing(field);
      })

      if (this.editingKey === field.key) {
        Column({ space: AppSpacing.SM }) {
          if (field.type === 'textarea') {
            TextArea({ placeholder: field.placeholder || '', text: this.editingDraft })
              .height(92)
              .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
              .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
              .onChange((v: string) => { this.editingDraft = v; })
          } else {
            TextInput({
              placeholder: field.type === 'secret' && this.secretSaved[field.key] ? '留空保持原值，输入新值覆盖' :
                (field.placeholder || ''),
              text: this.editingDraft
            })
              .type(field.type === 'secret' ? InputType.Password : (field.type === 'number' ? InputType.Number : InputType.Normal))
              .height(42)
              .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
              .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
              .onChange((v: string) => { this.editingDraft = v; })
              .onSubmit(() => this.commitEditing())
          }
          Button('完成')
            .height(36)
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
            .backgroundColor(`#1A${ThemeRuntime.accentColor(this.appDarkMode).substring(1)}`)
            .alignSelf(ItemAlign.End)
            .onClick(() => this.commitEditing())
        }
        .width('100%')
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG, bottom: 12 })
      }
      if (!last) {
        Divider().strokeWidth(0.5).color(ThemeRuntime.hairlineColor(this.appDarkMode)).margin({ left: AppSpacing.LG })
      }
    }
    .width('100%')
  }

  @Builder
  permissionRow(row: PluginPermissionRow) {
    Row({ space: AppSpacing.MD }) {
      Stack() {
        if (row.kind === 'network') {
          SymbolGlyph($r('sys.symbol.wifi')).fontSize(16).fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
        } else if (row.kind === 'storage') {
          SymbolGlyph($r('sys.symbol.key')).fontSize(16).fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
        } else if (row.kind === 'web') {
          SymbolGlyph($r('sys.symbol.lock_shield')).fontSize(16).fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
        } else {
          SymbolGlyph($r('sys.symbol.checkmark_shield')).fontSize(16).fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
        }
      }
      .width(30)
      .height(30)
      .borderRadius(9)
      .backgroundColor(`#1A${ThemeRuntime.accentColor(this.appDarkMode).substring(1)}`)
      Column({ space: 2 }) {
        Text(row.title)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        if (row.detail) {
          Text(row.detail)
            .fontSize(row.kind === 'network' ? 11 : AppFontSize.CAPTION)
            .lineHeight(row.kind === 'network' ? 17 : 18)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
            .wordBreak(WordBreak.BREAK_ALL)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: 12, bottom: 12 })
  }

  @Builder
  pageContent() {
    if (!this.record) {
      if (this.loaded) {
        Text('没有找到这个插件，可能已经卸载')
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .padding(AppSpacing.XL)
      }
    } else {
      this.heroCard(this.record)

      if ((this.record.manifest.contributes.tools || []).length > 0) {
        this.sectionTitle('工具')
        Column() {
          ForEach(this.record.manifest.contributes.tools || [], (tool: PluginToolContribution) => {
            this.toolRow(tool)
          }, (tool: PluginToolContribution) => tool.id)
        }
        .width('calc(100% - 24vp)')
        .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
        .borderRadius(ThemeRuntime.cardRadius())
        .clip(true)
        .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
      }

      if (this.record.manifest.actions.length > 0) {
        this.sectionTitle('操作')
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.record.manifest.actions, (action: PluginSettingAction, index: number) => {
            // 按钮数为奇数时，第一个占满一行作为主按钮。
            this.actionButton(action, index === 0 && this.record!.manifest.actions.length % 2 === 1)
          }, (action: PluginSettingAction) => action.id)
        }
        .width('calc(100% - 24vp)')
        .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
        .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.MD, bottom: 4 })
        .borderRadius(ThemeRuntime.cardRadius())
        .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
      }

      if (this.record.manifest.settings.length > 0) {
        this.sectionTitle('设置')
        Column() {
          ForEach(this.record.manifest.settings, (field: PluginSettingField, index: number) => {
            this.fieldRow(field, index === this.record!.manifest.settings.length - 1)
          }, (field: PluginSettingField) => field.key)
        }
        .width('calc(100% - 24vp)')
        .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
        .borderRadius(ThemeRuntime.cardRadius())
        .clip(true)
        .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
      }

      this.sectionTitle('权限与来源')
      Column() {
        ForEach(PluginCapabilities.permissions(this.record.manifest), (row: PluginPermissionRow) => {
          this.permissionRow(row)
          Divider().strokeWidth(0.5).color(ThemeRuntime.hairlineColor(this.appDarkMode)).margin({ left: AppSpacing.LG })
        }, (row: PluginPermissionRow) => `${row.kind}:${row.title}`)
        Row({ space: AppSpacing.MD }) {
          Column({ space: 2 }) {
            Text('签名')
              .fontSize(AppFontSize.BODY)
              .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
            Text(this.record.signer ? formatSignerFingerprint(this.record.signer) : this.record.manifest.id)
              .fontSize(11)
              .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
              .wordBreak(WordBreak.BREAK_ALL)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Row({ space: 4 }) {
            SymbolGlyph(this.record.signer ? $r('sys.symbol.checkmark_shield') : $r('sys.symbol.exclamationmark_shield_fill'))
              .fontSize(13)
              .fontColor([this.record.signer ? ThemeRuntime.successColor(this.appDarkMode) :
                ThemeRuntime.warningColor(this.appDarkMode)])
            Text(this.record.signer ? '已签名' : '未签名')
              .fontSize(12)
              .fontColor(this.record.signer ? ThemeRuntime.successColor(this.appDarkMode) :
                ThemeRuntime.warningColor(this.appDarkMode))
          }
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12)
          .backgroundColor(`#22${(this.record.signer ? ThemeRuntime.successColor(this.appDarkMode) :
            ThemeRuntime.warningColor(this.appDarkMode)).substring(1)}`)
        }
        .width('100%')
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: 12, bottom: 12 })
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))

      if (PluginCapabilities.unsupported(this.record.manifest).length > 0) {
        Text(`这个插件还包含本应用暂不支持的能力：${PluginCapabilities.unsupported(this.record.manifest).join('、')}，这部分不会生效。`)
          .fontSize(AppFontSize.CAPTION)
          .lineHeight(18)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .width('100%')
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM })
      }

      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(16)
            .fontColor([ThemeRuntime.dangerColor(this.appDarkMode)])
          Text('卸载插件')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
        }
      }
      .width('calc(100% - 24vp)')
      .height(50)
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.XL })
      .borderRadius(ThemeRuntime.cardRadius())
      .backgroundColor(`#1A${ThemeRuntime.dangerColor(this.appDarkMode).substring(1)}`)
      .onClick(() => this.confirmUninstall())
      Text('卸载后插件的数据和保存的令牌一起删除，用到它音色的地方会换回默认音色。')
        .fontSize(AppFontSize.CAPTION)
        .lineHeight(18)
        .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.XXL })
    }
  }

  @Builder
  toolPanelSheetContent() {
    Column() {
      Row() {
        Text(this.activePanelTitle || '插件面板')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          .layoutWeight(1)
        Button('关闭')
          .height(30)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showToolPanelSheet = false;
          })
      }
      .width('100%')
      .padding({ left: AppSpacing.LG, right: AppSpacing.MD, top: AppSpacing.SM, bottom: AppSpacing.SM })

      PluginSandboxWebView({
        pluginId: this.pluginId,
        panelPath: this.activePanelPath,
        initialDataJson: this.activePanelInitJson,
        darkMode: this.appDarkMode,
        onCloseRequest: () => {
          this.showToolPanelSheet = false;
        }
      })
        .layoutWeight(1)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
  }

  build() {
    Stack() {
      PageScaffold({
        title: '插件详情',
        content: () => {
          this.pageContent();
        }
      })
      Column()
        .width(1)
        .height(1)
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.showToolPanelSheet, this.toolPanelSheetContent(), {
          height: '82%',
          showClose: false,
          backgroundColor: ThemeRuntime.pageColor(this.appDarkMode)
        })
    }
    .width('100%')
    .height('100%')
  }
}
