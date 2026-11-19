import { router, promptAction } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { AppDatabase } from '../model/data/AppDatabase';
import { Book } from '@legado/sourceengine';
import { BookshelfDisplaySettingsStore } from '../utils/BookshelfDisplaySettingsStore';
import { SearchExplorePendingBook } from '../utils/SearchExplorePendingBook';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { PrivateShelfStore } from '../utils/PrivateShelfStore';
import { BiometricAuth, BiometricAuthOutcome } from '../utils/BiometricAuth';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { HdsFeedback } from '../utils/HdsFeedback';
import { LocalBookService } from '../core/book/LocalBookService';
import { BookDisplayHelper } from '../utils/BookDisplayHelper';
import { BookCoverCache } from '../utils/BookCoverCache';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import { ShelfGreetingEditor } from '../components/home/ShelfGreetingEditor';
import { ShelfSectionTitleEditor } from '../components/home/ShelfSectionTitleEditor';
import { ShelfGreetingTemplate } from '../utils/ShelfGreetingTemplate';
import { BookshelfSortHelper } from '../utils/BookshelfSortHelper';

@Entry
@Component
struct BookshelfSettingsPage {
  @StorageProp('applicationFontFamily') applicationFontFamily: string = '';
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('bookshelfShowTags') bookshelfShowTags: boolean = true;
  @StorageLink('bookshelfShowSource') bookshelfShowSource: boolean = true;
  @StorageLink('bookshelfShowIntro') bookshelfShowIntro: boolean = true;
  @StorageLink('bookshelfShowFullIntro') bookshelfShowFullIntro: boolean = false;
  @StorageLink('bookshelfShowProgressBar') bookshelfShowProgressBar: boolean = false;
  @StorageLink('bookshelfShowLastReadTime') bookshelfShowLastReadTime: boolean = true;
  @StorageLink('bookshelfShowLastReadChapter') bookshelfShowLastReadChapter: boolean = false;
  @StorageLink('bookshelfShowTypeBadge') bookshelfShowTypeBadge: boolean = true;
  @StorageLink('bookshelfLayoutMode') bookshelfLayoutMode: string = 'companion';
  @StorageLink('bookshelfLastReadLeafMode') bookshelfLastReadLeafMode: string = 'adaptive';
  @StorageLink('bookshelfLastReadPinMode') bookshelfLastReadPinMode: string = 'large';
  @StorageLink('bookshelfLastReadPinCount') bookshelfLastReadPinCount: number = 1;
  @StorageLink('bookshelfBookOpenAnimation') bookshelfBookOpenAnimation: boolean = true;
  @StorageLink('bookshelfTypeCategoryEnabled') bookshelfTypeCategoryEnabled: boolean = true;
  @StorageLink('bookshelfShowAllTypeTab') bookshelfShowAllTypeTab: boolean = true;
  @StorageLink('bookshelfCompanionStagger') bookshelfCompanionStagger: boolean = true;
  @StorageLink('bookshelfCompanionCoverShadow') bookshelfCompanionCoverShadow: boolean = true;
  @StorageLink('bookshelfTileCoverFrame') bookshelfTileCoverFrame: boolean = true;
  @StorageLink('bookshelfCompanionReadingNote') bookshelfCompanionReadingNote: boolean = true;
  @StorageLink('bookshelfGreetingMode') bookshelfGreetingMode: string = 'time';
  @StorageLink('bookshelfGreetingTitle') bookshelfGreetingTitle: string = '';
  @StorageLink('bookshelfGreetingSubtitle') bookshelfGreetingSubtitle: string = '';
  @StorageLink('bookshelfCompanionSectionTitle') bookshelfCompanionSectionTitle: string = '';
  @StorageLink('bookshelfAutoRefresh') bookshelfAutoRefresh: boolean = true;
  @StorageLink('bookshelfImmersive') bookshelfImmersive: boolean = false;
  @StorageLink('bookshelfImmersiveButtons') bookshelfImmersiveButtons: string = 'pull';
  @StorageLink('bookshelfRememberGroup') bookshelfRememberGroup: boolean = false;
  @StorageProp('webParseEnabled') webParseEnabled: boolean = false;
  @StorageProp('accountDisplayName') accountDisplayName: string = '';
  @StorageProp('shelfTodayReadMs') shelfTodayReadMs: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';

  @StorageLink('privateShelfEnabled') @Watch('onPrivateShelfEnabledChanged') privateShelfEnabled: boolean = false;
  @StorageLink('privateShelfHasPassword') privateShelfHasPassword: boolean = false;
  @StorageLink('privateShelfBiometric') @Watch('onPrivateShelfBiometricChanged') privateShelfBiometric: boolean = false;
  // 打开需要先通过一次系统验证，验证期间显示值与真实状态可以暂时不一致。
  @State privateShelfBiometricSwitchOn: boolean = false;
  // 开关的显示值。关闭需要先验证密码，验证期间它与真实状态可以暂时不一致。
  @State privateShelfSwitchOn: boolean = false;
  // 'disable'：关闭隐私书架前验证密码；'password'：设置、修改或清除密码。
  @State privatePasswordDialogMode: string = 'password';
  @State privatePasswordCurrent: string = '';
  @State privatePasswordNew: string = '';
  @State privatePasswordConfirm: string = '';
  @State privatePasswordError: string = '';
  @State privateShelfBusy: boolean = false;
  private privatePasswordDialogSession: SystemDialogSession = new SystemDialogSession();
  private greetingEditorDialogSession: SystemDialogSession = new SystemDialogSession();
  private sectionTitleEditorDialogSession: SystemDialogSession = new SystemDialogSession();

  aboutToAppear(): void {
    this.reloadDisplaySettings();
    this.reloadPrivateShelfSettings();
    this.syncBars();
  }

  aboutToDisappear(): void {
    this.privatePasswordDialogSession.close(this.getUIContext());
  }

  onPageShow(): void {
    this.reloadDisplaySettings();
    this.syncBars();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '书架设置', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    this.sectionTitle('布局与分类')
    Column() {
    this.selectItem('书架布局', '列表疏密、封面平铺，或带问候与阅读小记的陪伴首页',
      this.bookshelfLayoutOptions(), this.bookshelfLayoutSelectedIndex(), (index: number) => {
        this.bookshelfLayoutMode = index === 3 ? 'companion' : (index === 2 ? 'tile' : (index === 1 ? 'loose' : 'compact'));
        this.onDisplaySettingChanged();
      })
    if (this.bookshelfLayoutMode === 'tile') {
      this.itemDivider()
      this.selectItem('上次阅读置顶', '最近阅读的书排在最前的样式',
        this.lastReadPinOptions(), this.lastReadPinSelectedIndex(), (index: number) => {
          this.bookshelfLastReadPinMode = index === 0 ? 'off' : (index === 2 ? 'large' : 'medium');
          this.onDisplaySettingChanged();
        })
      this.itemDivider()
      SettingSwitchRow({
        title: '显示书籍边框',
        description: '封面的描边、投影与底色；关闭后封面直接放在书架上',
        isOn: this.bookshelfTileCoverFrame,
        showDivider: false,
        onChange: (value: boolean) => {
          this.bookshelfTileCoverFrame = value;
          this.onDisplaySettingChanged();
        }
      })
    }
    if ((this.bookshelfLayoutMode === 'tile' && this.bookshelfLastReadPinMode === 'large') ||
      this.bookshelfLayoutMode === 'companion') {
      this.itemDivider()
      this.selectItem('置顶数量', '按最近阅读排序，最多展示所选数量',
        this.lastReadPinCountOptions(),
        BookshelfDisplaySettingsStore.normalizeLastReadPinCount(this.bookshelfLastReadPinCount) - 1,
        (index: number) => {
          this.bookshelfLastReadPinCount = index + 1;
          this.onDisplaySettingChanged();
        })
    }
    if (this.bookshelfLayoutMode === 'companion') {
      this.itemDivider()
      SettingSwitchRow({
        title: '错落摆放',
        description: '书本高矮不一、偶有斜靠；关闭后大小一致、整齐立正',
        isOn: this.bookshelfCompanionStagger,
        showDivider: false,
        onChange: (value: boolean) => {
          this.bookshelfCompanionStagger = value;
          this.onDisplaySettingChanged();
        }
      })
      this.itemDivider()
      SettingSwitchRow({
        title: '封面阴影',
        description: '书本落在书架上的投影；关闭后书本不再有阴影',
        isOn: this.bookshelfCompanionCoverShadow,
        showDivider: false,
        onChange: (value: boolean) => {
          this.bookshelfCompanionCoverShadow = value;
          this.onDisplaySettingChanged();
        }
      })
      this.itemDivider()
      SettingSwitchRow({
        title: '阅读小记',
        description: '在继续阅读下方显示今日时长、近 7 天和连续阅读天数',
        isOn: this.bookshelfCompanionReadingNote,
        showDivider: false,
        onChange: (value: boolean) => {
          this.bookshelfCompanionReadingNote = value;
          this.onDisplaySettingChanged();
        }
      })
      this.itemDivider()
      this.selectItem('问候语', '书架左上角的两行文案，也可在书架上长按修改',
        this.greetingModeOptions(), this.greetingModeSelectedIndex(), (index: number) => {
          this.selectGreetingMode(index === 1 ? 'custom' : (index === 2 ? 'off' : 'time'));
        })
      if (this.bookshelfGreetingMode === 'custom') {
        this.itemDivider()
        this.actionItem('编辑问候语', this.greetingSummary(), this.primaryTextColor(), () => {
          this.openGreetingEditor();
        })
      }
      this.itemDivider()
      this.actionItem('书架标题',
        `${BookshelfDisplaySettingsStore.companionSectionTitleText(this.bookshelfCompanionSectionTitle)}，也可在书架上长按修改`,
        this.primaryTextColor(), () => {
          this.openSectionTitleEditor();
        })
    }
    if (this.bookshelfLayoutMode === 'tile' && this.bookshelfLastReadPinMode === 'medium') {
      this.itemDivider()
      this.selectItem('上次阅读扉页设置', '最近阅读书籍封面右侧的展示内容',
        this.lastReadLeafOptions(), this.lastReadLeafSelectedIndex(), (index: number) => {
          this.bookshelfLastReadLeafMode = index === 0 ? 'bookInfo' :
            (index === 1 ? 'contentPreview' : 'adaptive');
          this.onDisplaySettingChanged();
        })
    }
    this.itemDivider()
    SettingSwitchRow({
      title: '书籍分类',
      description: '书架顶部按小说、漫画、有声书等类型分页',
      isOn: this.bookshelfTypeCategoryEnabled,
      showDivider: false,
      onChange: (value: boolean) => {
        this.bookshelfTypeCategoryEnabled = value;
        this.onDisplaySettingChanged();
      }
    })
    if (this.bookshelfTypeCategoryEnabled) {
      this.itemDivider()
      SettingSwitchRow({
        title: '显示全部分类',
        description: '分类栏第一项为“全部”',
        isOn: this.bookshelfShowAllTypeTab,
        showDivider: false,
        onChange: (value: boolean) => {
          this.bookshelfShowAllTypeTab = value;
          this.onDisplaySettingChanged();
        }
      })
    }
    this.itemDivider()
    SettingSwitchRow({
      title: '书籍打开动画',
      description: '点击书籍时播放封面展开动画',
      isOn: this.bookshelfBookOpenAnimation,
      showDivider: false,
      onChange: (value: boolean) => {
        this.bookshelfBookOpenAnimation = value;
        this.onDisplaySettingChanged();
      }
    })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('进入书架')
    Column() {
    SettingSwitchRow({
      title: '沉浸书架',
      description: '进入书架时隐藏顶部按钮和底栏，向下滑动时出现',
      isOn: this.bookshelfImmersive,
      showDivider: false,
      onChange: (value: boolean) => {
        this.bookshelfImmersive = value;
        this.onDisplaySettingChanged();
      }
    })
    if (this.bookshelfImmersive) {
      this.itemDivider()
      this.selectItem('顶部按钮', '下拉显示：在书架顶部下拉时出现，几秒后收起；只留菜单按钮：右上角一个按钮收进全部操作',
        this.immersiveButtonsOptions(), this.immersiveButtonsSelectedIndex(),
        (index: number) => {
          this.bookshelfImmersiveButtons = index === 1 ? 'menu' : 'pull';
          this.onDisplaySettingChanged();
        })
    }
    this.itemDivider()
    SettingSwitchRow({
      title: '记住打开分组',
      description: '重新打开应用时回到上次所在的文件夹和分类；关闭后每次从书架首页开始',
      isOn: this.bookshelfRememberGroup,
      showDivider: false,
      onChange: (value: boolean) => {
        this.bookshelfRememberGroup = value;
        this.onDisplaySettingChanged();
      }
    })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('卡片信息')
    Column() {
    SettingSwitchRow({
      title: '书籍标签',
      description: '在书架卡片上显示标签',
      isOn: this.bookshelfShowTags,
      showDivider: false,
      onChange: (value: boolean) => {
        this.bookshelfShowTags = value;
        this.onDisplaySettingChanged();
      }
    })
    this.itemDivider()
    SettingSwitchRow({
      title: '书籍简介',
      description: '在书架卡片上显示简介',
      isOn: this.bookshelfShowIntro,
      showDivider: false,
      onChange: (value: boolean) => {
        this.bookshelfShowIntro = value;
        this.onDisplaySettingChanged();
      }
    })
    if (this.bookshelfShowIntro) {
      this.itemDivider()
      SettingSwitchRow({
        title: '显示全部简介',
        description: '简介不截断，完整显示',
        isOn: this.bookshelfShowFullIntro,
        showDivider: false,
        onChange: (value: boolean) => {
          this.bookshelfShowFullIntro = value;
          this.onDisplaySettingChanged();
        }
      })
    }
    this.itemDivider()
    SettingSwitchRow({
      title: '使用阅读进度条',
      description: '在卡片底部显示阅读百分比和阅读信息',
      isOn: this.bookshelfShowProgressBar,
      showDivider: false,
      onChange: (value: boolean) => {
        this.bookshelfShowProgressBar = value;
        this.onDisplaySettingChanged();
      }
    })
    if (this.bookshelfShowProgressBar) {
      this.itemDivider()
      SettingSwitchRow({
        title: '显示最后阅读时间',
        description: '在进度条旁显示上次阅读时间',
        isOn: this.bookshelfShowLastReadTime,
        showDivider: false,
        onChange: (value: boolean) => {
          this.bookshelfShowLastReadTime = value;
          this.onDisplaySettingChanged();
        }
      })
      this.itemDivider()
      SettingSwitchRow({
        title: '显示最后阅读章节',
        description: '在进度条旁显示上次阅读章节',
        isOn: this.bookshelfShowLastReadChapter,
        showDivider: false,
        onChange: (value: boolean) => {
          this.bookshelfShowLastReadChapter = value;
          this.onDisplaySettingChanged();
        }
      })
    }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('封面')
    Column() {
    this.navItem('封面设置', '封面来源与先后顺序、图集、多张封面的显示方式、封面标识', 'pages/CoverSettings')
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    if (this.webParseEnabled) {
      this.sectionTitle('书籍更新')
      Column() {
        SettingSwitchRow({
          title: '自动获取更新',
          description: '打开应用时在后台检查连载书籍的新章节；关闭后只在下拉书架时检查',
          isOn: this.bookshelfAutoRefresh,
          showDivider: false,
          onChange: (value: boolean) => {
            this.bookshelfAutoRefresh = value;
            this.onDisplaySettingChanged();
          }
        })
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(this.cardColor())
    }

    this.sectionTitle('隐私书架')
    Column() {
      this.privateShelfSwitchItem()
      if (this.privateShelfEnabled) {
        this.itemDivider()
        this.actionItem('隐私书架密码',
          this.privateShelfHasPassword ? '已设置，进入时需输入' : '未设置',
          this.primaryTextColor(), () => {
            this.openPrivatePasswordDialog('password');
          })
        if (this.privateShelfHasPassword) {
          this.itemDivider()
          this.privateShelfBiometricItem()
        }
        this.itemDivider()
        this.actionItem('重置隐私书架', '删除全部隐私书籍并关闭，忘记密码时使用', ThemeRuntime.dangerColor(this.appDarkMode), () => {
          this.confirmResetPrivateShelf();
        })
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
  }

  async reloadDisplaySettings(): Promise<void> {
    try {
      const settings = await BookshelfDisplaySettingsStore.load(getContext(this));
      this.bookshelfShowTags = settings.showTags;
      this.bookshelfShowSource = settings.showSource;
      this.bookshelfShowIntro = settings.showIntro;
      this.bookshelfShowFullIntro = settings.showFullIntro;
      this.bookshelfShowProgressBar = settings.showProgressBar;
      this.bookshelfShowLastReadTime = settings.showLastReadTime;
      this.bookshelfShowLastReadChapter = settings.showLastReadChapter;
      this.bookshelfShowTypeBadge = settings.showTypeBadge;
      this.bookshelfLayoutMode = settings.layoutMode;
      this.bookshelfLastReadLeafMode = settings.lastReadLeafMode;
      this.bookshelfLastReadPinMode = settings.lastReadPinMode;
      this.bookshelfLastReadPinCount = settings.lastReadPinCount;
      this.bookshelfBookOpenAnimation = settings.bookOpenAnimation;
      this.bookshelfTypeCategoryEnabled = settings.typeCategoryEnabled;
      this.bookshelfShowAllTypeTab = settings.showAllTypeTab;
      this.bookshelfCompanionStagger = settings.companionStagger;
      this.bookshelfCompanionCoverShadow = settings.companionCoverShadow;
      this.bookshelfCompanionReadingNote = settings.companionReadingNote;
      this.bookshelfTileCoverFrame = settings.tileCoverFrame;
      this.bookshelfGreetingMode = settings.greetingMode;
      this.bookshelfGreetingTitle = settings.greetingTitle;
      this.bookshelfGreetingSubtitle = settings.greetingSubtitle;
      this.bookshelfCompanionSectionTitle = settings.companionSectionTitle;
      this.bookshelfAutoRefresh = settings.autoRefresh;
      this.bookshelfImmersive = settings.immersive;
      this.bookshelfImmersiveButtons = settings.immersiveButtons;
      this.bookshelfRememberGroup = settings.rememberGroup;
    } catch (e) {
      console.warn('重新加载书架显示设置失败:', e);
    }
  }

  async reloadPrivateShelfSettings(): Promise<void> {
    try {
      await PrivateShelfStore.load(getContext(this));
    } catch (e) {
      console.warn('加载隐私书架设置失败:', e);
    }
    this.privateShelfSwitchOn = this.privateShelfEnabled;
    this.privateShelfBiometricSwitchOn = this.privateShelfBiometric;
  }

  onPrivateShelfEnabledChanged(): void {
    this.privateShelfSwitchOn = this.privateShelfEnabled;
  }

  onPrivateShelfBiometricChanged(): void {
    this.privateShelfBiometricSwitchOn = this.privateShelfBiometric;
  }

  async onPrivateShelfBiometricSwitchChanged(value: boolean): Promise<void> {
    if (value === this.privateShelfBiometric || this.privateShelfBusy) return;
    this.privateShelfBiometricSwitchOn = value;
    this.privateShelfBusy = true;
    try {
      if (value) {
        if (!BiometricAuth.isAvailable()) {
          HdsFeedback.showToast('请先在系统设置里录入指纹或人脸');
          return;
        }
        // 先确认本机认证能走通，免得打开后每次进入都要绕回密码。
        const outcome = await BiometricAuth.authenticate('开启指纹或人脸解锁');
        if (outcome === BiometricAuthOutcome.FAILED) HdsFeedback.showToast('未通过验证，没有开启');
        if (outcome !== BiometricAuthOutcome.SUCCESS) return;
      }
      await PrivateShelfStore.setBiometric(getContext(this), value);
    } catch (e) {
      console.warn('保存隐私书架指纹/人脸设置失败:', e);
      HdsFeedback.showToast('保存失败');
    } finally {
      this.privateShelfBusy = false;
      this.privateShelfBiometricSwitchOn = this.privateShelfBiometric;
    }
  }

  onPrivateShelfSwitchChanged(value: boolean): void {
    if (value === this.privateShelfEnabled) return;
    this.privateShelfSwitchOn = value;
    if (!value && this.privateShelfHasPassword) {
      this.openPrivatePasswordDialog('disable');
      return;
    }
    this.applyPrivateShelfEnabled(value);
  }

  async applyPrivateShelfEnabled(enabled: boolean): Promise<void> {
    try {
      await PrivateShelfStore.setEnabled(getContext(this), enabled);
    } catch (e) {
      console.warn('保存隐私书架开关失败:', e);
      HdsFeedback.showToast('保存失败');
    }
    this.privateShelfSwitchOn = this.privateShelfEnabled;
  }

  openPrivatePasswordDialog(mode: string): void {
    this.privatePasswordDialogMode = mode;
    this.privatePasswordCurrent = '';
    this.privatePasswordNew = '';
    this.privatePasswordConfirm = '';
    this.privatePasswordError = '';
    // 只能用按钮关闭：点蒙层关掉的话，“关闭隐私书架”的开关会停在错误的位置。
    this.privatePasswordDialogSession.open(this.getUIContext(), (): void => {
      this.privatePasswordDialogContent();
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示隐私书架密码弹窗失败:'
    });
  }

  closePrivatePasswordDialog(): void {
    this.privatePasswordDialogSession.close(this.getUIContext());
    this.privatePasswordCurrent = '';
    this.privatePasswordNew = '';
    this.privatePasswordConfirm = '';
    this.privatePasswordError = '';
    this.privateShelfSwitchOn = this.privateShelfEnabled;
  }

  async submitPrivatePasswordDialog(): Promise<void> {
    if (this.privateShelfBusy) return;
    this.privateShelfBusy = true;
    try {
      const context = getContext(this);
      if (this.privateShelfHasPassword &&
        !(await PrivateShelfStore.verifyPassword(context, this.privatePasswordCurrent))) {
        this.privatePasswordError = '当前密码不正确';
        return;
      }
      if (this.privatePasswordDialogMode === 'disable') {
        await PrivateShelfStore.setEnabled(context, false);
        this.closePrivatePasswordDialog();
        return;
      }
      if (this.privatePasswordNew !== this.privatePasswordConfirm) {
        this.privatePasswordError = '两次输入的新密码不一致';
        return;
      }
      if (!this.privatePasswordNew && !this.privateShelfHasPassword) {
        this.privatePasswordError = '请输入密码';
        return;
      }
      const cleared = !this.privatePasswordNew;
      await PrivateShelfStore.setPassword(context, this.privatePasswordNew);
      this.closePrivatePasswordDialog();
      HdsFeedback.showToast(cleared ? '已清除隐私书架密码' : '隐私书架密码已设置');
    } catch (e) {
      console.warn('保存隐私书架密码失败:', e);
      this.privatePasswordError = '保存失败，请重试';
    } finally {
      this.privateShelfBusy = false;
    }
  }

  async confirmResetPrivateShelf(): Promise<void> {
    const confirmation = await promptAction.showDialog({
      title: '重置隐私书架',
      message: '该操作会删除所有隐私书籍，包括进度、书签等，并关闭隐私书架选项',
      buttons: [{ text: '取消', color: this.subTextColor() }, { text: '确认', color: ThemeRuntime.dangerColor(this.appDarkMode) }]
    });
    if (confirmation.index !== 1 || this.privateShelfBusy) return;
    this.privateShelfBusy = true;
    try {
      const context = getContext(this);
      const db = AppDatabase.getInstance();
      await db.initWithContext(context);
      const privateBooks = (await db.getAllBooks()).filter((book: Book) => book.isPrivate);
      for (const book of privateBooks) {
        const covers = [
          ...BookDisplayHelper.decodeCoverList(book.customCoverUrl),
          ...BookDisplayHelper.decodeCoverList(book.coverUrl)
        ];
        for (const cover of covers) {
          BookCoverCache.deleteCachedCover(context, cover);
        }
        LocalBookService.deleteLocalBookFiles(context, book);
        await db.deleteBook(book.bookUrl, 'private_shelf_reset');
        // 阅读时长的 dayKey 形如 2026-10-10，这个区间覆盖全部日期。
        await db.deleteReadStatsForBook(book.bookUrl, '0000-00-00', '9999-99-99');
      }
      await PrivateShelfStore.reset(context);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      HdsFeedback.showToast('隐私书架已重置');
    } catch (e) {
      console.error('重置隐私书架失败:', e);
      HdsFeedback.showToast('重置失败');
    } finally {
      this.privateShelfBusy = false;
      this.privateShelfSwitchOn = this.privateShelfEnabled;
    }
  }

  onDisplaySettingChanged(): void {
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    const settings = BookshelfDisplaySettingsStore.fromStorage();
    settings.showTags = this.bookshelfShowTags;
    settings.showSource = this.bookshelfShowSource;
    settings.showIntro = this.bookshelfShowIntro;
    settings.showFullIntro = this.bookshelfShowFullIntro;
    settings.showProgressBar = this.bookshelfShowProgressBar;
    settings.showLastReadTime = this.bookshelfShowLastReadTime;
    settings.showLastReadChapter = this.bookshelfShowLastReadChapter;
    settings.showTypeBadge = this.bookshelfShowTypeBadge;
    settings.layoutMode = this.bookshelfLayoutMode;
    settings.lastReadLeafMode = this.bookshelfLastReadLeafMode;
    settings.lastReadPinMode = this.bookshelfLastReadPinMode;
    settings.lastReadPinCount = this.bookshelfLastReadPinCount;
    settings.bookOpenAnimation = this.bookshelfBookOpenAnimation;
    settings.typeCategoryEnabled = this.bookshelfTypeCategoryEnabled;
    settings.showAllTypeTab = this.bookshelfShowAllTypeTab;
    settings.companionStagger = this.bookshelfCompanionStagger;
    settings.companionCoverShadow = this.bookshelfCompanionCoverShadow;
    settings.companionReadingNote = this.bookshelfCompanionReadingNote;
    settings.tileCoverFrame = this.bookshelfTileCoverFrame;
    settings.greetingMode = this.bookshelfGreetingMode;
    settings.greetingTitle = this.bookshelfGreetingTitle;
    settings.greetingSubtitle = this.bookshelfGreetingSubtitle;
    settings.companionSectionTitle = this.bookshelfCompanionSectionTitle;
    settings.autoRefresh = this.bookshelfAutoRefresh;
    settings.immersive = this.bookshelfImmersive;
    settings.immersiveButtons = this.bookshelfImmersiveButtons;
    settings.rememberGroup = this.bookshelfRememberGroup;
    BookshelfDisplaySettingsStore.applyToStorage(settings);
    BookshelfDisplaySettingsStore.save(getContext(this), settings).catch((e: Error) => {
      console.warn('保存书架显示设置失败:', e);
    });
  }

  immersiveButtonsOptions(): SelectOption[] {
    return [{ value: '下拉显示' }, { value: '只留菜单按钮' }];
  }

  immersiveButtonsSelectedIndex(): number {
    return this.bookshelfImmersiveButtons === 'menu' ? 1 : 0;
  }

  greetingModeOptions(): SelectOption[] {
    return [{ value: '按时段' }, { value: '自定义' }, { value: '不显示' }];
  }

  greetingModeSelectedIndex(): number {
    if (this.bookshelfGreetingMode === 'custom') return 1;
    return this.bookshelfGreetingMode === 'off' ? 2 : 0;
  }

  greetingSummary(): string {
    const lines = [this.bookshelfGreetingTitle, this.bookshelfGreetingSubtitle].filter((line: string) => !!line);
    return lines.length > 0 ? lines.join(' / ') : '未填写，显示默认问候';
  }

  /** 切到自定义时若还没写过，先填入和内置一样的文案，书架上看起来不变，再打开编辑框。 */
  selectGreetingMode(mode: string): void {
    if (mode === 'custom' && !this.bookshelfGreetingTitle && !this.bookshelfGreetingSubtitle) {
      const draft = ShelfGreetingTemplate.defaultDraft(new Date().getHours());
      this.bookshelfGreetingTitle = draft[0];
      this.bookshelfGreetingSubtitle = draft[1];
    }
    this.bookshelfGreetingMode = mode;
    this.onDisplaySettingChanged();
    if (mode === 'custom') this.openGreetingEditor();
  }

  async openGreetingEditor(): Promise<void> {
    // 预览里的 {在读} 用书架上最近读的那本。
    let readingBookName = '';
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const books = PrivateShelfStore.publicBooks(SearchExplorePendingBook.filterShelfBooks(await db.getAllBooks()));
      const latest = BookshelfSortHelper.getPinnedRecentReadBooks(books, 1);
      readingBookName = latest.length > 0 ? latest[0].name : '';
    } catch (e) {
      console.warn('读取最近阅读书籍失败:', e);
    }
    const title = this.bookshelfGreetingTitle;
    const subtitle = this.bookshelfGreetingSubtitle;
    this.greetingEditorDialogSession.open(this.getUIContext(), (): void => {
      this.greetingEditorDialogContent(title, subtitle, readingBookName);
    }, {
      // 写到一半误触蒙层或返回键不能丢稿，只能点取消或保存关闭。
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示问候语编辑弹窗失败:'
    });
  }

  @Builder
  greetingEditorDialogContent(title: string, subtitle: string, readingBookName: string) {
    ShelfGreetingEditor({
      appDarkMode: this.appDarkMode,
      initialTitle: title,
      initialSubtitle: subtitle,
      nickname: this.accountDisplayName,
      todayReadMs: this.shelfTodayReadMs,
      readingBookName: readingBookName,
      onSave: (nextTitle: string, nextSubtitle: string): void => {
        this.bookshelfGreetingMode = 'custom';
        this.bookshelfGreetingTitle = nextTitle;
        this.bookshelfGreetingSubtitle = nextSubtitle;
        this.onDisplaySettingChanged();
        this.greetingEditorDialogSession.close(this.getUIContext());
      },
      onSaveDefault: (): void => {
        this.bookshelfGreetingMode = 'time';
        this.bookshelfGreetingTitle = '';
        this.bookshelfGreetingSubtitle = '';
        this.onDisplaySettingChanged();
        this.greetingEditorDialogSession.close(this.getUIContext());
      },
      onCancel: (): void => this.greetingEditorDialogSession.close(this.getUIContext())
    })
  }

  openSectionTitleEditor(): void {
    const title = this.bookshelfCompanionSectionTitle;
    this.sectionTitleEditorDialogSession.open(this.getUIContext(), (): void => {
      this.sectionTitleEditorDialogContent(title);
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示书架标题编辑弹窗失败:'
    });
  }

  @Builder
  sectionTitleEditorDialogContent(title: string) {
    ShelfSectionTitleEditor({
      appDarkMode: this.appDarkMode,
      initialTitle: title,
      onSave: (nextTitle: string): void => {
        this.bookshelfCompanionSectionTitle = nextTitle;
        this.onDisplaySettingChanged();
        this.sectionTitleEditorDialogSession.close(this.getUIContext());
      },
      onCancel: (): void => this.sectionTitleEditorDialogSession.close(this.getUIContext())
    })
  }

  bookshelfLayoutOptions(): SelectOption[] {
    return [{ value: '紧凑' }, { value: '宽松' }, { value: '平铺' }, { value: '陪伴' }];
  }

  bookshelfLayoutSelectedIndex(): number {
    if (this.bookshelfLayoutMode === 'companion') return 3;
    return this.bookshelfLayoutMode === 'tile' ? 2 : (this.bookshelfLayoutMode === 'loose' ? 1 : 0);
  }

  lastReadPinOptions(): SelectOption[] {
    return [{ value: '关闭' }, { value: '中' }, { value: '大' }];
  }

  lastReadPinCountOptions(): SelectOption[] {
    return [{ value: '1本' }, { value: '2本' }, { value: '3本' }, { value: '4本' }, { value: '5本' }];
  }

  lastReadPinSelectedIndex(): number {
    return this.bookshelfLastReadPinMode === 'off' ? 0 : (this.bookshelfLastReadPinMode === 'large' ? 2 : 1);
  }

  lastReadLeafOptions(): SelectOption[] {
    return [{ value: '书籍信息' }, { value: '内容预览' }, { value: '自适应' }];
  }

  lastReadLeafSelectedIndex(): number {
    return this.bookshelfLastReadLeafMode === 'bookInfo' ? 0 :
      (this.bookshelfLastReadLeafMode === 'contentPreview' ? 1 : 2);
  }

  optionValue(options: SelectOption[], index: number): ResourceStr {
    if (index >= 0 && index < options.length) {
      return options[index].value;
    }
    return '';
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

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
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

  @Builder
  itemDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(ThemeRuntime.hairlineColor(this.appDarkMode))
      .width('calc(100% - 32vp)')
      .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
  }

  @Builder
  selectItem(title: string, desc: string, options: SelectOption[], selected: number, onSelect: (index: number) => void) {
    SettingRow({ title: title, description: desc, showDivider: false }) {
      Select(options)
        .selected(selected)
        .value(this.optionValue(options, selected))
        .font({ size: AppFontSize.BODY, family: this.applicationFontFamily })
        .optionFont({ family: this.applicationFontFamily })
        .selectedOptionFont({ family: this.applicationFontFamily })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
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

  // 取消关闭时开关要能弹回去，所以 isOn 绑定单独的 privateShelfSwitchOn 状态。
  @Builder
  privateShelfSwitchItem() {
    SettingSwitchRow({
      title: '隐私书架',
      description: '双击书架顶部空白处进入，在隐私书架里双击返回；顶部不显示入口，关闭后隐私书籍仍隐藏',
      isOn: this.privateShelfSwitchOn,
      showDivider: false,
      onChange: (checked: boolean) => {
        this.onPrivateShelfSwitchChanged(checked);
      }
    })
  }

  @Builder
  privateShelfBiometricItem() {
    SettingSwitchRow({
      title: '指纹或人脸解锁',
      description: '进入隐私书架时先用系统指纹或人脸验证，未通过可改输密码',
      isOn: this.privateShelfBiometricSwitchOn,
      showDivider: false,
      onChange: (checked: boolean) => {
        this.onPrivateShelfBiometricSwitchChanged(checked);
      }
    })
  }

  @Builder
  actionItem(title: string, desc: string, titleColor: string, onClick: () => void) {
    SettingNavRow({ title: title, description: desc, titleColor: titleColor, showDivider: false, onTap: onClick })
  }

  @Builder
  privatePasswordField(placeholder: string, value: string, onChange: (value: string) => void) {
    TextInput({ placeholder: placeholder, text: value })
      .type(InputType.Password)
      .width('100%')
      .height(44)
      .fontColor(this.primaryTextColor())
      .placeholderColor(this.subTextColor())
      .backgroundColor(this.inputColor())
      .borderRadius(ThemeRuntime.mediumRadius())
      .margin({ bottom: AppSpacing.MD })
      .onChange((text: string) => {
        onChange(text);
      })
  }

  @Builder
  privatePasswordDialogContent() {
    Column() {
      Text(this.privatePasswordDialogMode === 'disable' ? '关闭隐私书架' : '隐私书架密码')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.XL })

      if (this.privateShelfHasPassword) {
        this.privatePasswordField('当前密码', this.privatePasswordCurrent, (value: string) => {
          this.privatePasswordCurrent = value;
          this.privatePasswordError = '';
        })
      }
      if (this.privatePasswordDialogMode !== 'disable') {
        this.privatePasswordField(this.privateShelfHasPassword ? '新密码（留空则清除密码）' : '密码',
          this.privatePasswordNew, (value: string) => {
            this.privatePasswordNew = value;
            this.privatePasswordError = '';
          })
        this.privatePasswordField(this.privateShelfHasPassword ? '再次输入新密码' : '再次输入密码',
          this.privatePasswordConfirm, (value: string) => {
            this.privatePasswordConfirm = value;
            this.privatePasswordError = '';
          })
      }

      if (this.privatePasswordError) {
        Text(this.privatePasswordError)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
          .width('100%')
      }

      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => this.closePrivatePasswordDialog())

        Button(this.privatePasswordDialogMode === 'disable' ? '关闭' : '保存')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            this.submitPrivatePasswordDialog();
          })
      }
      .width('100%')
      .margin({ top: AppSpacing.LG })
    }
    .padding(AppSpacing.XXL)
  }

  @Builder
  navItem(title: string, desc: string, url: string) {
    SettingNavRow({
      title: title,
      description: desc,
      showDivider: false,
      onTap: () => {
        router.pushUrl({ url });
      }
    })
  }
}
