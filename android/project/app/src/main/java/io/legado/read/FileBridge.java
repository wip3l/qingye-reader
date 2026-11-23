package io.legado.read;

import android.content.ContentResolver;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.provider.OpenableColumns;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

import ohos.ace.adapter.capability.bridge.BridgeManager;
import ohos.ace.adapter.capability.bridge.BridgePlugin;

/**
 * 文件桥：在 content:// 地址和应用沙箱路径之间搬运文件。
 *
 * 安卓的文件选择器、保存面板返回的是 content:// 地址，ArkTS 侧的文件接口只认沙箱路径。
 * 对应的 ArkTS 封装在 android/overlay/entry/src/main/ets/platform/Files.ts。
 * ArkTS 发起的调用由 BridgeManager 放到后台线程执行，这里可以直接做阻塞读写。
 * 返回值统一是 JSON 字符串，失败时带 error 字段，不抛异常（抛出的异常到 ArkTS 侧只剩错误码）。
 */
public class FileBridge extends BridgePlugin {
    /** 与 Files.ts 里的 BRIDGE_NAME 一致。 */
    public static final String NAME = "io.legado.read/file";

    private static final int BUFFER_SIZE = 64 * 1024;

    private final Context context;

    public FileBridge(Context context, BridgeManager bridgeManager) {
        super(context, NAME, bridgeManager);
        this.context = context;
    }

    /** 查询地址对应的文件名、大小、修改时间：{"name","size","mtime"}。 */
    public String stat(String uri) {
        try {
            return describe(uri).toString();
        } catch (Exception e) {
            return error(e);
        }
    }

    /**
     * 把地址指向的文件复制到沙箱路径 destPath（覆盖），返回 {"path","name","size","mtime"}。
     * size、mtime 取源文件的，供导入逻辑判断文件是否变过。
     */
    public String copyToPath(String uri, String destPath) {
        try {
            JSONObject info = describe(uri);
            File dest = new File(destPath);
            File parent = dest.getParentFile();
            if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
                throw new IOException("无法创建目录 " + parent);
            }
            File temp = new File(destPath + ".part");
            try (InputStream in = open(uri); OutputStream out = new FileOutputStream(temp)) {
                long copied = pump(in, out);
                if (info.optLong("size", -1) < 0) info.put("size", copied);
            }
            if (dest.exists() && !dest.delete()) throw new IOException("无法覆盖 " + dest);
            if (!temp.renameTo(dest)) throw new IOException("无法写入 " + dest);
            info.put("path", dest.getAbsolutePath());
            return info.toString();
        } catch (Exception e) {
            new File(destPath + ".part").delete();
            return error(e);
        }
    }

    /** 把沙箱文件 srcPath 写进地址 uri（保存面板返回的 content:// 地址，或沙箱路径），返回 {"size"}。 */
    public String copyFromPath(String srcPath, String uri) {
        try (InputStream in = new FileInputStream(srcPath); OutputStream out = openForWrite(uri)) {
            JSONObject result = new JSONObject();
            result.put("size", pump(in, out));
            return result.toString();
        } catch (Exception e) {
            return error(e);
        }
    }

    // ---------- 内部 ----------

    private static boolean isContent(String uri) {
        return uri != null && uri.startsWith(ContentResolver.SCHEME_CONTENT + "://");
    }

    private static File localFile(String uriOrPath) {
        String path = uriOrPath;
        if (path.startsWith("file://")) path = Uri.parse(path).getPath();
        return new File(path);
    }

    private InputStream open(String uri) throws IOException {
        if (!isContent(uri)) return new FileInputStream(localFile(uri));
        InputStream in = context.getContentResolver().openInputStream(Uri.parse(uri));
        if (in == null) throw new IOException("无法打开 " + uri);
        return in;
    }

    private OutputStream openForWrite(String uri) throws IOException {
        if (!isContent(uri)) return new FileOutputStream(localFile(uri));
        // "wt"：截断写。部分提供方不认 "wt"，退回 "w"。
        OutputStream out;
        try {
            out = context.getContentResolver().openOutputStream(Uri.parse(uri), "wt");
        } catch (IllegalArgumentException | UnsupportedOperationException e) {
            out = context.getContentResolver().openOutputStream(Uri.parse(uri), "w");
        }
        if (out == null) throw new IOException("无法写入 " + uri);
        return out;
    }

    private JSONObject describe(String uri) throws JSONException, IOException {
        JSONObject info = new JSONObject();
        if (!isContent(uri)) {
            File file = localFile(uri);
            if (!file.isFile()) throw new IOException("文件不存在 " + file);
            info.put("name", file.getName());
            info.put("size", file.length());
            info.put("mtime", file.lastModified() / 1000);
            return info;
        }
        Uri parsed = Uri.parse(uri);
        String name = "";
        long size = -1;
        long mtime = 0;
        try (Cursor cursor = context.getContentResolver().query(parsed, null, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                int sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE);
                int mtimeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED);
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) name = cursor.getString(nameIndex);
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) size = cursor.getLong(sizeIndex);
                if (mtimeIndex >= 0 && !cursor.isNull(mtimeIndex)) mtime = cursor.getLong(mtimeIndex) / 1000;
            }
        } catch (SecurityException | IllegalArgumentException e) {
            // 有的提供方不支持查询，只能打开流；名字退回地址最后一段。
        }
        if (name == null || name.isEmpty()) {
            String last = parsed.getLastPathSegment();
            name = last == null ? "" : last.substring(last.lastIndexOf('/') + 1);
        }
        info.put("name", name);
        info.put("size", size);
        // 与鸿蒙 fs.stat 一致，用秒。
        info.put("mtime", mtime);
        return info;
    }

    private static long pump(InputStream in, OutputStream out) throws IOException {
        byte[] buffer = new byte[BUFFER_SIZE];
        long total = 0;
        int read;
        while ((read = in.read(buffer)) != -1) {
            out.write(buffer, 0, read);
            total += read;
        }
        out.flush();
        return total;
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
