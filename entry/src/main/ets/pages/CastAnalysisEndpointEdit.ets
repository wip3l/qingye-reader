import { router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { CastVoicePolicy } from '../core/mimo/CastVoicePolicy';
import { MimoPolicy } from '../core/mimo/MimoPolicy';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { CastVoiceStore } from '../utils/mimo/CastVoiceStore';
import { AnalysisModelList, MimoAnalysisTarget, MimoClient } from '../utils/mimo/MimoClient';
import { HdsFeedback } from '../utils/HdsFeedback';
import { syncSystemBars } from '../utils/SystemBars';

class CastAnalysisEndpointEditParams {
  id: string = '';
}

/** 模型列表读到哪一步：没读、读取中、读到了、接口没给。 */
enum ModelListState { IDLE, LOADING, READY, NONE }

/** 模型框下拉里最多列几条；模型多时靠输入缩小范围。 */
const DROP_LIMIT: number = 8;

/**
 * 添加或修改一个识别人物用的接口（兼容 OpenAI chat/completions）。
 * 地址和密钥填好后自动向接口要一次模型列表（GET /models，不产生用量）：读到了，模型框带下拉箭头，
 * 输入时下拉按输入筛选、点一项填入；读不到就是普通输入框，照旧手填。
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
  @State models: string[] = [];
  @State modelListState: ModelListState = ModelListState.IDLE;
  @State modelListNote: string = '';
  @State dropOpen: boolean = false;
  private client: MimoClient = new MimoClient();
  private listClient: MimoClient = new MimoClient();
  private serial: number = 0;
  private listSerial: number = 0;
  private listTimer: number = -1;
  /** 上次成功读取时用的“地址 密钥”，没变就不重复请求。 */
  private listedFor: string = '';
  /** 测试进行中每秒刷新“已等几秒”，让人知道没卡死。 */
  private tickTimer: number = -1;

  aboutToAppear(): void {
    this.endpointId = (router.getParams() as CastAnalysisEndpointEditParams)?.id || '';
    const endpoint = this.endpointId ? CastVoiceStore.endpoint(this.endpointId) : undefined;
    if (!endpoint) { this.endpointId = ''; return; }
    this.name = endpoint.name; this.url = endpoint.url; this.model = endpoint.model;
    CastVoiceStore.analysisKey(endpoint.id)
      .then((key: string): void => {
        this.keySaved = key.length > 0;
        if (this.keySaved) this.scheduleModelList(0);
      }).catch((): void => {});
  }
  onPageShow(): void { syncSystemBars(getContext(this), this.dark, ThemeRuntime.pageColor(this.dark)); }
  aboutToDisappear(): void {
    this.serial++; this.listSerial++;
    this.client.stop(); this.listClient.stop();
    this.stopTicking();
    if (this.listTimer >= 0) { clearTimeout(this.listTimer); this.listTimer = -1; }
  }

  private stopTicking(): void {
    if (this.tickTimer >= 0) { clearInterval(this.tickTimer); this.tickTimer = -1; }
  }

  // ---- 模型列表 ----

  /** 地址或密钥改了：稍等一下再读，免得边打字边请求。 */
  private scheduleModelList(delay: number = 800): void {
    if (this.listTimer >= 0) clearTimeout(this.listTimer);
    this.listTimer = setTimeout((): void => {
      this.listTimer = -1;
      this.loadModelList(false);
    }, delay);
  }

  private async loadModelList(force: boolean): Promise<void> {
    const url = CastVoicePolicy.completionsUrl(this.url);
    if (!CastVoicePolicy.validUrl(url)) {
      this.listSerial++; this.listClient.stop();
      this.models = []; this.modelListState = ModelListState.IDLE; this.modelListNote = ''; this.listedFor = '';
      return;
    }
    const key = this.apiKey.trim() || (this.endpointId && this.keySaved ? await CastVoiceStore.analysisKey(this.endpointId) : '');
    if (!key) {
      this.models = []; this.modelListState = ModelListState.IDLE; this.modelListNote = ''; this.listedFor = '';
      return;
    }
    const wanted = url + ' ' + key;
    if (!force && wanted === this.listedFor && this.modelListState !== ModelListState.IDLE) return;
    const serial = ++this.listSerial;
    this.listClient.stop();
    this.modelListState = ModelListState.LOADING;
    this.modelListNote = '正在读取模型列表…';
    const result: AnalysisModelList = await this.listClient.listModels(key, url);
    if (serial !== this.listSerial) return;
    this.listedFor = wanted;
    this.models = result.models;
    if (result.models.length > 0) {
      this.modelListState = ModelListState.READY;
      this.modelListNote = `已从接口读到 ${result.models.length} 个模型`;
    } else {
      this.modelListState = ModelListState.NONE;
      this.dropOpen = false;
      this.modelListNote = result.status === 401 || result.status === 403 ?
        '密钥无效或没有权限，读不到模型列表，请手动填写' : '接口没给模型列表，请手动填写';
    }
  }

  /** 下拉里列出的模型：按输入筛选（不分大小写）；输入正好是某个模型名时列出全部，方便换一个。 */
  private dropModels(): string[] {
    const text = this.model.trim().toLowerCase();
    const exact = this.models.some((item: string): boolean => item.toLowerCase() === text);
    const matched = !text || exact ? this.models :
      this.models.filter((item: string): boolean => item.toLowerCase().includes(text));
    return matched.slice(0, DROP_LIMIT);
  }

  private dropMatchedCount(): number {
    const text = this.model.trim().toLowerCase();
    const exact = this.models.some((item: string): boolean => item.toLowerCase() === text);
    if (!text || exact) return this.models.length;
    return this.models.filter((item: string): boolean => item.toLowerCase().includes(text)).length;
  }

  private pickModel(name: string): void {
    this.model = name;
    this.dropOpen = false;
    this.passed = false;
  }

  // ---- 测试并保存 ----

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
    this.dropOpen = false;
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
  /** kind：0 名称，1 接口地址，3 API Key（模型框单独见 modelField）。 */
  @Builder
  field(label: string, kind: number, onChange: (value: string) => void) {
    Column({ space: AppSpacing.SM }) {
      Text(label).fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
      TextInput({
        text: kind === 0 ? this.name : (kind === 1 ? this.url : this.apiKey),
        placeholder: kind === 0 ? '不填就用模型名称' : (kind === 1 ? 'https://api.example.com/v1' :
          (this.keySaved ? '已保存，不改就留空' : '填写密钥'))
      })
        .type(kind === 3 ? InputType.Password : InputType.Normal)
        .maxLength(kind === 3 ? 4096 : (kind === 0 ? 30 : 500))
        .backgroundColor(ThemeRuntime.inputColor(this.dark)).fontColor(ThemeRuntime.primaryTextColor(this.dark))
        .onChange((value: string) => onChange(value))
    }.width('100%')
  }

  /** 一个模型框：读到列表时右侧带下拉箭头，输入时下拉按输入筛选；读不到就是普通输入框。 */
  @Builder
  modelField() {
    Column({ space: AppSpacing.SM }) {
      Text('模型').fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
      Row() {
        TextInput({
          text: this.model,
          placeholder: this.modelListState === ModelListState.READY ? '填写模型名，或从列表选' : '模型名称'
        })
          .maxLength(120)
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .fontColor(ThemeRuntime.primaryTextColor(this.dark))
          .onChange((value: string) => {
            if (value === this.model) return;
            this.model = value;
            this.passed = false;
            if (this.modelListState === ModelListState.READY) this.dropOpen = true;
          })
          .onEditChange((editing: boolean) => {
            if (editing && this.modelListState === ModelListState.READY) this.dropOpen = true;
          })
        if (this.modelListState === ModelListState.READY) {
          Stack() {
            SymbolGlyph(this.dropOpen ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
              .fontSize(16)
              .fontColor([ThemeRuntime.subTextColor(this.dark)])
          }
          .width(44)
          .height(40)
          .accessibilityText(this.dropOpen ? '收起模型列表' : '展开模型列表')
          .onClick(() => { this.dropOpen = !this.dropOpen; })
        }
      }
      .width('100%')
      .borderRadius(ThemeRuntime.mediumRadius())
      .backgroundColor(ThemeRuntime.inputColor(this.dark))

      if (this.dropOpen && this.modelListState === ModelListState.READY && this.dropModels().length > 0) {
        Column() {
          ForEach(this.dropModels(), (item: string) => {
            Row({ space: AppSpacing.SM }) {
              Text(item)
                .fontSize(AppFontSize.BODY)
                .fontColor(item === this.model ? ThemeRuntime.accentColor(this.dark) :
                  ThemeRuntime.primaryTextColor(this.dark))
                .wordBreak(WordBreak.BREAK_ALL)
                .layoutWeight(1)
              if (CastVoicePolicy.thinkingOnlyModel(item)) {
                Text('只会思考·不推荐')
                  .fontSize(11)
                  .fontColor(ThemeRuntime.warningColor(this.dark))
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(6)
                  .backgroundColor(`#22${ThemeRuntime.warningColor(this.dark).substring(1)}`)
              }
              if (item === this.model) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(16)
                  .fontColor([ThemeRuntime.accentColor(this.dark)])
              }
            }
            .width('100%')
            .constraintSize({ minHeight: 44 })
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: 8, bottom: 8 })
            .borderRadius(ThemeRuntime.mediumRadius())
            .backgroundColor(item === this.model ? ThemeRuntime.softFillColor(this.dark) : Color.Transparent)
            .onClick(() => this.pickModel(item))
          }, (item: string) => item)
          if (this.dropMatchedCount() > DROP_LIMIT) {
            Text(`还有 ${this.dropMatchedCount() - DROP_LIMIT} 个，继续输入可以缩小范围`)
              .fontSize(AppFontSize.CAPTION)
              .fontColor(ThemeRuntime.subTextColor(this.dark))
              .width('100%')
              .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: 6, bottom: 8 })
          }
        }
        .width('100%')
        .padding(4)
        .borderRadius(ThemeRuntime.mediumRadius())
        .backgroundColor(ThemeRuntime.cardColor(this.dark))
        .shadow({ radius: 16, color: '#26000000', offsetY: 6 })
        .border({ width: 0.5, color: ThemeRuntime.hairlineColor(this.dark) })
      }

      if (this.modelListState !== ModelListState.IDLE) {
        Row({ space: 6 }) {
          if (this.modelListState === ModelListState.LOADING) {
            LoadingProgress().width(14).height(14).color(ThemeRuntime.subTextColor(this.dark))
          } else {
            SymbolGlyph(this.modelListState === ModelListState.READY ? $r('sys.symbol.checkmark_circle') :
              $r('sys.symbol.exclamationmark_triangle'))
              .fontSize(13)
              .fontColor([this.modelListState === ModelListState.READY ? ThemeRuntime.successColor(this.dark) :
                ThemeRuntime.warningColor(this.dark)])
          }
          Text(this.modelListNote)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.modelListState === ModelListState.READY ? ThemeRuntime.successColor(this.dark) :
              (this.modelListState === ModelListState.NONE ? ThemeRuntime.warningColor(this.dark) :
                ThemeRuntime.subTextColor(this.dark)))
            .layoutWeight(1)
          if (this.modelListState !== ModelListState.LOADING) {
            Text(this.modelListState === ModelListState.READY ? '重新读取' : '重试')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(ThemeRuntime.accentColor(this.dark))
              .onClick(() => { this.loadModelList(true); })
          }
        }
        .width('100%')
      }
    }.width('100%')
  }

  @Builder
  content() {
    Column({ space: AppSpacing.LG }) {
      Column({ space: AppSpacing.XL }) {
        this.field('接口地址', 1, (value: string): void => { this.url = value; this.dropOpen = false; this.scheduleModelList(); })
        this.field('API Key', 3, (value: string): void => { this.apiKey = value; this.dropOpen = false; this.scheduleModelList(); })
        this.modelField()
        this.field('名称', 0, (value: string): void => { this.name = value; this.dropOpen = false; })
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
        '地址和密钥填好后会向接口要一次模型列表（不产生用量）；接口不提供列表时照旧手动填写。' +
        '测试会发一句示例对白，产生极少量用量；密钥只保存在这台设备上，不进备份。')
        .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
        .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
    }.width('100%').constraintSize({ maxWidth: 760 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
  }
}
