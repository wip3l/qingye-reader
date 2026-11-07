import { Router } from '@kit.ArkUI';

const HOME_URL = 'pages/Index';

/**
 * 回首页统一走这里：栈里已经有首页就退回去，没有才把当前页替换成首页。
 * 外部打开文件、快捷方式进书时首页可能还压在下面，直接 replaceUrl 会再叠一个首页；
 * 叠出来的首页互相看不见，书架开/关书按 id 截首页时会截到底下那个停在别的页签的旧实例。
 */
export class HomeRoute {
  static hasHome(appRouter: Router): boolean {
    try {
      return appRouter.getStateByUrl(HOME_URL).length > 0;
    } catch (_) {
      return false;
    }
  }

  static async replaceWithHome(appRouter: Router): Promise<void> {
    if (HomeRoute.hasHome(appRouter)) {
      appRouter.back({ url: HOME_URL });
      return;
    }
    await appRouter.replaceUrl({ url: HOME_URL });
  }
}
