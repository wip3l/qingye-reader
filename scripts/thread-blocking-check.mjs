import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), 'utf8');
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const scheduler = read('harmony-book-source-engine/sourceengine/src/main/ets/core/concurrency/CooperativeScheduler.ts');
const preprocessor = read('entry/src/main/ets/core/concurrency/ReaderContentPreprocessor.ets');
const models = read('harmony-book-source-engine/sourceengine/src/main/ets/core/rule/RuleExecutionModels.ts');
const service = read('harmony-book-source-engine/sourceengine/src/main/ets/core/rule/RuleExecutionService.ts');
const stageRuntime = read('harmony-book-source-engine/sourceengine/src/main/ets/core/book/BookSourceStageWebRuntime.ts');
const search = read('entry/src/main/ets/core/book/SearchCoordinator.ts');
const explore = read('entry/src/main/ets/core/book/ExploreCoordinator.ts');
const webBook = read('entry/src/main/ets/core/book/WebBookService.ts');
// 首页各页签已拆到 components/home，检查时与入口页拼在一起看。
const index = read('entry/src/main/ets/pages/Index.ets') + '\n' +
  ['HomeTabShells', 'BookshelfPage', 'ExplorePage', 'SearchPage', 'SettingsTabPage']
    .map((name) => read(`entry/src/main/ets/components/home/${name}.ets`)).join('\n');
const reader = read('entry/src/main/ets/pages/ReadBook.ets');
const paginator = read('entry/src/main/ets/core/reader/ReaderV2Paginator.ets');

assert(scheduler.includes('DEFAULT_UI_SLICE_MS: number = 6'),
  'Cooperative scheduler must keep the UI work slice below one frame');
assert(/setTimeout\(resolve,\s*[01]\)/.test(scheduler),
  'Cooperative scheduler must yield back to the event loop');
assert(scheduler.includes('CooperativeCancellationToken') && scheduler.includes('throwIfCancelled'),
  'Long-running rule work must remain cancellable');

assert(models.includes('listResult: boolean') && models.includes('readerActionMode: boolean'),
  'Rule requests must carry list-result and reader execution context');
assert(service.includes('executeFullJsFieldBatch') && service.includes('await runtime.execute(runtimeRequest)'),
  'Full JavaScript rules must execute through the isolated Stage Web runtime');
assert(!service.includes('fallback legacy'),
  'Unified rule execution must not silently fall back to synchronous legacy JavaScript');
assert(service.includes('await slice.checkpoint(token)') && service.includes('cancelOwner(ownerId: string)'),
  'Unified rule execution must be time-sliced and cancellable by owner');

for (const [name, source] of [['search', search], ['explore', explore], ['book', webBook]]) {
  assert(source.includes('RuleExecutionService'), `${name} flow must use RuleExecutionService`);
  assert(!source.includes('fallback legacy'), `${name} flow reintroduced a synchronous legacy fallback`);
}
assert(!search.includes('analyzeSearchField('),
  'Search must not parse result fields one-by-one on the UI thread');
assert(!explore.includes('analyzeExploreFieldBatch'),
  'Explore must not use its legacy field-batch parser');
assert((webBook.match(/RuleExecutionService\.get\(\)\.executeBatch/g) || []).length >= 5,
  'Book detail, catalogue and content parsing must use the unified execution entry');

assert(stageRuntime.includes('quarantineController') && stageRuntime.includes('this.controllers = this.controllers.filter'),
  'A timed-out Web runtime must be quarantined instead of reused');
assert(stageRuntime.includes('setResetHandler') && index.includes('resetStageRuntimeHost'),
  'The hidden Stage Web host must be rebuilt after a runtime timeout');

assert(preprocessor.includes('@Concurrent') && preprocessor.includes('taskpool.execute'),
  'Reader replacement rules must execute in TaskPool');
assert(preprocessor.includes('pattern.length > 4096') && preprocessor.includes('Nested unbounded quantifiers'),
  'Imported replacement rules must have basic regex abuse guards');
assert(reader.includes('ReaderContentPreprocessor.apply'),
  'Reader content must pass through the asynchronous preprocessor');
assert(reader.includes('await this.appendReaderPaginationBatch(result, chapterIndex, imageOnlyPagination ? 8 : 1,'),
  'Background pagination must be bounded to one text page or a small pure-image batch');
assert(reader.includes('await ReaderV2Paginator.appendPageAsync(session, isCurrent)') &&
  paginator.includes('await pending.paragraph.layout(pending.width)'),
  'Paged text must await native asynchronous layout and reject stale work');
assert(paginator.includes('breakStrategy: graphicsText.BreakStrategy.GREEDY'),
  'Native paragraph measurement must use the bounded greedy line-break strategy');
assert(reader.includes('batchElapsedMs') && reader.includes('adaptiveDelay'),
  'Background pagination must monitor cost and adapt its scheduling delay');
assert(reader.includes("'下拉加载上一章'") && reader.includes("'上滑加载下一章'"),
  'Continuous reading must expose both chapter-boundary pull hints');
assert(reader.includes('runReaderComicChapterTransition') &&
  reader.includes('readerComicChapterTransitionOpacity'),
  'Continuous chapter switches must keep an explicit content transition');
assert(reader.includes('schedulePreviousChapterPaginationCompletion') &&
  reader.includes('scheduleNextChapterPaginationCompletion'),
  'Both adjacent chapters must be fully pre-paginated before a boundary switch');

console.log('Thread-blocking gate passed: rule isolation, cancellation, TaskPool preprocessing, ' +
  'Web quarantine, bounded pagination and continuous chapter handoff are all connected.');
