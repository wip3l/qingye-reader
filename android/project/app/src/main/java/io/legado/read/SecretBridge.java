package io.legado.read;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import org.json.JSONException;
import org.json.JSONObject;

import java.security.KeyStore;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.IvParameterSpec;

import ohos.ace.adapter.capability.bridge.BridgeManager;
import ohos.ace.adapter.capability.bridge.BridgePlugin;

/**
 * 密钥库桥：用安卓密钥库里的 AES-256 密钥做 CBC/PKCS7 加解密，替代鸿蒙的 HUKS。
 *
 * 对应 android/overlay/entry/src/main/ets/platform/KeystoreCipher.ts。密钥按别名首次使用时生成，不出密钥库。
 * IV 由调用方给出（与鸿蒙端的记录格式一致），所以生成密钥时关掉了强制随机 IV。
 * 字节数组以 Base64 传递；返回 {"data": Base64}，失败时 {"error": 原因}。
 */
public class SecretBridge extends BridgePlugin {
    /** 与 KeystoreCipher.ts 里的 SECRET_BRIDGE_NAME 一致。 */
    public static final String NAME = "io.legado.read/secret";

    private static final String KEYSTORE = "AndroidKeyStore";
    private static final String TRANSFORMATION = "AES/CBC/PKCS7Padding";

    public SecretBridge(Context context, BridgeManager bridgeManager) {
        super(context, NAME, bridgeManager);
    }

    public String encrypt(String alias, String data, String iv) {
        return transform(Cipher.ENCRYPT_MODE, alias, data, iv);
    }

    public String decrypt(String alias, String data, String iv) {
        return transform(Cipher.DECRYPT_MODE, alias, data, iv);
    }

    private String transform(int mode, String alias, String data, String iv) {
        try {
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(mode, key(alias), new IvParameterSpec(Base64.decode(iv, Base64.NO_WRAP)));
            byte[] output = cipher.doFinal(Base64.decode(data, Base64.NO_WRAP));
            JSONObject result = new JSONObject();
            result.put("data", Base64.encodeToString(output, Base64.NO_WRAP));
            return result.toString();
        } catch (Exception e) {
            return error(e);
        }
    }

    private static synchronized SecretKey key(String alias) throws Exception {
        KeyStore store = KeyStore.getInstance(KEYSTORE);
        store.load(null);
        KeyStore.Entry entry = store.getEntry(alias, null);
        if (entry instanceof KeyStore.SecretKeyEntry) {
            return ((KeyStore.SecretKeyEntry) entry).getSecretKey();
        }
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE);
        generator.init(new KeyGenParameterSpec.Builder(alias,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_CBC)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_PKCS7)
                .setRandomizedEncryptionRequired(false)
                .build());
        return generator.generateKey();
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
