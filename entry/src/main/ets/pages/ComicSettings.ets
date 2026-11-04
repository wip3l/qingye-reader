import { router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import {
  ReaderComicBackground,
  ReaderComicFit,
  ReaderComicMode,
  ReaderComicSettings,
  ReaderComicSettingsStore
} from '../core/reader/ReaderComicSettings';
import {
  ComicChineseConverter,
  ComicColorizer,
  ReaderComicSuperResolution,
  ReaderComicSuperResolutionAccess
} from '@legado/aiengine';
import { ComicColorDownloadPrompt } from '../utils/ComicColorDownloadPrompt';
import { ComicColorDownloadProgress } from '../components/reader/ComicColorDownloadProgress';
import { HdsFeedback } from '../utils/HdsFeedback';

/**
 * 阅读与收听 → 漫画：漫画的全局设置。与阅读页「阅读方式」「画面设置」面板读写同一份设置；
 * 按书单独设置的阅读方式只在阅读页里改。AI 着色、翻译按书保存，这里改的是没单独设置过的书用的默认值。
 */
@Entry
@Component
struct ComicSettingsPage {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  /** 会员档位变化（开通后返回本页）时刷新AI超分一行。 */
  @StorageProp('accountMembershipSku') membershipSku: string = '';
  @State settings: ReaderComicSettings = new ReaderComicSettings();
  /**
   * 读到已存设置后才建内容：selectItem 是按值传参的 @Builder，下拉框只认首次建出时的选中项，
   * 先用默认值建出来再异步读取，就会一直显示默认值。
   */
  @State loaded: boolean = false;
  @State modelStatus: string = '';
  @State modelReceivedBytes: number = 0;
  @State modelTotalBytes: number = 0;
  private modelRequest: number = 0;
  private pageVisible: boolean = false;

  private static readonly MODES: string[] = [ReaderComicMode.WEBTOON, ReaderComicMode.LTR, ReaderComicMode.RTL];
  private static readonly BACKGROUNDS: string[] =
    [ReaderComicBackground.BLACK, ReaderComicBackground.WHITE, ReaderComicBackground.THEME];
  private static readonly FITS: string[] = [ReaderComicFit.WIDTH, ReaderComicFit.SCREEN];

  onPageShow(): void {
    this.pageVisible = true;
    this.syncBars();
    ReaderComicSettingsStore.load(getContext(this)).then((settings: ReaderComicSettings): void => {
      this.settings = settings;
      this.loaded = true;
    });
  }

  onPageHide(): void {
    this.pageVisible = false;
  }

  aboutToDisappear(): void {
    // 离开页面就取消还在下的着色模型，和阅读页面板的行为一致。
    this.pageVisible = false;
    this.modelRequest++;
  }

  build() {
    Stack() {
      PageScaffold({ title: '漫画设置', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    if (this.loaded) {
      this.settingsContent()
    }
  }

  @Builder
  settingsContent() {
    this.sectionTitle('阅读方式')
    Column() {
      this.selectItem('默认阅读方式', '没单独设置过的漫画使用这里的方式',
        ComicSettingsPage.MODES.map((mode: string): SelectOption => ({ value: ReaderComicMode.label(mode) })),
        Math.max(0, ComicSettingsPage.MODES.indexOf(this.settings.defaultMode)), (index: number) => {
          this.update((next: ReaderComicSettings): void => {
            next.defaultMode = ComicSettingsPage.MODES[index] || ReaderComicMode.WEBTOON;
          });
        }, 'comic_settings_default_mode_select')
      SettingSwitchRow({
        title: '使用双翻页',
        description: '从左往右或从右往左阅读时，宽屏下并排显示两页；条漫不生效',
        isOn: this.settings.dualPage,
        onChange: (value: boolean) => {
          this.update((next: ReaderComicSettings): void => {
            next.dualPage = value;
          });
        }
      })
      SettingSwitchRow({
        title: '点击翻页',
        description: '点击屏幕两侧翻页（条漫为翻一屏），中间呼出菜单',
        isOn: this.settings.tapTurn,
        showDivider: false,
        onChange: (value: boolean) => {
          this.update((next: ReaderComicSettings): void => {
            next.tapTurn = value;
          });
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('画面')
    Column() {
      this.selectItem('背景', '图片四周和页间距的颜色',
        [{ value: '黑色' }, { value: '白色' }, { value: '跟随阅读主题' }],
        Math.max(0, ComicSettingsPage.BACKGROUNDS.indexOf(this.settings.background)), (index: number) => {
          this.update((next: ReaderComicSettings): void => {
            next.background = ComicSettingsPage.BACKGROUNDS[index] || ReaderComicBackground.BLACK;
          });
        }, 'comic_settings_background_select')
      this.selectItem('页间距', '条漫图片之间的间隔',
        [{ value: '无' }, { value: '小' }, { value: '大' }],
        Math.max(0, ReaderComicSettings.PAGE_GAPS.indexOf(this.settings.pageGap)), (index: number) => {
          this.update((next: ReaderComicSettings): void => {
            next.pageGap = ReaderComicSettings.PAGE_GAPS[index] ?? 0;
          });
        }, 'comic_settings_page_gap_select')
      this.selectItem('图片缩放', '条漫按宽度铺满，或整张放进一屏',
        [{ value: '适应宽度' }, { value: '适应屏幕' }],
        Math.max(0, ComicSettingsPage.FITS.indexOf(this.settings.fit)), (index: number) => {
          this.update((next: ReaderComicSettings): void => {
            next.fit = ComicSettingsPage.FITS[index] || ReaderComicFit.WIDTH;
          });
        }, 'comic_settings_fit_select')
      SettingSwitchRow({
        title: '双击缩放',
        description: '双击放大到 2 倍，再双击还原；关闭后单击响应更快',
        isOn: this.settings.doubleTapZoom,
        onChange: (value: boolean) => {
          this.update((next: ReaderComicSettings): void => {
            next.doubleTapZoom = value;
          });
        }
      })
      SettingSwitchRow({
        title: '信息条',
        description: '在右下角显示话名、页码、时间与电量',
        isOn: this.settings.infoBar,
        showDivider: false,
        onChange: (value: boolean) => {
          this.update((next: ReaderComicSettings): void => {
            next.infoBar = value;
          });
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('AI 功能')
    Column() {
      this.superResolutionRow()
      this.colorDefaultRow()
      this.textConvertDefaultRow()
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    Text('点击区域动作、屏幕方向、音量键翻页与小说共用，在上一页「阅读通用」中调整。AI 着色和翻译是默认值，在阅读页里给某本书单独开关过的以那本书为准；单本漫画的阅读方式也在阅读页里设置。')
      .fontSize(AppFontSize.CAPTION)
      .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.XXL })
  }

  @Builder
  superResolutionRow() {
    if (this.superResolutionAccess() === ReaderComicSuperResolutionAccess.READY) {
      SettingSwitchRow({
        title: 'AI超分',
        minimumMembership: 'MONTHLY',
        description: '借助AI把低清图片放大变清晰，处理好后自动替换；只处理正在看的图，会多耗一些电',
        isOn: this.settings.superResolution,
        onChange: (value: boolean) => {
          this.update((next: ReaderComicSettings): void => {
            next.superResolution = value;
          });
        }
      })
    } else if (this.superResolutionAccess() === ReaderComicSuperResolutionAccess.MEMBER_REQUIRED) {
      SettingNavRow({
        title: 'AI超分',
        minimumMembership: 'MONTHLY',
        description: this.settings.superResolution ? '会员已到期，续费后自动恢复' :
          '借助AI把低清图片放大变清晰',
        value: '开通会员',
        onTap: () => {
          router.pushUrl({ url: 'pages/AccountCenter' });
        }
      })
    } else {
      SettingSwitchRow({
        title: 'AI超分',
        minimumMembership: 'MONTHLY',
        description: '当前系统不支持，需要 API 26 及以上且支持图片超分的设备',
        isOn: false,
        switchEnabled: false
      })
    }
  }

  colorAccess(): string {
    const sku = this.membershipSku;
    if (!ComicColorizer.supported()) return ReaderComicSuperResolutionAccess.UNSUPPORTED;
    return sku !== undefined && ComicColorizer.memberAllowed() ?
      ReaderComicSuperResolutionAccess.READY : ReaderComicSuperResolutionAccess.MEMBER_REQUIRED;
  }

  textConvertAccess(): string {
    const sku = this.membershipSku;
    return sku !== undefined ? ComicChineseConverter.access() : ReaderComicSuperResolutionAccess.MEMBER_REQUIRED;
  }

  @Builder
  colorDefaultRow() {
    if (this.colorAccess() === ReaderComicSuperResolutionAccess.READY) {
      SettingSwitchRow({
        title: 'AI着色',
        minimumMembership: 'MONTHLY',
        description: '新打开的黑白漫画默认着色，当前画面优先；单张超长图暂不支持。首次开启需下载着色模型，开启后暂停AI超分',
        isOn: this.settings.colorDefault,
        switchEnabled: !this.modelStatus,
        onChange: (value: boolean) => {
          this.setColorDefault(value).catch((error: Error) => console.warn('保存默认着色失败:', error));
        }
      })
    } else if (this.colorAccess() === ReaderComicSuperResolutionAccess.MEMBER_REQUIRED) {
      SettingNavRow({
        title: 'AI着色',
        minimumMembership: 'MONTHLY',
        description: this.settings.colorDefault ? '会员已到期，续费后自动恢复' : '借助AI为黑白漫画着色',
        value: '开通会员',
        onTap: () => {
          router.pushUrl({ url: 'pages/AccountCenter' });
        }
      })
    } else {
      SettingSwitchRow({
        title: 'AI着色',
        minimumMembership: 'MONTHLY',
        description: '当前设备不支持本地着色引擎',
        isOn: false,
        switchEnabled: false
      })
    }
    if (this.modelStatus) {
      Column({ space: AppSpacing.MD }) {
        Text(this.modelStatus).fontSize(AppFontSize.CAPTION).fontColor(this.primaryTextColor()).width('100%')
        if (this.modelTotalBytes > 0) {
          ComicColorDownloadProgress({ receivedBytes: this.modelReceivedBytes, totalBytes: this.modelTotalBytes,
            accent: this.accentColor(), labelColor: ThemeRuntime.subTextColor(this.appDarkMode) })
        } else {
          LoadingProgress().width(24).height(24).color(this.accentColor())
        }
        Button('取消模型下载').onClick(() => { this.modelRequest++; })
      }
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.SM, bottom: AppSpacing.MD })
    }
  }

  /** 打开默认着色前先确保模型已下好；没下好时阅读页不会着色，开关打开也没用。 */
  async setColorDefault(value: boolean): Promise<void> {
    if (!value) {
      this.modelRequest++;
      this.update((next: ReaderComicSettings): void => { next.colorDefault = false; });
      return;
    }
    if (this.modelStatus) return;
    const ticket = ++this.modelRequest;
    const active = (): boolean => ticket === this.modelRequest && this.pageVisible && ComicColorizer.isAppForeground();
    let ready = false;
    try {
      ready = await ComicColorDownloadPrompt.ensure(getContext(this), this.getUIContext(), active,
        (status: string): void => { if (active()) this.modelStatus = status; },
        (received: number, total: number): void => {
          if (!active()) return;
          this.modelReceivedBytes = received;
          this.modelTotalBytes = total;
        });
    } catch (error) {
      if (active()) HdsFeedback.showToast((error as Error).message || '模型下载失败，请重试');
    } finally {
      this.modelStatus = '';
      this.modelReceivedBytes = 0;
      this.modelTotalBytes = 0;
    }
    if (ready && ticket === this.modelRequest) {
      this.update((next: ReaderComicSettings): void => { next.colorDefault = true; });
    } else {
      // 没开成时把开关拨回去：开关显示的是 settings 里的值，换一份新对象让它刷新。
      this.settings = this.settings.copy();
    }
  }

  @Builder
  textConvertDefaultRow() {
    if (this.textConvertAccess() === ReaderComicSuperResolutionAccess.READY) {
      this.selectItem('AI翻译', '新打开的漫画默认转换对白；日→中、韩→中即将推出',
        [{ value: '关闭' }, { value: '繁→简' }], this.settings.textConvertDefault ? 1 : 0,
        (index: number) => {
          this.update((next: ReaderComicSettings): void => { next.textConvertDefault = index === 1; });
        }, 'comic_settings_text_convert_default_select', false, 'MONTHLY')
    } else if (this.textConvertAccess() === ReaderComicSuperResolutionAccess.MEMBER_REQUIRED) {
      SettingNavRow({
        title: 'AI翻译',
        minimumMembership: 'MONTHLY',
        description: this.settings.textConvertDefault ? '会员已到期，续费后自动恢复' : '借助AI识别并转换漫画对白',
        value: '开通会员',
        showDivider: false,
        onTap: () => {
          router.pushUrl({ url: 'pages/AccountCenter' });
        }
      })
    } else {
      SettingNavRow({
        title: 'AI翻译',
        minimumMembership: 'MONTHLY',
        description: '当前设备不支持系统文字识别',
        value: '',
        showDivider: false
      })
    }
  }

  superResolutionAccess(): string {
    // 读取会员档位只为让档位变化时界面重算；是否有效以账号快照按服务端时间推算为准。
    const sku = this.membershipSku;
    return sku !== undefined ? ReaderComicSuperResolution.access() : ReaderComicSuperResolutionAccess.MEMBER_REQUIRED;
  }

  update(mutate: (settings: ReaderComicSettings) => void): void {
    const next = this.settings.copy();
    mutate(next);
    this.settings = next;
    ReaderComicSettingsStore.save(getContext(this), next).catch((error: Error) => {
      console.warn('保存漫画设置失败:', error);
    });
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  @Builder
  selectItem(title: string, desc: string, options: SelectOption[], selected: number,
    onSelect: (index: number) => void, controlId: string, showDivider: boolean = true, minimumMembership: string = '') {
    SettingRow({ title: title, description: desc, showDivider: showDivider, minimumMembership: minimumMembership }) {
      Select(options)
        .id(controlId)
        .selected(selected)
        .value(selected >= 0 && selected < options.length ? options[selected].value : '')
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => {
          onSelect(index);
        })
    }
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
  }
}
