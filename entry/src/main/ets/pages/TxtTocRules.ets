import { router } from '@kit.ArkUI';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingSwitchRow } from '../components/common/SettingRow';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { PopupMenuAction, PopupMenuHeader } from '../components/common/PopupMenuAction';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { TxtTocRuleSettings, TxtTocRuleStore } from '../utils/TxtTocRuleStore';
import { TxtTocRule, TxtTocRules } from '../core/book/TxtTocRules';

const TXT_TOC_RULE_IMPORT_LIMIT_BYTES = 2 * 1024 * 1024;

/** 设置 › 小说 › TXT 目录规则：内置规则开关、自定义规则、新导入 TXT 的默认规则、导入导出。 */
@Entry
@Component
struct TxtTocRulesPage {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @State settings: TxtTocRuleSettings = new TxtTocRuleSettings();
  @State rules: TxtTocRule[] = [];
  @State loaded: boolean = false;
  @State showMoreMenu: boolean = false;
  @State showDefaultMenu: boolean = false;
  private bookUrl: string = '';
  private loadGeneration: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    this.bookUrl = params && typeof params['bookUrl'] === 'string' ? params['bookUrl'] : '';
  }

  onPageShow(): void {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    syncSystemBars(context, this.darkMode);
    const token = ++this.loadGeneration;
    TxtTocRuleStore.load(context, true).then((settings: TxtTocRuleSettings): void => {
      if (token !== this.loadGeneration) return;
      this.applySettings(settings);
      this.loaded = true;
    });
  }

  onPageHide(): void {
    this.loadGeneration++;
    this.showMoreMenu = false;
    this.showDefaultMenu = false;
  }

  private applySettings(settings: TxtTocRuleSettings): void {
    this.settings = settings;
    this.rules = TxtTocRuleStore.allRules(settings);
  }

  private async save(next: TxtTocRuleSettings): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const previous = this.settings;
    this.applySettings(next);
    try {
      await TxtTocRuleStore.save(context, next);
    } catch (e) {
      console.warn('[TxtTocRules] 保存失败:', e);
      this.applySettings(previous);
      HdsFeedback.showToast('目录规则保存失败，请重试');
    }
  }

  private copySettings(): TxtTocRuleSettings {
    const next = new TxtTocRuleSettings();
    next.customRules = this.settings.customRules.map((rule: TxtTocRule): TxtTocRule => TxtTocRules.clone(rule));
    next.disabledBuiltins = this.settings.disabledBuiltins.slice();
    next.defaultRuleRef = this.settings.defaultRuleRef;
    return next;
  }

  private setBuiltinEnabled(rule: TxtTocRule, enabled: boolean): void {
    if (rule.id === TxtTocRules.AUTO_ID) return;
    const next = this.copySettings();
    next.disabledBuiltins = next.disabledBuiltins.filter((id: string): boolean => id !== rule.id);
    if (!enabled) next.disabledBuiltins.push(rule.id);
    this.save(next);
  }

  private setDefaultRule(ref: string): void {
    this.showDefaultMenu = false;
    const next = this.copySettings();
    next.defaultRuleRef = ref;
    this.save(next);
  }

  private defaultRuleLabel(): string {
    const resolved = TxtTocRuleStore.resolveIn(this.settings, this.settings.defaultRuleRef);
    return TxtTocRules.displayName(resolved.rule, resolved.wordsPerChapter);
  }

  private builtinRules(): TxtTocRule[] {
    return this.rules.filter((rule: TxtTocRule): boolean => rule.builtin);
  }

  private customRules(): TxtTocRule[] {
    return this.rules.filter((rule: TxtTocRule): boolean => !rule.builtin);
  }

  private openEditor(ruleId: string, copyFrom: string = ''): void {
    const params: Record<string, string> = {};
    params['ruleId'] = ruleId;
    params['copyFrom'] = copyFrom;
    params['bookUrl'] = this.bookUrl;
    router.pushUrl({ url: 'pages/TxtTocRuleEdit', params: params }).catch((e: Error): void => {
      console.warn('[TxtTocRules] 打开编辑页失败:', e);
    });
  }

  private async importFromFile(): Promise<void> {
    this.showMoreMenu = false;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    let file: fs.File | null = null;
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['JSON|.json', '文本|.txt'];
      const result: string[] = await new picker.DocumentViewPicker(context).select(options);
      if (!result || result.length === 0) return;
      const stat = await fs.stat(result[0]);
      if (stat.size > TXT_TOC_RULE_IMPORT_LIMIT_BYTES) throw new Error('文件过大');
      file = await fs.open(result[0], fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(Math.max(0, stat.size));
      await fs.read(file.fd, buffer, { offset: 0, length: stat.size });
      const text = util.TextDecoder.create('utf-8')
        .decodeWithStream(new Uint8Array(buffer), { stream: false }).replace(/^\uFEFF/, '');
      this.importJson(text);
    } catch (e) {
      console.warn('[TxtTocRules] 导入失败:', e);
      HdsFeedback.showToast(`导入失败：${(e as Error)?.message || '文件读不出规则'}`);
    } finally {
      if (file) await fs.close(file);
    }
  }

  private importJson(text: string): void {
    const parsed = JSON.parse(text) as Object;
    const entries: Object[] = Array.isArray(parsed) ? parsed as Object[] : [parsed];
    const next = this.copySettings();
    let added = 0;
    let skipped = 0;
    for (const entry of entries) {
      const rule = TxtTocRules.fromImport(entry as Record<string, Object>);
      if (!rule || TxtTocRules.patternError(rule.pattern)) {
        skipped++;
        continue;
      }
      const duplicate = next.customRules.some((item: TxtTocRule): boolean =>
        item.pattern === rule.pattern && item.name === rule.name);
      if (duplicate) {
        skipped++;
        continue;
      }
      next.customRules.push(rule);
      added++;
    }
    if (added === 0) {
      HdsFeedback.showToast(skipped > 0 ? '没有可导入的新规则' : '文件里没有目录规则');
      return;
    }
    this.save(next);
    HdsFeedback.showToast(skipped > 0 ? `已导入 ${added} 条，跳过 ${skipped} 条` : `已导入 ${added} 条目录规则`);
  }

  private async exportRules(): Promise<void> {
    this.showMoreMenu = false;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const rules = this.settings.customRules;
    if (rules.length === 0) {
      HdsFeedback.showToast('还没有自己的规则可导出');
      return;
    }
    let file: fs.File | null = null;
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = ['txt-toc-rules.json'];
      options.fileSuffixChoices = ['JSON 文件|.json'];
      const result = await new picker.DocumentViewPicker(context).save(options);
      if (!result || result.length === 0) return;
      const payload = rules.map((rule: TxtTocRule, index: number): Record<string, Object> =>
        TxtTocRules.toExport(rule, index + 1));
      const bytes = new util.TextEncoder().encodeInto(JSON.stringify(payload, null, 2));
      file = await fs.open(result[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, bytes.buffer, { offset: 0, length: bytes.byteLength });
      HdsFeedback.showToast(`已导出 ${rules.length} 条目录规则`);
    } catch (e) {
      console.warn('[TxtTocRules] 导出失败:', e);
      HdsFeedback.showToast('导出失败，请重试');
    } finally {
      if (file) await fs.close(file);
    }
  }

  @Builder
  sectionTitle(label: string) {
    Text(label)
      .fontSize(AppFontSize.BODY)
      .fontColor(ThemeRuntime.subTextColor(this.darkMode))
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  @Builder
  moreMenu() {
    Column() {
      PopupMenuAction($r('sys.symbol.square_and_arrow_down'), '从文件导入',
        ThemeRuntime.primaryTextColor(this.darkMode), (): void => {
          this.importFromFile();
        })
      PopupMenuAction($r('sys.symbol.doc_text'), '导出我的规则', ThemeRuntime.primaryTextColor(this.darkMode),
        (): void => {
          this.exportRules();
        })
    }
    .width(200)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  defaultMenu() {
    Column() {
      PopupMenuHeader('新导入 TXT 默认规则', ThemeRuntime.subTextColor(this.darkMode))
      ForEach(this.rules.filter((rule: TxtTocRule): boolean => rule.enabled), (rule: TxtTocRule) => {
        if (rule.kind === TxtTocRules.KIND_WORDS) {
          ForEach(TxtTocRules.WORD_OPTIONS, (words: number) => {
            PopupMenuAction(undefined, TxtTocRules.displayName(rule, words), ThemeRuntime.primaryTextColor(this.darkMode),
              (): void => this.setDefaultRule(TxtTocRules.ref(rule.id, words)))
          }, (words: number) => `${words}`)
        } else {
          PopupMenuAction(undefined, rule.name, ThemeRuntime.primaryTextColor(this.darkMode),
            (): void => this.setDefaultRule(TxtTocRules.ref(rule.id)))
        }
      }, (rule: TxtTocRule) => rule.id)
    }
    .width(240)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  pageActions() {
    Row({ space: AppSpacing.MD }) {
      ImmersiveHeaderAction({
        icon: $r('sys.symbol.plus'),
        accessibilityLabel: '新建目录规则',
        onTap: () => this.openEditor('')
      })
      ImmersiveHeaderAction({
        icon: $r('sys.symbol.more'),
        accessibilityLabel: '导入导出',
        onTap: () => {
          this.showMoreMenu = !this.showMoreMenu;
        }
      })
        .bindPopup(this.showMoreMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
          (): void => {
            this.moreMenu();
          }, Placement.BottomRight, this.darkMode, ThemeRuntime.accentColor(this.darkMode), () => {
            this.showMoreMenu = false;
          }))
    }
    .margin({ right: AppSpacing.XL })
  }

  @Builder
  pageContent() {
    if (this.loaded) {
      Column() {
        Column() {
          SettingNavRow({
            title: '新导入 TXT 默认规则',
            description: '已导入的书不受影响，可在书内单独切换',
            value: this.defaultRuleLabel(),
            showDivider: false,
            onTap: (): void => {
              this.showDefaultMenu = !this.showDefaultMenu;
            }
          })
        }
        .bindPopup(this.showDefaultMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
          (): void => {
            this.defaultMenu();
          }, Placement.Bottom, this.darkMode, ThemeRuntime.accentColor(this.darkMode), () => {
            this.showDefaultMenu = false;
          }))
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD })
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(ThemeRuntime.cardColor(this.darkMode))

      this.sectionTitle('内置规则 · 关掉的不会出现在书内列表，长按可复制为我的规则')
      Column() {
        ForEach(this.builtinRules(), (rule: TxtTocRule, index: number) => {
          Column() {
            SettingSwitchRow({
              title: rule.name,
              description: rule.desc,
              isOn: rule.enabled,
              switchEnabled: rule.id !== TxtTocRules.AUTO_ID,
              showDivider: index < this.builtinRules().length - 1,
              onChange: (checked: boolean): void => this.setBuiltinEnabled(rule, checked)
            })
          }
          .parallelGesture(LongPressGesture({ duration: 500 }).onAction(() => {
            if (rule.kind === TxtTocRules.KIND_WORDS) {
              HdsFeedback.showToast('按字数分章没有正则，不能复制');
              return;
            }
            this.openEditor('', rule.id);
          }))
        }, (rule: TxtTocRule) => `${rule.id}|${rule.enabled}`)
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(ThemeRuntime.cardColor(this.darkMode))

      this.sectionTitle('我的规则')
      Column() {
        ForEach(this.customRules(), (rule: TxtTocRule) => {
          SettingNavRow({
            title: rule.name,
            description: rule.pattern,
            value: rule.enabled ? '' : '已关闭',
            onTap: (): void => this.openEditor(rule.id)
          })
        }, (rule: TxtTocRule) => `${rule.id}|${rule.name}|${rule.pattern}|${rule.enabled}`)
        SettingNavRow({
          title: '新建规则',
          titleColor: ThemeRuntime.accentColor(this.darkMode),
          description: '写一条正则，匹配到的行就是章节标题',
          showDivider: false,
          onTap: (): void => this.openEditor('')
        })
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(ThemeRuntime.cardColor(this.darkMode))

      Text('目录规则只用于本地 TXT。在阅读页的目录或“更多”菜单里可以为每本书单独选规则，选的时候会先预览分章结果。导入兼容安卓阅读导出的 TXT 目录规则文件。')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.subTextColor(this.darkMode))
        .width('100%')
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.XXL })
    }
  }

  build() {
    Stack() {
      PageScaffold({
        title: 'TXT 目录规则',
        content: (): void => {
          this.pageContent();
        },
        actions: (): void => {
          this.pageActions();
        }
      })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
