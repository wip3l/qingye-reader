import { router } from '@kit.ArkUI';

export const OPEN_BOOK_SHORTCUT_ACTION = 'open_book';

class RecentReadRouteParams {
  bookUrl: string = '';
  shortcutEntry: string = 'true';
  shortcutReplace: string = 'false';

  constructor(bookUrl: string, replace: boolean = false) {
    this.bookUrl = bookUrl;
    this.shortcutReplace = replace ? 'true' : 'false';
  }
}

class RouteTarget {
  url: string = '';
  params?: RecentReadRouteParams;

  constructor(url: string, params?: RecentReadRouteParams) {
    this.url = url;
    this.params = params;
  }
}

export class RecentReadShortcut {
  static isPending(): boolean {
    const action = AppStorage.get<string>('launchShortcutAction') || '';
    return action === OPEN_BOOK_SHORTCUT_ACTION;
  }

  static requestBook(bookUrl: string): void {
    AppStorage.setOrCreate('launchShortcutAction', OPEN_BOOK_SHORTCUT_ACTION);
    AppStorage.setOrCreate('launchShortcutBookUrl', bookUrl);
    AppStorage.setOrCreate('launchShortcutNonce', Date.now());
  }

  static consume(): void {
    AppStorage.setOrCreate('launchShortcutAction', '');
    AppStorage.setOrCreate('launchShortcutBookUrl', '');
  }

  static async openPending(replaceWhenFallback: boolean = false): Promise<boolean> {
    const action = AppStorage.get<string>('launchShortcutAction') || '';
    const bookUrl = AppStorage.get<string>('launchShortcutBookUrl') || '';
    if (action === OPEN_BOOK_SHORTCUT_ACTION && bookUrl) {
      RecentReadShortcut.consume();
      return await RecentReadShortcut.openBook(bookUrl, replaceWhenFallback);
    }
    return false;
  }

  static async openBook(bookUrl: string, replaceWhenFallback: boolean = false): Promise<boolean> {
    if (!bookUrl) {
      return false;
    }
    const target = new RouteTarget('pages/ReadBook', new RecentReadRouteParams(bookUrl, replaceWhenFallback));
    return await RecentReadShortcut.navigate(target, replaceWhenFallback);
  }

  private static async navigate(target: RouteTarget, replace: boolean): Promise<boolean> {
    try {
      if (replace) {
        await router.replaceUrl(target);
      } else {
        await router.pushUrl(target);
      }
      return true;
    } catch (e) {
      console.error('打开最近阅读路由失败:', e);
      return false;
    }
  }
}
