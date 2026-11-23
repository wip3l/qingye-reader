// platform/LaunchAgent.ts 的安卓实现。安卓上没有 WantAgent；通知栏、媒体控件拉起应用的意图由
// PlaybackService 自己设置，这里返回占位对象，只为让共用代码的调用链走得下去。
import { common, WantAgent } from '@kit.AbilityKit';

export async function createLaunchAgent(_context: common.UIAbilityContext, _requestCode: number,
  _parameters?: Record<string, Object>): Promise<WantAgent> {
  return {} as WantAgent;
}
