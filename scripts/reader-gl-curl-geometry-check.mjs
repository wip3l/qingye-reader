// GPU 仿真翻页的几何回归：按着色器同样的公式把纸上的点映射到屏幕，检查翻完、跟手、纸不拉长和松手连续。
import assert from 'node:assert/strict';
import { ReaderGlCurlGeometry } from '../entry/src/main/ets/core/reader/ReaderGlCurlGeometry.ts';

const W = 390;
const H = 844;
const TOP = ReaderGlCurlGeometry.REGION_TOP;
const MIDDLE = ReaderGlCurlGeometry.REGION_MIDDLE;
const BOTTOM = ReaderGlCurlGeometry.REGION_BOTTOM;

// 与 page_curl.cpp 顶点着色器相同：折线另一侧卷上圆柱，卷过半圈后平压回来。
function land(fold, x, y) {
  if (!fold.active) return { x, y, z: 0 };
  const d = (x - fold.p0x) * fold.nx + (y - fold.p0y) * fold.ny;
  if (d <= 0) return { x, y, z: 0 };
  const r = fold.radius;
  if (d < Math.PI * r) {
    const shift = r * Math.sin(d / r) - d;
    return { x: x + fold.nx * shift, y: y + fold.ny * shift, z: r * (1 - Math.cos(d / r)) };
  }
  const shift = -d - (d - Math.PI * r);
  return { x: x + fold.nx * shift, y: y + fold.ny * shift, z: 2 * r };
}

function landedExtent(fold) {
  let minX = Infinity;
  let maxX = -Infinity;
  for (let i = 0; i <= 40; i++) {
    for (let j = 0; j <= 80; j++) {
      const p = land(fold, (i / 40) * W, (j / 80) * H);
      minX = Math.min(minX, p.x);
      maxX = Math.max(maxX, p.x);
    }
  }
  // 弧面在屏幕上最远处是弧顶，比纸上的点映射还要多出约半径；按折线外侧 R 处计入。
  const crest = fold.p0x + fold.nx * fold.radius;
  return { minX: Math.min(minX, crest), maxX: Math.max(maxX, crest) };
}

const near = (a, b, eps, label) => assert(Math.abs(a - b) <= eps, `${label}: ${a} vs ${b}`);

// 平铺与点按翻页。
{
  const g = new ReaderGlCurlGeometry();
  assert.equal(g.fold(W, H, 0, 1, BOTTOM).active, false, 'progress 0 is the flat page');
  const half = g.fold(W, H, 0.5, 1, BOTTOM);
  assert.equal(half.active, true);
  assert(half.ny > 0, 'a tapped bottom-corner turn lifts the corner along an arc, so the fold leans');
  const done = g.fold(W, H, 1, 1, BOTTOM);
  assert(Math.abs(done.ny) < 1e-6, 'the fold stands upright at the end of a tapped turn');
  assert(landedExtent(done).maxX <= 0.5, 'a finished forward turn leaves nothing on screen');
  const back = g.fold(W, H, 1, -1, BOTTOM);
  assert(landedExtent(back).minX >= W - 0.5, 'a finished backward turn leaves nothing on screen');
  const backHalf = g.fold(W, H, 0.5, -1, BOTTOM);
  assert(backHalf.nx < 0, 'backward turns curl from the left edge');
}

// 拖动：页角落在手指下，往前翻也一样（镜像）。
for (const [direction, corner, finger] of [[1, { x: W, y: H }, { x: 120, y: 700 }],
  [-1, { x: 0, y: H }, { x: 260, y: 690 }], [1, { x: W, y: 0 }, { x: 150, y: 120 }]]) {
  const g = new ReaderGlCurlGeometry();
  g.dragCorner(finger.x, finger.y);
  const region = corner.y === 0 ? TOP : BOTTOM;
  const fold = g.fold(W, H, 0.5, direction, region);
  const p = land(fold, corner.x, corner.y);
  near(p.x, finger.x, 0.5, 'corner follows finger x');
  near(p.y, finger.y, 0.5, 'corner follows finger y');
}

// 纸不能被拉长：手指拖到很远，页角离书脊一侧页角的距离不超过页宽。
{
  const g = new ReaderGlCurlGeometry();
  g.dragCorner(-300, 200);
  const fold = g.fold(W, H, 0.9, 1, BOTTOM);
  const p = land(fold, W, H);
  assert(Math.hypot(p.x, p.y - H) <= W + 0.5, 'the page is never stretched past the spine corner');
}

// 中部起手：折线倾斜受限。
{
  const g = new ReaderGlCurlGeometry();
  g.dragCorner(330, 420);
  g.dragCorner(160, 80);
  const fold = g.fold(W, H, 0.5, 1, MIDDLE);
  assert(Math.abs(fold.ny / fold.nx) <= 0.42 + 1e-6, 'middle grabs tilt the fold only a little');
}

// 起手瞬间：手指刚动一点，纸从页角卷起一点点，不会整张跳到手指处。
{
  const g = new ReaderGlCurlGeometry();
  g.dragCorner(150, 600);
  const fold = g.fold(W, H, 2 / W, 1, BOTTOM);
  const p = land(fold, W, H);
  assert(W - p.x < 20, `a 2vp drag only lifts the corner slightly, moved ${W - p.x}`);
}

// 手指抖动：120Hz 触摸、上下 ±1.5vp 抖动，折线角度的逐帧变化要平稳（不滤时每帧来回摆 2~4 度，宽阴影跟着闪）。
for (const speed of [150, 600, 1500]) {
  const g = new ReaderGlCurlGeometry();
  const angles = [];
  let lag = 0;
  for (let frame = 0; frame <= Math.round(300 / speed * 120); frame++) {
    const t = frame * 1000 / 120;
    const x = 330 - speed * frame / 120;
    const y = 700 - speed * 0.2 * frame / 120 + (frame % 2 ? 1.5 : -1.5);
    g.dragCorner(x, y, t);
    const fold = g.fold(W, H, Math.max(0, (330 - x) / W), 1, BOTTOM);
    angles.push(Math.atan2(fold.ny, fold.nx) * 180 / Math.PI);
    // 起手 56vp 内页角本来就从纸边过渡到手指下方，之后才比较跟手的滞后。
    if (330 - x > 70) {
      const corner = land(fold, W, H);
      lag = Math.max(lag, Math.hypot(corner.x - x, corner.y - y));
    }
  }
  let jerk = 0;
  for (let i = 22; i < angles.length; i++) {
    jerk = Math.max(jerk, Math.abs(angles[i] - 2 * angles[i - 1] + angles[i - 2]));
  }
  assert(jerk < 0.6, `fold angle wobble ${jerk.toFixed(2)}° at ${speed}vp/s`);
  assert(lag < 22, `corner lags the finger by ${lag.toFixed(1)}vp at ${speed}vp/s`);
}

// 按住不动：页面传来的拖动进度会抖（原始偏移），页角已经贴住手指后不能再被拉回“半贴”状态。
{
  const g = new ReaderGlCurlGeometry();
  g.dragCorner(330, 760, 0);
  g.dragCorner(200, 700, 100);
  const held = g.fold(W, H, 0.3, 1, BOTTOM);
  for (const progress of [0.08, 0.3, 0.05, 0.3]) {
    const fold = g.fold(W, H, progress, 1, BOTTOM);
    for (const key of ['p0x', 'p0y', 'nx', 'ny', 'radius']) near(fold[key], held[key], 1e-9, `held fold keeps ${key}`);
  }
}

// 松手：画面连续，之后继续翻完或弹回。
{
  const g = new ReaderGlCurlGeometry();
  g.dragCorner(200, 760);
  const before = g.fold(W, H, 0.45, 1, BOTTOM);
  g.releaseCorner();
  const after = g.fold(W, H, 0.45, 1, BOTTOM);
  for (const key of ['p0x', 'p0y', 'nx', 'ny', 'radius']) near(after[key], before[key], 1e-6, `release keeps ${key}`);
  const fraction = g.remainingFraction(W);
  assert(fraction > 0 && fraction < 1, `remaining fraction ${fraction}`);
  assert(landedExtent(g.fold(W, H, 1, 1, BOTTOM)).maxX <= 0.5, 'a released turn finishes off screen');
  const back = g.fold(W, H, 0.0005, 1, BOTTOM);
  assert.equal(back.active, false, 'a cancelled turn lands flat');
  g.clearCorner();
  assert.equal(g.remainingFraction(W), -1);
}

console.log('PASS: flat start, tapped arc and finish, mirrored backward turns, corner under finger, spine limit, middle tilt, gentle start, jitter filtering and release continuity');
