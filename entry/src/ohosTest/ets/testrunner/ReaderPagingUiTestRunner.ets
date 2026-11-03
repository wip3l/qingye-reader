import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';

export default class ReaderPagingUiTestRunner implements TestRunner {
  onPrepare(): void {}
  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    AppStorage.setOrCreate('readerPagingTestResult', '');
    try {
      await delegator.startAbility({ bundleName: 'io.legado.read', moduleName: 'entry_test',
        abilityName: 'ReaderPagingPerformanceTestAbility' });
      const deadline = Date.now() + 60000;
      while (Date.now() < deadline) {
        const result = AppStorage.get<string>('readerPagingTestResult') || '';
        if (result) { await delegator.finishTest(result, result.startsWith('PASS') ? 0 : -1); return; }
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 100); });
      }
      await delegator.finishTest('FAIL Reader paging UI timed out', -1);
    } catch (error) { await delegator.finishTest(`FAIL Reader paging UI: ${(error as Error).message}`, -1); }
  }
}
