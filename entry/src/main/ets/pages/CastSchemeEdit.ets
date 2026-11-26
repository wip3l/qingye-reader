import { router } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { PageScaffold } from '../components/common/PageScaffold';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { CastVoiceLine, CastVoicePicker } from '../components/CastVoiceViews';
import { CastScheme, CastVoicePolicy, CastVoiceRef } from '../core/mimo/CastVoicePolicy';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { CastVoiceItem, CastVoiceStore } from '../utils/mimo/CastVoiceStore';
import { CastVoicePreview } from '../utils/mimo/CastVoicePreview';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ThemedDialog } from '../utils/ThemedDialog';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { syncSystemBars } from '../utils/SystemBars';

class CastSchemeParams { id: string = ''; }

/**
 * 编辑一个音色方案：旁白、男主角、女主角各一个音色，男配角、女配角各一组（新人物轮流取），
 * 性别不明的人物默认跟旁白。
 */
@Entry
@Component
struct CastSchemeEditPage {
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @State scheme: CastScheme = new CastScheme();
  @State name: string = '';
  @State dirty: boolean = false;
  @State isNew: boolean = false;
  @State inUse: boolean = false;
  @State showPicker: boolean = false;
  @State pickSlot: string = '';
  @State previewing: string = '';
  private preview: CastVoicePreview = new CastVoicePreview();

  aboutToAppear(): void {
    const params = router.getParams() as CastSchemeParams;
    const library = CastVoiceStore.library();
    const found = library.schemes.find((item: CastScheme): boolean => item.id === (params?.id || ''));
    if (found) {
      this.scheme = CastVoicePolicy.cloneScheme(found);
      this.inUse = library.schemeId === found.id;
    } else {
      this.scheme = CastVoicePolicy.scheme(util.generateRandomUUID(), '');
      this.isNew = true;
    }
    this.name = this.scheme.name;
  }
  onPageShow(): void { syncSystemBars(getContext(this), this.dark, ThemeRuntime.pageColor(this.dark)); }
  onPageHide(): void { this.stopPreview(); }
  aboutToDisappear(): void { this.preview.release(); }
  onBackPress(): boolean { this.back(); return true; }

  private stopPreview(): void { this.preview.stop(); this.previewing = ''; }
  private async togglePreview(ref: CastVoiceRef): Promise<void> {
    const key = CastVoicePolicy.key(ref);
    if (this.previewing === key) { this.stopPreview(); return; }
    this.previewing = key;
    try { await this.preview.play(ref); } catch (error) {
      if (!CastVoicePreview.interrupted(error as Error)) HdsFeedback.showToast((error as Error).message || '试听失败');
    }
    if (this.previewing === key) this.previewing = '';
  }

  private async back(): Promise<void> {
    this.stopPreview();
    if (!this.dirty) { router.back(); return; }
    const result = await ThemedDialog.showDialog(this.getUIContext(), {
      title: '放弃修改？', message: '这个方案的修改还没有保存。',
      buttons: [{ text: '继续编辑', color: ThemeRuntime.subTextColor(this.dark) },
        { text: '放弃', color: ThemeRuntime.dangerColor(this.dark) }]
    });
    if (result.index === 1) router.back();
  }
  private save(): void {
    try {
      this.scheme.name = this.name;
      CastVoiceStore.saveScheme(this.scheme);
      this.dirty = false;
      HdsFeedback.showToast('已保存');
      router.back();
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }
  private use(): void {
    try {
      this.scheme.name = this.name;
      CastVoiceStore.saveScheme(this.scheme);
      CastVoiceStore.useScheme(this.scheme.id);
      this.dirty = false; this.inUse = true; this.isNew = false;
      HdsFeedback.showToast('已切换到这个方案');
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }
  private async remove(): Promise<void> {
    const result = await ThemedDialog.showDialog(this.getUIContext(), {
      title: '删除这个方案？', message: '用它的书会改用正在使用的方案，已分配给人物的声音不变。',
      buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.dark) },
        { text: '删除', color: ThemeRuntime.dangerColor(this.dark) }]
    });
    if (result.index !== 1) return;
    try { CastVoiceStore.deleteScheme(this.scheme.id); this.dirty = false; router.back(); }
    catch (error) { HdsFeedback.showToast((error as Error).message); }
  }

  private touch(): void {
    this.scheme = CastVoicePolicy.cloneScheme(this.scheme);
    this.dirty = true;
  }
  private single(slot: string): CastVoiceRef {
    if (slot === 'narrator') return this.scheme.narrator;
    if (slot === 'maleLead') return this.scheme.maleLead;
    if (slot === 'femaleLead') return this.scheme.femaleLead;
    return this.scheme.unknown;
  }
  private setSingle(slot: string, ref: CastVoiceRef): void {
    if (slot === 'narrator') this.scheme.narrator = ref;
    else if (slot === 'maleLead') this.scheme.maleLead = ref;
    else if (slot === 'femaleLead') this.scheme.femaleLead = ref;
    else this.scheme.unknown = ref;
    this.touch();
  }
  private pool(slot: string): CastVoiceRef[] {
    return slot === 'malePool' ? this.scheme.malePool : this.scheme.femalePool;
  }
  private removeFromPool(slot: string, key: string): void {
    const rest = this.pool(slot).filter((ref: CastVoiceRef): boolean => CastVoicePolicy.key(ref) !== key);
    if (slot === 'malePool') this.scheme.malePool = rest; else this.scheme.femalePool = rest;
    this.touch();
  }
  private isPool(slot: string): boolean { return slot === 'malePool' || slot === 'femalePool'; }

  private openPicker(slot: string): void {
    this.stopPreview();
    this.pickSlot = slot;
    this.showPicker = true;
  }
  private pick(item: CastVoiceItem): void {
    const slot = this.pickSlot;
    if (this.isPool(slot)) {
      if (this.pool(slot).some((ref: CastVoiceRef): boolean => CastVoicePolicy.key(ref) === item.key)) {
        this.removeFromPool(slot, item.key);
      } else if (this.pool(slot).length >= CastVoicePolicy.POOL_LIMIT) {
        HdsFeedback.showToast(`一组最多 ${CastVoicePolicy.POOL_LIMIT} 个音色`);
        return;
      } else {
        this.pool(slot).push(CastVoicePolicy.clone(item.ref));
        this.touch();
      }
    } else {
      this.setSingle(slot, CastVoicePolicy.clone(item.ref));
    }
    this.showPicker = false;
  }
  private pickerGender(): string {
    if (this.pickSlot === 'maleLead' || this.pickSlot === 'malePool') return 'male';
    if (this.pickSlot === 'femaleLead' || this.pickSlot === 'femalePool') return 'female';
    return 'unknown';
  }
  private slotLabel(slot: string): string {
    const labels: string[] = ['旁白', '男主角', '女主角', '男配角', '女配角', '性别不明'];
    const slots: string[] = ['narrator', 'maleLead', 'femaleLead', 'malePool', 'femalePool', 'unknown'];
    return labels[slots.indexOf(slot)] || '';
  }
  private pickerSelected(): string[] {
    if (this.isPool(this.pickSlot)) return this.pool(this.pickSlot).map((ref: CastVoiceRef): string => CastVoicePolicy.key(ref));
    const key = CastVoicePolicy.key(this.single(this.pickSlot));
    return key ? [key] : [];
  }
  /** 方案里别的位置已经用了哪些音色：key 与“××在用”一一对应。 */
  private usage(keys: boolean): string[] {
    const result: string[] = [];
    const add = (slot: string, ref: CastVoiceRef): void => {
      const key = CastVoicePolicy.key(ref);
      if (!key || slot === this.pickSlot) return;
      result.push(keys ? key : this.slotLabel(slot) + '在用');
    };
    add('narrator', this.scheme.narrator);
    add('maleLead', this.scheme.maleLead);
    add('femaleLead', this.scheme.femaleLead);
    this.scheme.malePool.forEach((ref: CastVoiceRef): void => add('malePool', ref));
    this.scheme.femalePool.forEach((ref: CastVoiceRef): void => add('femalePool', ref));
    add('unknown', this.scheme.unknown);
    return result;
  }

  /** 方案用到几个不同的离线模型；多于一个时换人说话要重新加载模型。 */
  private offlineModels(): number {
    const dirs: Set<string> = new Set<string>();
    for (const ref of CastVoicePolicy.schemeVoices(this.scheme)) {
      const model = CastVoiceStore.localModel(ref);
      if (model) dirs.add(model.dirName);
    }
    return dirs.size;
  }
  private tagText(ref: CastVoiceRef): string {
    const item = CastVoiceStore.item(ref);
    return item ? CastVoicePolicy.tagLabel(item.tag) : '';
  }
  private problem(ref: CastVoiceRef): string {
    const item = CastVoiceStore.item(ref);
    if (!item) return '已不可用';
    return item.unsupported ? item.reason : '';
  }

  pickerOptions(): SheetOptions {
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, {
      height: '75%',
      dragBar: true,
      showClose: false,
      onDisappear: () => { this.showPicker = false; }
    }, this.dark, ThemeRuntime.accentColor(this.dark));
  }

  build() {
    Stack() {
      PageScaffold({
        title: this.isNew ? '新建方案' : '音色方案',
        onBack: () => { this.back(); },
        content: () => { this.content() },
        actions: () => { this.actions() }
      })
    }.width('100%').height('100%')
    .bindSheet($$this.showPicker, this.pickerSheet(), this.pickerOptions())
  }

  @Builder
  actions() {
    ImmersiveHeaderAction({ label: '保存', tint: ThemeRuntime.accentColor(this.dark), onTap: () => this.save() })
      .margin({ right: AppSpacing.XL })
  }

  @Builder
  pickerSheet() {
    CastVoicePicker({
      heading: this.slotLabel(this.pickSlot) + (this.isPool(this.pickSlot) ? ' · 添加或移除' : ' · 选择音色'),
      sub: this.pickSlot === 'narrator' ? '“合适的”里只列标了“适合读旁白”的音色' :
        (this.pickSlot === 'unknown' ? '识别不出性别的人物用它；不选就跟旁白一样' : ''),
      gender: this.pickerGender(),
      narratorOnly: this.pickSlot === 'narrator',
      selectedKeys: this.pickerSelected(),
      usedKeys: this.usage(true),
      usedLabels: this.usage(false),
      onPick: (item: CastVoiceItem): void => this.pick(item)
    })
  }

  @Builder
  label(title: string, hint: string) {
    Row({ space: AppSpacing.MD }) {
      Text(title).fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium)
        .fontColor(ThemeRuntime.primaryTextColor(this.dark))
      if (hint) {
        Text(hint).fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark))
      }
    }.width('100%').padding({ left: AppSpacing.XXS, top: AppSpacing.SM })
  }

  @Builder
  emptyRow(text: string, slot: string) {
    Row() {
      Text(text).fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.accentColor(this.dark))
    }
    .width('100%').height(48).justifyContent(FlexAlign.Center)
    .onClick(() => this.openPicker(slot))
  }

  @Builder
  singleSlot(slot: string, hint: string, empty: string) {
    this.label(this.slotLabel(slot), hint)
    Column() {
      if (CastVoicePolicy.key(this.single(slot))) {
        CastVoiceLine({
          title: this.single(slot).name,
          source: CastVoicePolicy.sourceLabel(this.single(slot).kind),
          tagText: this.tagText(this.single(slot)),
          note: this.problem(this.single(slot)), noteTone: 'danger',
          playing: this.previewing === CastVoicePolicy.key(this.single(slot)),
          action: slot === 'narrator' ? '更换' : '清除',
          onTap: (): void => this.openPicker(slot),
          onPlay: (): void => { this.togglePreview(this.single(slot)); },
          onAction: (): void => {
            if (slot === 'narrator') this.openPicker(slot);
            else this.setSingle(slot, new CastVoiceRef());
          }
        })
      } else {
        this.emptyRow(empty, slot)
      }
    }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
  }

  @Builder
  poolSlot(slot: string) {
    this.label(this.slotLabel(slot), this.pool(slot).length > 0 ? `${this.pool(slot).length} 个，轮流取` : '')
    Column() {
      ForEach(this.pool(slot), (ref: CastVoiceRef) => {
        CastVoiceLine({
          title: ref.name, source: CastVoicePolicy.sourceLabel(ref.kind), tagText: this.tagText(ref),
          note: this.problem(ref), noteTone: 'danger',
          playing: this.previewing === CastVoicePolicy.key(ref), action: '移除', showDivider: true,
          onPlay: (): void => { this.togglePreview(ref); },
          onAction: (): void => this.removeFromPool(slot, CastVoicePolicy.key(ref))
        })
      }, (ref: CastVoiceRef): string => slot + CastVoicePolicy.key(ref) + this.tagText(ref) + this.problem(ref) +
        (this.previewing === CastVoicePolicy.key(ref) ? 'p' : ''))
      this.emptyRow('添加音色', slot)
    }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
  }

  @Builder
  content() {
    Column({ space: AppSpacing.LG }) {
      TextInput({ text: this.name, placeholder: '方案名称' }).maxLength(30)
        .backgroundColor(ThemeRuntime.inputColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
        .onChange((text: string) => { if (text !== this.name) { this.name = text; this.dirty = true; } })

      if (this.offlineModels() > 1) {
        Text(`这个方案用了 ${this.offlineModels()} 个不同的离线模型。离线引擎一次只能加载一个，每次换到另一个模型的人物说话都要重新加载，停顿明显也更占内存。建议离线音色都选同一个多人音色包里的。`)
          .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.primaryTextColor(this.dark)).width('100%')
          .padding(AppSpacing.LG).borderRadius(14).backgroundColor(ThemeRuntime.accentSurfaceColor(this.dark))
      }

      this.singleSlot('narrator', '', '选择旁白音色')
      this.singleSlot('maleLead', '', '选择音色（不选就从男配角里取）')
      this.singleSlot('femaleLead', '', '选择音色（不选就从女配角里取）')
      this.poolSlot('malePool')
      this.poolSlot('femalePool')
      this.singleSlot('unknown', '', '跟旁白一样')

      Text('主角要在“本书人物”里标出来才会用主角音色。一组里的音色优先分给还没人用的，其次选年龄段相符的；组里没有音色时由旁白读。')
        .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
        .padding({ left: AppSpacing.XS, right: AppSpacing.XS })

      if (!this.inUse) {
        Button('保存并使用这个方案').width('100%').height(44).fontSize(AppFontSize.BODY)
          .backgroundColor(ThemeRuntime.buttonColor(this.dark))
          .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.dark)))
          .onClick(() => this.use())
      }
      if (!this.isNew && !this.inUse) {
        Button('删除方案').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.dangerColor(this.dark))
          .backgroundColor(Color.Transparent).onClick(() => { this.remove(); })
      }
    }.width('100%').constraintSize({ maxWidth: 760 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
  }
}
