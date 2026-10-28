import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';

export default class WebVerificationTestRunner implements TestRunner {
  onPrepare(): void {}
  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    AppStorage.setOrCreate('webVerificationTestResult', '');
    await delegator.startAbility({ bundleName: 'io.legado.read', moduleName: 'entry_test',
      abilityName: 'WebVerificationTestAbility' });
    for (let i = 0; i < 600; i++) {
      const result = AppStorage.get<string>('webVerificationTestResult') || '';
      if (result) {
        await delegator.print(result + '\n');
        await delegator.finishTest(result, result.startsWith('PASS') ? 0 : -1);
        return;
      }
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 100); });
    }
    await delegator.finishTest('FAIL WebVerification: test page timeout', -1);
  }
}
