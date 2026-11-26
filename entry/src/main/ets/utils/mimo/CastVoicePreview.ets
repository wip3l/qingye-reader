import { CastVoiceRef } from '../../core/mimo/CastVoicePolicy';
import { HttpTtsReader } from '../HttpTtsReader';
import { LocalTtsEngine } from '../localtts/LocalTtsEngine';
import { ReaderTtsFloatingSession } from '../ReaderTtsFloatingSession';
import { CastVoiceStore } from './CastVoiceStore';

/** 多角色朗读各页面里的试听：用选中的离线音色或自定义音色读一句固定的话。 */
export class CastVoicePreview {
  static readonly SAMPLE: string = '雨停了，我们一起出发吧。';
  private reader: HttpTtsReader = new HttpTtsReader();
  private serial: number = 0;

  /** 读完或被打断后返回；失败时抛出可以直接显示的错误。 */
  async play(ref: CastVoiceRef): Promise<void> {
    this.stop();
    const serial = this.serial;
    ReaderTtsFloatingSession.stop();
    if (ref.kind === 'local') {
      const model = CastVoiceStore.localModel(ref);
      if (!model) throw new Error('这个离线音色已不可用');
      const audio = await LocalTtsEngine.synthesize(model, CastVoicePreview.SAMPLE, 1);
      if (serial !== this.serial) return;
      await this.reader.writeAudio(audio);
      await this.reader.drain();
      return;
    }
    const voice = CastVoiceStore.customVoice(ref);
    if (!voice) throw new Error('这个自定义音色已不可用');
    await this.reader.play(voice, CastVoicePreview.SAMPLE, 1);
  }

  stop(): void {
    this.serial++;
    this.reader.stop();
    LocalTtsEngine.cancelAll();
  }

  release(): void {
    this.stop();
    this.reader.release();
  }

  /** 被 stop 打断时两种合成各自抛出的“已取消”，界面不用提示。 */
  static interrupted(error: Error): boolean {
    return LocalTtsEngine.isCancelled(error) || error?.name === 'HttpTtsCancelledError' ||
      (error?.message || '').includes('已停止') || (error?.message || '').includes('已取消');
  }
}
