package io.legado.read;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.media.session.MediaSession;
import android.os.Build;
import android.os.IBinder;

/**
 * 后台朗读、听书的前台服务，对应鸿蒙的音频播放长时任务。通知栏显示书名和上一段/播放暂停/下一段，
 * 按钮经 MediaBridge 转成和锁屏、耳机按键一样的媒体命令。
 */
public class PlaybackService extends Service {
    private static final String CHANNEL_ID = "playback";
    private static final int NOTIFICATION_ID = 7302;
    private static final String ACTION_COMMAND = "io.legado.read.PLAYBACK_COMMAND";
    private static final String EXTRA_COMMAND = "command";
    private static volatile boolean running;

    static void start(Context context) {
        Intent intent = new Intent(context, PlaybackService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
    }

    static void stop(Context context) {
        if (running) context.stopService(new Intent(context, PlaybackService.class));
    }

    /** 媒体信息或播放状态变化时刷新通知；服务没在运行时什么也不做。 */
    static void refresh(Context context) {
        if (!running) return;
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        manager.notify(NOTIFICATION_ID, build(context));
    }

    @Override
    public void onCreate() {
        super.onCreate();
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            NotificationChannel channel = new NotificationChannel(CHANNEL_ID, "朗读与听书", NotificationManager.IMPORTANCE_LOW);
            channel.setShowBadge(false);
            manager.createNotificationChannel(channel);
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_COMMAND.equals(intent.getAction())) {
            MediaBridge bridge = MediaBridge.instance();
            String command = intent.getStringExtra(EXTRA_COMMAND);
            if (bridge != null && command != null) bridge.dispatch(command, "notification");
            return START_NOT_STICKY;
        }
        Notification notification = build(this);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
        running = true;
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        running = false;
        stopForeground(true);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private static Notification build(Context context) {
        MediaBridge bridge = MediaBridge.instance();
        String title = bridge == null || bridge.title.isEmpty() ? context.getString(R.string.app_name) : bridge.title;
        String artist = bridge == null ? "" : bridge.artist;
        boolean playing = bridge != null && bridge.playing;
        Notification.Builder builder = new Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle(title)
                .setContentText(artist)
                .setOngoing(playing)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .addAction(action(context, android.R.drawable.ic_media_previous, "上一段", "playPrevious", 1))
                .addAction(playing
                        ? action(context, android.R.drawable.ic_media_pause, "暂停", "pause", 2)
                        : action(context, android.R.drawable.ic_media_play, "播放", "play", 2))
                .addAction(action(context, android.R.drawable.ic_media_next, "下一段", "playNext", 3));
        Notification.MediaStyle style = new Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2);
        MediaSession.Token token = bridge == null ? null : bridge.sessionToken();
        if (token != null) style.setMediaSession(token);
        builder.setStyle(style);
        if (bridge != null) {
            builder.setContentIntent(PendingIntent.getActivity(context, 0, bridge.launchIntent(),
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
        }
        return builder.build();
    }

    private static Notification.Action action(Context context, int icon, String label, String command, int requestCode) {
        Intent intent = new Intent(context, PlaybackService.class).setAction(ACTION_COMMAND).putExtra(EXTRA_COMMAND, command);
        PendingIntent pending = PendingIntent.getService(context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Action.Builder(android.graphics.drawable.Icon.createWithResource(context, icon), label, pending)
                .build();
    }
}
