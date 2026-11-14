import { router, SymbolGlyphModifier } from '@kit.ArkUI';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingSwitchRow } from '../components/common/SettingRow';
import { MimoVoiceSelectRow } from '../components/MimoVoiceSelectRow';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ListDissolve } from '../utils/ListDissolve';
import { DeleteParticleBurst, DeleteParticleLayer } from '../components/common/DeleteParticles';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { PopupMenuAction } from '../components/common/PopupMenuAction';
import { ImmersiveMaterialSurface } from '../components/ImmersiveMaterialSurface';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
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
  /** 删掉一个预设，走 onDataDelete 让 List 播补位动画。 */
  remove(id: string): void {
    const index = this.items.findIndex((item: MimoVoicePreset): boolean => item.id === id);
    if (index < 0) return;
    this.items = this.items.filter((item: MimoVoicePreset): boolean => item.id !== id);
    this.listeners.forEach((l: DataChangeListener): void => l.onDataDelete(index));
  }
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
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('navBarHeight') navBarHeight: number = 0;
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
  @State disabledIds: string[] = [];
  @State defaultPresetId: string = '';
  @State showPresetMenu: boolean = false;
  @State actionPresetId: string = '';
  @State disabledSchemeIds: string[] = [];
  @State showSchemeMenu: boolean = false;
  @State actionSchemeId: string = '';
  @State menuX: number = 16;
  @State menuY: number = 0;
  private pageX: number = 0;
  private pageY: number = 0;
  private source: MimoPresetDataSource = new MimoPresetDataSource();
  /** 正在消散的预设或方案 id，见 ListDissolve。 */
  @State dissolvingIds: string[] = [];
  @State deleteParticleBursts: DeleteParticleBurst[] = [];
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
      this.disabledIds = library.disabledPresetIds; this.defaultPresetId = library.defaultPreset.id;
      this.disabledSchemeIds = library.disabledSchemeIds;
      const cast = this.book ? MimoStore.cast(this.book) : null;
      this.activeScheme = cast ? MimoStore.schemeId(cast, library) : library.schemeId;
      this.assignmentEnabled = cast ? (cast.assignmentEnabled ?? library.assignmentEnabled) : library.assignmentEnabled;
      this.inherited = !!cast && !cast.schemeId;
      // Disabled presets leave the default-voice chooser but stay manageable in the library and schemes.
      this.source.reload(this.screen === 'default' ?
        this.presets.filter((p: MimoVoicePreset): boolean => this.presetEnabled(p)) : this.presets);
      this.error = '';
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
  private presetEnabled(preset: MimoVoicePreset): boolean { return !this.disabledIds.includes(preset.id); }
  private togglePreset(preset: MimoVoicePreset): void {
    const enabled = !this.presetEnabled(preset);
    try {
      MimoStore.setPresetEnabled(preset.id, enabled); this.refresh();
      HdsFeedback.showToast(enabled ? '已启用“' + preset.name + '”' : '已禁用，不再出现在选择列表和自动分配中，已有绑定保留');
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }
  private openPresetMenu(preset: MimoVoicePreset, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) { this.menuX = finger.globalX - this.pageX; this.menuY = finger.globalY - this.pageY; }
    this.actionPresetId = preset.id; this.showPresetMenu = true;
  }
  /** Menu actions close the popup first and act on the preset that was long-pressed. */
  private presetAction(action: (preset: MimoVoicePreset) => void): void {
    const preset = this.presets.find((p: MimoVoicePreset): boolean => p.id === this.actionPresetId);
    this.showPresetMenu = false;
    if (preset) action(preset);
  }
  private rolePresets(): MimoVoicePreset[] {
    return this.presets.filter((p: MimoVoicePreset): boolean => this.presetEnabled(p) || p.id === this.rolePresetId);
  }
  private async remove(preset: MimoVoicePreset): Promise<void> {
    if (!await this.confirm('删除“' + preset.name + '”？', '', '删除', true)) return;
    try { MimoStore.deletePreset(preset.id); } catch (error) { HdsFeedback.showToast((error as Error).message); return; }
    await this.dissolveMimo(preset.id, () => this.source.remove(preset.id));
  }

  mimoCardElementId(id: string): string { return `mimo_card_${encodeURIComponent(id)}`; }

  isMimoDissolving(id: string): boolean {
    return this.dissolvingIds.length > 0 && this.dissolvingIds.indexOf(id) >= 0;
  }

  /** 从确认框里删除：等它退场后这张卡片消散，播完在补位动画里执行 remove，补位结束再整体刷新。 */
  private async dissolveMimo(id: string, remove: () => void): Promise<void> {
    const keys = [id];
    await ListDissolve.fadeOut(this.getUIContext(), keys, (key: string) => {
      this.dissolvingIds = [...this.dissolvingIds, key];
    }, ListDissolve.particles('mimo_voices_root',
      [ThemeRuntime.accentColor(this.dark), ThemeRuntime.primaryTextColor(this.dark), ThemeRuntime.subTextColor(this.dark)],
      (key: string): string => this.mimoCardElementId(key), (): DeleteParticleBurst[] => this.deleteParticleBursts,
      (bursts: DeleteParticleBurst[]): void => { this.deleteParticleBursts = bursts; }), ListDissolve.AFTER_DIALOG_MS);
    ListDissolve.commit(this.getUIContext(), remove, () => {
      this.dissolvingIds = ListDissolve.without(this.dissolvingIds, keys);
      this.refresh();
    });
  }
  private editScheme(scheme?: MimoVoiceScheme): void {
    this.editId = scheme?.id || ''; this.editName = scheme?.name || '';
    this.schemeIds = scheme?.presetIds.slice() || []; this.screen = 'schemeEdit'; this.dirty = false;
  }
  private async removeScheme(scheme: MimoVoiceScheme): Promise<void> {
    if (!await this.confirm('删除方案“' + scheme.name + '”？', '仅删除方案，保留音色预设和人物声音。', '删除', true)) return;
    try { MimoStore.deleteScheme(scheme.id); }
    catch (error) { HdsFeedback.showToast((error as Error).message); return; }
    await this.dissolveMimo(scheme.id, () => {
      this.schemes = this.schemes.filter((item: MimoVoiceScheme): boolean => item.id !== scheme.id);
    });
  }
  private schemeEnabled(scheme: MimoVoiceScheme): boolean { return !this.disabledSchemeIds.includes(scheme.id); }
  private toggleScheme(scheme: MimoVoiceScheme): void {
    const enabled = !this.schemeEnabled(scheme);
    try {
      MimoStore.setSchemeEnabled(scheme.id, enabled); this.refresh();
      HdsFeedback.showToast(enabled ? '已启用“' + scheme.name + '”' : '已禁用，暂时不能设为使用中的方案');
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }
  private openSchemeMenu(scheme: MimoVoiceScheme, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) { this.menuX = finger.globalX - this.pageX; this.menuY = finger.globalY - this.pageY; }
    this.actionSchemeId = scheme.id; this.showSchemeMenu = true;
  }
  private schemeAction(action: (scheme: MimoVoiceScheme) => void): void {
    const scheme = this.schemes.find((item: MimoVoiceScheme): boolean => item.id === this.actionSchemeId);
    this.showSchemeMenu = false;
    if (scheme) action(scheme);
  }
  private schemeCandidates(scheme: MimoVoiceScheme): string {
    return scheme.presetIds.map((id: string): string => this.presets.find((p: MimoVoicePreset): boolean => p.id === id)?.name || '')
      .filter((name: string): boolean => !!name).join(' · ');
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
    Stack({ alignContent: Alignment.BottomEnd }) {
      PageScaffold({ title: this.title(), scrollable: !['library', 'default', 'schemeEdit', 'schemes'].includes(this.screen),
        onBack: () => { this.back(); }, actions: () => { this.actions(); }, content: () => { this.content(); } })
      if (this.screen === 'library') { this.addButton('新增提示词', () => this.editPreset()) }
      else if (this.screen === 'schemes') { this.addButton('新建音色方案', () => this.editScheme()) }
      Column().width(1).height(1).position({ x: this.menuX, y: this.menuY }).hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showPresetMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.presetMenu()
        }, Placement.BottomLeft, this.dark, ThemeRuntime.accentColor(this.dark), () => { this.showPresetMenu = false; }))
      Column().width(1).height(1).position({ x: this.menuX, y: this.menuY }).hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showSchemeMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.schemeMenu()
        }, Placement.BottomLeft, this.dark, ThemeRuntime.accentColor(this.dark), () => { this.showSchemeMenu = false; }))
      if (this.deleteParticleBursts.length > 0) {
        DeleteParticleLayer({ bursts: this.deleteParticleBursts })
      }
    }.id('mimo_voices_root').width('100%').height('100%')
    .onAreaChange((_old: Area, area: Area) => {
      this.pageX = Number(area.globalPosition.x) || 0; this.pageY = Number(area.globalPosition.y) || 0;
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
  @Builder
  actions() {
    if (['edit', 'schemeEdit', 'role'].includes(this.screen)) {
      ImmersiveHeaderAction({ label: '保存', tint: ThemeRuntime.accentColor(this.dark), onTap: () => this.save() })
        .margin({ right: AppSpacing.XL })
    }
  }
  /** Same floating add button as the custom voice manager. */
  @Builder
  addButton(label: string, action: () => void) {
    Stack() {
      ImmersiveMaterialSurface({ surfaceWidth: 52, surfaceHeight: 52, darkMode: this.dark,
        fallbackColor: ThemeRuntime.cardColor(this.dark), glowColor: `#40${ThemeRuntime.accentColor(this.dark).substring(1)}` }) {
        SymbolGlyph($r('sys.symbol.plus')).fontSize(25).fontColor([ThemeRuntime.accentColor(this.dark)])
      }
    }
    .width(52).height(52)
    .margin({ right: AppSpacing.XXL, bottom: this.navBarHeight + 22 })
    .accessibilityText(label).accessibilityRole(AccessibilityRoleType.BUTTON)
    .onClick(action)
  }
  @Builder
  hint(text: string) {
    Text(text).fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
  }
  @Builder
  content() {
    if (['library', 'default', 'schemeEdit'].includes(this.screen)) {
      this.presetList()
    } else if (this.screen === 'schemes') {
      this.schemeList()
    } else {
      Column({ space: AppSpacing.LG }) {
        if (this.error) { this.hint(this.error) }
        if (this.screen === 'edit') { this.presetForm() }
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
      this.hint(this.screen === 'library' ? '加入方案后才参与自动分配。左滑可禁用或删除，长按查看全部操作。' :
        this.screen === 'default' ? '单音色朗读和未匹配人物使用，已有角色绑定保留。' : '只勾选少量候选，多个人物可以共享同一声音。')
      List({ space: AppSpacing.MD }) {
        LazyForEach(this.source, (preset: MimoVoicePreset) => {
          // HdsListItem 必须直接挂在 List 下，侧滑才不被包装节点阻断。
          if (this.screen === 'library' && deviceInfo.sdkApiVersion >= 26) {
            HdsListItem({ customItemBuilder: (): void => { this.presetCard(preset); },
              swipeActionOptions: this.presetSwipeActions(preset) })
          } else {
            ListItem() {
              if (this.screen === 'schemeEdit') {
                Column() {
                  SettingSwitchRow({ title: preset.name, description: MimoVoicePolicy.ageLabel(preset.age) + ' · ' + preset.voice +
                    (this.presetEnabled(preset) ? '' : ' · 已禁用，不参与分配'),
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
            .borderRadius(ThemeRuntime.mediumRadius()).clip(true)
            .swipeAction(this.screen === 'library' ? {
              end: { builder: (): void => { this.presetFallbackSwipeActions(preset); } }, edgeEffect: SwipeEdgeEffect.Spring
            } : {})
          }
        }, (preset: MimoVoicePreset): string => preset.id + ':' + preset.revision + ':' + this.presetEnabled(preset) +
          ':' + (this.defaultPresetId === preset.id) + ':' + this.presetSchemeCount(preset))
        // 右下角悬浮新增按钮（52 高，底边距 navBarHeight+22）要完整让出最后一张卡片。
        if (this.screen === 'library') {
          ListItem() { Row().height(this.navBarHeight + 88).hitTestBehavior(HitTestMode.None) }
        }
      }.width('100%').layoutWeight(1).cachedCount(3)
      .scrollBar(BarState.Off)
    }.height('100%').width('100%').constraintSize({ maxWidth: 760 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG,
      bottom: this.screen === 'library' ? 0 : AppSpacing.XL })
  }
  /** Same layout as the book source list: bold name line, wrapping metadata, one-line detail. */
  @Builder
  presetCard(preset: MimoVoicePreset) {
    Column({ space: AppSpacing.XS }) {
      Text(preset.name).fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(this.dark)).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        this.presetMeta(preset.voice, ThemeRuntime.subTextColor(this.dark))
        this.presetMeta(MimoVoicePolicy.ageLabel(preset.age) + ' / ' + MimoVoicePolicy.genderLabel(preset.gender),
          ThemeRuntime.subTextColor(this.dark))
        if (this.defaultPresetId === preset.id) { this.presetMeta('默认声音', ThemeRuntime.accentColor(this.dark)) }
        if (this.presetSchemeCount(preset) > 0) {
          this.presetMeta(this.presetSchemeCount(preset) + ' 个方案', ThemeRuntime.subTextColor(this.dark))
        }
        if (!this.presetEnabled(preset)) { this.presetMeta('已禁用', ThemeRuntime.dangerColor(this.dark)) }
      }.width('100%')
      Text(preset.prompt || '无额外提示词').fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
    }
    .alignItems(HorizontalAlign.Start).width('100%').padding(AppSpacing.LG)
    .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.mediumRadius())
    .opacity(this.isMimoDissolving(preset.id) ? 0 : (this.presetEnabled(preset) ? 1 : 0.45))
    .scale(ListDissolve.scale(this.isMimoDissolving(preset.id)))
    .blur(ListDissolve.blur(this.isMimoDissolving(preset.id)))
    .hitTestBehavior(this.isMimoDissolving(preset.id) ? HitTestMode.None : HitTestMode.Default)
    .id(this.mimoCardElementId(preset.id))
    .gesture(LongPressGesture({ repeat: false }).onAction((event: GestureEvent) => this.openPresetMenu(preset, event)))
    .onClick(() => this.editPreset(preset))
  }
  @Builder
  presetMeta(label: string, color: string) {
    Text(label).fontSize(AppFontSize.CAPTION).fontColor(color).maxLines(1).margin({ right: AppSpacing.MD, bottom: AppSpacing.XXS })
  }
  private presetSchemeCount(preset: MimoVoicePreset): number {
    return this.schemes.filter((s: MimoVoiceScheme): boolean => s.presetIds.includes(preset.id)).length;
  }
  private presetSwipeActions(preset: MimoVoicePreset): HdsSwipeActionOptions {
    const enabled = this.presetEnabled(preset);
    return { icons: [
      { icon: new SymbolGlyphModifier(enabled ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle')),
        backgroundColor: ThemeRuntime.buttonColor(this.dark), iconOptions: { accessibilityText: enabled ? '禁用音色' : '启用音色' },
        onAction: () => this.togglePreset(preset) },
      { icon: new SymbolGlyphModifier($r('sys.symbol.trash')), backgroundColor: ThemeRuntime.dangerColor(this.dark),
        iconOptions: { accessibilityText: '删除音色' }, onAction: () => { this.remove(preset); } }
    ] };
  }
  @Builder
  presetFallbackSwipeActions(preset: MimoVoicePreset) {
    Row() {
      this.swipeButton(this.presetEnabled(preset) ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle'),
        this.presetEnabled(preset) ? '禁用' : '启用', ThemeRuntime.buttonColor(this.dark), () => this.togglePreset(preset))
      this.swipeButton($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.dark), () => { this.remove(preset); })
    }.height('100%')
  }
  @Builder
  swipeButton(icon: Resource, label: string, color: string, action: () => void) {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph(icon).fontSize(22).fontColor(['#FFFFFF'])
      Text(label).fontSize(AppFontSize.CAPTION).fontColor('#FFFFFF')
    }.width(64).height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(color).onClick(action)
  }
  @Builder
  presetMenu() {
    Scroll() {
      Column() {
        PopupMenuAction($r('sys.symbol.speaker_wave_2'), '试听', ThemeRuntime.primaryTextColor(this.dark),
          () => this.presetAction((p: MimoVoicePreset) => this.openPreview(p)))
        PopupMenuAction($r('sys.symbol.square_and_pencil'), '编辑', ThemeRuntime.primaryTextColor(this.dark),
          () => this.presetAction((p: MimoVoicePreset) => this.editPreset(p)))
        PopupMenuAction($r('sys.symbol.plus_square_on_square'), '复制', ThemeRuntime.primaryTextColor(this.dark),
          () => this.presetAction((p: MimoVoicePreset) => this.editPreset(p, true)))
        PopupMenuAction(this.disabledIds.includes(this.actionPresetId) ? $r('sys.symbol.checkmark_circle') :
          $r('sys.symbol.minus_circle'), this.disabledIds.includes(this.actionPresetId) ? '启用' : '禁用',
          ThemeRuntime.primaryTextColor(this.dark), () => this.presetAction((p: MimoVoicePreset) => this.togglePreset(p)))
        PopupMenuAction($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.dark),
          () => this.presetAction((p: MimoVoicePreset) => { this.remove(p); }))
      }.width('100%')
    }
    .width(176)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
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
    List({ space: AppSpacing.MD }) {
      ListItem() {
        Column({ space: AppSpacing.MD }) {
          if (this.error) { this.hint(this.error) }
          Column() {
            SettingSwitchRow({ title: '使用方案自动分配', description: '关闭后新人物使用旁白，已有绑定保留',
              isOn: this.assignmentEnabled, showDivider: false, onChange: (flag: boolean) => this.toggleAssignment(flag) })
          }.backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
          this.hint((this.book ? (this.inherited ? '本书当前继承默认方案。' : '本书使用独立方案。') : '默认方案供未单独设置的书籍使用。') +
            '左滑可禁用或删除，长按查看全部操作。')
        }
      }
      ForEach(this.schemes, (scheme: MimoVoiceScheme) => {
        // HdsListItem 必须直接挂在 List 下，侧滑才不被包装节点阻断。
        if (deviceInfo.sdkApiVersion >= 26) {
          HdsListItem({ customItemBuilder: (): void => { this.schemeCard(scheme); },
            swipeActionOptions: this.schemeSwipeActions(scheme) })
        } else {
          ListItem() { this.schemeCard(scheme) }
            .borderRadius(ThemeRuntime.mediumRadius()).clip(true)
            .swipeAction({ end: { builder: (): void => { this.schemeFallbackSwipeActions(scheme); } }, edgeEffect: SwipeEdgeEffect.Spring })
        }
      }, (scheme: MimoVoiceScheme): string => scheme.id + ':' + this.schemeCandidates(scheme) + ':' + this.schemeEnabled(scheme) +
        ':' + (this.activeScheme === scheme.id))
      if (this.book && !this.inherited) {
        ListItem() {
          Button('恢复跟随默认方案').fontSize(AppFontSize.BODY).backgroundColor(Color.Transparent)
            .fontColor(ThemeRuntime.accentColor(this.dark)).onClick(() => {
              const cast = MimoStore.cast(this.book); cast.schemeId = ''; cast.assignmentEnabled = undefined;
              MimoStore.saveCast(this.book, cast); this.refresh();
            })
        }
      }
      // 右下角悬浮新增按钮（52 高，底边距 navBarHeight+22）要完整让出最后一张卡片。
      ListItem() { Row().height(this.navBarHeight + 88).hitTestBehavior(HitTestMode.None) }
    }
    .width('100%').height('100%').constraintSize({ maxWidth: 760 }).scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
  }
  @Builder
  schemeCard(scheme: MimoVoiceScheme) {
    Column({ space: AppSpacing.XS }) {
      Text(scheme.name).fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(this.dark)).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        if (this.activeScheme === scheme.id) { this.presetMeta('正在使用', ThemeRuntime.accentColor(this.dark)) }
        this.presetMeta(scheme.presetIds.length + ' 个候选', ThemeRuntime.subTextColor(this.dark))
        if (!this.schemeEnabled(scheme)) { this.presetMeta('已禁用', ThemeRuntime.dangerColor(this.dark)) }
      }.width('100%')
      Text(this.schemeCandidates(scheme) || '没有候选，新人物使用旁白').fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.subTextColor(this.dark)).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
    }
    .alignItems(HorizontalAlign.Start).width('100%').padding(AppSpacing.LG)
    .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.mediumRadius())
    .opacity(this.isMimoDissolving(scheme.id) ? 0 : (this.schemeEnabled(scheme) ? 1 : 0.45))
    .scale(ListDissolve.scale(this.isMimoDissolving(scheme.id)))
    .blur(ListDissolve.blur(this.isMimoDissolving(scheme.id)))
    .hitTestBehavior(this.isMimoDissolving(scheme.id) ? HitTestMode.None : HitTestMode.Default)
    .id(this.mimoCardElementId(scheme.id))
    .gesture(LongPressGesture({ repeat: false }).onAction((event: GestureEvent) => this.openSchemeMenu(scheme, event)))
    .onClick(() => this.editScheme(scheme))
  }
  private schemeSwipeActions(scheme: MimoVoiceScheme): HdsSwipeActionOptions {
    const enabled = this.schemeEnabled(scheme);
    return { icons: [
      { icon: new SymbolGlyphModifier(enabled ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle')),
        backgroundColor: ThemeRuntime.buttonColor(this.dark), iconOptions: { accessibilityText: enabled ? '禁用方案' : '启用方案' },
        onAction: () => this.toggleScheme(scheme) },
      { icon: new SymbolGlyphModifier($r('sys.symbol.trash')), backgroundColor: ThemeRuntime.dangerColor(this.dark),
        iconOptions: { accessibilityText: '删除方案' }, onAction: () => { this.removeScheme(scheme); } }
    ] };
  }
  @Builder
  schemeFallbackSwipeActions(scheme: MimoVoiceScheme) {
    Row() {
      this.swipeButton(this.schemeEnabled(scheme) ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle'),
        this.schemeEnabled(scheme) ? '禁用' : '启用', ThemeRuntime.buttonColor(this.dark), () => this.toggleScheme(scheme))
      this.swipeButton($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.dark), () => { this.removeScheme(scheme); })
    }.height('100%')
  }
  @Builder
  schemeMenu() {
    Scroll() {
      Column() {
        if (this.actionSchemeId !== this.activeScheme && !this.disabledSchemeIds.includes(this.actionSchemeId)) {
          PopupMenuAction($r('sys.symbol.checkmark'), '使用此方案', ThemeRuntime.primaryTextColor(this.dark),
            () => this.schemeAction((scheme: MimoVoiceScheme) => { this.activate(scheme); }))
        }
        PopupMenuAction($r('sys.symbol.square_and_pencil'), '编辑候选', ThemeRuntime.primaryTextColor(this.dark),
          () => this.schemeAction((scheme: MimoVoiceScheme) => this.editScheme(scheme)))
        PopupMenuAction(this.disabledSchemeIds.includes(this.actionSchemeId) ? $r('sys.symbol.checkmark_circle') :
          $r('sys.symbol.minus_circle'), this.disabledSchemeIds.includes(this.actionSchemeId) ? '启用' : '禁用',
          ThemeRuntime.primaryTextColor(this.dark), () => this.schemeAction((scheme: MimoVoiceScheme) => this.toggleScheme(scheme)))
        PopupMenuAction($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.dark),
          () => this.schemeAction((scheme: MimoVoiceScheme) => { this.removeScheme(scheme); }))
      }.width('100%')
    }
    .width(176)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }
  @Builder
  roleForm() {
    Column() {
      MimoVoiceSelectRow({ title: '年龄段', choices: MIMO_AGE_LABELS, selection: MimoVoicePolicy.ageLabel(this.editAge),
        onSelect: (i: number) => { this.editAge = MIMO_AGES[i]; this.dirty = true; } })
      MimoVoiceSelectRow({ title: '性别', choices: MIMO_GENDER_LABELS, selection: MimoVoicePolicy.genderLabel(this.editGender),
        onSelect: (i: number) => { this.editGender = MIMO_GENDERS[i]; this.dirty = true; } })
      MimoVoiceSelectRow({ title: '人物音色', choices: this.rolePresets().map((p: MimoVoicePreset): string => p.name),
        selection: this.rolePresetName, onSelect: (i: number) => this.chooseRolePreset(this.rolePresets()[i]) })
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
