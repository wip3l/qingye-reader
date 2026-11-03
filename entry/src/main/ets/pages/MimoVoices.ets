import { router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingSwitchRow } from '../components/common/SettingRow';
import { MimoVoiceSelectRow } from '../components/MimoVoiceSelectRow';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { HdsFeedback } from '../utils/HdsFeedback';
import { syncSystemBars } from '../utils/SystemBars';
import { MimoStore } from '../utils/mimo/MimoStore';
import { MimoPreviewSession } from '../utils/mimo/MimoPreviewSession';
import { MimoRole, MIMO_VOICES } from '../core/mimo/MimoPolicy';
import { MimoVoicePreset, MimoVoiceScheme, MimoVoiceChange, MimoVoicePolicy,
  MIMO_AGES, MIMO_AGE_LABELS, MIMO_GENDERS, MIMO_GENDER_LABELS } from '../core/mimo/MimoVoicePolicy';

class MimoVoicePageParams { screen: string = 'library'; book: string = ''; roleId: string = ''; }
class MimoPresetDataSource implements IDataSource {
  private items: MimoVoicePreset[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.items.length; }
  getData(index: number): MimoVoicePreset { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener);
  }
  reload(items: MimoVoicePreset[]): void { this.items = items; this.listeners.forEach((l: DataChangeListener): void => l.onDataReloaded()); }
}
const MIMO_PREVIEW_NAMES: string[] = ['旁白与对白', '儿童对白', '情绪变化', '自定义文字'];
const MIMO_PREVIEW_TEXTS: string[] = [
  '晚风穿过长街，她停下脚步，轻声说：“我们回家吧。”',
  '“妈妈，你看！那颗星星是不是在跟我眨眼睛呀？”小禾仰起头，认真地问。',
  '“别担心，我会回来的。”他停了一下，又轻声补充：“这一次，我说到做到。”'
];

/** Voice library, scheme and audition pages share the app's native settings scaffold and controls. */
@Entry
@Component
struct MimoVoicesPage {
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @State screen: string = 'library';
  @State presets: MimoVoicePreset[] = [];
  @State schemes: MimoVoiceScheme[] = [];
  @State activeScheme: string = '';
  @State assignmentEnabled: boolean = true;
  @State inherited: boolean = false;
  @State error: string = '';
  @State editName: string = '';
  @State editVoice: string = '白桦';
  @State editPrompt: string = '';
  @State editAge: string = 'unknown';
  @State editGender: string = 'unknown';
  @State roleLocked: boolean = true;
  @State rolePresetId: string = '';
  @State rolePresetName: string = '';
  @State roleVersion: number = 1;
  @State roleHasUpdate: boolean = false;
  @State roleEvidence: string = '';
  @State schemeIds: string[] = [];
  @State previewName: string = '';
  @State previewText: string = MIMO_PREVIEW_TEXTS[0];
  @State sampleName: string = MIMO_PREVIEW_NAMES[0];
  @State previewBusy: boolean = false;
  @State changes: MimoVoiceChange[] = [];
  private source: MimoPresetDataSource = new MimoPresetDataSource();
  private book: string = '';
  private roleId: string = '';
  private editId: string = '';
  private editRevision: number = 1;
  private dirty: boolean = false;
  private previewReturn: string = 'library';
  private previewPreset: MimoVoicePreset = new MimoVoicePreset();
  private selectedRolePreset: MimoVoicePreset = new MimoVoicePreset();
  private preview: MimoPreviewSession = new MimoPreviewSession();
  private serial: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as MimoVoicePageParams;
    this.book = params?.book || ''; this.roleId = params?.roleId || '';
    this.screen = ['library', 'schemes', 'default', 'role', 'changes'].includes(params?.screen) ? params.screen : 'library';
    this.refresh();
    try {
      if (this.screen === 'role') this.loadRole();
      if (this.screen === 'changes') this.changes = MimoStore.changes(this.book);
    } catch (error) { this.error = (error as Error).message; }
  }
  onPageShow(): void { syncSystemBars(getContext(this), this.dark, ThemeRuntime.pageColor(this.dark)); }
  onPageHide(): void { this.stopPreview(); }
  aboutToDisappear(): void { this.stopPreview(); this.preview.release(); }
  onBackPress(): boolean { this.back(); return true; }
  private refresh(): void {
    try {
      const library = MimoStore.library(); this.presets = library.presets; this.schemes = library.schemes;
      const cast = this.book ? MimoStore.cast(this.book) : null;
      this.activeScheme = cast ? MimoStore.schemeId(cast, library) : library.schemeId;
      this.assignmentEnabled = cast ? (cast.assignmentEnabled ?? library.assignmentEnabled) : library.assignmentEnabled;
      this.inherited = !!cast && !cast.schemeId;
      this.source.reload(this.presets); this.error = '';
    } catch (error) { this.error = (error as Error).message; }
  }
  private title(): string {
    if (this.screen === 'edit') return this.editId ? '编辑提示词' : '新增提示词';
    if (this.screen === 'schemeEdit') return this.editId ? '编辑音色方案' : '新建音色方案';
    if (this.screen === 'preview') return '试听';
    if (this.screen === 'role') return '人物声音';
    if (this.screen === 'changes') return '重新分配预览';
    return this.screen === 'schemes' ? '音色方案' : this.screen === 'default' ? '默认声音' : '音色与提示词';
  }
  private async back(): Promise<void> {
    this.stopPreview();
    if (this.screen === 'preview') { this.screen = this.previewReturn; return; }
    if (this.dirty) {
      if (!await this.confirm('放弃未保存的修改？', '', '放弃', true, '继续编辑')) return;
    }
    this.dirty = false;
    if (this.screen === 'edit') this.screen = 'library';
    else if (this.screen === 'schemeEdit') this.screen = 'schemes';
    else if (this.screen === 'changes') { this.changes = []; router.back(); }
    else router.back();
  }
  /** Dismissing a native dialog with Back is a cancellation, including rejected dialog promises. */
  private async confirm(title: string, message: string, action: string, danger: boolean = false,
    cancel: string = '取消'): Promise<boolean> {
    try {
      const answer = await this.getUIContext().getPromptAction().showDialog({ title, message,
        buttons: [{ text: cancel, color: ThemeRuntime.subTextColor(this.dark) },
          { text: action, color: danger ? ThemeRuntime.dangerColor(this.dark) : ThemeRuntime.accentColor(this.dark) }] });
      return answer.index === 1;
    } catch (_) { return false; }
  }
  private editPreset(preset?: MimoVoicePreset, duplicate: boolean = false): void {
    this.editId = duplicate ? '' : (preset?.id || ''); this.editRevision = preset?.revision || 1;
    this.editName = preset ? preset.name + (duplicate ? ' 副本' : '') : '';
    this.editVoice = preset?.voice || '白桦'; this.editPrompt = preset?.prompt || '';
    this.editAge = preset?.age || 'unknown'; this.editGender = preset?.gender || 'unknown';
    this.screen = 'edit'; this.dirty = duplicate;
  }
  private draft(): MimoVoicePreset {
    const preset = MimoVoicePolicy.preset(this.editId || 'user-' + Date.now(), this.editName.trim(),
      this.editVoice, this.editPrompt, this.editAge, this.editGender);
    preset.revision = this.editRevision; return preset;
  }
  private save(): void {
    try {
      if (this.screen === 'edit') { MimoStore.savePreset(this.draft()); this.screen = 'library'; }
      else if (this.screen === 'schemeEdit') {
        const library = MimoStore.library();
        if (!this.editName.trim()) throw new Error('请填写方案名称');
        const scheme = new MimoVoiceScheme(); scheme.id = this.editId || 'scheme-' + Date.now();
        scheme.name = this.editName.trim(); scheme.presetIds = this.schemeIds.slice();
        if (library.schemes.some((s: MimoVoiceScheme): boolean => s.id !== scheme.id && s.name === scheme.name)) throw new Error('已有同名方案');
        const index = library.schemes.findIndex((s: MimoVoiceScheme): boolean => s.id === scheme.id);
        if (index >= 0) library.schemes[index] = scheme; else library.schemes.push(scheme);
        MimoStore.saveLibrary(library); this.screen = 'schemes';
      } else if (this.screen === 'role') {
        const cast = MimoStore.cast(this.book), role = cast.roles.find((r: MimoRole): boolean => r.id === this.roleId);
        if (!role) throw new Error('人物档案不存在');
        role.age = this.editAge; role.gender = this.editGender; role.locked = this.roleLocked; role.manual = true;
        role.ageEvidence = '用户手动确认'; MimoVoicePolicy.bind(role, this.selectedRolePreset);
        MimoStore.saveCast(this.book, cast); this.dirty = false; router.back();
      }
      this.dirty = false; this.refresh(); HdsFeedback.showToast('已保存，已有绑定保持原版本，声音修改从下一段生效');
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }
  private async remove(preset: MimoVoicePreset): Promise<void> {
    if (!await this.confirm('删除“' + preset.name + '”？', '', '删除', true)) return;
    try { MimoStore.deletePreset(preset.id); this.refresh(); } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }
  private editScheme(scheme?: MimoVoiceScheme): void {
    this.editId = scheme?.id || ''; this.editName = scheme?.name || '';
    this.schemeIds = scheme?.presetIds.slice() || []; this.screen = 'schemeEdit'; this.dirty = false;
  }
  private async removeScheme(scheme: MimoVoiceScheme): Promise<void> {
    if (!await this.confirm('删除方案“' + scheme.name + '”？', '仅删除方案，保留音色预设和人物声音。', '删除', true)) return;
    try { MimoStore.deleteScheme(scheme.id); this.refresh(); }
    catch (error) { HdsFeedback.showToast((error as Error).message); }
  }
  private async activate(scheme: MimoVoiceScheme): Promise<void> {
    if (!await this.confirm('启用“' + scheme.name + '”？',
      '仅影响新人物分配，已有绑定保留。需要更新时，可在本书人物中预览重新分配。', '启用')) return;
    try {
      if (this.book) {
        const cast = MimoStore.cast(this.book); cast.schemeId = scheme.id; cast.assignmentEnabled = true;
        MimoStore.saveCast(this.book, cast);
      } else {
        const library = MimoStore.library(); library.schemeId = scheme.id; library.assignmentEnabled = true;
        MimoStore.saveLibrary(library);
      }
      this.refresh();
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }
  private toggleAssignment(flag: boolean): void {
    try {
      if (this.book) { const cast = MimoStore.cast(this.book); cast.assignmentEnabled = flag; MimoStore.saveCast(this.book, cast); }
      else { const library = MimoStore.library(); library.assignmentEnabled = flag; MimoStore.saveLibrary(library); }
      this.refresh();
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }
  private useDefault(preset: MimoVoicePreset): void {
    try { const library = MimoStore.library(); library.defaultPreset = MimoVoicePolicy.clone(preset); MimoStore.saveLibrary(library); router.back(); }
    catch (error) { HdsFeedback.showToast((error as Error).message); }
  }
  private loadRole(): void {
    const role = MimoStore.cast(this.book).roles.find((r: MimoRole): boolean => r.id === this.roleId);
    if (!role) { this.error = '人物档案不存在'; return; }
    this.editName = role.name; this.editAge = role.age || 'unknown'; this.editGender = role.gender || 'unknown';
    this.roleLocked = role.locked; this.roleEvidence = role.ageEvidence || '暂无可靠年龄依据，可手动纠正';
    this.chooseRolePreset(MimoVoicePolicy.rolePreset(role)); this.dirty = false;
  }
  private chooseRolePreset(preset: MimoVoicePreset): void {
    this.selectedRolePreset = MimoVoicePolicy.clone(preset); this.rolePresetId = preset.id; this.rolePresetName = preset.name;
    this.roleVersion = preset.revision;
    const latest = this.presets.find((p: MimoVoicePreset): boolean => p.id === preset.id);
    this.roleHasUpdate = !!latest && latest.revision !== preset.revision;
    this.dirty = true;
  }
  private matchRole(): void {
    try {
    const role = new MimoRole(); role.id = this.roleId; role.age = this.editAge; role.gender = this.editGender;
    const cast = MimoStore.cast(this.book), library = MimoStore.library();
    const result = MimoVoicePolicy.match(role, library, MimoStore.schemeId(cast, library),
      cast.assignmentEnabled ?? library.assignmentEnabled);
    this.chooseRolePreset(result.preset); HdsFeedback.showToast(result.reason);
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }
  private openPreview(preset: MimoVoicePreset): void {
    this.stopPreview(); this.previewReturn = this.screen; this.previewPreset = MimoVoicePolicy.clone(preset);
    this.previewName = preset.name || '草稿'; this.screen = 'preview';
  }
  private stopPreview(): void { this.serial++; this.preview.stop(); this.previewBusy = false; }
  private async play(original: boolean = false): Promise<void> {
    this.stopPreview(); const serial = this.serial; this.previewBusy = true;
    try { await this.preview.play(this.previewPreset, this.previewText, original); }
    catch (error) { if (serial === this.serial) HdsFeedback.showToast((error as Error).message); }
    finally { if (serial === this.serial) this.previewBusy = false; }
  }
  private async reassign(): Promise<void> {
    try {
      if (!await this.confirm('应用预览中的更新？', '跳过已锁定和手动指定的人物，从下一段生效。', '应用')) return;
      MimoStore.applyChanges(this.book, this.changes); router.back();
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }
  build() {
    Stack() {
      PageScaffold({ title: this.title(), scrollable: !['library', 'default', 'schemeEdit'].includes(this.screen),
        onBack: () => { this.back(); }, actions: () => { this.actions(); }, content: () => { this.content(); } })
    }.width('100%').height('100%')
  }
  @Builder
  actions() {
    if (this.screen === 'library' || this.screen === 'schemes') {
      Button('新增').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.accentColor(this.dark)).backgroundColor(Color.Transparent)
        .onClick(() => { if (this.screen === 'library') this.editPreset(); else this.editScheme(); })
    } else if (['edit', 'schemeEdit', 'role'].includes(this.screen)) {
      Button('保存').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.accentColor(this.dark)).backgroundColor(Color.Transparent)
        .onClick(() => this.save())
    }
  }
  @Builder
  hint(text: string) {
    Text(text).fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
  }
  @Builder
  content() {
    if (['library', 'default', 'schemeEdit'].includes(this.screen)) {
      this.presetList()
    } else {
      Column({ space: AppSpacing.LG }) {
        if (this.error) { this.hint(this.error) }
        if (this.screen === 'edit') { this.presetForm() }
        else if (this.screen === 'schemes') { this.schemeList() }
        else if (this.screen === 'role') { this.roleForm() }
        else if (this.screen === 'preview') { this.previewForm() }
        else if (this.screen === 'changes') { this.changesForm() }
      }.width('100%').constraintSize({ maxWidth: 760 })
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
    }
  }
  @Builder
  presetList() {
    Column({ space: AppSpacing.MD }) {
      if (this.error) { this.hint(this.error) }
      if (this.screen === 'schemeEdit') {
        TextInput({ text: this.editName, placeholder: '方案名称' }).maxLength(30)
          .backgroundColor(ThemeRuntime.inputColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
          .onChange((text: string) => { if (text !== this.editName) { this.editName = text; this.dirty = true; } })
      }
      this.hint(this.screen === 'library' ? '预设保存到本地，加入方案后才参与自动分配。' :
        this.screen === 'default' ? '单音色朗读和未匹配人物使用，已有角色绑定保留。' : '只勾选少量候选，多个人物可以共享同一声音。')
      List({ space: AppSpacing.MD }) {
        LazyForEach(this.source, (preset: MimoVoicePreset) => {
          ListItem() {
            if (this.screen === 'schemeEdit') {
              Column() {
                SettingSwitchRow({ title: preset.name, description: MimoVoicePolicy.ageLabel(preset.age) + ' · ' + preset.voice,
                  isOn: this.schemeIds.includes(preset.id), showDivider: false,
                  onChange: (flag: boolean) => {
                    this.schemeIds = flag ? this.schemeIds.concat([preset.id]) : this.schemeIds.filter((id: string): boolean => id !== preset.id);
                    this.dirty = true;
                  } })
              }.backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
            } else if (this.screen === 'default') {
              Column() { SettingNavRow({ title: preset.name, value: preset.voice, showDivider: false, onTap: () => this.useDefault(preset) }) }
                .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
            } else { this.presetCard(preset) }
          }
        }, (preset: MimoVoicePreset): string => preset.id + ':' + preset.revision)
      }.width('100%').layoutWeight(1).cachedCount(3)
    }.height('100%').width('100%').constraintSize({ maxWidth: 760 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.XL })
  }
  @Builder
  presetCard(preset: MimoVoicePreset) {
    Column({ space: AppSpacing.MD }) {
      Text(preset.name).fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium)
        .fontColor(ThemeRuntime.primaryTextColor(this.dark)).width('100%')
      this.hint(preset.voice + ' · ' + MimoVoicePolicy.ageLabel(preset.age) + ' / ' + MimoVoicePolicy.genderLabel(preset.gender))
      Text(preset.prompt || '无额外提示词').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.dark))
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      Row({ space: AppSpacing.SM }) {
        Button('试听').fontSize(AppFontSize.CAPTION).onClick(() => this.openPreview(preset))
          .backgroundColor(ThemeRuntime.softFillColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
        Button('编辑').fontSize(AppFontSize.CAPTION).onClick(() => this.editPreset(preset))
          .backgroundColor(ThemeRuntime.softFillColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
        Button('复制').fontSize(AppFontSize.CAPTION).onClick(() => this.editPreset(preset, true))
          .backgroundColor(ThemeRuntime.softFillColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
        Button('删除').fontSize(AppFontSize.CAPTION).onClick(() => this.remove(preset))
          .backgroundColor(Color.Transparent).fontColor(ThemeRuntime.dangerColor(this.dark))
      }.width('100%')
    }.padding(AppSpacing.XL).width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
  }
  @Builder
  presetForm() {
    Column({ space: AppSpacing.MD }) {
      TextInput({ text: this.editName, placeholder: '预设名称' }).maxLength(30)
        .backgroundColor(ThemeRuntime.inputColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
        .onChange((text: string) => { if (text !== this.editName) { this.editName = text; this.dirty = true; } })
      MimoVoiceSelectRow({ title: '基础音色', choices: MIMO_VOICES, selection: this.editVoice,
        onSelect: (i: number) => { this.editVoice = MIMO_VOICES[i]; this.dirty = true; } })
      MimoVoiceSelectRow({ title: '适用年龄', choices: MIMO_AGE_LABELS, selection: MimoVoicePolicy.ageLabel(this.editAge),
        onSelect: (i: number) => { this.editAge = MIMO_AGES[i]; this.dirty = true; } })
      MimoVoiceSelectRow({ title: '适用性别', choices: MIMO_GENDER_LABELS, selection: MimoVoicePolicy.genderLabel(this.editGender),
        onSelect: (i: number) => { this.editGender = MIMO_GENDERS[i]; this.dirty = true; } })
      TextArea({ text: this.editPrompt, placeholder: '描述声音与表达习惯，不放入待朗读正文' }).height(180).maxLength(1200)
        .fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.primaryTextColor(this.dark)).backgroundColor(ThemeRuntime.inputColor(this.dark))
        .onChange((text: string) => { if (text !== this.editPrompt) { this.editPrompt = text; this.dirty = true; } })
      this.hint('最多 1200 字。年龄标签用于匹配，儿童演绎效果需试听确认。朗读倍速仍由播放器统一管理。')
      Button('用草稿试听').width('100%').fontSize(AppFontSize.BODY).backgroundColor(ThemeRuntime.softFillColor(this.dark))
        .fontColor(ThemeRuntime.primaryTextColor(this.dark)).onClick(() => this.openPreview(this.draft()))
    }.width('100%').padding(AppSpacing.XL).backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
  }
  @Builder
  schemeList() {
    Column() {
      SettingSwitchRow({ title: '使用方案自动分配', description: '关闭后新人物使用旁白，已有绑定保留',
        isOn: this.assignmentEnabled, showDivider: false, onChange: (flag: boolean) => this.toggleAssignment(flag) })
    }.backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
    this.hint(this.book ? (this.inherited ? '本书当前继承默认方案。' : '本书使用独立方案。') : '默认方案供未单独设置的书籍使用。')
    ForEach(this.schemes, (scheme: MimoVoiceScheme) => {
      Column({ space: AppSpacing.MD }) {
        Text(scheme.name + (this.activeScheme === scheme.id ? ' · 当前启用' : '')).fontSize(AppFontSize.BODY_LARGE)
          .fontColor(ThemeRuntime.primaryTextColor(this.dark)).width('100%')
        this.hint(scheme.presetIds.map((id: string): string => this.presets.find((p: MimoVoicePreset): boolean => p.id === id)?.name || '').join(' · ') || '没有候选，新人物使用旁白')
        Row({ space: AppSpacing.MD }) {
          Button('编辑候选').fontSize(AppFontSize.BODY).backgroundColor(ThemeRuntime.softFillColor(this.dark))
            .fontColor(ThemeRuntime.primaryTextColor(this.dark)).onClick(() => this.editScheme(scheme))
          Button(this.activeScheme === scheme.id ? '正在使用' : '启用方案').fontSize(AppFontSize.BODY)
            .enabled(this.activeScheme !== scheme.id).backgroundColor(ThemeRuntime.buttonColor(this.dark))
            .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.dark))).onClick(() => this.activate(scheme))
          Button('删除').fontSize(AppFontSize.CAPTION).backgroundColor(Color.Transparent)
            .fontColor(ThemeRuntime.dangerColor(this.dark)).onClick(() => this.removeScheme(scheme))
        }
      }.width('100%').padding(AppSpacing.XL).backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
    }, (scheme: MimoVoiceScheme): string => scheme.id + scheme.presetIds.join(','))
    if (this.book && !this.inherited) {
      Button('恢复跟随默认方案').fontSize(AppFontSize.BODY).backgroundColor(Color.Transparent)
        .fontColor(ThemeRuntime.accentColor(this.dark)).onClick(() => {
          const cast = MimoStore.cast(this.book); cast.schemeId = ''; cast.assignmentEnabled = undefined;
          MimoStore.saveCast(this.book, cast); this.refresh();
        })
    }
  }
  @Builder
  roleForm() {
    Column() {
      MimoVoiceSelectRow({ title: '年龄段', choices: MIMO_AGE_LABELS, selection: MimoVoicePolicy.ageLabel(this.editAge),
        onSelect: (i: number) => { this.editAge = MIMO_AGES[i]; this.dirty = true; } })
      MimoVoiceSelectRow({ title: '性别', choices: MIMO_GENDER_LABELS, selection: MimoVoicePolicy.genderLabel(this.editGender),
        onSelect: (i: number) => { this.editGender = MIMO_GENDERS[i]; this.dirty = true; } })
      MimoVoiceSelectRow({ title: '人物音色', choices: this.presets.map((p: MimoVoicePreset): string => p.name), selection: this.rolePresetName,
        onSelect: (i: number) => this.chooseRolePreset(this.presets[i]) })
      SettingSwitchRow({ title: '锁定人物声音', description: '重新分配时跳过，手动设置始终保留',
        isOn: this.roleLocked, showDivider: false, onChange: (flag: boolean) => { this.roleLocked = flag; this.dirty = true; } })
    }.backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
    this.hint(this.editName + ' · ' + this.roleEvidence)
    this.hint('当前绑定使用第 ' + this.roleVersion + ' 版提示词；修改预设不会自动改变已有绑定。')
    if (this.roleHasUpdate) {
      Button('使用该预设最新版本').fontSize(AppFontSize.BODY).width('100%')
        .backgroundColor(ThemeRuntime.softFillColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
        .onClick(() => {
          const latest = this.presets.find((p: MimoVoicePreset): boolean => p.id === this.rolePresetId);
          if (latest) this.chooseRolePreset(latest);
        })
    }
    Button('按当前方案匹配一次').fontSize(AppFontSize.BODY).width('100%').backgroundColor(ThemeRuntime.softFillColor(this.dark))
      .fontColor(ThemeRuntime.primaryTextColor(this.dark)).onClick(() => this.matchRole())
    Button('试听当前声音').fontSize(AppFontSize.BODY).width('100%').backgroundColor(ThemeRuntime.softFillColor(this.dark))
      .fontColor(ThemeRuntime.primaryTextColor(this.dark)).onClick(() => this.openPreview(this.selectedRolePreset))
  }
  @Builder
  previewForm() {
    Column({ space: AppSpacing.LG }) {
      Text(this.previewName + ' · ' + this.previewPreset.voice).fontSize(AppFontSize.BODY_LARGE)
        .fontColor(ThemeRuntime.primaryTextColor(this.dark)).width('100%')
      MimoVoiceSelectRow({ title: '示例文字', choices: MIMO_PREVIEW_NAMES, selection: this.sampleName, onSelect: (i: number) => {
        this.stopPreview(); this.sampleName = MIMO_PREVIEW_NAMES[i]; if (i < 3) this.previewText = MIMO_PREVIEW_TEXTS[i];
      } })
      TextArea({ text: this.previewText, placeholder: '请输入试听文字' }).height(140).maxLength(300)
        .fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.primaryTextColor(this.dark)).backgroundColor(ThemeRuntime.inputColor(this.dark))
        .onChange((text: string) => {
          if (text !== this.previewText) { this.stopPreview(); this.previewText = text; this.sampleName = '自定义文字'; }
        })
      this.hint('只合成以上短文。试听会使用 MiMo 服务，已有听书会暂停。')
      Row({ space: AppSpacing.MD }) {
        Button(this.previewBusy ? '重新试听' : '开始试听').fontSize(AppFontSize.BODY).backgroundColor(ThemeRuntime.buttonColor(this.dark))
          .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.dark))).onClick(() => this.play())
        Button('原声对比').fontSize(AppFontSize.BODY).backgroundColor(ThemeRuntime.softFillColor(this.dark))
          .fontColor(ThemeRuntime.primaryTextColor(this.dark)).onClick(() => this.play(true))
        Button('停止').fontSize(AppFontSize.BODY).enabled(this.previewBusy).backgroundColor(ThemeRuntime.softFillColor(this.dark))
          .fontColor(ThemeRuntime.primaryTextColor(this.dark)).onClick(() => this.stopPreview())
      }
    }.padding(AppSpacing.XL).width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
  }
  @Builder
  changesForm() {
    this.hint('只更新未锁定、未手动指定的人物。确认后从下一段生效。')
    ForEach(this.changes, (change: MimoVoiceChange) => {
      Column({ space: AppSpacing.SM }) {
        Text(change.roleName).fontSize(AppFontSize.BODY_LARGE).fontColor(ThemeRuntime.primaryTextColor(this.dark)).width('100%')
        this.hint(change.before + ' → ' + change.preset.name)
        this.hint(change.reason)
      }.padding(AppSpacing.XL).width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
    }, (change: MimoVoiceChange): string => change.roleId)
    Button('应用预览中的更新').width('100%').fontSize(AppFontSize.BODY).backgroundColor(ThemeRuntime.buttonColor(this.dark))
      .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.dark))).onClick(() => this.reassign())
  }
}
