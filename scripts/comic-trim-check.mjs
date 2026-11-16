import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { ComicTrimRect, ReaderComicTrimDetect } from '../entry/src/main/ets/core/reader/ReaderComicTrimDetect.ts';
import { readEtsModule } from './lib/ets-module-staging.mjs';

function page(width, height, background) {
  const pixels = new Uint8Array(width * height * 4);
  for (let i = 0; i < pixels.length; i += 4) {
    pixels[i] = background[0];
    pixels[i + 1] = background[1];
    pixels[i + 2] = background[2];
    pixels[i + 3] = 255;
  }
  return { width, height, pixels };
}

function fill(img, x0, y0, x1, y1, color) {
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      const i = (y * img.width + x) * 4;
      img.pixels[i] = color[0];
      img.pixels[i + 1] = color[1];
      img.pixels[i + 2] = color[2];
    }
  }
}

/** 一格分镜：粗黑框加一块彩色画面。 */
function panel(img, x0, y0, x1, y1) {
  fill(img, x0, y0, x1, y1, [20, 20, 20]);
  fill(img, x0 + 2, y0 + 2, x1 - 2, y1 - 2, [230, 150, 90]);
}

function noise(img, amount, seed = 7) {
  let state = seed;
  for (let i = 0; i < img.pixels.length; i += 4) {
    for (let c = 0; c < 3; c++) {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      const delta = (state % (amount * 2 + 1)) - amount;
      img.pixels[i + c] = Math.max(0, Math.min(255, img.pixels[i + c] + delta));
    }
  }
}

const detect = (img) => ReaderComicTrimDetect.detect(img.pixels, img.width, img.height);
const near = (actual, expected, label) =>
  assert.ok(Math.abs(actual - expected) < 0.004, `${label}: expected ${expected.toFixed(4)}, got ${actual.toFixed(4)}`);

// 白边：四边按空白宽度往回留一个采样像素。
{
  const img = page(300, 420, [255, 255, 255]);
  panel(img, 20, 15, 280, 200);
  panel(img, 20, 210, 280, 400);
  const rect = detect(img);
  assert.ok(rect, 'white margins should be trimmed');
  near(rect.left, 19 / 300, 'left');
  near(rect.right, 19 / 300, 'right');
  near(rect.top, 14 / 420, 'top');
  near(rect.bottom, 19 / 420, 'bottom');
}

// 黑边同样裁；纸色偏黄、带 JPEG 杂色也能认出底色。
{
  const img = page(300, 420, [0, 0, 0]);
  fill(img, 30, 30, 270, 390, [200, 120, 60]);
  const rect = detect(img);
  assert.ok(rect, 'black margins should be trimmed');
  near(rect.left, 29 / 300, 'black left');
  near(rect.top, 29 / 420, 'black top');
}
{
  const img = page(300, 420, [238, 232, 214]);
  panel(img, 24, 18, 276, 402);
  noise(img, 14);
  const rect = detect(img);
  assert.ok(rect, 'noisy off-white paper should still be detected');
  near(rect.left, 23 / 300, 'noisy left');
  near(rect.bottom, 17 / 420, 'noisy bottom');
}

// 页角水印压在下边距和右边距里：跳过水印裁下边，右边按画框裁，不被水印挡住。
{
  const img = page(300, 420, [255, 255, 255]);
  panel(img, 20, 15, 280, 400);
  fill(img, 240, 408, 292, 415, [120, 120, 120]);
  const rect = detect(img);
  assert.ok(rect, 'watermarked page should be trimmed');
  near(rect.bottom, 19 / 420, 'bottom skips the watermark and the gap above it');
  near(rect.right, 19 / 300, 'right follows the panel, not the watermark');
}

// 紧贴画框的一段内容太厚或太密就不是水印，不跳过。
{
  const img = page(300, 420, [255, 255, 255]);
  panel(img, 20, 15, 280, 380);
  fill(img, 20, 386, 280, 412, [40, 40, 40]);
  const rect = detect(img);
  assert.ok(rect);
  near(rect.bottom, 7 / 420, 'a dense caption band is kept');
}

// 满版彩图、彩色底、几乎全空的过场页都不裁。
{
  const img = page(300, 420, [90, 160, 220]);
  fill(img, 40, 40, 260, 380, [250, 250, 250]);
  assert.equal(detect(img), null, 'colored backgrounds are not margins');
}
{
  const img = page(300, 420, [255, 255, 255]);
  fill(img, 0, 0, 300, 420, [200, 100, 50]);
  fill(img, 0, 0, 3, 3, [255, 255, 255]);
  assert.equal(detect(img), null, 'full-bleed art is not trimmed');
}
{
  const img = page(300, 420, [255, 255, 255]);
  fill(img, 120, 190, 180, 220, [0, 0, 0]);
  assert.equal(detect(img), null, 'a mostly blank title page is not zoomed in');
}

// 窄边不到 1% 不裁，单边最多 20%。
{
  const img = page(300, 420, [255, 255, 255]);
  panel(img, 2, 2, 298, 418);
  assert.equal(detect(img), null, 'sub-1% margins are ignored');
}
{
  const img = page(300, 420, [255, 255, 255]);
  panel(img, 75, 2, 298, 418);
  const rect = detect(img);
  assert.ok(rect);
  assert.equal(rect.left, ReaderComicTrimDetect.MAX_SIDE, 'one side is capped');
}

// 缩小解码尺寸：宽不超过 320、总像素不超过 60 万。
assert.deepEqual(ReaderComicTrimDetect.sampleSize(1000, 1400), [320, 448]);
const strip = ReaderComicTrimDetect.sampleSize(800, 12000);
assert.ok(strip[0] * strip[1] <= 600000 * 1.01 && strip[0] <= 320, `long strip sample ${strip}`);
assert.deepEqual(ReaderComicTrimDetect.sampleSize(200, 300), [200, 300]);

// 图片项的裁剪排版：取图片项的生产代码（去掉 ArkUI 的 build），核对显示比例、整图尺寸与平移。
{
  const context = vm.createContext({ console, vp2px: x => x, px2vp: x => x, ComicTrimRect,
    ReaderComicProcessing: { owner: () => 1 },
    ReaderComicTrimMode: { OFF: 'off', SIDES: 'sides', ALL: 'all', normalize: v => v },
    ImageFit: { Contain: 'contain', Fill: 'fill' } });
  let body = readEtsModule('components/reader/ReaderComicView.ets').split('export struct ReaderComicImageItem {')[1]
    .split('\n  build() {')[0];
  body = body.replace(/@(StorageProp|Prop|State|Watch)(\([^)]*\))?\s*/g, '');
  vm.runInContext(stripTypeScriptTypes(`class ComicItem {${body}\n}`), context);
  const Item = vm.runInContext('ComicItem', context);
  const close = (actual, expected, label) => assert.ok(Math.abs(actual - expected) < 1e-6, `${label}: ${actual} vs ${expected}`);

  // 条漫：宽 300 的视图，原图高宽比 1.4，左右各裁 10%、上 5% 下 15%。
  const item = new Item();
  Object.assign(item, { viewWidth: 300, viewHeight: 600, ratio: 1.4, trimMode: 'all',
    trimRect: new ComicTrimRect(0.1, 0.05, 0.1, 0.15) });
  close(item.viewRatio(), 1.4 * 0.8 / 0.8, 'cropped ratio');
  close(item.fullWidth(), 300 / 0.8, 'full image is wider than the view');
  close(item.fullHeight(), item.imageHeight() / 0.8, 'full image is taller than the frame');
  close(item.layerShiftX(), 0, 'symmetric side crop needs no horizontal shift');
  close(item.layerShiftY(), item.fullHeight() * (0.15 - 0.05) / 2, 'top-left of the crop lands at the frame origin');
  assert.equal(item.layerFit(true), 'fill');

  // 只裁左右、长条图都不动上下。
  item.trimMode = 'sides';
  assert.deepEqual([...item.activeCut()], [0.1, 0, 0.1, 0]);
  item.trimMode = 'all';
  item.ratio = 3;
  assert.deepEqual([...item.activeCut()], [0.1, 0, 0.1, 0], 'long strips keep their top and bottom');

  // 翻页框里：两页取较少的上下裁剪，缩放一致。
  const merged = Item.mergeTrim(new ComicTrimRect(0.05, 0.04, 0.06, 0.1), new ComicTrimRect(0.08, 0.06, 0.02, 0.03), true);
  assert.deepEqual([merged.left, merged.top, merged.right, merged.bottom], [0.05, 0.04, 0.06, 0.03]);
  assert.equal(Item.mergeTrim(new ComicTrimRect(0, 0.04, 0, 0.1), null, true), null,
    'a partner without margins cancels vertical crop');
  const boxed = new Item();
  Object.assign(boxed, { boxWidth: 450, boxHeight: 500, ratio: 1.5, trimMode: 'all',
    trimRect: new ComicTrimRect(0, 0.1, 0, 0.1) });
  close(boxed.displayHeight(), 500, 'height-limited page fills the box after cropping');
  close(boxed.displayWidth(), 500 / 1.2, 'width follows the cropped ratio');
  close(boxed.fullHeight(), 500 / 0.8, 'full image overflows the box vertically');

  // 不裁时保持原来的排版。
  const plain = new Item();
  Object.assign(plain, { viewWidth: 300, viewHeight: 600, ratio: 1.4, trimMode: 'off', trimRect: null });
  assert.equal(plain.activeCut(), null);
  assert.equal(plain.layerWidth(), 300);
  assert.equal(plain.layerFit(true), 'contain');
}

console.log('comic-trim-check: ok');
