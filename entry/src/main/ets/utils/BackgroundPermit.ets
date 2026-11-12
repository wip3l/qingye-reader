import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, WantAgent } from '@kit.AbilityKit';

export type BackgroundPermitMode = 'audioPlayback' | 'dataTransfer';

interface BackgroundPermitClaim {
  mode: BackgroundPermitMode;
  agent: WantAgent;
  context: common.UIAbilityContext;
  order: number;
}

const RETRY_DELAYS_MS: number[] = [2000, 5000, 15000, 30000];

/**
 * 应用的后台长时任务，整个进程只有一份。
 *
 * 一个 Ability 同一时刻只能有一个长时任务，停止时也不分是谁申请的。听书、朗读、全文缓存、规则校验、
 * 局域网服务都要用它，所以统一在这里登记：各自按名字申请和释放，全部释放后才真正停止。
 * 有播放声音的一方在时，任务类型用 audioPlayback（没有它系统会在退后台时停掉声音），
 * 其余时候用 dataTransfer；类型需要变时直接更新现有任务，中间不留空档。申请失败会重试几次。
 *
 * 必须放在 utils 模块里：pages 下的类静态字段每次开页都是新的。
 */
export class BackgroundPermit {
  private static claims: Map<string, BackgroundPermitClaim> = new Map<string, BackgroundPermitClaim>();
  private static runningMode: string = '';
  private static runningContext: common.UIAbilityContext | null = null;
  private static runningTaskId: number = -1;
  private static queue: Promise<void> = Promise.resolve();
  private static retryTimerId: number = -1;
  private static retryCount: number = 0;
  private static orderSeed: number = 0;
  private static ownerSeed: number = 0;
  private static cancelListening: boolean = false;

  /** 同一个类会有多个实例（每个阅读页一份）时，用它取互不相同的名字。 */
  static uniqueOwner(prefix: string): string {
    return `${prefix}-${++BackgroundPermit.ownerSeed}`;
  }

  /**
   * 登记并申请。返回 true 表示任务已在运行且类型满足这一方：播放方要求 audioPlayback，
   * 传输方只要有任务在即可。返回 false 时登记仍然保留，后面会自动重试，不需要调用方自己再停。
   */
  static async acquire(context: common.UIAbilityContext, owner: string, mode: BackgroundPermitMode,
    agent: WantAgent): Promise<boolean> {
    if (!owner) return false;
    // 有人新来登记：之前用完的重试次数重新计。
    if (BackgroundPermit.retryTimerId < 0) BackgroundPermit.retryCount = 0;
    const previous = BackgroundPermit.claims.get(owner);
    BackgroundPermit.claims.set(owner, {
      mode: mode,
      agent: agent,
      context: context,
      order: previous && previous.mode === mode ? previous.order : ++BackgroundPermit.orderSeed
    });
    await BackgroundPermit.enqueueReconcile();
    return BackgroundPermit.satisfies(owner);
  }

  static async release(owner: string): Promise<void> {
    if (!BackgroundPermit.claims.delete(owner)) return;
    await BackgroundPermit.enqueueReconcile();
  }

  /** 这一方已登记，且当前运行的任务类型满足它。 */
  static satisfies(owner: string): boolean {
    const claim = BackgroundPermit.claims.get(owner);
    if (!claim || !BackgroundPermit.runningMode) return false;
    return claim.mode !== 'audioPlayback' || BackgroundPermit.runningMode === 'audioPlayback';
  }

  static debugState(): string {
    return `running=${BackgroundPermit.runningMode || 'none'},owners=${Array.from(BackgroundPermit.claims.keys()).join('|')}`;
  }

  private static enqueueReconcile(): Promise<void> {
    const task = BackgroundPermit.queue.then((): Promise<void> => BackgroundPermit.reconcile());
    BackgroundPermit.queue = task.catch((): void => {});
    return BackgroundPermit.queue;
  }

  /** 某一类里最后登记的一方，通知点开后回到它。 */
  private static latestClaim(mode: BackgroundPermitMode): BackgroundPermitClaim | null {
    let latest: BackgroundPermitClaim | null = null;
    BackgroundPermit.claims.forEach((claim: BackgroundPermitClaim): void => {
      if (claim.mode === mode && (!latest || claim.order > latest.order)) latest = claim;
    });
    return latest;
  }

  /** 播放方优先。 */
  private static leadClaim(): BackgroundPermitClaim | null {
    return BackgroundPermit.latestClaim('audioPlayback') || BackgroundPermit.latestClaim('dataTransfer');
  }

  private static async reconcile(): Promise<void> {
    const lead = BackgroundPermit.leadClaim();
    if (!lead) {
      BackgroundPermit.clearRetry();
      await BackgroundPermit.stopRunning();
      return;
    }
    if (BackgroundPermit.runningMode === lead.mode) {
      BackgroundPermit.clearRetry();
      return;
    }
    if (BackgroundPermit.runningMode && await BackgroundPermit.updateRunning(lead)) {
      BackgroundPermit.clearRetry();
      console.info(`[BgPermit] updated: ${BackgroundPermit.debugState()}`);
      return;
    }
    const previousMode = BackgroundPermit.runningMode;
    await BackgroundPermit.stopRunning();
    try {
      await BackgroundPermit.startRunning(lead);
    } catch (error) {
      // 可能还留着一个这里不知道的任务（上次停止没成功）：停掉再申请一次。
      try {
        await backgroundTaskManager.stopBackgroundRunning(lead.context);
        await BackgroundPermit.startRunning(lead);
      } catch (_) {
        console.warn(`[BgPermit] start ${lead.mode} failed: ${BackgroundPermit.formatError(error as Object)}; ` +
          BackgroundPermit.debugState());
        await BackgroundPermit.restorePrevious(previousMode, lead.mode);
        BackgroundPermit.scheduleRetry();
        return;
      }
    }
    BackgroundPermit.clearRetry();
    console.info(`[BgPermit] started: ${BackgroundPermit.debugState()}`);
  }

  /** 任务已在运行、只是类型要变：直接更新，不停任务，应用在后台时也不会因为重新申请被拒而丢掉任务。 */
  private static async updateRunning(lead: BackgroundPermitClaim): Promise<boolean> {
    const context = BackgroundPermit.runningContext;
    if (!context) return false;
    try {
      const notification = await backgroundTaskManager.updateBackgroundRunning(context, [lead.mode]);
      BackgroundPermit.runningMode = lead.mode;
      const taskId = notification?.continuousTaskId;
      if (taskId !== undefined) BackgroundPermit.runningTaskId = taskId;
      return true;
    } catch (error) {
      console.warn(`[BgPermit] update to ${lead.mode} failed: ${BackgroundPermit.formatError(error as Object)}`);
      return false;
    }
  }

  /** 换类型没换成、原来的任务又已经停了：先把原来那类申请回来，别让还在跑的缓存、传输跟着被挂起。 */
  private static async restorePrevious(previousMode: string, failedMode: string): Promise<void> {
    if (!previousMode || previousMode === failedMode || BackgroundPermit.runningMode) return;
    const fallback = BackgroundPermit.latestClaim(previousMode as BackgroundPermitMode);
    if (!fallback) return;
    try {
      await BackgroundPermit.startRunning(fallback);
      console.info(`[BgPermit] restored: ${BackgroundPermit.debugState()}`);
    } catch (error) {
      console.warn(`[BgPermit] restore ${previousMode} failed: ${BackgroundPermit.formatError(error as Object)}`);
    }
  }

  private static async startRunning(claim: BackgroundPermitClaim): Promise<void> {
    BackgroundPermit.listenForCancel();
    const notification = await backgroundTaskManager.startBackgroundRunning(claim.context, [claim.mode], claim.agent);
    BackgroundPermit.runningMode = claim.mode;
    BackgroundPermit.runningContext = claim.context;
    BackgroundPermit.runningTaskId = notification?.continuousTaskId ?? -1;
  }

  private static async stopRunning(): Promise<void> {
    const context = BackgroundPermit.runningContext;
    if (!BackgroundPermit.runningMode || !context) return;
    BackgroundPermit.runningMode = '';
    BackgroundPermit.runningContext = null;
    BackgroundPermit.runningTaskId = -1;
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      console.info(`[BgPermit] stopped: ${BackgroundPermit.debugState()}`);
    } catch (error) {
      console.warn(`[BgPermit] stop failed: ${BackgroundPermit.formatError(error as Object)}`);
    }
  }

  /**
   * 系统或用户取消了任务（例如长时间没有声音、划掉通知）：只记下来，不在这里重新申请，
   * 否则会和系统来回拉扯。还在出声的一方由自己的心跳再来申请。
   */
  private static listenForCancel(): void {
    if (BackgroundPermit.cancelListening) return;
    BackgroundPermit.cancelListening = true;
    try {
      backgroundTaskManager.on('continuousTaskCancel', (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
        // 自己停止时也会收到；那时任务号已清掉或已换成新任务的，对不上就不管。
        if (!BackgroundPermit.runningMode || info.id !== BackgroundPermit.runningTaskId) return;
        console.warn(`[BgPermit] cancelled by system: reason=${info.reason}; ${BackgroundPermit.debugState()}`);
        BackgroundPermit.runningMode = '';
        BackgroundPermit.runningContext = null;
        BackgroundPermit.runningTaskId = -1;
      });
    } catch (error) {
      console.warn(`[BgPermit] listen cancel failed: ${BackgroundPermit.formatError(error as Object)}`);
    }
  }

  /** 只重试有限几次；之后由下一次登记，或出声一方的心跳再触发。 */
  private static scheduleRetry(): void {
    if (BackgroundPermit.retryTimerId >= 0 || BackgroundPermit.retryCount >= RETRY_DELAYS_MS.length) return;
    const delay = RETRY_DELAYS_MS[BackgroundPermit.retryCount];
    BackgroundPermit.retryCount++;
    BackgroundPermit.retryTimerId = setTimeout((): void => {
      BackgroundPermit.retryTimerId = -1;
      if (BackgroundPermit.claims.size > 0) BackgroundPermit.enqueueReconcile();
    }, delay);
  }

  private static clearRetry(): void {
    BackgroundPermit.retryCount = 0;
    if (BackgroundPermit.retryTimerId < 0) return;
    clearTimeout(BackgroundPermit.retryTimerId);
    BackgroundPermit.retryTimerId = -1;
  }

  private static formatError(error: Object): string {
    if (error instanceof Error) return error.message || String(error);
    try {
      return JSON.stringify(error);
    } catch (_) {
      return String(error);
    }
  }
}
