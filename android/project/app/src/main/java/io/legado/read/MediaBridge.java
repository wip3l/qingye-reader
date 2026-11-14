package io.legado.read;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaMetadata;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.Build;

import org.json.JSONException;
import org.json.JSONObject;

import ohos.ace.adapter.capability.bridge.BridgeManager;
import ohos.ace.adapter.capability.bridge.BridgePlugin;

/**
 * 媒体会话桥：鸿蒙 AVSession 与后台播放许可（长时任务）在安卓上的对应实现。
 *
 * - 媒体会话：系统的 MediaSession，锁屏、耳机按键、通知栏控件的命令经 onMediaCommand 回调给 ArkTS；
 * - 后台播放：PlaybackService 前台服务，通知栏显示当前书名和播放控件；
 * - 音频焦点：来电、其它应用播放时暂停，短暂失去焦点（如导航播报）结束后续播，对应鸿蒙端的音频打断处理。
 *
 * ArkTS 侧封装见 android/overlay/entry/src/main/ets/platform/MediaSession.ts 和 BackgroundTasks.ts。
 * 整个进程只有一个会话（与鸿蒙“一个 Ability 一个会话”一致），朗读和听书共用。
 */
public class MediaBridge extends BridgePlugin {
    /** 与 MediaSession.ts 里的 MEDIA_BRIDGE_NAME 一致。 */
    public static final String NAME = "io.legado.read/media";

    private static final int NOTIFICATION_PERMISSION_REQUEST = 7301;
    private static MediaBridge instance;

    private final Activity activity;
    private final AudioManager audioManager;
    private MediaSession session;
    private AudioFocusRequest focusRequest;
    private boolean hasFocus;
    private boolean resumeOnFocusGain;

    volatile String title = "";
    volatile String artist = "";
    volatile boolean playing;

    public MediaBridge(Activity activity, BridgeManager bridgeManager) {
        super(activity, NAME, bridgeManager);
        this.activity = activity;
        this.audioManager = (AudioManager) activity.getSystemService(Activity.AUDIO_SERVICE);
        instance = this;
    }

    static MediaBridge instance() {
        return instance;
    }

    MediaSession.Token sessionToken() {
        return session == null ? null : session.getSessionToken();
    }

    Activity activity() {
        return activity;
    }

    /** 建会话；已建过时直接返回。 */
    public String create(String tag) {
        activity.runOnUiThread(() -> {
            if (session != null) return;
            session = new MediaSession(activity, tag == null || tag.isEmpty() ? "qingye" : tag);
            session.setCallback(new MediaSession.Callback() {
                @Override
                public void onPlay() {
                    dispatch("play", "");
                }

                @Override
                public void onPause() {
                    dispatch("pause", "");
                }

                @Override
                public void onStop() {
                    dispatch("stop", "");
                }

                @Override
                public void onSkipToNext() {
                    dispatch("playNext", "");
                }

                @Override
                public void onSkipToPrevious() {
                    dispatch("playPrevious", "");
                }

                @Override
                public void onSeekTo(long position) {
                    dispatch("seek", String.valueOf(position));
                }
            });
        });
        return "{}";
    }

    /** {"title","artist","album","duration"(毫秒)} */
    public String setMetadata(String json) {
        try {
            JSONObject data = new JSONObject(json);
            title = data.optString("title", "");
            artist = data.optString("artist", "");
            MediaMetadata metadata = new MediaMetadata.Builder()
                    .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                    .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                    .putString(MediaMetadata.METADATA_KEY_ALBUM, data.optString("album", ""))
                    .putLong(MediaMetadata.METADATA_KEY_DURATION, data.optLong("duration", -1))
                    .build();
            activity.runOnUiThread(() -> {
                if (session != null) session.setMetadata(metadata);
                PlaybackService.refresh(activity);
            });
            return "{}";
        } catch (JSONException e) {
            return error(e);
        }
    }

    /** {"state": "play"|"pause"|"stop"|"buffering", "position"(毫秒), "speed"} */
    public String setPlaybackState(String json) {
        try {
            JSONObject data = new JSONObject(json);
            String state = data.optString("state", "stop");
            playing = "play".equals(state) || "buffering".equals(state);
            int code;
            switch (state) {
                case "play":
                    code = PlaybackState.STATE_PLAYING;
                    break;
                case "pause":
                    code = PlaybackState.STATE_PAUSED;
                    break;
                case "buffering":
                    code = PlaybackState.STATE_BUFFERING;
                    break;
                default:
                    code = PlaybackState.STATE_STOPPED;
            }
            PlaybackState playbackState = new PlaybackState.Builder()
                    .setActions(PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PAUSE | PlaybackState.ACTION_PLAY_PAUSE
                            | PlaybackState.ACTION_STOP | PlaybackState.ACTION_SKIP_TO_NEXT
                            | PlaybackState.ACTION_SKIP_TO_PREVIOUS | PlaybackState.ACTION_SEEK_TO)
                    .setState(code, data.optLong("position", PlaybackState.PLAYBACK_POSITION_UNKNOWN),
                            (float) data.optDouble("speed", 1.0))
                    .build();
            activity.runOnUiThread(() -> {
                if (session != null) session.setPlaybackState(playbackState);
                if (playing) {
                    requestFocus();
                } else if (!"pause".equals(state) || !resumeOnFocusGain) {
                    // 被打断而暂停时保留焦点请求，焦点回来才能续播；用户主动暂停、停止时交还焦点。
                    abandonFocus();
                }
                PlaybackService.refresh(activity);
            });
            return "{}";
        } catch (JSONException e) {
            return error(e);
        }
    }

    public String activate() {
        activity.runOnUiThread(() -> {
            if (session != null) session.setActive(true);
        });
        return "{}";
    }

    public String deactivate() {
        activity.runOnUiThread(() -> {
            if (session != null) session.setActive(false);
        });
        return "{}";
    }

    public String destroy() {
        activity.runOnUiThread(() -> {
            abandonFocus();
            PlaybackService.stop(activity);
            if (session != null) {
                session.release();
                session = null;
            }
            playing = false;
        });
        return "{}";
    }

    /** 开始后台播放：前台服务 + 通知栏控件。Android 13 起首次会申请通知权限。 */
    public String startBackground() {
        activity.runOnUiThread(() -> {
            if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                    != PackageManager.PERMISSION_GRANTED) {
                activity.requestPermissions(new String[] {Manifest.permission.POST_NOTIFICATIONS},
                        NOTIFICATION_PERMISSION_REQUEST);
            }
            PlaybackService.start(activity);
        });
        return "{}";
    }

    public String stopBackground() {
        activity.runOnUiThread(() -> PlaybackService.stop(activity));
        return "{}";
    }

    /** 通知栏按钮经 PlaybackService 转到这里。 */
    void dispatch(String command, String argument) {
        callMethod("onMediaCommand", command, argument);
    }

    private void requestFocus() {
        if (hasFocus) return;
        if (focusRequest == null) {
            focusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(new AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build())
                    .setWillPauseWhenDucked(false)
                    .setOnAudioFocusChangeListener(this::onFocusChange)
                    .build();
        }
        hasFocus = audioManager.requestAudioFocus(focusRequest) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED;
    }

    private void abandonFocus() {
        resumeOnFocusGain = false;
        if (focusRequest != null && hasFocus) audioManager.abandonAudioFocusRequest(focusRequest);
        hasFocus = false;
    }

    private void onFocusChange(int change) {
        switch (change) {
            case AudioManager.AUDIOFOCUS_LOSS:
                hasFocus = false;
                resumeOnFocusGain = false;
                if (playing) dispatch("pause", "focusLoss");
                break;
            case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
                if (playing) {
                    resumeOnFocusGain = true;
                    dispatch("pause", "focusLossTransient");
                }
                break;
            case AudioManager.AUDIOFOCUS_GAIN:
                hasFocus = true;
                if (resumeOnFocusGain) {
                    resumeOnFocusGain = false;
                    dispatch("play", "focusGain");
                }
                break;
            default:
                // AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK：系统自动压低音量，不打断朗读。
                break;
        }
    }

    private static String error(Exception e) {
        JSONObject result = new JSONObject();
        try {
            result.put("error", e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage());
        } catch (JSONException ignored) {
            // put 一个非空字符串不会失败
        }
        return result.toString();
    }

    /** 给 PlaybackService 拉起界面用。 */
    Intent launchIntent() {
        Intent intent = new Intent(activity, activity.getClass());
        intent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
        return intent;
    }
}
