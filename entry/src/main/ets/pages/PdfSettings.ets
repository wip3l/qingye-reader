import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingSwitchRow } from '../components/common/SettingRow';
import { ReaderPdfSettings } from '../core/book/pdf/ReaderPdfSettings';
import { ReaderPdfSettingsStore } from '../core/book/pdf/ReaderPdfSettingsStore';
import { ReaderComicSuperResolution, ReaderComicSuperResolutionAccess } from '@legado/aiengine';
import { AiAccessPolicy } from '../account/AiAccessPolicy';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';

/** Reading settings → PDF: default preferences, below explicit per-book choices. */
@Entry
@Component
struct PdfSettingsPage {
  @StorageProp('appDarkMode') darkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
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
        SettingSwitchRow({ title: '双页显示', description: '宽屏窗口下并排显示两页，窄窗口自动使用单页', isOn: this.settings.doublePage,
          onChange: (checked: boolean): void => {
            this.update((next: ReaderPdfSettings): void => { next.doublePage = checked; });
          } })
        SettingSwitchRow({ title: '适配整页', description: '关闭后按页面宽度显示', isOn: this.settings.fitPage, showDivider: false,
          onChange: (checked: boolean): void => {
            this.update((next: ReaderPdfSettings): void => { next.fitPage = checked; });
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
