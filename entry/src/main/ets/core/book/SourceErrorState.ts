import { BookSource, SourceEngineHost, SourceExecutionState } from '@legado/sourceengine';

/**
 * 书源阶段的失败原因按书源地址分开记。引擎默认只有一个全局键，书架检查、边听边下、换源等并发任务
 * 每开始一个阶段就把它清空，听书页、阅读页去读时这本书的原因已经被别的书源冲掉，只能显示笼统的说明。
 * 旧的全局键照样写，直接读 AppStorage 的地方行为不变。书源副本与原书源地址相同，不需要另外绑定。
 */
export class SourceErrorState implements SourceExecutionState {
  private errors: Map<string, string> = new Map<string, string>();

  static install(): void {
    SourceEngineHost.install({ state: new SourceErrorState() });
  }

  bindSource(source: BookSource, target: BookSource): void {
  }

  setError(source: BookSource, message: string): void {
    const key = source?.bookSourceUrl || '';
    if (message) this.errors.set(key, message);
    else this.errors.delete(key);
    AppStorage.setOrCreate<string>(SourceEngineHost.LAST_ERROR_KEY, message);
  }

  getError(source: BookSource): string {
    return this.errors.get(source?.bookSourceUrl || '') || '';
  }
}
