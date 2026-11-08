import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import { ReaderPdfSettings } from '../core/book/pdf/ReaderPdfSettings';
import { ReaderPdfSettingsStore } from '../core/book/pdf/ReaderPdfSettingsStore';
import { ReaderComicSuperResolution, ReaderComicSuperResolutionAccess } from '@legado/aiengine';
import { AiAccessPolicy } from '../account/AiAccessPolicy';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';

/** Reading settings → PDF: default preferences, below explicit per-book choices. */
@Entry
@Component
struct PdfSettingsPage {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageProp('accountMembershipSku') @Watch('refreshAccess') membershipSku: string = '';
  @StorageProp('accountEntitlementsRevision') @Watch('refreshAccess') accountRevision: number = 0;
  @StorageProp('aiTrialOpen') @Watch('refreshAccess') trialOpen: boolean = false;
  @State settings: ReaderPdfSettings = new ReaderPdfSettings();
  @State loaded: boolean = false;
  @State access: string = ReaderComicSuperResolutionAccess.UNSUPPORTED;
  private loadGeneration: number = 0;
  private saveGeneration: number = 0;

  onPageShow(): void {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    syncSystemBars(context, this.darkMode);
    AiAccessPolicy.refresh(); this.refreshAccess();
    const token = ++this.loadGeneration;
    ReaderPdfSettingsStore.load(context).then((settings: ReaderPdfSettings): void => {
      if (token !== this.loadGeneration) return;
      this.settings = settings; this.loaded = true;
    });
  }

  onPageHide(): void { this.loadGeneration++; }
  aboutToDisappear(): void { this.loadGeneration++; }

  refreshAccess(): void { this.access = ReaderComicSuperResolution.access(); }

  private update(mutate: (settings: ReaderPdfSettings) => void): void {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.loaded) return;
    const previous = this.settings;
    const next = previous.copy(); mutate(next);
    this.settings = next;
    const token = ++this.saveGeneration;
    ReaderPdfSettingsStore.save(context, next).catch((error: Error): void => {
      if (token === this.saveGeneration) this.settings = previous;
      console.warn('[PDF] defaults save failed:', error);
      HdsFeedback.showToast('PDF 设置保存失败，请重试');
    });
  }

  private openAccount(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/AccountCenter' })
      .catch((error: Error): void => { console.warn('[PDF] account page failed:', error); });
  }

  @Builder
  sectionTitle(label: string) {
    Text(label).fontSize(AppFontSize.BODY).fontColor(ThemeRuntime.subTextColor(this.darkMode)).width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  @Builder
  superResolutionRow() {
    if (this.access === ReaderComicSuperResolutionAccess.READY) {
      SettingSwitchRow({ title: 'AI超分', minimumMembership: AiAccessPolicy.trialOpen() ? '' : 'MONTHLY',
        description: '增强符合条件的低清扫描页，文字页保持原生显示；会增加耗电',
        isOn: this.settings.superResolution, showDivider: false,
        onChange: (checked: boolean): void => {
          this.refreshAccess();
          if (checked && this.access !== ReaderComicSuperResolutionAccess.READY) return;
          this.update((next: ReaderPdfSettings): void => { next.superResolution = checked; });
        } })
    } else if (this.access === ReaderComicSuperResolutionAccess.MEMBER_REQUIRED) {
      SettingNavRow({ title: 'AI超分', minimumMembership: AiAccessPolicy.trialOpen() ? '' : 'MONTHLY',
        description: AiAccessPolicy.blockedMessage(), value: AiAccessPolicy.actionText(), showDivider: false,
        onTap: (): void => { this.openAccount(); } })
    } else {
      SettingSwitchRow({ title: 'AI超分', description: '需要 API 26 及以上且支持图片超分的设备',
        isOn: false, switchEnabled: false, showDivider: false })
    }
  }

  @Builder
  pageContent() {
    if (this.loaded) {
      this.sectionTitle('阅读方式')
      Column() {
        SettingSwitchRow({ title: '连续滚动', description: '上下滑动，连续阅读文档', isOn: this.settings.continuous,
          onChange: (checked: boolean): void => {
            this.update((next: ReaderPdfSettings): void => { next.continuous = checked; });
          } })
        SettingSwitchRow({ title: '适配整页', description: '关闭后按页面宽度显示', isOn: this.settings.fitPage, showDivider: false,
          onChange: (checked: boolean): void => {
            this.update((next: ReaderPdfSettings): void => { next.fitPage = checked; });
          } })
      }.width('calc(100% - 24vp)').margin({ left: AppSpacing.LG, right: AppSpacing.LG })
        .borderRadius(ThemeRuntime.cardRadius()).clip(true).backgroundColor(ThemeRuntime.cardColor(this.darkMode))

      this.sectionTitle('画面')
      Column() {
        // 与漫画设置页的下拉行同一种写法；直接写在这里而不是按值 @Builder，选完下拉跟着刷新。
        SettingRow({ title: '夜间页面', description: '应用夜间模式时 PDF 页面的显示；反色把白纸变成深灰、黑字变成浅灰' }) {
          Select(ReaderPdfSettings.NIGHT_LABELS.map((label: string): SelectOption => ({ value: label })))
            .selected(Math.max(0, ReaderPdfSettings.NIGHT_MODES.indexOf(this.settings.nightMode)))
            .value(ReaderPdfSettings.NIGHT_LABELS[Math.max(0, ReaderPdfSettings.NIGHT_MODES.indexOf(this.settings.nightMode))])
            .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
            .optionFont({ family: this.applicationFontFamily })
            .selectedOptionFont({ family: this.applicationFontFamily })
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
            .backgroundColor(Color.Transparent)
            .arrowPosition(ArrowPosition.END)
            .padding({ left: 0, right: 0 })
            .borderRadius(16)
            .border({ width: 0 })
            .optionBgColor(Color.Transparent)
            .divider(null)
            .optionFontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .selectedOptionFontColor(ThemeRuntime.accentColor(this.darkMode))
            .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.darkMode))
            .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.darkMode))
            .menuBackgroundBlurStyle(BlurStyle.NONE)
            .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
            .onSelect((index: number): void => {
              this.update((next: ReaderPdfSettings): void => { next.nightMode = ReaderPdfSettings.NIGHT_MODES[index]; });
            })
        }
        SettingSwitchRow({ title: '页码角标', description: '阅读时右下角显示目录标题、页码、时间与电量',
          isOn: this.settings.pageBadge, showDivider: false,
          onChange: (checked: boolean): void => {
            this.update((next: ReaderPdfSettings): void => { next.pageBadge = checked; });
          } })
      }.width('calc(100% - 24vp)').margin({ left: AppSpacing.LG, right: AppSpacing.LG })
        .borderRadius(ThemeRuntime.cardRadius()).clip(true).backgroundColor(ThemeRuntime.cardColor(this.darkMode))

      this.sectionTitle('AI超分')
      Column() { this.superResolutionRow() }
        .width('calc(100% - 24vp)').margin({ left: AppSpacing.LG, right: AppSpacing.LG })
        .borderRadius(ThemeRuntime.cardRadius()).clip(true).backgroundColor(ThemeRuntime.cardColor(this.darkMode))

      Text('这里设置 PDF 的默认阅读方式，单本 PDF 在阅读页中单独调整过的选项优先。AI 超分默认关闭，开启后可在阅读菜单中查看原页对比；AI 可能改变细小文字或数字。')
        .fontSize(AppFontSize.CAPTION).fontColor(ThemeRuntime.subTextColor(this.darkMode)).width('100%')
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.XXL })
    }
  }

  build() {
    Stack() {
      PageScaffold({ title: 'PDF 设置', content: (): void => { this.pageContent(); } })
    }.width('100%').height('100%').expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
