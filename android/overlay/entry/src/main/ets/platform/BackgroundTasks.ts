// platform/BackgroundTasks.ts 的安卓实现：后台长时任务对应安卓的前台服务（PlaybackService，经 MediaBridge 启停）。
// 只实现 BackgroundPermit 用到的接口。
import { common, WantAgent } from '@kit.AbilityKit';
import { callMedia } from './MediaBridgeClient';

export namespace backgroundTaskManager {
  export interface ContinuousTaskNotification {
    slotType?: number;
    contentType?: number;
    notificationId: number;
    continuousTaskId?: number;
  }

  export interface ContinuousTaskCancelInfo {
    reason: number;
    id: number;
  }

  /** 安卓上只有一个前台服务，任务号恒为 1。 */
  const TASK_ID = 1;

  export async function startBackgroundRunning(_context: common.UIAbilityContext, _modes: string[],
    _agent: WantAgent): Promise<ContinuousTaskNotification> {
    await callMedia('startBackground');
    return { notificationId: TASK_ID, continuousTaskId: TASK_ID };
  }

  export async function updateBackgroundRunning(_context: common.UIAbilityContext, _modes: string[]):
    Promise<ContinuousTaskNotification> {
    await callMedia('startBackground');
    return { notificationId: TASK_ID, continuousTaskId: TASK_ID };
  }

  export async function stopBackgroundRunning(_context: common.UIAbilityContext): Promise<void> {
    await callMedia('stopBackground');
  }

  /** 安卓前台服务不会被系统按“长时间没有声音”取消，没有取消事件可报。 */
  export function on(_type: string, _callback: (info: ContinuousTaskCancelInfo) => void): void {
  }
}
