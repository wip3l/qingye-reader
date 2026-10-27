import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
const root = new URL('../entry/src/main/ets/', import.meta.url);
const read = file => fs.readFileSync(new URL(file, root), 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });
const picker = read('components/ColorCodePicker.ets');
const methods = picker.slice(picker.indexOf('  private normalizeColor('), picker.indexOf('  private openPicker('));
const hsv = picker.slice(picker.indexOf('class HsvColor'), picker.indexOf('@Component'));
const sandbox = vm.createContext({});
vm.runInContext(compile(read('utils/HexColor.ts')) + '\n' + compile(hsv) + '\n' + compile(`
  class PickerHarness {
    allowAlpha = true;
    colorOpacity = 100;
    ${methods}
  }
  globalThis.Picker = PickerHarness;
`), sandbox);
const p = new sandbox.Picker();
for (const alpha of ['00', '80', 'FF']) {
  const color = `#${alpha}12AB34`;
  p.updateHsvFromColor(color);
  assert.equal(Math.round(p.colorOpacity * 2.55), parseInt(alpha, 16));
  p.hue = 270;
  p.saturation = 80;
  p.colorBrightness = 60;
  p.updateDraftFromHsv();
  assert.equal(p.draftColor.slice(1, 3), alpha, 'HSV adjustments preserve opacity');
  assert.equal(p.normalizeColor(color, '#FFFFFF'), color);
}
p.allowAlpha = false;
p.updateHsvFromColor('#12AB34');
p.updateDraftFromHsv();
assert.equal(p.draftColor.length, 7, 'existing RGB picker behavior stays unchanged');
assert.equal(p.normalizeColor('#8012AB34', '#123456'), '#123456');
console.log('PASS: picker HSV edits preserve transparent, translucent and opaque alpha; RGB callers remain compatible');
