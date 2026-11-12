/**
 * 听书页按"播放器"进出：从底部滑上来、向底部滑下去，下面那一页原地不动。
 *
 * 听书页自己的进出在它的 pageTransition 里；下面那一页（首页、书籍详情）的退出/返回进入要配合成静止，
 * 它们的 pageTransition 读这里。系统在新页面第一帧画出时才读下层页面的转场，所以听书页在 aboutToAppear
 * 里登记来得及；返回时下层页面的进入转场在听书页销毁前读取，撤销登记要晚一点。
 * 用计数而不是开关：听书页上还能再开一层听书页（播放面板的设置入口）。
 * 进程级模块：页面文件里的类静态字段每次开页都是新的，不能放在页面里。
 */
export const AUDIO_SHEET_ENTER_DURATION: number = 320;
export const AUDIO_SHEET_EXIT_DURATION: number = 260;
const AUDIO_SHEET_RELEASE_DELAY: number = AUDIO_SHEET_EXIT_DURATION + 240;

export class AudioSheetTransition {
  private static count: number = 0;

  static attach(): void {
    AudioSheetTransition.count++;
  }

  static detach(): void {
    setTimeout((): void => {
      AudioSheetTransition.count = Math.max(0, AudioSheetTransition.count - 1);
    }, AUDIO_SHEET_RELEASE_DELAY);
  }

  /** 是否有听书页叠在上面（或刚收下去）：下层页面据此让自己的转场保持静止。 */
  static active(): boolean {
    return AudioSheetTransition.count > 0;
  }
}
