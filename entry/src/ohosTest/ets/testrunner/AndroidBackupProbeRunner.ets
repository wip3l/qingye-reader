import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';

export default class AndroidBackupProbeRunner implements TestRunner {
  onPrepare(): void {}
  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const parameters = abilityDelegatorRegistry.getArguments().parameters;
    AppStorage.setOrCreate('androidBackupProbeUrl', parameters['fixtureUrl'] ||
      parameters['-s fixtureUrl'] || 'http://127.0.0.1:18395/fixture');
    AppStorage.setOrCreate('androidBackupProbeResult', '');
    await delegator.startAbility({ bundleName: 'io.legado.read', moduleName: 'entry_test',
      abilityName: 'AndroidBackupProbeAbility' });
    for (let attempt = 0; attempt < 900; attempt++) {
      const result = AppStorage.get<string>('androidBackupProbeResult') || '';
      if (result) { await delegator.finishTest(result, result.startsWith('PASS') ? 0 : -1); return; }
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 200); });
    }
    await delegator.finishTest('FAIL Android backup open timed out', -1);
  }
}
