import { router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { CastVoicePolicy } from '../core/mimo/CastVoicePolicy';
import { MimoPolicy } from '../core/mimo/MimoPolicy';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { CastVoiceStore } from '../utils/mimo/CastVoiceStore';
import { MimoAnalysisTarget, MimoClient } from '../utils/mimo/MimoClient';
import { HdsFeedback } from '../utils/HdsFeedback';
import { syncSystemBars } from '../utils/SystemBars';

class CastAnalysisEndpointEditParams {
  id: string = '';
}

/**
 * 添加或修改一个识别人物用的接口（兼容 OpenAI chat/completions）。
 * 要先测试通过才保存；密钥只存在本机安全存储里。保存不改变正在用哪个接口，
 * 只有当前没有任何能用的分析模型时，才顺手改用刚保存的这个。
 */
@Entry
@Component
struct CastAnalysisEndpointEditPage {
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  /** 空串表示正在添加，保存成功后换成新接口的 id。 */
  @State endpointId: string = '';
  @State name: string = '';
  @State url: string = '';
  @State model: string = '';
  @State apiKey: string = '';
  @State keySaved: boolean = false;
  @State testing: boolean = false;
  @State passed: boolean = false;
  @State status: string = '';
  private client: MimoClient = new MimoClient();
  private serial: number = 0;
  /** 测试进行中每秒刷新“已等几秒”，让人知道没卡死。 */
  private tickTimer: number = -1;

  aboutToAppear(): void {
    this.endpointId = (router.getParams() as CastAnalysisEndpointEditParams)?.id || '';
    const endpoint = this.endpointId ? CastVoiceStore.endpoint(this.endpointId) : undefined;
    if (!endpoint) { this.endpointId = ''; return; }
    this.name = endpoint.name; this.url = endpoint.url; this.model = endpoint.model;
    CastVoiceStore.analysisKey(endpoint.id)
      .then((key: string): void => { this.keySaved = key.length > 0; }).catch((): void => {});
  }
  onPageShow(): void { syncSystemBars(getContext(this), this.dark, ThemeRuntime.pageColor(this.dark)); }
  aboutToDisappear(): void { this.serial++; this.client.stop(); this.stopTicking(); }

  private stopTicking(): void {
    if (this.tickTimer >= 0) { clearInterval(this.tickTimer); this.tickTimer = -1; }
  }
  /** 测试中再点按钮：放弃这次测试。 */
  private cancelTest(): void {
    this.serial++;
    this.client.stop();
    this.stopTicking();
    this.testing = false;
    this.status = '已取消测试';
  }

  private async test(): Promise<void> {
    if (this.testing) return;
    const url = CastVoicePolicy.completionsUrl(this.url);
    const model = this.model.trim();
    this.passed = false;
    if (!CastVoicePolicy.validUrl(url)) { this.status = '接口地址要以 http:// 或 https:// 开头，例如 https://api.example.com/v1'; return; }
    if (!model) { this.status = '请填写模型名称'; return; }
    if (model.length > 120) { this.status = '模型名称太长'; return; }
    const serial = ++this.serial;
    this.testing = true; this.status = '正在测试…';
    const startedAt = Date.now();
    this.stopTicking();
    this.tickTimer = setInterval((): void => {
      if (serial !== this.serial || !this.testing) return;
      const seconds = Math.floor((Date.now() - startedAt) / 1000);
      this.status = seconds < 15 ? '正在测试…' : `正在测试…已等 ${seconds} 秒（最长 90 秒）。推理模型会先“思考”，可能较慢`;
    }, 1000);
    try {
      const key = this.apiKey.trim() || (this.endpointId ? await CastVoiceStore.analysisKey(this.endpointId) : '');
      if (serial !== this.serial) return;
      if (!key) { this.status = '请填写 API Key'; return; }
      const target = new MimoAnalysisTarget(); target.url = url; target.model = model;
      await this.client.analyze(key, MimoPolicy.split('小明说：“我们走吧。”'), [], '', undefined, target);
      if (serial !== this.serial) return;
      const idle = !CastVoiceStore.analysisReady() && !CastVoiceStore.usesCustomAnalysis();
      this.endpointId = await CastVoiceStore.saveEndpoint(this.endpointId, this.name, url, model, this.apiKey.trim());
      if (idle) CastVoiceStore.useEndpoint(this.endpointId);
      this.url = url; this.apiKey = ''; this.keySaved = true; this.passed = true;
      this.status = idle ? '测试通过，已保存并改用这个接口识别人物。' : '测试通过，已保存。';
      HdsFeedback.showToast('已保存');
      router.back();
    } catch (error) {
      if (serial === this.serial) this.status = '测试没通过：' + ((error as Error).message || '未知错误');
    } finally {
      if (serial === this.serial) { this.testing = false; this.stopTicking(); }
    }
  }

  build() {
    Stack() {
      PageScaffold({ title: this.endpointId ? '编辑接口' : '添加接口', content: () => { this.content() } })
    }.width('100%').height('100%')
  }

  // 按值传进 @Builder 的参数不会随状态刷新，所以输入框内容在这里直接读 this 上的状态。
  /** kind：0 名称，1 接口地址，2 模型，3 API Key。 */
  @Builder
  field(label: string, kind: number, onChange: (value: string) => void) {
    Column({ space: AppSpacing.SM }) {
      Text(label).fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
      TextInput({
        text: kind === 0 ? this.name : (kind === 1 ? this.url : (kind === 2 ? this.model : this.apiKey)),
        placeholder: kind === 0 ? '不填就用模型名称' : (kind === 1 ? 'https://api.example.com/v1' :
          (kind === 2 ? '模型名称' : (this.keySaved ? '已保存，不改就留空' : '填写密钥')))
      })
        .type(kind === 3 ? InputType.Password : InputType.Normal)
        .maxLength(kind === 3 ? 4096 : (kind === 0 ? 30 : (kind === 2 ? 120 : 500)))
        .backgroundColor(ThemeRuntime.inputColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
        .onChange((value: string) => onChange(value))
    }.width('100%')
  }

  @Builder
  content() {
    Column({ space: AppSpacing.LG }) {
      Column({ space: AppSpacing.XL }) {
        this.field('名称', 0, (value: string): void => { this.name = value; })
        this.field('接口地址', 1, (value: string): void => { this.url = value; })
        this.field('模型', 2, (value: string): void => { this.model = value; })
        this.field('API Key', 3, (value: string): void => { this.apiKey = value; })
      }.width('100%').padding(AppSpacing.XL).margin({ top: AppSpacing.SM })
      .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())

      if (this.status) {
        Text(this.status).fontSize(AppFontSize.BODY).width('100%')
          .fontColor(this.passed ? ThemeRuntime.successColor(this.dark) :
            (this.testing ? ThemeRuntime.subTextColor(this.dark) : ThemeRuntime.dangerColor(this.dark)))
      }

      Button(this.testing ? '取消测试' : '测试并保存').width('100%').height(44).fontSize(AppFontSize.BODY)
        .backgroundColor(this.testing ? ThemeRuntime.softFillColor(this.dark) : ThemeRuntime.buttonColor(this.dark))
        .fontColor(this.testing ? ThemeRuntime.primaryTextColor(this.dark) :
          ThemeRuntime.onAccentColor(ThemeRuntime.buttonColor(this.dark)))
        .onClick(() => { if (this.testing) this.cancelTest(); else this.test(); })

      Text('接口要兼容 OpenAI 的 chat/completions，并能按要求只输出 JSON。地址填到 /v1 即可，会自动补上 /chat/completions。' +
        '测试会发一句示例对白，产生极少量用量；密钥只保存在这台设备上，不进备份。')
        .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
        .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
    }.width('100%').constraintSize({ maxWidth: 760 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
  }
}
