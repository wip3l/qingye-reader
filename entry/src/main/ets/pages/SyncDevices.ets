import { promptAction, router, SymbolGlyphModifier } from '@kit.ArkUI';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { AccountCommerceApi } from '../account/AccountCommerceApi';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { CloudSyncDevice } from '../account/CloudSyncModels';
import { CloudSyncStateStore } from '../account/CloudSyncStateStore';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { ImmersiveHeaderAction } from '../components/ImmersiveHeaderAction';
import { CollapsingHeader } from '../utils/CollapsingHeader';

@Entry
@Component
struct SyncDevicesPage {
  @State headerCollapse: number = 0;
  private headerScroller: Scroller = new Scroller();
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State devices: CloudSyncDevice[] = [];
  @State currentDeviceId: string = '';
  @State loading: boolean = true;
  @State errorMessage: string = '';
  private renameDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('onSystemDialogFlagChanged') showRenameDialog: boolean = false;
  @State renameDeviceId: string = '';
  @State renameDeviceName: string = '';
  @State renaming: boolean = false;

  aboutToAppear(): void {
    this.loadDevices();
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
  }

  async loadDevices(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    try {
      await AccountSessionStore.load(getContext(this));
      if (!AccountSessionStore.isLoggedIn()) {
        this.errorMessage = '请先登录华为账号';
        return;
      }
      this.currentDeviceId = await CloudSyncStateStore.deviceId(getContext(this));
      const response = await AccountCommerceApi.fetchSyncDevices(AccountSessionStore.token());
      // 服务端会保留已移除设备的记录，列表里只显示仍然有效的设备。
      this.devices = (response.devices || []).filter((device: CloudSyncDevice) => !device.revokedAt);
    } catch (e) {
      this.errorMessage = e instanceof Error ? e.message : String(e);
    } finally {
      this.loading = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 列表铺满整页并从顶栏下方滚过去，上下留白由列表里的占位项提供。
      PageScaffold({ title: '同步设备', scrollable: false, externalCollapse: this.headerCollapse, edgeToEdge: true, content: () => {
        this.pageContent()
      }, actions: () => {
        this.titleActions()
      } })

    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    List({ scroller: this.headerScroller, space: AppSpacing.MD }) {
      ListItem() {
        Row()
          .width('100%')
          .height(PageScaffold.BAR_HEIGHT + this.statusBarHeight)
          .hitTestBehavior(HitTestMode.None)
      }

      if (this.loading) {
        ListItem() {
          Column({ space: AppSpacing.LG }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.accentColor())
            Text('正在读取同步设备…')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
          }
          .width('100%')
          .padding({ top: 48 })
        }
      } else if (this.errorMessage) {
        ListItem() {
          Column({ space: AppSpacing.LG }) {
            Text(this.errorMessage)
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
              .textAlign(TextAlign.Center)
            Button('重试')
              .height(40)
              .backgroundColor(this.accentColor())
              .onClick(() => this.loadDevices())
          }
          .width('100%')
          .padding(AppSpacing.XXL)
          .margin({ top: AppSpacing.LG })
          .borderRadius(ThemeRuntime.cardRadius())
          .backgroundColor(this.cardColor())
        }
      } else {
        ListItem() {
          Text('已登录设备')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
            .width('100%')
            .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: AppSpacing.LG })
        }

        if (this.devices.length === 0) {
          ListItem() {
            Text('完成首次同步后，当前设备会显示在这里。')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
              .width('100%')
              .padding(AppSpacing.XL)
              .borderRadius(ThemeRuntime.cardRadius())
              .backgroundColor(this.cardColor())
          }
        }

        ForEach(this.devices, (device: CloudSyncDevice) => {
          if (deviceInfo.sdkApiVersion >= 26) {
            HdsListItem({
              customItemBuilder: (): void => {
                this.deviceItem(device)
              },
              swipeActionOptions: this.deviceSwipeActions(device)
            })
          }
          if (deviceInfo.sdkApiVersion < 26) {
            ListItem() {
              this.deviceItem(device)
            }
            .borderRadius(ThemeRuntime.mediumRadius())
            .clip(true)
            .swipeAction({
              end: {
                builder: (): void => {
                  this.deviceSwipeButtons(device)
                },
                actionAreaDistance: this.isCurrentDevice(device) ? 64 : 128
              },
              edgeEffect: SwipeEdgeEffect.Spring
            })
          }
        }, (device: CloudSyncDevice) => device.deviceId)

        ListItem() {
          Text('左滑设备可以改名，或移除不再使用的其他设备。本机同步权限需要通过关闭云同步或退出账号进行管理。')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .lineHeight(18)
            .width('100%')
            .padding({ left: AppSpacing.XS, right: AppSpacing.XS, top: AppSpacing.XS })
        }
      }

      ListItem() {
        Row()
          .width('100%')
          .height(32 + this.navBarHeight)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .onDidScroll((yOffset: number) => {
      this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
        this.headerScroller.currentOffset().yOffset);
    })
    .onScrollStop(() => {
      const target = CollapsingHeader.settle(this.headerCollapse, this.headerScroller.currentOffset().yOffset);
      if (target !== this.headerCollapse) {
        animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
          this.headerCollapse = target;
        });
      }
    })
  }

  @Builder
  titleActions() {
    ImmersiveHeaderAction({
      icon: $r('sys.symbol.arrow_clockwise'),
      tint: this.accentColor(),
      accessibilityLabel: '刷新设备列表',
      onTap: () => this.loadDevices()
    })
      .margin({ right: AppSpacing.XL })
  }

  @Builder
  deviceItem(device: CloudSyncDevice) {
    Row({ space: AppSpacing.LG }) {
      this.deviceIcon(device)

      Column({ space: AppSpacing.XS }) {
        Row({ space: AppSpacing.MD }) {
          Text(device.deviceName || 'HarmonyOS 设备')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.primaryTextColor())
          if (this.isCurrentDevice(device)) {
            Text('本机')
              .fontSize(AppFontSize.CAPTION)
              .fontColor(this.accentColor())
              .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
              .borderRadius(ThemeRuntime.mediumRadius())
              .backgroundColor(this.softColor())
          }
        }
        Text(`${device.platform || 'HarmonyOS'}${device.appVersion ? ` · ${device.appVersion}` : ''}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
        Text(`最近同步：${this.timeText(device.lastSeenAt)}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .constraintSize({ minHeight: 86 })
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    .alignItems(VerticalAlign.Center)
  }

  private isCurrentDevice(device: CloudSyncDevice): boolean {
    return device.deviceId === this.currentDeviceId;
  }

  private deviceSwipeActions(device: CloudSyncDevice): HdsSwipeActionOptions {
    if (this.isCurrentDevice(device)) {
      return { icons: [
        { icon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
          backgroundColor: ThemeRuntime.buttonColor(this.appDarkMode),
          iconOptions: { accessibilityText: '改名' },
          onAction: () => this.openRename(device) }
      ] };
    }
    return { icons: [
      { icon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
        backgroundColor: ThemeRuntime.buttonColor(this.appDarkMode),
        iconOptions: { accessibilityText: '改名' },
        onAction: () => this.openRename(device) },
      { icon: new SymbolGlyphModifier($r('sys.symbol.trash')),
        backgroundColor: ThemeRuntime.dangerColor(this.appDarkMode),
        iconOptions: { accessibilityText: '移除设备' },
        onAction: () => this.confirmRevoke(device) }
    ] };
  }

  @Builder
  deviceSwipeButtons(device: CloudSyncDevice) {
    Row() {
      this.deviceSwipeButton($r('sys.symbol.square_and_pencil'), '改名',
        ThemeRuntime.buttonColor(this.appDarkMode), () => this.openRename(device))
      if (!this.isCurrentDevice(device)) {
        this.deviceSwipeButton($r('sys.symbol.trash'), '移除',
          ThemeRuntime.dangerColor(this.appDarkMode), () => this.confirmRevoke(device))
      }
    }
    .height('100%')
  }

  @Builder
  deviceSwipeButton(icon: Resource, label: string, color: string, action: () => void) {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text(label)
        .fontSize(AppFontSize.CAPTION)
        .fontColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(color)
    .onClick(() => action())
  }

  @Builder
  deviceIcon(device: CloudSyncDevice) {
    if (device.deviceKind === 'foldable') {
      Image($r('app.media.ic_device_foldable'))
        .width(32)
        .height(32)
        .fillColor(this.accentColor())
    } else if (device.deviceKind === '2in1') {
      Image($r('app.media.ic_device_2in1'))
        .width(32)
        .height(32)
        .fillColor(this.accentColor())
    } else if (device.deviceKind === 'tablet') {
      Image($r('app.media.ic_device_tablet'))
        .width(32)
        .height(32)
        .fillColor(this.accentColor())
    } else {
      Image($r('app.media.ic_device_phone'))
        .width(32)
        .height(32)
        .fillColor(this.accentColor())
    }
  }

  openRename(device: CloudSyncDevice): void {
    this.renameDeviceId = device.deviceId;
    this.renameDeviceName = device.deviceName || 'HarmonyOS 设备';
    this.openRenameDialog();
  }

  async saveRename(): Promise<void> {
    const name = this.renameDeviceName.trim();
    if (!name || this.renaming) {
      return;
    }
    this.renaming = true;
    try {
      await AccountCommerceApi.renameSyncDevice(
        this.renameDeviceId, name, AccountSessionStore.token());
      this.showRenameDialog = false;
      HdsFeedback.showToast('设备名称已更新');
      await this.loadDevices();
    } catch (e) {
      HdsFeedback.showToast(e instanceof Error ? `改名失败：${e.message}` : '设备改名失败');
    } finally {
      this.renaming = false;
    }
  }


  onSystemDialogFlagChanged(): void {
    if (!this.showRenameDialog) this.renameDialogSession.close(this.getUIContext());
  }

  openRenameDialog(): void {
    this.showRenameDialog = true;
    this.renameDialogSession.open(this.getUIContext(), (): void => {
      this.renameDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示设备重命名弹窗失败:'
    });
  }

  @Builder
  renameDialogContent() {
    Column({ space: AppSpacing.XL }) {
      Text('修改设备名称')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
      TextInput({ placeholder: '输入设备名称', text: this.renameDeviceName })
        .width('100%')
        .height(42)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.softColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .maxLength(80)
        .onChange((value: string) => {
          this.renameDeviceName = value;
        })
      Row({ space: AppSpacing.LG }) {
        Button('取消', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.cardColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.showRenameDialog = false;
          })
        Button(this.renaming ? '保存中' : '保存', { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(42)
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(this.accentColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .enabled(!!this.renameDeviceName.trim() && !this.renaming)
          .onClick(() => this.saveRename())
      }
      .width('100%')
    }    .constraintSize({ maxWidth: 360 })
    .padding(AppSpacing.XXL)
  }


  async confirmRevoke(device: CloudSyncDevice): Promise<void> {
    const result = await promptAction.showDialog({
      title: '移除同步设备',
      message: `确定移除“${device.deviceName || 'HarmonyOS 设备'}”吗？移除后该设备将停止同步。`,
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '移除', color: ThemeRuntime.dangerColor(this.appDarkMode) }
      ]
    });
    if (result.index !== 1) {
      return;
    }
    try {
      await AccountCommerceApi.revokeSyncDevice(device.deviceId, AccountSessionStore.token());
      HdsFeedback.showToast('设备已移除');
      this.devices = this.devices.filter((item: CloudSyncDevice) => item.deviceId !== device.deviceId);
    } catch (e) {
      HdsFeedback.showToast(e instanceof Error ? `移除失败：${e.message}` : '移除设备失败');
    }
  }

  timeText(timestamp: number): string {
    return timestamp > 0 ? new Date(timestamp).toLocaleString() : '尚未同步';
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  softColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
