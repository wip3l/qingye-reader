import { router } from '@kit.ArkUI';
import { AccountCredentialService } from '../account/AccountCredentialService';
import { AccountApiError, PasswordLoginResponse } from '../account/AccountCommerceModels';
import { CloudAutoSync } from '../account/CloudAutoSync';
import { PageScaffold } from '../components/common/PageScaffold';
import { RecoveryCodesPanel } from '../components/common/RecoveryCodesPanel';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { HdsFeedback } from '../utils/HdsFeedback';
import { syncSystemBars } from '../utils/SystemBars';

const MODE_LOGIN = 'login';
const MODE_REGISTER = 'register';
const MODE_RECOVER = 'recover';
const MODE_CODES = 'codes';

/** 用户名登录、注册和用恢复码找回密码。注册成功后先展示恢复码，再回到会员与账号页。 */
@Entry
@Component
struct AccountPasswordLoginPage {
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @State mode: string = MODE_LOGIN;
  @State username: string = '';
  @State password: string = '';
  @State confirmPassword: string = '';
  @State recoveryCode: string = '';
  @State errorText: string = '';
  @State busy: boolean = false;
  @State recoveryCodes: string[] = [];

  onPageShow(): void {
    syncSystemBars(getContext(this), this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
  }

  build() {
    Stack() {
      PageScaffold({ title: this.title(), content: () => {
        this.pageContent()
      }, onBack: () => {
        this.leave();
      } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  onBackPress(): boolean {
    if (this.mode === MODE_RECOVER) {
      this.switchMode(MODE_LOGIN);
      return true;
    }
    return false;
  }

  private title(): string {
    if (this.mode === MODE_REGISTER) return '注册账号';
    if (this.mode === MODE_RECOVER) return '找回密码';
    if (this.mode === MODE_CODES) return '保存恢复码';
    return '用户名登录';
  }

  private leave(): void {
    if (this.mode === MODE_RECOVER) {
      this.switchMode(MODE_LOGIN);
      return;
    }
    router.back();
  }

  private switchMode(mode: string): void {
    if (this.busy) return;
    this.mode = mode;
    this.password = '';
    this.confirmPassword = '';
    this.recoveryCode = '';
    this.errorText = '';
  }

  @Builder
  pageContent() {
    Column({ space: AppSpacing.LG }) {
      if (this.mode === MODE_CODES) {
        RecoveryCodesPanel({ codes: this.recoveryCodes, doneLabel: '我已保存，完成', onDone: () => {
          router.back();
        } })
      } else {
        if (this.mode !== MODE_RECOVER) {
          this.modeTabs()
        }
        this.formCard()
        this.notes()
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: 14 })
  }

  @Builder
  modeTabs() {
    Row({ space: AppSpacing.XS }) {
      this.modeTab(MODE_LOGIN, '登录')
      this.modeTab(MODE_REGISTER, '注册')
    }
    .width('100%')
    .padding(AppSpacing.XS)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
  }

  @Builder
  modeTab(mode: string, label: string) {
    Text(label)
      .layoutWeight(1)
      .height(36)
      .textAlign(TextAlign.Center)
      .fontSize(AppFontSize.BODY_LARGE)
      .fontWeight(this.mode === mode ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.mode === mode ? ThemeRuntime.onAccentColor(ThemeRuntime.accentColor(this.appDarkMode)) :
        ThemeRuntime.subTextColor(this.appDarkMode))
      .borderRadius(ThemeRuntime.mediumRadius())
      .backgroundColor(this.mode === mode ? ThemeRuntime.accentColor(this.appDarkMode) : Color.Transparent)
      .onClick(() => {
        this.switchMode(mode);
      })
  }

  @Builder
  formCard() {
    Column({ space: AppSpacing.MD }) {
      this.field('username', '用户名', false)
      if (this.mode === MODE_RECOVER) {
        this.field('recoveryCode', '恢复码，例如 ABCD-EFGH-JKLM', false)
      }
      this.field('password', this.mode === MODE_LOGIN ? '密码' : '设置新密码', true)
      if (this.mode !== MODE_LOGIN) {
        this.field('confirmPassword', '再输入一次密码', true)
        Text(`用户名：${AccountCredentialService.USERNAME_HINT}\n密码：${AccountCredentialService.PASSWORD_HINT}`)
          .fontSize(AppFontSize.CAPTION)
          .lineHeight(18)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .width('100%')
      }
      if (this.errorText) {
        Text(this.errorText)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.dangerColor(this.appDarkMode))
          .width('100%')
      }
      Button(this.submitLabel())
        .width('100%')
        .height(44)
        .margin({ top: AppSpacing.XS })
        .fontSize(AppFontSize.BODY_LARGE)
        .enabled(!this.busy)
        .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.accentColor(this.appDarkMode)))
        .backgroundColor(ThemeRuntime.accentColor(this.appDarkMode))
        .onClick(() => {
          this.submit();
        })
      if (this.mode === MODE_LOGIN) {
        Text('忘记密码？用恢复码重设')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.accentColor(this.appDarkMode))
          .padding({ top: AppSpacing.XS, bottom: AppSpacing.XS })
          .onClick(() => {
            this.switchMode(MODE_RECOVER);
          })
      }
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
  }

  // 只传固定的字段名和提示文字，输入值在 builder 里按字段名读状态，避免按值传参不刷新。
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
      .maxLength(key === 'username' ? 20 : (key === 'recoveryCode' ? 20 : 64))
      .enabled(!this.busy)
      .onChange((value: string) => {
        this.setField(key, value);
      })
  }

  private fieldValue(key: string): string {
    if (key === 'username') return this.username;
    if (key === 'password') return this.password;
    if (key === 'confirmPassword') return this.confirmPassword;
    return this.recoveryCode;
  }

  private setField(key: string, value: string): void {
    if (key === 'username') {
      this.username = value;
    } else if (key === 'password') {
      this.password = value;
    } else if (key === 'confirmPassword') {
      this.confirmPassword = value;
    } else {
      this.recoveryCode = value;
    }
    this.errorText = '';
  }

  @Builder
  notes() {
    Text(this.noteText())
      .fontSize(AppFontSize.CAPTION)
      .lineHeight(18)
      .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .width('100%')
      .padding({ left: AppSpacing.XS, right: AppSpacing.XS })
  }

  private noteText(): string {
    if (this.mode === MODE_REGISTER) {
      return '用户名注册的账号不送新用户点数；之后在“登录与账号安全”里绑定一个没领过的华为账号，可补领 300 点。' +
        '服务端只保存用户名和加密后的密码。注册表示你同意应用的用户协议与隐私政策。';
    }
    if (this.mode === MODE_RECOVER) {
      return '每个恢复码只能用一次。重设密码后，已登录的其他设备都会退出登录。恢复码也用完了的话，绑定过华为账号的可以用华为账号登录后在“登录与账号安全”里改密码。';
    }
    return '已在华为账号下的账号，可以在“会员与账号 › 登录与账号安全”里设置用户名和密码后用这里登录。';
  }

  private submitLabel(): string {
    if (this.busy) return '请稍候';
    if (this.mode === MODE_REGISTER) return '注册并登录';
    if (this.mode === MODE_RECOVER) return '重设密码并登录';
    return '登录';
  }

  private validate(): string {
    const usernameProblem = AccountCredentialService.usernameProblem(this.username);
    if (this.mode === MODE_LOGIN) {
      if (usernameProblem || !this.password) return '请输入正确的用户名和密码';
      return '';
    }
    if (usernameProblem) return usernameProblem;
    if (this.mode === MODE_RECOVER && this.recoveryCode.replace(/[^A-Za-z0-9]/g, '').length !== 12) {
      return '恢复码是 12 位字母和数字';
    }
    const passwordProblem = AccountCredentialService.passwordProblem(this.password, this.username);
    if (passwordProblem) return passwordProblem;
    if (this.password !== this.confirmPassword) return '两次输入的密码不一致';
    return '';
  }

  private async submit(): Promise<void> {
    if (this.busy) return;
    const problem = this.validate();
    if (problem) {
      this.errorText = problem;
      return;
    }
    this.busy = true;
    this.errorText = '';
    const context = getContext(this);
    try {
      let response: PasswordLoginResponse;
      if (this.mode === MODE_REGISTER) {
        response = await AccountCredentialService.register(context, this.username, this.password);
      } else if (this.mode === MODE_RECOVER) {
        response = await AccountCredentialService.recover(context, this.username, this.recoveryCode, this.password);
      } else {
        response = await AccountCredentialService.login(context, this.username, this.password);
      }
      CloudAutoSync.schedule(context, 0);
      if (this.mode === MODE_REGISTER && response.recoveryCodes.length > 0) {
        this.recoveryCodes = response.recoveryCodes;
        this.password = '';
        this.confirmPassword = '';
        this.mode = MODE_CODES;
        return;
      }
      if (this.mode === MODE_RECOVER) {
        HdsFeedback.showToast(response.remainingRecoveryCodes > 0 ?
          `密码已重设，还剩 ${response.remainingRecoveryCodes} 个恢复码` : '密码已重设。恢复码已用完，请尽快重新生成');
      } else if (response.deletionCancelled) {
        HdsFeedback.showToast('登录成功，已撤销账号注销申请');
      } else {
        HdsFeedback.showToast('登录成功');
      }
      router.back();
    } catch (e) {
      this.errorText = this.errorMessage(e);
    } finally {
      this.busy = false;
    }
  }

  private errorMessage(e: Object): string {
    if (e instanceof AccountApiError && e.message) return e.message;
    if (e instanceof Error && e.message) return e.message;
    return '请求失败，请检查网络后重试';
  }
}
