import fs from '@ohos.file.fs';
import { HttpTTS } from '@legado/sourceengine';
import { PluginRegistry } from '@legado/pluginengine';
import { HttpTtsAudio } from '../../utils/HttpTtsReader';
import { TtsCustomVoices } from '../../utils/TtsVoiceModels';
import { PluginFeatureStore } from '../../utils/PluginFeatureStore';

const PLUGIN_TTS_URL_PREFIX: string = TtsCustomVoices.PLUGIN_URL_PREFIX;
/** MP3/WAV 结果写成临时文件交给播放器；只留最近这么多个，旧的删掉。 */
const MAX_CACHED_FILES: number = 40;

function normalizeTtsFormat(raw: Object | null | undefined): 'pcm16le' | 'wav' | 'mp3' | '' {
  if (typeof raw !== 'string') return '';
  const clean = raw.trim().toLowerCase();
  if (clean === 'pcm16le' || clean === 'pcm' || clean === 'audio/pcm' || clean === 'audio/l16') {
    return 'pcm16le';
  }
  if (clean === 'wav' || clean === 'audio/wav' || clean === 'audio/x-wav') {
    return 'wav';
  }
  if (clean === 'mp3' || clean === 'audio/mpeg' || clean === 'audio/mp3') {
    return 'mp3';
  }
  return '';
}

/**
 * 插件音色的合成：调用插件声明的 handler，PCM 直接交给播放器，MP3/WAV 写成临时文件；原速音频由播放器变速。
 * 由 HttpTtsReader 在用到插件音色时按需加载。音色列表见 PluginTtsVoices。
 */
export class PluginTtsBridge {
  static async synthesize(voice: HttpTTS, text: string, speed: number): Promise<HttpTtsAudio> {
    if (!PluginFeatureStore.enabled()) {
      throw new Error('插件功能已关闭，插件音色暂时不能使用');
    }
    await PluginRegistry.getInstance().ensureInitialized();
    const rest = voice.url.slice(PLUGIN_TTS_URL_PREFIX.length);
    const slash = rest.indexOf('/');
    if (slash <= 0) {
      throw new Error('无效的插件音色标识');
    }
    const pluginId = decodeURIComponent(rest.slice(0, slash));
    const voiceId = decodeURIComponent(rest.slice(slash + 1));

    const bound = PluginRegistry.getInstance()
      .getTtsProviders()
      .find((p) => p.plugin.manifest.id === pluginId);
    if (!bound) {
      throw new Error('朗读音色所属插件未启用');
    }
    const voiceSpec = bound.contribution.voices.find((v) => v.id === voiceId);

    const res = await PluginRegistry.getInstance().invokePlugin<Record<string, Object | null>>(
      pluginId,
      bound.contribution.handler,
      {
        voiceId,
        text,
        speed
      },
      { cpuTimeoutMs: 6000, wallTimeoutMs: 45000 }
    );

    const audioBytes = res.bytes;
    if (!audioBytes || audioBytes.byteLength === 0) {
      throw new Error('朗读插件未返回音频字节数据');
    }

    const out = new HttpTtsAudio();
    out.speed = speed;
    out.playerSpeed = true;

    const fmt = normalizeTtsFormat(res.data?.['outputFormat'])
      || normalizeTtsFormat(res.data?.['mimeType'])
      || voiceSpec?.outputFormat
      || bound.contribution.outputFormat;
    if (fmt === 'pcm16le') {
      const sampleRate = typeof res.data?.['sampleRate'] === 'number'
        ? Number(res.data['sampleRate'])
        : (voiceSpec?.sampleRate || bound.contribution.sampleRate || 24000);
      const copy = audioBytes.buffer.slice(
        audioBytes.byteOffset,
        audioBytes.byteOffset + audioBytes.byteLength
      ) as ArrayBuffer;
      out.pcm = copy;
      out.sampleRate = sampleRate;
      out.contentType = 'audio/pcm';
      return out;
    }

    const cacheRoot = AppStorage.get<string>('appCacheDir') || '';
    if (!cacheRoot) {
      throw new Error('音频缓存目录不可用');
    }
    const dir = `${cacheRoot}/plugin_tts`;
    try {
      if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
    } catch (_) {}
    const ext = fmt === 'wav' ? 'wav' : 'mp3';
    const filePath = `${dir}/ptts_${Date.now()}_${Math.floor(Math.random() * 100000)}.${ext}`;
    PluginTtsBridge.pruneCache(dir);
    const fd = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    try {
      const slice = audioBytes.buffer.slice(
        audioBytes.byteOffset,
        audioBytes.byteOffset + audioBytes.byteLength
      );
      fs.writeSync(fd.fd, slice);
    } finally {
      fs.closeSync(fd);
    }
    out.filePath = filePath;
    out.contentType = fmt === 'wav' ? 'audio/wav' : 'audio/mpeg';
    return out;
  }

  /** 文件名带写入时间，按名字排序就是新旧顺序；正在播的总是最新的几个，不会被删到。 */
  private static pruneCache(dir: string): void {
    try {
      const names = fs.listFileSync(dir).filter((name: string): boolean => name.startsWith('ptts_')).sort();
      const excess = names.length - (MAX_CACHED_FILES - 1);
      for (let i = 0; i < excess; i++) {
        try {
          fs.unlinkSync(`${dir}/${names[i]}`);
        } catch (_) {
        }
      }
    } catch (_) {
    }
  }
}
