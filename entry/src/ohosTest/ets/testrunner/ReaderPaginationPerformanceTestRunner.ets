import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { ReaderV2DocumentParser } from '../../../main/ets/core/reader/ReaderV2Document';
import { ReaderV2LayoutInput, ReaderV2LayoutSnapshot } from '../../../main/ets/core/reader/ReaderV2LayoutSnapshot';
import { ReaderV2Paginator } from '../../../main/ets/core/reader/ReaderV2Paginator';
import { ReaderV2PageLayout } from '../../../main/ets/core/reader/ReaderV2PageLayout';

/** Deterministic native-layout fixtures; never opens the production database or changes preferences. */
export default class ReaderPaginationPerformanceTestRunner implements TestRunner {
  onPrepare(): void {}

  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    try {
      const prose = '窗外微风轻轻吹过，阅读时每一个字符都应保持原来的位置。标点、ABC 123、emoji😀与换行。';
      const sources: string[] = [
        Array.from({ length: 40 }, (_item: Object, index: number): string => `${index} ${prose.repeat(3)}`).join('\n'),
        prose.repeat(160),
        Array.from({ length: 120 }, (_item: Object, index: number): string => `${index} ${prose}`).join('\n')
      ];
      for (let round = 0; round < 3; round++) {
      for (let fixture = 0; fixture < sources.length; fixture++) {
        for (const columns of [1, 2]) {
          const input = new ReaderV2LayoutInput();
          input.viewportWidthPx = 1648; input.viewportHeightPx = 1236;
          input.columnCount = columns; input.columnGapPx = 24;
          input.marginLeftPx = 32; input.marginRightPx = 32;
          input.marginTopPx = 32; input.marginBottomPx = 32;
          input.fontSizePx = 32; input.lineSpacingPx = 8; input.paragraphSpacingPx = 10;
          const document = ReaderV2DocumentParser.parse(sources[fixture], fixture, '');
          let lastTick = Date.now();
          let syncGap = 0;
          const syncTimer = setInterval((): void => {
            const now = Date.now(); syncGap = Math.max(syncGap, now - lastTick); lastTick = now;
          }, 1);
          await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 16); });
          const start = Date.now();
          const pages = ReaderV2Paginator.paginate(document, ReaderV2LayoutSnapshot.create(input));
          const syncMs = Date.now() - start;
          await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 16); });
          clearInterval(syncTimer);
          if (!pages.complete || pages.pages.length < 2) throw new Error('Fixture did not paginate');
          const boundaries = pages.pages.map((page: ReaderV2PageLayout): string => `${page.displayStart}:${page.displayEnd}`).join(',');
          await delegator.print(`READER_BASELINE round=${round} fixture=${fixture} columns=${columns} pages=${pages.pages.length} ` +
            `totalMs=${syncMs} eventLoopMaxGapMs=${syncGap} boundaries=${boundaries}\n`);
          const session = ReaderV2Paginator.start(document, ReaderV2LayoutSnapshot.create(input));
          const cpuMax: Map<string, number> = new Map<string, number>();
          ReaderV2Paginator.onWorkMeasured = (stage: string, elapsedMs: number): void => {
            cpuMax.set(stage, Math.max(cpuMax.get(stage) ?? 0, elapsedMs));
          };
          let asyncGap = 0;
          lastTick = Date.now();
          const asyncTimer = setInterval((): void => {
            const now = Date.now(); asyncGap = Math.max(asyncGap, now - lastTick); lastTick = now;
          }, 1);
          const asyncStart = Date.now();
          let firstPageMs = 0;
          try {
            while (!session.pageSet.complete) {
              await ReaderV2Paginator.appendPageAsync(session);
              if (!firstPageMs) firstPageMs = Date.now() - asyncStart;
            }
          } finally { clearInterval(asyncTimer); ReaderV2Paginator.onWorkMeasured = null; }
          const actual = session.pageSet.pages.map((page: ReaderV2PageLayout): string =>
            `${page.displayStart}:${page.displayEnd}`).join(',');
          if (actual !== boundaries) throw new Error('Async native layout changed page boundaries');
          for (let index = 0; index < pages.pages.length; index++) {
            if (session.pageSet.pages[index].selectionText !== pages.pages[index].selectionText) {
              throw new Error('Async native layout changed selectable text');
            }
          }
          await delegator.print(`READER_ASYNC round=${round} fixture=${fixture} columns=${columns} pages=${session.pageSet.pages.length} ` +
            `totalMs=${Date.now() - asyncStart} firstPageMs=${firstPageMs} eventLoopMaxGapMs=${asyncGap} ` +
            `cpuMax=${JSON.stringify(Array.from(cpuMax.entries()))} parity=true\n`);
          await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 16); });
        }
      }
      }
      await delegator.finishTest('PASS ReaderPaginationPerformance', 0);
    } catch (error) {
      await delegator.finishTest(`FAIL ReaderPaginationPerformance: ${(error as Error).message}`, -1);
    }
  }
}
