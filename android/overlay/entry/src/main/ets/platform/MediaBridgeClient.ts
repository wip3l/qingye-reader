// 安卓专用：MediaSession.ts 和 BackgroundTasks.ts 共用的媒体桥（MediaBridge.java）客户端。鸿蒙构建里没有这个文件。
import bridge from '@arkui-x.bridge';

/** 与 MediaBridge.NAME 一致。 */
const MEDIA_BRIDGE_NAME = 'io.legado.read/media';

type CommandHandler = (command: string, argument: string) => void;

let mediaBridge: bridge.BridgeObject | null = null;
let commandHandler: CommandHandler | null = null;

function object(): bridge.BridgeObject {
  if (!mediaBridge) {
    mediaBridge = bridge.createBridge(MEDIA_BRIDGE_NAME);
    // 锁屏、耳机、通知栏按钮和音频焦点变化都经这里回来。
    mediaBridge.registerMethod({
      name: 'onMediaCommand',
      method: (command: Object, argument: Object): string => {
        if (commandHandler) commandHandler(String(command), String(argument || ''));
        return '';
      }
    }).catch((error: Error) => console.warn('[Media] 注册媒体命令回调失败:', error.message));
  }
  return mediaBridge;
}

export async function callMedia(method: string, ...args: string[]): Promise<void> {
  const raw = await object().callMethod(method, ...args);
  const text = String(raw || '');
  if (!text) return;
  const result = JSON.parse(text) as Record<string, string>;
  if (result.error) throw new Error(result.error);
}

export function setMediaCommandHandler(handler: CommandHandler | null): void {
  object();
  commandHandler = handler;
}
