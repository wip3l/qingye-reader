package io.legado.read;

import android.os.Bundle;

import ohos.stage.ability.adapter.StageActivity;

/** entry 模块 EntryAbility 的安卓宿主。实例名格式为 <bundleName>:<模块名>:<Ability 名>:。 */
public class EntryEntryAbilityActivity extends StageActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setInstanceName("io.legado.read:entry:EntryAbility:");
        super.onCreate(savedInstanceState);
    }
}
