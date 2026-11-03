import { FrameCallback, UIContext } from '@ohos.arkui.UIContext';
import { image } from '@kit.ImageKit';
import Animator, { AnimatorResult } from '@ohos.animator';
import { ReaderV2DocumentParser } from '../../../main/ets/core/reader/ReaderV2Document';
import { ReaderV2LayoutInput, ReaderV2LayoutSnapshot } from '../../../main/ets/core/reader/ReaderV2LayoutSnapshot';
import { ReaderV2PageSet } from '../../../main/ets/core/reader/ReaderV2PageLayout';
import { ReaderV2Paginator } from '../../../main/ets/core/reader/ReaderV2Paginator';
import { ReaderV2SpanStyleRange } from '../../../main/ets/core/reader/ReaderV2Style';
import { ReaderV2PageNodeController } from '../../../main/ets/core/reader/ReaderV2RenderNode';
import { ReaderRenderFrame } from '../../../main/ets/core/reader/ReaderRenderFrame';
import { ReaderPageTextureCache, ReaderPageTextureLease } from '../../../main/ets/core/reader/ReaderPageTextureCache';
import { ReaderPageTexturePair } from '../../../main/ets/core/reader/ReaderPageTexturePair';
import { ReaderPageCurlPainter } from '../../../main/ets/components/ReaderPageCurlPainter';
import { ReaderEmulationFlipPainter, ReaderEmulationFlipRegion } from '../../../main/ets/components/ReaderEmulationFlipPainter';

class ReaderPagingFrameSampler extends FrameCallback {
  intervals: number[] = [];
  running: boolean = true;
  private previous: number = 0;
  private ui: UIContext;
  constructor(ui: UIContext) { super(); this.ui = ui; }
  onFrame(timeInNano: number): void {
    if (!this.running) return;
    if (this.previous > 0) this.intervals.push((timeInNano - this.previous) / 1000000);
    this.previous = timeInNano;
    this.ui.postFrameCallback(this);
  }
}

/** Uses real Paragraphs, retained nodes, snapshots and both production painters, with no user books/settings. */
@Entry
@Component
struct ReaderPagingPerformanceTest {
  @State status: string = 'Preparing reader performance fixtures';
  @State canvasShown: boolean = false;
  @State pageOffset: number = 0;
  @State hostIdentity: string = 'reader_perf_initial';
  @State incomingHostIdentity: string = 'reader_perf_incoming_initial';
  private controller: ReaderV2PageNodeController = new ReaderV2PageNodeController();
  private incoming: ReaderV2PageNodeController = new ReaderV2PageNodeController();
  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private curl: ReaderPageCurlPainter = new ReaderPageCurlPainter();
  private fold: ReaderEmulationFlipPainter = new ReaderEmulationFlipPainter();
  private widthVp: number = 0;
  private heightVp: number = 0;
  private canvasReady: boolean = false;
  private started: boolean = false;
  private alive: boolean = true;
  private animator: AnimatorResult | null = null;
  private sampler: ReaderPagingFrameSampler | null = null;

  aboutToDisappear(): void { this.alive = false; this.animator?.cancel(); if (this.sampler) this.sampler.running = false; }

  private startIfReady(): void {
    if (this.started || !this.canvasReady || this.widthVp <= 0 || this.heightVp <= 0) return;
    this.started = true;
    this.run().catch((error: Error): void => {
      AppStorage.setOrCreate('readerPagingTestResult', `FAIL ${error.message}`);
      this.status = `FAIL ${error.message}`;
    });
  }

  private async snapshot(scale: number = 0.42, surface: string = 'reader_perf_surface'): Promise<image.PixelMap> {
    await ReaderRenderFrame.wait(this.getUIContext());
    return this.getUIContext().getComponentSnapshot().get(surface, {
      scale: scale, waitUntilRenderFinished: true
    });
  }

  private async checksum(bitmap: image.PixelMap): Promise<number> {
    const bytes = new ArrayBuffer(bitmap.getPixelBytesNumber());
    await bitmap.readPixelsToBuffer(bytes);
    const pixels = new Uint8Array(bytes);
    let sum = 0;
    for (let i = 0; i < pixels.length; i += 97) sum = (sum * 31 + pixels[i]) & 0x7fffffff;
    return sum;
  }

  private percentile(values: number[], ratio: number): number {
    const ordered = values.slice().sort((a: number, b: number): number => a - b);
    return ordered.length > 0 ? ordered[Math.min(ordered.length - 1, Math.floor(ordered.length * ratio))] : 0;
  }

  private async checkOpaquePaper(): Promise<void> {
    const transparent = await image.createPixelMap(new ArrayBuffer(64 * 64 * 4), {
      size: { width: 64, height: 64 }, pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.UNPREMUL
    });
    try {
      for (const dark of [false, true]) {
        for (const direction of [1, -1]) {
          const painter = new ReaderEmulationFlipPainter();
          painter.dragCorner(120, 120);
          painter.draw(this.canvas, transparent, null, 240, 240, 0.5, direction,
            ReaderEmulationFlipRegion.MIDDLE, false, 240, 0, 1,
            dark ? '#40101826' : '#80F5F0E6', dark);
          const flat = this.canvas.getImageData(direction > 0 ? 20 : 220, 120, 1, 1).data;
          const back = this.canvas.getImageData(direction > 0 ? 150 : 90, 120, 1, 1).data;
          const expected = dark ? [16, 24, 38] : [245, 240, 230];
          if (flat[3] !== 255 || back[3] !== 255 ||
            expected.some((value: number, index: number): boolean => Math.abs(flat[index] - value) > 1)) {
            throw new Error(`3D paper is translucent dark=${dark} direction=${direction} ` +
              `frontAlpha=${flat[3]} backAlpha=${back[3]}`);
          }
        }
      }
    } finally { await transparent.release(); }
  }

  private async compareHostBinding(pages: ReaderV2PageSet, checksums: number[]): Promise<string> {
    let created = 0;
    ReaderV2PageNodeController.onNodeCreated = (): void => { created++; };
    const counts: number[] = [];
    try {
      for (const mode of [0, 1]) {
        const start = created;
        for (let turn = 0; turn < 40; turn++) {
          const index = turn % 2;
          const host = `reader_perf_host_${mode}_${turn}`;
          if (mode === 0) this.controller.updatePage(pages.pages[index]);
          else this.controller.bindPageToHost(pages.pages[index], host);
          this.hostIdentity = host;
          await ReaderRenderFrame.wait(this.getUIContext());
          if (turn === 0 || turn === 39) {
            const bitmap = await this.snapshot();
            try {
              if (await this.checksum(bitmap) !== checksums[index]) throw new Error('Bound page did not advance');
            } finally { await bitmap.release(); }
          }
        }
        counts.push(created - start);
      }
      if (counts[1] > counts[0] * 0.75) throw new Error('Host binding did not reduce native node creation');
      const beforeRepair = created;
      // Deliberately retain the declarative host: verify the compatibility fallback still republishes its page.
      this.controller.bindPageToHost(pages.pages[0], 'reader_perf_retained_host');
      await ReaderRenderFrame.wait(this.getUIContext());
      const repaired = await this.snapshot();
      try {
        if (await this.checksum(repaired) !== checksums[0]) throw new Error('Retained-host repair failed');
      } finally { await repaired.release(); }
      return `baselineNodes=${counts[0]} boundNodes=${counts[1]} repairNodes=${created - beforeRepair}`;
    } finally { ReaderV2PageNodeController.onNodeCreated = null; }
  }

  private async compareLeafCapture(scale: number): Promise<string> {
    const baselineTimes: number[] = [];
    const pairedTimes: number[] = [];
    const crop = async (bitmap: image.PixelMap, direction: number): Promise<void> => {
      const info = await bitmap.getImageInfo();
      const half = Math.floor(info.size.width / 2);
      await bitmap.crop({ x: direction > 0 ? info.size.width - half : 0, y: 0,
        size: { width: half, height: info.size.height } });
    };
    for (let round = 0; round < 3; round++) {
      const start = Date.now();
      const right = await this.snapshot(scale);
      await crop(right, 1);
      const left = await this.snapshot(scale);
      await crop(left, -1);
      baselineTimes.push(Date.now() - start);
      let pair: ReaderPageTexturePair | null = null;
      try {
        const pairedStart = Date.now();
        pair = await ReaderPageTexturePair.capture((): Promise<image.PixelMap> => this.snapshot(scale), crop);
        pairedTimes.push(Date.now() - pairedStart);
        if (await this.checksum(pair.right) !== await this.checksum(right) ||
          await this.checksum(pair.left) !== await this.checksum(left)) throw new Error('Paired leaf pixels changed');
      } finally {
        pair?.release(); await right.release(); await left.release();
      }
    }
    return `scale=${scale} baselinePairMs=${JSON.stringify(baselineTimes)} pairedMs=${JSON.stringify(pairedTimes)}`;
  }

  private async checkIncomingHandoff(pages: ReaderV2PageSet, checksums: number[]): Promise<void> {
    // Keep the animation branch mounted while destinations are superseded before the next render frame.
    // Inspect the destination itself, rather than the footer or the settled foreground page.
    this.pageOffset = this.widthVp;
    try {
      for (let turn = 0; turn < 24; turn++) {
        let index = 0;
        for (let queued = 0; queued < 3; queued++) {
          index = (turn + queued) % 2;
          this.incoming.updatePage(pages.pages[index]);
          this.incomingHostIdentity = `incoming_${Math.floor(turn / 8)}_${index}_${turn}_${queued}`;
        }
        const bitmap = await this.snapshot(0.42, 'reader_perf_incoming');
        try {
          if (await this.checksum(bitmap) !== checksums[index]) {
            throw new Error(`Incoming page stayed stale at queued handoff ${turn}`);
          }
        } finally { await bitmap.release(); }
      }
    } finally { this.pageOffset = 0; }
  }

  private async animate(mode: number, front: image.PixelMap, back: image.PixelMap,
    doublePage: boolean = false, highRefresh: boolean = false): Promise<string> {
    const samples: number[] = [];
    const cpu: number[] = [];
    let previous = 0;
    this.sampler = new ReaderPagingFrameSampler(this.getUIContext());
    this.getUIContext().postFrameCallback(this.sampler);
    for (let turn = 0; turn < 4 && this.alive; turn++) {
      await new Promise<void>((resolve: () => void): void => {
        const animation = Animator.create({ duration: 340, easing: 'linear', delay: 0, fill: 'forwards',
          direction: 'normal', iterations: 1, begin: 0, end: 1 });
        if (highRefresh) animation.setExpectedFrameRateRange({ min: 60, max: 120, expected: 120 });
        this.animator = animation;
        animation.onFrame = (progress: number): void => {
          const now = Date.now();
          if (previous > 0) samples.push(now - previous);
          previous = now;
          const startedAt = Date.now();
          if (mode === 0) {
            this.curl.draw(this.canvas, front, back, this.widthVp, this.heightVp, progress, 1, doublePage, false,
              this.widthVp / 2, this.widthVp / 2);
          } else {
            this.fold.draw(this.canvas, front, null, this.widthVp, this.heightVp, progress, 1,
              ReaderEmulationFlipRegion.BOTTOM, doublePage, this.widthVp / 2, this.widthVp / 2,
              1 / this.getUIContext().vp2px(1), '#FFFFFF', false);
          }
          cpu.push(Date.now() - startedAt);
        };
        animation.onFinish = resolve; animation.onCancel = resolve;
        animation.play();
      });
    }
    this.sampler.running = false;
    const maximum = cpu.reduce((max: number, value: number): number => Math.max(max, value), 0);
    return `mode=${mode} double=${doublePage} highRefresh=${highRefresh} drawP95Ms=${this.percentile(cpu, 0.95)} drawMaxMs=${maximum} ` +
      `animatorP95Ms=${this.percentile(samples, 0.95)} frameCallbackP95Ms=${this.percentile(this.sampler.intervals, 0.95)}`;
  }

  private async slide(pages: ReaderV2PageSet): Promise<number> {
    this.sampler = new ReaderPagingFrameSampler(this.getUIContext());
    this.getUIContext().postFrameCallback(this.sampler);
    try {
      for (let turn = 0; turn < 12 && this.alive; turn++) {
        this.incoming.updatePage(pages.pages[(turn + 1) % pages.pages.length]);
        await new Promise<void>((resolve: () => void): void => {
          this.getUIContext().animateTo({ duration: 220, curve: Curve.Linear, onFinish: resolve }, (): void => {
            this.pageOffset = -this.widthVp;
          });
        });
        this.controller.updatePage(pages.pages[(turn + 1) % pages.pages.length]);
        this.pageOffset = 0;
        await ReaderRenderFrame.wait(this.getUIContext());
      }
      return this.percentile(this.sampler.intervals, 0.95);
    } finally { this.sampler.running = false; }
  }

  private async run(): Promise<void> {
    const input = new ReaderV2LayoutInput();
    input.viewportWidthPx = this.getUIContext().vp2px(this.widthVp);
    input.viewportHeightPx = this.getUIContext().vp2px(this.heightVp);
    input.fontSizePx = 64; input.lineSpacingPx = 14; input.paragraphSpacingPx = 18;
    const prose = Array.from({ length: 100 }, (_item: Object, i: number): string =>
      `段落${i} 阅读翻页测试，字形、标点与位置需要保持一致。ABC 123 😀。`.repeat(3)).join('\n');
    const document = ReaderV2DocumentParser.parse(prose, 0, '');
    const styles: ReaderV2SpanStyleRange[] = [];
    for (const block of document.blocks) {
      const style = new ReaderV2SpanStyleRange(block.displayStart + 4, Math.min(block.displayEnd, block.displayStart + 16));
      style.decorationEnabled = true; style.decorationStyleId = 'crimson-stamp'; style.decorationSizePx = 20;
      style.backgroundColor = 0xFFFFE8D0; style.color = 0xFF202124;
      style.shadowEnabled = true; style.shadowRadiusPx = 3; style.shadowColor = 0x55000000;
      style.radiusTopLeftPx = 8; style.radiusTopRightPx = 8;
      style.radiusBottomLeftPx = 8; style.radiusBottomRightPx = 8;
      styles.push(style);
    }
    const session = ReaderV2Paginator.start(document, ReaderV2LayoutSnapshot.create(input), styles);
    while (!session.pageSet.complete && this.alive) await ReaderV2Paginator.appendPageAsync(session);
    const pages: ReaderV2PageSet = session.pageSet;
    if (!this.alive || pages.pages.length < 2) throw new Error('Test page has no usable layout');
    this.controller.updatePage(pages.pages[0]);
    const captureStart = Date.now();
    const front = await this.snapshot();
    const captureMs = Date.now() - captureStart;
    this.controller.updatePage(pages.pages[1]);
    const back = await this.snapshot();
    const cache = new ReaderPageTextureCache();
    let activeLease: ReaderPageTextureLease | null = null;
    let doubleFront: image.PixelMap | null = null;
    let highFront: image.PixelMap | null = null;
    let doubleHigh: image.PixelMap | null = null;
    try {
      const frontChecksum = await this.checksum(front);
      const backChecksum = await this.checksum(back);
      if (frontChecksum === backChecksum) throw new Error('Retained node did not advance');
      const hostBinding = await this.compareHostBinding(pages, [frontChecksum, backChecksum]);
      await this.checkIncomingHandoff(pages, [frontChecksum, backChecksum]);
      const pairedCapture = await this.compareLeafCapture(0.42);
      const pairedHighCapture = await this.compareLeafCapture(0.75);
      const updateTimes: number[] = [];
      for (let turn = 0; turn < 100 && this.alive; turn++) {
        const startedAt = Date.now(); this.controller.updatePage(pages.pages[turn % pages.pages.length]);
        await ReaderRenderFrame.wait(this.getUIContext());
        updateTimes.push(Date.now() - startedAt);
      }
      const slideFrameP95Ms = await this.slide(pages);
      const info = await front.getImageInfo();
      activeLease = cache.put('front', front, info.size.width * info.size.height * 4);
      const cacheStart = Date.now();
      const reused = cache.acquire('front');
      if (!reused || reused.bitmap !== front) throw new Error('Snapshot cache missed the prepared frame');
      const cacheMs = Date.now() - cacheStart; reused.release();
      this.canvasShown = true;
      await this.checkOpaquePaper();
      const curl = await this.animate(0, front, back);
      highFront = await this.snapshot(0.75);
      const fold = await this.animate(1, highFront, back);
      doubleFront = await this.snapshot();
      const doubleInfo = await doubleFront.getImageInfo();
      const half = Math.floor(doubleInfo.size.width / 2);
      await doubleFront.crop({ x: doubleInfo.size.width - half, y: 0,
        size: { width: half, height: doubleInfo.size.height } });
      const doubleCurl = await this.animate(0, doubleFront, back, true);
      doubleHigh = await this.snapshot(0.75);
      const highInfo = await doubleHigh.getImageInfo();
      const highHalf = Math.floor(highInfo.size.width / 2);
      await doubleHigh.crop({ x: highInfo.size.width - highHalf, y: 0,
        size: { width: highHalf, height: highInfo.size.height } });
      const doubleFold = await this.animate(1, doubleHigh, back, true);
      const highRefreshCurl = await this.animate(0, front, back, false, true);
      const highRefreshFold = await this.animate(1, highFront, back, false, true);
      this.canvasShown = false;
      const result = `PASS READER_UI updateP95Ms=${this.percentile(updateTimes, 0.95)} ` +
        `slideFrameP95Ms=${slideFrameP95Ms} captureMs=${captureMs} cacheAcquireMs=${cacheMs} ` +
        `opaquePaper=true incomingHandoffs=24 ${hostBinding} ${pairedCapture} ${pairedHighCapture} ${curl} ${fold} ${doubleCurl} ${doubleFold} ` +
        `${highRefreshCurl} ${highRefreshFold}`;
      this.status = result;
      AppStorage.setOrCreate('readerPagingTestResult', result);
    } finally {
      cache.clear();
      if (activeLease) activeLease.release(); else await front.release();
      if (doubleFront) await doubleFront.release();
      if (highFront) await highFront.release();
      if (doubleHigh) await doubleHigh.release();
      await back.release();
    }
  }

  build() {
    Column() {
      Text(this.status).fontSize(14).id('reader_perf_status')
      Stack() {
        ForEach([this.incomingHostIdentity], (_incomingHost: string) => {
          NodeContainer(this.incoming).width('100%').height('100%').backgroundColor(Color.White)
            .id('reader_perf_incoming')
        }, (incomingHost: string) => incomingHost)
        ForEach([this.hostIdentity], (_host: string) => {
          NodeContainer(this.controller).width('100%').height('100%').id('reader_perf_surface')
            .backgroundColor(Color.White).translate({ x: this.pageOffset })
        }, (host: string) => host)
        Canvas(this.canvas).width('100%').height('100%').opacity(this.canvasShown ? 1 : 0)
          .onReady((): void => { this.canvasReady = true; this.startIfReady(); })
      }.width('100%').layoutWeight(1).onAreaChange((_old: Area, area: Area): void => {
        this.widthVp = Number(area.width); this.heightVp = Number(area.height); this.startIfReady();
      })
    }.width('100%').height('100%').backgroundColor(Color.White)
  }
}
