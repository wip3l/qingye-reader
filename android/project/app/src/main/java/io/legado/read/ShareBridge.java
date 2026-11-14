package io.legado.read;

import android.app.Activity;
import android.content.ClipData;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;

import ohos.ace.adapter.capability.bridge.BridgeManager;
import ohos.ace.adapter.capability.bridge.BridgePlugin;

/**
 * 分享桥：系统分享面板（替代鸿蒙 systemShare）和保存图片到相册（替代 photoAccessHelper 的创建对话框）。
 * 对应 android/overlay/entry/src/main/ets/platform/Share.ts。返回 JSON，失败时带 error。
 */
public class ShareBridge extends BridgePlugin {
    /** 与 Share.ts 里的 SHARE_BRIDGE_NAME 一致。 */
    public static final String NAME = "io.legado.read/share";

    private final Activity activity;

    public ShareBridge(Activity activity, BridgeManager bridgeManager) {
        super(activity, NAME, bridgeManager);
        this.activity = activity;
    }

    /** {"paths": [...], "mime": "image/png", "title": "..."} */
    public String shareFiles(String json) {
        try {
            JSONObject data = new JSONObject(json);
            JSONArray paths = data.getJSONArray("paths");
            String mime = data.optString("mime", "*/*");
            ArrayList<Uri> uris = new ArrayList<>();
            for (int i = 0; i < paths.length(); i++) uris.add(ShareProvider.uriFor(new File(paths.getString(i))));
            if (uris.isEmpty()) throw new IllegalArgumentException("没有要分享的文件");
            Intent intent;
            if (uris.size() == 1) {
                intent = new Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris.get(0));
            } else {
                intent = new Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris);
            }
            intent.setType(mime);
            ClipData clip = ClipData.newRawUri("", uris.get(0));
            for (int i = 1; i < uris.size(); i++) clip.addItem(new ClipData.Item(uris.get(i)));
            intent.setClipData(clip);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            String title = data.optString("title", "");
            if (!title.isEmpty()) intent.putExtra(Intent.EXTRA_TITLE, title);
            Intent chooser = Intent.createChooser(intent, title.isEmpty() ? null : title);
            activity.runOnUiThread(() -> activity.startActivity(chooser));
            return "{}";
        } catch (Exception e) {
            return error(e);
        }
    }

    /** 把图片存进相册的 Pictures/开源轻页 下。{"paths": [...], "mime": "image/png"}，返回 {"saved": 张数}。 */
    public String saveImages(String json) {
        try {
            JSONObject data = new JSONObject(json);
            JSONArray paths = data.getJSONArray("paths");
            String mime = data.optString("mime", "image/png");
            ContentResolver resolver = activity.getContentResolver();
            int saved = 0;
            for (int i = 0; i < paths.length(); i++) {
                File file = new File(paths.getString(i));
                ContentValues values = new ContentValues();
                values.put(MediaStore.Images.Media.DISPLAY_NAME, file.getName());
                values.put(MediaStore.Images.Media.MIME_TYPE, mime);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    values.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/开源轻页");
                }
                Uri target = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values);
                if (target == null) throw new IllegalStateException("无法写入相册");
                try (InputStream in = new FileInputStream(file); OutputStream out = resolver.openOutputStream(target)) {
                    if (out == null) throw new IllegalStateException("无法写入相册");
                    byte[] buffer = new byte[64 * 1024];
                    int read;
                    while ((read = in.read(buffer)) != -1) out.write(buffer, 0, read);
                }
                saved++;
            }
            JSONObject result = new JSONObject();
            result.put("saved", saved);
            return result.toString();
        } catch (Exception e) {
            return error(e);
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
}
