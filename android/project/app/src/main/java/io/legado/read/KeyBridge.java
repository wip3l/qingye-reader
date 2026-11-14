package io.legado.read;

import android.content.Context;
import android.view.KeyEvent;

import java.util.Set;
import java.util.concurrent.CopyOnWriteArraySet;

import ohos.ace.adapter.capability.bridge.BridgeManager;
import ohos.ace.adapter.capability.bridge.BridgePlugin;

/**
 * 按键接管桥：鸿蒙 inputConsumer 在安卓上的对应实现，目前用于音量键翻页。
 *
 * ArkTS 侧登记要接管的按键（鸿蒙键码），Activity 的 dispatchKeyEvent 先问这里：接管的键按下时回调
 * onKeyPressed（鸿蒙键码），按下、抬起都吞掉，系统音量不变。没登记时按键照常走系统。
 * ArkTS 侧封装见 android/overlay/entry/src/main/ets/platform/KeyConsumer.ts。
 */
public class KeyBridge extends BridgePlugin {
    /** 与 KeyConsumer.ts 里的 KEY_BRIDGE_NAME 一致。 */
    public static final String NAME = "io.legado.read/key";

    /** 鸿蒙键码 → 安卓键码，只列需要接管的键。 */
    private static final int OH_VOLUME_UP = 16;
    private static final int OH_VOLUME_DOWN = 17;

    private final Set<Integer> intercepted = new CopyOnWriteArraySet<>();

    public KeyBridge(Context context, BridgeManager bridgeManager) {
        super(context, NAME, bridgeManager);
    }

    public String intercept(String ohKeyCode) {
        int code = androidKeyCode(parse(ohKeyCode));
        if (code != KeyEvent.KEYCODE_UNKNOWN) intercepted.add(code);
        return "{}";
    }

    public String release(String ohKeyCode) {
        intercepted.remove(androidKeyCode(parse(ohKeyCode)));
        return "{}";
    }

    /** 由 Activity.dispatchKeyEvent 调用；返回 true 表示已接管。 */
    boolean handle(KeyEvent event) {
        if (!intercepted.contains(event.getKeyCode())) return false;
        if (event.getAction() == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0) {
            callMethod("onKeyPressed", String.valueOf(ohKeyCode(event.getKeyCode())));
        }
        return true;
    }

    private static int parse(String value) {
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    private static int androidKeyCode(int ohKeyCode) {
        switch (ohKeyCode) {
            case OH_VOLUME_UP:
                return KeyEvent.KEYCODE_VOLUME_UP;
            case OH_VOLUME_DOWN:
                return KeyEvent.KEYCODE_VOLUME_DOWN;
            default:
                return KeyEvent.KEYCODE_UNKNOWN;
        }
    }

    private static int ohKeyCode(int androidKeyCode) {
        switch (androidKeyCode) {
            case KeyEvent.KEYCODE_VOLUME_UP:
                return OH_VOLUME_UP;
            case KeyEvent.KEYCODE_VOLUME_DOWN:
                return OH_VOLUME_DOWN;
            default:
                return -1;
        }
    }
}
