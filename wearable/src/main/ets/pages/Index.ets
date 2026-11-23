import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { vibrator } from '@kit.SensorServiceKit';
import { LinkFailure, PhoneLink } from '../common/PhoneLink';
import { PhoneReaderState, PhoneState } from '../common/WatchRemoteProtocol';
import { WatchPrefs } from '../common/WatchPrefs';

enum ScreenMode {
  CONNECTING = 0,
  READY = 1,
  MESSAGE = 2
}

enum MessageAction {
  NONE = 0,
  RETRY = 1,
  OPEN_ON_PHONE = 2
}

enum MessageIcon {
  BOOK = 0,
  WAIT = 1,
  LINK = 2
}

/**
 * 手表翻页遥控（方案 A：上下分区）。上三分之一点一下上一页，下三分之二下一页；转表冠也翻页；
 * 外圈细环是全书进度；长按打开设置。手机不能翻页时整屏换成一句原因，手机状态一变自动回来。
 */
@Entry
@Component
struct Index {
  @State mode: ScreenMode = ScreenMode.CONNECTING;
  @State phone: PhoneState = new PhoneState();
  @State messageTitle: string = '';
  @State messageBody: string = '';
  @State messageIcon: MessageIcon = MessageIcon.LINK;
  @State messageAction: MessageAction = MessageAction.NONE;
  @State flashDirection: number = 0;
  @State prefs: WatchPrefs = new WatchPrefs();
  @State showSettings: boolean = false;
  private link: PhoneLink | null = null;
  private visible: boolean = false;
  private retryTimerId: number = -1;
  private flashTimerId: number = -1;
  private crownDegrees: number = 0;
  private lastCrownTurnAt: number = 0;

  aboutToAppear(): void {
    const context = this.hostContext();
    const link = new PhoneLink(context);
    link.onState = (state: PhoneState): void => this.applyPhoneState(state);
    link.onFailure = (failure: LinkFailure): void => this.applyFailure(failure);
    this.link = link;
    WatchPrefs.load(context).then((prefs: WatchPrefs): void => {
      this.prefs = prefs;
      this.applyKeepScreenOn();
    });
  }

  aboutToDisappear(): void {
    this.clearRetry();
    this.link?.release();
  }

  onPageShow(): void {
    this.visible = true;
    this.applyKeepScreenOn();
    this.connect();
  }

  onPageHide(): void {
    this.visible = false;
    this.clearRetry();
    this.setKeepScreenOn(false);
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private connect(): void {
    if (this.mode !== ScreenMode.READY) this.mode = ScreenMode.CONNECTING;
    this.link?.connect();
  }

  private applyPhoneState(state: PhoneState): void {
    this.clearRetry();
    if (state.st === PhoneReaderState.READY) {
      if (state.nc && this.mode === ScreenMode.READY) this.vibrate(true);
      this.phone = state;
      this.mode = ScreenMode.READY;
      return;
    }
    if (state.st === PhoneReaderState.NO_BOOK) {
      this.showMessage(MessageIcon.BOOK, '手机上没打开书', '在开源轻页里打开一本书，\n这里就会自动变成翻页键',
        this.link?.canOpenOnPhone() ? MessageAction.OPEN_ON_PHONE : MessageAction.NONE);
      return;
    }
    this.showMessage(MessageIcon.WAIT, '暂时不能翻页', state.why || '手机上暂时不接受翻页', MessageAction.NONE);
    // 朗读开始/停止手机会主动推；菜单、目录关上不会推，所以隔几秒问一次。
    this.scheduleRetry(3000);
  }

  private applyFailure(failure: LinkFailure): void {
    switch (failure) {
      case LinkFailure.APP_NOT_INSTALLED:
        this.showMessage(MessageIcon.LINK, '手机上没装开源轻页', '在手机应用市场搜索“开源轻页”安装', MessageAction.RETRY);
        break;
      case LinkFailure.APP_NOT_RUNNING:
        this.showMessage(MessageIcon.LINK, '手机上的开源轻页没打开', '打开后在 我的 › 阅读与收听\n里打开“手表翻页”',
          this.link?.canOpenOnPhone() ? MessageAction.OPEN_ON_PHONE : MessageAction.RETRY);
        break;
      case LinkFailure.NO_REPLY:
        this.showMessage(MessageIcon.LINK, '连不上手机', '确认手机上开着开源轻页，\n并在设置里打开了“手表翻页”',
          MessageAction.RETRY);
        break;
      case LinkFailure.SERVICE:
        this.showMessage(MessageIcon.LINK, '穿戴服务暂时不可用', '请稍后再试', MessageAction.RETRY);
        break;
      default:
        this.showMessage(MessageIcon.LINK, '连不上手机', '确认手机在身边、蓝牙开着', MessageAction.RETRY);
        break;
    }
    this.scheduleRetry(5000);
  }

  private showMessage(icon: MessageIcon, title: string, body: string, action: MessageAction): void {
    this.messageIcon = icon;
    this.messageTitle = title;
    this.messageBody = body;
    this.messageAction = action;
    this.mode = ScreenMode.MESSAGE;
  }

  /** 不能翻页时隔一会儿再问手机，手机那边好了就自动回到遥控页。 */
  private scheduleRetry(delayMs: number): void {
    this.clearRetry();
    if (!this.visible) return;
    this.retryTimerId = setTimeout((): void => {
      this.retryTimerId = -1;
      if (this.visible) this.link?.connect();
    }, delayMs);
  }

  private clearRetry(): void {
    if (this.retryTimerId >= 0) clearTimeout(this.retryTimerId);
    this.retryTimerId = -1;
  }

  private turn(direction: number): void {
    if (this.mode !== ScreenMode.READY || this.showSettings) return;
    this.vibrate(false);
    this.flash(direction);
    this.link?.turn(direction);
  }

  private flash(direction: number): void {
    this.flashDirection = direction;
    if (this.flashTimerId >= 0) clearTimeout(this.flashTimerId);
    this.flashTimerId = setTimeout((): void => {
      this.flashTimerId = -1;
      this.flashDirection = 0;
    }, 180);
  }

  private onCrown(event: CrownEvent): void {
    if (!this.prefs.crownTurn || this.mode !== ScreenMode.READY || this.showSettings) return;
    // BEGIN 在新 SDK 里标了弃用，但旧手表仍会发；只按 END 清零，BEGIN 与 UPDATE 都累加转角。
    if (event.action === CrownAction.END) {
      this.crownDegrees = 0;
      return;
    }
    this.crownDegrees += event.degree;
    const now = Date.now();
    // 转过约一格（15°）翻一页，连续转动时至少隔 220ms，免得一甩翻好几页。
    if (Math.abs(this.crownDegrees) < 15 || now - this.lastCrownTurnAt < 220) return;
    const clockwise = this.crownDegrees > 0;
    this.crownDegrees = 0;
    this.lastCrownTurnAt = now;
    const next = this.prefs.swapZones ? !clockwise : clockwise;
    this.turn(next ? 1 : -1);
  }

  private vibrate(strong: boolean): void {
    if (!this.prefs.vibrate) return;
    try {
      vibrator.startVibration({ type: 'time', duration: strong ? 45 : 18 }, { usage: 'touch' })
        .catch((): void => {});
    } catch (error) {
      console.warn('[WatchRemote] 震动失败:', JSON.stringify(error));
    }
  }

  private applyKeepScreenOn(): void {
    if (this.visible) this.setKeepScreenOn(this.prefs.keepScreenOn);
  }

  private setKeepScreenOn(on: boolean): void {
    window.getLastWindow(this.hostContext()).then((win: window.Window): Promise<void> =>
      win.setWindowKeepScreenOn(on)).catch((): void => {});
  }

  private updatePrefs(change: (prefs: WatchPrefs) => void): void {
    const next = this.prefs.copy();
    change(next);
    this.prefs = next;
    this.applyKeepScreenOn();
    WatchPrefs.save(this.hostContext(), next);
  }

  private onMessageAction(): void {
    if (this.messageAction === MessageAction.OPEN_ON_PHONE) {
      this.link?.openOnPhone().then((opened: boolean): void => {
        if (opened) setTimeout((): void => this.connect(), 1500);
      });
      return;
    }
    this.connect();
  }

  private pageLine(): string {
    return this.phone.pages > 0 ? `${this.phone.page} / ${this.phone.pages} 页` : '';
  }

  build() {
    Stack() {
      if (this.mode === ScreenMode.READY) {
        this.remoteView()
      } else if (this.mode === ScreenMode.MESSAGE) {
        this.messageView()
      } else {
        Column({ space: 8 }) {
          LoadingProgress().width(36).height(36).color('#9DB0C6')
          Text('正在连接手机…').fontSize(14).fontColor('#9AA0A8')
        }
        .justifyContent(FlexAlign.Center)
      }
      if (this.showSettings) {
        this.settingsView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .focusable(true)
    .defaultFocus(true)
    .onDigitalCrown((event: CrownEvent): void => this.onCrown(event))
  }

  @Builder
  remoteView() {
    Stack() {
      Column() {
        if (this.prefs.swapZones) {
          this.nextZone('67%', false)
          this.prevZone('33%', false)
        } else {
          this.prevZone('33%', true)
          this.nextZone('67%', true)
        }
      }
      .width('100%')
      .height('100%')

      Progress({ value: Math.round(this.phone.prog * 1000), total: 1000, type: ProgressType.Ring })
        .width('100%')
        .height('100%')
        .color('#6FA0D8')
        .backgroundColor('#2A2C30')
        .style({ strokeWidth: 4 })
        .hitTestBehavior(HitTestMode.Transparent)
        .accessibilityText(`全书进度 ${Math.round(this.phone.prog * 100)}%`)
    }
    .width('100%')
    .height('100%')
  }

  /** 上一页区。atTop 时内容贴下沿（圆形表盘上沿太窄）。 */
  @Builder
  prevZone(height: string, atTop: boolean) {
    Column({ space: 2 }) {
      if (atTop) {
        this.connectedBadge()
      }
      SymbolGlyph(atTop ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
        .fontSize(18)
        .fontColor(['#A9ADB4'])
      Text('上一页').fontSize(14).fontColor('#A9ADB4')
    }
    .width('100%')
    .height(height)
    .justifyContent(atTop ? FlexAlign.End : FlexAlign.Start)
    .padding(atTop ? { bottom: 10 } : { top: 10 })
    .backgroundColor(this.flashDirection < 0 ? '#2A2D33' : '#15171A')
    .accessibilityText('上一页')
    .gesture(GestureGroup(GestureMode.Exclusive,
      LongPressGesture({ duration: 600 }).onAction((): void => {
        this.showSettings = true;
      }),
      TapGesture().onAction((): void => this.turn(-1))
    ))
  }

  @Builder
  nextZone(height: string, atBottom: boolean) {
    Column() {
      if (!atBottom) {
        this.connectedBadge()
      }
      Text(this.phone.book || '正在阅读')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('70%')
      if (this.phone.chap) {
        Text(this.phone.chap)
          .fontSize(12)
          .fontColor(this.flashDirection > 0 ? '#D5E2F0' : '#9DB0C6')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width('70%')
          .margin({ top: 4 })
      }
      if (this.pageLine()) {
        Text(this.pageLine())
          .fontSize(12)
          .fontColor(this.flashDirection > 0 ? '#FFFFFF' : '#9DB0C6')
          .margin({ top: 2 })
      }
      Blank()
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(22)
        .fontColor([this.flashDirection > 0 ? '#FFFFFF' : '#DCE8F6'])
      Text('下一页')
        .fontSize(19)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.flashDirection > 0 ? '#FFFFFF' : '#DCE8F6')
    }
    .width('100%')
    .height(height)
    .padding(atBottom ? { top: 14, bottom: 26 } : { top: 26, bottom: 14 })
    .backgroundColor(this.flashDirection > 0 ? '#2E5A88' : '#14243A')
    .accessibilityText(`下一页，${this.phone.book} ${this.phone.chap} ${this.pageLine()}`)
    .gesture(GestureGroup(GestureMode.Exclusive,
      LongPressGesture({ duration: 600 }).onAction((): void => {
        this.showSettings = true;
      }),
      TapGesture().onAction((): void => this.turn(1))
    ))
  }

  @Builder
  connectedBadge() {
    Row({ space: 4 }) {
      Row().width(6).height(6).borderRadius(3).backgroundColor('#7FC59A')
      Text('已连接').fontSize(11).fontColor('#7FC59A')
    }
    .margin({ bottom: 4 })
  }

  @Builder
  messageView() {
    Column() {
      SymbolGlyph(this.messageIcon === MessageIcon.BOOK ? $r('sys.symbol.book') :
        $r('sys.symbol.exclamationmark_circle'))
        .fontSize(34)
        .fontColor([this.messageIcon === MessageIcon.BOOK ? '#9DB0C6' :
          (this.messageIcon === MessageIcon.WAIT ? '#E0B060' : '#C98A8A')])
      Text(this.messageTitle)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .margin({ top: 10 })
      Text(this.messageBody)
        .fontSize(12)
        .fontColor('#9AA0A8')
        .textAlign(TextAlign.Center)
        .lineHeight(18)
        .width('72%')
        .margin({ top: 6 })
      if (this.messageAction !== MessageAction.NONE) {
        Button(this.messageAction === MessageAction.OPEN_ON_PHONE ? '在手机上打开' : '重试')
          .height(40)
          .fontSize(14)
          .fontColor(this.messageAction === MessageAction.OPEN_ON_PHONE ? '#FFFFFF' : '#E8EAED')
          .backgroundColor(this.messageAction === MessageAction.OPEN_ON_PHONE ? '#2E5A88' : '#26282D')
          .padding({ left: 20, right: 20 })
          .margin({ top: 14 })
          .onClick((): void => this.onMessageAction())
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .gesture(LongPressGesture({ duration: 600 }).onAction((): void => {
      this.showSettings = true;
    }))
  }

  @Builder
  settingsView() {
    Column() {
      Text('设置')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .margin({ top: 30, bottom: 8 })
      List({ space: 6 }) {
        ListItem() {
          this.settingRow('屏幕常亮', this.prefs.keepScreenOn, (on: boolean): void => {
            this.updatePrefs((prefs: WatchPrefs): void => {
              prefs.keepScreenOn = on;
            });
          })
        }
        ListItem() {
          this.settingRow('翻页震动', this.prefs.vibrate, (on: boolean): void => {
            this.updatePrefs((prefs: WatchPrefs): void => {
              prefs.vibrate = on;
            });
          })
        }
        ListItem() {
          this.settingRow('表冠翻页', this.prefs.crownTurn, (on: boolean): void => {
            this.updatePrefs((prefs: WatchPrefs): void => {
              prefs.crownTurn = on;
            });
          })
        }
        ListItem() {
          this.settingRow('上下对调', this.prefs.swapZones, (on: boolean): void => {
            this.updatePrefs((prefs: WatchPrefs): void => {
              prefs.swapZones = on;
            });
          })
        }
        ListItem() {
          Button('完成')
            .width('100%')
            .height(40)
            .fontSize(14)
            .backgroundColor('#2E5A88')
            .margin({ top: 4, bottom: 40 })
            .onClick((): void => {
              this.showSettings = false;
            })
        }
      }
      .width('76%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }

  @Builder
  settingRow(title: string, isOn: boolean, onChange: (on: boolean) => void) {
    Row() {
      Text(title).fontSize(14).fontColor('#E8EAED').layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor('#2E5A88')
        .onChange((on: boolean): void => onChange(on))
    }
    .width('100%')
    .height(44)
    .padding({ left: 14, right: 8 })
    .borderRadius(22)
    .backgroundColor('#1A1C20')
  }
}
