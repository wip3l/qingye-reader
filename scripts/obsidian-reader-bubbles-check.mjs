import assert from 'node:assert/strict';
import { loadObsidianReader } from './lib/obsidian-reader-fixture.mjs';
const {ThemeRuntime:runtime,ThemeAssetRegistry:assets,ReaderHarness,ReaderRegexFontRule:Rule,
  ReaderCommentBubblePainter:painter,store,sandbox,Canvas}=loadObsidianReader();
const reader=new ReaderHarness();
// Reproduce the old normalization failure through theme application, not by injecting the style into a resolver.
runtime.applyTheme('obsidian-archive');
for(const dark of [false,true]) {
  store.set('appDarkMode',dark);reader.appDarkMode=dark;
  assert.equal(runtime.regexBubbleStyle(),'gilded-orbit');
  const native=reader.buildReaderV2RegexStyleTemplate({});
  assert.equal(native.decorationStyleId,'gilded-orbit');
  assert.equal(native.decorationEnabled,true);
  assert.equal(native.backgroundEnabled,true);
  assert.equal(native.backgroundColor,dark?0xFF463B2A:0xFF292620);
  assert.equal(native.color,dark?0xFFF4E3BF:0xFFF2DEAE,'Inherited text colour must match the dark bookplate');
  assert.ok(assets.regexBubbleCap(native.decorationStyleId));
  assert.ok(native.decorationSizePx>0);
  const comment=reader.readerCommentBubbleStyle();
  assert.equal(comment.ornament,'folio');
  assert.equal(comment.fill,dark?0xFFDEC79A:0xFF292620);
  assert.equal(comment.text,dark?0xFF30291E:0xFFF2DEAE);
  for(const label of ['1','128','999+','本章说']) {
    const canvas=new Canvas(),h=painter.heightFor(18),w=Math.max(h,label.length*18+18*.84);
    painter.paint(canvas,10,10,10+w,10+h,comment,true);
    assert.equal(canvas.commands.length,4,'Body, foil edge, ribbon and fold must all be drawn');
    assert.ok(canvas.commands.every(c=>!c.d.includes('NaN')));
    assert.equal(canvas.commands[0].fill.red,(comment.fill>>>16)&255);
    assert.ok(canvas.commands[0].d.includes('Q'),'Bookplate has folded corners');
  }
  // Invalid stored values fall back to the current theme; previously even this fallback rejected the new style.
  const key=dark?runtime.KEY_DARK_REGEX_BUBBLE_STYLE:runtime.KEY_LIGHT_REGEX_BUBBLE_STYLE;
  store.set(key,'invalid-legacy-value');assert.equal(runtime.regexBubbleStyle(),'gilded-orbit');
  runtime.applyTheme('obsidian-archive');
}
reader.sourceSettings={'段评填充颜色':'#123456','段评字体颜色':'#FFFFFF','段评样式':'自定义'};
const explicit=reader.readerCommentBubbleStyle();
assert.equal(explicit.fill,0xFF123456);assert.equal(explicit.text,0xFFFFFFFF);
assert.equal(explicit.stroke,0);assert.equal(explicit.radiusPx,4);
reader.rule=new Rule();reader.rule.emphasisMode='none';
assert.equal(reader.buildReaderV2RegexStyleTemplate({}).backgroundEnabled,false);
reader.rule=null;sandbox.granted=false;
assert.notEqual(reader.buildReaderV2RegexStyleTemplate({}).decorationStyleId,'gilded-orbit');
sandbox.granted=true;
runtime.applyTheme('classic-blue');
assert.equal(runtime.regexBubbleStyle(),'classic-glass');
runtime.applyTheme('plain-default');
for (const dark of [false, true]) {
  reader.appDarkMode=dark;store.set('appDarkMode',dark);
  reader.sourceSettings={};
  const native=reader.readerCommentBubbleStyle();
  reader.sourceSettings={'段评填充颜色':'#123456','段评字体颜色':'#FFFFFF','段评样式':'3'};
  const compatible=reader.readerCommentBubbleStyle();
  assert.equal(compatible.identity(),native.identity(),'source defaults must not override the default outline');
  assert.equal(compatible.fill,0);
  assert.equal(compatible.radiusRatio,0.4);
  assert.equal(compatible.radiusPx,-1);
  assert.equal(compatible.text,compatible.stroke);
}
console.log('PASS: theme application → reader context → native text/cap style; both modes, comment/chapter painter, source overrides and entitlement fallback.');
