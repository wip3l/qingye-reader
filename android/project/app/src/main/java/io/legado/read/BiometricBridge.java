package io.legado.read;

import android.app.Activity;
import android.hardware.biometrics.BiometricManager;
import android.hardware.biometrics.BiometricPrompt;
import android.os.Build;
import android.os.CancellationSignal;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import ohos.ace.adapter.capability.bridge.BridgeManager;
import ohos.ace.adapter.capability.bridge.BridgePlugin;

/**
 * 生物认证桥：系统 BiometricPrompt（指纹、人脸），替代鸿蒙的统一认证控件。只在本机做门禁（隐私书架）。
 * 对应 android/overlay/entry/src/main/ets/platform/BiometricAuth.ets。
 * 返回值是纯字符串：available 返回 "1"/"0"；authenticate 返回 success / usePassword / canceled / failed。
 */
public class BiometricBridge extends BridgePlugin {
    /** 与 BiometricAuth.ets 里的 BIOMETRIC_BRIDGE_NAME 一致。 */
    public static final String NAME = "io.legado.read/biometric";

    private final Activity activity;

    public BiometricBridge(Activity activity, BridgeManager bridgeManager) {
        super(activity, NAME, bridgeManager);
        this.activity = activity;
    }

    /** 是否有已录入、可用的强生物认证（Android 10 起才能可靠判断，更早的系统按不可用处理）。 */
    public String available() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "0";
        BiometricManager manager = activity.getSystemService(BiometricManager.class);
        if (manager == null) return "0";
        int status = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                ? manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
                : manager.canAuthenticate();
        return status == BiometricManager.BIOMETRIC_SUCCESS ? "1" : "0";
    }

    /**
     * 弹出认证框。negativeText 是取消按钮的文字；usePassword 为 "1" 时点它表示“改用应用密码”。
     * 在后台线程等待结果（ArkTS 的异步调用本来就在后台线程）。
     */
    public String authenticate(String title, String negativeText, String usePassword) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "failed";
        final String[] outcome = {"failed"};
        final CountDownLatch done = new CountDownLatch(1);
        final boolean negativeMeansPassword = "1".equals(usePassword);
        activity.runOnUiThread(() -> {
            BiometricPrompt prompt = new BiometricPrompt.Builder(activity)
                    .setTitle(title == null || title.isEmpty() ? "验证身份" : title)
                    .setNegativeButton(negativeText == null || negativeText.isEmpty() ? "取消" : negativeText,
                            activity.getMainExecutor(), (dialog, which) -> {
                                outcome[0] = negativeMeansPassword ? "usePassword" : "canceled";
                                done.countDown();
                            })
                    .build();
            prompt.authenticate(new CancellationSignal(), activity.getMainExecutor(),
                    new BiometricPrompt.AuthenticationCallback() {
                        @Override
                        public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult result) {
                            outcome[0] = "success";
                            done.countDown();
                        }

                        @Override
                        public void onAuthenticationError(int errorCode, CharSequence message) {
                            outcome[0] = errorCode == BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED
                                    || errorCode == BiometricPrompt.BIOMETRIC_ERROR_CANCELED ? "canceled" : "failed";
                            done.countDown();
                        }
                    });
        });
        try {
            done.await(5, TimeUnit.MINUTES);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return outcome[0];
    }
}
