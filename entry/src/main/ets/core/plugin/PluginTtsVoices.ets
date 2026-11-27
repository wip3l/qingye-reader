import { HttpTTS } from '@legado/sourceengine';
import { PluginRegistry } from '@legado/pluginengine';
import { TtsCustomVoices } from '../../utils/TtsVoiceModels';
import { PluginFeatureStore } from '../../utils/PluginFeatureStore';

/** 插件音色的 id 由插件 ID 和音色 ID 算出，固定为负数，不会和用户自己的自定义音色撞号；选中状态按它记。 */
function hashVoiceNumericId(pluginId: string, voiceId: string): number {
  const key = `${pluginId}:${voiceId}`;
  let h = 2166136261;
  for (let i = 0; i < key.length; i++) {
    h ^= key.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return -Math.max(1, Math.abs(h | 0));
}

/**
 * 启用中的插件声明的音色，并进自定义音色列表（名字后带插件名），地址为 plugin-tts://插件ID/音色ID。
 * 只列音色、不做合成，启动时就能装上而不必加载朗读引擎；合成在 PluginTtsBridge。
 * 插件功能总开关关闭时列表为空。
 */
export class PluginTtsVoices {
  static install(): void {
    TtsCustomVoices.extraVoicesProvider = (): HttpTTS[] => PluginTtsVoices.list();
  }

  static list(): HttpTTS[] {
    const out: HttpTTS[] = [];
    if (!PluginFeatureStore.enabled()) return out;
    for (const bound of PluginRegistry.getInstance().getTtsProviders()) {
      const pluginId = bound.plugin.manifest.id;
      for (const spec of bound.contribution.voices) {
        const fmt = spec.outputFormat || bound.contribution.outputFormat;
        const v = new HttpTTS();
        v.id = hashVoiceNumericId(pluginId, spec.id);
        v.name = `${spec.name}（${bound.contribution.name || bound.plugin.manifest.name}）`;
        v.url = `${TtsCustomVoices.PLUGIN_URL_PREFIX}${encodeURIComponent(pluginId)}/${encodeURIComponent(spec.id)}`;
        v.contentType = fmt === 'pcm16le'
          ? 'audio/pcm'
          : (fmt === 'wav' ? 'audio/wav' : 'audio/mpeg');
        v.concurrentRate = spec.concurrentRate || bound.contribution.concurrentRate || '';
        v.enabled = true;
        v.speedMode = 'client';
        out.push(v);
      }
    }
    return out;
  }
}
