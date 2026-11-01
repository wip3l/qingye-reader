import { router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingRow } from '../components/common/SettingRow';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { MimoCorrection, MimoStore } from '../utils/mimo/MimoStore';
import { MimoClient } from '../utils/mimo/MimoClient';
import { MimoRole, MIMO_VOICES } from '../core/mimo/MimoPolicy';
import { TtsPcmAudioPlayer } from '../utils/TtsPcmAudioPlayer';
import { ReaderTtsFloatingSession } from '../utils/ReaderTtsFloatingSession';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { appDb } from '../model/data/AppDatabase';

class MimoRolePageParams { book: string = ''; }

const EMOTIONS: string[] = ['自然', '克制', '生动'];

@Entry
@Component
struct MimoBookRolesPage {
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @State bookName: string = '';
  @State roles: MimoRole[] = [];
  @State emotion: string = '自然';
  @State currentText: string = '';
  @State correctionRole: string = 'narrator';
  /** Role id being previewed, empty when idle. */
  @State previewing: string = '';
  private book: string = '';
  private correctionKey: string = '';
  private serial: number = 0;
  private client: MimoClient = new MimoClient();
  private player: TtsPcmAudioPlayer = new TtsPcmAudioPlayer();
  aboutToAppear(): void {
    const params = router.getParams() as MimoRolePageParams;
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
  onPageShow(): void { syncSystemBars(getContext(this), this.dark, ThemeRuntime.pageColor(this.dark)); }
  onPageHide(): void { this.stopPreview(); }
  aboutToDisappear(): void { this.stopPreview(); this.player.release(); }
  private async loadBookName(): Promise<void> {
    let name = '';
    try { name = (await appDb.getBook(this.book))?.name || ''; } catch (_) {}
    // A book removed from the shelf keeps the title saved with its cast.
    this.bookName = name || MimoStore.cast(this.book).bookName || '';
  }
  private stopPreview(): void { this.serial++; this.client.stop(); this.player.stop(); this.previewing = ''; }
  private refresh(): void { const cast = MimoStore.cast(this.book); this.roles = cast.roles; this.emotion = cast.emotion; }
  private setVoice(id: string, voice: string): void {
    const cast = MimoStore.cast(this.book);
    const role = cast.roles.find((item: MimoRole): boolean => item.id === id);
    if (!role || role.voice === voice) return;
    role.voice = voice; role.locked = true;
    MimoStore.saveCast(this.book, cast, this.bookName); this.refresh();
    HdsFeedback.showToast('已保存，之后新生成的片段使用此音色');
  }
  private setEmotion(emotion: string): void {
    const cast = MimoStore.cast(this.book); cast.emotion = emotion;
    MimoStore.saveCast(this.book, cast, this.bookName); this.refresh();
  }
  private correct(): void {
    if (!this.correctionKey) return;
    const cast = MimoStore.cast(this.book);
    // Short neighbours are read together, so one sentence on screen can carry several keys.
    for (const key of this.correctionKey.split(',')) {
      const existing = cast.corrections.find((item: MimoCorrection): boolean => item.key === key);
      if (existing) existing.roleId = this.correctionRole;
      else { const item = new MimoCorrection(); item.key = key; item.roleId = this.correctionRole; cast.corrections.push(item); }
    }
    MimoStore.saveCast(this.book, cast, this.bookName);
    HdsFeedback.showToast('已纠正，重新朗读这句时生效');
  }
  private async clearCast(): Promise<void> {
    const result = await this.getUIContext().getPromptAction().showDialog({ title: '清除本书人物档案？',
      message: '人物、音色和纠正记录都会删除，下次多角色朗读时重新识别。',
      buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.dark) },
        { text: '清除', color: ThemeRuntime.dangerColor(this.dark) }] });
    if (result.index !== 1) return;
    this.stopPreview();
    MimoStore.deleteCast(this.book);
    HdsFeedback.showToast('已清除本书人物档案');
    router.back();
  }
  private togglePreview(role: MimoRole): void {
    if (this.previewing === role.id) { this.stopPreview(); return; }
    this.preview(role);
  }
  private async preview(role: MimoRole): Promise<void> {
    this.stopPreview();
    const serial = this.serial;
    this.previewing = role.id;
    try {
      await ReaderTtsFloatingSession.stop();
      const key = await MimoStore.key();
      if (serial !== this.serial) return;
      if (!key) throw new Error('请先配置 MiMo API Key');
      let write: Promise<void> = Promise.resolve();
      let failure: Error | null = null;
      await this.client.synthesize(key, '雨停了，我们一起出发吧。', role.voice, '单一说话人，自然平静',
        async (pcm: ArrayBuffer): Promise<void> => {
          if (serial !== this.serial) throw new Error('试听已停止');
          if (failure) throw failure;
          write = Promise.all([write, this.player.write(pcm, 24000)]).then((): void => {});
          write.catch((error: Error): void => { failure = error; });
        });
      await write; await this.player.drain();
    } catch (error) { if (serial === this.serial) HdsFeedback.showToast((error as Error).message); }
    finally { if (serial === this.serial) { this.previewing = ''; this.player.stop(); } }
  }
  build() {
    Stack() {
      PageScaffold({ title: '本书角色', content: () => { this.content() } })
    }.width('100%').height('100%')
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
        Column({ space: AppSpacing.XS }) {
          Text(this.bookName ? '《' + this.bookName + '》' : '当前书籍').fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium).fontColor(ThemeRuntime.primaryTextColor(this.dark))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text('同一人物跨章节保持同一音色，修改只影响本书；四款音色可由多个人物共用。')
            .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
        }.width('100%').padding({ top: AppSpacing.SM })

        if (this.currentText && this.correctionKey) {
          this.correctionCard()
        }

        Column() {
          ForEach(this.roles, (role: MimoRole, index: number) => {
            this.roleRow(role, index === this.roles.length - 1)
          }, (role: MimoRole): string => role.id + role.voice)
        }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())

        Column() {
          SettingRow({ title: '情绪表达', description: '克制时统一平静语气，生动时情绪更鲜明', showDivider: false }) {
            Select(EMOTIONS.map((value: string): SelectOption => ({ value: value })))
              .value(this.emotion).selected(EMOTIONS.indexOf(this.emotion))
              .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
              .fontColor(ThemeRuntime.subTextColor(this.dark))
              .backgroundColor(Color.Transparent)
              .arrowPosition(ArrowPosition.END)
              .padding({ left: 0, right: 0 })
              .borderRadius(16)
              .border({ width: 0 })
              .divider(null)
              .optionBgColor(Color.Transparent)
              .optionFontColor(ThemeRuntime.primaryTextColor(this.dark))
              .selectedOptionFontColor(ThemeRuntime.accentColor(this.dark))
              .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.dark))
              .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.dark))
              .menuBackgroundBlurStyle(BlurStyle.NONE)
              .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
              .onSelect((index: number) => this.setEmotion(EMOTIONS[index]))
          }
        }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())

        Text('试听会产生少量 MiMo 用量。说话人不确定时由旁白朗读，可在播放器里点“这句不对？”纠正。')
          .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
        Button('清除本书人物档案').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.dangerColor(this.dark))
          .backgroundColor(Color.Transparent).onClick(() => this.clearCast())
      }
    }.width('100%').constraintSize({ maxWidth: 760 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
  }

  @Builder
  roleRow(role: MimoRole, last: boolean) {
    SettingRow({ title: role.name, description: role.aliases.length > 0 ? '别名：' + role.aliases.join('、') : '',
      showDivider: !last }) {
      Row({ space: AppSpacing.MD }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.previewing === role.id ? $r('sys.symbol.stop_circle') : $r('sys.symbol.play_fill'))
            .fontSize(18).fontColor([ThemeRuntime.primaryTextColor(this.dark)])
        }.width(36).height(36).backgroundColor(ThemeRuntime.softFillColor(this.dark))
        .accessibilityText(this.previewing === role.id ? '停止试听' : '试听 ' + role.name)
        .onClick(() => this.togglePreview(role))
        Select(MIMO_VOICES.map((voice: string): SelectOption => ({ value: voice })))
          .selected(MIMO_VOICES.indexOf(role.voice)).value(role.voice)
          .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
          .fontColor(ThemeRuntime.subTextColor(this.dark))
          .backgroundColor(Color.Transparent)
          .arrowPosition(ArrowPosition.END)
          .padding({ left: 0, right: 0 })
          .borderRadius(16)
          .border({ width: 0 })
          .divider(null)
          .optionBgColor(Color.Transparent)
          .optionFontColor(ThemeRuntime.primaryTextColor(this.dark))
          .selectedOptionFontColor(ThemeRuntime.accentColor(this.dark))
          .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.dark))
          .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.dark))
          .menuBackgroundBlurStyle(BlurStyle.NONE)
          .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
          .accessibilityText(role.name + '的音色，' + role.voice)
          .onSelect((index: number) => this.setVoice(role.id, MIMO_VOICES[index]))
      }.margin({ left: AppSpacing.MD })
    }
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
        Select(this.roles.map((role: MimoRole): SelectOption => ({ value: role.name })))
          .selected(this.roles.findIndex((role: MimoRole): boolean => role.id === this.correctionRole))
          .value(this.roles.find((role: MimoRole): boolean => role.id === this.correctionRole)?.name || '旁白')
          .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
          .fontColor(ThemeRuntime.subTextColor(this.dark))
          .backgroundColor(Color.Transparent)
          .arrowPosition(ArrowPosition.END)
          .padding({ left: 0, right: 0 })
          .borderRadius(16)
          .border({ width: 0 })
          .divider(null)
          .optionBgColor(Color.Transparent)
          .optionFontColor(ThemeRuntime.primaryTextColor(this.dark))
          .selectedOptionFontColor(ThemeRuntime.accentColor(this.dark))
          .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.dark))
          .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.dark))
          .menuBackgroundBlurStyle(BlurStyle.NONE)
          .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
          .onSelect((index: number) => { this.correctionRole = this.roles[index].id; })
        Blank()
        Button('确认').height(36).fontSize(AppFontSize.BODY).backgroundColor(ThemeRuntime.buttonColor(this.dark))
          .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.dark))).onClick(() => this.correct())
      }.width('100%')
    }.padding(AppSpacing.XL).width('100%')
    .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
  }
}
