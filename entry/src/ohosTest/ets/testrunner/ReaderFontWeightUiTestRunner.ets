import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';

/** Host-side uitest commands drive the actual controls without depending on Driver initialization. */
export default class ReaderFontWeightUiTestRunner implements TestRunner {
  onPrepare(): void {}
  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    await delegator.startAbility({ bundleName: 'io.legado.read', moduleName: 'entry_test',
      abilityName: 'ReaderFontWeightTestAbility' });
    await delegator.print('STEPPER_UI_READY\n');
    await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 120000); });
    await delegator.finishTest('FAIL: UI host timeout', -1);
  }
}
