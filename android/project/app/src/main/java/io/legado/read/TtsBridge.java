package io.legado.read;

import android.content.Context;
import android.os.Bundle;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.speech.tts.Voice;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import ohos.ace.adapter.capability.bridge.BridgeManager;
import ohos.ace.adapter.capability.bridge.BridgePlugin;

/**
 * 系统朗读桥：安卓 TextToSpeech 合成到 WAV 文件，由 ArkTS 侧读出 PCM 交给应用自己的播放器。
 *
 * 鸿蒙端的系统朗读也是引擎回调 PCM、应用播放，所以朗读逻辑（分段、高亮、续播）两端共用，
 * ArkTS 侧的引擎替身见 android/overlay/entry/src/main/ets/platform/SpeechKit.ts。
 * ArkTS 发起的调用在后台线程执行，这里可以阻塞等待合成完成。返回 JSON，失败时带 error。
 */
public class TtsBridge extends BridgePlugin {
    /** 与 SpeechKit.ts 里的 TTS_BRIDGE_NAME 一致。 */
    public static final String NAME = "io.legado.read/tts";

    private static final long INIT_TIMEOUT_SECONDS = 10;
    private static final long SYNTHESIS_TIMEOUT_SECONDS = 60;

    private final Context context;
    private final Map<String, CountDownLatch> pending = new ConcurrentHashMap<>();
    private final Map<String, String> failures = new ConcurrentHashMap<>();
    private TextToSpeech tts;
    private volatile int initStatus = Integer.MIN_VALUE;

    public TtsBridge(Context context, BridgeManager bridgeManager) {
        super(context, NAME, bridgeManager);
        this.context = context.getApplicationContext();
    }

    /** 可用的语音：[{"name","locale","network","quality"}]，按系统给出的顺序。 */
    public String listVoices() {
        try {
            TextToSpeech engine = engine();
            JSONArray voices = new JSONArray();
            if (engine.getVoices() != null) {
                for (Voice voice : engine.getVoices()) {
                    if (voice.getFeatures() != null && voice.getFeatures().contains(
                            TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)) {
                        continue;
                    }
                    JSONObject item = new JSONObject();
                    item.put("name", voice.getName());
                    item.put("locale", voice.getLocale().toLanguageTag());
                    item.put("network", voice.isNetworkConnectionRequired());
                    item.put("quality", voice.getQuality());
                    voices.put(item);
                }
            }
            JSONObject result = new JSONObject();
            result.put("voices", voices);
            Voice current = engine.getDefaultVoice();
            result.put("defaultVoice", current == null ? "" : current.getName());
            return result.toString();
        } catch (Exception e) {
            return error(e);
        }
    }

    /**
     * 把 text 合成到 path（WAV）。voice 为空时用 language 对应的默认语音；rate、pitch 为 1 表示正常。
     * 返回 {"path"}。
     */
    public String synthesize(String text, String voice, String language, String rate, String pitch, String path) {
        String utteranceId = "qingye-" + System.nanoTime();
        CountDownLatch done = new CountDownLatch(1);
        pending.put(utteranceId, done);
        try {
            TextToSpeech engine = engine();
            synchronized (this) {
                applyVoice(engine, voice, language);
                engine.setSpeechRate(parseFloat(rate, 1f));
                engine.setPitch(parseFloat(pitch, 1f));
                File file = new File(path);
                File parent = file.getParentFile();
                if (parent != null && !parent.isDirectory()) parent.mkdirs();
                Bundle params = new Bundle();
                int status = engine.synthesizeToFile(text, params, file, utteranceId);
                if (status != TextToSpeech.SUCCESS) throw new IllegalStateException("系统朗读合成失败");
            }
            if (!done.await(SYNTHESIS_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                throw new IllegalStateException("系统朗读合成超时");
            }
            String failure = failures.remove(utteranceId);
            if (failure != null) throw new IllegalStateException(failure);
            JSONObject result = new JSONObject();
            result.put("path", path);
            return result.toString();
        } catch (Exception e) {
            return error(e);
        } finally {
            pending.remove(utteranceId);
        }
    }

    public String stop() {
        TextToSpeech engine = tts;
        if (engine != null) engine.stop();
        return "{}";
    }

    private void applyVoice(TextToSpeech engine, String voiceName, String language) {
        if (voiceName != null && !voiceName.isEmpty() && engine.getVoices() != null) {
            for (Voice voice : engine.getVoices()) {
                if (voice.getName().equals(voiceName)) {
                    engine.setVoice(voice);
                    return;
                }
            }
        }
        if (language != null && !language.isEmpty()) {
            engine.setLanguage(Locale.forLanguageTag(language));
        }
    }

    private synchronized TextToSpeech engine() throws Exception {
        if (tts != null && initStatus == TextToSpeech.SUCCESS) return tts;
        if (tts != null) tts.shutdown();
        final CountDownLatch ready = new CountDownLatch(1);
        initStatus = Integer.MIN_VALUE;
        tts = new TextToSpeech(context, status -> {
            initStatus = status;
            ready.countDown();
        });
        if (!ready.await(INIT_TIMEOUT_SECONDS, TimeUnit.SECONDS) || initStatus != TextToSpeech.SUCCESS) {
            tts.shutdown();
            tts = null;
            throw new IllegalStateException("系统没有可用的朗读引擎");
        }
        tts.setOnUtteranceProgressListener(new UtteranceProgressListener() {
            @Override
            public void onStart(String utteranceId) {
            }

            @Override
            public void onDone(String utteranceId) {
                release(utteranceId, null);
            }

            @Override
            @Deprecated
            public void onError(String utteranceId) {
                release(utteranceId, "系统朗读合成失败");
            }

            @Override
            public void onError(String utteranceId, int errorCode) {
                release(utteranceId, "系统朗读合成失败（" + errorCode + "）");
            }

            @Override
            public void onStop(String utteranceId, boolean interrupted) {
                release(utteranceId, "已停止");
            }
        });
        return tts;
    }

    private void release(String utteranceId, String failure) {
        if (failure != null) failures.put(utteranceId, failure);
        CountDownLatch latch = pending.get(utteranceId);
        if (latch != null) latch.countDown();
    }

    private static float parseFloat(String value, float fallback) {
        try {
            float parsed = Float.parseFloat(value);
            return parsed > 0 ? parsed : fallback;
        } catch (RuntimeException e) {
            return fallback;
        }
    }

    private static String error(Exception e) {
        JSONObject result = new JSONObject();
        try {
            String message = e.getMessage();
            result.put("error", message == null || message.isEmpty() ? e.getClass().getSimpleName() : message);
        } catch (JSONException ignored) {
            // put 一个非空字符串不会失败
        }
        return result.toString();
    }
}
