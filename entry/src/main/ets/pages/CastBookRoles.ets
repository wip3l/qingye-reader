import { router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow } from '../components/common/SettingRow';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { CastAvatar, CastPill, CastVoicePicker } from '../components/CastVoiceViews';
import { BookNameStyleSection } from '../components/BookNameStyleSection';
import { CastScheme, CastVoicePolicy, CastVoiceRef } from '../core/mimo/CastVoicePolicy';
import { MimoVoicePolicy } from '../core/mimo/MimoVoicePolicy';
import { MimoRole } from '../core/mimo/MimoPolicy';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { CastVoiceItem, CastVoiceStore } from '../utils/mimo/CastVoiceStore';
import { CastVoicePreview } from '../utils/mimo/CastVoicePreview';
import { MimoCorrection, MimoStore } from '../utils/mimo/MimoStore';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ThemedDialog } from '../utils/ThemedDialog';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { appDb } from '../model/data/AppDatabase';

class CastRolePageParams { book: string = ''; }

/** 一个人物在列表里显示的内容。 */
class CastRoleView {
  id: string = '';
  name: string = '';
  gender: string = 'unknown';
  lead: boolean = false;
  manual: boolean = false;
  sub: string = '';
  voice: string = '';
  source: string = '';
  ref: CastVoiceRef = new CastVoiceRef();
  signature: string = '';
}

/** 多角色朗读的“本书人物”：每个人物用哪个离线/自定义音色，标主角、换音色、纠正正在读的这句。 */
@Entry
@Component
struct CastBookRolesPage {
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('castVoiceRevision') @Watch('refresh') castRevision: number = 0;
  @State bookName: string = '';
  @State roles: CastRoleView[] = [];
  @State schemeName: string = '';
  @State followsDefault: boolean = true;
  @State currentText: string = '';
  @State correctionRole: string = 'narrator';
  @State previewing: string = '';
  @State showPicker: boolean = false;
  @State pickRole: string = '';
  /** 简单的单选面板（选方案、选说话人）：系统操作菜单最多 6 项，人物和方案可能更多。 */
  @State showOptions: boolean = false;
  @State optionTitle: string = '';
  @State optionLabels: string[] = [];
  @State optionSelected: number = -1;
  private onOption: (index: number) => void = (_index: number): void => {};
  private book: string = '';
  private correctionKey: string = '';
  private preview: CastVoicePreview = new CastVoicePreview();

  aboutToAppear(): void {
    const params = router.getParams() as CastRolePageParams;
    this.book = params?.book || AppStorage.get<string>('mimoReadingBook') || '';
    if (!this.book) return;
    this.refresh();
    this.loadBookName();
    if (this.book === AppStorage.get<string>('mimoReadingBook')) {
      this.currentText = AppStorage.get<string>('mimoCurrentText') || '';
      this.correctionKey = AppStorage.get<string>('mimoCorrectionKey') || '';
      this.correctionRole = AppStorage.get<string>('mimoCurrentRoleId') || 'narrator';
    }
  }
  onPageShow(): void {
    syncSystemBars(getContext(this), this.dark, ThemeRuntime.pageColor(this.dark));
    if (this.book) this.refresh();
  }
  onPageHide(): void { this.stopPreview(); }
  aboutToDisappear(): void { this.preview.release(); }

  private async loadBookName(): Promise<void> {
    let name = '';
    try { name = (await appDb.getBook(this.book))?.name || ''; } catch (_) {}
    this.bookName = name || MimoStore.cast(this.book).bookName || '';
  }
  private stopPreview(): void { this.preview.stop(); this.previewing = ''; }

  refresh(): void {
    if (!this.book) return;
    try {
      const cast = MimoStore.cast(this.book);
      const scheme = CastVoiceStore.scheme(cast);
      this.schemeName = scheme.name;
      this.followsDefault = !cast.castSchemeId;
      let changed = false;
      const views: CastRoleView[] = [];
      for (const role of cast.roles) {
        const match = CastVoiceStore.voiceFor(role, cast);
        if (match.changed) changed = true;
        const view = new CastRoleView();
        view.id = role.id; view.name = role.name; view.gender = role.gender || 'unknown';
        view.lead = role.lead === true; view.manual = match.slot === '已指定';
        const parts: string[] = [];
        if (role.id !== 'narrator') {
          parts.push(view.gender === 'male' ? '男' : (view.gender === 'female' ? '女' : '性别不明'));
          if (role.age && role.age !== 'unknown') parts.push(MimoVoicePolicy.ageLabel(role.age));
        }
        if (match.slot !== '已指定' && match.slot !== '性别不明') parts.push(role.id === 'narrator' ? '方案里的旁白' : match.slot);
        view.sub = parts.join(' · ');
        view.ref = match.ref;
        view.voice = match.ref.name || '没有可用音色';
        view.source = CastVoicePolicy.sourceLabel(match.ref.kind);
        view.signature = [view.id, view.name, view.gender, view.sub, view.voice, view.source, view.lead ? 'L' : '', view.manual ? 'M' : ''].join('|');
        views.push(view);
      }
      // 配角第一次显示时就把取到的音色记进档案，列表里看到的和朗读时用的才是同一个。
      if (changed) MimoStore.saveCast(this.book, cast, this.bookName);
      this.roles = views;
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }

  private async togglePreview(view: CastRoleView): Promise<void> {
    if (this.previewing === view.id) { this.stopPreview(); return; }
    if (!CastVoicePolicy.key(view.ref)) { HdsFeedback.showToast('这个人物还没有可用的音色'); return; }
    this.previewing = view.id;
    try { await this.preview.play(view.ref); } catch (error) {
      if (!CastVoicePreview.interrupted(error as Error)) HdsFeedback.showToast((error as Error).message || '试听失败');
    }
    if (this.previewing === view.id) this.previewing = '';
  }

  private update(id: string, change: (role: MimoRole) => void, toast: string): void {
    const cast = MimoStore.cast(this.book);
    const role = cast.roles.find((item: MimoRole): boolean => item.id === id);
    if (!role) return;
    change(role);
    MimoStore.saveCast(this.book, cast, this.bookName);
    this.refresh();
    if (toast) HdsFeedback.showToast(toast);
  }
  private picked(): CastRoleView | undefined {
    return this.roles.find((view: CastRoleView): boolean => view.id === this.pickRole);
  }
  private pick(item: CastVoiceItem): void {
    this.showPicker = false;
    this.update(this.pickRole, (role: MimoRole): void => {
      role.castVoice = CastVoicePolicy.clone(item.ref); role.castManual = true;
    }, '已保存，之后读到的片段用这个音色');
  }
  private pickerActions(): string[] {
    const view = this.picked();
    if (!view) return [];
    const actions: string[] = ['恢复自动分配'];
    if (view.id !== 'narrator' && (view.gender === 'male' || view.gender === 'female')) {
      actions.push(view.lead ? '取消主角' : (view.gender === 'male' ? '设为男主角' : '设为女主角'));
    }
    return actions;
  }
  private pickerAction(index: number): void {
    const view = this.picked();
    this.showPicker = false;
    if (!view) return;
    if (index === 0) {
      this.update(view.id, (role: MimoRole): void => { role.castVoice = undefined; role.castManual = false; }, '已恢复自动分配');
      return;
    }
    const lead = !view.lead;
    this.update(view.id, (role: MimoRole): void => {
      role.lead = lead;
      // 主角跟方案走，不留手动指定的音色。
      if (lead) { role.castVoice = undefined; role.castManual = false; }
    }, lead ? '已设为主角，用方案里的主角音色' : '已取消主角');
  }
  private usage(keys: boolean): string[] {
    const result: string[] = [];
    for (const view of this.roles) {
      const key = CastVoicePolicy.key(view.ref);
      if (!key || view.id === this.pickRole) continue;
      result.push(keys ? key : view.name + '在用');
    }
    return result;
  }
  private pickerSelected(): string[] {
    const key = CastVoicePolicy.key(this.picked()?.ref);
    return key ? [key] : [];
  }

  private chooseScheme(): void {
    const schemes = CastVoiceStore.library().schemes;
    const current = MimoStore.cast(this.book).castSchemeId || '';
    this.optionTitle = '本书用哪个音色方案';
    this.optionLabels = ['跟随正在使用的方案'].concat(schemes.map((scheme: CastScheme): string => scheme.name));
    this.optionSelected = current ? schemes.findIndex((scheme: CastScheme): boolean => scheme.id === current) + 1 : 0;
    this.onOption = (index: number): void => {
      const cast = MimoStore.cast(this.book);
      cast.castSchemeId = index === 0 ? '' : schemes[index - 1].id;
      MimoStore.saveCast(this.book, cast, this.bookName);
      this.refresh();
    };
    this.showOptions = true;
  }
  private async reassign(): Promise<void> {
    const result = await ThemedDialog.showDialog(this.getUIContext(), {
      title: '重新分配配角的声音？', message: '手动指定过的人物和主角不变，其余配角按现在的方案重新取音色。',
      buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.dark) },
        { text: '重新分配', color: ThemeRuntime.accentColor(this.dark) }]
    });
    if (result.index !== 1) return;
    const cast = MimoStore.cast(this.book);
    for (const role of cast.roles) {
      if (!role.castManual) role.castVoice = undefined;
    }
    MimoStore.saveCast(this.book, cast, this.bookName);
    this.refresh();
    HdsFeedback.showToast('已重新分配');
  }
  private correct(): void {
    if (!this.correctionKey) return;
    const cast = MimoStore.cast(this.book);
    for (const key of this.correctionKey.split(',')) {
      const existing = cast.corrections.find((item: MimoCorrection): boolean => item.key === key);
      if (existing) existing.roleId = this.correctionRole;
      else { const item = new MimoCorrection(); item.key = key; item.roleId = this.correctionRole; cast.corrections.push(item); }
    }
    MimoStore.saveCast(this.book, cast, this.bookName);
    HdsFeedback.showToast('已纠正，重新朗读这句时生效');
  }
  private chooseCorrectionRole(): void {
    this.optionTitle = '这句是谁说的';
    this.optionLabels = this.roles.map((view: CastRoleView): string => view.name);
    this.optionSelected = this.roles.findIndex((view: CastRoleView): boolean => view.id === this.correctionRole);
    this.onOption = (index: number): void => {
      if (index >= 0 && index < this.roles.length) this.correctionRole = this.roles[index].id;
    };
    this.showOptions = true;
  }
  private async clearCast(): Promise<void> {
    const result = await ThemedDialog.showDialog(this.getUIContext(), { title: '清除本书人物档案？',
      message: '人物、音色和纠正记录都会删除，下次多角色朗读时重新识别。',
      buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.dark) },
        { text: '清除', color: ThemeRuntime.dangerColor(this.dark) }] });
    if (result.index !== 1) return;
    this.stopPreview();
    MimoStore.deleteCast(this.book);
    HdsFeedback.showToast('已清除本书人物档案');
    router.back();
  }

  pickerOptions(): SheetOptions {
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, {
      height: '75%',
      dragBar: true,
      showClose: false,
      onDisappear: () => { this.showPicker = false; }
    }, this.dark, ThemeRuntime.accentColor(this.dark));
  }

  optionSheetOptions(): SheetOptions {
    return ImmersiveMaterialRuntime.applySheetMaterial(this.immersiveLightLevel, {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      onDisappear: () => { this.showOptions = false; }
    }, this.dark, ThemeRuntime.accentColor(this.dark));
  }

  build() {
    Stack() {
      PageScaffold({ title: '本书人物', content: () => { this.content() }, actions: () => { this.actions() } })
        .bindSheet($$this.showOptions, this.optionSheet(), this.optionSheetOptions())
    }.width('100%').height('100%')
    .bindSheet($$this.showPicker, this.pickerSheet(), this.pickerOptions())
  }

  @Builder
  optionSheet() {
    Column({ space: AppSpacing.LG }) {
      Text(this.optionTitle).fontSize(AppFontSize.SUBTITLE).fontWeight(FontWeight.Medium)
        .fontColor(ThemeRuntime.primaryTextColor(this.dark)).width('100%')
      Scroll() {
        Column() {
          ForEach(this.optionLabels, (label: string, index: number) => {
            Row() {
              Text(label).fontSize(AppFontSize.BODY_LARGE).fontColor(ThemeRuntime.primaryTextColor(this.dark))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              if (index === this.optionSelected) {
                SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([ThemeRuntime.accentColor(this.dark)])
              }
            }
            .width('100%').height(52).padding({ left: AppSpacing.XL, right: AppSpacing.XL })
            .onClick(() => { this.showOptions = false; this.onOption(index); })
          }, (label: string, index: number): string => `${index}|${label}|${index === this.optionSelected}`)
        }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
      }.constraintSize({ maxHeight: 420 }).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.XXXL })
  }

  @Builder
  actions() {
    if (this.book && this.roles.length > 1) {
      ImmersiveHeaderAction({ label: '重新分配', onTap: () => { this.reassign(); } }).margin({ right: AppSpacing.XL })
    }
  }

  @Builder
  pickerSheet() {
    CastVoicePicker({
      heading: (this.picked()?.name || '') + '的声音',
      sub: this.picked()?.sub || '',
      avatar: this.picked()?.name || '',
      gender: this.picked()?.gender || 'unknown',
      narratorOnly: this.pickRole === 'narrator',
      selectedKeys: this.pickerSelected(),
      usedKeys: this.usage(true),
      usedLabels: this.usage(false),
      actions: this.pickerActions(),
      onPick: (item: CastVoiceItem): void => this.pick(item),
      onAction: (index: number): void => this.pickerAction(index)
    })
  }

  @Builder
  roleRow(view: CastRoleView, last: boolean) {
    Column() {
      Row({ space: AppSpacing.LG }) {
        CastAvatar({ label: view.name, gender: view.gender })
        Column({ space: 3 }) {
          Row({ space: AppSpacing.SM }) {
            Text(view.name).fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium)
              .fontColor(ThemeRuntime.primaryTextColor(this.dark)).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (view.lead) {
              SymbolGlyph($r('sys.symbol.star_fill')).fontSize(13).fontColor([ThemeRuntime.accentColor(this.dark)])
            }
            if (view.manual) { CastPill({ text: '已指定', tone: 'accent' }) }
          }.width('100%')
          if (view.sub) {
            Text(view.sub).fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }
          Text(view.voice + (view.source ? ' · ' + view.source : '')).fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.primaryTextColor(this.dark))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.previewing === view.id ? $r('sys.symbol.stop_circle') : $r('sys.symbol.play_fill'))
            .fontSize(15).fontColor([ThemeRuntime.accentColor(this.dark)])
        }.width(32).height(32).backgroundColor(ThemeRuntime.accentSurfaceColor(this.dark))
        .accessibilityText(this.previewing === view.id ? '停止试听' : '试听 ' + view.name)
        .onClick(() => { this.togglePreview(view); })
      }
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
      .onClick(() => { this.stopPreview(); this.pickRole = view.id; this.showPicker = true; })
      if (!last) {
        Divider().strokeWidth(0.5).color(ThemeRuntime.dividerColor(this.dark)).margin({ left: 66 })
      }
    }.width('100%')
  }

  @Builder
  correctionCard() {
    Column({ space: AppSpacing.LG }) {
      Text('纠正正在朗读的这句').fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium)
        .fontColor(ThemeRuntime.primaryTextColor(this.dark)).width('100%')
      Text(this.currentText).fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.dark))
        .maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        .padding(AppSpacing.LG).borderRadius(AppSpacing.MD).backgroundColor(ThemeRuntime.softFillColor(this.dark))
      Row({ space: AppSpacing.MD }) {
        Text('说话人').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.primaryTextColor(this.dark))
        Text(this.roles.find((view: CastRoleView): boolean => view.id === this.correctionRole)?.name || '旁白')
          .fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.accentColor(this.dark))
          .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
          .borderRadius(14).backgroundColor(ThemeRuntime.accentSurfaceColor(this.dark))
          .onClick(() => this.chooseCorrectionRole())
        Blank()
        Button('确认').height(36).fontSize(AppFontSize.BODY).backgroundColor(ThemeRuntime.buttonColor(this.dark))
          .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.dark))).onClick(() => this.correct())
      }.width('100%')
    }.padding(AppSpacing.XL).width('100%')
    .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
  }

  @Builder
  content() {
    Column({ space: AppSpacing.LG }) {
      if (!this.book) {
        Column({ space: AppSpacing.MD }) {
          SymbolGlyph($r('sys.symbol.person')).fontSize(40).fontColor([ThemeRuntime.subTextColor(this.dark)])
          Text('选择一本书').fontSize(AppFontSize.BODY_LARGE).fontColor(ThemeRuntime.primaryTextColor(this.dark))
          Text('当前没有正在朗读的书。')
            .fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.dark)).textAlign(TextAlign.Center)
          Button('查看全部人物档案').height(40).fontSize(AppFontSize.BODY)
            .backgroundColor(ThemeRuntime.softFillColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
            .onClick(() => router.replaceUrl({ url: 'pages/MimoBooks' }))
        }.width('100%').padding({ top: 80, left: AppSpacing.XL, right: AppSpacing.XL })
      } else {
        Text(this.bookName ? '《' + this.bookName + '》' : '当前书籍').fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium).fontColor(ThemeRuntime.primaryTextColor(this.dark))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').padding({ top: AppSpacing.SM })

        if (this.currentText && this.correctionKey) {
          this.correctionCard()
        }

        Column() {
          SettingNavRow({ title: '音色方案', value: this.schemeName + (this.followsDefault ? '' : ' · 本书单独设置'),
            showDivider: false, onTap: (): void => this.chooseScheme() })
        }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())

        BookNameStyleSection({ book: this.book })

        Row({ space: AppSpacing.MD }) {
          Text('人物').fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.dark))
          Text(`${this.roles.length} 个`).fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark))
        }.width('100%').padding({ left: AppSpacing.XXS, top: AppSpacing.SM })

        Column() {
          ForEach(this.roles, (view: CastRoleView, index: number) => {
            this.roleRow(view, index === this.roles.length - 1)
            // 键里带上“是不是最后一行”：人物变多后，原来的最后一行要补上分隔线。
          }, (view: CastRoleView, index: number): string => view.signature + (this.previewing === view.id ? 'p' : '') +
            (index === this.roles.length - 1 ? 'e' : ''))
        }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())

        Text('点人物可以换音色或设为主角。人物声音跨章节固定，修改只影响本书；拿不准是谁说的句子由旁白读，可以在播放器里点“这句不对？”纠正。')
          .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
          .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
        Button('清除本书人物档案').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.dangerColor(this.dark))
          .backgroundColor(Color.Transparent).onClick(() => { this.clearCast(); })
      }
    }.width('100%').constraintSize({ maxWidth: 760 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
  }
}
