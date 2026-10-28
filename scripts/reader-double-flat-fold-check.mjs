import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

class Path {
  points = [];
  moveTo(x, y) { this.points.push([x, y]); }
  lineTo(x, y) { this.points.push([x, y]); }
  closePath() {}
}
const box = vm.createContext({ Path2D: Path });
vm.runInContext(stripTypeScriptTypes(fs.readFileSync('entry/src/main/ets/components/ReaderEmulationFlipPainter.ets', 'utf8')
  .replace(/^import.*$/gm, '').replaceAll('export ', ''), {mode: 'transform'}), box);
const Painter = vm.runInContext('ReaderEmulationFlipPainter', box);
const near = (a, b, label) => assert.ok(Math.abs(a - b) < 1e-6, `${label}: ${a} != ${b}`);
function multiply(a, b) {
  return [a[0]*b[0]+a[2]*b[1], a[1]*b[0]+a[3]*b[1], a[0]*b[2]+a[2]*b[3],
    a[1]*b[2]+a[3]*b[3], a[0]*b[4]+a[2]*b[5]+a[4], a[1]*b[4]+a[3]*b[5]+a[5]];
}
function context() {
  let matrix = [1,0,0,1,0,0]; const stack = [], draws = [];
  return { draws, globalAlpha: 1,
    save() { stack.push({matrix: [...matrix], alpha: this.globalAlpha}); },
    restore() { const s = stack.pop(); assert.ok(s); matrix = s.matrix; this.globalAlpha = s.alpha; },
    transform(...m) { assert.ok(m.every(Number.isFinite)); matrix = multiply(matrix, m); },
    translate(x,y) { this.transform(1,0,0,1,x,y); }, scale(x,y) { this.transform(x,0,0,y,0,0); },
    drawImage(texture, ...rect) { draws.push({texture, rect, matrix: [...matrix], alpha: this.globalAlpha}); },
    createLinearGradient(...coords) { assert.ok(coords.every(Number.isFinite)); return {addColorStop(t) {
      assert.ok(t >= 0 && t <= 1); }}; },
    clip(p) { assert.ok(p.points.flat().every(Number.isFinite)); },
    fill() { assert.ok(Number.isFinite(this.globalAlpha)); }, clearRect() {}, beginPath() {}, moveTo() {}, lineTo() {}, stroke() {},
    balanced() { assert.equal(stack.length, 0); near(this.globalAlpha, 1, 'Canvas alpha restored'); }
  };
}
const front = {}, back = {};
let samples = 0;
for (const [width, height, gap] of [[1000,700,2], [841.5,616.25,1.5], [640,920,2]]) {
  const leaf = (width - gap) / 2, origin = leaf + gap;
  for (const direction of [-1,1]) for (const region of [0,1,2]) for (const dark of [false,true]) {
    for (const p of [0,.001,.05,.2,.5,.7,.9,.99,.9999,1]) {
      const painter = new Painter(), c = context();
      painter.draw(c, front, back, width, height, p, direction, region, true, leaf, origin, .5, '#ede6d6', dark);
      c.balanced(); assert.ok(c.draws.length > 0 && c.draws.length <= 2, 'At most front and back texture draws');
      for (const draw of c.draws) {
        const m = draw.matrix;
        near(m[0]*m[3]-m[1]*m[2], 1, 'Paper must rotate/refold without text compression or mirroring');
        near(draw.alpha, 1, 'Page texture remains opaque');
        if (draw.texture === front) {
          near(m[0], 1, 'Unfolded text X scale'); near(m[3], 1, 'Unfolded text Y scale');
        }
      }
      if (p === 0 || p === 1) {
        assert.equal(c.draws[0].texture, p === 0 ? front : back);
        near(c.draws[0].rect[0], (p === 0 ? direction > 0 : direction < 0) ? origin : 0, 'Resting column');
      }
      samples++;
    }
    // Exercise the actual shared fold at its terminal frame, before the endpoint shortcut.
    const painter = new Painter(), end = context();
    painter.drawFlatFold(end, front, leaf, height, 1, direction, region, back, width, origin);
    const landed = end.draws.find(d => d.texture === back);
    assert.ok(landed); near(landed.matrix[0], 1, 'Landed text orientation');
    near(landed.matrix[3], 1, 'Landed text height');
    near(landed.matrix[4], direction > 0 ? 0 : origin, 'Fold lands on opposite column without a jump');
    near(landed.matrix[5], 0, 'Fold lands at original baseline'); end.balanced();

    // A drag uses spread coordinates; release and rollback start from exactly the last drawn corner.
    const canonicalX = leaf * .35;
    const y = height * (region === 0 ? .2 : region === 2 ? .8 : .5);
    const fingerX = direction > 0 ? origin + canonicalX : width - origin - canonicalX;
    painter.dragCorner(fingerX, y);
    const grab = painter.flatGrabPoint(leaf, height, region);
    const dragged = painter.flatFoldTarget(leaf, height, .3, region, grab, direction < 0, width, origin);
    near(dragged.x, canonicalX, 'Finger translated into leaf coordinates'); near(dragged.y, y, 'Finger height');
    painter.releaseCorner();
    const released = painter.flatFoldTarget(leaf, height, .3, region, grab, direction < 0, width, origin);
    near(released.x, dragged.x, 'Release X continuity'); near(released.y, dragged.y, 'Release Y continuity');
    const finished = painter.flatFoldTarget(leaf, height, 1, region, grab, direction < 0, width, origin);
    near(finished.x, -origin, 'Released corner lands at opposite outer edge'); near(finished.y, grab.y, 'Released corner settles');
    const rollback = painter.flatFoldTarget(leaf, height, 0, region, grab, direction < 0, width, origin);
    near(rollback.x, grab.x, 'Rollback X'); near(rollback.y, grab.y, 'Rollback Y');
    assert.ok(painter.flatRemainingFraction(leaf, origin) > 0 && painter.flatRemainingFraction(leaf, origin) < 1);
  }
}
const reader = fs.readFileSync('entry/src/main/ets/pages/ReadBook.ets', 'utf8');
const fingerMethod = reader.slice(reader.indexOf('  updateReaderCurlFinger('), reader.indexOf('  captureReaderCurlStartRegion('));
assert.ok(!fingerMethod.includes('isLandscapeDoublePageActive'), 'Double-page gestures must reach the same painter');
console.log(`PASS: ${samples} dual-page folds, no texture compression/mirroring, exact landing, finger coordinates, release and rollback.`);
