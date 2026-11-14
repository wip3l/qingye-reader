package io.legado.read;

import android.os.Bundle;

import ohos.stage.ability.adapter.StageActivity;

/** entry 模块 EntryAbility 的安卓宿主。实例名格式为 <bundleName>:<模块名>:<Ability 名>:。 */
public class EntryEntryAbilityActivity extends StageActivity {
    /** 桥对象要一直持有，被回收后 ArkTS 侧的调用就没有接收方了。 */
    private FileBridge fileBridge;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setInstanceName("io.legado.read:entry:EntryAbility:");
        super.onCreate(savedInstanceState);
        fileBridge = new FileBridge(this, getBridgeManager());
    }
}
