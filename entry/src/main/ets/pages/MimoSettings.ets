import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow } from '../components/common/SettingRow';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { MimoStore } from '../utils/mimo/MimoStore';
import { MimoClient } from '../utils/mimo/MimoClient';
import { MimoReadingSession } from '../utils/mimo/MimoReadingSession';
import { MimoPolicy, MIMO_VOICES } from '../core/mimo/MimoPolicy';
import { TtsPcmAudioPlayer } from '../utils/TtsPcmAudioPlayer';
import { ReaderTtsFloatingSession } from '../utils/ReaderTtsFloatingSession';
import { HdsFeedback } from '../utils/HdsFeedback';
import { syncSystemBars } from '../utils/SystemBars';

@Entry
@Component
struct MimoSettingsPage {
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @State hasKey: boolean = false;
  @State editing: boolean = true;
  @State keyInput: string = '';
  @State consent: boolean = false;
  @State busy: boolean = false;
  @State tested: boolean = false;
  @State ttsPassed: boolean = false;
  @State analysisPassed: boolean = false;
  @State ttsStatus: string = '';
  @State analysisStatus: string = '';
  @State notice: string = '';
  @State voice: string = '白桦';
  @State mimoEnabled: boolean = false;
  @State multi: boolean = false;
  private testedKey: string = '';
  private serial: number = 0;
  private client: MimoClient = new MimoClient();
  private player: TtsPcmAudioPlayer = new TtsPcmAudioPlayer();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void { this.load(); }
  onPageShow(): void { syncSystemBars(getContext(this), this.dark, ThemeRuntime.pageColor(this.dark)); }
  onPageHide(): void { this.cancel(); }
  aboutToDisappear(): void { this.cancel(); this.player.release(); }
  private cancel(): void {
    this.serial++; this.client.stop(); this.player.stop(); this.busy = false;
    this.keyInput = ''; this.testedKey = ''; this.tested = false;
    this.consent = false;
  }
  private async load(): Promise<void> {
    const serial = ++this.serial;
    const settings = MimoStore.load();
    this.voice = settings.voice; this.mimoEnabled = settings.enabled; this.multi = settings.multi;
    this.analysisPassed = settings.analysisAvailable;
    try {
      const key = await MimoStore.key();
      if (serial !== this.serial) return;
      this.hasKey = key.length > 0; this.editing = !this.hasKey;
    } catch (error) { if (serial === this.serial) this.notice = (error as Error).message; }
  }
  private async openPlatform(): Promise<void> {
    try { await this.context.startAbility({ action: 'ohos.want.action.viewData', uri: 'https://platform.xiaomimimo.com/' }); }
    catch (_) { HdsFeedback.showToast('无法打开浏览器，请访问 platform.xiaomimimo.com'); }
  }
  private async test(saved: boolean = false): Promise<void> {
    if (this.busy) return;
    if (!saved && (!this.consent || !this.keyInput.trim())) return;
    const serial = ++this.serial;
    this.busy = true; this.tested = false; this.testedKey = '';
    this.ttsPassed = false; this.analysisPassed = false;
    this.ttsStatus = '正在合成试听…'; this.analysisStatus = '等待验证'; this.notice = '';
    await ReaderTtsFloatingSession.stop();
    try {
      const key = saved ? await MimoStore.key() : this.keyInput.trim();
      if (serial !== this.serial) return;
      if (!key || key.length > 4096 || /\s/.test(key)) throw new Error('请输入完整的 MiMo API Key');
      let pending: Promise<void> = Promise.resolve();
      let playbackError: Error | null = null;
      try {
        await this.client.synthesize(key, '雨声渐渐小了，远处的山色清晰起来。', this.voice,
          '自然平静的旁白', async (pcm: ArrayBuffer): Promise<void> => {
            if (serial !== this.serial) throw new Error('测试已取消');
            if (playbackError) throw playbackError;
            const write = this.player.write(pcm, 24000);
            pending = Promise.all([pending, write]).then((): void => {});
            pending.catch((error: Error): void => { playbackError = error; });
          });
        await pending;
        await this.player.drain();
        if (serial !== this.serial) return;
        this.ttsPassed = true; this.ttsStatus = '可用 · 已播放试听';
      } catch (error) {
        if (serial !== this.serial) return;
        this.ttsStatus = (error as Error).message;
        this.analysisStatus = '未测试，请先恢复语音合成';
        throw error as Error;
      }
      this.analysisStatus = '正在识别示例人物…';
      try {
        const units = MimoPolicy.split('小明说：“我们走吧。”');
        await this.client.analyze(key, units, [], '');
        if (serial !== this.serial) return;
        this.analysisPassed = true; this.analysisStatus = '可用';
      } catch (error) {
        if (serial !== this.serial) return;
        this.analysisStatus = (error as Error).message;
      }
      this.testedKey = key;
      this.tested = true;
      this.notice = this.analysisPassed ? '两项能力均可用，可以保存并开启多角色。' : '语音合成可用，可先保存并使用单音色。';
    } catch (error) { if (serial === this.serial) this.notice = (error as Error).message; }
    finally { if (serial === this.serial) { this.busy = false; this.player.stop(); } }
  }
  private async save(): Promise<void> {
    if (!this.tested || !this.ttsPassed || !this.testedKey || this.busy) return;
    this.busy = true;
    try {
      await MimoStore.saveKey(this.testedKey, this.analysisPassed, this.voice);
      this.keyInput = ''; this.testedKey = ''; this.editing = false; this.hasKey = true;
      this.mimoEnabled = true; this.multi = this.analysisPassed; this.tested = false;
      HdsFeedback.showToast(this.multi ? '已开启 MiMo 多角色朗读' : '已开启 MiMo 单音色朗读');
    } catch (error) { this.notice = (error as Error).message; }
    finally { this.busy = false; }
  }
  private async removeKey(): Promise<void> {
    const result = await this.getUIContext().getPromptAction().showDialog({ title: '删除本机密钥？',
      message: '将停止 MiMo 朗读并清除密钥。本书角色设置保留。',
      buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.dark) },
        { text: '删除', color: ThemeRuntime.dangerColor(this.dark) }] });
    if (result.index !== 1) return;
    try {
      await ReaderTtsFloatingSession.stop();
      await MimoStore.deleteKey();
      this.cancel(); this.hasKey = false; this.editing = true; this.mimoEnabled = false;
      this.notice = '本机密钥已删除';
    } catch (error) { this.notice = (error as Error).message; }
  }
  private setMode(multi: boolean): void {
    if (multi && !MimoStore.load().analysisAvailable) { HdsFeedback.showToast('请先重新测试角色分析能力'); return; }
    this.multi = multi; MimoStore.load().multi = multi; MimoStore.saveSettings();
  }
  build() {
    Stack() {
      PageScaffold({ title: 'MiMo 朗读', content: () => { this.content() } })
    }.width('100%').height('100%')
  }
  @Builder
  content() {
    Column({ space: 16 }) {
      if (this.editing) {
        Text('让书中的人物拥有自己的声音').fontSize(AppFontSize.TITLE).fontWeight(FontWeight.Medium)
          .fontColor(ThemeRuntime.primaryTextColor(this.dark)).width('100%')
        Column({ space: 10 }) {
          Text('获取你的 API Key').fontWeight(FontWeight.Medium).width('100%')
          Text('1. 打开小米 MiMo 开放平台并登录。\n2. 在控制台创建并复制 API Key。\n3. 回到这里填写并测试连接。')
            .fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
          Button('前往 MiMo 开放平台').onClick(() => this.openPlatform())
            .backgroundColor(ThemeRuntime.softFillColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
        }.width('100%').padding(20).backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
        Column({ space: 12 }) {
          Text('API Key').width('100%').fontWeight(FontWeight.Medium)
          TextInput({ text: this.keyInput, placeholder: '粘贴你的 MiMo API Key' }).type(InputType.Password)
            .showPasswordIcon(true).maxLength(4096).enabled(!this.busy)
            .backgroundColor(ThemeRuntime.inputColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
            .onChange((value: string) => { this.keyInput = value; this.tested = false; this.testedKey = ''; })
          Text('仅在本机安全保存，不随备份、同步或分享导出。').fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
          Row({ space: 8 }) {
            Checkbox().select(this.consent).enabled(!this.busy).selectedColor(ThemeRuntime.accentColor(this.dark))
              .onChange((value: boolean) => { this.consent = value; })
            Text('我知晓小说片段将发送给小米进行分析与合成，测试和朗读用量计入自己的 MiMo 账号，费用以平台规则为准。')
              .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).layoutWeight(1)
          }.width('100%')
        }.width('100%').padding(20).backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
        this.voicePicker()
        Button(this.busy ? '正在测试…' : '测试连接与试听').width('100%').height(46)
          .enabled(!this.busy && this.consent && this.keyInput.trim().length > 0)
          .backgroundColor(ThemeRuntime.buttonColor(this.dark)).fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.dark)))
          .onClick(() => this.test())
      } else {
        Column() {
          SettingRow({ title: '使用 MiMo 朗读' }) {
            Toggle({ type: ToggleType.Switch, isOn: this.mimoEnabled }).selectedColor(ThemeRuntime.accentColor(this.dark))
              .onChange((value: boolean) => {
                ReaderTtsFloatingSession.stop(); this.mimoEnabled = value; MimoStore.setEnabled(value);
              })
          }
          SettingRow({ title: '自动多角色' }) {
            Toggle({ type: ToggleType.Switch, isOn: this.multi }).selectedColor(ThemeRuntime.accentColor(this.dark))
              .onChange((value: boolean) => this.setMode(value))
          }
          SettingNavRow({ title: '本书角色', description: '固定人物音色与纠正对白归属', onTap: () => router.pushUrl({ url: 'pages/MimoBookRoles' }) })
          SettingNavRow({ title: '查看用量与额度', description: '前往小米控制台', onTap: () => this.openPlatform() })
          SettingNavRow({ title: '更换 API Key', description: '现有密钥不会在界面中显示', onTap: () => { this.cancel(); this.editing = true; this.notice = ''; } })
          SettingNavRow({ title: '重新测试与试听', description: '会产生少量 API 用量', onTap: () => this.test(true) })
          SettingNavRow({ title: '清理 MiMo 缓存', description: '保留密钥和人物设置', onTap: () => {
            MimoReadingSession.clearCache(); HdsFeedback.showToast('MiMo 缓存已清理');
          } })
        }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
        this.voicePicker()
        Button('删除本机密钥').fontColor(ThemeRuntime.dangerColor(this.dark))
          .backgroundColor(ThemeRuntime.softFillColor(this.dark)).onClick(() => this.removeKey())
      }
      if (this.ttsStatus || this.analysisStatus) {
        Column({ space: 10 }) {
          Text('语音合成：' + this.ttsStatus).width('100%')
          Text('角色分析：' + this.analysisStatus).width('100%')
        }.padding(20).width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
      }
      if (this.tested && this.ttsPassed) {
        Button(this.analysisPassed ? '保存并开启多角色朗读' : '保存并使用单音色').width('100%').height(46).enabled(!this.busy)
          .backgroundColor(ThemeRuntime.buttonColor(this.dark)).fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.dark)))
          .onClick(() => this.save())
      }
      if (this.notice) { Text(this.notice).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%') }
      Text('MiMo 不消耗 App 在线朗读字数包。多角色的文本分析与语音合成分别计入 MiMo 用量。')
        .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
    }.width('100%').constraintSize({ maxWidth: 760 }).padding(20).foregroundColor(ThemeRuntime.primaryTextColor(this.dark))
  }
  @Builder
  voicePicker() {
    Row() {
      Text('默认旁白音色').layoutWeight(1)
      Select(MIMO_VOICES.map((voice: string): SelectOption => ({ value: voice })))
        .value(this.voice).selected(MIMO_VOICES.indexOf(this.voice))
        .fontColor(ThemeRuntime.primaryTextColor(this.dark)).backgroundColor(ThemeRuntime.inputColor(this.dark))
        .onSelect((index: number) => {
          this.voice = MIMO_VOICES[index];
          if (!this.editing) { MimoStore.load().voice = this.voice; MimoStore.saveSettings(); }
        })
    }.padding(20).width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
  }
}
