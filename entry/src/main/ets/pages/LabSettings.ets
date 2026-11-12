import { promptAction, router } from '@kit.ArkUI';
import pasteboard from '@ohos.pasteboard';
import { Book } from '@legado/sourceengine';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { lanReaderServer } from '../core/lan/LanReaderServer';
import { LanReaderPasswordStore } from '../core/lan/LanReaderPasswordStore';
import { HdsFeedback } from '../utils/HdsFeedback';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { NetworkSettingsStore } from '../utils/NetworkSettingsStore';
import { WebParseSettingsStore } from '../utils/WebParseSettingsStore';
import { AppDatabase } from '../model/data/AppDatabase';

/**
 * 我的 › 实验室：网页解析总开关及其名下的入口（解析规则、搜索与发现、安卓备份导入、兼容与诊断），
 * 以及浏览器看书。网页解析关闭时这里只剩开关和浏览器看书。
 */
@Entry
@Component
struct LabSettingsPage {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('webParseEnabled') @Watch('onWebParseEnabledChanged') webParseEnabled: boolean = false;
  @StorageProp('webParseNoticePending') webParseNoticePending: boolean = false;
  /** 开关的显示状态。用户拨动后先跟着变，取消确认时再拨回去。 */
  @State webParseSwitchOn: boolean = false;
  @State webParseSwitching: boolean = false;
  @StorageLink('networkForceHttp1') networkForceHttp1: boolean = false;
  @StorageLink('readerImageConcurrency') readerImageConcurrency: number = 4;
  @State savingNetwork: boolean = false;
  @State savingImageConcurrency: boolean = false;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('lanReaderEnabled') lanReaderEnabled: boolean = false;
  @StorageLink('lanReaderAddress') lanReaderAddress: string = '';
  @StorageLink('lanReaderStatus') lanReaderStatus: string = '已关闭';
  @StorageLink('lanReaderToken') lanReaderToken: string = '';
  @StorageLink('lanReaderPassword') lanReaderPassword: string = '';
  @StorageProp('lanReaderPasswordUnreadable') lanReaderPasswordUnreadable: boolean = false;
  @StorageLink('lanReaderBackgroundStatus') lanReaderBackgroundStatus: string = '未启动';
  @State lanReaderPasswordDraft: string = '';

  aboutToAppear(): void {
    this.webParseSwitchOn = this.webParseEnabled;
    this.lanReaderPasswordDraft = this.lanReaderPasswordUnreadable ? '' : this.lanReaderPassword;
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
      PageScaffold({ title: '实验室', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    Text('这里放的是还在打磨的功能，可能不太稳定，之后也可能调整或下线。')
      .fontSize(AppFontSize.CAPTION)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })

    this.sectionTitle('网页解析')
    Column() {
      SettingSwitchRow({
        title: '网页解析',
        description: '用你自己添加的规则打开网页，并排成适合阅读的版式。开启前请先看一下使用须知',
        isOn: this.webParseSwitchOn,
        switchEnabled: !this.webParseSwitching,
        showDivider: this.webParseEnabled,
        onChange: (value: boolean) => { this.onWebParseSwitch(value); }
      })
      if (this.webParseEnabled) {
        if (this.webParseNoticePending) {
          SettingNavRow({
            title: '请确认使用须知',
            description: '继续使用网页解析前，请先看一下使用须知',
            titleColor: ThemeRuntime.warningColor(this.appDarkMode),
            onTap: () => { this.openNotice(true); }
          })
        }
        SettingNavRow({
          title: '解析规则',
          description: '添加、编辑和管理你自己的规则',
          onTap: () => {
            router.pushUrl({ url: 'pages/BookSource' });
          }
        })
        SettingNavRow({
          title: '搜索与发现',
          description: '搜索范围、结果合并、发现页排序',
          onTap: () => {
            router.pushUrl({ url: 'pages/SearchExploreSettings' });
          }
        })
        SettingNavRow({
          title: '导入安卓阅读备份',
          description: '导入安卓版阅读导出的 ZIP 备份，恢复规则、书架、阅读进度和记录',
          onTap: () => {
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/DataBackup',
              params: { mode: 'import', sourceFormat: 'legado-android' }
            });
          }
        })
        SettingNavRow({
          title: '使用须知',
          description: '查看网页解析使用须知',
          showDivider: false,
          onTap: () => { this.openNotice(false); }
        })
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    if (this.webParseEnabled) {
      this.sectionTitle('兼容与诊断')
      Column() {
        SettingRow({ title: '图片下载并发', description: '默认 4 张；网络较快时可提高，图片站限流或加载不稳时调回 4 张' }) {
          Select([{ value: '4 张' }, { value: '8 张' }, { value: '12 张' }])
            .selected(Math.max(0, [4, 8, 12].indexOf(this.readerImageConcurrency)))
            .value(`${this.readerImageConcurrency} 张`)
            .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
            .optionFont({ family: this.applicationFontFamily })
            .selectedOptionFont({ family: this.applicationFontFamily })
            .fontColor(this.primaryTextColor())
            .backgroundColor(Color.Transparent)
            .enabled(!this.savingImageConcurrency)
            .onSelect((index: number) => { this.saveImageConcurrency([4, 8, 12][index] || 4); })
        }
        SettingSwitchRow({
          title: 'HTTP/1.1 兼容模式',
          description: '网页连接反复出现传输错误时可尝试开启，对后续原生网络请求生效',
          isOn: this.networkForceHttp1,
          onChange: (value: boolean) => { this.saveHttpCompatibility(value); }
        })
        SettingNavRow({
          title: '后台脚本线程验证',
          description: '检查 QuickJS 后台线程的响应、超时取消与并发',
          showDivider: false,
          onTap: () => {
            router.pushUrl({ url: 'pages/ScriptThreadProbe' });
          }
        })
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(this.cardColor())
    }

    this.sectionTitle('浏览器看书')
    Column() {
      SettingSwitchRow({
        title: '浏览器看书',
        description: '同一局域网内的设备可用浏览器访问本机书架',
        isOn: this.lanReaderEnabled,
        onChange: (value: boolean) => {
          this.setLanReaderEnabled(value);
        }
      })
      if (this.lanReaderEnabled) {
        this.lanReaderAddressRow()
        this.lanReaderPasswordRow()
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, bottom: AppSpacing.XXL })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
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
        message: (hidden > 0 ? `关闭后，发现、搜索和解析规则会收起来，书架上 ${hidden} 本通过网页解析添加的书也会暂时隐藏。` :
          '关闭后，发现、搜索和解析规则会收起来。') +
          '\n你的规则、书籍、进度和缓存都还在，重新开启就能恢复。',
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

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  private async saveHttpCompatibility(value: boolean): Promise<void> {
    if (this.savingNetwork) return;
    this.savingNetwork = true;
    try {
      await NetworkSettingsStore.save(this.getUIContext().getHostContext()!, value);
    } catch (_) {
      HdsFeedback.showToast('网络设置保存失败，请重试');
    } finally {
      this.savingNetwork = false;
    }
  }

  private async saveImageConcurrency(value: number): Promise<void> {
    if (this.savingImageConcurrency) return;
    this.savingImageConcurrency = true;
    try {
      await NetworkSettingsStore.saveImageConcurrency(this.getUIContext().getHostContext()!, value);
    } catch (_) {
      HdsFeedback.showToast('图片并发设置保存失败，请重试');
    } finally {
      this.savingImageConcurrency = false;
    }
  }

  lanReaderUrl(): string {

    return this.lanReaderAddress;
  }

  @Builder
  lanReaderPasswordRow() {
    Column() {
      Text('访问密码（可选）')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Row({ space: AppSpacing.MD }) {
        TextInput({ text: this.lanReaderPasswordDraft, placeholder: '留空则无需密码' })
          .type(InputType.Password)
          .layoutWeight(1)
          .onChange((value: string) => this.lanReaderPasswordDraft = value)
        Button(this.lanReaderPassword ? '修改' : '设置')
          .fontSize(AppFontSize.BODY)
          .onClick(() => this.saveLanReaderPassword())
        if (this.lanReaderPassword) {
          Button('清除')
            .fontSize(AppFontSize.BODY)
            .onClick(() => {
              this.lanReaderPasswordDraft = '';
              this.saveLanReaderPassword();
            })
        }
      }
      .width('100%')
      .margin({ top: AppSpacing.MD })
      Text(this.lanReaderPasswordUnreadable ? '已保存的密码无法读取，浏览器访问已锁定，请重新设置密码' :
        (this.lanReaderPassword ? '已设置密码，访问地址无需携带 token' : '未设置密码，局域网内打开地址即可进入'))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .margin({ top: AppSpacing.XS })
        .width('100%')
    }
    .width('calc(100% - 32vp)')
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })
  }

  async saveLanReaderPassword(): Promise<void> {
    const password = this.lanReaderPasswordDraft.trim();
    if (password.length > 64) {
      HdsFeedback.showToast('密码最多 64 个字符');
      return;
    }
    try {
      await LanReaderPasswordStore.save(getContext(this), password);
    } catch (error) {
      HdsFeedback.showToast(`访问密码保存失败：${(error as Error).message}`);
      return;
    }
    lanReaderServer.setPassword(password);
    this.lanReaderPasswordDraft = password;
    HdsFeedback.showToast(password ? '访问密码已设置' : '已取消访问密码');
  }

  @Builder
  lanReaderAddressRow() {
    Row() {
      Text(this.lanReaderUrl() || this.lanReaderStatus)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .maxLines(2)
        .onClick(() => this.copyLanReaderAddress())
      Button() {
        Text('⧉')
          .fontSize(AppFontSize.TITLE)
      }
      .width(40)
      .height(36)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.copyLanReaderAddress())
    }
    .width('calc(100% - 32vp)')
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.MD })
    .alignItems(VerticalAlign.Center)
  }

  async copyLanReaderAddress(): Promise<void> {
    const address = this.lanReaderUrl();
    if (!address) return;
    try {
      const board = pasteboard.getSystemPasteboard();
      await board.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, address));
      HdsFeedback.showToast('访问地址已复制');
    } catch (error) {
      console.error('复制浏览器看书地址失败', error);
      HdsFeedback.showToast('复制失败，请长按地址复制');
    }
  }

  async setLanReaderEnabled(enabled: boolean): Promise<void> {
    this.lanReaderEnabled = enabled;
    if (!enabled) {
      await lanReaderServer.stop();
      return;
    }
    try {
      await lanReaderServer.start(getContext(this));
    } catch (error) {
      this.lanReaderEnabled = false;
      this.lanReaderStatus = '启动失败';
      console.error('浏览器看书服务启动失败', error);
    }
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }
}
