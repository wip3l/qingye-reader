import { promptAction, router } from '@kit.ArkUI';
import { Book } from '@legado/sourceengine';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingSwitchRow } from '../components/common/SettingRow';
import { AppSpacing } from '../theme/AppSpacing';
import { WebParseSettingsStore } from '../utils/WebParseSettingsStore';
import { AppDatabase } from '../model/data/AppDatabase';

/**
 * 我的 › 在线阅读：网页解析总开关、使用须知和安卓备份导入。
 * 入口和页面标题叫“在线阅读”好让人认出用途，开关本身和须知仍叫“网页解析”。
 * 书源管理、搜索与发现在开启后直接出现在“我的”页，这里不重复放。
 * 开关关闭时界面用“规则”这个中性叫法，开启（已同意须知）后才出现“书源”。
 */
@Entry
@Component
struct WebParseSettingsPage {
  @StorageProp('webParseEnabled') @Watch('onWebParseEnabledChanged') webParseEnabled: boolean = false;
  @StorageProp('webParseNoticePending') webParseNoticePending: boolean = false;
  /** 开关的显示状态。用户拨动后先跟着变，取消确认时再拨回去。 */
  @State webParseSwitchOn: boolean = false;
  @State webParseSwitching: boolean = false;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;

  aboutToAppear(): void {
    this.webParseSwitchOn = this.webParseEnabled;
    this.syncBars();
  }

  onPageShow(): void {
    // 从须知页没同意就返回时，把拨开的开关拨回去。
    this.webParseSwitchOn = this.webParseEnabled;
    this.syncBars();
  }

  onWebParseEnabledChanged(): void {
    this.webParseSwitchOn = this.webParseEnabled;
  }

  build() {
    Stack() {
      PageScaffold({ title: '在线阅读', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    Column() {
      SettingSwitchRow({
        title: '网页解析',
        description: this.webParseEnabled ? '用你自己添加的书源打开网页，并排成适合阅读的版式' :
          '用你自己添加的规则打开网页，并排成适合阅读的版式。开启前请先看一下使用须知',
        isOn: this.webParseSwitchOn,
        switchEnabled: !this.webParseSwitching,
        onChange: (value: boolean) => { this.onWebParseSwitch(value); }
      })
      if (this.webParseEnabled && this.webParseNoticePending) {
        SettingNavRow({
          title: '请确认使用须知',
          description: '继续使用网页解析前，请先看一下使用须知',
          titleColor: ThemeRuntime.warningColor(this.appDarkMode),
          onTap: () => { this.openNotice(true); }
        })
      }
      SettingNavRow({
        title: '使用须知',
        description: '查看网页解析使用须知',
        showDivider: false,
        onTap: () => { this.openNotice(false); }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))

    if (this.webParseEnabled) {
      Column() {
        SettingNavRow({
          title: '导入安卓阅读备份',
          description: '导入安卓版阅读导出的 ZIP 备份，恢复书源、书架、阅读进度和记录',
          showDivider: false,
          onTap: () => {
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/DataBackup',
              params: { mode: 'import', sourceFormat: 'legado-android' }
            });
          }
        })
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.LG, bottom: AppSpacing.XXL })
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
    }
  }

  openNotice(accept: boolean): void {
    router.pushUrl({ url: 'pages/WebParseNotice', params: { mode: accept ? 'accept' : 'view' } });
  }

  onWebParseSwitch(value: boolean): void {
    if (this.webParseSwitching || value === this.webParseSwitchOn) return;
    this.webParseSwitchOn = value;
    if (value === this.webParseEnabled) return;
    if (value) {
      // 同意须知后由须知页打开开关。
      this.openNotice(true);
      return;
    }
    this.confirmDisableWebParse();
  }

  /** 关闭前说明会发生什么：在线书籍从书架隐藏但不删除，重新开启即恢复。 */
  async confirmDisableWebParse(): Promise<void> {
    this.webParseSwitching = true;
    try {
      let hidden = 0;
      try {
        const db = AppDatabase.getInstance();
        await db.initWithContext(getContext(this));
        hidden = (await db.getAllBooks()).filter((book: Book): boolean =>
          !book.pendingAddToShelf && book.origin !== 'local').length;
      } catch (error) {
        console.warn('统计在线书籍失败:', error);
      }
      const answer = await promptAction.showDialog({
        title: '关闭网页解析？',
        message: (hidden > 0 ? `关闭后，发现、搜索和书源管理会收起来，书架上 ${hidden} 本通过网页解析添加的书也会暂时隐藏。` :
          '关闭后，发现、搜索和书源管理会收起来。') +
          '\n你的书源、书籍、进度和缓存都还在，重新开启就能恢复。',
        buttons: [{ text: '取消', color: ThemeRuntime.subTextColor(this.appDarkMode) },
          { text: '关闭', color: ThemeRuntime.dangerColor(this.appDarkMode) }]
      });
      if (answer.index !== 1) {
        this.webParseSwitchOn = this.webParseEnabled;
        return;
      }
      await WebParseSettingsStore.disable(getContext(this));
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (error) {
      // 点对话框外面关闭也算取消。
      this.webParseSwitchOn = this.webParseEnabled;
    } finally {
      this.webParseSwitching = false;
    }
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
  }
}
