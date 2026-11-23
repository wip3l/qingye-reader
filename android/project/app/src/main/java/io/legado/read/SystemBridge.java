package io.legado.read;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.graphics.Insets;
import android.os.Build;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import ohos.ace.adapter.capability.bridge.BridgeManager;
import ohos.ace.adapter.capability.bridge.BridgePlugin;

/**
 * 系统能力桥：ArkUI-X 没有实现或实现不全的窗口能力。
 *
 * 对应的 ArkTS 封装在 android/overlay/entry/src/main/ets/platform/ 下。返回值约定同 FileBridge：
 * JSON 字符串，失败时带 error 字段。ArkTS 发起的调用在后台线程，改窗口属性要切回主线程。
 */
public class SystemBridge extends BridgePlugin {
    /** 与 overlay 里的 SYSTEM_BRIDGE_NAME 一致。 */
    public static final String NAME = "io.legado.read/system";

    private final Activity activity;

    public SystemBridge(Activity activity, BridgeManager bridgeManager) {
        super(activity, NAME, bridgeManager);
        this.activity = activity;
    }

    /**
     * 设置当前窗口亮度。value 为 0~1，小于 0 表示跟随系统（WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE）。
     * ArkUI-X 的 setWindowBrightness 不接受负数，没法把窗口交还给系统，所以走这里。
     */
    public String setWindowBrightness(String value) {
        final float brightness;
        try {
            float parsed = Float.parseFloat(value);
            brightness = parsed < 0 ? WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE : Math.min(1f, parsed);
        } catch (NumberFormatException e) {
            return error("亮度值无效：" + value);
        }
        final String[] failure = new String[1];
        final CountDownLatch done = new CountDownLatch(1);
        activity.runOnUiThread(() -> {
            try {
                Window window = activity.getWindow();
                WindowManager.LayoutParams params = window.getAttributes();
                params.screenBrightness = brightness;
                window.setAttributes(params);
            } catch (RuntimeException e) {
                failure[0] = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
            } finally {
                done.countDown();
            }
        });
        try {
            if (!done.await(2, TimeUnit.SECONDS)) return error("设置亮度超时");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return error("设置亮度被中断");
        }
        return failure[0] == null ? "{}" : error(failure[0]);
    }

    /**
     * 当前窗口的系统栏占位（px）：{"top": 状态栏, "bottom": 导航栏或手势条}。
     * ArkUI-X 的 getWindowAvoidArea 在安卓上返回全 0，安全区从这里取。
     */
    public String getSystemInsets() {
        final int[] insets = new int[] {0, 0};
        final CountDownLatch done = new CountDownLatch(1);
        Runnable read = () -> {
            try {
                View decor = activity.getWindow().getDecorView();
                WindowInsets root = decor.getRootWindowInsets();
                if (root != null) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        Insets bars = root.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars());
                        insets[0] = bars.top;
                        insets[1] = bars.bottom;
                    } else {
                        insets[0] = root.getSystemWindowInsetTop();
                        insets[1] = root.getSystemWindowInsetBottom();
                    }
                }
            } finally {
                done.countDown();
            }
        };
        activity.runOnUiThread(read);
        try {
            if (!done.await(2, TimeUnit.SECONDS)) return error("读取系统栏高度超时");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return error("读取系统栏高度被中断");
        }
        JSONObject result = new JSONObject();
        try {
            result.put("top", insets[0]);
            result.put("bottom", insets[1]);
        } catch (JSONException ignored) {
            // put 数值不会失败
        }
        return result.toString();
    }

    /**
     * 隐藏或恢复导航栏。value 为 "1" 时隐藏，从屏幕边缘滑动可临时唤出；其它值恢复。
     * 阅读页的页脚贴近屏幕底边，安卓的三键导航栏和手势条都比鸿蒙的导航条高，会压在页脚上。
     */
    public String setNavigationBarHidden(String value) {
        final boolean hidden = "1".equals(value);
        activity.runOnUiThread(() -> {
            View decor = activity.getWindow().getDecorView();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                WindowInsetsController controller = decor.getWindowInsetsController();
                if (controller == null) return;
                if (hidden) {
                    controller.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
                    controller.hide(WindowInsets.Type.navigationBars());
                } else {
                    controller.show(WindowInsets.Type.navigationBars());
                }
            } else {
                int flags = decor.getSystemUiVisibility();
                int immersive = View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY;
                decor.setSystemUiVisibility(hidden ? flags | immersive : flags & ~immersive);
            }
        });
        return "{}";
    }

    /**
     * 用系统浏览器打开网页（充值收银台等）。只接受 https 地址；支付宝 App 装了的话收银台会自动拉起它。
     */
    public String openUrl(String url) {
        Uri uri = Uri.parse(url == null ? "" : url);
        if (!"https".equals(uri.getScheme())) return error("只能打开 https 地址");
        Intent intent = new Intent(Intent.ACTION_VIEW, uri);
        intent.addCategory(Intent.CATEGORY_BROWSABLE);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            activity.startActivity(intent);
        } catch (ActivityNotFoundException e) {
            return error("没有可用的浏览器");
        }
        return "{}";
    }

    private static String error(String message) {
        JSONObject result = new JSONObject();
        try {
            result.put("error", message);
        } catch (JSONException ignored) {
            // put 一个非空字符串不会失败
        }
        return result.toString();
    }
}
