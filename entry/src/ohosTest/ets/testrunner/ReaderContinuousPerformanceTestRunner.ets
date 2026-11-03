import { TestRunner, abilityDelegatorRegistry } from '@kit.TestKit';
import { ReaderV2DocumentParser } from '../../../main/ets/core/reader/ReaderV2Document';
import { ReaderV2LayoutInput, ReaderV2LayoutSnapshot } from '../../../main/ets/core/reader/ReaderV2LayoutSnapshot';
import { ReaderV2Paginator } from '../../../main/ets/core/reader/ReaderV2Paginator';
import { ReaderV2PageLayout, ReaderV2PageFragment } from '../../../main/ets/core/reader/ReaderV2PageLayout';

/** Native scrolling-chunk parity and event-loop responsiveness; independent of user books and preferences. */
export default class ReaderContinuousPerformanceTestRunner implements TestRunner {
  onPrepare(): void {}

  private geometry(page: ReaderV2PageLayout | null): string {
    if (!page) return '';
    return `${page.contentBottomPx}|${page.selectionText}|` + page.fragments.map((fragment: ReaderV2PageFragment): string =>
      `${fragment.displayStart}:${fragment.displayEnd}:${fragment.paragraphX}:${fragment.paragraphY}:` +
      `${fragment.paragraphHeight}:${fragment.localStart}:${fragment.localEnd}`).join('|');
  }

  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    try {
      const prose = '阅读时每一个字符都应保持原来的位置，标点、ABC 123、emoji😀与换行。';
      const fixtures: string[] = [prose.repeat(48),
        Array.from({ length: 32 }, (_item: Object, index: number): string => `${index} ${prose}`).join('\n')];
      for (let round = 0; round < 3; round++) {
        for (let fixture = 0; fixture < fixtures.length; fixture++) {
          for (const width of [540, 1648]) {
            const input = new ReaderV2LayoutInput();
            input.viewportWidthPx = width; input.viewportHeightPx = 1236;
            input.fontSizePx = 32; input.lineSpacingPx = 8; input.paragraphSpacingPx = 10;
            input.marginLeftPx = 32; input.marginRightPx = 32;
            const snapshot = ReaderV2LayoutSnapshot.create(input);
            const document = ReaderV2DocumentParser.parse(fixtures[fixture], fixture, '');
            let last = Date.now(); let gap = 0;
            const timer = setInterval((): void => {
              const now = Date.now(); gap = Math.max(gap, now - last); last = now;
            }, 1);
            let baseline: ReaderV2PageLayout | null = null;
            let actual: ReaderV2PageLayout | null = null;
            let syncMs = 0; let asyncMs = 0; let syncGap = 0;
            try {
              await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 16); });
              const syncStart = Date.now();
              baseline = ReaderV2Paginator.layoutContinuous(document, snapshot);
              syncMs = Date.now() - syncStart;
              await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 16); });
              syncGap = gap; gap = 0; last = Date.now();
              const asyncStart = Date.now();
              actual = await ReaderV2Paginator.layoutContinuousAsync(document, snapshot);
              asyncMs = Date.now() - asyncStart;
              await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 16); });
            } finally { clearInterval(timer); }
            if (!actual || this.geometry(actual) !== this.geometry(baseline)) {
              throw new Error(`Continuous geometry/selection mismatch fixture=${fixture} width=${width}`);
            }
            await delegator.print(`READER_CONTINUOUS round=${round} fixture=${fixture} width=${width} ` +
              `syncMs=${syncMs} asyncMs=${asyncMs} syncMaxGapMs=${syncGap} asyncMaxGapMs=${gap} parity=true\n`);
          }
        }
      }
      await delegator.finishTest('PASS ReaderContinuousPerformance', 0);
    } catch (error) {
      await delegator.finishTest(`FAIL ReaderContinuousPerformance: ${(error as Error).message}`, -1);
    }
  }
}
