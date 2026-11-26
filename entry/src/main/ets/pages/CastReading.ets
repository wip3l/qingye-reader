import { router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingSwitchRow } from '../components/common/SettingRow';
import { CastAvatar, CastPill } from '../components/CastVoiceViews';
import { CastScheme, CastVoicePolicy, CastVoiceRef } from '../core/mimo/CastVoicePolicy';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { CastVoiceStore } from '../utils/mimo/CastVoiceStore';
import { MimoStore } from '../utils/mimo/MimoStore';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ThemedDialog } from '../utils/ThemedDialog';
import { syncSystemBars } from '../utils/SystemBars';

/**
 * 多角色朗读的入口：总开关、人物识别用的模型、音色方案、人物档案与音色标签。
 * 人物由 MiMo 的文本模型识别，声音来自已下载的离线音色和自定义音色。
 */
@Entry
@Component
struct CastReadingPage {
  @StorageProp('appDarkMode') dark: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('castVoiceEnabled') castOn: boolean = false;
  @StorageProp('castVoiceRevision') @Watch('refresh') revision: number = 0;
  @StorageProp('mimoConfigured') @Watch('refresh') mimoConfigured: boolean = false;
  @StorageProp('mimoAnalysisAvailable') @Watch('refresh') analysisAvailable: boolean = false;
  @State schemes: CastScheme[] = [];
  @State schemeId: string = '';
  @State untagged: number = 0;
  @State books: number = 0;
  @State analysisTitle: string = '';
  @StorageProp('castAnalysisCustom') @Watch('refresh') analysisCustom: boolean = false;

  aboutToAppear(): void {
    MimoStore.load();
    this.refresh();
  }
  onPageShow(): void {
    syncSystemBars(getContext(this), this.dark, ThemeRuntime.pageColor(this.dark));
    this.refresh();
  }
  refresh(): void {
    try {
      const library = CastVoiceStore.library();
      this.schemes = library.schemes.slice();
      this.schemeId = library.schemeId;
      this.untagged = CastVoiceStore.untaggedCount();
      this.books = MimoStore.castSummaries().length;
      this.analysisTitle = CastVoiceStore.analysisTitle();
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }


  private async toggle(on: boolean): Promise<void> {
    if (!on) { CastVoiceStore.setEnabled(false); return; }
    if (!CastVoiceStore.analysisReady()) {
      const result = await ThemedDialog.showDialog(this.getUIContext(), {
        title: '先配置分析模型', message: '多角色朗读靠一个文本模型识别每句话是谁说的。可以用 MiMo 的密钥，也可以填别家兼容接口，测试通过后才能开启。',
        buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.dark) },
          { text: '去配置', color: ThemeRuntime.accentColor(this.dark) }]
      });
      if (result.index === 1) router.pushUrl({ url: 'pages/CastAnalysisModel' });
      return;
    }
    try {
      CastVoiceStore.prepareDefaultScheme();
      const blocker = CastVoiceStore.blocker();
      if (blocker) {
        HdsFeedback.showToast('先给方案选一个旁白音色');
        router.pushUrl({ url: 'pages/CastSchemeEdit', params: { id: CastVoiceStore.scheme().id } });
        return;
      }
      CastVoiceStore.setEnabled(true);
    } catch (error) { HdsFeedback.showToast((error as Error).message); }
  }

  private newScheme(): void {
    router.pushUrl({ url: 'pages/CastSchemeEdit', params: { id: '' } });
  }

  private schemeSummary(scheme: CastScheme): string {
    const count = CastVoicePolicy.schemeVoices(scheme).length;
    if (count === 0) return '还没有选音色';
    const offline = CastVoicePolicy.schemeVoices(scheme).every((ref: CastVoiceRef): boolean => ref.kind === 'local');
    return `${count} 个音色` + (offline ? ' · 不用联网合成' : '');
  }

  build() {
    Stack() {
      PageScaffold({ title: '多角色朗读', content: () => { this.content() } })
    }.width('100%').height('100%')
  }

  @Builder
  sectionLabel(title: string, tool: string, onTool: () => void) {
    Row() {
      Text(title).fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium)
        .fontColor(ThemeRuntime.primaryTextColor(this.dark)).layoutWeight(1)
      if (tool) {
        Text(tool).fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.accentColor(this.dark))
          .padding({ left: AppSpacing.LG, top: AppSpacing.XS, bottom: AppSpacing.XS })
          .onClick(() => onTool())
      }
    }.width('100%').padding({ left: AppSpacing.XXS, right: AppSpacing.XXS, top: AppSpacing.SM })
  }

  @Builder
  schemeCard(scheme: CastScheme) {
    Row({ space: AppSpacing.LG }) {
      Column({ space: AppSpacing.MD }) {
        Text(scheme.name).fontSize(AppFontSize.BODY_LARGE).fontWeight(FontWeight.Medium)
          .fontColor(ThemeRuntime.primaryTextColor(this.dark))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Row({ space: AppSpacing.MD }) {
          Row() {
            CastAvatar({ label: '旁', gender: 'unknown', diameter: 26 })
            CastAvatar({ label: '男', gender: 'male', diameter: 26 }).margin({ left: -7 })
            CastAvatar({ label: '女', gender: 'female', diameter: 26 }).margin({ left: -7 })
          }
          Text(this.schemeSummary(scheme)).fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.dark)).maxLines(1)
          if (scheme.id === this.schemeId) { CastPill({ text: '正在使用', tone: 'accent' }) }
        }.width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([ThemeRuntime.subTextColor(this.dark)])
    }
    .width('100%').padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: 14, bottom: 14 })
    .backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())
    .border({ width: scheme.id === this.schemeId ? 1.5 : 0, color: ThemeRuntime.accentColor(this.dark) })
    .onClick(() => router.pushUrl({ url: 'pages/CastSchemeEdit', params: { id: scheme.id } }))
  }

  @Builder
  content() {
    Column({ space: AppSpacing.LG }) {
      Column() {
        SettingSwitchRow({ title: '多角色朗读', description: '识别每句话是谁说的，旁白和人物用不同的音色朗读。',
          isOn: this.castOn, showDivider: false, onChange: (on: boolean): void => { this.toggle(on); } })
      }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())

      this.sectionLabel('人物识别', '', (): void => {})
      Column() {
        SettingNavRow({ title: '分析模型', value: this.analysisTitle, showDivider: false,
          onTap: (): void => { router.pushUrl({ url: 'pages/CastAnalysisModel' }); } })
      }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())

      this.sectionLabel('音色方案', '新建', (): void => this.newScheme())
      ForEach(this.schemes, (scheme: CastScheme) => {
        this.schemeCard(scheme)
      }, (scheme: CastScheme): string => scheme.id + '|' + scheme.name + '|' + this.schemeSummary(scheme) +
        (scheme.id === this.schemeId ? '*' : ''))

      this.sectionLabel('本书与档案', '', (): void => {})
      Column() {
        SettingNavRow({ title: '人物档案', description: this.books > 0 ? `${this.books} 本书` : '朗读后识别到的人物会记在这里',
          onTap: (): void => { router.pushUrl({ url: 'pages/MimoBooks' }); } })
        SettingNavRow({ title: '音色标签', description: this.untagged > 0 ? `${this.untagged} 个音色还没标` : '性别、年龄段、是否适合读旁白',
          showDivider: false, onTap: (): void => { router.pushUrl({ url: 'pages/CastVoiceTags' }); } })
      }.width('100%').backgroundColor(ThemeRuntime.cardColor(this.dark)).borderRadius(ThemeRuntime.cardRadius())

      Text('识别人物会把正文片段发给分析模型，产生少量用量。离线音色的合成在本机完成；拿不准是谁说的句子由旁白读。' +
        '不同音色的音量会自动拉到差不多一样。')
        .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.dark)).width('100%')
        .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
    }.width('100%').constraintSize({ maxWidth: 760 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
  }
}
