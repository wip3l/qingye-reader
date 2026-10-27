import { abilityDelegatorRegistry } from '@kit.TestKit';
import { ReaderFontWeightStepper } from '../../../main/ets/components/reader/ReaderFontWeightStepper';
import { ReaderWeightedText, ReaderWeightedTextSpan } from '../../../main/ets/components/reader/ReaderWeightedText';
import { ReaderSettings, ReaderSettingsStore } from '../../../main/ets/utils/ReaderSettingsStore';
import { ReaderRegexFontCodec, ReaderRegexFontRule } from '../../../main/ets/model/reader/ReaderRegexFontRule';

/** Uses entry_test preferences only; never edits the production reader's settings. */
@Entry
@Component
struct ReaderFontWeightStepperTest {
  @State bodyWeight: number = 400;
  @State titleWeight: number = 600;
  @State ruleWeight: number = 400;
  @State restored: boolean = false;
  private pending: Promise<void> = Promise.resolve();

  private save(): void {
    const settings = new ReaderSettings();
    settings.fontWeight = this.bodyWeight;
    settings.titleFontWeight = this.titleWeight;
    const rule = new ReaderRegexFontRule();
    rule.id = 'stepper-test'; rule.pattern = '测试'; rule.fontWeight = this.ruleWeight;
    settings.regexFontRulesRaw = ReaderRegexFontCodec.encode([rule]);
    this.pending = ReaderSettingsStore.saveReaderFontStyleSettings(getContext(this), settings);
  }

  build() {
    Column({ space: 8 }) {
      Text('字体粗细交互回归').fontSize(20)
      ReaderFontWeightStepper({ value: this.bodyWeight, scope: '正文', onChange: (value: number) => {
        this.bodyWeight = value; this.save();
      } })
      ReaderFontWeightStepper({ value: this.titleWeight, scope: '标题', onChange: (value: number) => {
        this.titleWeight = value; this.save();
      } })
      ReaderFontWeightStepper({ value: this.ruleWeight, scope: '规则', onChange: (value: number) => {
        this.ruleWeight = value; this.save();
      } })
      Text(`${this.bodyWeight}/${this.titleWeight}/${this.ruleWeight}`).id('weight_parent_state')
      ReaderWeightedText({ spans: [ReaderWeightedTextSpan.create(this.getUIContext(),
        '正文预览与状态同步', 22, '', '#202124')], weight: this.bodyWeight, maxLines: 2 })
      Button('设置下限').id('set_weight_min').onClick(() => { this.bodyWeight = 50; })
      Button('设置上限').id('set_weight_max').onClick(() => { this.bodyWeight = 900; })
      Button('清空显示').id('clear_weight_display').onClick(() => {
        this.bodyWeight = 400; this.titleWeight = 600; this.ruleWeight = 400;
      })
      Button('重新加载').id('reload_weight').onClick(async () => {
        await this.pending;
        const settings = await ReaderSettingsStore.reload(getContext(this));
        this.bodyWeight = settings.fontWeight;
        this.titleWeight = settings.titleFontWeight;
        this.ruleWeight = ReaderRegexFontCodec.decode(settings.regexFontRulesRaw)[0].fontWeight;
        this.restored = true;
      })
      Text(this.restored ? '已恢复' : '待测试').id('weight_reload_status')
      Button('结束测试').id('finish_weight_test').onClick(() => {
        abilityDelegatorRegistry.getAbilityDelegator().finishTest('UI session closed; see host assertions', 0);
      })
    }
    .width('100%').height('100%').padding({ top: 56, left: 12, right: 12 }).backgroundColor('#FFFFFF')
  }
}
