package io.legado.read;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import android.webkit.MimeTypeMap;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;

/**
 * 把应用沙箱里的文件以 content:// 地址交给其它应用（系统分享面板）。只读，且只放行应用自己的
 * files / cache 目录下的文件。地址形如 content://io.legado.read.share/<编码后的绝对路径>。
 * 项目没有引入 androidx，所以不用 FileProvider，自己实现这几个方法。
 */
public class ShareProvider extends ContentProvider {
    static final String AUTHORITY = "io.legado.read.share";

    static Uri uriFor(File file) {
        return new Uri.Builder().scheme("content").authority(AUTHORITY).appendPath(file.getAbsolutePath()).build();
    }

    private File fileFor(Uri uri) throws FileNotFoundException {
        String path = uri.getLastPathSegment();
        if (path == null) throw new FileNotFoundException(String.valueOf(uri));
        try {
            File file = new File(path).getCanonicalFile();
            String files = getContext().getFilesDir().getCanonicalPath() + File.separator;
            String cache = getContext().getCacheDir().getCanonicalPath() + File.separator;
            String target = file.getPath();
            if (!target.startsWith(files) && !target.startsWith(cache)) throw new FileNotFoundException("不允许分享 " + target);
            if (!file.isFile()) throw new FileNotFoundException("文件不存在 " + target);
            return file;
        } catch (IOException e) {
            throw new FileNotFoundException(e.getMessage());
        }
    }

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        return ParcelFileDescriptor.open(fileFor(uri), ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        File file;
        try {
            file = fileFor(uri);
        } catch (FileNotFoundException e) {
            return null;
        }
        String[] columns = projection != null ? projection : new String[] {OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE};
        MatrixCursor cursor = new MatrixCursor(columns, 1);
        Object[] row = new Object[columns.length];
        for (int i = 0; i < columns.length; i++) {
            if (OpenableColumns.DISPLAY_NAME.equals(columns[i])) row[i] = file.getName();
            else if (OpenableColumns.SIZE.equals(columns[i])) row[i] = file.length();
        }
        cursor.addRow(row);
        return cursor;
    }

    @Override
    public String getType(Uri uri) {
        String name = uri.getLastPathSegment();
        String extension = name == null ? "" : MimeTypeMap.getFileExtensionFromUrl(Uri.encode(name));
        String type = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension.toLowerCase());
        return type == null ? "application/octet-stream" : type;
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        throw new UnsupportedOperationException("只读");
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException("只读");
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException("只读");
    }
}
