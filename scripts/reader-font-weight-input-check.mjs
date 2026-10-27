import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
const root = new URL('../entry/src/main/ets/', import.meta.url);
const read = file => fs.readFileSync(new URL(file, root), 'utf8');
const source = read('components/reader/ReaderFontWeightStepper.ets');
const methods = source.slice(source.indexOf('  private apply('), source.indexOf('  build()'));
const compile = code => stripTypeScriptTypes(code.replace(/^export /gm, ''), { mode: 'strip' });
const context = vm.createContext({});
vm.runInContext(compile(read('core/reader/ReaderFontWeight.ts')) + '\n' + compile(`
class Harness {
  value = 400;
  inputVisible = false;
  inputDraft = '';
  updates: number[] = [];
  onChange(value: number): void { this.updates.push(value); }
  ${methods}
}
globalThis.Harness = Harness;
`), context);
for (const [input, expected] of [['425', 425], ['537', 537], ['1', 50], ['999', 900], ['', 400], ['abc', 400], ['4.5', 400]]) {
  const h = new context.Harness();
  h.inputVisible = true;
  h.inputDraft = input;
  h.applyInput();
  h.applyInput(); // Keyboard Done can be followed by blur; never save twice.
  assert.equal(h.value, expected);
  assert.equal(h.updates.length, expected === 400 ? 0 : 1);
}
const h = new context.Harness();
h.inputVisible = true;
h.inputDraft = '537';
h.step(50);
assert.equal(h.value, 587, 'clicking plus during editing starts from the typed value');
h.step(-50);
assert.equal(h.value, 537);
console.log('PASS: precise integers, clamping, blank/invalid input, duplicate blur and stepping while editing');
