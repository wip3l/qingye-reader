package io.legado.read;

import android.content.Context;

import com.k2fsa.sherpa.onnx.GeneratedAudio;
import com.k2fsa.sherpa.onnx.OfflineTts;
import com.k2fsa.sherpa.onnx.OfflineTtsConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsKokoroModelConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsMatchaModelConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;

import ohos.ace.adapter.capability.bridge.BridgeManager;
import ohos.ace.adapter.capability.bridge.BridgePlugin;

/**
 * 离线朗读桥：sherpa-onnx 的安卓 Java 接口（替代鸿蒙上的 sherpa_onnx NAPI 包和合成线程）。
 *
 * 对应 android/overlay/entry/src/main/ets/utils/localtts/LocalTtsEngine.ets。ArkTS 发起的调用在后台线程执行，
 * 模型加载和合成都可以直接阻塞；同一时刻只合成一条（加锁）。取消拦不住正在合成的那一条，只丢弃它的结果，
 * 与鸿蒙端一致。合成结果写成 16 位小端 PCM 文件交给 ArkTS 读，避免大数组过桥。返回 JSON，失败时带 error。
 */
public class SherpaBridge extends BridgePlugin {
    /** 与 LocalTtsEngine.ets 里的 SHERPA_BRIDGE_NAME 一致。 */
    public static final String NAME = "io.legado.read/sherpa";

    private final Object lock = new Object();
    private OfflineTts tts;
    private volatile int generation;

    public SherpaBridge(Context context, BridgeManager bridgeManager) {
        super(context, NAME, bridgeManager);
    }

    /**
     * 加载模型。参数与鸿蒙合成线程的 init 请求相同：
     * {"kind": "vits"|"matcha"|"kokoro", "model", "vocoder", "voices", "tokens", "lexicon", "dataDir", "ruleFsts",
     *  "noiseScale", "noiseScaleW", "threads"}，路径都是绝对路径，多个词典/规则用逗号连接。返回 {"sampleRate", "ms"}。
     */
    public String load(String json) {
        long startedAt = System.currentTimeMillis();
        try {
            JSONObject request = new JSONObject(json);
            String kind = request.optString("kind", "vits");
            OfflineTtsModelConfig.Builder model = OfflineTtsModelConfig.builder()
                    .setNumThreads(request.optInt("threads", 2))
                    .setDebug(false);
            String tokens = request.optString("tokens", "");
            String lexicon = request.optString("lexicon", "");
            String dataDir = request.optString("dataDir", "");
            if ("matcha".equals(kind)) {
                model.setMatcha(OfflineTtsMatchaModelConfig.builder()
                        .setAcousticModel(request.optString("model", ""))
                        .setVocoder(request.optString("vocoder", ""))
                        .setTokens(tokens).setLexicon(lexicon).setDataDir(dataDir)
                        .build());
            } else if ("kokoro".equals(kind)) {
                model.setKokoro(OfflineTtsKokoroModelConfig.builder()
                        .setModel(request.optString("model", ""))
                        .setVoices(request.optString("voices", ""))
                        .setTokens(tokens).setLexicon(lexicon).setDataDir(dataDir)
                        .build());
            } else {
                OfflineTtsVitsModelConfig.Builder vits = OfflineTtsVitsModelConfig.builder()
                        .setModel(request.optString("model", ""))
                        .setTokens(tokens).setLexicon(lexicon).setDataDir(dataDir);
                // 不传就用 sherpa-onnx 默认值；Piper 模型训练时的推荐值往往更小，读错字更少。
                double noiseScale = request.optDouble("noiseScale", 0);
                double noiseScaleW = request.optDouble("noiseScaleW", 0);
                if (noiseScale > 0) vits.setNoiseScale((float) noiseScale);
                if (noiseScaleW > 0) vits.setNoiseScaleW((float) noiseScaleW);
                model.setVits(vits.build());
            }
            OfflineTtsConfig config = OfflineTtsConfig.builder()
                    .setModel(model.build())
                    .setRuleFsts(existingPaths(request.optString("ruleFsts", "")))
                    .build();
            int sampleRate;
            synchronized (lock) {
                releaseLocked();
                tts = new OfflineTts(config);
                sampleRate = tts.getSampleRate();
            }
            JSONObject result = new JSONObject();
            result.put("sampleRate", sampleRate);
            result.put("ms", System.currentTimeMillis() - startedAt);
            return result.toString();
        } catch (Throwable e) {
            return error(e);
        }
    }

    /** 合成一句，写到 path（16 位小端 PCM）。返回 {"path", "sampleRate"}，被取消时 {"cancelled": true}。 */
    public String synthesize(String text, String sid, String speed, String path) {
        int startGeneration = generation;
        try {
            GeneratedAudio audio;
            synchronized (lock) {
                if (startGeneration != generation) return cancelled();
                if (tts == null) throw new IllegalStateException("离线音色未加载");
                audio = tts.generate(text, Integer.parseInt(sid), Float.parseFloat(speed));
            }
            if (startGeneration != generation) return cancelled();
            writePcm16(audio.getSamples(), path);
            JSONObject result = new JSONObject();
            result.put("path", path);
            result.put("sampleRate", audio.getSampleRate());
            return result.toString();
        } catch (Throwable e) {
            return error(e);
        }
    }

    /** 作废排队中和正在合成的请求（正在合成的那一条算完后丢弃）。 */
    public String cancel() {
        generation++;
        return "{}";
    }

    /** 释放模型（一百多 MB）。 */
    public String unload() {
        generation++;
        synchronized (lock) {
            releaseLocked();
        }
        return "{}";
    }

    private void releaseLocked() {
        if (tts != null) {
            tts.release();
            tts = null;
        }
    }

    private static String existingPaths(String joined) {
        StringBuilder out = new StringBuilder();
        for (String path : joined.split(",")) {
            if (path.isEmpty() || !new File(path).exists()) continue;
            if (out.length() > 0) out.append(',');
            out.append(path);
        }
        return out.toString();
    }

    private static void writePcm16(float[] samples, String path) throws IOException {
        File file = new File(path);
        File parent = file.getParentFile();
        if (parent != null && !parent.isDirectory() && !parent.mkdirs()) throw new IOException("无法创建目录 " + parent);
        byte[] buffer = new byte[samples.length * 2];
        for (int i = 0; i < samples.length; i++) {
            float value = Math.max(-1f, Math.min(1f, samples[i]));
            int sample = Math.round(value * 32767f);
            buffer[i * 2] = (byte) (sample & 0xff);
            buffer[i * 2 + 1] = (byte) ((sample >> 8) & 0xff);
        }
        try (OutputStream out = new BufferedOutputStream(new FileOutputStream(file))) {
            out.write(buffer);
        }
    }

    private static String cancelled() {
        return "{\"cancelled\":true}";
    }

    private static String error(Throwable e) {
        JSONObject result = new JSONObject();
        try {
            result.put("error", e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage());
        } catch (JSONException ignored) {
            // put 一个非空字符串不会失败
        }
        return result.toString();
    }
}
