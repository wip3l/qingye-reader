import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AccountCredentialService } from '../account/AccountCredentialService';
import { AccountApiError, AccountLoginMethods } from '../account/AccountCommerceModels';
import { CloudAutoSync } from '../account/CloudAutoSync';
import { PageScaffold } from '../components/common/PageScaffold';
import { RecoveryCodesPanel } from '../components/common/RecoveryCodesPanel';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { HdsFeedback } from '../utils/HdsFeedback';
import { syncSystemBars } from '../utils/SystemBars';
import { PlatformInfo } from '../platform/PlatformInfo';

const VIEW_OVERVIEW = '';
const VIEW_PASSWORD = 'password';
const VIEW_REGENERATE = 'regenerate';
const VIEW_DELETE = 'delete';
const VIEW_CODES = 'codes';
const DELETION_GRACE_DAYS = 7;

/** 登录与账号安全：华为账号绑定、用户名与密码、恢复码和注销账号。 */
@Entry
@Component
struct AccountSecurityPage {
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('accountLoggedIn') accountLoggedIn: boolean = false;
  @State methods: AccountLoginMethods = new AccountLoginMethods();
  @State loaded: boolean = false;
  @State loadError: string = '';
  @State view: string = VIEW_OVERVIEW;
  @State busy: boolean = false;
  @State usernameInput: string = '';
  @State currentPassword: string = '';
  @State newPassword: string = '';
  @State confirmPassword: string = '';
  @State errorText: string = '';
  @State recoveryCodes: string[] = [];
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.load();
  }

  onPageShow(): void {
    syncSystemBars(this.context, this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
  }

  onBackPress(): boolean {
    if (this.view !== VIEW_OVERVIEW && this.view !== VIEW_CODES) {
      this.showView(VIEW_OVERVIEW);
      return true;
    }
    return false;
  }

  build() {
    Stack() {
      PageScaffold({ title: this.title(), content: () => {
        this.pageContent()
      }, onBack: () => {
        if (!this.onBackPress()) router.back();
      } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private title(): string {
    if (this.view === VIEW_PASSWORD) return this.methods.hasPassword ? '修改密码' : '设置用户名和密码';
    if (this.view === VIEW_REGENERATE) return '重新生成恢复码';
    if (this.view === VIEW_DELETE) return '注销账号';
    if (this.view === VIEW_CODES) return '保存恢复码';
    return '登录与账号安全';
  }

  private async load(): Promise<void> {
    try {
      this.methods = await AccountCredentialService.loginMethods(this.context);
      this.loadError = '';
      this.loaded = true;
    } catch (e) {
      this.loadError = this.errorMessage(e, '账号信息加载失败，请稍后重试');
    }
  }

  private showView(view: string): void {
    if (this.busy) return;
    this.view = view;
    this.usernameInput = '';
    this.currentPassword = '';
    this.newPassword = '';
    this.confirmPassword = '';
    this.errorText = '';
  }

  @Builder
  pageContent() {
    Column({ space: AppSpacing.LG }) {
      if (this.view === VIEW_CODES) {
        RecoveryCodesPanel({ codes: this.recoveryCodes, onDone: () => {
          this.recoveryCodes = [];
          this.showView(VIEW_OVERVIEW);
        } })
      } else if (this.view === VIEW_PASSWORD) {
        this.passwordForm()
      } else if (this.view === VIEW_REGENERATE) {
        this.regenerateForm()
      } else if (this.view === VIEW_DELETE) {
        this.deleteForm()
      } else if (!this.loaded) {
        Text(this.loadError || '正在加载…')
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(AppSpacing.XXXL)
          .onClick(() => {
            if (this.loadError) this.load();
          })
      } else {
        this.overview()
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: 14 })
  }

  @Builder
  overview() {
    this.sectionTitle('登录方式')
    Column() {
      this.methodRow($r('sys.symbol.person'), '华为账号',
        'huawei', true)
      this.methodRow($r('sys.symbol.lock'), '用户名与密码', 'password', false)
    }
    .width('100%')
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))

    if (this.methods.hasPassword) {
      this.sectionTitle('恢复码')
      Column() {
        this.methodRow($r('sys.symbol.checkmark_shield'), '恢复码', 'codes', false)
      }
      .width('100%')
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
    }

    Text('注销账号')
      .width('100%')
      .height(48)
      .margin({ top: AppSpacing.LG })
      .textAlign(TextAlign.Center)
      .fontSize(AppFontSize.BODY_LARGE)
      .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
      .borderRadius(ThemeRuntime.cardRadius())
      .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
      .onClick(() => {
        this.showView(VIEW_DELETE);
      })
    this.caption(this.methods.huaweiBound && this.methods.hasPassword ?
      '华为账号和用户名密码登录的是同一个账号，点数、会员和同步数据都相同。' :
      '至少保留一种登录方式。绑定华为账号或设置用户名密码后，换设备时多一条登录途径。')
  }

  // 行内容按 kind 在 builder 里读状态算，绑定或设置完成后会跟着刷新。
  @Builder
  methodRow(icon: Resource, title: string, kind: string, showDivider: boolean) {
    Column() {
      Row({ space: AppSpacing.LG }) {
        SymbolGlyph(icon)
          .fontSize(22)
          .fontColor([ThemeRuntime.accentColor(this.appDarkMode)])
          .width(28)
        Column({ space: AppSpacing.XXS }) {
          Text(title)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
          Text(this.methodDetail(kind))
            .fontSize(AppFontSize.CAPTION)
            .fontColor(kind === 'codes' && this.methods.recoveryCodesRemaining <= 2 ?
              ThemeRuntime.dangerColor(this.appDarkMode) : ThemeRuntime.subTextColor(this.appDarkMode))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (this.methodAction(kind)) {
          Text(this.methodAction(kind))
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
            .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
            .borderRadius(14)
            .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
            .enabled(!this.busy)
            .onClick(() => {
              this.runMethodAction(kind);
            })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 64 })
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
      .alignItems(VerticalAlign.Center)
      if (showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color(ThemeRuntime.hairlineColor(this.appDarkMode))
          .margin({ left: 56, right: AppSpacing.XL })
      }
    }
    .width('100%')
  }

  private methodDetail(kind: string): string {
    if (kind === 'huawei') {
      return this.methods.huaweiBound ? '已绑定，可用华为账号一键登录' : '未绑定 · 绑定没领过赠点的华为账号可领 300 点';
    }
    if (kind === 'password') {
      return this.methods.hasPassword ? `用户名 ${this.methods.username}` : '未设置 · 设置后可在任何设备用用户名登录';
    }
    return this.methods.recoveryCodesRemaining > 0 ?
      `还剩 ${this.methods.recoveryCodesRemaining} 个可用，忘记密码时用来重设` : '已用完，请重新生成';
  }

  private methodAction(kind: string): string {
    // 安卓上没有华为账号服务，不提供绑定。
    if (kind === 'huawei') return this.methods.huaweiBound || PlatformInfo.ANDROID ? '' : (this.busy ? '绑定中' : '绑定');
    if (kind === 'password') return this.methods.hasPassword ? '修改密码' : '设置';
    return '重新生成';
  }

  private runMethodAction(kind: string): void {
    if (kind === 'huawei') {
      if (!PlatformInfo.ANDROID) this.bindHuawei();
    } else if (kind === 'password') {
      this.showView(VIEW_PASSWORD);
    } else {
      this.showView(VIEW_REGENERATE);
    }
  }

  @Builder
  passwordForm() {
    Column({ space: AppSpacing.MD }) {
      if (!this.methods.hasPassword) {
        this.field('username', '用户名', false)
        Text(`用户名设置后不能修改，${AccountCredentialService.USERNAME_HINT}。`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .width('100%')
      } else {
        Text(`用户名 ${this.methods.username}`)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .width('100%')
        this.field('current', '当前密码', true)
      }
      this.field('new', '新密码', true)
      this.field('confirm', '再输入一次新密码', true)
      Text(`密码${AccountCredentialService.PASSWORD_HINT}。保存后其他设备会退出登录。`)
        .fontSize(AppFontSize.CAPTION)
        .lineHeight(18)
        .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .width('100%')
      this.errorLine()
      this.formButtons(this.methods.hasPassword ? '保存新密码' : '保存', false)
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
  }

  @Builder
  regenerateForm() {
    Column({ space: AppSpacing.MD }) {
      Text('重新生成后，之前的恢复码全部作废。请输入当前密码确认。')
        .fontSize(AppFontSize.BODY)
        .lineHeight(21)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .width('100%')
      this.field('current', '当前密码', true)
      this.errorLine()
      this.formButtons('生成新的恢复码', false)
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
  }

  @Builder
  deleteForm() {
    Column({ space: AppSpacing.MD }) {
      Text(`申请后所有设备立即退出登录，${DELETION_GRACE_DAYS} 天冷静期内用任意方式重新登录即可撤销。`)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Medium)
        .lineHeight(23)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .width('100%')
      Text('冷静期满后：\n' +
        '• 删除用户名、密码、恢复码和华为账号绑定，昵称头像改为“已注销用户”\n' +
        '• 删除云端同步的书架、进度、书签、划线等数据，以及阅读统计\n' +
        '• 删除云空间里的书籍和字体\n' +
        '• 剩余点数、会员和已兑换的主题全部作废，不能找回，也不能退款或转移\n' +
        '• 本机已下载的书和本地数据不受影响\n' +
        '• 之后用同一个华为账号登录会是一个新账号，不再赠送新用户点数')
        .fontSize(AppFontSize.BODY)
        .lineHeight(22)
        .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .width('100%')
      if (this.methods.hasPassword) {
        this.field('current', '输入当前密码确认', true)
      }
      this.errorLine()
      this.formButtons('申请注销', true)
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
  }

  @Builder
  formButtons(confirmLabel: string, danger: boolean) {
    Row({ space: AppSpacing.LG }) {
      Button('取消')
        .layoutWeight(1)
        .height(42)
        .fontSize(AppFontSize.BODY)
        .enabled(!this.busy)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
        .onClick(() => {
          this.showView(VIEW_OVERVIEW);
        })
      Button(this.busy ? '请稍候' : confirmLabel)
        .layoutWeight(1)
        .height(42)
        .fontSize(AppFontSize.BODY)
        .enabled(!this.busy)
        .fontColor(danger ? '#FFFFFF' : ThemeRuntime.onAccentColor(ThemeRuntime.accentColor(this.appDarkMode)))
        .backgroundColor(danger ? ThemeRuntime.dangerColor(this.appDarkMode) : ThemeRuntime.accentColor(this.appDarkMode))
        .onClick(() => {
          this.submit();
        })
    }
    .width('100%')
    .margin({ top: AppSpacing.XS })
  }

  @Builder
  errorLine() {
    if (this.errorText) {
      Text(this.errorText)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
        .width('100%')
    }
  }

  @Builder
  field(key: string, placeholder: string, secret: boolean) {
    TextInput({ text: this.fieldValue(key), placeholder: placeholder })
      .type(secret ? InputType.Password : InputType.Normal)
      .width('100%')
      .height(44)
      .fontSize(AppFontSize.BODY_LARGE)
      .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
      .placeholderColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
      .borderRadius(ThemeRuntime.mediumRadius())
      .maxLength(key === 'username' ? 20 : 64)
      .enabled(!this.busy)
      .onChange((value: string) => {
        this.setField(key, value);
      })
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.CAPTION)
      .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .width('100%')
      .padding({ left: AppSpacing.XS, top: AppSpacing.XS })
  }

  @Builder
  caption(text: string) {
    Text(text)
      .fontSize(AppFontSize.CAPTION)
      .lineHeight(18)
      .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .width('100%')
      .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
  }

  private fieldValue(key: string): string {
    if (key === 'username') return this.usernameInput;
    if (key === 'current') return this.currentPassword;
    if (key === 'new') return this.newPassword;
    return this.confirmPassword;
  }

  private setField(key: string, value: string): void {
    if (key === 'username') {
      this.usernameInput = value;
    } else if (key === 'current') {
      this.currentPassword = value;
    } else if (key === 'new') {
      this.newPassword = value;
    } else {
      this.confirmPassword = value;
    }
    this.errorText = '';
  }

  private submit(): void {
    if (this.view === VIEW_PASSWORD) {
      this.savePassword();
    } else if (this.view === VIEW_REGENERATE) {
      this.regenerate();
    } else if (this.view === VIEW_DELETE) {
      this.requestDeletion();
    }
  }

  private async savePassword(): Promise<void> {
    if (this.busy) return;
    const username = this.methods.hasPassword ? this.methods.username : this.usernameInput.trim();
    const problem = (this.methods.hasPassword ? '' : AccountCredentialService.usernameProblem(username)) ||
      (this.methods.hasPassword && !this.currentPassword ? '请输入当前密码' : '') ||
      AccountCredentialService.passwordProblem(this.newPassword, username) ||
      (this.newPassword !== this.confirmPassword ? '两次输入的新密码不一致' : '');
    if (problem) {
      this.errorText = problem;
      return;
    }
    const firstTime = !this.methods.hasPassword;
    this.busy = true;
    try {
      const result = await AccountCredentialService.setPassword(this.context, username, this.newPassword,
        this.currentPassword);
      this.methods = result.loginMethods;
      this.busy = false;
      if (firstTime && result.recoveryCodes.length > 0) {
        HdsFeedback.showToast('用户名和密码已设置');
        this.recoveryCodes = result.recoveryCodes;
        this.showView(VIEW_CODES);
      } else {
        HdsFeedback.showToast('密码已修改，其他设备已退出登录');
        this.showView(VIEW_OVERVIEW);
      }
    } catch (e) {
      this.errorText = this.errorMessage(e, '保存失败，请稍后重试');
    } finally {
      this.busy = false;
    }
  }

  private async regenerate(): Promise<void> {
    if (this.busy) return;
    if (!this.currentPassword) {
      this.errorText = '请输入当前密码';
      return;
    }
    this.busy = true;
    try {
      const result = await AccountCredentialService.regenerateRecoveryCodes(this.context, this.currentPassword);
      this.methods = result.loginMethods;
      this.busy = false;
      this.recoveryCodes = result.recoveryCodes;
      this.showView(VIEW_CODES);
    } catch (e) {
      this.errorText = this.errorMessage(e, '生成失败，请稍后重试');
    } finally {
      this.busy = false;
    }
  }

  private async bindHuawei(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      const result = await AccountCredentialService.bindHuawei(this.context);
      this.methods = result.loginMethods;
      HdsFeedback.showToast(result.welcomeGranted ? '已绑定华为账号，赠送的 300 点已到账' : '已绑定华为账号');
    } catch (e) {
      const error = e as BusinessError;
      // 1001502005 / 1001502012：用户取消了华为账号授权。
      if (error.code !== 1001502005 && error.code !== 1001502012) {
        HdsFeedback.showToast(this.errorMessage(e, '绑定华为账号失败'));
      }
    } finally {
      this.busy = false;
    }
  }

  private async requestDeletion(): Promise<void> {
    if (this.busy) return;
    if (this.methods.hasPassword && !this.currentPassword) {
      this.errorText = '请输入当前密码';
      return;
    }
    const confirm = await promptAction.showDialog({
      title: '确认注销账号？',
      message: `所有设备会立即退出登录。${DELETION_GRACE_DAYS} 天内重新登录可撤销，期满后点数、会员和云端数据都无法找回。`,
      buttons: [
        { text: '再想想', color: ThemeRuntime.subTextColor(this.appDarkMode) },
        { text: '申请注销', color: ThemeRuntime.dangerColor(this.appDarkMode) }
      ]
    });
    if (confirm.index !== 1) return;
    this.busy = true;
    try {
      const result = await AccountCredentialService.requestDeletion(this.context, this.currentPassword);
      CloudAutoSync.schedule(this.context, 0);
      HdsFeedback.showToast(`已申请注销，将于 ${this.formatDate(result.scheduledAt)} 生效，期间登录即可撤销`);
      this.busy = false;
      router.back();
    } catch (e) {
      this.errorText = this.errorMessage(e, '申请失败，请稍后重试');
    } finally {
      this.busy = false;
    }
  }

  private formatDate(value: number): string {
    if (!value) return `${DELETION_GRACE_DAYS} 天后`;
    const date = new Date(value);
    return `${date.getMonth() + 1} 月 ${date.getDate()} 日`;
  }

  private errorMessage(e: Object, fallback: string): string {
    if (e instanceof AccountApiError && e.message) return e.message;
    if (e instanceof Error && e.message) return e.message;
    return fallback;
  }
}
