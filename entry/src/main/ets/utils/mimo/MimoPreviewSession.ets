import fs from '@ohos.file.fs';
import { MimoVoicePreset, MimoVoicePolicy } from '../../core/mimo/MimoVoicePolicy';
import { MimoClient } from './MimoClient';
import { MimoStore } from './MimoStore';
import { TtsPcmAudioPlayer } from '../TtsPcmAudioPlayer';
import { ReaderTtsFloatingSession } from '../ReaderTtsFloatingSession';

/** Isolated short-text audition; never creates a cast or changes a book's reading progress. */
export class MimoPreviewSession {
  private client: MimoClient = new MimoClient();
  private player: TtsPcmAudioPlayer = new TtsPcmAudioPlayer();
  private generation: number = 0;
  stop(): void { this.generation++; this.client.stop(); this.player.stop(); }
  release(): void { this.stop(); this.player.release(); }
  async play(preset: MimoVoicePreset, text: string, original: boolean = false): Promise<void> {
    this.stop();
    const generation = this.generation;
    if (!text.trim() || text.length > 300) throw new Error('请输入 1～300 字的试听文字');
    const snapshot = MimoVoicePolicy.clone(preset);
    if (original) snapshot.prompt = '';
    const style = MimoVoicePolicy.prompt(snapshot, '平静', '自然', 1);
    const cancel = (): void => { if (generation === this.generation) this.stop(); };
    MimoStore.onCredentialsChanged.push(cancel);
    try {
      await ReaderTtsFloatingSession.stop();
      const key = await MimoStore.key();
      if (generation !== this.generation) return;
      if (!key) throw new Error('请先配置 MiMo API Key');
      const dir = (AppStorage.get<string>('appCacheDir') || '') + '/mimo_preview';
      if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
      const path = dir + '/' + MimoStore.hash('pcm24-preview-v1:' + MimoStore.load().namespace + snapshot.voice + style + text) + '.pcm';
      let pcm: ArrayBuffer | null = null;
      try {
        const size = fs.statSync(path).size;
        if (size > 0 && size <= 4 * 1024 * 1024 && size % 2 === 0) {
          pcm = new ArrayBuffer(size); const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
          try { if (fs.readSync(file.fd, pcm) !== size) pcm = null; } finally { fs.closeSync(file); }
        }
      } catch (_) {}
      if (!pcm) {
        pcm = await this.client.synthesize(key, text, snapshot.voice, style, async (_data: ArrayBuffer): Promise<void> => {});
        if (generation !== this.generation) return;
        // Short auditions are bounded separately and can be cleared with the ordinary MiMo cache.
        const names = fs.listFileSync(dir).filter((name: string): boolean => /^[a-f0-9]{64}\.pcm$/.test(name));
        // Keep both sides of repeated A/B comparisons; eight bounded clips use at most 32 MiB.
        for (let i = 0; i < names.length - 7; i++) {
          try { fs.unlinkSync(dir + '/' + names[i]); } catch (_) {}
        }
        const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try { fs.writeSync(file.fd, pcm); } finally { fs.closeSync(file); }
      }
      if (generation !== this.generation) return;
      await this.player.play(pcm, 24000);
    } finally {
      MimoStore.onCredentialsChanged = MimoStore.onCredentialsChanged.filter((f: () => void): boolean => f !== cancel);
      if (generation === this.generation) this.player.stop();
    }
  }
}
