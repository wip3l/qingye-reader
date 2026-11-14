package io.legado.read;

import android.os.Bundle;
import android.view.KeyEvent;

import ohos.stage.ability.adapter.StageActivity;

/** entry 模块 EntryAbility 的安卓宿主。实例名格式为 <bundleName>:<模块名>:<Ability 名>:。 */
public class EntryEntryAbilityActivity extends StageActivity {
    /** 桥对象要一直持有，被回收后 ArkTS 侧的调用就没有接收方了。 */
    private FileBridge fileBridge;
    private SystemBridge systemBridge;
    private CookieBridge cookieBridge;
    private SecretBridge secretBridge;
    private TtsBridge ttsBridge;
    private MediaBridge mediaBridge;
    private KeyBridge keyBridge;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setInstanceName("io.legado.read:entry:EntryAbility:");
        super.onCreate(savedInstanceState);
        fileBridge = new FileBridge(this, getBridgeManager());
        systemBridge = new SystemBridge(this, getBridgeManager());
        cookieBridge = new CookieBridge(this, getBridgeManager());
        secretBridge = new SecretBridge(this, getBridgeManager());
        ttsBridge = new TtsBridge(this, getBridgeManager());
        mediaBridge = new MediaBridge(this, getBridgeManager());
        keyBridge = new KeyBridge(this, getBridgeManager());
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        // 阅读页开了音量键翻页时，音量键交给 ArkTS，不调系统音量。
        if (keyBridge != null && keyBridge.handle(event)) return true;
        return super.dispatchKeyEvent(event);
    }
}
