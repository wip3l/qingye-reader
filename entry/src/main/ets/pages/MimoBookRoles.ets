import { router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { MimoBookCast, MimoCorrection, MimoStore } from '../utils/mimo/MimoStore';
import { MimoClient } from '../utils/mimo/MimoClient';
import { MimoRole, MIMO_VOICES } from '../core/mimo/MimoPolicy';
import { TtsPcmAudioPlayer } from '../utils/TtsPcmAudioPlayer';
import { ReaderTtsFloatingSession } from '../utils/ReaderTtsFloatingSession';
import { HdsFeedback } from '../utils/HdsFeedback';
import { syncSystemBars } from '../utils/SystemBars';

class MimoRolePageParams { book: string = ''; }

@Entry
@Component
struct MimoBookRolesPage {
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @State roles: MimoRole[] = [];
  @State emotion: string = '自然';
  @State currentText: string = '';
  @State correctionRole: string = 'narrator';
  @State busy: boolean = false;
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
    if (this.book === AppStorage.get<string>('mimoReadingBook')) {
      this.currentText = AppStorage.get<string>('mimoCurrentText') || '';
      this.correctionKey = AppStorage.get<string>('mimoCorrectionKey') || '';
      this.correctionRole = AppStorage.get<string>('mimoCurrentRoleId') || 'narrator';
    }
  }
  onPageShow(): void { syncSystemBars(getContext(this), this.dark, ThemeRuntime.pageColor(this.dark)); }
  onPageHide(): void { this.stopPreview(); }
  aboutToDisappear(): void { this.stopPreview(); this.player.release(); }
  private stopPreview(): void { this.serial++; this.client.stop(); this.player.stop(); this.busy = false; }
  private refresh(): void { const cast = MimoStore.cast(this.book); this.roles = cast.roles; this.emotion = cast.emotion; }
  private setVoice(id: string, voice: string): void {
    const cast = MimoStore.cast(this.book);
    const role = cast.roles.find((item: MimoRole): boolean => item.id === id);
    if (!role) return;
    role.voice = voice; role.locked = true;
    MimoStore.saveCast(this.book, cast); this.refresh();
    HdsFeedback.showToast('已保存，后续新生成片段使用此音色');
  }
  private correct(): void {
    if (!this.correctionKey) return;
    const cast = MimoStore.cast(this.book);
    const existing = cast.corrections.find((item: MimoCorrection): boolean => item.key === this.correctionKey);
    if (existing) existing.roleId = this.correctionRole;
    else { const item = new MimoCorrection(); item.key = this.correctionKey; item.roleId = this.correctionRole; cast.corrections.push(item); }
    MimoStore.saveCast(this.book, cast);
    HdsFeedback.showToast('已纠正，重新朗读该片段时生效');
  }
  private async preview(role: MimoRole): Promise<void> {
    this.stopPreview();
    const serial = this.serial;
    this.busy = true;
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
    finally { if (serial === this.serial) { this.busy = false; this.player.stop(); } }
  }
  build() {
    Stack() {
      PageScaffold({ title: '本书角色', content: () => { this.content() } })
    }.width('100%').height('100%')
  }
  @Builder
  content() {
    Column({ space: 16 }) {
      if (!this.book) {
        Text('开始朗读一本书后，这里会自动建立人物档案。').fontColor(ThemeRuntime.subTextColor(this.dark))
      } else {
        Text('同一人物，跨章节保持同一音色').fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium).width('100%')
        Text('修改只影响本书。四款中文预置音色可由多个角色共用。').fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
        Column() {
          ForEach(this.roles, (role: MimoRole) => {
            Column({ space: 8 }) {
              Row({ space: 10 }) {
                Column({ space: 4 }) {
                  Text(role.name).fontWeight(FontWeight.Medium).width('100%')
                  if (role.aliases.length > 0) {
                    Text('别名：' + role.aliases.join('、')).fontSize(AppFontSize.CAPTION)
                      .fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
                  }
                }.layoutWeight(1)
                Select(MIMO_VOICES.map((voice: string): SelectOption => ({ value: voice })))
                  .selected(MIMO_VOICES.indexOf(role.voice)).value(role.voice)
                  .fontColor(ThemeRuntime.primaryTextColor(this.dark)).backgroundColor(ThemeRuntime.inputColor(this.dark))
                  .onSelect((index: number) => this.setVoice(role.id, MIMO_VOICES[index]))
              }.width('100%')
              Button('试听 ' + role.name).enabled(!this.busy).fontSize(AppFontSize.CAPTION)
                .backgroundColor(ThemeRuntime.softFillColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
                .onClick(() => this.preview(role))
            }.width('100%').padding(16)
          }, (role: MimoRole): string => role.id + role.voice)
        }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
        if (this.currentText && this.correctionKey) {
          Column({ space: 12 }) {
            Text('纠正当前对白').fontWeight(FontWeight.Medium).width('100%')
            Text(this.currentText).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
            Select(this.roles.map((role: MimoRole): SelectOption => ({ value: role.name })))
              .selected(this.roles.findIndex((role: MimoRole): boolean => role.id === this.correctionRole))
              .value(this.roles.find((role: MimoRole): boolean => role.id === this.correctionRole)?.name || '旁白')
              .onSelect((index: number) => { this.correctionRole = this.roles[index].id; })
            Button('确认说话人').backgroundColor(ThemeRuntime.buttonColor(this.dark))
              .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.dark))).onClick(() => this.correct())
          }.padding(20).width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
        }
        Row() {
          Text('情绪表达').layoutWeight(1)
          Select([{ value: '自然' }, { value: '克制' }, { value: '生动' }]).value(this.emotion)
            .selected(['自然', '克制', '生动'].indexOf(this.emotion))
            .onSelect((index: number) => {
              const cast = MimoStore.cast(this.book); cast.emotion = ['自然', '克制', '生动'][index];
              MimoStore.saveCast(this.book, cast); this.refresh();
            })
        }.padding(20).width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
        if (this.busy) { Button('停止试听').onClick(() => this.stopPreview()) }
        Text('试听会产生少量 MiMo 用量。说话人不确定时使用旁白，可在播放器中纠正。')
          .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
      }
    }.width('100%').constraintSize({ maxWidth: 760 }).padding(20).foregroundColor(ThemeRuntime.primaryTextColor(this.dark))
  }
}
