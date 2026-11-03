import fs from '@ohos.file.fs';
import { MimoAnalysis, MimoRole, MimoUnit, MimoPolicy, MIMO_VOICES } from '../../core/mimo/MimoPolicy';
import { MimoClient } from './MimoClient';
import { MimoBookCast, MimoStore } from './MimoStore';
import { MimoVoicePolicy, MimoVoicePreset, MIMO_AGES, MIMO_GENDERS } from '../../core/mimo/MimoVoicePolicy';
import { TtsPcmAudioPlayer } from '../TtsPcmAudioPlayer';

export interface MimoReadingOptions {
  book: string;
  /** Book title recorded in the cast so the cast list can show it. */
  bookName?: string;
  chapter: string;
  sourceOffset: number;
  speed: number;
  onFocus: (unit: MimoUnit, index: number) => void;
  onAudio: () => void;
}

class MimoCacheFile {
  path: string;
  size: number;
  mtime: number;
  constructor(path: string, size: number, mtime: number) { this.path = path; this.size = size; this.mtime = mtime; }
}

/** One synthesis request: a unit, or short neighbours with the same role, voice and style merged together. */
class MimoSegment {
  first: number = 0;
  last: number = 0;
  unit: MimoUnit = new MimoUnit();
  /** Correction keys of every merged unit; a correction applies to all of them. */
  keys: string[] = [];
  role: MimoRole = new MimoRole();
  voice: string = '';
  presetName: string = '';
  style: string = '';
  cachePath: string = '';
}

export class MimoReadingSession {
  private client: MimoClient = new MimoClient();
  private player: TtsPcmAudioPlayer = new TtsPcmAudioPlayer();
  private generation: number = 0;
  private paused: boolean = false;
  private resumeWaiters: (() => void)[] = [];
  private active: boolean = false;

  stop(): void {
    if (this.active) {
      AppStorage.setOrCreate('mimoReadingActive', false);
      AppStorage.setOrCreate('mimoReadingStatus', '');
    }
    this.generation++;
    this.active = false;
    this.paused = false;
    this.client.stop();
    this.player.stop();
    this.resumeWaiters.splice(0).forEach((resolve: () => void): void => resolve());
  }
  release(): void { this.stop(); this.player.release(); }
  async pause(): Promise<void> { this.paused = true; await this.player.pause(); }
  async resume(): Promise<void> {
    this.paused = false;
    await this.player.resume();
    this.resumeWaiters.splice(0).forEach((resolve: () => void): void => resolve());
  }
  private async ready(generation: number): Promise<void> {
    if (this.paused) await new Promise<void>((resolve) => { this.resumeWaiters.push(resolve); });
    if (generation !== this.generation) throw new Error('MiMo 朗读已停止');
  }
  private directory(name: string): string {
    const path = (AppStorage.get<string>('appCacheDir') || '') + '/' + name;
    if (!fs.accessSync(path)) fs.mkdirSync(path, true);
    return path;
  }
  private trimCache(path: string, limit: number): void {
    let total = 0;
    // Stat each file once; sorting with statSync in the comparator costs O(n log n) disk calls.
    const files: MimoCacheFile[] = [];
    for (const name of fs.listFileSync(path)) {
      if (!/^[a-f0-9]{64}\.(pcm|json)$/.test(name)) continue;
      try {
        const stat = fs.statSync(path + '/' + name);
        files.push(new MimoCacheFile(path + '/' + name, stat.size, stat.mtime));
        total += stat.size;
      } catch (_) {}
    }
    if (total <= limit) return;
    files.sort((a: MimoCacheFile, b: MimoCacheFile): number => a.mtime - b.mtime);
    for (const file of files) {
      if (total <= limit) break;
      try { fs.unlinkSync(file.path); total -= file.size; } catch (_) {}
    }
  }
  private hasAudio(path: string): boolean {
    try { return fs.statSync(path).size > 0; } catch (_) { return false; }
  }
  private readAudio(path: string): ArrayBuffer | null {
    try {
      const size = fs.statSync(path).size;
      if (size <= 0 || size > 4 * 1024 * 1024 || size % 2 !== 0) return null;
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try { const data = new ArrayBuffer(size); return fs.readSync(file.fd, data) === size ? data : null; }
      finally { fs.closeSync(file); }
    } catch (_) { return null; }
  }
  private writeAudio(path: string, pcm: ArrayBuffer, directory: string): void {
    const file = fs.openSync(path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, pcm); } finally { fs.closeSync(file); }
    fs.renameSync(path + '.tmp', path);
    this.trimCache(directory, 64 * 1024 * 1024);
  }
  private async analyze(key: string, batch: MimoUnit[], book: string, bookName: string, context: string,
    generation: number): Promise<void> {
    const cast = MimoStore.cast(book);
    const directory = this.directory('mimo_analysis');
    const identity = cast.roles.map((role: MimoRole): string => role.id + ':' + role.name + ':' + role.aliases.join(',')).join('|');
    const cachePath = directory + '/' + MimoStore.hash('age-v2:mimo-v2.6-flash:' + MimoStore.load().namespace +
      identity + context + JSON.stringify(batch)) + '.json';
    let analysis: MimoAnalysis | null = null;
    try {
      analysis = JSON.parse(fs.readTextSync(cachePath)) as MimoAnalysis;
      MimoPolicy.validate(analysis, batch);
    } catch (_) { analysis = null; }
    if (!analysis) {
      try { analysis = await this.client.analyze(key, batch, cast.roles.slice(-100), context); }
      catch (error) { throw new Error('MIMO_ANALYSIS:' + (error as Error).message); }
      await this.ready(generation);
      MimoStore.write(cachePath, JSON.stringify(analysis));
      this.trimCache(directory, 4 * 1024 * 1024);
    }
    await this.ready(generation);
    // Reload after the network await so user voice changes are not overwritten.
    const latest = MimoStore.cast(book);
    const library = MimoStore.library();
    let changed = false;
    for (const proposal of analysis.roles) {
      if (proposal.id === 'narrator' || latest.roles.some((role: MimoRole): boolean => role.id === proposal.id)) continue;
      if (latest.roles.length >= 200) continue;
      const role = new MimoRole();
      role.id = proposal.id;
      role.name = proposal.name;
      role.aliases = proposal.aliases;
      role.gender = MIMO_GENDERS.includes(proposal.gender) ? proposal.gender : 'unknown';
      const evidence = typeof proposal.ageEvidence === 'string' ? proposal.ageEvidence.trim() : '';
      const source = context + batch.map((unit: MimoUnit): string => unit.text).join('');
      if (MIMO_AGES.includes(proposal.age) && proposal.age !== 'unknown' &&
        Number.isFinite(proposal.ageConfidence) && proposal.ageConfidence >= 0.8 && proposal.ageConfidence <= 1 &&
        evidence.length > 0 && evidence.length <= 120 && source.includes(evidence)) {
        role.age = proposal.age; role.ageEvidence = evidence;
      }
      MimoStore.assign(role, latest, library);
      latest.roles.push(role);
      changed = true;
    }
    for (const unit of batch) {
      const item = analysis.assignments.find((assignment): boolean => assignment.unitId === unit.id);
      if (!item) throw new Error('角色标注不完整');
      const known = latest.roles.some((role: MimoRole): boolean => role.id === item.roleId);
      unit.uncertain = !known || item.confidence < 0.7;
      unit.roleId = unit.uncertain ? 'narrator' : item.roleId;
      unit.emotion = MimoPolicy.emotion(item.emotion);
    }
    if (changed) MimoStore.saveCast(book, latest, bookName);
  }

  static correctionKey(chapter: string, start: number, text: string): string {
    return MimoStore.hash(chapter + ':' + start + ':' + text);
  }
  static clearCache(): void {
    const base = AppStorage.get<string>('appCacheDir') || '';
    for (const name of ['mimo_audio', 'mimo_analysis', 'mimo_preview']) {
      const directory = base + '/' + name;
      if (!fs.accessSync(directory)) continue;
      for (const entry of fs.listFileSync(directory)) {
        if (/^[a-f0-9]{64}\.(pcm|json)(\.tmp)?$/.test(entry)) {
          try { fs.unlinkSync(directory + '/' + entry); } catch (_) {}
        }
      }
    }
  }

  /** Builds the request starting at `index`, merging following units up to `limit` (exclusive). */
  private segment(units: MimoUnit[], index: number, limit: number, options: MimoReadingOptions,
    cast: MimoBookCast, multi: boolean, configuredPreset: MimoVoicePreset, namespace: string, audioDir: string): MimoSegment {
    const defaultPreset = multi || cast.roles[0].manual === true ?
      MimoVoicePolicy.rolePreset(cast.roles[0]) : configuredPreset;
    const roleOf = (unit: MimoUnit, key: string): MimoRole => {
      const corrected = multi ? cast.corrections.find((item): boolean => item.key === key) : undefined;
      const roleId = multi ? (corrected?.roleId || unit.roleId) : 'narrator';
      return cast.roles.find((item: MimoRole): boolean => item.id === roleId) || cast.roles[0];
    };
    const styleOf = (unit: MimoUnit): string => {
      const emotion = cast.emotion === '克制' ? '平静' : unit.emotion;
      const role = roleOf(unit, MimoReadingSession.correctionKey(options.chapter, options.sourceOffset + unit.start, unit.text));
      const preset = multi ? MimoVoicePolicy.rolePreset(role) : defaultPreset;
      return MimoVoicePolicy.prompt(preset, multi ? emotion : '平静', cast.emotion, options.speed);
    };
    const keyOf = (unit: MimoUnit): string =>
      MimoReadingSession.correctionKey(options.chapter, options.sourceOffset + unit.start, unit.text);
    const head = units[index];
    const segment = new MimoSegment();
    segment.first = index;
    segment.last = index;
    segment.keys = [keyOf(head)];
    segment.role = roleOf(head, segment.keys[0]);
    segment.voice = multi ? segment.role.voice : defaultPreset.voice;
    const spokenPreset = multi ? MimoVoicePolicy.rolePreset(segment.role) : defaultPreset;
    segment.presetName = spokenPreset.id ? spokenPreset.name : '';
    segment.style = styleOf(head);
    let text = head.text;
    for (let next = index + 1; next < limit; next++) {
      const unit = units[next];
      const key = keyOf(unit);
      if (roleOf(unit, key).id !== segment.role.id || styleOf(unit) !== segment.style ||
        !MimoPolicy.canMerge(text, unit.text)) break;
      text += unit.text;
      segment.keys.push(key);
      segment.last = next;
    }
    segment.unit.id = head.id;
    segment.unit.start = head.start;
    segment.unit.end = units[segment.last].end;
    segment.unit.text = text;
    segment.unit.roleId = segment.role.id;
    segment.unit.emotion = head.emotion;
    segment.cachePath = audioDir + '/' + MimoStore.hash('pcm24-voice-v2:mimo-v2.5-tts:' + namespace + segment.voice + segment.style + text) + '.pcm';
    return segment;
  }

  async read(text: string, options: MimoReadingOptions): Promise<void> {
    this.stop();
    const generation = this.generation;
    this.active = true;
    const cancel = (): void => this.stop();
    MimoStore.onCredentialsChanged.push(cancel);
    try {
      const key = await MimoStore.key();
      await this.ready(generation);
      if (!key) throw new Error('请先在朗读设置中配置 MiMo API Key');
      const units = MimoPolicy.split(text);
      let firstAudio = true;
      const pendingPlayback: Promise<void>[] = [];
      const audioDir = this.directory('mimo_audio');
      // Read the library once per settings revision, rather than synchronously per sentence.
      let voiceLibrary = MimoStore.library();
      let voiceRevision = MimoStore.voiceRevision;
      const preview = options.book === 'preview';
      if (!preview) AppStorage.setOrCreate('mimoReadingBook', options.book);
      AppStorage.setOrCreate('mimoReadingActive', true);

      // Role analysis runs one batch ahead of playback, so only the opening batch is waited for.
      const analyses: Map<number, Promise<void>> = new Map();
      const analyzed: Set<number> = new Set();
      const startAnalysis = (start: number): Promise<void> => {
        let task = analyses.get(start);
        if (!task) {
          const batch = units.slice(start, MimoPolicy.batchEnd(start, units.length));
          const context = text.slice(Math.max(0, units[start].start - 800), units[start].start);
          task = this.analyze(key, batch, options.book, options.bookName || '', context, generation)
            .then((): void => { analyzed.add(start); });
          task.catch((): void => {});
          analyses.set(start, task);
        }
        return task;
      };
      /** End of the contiguous analysed range that contains `index`. */
      const analyzedEnd = (index: number): number => {
        let end = MimoPolicy.batchEnd(MimoPolicy.batchStart(index), units.length);
        while (end < units.length && analyzed.has(end)) end = MimoPolicy.batchEnd(end, units.length);
        return end;
      };

      // Upcoming segments are synthesised into the audio cache one at a time while the current
      // one plays, which hides the request latency that caused gaps between sentences.
      const prefetches: Map<string, Promise<void>> = new Map();
      let prefetchTail: Promise<void> = Promise.resolve();
      const prefetch = (segment: MimoSegment): void => {
        if (prefetches.has(segment.cachePath) || this.hasAudio(segment.cachePath)) return;
        const revision = MimoStore.voiceRevision;
        const task = prefetchTail.then(async (): Promise<void> => {
          if (generation !== this.generation || revision !== MimoStore.voiceRevision) return;
          try {
            const pcm = await this.client.synthesize(key, segment.unit.text, segment.voice, segment.style,
              async (_pcm: ArrayBuffer): Promise<void> => {});
            if (generation === this.generation && revision === MimoStore.voiceRevision) this.writeAudio(segment.cachePath, pcm, audioDir);
          } catch (_) {
            // The segment is requested again, streaming, when its turn comes.
          }
        });
        prefetches.set(segment.cachePath, task);
        prefetchTail = task;
      };

      let index = 0;
      while (index < units.length) {
        await this.ready(generation);
        // Never queue a future segment in the renderer. Voice edits take effect at the next boundary.
        if (pendingPlayback.length > 0) { await Promise.all(pendingPlayback.splice(0)); await this.player.waitForSegmentEnd(); }
        await this.ready(generation);
        const settings = MimoStore.load();
        const multi = settings.multi && !preview;
        let limit = units.length;
        if (multi) {
          const start = MimoPolicy.batchStart(index);
          if (!analyzed.has(start)) {
            AppStorage.setOrCreate('mimoReadingStatus', '正在识别人物…');
            await startAnalysis(start);
            await this.ready(generation);
          }
          const next = MimoPolicy.batchEnd(start, units.length);
          if (next < units.length) startAnalysis(next);
          limit = analyzedEnd(index);
        }
        if (!/[\p{L}\p{N}]/u.test(units[index].text)) { index++; continue; }
        if (voiceRevision !== MimoStore.voiceRevision) {
          voiceLibrary = MimoStore.library(); voiceRevision = MimoStore.voiceRevision;
        }
        const cast = MimoStore.cast(options.book);
        const revision = MimoStore.voiceRevision;
        const segment = this.segment(units, index, limit, options, cast, multi, voiceLibrary.defaultPreset, settings.namespace, audioDir);
        let ahead = segment.last + 1;
        for (let count = 0; count < 2 && ahead < limit; count++) {
          while (ahead < limit && !/[\p{L}\p{N}]/u.test(units[ahead].text)) ahead++;
          if (ahead >= limit) break;
          const upcoming = this.segment(units, ahead, limit, options, cast, multi, voiceLibrary.defaultPreset, settings.namespace, audioDir);
          prefetch(upcoming);
          ahead = upcoming.last + 1;
        }

        let focused = false;
        let playback: Promise<void> = Promise.resolve();
        let playbackError: Error | null = null;
        let carry = new Uint8Array(0);
        const focus = (): void => {
          if (generation !== this.generation) return;
          if (firstAudio) { firstAudio = false; options.onAudio(); }
          AppStorage.setOrCreate('mimoCurrentRole', segment.role.name + ' · ' + (segment.presetName || segment.voice));
          if (!preview) {
            AppStorage.setOrCreate('mimoCurrentText', segment.unit.text);
            AppStorage.setOrCreate('mimoCorrectionKey', segment.keys.join(','));
            AppStorage.setOrCreate('mimoCurrentRoleId', segment.role.id);
          }
          AppStorage.setOrCreate('mimoReadingStatus', '');
          options.onFocus(segment.unit, segment.first);
        };
        const receive = async (buffer: ArrayBuffer): Promise<void> => {
          if (generation !== this.generation) throw new Error('MiMo 朗读已停止');
          if (!focused && revision !== MimoStore.voiceRevision) throw new Error('MiMo 声音配置已更新');
          if (playbackError) throw playbackError;
          const merged = new Uint8Array(carry.length + buffer.byteLength);
          merged.set(carry); merged.set(new Uint8Array(buffer), carry.length);
          const aligned = merged.length - merged.length % 2;
          carry = merged.slice(aligned);
          if (!aligned) return;
          const write = focused ? this.player.write(merged.buffer.slice(0, aligned), 24000) :
            this.player.writeSegment(merged.buffer.slice(0, aligned), 24000, focus);
          focused = true;
          playback = Promise.all([playback, write]).then((): void => {});
          playback.catch((error: Error): void => {
            playbackError = error;
            if (generation === this.generation) this.client.stop();
          });
        };
        AppStorage.setOrCreate('mimoReadingStatus', firstAudio ? '正在生成语音…' : '');
        // A request already under way for this segment beats starting a second one.
        const pending = prefetches.get(segment.cachePath);
        if (pending) { await pending; await this.ready(generation); }
        if (revision !== MimoStore.voiceRevision) continue;
        const cached = this.readAudio(segment.cachePath);
        if (cached) await receive(cached);
        else {
          try {
            const pcm = await this.client.synthesize(key, segment.unit.text, segment.voice, segment.style, receive);
            await this.ready(generation);
            this.writeAudio(segment.cachePath, pcm, audioDir);
          } catch (error) {
            // A settings edit before the first audible buffer must not play a stale request or skip text.
            if (!focused && generation === this.generation && revision !== MimoStore.voiceRevision) continue;
            throw error as Error;
          }
        }
        if (carry.length) throw new Error('MiMo 音频采样不完整');
        if (playbackError) throw playbackError as Error;
        pendingPlayback.push(playback);
        index = segment.last + 1;
      }
      await Promise.all(pendingPlayback);
      await this.player.drain();
      await this.ready(generation);
    } catch (error) {
      if (generation === this.generation) { this.client.stop(); this.player.stop(); }
      throw error as Error;
    } finally {
      MimoStore.onCredentialsChanged = MimoStore.onCredentialsChanged.filter((item: () => void): boolean => item !== cancel);
      if (generation === this.generation) {
        this.active = false;
        AppStorage.setOrCreate('mimoReadingStatus', '');
        AppStorage.setOrCreate('mimoReadingActive', false);
      }
    }
  }
}
