import { window } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ThemeRuntime } from '../theme/ThemeRuntime';

let safeAreaWindow: window.Window | undefined;
let desktopWindow: window.Window | undefined;
const safeAreaChanged = (_data: window.AvoidAreaOptions): void => {
  if (safeAreaWindow) syncSystemSafeAreas(safeAreaWindow);
};
const desktopTitleRectChanged = (rect: window.TitleButtonRect): void => {
  if (!desktopWindow) return;
  updateDesktopTitleInset(desktopWindow, rect);
  syncSystemSafeAreas(desktopWindow);
};

// These APIs require loaded UI content. Keep the native buttons and title drag/double-click hot zone.
export function syncDesktopTitleBar(mainWindow: window.Window, darkMode: boolean): void {
  if (deviceInfo.deviceType !== '2in1') return;
  if (desktopWindow !== mainWindow) {
    try {
      mainWindow.on('windowTitleButtonRectChange', desktopTitleRectChanged);
      mainWindow.setWindowTitleMoveEnabled(true);
      mainWindow.setWindowDecorVisible(false);
      desktopWindow = mainWindow;
      updateDesktopTitleInset(mainWindow, mainWindow.getTitleButtonRect());
    } catch (err) {
      // Keep the standard title bar if this desktop runtime cannot provide safe button geometry.
      try {
        mainWindow.off('windowTitleButtonRectChange', desktopTitleRectChanged);
        mainWindow.setWindowDecorVisible(true);
      } catch (_) {}
      desktopWindow = undefined;
      AppStorage.setOrCreate('desktopTitleBarHeight', 0);
      console.warn('启用桌面沉浸标题栏失败，保留系统标题栏:', err);
      return;
    }
  }
  try {
    mainWindow.setDecorButtonStyle({
      colorMode: darkMode ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
        ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
    });
  } catch (err) {
    console.warn('同步桌面窗口按钮颜色失败:', err);
  }
  syncSystemSafeAreas(mainWindow);
}

function updateDesktopTitleInset(mainWindow: window.Window, rect: window.TitleButtonRect): void {
  // TitleButtonRect and decor height are already vp. A zero rectangle means hidden controls/full screen.
  const buttonBottom = rect.width > 0 && rect.height > 0 ? Math.max(0, rect.top + rect.height) : 0;
  let topInset = buttonBottom;
  if (buttonBottom > 0) {
    try {
      topInset = Math.max(buttonBottom, mainWindow.getWindowDecorHeight());
    } catch (_) {}
  }
  AppStorage.setOrCreate('desktopTitleBarHeight', topInset);
}

export function releaseSystemBarListeners(): void {
  try {
    safeAreaWindow?.off('avoidAreaChange', safeAreaChanged);
  } catch (_) {}
  try {
    desktopWindow?.off('windowTitleButtonRectChange', desktopTitleRectChanged);
  } catch (_) {}
  safeAreaWindow = undefined;
  desktopWindow = undefined;
  AppStorage.setOrCreate('desktopTitleBarHeight', 0);
}

export function syncSystemBars(context: Context, darkMode: boolean, backgroundColor?: string): void {
  const bg = backgroundColor || ThemeRuntime.pageColor(darkMode);
  window.getLastWindow(context).then((mainWindow: window.Window) => {
    mainWindow.setWindowBackgroundColor(bg);
    mainWindow.setWindowLayoutFullScreen(true);
    mainWindow.setWindowSystemBarEnable(['navigation', 'status']);
    syncDesktopTitleBar(mainWindow, darkMode);
    syncSystemSafeAreas(mainWindow);
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      isStatusBarLightIcon: darkMode,
      statusBarContentColor: ThemeRuntime.primaryTextColor(darkMode),
      navigationBarColor: '#00000000',
      isNavigationBarLightIcon: darkMode,
      navigationBarContentColor: ThemeRuntime.primaryTextColor(darkMode)
    });
  }).catch((err: Error) => {
    console.error('同步系统栏颜色失败:', err);
  });
}

export function syncSystemSafeAreas(mainWindow: window.Window): void {
  try {
    const systemArea = mainWindow.getWindowAvoidAreaIgnoringVisibility(window.AvoidAreaType.TYPE_SYSTEM);
    const navigationArea = mainWindow.getWindowAvoidAreaIgnoringVisibility(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    const gestureArea = mainWindow.getWindowAvoidAreaIgnoringVisibility(window.AvoidAreaType.TYPE_SYSTEM_GESTURE);
    const uiContext = mainWindow.getUIContext();
    const topHeight = Math.max(uiContext.px2vp(Math.max(0, systemArea.topRect.height)),
      AppStorage.get<number>('desktopTitleBarHeight') ?? 0);
    const bottomHeight = uiContext.px2vp(Math.max(
      0,
      navigationArea.bottomRect.height,
      gestureArea.bottomRect.height
    ));
    // A zero top avoid area is valid in landscape, free-form windows and on devices whose
    // system bar is not attached to the top edge. Treating it as a failed query leaves a
    // permanent 32vp strip in full-screen readers.
    AppStorage.setOrCreate('statusBarHeight', topHeight);
    AppStorage.setOrCreate('navBarHeight', bottomHeight > 0 ? bottomHeight : 0);
    registerSafeAreaListener(mainWindow);
  } catch (err) {
    console.error('同步系统安全区失败:', err);
    AppStorage.setOrCreate('statusBarHeight', Math.max(AppStorage.get<number>('statusBarHeight') ?? 0,
      AppStorage.get<number>('desktopTitleBarHeight') ?? 0));
    AppStorage.setOrCreate('navBarHeight', AppStorage.get<number>('navBarHeight') ?? 0);
  }
}

function registerSafeAreaListener(mainWindow: window.Window): void {
  if (safeAreaWindow === mainWindow) {
    return;
  }
  try {
    safeAreaWindow?.off('avoidAreaChange', safeAreaChanged);
    mainWindow.on('avoidAreaChange', safeAreaChanged);
    safeAreaWindow = mainWindow;
  } catch (err) {
    console.error('注册系统安全区监听失败:', err);
  }
}
