import { common } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { SystemTtsReader, TtsChunk, TtsReadOptions } from '../../utils/SystemTtsReader';
import { TtsVoicePicker } from '../../utils/TtsVoicePicker';
import { ReaderTtsFloatingSession } from '../../utils/ReaderTtsFloatingSession';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { ReaderTtsMediaInfo, ReaderTtsMediaSession } from '../reader/ReaderTtsMediaSession';
import { ReaderProgressCheckpoint } from '../../utils/ReaderProgressCheckpoint';
import { EpubOriginalPosition } from './EpubOriginalPosition';

/** 网页正文里要念的文字（见 EpubOriginalScript 的 speechInfo）。 */
export class EpubSpeechText {
  text: string = '';
  /** 当前屏第一个要念的字。 */
  start: number = 0;
  /** 翻页模式下每一页第一个字的下标，朗读在这里断句。 */
  breaks: number[] = [];
}

/**
 * 朗读的内容与动作由谁提供：文件排版页（网页正文）或页面关掉后的后台朗读（应用排版正文，见 EpubOriginalBackgroundHost）。
 */
export interface EpubReadAloudHost {
  context: () => common.UIAbilityContext;
  bookUrl: () => string;
  bookName: () => string;
  author: () => string;
  chapterIndex: () => number;
  chapterTitles: () => string[];
  /** 章内进度 0–1，用于面板与媒体卡片的进度。 */
  chapterProgress: () => number;
  /** 媒体卡片副标题里的位置，如“第 3/12 页”。 */
  positionLabel: () => string;
  cover: () => ResourceStr;
  coverRaw: () => ResourceStr;
  /** 取当前章里要念的文字。 */
  speech: () => Promise<EpubSpeechText | null>;
  /** 正在念 text 的 [start, end)：页面高亮并翻页跟随，后台记下进度。 */
  focus: (start: number, end: number, text: string) => void;
  clearFocus: () => void;
  /** 换到某章开头并等它准备好；换成了返回 true。 */
  openChapter: (index: number) => Promise<boolean>;
  openMimoSettings: () => void;
  /** 朗读 / 暂停状态变了，页面据此刷新按钮与胶囊。 */
  changed: () => void;
  /** 朗读结束（停止、读完、被别处接管）。 */
  stopped: () => void;
}

/** 连续朗读时章节末尾没确认念完，最多从最后一句重读这么多次。 */
const TAIL_RETRIES = 2;
/** 用户翻页、跳转后等这么久再从新位置接着读，连续翻页只重开一次。 */
const MOVE_RESTART_MS = 450;
/** 后台朗读时隔这么久看一眼：普通阅读页在前台打开了同一本书就停下，交给它。 */
const DETACHED_WATCH_MS = 1000;

/**
 * 文件排版页的朗读：文字从网页正文取（排版即所见），朗读引擎、系统媒体控件、悬浮朗读面板与普通阅读页共用。
 * 念到哪句由引擎回报文字里的偏移，交给页面高亮、翻页；一章念完换到下一章开头接着念。
 * 用户自己翻页、跳章时从新位置重新开始。
 * 离开这本书时页面把朗读交给后台（detach），文字改读应用排版正文接着念；重新打开这本书时页面接回来（attach）。
 * 两种文字之间的位置按文字片段换算（EpubOriginalPosition），同一章换了文字来源也能接着原处读。
 */
export class EpubOriginalReadAloud {
  /** 离开了页面、在后台接着念的朗读，按书记着，重新打开这本书的页面据此接手。 */
  private static detachedSessions: Map<string, EpubOriginalReadAloud> = new Map<string, EpubOriginalReadAloud>();
  readonly ownerId: string = `epub_original_tts_${Date.now()}_${Math.random()}`;
  speaking: boolean = false;
  paused: boolean = false;
  private host: EpubReadAloudHost;
  private detachedBookUrl: string = '';
  /** 重新打开这本书的文件排版页已经认领，正在等它排好版再接手。 */
  private claimed: boolean = false;
  private watchTimer: number = -1;
  private engine: SystemTtsReader | null = null;
  private media: ReaderTtsMediaSession | null = null;
  private voices: TtsVoicePicker | null = null;
  private token: number = 0;
  private autoContinue: boolean = false;
  /** 正在念的这一章的文字与章节号；begin 是交给引擎的那段从哪里开始。 */
  private text: string = '';
  private chapter: number = -1;
  private begin: number = 0;
  private focusStart: number = -1;
  private focusEnd: number = -1;
  private spokenEnd: number = -1;
  private expectedEnd: number = -1;
  private tailRetries: number = 0;
  private switching: boolean = false;
  private voicesRequested: boolean = false;
  private moveTimer: number = -1;
  private speedTimer: number = -1;
  private sleepTimer: number = -1;
  private sleepEndAt: number = 0;
  private sleepMinutes: number = 0;
  private sleepRemaining: number = 0;

  constructor(host: EpubReadAloudHost) {
    this.host = host;
  }

  /** 这本书在后台接着念的朗读；没有返回 null。 */
  static detachedFor(bookUrl: string): EpubOriginalReadAloud | null {
    const session = bookUrl ? EpubOriginalReadAloud.detachedSessions.get(bookUrl) : undefined;
    if (!session) return null;
    if (!session.active()) {
      session.endDetached();
      return null;
    }
    return session;
  }

  /** 朗读会话还在（在念、暂停或出错后停着等重试）。 */
  active(): boolean {
    return this.speaking || ReaderTtsFloatingSession.isOwner(this.ownerId);
  }

  private reader(): SystemTtsReader {
    if (!this.engine) this.engine = new SystemTtsReader();
    return this.engine;
  }

  private picker(): TtsVoicePicker {
    if (!this.voices) {
      this.voices = new TtsVoicePicker(this.host.context(), (): string => this.host.bookUrl());
      this.voices.onListChanged = (): void => this.publishVoices();
      this.voices.onOpenMimoSettings = (): void => this.host.openMimoSettings();
    }
    return this.voices;
  }

  /** 打开朗读面板前读一遍音色设置与列表。 */
  prepare(): void {
    this.voicesRequested = true;
    this.picker().load().catch((error: Error): void => console.warn('[EpubTts] voices failed:', error));
  }

  // ---- 开始、暂停、停止 ----

  /** offset < 0 从当前屏第一个字开始；continuing 表示一章念完自动接下一章。 */
  async start(offset: number = -1, showToast: boolean = false, continuing: boolean = false,
    keepRetries: boolean = false): Promise<void> {
    this.cancelMoveRestart();
    const token = ++this.token;
    if (!keepRetries) this.tailRetries = 0;
    await this.picker().load(!this.voicesRequested);
    this.voicesRequested = true;
    const previousText = this.text;
    const previousChapter = this.chapter;
    const speech = await this.host.speech();
    if (token !== this.token) return;
    const text = speech ? speech.text : '';
    if (!text.trim()) {
      if (continuing) {
        // 整章只有插图：直接接着下一章。
        this.chapter = this.host.chapterIndex();
        this.expectedEnd = -1;
        await this.advance(token);
        return;
      }
      this.finish(false);
      if (showToast) HdsFeedback.showToast('当前没有可朗读内容');
      return;
    }
    this.text = text;
    this.chapter = this.host.chapterIndex();
    let requested = offset >= 0 ? offset : (speech?.start ?? 0);
    if (offset >= 0 && previousText && previousText !== text && previousChapter === this.chapter) {
      // 同一章换了文字来源（离开页面改读正文、回到页面改读网页）：offset 是旧文字里的，按文字片段换算过来。
      requested = EpubOriginalPosition.offsetFor(text, EpubOriginalPosition.spotAt(previousText, offset));
    }
    const begin = Math.max(0, Math.min(text.length - 1, requested));
    const part = text.substring(begin);
    this.begin = begin;
    this.focusStart = -1;
    this.focusEnd = -1;
    this.spokenEnd = -1;
    const audibleEnd = this.reader().speechTextEnd(part);
    this.expectedEnd = audibleEnd > 0 ? begin + audibleEnd : -1;
    await ReaderTtsFloatingSession.stopOther(this.ownerId);
    if (token !== this.token) return;
    this.autoContinue = true;
    this.paused = false;
    this.speaking = true;
    this.host.changed();
    const background = await this.mediaSession().startBackgroundRunning();
    if (token !== this.token) return;
    if (!background && showToast) HdsFeedback.showToast('后台朗读任务启动失败，息屏后可能中断');
    this.publish();
    const breaks: number[] = [];
    for (const value of speech?.breaks ?? []) {
      if (value > begin && value - begin < part.length) breaks.push(value - begin);
    }
    const options: TtsReadOptions = {
      mimoBook: this.host.bookUrl(),
      mimoBookName: this.host.bookName(),
      // MiMo 的角色修正按“章节 + 偏移 + 原文”记；文件排版的偏移与应用排版不同，章节键分开。
      mimoChapter: `epub-original:${this.chapter}`,
      mimoSourceOffset: begin,
      focusBreakOffsets: breaks,
      keepAudioOutputOnFinish: true,
      onFinished: (): void => {
        this.onFinished(token).catch((error: Error): void => {
          console.warn('[EpubTts] continue failed:', error);
          if (token === this.token) this.finish(false);
        });
      },
      onSpeechless: (): void => {
        if (token === this.token) this.expectedEnd = -1;
      },
      onError: (message: string): void => {
        if (token !== this.token) return;
        this.finish(true);
        HdsFeedback.showToast(message.startsWith('MIMO_ANALYSIS:') ?
          message.substring('MIMO_ANALYSIS:'.length) : (message || '朗读失败'));
      },
      onChunkStart: (chunk: TtsChunk): void => this.onChunk(chunk, token),
      onAudioStart: (): void => {
        if (token === this.token) this.mediaSession().onAudioStarted();
      }
    };
    this.picker().fillOptions(options);
    try {
      await this.reader().start(part, options);
      if (showToast && token === this.token) HdsFeedback.showToast('开始连续朗读');
    } catch (error) {
      if (token !== this.token) return;
      console.error('[EpubTts] start failed:', error);
      this.finish(true);
      HdsFeedback.showToast('当前系统不支持朗读或 TTS 初始化失败');
    }
  }

  /** 播放键：没在念就从当前屏（或停下的那句）开始，在念就暂停 / 继续。 */
  async toggle(): Promise<void> {
    if (this.moveTimer >= 0) {
      // 翻页后正等着从新位置重开：这时按暂停就停在新位置，继续时从那里读。
      this.cancelMoveRestart();
      this.speaking = false;
      this.paused = true;
      this.publishState();
      this.host.changed();
      return;
    }
    if (!this.speaking) {
      await this.start(this.resumeOffset(), true);
      return;
    }
    try {
      if (this.paused || this.engine?.isPaused()) {
        this.paused = false;
        if (await this.reader().resume()) {
          this.publishState();
          await this.mediaSession().updatePlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY);
        } else {
          this.paused = true;
        }
      } else {
        this.paused = true;
        if (await this.engine?.pause()) {
          this.publishState();
          await this.mediaSession().updatePlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
        } else {
          this.paused = false;
        }
      }
    } catch (error) {
      this.paused = this.engine?.isPaused() === true;
      console.warn('[EpubTts] toggle failed:', error);
    }
    this.publishState();
  }

  private resumeOffset(): number {
    return this.chapter === this.host.chapterIndex() && this.focusStart >= 0 ? this.focusStart : -1;
  }

  /** 停止并收起悬浮朗读与系统媒体控件。 */
  stop(): void {
    this.token++;
    this.autoContinue = false;
    this.cancelMoveRestart();
    this.clearSleepTimer(false);
    this.engine?.stop();
    this.speaking = false;
    this.paused = false;
    this.focusStart = -1;
    this.focusEnd = -1;
    ReaderTtsFloatingSession.clear(this.ownerId);
    this.media?.stopBackgroundRunning();
    this.host.clearFocus();
    this.host.changed();
    this.host.stopped();
    this.endDetached();
  }

  /**
   * 念不下去了（出错、读完）。keepControls：出错时留着面板与暂停状态，可以换个音色再点播放重试。
   */
  private finish(keepControls: boolean): void {
    const keep = keepControls && ReaderTtsFloatingSession.isOwner(this.ownerId);
    this.token++;
    this.autoContinue = false;
    this.cancelMoveRestart();
    this.engine?.stop();
    this.speaking = false;
    if (keep) {
      this.paused = true;
      this.publishState();
      this.mediaSession().updatePlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE).catch((): void => {});
      this.host.changed();
      return;
    }
    this.clearSleepTimer(false);
    this.paused = false;
    ReaderTtsFloatingSession.clear(this.ownerId);
    this.media?.stopBackgroundRunning();
    this.host.clearFocus();
    this.host.changed();
    this.host.stopped();
    this.endDetached();
  }

  // ---- 离开页面后接着念 ----

  /** 页面关掉了：换成后台的内容来源接着念，当前这段已经交给引擎的文字照常念完。 */
  detach(host: EpubReadAloudHost): void {
    this.cancelMoveRestart();
    this.host = host;
    this.claimed = false;
    this.detachedBookUrl = host.bookUrl();
    if (this.detachedBookUrl) EpubOriginalReadAloud.detachedSessions.set(this.detachedBookUrl, this);
    // 页面不在了，用户翻页后等着重开的那次照样要开：从停下的地方接着读。
    if (this.speaking && !this.paused && this.engine && !this.engine.isSpeaking()) {
      this.start(this.resumeOffset());
    }
    ReaderProgressCheckpoint.retainBackground(this.ownerId, (): string => this.detachedBookUrl);
    this.watchTimer = setInterval((): void => this.watchDetached(), DETACHED_WATCH_MS);
    this.publishDetails();
  }

  /** 重新打开这本书的文件排版页先认领，排好版后再 attach；页面没打开成就 unclaim。 */
  claim(): void {
    this.claimed = true;
  }

  unclaim(): void {
    this.claimed = false;
  }

  /** 页面接回来：在念就从正在念的那句接着（换算到网页文字），暂停着就停在那里等继续。 */
  async attach(host: EpubReadAloudHost): Promise<void> {
    this.endDetached();
    this.host = host;
    host.changed();
    if (!this.active()) return;
    const playing = this.speaking && !this.paused;
    const offset = this.focusStart >= 0 ? this.focusStart : this.begin;
    const token = ++this.token;
    this.engine?.stop();
    if (this.chapter >= 0 && this.chapter !== host.chapterIndex()) {
      this.switching = true;
      let opened = false;
      try {
        opened = await host.openChapter(this.chapter);
      } finally {
        this.switching = false;
      }
      if (token !== this.token) return;
      if (!opened) this.chapter = -1;
    }
    if (playing) {
      await this.start(this.chapter >= 0 ? offset : -1);
      return;
    }
    this.speaking = false;
    this.paused = true;
    this.publishState();
    host.changed();
  }

  private watchDetached(): void {
    if (!this.detachedBookUrl || this.claimed) return;
    if (!this.active()) {
      this.endDetached();
      return;
    }
    // 普通阅读页在前台打开了同一本书：它看不懂网页文字的位置，两边一起控制会乱，停下交给它。
    if (ReaderProgressCheckpoint.activeBookUrl() === this.detachedBookUrl) {
      this.stop();
      HdsFeedback.showToast('已在阅读页打开这本书，后台朗读已停止');
    }
  }

  private endDetached(): void {
    if (this.watchTimer >= 0) {
      clearInterval(this.watchTimer);
      this.watchTimer = -1;
    }
    if (this.detachedBookUrl &&
      EpubOriginalReadAloud.detachedSessions.get(this.detachedBookUrl) === this) {
      EpubOriginalReadAloud.detachedSessions.delete(this.detachedBookUrl);
    }
    const wasDetached = !!this.detachedBookUrl;
    this.detachedBookUrl = '';
    this.claimed = false;
    ReaderProgressCheckpoint.releaseBackground(this.ownerId);
    // 后台朗读结束后没有页面再用这个引擎了。
    if (wasDetached && !this.active()) {
      this.engine?.shutdown();
      this.engine = null;
    }
  }

  /** 页面关闭：停掉朗读并释放引擎。 */
  shutdown(): void {
    if (this.active()) this.stop();
    this.voices?.flush();
    if (this.speedTimer >= 0) clearTimeout(this.speedTimer);
    this.engine?.shutdown();
    this.engine = null;
  }

  // ---- 引擎回报 ----

  private onChunk(chunk: TtsChunk, token: number): void {
    if (token !== this.token || this.chapter !== this.host.chapterIndex()) return;
    const start = this.begin + chunk.start;
    const end = this.begin + chunk.end;
    this.focusStart = start;
    this.focusEnd = end;
    this.spokenEnd = Math.max(this.spokenEnd, end);
    this.host.focus(start, end, this.text);
    this.publishDetails();
  }

  private async onFinished(token: number): Promise<void> {
    if (token !== this.token || !this.autoContinue || this.switching) return;
    // 有的朗读通道会提前报完成：章末没确认念到就从最后一句重读，不吞掉没念的结尾。
    if (this.expectedEnd >= 0 && this.spokenEnd < this.expectedEnd - 4) {
      if (this.tailRetries < TAIL_RETRIES) {
        this.tailRetries++;
        console.warn(`[EpubTts] finished before chapter tail: spoken=${this.spokenEnd}, expected=${this.expectedEnd}`);
        await this.start(this.focusStart >= 0 ? this.focusStart : this.begin, false, false, true);
        return;
      }
      this.finish(true);
      HdsFeedback.showToast('当前章节末尾朗读未确认，朗读已暂停');
      return;
    }
    await this.advance(token);
  }

  private async advance(token: number): Promise<void> {
    const next = this.chapter + 1;
    if (next >= this.host.chapterTitles().length) {
      this.finish(false);
      HdsFeedback.showToast('已读完最后一章');
      return;
    }
    this.switching = true;
    this.host.clearFocus();
    let opened = false;
    try {
      this.mediaSession().updatePlaybackState(avSession.PlaybackState.PLAYBACK_STATE_BUFFERING).catch((): void => {});
      opened = await this.openChapterOnHost(next);
    } finally {
      this.switching = false;
    }
    if (token !== this.token) return;
    if (!opened) {
      this.finish(false);
      HdsFeedback.showToast('下一章加载失败，朗读已停止');
      return;
    }
    await this.start(0, false, true);
  }

  // ---- 用户操作 ----

  /** 用户自己翻页、跳转、改了版式：在念就从新位置重开；暂停着就记下，继续时从新位置读。 */
  userMoved(): void {
    if (!this.active() || this.switching) return;
    this.token++;
    this.engine?.stop();
    this.focusStart = -1;
    this.focusEnd = -1;
    this.chapter = -1;
    this.host.clearFocus();
    if (!this.speaking || this.paused) {
      // 引擎已经停了，继续时走 start。
      this.speaking = false;
      this.paused = true;
      this.publishState();
      this.host.changed();
      return;
    }
    this.cancelMoveRestart();
    this.moveTimer = setTimeout((): void => {
      this.moveTimer = -1;
      this.start(-1).catch((error: Error): void => console.warn('[EpubTts] restart failed:', error));
    }, MOVE_RESTART_MS);
  }

  /** 换章期间页面关掉了（交给了后台）：页面那边的等待作废，换到新的内容来源上再换一次。 */
  private async openChapterOnHost(index: number): Promise<boolean> {
    const host = this.host;
    const opened = await host.openChapter(index);
    if (opened || this.host === host) return opened;
    return await this.host.openChapter(index);
  }

  private cancelMoveRestart(): void {
    if (this.moveTimer >= 0) {
      clearTimeout(this.moveTimer);
      this.moveTimer = -1;
    }
  }

  /** 面板目录、上一章 / 下一章、媒体控件：换到那一章开头接着念。 */
  async playChapter(index: number): Promise<void> {
    const titles = this.host.chapterTitles();
    if (index < 0 || index >= titles.length || this.switching) return;
    const resume = this.speaking && !this.paused;
    const token = ++this.token;
    this.engine?.stop();
    this.focusStart = -1;
    this.focusEnd = -1;
    this.host.clearFocus();
    this.switching = true;
    let opened = false;
    try {
      opened = await this.openChapterOnHost(index);
    } finally {
      this.switching = false;
    }
    if (token !== this.token) return;
    if (!opened) HdsFeedback.showToast('章节加载失败，已保留当前朗读位置');
    if (resume || !opened) {
      await this.start(opened ? 0 : this.resumeOffset());
      return;
    }
    this.speaking = false;
    this.paused = true;
    this.chapter = -1;
    this.publishState();
    this.host.changed();
  }

  private setSpeed(value: number): void {
    if (!this.picker().setSpeed(value)) return;
    this.publishDetails();
    if (!this.speaking || this.paused) return;
    // 拖动倍速时合并成一次重开，从正在念的那句接着读。
    if (this.speedTimer >= 0) clearTimeout(this.speedTimer);
    this.speedTimer = setTimeout((): void => {
      this.speedTimer = -1;
      if (this.speaking && !this.paused) this.start(this.resumeOffset());
    }, 120);
  }

  private selectVoice(index: number): void {
    const changed = this.picker().select(index);
    setTimeout((): void => this.publishVoices(), 0);
    if (changed && this.speaking && !this.paused) this.start(this.resumeOffset());
  }

  // ---- 定时停止 ----

  private setSleepTimer(minutes: number): void {
    this.clearSleepTimer(false);
    if (minutes <= 0) {
      HdsFeedback.showToast('已关闭朗读定时');
      this.publishDetails();
      return;
    }
    this.sleepMinutes = minutes;
    this.sleepRemaining = minutes * 60;
    this.sleepEndAt = Date.now() + minutes * 60 * 1000;
    this.sleepTimer = setInterval((): void => {
      this.sleepRemaining = Math.max(0, Math.ceil((this.sleepEndAt - Date.now()) / 1000));
      ReaderTtsFloatingSession.updateTimer(this.ownerId, this.sleepMinutes, this.sleepRemaining);
      if (this.sleepRemaining <= 0) {
        this.stop();
        HdsFeedback.showToast('朗读定时结束，已停止朗读');
      }
    }, 1000);
    this.publishDetails();
    HdsFeedback.showToast(`将在 ${minutes} 分钟后停止朗读`);
  }

  private clearSleepTimer(publish: boolean): void {
    if (this.sleepTimer >= 0) {
      clearInterval(this.sleepTimer);
      this.sleepTimer = -1;
    }
    this.sleepEndAt = 0;
    this.sleepMinutes = 0;
    this.sleepRemaining = 0;
    if (publish) this.publishDetails();
  }

  // ---- 悬浮朗读面板与系统媒体控件 ----

  private publish(): void {
    const titles = this.host.chapterTitles();
    ReaderTtsFloatingSession.attach(this.ownerId, this.host.bookUrl(), this.host.bookName() || '正在朗读',
      this.chapterTitle(), this.paused, (): Promise<void> => this.toggle(),
      (): boolean => this.paused || this.engine?.isPaused() === true, (): Promise<void> => this.stopForOther());
    ReaderTtsFloatingSession.configureControls(this.ownerId,
      (): void => { this.playChapter(this.host.chapterIndex() - 1); },
      (): void => { this.playChapter(this.host.chapterIndex() + 1); },
      (value: number): void => this.setSpeed(value),
      (minutes: number): void => this.setSleepTimer(minutes));
    ReaderTtsFloatingSession.configureCatalog(this.ownerId, titles, this.host.chapterIndex(),
      (index: number): void => { this.playChapter(index); });
    this.publishVoices();
    this.publishDetails();
  }

  /** 别的页面开始朗读或听书时先停掉这里，等媒体会话与后台许可释放完再返回。 */
  private async stopForOther(): Promise<void> {
    this.stop();
    if (this.media) await this.media.stopBackgroundRunning();
  }

  private publishVoices(): void {
    if (!ReaderTtsFloatingSession.isOwner(this.ownerId)) return;
    const picker = this.picker();
    ReaderTtsFloatingSession.configureTtsVoices(this.ownerId, picker.labels(), picker.selectedIndex(),
      (index: number): void => this.selectVoice(index));
  }

  private publishState(): void {
    ReaderTtsFloatingSession.update(this.ownerId, this.host.bookName() || '正在朗读', this.chapterTitle(), this.paused);
    this.publishDetails();
  }

  private chapterTitle(): string {
    const titles = this.host.chapterTitles();
    const index = this.host.chapterIndex();
    return titles[index] || `第${index + 1}章`;
  }

  private publishDetails(): void {
    if (!ReaderTtsFloatingSession.isOwner(this.ownerId)) return;
    const index = this.host.chapterIndex();
    const count = Math.max(1, this.host.chapterTitles().length);
    ReaderTtsFloatingSession.update(this.ownerId, this.host.bookName() || '正在朗读', this.chapterTitle(), this.paused);
    ReaderTtsFloatingSession.updateCatalogIndex(this.ownerId, index);
    const text = this.chapter === index ? this.text : '';
    const hasFocus = this.focusStart >= 0 && this.focusEnd > this.focusStart && this.focusEnd <= text.length;
    let before = '';
    let current = '';
    let after = '';
    if (hasFocus) {
      before = text.substring(Math.max(0, this.focusStart - 4000), this.focusStart);
      current = text.substring(this.focusStart, this.focusEnd);
      after = text.substring(this.focusEnd, Math.min(text.length, this.focusEnd + 6000));
    } else if (text) {
      after = text.substring(this.begin, Math.min(text.length, this.begin + 6000));
    }
    const inChapter = Math.max(0, Math.min(1, this.host.chapterProgress()));
    const progress = Math.max(0, Math.min(100, (Math.min(index, count - 1) + inChapter) / count * 100));
    ReaderTtsFloatingSession.updateDetails(this.ownerId, (before + current + after) || '正在准备朗读内容…',
      before, current, after, this.host.cover(), '', `${index + 1}/${count}章`, this.picker().speed,
      this.sleepMinutes, this.sleepRemaining, index > 0, index < count - 1, progress, inChapter * 100);
  }

  private mediaSession(): ReaderTtsMediaSession {
    if (!this.media) {
      this.media = new ReaderTtsMediaSession({
        abilityContext: (): common.UIAbilityContext => this.host.context(),
        isSpeaking: (): boolean => this.speaking || this.engine?.isSpeaking() === true,
        isPaused: (): boolean => this.paused || this.engine?.isPaused() === true,
        audioDebugState: (): string => this.engine ? this.engine.audioDebugState() : 'idle',
        mediaInfo: (): ReaderTtsMediaInfo => this.mediaInfo(),
        coverRaw: (): ResourceStr => this.host.coverRaw(),
        onPlay: (): void => {
          if (!this.speaking || this.paused) this.toggle();
        },
        onPause: (): void => {
          if (this.speaking && !this.paused) this.toggle();
        },
        onStop: (): void => this.stop(),
        onPlayNext: (): void => { this.playChapter(this.host.chapterIndex() + 1); },
        onPlayPrevious: (): void => { this.playChapter(this.host.chapterIndex() - 1); },
        onSetSpeed: (speed: number): void => this.setSpeed(speed),
        cacheTaskRunning: (): boolean => false,
        cacheHoldsBackground: (): boolean => false,
        handBackgroundToCache: (): void => {}
      });
    }
    return this.media;
  }

  private mediaInfo(): ReaderTtsMediaInfo {
    const index = this.host.chapterIndex();
    const count = this.host.chapterTitles().length;
    const fraction = Math.max(0, Math.min(1, this.host.chapterProgress()));
    const chars = Math.max(1, this.chapter === index ? this.text.length : 0);
    const duration = Math.max(60000, Math.round(chars / (260 * Math.max(this.picker().speed || 1, 0.5)) * 60000));
    const title = this.chapterTitle();
    const info: ReaderTtsMediaInfo = {
      bookUrl: this.host.bookUrl(),
      bookName: this.host.bookName(),
      author: this.host.author(),
      chapterIndex: index,
      chapterTitle: title,
      subtitle: this.host.positionLabel() ? `${title} · ${this.host.positionLabel()}` : title,
      pageIndex: 0,
      elapsedTime: Math.round(fraction * duration),
      duration: duration,
      canPlayPrevious: index > 0,
      canPlayNext: index < count - 1
    };
    return info;
  }
}
