import fs from '@ohos.file.fs';
import { MimoAnalysis, MimoRole, MimoUnit, MimoPolicy, MIMO_VOICES } from '../../core/mimo/MimoPolicy';
import { MimoAnalysisTarget, MimoClient } from './MimoClient';
import { TtsAudioDecodeTask } from '../../core/concurrency/TtsAudioDecodeTask';
import { MimoBookCast, MimoStore } from './MimoStore';
import { MimoVoicePolicy, MimoVoicePreset, MIMO_AGES, MIMO_GENDERS } from '../../core/mimo/MimoVoicePolicy';
import { TtsPcmAudioPlayer } from '../TtsPcmAudioPlayer';
import { CastVoicePolicy, CastVoiceRef } from '../../core/mimo/CastVoicePolicy';
import { CastVoiceStore } from './CastVoiceStore';
import { HttpTtsAudio, HttpTtsReader } from '../HttpTtsReader';
import { LocalTtsEngine } from '../localtts/LocalTtsEngine';
import { PcmTimeStretch } from '../PcmTimeStretch';

export interface MimoReadingOptions {
  book: string;
  /** Book title recorded in the cast so the cast list can show it. */
  bookName?: string;
  chapter: string;
  sourceOffset: number;
  speed: number;
  onFocus: (unit: MimoUnit, index: number) => void;
  onAudio: () => void;
  /** 多角色朗读：人物识别照旧，但每个人物用离线音色或自定义音色发声（见 CastVoiceStore），不走 MiMo 合成。 */
  cast?: boolean;
  /** 朗读设置里的倍速，给离线音色和自定义音色用。 */
  voiceSpeed?: number;
  /** 把原文片段整理成适合送去合成的文本（去注释编号、装饰符号等）；返回空串表示这段不用读。 */
  speakText?: (text: string) => string;
}

/** 这个自定义音色返回的是压缩音频（MP3），没法和其他音色拼进同一路 PCM。 */
class CastUnsupportedVoiceError extends Error {}

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
  /** 多角色朗读时这段用的离线/自定义音色。 */
  ref: CastVoiceRef = new CastVoiceRef();
}

export class MimoReadingSession {
  private client: MimoClient = new MimoClient();
  private player: TtsPcmAudioPlayer = new TtsPcmAudioPlayer();
  private generation: number = 0;
  private paused: boolean = false;
  private resumeWaiters: (() => void)[] = [];
  private active: boolean = false;
  private static readonly CAST_SAMPLE_RATE: number = 24000;
  private http: HttpTtsReader | null = null;
  private castPending: Map<string, Promise<ArrayBuffer>> = new Map<string, Promise<ArrayBuffer>>();
  private castActive: boolean = false;
  /** 离线引擎一次只加载一个模型，换模型会作废还在排队的请求，所以离线合成一条一条来。 */
  private localTail: Promise<void> = Promise.resolve();
  /** 每个音色说话部分的平均响度（进程内累计），用来把不同音色拉到差不多一样响。 */
  private static levels: Map<string, number> = new Map<string, number>();
  /** 离线音色最多提前合成这么多段：够把同一个模型的片段排到一起，又不会占太多内存。 */
  private static readonly CAST_LOCAL_AHEAD: number = 8;

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
    this.http?.stop();
    if (this.castActive) { this.castActive = false; LocalTtsEngine.cancelAll(); }
    this.castPending.clear();
    this.resumeWaiters.splice(0).forEach((resolve: () => void): void => resolve());
  }
  release(): void { this.stop(); this.player.release(); this.http?.release(); this.http = null; }

  /** 合成一段并统一成 24 kHz 的 PCM；同一段只合成一次，提前合成和正式播放共用结果。 */
  private castAudio(ref: CastVoiceRef, text: string, speed: number, generation: number): Promise<ArrayBuffer> {
    const key = CastVoicePolicy.key(ref) + '|' + speed + '|' + text;
    let task = this.castPending.get(key);
    if (!task) {
      const created = this.castSynthesize(ref, text, speed, generation);
      created.catch((): void => { if (this.castPending.get(key) === created) this.castPending.delete(key); });
      this.castPending.set(key, created);
      task = created;
    }
    return task;
  }
  private async castSynthesize(ref: CastVoiceRef, text: string, speed: number, generation: number): Promise<ArrayBuffer> {
    let audio: HttpTtsAudio;
    const startedAt = Date.now();
    let decoded = false;
    if (ref.kind === 'local') {
      const model = CastVoiceStore.localModel(ref);
      if (!model) throw new Error(`离线音色“${ref.name}”已不可用，请到音色方案里重新选择`);
      const run = this.localTail.then((): Promise<HttpTtsAudio> => {
        if (generation !== this.generation) throw new Error('MiMo 朗读已停止');
        return LocalTtsEngine.synthesize(model, text, speed);
      });
      this.localTail = run.then((): void => {}, (): void => {});
      audio = await run;
    } else {
      const voice = CastVoiceStore.customVoice(ref);
      if (!voice) throw new Error(`自定义音色“${ref.name}”已不可用，请到音色方案里重新选择`);
      if (!this.http) this.http = new HttpTtsReader();
      audio = await this.http.synthesize(voice, text, speed);
      if (audio.filePath) {
        // 接口返回的是 MP3 之类的压缩音频：解成 PCM 才能和别的音色接在同一路输出里。
        try {
          audio.pcm = await TtsAudioDecodeTask.decode(audio.filePath, MimoReadingSession.CAST_SAMPLE_RATE);
          audio.sampleRate = MimoReadingSession.CAST_SAMPLE_RATE;
          decoded = true;
        } catch (error) {
          console.warn('[TTS] cast voice decode failed:', (error as Error).message);
          audio.pcm = new ArrayBuffer(0);
        } finally { this.http.discardAudio(audio); }
        if (generation !== this.generation) throw new Error('MiMo 朗读已停止');
        if (audio.pcm.byteLength < 2) {
          CastVoiceStore.markUnsupported(CastVoicePolicy.key(ref));
          throw new CastUnsupportedVoiceError(`自定义音色“${ref.name}”返回的音频无法解码，暂时不能用于多角色朗读`);
        }
      }
    }
    if (generation !== this.generation) throw new Error('MiMo 朗读已停止');
    let pcm = audio.pcm;
    // 接口不带倍速变量的自定义音色本来由播放器变速；这里几个音色共用一路输出，改成先在本地变速。
    if (audio.playerSpeed && Math.abs((audio.speed || 1) - 1) >= 0.001) {
      pcm = PcmTimeStretch.stretch16BitMono(pcm, audio.sampleRate, audio.speed);
    }
    if (pcm.byteLength < 2) throw new Error(`音色“${ref.name}”没有返回音频`);
    pcm = CastVoicePolicy.resample(pcm, audio.sampleRate, MimoReadingSession.CAST_SAMPLE_RATE);
    // 响度校准：按这个音色累计的平均响度定增益，而不是每段各算各的，免得同一个人的轻声和大声被抹平。
    const voiceKey = CastVoicePolicy.key(ref);
    const level = CastVoicePolicy.level(pcm, MimoReadingSession.CAST_SAMPLE_RATE);
    if (level > 0) {
      const known = MimoReadingSession.levels.get(voiceKey);
      MimoReadingSession.levels.set(voiceKey, known ? known * 0.8 + level * 0.2 : level);
    }
    const gain = CastVoicePolicy.gain(MimoReadingSession.levels.get(voiceKey) || 0, CastVoicePolicy.peak(pcm));
    // 每段一行，真机上对照听感用：哪个音色、合成花了多久、原始采样率、是否经过解码、响度与增益。
    console.info(`[TTS] cast segment: voice=${voiceKey},chars=${text.length},ms=${Date.now() - startedAt},` +
      `rate=${audio.sampleRate},decoded=${decoded},level=${Math.round(level)},gain=${gain.toFixed(2)},` +
      `audioMs=${Math.round(pcm.byteLength / 2 / MimoReadingSession.CAST_SAMPLE_RATE * 1000)}`);
    return CastVoicePolicy.amplify(pcm, gain);
  }
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
    generation: number, target?: MimoAnalysisTarget): Promise<void> {
    const cast = MimoStore.cast(book);
    const directory = this.directory('mimo_analysis');
    // 结果按“这本书的这份人物档案 + 这段原文”存：重读同一段不再请求模型，也不再消耗用量；
    // 清除人物档案后 epoch 变了，旧结果自然作废。
    const cachePath = directory + '/' + MimoStore.hash('age-v3:' +
      (target ? target.url + '|' + target.model : 'mimo-v2.6-flash:' + MimoStore.load().namespace) + '|' +
      book + '|' + (cast.epoch || 0) + '|' + context + JSON.stringify(batch)) + '.json';
    let analysis: MimoAnalysis | null = null;
    try {
      analysis = JSON.parse(fs.readTextSync(cachePath)) as MimoAnalysis;
      MimoPolicy.validate(analysis, batch);
    } catch (_) { analysis = null; }
    const analysisStartedAt = Date.now();
    const analysisCached = !!analysis;
    if (!analysis) {
      try { analysis = await this.client.analyze(key, batch, cast.roles.slice(-100), context, undefined, target); }
      catch (error) { throw new Error('MIMO_ANALYSIS:' + (error as Error).message); }
      await this.ready(generation);
      MimoStore.write(cachePath, JSON.stringify(analysis));
      this.trimCache(directory, 16 * 1024 * 1024);
    }
    console.info(`[TTS] role analysis: units=${batch[0].id}-${batch[batch.length - 1].id},cached=${analysisCached},` +
      `ms=${Date.now() - analysisStartedAt},newRoles=${analysis.roles.length}`);
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
    cast: MimoBookCast, multi: boolean, configuredPreset: MimoVoicePreset, namespace: string, audioDir: string,
    castOn: boolean = false): MimoSegment {
    const defaultPreset = multi || cast.roles[0].manual === true ?
      MimoVoicePolicy.rolePreset(cast.roles[0]) : configuredPreset;
    const roleOf = (unit: MimoUnit, key: string): MimoRole => {
      const corrected = multi ? cast.corrections.find((item): boolean => item.key === key) : undefined;
      const roleId = multi ? (corrected?.roleId || unit.roleId) : 'narrator';
      return cast.roles.find((item: MimoRole): boolean => item.id === roleId) || cast.roles[0];
    };
    const styleOf = (unit: MimoUnit): string => {
      if (castOn) return '';
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
    if (castOn) {
      // 人物的音色在进入这里之前已经分配并保存过（见 read 里的循环），这里只取结果。
      segment.ref = CastVoiceStore.voiceFor(segment.role, cast).ref;
      segment.voice = CastVoicePolicy.key(segment.ref);
      segment.presetName = segment.ref.name;
      return segment;
    }
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
      const preview = options.book === 'preview';
      const castOn = options.cast === true && !preview;
      // 多角色朗读可以改用别家兼容接口识别人物；MiMo 朗读本身仍只用 MiMo 的密钥。
      let target: MimoAnalysisTarget | undefined = undefined;
      if (castOn && CastVoiceStore.usesCustomAnalysis()) {
        target = new MimoAnalysisTarget();
        target.url = CastVoiceStore.analysis().url; target.model = CastVoiceStore.analysis().model;
      }
      const key = target ? await CastVoiceStore.analysisKey() : await MimoStore.key();
      await this.ready(generation);
      if (!key) {
        throw new Error(target ? '还没有保存分析模型的 API Key，请到“多角色朗读 › 分析模型”里重新填写并测试' :
          (castOn ? '多角色朗读靠分析模型识别人物，请先在“多角色朗读 › 分析模型”里配置' : '请先在朗读设置中配置 MiMo API Key'));
      }
      this.castActive = castOn;
      if (castOn) {
        // 先把人物档案落盘（记下 epoch），识别结果才有稳定的缓存键。
        const opening = MimoStore.cast(options.book);
        if (!opening.epoch) MimoStore.saveCast(options.book, opening, options.bookName || '');
      }
      const castSpeed = Math.max(0.5, Math.min(3, options.voiceSpeed || 1));
      const speak = (value: string): string => options.speakText ? options.speakText(value) : value;
      const units = MimoPolicy.split(text);
      let firstAudio = true;
      const pendingPlayback: Promise<void>[] = [];
      const audioDir = this.directory('mimo_audio');
      // Read the library once per settings revision, rather than synchronously per sentence.
      let voiceLibrary = MimoStore.library();
      let voiceRevision = MimoStore.voiceRevision;
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
          const created = this.analyze(key, batch, options.book, options.bookName || '', context, generation, target)
            .then((): void => {
              analyzed.add(start);
              // 多角色朗读：一批识别完接着识别下一批，直到本章结束。后面的片段早早知道是谁说的，
              // 才能把同一个离线模型的片段排在一起合成；每批都要用到上一批新认出的人物，所以一批一批来。
              const following = MimoPolicy.batchEnd(start, units.length);
              if (castOn && following < units.length && generation === this.generation) startAnalysis(following);
            });
          // 后台识别失败不留在表里：真读到这一批时重新请求一次，而不是报一个早就过时的错误。
          created.catch((): void => { if (analyses.get(start) === created) analyses.delete(start); });
          analyses.set(start, created);
          task = created;
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
        if (pendingPlayback.length > 0) {
          await Promise.all(pendingPlayback.splice(0));
          // MiMo 是边合成边播，要等上一段放完再开下一段。多角色朗读的下一段通常已经合成好了：
          // 上一段的数据一被输出取走就接着写，不等它放完——否则每段之间会多出约 0.4 秒的空白
          //（等放完 + 输出重新起步），短对白听起来一顿一顿的。高亮仍按实际播放到的位置触发。
          if (!castOn) await this.player.waitForSegmentEnd();
        }
        await this.ready(generation);
        const settings = MimoStore.load();
        const multi = castOn || (settings.multi && !preview);
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
        if (castOn) {
          const blocker = CastVoiceStore.blocker(cast);
          if (blocker) throw new Error(blocker);
          // 配角第一次出场时从方案的配角组里取一个音色并记进档案，之后各章都用它。
          let assigned = false;
          for (const role of cast.roles) {
            if (CastVoiceStore.voiceFor(role, cast).changed) assigned = true;
          }
          if (assigned) MimoStore.saveCast(options.book, cast, options.bookName || '');
        }
        const revision = MimoStore.voiceRevision;
        const segment = this.segment(units, index, limit, options, cast, multi, voiceLibrary.defaultPreset, settings.namespace, audioDir, castOn);
        const spoken = castOn ? speak(segment.unit.text) : segment.unit.text;
        if (castOn && !/[\p{L}\p{N}]/u.test(spoken)) { index = segment.last + 1; continue; }
        let ahead = segment.last + 1;
        if (castOn) {
          // 提前合成：自定义音色只提前两段（走网络，不多占接口）；离线音色最多提前 CAST_LOCAL_AHEAD 段，
          // 并按模型排在一起——离线引擎一次只加载一个模型，旁白和人物用了不同模型时不必每句都重新加载。
          const queueRefs: CastVoiceRef[] = [segment.ref];
          const queueTexts: string[] = [spoken];
          for (let count = 0; count < MimoReadingSession.CAST_LOCAL_AHEAD && ahead < limit; count++) {
            while (ahead < limit && !/[\p{L}\p{N}]/u.test(units[ahead].text)) ahead++;
            if (ahead >= limit) break;
            const upcoming = this.segment(units, ahead, limit, options, cast, multi, voiceLibrary.defaultPreset, settings.namespace, audioDir, castOn);
            queueRefs.push(upcoming.ref);
            queueTexts.push(speak(upcoming.unit.text));
            ahead = upcoming.last + 1;
          }
          // 失败的这次不留在缓存里，轮到它时会再合成一次并把错误报出来。
          const submit = (position: number): void => {
            if (!/[\p{L}\p{N}]/u.test(queueTexts[position]) || !CastVoicePolicy.key(queueRefs[position])) return;
            this.castAudio(queueRefs[position], queueTexts[position], castSpeed, generation).catch((): void => {});
          };
          const groups = queueRefs.map((ref: CastVoiceRef): string => CastVoiceStore.modelGroup(ref));
          for (const position of CastVoicePolicy.synthesisOrder(groups)) submit(position);
          for (let position = 0; position < Math.min(3, queueRefs.length); position++) {
            if (!groups[position]) submit(position);
          }
        } else {
          for (let count = 0; count < 2 && ahead < limit; count++) {
            while (ahead < limit && !/[\p{L}\p{N}]/u.test(units[ahead].text)) ahead++;
            if (ahead >= limit) break;
            const upcoming = this.segment(units, ahead, limit, options, cast, multi, voiceLibrary.defaultPreset, settings.namespace, audioDir, castOn);
            prefetch(upcoming);
            ahead = upcoming.last + 1;
          }
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
        if (castOn) {
          let pcm: ArrayBuffer;
          try { pcm = await this.castAudio(segment.ref, spoken, castSpeed, generation); } catch (error) {
            await this.ready(generation);
            // 这个音色已被记为不可用：重新走一遍分配，改由方案里别的音色（或旁白）来读这一段。
            if (error instanceof CastUnsupportedVoiceError) continue;
            throw error as Error;
          }
          await this.ready(generation);
          // 合成期间人物档案变过（后台又认出了新人物、换了音色、纠正了说话人）：这段按新的档案重新走一遍。
          // 合成好的音频还留在 castPending 里，音色没变的话下一轮直接拿来用，不会再合成一次。
          if (revision !== MimoStore.voiceRevision) continue;
          this.castPending.delete(CastVoicePolicy.key(segment.ref) + '|' + castSpeed + '|' + spoken);
          await receive(pcm);
          if (playbackError) throw playbackError as Error;
          pendingPlayback.push(playback);
          index = segment.last + 1;
          continue;
        }
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
