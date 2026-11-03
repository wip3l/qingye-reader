import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { MimoStore } from '../utils/mimo/MimoStore';
import { MimoClient } from '../utils/mimo/MimoClient';
import { MimoReadingSession } from '../utils/mimo/MimoReadingSession';
import { MimoPolicy, MIMO_VOICES } from '../core/mimo/MimoPolicy';
import { TtsPcmAudioPlayer } from '../utils/TtsPcmAudioPlayer';
import { ReaderTtsFloatingSession } from '../utils/ReaderTtsFloatingSession';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { AccountCommerceApi } from '../account/AccountCommerceApi';
import { MembershipBadge } from '../components/common/MembershipBadge';

/** Result of one capability check: idle (not run), running, ok, fail, skipped. */
type MimoCheck = 'idle' | 'running' | 'ok' | 'fail' | 'skipped';

interface MimoCheckLineParams {
  title: string;
  check: MimoCheck;
  status: string;
}

/** Passed as one object literal so @Builder takes it by reference and refreshes on state changes. */
interface PrimaryButtonParams {
  label: string;
  enabled: boolean;
  action: () => void;
}

@Entry
@Component
struct MimoSettingsPage {
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @State hasKey: boolean = false;
  @State editing: boolean = true;
  @State keyInput: string = '';
  @State consent: boolean = false;
  @State busy: boolean = false;
  /** A fresh key passed the speech check and can be saved. */
  @State tested: boolean = false;
  @State ttsCheck: MimoCheck = 'idle';
  @State analysisCheck: MimoCheck = 'idle';
  @State ttsStatus: string = '';
  @State analysisStatus: string = '';
  @State notice: string = '';
  @State filling: boolean = false;
  /** Read so the one-click fill button follows membership changes; the store stays authoritative. */
  @StorageProp('accountMembershipSku') membershipSku: string = '';
  @State voice: string = '白桦';
  @State voiceName: string = '白桦';
  @State mimoEnabled: boolean = false;
  @State multi: boolean = false;
  @State analysisAvailable: boolean = false;
  private testedKey: string = '';
  /** The member shared key never enters the text box, whose eye icon would reveal it. */
  private sharedKey: string = '';
  @State usingShared: boolean = false;
  private serial: number = 0;
  private client: MimoClient = new MimoClient();
  private player: TtsPcmAudioPlayer = new TtsPcmAudioPlayer();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void { this.load(); }
  onPageShow(): void {
    syncSystemBars(getContext(this), this.dark, ThemeRuntime.pageColor(this.dark));
    // The reader can switch to single voice behind this page; keep an unsaved voice choice while setting up.
    this.syncSettings(!this.editing);
  }
  // Leaving for the browser must not wipe a key the user just pasted.
  onPageHide(): void { this.stopTest(); }
  aboutToDisappear(): void { this.stopTest(); this.clearPendingKey(); this.testedKey = ''; this.player.release(); }
  private pendingKey(): string { return this.usingShared ? this.sharedKey : this.keyInput.trim(); }
  private clearPendingKey(): void { this.keyInput = ''; this.sharedKey = ''; this.usingShared = false; }
  private stopTest(): void {
    this.serial++; this.client.stop(); this.player.stop();
    if (this.busy) {
      this.busy = false;
      if (this.ttsCheck === 'running') { this.ttsCheck = 'idle'; this.ttsStatus = ''; }
      if (this.analysisCheck === 'running' || this.analysisCheck === 'idle') { this.analysisCheck = 'idle'; this.analysisStatus = ''; }
    }
  }
  private resetResults(): void {
    this.tested = false; this.testedKey = '';
    this.ttsCheck = 'idle'; this.analysisCheck = 'idle';
    this.ttsStatus = ''; this.analysisStatus = ''; this.notice = '';
  }
  private syncSettings(includeVoice: boolean = true): void {
    const settings = MimoStore.load();
    if (includeVoice) this.voice = settings.voice;
    try { this.voiceName = MimoStore.library().defaultPreset.name; } catch (_) { this.voiceName = settings.voice; }
    this.mimoEnabled = settings.enabled;
    this.multi = settings.multi; this.analysisAvailable = settings.analysisAvailable;
  }
  private async load(): Promise<void> {
    const serial = ++this.serial;
    this.syncSettings();
    try {
      const key = await MimoStore.key();
      if (serial !== this.serial) return;
      this.hasKey = key.length > 0; this.editing = !this.hasKey;
    } catch (error) { if (serial === this.serial) this.notice = (error as Error).message; }
  }
  private lifetimeMember(): boolean {
    if (this.membershipSku !== 'LIFETIME' && this.membershipSku !== 'SUPER_LIFETIME') return false;
    const sku = AccountSessionStore.activeMembershipSku();
    return sku === 'LIFETIME' || sku === 'SUPER_LIFETIME';
  }
  /** Fills the operator's key for lifetime members; consent and a passing test are still required to save. */
  private async fillSharedKey(): Promise<void> {
    if (this.busy) return;
    if (!AccountSessionStore.isLoggedIn()) { HdsFeedback.showToast('请先在“会员与账号”中登录'); return; }
    if (!this.lifetimeMember()) { HdsFeedback.showToast('一键填充仅限终身会员'); return; }
    const serial = ++this.serial;
    this.busy = true; this.filling = true;
    try {
      const key = await AccountCommerceApi.fetchMimoSharedKey(AccountSessionStore.token());
      if (serial !== this.serial) return;
      // Distinct from the server's "no key stored" message, so a malformed stored key is told apart.
      if (!key || key.length > 4096 || /\s/.test(key)) throw new Error('服务端返回的共享密钥格式不正确，请联系开发者');
      this.keyInput = '';
      this.sharedKey = key;
      this.usingShared = true;
      this.resetResults();
      HdsFeedback.showToast(this.consent ? '已填入会员共享密钥，请点击测试' : '已填入会员共享密钥，请勾选同意后测试');
    } catch (error) {
      if (serial === this.serial) HdsFeedback.showToast((error as Error).message || '填充失败，请稍后再试');
    } finally {
      if (serial === this.serial) this.busy = false;
      this.filling = false;
    }
  }
  private async openPlatform(): Promise<void> {
    try { await this.context.startAbility({ action: 'ohos.want.action.viewData', uri: 'https://platform.xiaomimimo.com/' }); }
    catch (_) { HdsFeedback.showToast('无法打开浏览器，请访问 platform.xiaomimimo.com'); }
  }
  private async test(saved: boolean = false): Promise<void> {
    if (this.busy) return;
    if (!saved && (!this.consent || !this.pendingKey())) return;
    const serial = ++this.serial;
    this.resetResults();
    this.busy = true;
    this.ttsCheck = 'running'; this.ttsStatus = '正在等待试听音频…';
    this.analysisCheck = 'running'; this.analysisStatus = '正在识别示例人物…';
    ReaderTtsFloatingSession.stop();
    try {
      const key = saved ? await MimoStore.key() : this.pendingKey();
      if (serial !== this.serial) return;
      if (!key || key.length > 4096 || /\s/.test(key)) throw new Error('请输入完整的 MiMo API Key');
      // Independent probes overlap network/model latency with the audible preview.
      const results = await Promise.all([this.testSpeech(key, serial), this.testAnalysis(key, serial)]);
      if (serial !== this.serial || !results[0]) return;
      const analysis = results[1];
      if (saved) {
        const wasMulti = this.multi;
        MimoStore.setAnalysisAvailable(analysis);
        this.syncSettings();
        this.notice = analysis ? '两项能力均可用。' :
          (wasMulti ? '角色分析不可用，已改为单音色朗读。' : '角色分析不可用，可继续使用单音色朗读。');
      } else {
        this.testedKey = key; this.tested = true;
        this.notice = analysis ? '两项能力均可用，保存后即可开启多角色朗读。' : '语音合成可用，可以先保存并使用单音色朗读。';
      }
    } catch (error) {
      if (serial !== this.serial) return;
      this.ttsCheck = 'fail'; this.ttsStatus = (error as Error).message;
      this.analysisCheck = 'skipped'; this.analysisStatus = '未完成测试';
    } finally { if (serial === this.serial) { this.busy = false; this.player.stop(); } }
  }
  private async testSpeech(key: string, serial: number): Promise<boolean> {
    const startedAt = Date.now();
    let firstChunk = true;
    let pending: Promise<void> = Promise.resolve();
    let playbackError: Error | null = null;
    console.info('[MiMo test] speech request started');
    try {
      await this.client.synthesize(key, '雨声渐渐小了，远处的山色清晰起来。', this.voice,
        '自然平静的旁白', async (pcm: ArrayBuffer): Promise<void> => {
          if (serial !== this.serial) throw new Error('测试已取消');
          if (playbackError) throw playbackError;
          const first = firstChunk;
          if (first) {
            firstChunk = false;
            console.info(`[MiMo test] first PCM: elapsedMs=${Date.now() - startedAt}`);
            this.ttsStatus = '音频已返回，正在准备播放…';
          }
          const write = first ? this.player.writeSegment(pcm, 24000, (): void => {
            if (serial !== this.serial) return;
            this.ttsStatus = '正在播放试听…';
            console.info(`[MiMo test] playback started: elapsedMs=${Date.now() - startedAt}`);
          }) : this.player.write(pcm, 24000);
          pending = Promise.all([pending, write]).then((): void => {});
          pending.catch((error: Error): void => { playbackError = error; });
        }, (delay: number): void => {
          if (serial !== this.serial) return;
          this.ttsStatus = `语音请求被限流，${Math.ceil(delay / 1000)} 秒后自动重试…`;
          console.info(`[MiMo test] speech retry: delayMs=${delay}`);
        });
      if (serial !== this.serial) return false;
      console.info(`[MiMo test] speech stream complete: elapsedMs=${Date.now() - startedAt}`);
      await pending;
      if (serial !== this.serial) return false;
      await this.player.drain();
      if (serial !== this.serial) return false;
      this.ttsCheck = 'ok'; this.ttsStatus = '可用，已播放试听';
      console.info(`[MiMo test] playback complete: elapsedMs=${Date.now() - startedAt}`);
      return true;
    } catch (error) {
      if (serial !== this.serial) return false;
      this.player.stop();
      this.ttsCheck = 'fail'; this.ttsStatus = (error as Error).message;
      console.info(`[MiMo test] speech failed: elapsedMs=${Date.now() - startedAt}`);
      return false;
    }
  }
  private async testAnalysis(key: string, serial: number): Promise<boolean> {
    const startedAt = Date.now();
    console.info('[MiMo test] analysis request started');
    try {
      await this.client.analyze(key, MimoPolicy.split('小明说：“我们走吧。”'), [], '', (delay: number): void => {
        if (serial !== this.serial) return;
        this.analysisStatus = `角色分析被限流，${Math.ceil(delay / 1000)} 秒后自动重试…`;
        console.info(`[MiMo test] analysis retry: delayMs=${delay}`);
      });
      if (serial !== this.serial) return false;
      this.analysisCheck = 'ok'; this.analysisStatus = '可用';
      console.info(`[MiMo test] analysis complete: elapsedMs=${Date.now() - startedAt}`);
      return true;
    } catch (error) {
      if (serial !== this.serial) return false;
      this.analysisCheck = 'fail'; this.analysisStatus = (error as Error).message;
      console.info(`[MiMo test] analysis failed: elapsedMs=${Date.now() - startedAt}`);
      return false;
    }
  }
  private async save(): Promise<void> {
    if (!this.tested || !this.testedKey || this.busy) return;
    this.busy = true;
    try {
      await MimoStore.saveKey(this.testedKey, this.analysisCheck === 'ok', this.voice);
      this.clearPendingKey(); this.consent = false; this.editing = false; this.hasKey = true;
      this.resetResults(); this.syncSettings();
      HdsFeedback.showToast(this.multi ? '已开启 MiMo 多角色朗读' : '已开启 MiMo 单音色朗读');
    } catch (error) { this.notice = (error as Error).message; }
    finally { this.busy = false; }
  }
  private startReplacing(): void {
    this.stopTest(); this.resetResults(); this.clearPendingKey(); this.consent = false; this.editing = true;
  }
  private cancelReplacing(): void {
    this.stopTest(); this.resetResults(); this.clearPendingKey(); this.consent = false; this.editing = false;
    this.syncSettings();
  }
  private async removeKey(): Promise<void> {
    const result = await this.getUIContext().getPromptAction().showDialog({ title: '删除本机密钥？',
      message: '将停止 MiMo 朗读并清除密钥。人物档案保留。',
      buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.dark) },
        { text: '删除', color: ThemeRuntime.dangerColor(this.dark) }] });
    if (result.index !== 1) return;
    try {
      this.stopTest();
      await ReaderTtsFloatingSession.stop();
      await MimoStore.deleteKey();
      this.resetResults(); this.syncSettings();
      this.hasKey = false; this.editing = true; this.clearPendingKey(); this.consent = false;
      HdsFeedback.showToast('本机密钥已删除');
    } catch (error) { this.notice = (error as Error).message; }
  }
  private setMode(multi: boolean): void {
    if (multi && !MimoStore.load().analysisAvailable) { HdsFeedback.showToast('请先重新测试，通过角色分析后再开启'); return; }
    this.multi = multi; MimoStore.load().multi = multi; MimoStore.saveSettings();
  }
  private setVoice(voice: string): void {
    this.voice = voice;
    if (!this.editing) { MimoStore.load().voice = voice; MimoStore.saveSettings(); }
  }

  build() {
    Stack() {
      PageScaffold({ title: 'MiMo 朗读', content: () => { this.content() } })
    }.width('100%').height('100%')
  }
  @Builder
  content() {
    Column({ space: AppSpacing.LG }) {
      if (this.editing) {
        this.voiceManagementSection()
        this.setupSection()
      } else {
        this.configuredSection()
      }
      if (this.ttsCheck !== 'idle') {
        this.resultCard()
      }
      if (this.notice) {
        Text(this.notice).fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
      }
      Text('MiMo 用量计入你自己的小米账号，不消耗 App 在线朗读字数包。多角色朗读的人物识别与语音合成分别计费。')
        .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
    }.width('100%').constraintSize({ maxWidth: 760 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
  }

  @Builder
  setupSection() {
    Column({ space: AppSpacing.MD }) {
      Text('让书中的人物拥有自己的声音').fontSize(AppFontSize.TITLE).fontWeight(FontWeight.Medium)
        .fontColor(ThemeRuntime.primaryTextColor(this.dark)).width('100%')
      Text('使用你自己的小米 MiMo API Key，自动区分旁白与人物，并为每个人物分配音色。')
        .fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
    }.width('100%').padding({ top: AppSpacing.SM, bottom: AppSpacing.XS })

    Column() {
      this.step(1, '登录小米 MiMo 开放平台')
      this.step(2, '在控制台创建并复制 API Key')
      this.step(3, '粘贴到下方，测试通过后保存')
      Button('前往 MiMo 开放平台').height(40).margin({ top: AppSpacing.MD })
        .backgroundColor(ThemeRuntime.softFillColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
        .fontSize(AppFontSize.BODY).onClick(() => this.openPlatform())
    }.width('100%').padding(AppSpacing.XL).alignItems(HorizontalAlign.Start)
    .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())

    Column({ space: AppSpacing.LG }) {
      Text('API Key').fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium)
        .fontColor(ThemeRuntime.primaryTextColor(this.dark)).width('100%')
      if (this.usingShared) {
        Row({ space: AppSpacing.MD }) {
          SymbolGlyph($r('sys.symbol.checkmark_shield')).fontSize(20).fontColor([ThemeRuntime.accentColor(this.dark)])
          Text('已填入会员共享密钥').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.primaryTextColor(this.dark))
            .layoutWeight(1)
          Button('改用自己的密钥').height(32).fontSize(AppFontSize.CAPTION).enabled(!this.busy)
            .backgroundColor(Color.Transparent).fontColor(ThemeRuntime.subTextColor(this.dark))
            .onClick(() => { this.clearPendingKey(); this.resetResults(); })
        }.width('100%').height(46).padding({ left: AppSpacing.LG, right: AppSpacing.XS })
        .borderRadius(ThemeRuntime.mediumRadius()).backgroundColor(ThemeRuntime.inputColor(this.dark))
      } else {
        TextInput({ text: this.keyInput, placeholder: '按量付费 sk- 或 Token Plan tp-/ttp- 密钥' }).type(InputType.Password)
          .showPasswordIcon(true).maxLength(4096).enabled(!this.busy).height(46)
          .backgroundColor(ThemeRuntime.inputColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
          .onChange((value: string) => { this.keyInput = value; this.resetResults(); })
        Row({ space: AppSpacing.SM }) {
          MembershipBadge({ sku: 'LIFETIME' })
          Text(this.lifetimeMember() ? '终身会员可直接使用开发者提供的密钥' : '终身会员可一键填入开发者提供的密钥')
            .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).layoutWeight(1)
          Button(this.filling ? '填充中…' : '一键填充').height(32).fontSize(AppFontSize.CAPTION)
            .enabled(!this.busy).opacity(this.lifetimeMember() && !this.busy ? 1 : 0.5)
            .backgroundColor(ThemeRuntime.softFillColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
            .onClick(() => this.fillSharedKey())
        }.width('100%')
      }
      Text(this.usingShared ? '共享密钥不会在界面中显示，只保存在本机安全存储中。' :
        MimoPolicy.isTokenPlan(this.keyInput.trim()) ?
        'Token Plan 密钥将使用套餐专属地址；若套餐不含语音合成，请改用按量付费的 sk- 密钥。' :
        '只保存在本机安全存储中，不随备份、同步或分享导出。')
        .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
      Row({ space: AppSpacing.MD }) {
        Checkbox().select(this.consent).enabled(!this.busy).selectedColor(ThemeRuntime.accentColor(this.dark))
          .width(20).height(20).margin(0)
          .onChange((value: boolean) => { this.consent = value; })
        Text('我知晓小说片段将发送给小米进行人物识别与语音合成，用量和费用以小米平台规则为准。')
          .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).layoutWeight(1)
          .onClick(() => { if (!this.busy) this.consent = !this.consent; })
      }.width('100%').alignItems(VerticalAlign.Top)
    }.width('100%').padding(AppSpacing.XL)
    .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())

    Column() {
      this.voiceRow()
    }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())

    // Pass an object literal: by-value @Builder arguments freeze at first build, which kept this button disabled.
    if (this.tested) {
      this.primaryButton({ label: this.analysisCheck === 'ok' ? '保存并开启多角色朗读' : '保存并使用单音色朗读',
        enabled: !this.busy, action: () => this.save() })
    } else {
      this.primaryButton({ label: this.busy ? '正在测试…' : '测试连接与试听',
        enabled: !this.busy && this.consent && this.pendingKey().length > 0, action: () => this.test() })
    }
    if (this.hasKey) {
      Button('取消，继续使用现有密钥').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.dark))
        .backgroundColor(Color.Transparent).onClick(() => this.cancelReplacing())
    }
  }

  @Builder
  configuredSection() {
    Column() {
      SettingSwitchRow({ title: '使用 MiMo 朗读', isOn: this.mimoEnabled,
        onChange: (value: boolean) => {
          ReaderTtsFloatingSession.stop(); this.mimoEnabled = value; MimoStore.setEnabled(value);
        } })
      SettingSwitchRow({ title: '自动多角色', isOn: this.multi, switchEnabled: this.analysisAvailable,
        description: this.analysisAvailable ? '识别旁白与人物，分别使用不同音色' : '角色分析未通过测试，暂不可用',
        onChange: (value: boolean) => this.setMode(value) })
    }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())

    this.voiceManagementSection()

    Column() {
      SettingNavRow({ title: '人物档案', description: '多角色朗读过的书，调整人物音色与对白归属',
        onTap: () => router.pushUrl({ url: 'pages/MimoBooks' }) })
      SettingNavRow({ title: '重新测试与试听', description: '会产生少量 API 用量',
        value: this.busy ? '测试中…' : '', onTap: () => this.test(true) })
      SettingNavRow({ title: '清理 MiMo 缓存', description: '保留密钥和人物设置', showDivider: false,
        onTap: () => { MimoReadingSession.clearCache(); HdsFeedback.showToast('MiMo 缓存已清理'); } })
    }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())

    Column() {
      SettingNavRow({ title: '查看用量与余额', description: '前往小米 MiMo 控制台', onTap: () => this.openPlatform() })
      SettingNavRow({ title: '更换 API Key', description: '现有密钥不会在界面中显示', onTap: () => this.startReplacing() })
      SettingNavRow({ title: '删除本机密钥', titleColor: ThemeRuntime.dangerColor(this.dark), showDivider: false,
        onTap: () => this.removeKey() })
    }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
  }

  @Builder
  voiceManagementSection() {
    Column() {
      SettingNavRow({ title: '默认声音', description: '单音色朗读及未匹配人物使用，已有绑定保留', value: this.voiceName,
        onTap: () => router.pushUrl({ url: 'pages/MimoVoices', params: { screen: 'default' } }) })
      SettingNavRow({ title: '音色与提示词', description: '新增、编辑和试听自定义声音',
        onTap: () => router.pushUrl({ url: 'pages/MimoVoices', params: { screen: 'library' } }) })
      SettingNavRow({ title: '默认音色方案', description: '只在方案候选内为新人物分配声音', showDivider: false,
        onTap: () => router.pushUrl({ url: 'pages/MimoVoices', params: { screen: 'schemes' } }) })
    }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
  }

  @Builder
  resultCard() {
    Column({ space: AppSpacing.LG }) {
      this.checkLine({ title: '语音合成', check: this.ttsCheck, status: this.ttsStatus })
      this.checkLine({ title: '角色分析', check: this.analysisCheck, status: this.analysisStatus })
      if (this.ttsCheck === 'fail') {
        Button('前往小米控制台查看').height(36).fontSize(AppFontSize.CAPTION)
          .backgroundColor(ThemeRuntime.softFillColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
          .onClick(() => this.openPlatform())
      }
    }.width('100%').padding(AppSpacing.XL).alignItems(HorizontalAlign.Start)
    .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
  }

  @Builder
  checkLine($$: MimoCheckLineParams) {
    Row({ space: AppSpacing.MD }) {
      if ($$.check === 'running') {
        LoadingProgress().width(20).height(20).color(ThemeRuntime.accentColor(this.dark))
      } else {
        SymbolGlyph($$.check === 'ok' ? $r('sys.symbol.checkmark_circle_fill') :
          $$.check === 'fail' ? $r('sys.symbol.xmark_circle_fill') : $r('sys.symbol.exclamationmark_circle'))
          .fontSize(20)
          .fontColor([$$.check === 'ok' ? ThemeRuntime.successColor(this.dark) :
            $$.check === 'fail' ? ThemeRuntime.dangerColor(this.dark) : ThemeRuntime.subTextColor(this.dark)])
      }
      Column({ space: AppSpacing.XXS }) {
        Text($$.title).fontSize(AppFontSize.BODY_LARGE).fontColor(ThemeRuntime.primaryTextColor(this.dark))
        if ($$.status) {
          Text($$.status).fontSize(AppFontSize.CAPTION).width('100%')
            .fontColor($$.check === 'fail' ? ThemeRuntime.dangerColor(this.dark) : ThemeRuntime.subTextColor(this.dark))
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(VerticalAlign.Top)
  }

  @Builder
  step(index: number, text: string) {
    Row({ space: AppSpacing.MD }) {
      Text(String(index)).fontSize(AppFontSize.CAPTION).fontWeight(FontWeight.Medium)
        .fontColor(ThemeRuntime.accentColor(this.dark)).textAlign(TextAlign.Center)
        .width(22).height(22).borderRadius(11).backgroundColor(ThemeRuntime.accentSurfaceColor(this.dark))
      Text(text).fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.primaryTextColor(this.dark)).layoutWeight(1)
    }.width('100%').padding({ top: AppSpacing.XS, bottom: AppSpacing.XS })
  }

  @Builder
  primaryButton(params: PrimaryButtonParams) {
    Button(params.label).width('100%').height(46).enabled(params.enabled).opacity(params.enabled ? 1 : 0.5)
      .backgroundColor(ThemeRuntime.buttonColor(this.dark))
      .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.dark)))
      .onClick(() => params.action())
  }

  @Builder
  voiceRow() {
    SettingRow({ title: this.multi && !this.editing ? '默认音色' : '旁白音色',
      description: this.multi && !this.editing ? '新书旁白使用，人物音色在“人物档案”中调整' : '',
      showDivider: false }) {
      Select(MIMO_VOICES.map((voice: string): SelectOption => ({ value: voice })))
        .enabled(!this.busy)
        .value(this.voice).selected(MIMO_VOICES.indexOf(this.voice))
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
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
        .accessibilityText('音色，' + this.voice)
        .onSelect((index: number) => this.setVoice(MIMO_VOICES[index]))
    }
  }
}
