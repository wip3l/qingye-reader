import fs from '@ohos.file.fs';
import { MimoAnalysis, MimoRole, MimoUnit, MimoPolicy, MIMO_VOICES } from '../../core/mimo/MimoPolicy';
import { MimoClient } from './MimoClient';
import { MimoBookCast, MimoStore } from './MimoStore';
import { TtsPcmAudioPlayer } from '../TtsPcmAudioPlayer';

export interface MimoReadingOptions {
  book: string;
  chapter: string;
  sourceOffset: number;
  speed: number;
  onFocus: (unit: MimoUnit, index: number) => void;
  onAudio: () => void;
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
    const names = fs.listFileSync(path);
    let total = 0;
    const files: string[] = names.filter((name: string): boolean => /^[a-f0-9]{64}\.(pcm|json)$/.test(name));
    files.sort((a: string, b: string): number => fs.statSync(path + '/' + a).mtime - fs.statSync(path + '/' + b).mtime);
    files.forEach((name: string): void => { total += fs.statSync(path + '/' + name).size; });
    for (const name of files) {
      if (total <= limit) break;
      const file = path + '/' + name;
      total -= fs.statSync(file).size;
      fs.unlinkSync(file);
    }
  }
  private async analyze(key: string, batch: MimoUnit[], book: string, context: string,
    generation: number): Promise<void> {
    const cast = MimoStore.cast(book);
    const directory = this.directory('mimo_analysis');
    const identity = cast.roles.map((role: MimoRole): string => role.id + ':' + role.name + ':' + role.aliases.join(',')).join('|');
    const cachePath = directory + '/' + MimoStore.hash('v1:mimo-v2.6-flash:' + MimoStore.load().namespace +
      identity + context + JSON.stringify(batch)) + '.json';
    let analysis: MimoAnalysis | null = null;
    try {
      analysis = JSON.parse(fs.readTextSync(cachePath)) as MimoAnalysis;
      MimoPolicy.validate(analysis, batch);
    } catch (_) { analysis = null; }
    if (!analysis) {
      AppStorage.setOrCreate('mimoReadingStatus', '正在识别人物…');
      try { analysis = await this.client.analyze(key, batch, cast.roles.slice(-100), context); }
      catch (error) { throw new Error('MIMO_ANALYSIS:' + (error as Error).message); }
      await this.ready(generation);
      MimoStore.write(cachePath, JSON.stringify(analysis));
      this.trimCache(directory, 4 * 1024 * 1024);
    }
    await this.ready(generation);
    // Reload after the network await so user voice changes are not overwritten.
    const latest = MimoStore.cast(book);
    let changed = false;
    for (const proposal of analysis.roles) {
      if (proposal.id === 'narrator' || latest.roles.some((role: MimoRole): boolean => role.id === proposal.id)) continue;
      if (latest.roles.length >= 200) continue;
      const role = new MimoRole();
      role.id = proposal.id;
      role.name = proposal.name;
      role.aliases = proposal.aliases;
      const voices = proposal.gender === 'female' ? ['茉莉', '冰糖'] : proposal.gender === 'male' ? ['苏打', '白桦'] : MIMO_VOICES;
      role.voice = voices[latest.roles.length % voices.length];
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
    if (changed) MimoStore.saveCast(book, latest);
  }

  static correctionKey(chapter: string, start: number, text: string): string {
    return MimoStore.hash(chapter + ':' + start + ':' + text);
  }
  static clearCache(): void {
    const base = AppStorage.get<string>('appCacheDir') || '';
    for (const name of ['mimo_audio', 'mimo_analysis']) {
      const directory = base + '/' + name;
      if (!fs.accessSync(directory)) continue;
      for (const entry of fs.listFileSync(directory)) {
        if (/^[a-f0-9]{64}\.(pcm|json)(\.tmp)?$/.test(entry)) {
          try { fs.unlinkSync(directory + '/' + entry); } catch (_) {}
        }
      }
    }
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
      let analyzed = 0;
      let firstAudio = true;
      const pendingPlayback: Promise<void>[] = [];
      const audioDir = this.directory('mimo_audio');
      const preview = options.book === 'preview';
      if (!preview) AppStorage.setOrCreate('mimoReadingBook', options.book);
      AppStorage.setOrCreate('mimoReadingActive', true);
      for (let index = 0; index < units.length; index++) {
        await this.ready(generation);
        if (pendingPlayback.length >= 2) await pendingPlayback.shift();
        await this.ready(generation);
        const settings = MimoStore.load();
        if (settings.multi && !preview && index >= analyzed) {
          const end = Math.min(units.length, index + (index === 0 ? 5 : 16));
          const batch = units.slice(index, end);
          await this.analyze(key, batch, options.book, text.slice(Math.max(0, units[index].start - 800), units[index].start), generation);
          analyzed = end;
        }
        const unit = units[index];
        if (!/[\p{L}\p{N}]/u.test(unit.text)) continue;
        const cast = MimoStore.cast(options.book);
        const correctionKey = MimoReadingSession.correctionKey(options.chapter, options.sourceOffset + unit.start, unit.text);
        const corrected = cast.corrections.find((item): boolean => item.key === correctionKey);
        const roleId = settings.multi && !preview ? (corrected?.roleId || unit.roleId) : 'narrator';
        const role = cast.roles.find((item: MimoRole): boolean => item.id === roleId) || cast.roles[0];
        const voice = settings.multi ? role.voice : settings.voice;
        const emotion = cast.emotion === '克制' ? '平静' : unit.emotion;
        const style = `单一说话人，保持音色稳定。${emotion}，${cast.emotion === '生动' ? '情绪鲜明' : '自然克制'}。` +
          `按通常朗读语速的 ${options.speed.toFixed(1)} 倍演绎`;
        const cachePath = audioDir + '/' + MimoStore.hash('pcm24-v1:' + settings.namespace + voice + style + unit.text) + '.pcm';
        let focused = false;
        let playback: Promise<void> = Promise.resolve();
        let playbackError: Error | null = null;
        let carry = new Uint8Array(0);
        const focus = (): void => {
          if (generation !== this.generation) return;
          if (firstAudio) { firstAudio = false; options.onAudio(); }
          AppStorage.setOrCreate('mimoCurrentRole', role.name + ' · ' + voice);
          if (!preview) {
            AppStorage.setOrCreate('mimoCurrentText', unit.text);
            AppStorage.setOrCreate('mimoCorrectionKey', correctionKey);
            AppStorage.setOrCreate('mimoCurrentRoleId', role.id);
          }
          AppStorage.setOrCreate('mimoReadingStatus', '');
          options.onFocus(unit, index);
        };
        const receive = async (buffer: ArrayBuffer): Promise<void> => {
          if (generation !== this.generation) throw new Error('MiMo 朗读已停止');
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
        let cached: ArrayBuffer | null = null;
        try {
          const size = fs.statSync(cachePath).size;
          if (size > 0 && size <= 4 * 1024 * 1024 && size % 2 === 0) {
            const file = fs.openSync(cachePath, fs.OpenMode.READ_ONLY);
            try { const data = new ArrayBuffer(size); if (fs.readSync(file.fd, data) === size) cached = data; }
            finally { fs.closeSync(file); }
          }
        } catch (_) {}
        if (cached) await receive(cached);
        else {
          const pcm = await this.client.synthesize(key, unit.text, voice, style, receive);
          await this.ready(generation);
          const file = fs.openSync(cachePath + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          try { fs.writeSync(file.fd, pcm); } finally { fs.closeSync(file); }
          fs.renameSync(cachePath + '.tmp', cachePath);
          this.trimCache(audioDir, 64 * 1024 * 1024);
        }
        if (carry.length) throw new Error('MiMo 音频采样不完整');
        if (playbackError) throw playbackError as Error;
        pendingPlayback.push(playback);
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
