import { ComponentContent, UIContext, promptAction } from '@kit.ArkUI';
import { SystemDialogSession } from './SystemDialogSession';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { DialogButtonRole, DialogStyle } from '../theme/DialogStyle';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';

/** 弹窗内容需要的全部数据。内容在全局 @Builder 里画，只用系统内置组件。 */
class ThemedDialogContent {
  title: ResourceStr = '';
  message: ResourceStr = '';
  /** 标题较长时（多为一句说明）按正文样式显示。 */
  titleAsHint: boolean = false;
  labels: ResourceStr[] = [];
  roles: DialogButtonRole[] = [];
  /** 按钮竖排：超过两个，或文字较长并排放不下。 */
  stacked: boolean = false;
  darkMode: boolean = false;
  onPick: (index: number) => void = (_index: number): void => {};
  onCancel: () => void = (): void => {};
}

@Builder
function themedDialogButton(content: ThemedDialogContent, index: number) {
  // 按钮铺满所在的格子：并排时各占一半，竖排时整行宽，否则按钮只有文字那么宽、贴在左边。
  Button(content.labels[index])
    .type(ButtonType.Capsule)
    .width('100%')
    .height(DialogStyle.BUTTON_HEIGHT)
    .fontSize(AppFontSize.BODY_LARGE)
    .fontWeight(FontWeight.Medium)
    .fontColor(DialogStyle.text(content.roles[index], content.darkMode))
    .backgroundColor(DialogStyle.fill(content.roles[index], content.darkMode))
    .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
    .onClick(() => {
      content.onPick(index);
    })
}

@Builder
function themedConfirmContent(content: ThemedDialogContent) {
  Column({ space: AppSpacing.MD }) {
    if (content.title) {
      Text(content.title)
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(content.darkMode))
        .width('100%')
    }
    if (content.message) {
      Scroll() {
        Text(content.message)
          .fontSize(AppFontSize.BODY)
          .lineHeight(22)
          .fontColor(ThemeRuntime.subTextColor(content.darkMode))
          .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: 360 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .align(Alignment.TopStart)
    }
    if (content.labels.length > 0) {
      if (content.stacked) {
        Column({ space: AppSpacing.SM }) {
          ForEach(content.labels, (_label: ResourceStr, index: number) => {
            themedDialogButton(content, index)
          }, (_label: ResourceStr, index: number): string => `${index}`)
        }
        .width('100%')
        .margin({ top: AppSpacing.XS })
      } else {
        Row({ space: AppSpacing.MD }) {
          ForEach(content.labels, (_label: ResourceStr, index: number) => {
            Row() {
              themedDialogButton(content, index)
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          }, (_label: ResourceStr, index: number): string => `${index}`)
        }
        .width('100%')
        .margin({ top: AppSpacing.XS })
      }
    }
  }
  .padding({ left: AppSpacing.XXXL, right: AppSpacing.XXXL, top: AppSpacing.XXXL, bottom: AppSpacing.XXL })
}

@Builder
function themedMenuRow(content: ThemedDialogContent, index: number) {
  Row({ space: AppSpacing.LG }) {
    Text(content.labels[index])
      .fontSize(AppFontSize.BODY_LARGE)
      .fontWeight(FontWeight.Medium)
      .fontColor(content.roles[index] === 'danger' ? ThemeRuntime.dangerColor(content.darkMode) :
        ThemeRuntime.primaryTextColor(content.darkMode))
      .layoutWeight(1)
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(14)
      .fontColor([ThemeRuntime.subTextColor(content.darkMode)])
  }
  .width('100%')
  .constraintSize({ minHeight: 50 })
  .padding({ left: AppSpacing.XL, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.MD })
  .borderRadius(ThemeRuntime.largeRadius())
  .backgroundColor(DialogStyle.rowFill(content.darkMode))
  .alignItems(VerticalAlign.Center)
  .onClick(() => {
    content.onPick(index);
  })
}

@Builder
function themedMenuContent(content: ThemedDialogContent) {
  Column({ space: AppSpacing.MD }) {
    if (content.title) {
      Text(content.title)
        .fontSize(content.titleAsHint ? AppFontSize.BODY : AppFontSize.SUBTITLE)
        .fontWeight(content.titleAsHint ? FontWeight.Normal : FontWeight.Bold)
        .fontColor(content.titleAsHint ? ThemeRuntime.subTextColor(content.darkMode) :
          ThemeRuntime.primaryTextColor(content.darkMode))
        .lineHeight(content.titleAsHint ? 22 : undefined)
        .width('100%')
        .margin({ bottom: AppSpacing.XS })
    }
    Scroll() {
      Column({ space: AppSpacing.MD }) {
        ForEach(content.labels, (_label: ResourceStr, index: number) => {
          themedMenuRow(content, index)
        }, (_label: ResourceStr, index: number): string => `${index}`)
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxHeight: 420 })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    Text('取消')
      .fontSize(AppFontSize.BODY_LARGE)
      .fontColor(ThemeRuntime.subTextColor(content.darkMode))
      .textAlign(TextAlign.Center)
      .width('100%')
      .height(40)
      .onClick(() => {
        content.onCancel();
      })
  }
  .padding({ left: AppSpacing.XXXL, right: AppSpacing.XXXL, top: AppSpacing.XXXL, bottom: AppSpacing.LG })
}

/** ThemedDialog.showAlertDialog 的按钮，字段与系统 showAlertDialog 的按钮一致。 */
export interface ThemedAlertButton {
  value: ResourceStr;
  fontColor?: ResourceColor;
  action: () => void;
}

/** ThemedDialog.showAlertDialog 的参数，字段与系统 showAlertDialog 一致（只取用到的部分）。 */
export interface ThemedAlertOptions {
  title?: ResourceStr;
  message: ResourceStr;
  confirm?: ThemedAlertButton;
  primaryButton?: ThemedAlertButton;
  secondaryButton?: ThemedAlertButton;
  cancel?: () => void;
}

interface ThemedDialogHostApi {
  confirm: (content: ThemedDialogContent) => void;
  menu: (content: ThemedDialogContent) => void;
}

/** 宿主组件 aboutToAppear 时登记在这里，由 ThemedDialog.hostFor 取走。 */
let pendingHostApi: ThemedDialogHostApi | undefined = undefined;

/**
 * 弹窗内容的宿主。openCustomDialog 调 builder 时不带组件 this，而 @Builder 里每个组件都要经
 * this.observeComponentCreation2 创建，直接在静态方法里调全局 @Builder 会以 undefined 为 this 闪退。
 * 这里把宿主建在离屏的 ComponentContent 里（不挂到页面上），弹窗内容经它的成员 @Builder 画，
 * 调用方不论是不是组件都不用传宿主。内容不带状态变量，宿主不在树上也不影响显示。
 */
@Component
struct ThemedDialogHost {
  aboutToAppear(): void {
    pendingHostApi = {
      confirm: (content: ThemedDialogContent): void => {
        this.confirmContent(content);
      },
      menu: (content: ThemedDialogContent): void => {
        this.menuContent(content);
      }
    };
  }

  @Builder
  confirmContent(content: ThemedDialogContent) {
    themedConfirmContent(content)
  }

  @Builder
  menuContent(content: ThemedDialogContent) {
    themedMenuContent(content)
  }

  build() {
    Column()
  }
}

@Builder
function themedDialogHostNode() {
  ThemedDialogHost()
}

/**
 * 应用内的确认框和操作菜单，替代系统的 showDialog / showActionMenu：表面是沉浸光感材质（经 SystemDialogSession），
 * 按钮与选项行用半透明底（见 DialogStyle），和其他居中弹窗一个样子。
 *
 * 用法与系统接口一致：选中按钮时返回 { index }；点蒙层或返回键取消时 Promise 被拒绝，调用方照旧 catch。
 * 按钮的 color 只用来认出删除类按钮（传危险色或警告色），其余按位置定：最后一个是确认，前面的是取消/次要。
 */
export class ThemedDialog {
  private static hostNode: ComponentContent<Object> | undefined = undefined;
  private static hostContext: UIContext | undefined = undefined;
  private static hostApi: ThemedDialogHostApi | undefined = undefined;

  static showDialog(uiContext: UIContext, options: promptAction.ShowDialogOptions,
    darkMode?: boolean): Promise<promptAction.ShowDialogSuccessResponse> {
    const dark = ThemedDialog.darkOf(darkMode);
    const content = new ThemedDialogContent();
    content.darkMode = dark;
    content.title = options.title || '';
    content.message = options.message || '';
    const buttons: promptAction.Button[] = options.buttons ? options.buttons : [];
    for (let i = 0; i < buttons.length; i++) {
      content.labels.push(buttons[i].text);
      content.roles.push(ThemedDialog.roleOf(buttons[i], i, buttons.length, dark));
    }
    content.stacked = buttons.length > 2 || content.labels.some((label: ResourceStr): boolean =>
      typeof label === 'string' && label.length > 6);
    return ThemedDialog.run(uiContext, content, false).then((index: number) => {
      const result: promptAction.ShowDialogSuccessResponse = { index: index };
      return result;
    });
  }

  static showActionMenu(uiContext: UIContext, options: promptAction.ActionMenuOptions,
    darkMode?: boolean): Promise<promptAction.ActionMenuSuccessResponse> {
    const dark = ThemedDialog.darkOf(darkMode);
    const content = new ThemedDialogContent();
    content.darkMode = dark;
    content.title = options.title || '';
    content.titleAsHint = typeof content.title === 'string' && content.title.length > 12;
    const buttons: promptAction.Button[] = [];
    options.buttons.forEach((button: promptAction.Button | undefined) => {
      if (button) buttons.push(button);
    });
    for (let i = 0; i < buttons.length; i++) {
      content.labels.push(buttons[i].text);
      content.roles.push(ThemedDialog.isDangerColor(buttons[i].color, dark) ? 'danger' : 'cancel');
    }
    return ThemedDialog.run(uiContext, content, true).then((index: number) => {
      const result: promptAction.ActionMenuSuccessResponse = { index: index };
      return result;
    });
  }

  /**
   * 替代 UIContext.showAlertDialog：按钮带回调的写法。confirm 是只有一个按钮的提示；
   * primaryButton 在左、secondaryButton 在右（右边按确认显示，fontColor 传危险色时按删除类显示）。
   * 点蒙层或返回键关闭时调 cancel。
   */
  static showAlertDialog(uiContext: UIContext, options: ThemedAlertOptions, darkMode?: boolean): void {
    const dark = ThemedDialog.darkOf(darkMode);
    const content = new ThemedDialogContent();
    content.darkMode = dark;
    content.title = options.title || '';
    content.message = options.message || '';
    const buttons: ThemedAlertButton[] = [];
    if (options.confirm) buttons.push(options.confirm);
    if (options.primaryButton) buttons.push(options.primaryButton);
    if (options.secondaryButton) buttons.push(options.secondaryButton);
    for (let i = 0; i < buttons.length; i++) {
      content.labels.push(buttons[i].value);
      content.roles.push(ThemedDialog.isDangerColor(buttons[i].fontColor, dark) ? 'danger' :
        (i === buttons.length - 1 ? 'primary' : 'cancel'));
    }
    content.stacked = buttons.length > 2 || content.labels.some((label: ResourceStr): boolean =>
      typeof label === 'string' && label.length > 6);
    ThemedDialog.run(uiContext, content, false).then((index: number): void => {
      if (index >= 0 && index < buttons.length) buttons[index].action();
    }, (): void => {
      if (options.cancel) options.cancel();
    });
  }

  private static run(uiContext: UIContext, content: ThemedDialogContent, menu: boolean): Promise<number> {
    return new Promise<number>((resolve: (index: number) => void, reject: (error: Error) => void) => {
      const session = new SystemDialogSession();
      let settled = false;
      const finish = (index: number): void => {
        if (settled) return;
        settled = true;
        session.close(uiContext);
        if (index >= 0) {
          resolve(index);
        } else {
          reject(new Error('cancel'));
        }
      };
      content.onPick = (index: number): void => finish(index);
      content.onCancel = (): void => finish(-1);
      const host = ThemedDialog.hostFor(uiContext);
      if (!host) {
        settled = true;
        reject(new Error('themed dialog host unavailable'));
        return;
      }
      session.open(uiContext, (): void => {
        if (menu) {
          host.menu(content);
        } else {
          host.confirm(content);
        }
      }, {
        darkMode: content.darkMode,
        autoCancel: true,
        maskColor: ThemeRuntime.scrimColor(content.darkMode),
        warnTag: menu ? '显示操作菜单失败:' : '显示确认框失败:',
        onDismiss: (): void => {
          if (settled) return;
          settled = true;
          reject(new Error('cancel'));
        },
        onOpenFailed: (error: Error): void => {
          if (settled) return;
          settled = true;
          reject(error);
        }
      });
    });
  }

  /** 每个窗口（UIContext）一个离屏宿主；换了窗口就重建，旧的留给可能还开着的弹窗，不主动释放。 */
  private static hostFor(uiContext: UIContext): ThemedDialogHostApi | undefined {
    if (ThemedDialog.hostApi && ThemedDialog.hostContext === uiContext) return ThemedDialog.hostApi;
    pendingHostApi = undefined;
    try {
      ThemedDialog.hostNode = new ComponentContent<Object>(uiContext, wrapBuilder(themedDialogHostNode));
    } catch (error) {
      console.warn('创建弹窗宿主失败:', error);
      return undefined;
    }
    if (!pendingHostApi) return undefined;
    ThemedDialog.hostApi = pendingHostApi;
    ThemedDialog.hostContext = uiContext;
    pendingHostApi = undefined;
    return ThemedDialog.hostApi;
  }

  private static darkOf(darkMode?: boolean): boolean {
    return darkMode !== undefined ? darkMode : (AppStorage.get<boolean>('appDarkMode') || false);
  }

  private static roleOf(button: promptAction.Button, index: number, count: number, dark: boolean): DialogButtonRole {
    if (ThemedDialog.isDangerColor(button.color, dark)) return 'danger';
    if (button.primary === true || index === count - 1) return 'primary';
    return 'cancel';
  }

  private static isDangerColor(color: ResourceColor | undefined, dark: boolean): boolean {
    if (typeof color !== 'string') return false;
    const value = color.toUpperCase();
    const candidates: string[] = [ThemeRuntime.dangerColor(dark), ThemeRuntime.dangerColor(!dark),
      ThemeRuntime.warningColor(dark)];
    return candidates.some((candidate: string): boolean => candidate.toUpperCase() === value);
  }
}
