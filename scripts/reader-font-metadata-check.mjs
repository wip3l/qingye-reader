import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const context = vm.createContext({});
for (const name of ['ReaderFontMetadata', 'ReaderFontWeight']) {
  const source = fs.readFileSync(new URL(`../entry/src/main/ets/core/reader/${name}.ts`, import.meta.url), 'utf8');
  vm.runInContext(stripTypeScriptTypes(source.replace('export class', 'class')) + `\nglobalThis.${name} = ${name};`, context);
}
const { ReaderFontMetadata: Metadata, ReaderFontWeight: Weight } = context;
function inspect(bytes) {
  let total = 0;
  const result = Metadata.inspect(bytes.length, (offset, length) => {
    assert(offset >= 0 && offset + length <= bytes.length, 'bounded file reads');
    total += length;
    return new Uint8Array(bytes.subarray(offset, offset + length));
  });
  return { result, total };
}
function sfnt(variable) {
  const b = Buffer.alloc(128);
  b.writeUInt32BE(0x00010000, 0); b.writeUInt16BE(variable ? 2 : 1, 4);
  b.write('OS/2', 12); b.writeUInt32BE(64, 20); b.writeUInt32BE(6, 24); b.writeUInt16BE(400, 68);
  if (variable) {
    b.write('fvar', 28); b.writeUInt32BE(80, 36); b.writeUInt32BE(36, 40);
    b.writeUInt16BE(16, 84); b.writeUInt16BE(1, 88); b.writeUInt16BE(20, 90);
    b.write('wght', 96);
    b.writeInt32BE(200 * 65536, 100); b.writeInt32BE(400 * 65536, 104); b.writeInt32BE(700 * 65536, 108);
  }
  return b;
}
assert.equal(inspect(sfnt(false)).result.known, true);
assert.equal(inspect(sfnt(false)).result.variableWeight, false);
assert.equal(inspect(sfnt(true)).result.variableWeight, true);
assert.equal(inspect(sfnt(true)).result.minWeight, 200);
assert.equal(inspect(sfnt(true)).result.maxWeight, 700);
for (let length = 0; length < 28; length++) assert.equal(inspect(sfnt(false).subarray(0, length)).result.known, false);
const collection = sfnt(false); collection.write('ttcf');
assert.equal(inspect(collection).result.known, false, 'collections retain native face matching');
const badTable = sfnt(true); badTable.writeUInt32BE(0xfffffff0, 36);
assert.equal(inspect(badTable).result.known, false);
const badAxis = sfnt(true); badAxis.writeUInt16BE(65535, 88);
assert.equal(inspect(badAxis).result.known, false);
const otherAxis = sfnt(true); otherAxis.write('wdth', 96);
assert.equal(inspect(otherAxis).result.variableWeight, false, 'only wght permits native weight variation');
Weight.registerStatic('custom', 'Original Face');
for (const value of [50, 400, 450, 600, 900]) assert.equal(Weight.layoutWeight('custom', value), 400);
assert.equal(Weight.strokeWidth('custom', 50, 40), 0);
assert.equal(Weight.strokeWidth('custom', 400, 40), 0);
assert(Weight.strokeWidth('custom', 450, 40) < Weight.strokeWidth('custom', 500, 40));
assert.equal(Weight.strokeWidth('custom', 900, 80), Weight.strokeWidth('custom', 900, 40) * 2);
assert.equal(Weight.matchesStaticFace('custom', 'Emoji fallback'), false);
assert.equal(Weight.matchesStaticFace('custom', 'Original Face'), true);
assert.equal(Weight.strokeWidth('system', 900, 40), 0);
Weight.registerVariable('custom', 200, 700);
assert.equal(Weight.isStatic('custom'), false, 're-registration invalidates old static capability');
assert.equal(Weight.layoutWeight('custom', 50), 200);
assert.equal(Weight.layoutWeight('custom', 475), 475);
assert.equal(Weight.layoutWeight('custom', 900), 700);
Weight.unregister('custom');
assert.equal(Weight.layoutWeight('custom', 900), 900);
if (process.argv[2]) {
  const { result, total } = inspect(fs.readFileSync(process.argv[2]));
  assert(result.known);
  console.log(`Fixture: ${JSON.stringify(result)}, metadata bytes read=${total}`);
}
console.log('PASS: bounded SFNT metadata, static/variable routing, fallback faces and continuous stroke scale');
