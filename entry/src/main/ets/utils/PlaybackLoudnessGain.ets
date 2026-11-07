import { Context } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { media } from '@kit.MediaKit';
import preferences from '@ohos.data.preferences';
import deviceInfo from '@ohos.deviceInfo';

interface TrackedAvPlayer {
  kind: string;
  player: media.AVPlayer;
}

/**
 * 朗读与有声书的音量增益（0~24 dB，存本机、不同步）。朗读和有声书各存一个值。
 *
 * 增益靠系统的响度接口实现，只对 STREAM_USAGE_AUDIOBOOK 等音频流生效：
 * - 朗读的 PCM 输出走 AudioRenderer.setLoudnessGain（API 20 起）；
 * - 在线朗读的音频文件和有声书走 AVPlayer.setLoudnessGain（API 21 起）；
 * - 系统朗读引擎自己出声（playType=1）时拿不到音频流，无法增益。
 * 播放器在创建/准备好后登记到这里，改值时对所有登记中的播放器立即生效；
 * 换章、换段会重建或重新准备播放器，届时按当前值重新下发。
 * 当前播放链能否增益发布在 *_SUPPORTED_KEY，面板据此置灰。
 */
export class PlaybackLoudnessGain {
  static readonly TTS: string = 'tts';
  static readonly AUDIO: string = 'audio';
  static readonly MAX_DB: number = 24;
  /** 快捷档只到 +12，再往上容易破音，界面上给提示。 */
  static readonly SAFE_DB: number = 12;
  static readonly TTS_KEY: string = 'ttsLoudnessGain';
  static readonly AUDIO_KEY: string = 'audioLoudnessGain';
  static readonly TTS_SUPPORTED_KEY: string = 'ttsLoudnessGainSupported';
  static readonly AUDIO_SUPPORTED_KEY: string = 'audioLoudnessGainSupported';
  private static readonly STORE: string = 'playback_loudness_gain';
  /** 部分设备上增益已经生效但 Promise 一直不返回，最多等这么久就按成功处理。 */
  private static readonly APPLY_WAIT_MS: number = 1500;
  private static context: Context | null = null;
  private static writes: Promise<void> = Promise.resolve();
  private static renderers: audio.AudioRenderer[] = [];
  private static avPlayers: TrackedAvPlayer[] = [];

  static async load(context: Context): Promise<void> {
    PlaybackLoudnessGain.context = context;
    AppStorage.setOrCreate(PlaybackLoudnessGain.TTS_SUPPORTED_KEY, true);
    AppStorage.setOrCreate(PlaybackLoudnessGain.AUDIO_SUPPORTED_KEY, PlaybackLoudnessGain.avPlayerSupported());
    const store = await preferences.getPreferences(context, PlaybackLoudnessGain.STORE);
    const tts = await store.get(PlaybackLoudnessGain.TTS_KEY, 0);
    const audioGain = await store.get(PlaybackLoudnessGain.AUDIO_KEY, 0);
    AppStorage.setOrCreate(PlaybackLoudnessGain.TTS_KEY, PlaybackLoudnessGain.normalize(tts as number));
    AppStorage.setOrCreate(PlaybackLoudnessGain.AUDIO_KEY, PlaybackLoudnessGain.normalize(audioGain as number));
    // 设置读出来之前就已开始的播放补一次。
    PlaybackLoudnessGain.applyToTracked(PlaybackLoudnessGain.TTS);
    PlaybackLoudnessGain.applyToTracked(PlaybackLoudnessGain.AUDIO);
  }

  static normalize(value: number): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) return 0;
    return Math.max(0, Math.min(PlaybackLoudnessGain.MAX_DB, Math.round(value)));
  }

  static gain(kind: string): number {
    return PlaybackLoudnessGain.normalize(AppStorage.get<number>(PlaybackLoudnessGain.keyOf(kind)) ?? 0);
  }

  static set(kind: string, value: number): void {
    const gain = PlaybackLoudnessGain.normalize(value);
    const key = PlaybackLoudnessGain.keyOf(kind);
    AppStorage.setOrCreate(key, gain);
    PlaybackLoudnessGain.applyToTracked(kind);
    const context = PlaybackLoudnessGain.context;
    if (!context) return;
    const write = PlaybackLoudnessGain.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, PlaybackLoudnessGain.STORE);
      await store.put(key, gain);
      await store.flush();
    });
    PlaybackLoudnessGain.writes = write.catch((error: Error) => {
      console.warn('[Loudness] save gain failed:', error?.message);
    });
  }

  static avPlayerSupported(): boolean {
    return deviceInfo.sdkApiVersion >= 21;
  }

  /** 正在播放的链路能否增益；面板据此置灰并说明原因。 */
  static markSupported(kind: string, supported: boolean): void {
    const key = kind === PlaybackLoudnessGain.AUDIO ? PlaybackLoudnessGain.AUDIO_SUPPORTED_KEY :
      PlaybackLoudnessGain.TTS_SUPPORTED_KEY;
    if (AppStorage.get<boolean>(key) !== supported) AppStorage.setOrCreate(key, supported);
  }

  /** 朗读的 PCM 输出。新建的渲染器处于 prepared，可以直接设置。 */
  static trackRenderer(renderer: audio.AudioRenderer): void {
    PlaybackLoudnessGain.pruneRenderers();
    if (!PlaybackLoudnessGain.renderers.includes(renderer)) PlaybackLoudnessGain.renderers.push(renderer);
    PlaybackLoudnessGain.markSupported(PlaybackLoudnessGain.TTS, true);
    const gain = PlaybackLoudnessGain.gain(PlaybackLoudnessGain.TTS);
    if (gain > 0) PlaybackLoudnessGain.applyRenderer(renderer, gain);
  }

  static untrackRenderer(renderer: audio.AudioRenderer): void {
    PlaybackLoudnessGain.renderers = PlaybackLoudnessGain.renderers.filter(item => item !== renderer);
  }

  /** prepare 完成后调用（AVPlayer 只在 prepared/playing/paused/completed 接受设置）。重复调用只更新登记。 */
  static trackAvPlayer(kind: string, player: media.AVPlayer): void {
    PlaybackLoudnessGain.pruneAvPlayers();
    const supported = PlaybackLoudnessGain.avPlayerSupported();
    PlaybackLoudnessGain.markSupported(kind, supported);
    if (!supported) return;
    const existing = PlaybackLoudnessGain.avPlayers.find(item => item.player === player);
    if (existing) {
      existing.kind = kind;
    } else {
      PlaybackLoudnessGain.avPlayers.push({ kind: kind, player: player });
    }
    // 重新 prepare 后播放器回到默认 0 dB，即使值为 0 也不必下发。
    const gain = PlaybackLoudnessGain.gain(kind);
    if (gain > 0) PlaybackLoudnessGain.applyAvPlayer(kind, player, gain);
  }

  static untrackAvPlayer(player: media.AVPlayer): void {
    PlaybackLoudnessGain.avPlayers = PlaybackLoudnessGain.avPlayers.filter(item => item.player !== player);
  }

  private static keyOf(kind: string): string {
    return kind === PlaybackLoudnessGain.AUDIO ? PlaybackLoudnessGain.AUDIO_KEY : PlaybackLoudnessGain.TTS_KEY;
  }

  private static applyToTracked(kind: string): void {
    const gain = PlaybackLoudnessGain.gain(kind);
    if (kind === PlaybackLoudnessGain.TTS) {
      PlaybackLoudnessGain.pruneRenderers();
      for (const renderer of PlaybackLoudnessGain.renderers) {
        PlaybackLoudnessGain.applyRenderer(renderer, gain);
      }
    }
    PlaybackLoudnessGain.pruneAvPlayers();
    for (const item of PlaybackLoudnessGain.avPlayers) {
      if (item.kind === kind) PlaybackLoudnessGain.applyAvPlayer(kind, item.player, gain);
    }
  }

  private static applyRenderer(renderer: audio.AudioRenderer, gain: number): void {
    try {
      PlaybackLoudnessGain.settle(renderer.setLoudnessGain(gain), PlaybackLoudnessGain.TTS);
    } catch (error) {
      PlaybackLoudnessGain.reportFailure(PlaybackLoudnessGain.TTS, error as Object);
    }
  }

  private static applyAvPlayer(kind: string, player: media.AVPlayer, gain: number): void {
    const state = player.state;
    if (state !== 'prepared' && state !== 'playing' && state !== 'paused' && state !== 'completed') return;
    try {
      PlaybackLoudnessGain.settle(player.setLoudnessGain(gain), kind);
    } catch (error) {
      PlaybackLoudnessGain.reportFailure(kind, error as Object);
    }
  }

  /** 不让调用方等这个 Promise：有的设备永远不返回。只在明确失败时记下不支持。 */
  private static settle(pending: Promise<void>, kind: string): void {
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
    }, PlaybackLoudnessGain.APPLY_WAIT_MS);
    pending.then(() => {
      clearTimeout(timer);
    }).catch((error: Object) => {
      clearTimeout(timer);
      if (!timedOut) PlaybackLoudnessGain.reportFailure(kind, error);
    });
  }

  private static reportFailure(kind: string, error: Object): void {
    const code = (error as Record<string, Object>)?.['code'];
    console.warn(`[Loudness] set ${kind} gain failed: ${JSON.stringify(error)}`);
    // 6800104：这个流不支持增益（例如走了高清直通通路）。其它错误多是状态时机问题，下次准备好会重试。
    if (code === 6800104 || code === 801) PlaybackLoudnessGain.markSupported(kind, false);
  }

  private static pruneRenderers(): void {
    PlaybackLoudnessGain.renderers = PlaybackLoudnessGain.renderers.filter(renderer =>
      renderer.state !== audio.AudioState.STATE_RELEASED);
  }

  private static pruneAvPlayers(): void {
    PlaybackLoudnessGain.avPlayers = PlaybackLoudnessGain.avPlayers.filter(item =>
      item.player.state !== 'released' && item.player.state !== 'error');
  }
}
